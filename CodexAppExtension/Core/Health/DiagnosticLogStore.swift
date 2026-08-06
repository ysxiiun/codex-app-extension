import Foundation

public actor DiagnosticLogStore {
    public static let defaultMaximumFileBytes = 1_048_576
    public static let defaultMaximumFileCount = 5

    public nonisolated let directory: URL
    public nonisolated let maximumFileBytes: Int
    public nonisolated let maximumFileCount: Int

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: URL? = nil,
        maximumFileBytes: Int = DiagnosticLogStore.defaultMaximumFileBytes,
        maximumFileCount: Int = DiagnosticLogStore.defaultMaximumFileCount,
        fileManager: FileManager = .default
    ) {
        let defaultRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex App Extension", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        self.directory = directory ?? defaultRoot
        self.maximumFileBytes = max(256, maximumFileBytes)
        self.maximumFileCount = max(1, maximumFileCount)
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
    }

    /// Returns false rather than destabilizing the runtime when diagnostics storage is unavailable.
    @discardableResult
    public func append(_ event: DiagnosticEvent) -> Bool {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            var line = try encoder.encode(event)
            line.append(0x0A)
            let current = fileURL(index: 0)
            let currentSize = existingSize(at: current)
            if currentSize > 0, currentSize + line.count > maximumFileBytes {
                try rotate()
            }
            try append(line, to: current)
            return true
        } catch {
            return false
        }
    }

    public func events() -> [DiagnosticEvent] {
        var decoded: [DiagnosticEvent] = []
        for index in stride(from: maximumFileCount - 1, through: 0, by: -1) {
            let url = fileURL(index: index)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            for line in data.split(separator: 0x0A) {
                if let event = try? decoder.decode(DiagnosticEvent.self, from: Data(line)) {
                    decoded.append(event)
                }
            }
        }
        return decoded
    }

    public func fileURLsNewestFirst() -> [URL] {
        (0..<maximumFileCount)
            .map(fileURL(index:))
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func rotate() throws {
        if maximumFileCount == 1 {
            try? fileManager.removeItem(at: fileURL(index: 0))
            return
        }
        try? fileManager.removeItem(at: fileURL(index: maximumFileCount - 1))
        for index in stride(from: maximumFileCount - 2, through: 0, by: -1) {
            let source = fileURL(index: index)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = fileURL(index: index + 1)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    private func append(_ data: Data, to url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url, options: [.atomic])
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func existingSize(at url: URL) -> Int {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.intValue
    }

    private func fileURL(index: Int) -> URL {
        directory.appendingPathComponent("diagnostics-\(index).jsonl")
    }
}
