//
//  PaneLayout.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import Foundation
import CoreGraphics

// Pure geometry behind the move-pane menu (NAVI-9): a value snapshot of the
// split tree with normalized pane rectangles, and the enumeration of swap and
// insert candidates with the rectangles needed to draw the menu's layout icons.

struct PaneLayoutSnapshot {
    struct Node {
        let id: UUID
        let paneType: PaneType
        let direction: SplitDirection?
        let children: [Node]
        let rect: CGRect    // normalized 0…1, y pointing down

        var isLeaf: Bool { children.isEmpty }

        func find(_ id: UUID) -> Node? {
            if self.id == id { return self }
            return children.compactMap { $0.find(id) }.first
        }

        func findParent(of id: UUID) -> (parent: Node, index: Int)? {
            for (index, child) in children.enumerated() {
                if child.id == id { return (self, index) }
                if let result = child.findParent(of: id) { return result }
            }
            return nil
        }

        var leaves: [Node] {
            isLeaf ? [self] : children.flatMap(\.leaves)
        }

        // Post-order: leaves before the groups that contain them, so leaf
        // positions come first in the move menu and window edges last.
        var nodesPostOrder: [Node] {
            children.flatMap(\.nodesPostOrder) + [self]
        }
    }

    let root: Node

    var leafRects: [CGRect] { root.leaves.map(\.rect) }

