(function registerWideLayout(window) {
  "use strict";
  const runtime = window.__codexAppExtensionV2;
  const adapterId = "wide-layout";
  const styleId = "cae-wide-layout-style";
  const marker = "data-cae-wide-layout";
  const properties = [
    "--thread-content-max-width",
    "--thread-composer-max-width",
    "--markdown-wide-block-max-width",
    "--cae-wide-layout-side-padding",
    "--cae-wide-layout-content-offset-x"
  ];
  const canonicalWidthConsumer = "[class*='thread-content-max-width']";
  const composerWidthConsumer = "[class*='thread-composer-max-width']";
  const ownerOffsetProperty = "--cae-wide-layout-owner-offset-x";
  const persistentRightRail = [
    "[class*='thread-floating-content-top-inset'][class*='thread-floating-content-bottom-inset']",
    "[data-codex-app-extension-native-floating-panel='true']"
  ].join(", ");
  const transientOverlayRoles = new Set(["menu", "listbox", "dialog"]);
  const excludedContentScope = [
    "[data-selected-text-overlay-target]",
    "[data-selected-text-overlay-target] *",
    "[class*='markdown-wide-block-max-width']",
    "[class*='markdown-wide-block-max-width'] *",
    ".ProseMirror[contenteditable='true']",
    ".ProseMirror[contenteditable='true'] *",
    ".ProseMirror[contenteditable='plaintext-only']",
    ".ProseMirror[contenteditable='plaintext-only'] *",
    "[role='menu']",
    "[role='menu'] *",
    "[role='listbox']",
    "[role='listbox'] *",
    "[role='dialog']",
    "[role='dialog'] *",
    "[class*='thread-floating-content']",
    "[class*='thread-floating-content'] *",
    "[data-codex-app-extension-native-floating-panel='true']",
    "[data-codex-app-extension-native-floating-panel='true'] *"
  ].join(", ");
  let unsubscribe = null;
  let activeConfig = null;
  let target = null;
  let attributeSnapshot = null;
  let propertySnapshots = null;
  let styleSnapshot = null;
  let geometryObserver = null;
  let geometryMutationObserver = null;
  let observedGeometryNodes = [];
  let observedWidthOwners = [];
  let observedRailShells = [];
  let observedNativeShiftNodes = [];
  let observedMotionNodes = [];
  let ownerPropertySnapshots = new Map();
  let activeGeometryMotions = new Map();
  let geometryFrame = null;
  let windowResizeBound = false;
  let cachedOrdinaryIdentity = null;
  let lastPublicState = null;
  let lastOwnerOffsets = [];

  function captureAttribute(node, name) {
    return { existed: node.hasAttribute(name), value: node.getAttribute(name) };
  }

  function writeAttribute(node, name, value) {
    if (node.hasAttribute(name) && node.getAttribute(name) === value) return false;
    node.setAttribute(name, value);
    return true;
  }

  function restoreAttribute(node, name, snapshot) {
    if (snapshot?.existed) return writeAttribute(node, name, snapshot.value ?? "");
    if (!node.hasAttribute(name)) return false;
    node.removeAttribute(name);
    return true;
  }

  function captureProperties(node) {
    return Object.fromEntries(properties.map((name) => [name, {
      value: node.style.getPropertyValue(name),
      priority: node.style.getPropertyPriority(name)
    }]));
  }

  function writeProperty(node, name, value, priority = "") {
    if (node.style.getPropertyValue(name) === value &&
        node.style.getPropertyPriority(name) === priority) {
      return false;
    }
    node.style.setProperty(name, value, priority);
    return true;
  }

  function restoreProperties(node, snapshots) {
    let changed = false;
    for (const name of properties) {
      const snapshot = snapshots?.[name];
      if (snapshot?.value) {
        changed = writeProperty(node, name, snapshot.value, snapshot.priority) || changed;
      } else if (node.style.getPropertyValue(name) || node.style.getPropertyPriority(name)) {
        node.style.removeProperty(name);
        changed = true;
      }
    }
    return changed;
  }

  function desiredStyleText() {
    const scope = ".thread-scroll-container[data-cae-wide-layout='true']";
    const widthOwners = [canonicalWidthConsumer, composerWidthConsumer];
    const outsideOwnerAncestor = widthOwners
      .map((selector) => `:not(${selector} *)`)
      .join("");
    const outsideExcludedContent = `:not(${excludedContentScope})`;
    const contentSelector = widthOwners.map((selector) =>
      `${scope} ${selector}${outsideOwnerAncestor}${outsideExcludedContent}`
    ).join(",\n");
    return [
      `${contentSelector} {`,
      "  box-sizing: border-box;",
      "  inline-size: min(100%, var(--thread-content-max-width));",
      "  max-inline-size: var(--thread-content-max-width) !important;",
      "  max-width: var(--thread-content-max-width) !important;",
      `  translate: var(${ownerOffsetProperty}, var(--cae-wide-layout-content-offset-x)) 0 !important;`,
      "}"
    ].join("\n");
  }

  function elementRect(element) {
    if (!element || typeof element.getBoundingClientRect !== "function") return null;
    const rect = element.getBoundingClientRect();
    if (![rect.left, rect.right, rect.top, rect.bottom, rect.width, rect.height].every(Number.isFinite)) {
      return null;
    }
    return rect.width >= 1 && rect.height >= 1 ? rect : null;
  }

  function layoutReferenceRect(scroller) {
    const scrollerRect = elementRect(scroller);
    if (!scrollerRect) return null;
    const candidates = Array.from(scroller.children ?? [])
      .map(elementRect)
      .filter((rect) => rect &&
        rect.width >= scrollerRect.width * 0.75 &&
        rect.left >= scrollerRect.left - 1 &&
        rect.right <= scrollerRect.right + 1)
      .sort((left, right) => right.width - left.width);
    return candidates[0] ?? scrollerRect;
  }

  function hasPaintedPanelAppearance(element) {
    const style = typeof getComputedStyle === "function" ? getComputedStyle(element) : null;
    const background = style?.backgroundColor ?? "";
    const shadow = style?.boxShadow ?? "";
    const borderWidth = Math.max(
      Number.parseFloat(style?.borderLeftWidth ?? "0") || 0,
      Number.parseFloat(style?.borderRightWidth ?? "0") || 0,
      Number.parseFloat(style?.borderTopWidth ?? "0") || 0,
      Number.parseFloat(style?.borderBottomWidth ?? "0") || 0
    );
    return (background && background !== "transparent" && background !== "rgba(0, 0, 0, 0)") ||
      (shadow && shadow !== "none") ||
      borderWidth > 0;
  }

  function isWithinTransientRailSubtree(element, railShell) {
    for (let current = element; current && current !== railShell; current = current.parentElement) {
      if (transientOverlayRoles.has(current.getAttribute?.("role"))) return true;
    }
    return false;
  }

  function panelBodyCandidates(element) {
    const descendants = Array.from(element.querySelectorAll?.("*") ?? []);
    const candidates = element.getAttribute?.("data-codex-app-extension-native-floating-panel") === "true"
      ? [element, ...descendants]
      : descendants;
    return candidates.filter((candidate) => !isWithinTransientRailSubtree(candidate, element));
  }

  function renderedPanelBodyIntersectsRail(paintedBodies, railRect, referenceRect) {
    return paintedBodies.some((descendant) => {
      const rect = elementRect(descendant);
      if (!rect || rect.width < 80 || rect.height < 80) return false;
      const style = typeof getComputedStyle === "function" ? getComputedStyle(descendant) : null;
      if (style?.display === "none" || style?.visibility === "hidden" || Number(style?.opacity ?? 1) <= 0) {
        return false;
      }
      const horizontalOverlap = Math.min(rect.right, railRect.right, referenceRect.right) -
        Math.max(rect.left, railRect.left, referenceRect.left);
      const verticalOverlap = Math.min(rect.bottom, railRect.bottom, referenceRect.bottom) -
        Math.max(rect.top, railRect.top, referenceRect.top);
      if (horizontalOverlap < Math.min(80, rect.width / 2) || verticalOverlap < Math.min(80, rect.height / 2)) {
        return false;
      }
      return true;
    });
  }

  function isPersistentRailShell(element) {
    for (let current = element; current; current = current.parentElement) {
      if (transientOverlayRoles.has(current.getAttribute?.("role"))) return false;
    }
    const style = typeof getComputedStyle === "function" ? getComputedStyle(element) : null;
    const nativeRail = element.getAttribute?.("data-codex-app-extension-native-floating-panel") === "true";
    const className = element.getAttribute?.("class") ?? "";
    const nativeRailShell = className.includes("thread-floating-content-top-inset") &&
      className.includes("thread-floating-content-bottom-inset");
    return nativeRail || (nativeRailShell && style?.pointerEvents === "none");
  }

  function persistentRailCandidates() {
    if (!document.body) return [];
    return Array.from(document.querySelectorAll(persistentRightRail));
  }

  function persistentRailRecords(candidates) {
    return candidates.filter(isPersistentRailShell).map((element) => {
      const bodies = panelBodyCandidates(element);
      return {
        element,
        paintedBodies: bodies.filter(hasPaintedPanelAppearance)
      };
    });
  }

  function isWidthOwnerNode(node) {
    const className = node?.getAttribute?.("class") ?? "";
    return className.includes("thread-content-max-width") || className.includes("thread-composer-max-width");
  }

  function isExcludedWidthOwner(candidate, scroller) {
    for (let current = candidate; current && current !== scroller; current = current.parentElement) {
      const className = current.getAttribute?.("class") ?? "";
      const editable = current.getAttribute?.("contenteditable");
      if (current.hasAttribute?.("data-selected-text-overlay-target") ||
          className.includes("markdown-wide-block-max-width") ||
          (className.includes("ProseMirror") && (editable === "true" || editable === "plaintext-only")) ||
          transientOverlayRoles.has(current.getAttribute?.("role")) ||
          className.includes("thread-floating-content") ||
          current.getAttribute?.("data-codex-app-extension-native-floating-panel") === "true") {
        return true;
      }
    }
    return false;
  }

  function enhancedWidthOwners(scroller) {
    const candidates = [
      ...Array.from(scroller?.querySelectorAll?.(canonicalWidthConsumer) ?? []),
      ...Array.from(scroller?.querySelectorAll?.(composerWidthConsumer) ?? [])
    ];
    return candidates.filter((candidate, index) => {
      if (candidates.indexOf(candidate) !== index || isExcludedWidthOwner(candidate, scroller)) return false;
      for (let current = candidate.parentElement; current && current !== scroller; current = current.parentElement) {
        if (isWidthOwnerNode(current)) return false;
      }
      return true;
    });
  }

  function canonicalContentOwner(scroller, owners = enhancedWidthOwners(scroller)) {
    return owners
      .find((owner) => (owner.getAttribute?.("class") ?? "").includes("thread-content-max-width")) ?? null;
  }

  function nativeShiftNodes(scroller, owner = canonicalContentOwner(scroller)) {
    const nodes = [];
    for (let current = owner?.parentElement;
         current && current !== scroller;
         current = current.parentElement) {
      nodes.push(current);
    }
    return nodes;
  }

  function matrixTranslationX(transform) {
    if (!transform || transform === "none") return 0;
    const match = String(transform).match(/^matrix(3d)?\((.+)\)$/);
    if (!match) return 0;
    const values = match[2].split(",").map((value) => Number.parseFloat(value.trim()));
    const pureTranslation = match[1]
      ? values.length === 16 && [0, 5, 10, 15].every((index) => values[index] === 1) &&
        [1, 2, 3, 4, 6, 7, 8, 9, 11].every((index) => values[index] === 0)
      : values.length === 6 && values[0] === 1 && values[1] === 0 && values[2] === 0 && values[3] === 1;
    if (!pureTranslation) return 0;
    const index = match[1] ? 12 : 4;
    return Number.isFinite(values[index]) ? values[index] : 0;
  }

  function individualTranslationX(translate) {
    if (!translate || translate === "none") return 0;
    const token = String(translate).trim().split(/\s+/)[0];
    if (!token.endsWith("px") && !/^-?0(?:\.0+)?$/.test(token)) return 0;
    const value = Number.parseFloat(token);
    return Number.isFinite(value) ? value : 0;
  }

  function nativeAncestorOffsetX(scroller, owner) {
    const ownerStyle = typeof getComputedStyle === "function" ? getComputedStyle(owner) : null;
    // The extension owns the width owner's individual `translate`; only its native
    // transform participates in the host offset or the residual would feed back.
    const ownerTransformOffset = matrixTranslationX(ownerStyle?.transform);
    return nativeShiftNodes(scroller, owner).reduce((total, node) => {
      const style = typeof getComputedStyle === "function" ? getComputedStyle(node) : null;
      return total + matrixTranslationX(style?.transform) + individualTranslationX(style?.translate);
    }, ownerTransformOffset);
  }

  function findPersistentRightRail(referenceRect, railRecords) {
    if (!referenceRect) return null;
    const viewportRight = window.innerWidth || referenceRect.right;
    const minimumHeight = Math.min(160, Math.max(96, (window.innerHeight || 0) * 0.10));
    const candidates = railRecords
      .map((record) => ({ ...record, rect: elementRect(record.element) }))
      .filter(({ element, paintedBodies, rect }) => {
        if (!rect || rect.width < 80 || rect.height < minimumHeight) return false;
        const style = typeof getComputedStyle === "function" ? getComputedStyle(element) : null;
        return renderedPanelBodyIntersectsRail(paintedBodies, rect, referenceRect) &&
          rect.left > referenceRect.left + 120 &&
          rect.left < referenceRect.right - 40 &&
          (rect.right >= referenceRect.right - 80 || rect.right >= viewportRight - 80) &&
          rect.bottom > referenceRect.top + 80 &&
          rect.top < referenceRect.bottom - 80 &&
          style?.display !== "none" &&
          style?.visibility !== "hidden";
      })
      .sort((left, right) => left.rect.left - right.rect.left);
    return candidates[0] ?? null;
  }

  function sameNodes(left, right) {
    return left.length === right.length && left.every((node, index) => node === right[index]);
  }

  function uniqueNodes(nodes) {
    return nodes.filter((node, index) => node && nodes.indexOf(node) === index);
  }

  function ancestorPath(node, boundary) {
    const nodes = [];
    for (let current = node?.parentElement;
         current && current !== boundary;
         current = current.parentElement) {
      nodes.push(current);
      if (current === document.body || current === document.documentElement) break;
    }
    return nodes;
  }

  function hostSignal(node) {
    return {
      node,
      className: node.getAttribute?.("class") ?? null,
      style: node.getAttribute?.("style") ?? null,
      hidden: node.getAttribute?.("hidden") ?? null,
      ariaHidden: node.getAttribute?.("aria-hidden") ?? null,
      state: node.getAttribute?.("data-state") ?? null
    };
  }

  function sameHostSignals(left, right) {
    return left.length === right.length && left.every((signal, index) => {
      const other = right[index];
      return signal.node === other.node &&
        signal.className === other.className &&
        signal.style === other.style &&
        signal.hidden === other.hidden &&
        signal.ariaHidden === other.ariaHidden &&
        signal.state === other.state;
    });
  }

  function ordinaryIdentity(currentSurface, owners, railCandidates) {
    const ownerHosts = uniqueNodes(owners.flatMap((owner) =>
      nativeShiftNodes(currentSurface.threadScroller, owner)));
    const railHosts = uniqueNodes(railCandidates.flatMap((rail) =>
      [rail, ...ancestorPath(rail, currentSurface.layoutRoot)]));
    return {
      surfaceRevision: currentSurface.revision,
      layoutRoot: currentSurface.layoutRoot,
      threadScroller: currentSurface.threadScroller,
      owners,
      railCandidates,
      ownerHosts,
      hostSignals: uniqueNodes([...ownerHosts, ...railHosts]).map(hostSignal)
    };
  }

  function sameOrdinaryIdentity(left, right) {
    return Boolean(left && right &&
      left.surfaceRevision === right.surfaceRevision &&
      left.layoutRoot === right.layoutRoot &&
      left.threadScroller === right.threadScroller &&
      sameNodes(left.owners, right.owners) &&
      sameNodes(left.railCandidates, right.railCandidates) &&
      sameNodes(left.ownerHosts, right.ownerHosts) &&
      sameHostSignals(left.hostSignals, right.hostSignals));
  }

  function appliedStateMatches() {
    if (!target || !lastPublicState || target.getAttribute(marker) !== "true") return false;
    const style = document.getElementById(styleId);
    if (!styleSnapshot || style !== styleSnapshot.node || style.textContent !== desiredStyleText()) return false;
    const propertiesMatch =
      target.style.getPropertyValue("--thread-content-max-width") === lastPublicState.effectiveWidth &&
      target.style.getPropertyValue("--thread-composer-max-width") === lastPublicState.effectiveWidth &&
      target.style.getPropertyValue("--markdown-wide-block-max-width") === lastPublicState.effectiveWidth &&
      target.style.getPropertyValue("--cae-wide-layout-side-padding") === lastPublicState.sidePadding &&
      target.style.getPropertyValue("--cae-wide-layout-content-offset-x") === lastPublicState.contentOffset;
    const ownerPropertiesMatch = lastOwnerOffsets.every(({ owner, residualOffset }) =>
      owner.style.getPropertyValue(ownerOffsetProperty) === (residualOffset === 0 ? "0px" : `${residualOffset}px`));
    return propertiesMatch && ownerPropertiesMatch;
  }

  function clearOrdinaryCache() {
    cachedOrdinaryIdentity = null;
    lastPublicState = null;
    lastOwnerOffsets = [];
  }

  function geometryObservationState(currentSurface, owners, railRecords) {
    if (!currentSurface?.qualified) return { nodes: [], widthOwners: [], railShells: [], nativeShiftNodes: [], motionNodes: [] };
    const railShells = railRecords.map((record) => record.element);
    const currentNativeShiftNodes = [];
    for (const owner of owners) {
      for (const node of nativeShiftNodes(currentSurface.threadScroller, owner)) {
        if (!currentNativeShiftNodes.includes(node)) currentNativeShiftNodes.push(node);
      }
    }
    const nodes = [];
    const motionNodes = [];
    const addNode = (node) => {
      if (node && !nodes.includes(node)) nodes.push(node);
    };
    addNode(currentSurface.layoutRoot);
    addNode(currentSurface.threadScroller);
    owners.forEach(addNode);
    for (const { element: railShell, paintedBodies } of railRecords) {
      addNode(railShell);
      motionNodes.push(railShell);
      for (const panelBody of paintedBodies) {
        addNode(panelBody);
        if (!motionNodes.includes(panelBody)) motionNodes.push(panelBody);
      }
    }
    for (const node of currentNativeShiftNodes) {
      if (!motionNodes.includes(node)) motionNodes.push(node);
    }
    return { nodes, widthOwners: owners.slice(), railShells, nativeShiftNodes: currentNativeShiftNodes, motionNodes };
  }

  function scheduleGeometryReconcile() {
    if (!activeConfig || geometryFrame !== null) return;
    geometryFrame = requestAnimationFrame(() => {
      geometryFrame = null;
      reconcile("geometry-resize", runtime.surface());
      if (activeGeometryMotions.size > 0) scheduleGeometryReconcile();
    });
  }

  function geometryMotionKey(event) {
    const kind = event.type.startsWith("animation") ? "animation" : "transition";
    return `${kind}:${event.animationName || event.propertyName || "*"}`;
  }

  function handleGeometryMotion(event) {
    const delegatedRailMotion = event.target !== event.currentTarget &&
      observedRailShells.includes(event.currentTarget) &&
      panelBodyCandidates(event.currentTarget).includes(event.target);
    if (event.target !== event.currentTarget && !delegatedRailMotion) return;
    const key = geometryMotionKey(event);
    const ending = event.type.endsWith("end") || event.type.endsWith("cancel");
    const motionTarget = event.target;
    const keys = activeGeometryMotions.get(motionTarget) ?? new Set();
    if (ending) keys.delete(key);
    else keys.add(key);
    if (keys.size > 0) activeGeometryMotions.set(motionTarget, keys);
    else activeGeometryMotions.delete(motionTarget);
    scheduleGeometryReconcile();
  }

  const geometryMotionEvents = [
    "transitionrun", "transitionstart", "transitionend", "transitioncancel",
    "animationstart", "animationend", "animationcancel"
  ];

  function rebindMotionListeners(nodes) {
    observedMotionNodes.forEach((node) => geometryMotionEvents.forEach((type) =>
      node.removeEventListener?.(type, handleGeometryMotion)));
    observedMotionNodes = nodes;
    for (const motionTarget of activeGeometryMotions.keys()) {
      const retainedDirectly = nodes.includes(motionTarget);
      const retainedByRail = observedRailShells.some((railShell) =>
        panelBodyCandidates(railShell).includes(motionTarget));
      if (!retainedDirectly && !retainedByRail) activeGeometryMotions.delete(motionTarget);
    }
    observedMotionNodes.forEach((node) => geometryMotionEvents.forEach((type) =>
      node.addEventListener?.(type, handleGeometryMotion)));
  }

  function bindGeometryObservers(currentSurface, owners, railRecords) {
    if (!windowResizeBound && typeof window.addEventListener === "function") {
      window.addEventListener("resize", scheduleGeometryReconcile);
      windowResizeBound = true;
    }
    const observationState = geometryObservationState(currentSurface, owners, railRecords);
    if (sameNodes(observationState.nodes, observedGeometryNodes) &&
        sameNodes(observationState.widthOwners, observedWidthOwners) &&
        sameNodes(observationState.railShells, observedRailShells) &&
        sameNodes(observationState.nativeShiftNodes, observedNativeShiftNodes) &&
        sameNodes(observationState.motionNodes, observedMotionNodes)) return;
    observedGeometryNodes = observationState.nodes;
    observedWidthOwners = observationState.widthOwners;
    observedRailShells = observationState.railShells;
    observedNativeShiftNodes = observationState.nativeShiftNodes;
    rebindMotionListeners(observationState.motionNodes);
    geometryObserver?.disconnect();
    if (typeof window.ResizeObserver === "function" && observedGeometryNodes.length > 0) {
      geometryObserver ??= new window.ResizeObserver(scheduleGeometryReconcile);
      observedGeometryNodes.forEach((node) => geometryObserver.observe(node));
    }
    geometryMutationObserver?.disconnect();
    if (typeof window.MutationObserver === "function" &&
        (observedWidthOwners.length > 0 || observedRailShells.length > 0 || observedNativeShiftNodes.length > 0)) {
      geometryMutationObserver ??= new window.MutationObserver(scheduleGeometryReconcile);
      observedWidthOwners.forEach((owner) => geometryMutationObserver.observe(owner, {
        attributes: true,
        attributeFilter: ["class", "style", "hidden", "aria-hidden", "data-state"]
      }));
      observedRailShells.forEach((railShell) => geometryMutationObserver.observe(railShell, {
        attributes: true,
        childList: true,
        subtree: true,
        attributeFilter: ["class", "style", "hidden", "aria-hidden", "data-state"]
      }));
      observedNativeShiftNodes.forEach((node) => geometryMutationObserver.observe(node, {
        attributes: true,
        attributeFilter: ["class", "style", "hidden", "aria-hidden", "data-state"]
      }));
    }
  }

  function stopGeometryObservers() {
    geometryObserver?.disconnect();
    geometryObserver = null;
    geometryMutationObserver?.disconnect();
    geometryMutationObserver = null;
    observedGeometryNodes = [];
    observedWidthOwners = [];
    observedRailShells = [];
    observedNativeShiftNodes = [];
    rebindMotionListeners([]);
    if (windowResizeBound && typeof window.removeEventListener === "function") {
      window.removeEventListener("resize", scheduleGeometryReconcile);
    }
    windowResizeBound = false;
    if (geometryFrame !== null) {
      cancelAnimationFrame(geometryFrame);
      geometryFrame = null;
    }
  }

  function layoutState(scroller, owners, railRecords) {
    const maximumWidth = Math.max(1, Number(activeConfig.maximumContentWidth) || 1);
    const minimumSidePadding = Math.max(0, Number(activeConfig.minimumSidePadding) || 0);
    const referenceRect = layoutReferenceRect(scroller);
    if (!referenceRect) {
      return {
        maximumWidth: `${maximumWidth}px`,
        effectiveWidth: `min(${maximumWidth}px, max(1px, calc(100% - ${minimumSidePadding * 2}px)))`,
        sidePadding: `${minimumSidePadding}px`,
        contentOffset: "0px",
        availableWidth: null,
        rightBoundary: null,
        rightRail: false,
        ownerOffsets: []
      };
    }

    const rail = findPersistentRightRail(referenceRect, railRecords);
    const rightBoundary = rail ? Math.min(referenceRect.right, rail.rect.left) : referenceRect.right;
    const availableWidth = Math.max(1, Math.floor(rightBoundary - referenceRect.left));
    const usableWidth = Math.max(1, availableWidth - minimumSidePadding * 2);
    const effectiveWidthPixels = Math.max(1, Math.min(maximumWidth, usableWidth));
    const rightInset = Math.max(0, referenceRect.right - rightBoundary);
    const requestedShift = Math.max(0, Math.floor(rightInset / 2));
    const naturalLeftMargin = Math.max(0, (referenceRect.width - effectiveWidthPixels) / 2);
    const maximumSafeShift = Math.max(0, Math.floor(naturalLeftMargin - minimumSidePadding));
    const desiredTotalOffset = -Math.min(requestedShift, maximumSafeShift);
    const ownerOffsets = owners.map((owner) => {
      const nativeOffset = nativeAncestorOffsetX(scroller, owner);
      const residualOffset = rail ? Math.round(desiredTotalOffset - nativeOffset) : 0;
      return { owner, nativeOffset, residualOffset };
    });
    const primaryOffset = ownerOffsets.find(({ owner }) => owner === canonicalContentOwner(scroller, owners)) ?? ownerOffsets[0];
    return {
      maximumWidth: `${maximumWidth}px`,
      effectiveWidth: `${effectiveWidthPixels}px`,
      sidePadding: `${minimumSidePadding}px`,
      contentOffset: primaryOffset?.residualOffset ? `${primaryOffset.residualOffset}px` : "0px",
      availableWidth,
      rightBoundary: Math.round(rightBoundary * 100) / 100,
      rightRail: Boolean(rail),
      nativeContentOffset: Math.round((primaryOffset?.nativeOffset ?? 0) * 100) / 100,
      ownerOffsets
    };
  }

  function restoreOwnerProperties(keeping = []) {
    let changed = false;
    for (const [owner, snapshot] of ownerPropertySnapshots) {
      if (keeping.includes(owner)) continue;
      if (snapshot.value) changed = writeProperty(owner, ownerOffsetProperty, snapshot.value, snapshot.priority) || changed;
      else if (owner.style.getPropertyValue(ownerOffsetProperty) || owner.style.getPropertyPriority(ownerOffsetProperty)) {
        owner.style.removeProperty(ownerOffsetProperty);
        changed = true;
      }
      ownerPropertySnapshots.delete(owner);
    }
    return changed;
  }

  function applyOwnerOffsets(ownerOffsets) {
    const owners = ownerOffsets.map(({ owner }) => owner);
    let changed = restoreOwnerProperties(owners);
    for (const { owner, residualOffset } of ownerOffsets) {
      if (!ownerPropertySnapshots.has(owner)) {
        ownerPropertySnapshots.set(owner, {
          value: owner.style.getPropertyValue(ownerOffsetProperty),
          priority: owner.style.getPropertyPriority(ownerOffsetProperty)
        });
      }
      const value = residualOffset === 0 ? "0px" : `${residualOffset}px`;
      changed = writeProperty(owner, ownerOffsetProperty, value) || changed;
    }
    return changed;
  }

  function ensureStyle() {
    let changed = false;
    let style = document.getElementById(styleId);
    if (!style) {
      style = document.createElement("style");
      style.id = styleId;
      document.head.appendChild(style);
      styleSnapshot = { node: style, existed: false, text: "" };
      changed = true;
    } else if (!styleSnapshot || styleSnapshot.node !== style) {
      styleSnapshot = { node: style, existed: true, text: style.textContent };
    }
    const desired = desiredStyleText();
    if (style.textContent !== desired) {
      style.textContent = desired;
      changed = true;
    }
    return changed;
  }

  function restoreTarget() {
    let changed = restoreOwnerProperties();
    if (!target) return changed;
    changed = restoreAttribute(target, marker, attributeSnapshot) || changed;
    changed = restoreProperties(target, propertySnapshots) || changed;
    target = null;
    attributeSnapshot = null;
    propertySnapshots = null;
    return changed;
  }

  function restoreStyle() {
    if (!styleSnapshot) return false;
    let changed = false;
    if (styleSnapshot.existed) {
      if (styleSnapshot.node.textContent !== styleSnapshot.text) {
        styleSnapshot.node.textContent = styleSnapshot.text;
        changed = true;
      }
    } else if (styleSnapshot.node.isConnected || styleSnapshot.node.parentElement) {
      styleSnapshot.node.remove();
      changed = true;
    }
    styleSnapshot = null;
    return changed;
  }

  function probe() {
    const surface = runtime.surface();
    const contentCandidateCount = surface.qualified ? enhancedWidthOwners(surface.threadScroller).length : 0;
    const qualified = Boolean(surface.qualified && contentCandidateCount > 0);
    const recoverable = surface.layoutRootCount === 0 ||
      (surface.layoutRootCount === 1 && surface.threadScrollerCount === 0);
    return {
      qualified,
      recoverable: !qualified && (recoverable || (surface.qualified && contentCandidateCount === 0)),
      reason: qualified ? null : surface.qualified ? "wide-content-candidate-missing" : "native-surface-not-unique"
    };
  }

  function reconcile(reason, observedSurface) {
    const currentSurface = observedSurface ?? runtime.surface();
    const owners = currentSurface.qualified ? enhancedWidthOwners(currentSurface.threadScroller) : [];
    const railCandidates = persistentRailCandidates();
    const identity = ordinaryIdentity(currentSurface, owners, railCandidates);
    const ordinaryRefresh = reason === "animation-frame" || reason === "settled";
    if (ordinaryRefresh && activeConfig && currentSurface.qualified && owners.length > 0 &&
        target === currentSurface.threadScroller && sameOrdinaryIdentity(identity, cachedOrdinaryIdentity) &&
        appliedStateMatches()) {
      return { changed: false, qualified: true, recoverable: false, ...lastPublicState };
    }
    const railRecords = persistentRailRecords(railCandidates);
    bindGeometryObservers(currentSurface, owners, railRecords);
    const contentCandidateCount = owners.length;
    if (!activeConfig || !currentSurface.qualified || contentCandidateCount === 0) {
      clearOrdinaryCache();
      let changed = restoreTarget();
      changed = restoreStyle() || changed;
      const recoverable = currentSurface.layoutRootCount === 0 ||
        (currentSurface.layoutRootCount === 1 && currentSurface.threadScrollerCount === 0) ||
        (currentSurface.qualified && contentCandidateCount === 0);
      return {
        changed,
        qualified: false,
        recoverable,
        reason: currentSurface.qualified ? "wide-content-candidate-missing" : "native-surface-not-unique"
      };
    }
    const scroller = currentSurface.threadScroller;
    let changed = false;
    if (target && target !== scroller) changed = restoreTarget();
    if (!target) {
      target = scroller;
      attributeSnapshot = captureAttribute(target, marker);
      propertySnapshots = captureProperties(target);
    }
    changed = ensureStyle() || changed;
    changed = writeAttribute(target, marker, "true") || changed;
    const state = layoutState(target, owners, railRecords);
    changed = applyOwnerOffsets(state.ownerOffsets) || changed;
    changed = writeProperty(target, "--thread-content-max-width", state.effectiveWidth) || changed;
    changed = writeProperty(target, "--thread-composer-max-width", state.effectiveWidth) || changed;
    changed = writeProperty(target, "--markdown-wide-block-max-width", state.effectiveWidth) || changed;
    changed = writeProperty(target, "--cae-wide-layout-side-padding", state.sidePadding) || changed;
    changed = writeProperty(target, "--cae-wide-layout-content-offset-x", state.contentOffset) || changed;
    const { ownerOffsets: _ownerOffsets, ...publicState } = state;
    cachedOrdinaryIdentity = identity;
    lastPublicState = publicState;
    lastOwnerOffsets = state.ownerOffsets.slice();
    return { changed, qualified: true, recoverable: false, ...publicState };
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
    const owners = enhancedWidthOwners(target);
    const railRecords = persistentRailRecords(persistentRailCandidates());
    const state = layoutState(target, owners, railRecords);
    const ownerPropertiesMatch = state.ownerOffsets.every(({ owner, residualOffset }) =>
      owner.style.getPropertyValue(ownerOffsetProperty) === (residualOffset === 0 ? "0px" : `${residualOffset}px`));
    const propertiesMatch =
      target.style.getPropertyValue("--thread-content-max-width") === state.effectiveWidth &&
      target.style.getPropertyValue("--thread-composer-max-width") === state.effectiveWidth &&
      target.style.getPropertyValue("--markdown-wide-block-max-width") === state.effectiveWidth &&
      target.style.getPropertyValue("--cae-wide-layout-side-padding") === state.sidePadding &&
      target.style.getPropertyValue("--cae-wide-layout-content-offset-x") === state.contentOffset &&
      ownerPropertiesMatch;
    return propertiesMatch
      ? { qualified: true }
      : { qualified: false, reason: "adapter-property-mismatch" };
  }

  function uninstall() {
    stopGeometryObservers();
    let changed = restoreTarget();
    changed = restoreStyle() || changed;
    unsubscribe?.();
    unsubscribe = null;
    activeConfig = null;
    clearOrdinaryCache();
    return { changed };
  }

  runtime.register({ adapterId, probe, install: apply, update: apply, diagnose, uninstall });
})(window);
