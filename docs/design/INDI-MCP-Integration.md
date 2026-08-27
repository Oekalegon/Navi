# INDI-MCP Integration — Design Document

Status: **Draft, fully scoped** — Phase 1 scoping and the Rig/Observatory/equipment-library design pass are both
complete; every open issue below is resolved. Ready to move into implementation per §7.
Owner: Don Willems
Related: `Navi/TelescopeControl/*` (static mockup, precedes this doc), INDIMCPKit (`/Users/donwillems/Personal/Development/INDIMCPKit`), INDIMCP-server (`/Users/donwillems/Personal/Development/INDIMCP-server`)

## 1. Goal

Give Navi live control of an observatory rig (mount, camera, filter wheel, focuser) via INDIMCPKit, which talks to
an INDIMCP-server instance fronting `indiserver` and its drivers over MCP (Streamable HTTP).

This doc scopes the work in two phases and calls out the open questions that need answers before implementation
starts.

- **Phase 1** — observatory/rig setup, connecting to INDI-MCP, starting/stopping `indiserver` and drivers.
- **Phase 2** — camera functions (capture, cooling, filter wheel).
- **Later / explicitly out of scope for now** — mount control beyond what's needed to validate the connection
  (Mount's API is already thin — no abort-slew, no telemetry getters — so a full mount UI is a separate pass),
  guiding, plate solving, calibration sweeps, focuser automation.

## 2. Existing groundwork

`Navi/TelescopeControl/` (this repo) already has a **static SwiftUI mockup** — `TelescopeControlView` (tab host),
`MountPanelView`, `CameraPanelView` — built against `@Observable` mock state classes, explicitly labeled "NOT wired
to INDIMCPKit yet." Its doc comments were written against INDIMCPKit's actual method surface, so the control
inventory (what buttons/fields exist) is already reasonably accurate. This design reuses that layout as the UI
target and replaces the mock state with real `INDIMCPClient`/device-handle-backed state.

Two things the mockup already got right that matter for this doc:
- Mount's mockup uses coordinate-entry slewing (no N/S/E/W nudge, no slew-rate picker) because `Mount` genuinely
  has no such API — confirmed against INDIMCPKit's source, not a mockup shortcut.
- Camera's filter picker is populated from a rig's dynamic slot list, not a hardcoded enum — matches
  `Component.slots: [Int: String]` on a rig's filter-wheel component.

## 3. Architecture

### 3.1 How this differs from the AstroKit integration pattern

Navi's existing MCP-shaped integration (AstroKit) is **in-process / stdio**: `ArchiveManager` implements the `archive_*` tools natively, and pipeline
execution talks to a co-located AstroKit MCP server. INDI-MCP is different in a way that should be explicit in the
architecture, not discovered later:

- **INDIMCPKit only supports Streamable HTTP**, not stdio (the doc comments call stdio "local-testing-only" and
  the kit deliberately doesn't implement it). So `INDIMCPClient` always talks to a **network endpoint**
  (`http://host:port/mcp`), not a subprocess Navi spawns and pipes to.
- **INDIMCP-server is a separate, long-running Python process** (the `indi-mcp` project) that in turn manages
  `indiserver` and INDI driver child processes. It is *not* part of INDIMCPKit and Navi has no code-level
  relationship to it beyond talking to its HTTP endpoint. Resolved in [I-1](#i-1-does-navi-ever-launch-indimcp-server-itself--resolved-no):
  it runs as a boot-time system service on a Raspberry Pi at the observatory — Navi never launches or manages that
  process, only connects to it.
- Because it's HTTP, the server the user talks to is expected to be **a Raspberry Pi on the local network at the
  telescope**, not the Mac running Navi itself — the endpoint is user/observatory-configured (hostname/IP + port),
  not hardcoded.

### 3.2 Session/service layer

Following the existing pattern of a single owning manager per subsystem (`ArchiveManager`, `SettingsManager`), this
introduces one new `@Observable` singleton-ish service, tentatively `TelescopeSessionManager` (owned the same way
`ArchiveManager` is — created once, referenced by panes, not one instance per pane/window):

- Owns the `INDIMCPClient` instance and its connection state (`.disconnected` / `.connecting` / `.connected(...)`
  / `.error(...)`).
- Owns the **connect cascade** (fully specified in §4.3), the active `Rig`/`Observatory`/server selection, and the
  `ObservableDevice` instances for whichever roles the current UI needs, so two panes/windows share one live
  subscription per device rather than each spinning up its own poll+stream (§4.5, I-8).
- Single choke point for hardware commands, so two panes can't independently fire conflicting commands (I-9).
- Owns liveness detection while connected: the `connectionEvents` push stream as the primary signal, plus a 30s
  heartbeat timer (a cheap call like `getINDIServerStatus()`) as a backstop against a connection that hangs
  without ever throwing — mirrors `ObservableDevice`'s own internal resync-timer safety net, just tuned shorter
  since a silently-dead connection to a live device deserves faster surfacing than a stale property read does.

### 3.3 Pane integration

Two new panes, following [Panel Architecture] conventions (`PaneType` case, `PaneManager.show...()`, toolbar
toggle, `PaneCloseButton`), plus the existing mockup tab shell:

- **`PaneType.telescopeControl`** — hosts `TelescopeControlView` (the existing mockup tab shell: Mount/Camera
  tabs), reading from `TelescopeSessionManager` via environment instead of owning mock state. Opens like any other
  pane — button-driven, not automatic.
- **`PaneType.observatoryDashboard`** — the status dashboard from §4.6. Unlike every other pane in the app, this
  one **opens automatically the moment Connect succeeds** — a deliberate, explicitly-decided exception to Navi's
  otherwise button-driven pane philosophy, since this is core live-status information you'd always want visible
  once connected. Placement follows the existing "reuse an empty pane, else split from the AI pane" rule already
  used by `showArchiveViewer`/`showFITSViewer`, unless a fixed/pinned location is preferred later.
- **`PaneType.telescopeMessages`** — the terminal/message pane from §4.7. Opens like a normal pane (button-driven),
  no auto-open.

Pane lifecycle matters here in a way it didn't for the archive/FITS panes: closing a pane should call
`ObservableDevice.stop()` (or have `TelescopeSessionManager` reference-count and stop only when the last consumer
goes away) — an `ObservableDevice` left running leaks a live MCP resource subscription and a periodic resync timer.

## 4. Phase 1 scope — observatory/rig setup, server & driver lifecycle

This section is the output of a dedicated design pass (a structured "grilling" session) covering everything the
original draft of this doc had deferred as a placeholder. It fully supersedes that placeholder — nothing below is
provisional.

### 4.1 Toolbar

One **selection button** (labeled with the current Observatory/Rig, e.g. "Home Backyard · My EQ6-R Rig") plus a
**Connect/Disconnect button** — revised from an earlier two-separate-dropdowns sketch, since a single entry point
into a modal picker scales better as the Observatory list grows (§4.2 notes it's expected to get large — many
one-off/occasional sites — while the Rig list stays short) and keeps both selections visually paired as "your
current setup" rather than two independent, easy-to-mismatch controls.

- **Selection button** — opens a modal panel with two pickers side by side (or stacked): **Observatory** (lists
  `listObservatories()`, plus a **"Current Location"** quick-create entry, visible/enabled only when
  `CLLocation`/Location Services access is available — hidden or disabled otherwise, never an error on tap;
  selecting it prompts for a single required field, the observatory's name, and saves immediately with everything
  else — lat/lon, elevation, whatever precision `CLLocation` gives — filled in automatically, no full-editor
  detour) and **Rig** (lists `listRigs()`, expected to stay short). Confirming in the modal updates the toolbar
  button's label; it does not itself connect anything.
- **Connect/Disconnect button** — a separate, explicit action from the selection modal. Picking a Rig/Observatory
  only *arms* the selection; it never triggers a connection attempt by itself. No separate Server picker exists —
  a Rig carries a default server reference (§4.2), so picking a Rig implicitly determines which server Connect
  targets; overriding that mapping is a Settings-only action, not a toolbar one.

### 4.2 Settings

- **Observatory pane** — full CRUD editor: name, lat/lon, elevation, and a horizon-obstruction profile. The
  profile is authored by **importing a `.hzn` file** (the plain-CSV `azimuth,altitude` format used by Stellarium
  and N.I.N.A., one line per integer azimuth degree) — confirmed already referenced in INDIMCP-server's own docs
  (`docs/ObservatorySchema.md`, `parse_hzn_profile`), but that parser is server-side Python only, not exposed as
  an MCP tool. Navi needs its own small client-side `.hzn` parser (trivial: split lines, `azimuth,altitude` pairs)
  feeding directly into `Observatory.horizonProfile` on save — no server/kit changes required.
- **Rig pane** — full CRUD editor, built on the equipment library (§4.3). Every device-bearing field (Mount,
  Camera, Guide Camera, Focuser, Filter Wheel — every role that binds to an INDI device, no exceptions) is
  **selection-only from the live device list, never free text** — a component's non-device fields (aperture, make/
  model, etc.) can be authored fully offline, but the actual `device` binding can only be set by picking from
  currently-visible devices while connected with messaging running. If not connected, or a driver you need isn't
  running, that field simply stays unresolved until you're in a position to pick correctly.

  Components are individually **selectable/deselectable per role** — a rig with no focuser or no filter wheel just
  omits those roles entirely, they're not forced fields. A role that's selected but has no `device` bound yet is a
  valid, saveable **"blank"** state (`saveRig` happily persists a `Component` with `device: nil`) — distinct from
  `checkRig`'s live **"missing"** state (a component *has* a device bound, but isn't currently connected). Both
  get surfaced as warnings, but with different remedies: blank → pick a device (when connected) or deselect the
  role; missing → go start that driver / check the connection. The UI should keep these visually distinct rather
  than lumping them into one generic "incomplete" badge.

  **Duplicate components per role are not allowed for now** (e.g. two independent `camera` components for a
  multi-OTA-on-one-mount setup) — INDIMCPKit's data model tolerates this (`DeviceControlError
  .ambiguousComponentForRole` exists specifically for it), but there's no way to group a duplicate's associated
  components (filter wheel, rotator) as belonging to the *same* optical path as one telescope rather than another
  — `Component` (`rig_store.py`) is a flat list with no parent/group field at all, confirmed by reading
  `Component.swift` directly. Filed upstream (originally as [GitHub #112 on `Oekalegon/indi-mcp`](https://github.com/Oekalegon/indi-mcp/issues/112),
  now closed in favor of tracking it as **INDIMCP-138** in the local todo tracker) — revisit once the server
  supports train grouping.
- **Server pane** — a list of named INDI-MCP servers (name + URL) in the local equipment library (§4.3), since
  it's likely the same Raspberry Pi (and thus the same server) is used for a specific rig session after session. A
  Rig references one as its default; changing that default is an explicit action here, never a side effect of a
  transient toolbar override (§4.4).

### 4.3 Equipment library (new local persistence — SwiftData)

Navi has no existing structured local data store today (only `UserDefaults`/Keychain for settings, security-scoped
bookmarks for files) — this is genuinely new. **SwiftData** is the chosen mechanism: a handful of small, related
record types with basic CRUD and no complex querying, exactly its sweet spot, and it plays natively with the
`@Observable` conventions already used throughout Navi.

Four reusable library entities, composed together to form a Rig — none of these concepts exist in INDIMCPKit
itself, which only ever sees the *flattened* `Component` list a Rig gets translated into on save:

- **Mount** — reusable on its own, since the same mount may carry different optical assemblies over time (swap
  telescopes on one mount).
- **Optical Assembly** (OTA + Focuser, combined as one unit) — aperture, focal length, telescope type (all manual
  input; an OTA has no INDI device of its own), plus its Focuser (device-linkable). Combined rather than modeled
  as two separately-reusable things, since a focuser is normally semi-permanently mounted to one tube — an actual
  focuser swap is rare enough to just edit the existing record when it happens.
- **Imaging Train** (Camera + Filter Wheel + Rotator) — the equipment that sits behind an Optical Assembly.
- **Guide Camera** — independent of Imaging Train (not nested inside it), because it needs to attach in two
  different places depending on setup: paired with a Guide-Scope-typed Optical Assembly (traditional piggyback
  guide scope — itself just another Optical Assembly record, typically without a focuser), or inserted directly
  into the main Imaging Train for an off-axis guider (which taps light from within the main optical path, no
  separate guide scope at all).

Composition rules: an Imaging Train pairs freely with any Optical Assembly (no hard compatibility constraint
modeled — image-circle/back-focus compatibility is a human judgment call at pick-time, not something worth
validating in software for v1). A saved Rig **tracks which library entity ids composed it** (a Navi-local
companion record, since the server has no such concept) — this is what lets "swap the whole Imaging Train" work
as a unit later, rather than every Rig edit meaning re-picking every field from scratch.

**Library edits vs. already-saved Rigs**: editing a library entity's fields (aperture, pixel geometry, the
`device` binding, etc.) does **not** silently cascade into every Rig that referenced it — that would mean
defeating `saveRig`'s `overwrite` safety guard silently in the background, needing an offline-queueing mechanism
(since pushing the resync needs a live connection, while editing the library doesn't), and risking rewriting a
Rig's config out from under an actively-connected session. Instead: **automatic detection, explicit confirmation**
— the moment you edit a library entity, Navi immediately shows which Rigs now reference stale data, with a
one-click **"Resync all"** action. You get the reuse workflow without a silent background push. (Editing a purely
Navi-local label/nickname on a library entity — as opposed to a field that actually flows into a `Component` —
needs no resync at all, since nothing about it is ever sent to the server.)

**Four roles have no library entity** — `.powerHub`, `.observatoryControl` (roof/dome), `.flatScreen`,
`.dewHeater` — none obviously fit "reusable optical equipment" (a dew heater controller has essentially no fields
worth capturing beyond "which device"). These get **simple standalone per-Rig components** in the Rig editor: a
device picker row, no library backing. `.observatoryControl` in particular is conceptually **site-fixed
equipment, not portable rig equipment** — a roof/dome controller doesn't travel with a mobile rig the way a camera
does, and arguably belongs on the *Observatory* record instead. But `Observatory` (`Observatories/Observatory.swift`)
has no equipment/components concept at all today — confirmed by reading the struct directly (just id/name/lat/
lon/elevation/horizonProfile) — so there's genuinely nowhere server-side to put it yet. Filed as **INDIMCP-139** in
the local todo tracker (add an equipment concept to `Observatory`, mirroring `Rig`'s `Component` list); until
that lands, `.observatoryControl` stays a standalone Rig component like the other three, and the Rig config also
carries its own server reference (§4.2) — once Observatory-scoped equipment exists server-side, the Observatory
record would need its own server reference too, since a fixed dome controller and a portable rig's camera could
plausibly be driven by different Pis/servers even at the same physical site.

### 4.4 Connect / Disconnect lifecycle

**Connect** triggers a fully specified cascade, every step of it idempotent (never restart something already
running, regardless of what started it):

1. MCP connect (the handshake).
2. Check `indiserver` status; start it only if not already running.
3. Start INDI messaging (if not already running).
4. For every component in the selected Rig that has a `device` bound (blank/unresolved components are skipped —
   nothing to start): start that component's driver only if it isn't already running, then `connectDevice` it.

**Disconnect** is the deliberate, symmetric "shut it down" action: it stops the rig's drivers and `indiserver`.
This is a real reversal from an earlier draft of this doc (which had leaned toward Disconnect only ever closing
Navi's own session) — the corrected model is:

- **Disconnect** (explicit button press) = deliberate, stops everything Connect started.
- **Navi quitting or crashing without an explicit Disconnect** = touches nothing on the Pi. An unattended overnight
  capture sequence, or a mount left tracking, keeps running exactly as if Navi were still open.
- **On launch**, Navi probes *every* saved server (§4.2's Server pane), concurrently (each under the timeout
  wrapper from I-5, so one unreachable/out-of-range server — e.g. a star-party site you're not currently at —
  can't block the others or slow down launch) — never just the last-used one, since you may rotate between
  several recurring sites. This is **detect-and-prompt, not silent auto-attach**: a server found already running
  surfaces as "already up, ready to connect" (e.g. a highlighted Connect affordance), but the actual MCP session
  only attaches when you press Connect yourself — consistent with picking a Rig never auto-connecting either.
  Whatever's found running is left exactly as-is (no restart, per the idempotent-start rule above).

### 4.5 Command serialization and shared device sessions

Unchanged from the original draft, restated here for completeness now that §4.1–§4.4 give it concrete grounding:
`TelescopeSessionManager` owns one `ObservableDevice` per role, shared across every pane/window that needs it
(I-8), and is the only place hardware-command methods live — views never hold a `Mount`/`Camera` handle directly
(I-9).

### 4.6 Dashboard pane

Opens automatically on Connect (§3.3). Shows, all live:

- Current time and current Local Sidereal Time.
- **Observatory** — lon/lat/elevation, and sunrise/sunset (or civil/nautical/astronomical twilight).
- **Rig** — every component, with connected/disconnected/error status for whichever ones are actually
  connectable (a passive item like an OTA has no device/connection state to show).

All of the astronomical math already exists in **AstroKit**, no new algorithm work needed: `SiderealTime(observatory:date:).local`
for LST, and `Sun().riseTransitSet(on:at:altitude:)` for sunrise/set and twilight (pass `.civilTwilight`/
`.nauticalTwilight`/`.astronomicalTwilight` as the altitude threshold). Two integration details worth flagging
explicitly since they're easy to get wrong silently: AstroKit's `Observatory` type takes longitude/latitude in
**radians**, while INDIMCPKit's `Observatory` uses **degrees** — Navi needs a small conversion layer between them
— and **both packages have a type literally named `Observatory`** with different shapes, so code that touches both
should qualify them clearly (e.g. `AstroKit.Observatory` vs. a locally-renamed INDI counterpart) rather than
relying on context to disambiguate.

Per-component status is driven by the same shared `ObservableDevice` instances from §4.5 — no new live-data
mechanism needed, just a view over state that already exists.

### 4.7 Terminal / message pane

Shows raw INDI-MCP server messages, **scoped to the current rig's devices** (not the whole server — unrelated
equipment's messages are just noise) via `messageEvents(device:)`. Unlike the live-only stance originally
sketched for other event streams in this doc, this pane **also loads history from the server's durable event log**
(`getEvents`) on open, rather than starting from a blank slate and only showing what arrives while you're
watching it.

## 5. Phase 2 scope — camera functions

Wire `CameraPanelView`'s mock state to `Camera`/`ObservableDevice`:

- Frame type / exposure / binning / gain / offset fields → `captureFrame(...)`. Capture is fire-and-poll, not
  fire-and-await: `captureFrame` returns `ScriptRunStarted` immediately, and progress must come from
  `waitForTerminalStatus` or the `scriptEvents(runId:)` `AsyncThrowingStream` — the mockup's `captureProgress`
  slider needs a real driver behind it (see [I-3](#i-3)).
- Cooling card → `coolCamera`/`coolerOn`/`coolerOff`/`setTargetTempC`, telemetry via `ObservableDevice.properties`
  or `Camera.currentTempC()`/`coolerPowerPercent()` (flagged by INDIMCPKit itself as unverified against a real
  driver — treat as best-effort display, not safety-relevant).
- Filter wheel picker → `FilterWheel.selectFilter(rigId:filterName:)`, slot list from `Component.slots`.
- **Frame retrieval and archival** — this is new integration surface, not just UI wiring: a completed capture's
  bytes never come back in the tool-call response. Navi has to poll/subscribe for the frame's metadata, download
  it via plain HTTP GET to a local path, verify its checksum, and only then feed it into the existing Archive
  import path (`ArchiveManager`) — then explicitly `confirmFrameTransfer` and eventually purge it server-side.
  This needs its own mini design (where do downloaded frames land in the sandbox, security-scoped bookmark or
  Navi-owned temp dir, does it dedupe against files already archived) — see [I-2](#i-2).

## 6. Open issues to resolve before implementation

### I-1: Does Navi ever launch INDIMCP-server itself? — **Resolved: no**
`startINDIServer`/`stopINDIServer` control **`indiserver`**, a process the *already-running* INDIMCP-server
manages. They say nothing about the INDIMCP-server process itself — if it's not running, `INDIMCPClient.connect()`
just fails to reach the endpoint.

**Decision:** INDIMCP-server is assumed to be a standing system service on a Raspberry Pi at the observatory,
started at boot (e.g. a systemd unit) and always up whenever the Pi is powered. Navi never launches, stops, or
manages that process — no SSH-launch story, no bundled local instance. "Connect" in the UI means only "reach the
configured URL and run the MCP handshake"; if that fails, the failure mode to surface to the user is "can't reach
the Pi" (network/DNS/Pi-powered-off) rather than "server not started," since Navi has no lever to start it. This
also means the endpoint config (§4) should default to whatever's easiest for a Pi-on-the-local-network setup
(e.g. `<hostname>.local`), and the connect-state-machine UI copy (§3.2) shouldn't offer a "start server" action —
only `indiserver` and driver start/stop are ever within Navi's control (§4's "Server control"/"Driver list" items
already scope correctly to that; no change needed there).

### I-2: Where do downloaded frames live, and how do they join the Archive? — **Resolved: auto-import, grouped into a frameset per capture run**
`downloadFrame` writes to a caller-supplied local `URL`. Need: a storage location decision consistent with
`SettingsManager.dataPath`/security-scoped bookmarks, a dedupe/naming scheme, and a decision on whether captured
frames auto-import into the Archive or require a user action (the existing Archive flow is explicitly
"button-driven, not automatic" per [Panel Architecture] — that pattern doesn't apply here).

**Decision:** captured frames are imported into the Archive automatically, with no user click required — unlike
the AI-chat "Browse in Archive" flow, a capture session can produce dozens of unattended frames overnight and
nobody should have to come back and manually pull each one in. This changes the shape of the work from "wire a
button" to "run an import pipeline as a side effect of every completed capture," which needs its own small state
machine per frame: `ScriptRunStatus.completed` → `listFrames`/`getFrameMetadata` → `downloadFrame` to a local path
→ `verifyChecksum` → `ArchiveManager.importFITS(urls:)` → on success, `confirmFrameTransfer(frameId:)` (only after
the archive import itself succeeds — a checksum-verified download that then fails to import must **not** be
confirmed/purged server-side, or the frame becomes unrecoverable). Failures at any step should be visible (not
another silent `catch {}`, per [I-4](#i-4-error-surface-is-split-across-three-channels--needs-one-navi-side-model))
but shouldn't block the capture sequence from continuing.

Frames from one capture run belong together, not as loose singles in the Archive table — they should be grouped
into a frameset (Archive already has frameset creation/membership APIs, e.g. `archive_frameset_create`/
`archive_frameset_add`, used today for calibration sessions per NAVI-38). Still open, and worth a follow-up pass
once this is actually built rather than blocking Phase 2 on it: what defines "one run" for grouping purposes —
one `TelescopeSessionManager` capture sequence (e.g. an N-frame light-frame set kicked off from one UI action), or
something coarser like "everything captured in one connected session/night" the way calibration sessions are
grouped today. Leaning toward the former (one explicit capture sequence = one frameset) since it maps directly to
a single user-initiated action and avoids having to infer session boundaries from idle time or local midnight.

Local storage location: alongside existing archived data under `SettingsManager.dataPath` (not a separate
INDI-specific folder) so the Archive's existing file-management assumptions (security-scoped bookmark, single
data root) keep holding; exact subfolder/naming scheme (e.g. by rig/date/frame-id) still to be worked out when
this is implemented.

### I-3: Progress model for capture and slew — polling vs. streaming, and how far Navi commits to it — **partially resolved**
Every hardware command is fire-and-return-runId. Navi needs a consistent pattern (probably `scriptEvents` as the
live feed, with `waitForTerminalStatus` or a resync timer as the fallback/catch-up path, mirroring what
`ObservableDevice` already does internally for messaging) used uniformly across capture, slew, cooling-wait, etc.

**Confirmed:** an in-progress exposure keeps running on the Pi regardless of what Navi's UI does — closing the
pane, backgrounding the app, even quitting Navi entirely does not stop the capture. This settles the cancellation
question: Navi must treat "no local task tracking this `runId`" as completely uninformative about whether the
hardware is actually idle, and design for **re-attaching to an in-flight run** as a first-class case, not an edge
case:
- `TelescopeSessionManager` should persist the active `runId` (per rig/role) somewhere that survives a pane close
  and an app relaunch — not just in-memory view state. `UserDefaults` (keyed by rig id) is probably sufficient
  since it's just a String; no need for anything heavier.
- On reconnect/pane-open, before assuming the camera is idle, check for a persisted `runId` and query
  `getScriptStatus`/re-subscribe to `scriptEvents(runId:)` to recover live progress — the UI's "Capture" button
  should come up already showing progress (or an abort option) rather than a stale idle state if a run is still
  going.
- Corollary: an "Abort" action in the UI is a real, separate operation from "the pane went away" — `abortExposure`
  must be an explicit user action (mirrors the mockup's existing separate Capture/Abort buttons), never something
  Navi does implicitly on pane close or app quit.
- Still open: exactly which of `scriptEvents` streaming vs. `waitForTerminalStatus` polling vs. a periodic resync
  is primary vs. fallback for each command family (capture vs. slew vs. cooling-wait), and whether that pattern
  gets its own small reusable helper (mirroring `ObservableDevice`'s internal snapshot+stream approach) rather
  than being reimplemented per device type — worth settling when this is actually built, not blocking Phase 1/2
  scoping.

### I-4: Error surface is split across three channels — needs one Navi-side model — **resolved from existing convention, not a product decision**
`INDIMCPClientError` (transport/tool-call rejection), `DeviceControlError` (client-side pre-flight), and
`ScriptRunStatus.failed` (mid-run failure, not a thrown error at all) all need to collapse into one place. This
didn't need a call from Don — Navi already has a settled, consistent pattern for this across `ArchiveManager` and
`AIConversationViewModel`: an owning manager exposes `var errorMessage: String?`, set on failure/cleared on
success, and the view reads it and renders inline (`AIAssistantView.swift` ~60, ~103) — no toasts, no `.alert()`
sheets anywhere in the app. `TelescopeSessionManager` follows the same shape: one `errorMessage: String?` (or,
given three distinct failure shapes feeding it, a small internal enum that formats down to that one String) that
all three error channels funnel into via `catch`, replacing the placeholder silent-`catch{}` anti-pattern already
flagged elsewhere in the codebase (`code-review.md`). This is pure implementation work, not something to resolve
at design-doc time — noted here only so the "which of three error types do I catch" question doesn't get
re-litigated per call site. A lost MCP connection specifically does **not** have a dedicated error case — it
surfaces as whatever the underlying `swift-sdk` transport throws, so catch sites need to treat "any `Error`" as a
possible disconnect, not just the two named enums, when deciding what string to show.

### I-5: No auto-reconnect, no request timeout — both are Navi's responsibility — **resolved: manual reconnect + timeout wrapper**
`INDIMCPClient` has no built-in reconnect/backoff and is single-use after `disconnect()` ("create a new one").
There's also no exposed HTTP request timeout, so a hung request can hang indefinitely. `TelescopeSessionManager`
owns both: a **manual, user-visible "Reconnect"** action rather than silent automatic reconnect-with-backoff — for
a live device-control app, reconnecting automatically while a slew or capture might be in progress is the riskier
default, and a manual action keeps the operator in the loop about connection state changing under them — plus a
**timeout wrapper** (race every `async throws` call against a `Task.sleep`) around commands so the UI never spins
forever on an unresponsive server. No open question left here; this is the accepted design.

### I-6: Is rig authoring in scope, or read-only rig selection only? — **Resolved: yes, in scope, fully specified in §4**
`saveRig` exists and Navi's Phase 1 rig UI is not just a picker over rigs authored elsewhere (`INDIMCPKitTestApp`,
hand-edited YAML) — it needs a real editor. This was originally left as a placeholder pending a dedicated design
pass; that pass has since happened and its full output — the equipment library, device-resolution rules (picker-
only, never free text), component selection/deselection, and the Rig↔Observatory↔Server relationships — lives in
§4.2–§4.3. Nothing further to resolve here.

### I-7: `INDI messaging` sequencing is a foot-gun — **resolved, no decision needed: already handled by §3.2's ordering**
Several calls (`ensureConnected`, `checkRig`, `getDeviceProperties`) fail with a generic `toolCallFailed` — not a
distinct "messaging not started" error — if `startINDIMessaging()` hasn't run yet. This is fully addressed by the
connect state machine already specified in §3.2: `startINDIMessaging` is its own explicit, ordered step (MCP
connect → server status/start → **messaging** → rigs/devices), so as long as `TelescopeSessionManager` gates rig-
and device-level calls behind that step actually completing, the class of error this issue describes can't happen
from Navi's own code paths — nothing further to design here. The one implementation nicety worth keeping in mind
when this is built: if a `toolCallFailed` still surfaces from a device-level call outside that gated flow (e.g. a
race where messaging silently died server-side after startup), pattern-matching its message to show something
better than the raw string is a nice-to-have, not a requirement — falls out of the I-4 error-message plumbing
rather than needing separate design.

### I-8: One shared device session across panes/windows, not one per view — **resolved, no decision needed: already the §3.2 design**
Navi supports multiple windows, and per [Panel Architecture] a pane type can appear in more than one window.
`ObservableDevice` is `@MainActor` and cheap to create, but nothing stops two independent instances for the same
rig+role from each polling and subscribing separately — wasteful, and worse, doubles the "harmless no-op" surface
if both independently retry something. This is already the design: §3.2 has `TelescopeSessionManager` own one
`ObservableDevice` per role and let multiple panes observe the same instance, matching how
`WindowRegistry`/`PaneManager` already centralize state rather than duplicating it per pane. Nothing further to
decide — just an implementation constraint to hold to.

### I-9: Command serialization — prevent two panes issuing conflicting hardware commands — **resolved, no decision needed: already the §3.2 design**
Nothing in INDIMCPKit itself prevents concurrent `slew`/`captureFrame`/etc. calls to the same device from two call
sites. With the single shared session from I-8, this is solved by construction as long as one rule holds:
hardware-command methods live only on `TelescopeSessionManager`; views never hold a `Mount`/`Camera` handle
directly and call it themselves. Stated here as an explicit constraint for whoever implements this, not a decision
point.

### I-10: Security posture of the HTTP endpoint
Both the MCP tool-call transport and frame download are plain HTTP with `URLSession` defaults — no TLS, no auth
mentioned anywhere in INDIMCPKit. Given I-1's resolution (a Pi on the observatory's local network), this is the
expected deployment shape and is fine on a trusted LAN/VPN — but worth stating explicitly as an assumption in this
doc (and in Settings UI copy) rather than silently inheriting it: **do not expose the INDI-MCP endpoint to an
untrusted network**, and don't add a "reach the Pi over the internet" convenience feature (e.g. port-forwarding,
cloud relay) without revisiting this — there's no auth layer to fall back on if the LAN assumption breaks.

### I-11: Version drift — pre-1.0, no changelog — **resolved: non-blocking warning banner, low-stakes default**
INDIMCPKit tracks INDIMCP-server `0.1.0` and states breaking changes should be expected release-to-release. A
lightweight startup check (`getServerInfo().matchesAlignedVersion`) surfaced as a non-blocking warning banner
("server version doesn't match the kit Navi was built against") rather than skipped — this is exactly the kind of
drift that produces confusing runtime failures otherwise. Low enough stakes (a warning, not a hard gate) that it
doesn't need sign-off beyond this — implement as described when this piece of work comes up.

## 7. Suggested sequencing

1. Add INDIMCPKit as a local package dependency (same pattern as `../AstroKit`).
2. Define the SwiftData schema for the equipment library (§4.3): Mount, Optical Assembly, Imaging Train, Guide
   Camera, Server, plus the Rig↔library-entity and Rig↔default-Observatory/Server link records.
3. Build `TelescopeSessionManager`: connection state, the connect/disconnect cascade (§4.4), liveness detection
   (§3.2's push-stream-plus-heartbeat), and the shared `ObservableDevice` ownership (§4.5) — no UI beyond a bare
   connect button and status text yet.
4. Build the toolbar (§4.1) and Settings panes (§4.2) against that manager; retire the mock connection state in
   `TelescopeControlView`.
5. Build the Dashboard pane (§4.6) and Terminal/message pane (§4.7).
6. Wire Camera (§5), including the frame-download/archive-import mini-design from I-2 — likely the largest single
   chunk of new work in this phase.
7. Defer Mount beyond "does the connection work" (see §1) to a follow-up design pass, since its API is thin enough
   that a real mount panel needs product decisions (e.g. how to present park/tracking state without any Mount
   telemetry getters) not yet made here.
