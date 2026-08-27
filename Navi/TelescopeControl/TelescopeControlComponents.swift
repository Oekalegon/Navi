//
//  TelescopeControlComponents.swift
//  Navi
//
//  Mockup — telescope control UI (NOT wired to INDIMCPKit yet).
//  Shared building blocks reused by MountPanelView and CameraPanelView.
//

import SwiftUI

// MARK: - Device state

/// Mirrors INDIMCPKit's `PropertyState` (Idle/Ok/Busy/Alert) so the mockup's
/// vocabulary matches what the real client will eventually report.
enum MockDeviceState {
    case idle, ok, busy, alert

    var label: String {
        switch self {
        case .idle: "Idle"
        case .ok: "Ready"
        case .busy: "Busy"
        case .alert: "Alert"
        }
    }

    var color: Color {
        switch self {
        case .idle: Color(nsColor: .tertiaryLabelColor)
        case .ok: .green
        case .busy: .orange
        case .alert: .red
        }
    }
}

/// Small rounded status chip, styled after `RejectToggleButton`'s badge look.
struct DeviceStateBadge: View {
    let state: MockDeviceState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
            Text(state.label)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(state.color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(state.color.opacity(0.4), lineWidth: 0.5))
    }
}

/// Connected/disconnected chip for a device row header.
struct ConnectionBadge: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isConnected ? "circle.fill" : "circle.slash")
                .font(.system(size: 7))
                .foregroundStyle(isConnected ? .green : .secondary)
            Text(isConnected ? "Connected" : "Disconnected")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Card / section layout

/// Card container matching the card pattern used in SettingsView/AIAssistantView:
/// padded VStack over `.controlBackgroundColor` with an 8pt corner radius.
struct PanelCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// Fixed-width label + value row, mirroring InfoPanelView's `InfoRow`.
struct TelemetryRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }
}

/// Label-left / monospaced-value-right slider row, styled after StretchPopover's
/// black point / white point sliders.
struct LabeledSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.0f"
    var unit: String = ""
    var step: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value) + unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

/// Segmented capsule progress bar, styled after ArchiveStatusBar's DiskUsageBar —
/// used for slew-in-progress / exposure-in-progress readouts.
struct ProgressCapsuleBar: View {
    let progress: Double // 0...1
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * min(max(progress, 0), 1)))
                Rectangle()
                    .fill(Color(nsColor: .quaternaryLabelColor))
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .frame(height: 6)
    }
}
