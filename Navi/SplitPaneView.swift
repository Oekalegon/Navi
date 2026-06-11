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
        if let children = pane.children, let direction = pane.direction {
            if direction == .horizontal {
                HSplitView {
                    ForEach(children) { child in
                        StableSplitPaneHost(pane: child, paneManager: paneManager)
                            .frame(idealWidth: child.preferredWidth, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VSplitView {
                    ForEach(children) { child in
                        StableSplitPaneHost(pane: child, paneManager: paneManager)
                            .frame(maxWidth: .infinity, idealHeight: child.preferredHeight, maxHeight: .infinity)
                    }
                }
            }
        } else {
            PaneContentView(pane: pane)
        }
    }
}

// Wraps SplitPaneView in a stable NSHostingView so the parent NSSplitView
// never sees a subview add/remove when pane content changes type
// (e.g. PaneContentView → VSplitView). NSSplitView only re-runs adjustSubviews
// on structural subview changes, so the user-set divider position is preserved.
struct StableSplitPaneHost: NSViewRepresentable {
    let pane: SplitPane
    let paneManager: PaneManager

    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        let view = NSHostingView(rootView: content)
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSHostingView<AnyView>, context: Context) {
        // SplitPane and PaneManager are both @Observable, so every view inside
        // the hosting view re-renders automatically when their properties change.
        // Re-setting rootView here would break AnyView type-identity tracking,
        // causing SwiftUI to lose @State (e.g. table selectionID) on every update.
    }

    private var content: AnyView {
        AnyView(
            SplitPaneView(pane: pane, paneManager: paneManager)
                .environment(paneManager)
        )
    }
}

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
    private var paneRoot: NSView?

    init(paneID: UUID, paneType: PaneType, paneManager: PaneManager) {
        self.paneID = paneID
        self.paneType = paneType
        self.paneManager = paneManager
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        paneRoot = nil
        guard let window else { return }
        paneRoot = findPaneRoot()
        observation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            self?.handleFirstResponderChange(window: window)
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
