//
//  MountPanelView.swift
//  Navi
//
//  Mockup — telescope mount control UI (NOT wired to INDIMCPKit yet).
//  Layout loosely inspired by KStars/Ekos's INDI control panel.
//
//  Controls here map to what INDIMCPKit's `Mount` handle actually exposes:
//  park(), unpark(), slew(ra:dec:), trackOff(), setTrackMode(_:),
//  setCustomTrackingRate(raRateArcsecPerSec:decRateArcsecPerSec:).
//  There is no discrete N/S/E/W nudge, slew-rate, abort, or pier-side control
//  in the kit today, so this mockup uses coordinate-entry slewing rather than
//  an Ekos-style direction pad.
//

import SwiftUI

/// Raw INDI track-mode switch elements, as accepted by `Mount.setTrackMode(_:)`.
enum MockTrackMode: String, CaseIterable, Identifiable {
    case sidereal = "TRACK_SIDEREAL"
    case solar = "TRACK_SOLAR"
    case lunar = "TRACK_LUNAR"
    case custom = "TRACK_CUSTOM"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sidereal: "Sidereal"
        case .solar: "Solar"
        case .lunar: "Lunar"
        case .custom: "Custom"
        }
    }
}

@Observable
final class MockMountState {
    var isConnected = true
    var deviceState: MockDeviceState = .ok

    // Mirrors the EQUATORIAL_EOD_COORD property vector.
    var currentRAHours: Double = 5.5877
    var currentDecDegrees: Double = -5.3897

    var targetRAHours: Double = 5.5877
    var targetDecDegrees: Double = -5.3897

    var isParked = false
    var isTracking = true
    var trackMode: MockTrackMode = .sidereal
    var customRARateArcsecPerSec: Double = 15.0
    var customDecRateArcsecPerSec: Double = 0.0

    var isSlewing = false
    var slewProgress: Double = 0.0
}

struct MountPanelView: View {
    @State private var mount = MockMountState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                PanelCard(title: "Position") {
                    VStack(alignment: .leading, spacing: 6) {
                        TelemetryRow(label: "RA", value: Self.formatHours(mount.currentRAHours))
                        TelemetryRow(label: "Dec", value: Self.formatDegrees(mount.currentDecDegrees))
                        TelemetryRow(label: "Tracking", value: mount.isTracking ? "On (\(mount.trackMode.label))" : "Off",
                                     valueColor: mount.isTracking ? .green : .secondary)
                    }

                    if mount.isSlewing {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Slewing…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ProgressCapsuleBar(progress: mount.slewProgress)
                        }
                        .padding(.top, 2)
                    }
                }

                PanelCard(title: "Slew") {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RA (hours)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0.0", value: $mount.targetRAHours, format: .number.precision(.fractionLength(4)))
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dec (degrees)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0.0", value: $mount.targetDecDegrees, format: .number.precision(.fractionLength(4)))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack {
                        Button {
                            mount.isSlewing = true
                            mount.slewProgress = 0.35
                            mount.deviceState = .busy
                        } label: {
                            Label("Slew", systemImage: "location.north.line.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(mount.isParked || mount.isSlewing)

                        if mount.isSlewing {
                            Button("Stop") {
                                mount.isSlewing = false
                                mount.slewProgress = 0
                                mount.deviceState = .ok
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                PanelCard(title: "Tracking") {
                    Toggle("Tracking enabled", isOn: $mount.isTracking)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(mount.isParked)

                    Picker("Track mode", selection: $mount.trackMode) {
                        ForEach(MockTrackMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(!mount.isTracking || mount.isParked)
                    .frame(maxWidth: 180)

                    if mount.trackMode == .custom {
                        LabeledSliderRow(label: "RA rate", value: $mount.customRARateArcsecPerSec,
                                          range: -60...60, format: "%.1f", unit: " arcsec/s", step: 0.5)
                        LabeledSliderRow(label: "Dec rate", value: $mount.customDecRateArcsecPerSec,
                                          range: -60...60, format: "%.1f", unit: " arcsec/s", step: 0.5)
                    }
                }

                PanelCard(title: "Park") {
                    HStack {
                        Button {
                            mount.isParked.toggle()
                            if mount.isParked {
                                mount.isTracking = false
                                mount.isSlewing = false
                                mount.slewProgress = 0
                            }
                        } label: {
                            Label(mount.isParked ? "Unpark" : "Park",
                                  systemImage: mount.isParked ? "lock.open.fill" : "lock.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Text(mount.isParked ? "Parked" : "Unparked")
                            .font(.caption)
                            .foregroundStyle(mount.isParked ? .orange : .secondary)
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Label("Mount", systemImage: "scope")
                .font(.headline)
            Spacer()
            ConnectionBadge(isConnected: mount.isConnected)
            DeviceStateBadge(state: mount.deviceState)
        }
    }

    private static func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let mFull = (hours - Double(h)) * 60
        let m = Int(mFull)
        let s = (mFull - Double(m)) * 60
        return String(format: "%02dh %02dm %04.1fs", h, m, s)
    }

    private static func formatDegrees(_ degrees: Double) -> String {
        let sign = degrees < 0 ? "-" : "+"
        let d = abs(degrees)
        let deg = Int(d)
        let mFull = (d - Double(deg)) * 60
        let m = Int(mFull)
        let s = (mFull - Double(m)) * 60
        return String(format: "%@%02d° %02d' %04.1f\"", sign, deg, m, s)
    }
}

#Preview {
    MountPanelView()
        .frame(width: 340, height: 640)
}
