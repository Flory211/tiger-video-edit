# Effects and animation in schema 3

`model.dart` exports `effects.dart`. Existing seven legacy map effects stay intact; new effects use `Still.effectStack` in list order. Each instance has a stable unique ID, type, enabled switch, strength, duration/delay in microseconds, frequency in Hz, begin/end intensity, smoothing, interpolation and cubic Bezier control points. Strength/intensities/smoothing are 0..1; frequency is 0..60 Hz. Delay/duration are bounded to one hour; duration is at least 1 ms. Unsupported types, nonfinite values and duplicate IDs are rejected when opening projects.

`effectCategories` is the authoritative list of actual Canvas primitives:

| Category | Types |
| --- | --- |
| Motion | shake, zoom, pan, rotation, pulse |
| Glitch | glitch, rgb, scanlines |
| Light | blur, glow, flash, vignette, lightSweep |
| Transitions | crossfade, slide, wipe |

`effect_recipes.dart` supplies all 29 names requested in the specification as editable combinations of these primitives, through `effectRecipes`. These are styles, not 29 separate shaders. Pixel Stretch uses displaced horizontal bands; Lens Flare uses a light sweep and glow. VHS is scanlines/RGB/bands/blur. They are deliberate stylizations rather than physical simulations. Each transition recipe includes a genuine previous-image transition. `needsPreviousImage` identifies that dependency.

`Still.animations` contains ordered `AnimationTrack`s for x/y (fractions of composition size), scale (absolute multiplier), rotation (radians) or opacity (0..1 at paint time). Keyframes are strictly increasing local microseconds with finite values. Values hold before the first and after the final keyframe. The outgoing key's interpolation controls its interval: linear, easeInOut, cubicBezier, back, bounce or elastic. Bezier x control points must stay in 0..1. Back and elastic preserve overshoot in evaluation; rendering clamps opacity and scale to drawable bounds.

`Project.globalEffects` holds ordered `GlobalAdjustmentLayer`s. `globalEffectsEnabled` bypasses them all. Unlike copying effects onto images, the global stack receives the composition after captions and can blur, move, brighten or distort captions as well.

- `always`: anchored at project trim start; holds end intensity after the effect duration. For a constant treatment use equal begin/end intensity (normally 1).
- `range`: anchored at startUs, active in [startUs,endUs), holding end intensity after the effect duration.
- `everyMarker`: restart from latest marker in the project trim.
- `selectedMarkers`: restart only from latest referenced marker ID.
- `imageChanges`: restart at each quantized image segment boundary, including the first image.

Marker/image pulses expire at each instance's delay plus duration. Range limits and marker IDs are validated. Frequency modulates the envelope with a deterministic cosine; 0 disables modulation. Smoothing blends linear progress with smoothstep after interpolation.

`paintFrame` accepts optional `project`, `previousImage`, and `previousItem`; existing callers remain compatible. Preview and export must pass the same project, normalized source/local time and previous decoded source to receive identical pixels. The previous source must be decoded at the corresponding previous-segment media time. Without it, transitions intentionally pass through the current picture. Crossfade blends actual previous/current sources; slide and wipe expose the previous picture. Previous-item transforms are preserved. Global transitions receive the previous source image, not a cached previous full composition with historical captions/effects.

Time is normalized to the nearest composition frame (legacy default: 30 fps), preserving floor-encoded frame timestamps such as 33333 us. Animation/effect evaluation is independent of UI wall time. Incoming layers are captured once per active effect as immutable Canvas Pictures, preventing repeated recursive rendering of nested glow/RGB stacks. Pictures and paragraphs are disposed after recording.

Schema 3 serializes stacks, animations, global layers and audio items while reading known schemas 1 and 2 with empty new lists/default enabled global switch. Legacy effects are kept in their old map instead of silently converting their decay behavior. Parsing never writes to or mutates the input map or source file. Future schema versions are rejected. Ordered keys/unique IDs are validated rather than silently repaired.

Tests cover every published primitive with generated pixel images, deterministic rendering/expiry, real previous-image transitions, ordered combination differences, global bypass/captions, animation interpolation endpoints/overshoot, all trigger modes, validation, old schema migration and audio serialization. Device performance, GPU/platform equivalence and complete export integration need separate application-level validation.


## Editing UI

`V3Panel(editor: editor)` embeds in the existing property list. `showEffectLibrary(context, editor)` opens a bounded, scrollable modal with search, categories, popular/recent/favorite styles and separate selected-image, all-images and global-layer commands. Only the selected recipe renders an animated generated 240-pixel example through `paintFrame`, with an actual alternate previous source for transitions. Settings and system reduced-motion preferences stop the preview clock. Favorites and recents use persisted application settings.

Global layer forms edit enabled state, mode, time range and selected marker IDs. Effect rows support enable, delete, upward reorder and validated strength/duration/delay/frequency/begin/end/smoothing/interpolation/Bezier editing. Animation forms add/edit/delete keys with numeric local times and values, property, enable switch, outgoing interpolation and Bezier controls; they sort valid keys and reject duplicate times. Graphs sample the same interpolation evaluator used by rendering and update as fields change. Mobile dialogs scroll their controls; cancel never writes partial changes. Automated panel tests cover 228-pixel property width, 320×568 phone dialogs, favorites persistence, actual selected/global updates, invalid strength/range, duplicate keys, animation save and cancellation.
