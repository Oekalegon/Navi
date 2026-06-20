//
//  SplitPaneView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AppKit

struct SplitPaneView: View {
    var pane: SplitPane
    var paneManager: PaneManager

    var body: some View {
        if let direction = pane.direction, pane.children != nil {
            ManagedSplitView(pane: pane, paneManager: paneManager,
                             isHorizontal: direction == .horizontal)
        } else {
            PaneContentView(pane: pane)
        }
    }
}

// MARK: - Managed NSSplitView

// NSViewRepresentable that owns an NSSplitView directly, acting as its own
// NSSplitViewDelegate. This gives us synchronous control over divider positions
// when panes are added — the delegate's resizeSubviewsWithOldSize fires inside
// addSubview, before any layout pass, so no async timing tricks are needed.
struct ManagedSplitView: NSViewRepresentable {
    let pane: SplitPane
    let paneManager: PaneManager
    let isHorizontal: Bool

    func makeNSView(context: Context) -> ManagedSplitContainer {
        ManagedSplitContainer(pane: pane, paneManager: paneManager, isHorizontal: isHorizontal)
    }

    func updateNSView(_ nsView: ManagedSplitContainer, context: Context) {
        // Children sync is driven by withObservationTracking inside the container.
    }
}

final class ManagedSplitContainer: NSView, NSSplitViewDelegate {
    let splitView = NSSplitView()
    private let pane: SplitPane
    private let paneManager: PaneManager
    private let isHorizontal: Bool
    // Maps each child pane's UUID to its host view inside the split.
    private var paneViews: [UUID: StablePaneHostView] = [:]

    init(pane: SplitPane, paneManager: PaneManager, isHorizontal: Bool) {
        self.pane = pane
        self.paneManager = paneManager
        self.isHorizontal = isHorizontal
        super.init(frame: .zero)

        splitView.isVertical = isHorizontal   // vertical dividers = left/right layout
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.autoresizingMask = [.width, .height]
        addSubview(splitView)

        syncChildren()

        // Set autosave name after initial sync so restoreState() fires with
        // the correct number of subviews already in place.
        splitView.autosaveName = NSSplitView.AutosaveName(pane.id.uuidString)

        observeChildren()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Child synchronisation

    func syncChildren() {
        guard let children = pane.children else { return }

        // Add views for children that don't have one yet.
        for (idx, child) in children.enumerated() {
            guard paneViews[child.id] == nil else { continue }
            let view = makeHostView(for: child)
            paneViews[child.id] = view
            // Insert at the correct position in the split.
            if idx < splitView.subviews.count {
                splitView.addSubview(view, positioned: .below, relativeTo: splitView.subviews[idx])
            } else {
                splitView.addSubview(view)
            }
            // addSubview triggers resizeSubviewsWithOldSize synchronously;
            // the delegate applies the pending initial width there.
        }

        // Remove views for children that no longer exist.
        let liveIDs = Set(children.map(\.id))
        for (id, view) in paneViews where !liveIDs.contains(id) {
            view.removeFromSuperview()
            paneViews.removeValue(forKey: id)
        }
    }

    private func makeHostView(for child: SplitPane) -> StablePaneHostView {
        let rootView = AnyView(
            SplitPaneView(pane: child, paneManager: paneManager)
                .environment(paneManager)
        )
        let view = StablePaneHostView(rootView: rootView)
        view.autoresizingMask = [.width, .height]
        return view
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        guard let children = pane.children, !splitView.subviews.isEmpty else { return }

        let totalSize  = isHorizontal ? splitView.bounds.width  : splitView.bounds.height
        let divSize    = splitView.dividerThickness
        let available  = totalSize - CGFloat(max(0, splitView.subviews.count - 1)) * divSize
        guard available > 0 else { return }

        // Find any child that is being newly opened (has a pending initial size).
        var newIdx: Int?
        var newSize: CGFloat?
        for (i, child) in children.prefix(splitView.subviews.count).enumerated() {
            if let pw = paneManager.pendingInitialWidths.removeValue(forKey: child.id) {
                newIdx  = i
                newSize = isHorizontal ? pw : (child.preferredHeight ?? pw)
                break
            }
        }

        if let idx = newIdx, let desired = newSize {
            // Give the new pane its preferred size; scale the others proportionally.
            let capped      = min(desired, available * 0.9)
            let otherAvail  = available - capped
            let existingSum = splitView.subviews.enumerated()
                .filter { $0.offset != idx }
                .reduce(0.0) { sum, pair in
                    isHorizontal ? sum + pair.element.frame.width
                                 : sum + pair.element.frame.height
                }

            var coord: CGFloat = 0
            for (i, sub) in splitView.subviews.enumerated() {
                let size: CGFloat
                if i == idx {
                    size = capped
                } else {
                    let frac = existingSum > 0
                        ? (isHorizontal ? sub.frame.width : sub.frame.height) / existingSum
                        : 1.0 / CGFloat(max(1, splitView.subviews.count - 1))
                    size = otherAvail * frac
                }
                if isHorizontal {
                    sub.frame = CGRect(x: coord, y: 0, width: size, height: splitView.bounds.height)
                    coord += size + divSize
                } else {
                    sub.frame = CGRect(x: 0, y: coord, width: splitView.bounds.width, height: size)
                    coord += size + divSize
                }
            }
        } else {
            // No new panes — use NSSplitView's default proportional resize,
            // which also restores autosaved divider positions.
            splitView.adjustSubviews()
        }
    }

    // MARK: - Observation

    private func observeChildren() {
        withObservationTracking {
            _ = pane.children?.map(\.id)  // track the child list
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.syncChildren()
                self?.observeChildren()
            }
        }
    }
}

