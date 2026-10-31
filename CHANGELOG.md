# Changelog

## 3.0.0 — in development

- Audited the existing Flutter application; preserved the verified 2.0 baseline in Git.
- Implemented .tve schema 3 with v1/v2 migration, ordered/local/global effects, keyframes and 8 curves, 29 recipes over 16 Canvas primitives.
- Added responsive home/projects/music/sounds/templates/settings, group editing, independent visual/audio tracks, audio fades/mixing, six Auto Edit profiles and safe template CRUD.
- Added verified update downloads with release/error caching, panel persistence, themes/accessibility, dirty-close guards, and 24/30/60 FPS at 480p/720p/1080p.
- Added independent Windows/Android CI, secret/integrity checks, protected release gates and production-signing guards. Android build number is 3004 to remain above legacy split-APK versionCode 2003.
- Final app checks: 119 root tests passed; analyzer clean. Real Windows native composition/audio/preview-parity and cancellation tests passed; production/device/publication gates remain open.
- No 3.0 release has been published. Read DEVELOPMENT_STATUS.md for tested behavior and remaining gates.

## 2.0.0

- Added per-item effects/presets, offline beat analysis, captions, mixed video/GIF and .tve schema v2.
