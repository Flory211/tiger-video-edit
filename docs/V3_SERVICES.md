# V3 local services and update safety

These services use Dart IO and the already installed `crypto` package (now an
explicit dependency). They never execute an installer or require the end user's
GitHub account. Application support paths should come from the existing
`LocalLibrary.root` so legacy user data stays in the same location.

## Settings

`SettingsStore(File('$root/app_settings.json')).load/save` persists typed
`AppSettings`: animations, reduced motion, system theme/dark/light, RU/EN,
autosave, interface sounds, preview volume and quality, export defaults,
favorite/recent effects, automatic update checks and notifications.
`animationsAllowed(systemReducedMotion: MediaQuery.disableAnimationsOf(context))`
combines user preferences and the operating system accessibility setting.
The new settings file must stay separate from the v2 `settings.json` map.

Writes stage and flush in the destination directory, keep a `.bak`, and restore
the previous destination if replacement fails. Invalid primary settings/catalog
JSON can fall back to the previous backup. Save calls on each store are serialized.

## Original sound effects

`SoundLibrary(Directory('$root/sounds')).generate()` creates ten mono 22,050 Hz
16-bit PCM WAVs with deterministic noise, sine sweeps and bounded envelopes:
Whoosh, Impact, Bass Hit, Click, Pop, Transition Hit, Riser, Reverse Whoosh,
Glitch Sound and Cinematic Boom. `SoundEffect` supplies `id`, `name`, absolute
`path`, and `duration` for the existing media player and sound timeline items.
Sounds range from 80 ms to 1.6 s, are faded at both boundaries and stay below
full scale. There are no external samples or recordings.

These are original procedural assets created for this project. The owner has
not yet selected their public distribution license; this implementation does
not assign an open source license or claim third party permission.

## Music library and online provider gate

`MusicLibrary(Directory('$root/music')).load()` reads its local JSON catalog.
`importFile` copies the selected audio into this library before committing
metadata. Deleting or moving the original import therefore does not break
library playback. Import requires a supported extension, a nonempty file and
at most 1 GiB. The caller should probe the real duration through the existing
media bridge and provide it; absent duration is explicitly unknown (`zero`).
Search matches title, artist and genre. Favorites and most recently used track
IDs persist. Local import does not assert synchronization or distribution
rights; users must have rights to their selected music.

`OnlineMusicProvider` defines real provider search and download boundaries.
`OnlineMusicTrack` carries source/preview/download URLs, duration, artist and
`MusicLicense` with attribution, license URL, and separate download, offline and
synchronization permissions. `canDownload` requires all three permissions and
an HTTPS URL. No synthetic search results, demo catalog, embedded client ID,
private API key or unapproved live music provider is shipped.

### Jamendo research, checked 2026-10-31

