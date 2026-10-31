# Tiger Video Edit rebrand

User request: rename the application to Tiger Video Edit and change project extension to .tve.

- Public Windows/Android names, window title, Dart package, app widget, executable, T icon, installer and APK names updated.
- Version 1.0.1+2. JSON schema stays at version 1; the data format is compatible.
- New saves and generated library paths use .tve. Legacy .leos can be opened. Saving a legacy project writes a .tve sibling without replacing its original.
- Existing library remains accessible. Android package ID and Windows installer GUID intentionally retained for upgrades. Workspace directory is unchanged.
- Windows installer registers TigerVideoEdit.Project for .tve, using a quoted command line for paths with spaces.
- Tests: 22 core/widget/export/storage tests; 2 native Windows integration tests passed. Updated Windows and Android release builds passed. Final installer verification recorded in DEVELOPMENT_STATUS.md.
- Original specification in USER_SPEC_RU.md remains an unchanged historical input; this request supersedes its product name/extension.

Installer verification: release setup compiled. A real Leos 1.0.0 installation was detected and preserved. Isolated same-payload installer with separate GUID and test-only extension passed association registration, installation, launch, FFmpeg and uninstall. Main setup was not installed over the user's existing app.
