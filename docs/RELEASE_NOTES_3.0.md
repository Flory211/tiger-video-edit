# Tiger Video Edit 3.0.0 — release candidate notes

This file is prepared for the explicit, approval-gated release workflow. It does not announce a published or production-approved release.

## Changes

- Responsive home/projects/music/sounds/templates/settings and accessible reduced-motion navigation.
- Ordered effect stacks, global composition layers, per-marker/range modes, bulk selection/copy/paste and an independent global bypass.
- Keyframes and 8 interpolation curves; 29 editable effect combinations over 16 actual Canvas primitives, including genuine previous-frame transitions.
- Additional visual/audio tracks, original generated sound effects, volume/fades and marker placement; bounded background PCM mixing.
- Auto Edit profiles and safe portable JSON templates; compatible .tve schema 3 with v1/v2 reading and backups.
- 24/30/60 FPS, 480p/720p/1080p, configurable quality, protected output commit and verified update downloads.
- Independent Windows/Android CI, checksums, secret scanning and production-signing/publishing gates.

## Before publication

Read DEVELOPMENT_STATUS.md, CI_RELEASE.md and PUBLICATION_REVIEW.md for the exact tested commit/artifacts. GitHub runner success and physical Android acceptance cannot be inferred from local builds. The test debug APK is not a production signed release. Jamendo needs an appropriate agreement; the working local music library is the active fallback. Confirm the inherited license and corresponding native-source obligations. Public source/release publication still requires the owner's explicit approval.
