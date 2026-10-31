# Tiger Video Edit 1.0

Native Flutter desktop/Android application. No server, accounts, web runtime or version 2 features.

## Decisions

- Dart models store absolute source-audio times as integer microseconds in versioned JSON. UI allows millisecond editing. Source duration and trim bounds are explicit.
- One 30 fps frame schedule drives preview and export. A marker takes effect on the first frame at or after its timestamp. Duplicate positions remain editable but collapse in the render schedule; multiple cuts in one frame resolve to the last image. No zero-length video segments.
- Audio uses media_kit (MIT wrapper; bundled native library licensing audited separately). Position comes from the player; no free-running playback clock.
- Windows uses an external bundled FFmpeg/ffprobe process with argument arrays, cancellation and temporary output validation. The installed FFmpeg is GPLv3 with libx264; distribution of this app therefore uses GPLv3 with corresponding source obligations. No claim of patent clearance.
- Android uses Media3 Transformer (Apache 2.0), MediaCodec H.264/AAC, and Storage Access Framework to save output. Codec availability is checked at runtime; no Windows executables on Android.
- Flutter Canvas generates transformed still frames for both preview and export, avoiding subtly different fit/crop implementations in FFmpeg and Android.
- Imported media is copied to the application project library. JSON references files without embedding bytes. Desktop paths can be relinked. Saves preserve a backup, autosave is separate.
- ChangeNotifier controller, immutable model snapshots for undo/redo, local JSON settings and recent-project index. No speculative effects/presets frameworks.

## Modules

`lib/model.dart`: validated project data, timeline and render segments.
`lib/storage.dart`: recoverable storage and settings.
`lib/platform_media.dart`: playback, waveform and export adapters.
`lib/editor.dart`: state and operations.
`lib/main.dart`: adaptive native UI and keyboard shortcuts.
`android/app/src/main/kotlin/.../MainActivity.kt`: waveform decoding, Media3 export, save via SAF.

## Verification

Core tests: precision, pause/seek capture, edit/undo, cyclic images, trim, duplicates, frame boundaries, JSON corruption, safe save. Integration: synthetic generated media, actual FFmpeg render, ffprobe H.264/AAC/duration/frame checks. Flutter analyze, tests, Windows release; Android APK only when SDK available. Installation/device tests require explicit recorded evidence.

## Sources checked 2026-10-29

- https://docs.flutter.dev/install/manual
- https://pub.dev/packages/media_kit/versions
- https://pub.dev/packages/file_picker
- https://developer.android.com/media/media3/transformer/transformations
- https://developer.android.com/media/media3/transformer/supported-formats
- https://developer.android.com/jetpack/androidx/releases/media3

Versions in pubspec.lock and Gradle are the build authority; online documentation may be newer than reachable artifact repositories.

