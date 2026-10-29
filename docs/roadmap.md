# Upcoming features

Planning baseline: **Twinvia 0.9.0 Developer Preview**, reviewed **27 October 2026**. This is a prioritized product backlog, not a release-date commitment. Features described here are not available merely because they appear in this document. The [README](../README.md#features-and-limitations) is the current capability list.

**Planned** means desired product work with a plausible implementation path. **Exploratory** requires a prototype before a delivery commitment. **Platform-blocked** requires capabilities the current supported platform path does not provide. These labels describe intent and constraints, not work already completed.

## First: installation, clipboard, and everyday reliability

| Area | Planned improvement | Completion criteria |
| --- | --- | --- |
| Clipboard onboarding | A Mac setup assistant that detects the phone and installed version, explains shell-helper access, activates the prebuilt helper after explicit USB authorization, and reports actionable failures | A new user can complete setup without a terminal; an already authorized phone can reactivate without rebuilding or changing pairing |
| Clipboard health | Separate transport, permission, lock-state, helper-process and listener status; a visible recovery action | UI distinguishes a disconnected Mac from a missing helper; reconnect/unlock recovers automatically while the helper remains alive; reboot explains why activation is needed |
| Stable distribution | Dedicated Android release signing, Developer ID/hardened/notarized Mac packaging, versioned installers, and verified update delivery | An upgrade preserves app data, permissions where supported, and saved trust; published signatures/checksums are verified; updates cannot install unrelated code |
| Startup and lifecycle | Opt-in Mac launch at login, clearer Android background-service guidance, and broader sleep/Doze/radio recovery validation | Repeated reboot, sleep/wake and out-of-range trials preserve pairing; a stopped or permission-denied component produces an accurate state rather than a false connected indicator |
| Device compatibility | Longer battery/resource trials and an OS/vendor compatibility matrix; investigate Intel/universal Mac builds | Measurements name devices, OS, transport, duration and unplugged power conditions; only tested configurations are advertised |

Clipboard adapter alternatives, including optional Shizuku and an explicit no-helper fallback, remain **exploratory** until tested. A normal foreground service, accessibility permission or device-admin checkbox must not be advertised as universal Android background clipboard access. See [clipboard improvement options](clipboard-sync.md#improvement-options).

## Remote phone-management interface

The existing app already shows phone status, media controls, contacts, call history and shared files. The missing piece is a coherent, permission-aware management workspace with better navigation and, later, optional screen interaction.

### Stage 1 — Unified management workspace: planned

- A resizable SwiftUI phone workspace, alongside the compact menu-bar controls, with overview, contacts, calls, files, notifications, clipboard and permission health in predictable locations.
- Search/filter for contacts and call history, incremental loading, explicit refresh, and useful offline/stale-data indicators. Existing phone-data access remains read-only unless a separately approved editing feature is designed.
- Clear battery/storage/connection information where exposed by Android; indicate missing permission or unsupported data instead of inventing a value.
- Supported app-launch/settings shortcuts where Android permits them, with visible phone-side consent when required. This does not promise arbitrary remote toggling of radios or protected settings.
- Keyboard navigation, VoiceOver labels, responsive layouts, reduced-motion support, and regression checks across macOS Spaces/full-screen applications.

Completion requires reconnect-safe state, permission-revocation handling and command-specific availability. Closing the management window must leave the optional background bridge running; quitting must stop it cleanly.

### Stage 2 — Phone screen viewing: on-demand source prototype; live stream exploratory

The source build now prototypes phone-approved, five-minute on-demand screenshots with a persistent notification and phone-side stop control. It uses Android's public AccessibilityService screenshot capability, with a separate approval for touch input. Lock, disconnect and service revocation end the session. Protected content may remain unavailable. Hardware latency and permission-state regression tests are still required. See [screen-control setup](remote-control.md).

The BLE preview is not an acceptable basis for a usable live desktop stream. A suitable faster, authenticated transport must be implemented and measured first; an optional USB adapter is one candidate. Android's public [MediaProjection](https://developer.android.com/media/grow/media-projection) path remains an option for live streaming and requires user consent per capture session. Public Mac NAN support remains a separate [platform dependency](transports.md).

### Stage 3 — Remote input: basic source prototype; richer input exploratory

The source build adds tap, swipe, explicit text/Enter/Backspace input, Back, Home and opening the notification panel after a separate phone-side control approval. Broader key handling, scroll-wheel gestures and live video remain exploratory. Android accessibility gesture APIs are the input adapter, not a clipboard-reading permission or automatic approval to control the device. See [AccessibilityService](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService).

Screen-view consent and input-control consent must remain separate. An unpaired peer, ended session, locked phone or revoked permission must reject input. Security dialogs and OS restrictions remain authoritative. No silent unlock, password collection, hidden unattended control or private application storage access is planned.

## Sharing and integration backlog

| Area | Missing work | Status / dependency |
| --- | --- | --- |
| Clipboard formats | Android-to-Mac images, MIME negotiation, controlled rich-text handling, optional size/compression choices | Planned after text reliability; URI grants, expiry and payload bounds need design |
| Clipboard controls | Per-direction settings, pause duration, explicit resend, sensitive-content handling, latest-update conflict policy | Planned; optional history must be opt-in with retention and clear/delete controls |
| Files | Sequential queues for selected batches, pause/resume, partial-file cleanup/recovery, overwrite decisions, better progress and completion receipts | Planned; selecting several files or dragging into the current UI does not mean a resumable queue exists |
| File browsing | Search, navigation history, previews/thumbnails and permission-aware shared-folder selection | Planned; rename/delete or other destructive actions require a separate confirmation and conflict design |
| Notifications | Better grouping, richer content where the source supplies it, action/dismiss consistency and optional retained history | Planned; history is opt-in and bounded, source-app capabilities still limit actions |
| System integration | Finder/share-sheet entry points, Android sharing intents for additional formats, clearer keyboard shortcuts and deep links | Planned; retain explicit approval and Android URI permissions |
| Multiple devices | Named trusted devices, intentional active-target selection and individual revoke/unpair controls | Exploratory; prevent clipboard/notification broadcast to every paired device by default |
| Privacy and support | Per-feature permissions, session visibility, safe diagnostic export, documented retention/deletion and troubleshooting | Planned; diagnostics exclude clipboard text, pairing secrets and notification content by default |
| Updates and recovery | Signed GitHub stable update channel, Sparkle and Android system-installer flow are in source builds | Real installation/relaunch and old-preview certificate migration need device validation; see [updates](updates.md). No forced reinstall or trust reset. |

## Calls, messaging, and faster wireless links

- **Calls — exploratory:** improve supported HFP control/routing diagnostics and research a legitimate, reliable two-way audio path. Test answer/end/handoff, mute, disconnect, latency and echo independently. Wi-Fi bandwidth alone does not grant cellular-call audio access. Production Mac call audio is not a committed near-term feature.
- **SMS management — deferred:** current notification replies remain the baseline. A dedicated SMS history/send interface requires a separate Android permission/role and distribution review. Apple Messages integration and registering an Android cellular line in Apple's Phone app have no established supported route here.
- **Wi-Fi Aware/NAN — platform-blocked on the currently documented Mac route:** track the Apple support/feedback discussion and re-evaluate when a supported API, provisioning and compatible hardware exist. Earlier private `wifip2pd` experiments are not a shipping plan.
- **AWDL — exploratory only:** system-managed sharing observations do not establish a public APK data API. Do not schedule a delivery milestone without a supported endpoint and actual application-level interoperability evidence.
- **USB — exploratory:** a separate data adapter could support large files and screen viewing. Current USB clipboard-helper activation is not a USB transport implementation.

The [transport guide](transports.md) explains prerequisites and the dated Apple feedback. No roadmap feature requires disabling Mac system protections or silently switching to a LAN/hotspot/cloud connection.

## Suggested implementation order

1. Clipboard setup assistant, clear health states and reconnect/reboot UX; stable signing and upgrade identity.
2. Unified phone-management workspace, permission controls and searchable phone data.
3. File queues/resume, Android-to-Mac image clipboard and richer explicit sharing.
4. Optional Shizuku proof of concept and faster-transport evaluation, each measured on supported devices.
5. Screen viewing, followed by independently authorized input control, only after transport and platform feasibility pass.

Each item needs appropriate unit/integration checks, real-device permission-denial/reconnect trials, documentation updates and a clear rollback/migration story. Battery, call-audio and live-screen quality require hardware evidence; a passing mock test is not sufficient.
