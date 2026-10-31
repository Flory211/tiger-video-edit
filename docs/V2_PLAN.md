# Tiger Video Edit 2.0 — first functional release

User explicitly authorized version 2.0 and selected all three proposed blocks: effects/presets; local beat detection/automatic assembly; captions/video/GIF. Preserve 1.0.1 installers and old .tve/.leos compatibility.

Architecture: extend existing immutable project schema to v2, accepting v1. Shared deterministic frame-number-based Canvas compositor applies per-item effect strengths/duration and timed text. Preview and export call the same compositor. Original static-image export remains a fast path; animated projects render frame sequences into FFmpeg (Windows) or Media3 (Android). Animation export uses temporary PNG frames and progress/cancellation; storage/time ceilings are documented. No paid services or runtime internet.

Model contract:
- Still: existing fields plus Map<String,double> effects, int effectDurationUs=500000, sourceStartUs=0, durationUs=0; kind getter image/gif/video inferred from extension. copy() supports all fields.
- Caption: id,text,startUs,endUs,x=.5,y=.85,fontSize=64,color=0xffffffff; copy(),toJson(),fromJson(). Absolute source audio times. Position normalized 0..1.
- Project: captions list; copy accepts captions; version2 serializer; v1 defaults empty. frameAt(sourceUs) returns active Segment; effect/clip local time = output frame minus segment.startFrame.
- EffectPreset: name,effects,durationUs, JSON; builtinEffectPresets map. Effects: shake,zoom,blur,glow,flash,rgb,glitch (0..1). Unknown keys rejected. Per-image effects also apply to video/GIF.

Modules: model.dart (parent), compositor.dart (parent), beat.dart (agent), media_bridge.dart (parent), media_frames.dart + native Android decoder bridge (agent), v2_panel.dart (agent), editor/main/platform export integration (parent).

Checks: synthetic pulse beats/silence; model migration/validation/captions/presets; GIF/video source frame seeking; composited frame hashes/boundaries; actual animated MP4 with text/effects; existing regression suite; analyzer; independent review; Windows Release/setup and Android APK. Device verification remains separate.

Plan:
- [x] Tests and model migration
- [x] Local rhythm analyzer and apply-as-one-undo-step assembly
- [x] Video/GIF decoded frame adapters and import
- [x] Deterministic effects + caption compositor and frame export
- [x] Real UI for every new function, presets persistence and temporal preview
- [x] Integration tests, review, release artifacts and status

Scope excludes the other original roadmap items not in the three presented choices (multiple audio tracks, online music sources, arbitrary output formats, slow playback). They are future increments, not fake controls.


Validation completed:45 core/widget/integration tests,3 native Windows tests, analyzer clean, Windows/setup and Android APK built. Android runtime acceptance remains pending; see DEVELOPMENT_STATUS.md.
