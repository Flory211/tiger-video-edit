# Music discovery for Tiger Video Edit

Lumos implements this inline in the existing Jamendo provider/page. User wants
more varied music, especially phonk and Brazilian funk for edits. No new service,
credentials, dependencies, offline catalogue or change to the editing permission gate.

Evidence: real API general `search=phonk` returned no rows while `namesearch=phonk`
reported 483 matches on 2026-11-19. Combining `namesearch=phonk` with `search=drift`
or `search=brazilian` returned relevant examples. Broad Brazilian funk search can
include adjacent styles; shortcuts are searches, not verified genre labels.

1. Add failing provider tests in test/jamendo_test.dart for English/Russian phonk
   aliases, drift/Brazilian combinations, sorting validation/cache isolation and
   artist grouping. Update lib/jamendo.dart minimally: optional sort/diverseArtists,
   explicit query mapping, preserve paging/bounds/fresh-rights/stream transport.
2. Add widget coverage in test/jamendo_page_test.dart: phone shortcuts remain
   accessible, no request on open, a shortcut clears unrelated genre/licence filters,
   paging keeps submitted sorting/grouping despite unsent edits. Extend the existing
   lib/jamendo_page.dart with horizontally scrollable quick searches and compact
   sort/grouping controls. Keep filters and track list usable on a phone.
3. Run targeted/full tests and analyzer; real API smoke of provider mappings and
   native desktop/phone screenshot/playback test. Review changes using existing
   reviewer workflow. Do not claim all keyword matches have a particular genre.
4. Bump patch/build to 3.0.1+3006 so installers are distinguishable from 3.0.0.
   Update guide/changelog; build private Windows/APK candidates with ignored local
   Client ID, verify manifests and available CI. Source publication remains
   authorized; do not publish a public binary Release or install over the running app.

API contract: https://developer.jamendo.com/v3.0/tracks (namesearch, search, order,
groupby=artist_id). One request per search/page, existing small memory cache.
