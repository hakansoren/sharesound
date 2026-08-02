# ShareSound — Design Document

**Date:** 1 August 2026
**Status:** Implemented

## Problem

Watching a movie, audio needs to reach two pairs of headphones at once: the user
and the friend beside them are looking at the same screen, each wearing their own
Bluetooth headset. macOS sends audio to a single output.

## Scope

**In:** Simultaneous playback to two or more output devices on the same Mac, in
the same room. Per-device volume control.

**Out:** Streaming to a remote friend over the internet. Hand-tuning the constant
latency offset between devices (a sync slider) — that would require capturing
system audio and running a mixer, which is a much larger program. macOS drift
compensation already closes the gap that opens over time; the remaining constant
offset is accepted.

## Approach

The mechanism is macOS's own: given `kAudioAggregateDeviceIsStackedKey`,
`AudioHardwareCreateAggregateDevice` produces exactly the virtual device that
"Multi-Output Device" in Audio MIDI Setup creates — incoming audio is copied to
every sub-device. The app never processes audio, it only routes it.

Two consequences matter:

- **No TCC permission is needed.** Because audio is never captured, no microphone
  or screen-recording prompt appears; the app works the moment it launches.
- **Drift compensation comes for free.** Every member except the master gets
  `kAudioSubDeviceDriftCompensationKey`, so devices on independent clocks stay
  continuously aligned to the master's.

### Alternatives rejected

| Alternative | Why not |
|---|---|
| Automate Audio MIDI Setup with AppleScript | Depends on UI scripting; breaks on macOS updates |
| Have the user build the device by hand and only select it | The app would add almost nothing |
| Capture audio with Core Audio Taps and write our own mixer | Only needed for the out-of-scope sync slider; unnecessary complexity without it |

## Architecture

Three layers with protocol boundaries between them:

```
ControlPanel (SwiftUI)
        │  reads state, reports intent
        ▼
ShareSessionController            ← all decision logic, knows nothing of CoreAudio
        │  AudioDeviceProviding
        │  AggregateDeviceControlling
        ▼
CoreAudioDeviceProvider / CoreAudioAggregateController
```

Keeping the controller ignorant of CoreAudio is what makes every behaviour
testable without hardware. Tests run against `FakeAudioSystem`, which can connect
and disconnect devices and make any call fail.

### Components

| Component | Responsibility |
|---|---|
| `AudioDevice`, `TransportType` | Device model and connection type |
| `ShareSession`, `SessionState` | Full description of a running share |
| `ShareSoundError` | User-facing error text and severity |
| `ShareSessionController` | Selection, start/stop, rebuild, rollback |
| `CoreAudioBridge` | Swift wrappers over the CoreAudio C interface |
| `CoreAudioDeviceProvider` | Device list, default output, volume, system listeners |
| `CoreAudioAggregateController` | Aggregate creation and removal, leftover cleanup |
| `ControlPanel` and its subviews | The menu bar panel |

## Data flow

**Start:** remember the previous output → create the aggregate (master is a
non-wireless member where possible, since its clock is steadier) → point the
system output at it.

**Stop:** restore the system output to the remembered device → remove the aggregate.

**Rebuild:** when the selection changes or a member disappears, the session is
rebuilt. Order matters: the new device is created and made active first, and only
then is the old one removed — which keeps the audio gap minimal. The pre-sharing
output is carried across rebuilds.

## Error handling

No half-finished state is ever left behind:

- If the aggregate cannot be created, the system is not touched at all.
- If the aggregate is created but the output will not switch, the new device is
  rolled back.
- If a rebuild fails, sharing shuts down and the previous output is restored.
- The aggregate device is removed even when restoring the output fails; otherwise
  an orphaned device would remain in the system.
- If the app crashes, the leftover device is recognised by its UID prefix and
  cleaned up on the next launch.

Errors are split by severity: `informational` (the user can fix it) and
`critical` (a system-level problem). The panel's colour and icon follow.

## Interface

A menu bar app (`LSUIElement`) with no Dock presence, reachable while a movie is
full screen. The visual language is the macOS 26 Liquid Glass material
(`glassEffect`, `GlassEffectContainer`, `.glassProminent`), and all interface text
is English.

**The menu bar panel derives its size from its content.** A `ScrollView` has no
ideal height along its scroll axis, so an unmeasured list makes the panel report a
zero-height list area and no devices appear at all. The list therefore measures
its content and pins a definite height; scrolling stays available once the content
outgrows the cap.

While a shared output is in use the keyboard volume keys never reach the member
devices, so each device's level is exposed separately in the panel — this is the
concrete advantage over a hand-built Multi-Output Device, and the footer caption
says so in one sentence rather than leaving the user to discover it.

Secondary actions (refresh, Sound Settings, quit) sit behind a single overflow
menu so the panel keeps one obvious primary action. A latency note appears when
two wireless devices are selected.

## Tests

51 tests across six suites: device listing and selection, sharing lifecycle,
losing a device, failures and recovery, volume, and model mapping. All of them run
through `FakeAudioSystem` and need no real hardware.

The CoreAudio layer (`CoreAudioBridge` and the two implementation classes) is by
nature bound to system calls and is not unit tested; the parts that need no
hardware — transport type mapping, member count validation — are.