// MARK: - Stable pane host

// Thin NSView shell around NSHostingView<AnyView>.  Sitting as a direct
// subview of NSSplitView ensures FocusTrackerView.findPaneRoot() stops here
// (its parent IS an NSSplitView), and the stable identity means NSSplitView
// never sees a subview swap when a leaf turns into a split node.
final class StablePaneHostView: NSView {
    let hostingView: NSHostingView<AnyView>

    init(rootView: AnyView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        addSubview(hostingView)
        hostingView.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Pane content

struct PaneContentView: View {
    var pane: SplitPane
    @Environment(PaneManager.self) private var paneManager

    var body: some View {
        Group {
            switch pane.paneType {
            case .aiAssistant:
                AIAssistantView(pane: pane)
            case .fitsViewer:
                FITSViewerView(pane: pane)
            case .archiveViewer:
                ArchiveViewerView(pane: pane)
            case .infoPanel:
                InfoPanelView(pane: pane)
            case .empty:
                Color.clear
            }
        }
        .frame(minWidth: 100, minHeight: 100)
        .background { PaneFocusTracker(paneID: pane.id, paneType: pane.paneType) }
        .overlay(alignment: .topLeading) {
            if pane.paneType != .empty && paneManager.focusedPaneID == pane.id {
                PaneFocusCorner()
            }
        }
    }
}

/// Header-bar button that closes the pane showing the given type.
struct PaneCloseButton: View {
    let paneType: PaneType
    @Environment(PaneManager.self) private var paneManager

    var body: some View {
        Button { paneManager.closePane(ofType: paneType) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .help("Close pane")
    }
}

private struct PaneFocusCorner: View {
    var body: some View {
        PaneFocusTriangle()
            .fill(Color.accentColor)
            .frame(width: 16, height: 16)
            .allowsHitTesting(false)
    }
}

private struct PaneFocusTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Focus tracking

// Observes NSWindow.firstResponder via KVO. When first responder becomes a
// descendant of this pane's NSHostingView, marks the pane as focused.
private struct PaneFocusTracker: NSViewRepresentable {
    let paneID: UUID
    let paneType: PaneType
    @Environment(PaneManager.self) var paneManager

    func makeNSView(context: Context) -> FocusTrackerView {
        FocusTrackerView(paneID: paneID, paneType: paneType, paneManager: paneManager)
    }

    func updateNSView(_ nsView: FocusTrackerView, context: Context) {
        nsView.paneManager = paneManager
    }
}

final class FocusTrackerView: NSView {
    let paneID: UUID
    let paneType: PaneType
    var paneManager: PaneManager
    private var observation: NSKeyValueObservation?
    private var eventMonitor: Any?
    private var paneRoot: NSView?

    init(paneID: UUID, paneType: PaneType, paneManager: PaneManager) {
        self.paneID = paneID
        self.paneType = paneType
        self.paneManager = paneManager
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        // deinit is not @MainActor-isolated but both NSEvent.removeMonitor and
        // paneFrameProviders mutations must happen on the main thread.
        let monitor = eventMonitor
        let key = ObjectIdentifier(self)
        let manager = paneManager
        DispatchQueue.main.async {
            if let monitor { NSEvent.removeMonitor(monitor) }
            manager.paneFrameProviders.removeValue(forKey: key)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        paneRoot = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard let window else {
            paneManager.paneFrameProviders.removeValue(forKey: ObjectIdentifier(self))
            return
        }
        paneRoot = findPaneRoot()
        // Lets PaneManager query this pane's frame (window coordinates, y-up)
        // on demand — e.g. to draw the move-pane menu's layout icons.
        paneManager.paneFrameProviders[ObjectIdentifier(self)] = { [weak self] in
            guard let self, let root = self.paneRoot, root.window != nil else { return nil }
            return (self.paneID, root.convert(root.bounds, to: nil))
        }
        observation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            self?.handleFirstResponderChange(window: window)
        }
        // First-responder tracking alone misses panes whose content never
        // becomes first responder (e.g. the FITS viewer's MTKView) and
        // gesture-only interactions like trackpad zoom, so also watch for
        // interaction events landing inside this pane.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .magnify]
        ) { [weak self] event in
            self?.handleInteractionEvent(event)
            return event
        }
    }

    private func handleInteractionEvent(_ event: NSEvent) {
        guard paneType != .empty,
              let window, event.window === window,
              let root = paneRoot else { return }
        let locationInRoot = root.convert(event.locationInWindow, from: nil)
        guard root.bounds.contains(locationInRoot) else { return }
        scheduleFocusUpdate()
    }

    // Defer until the run loop returns to .default mode so the focus-indicator
    // re-render never runs inside an event-tracking loop mid-interaction
    // (see handleFirstResponderChange).
    private func scheduleFocusUpdate() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            guard let self, self.paneManager.focusedPaneID != self.paneID else { return }
            self.paneManager.focusedPaneID = self.paneID
        }
    }

