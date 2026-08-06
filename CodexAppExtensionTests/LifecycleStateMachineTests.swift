import Foundation
import XCTest
@testable import ExtensionCore

final class LifecycleStateMachineTests: XCTestCase {
    func testOnlyExactChatGPTMainProcessMatches() async {
        let helper = RunningApplicationDescriptor(
            processIdentifier: 100,
            bundleIdentifier: "com.openai.codex",
            executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Frameworks/ChatGPT Helper.app/Contents/MacOS/ChatGPT Helper")
        )
        let wrongBundle = RunningApplicationDescriptor(
            processIdentifier: 101,
            bundleIdentifier: "com.openai.chatgpt.helper",
            executableURL: AppLifecycleMonitor.expectedExecutableURL
        )
        let main = RunningApplicationDescriptor(
            processIdentifier: 102,
            bundleIdentifier: "com.openai.codex",
            executableURL: AppLifecycleMonitor.expectedExecutableURL
        )
        let inspector = StubApplicationInspector(applications: [helper, wrongBundle, main])
        let monitor = AppLifecycleMonitor(inspector: inspector)

        let matched = await monitor.refreshProcess()

        XCTAssertEqual(matched, main)
        let phase = await monitor.currentPhase()
        XCTAssertEqual(phase, .runningWithoutCDP(processIdentifier: 102))
    }

    func testLifecycleAllowsOnlyLegalEdges() async throws {
        let monitor = AppLifecycleMonitor(inspector: StubApplicationInspector(applications: []))
        try await monitor.transition(to: .launching(port: 55_001))
        try await monitor.transition(to: .connecting(processIdentifier: 200, port: 55_001))
        try await monitor.transition(to: .probing(processIdentifier: 200))
        try await monitor.transition(to: .active(processIdentifier: 200, targetCount: 1))
        try await monitor.transition(to: .degraded(processIdentifier: 200, reason: "target-adapter"))
        try await monitor.transition(to: .backingOff(attempt: 1, delay: .seconds(1)))

        do {
            try await monitor.transition(to: .active(processIdentifier: 200, targetCount: 1))
            XCTFail("退避状态不能直接进入活动状态")
        } catch let error as LifecycleTransitionError {
            XCTAssertEqual(error.to, .active(processIdentifier: 200, targetCount: 1))
        } catch {
            XCTFail("错误类型不正确: \(error)")
        }
    }

    func testExistingProcessRequiresConfirmationBeforeAnyDestructiveAction() async throws {
        let allocator = StubPortAllocator(ports: [55_123])
        let controller = RecordingProcessController(launchedProcessIdentifier: 301)
        let manager = DebugSessionManager(portAllocator: allocator, processController: controller)
        let existing = RunningApplicationDescriptor(
            processIdentifier: 300,
            bundleIdentifier: "com.openai.codex",
            executableURL: AppLifecycleMonitor.expectedExecutableURL
        )

        let plan = try await manager.makePlan(for: existing)
        guard case let .restartAfterConfirmation(processIdentifier, port, arguments) = plan else {
            return XCTFail("已有无 CDP 进程必须生成确认式重启计划")
        }
        XCTAssertEqual(processIdentifier, 300)
        XCTAssertEqual(port, 55_123)
        XCTAssertEqual(arguments, [
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=55123"
        ])

        do {
            _ = try await manager.execute(plan)
            XCTFail("未经确认不应执行计划")
        } catch let error as DebugSessionError {
            XCTAssertEqual(error, .restartConfirmationRequired(processIdentifier: 300))
        }
        let actionsBeforeConfirmation = await controller.recordedActions()
        XCTAssertEqual(actionsBeforeConfirmation, [])

        let result = try await manager.execute(plan, restartConfirmed: true)
        XCTAssertEqual(result, .init(processIdentifier: 301, port: 55_123))
        let actionsAfterConfirmation = await controller.recordedActions()
        XCTAssertEqual(actionsAfterConfirmation, [
            .terminate(processIdentifier: 300),
            .launch(
                applicationURL: DebugSessionManager.chatGPTApplicationURL,
                arguments: arguments
            )
        ])
    }

    func testNewLaunchUsesFreshHighPortAndExplicitLoopback() async throws {
        let allocator = StubPortAllocator(ports: [49_152, 60_001])
        let controller = RecordingProcessController(launchedProcessIdentifier: 401)
        let manager = DebugSessionManager(portAllocator: allocator, processController: controller)

        let first = try await manager.makePlan(for: nil)
        let second = try await manager.makePlan(for: nil)

        guard case let .launch(firstPort, firstArguments) = first,
              case let .launch(secondPort, secondArguments) = second else {
            return XCTFail("未运行时必须生成启动计划")
        }
        XCTAssertNotEqual(firstPort, secondPort)
        XCTAssertGreaterThanOrEqual(firstPort, 49_152)
        XCTAssertTrue(firstArguments.contains("--remote-debugging-address=127.0.0.1"))
        XCTAssertTrue(secondArguments.contains("--remote-debugging-address=127.0.0.1"))
        XCTAssertFalse(firstArguments.joined().contains("0.0.0.0"))
    }

