# Jamendo integration — 2026-11-18

Extend the existing Music page rather than replace the local library. Add an online route with explicit search, genres, pagination, stream preview, track links/licences and copyable attribution. No network requests until the user searches; retain only a small in-memory search cache. Store the Client ID in a separate local configuration file or an ignored local build define; never use a Client Secret or commit credentials.

Use Jamendo API v3 tracks with bounded HTTPS JSON requests and strict Jamendo audio-host checks. Show all streamable results, but allow editing only for artist-download-enabled CC BY/CC0 tracks and only after the application's editing/storage scenario is approved by Jamendo. No user checkbox substitutes for that approval. Recheck track metadata before any editing download, bound size/time, allow cancellation, stage atomically and remove temporary material. Selection uses existing project media import, not the offline music collection. Preserve attribution in .tve and display it before export.

Implement and verify in order: provider/parser and failure tests; online UI/configuration/preview lifecycle and widget tests; gated selection/credits and project roundtrip; real API/stream smoke with ignored local Client ID; full tests/analyze; Windows candidate build and available CI. No public binary Release or claim of Jamendo editing approval.

Sources: https://developer.jamendo.com/v3.0/tracks and https://devportal.jamendo.com/api_terms_of_use . Account/application registration and a real search request succeeded. Permission for editing/export storage remains unconfirmed; search/preview can be implemented independently.
