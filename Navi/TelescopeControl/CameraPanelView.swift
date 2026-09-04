//
//  CameraPanelView.swift
//  Navi
//
//  Camera / filter wheel control (NAVI-52), wired to INDIMCPKit via TelescopeSessionManager (the
//  single choke point for camera hardware commands, I-9). Layout loosely inspired by KStars/
//  Ekos's INDI control panel.
//
//  Standing/live state (temperature, cooler, gain/offset/binning) reads from the shared, ref-
//  counted `ObservableDevice` for `.camera` (acquireDevice(for:), same pattern as
//  ObservatoryDashboardView/TelescopeMessagesView) via Camera's own pure parsing helpers
//  (Camera.coolerOn(from:), Camera.doubleElement(...)) — live-updating for free, no per-field
//  polling. Commands (capture, cooling, filter selection) go through TelescopeSessionManager.
//

import SwiftUI
import INDIMCPKit

struct CameraPanelView: View {
    @State private var telescope = TelescopeSessionManager.shared
    @State private var cameraDevice: ObservableDevice?

    @State private var frameType: FrameType = .light
    @State private var exposureSeconds: Double = 30
    @State private var binningX: Int = 1
    @State private var gain: Double = 100
    @State private var offset: Double = 10
    @State private var targetTempC: Double = -10

    @State private var filterNames: [Int: String] = [:]
    @State private var selectedFilterName: String = ""
    // Guards the async gap between tapping Capture and TelescopeSessionManager.activeCaptureRunId
    // actually being set — without it, a fast double-tap could fire two overlapping exposures
    // before the first one's response comes back (I-9: one command in flight at a time).
    @State private var isSubmittingCapture = false

    private static let frameTypes: [FrameType] = [.light, .dark, .flat, .bias]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                PanelCard(title: "Frame") {
                    Picker("Frame type", selection: $frameType) {
                        ForEach(Self.frameTypes, id: \.self) { type in
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
                            TextField("0.0", value: $exposureSeconds, format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Binning")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Stepper("\(binningX)×\(binningX)", value: $binningX, in: 1...4)
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }

                    LabeledSliderRow(label: "Gain", value: $gain, range: 0...600, format: "%.0f")
                    LabeledSliderRow(label: "Offset", value: $offset, range: 0...200, format: "%.0f")

                    HStack {
                        Button {
                            Task { await capture() }
                        } label: {
                            Label("Capture Frame", systemImage: "camera.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isCapturing || isSubmittingCapture || telescope.state != .connected)

                        if isCapturing {
                            Button("Abort") {
                                Task { await abort() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if isCapturing {
                        Text(captureStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                PanelCard(title: "Filter Wheel") {
                    if filterNames.isEmpty {
                        Text("No filter wheel configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Filter", selection: $selectedFilterName) {
                            ForEach(filterNames.keys.sorted(), id: \.self) { slot in
                                if let name = filterNames[slot] {
                                    Text(name).tag(name)
                                }
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: selectedFilterName) {
                            Task { await selectFilter(selectedFilterName) }
                        }
                    }
                }

                PanelCard(title: "Cooling") {
                    TelemetryRow(label: "Sensor", value: currentTempText)
                    LabeledSliderRow(label: "Target temp", value: $targetTempC,
                                      range: -30...20, format: "%.0f", unit: " °C")

                    if let power = coolerPowerPercent {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Cooler power")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(power))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            ProgressCapsuleBar(progress: power / 100, tint: .cyan)
                        }
                    }

                    HStack {
                        Button(isCoolerOn ? "Cooler Off" : "Cooler On") {
                            Task { await toggleCooler() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Text(isCoolerOn ? "Cooling" : "Idle")
                            .font(.caption)
                            .foregroundStyle(isCoolerOn ? .cyan : .secondary)
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: telescope.connectionSessionID) {
            await holdDeviceAcquisition()
        }
        .task(id: telescope.connectionSessionID) {
            await loadFilterNames()
        }
    }

    // MARK: - Live state (read from the shared ObservableDevice, matching ObservatoryDashboardView)

    private var deviceProperties: [String: DeviceProperty] { cameraDevice?.properties ?? [:] }
    private var isConnected: Bool { cameraDevice?.liveIsConnected ?? false }
    private var isCoolerOn: Bool { Camera.coolerOn(from: deviceProperties) ?? false }

    // Camera's own doubleElement(_:_:from:) parsing helper is internal to INDIMCPKit, so these
    // read the live property snapshot directly — the same elements it would parse, just without
    // going through that non-public helper.
    private func doubleElement(_ propertyName: String, _ elementName: String) -> Double? {
        deviceProperties[propertyName]?.elements[elementName].flatMap(Double.init)
    }

    private var currentTempText: String {
        guard let value = doubleElement("CCD_TEMPERATURE", "CCD_TEMPERATURE_VALUE") else { return "—" }
        return String(format: "%.1f °C", value)
    }
    private var coolerPowerPercent: Double? {
        doubleElement("CCD_COOLER_POWER", "CCD_COOLER_VALUE")
    }
    private var isCapturing: Bool { telescope.activeCaptureRunId != nil }
    private var captureStatusText: String {
        switch telescope.activeCaptureStatus {
        case .progress(let progress): "Exposing… \(progress.message ?? "")"
        case .started: "Exposure started…"
        default: "Exposing…"
        }
    }

    private var header: some View {
        HStack {
            Label("Camera", systemImage: "camera.aperture")
                .font(.headline)
            Spacer()
            ConnectionBadge(isConnected: isConnected)
            DeviceStateBadge(state: isCapturing ? .busy : (isConnected ? .ok : .idle))
        }
    }

    // MARK: - Actions

    private func capture() async {
        isSubmittingCapture = true
        defer { isSubmittingCapture = false }
        do {
            try await telescope.captureFrame(
                exposureSeconds: exposureSeconds, frameType: frameType,
                binningX: binningX, binningY: binningX, gain: gain, offset: offset)
        } catch {
            telescope.errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    private func abort() async {
        do {
            try await telescope.abortExposure()
        } catch {
            telescope.errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    private func selectFilter(_ name: String) async {
        guard !name.isEmpty else { return }
        do {
            try await telescope.selectFilter(name)
        } catch {
            telescope.errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    private func toggleCooler() async {
        do {
            if isCoolerOn {
                try await telescope.coolerOff()
            } else {
                try await telescope.coolCamera(targetTempC: targetTempC)
            }
        } catch {
            telescope.errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    private func loadFilterNames() async {
        guard telescope.state == .connected else {
            filterNames = [:]
            return
        }
        filterNames = (try? await telescope.filterNames()) ?? [:]
        if selectedFilterName.isEmpty {
            selectedFilterName = filterNames.keys.sorted().first.flatMap { filterNames[$0] } ?? ""
        }
    }

    // Acquires the shared camera ObservableDevice for the lifetime of one connected session,
    // releasing it when this task is cancelled — either connectionSessionID changing (disconnect/
    // reconnect) or this view disappearing (pane closed), mirroring
    // ObservatoryDashboardView.holdDeviceAcquisitions().
    private func holdDeviceAcquisition() async {
        guard telescope.state == .connected else { return }
        cameraDevice = telescope.acquireDevice(for: .camera)
        defer {
            telescope.releaseDevice(for: .camera)
            cameraDevice = nil
        }
        try? await Task.sleep(for: .seconds(86400))
    }
}

#Preview {
    CameraPanelView()
        .frame(width: 340, height: 720)
}
