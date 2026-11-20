# Publication review — 2026-10-31

## Standing update publication authorization — 2026-11-20

The owner explicitly approved public Windows updates through GitHub Releases and
requested this as the standing workflow for future finished updates. Further routine
publication confirmation is not needed. This supersedes the earlier source-only
authorization for compatible verified Windows update packages. The instruction is
recorded in AGENTS.md. No signing-key purchase, private Client ID disclosure, forced
editor closure or promotion of an Android TEST-debug APK is authorized by this rule.

The public 3.0.1 package is application-only (runner and data) and retains the
compatible installed 3.0.0 runtimes. It refuses missing/unsupported bases, mismatched
engines and locked application files. Four release-tool tests and isolated actual
installer tests passed; a patched 3005 copy starts and loads its retained Flutter
and libmpv runtimes. The original full-runtime draft is replaced before publishing;
its separate complete native source/notices review is not claimed resolved. Source
scope and reproducible inputs: docs/WINDOWS_UPDATE_SOURCES.md.

## Public source publication — 2026-11-18

Official GitHub CLI browser authentication completed as `Flory211`. The approved public repository https://github.com/Flory211/tiger-video-edit was created, with `main` as the default branch. Both `main` and `feature/tiger-3.0` received source commit `e55c2b7505bd73a50a123dc1c6a8ea2dda214a7a` and its preserved history; remote ref verification matched the local commit. A fresh all-reachable-history secret scan passed before upload. Ignored binaries, imported media, tool caches and credentials were not uploaded. Existing GPLv3 is retained as approved.

Windows and Android workflows automatically started for both branches. Main runs: https://github.com/Flory211/tiger-video-edit/actions/runs/44255815184 and https://github.com/Flory211/tiger-video-edit/actions/runs/44255815177. Their initial observed status was in progress; runner success is not inferred. No tag, binary Release, signing secret or external acceptance variable was created. Earlier statements that source was unpublished describe historical checkpoints.

## Corrected destination — 2026-11-15

The owner clarified that the publishing account is `Flory211`; the approved source destination is now `Flory211/tiger-video-edit`, with the same GPLv3 scope. The previously connected `GushinetsN` account was incorrectly assumed to be the destination. No source had been uploaded and no remote had been configured. Earlier account references below are historical. CLI authentication must be verified as `Flory211` before any repository creation or push. The application update owner and current documentation links were corrected accordingly; existing pre-correction local binaries retain the old default owner until rebuilt.

## Owner authorization — 2026-11-01

The owner explicitly confirmed public source publication to `GushinetsN/tiger-video-edit` with the existing GPLv3 license in this chat. This approval covers the reviewed application source/history and documentation. It does not approve a binary release, assert native corresponding-source compliance, production signing, Android acceptance or successful GitHub runners. Earlier pending-approval statements below describe the pre-authorization checkpoint. Official CLI browser authentication is the next prerequisite; credentials are not requested in chat.

## Final local candidate — 2026-11-01

Application binaries are built from commit `7d22cb4` on `feature/tiger-3.0`, preserving baseline `6f1e510`. Final documentation/notices are committed separately. Fresh Windows Release/Setup and ARM64 debug APK builds succeeded; the obsolete pre-v3 packaging smoke described below is historical evidence only. Final v3 installation/clean-machine acceptance is still pending. Exact current artifacts are recorded in local ignored `dist/V3_ARTIFACTS.json` and `dist/SHA256SUMS`.

121 root tests, clean analysis, 2 Python helper tests and 5 native Windows integration tests passed. Three workflow YAML files parse with the existing SDK YAML parser. Native tests use isolated temporary libraries; the installed application and user projects were not replaced. APK ZIP/ABI/version/certificate and bundled Windows FFmpeg/FFprobe checks passed. The TEST-debug APK has versionCode 3004, above legacy 2003, and the same local test certificate; this is not a production-signing or device-upgrade claim.

