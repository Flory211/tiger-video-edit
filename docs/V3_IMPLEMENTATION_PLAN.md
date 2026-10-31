# Tiger Video Edit 3.0 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans / dispatching-parallel-agents for the independent tasks below. Do not publish or mutate remote repositories.

**Goal:** Extend the existing offline Flutter editor to 3.0, preserving .tve v1/v2 and G-marker editing.
**Architecture:** Extend immutable Project/Still and the shared Canvas compositor; keep existing platform decoders/export adapters. Separate project data, local services, UI and build automation without replacing working components.
**Tech Stack:** Flutter 3.47.8 / Dart 3.13.7, media_kit, FFmpeg/libmpv Windows, Media3 Android, Inno Setup, GitHub Actions.
**Spec:** [V3_SPEC_RU.md](V3_SPEC_RU.md).

## Global constraints

- Tiger Video Edit 3.0.0; Windows x64 and Android ARM64; .tve remains the editable project format.
- Never modify installed application data for tests. Preserve original old projects, backups, and existing LICENSE.
- No public source upload, release, selected new license, secrets, or paid dependency without the required user decision.
- Local edits/export must work offline. No fake catalog, inactive feature buttons, or unverified CI/device claims.
- Only root agent commits. Workers own disjoint files and report exact interfaces before integration.

## Review focus

- Malformed/oversized v3 JSON and finite/range checks; old-schema migration must preserve defaults.
- Half-open ranges and non-frame-aligned markers must match preview/export.
- Cancelled renders/downloads preserve existing destination and remove staging data.
- Offline/network failures and unconfigured providers must leave local editing functional.
- Missing signing keys, publishing permission, license decision, GitHub runner/device access are explicit release blockers.

## Verified starting point — 2026-10-31

- Root tests: 45/45 passed; analyzer: no issues found. Logs in ignored .tools/v3-baseline-*.log.
- Git 2.54 available, repository initialized with baseline commit, branch feature/tiger-3.0. Existing user Git identity retained.
- GitHub CLI not on PATH. No remote source or public release created.
- Existing GPL-3.0 LICENSE preserved; publication/license status requires confirmation before first upload.
- v2 includes 7 per-media effects, presets, beat analysis, captions, video/GIF and native packaging. Android device acceptance remains outstanding. Prior demo test rendering used Ahem fonts; clean native demo export exists in ignored tutorial/assets/result-example.mp4.

## Tasks and ownership

- [x] 1. Audit existing source/docs/toolchain; baseline tests/analyzer; safe initial Git snapshot.
- [ ] 2. Build automation: .github/workflows/windows.yml, android.yml, release.yml; tools/build-windows.ps1, bootstrap/verification/signing scripts; retain explicit release gate and unsigned/test distinction.
- [ ] 3. Global effects and schema: lib/model.dart, lib/compositor.dart, new effect/animation modules and tests. Preserve old maps; add ordered instances, bulk/global distinctions, time modes and curve/keyframe evaluation.
- [ ] 4. Services: version/release/update checks with caching/checksums, offline local music catalog and lawful provider contract, settings persistence and generated original sounds; primary-source Jamendo research.
- [ ] 5. Controller integration: selection, bulk copy/paste, global effects, templates/Auto Edit profiles, audio clip editing and source relinking/history.
- [ ] 6. UI: new responsive home/projects/music/templates/settings, accessible animations, effect library/curve controls and timeline tracks, keyboard/touch commands, dirty-close guard.
- [ ] 7. Shared rendering: wire all new composition effects/animation/layers to preview and exporter; mix SFX/audio tracks on both platforms and verify actual MP4.
- [ ] 8. Regression and native tests; local Windows/Android builds; verify package payload and signing identity. No Android-device claim without actual device.
- [ ] 9. README/CONTRIBUTING/CHANGELOG/status/release notes and publication review with secret/history/dependency checks.
- [ ] 10. Present concrete publication report for confirmation only after completing all independent local work. GitHub execution/online-provider approval/production signing/device acceptance remain external gates when unavailable.

Each task adds behavior-focused tests first, runs relevant checks, updates status/changelog and makes a scoped commit after integration.
