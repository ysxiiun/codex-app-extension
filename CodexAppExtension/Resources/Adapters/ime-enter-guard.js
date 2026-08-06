(function registerIMEEnterGuard(window) {
  "use strict";
  const runtime = window.__codexAppExtensionV2;
  const adapterId = "ime-enter-guard";
  const marker = "data-cae-ime-enter-guard";
  const postCompositionGraceMilliseconds = 120;
  let unsubscribe = null;
  let activeConfig = null;
  let editor = null;
  let listenerTarget = null;
  let attributeSnapshot = null;
  let listenersInstalled = false;
  let compositionActive = false;
  let lastCompositionEnd = Number.NEGATIVE_INFINITY;
  let pendingTerminalEnter = false;

  function probe() {
    const surface = runtime.surface();
    const qualified = Boolean(surface.qualified && surface.editor);
    const recoverable = surface.layoutRootCount === 0 ||
      (surface.layoutRootCount === 1 && surface.threadScrollerCount === 0) ||
      (surface.qualified && surface.editorCount === 0);
    return {
      qualified,
      recoverable: !qualified && recoverable,
      reason: qualified ? null : surface.qualified ? "native-editor-not-unique" : "native-surface-not-unique"
    };
  }

  function onKeyDown(event) {
    const isEnterKey = event.key === "Enter" || event.code === "Enter";
    if (!editor || !(event.target === editor || editor.contains(event.target)) || !isEnterKey) {
      return;
    }
    const elapsedSinceCompositionEnd = Date.now() - lastCompositionEnd;
    const isInsideGrace = pendingTerminalEnter && elapsedSinceCompositionEnd >= 0 &&
      elapsedSinceCompositionEnd <= postCompositionGraceMilliseconds;
    if (event.isComposing || event.keyCode === 229 || compositionActive || isInsideGrace) {
      if (isInsideGrace) {
        pendingTerminalEnter = false;
        lastCompositionEnd = Number.NEGATIVE_INFINITY;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }

  function onCompositionStart(event) {
    if (editor && (event.target === editor || editor.contains(event.target))) {
      compositionActive = true;
      pendingTerminalEnter = false;
      lastCompositionEnd = Number.NEGATIVE_INFINITY;
    }
  }

  function onCompositionEnd(event) {
    if (editor && (event.target === editor || editor.contains(event.target))) {
      compositionActive = false;
      lastCompositionEnd = Date.now();
      pendingTerminalEnter = true;
    }
  }

  function restoreEditor() {
    if (!editor) return;
    listenerTarget?.removeEventListener("keydown", onKeyDown, true);
    listenerTarget?.removeEventListener("compositionstart", onCompositionStart, true);
    listenerTarget?.removeEventListener("compositionend", onCompositionEnd, true);
    listenerTarget = null;
    listenersInstalled = false;
    if (attributeSnapshot?.existed) editor.setAttribute(marker, attributeSnapshot.value ?? "");
    else editor.removeAttribute(marker);
    editor = null;
    attributeSnapshot = null;
    compositionActive = false;
    lastCompositionEnd = Number.NEGATIVE_INFINITY;
    pendingTerminalEnter = false;
  }

  function reconcile(_reason, observedSurface) {
    const surface = observedSurface ?? runtime.surface();
    if (!activeConfig?.protectCompositionEnter || !surface.qualified || !surface.editor) {
      restoreEditor();
      return {
        changed: false,
        qualified: false,
        recoverable: surface.layoutRootCount === 0 ||
          (surface.layoutRootCount === 1 && surface.threadScrollerCount === 0) ||
          (surface.qualified && surface.editorCount === 0),
        reason: surface.qualified ? "native-editor-not-unique" : "native-surface-not-unique"
      };
    }
    const nextEditor = surface.editor;
    if (editor !== nextEditor) {
      restoreEditor();
      editor = nextEditor;
      attributeSnapshot = { existed: editor.hasAttribute(marker), value: editor.getAttribute(marker) };
      // Window capture precedes document/React/ProseMirror delegated handlers. The
      // editor fallback exists only for minimal DOM hosts without window events.
      listenerTarget = typeof window.addEventListener === "function" ? window : editor;
      listenerTarget.addEventListener("keydown", onKeyDown, true);
      listenerTarget.addEventListener("compositionstart", onCompositionStart, true);
      listenerTarget.addEventListener("compositionend", onCompositionEnd, true);
      listenersInstalled = true;
    }
    editor.setAttribute(marker, "true");
    return { changed: true, qualified: true, recoverable: false, postCompositionGraceMilliseconds };
  }

  function install(config) {
    if (config.protectCompositionEnter === false) return uninstall();
    activeConfig = config;
    const surface = runtime.surface();
    unsubscribe ??= runtime.observe(adapterId, reconcile);
    return reconcile("apply", surface);
  }

  function diagnose() {
    const qualification = probe();
    if (!qualification.qualified) return qualification;
    const surface = runtime.surface();
    if (!activeConfig?.protectCompositionEnter || !editor) {
      return { qualified: false, reason: "adapter-not-installed" };
    }
    if (!unsubscribe) return { qualified: false, reason: "adapter-observer-missing" };
    if (editor !== surface.editor) return { qualified: false, reason: "adapter-editor-stale" };
    if (editor.getAttribute(marker) !== "true") return { qualified: false, reason: "adapter-marker-missing" };
    return listenersInstalled
      ? { qualified: true, postCompositionGraceMilliseconds }
      : { qualified: false, reason: "adapter-listeners-missing" };
  }

  function uninstall() {
    restoreEditor();
    unsubscribe?.();
    unsubscribe = null;
    activeConfig = null;
    return { changed: true };
  }

  runtime.register({ adapterId, probe, install, update: install, diagnose, uninstall });
})(window);
