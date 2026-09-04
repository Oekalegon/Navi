//
//  FilterWheelEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI
import SwiftData

/// Editor for one `FilterWheelProfile` (§4.3). See `MountEditForm`'s doc comment for the
/// bind-directly-to-the-record, no-Save-button convention.
struct FilterWheelEditForm: View {
    @Bindable var filterWheel: FilterWheelProfile

    /// "+" inserts a blank record and selects it, so the editor opens on something with no name.
    /// Focusing the name field means the next keystroke names it, rather than leaving a row reading
    /// "Untitled Camera" that's indistinguishable from the next one someone adds.
    @FocusState private var isNameFocused: Bool

    var body: some View {
        SettingsDetailForm(title: filterWheel.displayName) {
            LabeledField("Name") {
                TextField("EFW", text: $filterWheel.name)
                        .focused($isNameFocused)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("ZWO", text: Binding(nilAsEmpty: $filterWheel.make))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("EFW", text: Binding(nilAsEmpty: $filterWheel.model))
                        .textFieldStyle(.roundedBorder)
                }
            }
            DevicePickerField(label: "INDI Device", deviceName: $filterWheel.deviceName)
            slotsEditor
            LabeledField("Notes") {
                TextField("Optional notes", text: Binding(nilAsEmpty: $filterWheel.notes))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onAppear { if filterWheel.name.isEmpty { isNameFocused = true } }
        .onChange(of: changeKey) { touch() }
    }

    /// `slots` is a computed property over JSON `Data` (SwiftData can't store an array of custom
    /// Codable structs directly), so it can't be `@Bindable`-bound per element — edits go through
    /// read-modify-write on the whole array instead.
    private var slotsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter Slots")
                .font(.caption)
                .foregroundStyle(.secondary)
            let slots = filterWheel.slots ?? []
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                HStack {
                    TextField("Slot", value: Binding(
                        get: { slot.slot },
                        set: { updateSlot(at: index) { $0.slot = $1 } ($0) }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    TextField("Filter name", text: Binding(
                        get: { slot.name },
                        set: { newName in
                            var updated = filterWheel.slots ?? []
                            guard updated.indices.contains(index) else { return }
                            updated[index].name = newName
                            filterWheel.slots = updated
                            touch()
                        }
                    ))
                        .textFieldStyle(.roundedBorder)
                    Button(action: {
                        var updated = filterWheel.slots ?? []
                        guard updated.indices.contains(index) else { return }
                        updated.remove(at: index)
                        filterWheel.slots = updated.isEmpty ? nil : updated
                        touch()
                    }) {
                        // See `SettingsPaneHeader`'s "+"/"−" for why: `.buttonStyle(.plain)` hit-
                        // tests the label's own bounds, and a bare glyph's bounds are a few points
                        // of ink, not a comfortable click target.
                        Image(systemName: "minus.circle")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: {
                var updated = filterWheel.slots ?? []
                updated.append(FilterSlotEntry(slot: (updated.map(\.slot).max() ?? 0) + 1, name: ""))
                filterWheel.slots = updated
                touch()
            }) {
                Label("Add Slot", systemImage: "plus")
            }
            .buttonStyle(.plain)
        }
    }

    private func updateSlot(at index: Int, _ apply: @escaping (inout FilterSlotEntry, Int) -> Void) -> (Int) -> Void {
        { newValue in
            var updated = filterWheel.slots ?? []
            guard updated.indices.contains(index) else { return }
            apply(&updated[index], newValue)
            filterWheel.slots = updated
            touch()
        }
    }

    private func touch() {
        filterWheel.modifiedAt = .now
    }

    /// Every editable field folded into one comparable value, so `modifiedAt` is stamped from a
    /// single `.onChange` rather than one per field — see `CameraLikeProfile.editableChangeKey`
    /// for why the list is kept in one place.
    private var changeKey: String {
        var parts: [String] = []
        parts.append(filterWheel.name)
        parts.append(filterWheel.make ?? "")
        parts.append(filterWheel.model ?? "")
        parts.append(filterWheel.deviceName ?? "")
        parts.append(filterWheel.notes ?? "")
        // Slot edits go through `touch()` directly (they mutate the array wholesale), so they
        // are covered without appearing here.
        return parts.joined(separator: "\u{1F}")
    }

}
