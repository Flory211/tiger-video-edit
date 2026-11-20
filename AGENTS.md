# Project instructions

## Publishing updates

The owner authorized public Windows updates to `Flory211/tiger-video-edit` on
2026-11-20 and requested this as the standing workflow for future updates.

- A user-visible update is not complete with a source push or a local installer.
  Increment the semantic version/build, verify the build, then publish a stable
  GitHub Release with the compatible Windows installer and SHA256SUMS. Do not ask
  again for routine publication of a verified update within this scope.
- Verify the public, unauthenticated release feed using the real UpdateService
  against the previous installed version. Drafts/prereleases do not reach users.
- Preserve installed projects, settings, local Jamendo configuration and runtime
  prerequisites. Do not force-close an editor or delete/reinstall its library.
- Never publish local Client IDs, Client Secrets, signing keys or private configs.
  Release builds must use public configuration and preserve per-user settings.
- The 3.0.1 Windows update package reuses the compatible 3.0.0 native runtime.
  Check prerequisites and refuse unsupported installations. If Flutter, plugins,
  native dependencies or asset paths change, review the update format again.
- Keep Android production-signing/device requirements separate. A TEST-debug APK
  must not be offered as a stable automatic Android update or block Windows-only
  publication. Do not invent approval records or claim unrun checks passed.

Do not use Astra models or delegate to them without the owner's explicit consent.
