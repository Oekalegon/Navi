# Navi Codebase Review — 2026-06-15

Temp tracking doc. Strike through items as they are resolved.

---

## Blockers

- [x] **[BLOCKER] `FocusTrackerView.deinit` data race** — `SplitPaneView.swift` ~166  
  `deinit` is not `@MainActor`-isolated but mutates `paneManager.paneFrameProviders` and calls `NSEvent.removeMonitor`, both accessed exclusively on the main actor everywhere else. Potential intermittent crash.  
  Fix: hop to main via `DispatchQueue.main.async`, or mark the class `@MainActor`.

---

## Performance

- [x] **[PERF] Metal texture readback + pipeline execution on `@MainActor`** — `ArchiveManager.swift` ~822–837, ~1009  
  `autoArchiveResults` and `runPipeline` call `texture.getBytes(...)` (synchronous GPU readback) and `PipelineRunner.execute` while running on the main actor. Causes UI jank on large stacked frames.  
  Fix: wrap readback and `runner.execute` in `Task.detached(priority: .userInitiated)`.

---

## Quality

- [x] **[QUALITY] Duplicate `displayName(for: ArchivedFrame)`** — `FITSViewerView.swift` ~221 & `InfoPanelView.swift` ~361  
  Byte-for-byte identical function in two files. `ArchiveNameCell` in `ArchiveTableView.swift` has a related third variant.  
  Fix: extract to a free function in `ArchiveViewerContent.swift` or an extension on `ArchivedFrame`.

- [x] **[QUALITY] Stale Claude model IDs** — `ClaudeService.swift` ~48–49  
  `"claude-sonnet-4-5-20250929"` and `"claude-opus-4-5-20251101"` are dated snapshot identifiers that may be retired.  
  Fix: use alias form without date suffix.

- [x] **[QUALITY] Silent error swallowing in `loadChildren` / `loadObjects`** — `ArchiveTableView.swift` ~81, `ArchiveFilterSheet.swift` ~295  
  Empty `catch {}` — frameset expander silently shows nothing, object list silently stays empty.  
  Fix: `logger.warning("archive call failed: \(error)")` at minimum.

- [x] **[QUALITY] Silent error swallowing in `openFrameset`** — `InfoPanelView.swift` ~337  
  Empty `catch {}` on `callTool` throw. Tapping a frameset link and getting a failure is silent.  
  Fix: `logger.error("openFrameset failed: \(error)")`.

- [x] **[QUALITY] Force-unwrap in `SettingsManager.saveAPIKey`** — `SettingsManager.swift` ~51  
  `key.data(using: .utf8)!` — unnecessary force-unwrap.  
  Fix: `guard let data = key.data(using: .utf8) else { return }`.

- [x] **[QUALITY] `rejected` flag stored as `String` `"true"`/`"false"`** — `ArchiveViewerContent.swift` ~29, scattered callers  
  `row.values["rejected"] == "true"` repeated across 3+ files. A case change in the serialiser silently breaks all callers.  
  Fix: typed accessor `var isRejected: Bool { values["rejected"] == "true" }` on `ArchiveRow`.

- [x] **[QUALITY] `startAccessingSecurityScopedResource()` return value ignored** — `ArchiveManager.swift` ~117  
  If the bookmark is stale and access is denied, the error is indistinguishable from an init failure.  
  Fix: check and log the return value.

---

## Design

- [x] **[DESIGN] `ArchiveManager` is a ~1,200-line God class** — `ArchiveManager.swift`  
  Handles connection, bookmarks, FITS enumeration, MCP dispatch (~18 tools), pipeline execution, GPU readback, auto-archive, quality extraction, and import.  
  Fix: extract `ArchivePipelineRunner` (~400 lines) and `ArchiveQualityExtractor` (static methods) as a starting point.

- [ ] **[DESIGN] `frameType` and `processingLevel` stored as `String` in `ArchiveRow`** — `ArchiveViewerContent.swift` ~26–29  
  `ProcessingLevel` already exists as a typed enum in `AstrophotoArchiveKit`. Magic-string comparisons scattered across files.  
  Fix: typed accessors on `ArchiveRow`, or at minimum string constants.

- [ ] **[DESIGN] `AIAssistantView` initialises `viewModel` with empty API key** — `AIAssistantView.swift` ~15  
  `AIConversationViewModel(apiKey: "")` relies on `.onAppear` to set the real key. Window between creation and appearance where key is empty.  
  Fix: `AIConversationViewModel(apiKey: SettingsManager.shared.apiKey)`.

---

## Minor

- [ ] **[MINOR] `import AppKit` in `NaviApp.swift` not annotated as intentional** — `NaviApp.swift` ~9  
  Justified (NSOpenPanel), but should carry a comment per convention.

- [ ] **[MINOR] `Message` is `Codable` but `MessageType` is excluded** — `ClaudeService.swift` ~11–14, ~30–33  
  Round-tripping a `Message` silently loses `messageType`. Currently safe (in-memory only) but misleading.  
  Fix: either make `MessageType` fully `Codable`, or remove `Codable` from `Message`.

- [ ] **[MINOR] `DiskUsageBar` segment widths don't account for `archiveWidth` minimum clamp** — `ArchiveStatusBar.swift` ~76–84  
  `archiveWidth` uses `max(2, ...)` but `otherWidth` is computed from the raw proportion. Segments can exceed available width by 1–2pt.  
  Fix: subtract the clamped `archiveWidth` from the remaining budget before computing `otherWidth`.

- [ ] **[MINOR] `processConversationTurn` uses async recursion** — `AIConversationViewModel.swift` ~103–194  
  10-deep async recursion. Not a real overflow risk but a loop is cleaner.  
  Fix: `for depth in 0..<maxToolRounds { ... if done { break } }`.
