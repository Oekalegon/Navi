//
//  CameraPanelView.swift
//  Navi
//
//  Mockup — camera / filter wheel control UI (NOT wired to INDIMCPKit yet).
//  Layout loosely inspired by KStars/Ekos's INDI control panel.
//
//  Controls here map to what INDIMCPKit actually exposes:
//  Camera.captureFrame(exposureSeconds:frameType:binningX:binningY:gain:offset:...),
//  Camera.coolCamera/coolerOn/coolerOff/isCoolerOn, and
//  FilterWheel.selectFilter(_:) — filter names are a rig's dynamic slot
//  list, not a fixed enum, so the picker below is populated from sample
//  slot names rather than hardcoded filter cases.
//

import SwiftUI

/// Mirrors INDIMCPKit's `FrameType` enum (`Light`/`Dark`/`Flat`/`Bias`).
enum MockFrameType: String, CaseIterable, Identifiable {
    case light = "Light", dark = "Dark", flat = "Flat", bias = "Bias"
    var id: String { rawValue }
}

@Observable
final class MockCameraState {
    var isConnected = true
    var deviceState: MockDeviceState = .ok

    var frameType: MockFrameType = .light
    var exposureSeconds: Double = 30
    var binningX: Int = 1
    var binningY: Int = 1
    var gain: Double = 100
    var offset: Double = 10

    var isCapturing = false
    var captureProgress: Double = 0.0

    // Dynamic slot list, as reconciled from a rig's FilterWheel component.
    var filterSlots: [String] = ["L", "R", "G", "B", "Ha", "OIII", "SII"]
    var currentFilterName: String = "Ha"

    var isCoolerOn = true
    var targetTempC: Double = -10
    var currentTempC: Double = -9.4
    var coolerPower: Double = 0.68
}

struct CameraPanelView: View {
    @State private var camera = MockCameraState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                PanelCard(title: "Frame") {
                    Picker("Frame type", selection: $camera.frameType) {
                        ForEach(MockFrameType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exposure (s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0.0", value: $camera.exposureSeconds, format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Binning")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Stepper("\(camera.binningX)×\(camera.binningY)", value: $camera.binningX, in: 1...4)
                                    .onChange(of: camera.binningX) { _, newValue in camera.binningY = newValue }
                            }
                            .font(.caption)
                            .monospacedDigit()
                        }
                    }

                    LabeledSliderRow(label: "Gain", value: $camera.gain, range: 0...600, format: "%.0f")
                    LabeledSliderRow(label: "Offset", value: $camera.offset, range: 0...200, format: "%.0f")

                    HStack {
                        Button {
                            camera.isCapturing = true
                            camera.captureProgress = 0.4
                            camera.deviceState = .busy
                        } label: {
                            Label("Capture Frame", systemImage: "camera.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(camera.isCapturing)

                        if camera.isCapturing {
                            Button("Abort") {
                                camera.isCapturing = false
                                camera.captureProgress = 0
                                camera.deviceState = .ok
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if camera.isCapturing {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "Exposing… %.1fs / %.1fs",
                                        camera.captureProgress * camera.exposureSeconds, camera.exposureSeconds))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ProgressCapsuleBar(progress: camera.captureProgress)
                        }
                    }
                }

                PanelCard(title: "Filter Wheel") {
                    HStack {
                        Text("Current filter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(camera.currentFilterName)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }

                    Picker("Filter", selection: $camera.currentFilterName) {
                        ForEach(camera.filterSlots, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                PanelCard(title: "Cooling") {
                    TelemetryRow(label: "Sensor", value: String(format: "%.1f °C", camera.currentTempC))
                    LabeledSliderRow(label: "Target temp", value: $camera.targetTempC,
                                      range: -30...20, format: "%.0f", unit: " °C")

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Cooler power")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(camera.coolerPower * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        ProgressCapsuleBar(progress: camera.coolerPower, tint: .cyan)
                    }

                    HStack {
                        Button(camera.isCoolerOn ? "Cooler Off" : "Cooler On") {
                            camera.isCoolerOn.toggle()
                            camera.coolerPower = camera.isCoolerOn ? 0.68 : 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Text(camera.isCoolerOn ? "Cooling" : "Idle")
                            .font(.caption)
                            .foregroundStyle(camera.isCoolerOn ? .cyan : .secondary)
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Label("Camera", systemImage: "camera.aperture")
                .font(.headline)
            Spacer()
            ConnectionBadge(isConnected: camera.isConnected)
            DeviceStateBadge(state: camera.deviceState)
        }
    }
}

#Preview {
    CameraPanelView()
        .frame(width: 340, height: 720)
}
