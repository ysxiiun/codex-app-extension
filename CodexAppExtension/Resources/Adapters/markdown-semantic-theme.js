(function registerMarkdownSemanticTheme(window) {
  "use strict";
  const runtime = window.__codexAppExtensionV2;
  const adapterId = "markdown-semantic-theme";
  const styleId = "cae-markdown-semantic-theme-style";
  const marker = "data-cae-markdown-theme";
  const markdownCandidate = "[data-selected-text-overlay-target]";
  const properties = [
    "--cae-heading-color", "--cae-strong-color", "--cae-strong-weight",
    "--cae-inline-code-text", "--cae-inline-code-background", "--cae-inline-code-border",
    "--cae-blockquote-border", "--cae-blockquote-text", "--cae-blockquote-background"
  ];
  let unsubscribe = null;
  let activeConfig = null;
  let target = null;
  let attributeSnapshot = null;
  let propertySnapshots = null;
  let styleSnapshot = null;

  function candidates(scroller) {
    return scroller ? scroller.querySelectorAll(markdownCandidate) : [];
  }

  function probe() {
    const surface = runtime.surface();
    const roots = candidates(surface.threadScroller);
    const surfacePending = surface.layoutRootCount === 0 ||
      (surface.layoutRootCount === 1 && surface.threadScrollerCount === 0);
    return {
      qualified: Boolean(surface.qualified && roots.length > 0),
      recoverable: surfacePending || (surface.qualified && roots.length === 0),
      candidateCount: roots.length,
      reason: !surface.qualified ? "native-surface-not-unique" : roots.length ? null : "markdown-candidate-missing"
    };
  }

  function captureTarget(scroller) {
    target = scroller;
    attributeSnapshot = { existed: target.hasAttribute(marker), value: target.getAttribute(marker) };
    propertySnapshots = Object.fromEntries(properties.map((name) => [name, {
      value: target.style.getPropertyValue(name),
      priority: target.style.getPropertyPriority(name)
    }]));
  }

  function restoreTarget() {
    if (!target) return;
    if (attributeSnapshot?.existed) target.setAttribute(marker, attributeSnapshot.value ?? "");
    else target.removeAttribute(marker);
    for (const name of properties) {
      const snapshot = propertySnapshots?.[name];
      if (snapshot?.value) target.style.setProperty(name, snapshot.value, snapshot.priority);
      else target.style.removeProperty(name);
    }
    target = null;
    attributeSnapshot = null;
    propertySnapshots = null;
  }

  function ensureStyle(config) {
    let style = document.getElementById(styleId);
    let changed = false;
    if (!style) {
      style = document.createElement("style");
      style.id = styleId;
      document.head.appendChild(style);
      styleSnapshot = { node: style, existed: false, text: "" };
      changed = true;
    } else if (!styleSnapshot) {
      styleSnapshot = { node: style, existed: true, text: style.textContent };
    }
    const prefix = ".thread-scroll-container[data-cae-markdown-theme='true'] [data-selected-text-overlay-target]";
    const text = [
      config.heading.enabled
        ? `${prefix} :where(h1, h2, h3, h4, h5, h6) {\n  color: var(--cae-heading-color) !important;\n}`
        : "",
      config.strongText.enabled
        ? `${prefix} :where(p, li, blockquote, td, th) :where(strong) {\n  color: var(--cae-strong-color) !important;\n  font-weight: var(--cae-strong-weight) !important;\n}`
        : "",
      `${prefix} :where(.inline-markdown),\n${prefix} :where(p, li, blockquote, td, th, h1, h2, h3, h4, h5, h6) > code {\n  color: var(--cae-inline-code-text) !important;\n  background: var(--cae-inline-code-background) !important;\n  border: 1px solid var(--cae-inline-code-border) !important;\n  border-radius: 6px !important;\n  padding: 0.08em 0.36em !important;\n}`,
      `${prefix} :where(pre, pre *) code {\n  color: inherit !important;\n  background: transparent !important;\n  border: 0 !important;\n  border-radius: 0 !important;\n  padding: 0 !important;\n}`,
      `${prefix} :where(blockquote) {\n  color: var(--cae-blockquote-text) !important;\n  background: var(--cae-blockquote-background) !important;\n  border-left: 3px solid var(--cae-blockquote-border) !important;\n  border-radius: 0 6px 6px 0 !important;\n  margin-inline: 0 !important;\n  padding: 0.65em 0.9em !important;\n}`,
      // Nested quotes inherit text only, avoiding repeated background, border, and spacing.
      `${prefix} :where(blockquote) blockquote {\n  background: transparent !important;\n  border-left: 0 !important;\n  border-radius: 0 !important;\n  margin-inline: 0 !important;\n  padding: 0 !important;\n}`
    ].filter(Boolean).join("\n");
    if (style.textContent !== text) {
      style.textContent = text;
      changed = true;
    }
    return { style, changed };
  }

  function restoreStyle() {
    if (!styleSnapshot) return;
    if (styleSnapshot.existed) styleSnapshot.node.textContent = styleSnapshot.text;
    else styleSnapshot.node.remove();
    styleSnapshot = null;
  }

  function reconcile(_reason, observedSurface) {
    const surface = observedSurface ?? runtime.surface();
    const roots = candidates(surface.threadScroller);
    const qualification = {
      qualified: Boolean(surface.qualified && roots.length > 0),
      recoverable: surface.layoutRootCount === 0 ||
        (surface.layoutRootCount === 1 && surface.threadScrollerCount === 0) ||
        (surface.qualified && roots.length === 0),
      candidateCount: roots.length,
      reason: !surface.qualified ? "native-surface-not-unique" : roots.length ? null : "markdown-candidate-missing"
    };
    if (!qualification.qualified) {
      restoreTarget();
      restoreStyle();
      return { changed: false, qualified: false, recoverable: qualification.recoverable, reason: qualification.reason };
    }
    const scroller = surface.threadScroller;
    if (target && target !== scroller) restoreTarget();
    if (!target) captureTarget(scroller);
    const styleResult = ensureStyle(activeConfig);
    let changed = styleResult.changed;
    if (target.getAttribute(marker) !== "true") {
      target.setAttribute(marker, "true");
      changed = true;
    }
    const values = {
      "--cae-heading-color": activeConfig.heading.color,
      "--cae-strong-color": activeConfig.strongText.color,
      "--cae-strong-weight": String(activeConfig.strongText.fontWeight),
      "--cae-inline-code-text": activeConfig.inlineCode.textColor,
      "--cae-inline-code-background": activeConfig.inlineCode.backgroundColor,
      "--cae-inline-code-border": activeConfig.inlineCode.borderColor,
      "--cae-blockquote-border": activeConfig.blockquote.borderColor,
      "--cae-blockquote-text": activeConfig.blockquote.textColor,
      "--cae-blockquote-background": activeConfig.blockquote.backgroundColor
    };
    for (const [name, value] of Object.entries(values)) {
      if (target.style.getPropertyValue(name) === value && target.style.getPropertyPriority(name) === "") continue;
      target.style.setProperty(name, value);
      changed = true;
    }
    return {
      changed,
      qualified: true,
      recoverable: false,
      candidateCount: qualification.candidateCount,
      styleInstalled: Boolean(styleResult.style)
    };
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
    if (target !== surface.threadScroller) return { qualified: false, reason: "adapter-target-stale" };
    if (target.getAttribute(marker) !== "true") return { qualified: false, reason: "adapter-marker-missing" };
    const style = document.getElementById(styleId);
    if (!styleSnapshot || style !== styleSnapshot.node || !style.textContent.includes(marker)) {
      return { qualified: false, reason: "adapter-style-missing" };
    }
    const values = {
      "--cae-heading-color": activeConfig.heading.color,
      "--cae-strong-color": activeConfig.strongText.color,
      "--cae-strong-weight": String(activeConfig.strongText.fontWeight),
      "--cae-inline-code-text": activeConfig.inlineCode.textColor,
      "--cae-inline-code-background": activeConfig.inlineCode.backgroundColor,
      "--cae-inline-code-border": activeConfig.inlineCode.borderColor,
      "--cae-blockquote-border": activeConfig.blockquote.borderColor,
      "--cae-blockquote-text": activeConfig.blockquote.textColor,
      "--cae-blockquote-background": activeConfig.blockquote.backgroundColor
    };
    const propertiesMatch = Object.entries(values).every(
      ([name, value]) => target.style.getPropertyValue(name) === value
    );
    return propertiesMatch
      ? { qualified: true, candidateCount: qualification.candidateCount }
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