Read-only connected GitHub profile identified `GushinetsN`; no matching repository was found during preparation. Intended source destination: `GushinetsN/tiger-video-edit`. Portable official GitHub CLI is prepared but unauthenticated. No remote, login, source push or public release was created. The upload would include reachable source history from the preserved baseline through final documentation, synthetic demo fixtures and docs/screenshots; ignored `.tools`, builds/dist, tutorials, imported media and credentials are excluded. Existing GPLv3 is preserved pending owner confirmation; exact native corresponding-source preparation remains a binary-release gate.

Final staged and all-reachable-history secret scans exited 0 with no findings. `git diff --cached --check` passed; no tracked APK/EXE/MP4/private-key files or remote are present. The final integrity manifest create/verify passed. Windows Setup: 112,443,681 bytes, SHA256 `10a809d12194c5770e7b7ed03c88eff7f399d568ac5f407ad02e6b25b2fe8ac5`. Android TEST-debug: 93,527,489 bytes, SHA256 `a07cec4c1a51c65ef900c79b2631e1c6c59687007aac3a6233b81f9334a58cfc`. These checks support local review; they do not authorize publication or eliminate every possible secret/license issue.

Status: source and binaries have not been uploaded by this implementation. Existing GPL-3.0 LICENSE is preserved; this does not replace owner confirmation of the intended public license. No public repository or release is claimed ready solely from local checks.

Before the owner confirms first publication:

- Review `git status --short`, `git diff --cached --stat`, and the complete staged diff for personal paths, media and generated files. Keep original synthetic demo fixtures; exclude imported user media, caches, builds and credentials.
- Run `python tools/scan_secrets.py --mode staged` and `python tools/scan_secrets.py --mode history`. Scanner output contains file/line/rule only. It detects several token formats, private keys and credential filenames, but cannot guarantee all secrets are absent. History covers all reachable local refs; inspect additional fetched refs before publishing them. Do not print a suspected secret during review.
- Confirm repository owner/name and whether a remote already exists. Use existing official authentication; do not request credentials in chat. Show the exact files and history intended for upload before requesting owner approval.
- Confirm license choice, native binary versions, transitive licenses/notices, corresponding GPL sources and reproducible build instructions. FFmpeg with GPL codecs and libmpv require review of the exact distribution. URLs alone do not satisfy every source-distribution obligation. Existing THIRD_PARTY.md records local dependencies; CI uses separately pinned Gyan FFmpeg 9.0.2 and must be included in the final distribution record.
- Review production Android signing certificate identity and key backup. Configure protected release environment/reviewers and repository acceptance variables only after actual approval.
- Obtain passing Windows and Android GitHub runner results, clean-machine installer/runtime tests, Android ARM64 device import/edit/preview/export/save/reopen tests, and compare preview/export effects and mixed audio. No runner or device success is inferred from YAML or APK existence.

Local scanner/helper validation and build results must be reported with actual commands. Any open license, signing, public-upload approval, runner or device gate blocks production publication. Independent local development can continue.

## Local build-automation evidence

On 2026-10-31 PowerShell AST parsing of all `tools/*.ps1` passed. `python -m unittest discover -s tools -p test_release_tools.py` passed 2 tests (manifest tamper/path checks and scanner redaction); local execution used Python bundled with the Android NDK because the Windows Python app alias was unavailable. Staged and all-reachable-history scans exited 0 with no findings at that point; rerun after final staging.

`tools/verify-windows-payload.ps1 -Directory build/windows/x64/runner/Release` passed against the preexisting local native payload and actually ran bundled FFmpeg/FFprobe. `.tools/inno/ISCC.exe /DAppVersion=3.0.0 installer/windows.iss` successfully compiled that existing payload in 119 seconds. The smoke installer was renamed `dist/packaging-smoke-existing-payload.exe` to avoid presenting an old executable as a rebuilt v3 application. SHA256SUMS creation and verification passed for the local dist directory. These checks establish packaging mechanics only; a fresh integrated v3 application build and clean-device acceptance remain required. No workflow YAML execution, production signed APK, Authenticode signature or GitHub runner success is claimed.
