# Test artifact cleanup — 2026-09-06

User instruction: remove confirmed-unneeded test files; document anything left for later cleanup; retain analysis documents rather than raw test products.

Analysis and final tool errors are preserved in acceptance.md. Source worktrees, test code and Frozen fixtures are not temporary test products and were preserved. Shared global Maven/Xcode caches were not touched.

## This Goal — cleanup completed

| Path | Allocated bytes before cleanup | Result |
|---|---:|---|
| `/private/tmp/playback-freshness-calibration.py` | 4096 | removed |
| `/private/tmp/playback3-analyze-memory.py` | 4096 | removed |
| `/private/tmp/playback3-backend-final-targeted.log` | 16384 | removed |
| `/private/tmp/playback3-backend-targeted.log` | 16384 | removed |
| `/private/tmp/playback3-calibration.jsonl` | 4096 | removed |
| `/private/tmp/playback3-deploy-artifact` | 75231232 | removed |
| `/private/tmp/playback3-deployment-conclusion.json` | 4096 | removed |
| `/private/tmp/playback3-deployment-status.json` | 4096 | removed |
| `/private/tmp/playback3-device-build` | 484175872 | removed |
| `/private/tmp/playback3-device-build.log` | 94208 | removed |
| `/private/tmp/playback3-device-diagnostic-build.log` | 36864 | removed |
| `/private/tmp/playback3-device-final-candidate.log` | 61440 | removed |
| `/private/tmp/playback3-device-final-details.json` | 16384 | removed |
| `/private/tmp/playback3-device-final-details.log` | 4096 | removed |
| `/private/tmp/playback3-device-processes.json` | 81920 | removed |
| `/private/tmp/playback3-device-processes.log` | 106496 | removed |
| `/private/tmp/playback3-device-tests-update.log` | 36864 | removed |
| `/private/tmp/playback3-discarded-format-export.log` | 4096 | removed |
| `/private/tmp/playback3-discarded-format-sample.xml` | 40960 | removed |
| `/private/tmp/playback3-docs.py` | 16384 | removed |
| `/private/tmp/playback3-feature-ci-failed.log` | 208896 | removed |
| `/private/tmp/playback3-final-physical-build.log` | 32768 | removed |
| `/private/tmp/playback3-frozen-verification.json` | 4096 | removed |
| `/private/tmp/playback3-http` | 24576 | removed |
| `/private/tmp/playback3-instruments-device-options.json` | 4096 | removed |
| `/private/tmp/playback3-instruments-options.json` | 4096 | removed |
| `/private/tmp/playback3-instruments-templates.log` | 4096 | removed |
| `/private/tmp/playback3-ios-final-full.log` | 90112 | removed |
| `/private/tmp/playback3-ios-final-targeted.log` | 24576 | removed |
| `/private/tmp/playback3-ios-targeted.log` | 24576 | removed |
| `/private/tmp/playback3-m13-app-instruments.log` | 4096 | removed |
| `/private/tmp/playback3-m13-app-toc-export.log` | 4096 | removed |
| `/private/tmp/playback3-m13-app-toc.xml` | 16384 | removed |
| `/private/tmp/playback3-m13-app.trace` | 22822912 | removed |
| `/private/tmp/playback3-m13-discarded-export.log` | 4096 | removed |
| `/private/tmp/playback3-m13-discarded-toc.xml` | 20480 | removed |
| `/private/tmp/playback3-m13-finalizing-sample-command.log` | 4096 | removed |
| `/private/tmp/playback3-m13-finalizing-sample.txt` | 237568 | removed |
| `/private/tmp/playback3-m13-instruments.log` | 4096 | removed |
| `/private/tmp/playback3-m13-network-current.csv` | 4096 | removed |
| `/private/tmp/playback3-m13-network-progress.csv` | 4096 | removed |
| `/private/tmp/playback3-m13-normal-app.log` | 45056 | removed |
| `/private/tmp/playback3-m13-normal-app.xcresult` | 591151104 | removed |
| `/private/tmp/playback3-m13-open-files.txt` | 20480 | removed |
| `/private/tmp/playback3-m13-options-error.log` | 0 | removed |
| `/private/tmp/playback3-m13-recording-options.json` | 4096 | removed |
| `/private/tmp/playback3-m13-runner-pause.json` | 4096 | removed |
| `/private/tmp/playback3-m13-runner-resume.json` | 4096 | removed |
| `/private/tmp/playback3-m13-sample-command.log` | 4096 | removed |
| `/private/tmp/playback3-m13-tool-current.log` | 4096 | removed |
| `/private/tmp/playback3-m13-tool-errors.log` | 8192 | removed |
| `/private/tmp/playback3-m13-xctrace-sample.txt` | 225280 | removed |
| `/private/tmp/playback3-m13.trace` | 763805696 | removed |
| `/private/tmp/playback3-manual-handoff-build.log` | 32768 | removed |
| `/private/tmp/playback3-manual-lockscreen.log` | 8192 | removed |
| `/private/tmp/playback3-manual-lockscreen.xcresult` | 757760 | removed |
| `/private/tmp/playback3-real-fm-diagnostic-active.log` | 20480 | removed |
| `/private/tmp/playback3-real-fm-diagnostic-active.xcresult` | 118784 | removed |
| `/private/tmp/playback3-real-fm-diagnostic.log` | 8192 | removed |
| `/private/tmp/playback3-real-fm-diagnostic.xcresult` | 114688 | removed |
| `/private/tmp/playback3-real-fm.log` | 16384 | removed |
| `/private/tmp/playback3-real-fm.xcresult` | 135168 | removed |
| `/private/tmp/playback3-real-smoke.log` | 12288 | removed |
| `/private/tmp/playback3-real-smoke.xcresult` | 118784 | removed |
| `/private/tmp/playback3-real-ui-runner-restored.log` | 8192 | removed |
| `/private/tmp/playback3-real-ui-runner-restored.xcresult` | 163840 | removed |
| `/private/tmp/playback3-real-ui.log` | 4096 | removed |
| `/private/tmp/playback3-real-ui.xcresult` | 114688 | removed |
| `/private/tmp/setu-p11-main/.build` | 1327091712 | removed |
| `/private/tmp/setu-playback-backend-3/target` | 8314880 | removed |
| `/private/var/folders/63/nyv2g4h165x15z2xvr03hv6w0000gn/T/instruments5HWHuF.ktrace` | 13102350336 | removed |
| `/private/var/folders/63/nyv2g4h165x15z2xvr03hv6w0000gn/T/instrumentsTn8mMS.ktrace` | 19173085184 | removed |

