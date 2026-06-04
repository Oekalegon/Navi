//
//  FITSViewerView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AstrophotoKit
import Metal

struct FITSViewerView: View {
    var pane: SplitPane
    @Environment(PaneManager.self) private var paneManager

    @State private var fitsImage: FITSImage?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var frameType: String = ""
    @State private var frameLevel: String = "raw"

    @State private var zoom: Float = 1.0
    @State private var panOffset: SIMD2<Float> = SIMD2<Float>(0, 0)
    @State private var blackPoint: Float = 0.0
    @State private var whitePoint: Float = 1.0
    @State private var cursorPosition: SIMD2<Float>? = nil
    @State private var aspectRatio: SIMD2<Float> = SIMD2<Float>(1.0, 1.0)

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: paneManager.fitsURL) {
            await loadFITS()
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: frameTypeSymbolName(
                    type: frameType.isEmpty ? "light" : frameType,
                    level: frameLevel))
                .foregroundStyle(frameType.isEmpty || frameType.lowercased() == "light" ? .primary : .secondary)
                .font(.system(size: 14))
            Text(paneManager.fitsURL?.lastPathComponent ?? "FITS Viewer")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if fitsImage != nil {
                Button {
                    zoom = 1.0
                    panOffset = SIMD2<Float>(0, 0)
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Reset zoom and pan")

                Text(String(format: "%.0f%%", zoom * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var contentArea: some View {
        if paneManager.fitsURL == nil {
            emptyState("Open a FITS file to view it here")
        } else if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading \(paneManager.fitsURL?.lastPathComponent ?? "file")…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Could not load FITS file")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if let image = fitsImage {
            HSplitView {
                FITSImageView(
                    fitsImage: image,
                    zoom: $zoom,
                    panOffset: $panOffset,
                    blackPoint: $blackPoint,
                    whitePoint: $whitePoint,
                    cursorPosition: $cursorPosition,
                    aspectRatio: $aspectRatio
                )
                .frame(minWidth: 200)

                FITSInfoPanelView(
                    fitsImage: image,
                    blackPoint: $blackPoint,
                    whitePoint: $whitePoint,
                    cursorPosition: cursorPosition,
                    aspectRatio: aspectRatio,
                    zoom: $zoom,
                    panOffset: $panOffset
                )
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            }
        } else {
            emptyState("Open a FITS file to view it here")
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadFITS() async {
        guard let url = paneManager.fitsURL else { return }
        isLoading = true; loadError = nil; fitsImage = nil
        frameType = ""; frameLevel = "raw"

        // Look up frame metadata from the archive for the correct header icon.
        if let info = await ArchiveManager.shared.frameTypeInfo(filePath: url.path) {
            frameType = info.type
            frameLevel = info.level
        }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let file = try FITSFile(path: url.path)
                return try file.readFITSImage()
            }.value
            fitsImage = loaded
            blackPoint = loaded.originalMinValue
            whitePoint = loaded.originalMaxValue
            zoom = 1.0
            panOffset = SIMD2<Float>(0, 0)
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}
