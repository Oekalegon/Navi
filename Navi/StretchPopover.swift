//
//  StretchPopover.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AstrophotoKit

func applyStretch(_ sliderValue: Float, min: Float, max: Float, stretch: StretchSettings) -> Float {
    let range = max - min
    guard range > 0 else { return sliderValue }
    return min + stretch.effective(sliderNorm: (sliderValue - min) / range) * range
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
        applyStretch(sliderValue, min: originalMin, max: originalMax, stretch: stretchSettings)
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
