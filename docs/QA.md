# Verification and release checklist

This is a first working build, not a store-ready release. Automated tests and local browser inspection do not replace physical-device checks for camera scanning, file handling, lifecycle behavior or release signing.

## Automated checks

Latest completed run, October 1, 2026: **`flutter analyze` has no issues; all 41 Flutter tests pass.** This includes nine home/editor interaction tests and the compact single/multipart QR transfer tests.

Run from the repository root:

```sh
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
```

The suite covers:

- Model validation, immutable list contents, Unicode and date roundtrips.
- Persistence/reopening, ordered concurrent edits, failed writes and initialization retry.
- Independent received copies, collection removal, optional examples and their exact Unicode artwork/text.
- Backup roundtrip, preferences, duplicate/conflict handling and atomic rejection of invalid input.
- Single and multipart transfer roundtrips, reordered/repeated frames, malformed input, integrity failure and size limits.
- UI creation/autosave, saving on departure, clearing an already-autosaved new note, edited-example preservation, checklist actions and narrow-screen layout.
- Concealment of future letters in cards/search/editor and receive previews.
- Receive validation/import and animated QR pause, manual advance and dismissal.

Tests use local/in-memory databases and do not establish real camera or native share-sheet compatibility. Run the complete suite again after changes to editor saving, data schemas or transfer rules.

## Browser review

The release web preview completed these checks on October 1, 2026. Evidence: [browser-verification.json](../artifacts/browser-verification.json), [desktop pocket](../artifacts/desktop-pocket.png), [phone pocket](../artifacts/phone-pocket.png), [dark appearance](../artifacts/desktop-dark.png), and [rendered QR](../artifacts/pass-qr.png).

- [x] A saved note survives a browser reload.
- [x] The bundled ZXing decoder reconstructs the code from an actual rendered QR screenshot.
- [x] A separate browser context at 390 px previews and imports its own independent copy.
- [x] The inspected phone layout and desktop dark appearance render correctly.
- [x] The inspected run records zero external network requests and zero JavaScript errors.

To reproduce the recorded browser script, install Chrome, start the release preview on port 5178, then run:

```sh
npm install --no-save --prefix .dart_tool/browser-check playwright
node tool/browser_smoke.cjs
```

The broader release matrix below remains available for checks beyond those exercised paths. Decoding a screenshot does not establish physical camera capture or a two-device camera handoff.

Build and serve the release output, rather than relying only on the development server:

```sh
python -m http.server 5178 --bind 127.0.0.1 --directory build/web
```

Review `http://127.0.0.1:5178` at a narrow phone width and a desktop width:

- [ ] First launch is empty; example pages appear only after an explicit choice.
- [ ] Logo, local fonts, emoji, cards and controls render correctly in both appearances.
- [ ] Create each content type, leave immediately after typing, reopen and reload; committed content persists.
- [ ] Search/filter, pin, archive/restore, collections, checklist reset/duplicate and movie watched state work.
- [ ] Long titles, large text scale, keyboard opening and narrow sharing sheets have no overflow or obscured primary actions.
- [ ] Export a single page and full backup; inspect file names and re-import through the intended screens.
- [ ] Invalid/truncated data produces a useful error without altering existing notes.
- [ ] Inspect network requests: app fonts, renderer and scanner decoder come from the same local bundle; links load externally only after an explicit action.
- [ ] After an initial load and service-worker activation, reload offline and create/edit a page. Open the scanner offline too. Repeat with a fresh profile to distinguish first-load limitations from warm-cache behavior.
- [ ] Verify site-data clearing removes browser-local notes as documented. Use a disposable profile for this check.

Browser camera access requires HTTPS or localhost and permission. A desktop browser without a working camera should still support file/paste receiving. Generated service-worker cache behavior and IndexedDB persistence vary by browser; do not promise universal offline first launch or permanent browser storage.

## Native build verification

Completed on October 1, 2026:

- [x] Built [the optimized Android preview APK](../artifacts/pocklino-android-preview.apk); verified its development signature and absence of `INTERNET` / `ACCESS_NETWORK_STATE` in the final manifest. Production signing remains unconfigured.
- [x] Launched an Android debug build in an emulator without runtime errors and inspected its empty/populated screens. [Empty screen](../artifacts/android-empty.png), [populated pocket](../artifacts/android-pocket.png). This does not verify camera capture.
- [x] Built [the complete Windows release archive](../artifacts/Pocklino-Windows.zip) using [windows/build_release.ps1](../windows/build_release.ps1). The 26-entry bundle includes the executable, DLLs, and data.
- [x] Started the Windows executable in a brief process smoke check: it stayed running for three seconds and produced no stdout/stderr errors. Native rendering and file/share dialogs were not exercised.

## Physical Android and iOS checks still required

Use two devices, preferably one Android phone and one iPhone. Include one older supported device. A successful compiled APK is not evidence that this matrix passed.

- [ ] Launch, create and reopen notes in airplane mode.
- [ ] Pass a short page with one QR in both directions and verify exact Unicode, checkboxes, links and dates.
- [ ] Pass a long page with animated frames; miss frames, pause, resume and verify full reconstruction without duplication.
- [ ] Scan a different sender mid-transfer, reset, and receive correctly. Repeated scans must not import automatically.
- [ ] Preview, cancel and keep each content type; imports must create separate IDs and leave originals untouched.
- [ ] Deny camera permission, grant it later and reopen; backgrounds/foregrounds and closing the sheet release/recover the camera.
- [ ] Check focus, screen brightness, glare, rotation and large/small displays. QR legibility matters more than animation smoothness.
- [ ] Share/save `.pocklino` and backup files using native file providers. Test iPad share-sheet anchoring and cancellation.
- [ ] Export, move to another device and restore a backup with existing notes; identical records should skip and conflicting versions survive separately.
- [ ] Receive a future letter: only its envelope/title/date are visible. Check reveal at the chosen time, different timezones and an app resume after the deadline.
- [ ] Confirm the clock/data-inspection limitation is explained. No notification should be expected when the reveal time arrives.
- [ ] Check rapid checklist taps, immediate back navigation, interrupted saving and low-storage failures for visible feedback and preservation of committed data.
- [ ] Exercise TalkBack/VoiceOver, large text, keyboard focus and touch target sizes.

## Before distribution

- [ ] Run `flutter build apk --release` with the checked-in SDK/Gradle/JDK configuration and test the actual development-signed artifact. Verify the merged release manifest excludes `INTERNET` and `ACCESS_NETWORK_STATE`, even when dependencies are upgraded. Debug builds intentionally differ.
- [ ] Build iOS on macOS with Xcode, resolve signing and verify camera/file permissions on a real device. This has not been tested in the Windows workspace.
- [ ] Configure production signing and review application/bundle IDs. Android's current release build uses a development/debug key and must not be published as-is.
- [ ] Review store privacy declarations against actual dependencies, external-link behavior and operating-system backup behavior. Pocklino itself has no analytics pipeline; inspect transitive scanner SDK diagnostics and the difference between debug and release networking permissions.
- [ ] Review native release manifests/entitlements and avoid unnecessary permissions.
- [ ] Confirm bundled dependency/font licenses and brand asset sizes.
- [ ] Complete naming/trademark clearance separately; the project does not establish availability.
- [ ] Retain a known-good backup and verify migration/restore before any future schema change.

Do not advertise encrypted storage, secure time-locks, live collaboration, automatic IMDb metadata, reminders or push notifications; these are not features of this build.
