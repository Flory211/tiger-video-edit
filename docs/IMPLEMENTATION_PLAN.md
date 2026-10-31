# Version 1 implementation plan

Goal: installable offline music-marker editor for Windows and Android.
Spec: USER_SPEC_RU.md. Architecture: ARCHITECTURE.md.

- [x] Inspect empty workspace, tools, platform support and licenses.
- [x] Scaffold Flutter native hosts; lock supported dependencies.
- [x] Tests then model: precise markers, trim, cyclic images, normalized frame schedule, JSON validation, history.
- [x] Storage: atomic staging, backup, autosave, recent projects, durable imported files, relinking.
- [x] Media: audio playback, waveform, transformed PNG generation, Windows FFmpeg render with cancellation and validation.
- [x] Android: native waveform decoder, Media3 image sequence plus clipped audio, progress, cancellation, validation, SAF.
- [x] Adaptive UI: library/order, preview/transforms, properties, zoomable timeline, keyboard/touch marker capture, settings.
- [x] Generate own demo, run tests/analyzer/export smoke checks, build available release targets and installer.
- [x] Record verified platform acceptance criteria and remaining blockers in DEVELOPMENT_STATUS.md.

Failure review: Unicode/quoted paths; missing/corrupt assets; duplicate and subframe markers; cancellation and failed saves; unavailable platform codecs. Each must fail visibly without destroying existing output or project.


Platform acceptance is partial: see DEVELOPMENT_STATUS.md for manual Windows checks and Android device checks that remain. Checked tasks indicate implementation/build work, not blanket device acceptance.
