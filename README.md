# Pocklino

**A little space for your life.**

A Flutter notebook for thoughts, groceries, films, adventures and little surprises. Everything starts on your device. There are no accounts or Pocklino servers. Pocklino itself adds no analytics or advertising.

This repository contains the first working app and its original brand assets. It is not a signed store release.

## Inside your pocket

- Every kind of page is its own paper: a note slip, a receipt for a list, a cinema ticket, a luggage tag, an envelope. They lie in a stitched ink-blue pocket, by day or in the evening.
- Notes with personality: emoji, paper colors, collections, pinning, search and archive.
- Checklists with quick ticking, completed items grouped below, and reset/duplicate controls for reuse.
- Movie cards with a link and watched status; trip pages with dates, plans and packing lists.
- Letters with sender/recipient names and an optional **Open later** date and time.
- **Pass** a copy using one QR, an animated QR sequence, a copied code or a `.pocklino` file. Preview received content before keeping it.
- Local autosave, light/dark appearance, optional example pages, and portable JSON backup/restore.

Passing creates independent copies. Changes do not sync between people. Open later is a friendly reveal convention based on the receiving device's clock; transferred content is readable and is not securely time-locked or encrypted. Titles and opening dates remain visible.

Movie information is entered by the user; IMDb links open externally. Automatic movie metadata, notifications and scheduled reminders are not implemented.

## Preview builds

- [Android preview APK](artifacts/pocklino-android-preview.apk): optimized build signed with the development key. Its merged manifest excludes `INTERNET` and `ACCESS_NETWORK_STATE`.
- [Windows preview ZIP](artifacts/Pocklino-Windows.zip): extract the complete archive and run `pocklino.exe`; keep the adjacent DLLs and data directory. The executable passed a brief startup smoke check and drew its window; native dialogs were not exercised.

These are local preview artifacts, not signed store releases. Physical camera handoff, native share sheets, and iOS builds still need verification.

## Run it

The project was developed with Flutter 3.29.3 / Dart 3.7.2. Install Flutter and the toolchain for your chosen platform, then run from this directory:

```sh
flutter pub get
flutter run -d chrome
```

For Windows, install the Visual Studio desktop C++ workload and use:

```sh
flutter run -d windows
```

This Windows preview was built with the project-local [release build script](windows/build_release.ps1), which handles Flutter 3.29 tool selection with Visual Studio 2026 without modifying the Flutter SDK. Run `.\windows\build_release.ps1` from PowerShell for the same build path.

Windows supports creating and displaying QR codes, receiving pasted codes and files, and saving portable files. Camera scanning is unavailable in the Windows app. Android/iOS provide the intended camera experience; native sharing and scanning still need physical-device verification.

A new notebook starts empty. Choose **Take a peek at an example pocket** to explore the design; examples can be removed separately in Settings.

## Build and check

Verified on October 2, 2026: `flutter analyze` reports no issues and all **49 automated tests pass**. The release web preview also passed persistence after reload, decoding its actual rendered QR with the bundled decoder, preview/import into a separate browser context, phone layout, and dark-theme checks. The inspected browser run recorded no external requests and no JavaScript errors. See the [verification report](artifacts/browser-verification.json) and [remaining release checks](docs/QA.md). Physical-device camera handoff and iOS testing remain outstanding.

```sh
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
python -m http.server 5178 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:5178`. Use a static HTTPS host for a deployed web build: camera access requires a secure context, with loopback addresses allowed for development. The host serves application files; notes stay in the browser's local database.

Fonts, the web QR decoder and renderer resources are bundled locally. Flutter's generated service worker supports caching after the initial load. Offline startup depends on activation and browser cache availability; verify a fresh offline reload and scanning for each release. A first-ever web visit requires the application files, and clearing site data removes saved notes and cached app files.

For an optimized Android APK signed with the development key:

```sh
flutter build apk --release
```

Android configuration: minimum SDK 23, compile/target SDK 36, NDK `27.0.12077973`, AGP 8.12.1, Kotlin 2.2.0, Gradle 8.13, Java 17 or a compatible newer JDK. Install the matching SDK components and accept their licenses. The package ID is `se.goodjob.pocklino`. Production signing is not configured; the release configuration uses a development/debug key and is only suitable for local installation. Use `flutter build apk --debug` for development tooling.

The Android release manifest removes `INTERNET` and `ACCESS_NETWORK_STATE`, including permissions introduced by scanner dependencies. The release app process cannot make network requests; external links still open through the browser. Debug builds retain networking for Flutter tooling, and third-party scanner libraries may include diagnostics behavior. Pocklino does not implement an analytics pipeline.

The iOS source scaffold, icon set and camera usage description are included. Building and device testing require macOS, Xcode, a signing team and device-specific review. An iOS build was not tested in this Windows environment.

## Keep your data

Native platforms use a local Sembast database; web uses IndexedDB for that browser profile and origin. Export a backup before moving devices or removing the app. There is no account-based recovery. Browser data eviction, clearing site data or uninstalling can remove local notes.

Backups are readable JSON files with a 10 MB limit. Restore validates the complete file before saving, skips exact duplicates and preserves conflicting versions as separate copies. Passing one page supports up to 64 KiB of entry JSON; large pages may need many QR frames, so files are more convenient.

Pocklino does not upload your notes itself. Choosing an external messaging/cloud app for a file, or opening a web link, uses that service. Android automatic application backup is disabled; iOS device/iCloud backup behavior is controlled by the operating system and the user's settings. Local storage and export files have no application-level encryption.

## Brand and implementation

The identity pairs an ink-blue pocket with a butter-colored note and coral dot, and the interface is that mark at full size: paper things with ink outlines and hard shadows, tucked into a stitched pocket bar with a coral button. Bricolage Grotesque titles, DM Sans text and DM Mono small print make it read like printed tickets and receipts.

- [Brand guide](docs/BRAND.md), [vector logo](assets/brand/logo.svg), [logo preview](artifacts/logo-preview.png), [mark](assets/brand/mark.svg), [1024 px app icon](assets/brand/app-icon.png)
- [Architecture and transfer format](docs/ARCHITECTURE.md)
- [Verification and release checklist](docs/QA.md)

Regenerate launcher artwork with `python tool/generate_icons.py` after installing Pillow and fonttools. Font and decoder licenses are included beside their assets. The name is a project identity; no trademark clearance is asserted.
