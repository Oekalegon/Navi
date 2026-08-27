# INDI-MCP Integration — Design Document

Status: **Draft** — Phase 1 scoping
Owner: Don Willems
Related: [NAVI-42](.), `Navi/TelescopeControl/*` (static mockup, precedes this doc), INDIMCPKit (`/Users/donwillems/Personal/Development/INDIMCPKit`), INDIMCP-server (`/Users/donwillems/Personal/Development/INDIMCP-server`)

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
  relationship to it beyond talking to its HTTP endpoint. See open issue [I-1](#i-1) — whether Navi ever needs to
  launch this process itself, or always connects to one that's already running.
- Because it's HTTP, the server the user talks to could be **on the same Mac, on a Mac mini at the telescope, or
  anywhere reachable on the local network** — the endpoint is user/observatory-configured, not hardcoded.

### 3.2 Session/service layer

Following the existing pattern of a single owning manager per subsystem (`ArchiveManager`, `SettingsManager`), this
introduces one new `@Observable` singleton-ish service, tentatively `TelescopeSessionManager` (owned the same way
`ArchiveManager` is — created once, referenced by panes, not one instance per pane/window):

- Owns the `INDIMCPClient` instance and its connection state (`.disconnected` / `.connecting` / `.connected(...)`
  / `.error(...)`).
- Owns the connect sequence's state machine: MCP connect → `getINDIServerStatus`/`startINDIServer` →
  `startINDIMessaging` → `listRigs`/`getRig`/`checkRig`. Exposes this as a small number of observable states the
  UI can render as a progress list ("Connecting…", "Starting INDI server…", "Starting messaging…", "Ready"),
  because failures at each step throw differently (see [I-4](#i-4)) and a flat "connected: Bool" would hide where
  a startup actually failed.
- Owns the active `Rig` selection and the `ObservableDevice` instances for whichever roles the current UI needs
  (mount/camera/filter wheel), so two panes/windows showing telescope control share one live subscription per
  device rather than each spinning up its own poll+stream (see [I-8](#i-8)).
- Single choke point for hardware commands, so two panes can't independently fire conflicting commands (e.g. two
  concurrent `slew` calls) — see [I-9](#i-9).

### 3.3 Pane integration

Following [Panel Architecture] conventions: a new `PaneType.telescopeControl` case, `PaneManager.showTelescopeControl()`
following the `showArchiveViewer`/`showFITSViewer` pattern, a toolbar toggle, and a `PaneCloseButton`. The pane
hosts `TelescopeControlView` (already exists as the mockup's tab shell) which reads from `TelescopeSessionManager`
via environment rather than owning its own mock state.

Pane lifecycle matters here in a way it didn't for the archive/FITS panes: closing the pane should call
`ObservableDevice.stop()` (or have `TelescopeSessionManager` reference-count and stop only when the last consumer
goes away) — an `ObservableDevice` left running leaks a live MCP resource subscription and a periodic resync timer.

## 4. Phase 1 scope — observatory/rig setup, server & driver lifecycle

UI surface (new, not in the current mockup — the mockup starts *after* a rig is already connected):

- **Endpoint configuration** — extend `SettingsManager` with an INDI-MCP endpoint URL (plain `UserDefaults`, not
  Keychain — it's a URL, not a secret, same tier as `archivePath`/`dataPath`).
- **Connection control** — Connect/Disconnect, with the staged status list described in §3.2.
- **Server control** — start/stop/restart `indiserver`, showing `IndiServerStatus.running`/`.port`.
- **Driver list** — `listINDIDriverCatalog()` (all installed drivers) vs. `listRunningINDIDrivers()` (currently
  running), with per-driver start/stop.
- **Rig picker** — `listRigs()` → `RigSummary` list → select → `getRig(id:)` for the full `Rig` → `checkRig(id:)`
  to show which declared components are actually present/connected, surfaced as a per-component badge (this maps
  directly onto the mockup's `ConnectionBadge`/`DeviceStateBadge` components already in
  `TelescopeControlComponents.swift`).
- Rig **authoring** (creating/editing a rig's component list) is explicitly **not** in Phase 1 scope — see
  [I-6](#i-6).

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

### I-1: Does Navi ever launch INDIMCP-server itself?
`startINDIServer`/`stopINDIServer` control **`indiserver`**, a process the *already-running* INDIMCP-server
manages. They say nothing about the INDIMCP-server process itself — if it's not running, `INDIMCPClient.connect()`
just fails to reach the endpoint. Decide: is the INDIMCP-server assumed to be a standing service on the observatory
host (Navi only ever connects to a URL, full stop), or does Navi need a "start remote/local server" story too
(e.g. SSH-launch, or a bundled local instance for a single-Mac setup)? This changes what "Connect" even means in
the UI and whether there's a process-management surface beyond `indiserver`/drivers.

### I-2: Where do downloaded frames live, and how do they join the Archive?
`downloadFrame` writes to a caller-supplied local `URL`. Need: a storage location decision consistent with
`SettingsManager.dataPath`/security-scoped bookmarks, a dedupe/naming scheme, and a decision on whether captured
frames auto-import into the Archive or require a user action (the existing Archive flow is explicitly
"button-driven, not automatic" per [Panel Architecture] — probably the same philosophy applies here, but worth
confirming since a capture session could produce dozens of frames unattended).

### I-3: Progress model for capture and slew — polling vs. streaming, and how far Navi commits to it
Every hardware command is fire-and-return-runId. Navi needs a consistent pattern (probably `scriptEvents` as the
live feed, with `waitForTerminalStatus` or a resync timer as the fallback/catch-up path, mirroring what
`ObservableDevice` already does internally for messaging) used uniformly across capture, slew, cooling-wait, etc.,
plus cancellation semantics tied to view lifecycle (task cancelled on pane close mid-capture — does the exposure
keep running server-side? almost certainly yes, so the UI must be able to re-attach to an in-flight `runId` rather
than assuming a fresh pane means no capture is running).

### I-4: Error surface is split across three channels — needs one Navi-side model
`INDIMCPClientError` (transport/tool-call rejection), `DeviceControlError` (client-side pre-flight), and
`ScriptRunStatus.failed` (mid-run failure, not a thrown error at all) all need to collapse into whatever Navi
already uses for surfacing errors to the user (toasts? inline banners? — check existing pattern, e.g. how
`ArchiveTableView`/`ArchiveFilterSheet`'s currently-silent `catch {}` blocks were flagged in `code-review.md` as a
quality issue). A lost MCP connection specifically does **not** have a dedicated error case — it surfaces as
whatever the underlying `swift-sdk` transport throws, so Navi's catch sites need to treat "any Error" as a possible
disconnect, not just the two named enums.

### I-5: No auto-reconnect, no request timeout — both are Navi's responsibility
`INDIMCPClient` has no built-in reconnect/backoff and is single-use after `disconnect()` ("create a new one").
There's also no exposed HTTP request timeout, so a hung request can hang indefinitely. `TelescopeSessionManager`
needs to own both: a reconnect policy (manual button vs. automatic with backoff — for a live device-control app,
silent auto-reconnect while a slew is in progress seems risky; leaning toward user-visible "Reconnect" rather than
automatic) and a timeout wrapper (race every `async throws` call against a `Task.sleep`) around commands so the UI
never spins forever on an unresponsive server.

### I-6: Is rig authoring in scope, or read-only rig selection only?
`saveRig` exists but Phase 1 above scopes only listing/selecting an existing rig. If rigs are currently authored
via `INDIMCPKitTestApp` or hand-edited YAML on the server, confirm that stays true for the foreseeable future —
otherwise Phase 1's UI needs a rig editor, which is a much bigger surface (component list, role assignment, device
name resolution) than "connect and control."

### I-7: `INDI messaging` sequencing is a foot-gun
Several calls (`ensureConnected`, `checkRig`, `getDeviceProperties`) fail with a generic `toolCallFailed` — not a
distinct "messaging not started" error — if `startINDIMessaging()` hasn't run yet. The connect state machine in
§3.2 needs to make this an explicit, ordered step (and probably retry/prompt specifically when a failure pattern
looks like "messaging not running" rather than surfacing a raw tool-call error string to the user).

### I-8: One shared device session across panes/windows, not one per view
Navi supports multiple windows, and per [Panel Architecture] a pane type can appear in more than one window.
`ObservableDevice` is `@MainActor` and cheap to create, but nothing stops two independent instances for the same
rig+role from each polling and subscribing separately — wasteful, and worse, doubles the "harmless no-op" surface
if both independently retry something. `TelescopeSessionManager` (§3.2) should own one `ObservableDevice` per
role and let multiple panes observe the same instance, matching how `WindowRegistry`/`PaneManager` already
centralize state rather than duplicating it per pane.

### I-9: Command serialization — prevent two panes issuing conflicting hardware commands
Nothing in INDIMCPKit itself prevents concurrent `slew`/`captureFrame`/etc. calls to the same device from two call
sites. With a single shared session (I-8) this is mostly solved by construction (one owner, one place commands
originate), but worth an explicit rule: hardware-command methods live only on `TelescopeSessionManager`, views
never hold a `Mount`/`Camera` handle directly and call it themselves.

### I-10: Security posture of the HTTP endpoint
Both the MCP tool-call transport and frame download are plain HTTP with `URLSession` defaults — no TLS, no auth
mentioned anywhere in INDIMCPKit. Fine on a trusted local network (Mac ↔ Mac-mini-at-the-telescope on the same
LAN/VPN), but worth stating explicitly as an assumption in this doc (and in Settings UI copy) rather than silently
inheriting it: **do not expose the INDI-MCP endpoint to an untrusted network**, and don't add a "remote over the
internet" convenience feature without revisiting this.

### I-11: Version drift — pre-1.0, no changelog
INDIMCPKit tracks INDIMCP-server `0.1.0` and states breaking changes should be expected release-to-release. Worth
a lightweight startup check (`getServerInfo().matchesAlignedVersion`) surfaced as a non-blocking warning banner
("server version doesn't match the kit Navi was built against") rather than skipped — this is exactly the kind of
drift that produces confusing runtime failures otherwise.

## 7. Suggested sequencing

1. Resolve I-1 (deployment model) and I-6 (rig authoring scope) first — both change what Phase 1's UI actually
   needs to contain.
2. Add INDIMCPKit as a local package dependency (same pattern as `../AstroKit`).
3. Build `TelescopeSessionManager` with the connect state machine (§3.2) and Settings endpoint field — no UI
   beyond a connect button and status text yet.
4. Wire the Phase 1 UI (§4) against that manager; retire the mock connection state in `TelescopeControlView`.
5. Wire Camera (§5), including the frame-download/archive-import mini-design from I-2 — likely the largest single
   chunk of new work in this phase.
6. Defer Mount beyond "does the connection work" (see §1) to a follow-up design pass, since its API is thin enough
   that a real mount panel needs product decisions (e.g. how to present park/tracking state without any Mount
   telemetry getters) not yet made here.
