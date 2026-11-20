# Windows 3.0.1 in-app update

Owner explicitly authorized publication and future automatic-update releases.
The installed baseline is 3.0.0+3005, already pointing to Flory211.

1. Publish an application-only update (runner + data), reusing compatible existing
   Flutter/plugin/media runtimes. The previous full-Setup draft is not the artifact
   to publish: its native source/notices record is incomplete. Do not label the
   application source archive as complete native corresponding source.
2. Validate payload boundaries (no codecs/DLLs/tools/private values) and existing
   data paths. Inno preflight verifies the actual target baseline/engine and refuses
   missing/incompatible or locked application files. No automatic/forced close.
3. Build without private defines. Test on an isolated copy of 3.0.0+3005, including
   refusal for missing base, preservation of runtimes/settings and unlocked-file
   requirements. The installed user application is not modified by acceptance tests.
4. Preserve the existing local Jamendo connection, publish source/provenance/notes
   and checksums, replace draft assets, publish v3.0.1, and verify the anonymous
   updater detects/downloads 3.0.1 from 3.0.0. Verify the update offer in the app.
