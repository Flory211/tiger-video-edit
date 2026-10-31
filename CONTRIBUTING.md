# Contributing

Use Flutter 3.47.8 (Dart 3.13.7), Java 17 and Android SDK for Android, or Visual Studio C++ desktop tools and Windows SDK for Windows. The application ID stays `com.leos.leos_fast_video_edit` so installed projects remain compatible.

Run `flutter pub get`, `flutter analyze`, and `flutter test` before proposing a change. Generate original fixtures with `node tools/generate-demo.cjs` and `node tools/generate-v2-demo.cjs` (FFmpeg on PATH). Keep imported/private media, generated videos, signing keys and application data out of commits. Preserve old `.tve` compatibility and use temporary project directories for tests.

Use focused changes and behavior tests. Document offline behavior and preview/export parity. Test Android on an ARM64 device and Windows in a clean user profile before release. A successful compiler run does not establish device acceptance.

Run `python -m unittest discover -s tools -p test_release_tools.py`, `python tools/scan_secrets.py --mode staged`, and `python tools/scan_secrets.py --mode history` before publication. Review the diff manually too: the scanner is a limited heuristic, not a guarantee of no secrets.

See [CI and release setup](docs/CI_RELEASE.md) and [publication review](docs/PUBLICATION_REVIEW.md). Existing LICENSE is preserved; do not change licensing or publish source/binaries without the owner's approval.