The official [API terms](https://devportal.jamendo.com/api_terms_of_use),
especially sections 2 and 3.3, require registration of applications and limit
free API use to noncommercial use. Commercial use needs an agreement. Their
restriction on applications designed for caching/offline access conflicts with
this editor's persistent offline music requirement. Therefore normal API
access alone is insufficient for the requested integration. An application
agreement covering this workflow must be obtained before activating a provider.

The official [authentication guide](https://developer.jamendo.com/v3.0/authentication)
requires a registered application client ID for API calls; personal data/write
operations require OAuth. A test ID in documentation is not a production grant.
No secrets should be embedded in a distributable app; any confidential provider
credential would require an appropriately secured backend.

The official [tracks endpoint](https://developer.jamendo.com/v3.0/tracks)
returns `audiodownload_allowed`, introduced in February 2021, and separate
`audio`, `audiodownload` and license metadata. A provider must enforce that flag
and the track's applicable license. An accessible stream/download does not by
itself authorize editing or publication of synchronized video.

The official [individual licensing explanation](https://support-licensing.jamendo.com/individual-licenses)
describes synchronization licenses with a scope tied to a track and project.
A purchased license is not a blanket grant to sublicense a music catalog to
all editor users. Exact commercial/noncommercial, attribution, modification,
offline and synchronization rights must be reviewed for the actual agreement
and individual track before enabling download. `MusicSources.jamendoUnavailableReason`
exposes the real configuration status to the UI. The specified fallback is a
working local library and this extensible provider interface.

## Public release updates

Configure the publisher explicitly at build time:

```
--dart-define=TVE_GITHUB_OWNER=<actual-owner>
--dart-define=TVE_GITHUB_REPO=TigerVideoEdit
```

No owner/account is invented. Without a valid owner `check` returns
`UpdateStatus.notConfigured` and makes no network request. End users do not need
GitHub CLI, authentication or access to a personal GitHub account.

`UpdateService(cacheFile: File('$root/updates.json'))` uses the public GitHub
Releases REST API, a 20-second timeout, a 2 MiB metadata limit and a 24-hour
repository-scoped disk cache. `check(currentVersion, platform, force: true)` is
the manual check; automatic checks use the cache and should run once at startup
only when settings allow. UI notifications also respect `updateNotifications`.
Offline, timeout, rate-limit, invalid-response, server-error, not-configured and
missing-compatible-asset statuses are distinct. Failed requests do not overwrite
the last good cache. Releases use semantic version ordering including prerelease
precedence; release candidates/drafts are excluded from stable delivery.

Failed checks have a separate one-hour backoff in `updates.json.attempt.json`
(the configured cache filename plus `.attempt.json`). It records only publisher,
platform, installed version, UTC timestamp, error status and message, with no
credentials or response bodies. Automatic checks across app launches reuse the
same error with `fromCache: true`; a different publisher/platform/version does
not reuse it. A fresh valid 24-hour release cache keeps priority. Manual force
bypasses both caches; successful retrieval clears failed-attempt metadata.
Network failures never overwrite the valid release cache or turn expired release
metadata into an available-update notification. Read-only cache storage still
returns the real network result without failing the check.

Compatible asset filenames identify Windows x64 setup/installer `.exe` or Android
ARM64 `.apk`; debug and unsigned artifacts are rejected. Release packaging must
publish these explicit platform/architecture names. Selection requires either
GitHub's `sha256:` asset digest or an exact `.sha256` sidecar / SHA256SUMS manifest.
The [GitHub REST documentation](https://docs.github.com/en/rest/releases/releases)
documents public unauthenticated access, release assets and SHA-256 digest fields.

`download(asset, destination, cancellation:, onProgress:)` stages to a `.part`,
checks published byte count and computes streaming SHA-256 from the staged file,
then replaces the destination. On corruption, cancellation, partial response or
network failure, the previous destination remains untouched. A cancellation
token can interrupt a waiting body stream. A service permits one active download.
Checksums are required and matched to the exact filename; ambiguous manifests
are rejected. Original URLs must be HTTPS release downloads under the configured
GitHub repository and tag. Redirects permit only GitHub's known HTTPS asset
delivery hosts, reject credentials/custom ports, and have a five-hop limit.

The returned `File` is verified against trusted release metadata, not a substitute
for OS code signing. Only an explicit user action in the UI may hand that local
file to the operating system's installer/consent flow. The service does not spawn
processes, elevate privileges or install silently.

## Verification

`flutter test --no-pub test/v3_services_test.dart` uses temporary directories and
an injected fake transport, never the network. It verifies settings recovery,
copied local imports/favorites/history, ten valid deterministic WAVs, semantic
ordering, platform selection/cache, offline/rate errors, trusted URLs, checksum
manifests and preserving an existing installer on cancellation/corruption.

## Workspace integration and service pages

`WorkspaceShell(editor:, editorBuilder:)` retains the dashboard and editor in a
permanent `IndexedStack`. Returning home or visiting a service page never
disposes the editor or its project. `WorkspaceVisibility.isActive(context)` gates
the editor's global keyboard handler when another page or a confirmation dialog
is active. The root theme listens to the editor's settings notifier.

`SettingsPage`, `MusicLibraryPage`, `SoundLibraryPage` and `UpdatesPage` are real
Scaffolds connected through typed callbacks. Music import uses the platform file
picker, probes real duration with a separate lazy media-kit player, copies the
audio into its library and exposes metadata/rights alongside each track. Sound
preview uses another independent lazy player; timeline/marker insertion calls
the editor. No native preview player is initialized simply by opening a page.
Settings expose Russian; English translation is explicitly unfinished rather
than presented as a working switch.

`ProjectsPage` searches existing recent projects and the library's `projects`
directory, preserves legacy `.leos` compatibility and offers the native file
picker. Windows path casing/separators are normalized for duplicate detection.
New/open actions require Save/Discard/Cancel if dirty; a cancelled or failed save
cannot replace the current project. Home offers Save/Keep unsaved/Cancel because
the project remains mounted. Android Back from editing goes home; from the
dashboard it checks unsaved work before asking the system to close the app.

The shell uses the connected, verified publisher profile `GushinetsN` and planned
repository `tiger-video-edit`, still overridable via `TVE_GITHUB_OWNER/REPO`.
No repository/release was published by these services. Until a real public
release with compatible hashed assets exists, a 404 is shown as an unavailable
public release. Automatic checking runs once at startup using the 24-hour cache;
notifications respect preferences. Manual checks bypass the cache explicitly.

Windows download uses a save-location picker and launches the verified local EXE
only after a separate explicit button. Android saves to `filesDir/updates` and
uses `tiger/media` → `installUpdate` with a narrow FileProvider; a source permission
request requires the user to return and click again. There is no silent install.

Additional widget tests in `service_pages_test.dart` and `workspace_shell_test.dart`
exercise typed settings changes, honest empty music status, manual unconfigured
checks, phone sound actions, retained editor navigation, cancelled saves,
unsaved sessions and temporary-directory project discovery. They use fake
players/editors and never touch installed application data or the network.