Removed 72 generated paths; pre-cleanup allocated size total 35551260672 bytes. This sum is an artifact-size accounting, not a guaranteed filesystem free-space delta.

## Earlier artifacts — cleanup pending

These earlier artifacts were not removed because exact ownership or the remaining evidence dependency was not confirmed. Review their existing analysis/documents before deletion. Do not reopen or repeat P13 acceptance merely to clean files.

| Path | Allocated bytes | Pending condition |
|---|---:|---|
| `/private/tmp/p13-activate-current.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-after-next-lock.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-after-next-lock.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-create-export.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-create-wired-images` | 16789504 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-create-wired.log` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-create-wired.xcresult` | 16105472 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-current-app-match.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-current-app-match.png` | 2068480 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-current-device.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-current-device.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-current-processes.json` | 81920 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-details-current.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-details-current.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-read.log` | 98304 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-readiness-current.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-readiness-current.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-recheck.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-recheck.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-resume-check.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-device-resume-check.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-final-instruments-devices.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-frame-extract.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-local-layout-build.log` | 49152 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-after-6.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-after-6.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-after-7.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-after-7.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-artwork-a.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-artwork-a.png` | 10543104 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-artwork-b.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-artwork-b.png` | 10842112 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-artwork-c.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-artwork-c.png` | 45056 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-during-2.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-during-2.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-during-6.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-during-6.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-during-7.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-during-7.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-observation-1.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-observation-1.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-observation-2.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-observation-2.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-observation-3.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-observation-3.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-observation-4.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-observation-4.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-resume-7.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-resume-7.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-resume-8.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-resume-8.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-session-during.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-session-during.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-unlocked-confirm.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-lock-unlocked-confirm.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-additional-1.log` | 65536 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-additional-1.xcresult` | 47095808 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-additional-images` | 47009792 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-additional-images.log` | 8192 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-audits-1.log` | 167936 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-audits-1.xcresult` | 84672512 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-audits-2.log` | 86016 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-audits-2.xcresult` | 68972544 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-daily-activities.json` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-final-modals-export.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-final-modals-images` | 43175936 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-final-modals.log` | 86016 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-final-modals.xcresult` | 41517056 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-history-icons-images` | 5529600 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-history-icons-images.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-history-icons.log` | 45056 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-history-icons.xcresult` | 5541888 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-history-wrap-images` | 12312576 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-history-wrap-images.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-history-wrap.log` | 45056 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-history-wrap.xcresult` | 12324864 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-images` | 71929856 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-images-export.log` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-navigation-build.log` | 40960 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-navigation-final.log` | 57344 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-navigation-final.xcresult` | 79409152 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-navigation-images` | 79470592 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-navigation-images.log` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-recommended-expanded.log` | 69632 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-recommended-expanded.xcresult` | 2674688 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-recommended-final-images` | 3731456 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-recommended-final.log` | 53248 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-recommended-final.xcresult` | 2957312 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-results.json` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-submit-fix.log` | 114688 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-submit-fix.xcresult` | 56733696 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-submit-images` | 61833216 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m11-submit-images.log` | 8192 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m9-export-final.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m9-export.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m9-formal-1.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m9-formal-pid.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m9-formal-pid.trace` | 40960 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m9-launch.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-m9-launch.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-manual-lock-confirm.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-manual-lock-confirm.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-manual-remote-telemetry.jsonl` | 643072 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-manual-remote-window.log` | 8192 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-manual-remote-window.xcresult` | 159744 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-normal-capture.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-normal-launch.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-normal-screen.png` | 1830912 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-notification-isolated.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-previous-lock.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-previous-lock.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-process-check.json` | 81920 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-process-check.log` | 106496 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-caption-export.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-caption-images` | 7376896 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-caption.log` | 69632 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-caption.xcresult` | 7831552 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-closure-images` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-closure.log` | 57344 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-closure.xcresult` | 372736 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-export.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-unlocked.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-unlocked.xcresult` | 110592 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-wired-images` | 13611008 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-wired.log` | 8192 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-queue-wired.xcresult` | 14045184 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-real-app-capture.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-real-app-playing.png` | 1806336 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-real-artwork-prep.log` | 49152 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-real-artwork-prep.xcresult` | 3215360 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-recommended-final-export.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-reconnected.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-reconnected.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-remaining-full-once.log` | 86016 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-remaining-remote-prep.log` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-remaining-remote-prep.xcresult` | 167936 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-remote-prep-build.log` | 40960 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-remote-remaining.jsonl` | 331776 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-runner-uninstall.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-system-display-1.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-system-display-1.png` | 1806336 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-three-lock.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-three-lock.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-usb-current.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p13-usb-recheck.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-app-before-runner-extension.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-clang-cache` | 704512 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-controls-runner-build.log` | 32768 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-destinations.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-development-device.log` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-development-device.xcresult` | 118784 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-development-entry-diagnostic.log` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-development-entry-diagnostic.xcresult` | 180224 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-development-entry.log` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-development-entry.xcresult` | 176128 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-blocked-audit.json` | 8192 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-blocked-audit.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-now.json` | 8192 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-now.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-recheck.json` | 8192 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-recheck.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-resumed.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-resumed.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-tests-only-intermediates` | 99487744 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-device-tests-project.json` | 106496 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-direct-install.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-direct-launch.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-fm-live-after-deploy.log` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-fm-live-after-deploy.xcresult` | 118784 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-full-once.log` | 86016 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-installed-app.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-instrument-templates.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-live-device-code-build.log` | 32768 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-live-device-tests-build.log` | 442368 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-live-device-tests-link.log` | 20480 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-live-runner-build.log` | 155648 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-live-runner-diagnostic-build.log` | 32768 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-live-runner-only.log` | 65536 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-m13-devices.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-m13-templates.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-playback-diagnostic-build.log` | 61440 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-playback-diagnostic-intermediates` | 79036416 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-playback-diagnostic-run.log` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-playback-diagnostic.xcodeproj` | 208896 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-playback-diagnostic.xcresult` | 122880 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-destinations.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-device-project-archive.xcodeproj` | 212992 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-device.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-device.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-export.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-final-probes.log` | 20480 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-final-probes.xcresult` | 225280 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-normal-launch.json` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-runner-install.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-runner-project-archive.xcodeproj` | 212992 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-serial-diagnostics` | 24576 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-serial.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-serial.xcresult` | 110592 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-usb-device.json` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-usb-device.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-usb.log` | 90112 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-reaccept-usb.xcresult` | 8093696 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-runner-console.json` | 0 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-runner-diagnostics` | 24576 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-runner-only-intermediates` | 61693952 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-runner-project.json` | 106496 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-targeted-final.log` | 20480 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-targeted-native.log` | 16384 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-targeted-verified.log` | 12288 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-targeted.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-ui-attachments` | 1908736 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-ui-export.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-ui-final.log` | 4096 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-ui-final.xcresult` | 110592 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-ui-once.log` | 344064 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/tmp/p14-ui-once.xcresult` | 180224 | Confirm ownership and that existing analysis makes raw artifact unnecessary |
| `/private/var/folders/63/nyv2g4h165x15z2xvr03hv6w0000gn/T/instrumentsGN7mtX.ktrace` | 1478492160 | Confirm ownership and that existing analysis makes raw artifact unnecessary |

Pending earlier paths: 218; allocated size total 2572005376 bytes.

## Retained permanent results

- acceptance.md: implementation, validation, deployment binding, real FM findings and the explicit M-13 blocker.
- cleanup.md: this deletion and pending-cleanup record.
- Frozen fixtures and test/source code remain reproducible repository assets; they were not deleted.
- No current-Goal raw trace, xcresult, screenshot, downloaded deployment JAR or build tree is intentionally retained.
