# Publication review — 2026-10-31

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
