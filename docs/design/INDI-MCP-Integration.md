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
- Rig **authoring** — creating/editing a rig's component list (add/remove components, assign roles, resolve each
  component to an INDI device name, set role-specific metadata like camera pixel geometry or filter-wheel slot
  names) — is **in scope for Phase 1** (resolved, [I-6](#i-6-is-rig-authoring-in-scope-or-read-only-rig-selection-only--resolved-yes)),
  built on `saveRig`. This is a materially bigger UI surface than "connect and control" — a form/editor over
  `Rig`/`Component`, not just a picker — so it should be scoped as its own chunk of work within Phase 1 rather
  than an afterthought bolted onto the rig picker.
- **Observatory** setup — also in scope for Phase 1, and also a real editor, not just a picker. `Observatory` is a
  distinct concept from `Rig` in INDIMCPKit (`Observatories/Observatory.swift`): a site definition — lat/lon,
  elevation, and an optional horizon-obstruction profile used for visibility checks — with its own
  `listObservatories`/`getObservatory`/`saveObservatory` calls, plus a `draftObservatory()` helper that pre-fills a
  draft from a connected device's live `GEOGRAPHIC_COORD` (e.g. a GPS-capable mount) for the operator to review and
  save, never auto-saved. Both the Rig editor and the Observatory editor/selector need a dedicated UI/UX design
  pass of their own before implementation starts — Don has additional ideas for that pass beyond what's captured
  here, so treat both as **placeholders in this doc, not final specs**, and expect this section to be revised once
  that pass happens.

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

### I-6: Is rig authoring in scope, or read-only rig selection only? — **Resolved: yes, in scope**
`saveRig` exists and Navi's Phase 1 rig UI is not just a picker over rigs authored elsewhere (`INDIMCPKitTestApp`,
hand-edited YAML) — it needs a real editor: add/remove `Component`s, assign each a `Role`, resolve it to an INDI
device name, and set role-specific metadata (telescope aperture/focal length, camera pixel geometry, focuser
travel range, filter-wheel slot names). This is the single biggest unknown left in Phase 1's scope, since none of
that editing surface exists in the mockup or in INDIMCPKit's device model beyond the raw `saveRig(_:overwrite:)`
call — needs UI/UX design (form vs. wizard, how device-name resolution is presented — does Navi query `indiserver`
for currently-visible device names to populate a picker, or is it a free-text field?) before implementation, and
should be estimated/sequenced as its own piece of Phase 1 work rather than folded into "rig picker."

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
mentioned anywhere in INDIMCPKit. Given I-1's resolution (a Pi on the observatory's local network), this is the
expected deployment shape and is fine on a trusted LAN/VPN — but worth stating explicitly as an assumption in this
doc (and in Settings UI copy) rather than silently inheriting it: **do not expose the INDI-MCP endpoint to an
untrusted network**, and don't add a "reach the Pi over the internet" convenience feature (e.g. port-forwarding,
cloud relay) without revisiting this — there's no auth layer to fall back on if the LAN assumption breaks.

### I-11: Version drift — pre-1.0, no changelog
INDIMCPKit tracks INDIMCP-server `0.1.0` and states breaking changes should be expected release-to-release. Worth
a lightweight startup check (`getServerInfo().matchesAlignedVersion`) surfaced as a non-blocking warning banner
("server version doesn't match the kit Navi was built against") rather than skipped — this is exactly the kind of
drift that produces confusing runtime failures otherwise.

## 7. Suggested sequencing

1. **Dedicated design pass for the Rig and Observatory editor/selector UI** (§4) — before any of this is
   implemented. Don has additional ideas for this beyond what §4 currently sketches; this doc's Rig/Observatory
   bullets are placeholders, not a spec, until that pass happens.
2. Add INDIMCPKit as a local package dependency (same pattern as `../AstroKit`).
3. Build `TelescopeSessionManager` with the connect state machine (§3.2) and Settings endpoint field — no UI
   beyond a connect button and status text yet.
4. Wire the rest of the Phase 1 UI (§4) against that manager, using the editor design from step 1; retire the
   mock connection state in `TelescopeControlView`.
5. Wire Camera (§5), including the frame-download/archive-import mini-design from I-2 — likely the largest single
   chunk of new work in this phase.
6. Defer Mount beyond "does the connection work" (see §1) to a follow-up design pass, since its API is thin enough
   that a real mount panel needs product decisions (e.g. how to present park/tracking state without any Mount
   telemetry getters) not yet made here.
