# Windows application update 3.0.1 sources and prerequisites

The published `Windows-x64-Update-Setup.exe` contains the Tiger runner and `data/`
(AOT application, ICU data, Flutter assets and compressed `NOTICES.Z`). It retains
the existing compatible installation's engine, plugins, CRT, media runtimes and
uninstaller. It contains no libmpv/FFmpeg executable, native DLL, signing key or
local Jamendo configuration. This is not the earlier full-runtime Setup draft.

## Application source and build

The adjacent `Application-Source.zip` contains the exact release source snapshot,
including LICENSE, pubspec.lock, Windows runner/CMake files, assets, update script,
payload validator and acceptance test. The release provenance names the application
source used for compilation and the packaging/source snapshot separately when needed.

- Flutter 3.47.8, Dart 3.13.7: https://github.com/flutter/flutter/tree/737ba8f885dc774b53b442759999a312c9461e4e
- Hosted Dart package names, exact versions, archive SHA256 and registry origins:
  `pubspec.lock`. Each public archive is available at
  `https://pub.dev/api/archives/NAME-VERSION.tar.gz`; SDK packages are in the pinned
  Flutter source. Included package copyright/licence notices are retained in
  `data/flutter_assets/NOTICES.Z`.
- Windows build tools: Visual Studio C++ and the pinned Flutter SDK.
- Packaging: Inno Setup; this non-commercial update was built with local 7.1.1.
  Public compiler inputs are `installer/windows-update.iss` and
  `tools/build-windows-update.ps1`. The script supplies only the public GitHub
  owner/repository Dart defines, never a private Jamendo build file.

Rebuild with `flutter pub get`, then run `tools/build-windows-update.ps1` with
`-Python` pointing to Python and `-BaseDirectory` pointing to a supported baseline.
The validator enforces the supported base file paths and rejects native payloads.
Every public package requires a fresh public compilation from a clean source
snapshot; the builder cannot package stale private output with a skip-build flag.
The installer checks every replacement path before writing, backs up the application
files and restores them after an interrupted installation. Existing projects and
native libraries are outside that replacement/backup list.
Run `tools/test-windows-update.ps1` against a separate copy to verify installation.

## Retained runtime references

Runtime object files below are not distributed by this application-update package.
The preflight verifies compatible existing Flutter and libmpv hashes and required
files. These references identify their core sources and upstream build provenance;
the application archive is not a complete source bundle for a previous native
binary distribution or its statically linked transitive libraries.

- Existing Flutter engine hash: `eca1f8c9b1537bd585bbbcc62362df9ca7e69faa7d4e895688108af63ccea157`.
- Existing libmpv hash: `04e4d27dc385dc18ddd93fbe69c75e635b864f3c6ec53a9122df54c2f7842f4a`.
- mpv core: https://github.com/mpv-player/mpv/tree/e471496c56f0f49c133bd88b50aed62b845f1909
- FFmpeg inside that libmpv: https://github.com/FFmpeg/FFmpeg/tree/9a861e9687d30e657d59521817cad18405995983
- Upstream native recipe: https://github.com/shinchiro/mpv-winbuild-cmake/tree/1f8d2e76255abc48f0456d9be99b4cab9c6566e6
- Upstream build record: https://github.com/shinchiro/mpv-winbuild-cmake/actions/runs/39518569492
- Existing separate FFmpeg executables are retained; no FFmpeg version replacement
  is part of this update. The full-runtime CI candidate used Gyan 9.0.2 from core
  https://github.com/FFmpeg/FFmpeg/tree/946fcce07b6dcd0331c8cc609192aeff5e1924f8
  but that full installer is not the public update artifact.