    // `frames` holds the panes' live frames in window coordinates (y-up).
    // When a leaf's frame is unknown (not laid out yet), all rectangles fall
    // back to splitting each node's rectangle equally.
    init(root pane: SplitPane, frames: [UUID: CGRect]) {
        var leafFrames: [UUID: CGRect] = [:]
        var complete = true
        Self.forEachLeaf(of: pane) { leaf in
            if let frame = frames[leaf.id], frame.width > 0, frame.height > 0 {
                leafFrames[leaf.id] = frame
            } else {
                complete = false
            }
        }
        let union = leafFrames.values.reduce(CGRect.null) { $0.union($1) }
        if complete, union.width > 0, union.height > 0 {
            root = Self.build(pane) { id in
                let frame = leafFrames[id]!
                // Window coordinates are y-up; the snapshot is y-down.
                return CGRect(x: (frame.minX - union.minX) / union.width,
                              y: (union.maxY - frame.maxY) / union.height,
                              width: frame.width / union.width,
                              height: frame.height / union.height)
            }
        } else {
            root = Self.buildSynthetic(pane, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private static func forEachLeaf(of pane: SplitPane, _ body: (SplitPane) -> Void) {
        if let children = pane.children {
            children.forEach { forEachLeaf(of: $0, body) }
        } else {
            body(pane)
        }
    }

    private static func build(_ pane: SplitPane, leafRect: (UUID) -> CGRect) -> Node {
        guard let children = pane.children, let direction = pane.direction else {
            return Node(id: pane.id, paneType: pane.paneType, direction: nil,
                        children: [], rect: leafRect(pane.id))
        }
        let childNodes = children.map { build($0, leafRect: leafRect) }
        let rect = childNodes.map(\.rect).reduce(CGRect.null) { $0.union($1) }
        return Node(id: pane.id, paneType: pane.paneType, direction: direction,
                    children: childNodes, rect: rect)
    }

    private static func buildSynthetic(_ pane: SplitPane, rect: CGRect) -> Node {
        guard let children = pane.children, let direction = pane.direction else {
            return Node(id: pane.id, paneType: pane.paneType, direction: nil,
                        children: [], rect: rect)
        }
        let count = CGFloat(children.count)
        let childNodes = children.enumerated().map { index, child in
            let slice: CGRect
            switch direction {
            case .horizontal:
                let width = rect.width / count
                slice = CGRect(x: rect.minX + width * CGFloat(index), y: rect.minY,
                               width: width, height: rect.height)
            case .vertical:
                let height = rect.height / count
                slice = CGRect(x: rect.minX, y: rect.minY + height * CGFloat(index),
                               width: rect.width, height: height)
            }
            return buildSynthetic(child, rect: slice)
        }
        return Node(id: pane.id, paneType: pane.paneType, direction: direction,
                    children: childNodes, rect: rect)
    }
}

struct PaneMoveOption: Identifiable {
    enum Action: Equatable {
        case swap(targetID: UUID)
        case insert(targetID: UUID, direction: SplitDirection, before: Bool)
    }

    let id = UUID()
    let action: Action
    let title: String
    let leafRects: [CGRect]        // layout drawn in the icon: current for swaps,
                                   // the layout AFTER the move for inserts
    let sourceRect: CGRect?        // the pane's position before the move (swaps only)
    let destinationRect: CGRect    // normalized, y down — highlighted in the icon
}

struct PaneMoveOptions {
    let currentRect: CGRect    // the moving pane's own position, normalized
    let leafRects: [CGRect]    // every pane in the current layout, for dividers
    let swaps: [PaneMoveOption]
    let inserts: [PaneMoveOption]

    var isEmpty: Bool { swaps.isEmpty && inserts.isEmpty }
}

// Candidate destinations for moving `movingPane`:
// - swap with any other pane (layout unchanged, contents exchanged), and
// - insert positions: the pane is removed (its sibling absorbs the space) and
//   re-inserted by splitting any node of the remaining tree — leaves and
//   groups alike — on either side. Panes with a preferred width insert
//   horizontally, with a preferred height vertically, otherwise both ways.
// Swap icons show the current layout with source and destination; insert icons
// show the simulated layout AFTER the move, with only the new position marked.
// The candidate that would recreate the current position is skipped, as are
// candidates whose destination rectangle duplicates an earlier one.
func paneMoveOptions(for movingPane: SplitPane, root: SplitPane,
                     frames: [UUID: CGRect]) -> PaneMoveOptions? {
    let snapshot = PaneLayoutSnapshot(root: root, frames: frames)
    guard let moving = snapshot.root.find(movingPane.id), moving.isLeaf,
          let (parent, index) = snapshot.root.findParent(of: movingPane.id),
          let removedRoot = removingLeaf(moving.id, from: snapshot.root)
    else { return nil }
    let isBinaryParent = parent.children.count == 2
    // For binary splits the parent collapses into the sibling in removedRoot;
    // for N-ary splits the parent stays in removedRoot with one fewer child.
    let sibling: PaneLayoutSnapshot.Node? = isBinaryParent ? parent.children[1 - index] : nil
    let remainingRootID: UUID = (isBinaryParent && parent.id == snapshot.root.id)
        ? sibling!.id : snapshot.root.id

    let swaps = snapshot.root.leaves
        .filter { $0.id != moving.id }
        .map { leaf in
            PaneMoveOption(action: .swap(targetID: leaf.id),
                           title: "Swap with \(leaf.paneType.displayName)",
                           leafRects: snapshot.leafRects,
                           sourceRect: moving.rect,
                           destinationRect: leaf.rect)
        }

    var inserts: [PaneMoveOption] = []
    var seenRects: Set<String> = []
    for target in snapshot.root.nodesPostOrder {
        // The moving leaf is always an invalid insertion target.
        // For binary splits the parent also collapses and vanishes from removedRoot.
        guard target.id != moving.id else { continue }
        if isBinaryParent, target.id == parent.id { continue }
        for direction in insertDirections(for: movingPane) {
            for before in [true, false] {
                // Skip the insertion that recreates the current position.
                if isBinaryParent {
                    if target.id == sibling!.id, direction == parent.direction,
                       before == (index == 0) { continue }
                } else {
                    // N-ary: inserting before the next sibling or after the previous
                    // sibling (along parent's direction) recreates the current position.
                    if direction == parent.direction {
                        if index < parent.children.count - 1 {
                            if target.id == parent.children[index + 1].id, before { continue }
                        }
                        if index > 0 {
                            if target.id == parent.children[index - 1].id, !before { continue }
                        }
                    }
                }
                guard let preview = inserting(moving, at: target.id, direction: direction,
                                              before: before, in: removedRoot),
                      seenRects.insert(rectKey(preview.movedRect)).inserted else { continue }
                inserts.append(PaneMoveOption(
                    action: .insert(targetID: target.id, direction: direction, before: before),
                    title: insertTitle(direction: direction, before: before,
                                       target: target, remainingRootID: remainingRootID),
                    leafRects: preview.root.leaves.map(\.rect),
                    sourceRect: nil,
                    destinationRect: preview.movedRect))
            }
        }
    }

    return PaneMoveOptions(currentRect: moving.rect,
                           leafRects: snapshot.leafRects,
                           swaps: swaps, inserts: inserts)
}

private func insertDirections(for pane: SplitPane) -> [SplitDirection] {
    if pane.preferredWidth != nil, pane.preferredHeight == nil { return [.horizontal] }
    if pane.preferredHeight != nil, pane.preferredWidth == nil { return [.vertical] }
    return [.horizontal, .vertical]
}

private func half(of rect: CGRect, direction: SplitDirection, before: Bool) -> CGRect {
    switch direction {
    case .horizontal:
        CGRect(x: before ? rect.minX : rect.midX, y: rect.minY,
               width: rect.width / 2, height: rect.height)
    case .vertical:
        CGRect(x: rect.minX, y: before ? rect.minY : rect.midY,
               width: rect.width, height: rect.height / 2)
    }
}

private func insertTitle(direction: SplitDirection, before: Bool,
                         target: PaneLayoutSnapshot.Node, remainingRootID: UUID) -> String {
    let side = switch direction {
    case .horizontal: before ? "Left of" : "Right of"
    case .vertical: before ? "Above" : "Below"
    }
    let name = if target.isLeaf {
        target.paneType.displayName
    } else {
        target.id == remainingRootID ? "Window" : "Group"
    }
    return "\(side) \(name)"
}

// The remaining layout after removing a leaf, mirroring PaneManager.removeLeaf.
// Binary split: sibling expands to fill the parent's rectangle.
// N-ary split: remaining siblings redistribute their space proportionally.
private func removingLeaf(_ leafID: UUID,
                          from root: PaneLayoutSnapshot.Node) -> PaneLayoutSnapshot.Node? {
    guard let (parent, index) = root.findParent(of: leafID) else { return nil }
    if parent.children.count == 2 {
        let sibling = parent.children[1 - index]
        let expanded = remap(sibling, from: sibling.rect, to: parent.rect)
        return replacing(parent.id, with: expanded, in: root)
    }
    // N-ary (3+): remove the leaf and expand remaining siblings proportionally.
    guard let direction = parent.direction else { return nil }
    let remaining = parent.children.filter { $0.id != leafID }
    let newChildren = redistributeRects(remaining, into: parent.rect, direction: direction)
    let newParent = PaneLayoutSnapshot.Node(id: parent.id, paneType: parent.paneType,
                                            direction: direction, children: newChildren,
                                            rect: parent.rect)
    return replacing(parent.id, with: newParent, in: root)
}

// Scale a sequence of same-direction nodes to fill `parentRect`, preserving their
// relative sizes along the split axis.
private func redistributeRects(_ nodes: [PaneLayoutSnapshot.Node], into parentRect: CGRect,
                                direction: SplitDirection) -> [PaneLayoutSnapshot.Node] {
    switch direction {
    case .horizontal:
        let total = nodes.reduce(0.0) { $0 + $1.rect.width }
        guard total > 0 else { return nodes }
        let scale = parentRect.width / total
        var x = parentRect.minX
        return nodes.map { node in
            let w = node.rect.width * scale
            let newRect = CGRect(x: x, y: parentRect.minY, width: w, height: parentRect.height)
            x += w
            return remap(node, from: node.rect, to: newRect)
        }
    case .vertical:
        let total = nodes.reduce(0.0) { $0 + $1.rect.height }
        guard total > 0 else { return nodes }
        let scale = parentRect.height / total
        var y = parentRect.minY
        return nodes.map { node in
            let h = node.rect.height * scale
            let newRect = CGRect(x: parentRect.minX, y: y, width: parentRect.width, height: h)
            y += h
            return remap(node, from: node.rect, to: newRect)
        }
    }
}

// The layout after splitting `targetID` in half and placing `moving` on the
// chosen side; the target subtree is compressed into the other half.
private func inserting(_ moving: PaneLayoutSnapshot.Node, at targetID: UUID,
                       direction: SplitDirection, before: Bool,
                       in root: PaneLayoutSnapshot.Node)
    -> (root: PaneLayoutSnapshot.Node, movedRect: CGRect)? {
    guard let target = root.find(targetID) else { return nil }
    let movedRect = half(of: target.rect, direction: direction, before: before)
    let rest = remap(target, from: target.rect,
                     to: half(of: target.rect, direction: direction, before: !before))
    let moved = PaneLayoutSnapshot.Node(id: moving.id, paneType: moving.paneType,
                                        direction: nil, children: [], rect: movedRect)
    let group = PaneLayoutSnapshot.Node(id: UUID(), paneType: .empty, direction: direction,
                                        children: before ? [moved, rest] : [rest, moved],
                                        rect: target.rect)
    return (replacing(targetID, with: group, in: root), movedRect)
}

private func replacing(_ nodeID: UUID, with newNode: PaneLayoutSnapshot.Node,
                       in root: PaneLayoutSnapshot.Node) -> PaneLayoutSnapshot.Node {
    if root.id == nodeID { return newNode }
    return PaneLayoutSnapshot.Node(
        id: root.id, paneType: root.paneType, direction: root.direction,
        children: root.children.map { replacing(nodeID, with: newNode, in: $0) },
        rect: root.rect)
}

// Affine-remap a subtree's rectangles from the `old` region into `new`.
private func remap(_ node: PaneLayoutSnapshot.Node,
                   from old: CGRect, to new: CGRect) -> PaneLayoutSnapshot.Node {
    let sx = new.width / old.width
    let sy = new.height / old.height
    let rect = CGRect(x: new.minX + (node.rect.minX - old.minX) * sx,
                      y: new.minY + (node.rect.minY - old.minY) * sy,
                      width: node.rect.width * sx,
                      height: node.rect.height * sy)
    return PaneLayoutSnapshot.Node(
        id: node.id, paneType: node.paneType, direction: node.direction,
        children: node.children.map { remap($0, from: old, to: new) },
        rect: rect)
}

private func rectKey(_ rect: CGRect) -> String {
    let r = { (v: CGFloat) in (v * 1000).rounded() / 1000 }
    return "\(r(rect.minX)),\(r(rect.minY)),\(r(rect.width)),\(r(rect.height))"
}
