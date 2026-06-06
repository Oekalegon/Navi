//
//  FITSViewerView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AstrophotoKit
import AstrophotoArchiveKit
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
    @State private var originalMin: Float = 0.0
    @State private var originalMax: Float = 1.0
    @State private var stretchSettings: StretchSettings = .identity
    @State private var currentFrameID: UUID? = nil
    @State private var showingStretch = false
    @State private var saveTask: Task<Void, Never>? = nil
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
        .onChange(of: stretchSettings) { _, _ in scheduleSave() }
        .onChange(of: blackPoint)     { _, _ in scheduleSave() }
        .onChange(of: whitePoint)     { _, _ in scheduleSave() }
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
                    showingStretch.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Adjust stretch")
                .popover(isPresented: $showingStretch, arrowEdge: .bottom) {
                    StretchPopover(
                        fitsImage: fitsImage,
                        blackPoint: $blackPoint,
                        whitePoint: $whitePoint,
                        originalMin: originalMin,
                        originalMax: originalMax,
                        stretchSettings: $stretchSettings
                    )
                }

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
            FITSImageView(
                fitsImage: image,
                zoom: $zoom,
                panOffset: $panOffset,
                blackPoint: .init(
                    get: { effectivePoint(blackPoint, min: originalMin, max: originalMax) },
                    set: { _ in }
                ),
                whitePoint: .init(
                    get: { effectivePoint(whitePoint, min: originalMin, max: originalMax) },
                    set: { _ in }
                ),
                cursorPosition: $cursorPosition,
                aspectRatio: $aspectRatio
            )
        } else {
            emptyState("Open a FITS file to view it here")
        }
    }

    private func effectivePoint(_ sliderValue: Float, min: Float, max: Float) -> Float {
        let range = max - min
        guard range > 0 else { return sliderValue }
        let norm = (sliderValue - min) / range
        return min + stretchSettings.effective(sliderNorm: norm) * range
    }

    private func scheduleSave() {
        guard !isLoading, let frameID = currentFrameID else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let range = originalMax - originalMin
            let blackNorm = range > 0 ? (blackPoint - originalMin) / range : 0
            let whiteNorm = range > 0 ? (whitePoint - originalMin) / range : 1
            try? await ArchiveManager.shared.updateStretchSettings(
                stretchSettings.isIdentity ? nil : stretchSettings,
                sliderBlackNorm: blackNorm,
                sliderWhiteNorm: whiteNorm,
                id: frameID
            )
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
        saveTask?.cancel()
        saveTask = nil
        isLoading = true; loadError = nil; fitsImage = nil
        frameType = ""; frameLevel = "raw"
        currentFrameID = nil; stretchSettings = .identity

        let frame = await ArchiveManager.shared.archivedFrame(filePath: url.path)
        if let frame {
            frameType = frame.frameType
            frameLevel = frame.processingLevel.rawValue
            stretchSettings = frame.stretchSettings ?? .identity
            currentFrameID = frame.id
        }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let file = try FITSFile(path: url.path)
                return try file.readFITSImage()
            }.value
            fitsImage = loaded
            originalMin = loaded.originalMinValue
            originalMax = loaded.originalMaxValue
            let range = originalMax - originalMin
            blackPoint = originalMin + (frame?.sliderBlackNorm ?? 0.0) * range
            whitePoint = originalMin + (frame?.sliderWhiteNorm ?? 1.0) * range
            zoom = 1.0
            panOffset = SIMD2<Float>(0, 0)
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}

struct StretchPopover: View {
    let fitsImage: FITSImage?
    @Binding var blackPoint: Float
    @Binding var whitePoint: Float
    let originalMin: Float
    let originalMax: Float
    @Binding var stretchSettings: StretchSettings

    private var effectiveBP: Float { effective(blackPoint) }
    private var effectiveWP: Float { effective(whitePoint) }

    private func effective(_ sliderValue: Float) -> Float {
        let range = originalMax - originalMin
        guard range > 0 else { return sliderValue }
        let norm = (sliderValue - originalMin) / range
        return originalMin + stretchSettings.effective(sliderNorm: norm) * range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stretch")
                .font(.headline)

            FITSHistogramChart(
                fitsImage: fitsImage,
                showNormalized: true,
                blackPoint: effectiveBP,
                whitePoint: effectiveWP,
                useLogScale: false
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Black point")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.4f", effectiveBP))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $blackPoint, in: originalMin...max(originalMin, whitePoint - 0.0001))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("White point")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.4f", effectiveWP))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $whitePoint, in: min(blackPoint + 0.0001, originalMax)...originalMax)
            }

            HStack {
                Button("Reset") {
                    stretchSettings = .identity
                    blackPoint = originalMin
                    whitePoint = originalMax
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Normalize") {
                    let range = originalMax - originalMin
                    guard range > 0 else { return }
                    let blackNorm = (blackPoint - originalMin) / range
                    let whiteNorm = (whitePoint - originalMin) / range
                    stretchSettings = stretchSettings.normalized(
                        sliderBlackNorm: blackNorm,
                        sliderWhiteNorm: whiteNorm
                    )
                    blackPoint = originalMin
                    whitePoint = originalMax
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Bake current slider positions into the stretch and reset sliders to full range")
            }
        }
        .padding()
        .frame(width: 280)
    }
}
