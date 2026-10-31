# Tiger Video Edit 3.0.0+3004 — local release candidate

Branch: `feature/tiger-3.0`, baseline commit `6f1e510`. The existing v2 application/data and LICENSE were preserved; no public repository or release was created. Read docs/V3_IMPLEMENTATION_PLAN.md and docs/V3_COVERAGE.md for the full migration scope.

Verified before migration: 45/45 root tests, clean analyzer. New targeted checks cover schema migration, effect pixels/curves, service failures/checksums, navigation/unsaved guards, template files, audio mixing and settings/selection regressions. A native Windows v3 export passed twice: H.264/AAC, 854×480/24FPS/36frames/1.5s; preview-vs-output RGB MAE 1.384/255, actual layered effects/transition/overlay/Cyrillic caption/SFX and cancellation preservation. See docs/V3_NATIVE_EXPORT_CHECK.md. Final whole-suite and packaged artifact results will be added after integration.

Final application checkpoint: **119/119 root tests passed; flutter analyze reports No issues found.** Tool tests 2/2 pass. All three workflow YAML documents parse using the existing Flutter SDK YAML parser; official SDK tag 3.47.8 resolves to the pinned commit. Actual GitHub runner execution still awaits approved publication. Native v3 UI screenshots and interaction capture passed using an isolated temporary library: docs/V3_HOME.png, V3_EDITOR.png, V3_PHONE.png. The final build counter changed from 4 to **3004** because the old distributed ARM64 split APK has versionCode 2003; the legacy and current test signing certificate fingerprints match. Final packages will be rebuilt with 3004.

Intermediate Android debug v3.0.0+4 compiled and ZIP/ARM64-only/debug-signature/manifest checks passed; this is TEST-debug, not production signing and not physical-device acceptance. Windows v3 native close-handshake compiled; final integrated installer is being prepared.

External production gates: owner approval for source/release publication and inherited-license/native-source review; production Android signing; real GitHub Actions runs and clean-device acceptance; Jamendo agreement for an activated online provider. Local music/SFX/edit/export remain offline. Nothing behind these gates is claimed complete.

---

# Historical Tiger Video Edit 2.0.0 status

First functional v2 release of all three user-selected blocks is implemented and packaged. Existing 1.0.1 artifacts are preserved. The remaining original roadmap is not claimed complete.

## New deliverables

- `dist/TigerVideoEdit-2.0.0-Windows-x64-Setup.exe` — 112,112,329 bytes; Release x64 app and native runtimes, original v1/v2 demos. Real Inno Setup build passed.
- `dist/TigerVideoEdit-2.0.0-Android-arm64.apk` — 25,852,805 bytes; release-mode APK, v2 signature verified, application label Tiger Video Edit, version 2.0.0 / versionCode 2003, ARM64 only, min API24 / target36. Local debug signing identity, device acceptance pending.
- `demo/Pulse-v2.tve`, `motion.mp4`, `motion.gif`, original images/music; `demo/Pulse-v2.mp4` is an actual verified 10-second H.264/AAC 1920×1080, 30 FPS, 300-frame output.
- `docs/WINDOWS_V2_PREVIEW.png` — native integration screenshot; `docs/V2_GUIDE_RU.md` — feature guide.
- `dist/ARTIFACTS.json` — exact sizes/SHA256; latest=true marks v2 binaries.

## Implemented and checked

- Per-item Shake, Zoom, Blur, Glow, Flash, RGB Split and Glitch; combinations, strength, duration, built-in and persisted named custom presets, apply-to-all.
- Shared deterministic Canvas compositor for preview/export; timed captions with text, source time range, normalized position, size and color. Half-open caption intervals.
- Local amplitude-onset/tempo analysis, sensitivity, result confirmation and automatic marker assembly respecting trim. No fabricated silence grid. One-step undo restores previous markers.
- Mixed images, video and GIF; per-item source offset, looping, correct rotated video dimensions, video source audio excluded.
- Schema v2 saves effects/captions/clip metadata and reads schema v1. `.tve` remains the extension and `.leos` remains readable.
- Animated export renders each frame and encodes with FFmpeg on Windows or the existing native Media3 encoder on Android. Static projects keep the previous fast path. Progress/cancellation/temp cleanup retained.

## Verification evidence

- Full `flutter test`: **45/45 passed**.
- Full `flutter analyze`: **No issues found**.
- Native Windows integration: **3/3 passed**, including v2 video/GIF preview, real audio analysis and marker assembly, undo, v2 save/reopen, production bootstrap and G/pause/seek workflow.
- Actual v2 MP4 integration checks caption pixels and H.264/AAC/duration. Original v1 export and cancellation regressions remain green.
- Original v2 demo export passed; ffprobe confirms 300 frames / 10.000000s / H.264 + AAC / 1920×1080 / 30 FPS. This machine took about 2m37s to render that 10-second dynamic demo.
- Real decoder tests cover GIF/video seek/loop, 25 FPS tail EOF, phone-style rotation metadata, byte-for-byte sequential/direct/backward frame equivalence with fixed one-second seek anchors, missing/malformed sources.
- Independent review found four issues: tail-frame EOF, rotated video aspect, stale paused offset preview and beat analysis retained after audio undo. All were fixed with regressions. Follow-up bounded decoder discard to <=29 normalized frames per seek anchor; FFmpeg input seeks still depend on keyframe distance.
- Windows Release + actual installer compilation passed. A same-payload isolated installer with separate GUID and `.tve-smoke-v2` association passed **install / registration / launch / bundled FFmpeg / uninstall**. The real installed Tiger Video Edit 1.0.1 was left unchanged; user can run the new setup to update it.
- Android APK build and signature/ABI/name verification passed. No physical Android device or emulator available: actual system decode, SAF, encoder, output frame alignment and touch workflows are not asserted verified.

