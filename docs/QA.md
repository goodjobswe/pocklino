# Verification and release checklist

Version 1.0.0 is published as a signed APK and a Windows ZIP on GitHub, not through an app store. Automated tests and local browser inspection do not replace checks on real devices for camera scanning, file handling and lifecycle behavior; the lists below say what has been checked and what has not.

## Automated checks

Latest completed run, October 2, 2026, for version 1.0.2: **`flutter analyze` has no issues; all 63 Flutter tests pass.** This includes seventeen home/editor interaction tests, a check that the version in Settings matches `pubspec.yaml`, single/multipart QR transfers in both format versions, sharing-speed controls, and camera close/reopen sequencing.

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
- Single and multipart transfer roundtrips, reordered/repeated frames, malformed input, integrity failure and size limits, for version 1 and version 2.
- Version 2 codes: base45 against the RFC 9285 examples and an independent encoder, no frame denser than a 57 by 57 alphanumeric code, earlier version 1 codes still received, and a refusal to inflate past the entry size limit.
- UI creation/autosave, saving on departure, clearing an already-autosaved new note, edited-example preservation, checklist actions and narrow-screen layout.
- Card menus: deleting with undo while the menu is still closing, archiving to the Archive place and bringing back, and adding a collection after cancelling its dialog.
- The empty pocket's own button for a first page, the side panel on a wide window, and a failed save that leaves the cursor in its field.
- Button roles for the papers on the create sheet, as a screen reader hears them.
- Concealment of future letters in cards/search/editor and receive previews, and of a sealed page of any other kind on its card and in the editor.
- Receive validation/import, animated QR speed changes without resetting frames, pause/manual advance, enlargement of static and animated codes, and camera lifecycle.

Tests use local/in-memory databases and do not establish real camera or native share-sheet compatibility. Run the complete suite again after changes to editor saving, data schemas or transfer rules.

## Visual review

The suite lays text out in a placeholder font, so it cannot show how a screen looks. A separate harness draws the real screens with the bundled fonts and saves them as pictures:

```sh
flutter test tool/screens_test.dart
```

It writes about 80 PNG files to `build/screens` (or the folder named in `SCREENS_DIR`): every place, the create sheet, each editor, the pass and receive sheets, dialogs, pickers and settings, by day and in the evening, on a phone and a wide window, plus a short medium window, a 320 px phone and a small phone with large text. A layout overflow fails the run. Look through the pictures after any change to `lib/design.dart`, `lib/paper.dart` or `lib/pocket.dart`.

For QR sharing changes, render the targeted day/evening, narrow-phone and desktop cases, then decode their actual pixels with the bundled ZXing reader:

```sh
flutter test tool/screens_test.dart --plain-name QR
node tool/qr_image_check.cjs
```

The decoder check uses the local Playwright installation described below. It compares 20 displayed QR images with their exact expected payloads, including enlarged static and animated codes. Crops are normalized to at most 320 pixels before decoding: the bundled ZXing reader can choose false finder patterns at some larger cell sizes even with an exact QR matrix. Results go to `artifacts/qr-image-verification.json`. These checks establish rendered-code readability at the checked sizes, not physical-camera reliability.

## Browser review

The release web build completed these checks in Chrome on October 2, 2026, driven by `tool/browser_smoke.cjs`:

- [x] A saved note survives a browser reload.
- [x] The bundled ZXing decoder reconstructs the code from an actual rendered QR screenshot.
- [x] The receiving context inflates and previews that scanned version 2 code.
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

Completed on October 2, 2026, with version 1.0.0:

- [x] Built the release APK with the application ID `nu.goodjob.pocklino`, signed with the upload key. Checked the signature, and that the merged manifest asks for the camera only, with no `INTERNET` or `ACCESS_NETWORK_STATE`.
- [x] Installed that build on an Android 15 emulator and walked through the empty pocket, the examples, the create sheet, a note, a letter, collections and the evening appearance by their accessibility labels. The device log showed no Flutter errors. This does not verify camera capture.
- [x] Ran the release workflow by hand on GitHub Actions: it built the signed APK, with the same certificate and permissions as the local build, and the Windows ZIP with the executable, the DLLs and the data folder.
- [x] Started the Windows executable from that ZIP in a brief smoke check: it stayed running for six seconds, drew its window and wrote nothing to stdout or stderr. File and share dialogs were not exercised.

## Physical Android and iOS checks still required

Use two devices, preferably one Android phone and one iPhone. Include one older supported device. A successful compiled APK is not evidence that this matrix passed.

- [ ] Launch, create and reopen notes in airplane mode.
- [ ] Pass a short page with one QR in both directions and verify exact Unicode, checkboxes, links and dates.
- [ ] Pass a long page with animated frames; miss frames, pause, resume and verify full reconstruction without duplication.
- [ ] Adjust Sharing speed while the receiver is collecting pieces. Try 2.0, 1.0 and 0.4 seconds per frame on different phones, confirm existing progress stays, and verify slower playback helps when frames are missed.
- [ ] Confirm the QR and slider are visible together on a short phone, and enlarge a static and an animated code without losing the sharing sheet.
- [ ] Pass a long page from a computer monitor to a phone, at the normal size and enlarged. Both devices need a build with the version 2 QR format.
- [ ] Show a code from release 1.0.1 or earlier to a current receiver and verify it is still read.
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

- [x] Release signing is configured: the upload key stays outside the repository and in the repository secrets, see the [development guide](DEVELOPMENT.md). Keep a backup of the key.
- [x] Application and bundle IDs reviewed: `nu.goodjob.pocklino` on Android and iOS.
- [ ] After every dependency upgrade, verify that the merged release manifest still excludes `INTERNET` and `ACCESS_NETWORK_STATE`. Debug builds intentionally differ.
- [ ] Build iOS on macOS with Xcode, resolve signing and verify camera/file permissions on a real device. This has not been tested in the Windows workspace.
- [ ] Review store privacy declarations against actual dependencies, external-link behavior and operating-system backup behavior. Pocklino itself has no analytics pipeline; inspect transitive scanner SDK diagnostics and the difference between debug and release networking permissions.
- [ ] Review native release manifests/entitlements and avoid unnecessary permissions.
- [ ] Confirm bundled dependency/font licenses and brand asset sizes.
- [ ] Complete naming/trademark clearance separately; the project does not establish availability.
- [ ] Retain a known-good backup and verify migration/restore before any future schema change.

Do not advertise encrypted storage, secure time-locks, live collaboration, automatic IMDb metadata, reminders or push notifications; these are not features of this build.
