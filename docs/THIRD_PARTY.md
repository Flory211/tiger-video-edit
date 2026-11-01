# Third-party components and reproducible source references

The existing LICENSE contains GPLv3 text inherited from version 2.0 and is preserved unchanged. On 2026-11-01 the owner confirmed public application-source publication with this GPLv3 license. Binary distribution still requires exact native distribution/corresponding-source review and separate release approval; no production binary release is claimed.

| Component | Pinned version | License / source |
|---|---|---|
| Flutter / Dart | 3.47.8 / 3.13.7 | BSD-style, https://github.com/flutter/flutter/tree/737ba8f885dc774b53b442759999a312c9461e4e |
| media_kit Dart | 1.2.6 | MIT, https://pub.dev/packages/media_kit/license |
| crypto Dart | 3.0.8 | BSD-3-Clause, https://pub.dev/packages/crypto/license |
| libmpv Windows | 20261021, e471496c56 | GPL; https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261021 and upstream https://github.com/mpv-player/mpv |
| media_kit_libs_android_audio | 1.3.8 / libmpv audio build v1.1.8 | Wrapper MIT; native bundled libraries have their own GPL/LGPL notices; https://github.com/media-kit/libmpv-android-audio-build |
| FFmpeg Windows | N-124557-g9e71ea2d60-20260520 | Installed build is GPLv3, includes libx264. https://github.com/FFmpeg/FFmpeg/tree/9e71ea2d60 ; https://github.com/BtbN/FFmpeg-Builds |
| Media3 Transformer/Effect | 1.11.1 | Apache-2.0, https://github.com/androidx/media |
| file_selector / path_provider | 1.1.0 / 2.1.6 | BSD-3-Clause, https://github.com/flutter/packages |
| Inno Setup compiler | 7.1.1 | Build tool only, https://jrsoftware.org/isinfo.php |

Exact transitive Dart versions: pubspec.lock. Flutter embeds generated package license notices in its runtime license registry.

Windows libmpv archive SHA256: efc719eff3dc5954b4a5efc800632808bcec01cc9034940dd14e5eb7fe9ea633.
Archive URL: https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261021/mpv-dev-x86_64-20261021-git-e471496c56.7z

The installed FFmpeg is reused for local builds. tools/build-windows.ps1 copies ffmpeg.exe, ffprobe.exe and ALL accompanying DLLs; it does not assume statically linked executables. tools/bootstrap-windows.ps1 retrieves and verifies libmpv separately.

CI bootstrapping separately pins Gyan FFmpeg 9.0.2 with a checked archive hash; it is not the local N-124557 build recorded above. A future CI distribution must record that exact build and its corresponding sources independently.

Before distributing binaries to third parties, prepare complete corresponding source and build instructions for the exact native library builds and their transitive dependencies; source links alone do not replace GPL source delivery obligations. Preserve all upstream copyright/license notices. Codec patent obligations depend on distribution and jurisdiction; no patent clearance is claimed. This document records engineering choices, not a legal opinion.


The locally installed Inno Setup 7 compiler identifies itself as non-commercial-use-only. This local test installer has not been published commercially; commercial packaging requires an appropriate Inno Setup license or a suitably licensed alternative tool.