    func testDebugPortReuseRequiresOneExplicitIPv4LoopbackAddress() async throws {
        let valid = "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --remote-debugging-address=127.0.0.1 --remote-debugging-port=55123"
        XCTAssertEqual(SystemApplicationServices.parseDebugPort(command: valid), 55_123)

        let rejectedCommands = [
            "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --remote-debugging-port=55123",
            "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --remote-debugging-address=0.0.0.0 --remote-debugging-port=55123",
            "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --remote-debugging-address=::1 --remote-debugging-port=55123",
            "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --remote-debugging-address=localhost --remote-debugging-port=55123",
            "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --remote-debugging-address=192.168.1.10 --remote-debugging-port=55123",
            "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --remote-debugging-address=127.0.0.1 --remote-debugging-address=127.0.0.1 --remote-debugging-port=55123",
            "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --remote-debugging-address=127.0.0.1 --remote-debugging-port=0"
        ]
        for command in rejectedCommands {
            XCTAssertNil(SystemApplicationServices.parseDebugPort(command: command), command)
        }

        let processController = RecordingProcessController(launchedProcessIdentifier: 901)
        let manager = DebugSessionManager(
            portAllocator: StubPortAllocator(ports: Array(repeating: 56_000, count: rejectedCommands.count)),
            processController: processController
        )
        let validApplication = RunningApplicationDescriptor(
            processIdentifier: 900,
            bundleIdentifier: AppLifecycleMonitor.expectedBundleIdentifier,
            executableURL: AppLifecycleMonitor.expectedExecutableURL,
            debugPort: SystemApplicationServices.parseDebugPort(command: valid)
        )
        let validPlan = try await manager.makePlan(for: validApplication)
        XCTAssertEqual(validPlan, .connect(processIdentifier: 900, port: 55_123))

        for command in rejectedCommands {
            let application = RunningApplicationDescriptor(
                processIdentifier: 900,
                bundleIdentifier: AppLifecycleMonitor.expectedBundleIdentifier,
                executableURL: AppLifecycleMonitor.expectedExecutableURL,
                debugPort: SystemApplicationServices.parseDebugPort(command: command)
            )
            guard case .restartAfterConfirmation = try await manager.makePlan(for: application) else {
                return XCTFail("非显式 IPv4 loopback 启动参数不得直接复用: \(command)")
            }
        }
    }

    func testPortAllocatorSkipsConflictAndRejectsNonMainProcess() async throws {
        let allocator = SystemLoopbackPortAllocator(
            candidatePorts: [50_000, 50_001],
            availabilityProbe: { $0 == 50_001 }
        )
        let allocatedPort = try await allocator.allocate()
        XCTAssertEqual(allocatedPort, 50_001)

        let controller = RecordingProcessController(launchedProcessIdentifier: 601)
        let manager = DebugSessionManager(
            portAllocator: StubPortAllocator(ports: [55_111]),
            processController: controller
        )
        let helper = RunningApplicationDescriptor(
            processIdentifier: 600,
            bundleIdentifier: "com.openai.codex",
            executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Frameworks/ChatGPT Helper.app/Contents/MacOS/ChatGPT Helper")
        )
        do {
            _ = try await manager.makePlan(for: helper)
            XCTFail("Helper 进程不能进入调试会话计划")
        } catch let error as DebugSessionError {
            XCTAssertEqual(error, .invalidApplication(processIdentifier: 600))
        }
        let actions = await controller.recordedActions()
        XCTAssertEqual(actions, [])
    }

    func testTargetDegradationDoesNotMarkProcessDead() async {
        let healthCenter = HealthCenter()
        await healthCenter.updateProcess(.running(processIdentifier: 500))
        await healthCenter.updateTarget(.init(
            targetIdentifier: "target-1",
            adapterIdentifier: "markdown",
            state: .degraded(reason: "probe-failed")
        ))
        await healthCenter.updateTarget(.init(
            targetIdentifier: "target-1",
            adapterIdentifier: "layout",
            state: .healthy
        ))

        let snapshot = await healthCenter.snapshot()
        XCTAssertEqual(snapshot.process, .running(processIdentifier: 500))
        XCTAssertEqual(snapshot.targets.count, 2)
        XCTAssertTrue(snapshot.targets.contains { $0.state == .degraded(reason: "probe-failed") })
        XCTAssertTrue(snapshot.targets.contains { $0.state == .healthy })
    }
}

private actor StubApplicationInspector: RunningApplicationInspecting {
    let applications: [RunningApplicationDescriptor]

    init(applications: [RunningApplicationDescriptor]) {
        self.applications = applications
    }

    func runningApplications() -> [RunningApplicationDescriptor] {
        applications
    }
}

private actor StubPortAllocator: LoopbackPortAllocating {
    private var ports: [UInt16]

    init(ports: [UInt16]) {
        self.ports = ports
    }

    func allocate() throws -> UInt16 {
        guard !ports.isEmpty else { throw DebugSessionError.noAvailableLoopbackPort }
        return ports.removeFirst()
    }
}

private enum RecordedProcessAction: Equatable, Sendable {
    case terminate(processIdentifier: Int32)
    case launch(applicationURL: URL, arguments: [String])
}

private actor RecordingProcessController: DebugProcessControlling {
    private let launchedProcessIdentifier: Int32
    private var actions: [RecordedProcessAction] = []

    init(launchedProcessIdentifier: Int32) {
        self.launchedProcessIdentifier = launchedProcessIdentifier
    }

    func terminate(processIdentifier: Int32) {
        actions.append(.terminate(processIdentifier: processIdentifier))
    }

    func launch(applicationURL: URL, arguments: [String]) -> Int32 {
        actions.append(.launch(applicationURL: applicationURL, arguments: arguments))
        return launchedProcessIdentifier
    }

    func recordedActions() -> [RecordedProcessAction] {
        actions
    }
}
