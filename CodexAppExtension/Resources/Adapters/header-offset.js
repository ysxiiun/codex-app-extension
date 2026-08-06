(function registerHeaderOffset(window) {
  "use strict";
  const runtime = window.__codexAppExtensionV2;
  const adapterId = "header-offset";
  const styleId = "cae-header-offset-style";
  const marker = "data-cae-header-offset";
  const offsetProperty = "--cae-header-offset";
  const nativeOffsetProperties = [
    "--app-shell-main-content-frame-top-offset",
    "--inset-toolbar",
    "--height-toolbar"
  ];
  let unsubscribe = null;
  let activeConfig = null;
  let target = null;
  let attributeSnapshot = null;
  let propertySnapshot = null;
  let styleSnapshot = null;

  function captureAttribute(node) {
    return { existed: node.hasAttribute(marker), value: node.getAttribute(marker) };
  }

  function restoreAttribute(node, snapshot) {
    if (snapshot?.existed) node.setAttribute(marker, snapshot.value ?? "");
    else node.removeAttribute(marker);
  }

  function captureProperty(node) {
    return {
      value: node.style.getPropertyValue(offsetProperty),
      priority: node.style.getPropertyPriority(offsetProperty)
    };
  }

  function restoreProperty(node, snapshot) {
    if (snapshot?.value) node.style.setProperty(offsetProperty, snapshot.value, snapshot.priority);
    else node.style.removeProperty(offsetProperty);
  }

  function ensureStyle() {
    let style = document.getElementById(styleId);
    if (!style) {
      style = document.createElement("style");
      style.id = styleId;
      document.head.appendChild(style);
      styleSnapshot = { node: style, existed: false, text: "" };
    } else if (!styleSnapshot) {
      styleSnapshot = { node: style, existed: true, text: style.textContent };
    }
    style.textContent = [
      "[data-app-shell-main-content-layout][data-cae-header-offset='true'] {",
      "  box-sizing: border-box;",
      "  padding-top: var(--cae-header-offset) !important;",
      "}",
      "[data-app-shell-main-content-layout][data-cae-header-offset='true'] .thread-scroll-container {",
      "  scroll-padding-top: var(--cae-header-offset);",
      "}"
    ].join("\n");
  }

  function automaticOffset(layoutRoot) {
    const computed = window.getComputedStyle(layoutRoot);
    for (const property of nativeOffsetProperties) {
      const value = computed.getPropertyValue(property).trim();
      const match = /^(-?(?:\d+|\d*\.\d+))px$/.exec(value);
      if (match) return Math.max(0, Number(match[1]));
    }
    return null;
  }

  function probe() {
    const surface = runtime.surface();
    const recoverable = surface.layoutRootCount === 0 ||
      (surface.layoutRootCount === 1 && surface.threadScrollerCount === 0);
    return {
      qualified: Boolean(surface.qualified),
      recoverable: !surface.qualified && recoverable,
      automaticOffsetAvailable: Boolean(surface.layoutRoot && automaticOffset(surface.layoutRoot) !== null),
      reason: surface.qualified ? null : "native-surface-not-unique"
    };
  }

  function restoreTarget() {
    if (!target) return;
    restoreAttribute(target, attributeSnapshot);
    restoreProperty(target, propertySnapshot);
    target = null;
    attributeSnapshot = null;
    propertySnapshot = null;
  }

  function restoreStyle() {
    if (!styleSnapshot) return;
    if (styleSnapshot.existed) styleSnapshot.node.textContent = styleSnapshot.text;
    else styleSnapshot.node.remove();
    styleSnapshot = null;
  }

  function resolveOffset(config, layoutRoot) {
    if (config.mode === "custom") return Math.max(0, Number(config.customOffset));
    return automaticOffset(layoutRoot);
  }

  function writeOffset(offset) {
    const value = `${offset}px`;
    if (target.style.getPropertyValue(offsetProperty) === value &&
        target.style.getPropertyPriority(offsetProperty) === "") {
      return false;
    }
    target.style.setProperty(offsetProperty, value);
    return true;
  }

  function reconcile(_reason, observedSurface) {
    const surface = observedSurface ?? runtime.surface();
    if (!activeConfig || !surface.qualified) {
      restoreTarget();
      restoreStyle();
      const recoverable = surface.layoutRootCount === 0 ||
        (surface.layoutRootCount === 1 && surface.threadScrollerCount === 0);
      return { changed: false, qualified: false, recoverable, reason: "native-surface-not-unique" };
    }
    const offset = resolveOffset(activeConfig, surface.layoutRoot);
    if (offset === null) {
      restoreTarget();
      restoreStyle();
      return { changed: false, qualified: false, recoverable: false, reason: "native-toolbar-offset-unavailable" };
    }
    if (target && target !== surface.layoutRoot) restoreTarget();
    if (!target) {
      target = surface.layoutRoot;
      attributeSnapshot = captureAttribute(target);
      propertySnapshot = captureProperty(target);
    }
    ensureStyle();
    target.setAttribute(marker, "true");
    const offsetChanged = writeOffset(offset);
    return { changed: true, qualified: true, recoverable: false, mode: activeConfig.mode, offset, offsetChanged };
  }

  function apply(config) {
    activeConfig = config;
    const surface = runtime.surface();
    unsubscribe ??= runtime.observe(adapterId, reconcile);
    return reconcile("apply", surface);
  }

  function diagnose() {
    const qualification = probe();
    if (!qualification.qualified) return qualification;
    const surface = runtime.surface();
    if (!activeConfig || !target) return { qualified: false, reason: "adapter-not-installed" };
    if (!unsubscribe) return { qualified: false, reason: "adapter-observer-missing" };
    if (target !== surface.layoutRoot) return { qualified: false, reason: "adapter-target-stale" };
    if (target.getAttribute(marker) !== "true") return { qualified: false, reason: "adapter-marker-missing" };
    const style = document.getElementById(styleId);
    if (!styleSnapshot || style !== styleSnapshot.node || !style.textContent.includes(marker)) {
      return { qualified: false, reason: "adapter-style-missing" };
    }
    const offset = resolveOffset(activeConfig, surface.layoutRoot);
    if (offset === null) return { qualified: false, reason: "native-toolbar-offset-unavailable" };
    return target.style.getPropertyValue(offsetProperty) === `${offset}px`
      ? { qualified: true, mode: activeConfig.mode, offset }
      : { qualified: false, reason: "adapter-property-mismatch" };
  }

  function uninstall() {
    restoreTarget();
    restoreStyle();
    unsubscribe?.();
    unsubscribe = null;
    activeConfig = null;
    return { changed: true };
  }

  runtime.register({ adapterId, probe, install: apply, update: apply, diagnose, uninstall });
})(window);