## Real limits and next work

- Dynamic export writes temporary 1080p PNG frames before encoding, so it is slower and needs significant disk space. Long/detailed projects can require gigabytes. Preview follows audio time but may drop displayed video frames on slow decoding; export renders every output frame.
- Beat detection is a local amplitude-onset heuristic. Strong nonmusical transients, irregular music and half/double tempo can need manual corrections. Marker timing/capture precision is unchanged.
- Android runtime/device acceptance remains required, especially Media3 one-frame-image sequencing, system video codecs and SAF output save/cancel.
- Manual file-dialog/drag workflows and clean-machine Windows checks from v1 still remain; native/core automated checks do not replace every manual acceptance step.
- Other roadmap items (multiple audio tracks, online music sources, arbitrary output formats, playback speed, extended templates) were outside the three selected blocks and remain future work. No placeholder controls added for them.
- No public upload/release performed. Existing dependency/source, Inno Setup commercial-use and production-signing requirements remain in docs/THIRD_PARTY.md.

## Resume

Use root `flutter test`, `flutter analyze`, `tools/build-windows.ps1`. Native tests are in `native_test`. See docs/V2_PLAN.md and docs/V2_GUIDE_RU.md. Do not overwrite the user's installed app during smoke tests; use the isolated test recipe in .tools if needed.

---

# Historical version 1.0.1 record
# Tiger Video Edit 1.0.1 — rebrand

Current name: **Tiger Video Edit**. New project extension: **.tve**. Legacy .leos opens; saving creates a .tve sibling and preserves the original. Windows retains an existing legacy library so imported media and recent projects remain accessible. Android application ID and Windows installer identity remain stable for upgrades. Native media channel, Dart package, EXE, app label, icon and demo are updated. Windows installer registers .tve opening with Tiger Video Edit. Release installer compiled successfully. Your installed Leos 1.0.0 was detected and left unchanged. An isolated installer variant with a different GUID and .tve-smoke association passed install, association registration, launch, bundled FFmpeg and uninstall checks using the same Release payload. The actual .tve association is included in the release installer; installing that update is left to you. Android device acceptance remains pending.

## Verification record — 2026-10-29

Tiger Video Edit 1.0.1 implemented and packaged. Windows automated acceptance completed for the core workflow; Android APK built but device acceptance remains outstanding. Version 2.0 was explicitly authorized and is in progress; see docs/V2_PLAN.md.

## Deliverables

- `dist/TigerVideoEdit-1.0.1-Windows-x64-Setup.exe` — real Inno Setup installer, new branded build (exact size in dist/ARTIFACTS.json). Release x64 app, libmpv, FFmpeg/ffprobe and all shared DLLs, app-local Visual C++ runtime, license notices and original demo.
- `dist/TigerVideoEdit-1.0.1-Android-arm64.apk` — real release-mode APK, ARM64 only, Android API 24 minimum / target 36. Local debug signing key for sideload testing; not a public production signing identity.
- `demo/Pulse.tve`, three PNGs, original synthetic WAV, and verified `demo/Pulse.mp4`.
- `docs/WINDOWS_PREVIEW.png` — screenshot rendered by native Flutter integration test.
- `README.md` — usage, recovery, build and test commands; `docs/THIRD_PARTY.md` — dependency/source/license inventory.

## Actual verification

- `flutter test`: **22/22 passed** (last complete run in Windows packaging pipeline).
- `flutter analyze`: **No issues found**.
- Native Windows test: **2/2 passed** in isolated `native_test`: production bootstrap, real libmpv playback, G capture, pause/seek, save/reopen and rendered screenshot.
- Original demo render: **passed**; ffprobe confirms H.264, AAC, 1920×1080, 30/1 FPS, 10.000000 seconds.
- Real export tests inspect frames 15 and 16 around a non-frame-aligned marker, verify H.264/AAC/duration, waveform, missing/corrupt inputs, and cancellation without overwriting an existing file.
- Storage tests verify validated staging, previous-good backup, corrupt JSON handling and separate autosave. Controller tests reproduce/fix first-autosave recovery, save/switch race and audio/selection synchronization after Undo.
- Windows release build: **passed**. Inno Setup compilation: **passed**.
- `tools/test-installer.ps1`: **INSTALL / LAUNCH / BUNDLED FFMPEG / UNINSTALL: PASS**, in `.tools/install-check`. Installed app remained running; installed FFmpeg executed with app-local DLLs; normal uninstaller removed the EXE. No Flutter SDK is included or needed at runtime. A clean second Windows machine was not available.
- Android ARM64 release build: **passed**. `apksigner verify`: **verified, v2 signature**. `aapt`: only `arm64-v8a`, minSdk 24, targetSdk 36, version 1.0.1 / split versionCode 2002. No INTERNET or broad storage/media permission. Manifest has normal ACCESS_NETWORK_STATE, WAKE_LOCK and app-private receiver permission from dependencies.
- `adb devices`: no device attached. Android playback/export/SAF/touch interaction have **not** been verified on a device or emulator.
- Windows computer-use screenshot capture failed twice (`FrameArrived timed out` / `window capture timed out`). No claim of successful manual visual testing via that helper. Native integration independently rendered and saved the UI screenshot.

