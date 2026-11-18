# Changelog

## 3.0.0 — in development

- First Windows GitHub Actions builds passed with verified installer checksums. Android CI now installs FFmpeg without optional recommended desktop/speech packages, bounds network retries/timeouts, and separates SDK/FFmpeg/fixture steps after the first preparation run stalled on package downloads.
- Corrected the native window-close widget test to assert that the WM_CLOSE channel is absent on non-Windows hosts, while retaining dirty-project/reentrancy/busy-operation checks on Windows. The first Ubuntu test run exposed this platform assumption (120 passed, one failed); application close behavior is unchanged.
- Verified the corrected commit in real Windows and Android GitHub Actions: 121 tests passed and clean analysis on both; final installer/APK built, downloaded and checksum-verified. Android output remains explicitly TEST-debug.

- Audited the existing Flutter application; preserved the verified 2.0 baseline in Git.
- Implemented .tve schema 3 with v1/v2 migration, ordered/local/global effects, keyframes and 8 curves, 29 recipes over 16 Canvas primitives.
- Added responsive home/projects/music/sounds/templates/settings, group editing, independent visual/audio tracks, audio fades/mixing, six Auto Edit profiles and safe template CRUD.
- Added verified update downloads with release/error caching, panel persistence, themes/accessibility, dirty-close guards, and 24/30/60 FPS at 480p/720p/1080p.
- Added independent Windows/Android CI, secret/integrity checks, protected release gates and production-signing guards. Android build number is 3004 to remain above legacy split-APK versionCode 2003.
- Final app checks: 121 root tests passed; analyzer clean. Independent review fixes share music/SFX/voice gain rules between preview/export, restore source paths for every track, and prevent rapid-action ID collisions. Real Windows native composition/audio/preview-parity and cancellation tests passed; production/device/publication gates remain open.
- No 3.0 release has been published. Read DEVELOPMENT_STATUS.md for tested behavior and remaining gates.
- Final local Windows Setup and ARM64 TEST-debug APK built as 3.0.0+3004. Five native Windows integration checks passed, including late cancellation and isolated production bootstrap. Package integrity/signing details are recorded separately; production signing and device acceptance remain pending.

## 2.0.0

- Added per-item effects/presets, offline beat analysis, captions, mixed video/GIF and .tve schema v2.
