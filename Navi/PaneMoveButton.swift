//
//  PaneMoveButton.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import SwiftUI
import AppKit

/// Header-bar button that opens the move-pane menu (NAVI-9). Swap items show a
/// miniature of the current layout with the destination in the primary color
/// and the pane's current position in the secondary color; Move To items show
/// the layout as it will look AFTER the move (the pane removed, its sibling
/// absorbing the space, the chosen pane or group split) with only the new
/// position marked.
struct PaneMoveButton: View {
    let pane: SplitPane
    @Environment(PaneManager.self) private var paneManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !paneManager.rootPane.isLeaf {
            Menu {
                menuContent
            } label: {
                Image(systemName: "inset.filled.toptrailing.rectangle")
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Move pane")
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if let options = paneMoveOptions(for: pane, root: paneManager.rootPane,
                                         frames: paneManager.currentPaneFrames()),
           !options.isEmpty {
            if !options.swaps.isEmpty {
                Section("Swap With") {
                    ForEach(options.swaps) { option in
                        optionButton(option, in: options)
                    }
                }
            }
            if !options.inserts.isEmpty {
                Section("Move To") {
                    ForEach(options.inserts) { option in
                        optionButton(option, in: options)
                    }
                }
            }
        }
        Section {
            Button {
                moveToNewWindow()
            } label: {
                Label {
                    Text("New Window")
                } icon: {
                    // A window containing only this pane: full-rect destination.
                    if let image = layoutIconImage(leafRects: [], sourceRect: nil,
                                                   destinationRect: CGRect(x: 0, y: 0,
                                                                           width: 1, height: 1)) {
                        Image(nsImage: image)
                    }
                }
            }
        }
    }

    private func moveToNewWindow() {
        guard let manager = paneManager.detachPaneManager(for: pane) else { return }
        let token = WindowRegistry.shared.stage(manager)
        openWindow(value: WindowTabGroup.single(tabID: token.id))
    }

    private func optionButton(_ option: PaneMoveOption, in options: PaneMoveOptions) -> some View {
        Button {
            perform(option)
        } label: {
            Label {
                Text(option.title)
            } icon: {
                if let image = layoutIconImage(leafRects: option.leafRects,
                                               sourceRect: option.sourceRect,
                                               destinationRect: option.destinationRect) {
                    Image(nsImage: image)
                }
            }
        }
    }

    private func perform(_ option: PaneMoveOption) {
        switch option.action {
        case .swap(let targetID):
            guard let target = paneManager.findPane(id: targetID, in: paneManager.rootPane)
            else { return }
            paneManager.swapPanes(pane, target)
        case .insert(let targetID, let direction, let before):
            paneManager.movePane(pane, toTarget: targetID, direction: direction, before: before)
        }
    }

    private func layoutIconImage(leafRects: [CGRect], sourceRect: CGRect?,
                                 destinationRect: CGRect) -> NSImage? {
        let icon = PaneLayoutIcon(leafRects: leafRects, sourceRect: sourceRect,
                                  destinationRect: destinationRect)
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        image.size = NSSize(width: PaneLayoutIcon.size.width,
                            height: PaneLayoutIcon.size.height)
        // Template: the menu tints the icon with its label color, so full
        // opacity reads as the primary color and half opacity as secondary
        // on both light and dark menus.
        image.isTemplate = true
        return image
    }
}

/// Stylized miniature of a window layout: every pane outlined with dividers at
/// their real positions by scale, the destination filled at full strength
/// (primary) and, when shown, the moving pane's current position filled
/// half-strength (secondary). Drawn in black and rendered as a template image.
struct PaneLayoutIcon: View {
    static let size = CGSize(width: 24, height: 15)

    let leafRects: [CGRect]        // normalized 0…1, y down
    let sourceRect: CGRect?
    let destinationRect: CGRect

    var body: some View {
        Canvas { context, size in
            let scale = CGAffineTransform(scaleX: size.width, y: size.height)
            let outline = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            context.fill(Path(roundedRect: outline, cornerRadius: 4),
                         with: .color(.black.opacity(0.08)))
            if let sourceRect {
                context.fill(Path(sourceRect.applying(scale).insetBy(dx: 1, dy: 1)),
                             with: .color(.black.opacity(0.5)))
            }
            context.fill(Path(destinationRect.applying(scale).insetBy(dx: 1, dy: 1)),
                         with: .color(.black))
            for rect in leafRects {
                context.stroke(Path(rect.applying(scale)),
                               with: .color(.black.opacity(0.4)), lineWidth: 1)
            }
            context.stroke(Path(roundedRect: outline, cornerRadius: 4),
                           with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}