## Platform acceptance against the requested 12-step workflow

| Requirement | Windows evidence | Android evidence |
|---|---|---|
| Install | Silent install + normal uninstall passed | Signed APK built; not installed on device |
| Create project | Controller regression tests; native home bootstrap | Shared logic tested, device UI pending |
| Load music | Native WAV open/play/seek passed; file picker built, manual picker flow not exercised | Build only; device codecs/picker pending |
| Add/order images | Shared model, real decoder/render and native project load tested; drag/picker manual flow pending | Shared logic tested; touch/picker pending |
| Play | Real Windows libmpv tested | Device test pending |
| Press G / touch marker | Real G event during music tested | Touch/device test pending |
| View markers | Native rendered screenshot + adaptive widget tests | Phone-size widget layout tested; device pending |
| Move/delete markers | Controller/history tests; numeric editing implemented; mouse drag manual test pending | Shared editing tested; touch drag pending |
| Preview automatic edit | Native playback and shared frame-schedule tests passed | Device synchronization pending |
| Export MP4 with sound | Actual FFmpeg output, codec/duration/frame checks passed | Media3 adapter compiled; device encoder/export pending |
| Save project | Safe storage + native save passed | Shared storage tested; device pending |
| Reopen project | Native save/reopen times preserved | Shared JSON tested; device pending |

## Architecture and operational details

- Flutter 3.47.8 / Dart 3.13.7; exact Dart dependencies in pubspec.lock.
- Absolute audio timestamps stored as integer microseconds; numerical editor shows milliseconds. Capture reads player time, not an invented timer. Playback position polling reads the player every 16 ms; physical input/output accuracy is not guaranteed at 1 ms.
- One normalized 30 FPS schedule drives both preview and export. Duplicate positions collapse only for rendering; subframe cuts resolve on frame boundaries without zero-duration segments.
- Preview preloads up to 16 screen-resolution images; active widget owns a clone. Full-resolution Canvas transformation is shared with output PNG preparation. Very large libraries and rapid cuts exceeding the cache need stress testing.
- Windows uses verified upstream libmpv 20261021/e471496c56, not the legacy 2023 package binary. FFmpeg installed build N-124557-g9e71ea2d60-20260520 is GPLv3 with libx264.
- Android uses media_kit native audio and Media3 1.11.1 Transformer/MediaCodec; checks H.264/AAC encoder availability, handles errors/cancel, validates MP4 tracks and duration, saves through SAF.
- Native tests are a separate `native_test` Flutter host referencing the app source. Keeping integration_test in the production project's dev dependencies triggered a Flutter 3.47.8 Android release registrant/build mismatch; isolation removed it.
- Imported media is copied to the app library. JSON has references, not embedded audio bytes. Staged save + `.bak`, separate `.autosave`, recovery offer, recent projects and relinking are implemented. Save manually before closing; forced process termination may lose changes since the last successful save.

## Remaining acceptance / release work

1. Install the APK on an ARM64 device; verify MP3/WAV/FLAC/OGG playback, SAF source selection and output save, countdown, close markers, touch drag/zoom, encoder errors/cancel and long exports. Compare frame boundaries of Android output against the shared schedule.
2. Manually exercise Windows native file dialogs, library reorder, preview dragging, marker dragging and recovery dialogs; test on a clean Windows 10/11 computer without development tools. Automated native/core tests cover the underlying behavior but do not replace these manual checks.
3. Run long-file/large-library/performance and storage-full interruption tests. Windows currently encodes each normalized still segment separately before lossless concat; correct but many markers increase export overhead.
4. Before public/commercial release: own release signing key (Android), optional Windows signing, full corresponding native dependency sources/build instructions and license review. Current Inno Setup 7 compiler is non-commercial-use-only. No public upload or publication performed.

## Resume commands

From repository root: `flutter test`, `flutter analyze`, `tools/build-windows.ps1`, `tools/test-installer.ps1`.
Native tests: `cd native_test; ../.tools/flutter/bin/flutter.bat test integration_test/native_smoke_test.dart -d windows --dart-define=LEOS_ROOT=C:/LeosFastVideoEditor`.
Android: `flutter build apk --release --target-platform android-arm64 --split-per-abi` with local SDK/JDK configured as in README.

Do not report Android 1.0 as accepted until device checks pass.




