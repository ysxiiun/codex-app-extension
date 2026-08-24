(function bootstrapCodexAppExtensionV2(window) {
  "use strict";

  const runtimeVersion = 2;
  const implementationRevision = 15;
  const existingRuntime = window.__codexAppExtensionV2;
  if (existingRuntime?.runtimeVersion === runtimeVersion &&
      existingRuntime?.implementationRevision === implementationRevision) {
    return;
  }

  if (existingRuntime && typeof existingRuntime.execute === "function") {
    const previousExecute = existingRuntime.execute;
    const retiredAdapterIds = Object.freeze([
      "wide-layout",
      "header-offset",
      "ime-enter-guard",
      "focus-ring",
      "markdown-semantic-theme"
    ]);
    retiredAdapterIds.forEach(function uninstallPreviousImplementation(adapterId, index) {
      try {
        previousExecute.call(existingRuntime, {
          runtimeVersion,
          requestId: 1_900_000_000 + index,
          adapterId,
          operation: "uninstall",
          config: null
        });
      } catch (_) {
        // Retired-runtime cleanup is best effort; one missing or broken adapter must not block upgrade.
      }
    });
  }

  const adapters = new Map();
  const states = new Map();
  const observers = new Map();
  const failedOperationSignature = Symbol("adapter-operation-failed");
  let mutationObserver = null;
  let animationFrame = null;
  let settleTimer = null;
  let hydrated = false;
  let surfaceRevision = 0;
  let previousSurfaceNodes = {
    layoutRoot: null,
    threadScroller: null,
    editor: null,
    kind: null,
    editorSignal: null
  };
  const performanceEvents = [];
  const performancePolicy = Object.freeze({
    durationBudgetMilliseconds: 8,
    strikeLimit: 3,
    maximumObserverCount: 16,
    maximumEventCount: 32
  });

  const surfaceSelectors = Object.freeze({
    layoutRoot: "[data-app-shell-main-content-layout]",
    threadScroller: ".thread-scroll-container",
    markedEditor: ".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']",
    fallbackEditor: ".ProseMirror[contenteditable='true'], .ProseMirror[contenteditable='plaintext-only']",
    editorCandidate: ".ProseMirror"
  });

  function uniqueNode(selector) {
    const matches = document.querySelectorAll(selector);
    return matches.length === 1 ? matches[0] : null;
  }

  function uniqueNodeWithin(root, selector) {
    if (!root) return null;
    const matches = Array.from(document.querySelectorAll(selector)).filter((node) => root.contains(node));
    return matches.length === 1 ? matches[0] : null;
  }

  function nodesWithinLayout(layoutRoot, selector) {
    return layoutRoot
      ? Array.from(document.querySelectorAll(selector)).filter((node) => layoutRoot.contains(node))
      : [];
  }

  function renderedEmptyEditor(node, layoutRoot) {
    for (let current = node; current; current = current.parentElement) {
      if (current.hidden || current.getAttribute?.("aria-hidden") === "true") return false;
      const style = window.getComputedStyle(current);
      if (style.display === "none" || style.visibility === "hidden" ||
          style.visibility === "collapse" || Number(style.opacity) === 0) return false;
      if (current === layoutRoot) return true;
    }
    return false;
  }

  function surface() {
    const layoutRoots = Array.from(document.querySelectorAll(surfaceSelectors.layoutRoot));
    const layoutRoot = layoutRoots.length === 1 ? layoutRoots[0] : null;
    const threadScrollers = layoutRoot
      ? Array.from(document.querySelectorAll(surfaceSelectors.threadScroller)).filter((node) => layoutRoot.contains(node))
      : [];
    const threadScroller = threadScrollers.length === 1 ? threadScrollers[0] : null;
    const rawMarkedEditors = nodesWithinLayout(layoutRoot, surfaceSelectors.markedEditor);
    const markedEditors = threadScrollers.length === 0
      ? rawMarkedEditors.filter((node) => renderedEmptyEditor(node, layoutRoot))
      : rawMarkedEditors;
    const fallbackEditors = layoutRoot && threadScrollers.length === 0 && markedEditors.length === 0
      ? nodesWithinLayout(layoutRoot, surfaceSelectors.fallbackEditor)
        .filter((node) => renderedEmptyEditor(node, layoutRoot))
      : [];
    const editors = markedEditors.length > 0 ? markedEditors : fallbackEditors;
    const editor = editors.length === 1 ? editors[0] : null;
    const editorSignal = editor ? (markedEditors.length > 0 ? "marked" : "fallback") : null;
    const kind = layoutRoot && threadScrollers.length === 1
      ? "thread"
      : layoutRoot && threadScrollers.length === 0 && editor
        ? "empty-composer"
        : null;
    if (layoutRoot !== previousSurfaceNodes.layoutRoot ||
        threadScroller !== previousSurfaceNodes.threadScroller ||
        editor !== previousSurfaceNodes.editor ||
        kind !== previousSurfaceNodes.kind ||
        editorSignal !== previousSurfaceNodes.editorSignal) {
      surfaceRevision += 1;
      previousSurfaceNodes = { layoutRoot, threadScroller, editor, kind, editorSignal };
    }
    const qualified = kind !== null;
    return {
      layoutRoot,
      threadScroller,
      editor,
      composer: editor,
      composerSignal: editor ? "true" : null,
      editorSignal,
      kind,
      layoutRootCount: layoutRoots.length,
      threadScrollerCount: threadScrollers.length,
      editorCount: editors.length,
      qualified,
      revision: surfaceRevision
    };
  }

  function bindMutationObserver(currentSurface) {
    if (!mutationObserver || observers.size === 0) return;
    mutationObserver.disconnect();
    const stableRoot = document.documentElement ?? document.body;
    if (stableRoot) {
      mutationObserver.observe(stableRoot, { childList: true, subtree: true });
    }
    if (currentSurface.layoutRoot) {
      mutationObserver.observe(currentSurface.layoutRoot, {
        attributes: true,
        attributeFilter: ["data-app-shell-main-content-layout", "hidden", "aria-hidden", "style"]
      });
    }
    if (currentSurface.threadScroller) {
      mutationObserver.observe(currentSurface.threadScroller, {
        attributes: true,
        attributeFilter: ["class"]
      });
    }
    const editorCandidates = currentSurface.layoutRoot && currentSurface.threadScrollerCount === 0
      ? nodesWithinLayout(currentSurface.layoutRoot, surfaceSelectors.editorCandidate).slice(0, 16)
      : currentSurface.editor ? [currentSurface.editor] : [];
    for (const candidate of editorCandidates) {
      mutationObserver.observe(candidate, {
        attributes: true,
        attributeFilter: ["class", "contenteditable", "data-codex-composer", "hidden", "aria-hidden", "style"]
      });
      if (currentSurface.threadScrollerCount === 0) {
        for (let current = candidate.parentElement;
             current && current !== currentSurface.layoutRoot;
             current = current.parentElement) {
          mutationObserver.observe(current, {
            attributes: true,
            attributeFilter: ["hidden", "aria-hidden", "style"]
          });
        }
      }
    }
  }

  function refreshObservers(reason) {
    const currentSurface = surface();
    bindMutationObserver(currentSurface);
    for (const [adapterId, record] of observers.entries()) {
      if (record.degraded) {
        continue;
      }
      const startedAt = monotonicNow();
      try {
        const result = record.callback(reason, currentSurface) ?? {};
        record.qualified = result.qualified !== false;
        record.recoverable = result.recoverable === true;
        record.failureReason = record.qualified ? null : (result.reason ?? "adapter-reconcile-unqualified");
      } catch (error) {
        // One adapter observer failure must not block the remaining adapters.
        record.qualified = false;
        record.recoverable = false;
        record.failureReason = String(error?.message ?? error);
      }
      const durationMilliseconds = Math.max(0, monotonicNow() - startedAt);
      record.lastDurationMilliseconds = durationMilliseconds;
      if (durationMilliseconds > performancePolicy.durationBudgetMilliseconds) {
        record.strikes += 1;
      } else {
        record.strikes = 0;
      }
      if (record.strikes >= performancePolicy.strikeLimit) {
        record.degraded = true;
      }
      const state = states.get(adapterId);
      if (state?.installed) {
        states.set(adapterId, {
          ...state,
          surfaceRevision: currentSurface.revision,
          qualified: record.qualified,
          recoverable: record.recoverable
        });
      }
      performanceEvents.push({
        adapterId,
        durationMilliseconds,
        strikeCount: record.strikes,
        degraded: record.degraded
      });
      if (performanceEvents.length > performancePolicy.maximumEventCount) {
        performanceEvents.splice(0, performanceEvents.length - performancePolicy.maximumEventCount);
      }
    }
  }

  function monotonicNow() {
    if (window.performance && typeof window.performance.now === "function") {
      return window.performance.now();
    }
    return Date.now();
  }

  function scheduleRefresh() {
    if (animationFrame === null) {
      animationFrame = requestAnimationFrame(function onAnimationFrame() {
        animationFrame = null;
        refreshObservers("animation-frame");
      });
    }
    if (settleTimer === null) {
      settleTimer = setTimeout(function onSettled() {
        settleTimer = null;
        refreshObservers("settled");
      }, 80);
    }
  }

  function startMutationObserver() {
    if (observers.size === 0) return;
    mutationObserver ??= new MutationObserver(scheduleRefresh);
    bindMutationObserver(surface());
  }

  function stopMutationObserverIfUnused() {
    if (observers.size !== 0) {
      return;
    }
    mutationObserver?.disconnect();
    mutationObserver = null;
    if (animationFrame !== null) {
      cancelAnimationFrame(animationFrame);
      animationFrame = null;
    }
    if (settleTimer !== null) {
      clearTimeout(settleTimer);
      settleTimer = null;
    }
  }

  function observe(adapterId, callback) {
    if (!observers.has(adapterId) && observers.size >= performancePolicy.maximumObserverCount) {
      return function ignoredUnsubscribe() {};
    }
    observers.set(adapterId, {
      callback,
      strikes: 0,
      degraded: false,
      lastDurationMilliseconds: 0,
      qualified: true,
      recoverable: false,
      failureReason: null
    });
    startMutationObserver();
    return function unsubscribe() {
      observers.delete(adapterId);
      stopMutationObserverIfUnused();
    };
  }

  function responseEnvelope(request, result, error) {
    return {
      runtimeVersion,
      requestId: request?.requestId ?? null,
      adapterId: request?.adapterId ?? null,
      operation: request?.operation ?? null,
      config: request?.config ?? null,
      result: result ?? null,
      error: error ?? null
    };
  }

  function failure(request, code, message) {
    return responseEnvelope(request, null, { code, message });
  }

  function execute(request) {
    if (!request || request.runtimeVersion !== runtimeVersion) {
      return failure(request, "runtime-version-mismatch", "runtimeVersion must equal 2");
    }
    const adapter = adapters.get(request.adapterId);
    if (!adapter) {
      return failure(request, "adapter-not-registered", "Requested adapter is not registered");
    }
    const operation = request.operation;
    if (!["install", "update", "diagnose", "uninstall"].includes(operation)) {
      return failure(request, "unsupported-operation", "Unsupported adapter operation");
    }
    const observer = observers.get(request.adapterId);
    if (operation !== "uninstall" && observer?.degraded) {
      return failure(
        request,
        "adapter-performance-budget-exceeded",
        "Adapter observer exceeded the fixed performance budget"
      );
    }

    const currentSurface = surface();
    const previous = states.get(request.adapterId);
    const signature = JSON.stringify(request.config ?? null);
    if ((operation === "install" || operation === "update") &&
        previous?.installed && previous.signature === signature &&
        previous.surfaceRevision === currentSurface.revision &&
        previous.qualified !== false && observer?.qualified !== false) {
      return responseEnvelope(request, { changed: false, idempotent: true, recoverable: false }, null);
    }
    if (operation === "uninstall" && !previous?.installed) {
      return responseEnvelope(request, { changed: false, idempotent: true, recoverable: false }, null);
    }

    try {
      const adapterResult = adapter[operation](request.config ?? {}, runtimeAPI) ?? {};
      const result = {
        ...adapterResult,
        recoverable: adapterResult.recoverable === true
      };
      if (operation === "install" || operation === "update") {
        const nextObserver = observers.get(request.adapterId);
        if (nextObserver) {
          nextObserver.qualified = result.qualified !== false;
          nextObserver.recoverable = result.recoverable;
          nextObserver.failureReason = nextObserver.qualified ? null : (result.reason ?? "adapter-unqualified");
        }
        states.set(request.adapterId, {
          installed: true,
          signature,
          surfaceRevision: surface().revision,
          qualified: result.qualified !== false,
          recoverable: result.recoverable
        });
      } else if (operation === "uninstall") {
        states.delete(request.adapterId);
      }
      return responseEnvelope(request, result, null);
    } catch (error) {
      const failedObserver = observers.get(request.adapterId);
      if (failedObserver) {
        failedObserver.qualified = false;
        failedObserver.recoverable = false;
        failedObserver.failureReason = "adapter-operation-failed";
      }
      if (previous?.installed) {
        states.set(request.adapterId, {
          ...previous,
          signature: failedOperationSignature,
          qualified: false,
          recoverable: false
        });
      }
      return failure(request, "adapter-operation-failed", String(error?.message ?? error));
    }
  }

  const newRuntimeAPI = {
    runtimeVersion,
    implementationRevision,
    register(adapter) {
      if (!adapter || typeof adapter.adapterId !== "string") {
        return { registered: false, reason: "invalid-adapter" };
      }
      const required = ["probe", "install", "update", "diagnose", "uninstall"];
      if (!required.every((name) => typeof adapter[name] === "function")) {
        return { registered: false, reason: "incomplete-contract" };
      }
      if (adapters.has(adapter.adapterId)) {
        return { registered: true, duplicate: true };
      }
      adapters.set(adapter.adapterId, adapter);
      return { registered: true, duplicate: false };
    },
    handshake(requestId) {
      return responseEnvelope({
        runtimeVersion,
        requestId,
        adapterId: "runtime",
        operation: "handshake",
        config: null
      }, {
        runtimeVersion,
        implementationRevision,
        rehydrationRequired: !hydrated,
        hydrated
      }, null);
    },
    markHydrated() {
      hydrated = true;
      return { runtimeVersion, implementationRevision, hydrated };
    },
    hydrationState() {
      return { rehydrationRequired: !hydrated, hydrated };
    },
    install: execute,
    update: execute,
    diagnose: execute,
    uninstall: execute,
    execute,
    installAll(requests) {
      return Array.isArray(requests) ? requests.map(execute) : [];
    },
    surface,
    observe,
    observerCount() {
      return observers.size;
    },
    performanceSnapshot() {
      return {
        policy: performancePolicy,
        observers: Array.from(observers.entries()).map(([adapterId, record]) => ({
          adapterId,
          strikeCount: record.strikes,
          degraded: record.degraded,
          lastDurationMilliseconds: record.lastDurationMilliseconds,
          qualified: record.qualified,
          recoverable: record.recoverable,
          failureReason: record.failureReason
        })),
        events: performanceEvents.slice()
      };
    }
  };

  const runtimeAPI = existingRuntime && typeof existingRuntime === "object"
    ? existingRuntime
    : newRuntimeAPI;
  if (runtimeAPI === existingRuntime) {
    Object.assign(runtimeAPI, newRuntimeAPI);
  } else {
    Object.defineProperty(window, "__codexAppExtensionV2", {
      value: runtimeAPI,
      configurable: false,
      enumerable: false,
      writable: false
    });
  }
})(window);
