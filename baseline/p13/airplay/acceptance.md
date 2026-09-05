# P13 AirPlay hardware acceptance — 2026-09-05

Result: **PASS for M-4 physical AirPlay switching on accepted v1/default-off routing**. This does not close other P13 manual gates.

## Hardware and manual assistance

Connected physical iPhone 17 (iOS 27), signed Setu Debug build installed and launched by Xcode. Current Mac AirPlay Receiver was already enabled; its existing same-user/password settings were preserved. Bonjour advertised both AirPlay and RAOP. Actual system output picker identified the current Mac, and AVAudioSession reported AirPlay, independently of Bluetooth.

The user performed exactly the initial iPhone-to-Mac system output selection and confirmed it. That initial transition occurred before the final test launch, so its progress continuity was not captured. All subsequent controls and Mac → iPhone speaker → Mac selections were automated through real SpringBoard controls. No app route override or simulated route notification was used.

## Final execution

`AirPlayHardwareUITests/testPhysicalAirPlayRoundTrip`: 1/1 PASS, zero failures, 364.950 seconds. `xcodebuild` exit 0 and TEST SUCCEEDED.

Local result: `/private/tmp/setu-p13-airplay-hardware-7.xcresult`; runner log: `/private/tmp/setu-p13-airplay-hardware-7.log`. Credential-free fixture telemetry is saved in `hardware-telemetry.jsonl`. Raw system UI captures are not copied into this repository.

Observed transitions (same fixture track 7101 and queue [7101,7102,7103]):

| Route | Before / after AVPlayer seconds | After phase | URL count before / after |
| --- | --- | --- | --- |
| AirPlay → Speaker | 66.502 → 81.801 | playing | 3 → 3 |
| Speaker → AirPlay | 74.377 → 325.403 | playing | 3 → 3 |

Times bracket system UI automation, not AirPlay connection latency measurements. System animation-idle waits account for much of the second interval; no gapless latency claim is made. Route notification counter reached 3. System UI and actual AirPlay port jointly identify the receiver; the optional `targetMac` exact-port-name diagnostic stays false because iOS exposes an aggregate AirPlay port name.

On initial Mac, returned iPhone and second Mac: pause freezes the clock, resume advances it, next changes track identity, previous restores it, seek changes progress, queue remains consistent, phase matches controls, Now Playing title/artist match, enabled 15-minute Sleep Timer survives, loaded LRC active index advances without reparsing during steady playback. Control Center pause/resume also reaches the real remote-command path. Device lock/unlock was not separately tested.

52 samples, no reported playback error; one AVPlayer identity and one mini-player instance throughout. Route switches and idle observation windows cause no additional URL resolution. No app crash or observed retry loop. This is bounded fixture/runtime evidence, not a proof covering arbitrary provider failures or every retry/fallback branch.

## Scope and limitations

All client flags remain false, including v2 playback, lyrics, Home, word-by-word lyrics and in-app AirPlay picker. The fixture uses the accepted v1 MusicClient and a real audible generated PCM file through the actual AVPlayer/audio session. Only explicit DEBUG hardware arguments activate telemetry and test audio. The UITest additionally requires `TEST_RUNNER_SETU_AIRPLAY_HARDWARE=1`; ordinary test runs skip it.

Line-level LRC timing was verified; word-by-word rendering is **not verified in this flags-off run**. Sleep Timer persistence was checked, not its 15-minute expiry. Initial manual connection continuity was not measured; both subsequent transitions were measured. No other P13 manual or 120-Hz acceptance is implied.

Earlier selector attempts failed to locate hidden/renamed system elements. Run 6 successfully switched back to Mac, but its 180-second fixture naturally ended during long system UI waits, invalidating its same-track assertion. Run 7 used a 900-second hardware-only fixture and passed the complete round trip; normal lyrics fixture duration remains 180 seconds.

No backend, FINAL/Frozen, production playback controller or feature flag changes. Existing unrelated user UI edits remain preserved. No full Swift suite rerun for this hardware-only continuation.
