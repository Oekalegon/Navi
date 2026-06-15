//
//  ArchiveStatusBar.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import SwiftUI
import AppKit

// Status bar at the bottom of the archive pane: row count on the left;
// archive frame count, disk usage legend and capacity bar on the right
// (NAVI-25).
struct ArchiveStatusBar: View {
    let rowCount: Int
    let totalRowCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(rowCount == totalRowCount
                 ? "\(rowCount) \(rowCount == 1 ? "row" : "rows")"
                 : "\(rowCount) of \(totalRowCount) rows")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let usage = ArchiveManager.shared.diskUsage {
                Text("\(usage.frameCount.formatted()) \(usage.frameCount == 1 ? "frame" : "frames") in archive")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if usage.totalBytes > 0 {
                    legendItem(color: DiskUsageBar.archiveColor,
                               label: "Archive \(Self.formatted(usage.archiveBytes))")
                    DiskUsageBar(usage: usage)
                        .frame(width: 140, height: 7)
                    legendItem(color: DiskUsageBar.otherColor,
                               label: "Other \(Self.formatted(usage.otherBytes))")
                    legendItem(color: DiskUsageBar.freeColor,
                               label: "Free \(Self.formatted(usage.availableBytes))")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// Horizontal capacity bar for the volume holding the archive, split into
// archive / other / free segments.
private struct DiskUsageBar: View {
    let usage: ArchiveManager.DiskUsage

    static let archiveColor = Color.accentColor
    static let otherColor = Color(nsColor: .systemGray)
    static let freeColor = Color(nsColor: .quaternaryLabelColor)

    var body: some View {
        GeometryReader { geo in
            let total = Double(usage.totalBytes)
            // Keep a sliver of archive visible even when it is a tiny
            // fraction of the volume: it is the segment the user cares about.
            let archiveWidth = usage.archiveBytes > 0
                ? max(2, geo.size.width * Double(usage.archiveBytes) / total)
                : 0
            let otherWidth = (geo.size.width - archiveWidth) * Double(usage.otherBytes) / total
            HStack(spacing: 0) {
                Rectangle().fill(Self.archiveColor).frame(width: archiveWidth)
                Rectangle().fill(Self.otherColor).frame(width: otherWidth)
                Rectangle().fill(Self.freeColor)
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .help("Archive \(ArchiveStatusBar.formatted(usage.archiveBytes)) – "
              + "Other \(ArchiveStatusBar.formatted(usage.otherBytes)) – "
              + "Free \(ArchiveStatusBar.formatted(usage.availableBytes)) "
              + "of \(ArchiveStatusBar.formatted(usage.totalBytes))")
    }
}