    // Re-resolve paneRoot when this view is re-parented within the same window
    // (e.g. after a pane is split to add the FITS viewer).
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard window != nil else { return }
        paneRoot = findPaneRoot()
    }

    private func handleFirstResponderChange(window: NSWindow) {
        guard paneType != .empty,
              let root = paneRoot,
              let responder = window.firstResponder as? NSView,
              responder.isDescendant(of: root) else { return }
        // Defer until the run loop returns to .default mode. A plain
        // DispatchQueue.main.async block can run during NSTableView's
        // mouse-tracking loop (.eventTracking is in the common modes), so the
        // focus-indicator re-render would fire mid-click and SwiftUI's Table
        // would re-apply the stale selection binding, reverting the row the
        // user just clicked. Restricting to .default mode guarantees the
        // update runs only after the click (and its selection-binding write)
        // has fully completed.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            guard let self,
                  let root = self.paneRoot,
                  let responder = self.window?.firstResponder as? NSView,
                  responder.isDescendant(of: root),
                  self.paneManager.focusedPaneID != self.paneID else { return }
            self.paneManager.focusedPaneID = self.paneID
        }
    }

    // Walk up until we find a view whose direct parent is an NSSplitView —
    // that view is the boundary for this pane's subtree.
    private func findPaneRoot() -> NSView? {
        var current: NSView? = self
        while let view = current {
            if view.superview is NSSplitView { return view }
            current = view.superview
        }
        return nil
    }
}
