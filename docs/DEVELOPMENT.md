# Development guide

Pocklino has Android, iOS, web and Windows targets. The tested baseline is Flutter 3.29.3 with its bundled Dart 3.7.2 and the committed `pubspec.lock`.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

The GitHub Actions workflow in `.github/workflows/ci.yml` runs the same checks on Flutter 3.29.3 for every push to `main` and every pull request, then builds the web app and a debug APK. Bump the pinned Flutter version there and in `release.yml` together with the README baseline.

## Looking at the screens

The tests lay text out in a placeholder font, so they cannot show how a screen looks. A separate tool draws the real screens with the bundled fonts:

```sh
flutter test tool/screens_test.dart
```

It writes about 80 PNG files to `build/screens`, or to the folder named in `SCREENS_DIR`: every place, sheet, editor, dialog and picker, by day and in the evening, on a phone and a wide window. A layout overflow fails the run. Look through the pictures after a change to `lib/design.dart`, `lib/paper.dart` or `lib/pocket.dart`.

## Web

```sh
flutter build web --no-web-resources-cdn
python -m http.server 5178 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:5178`. Fonts, the QR decoder and the renderer are bundled, so the app makes no outside requests. Camera access in a browser needs HTTPS or a loopback address. To host the build, serve `build/web` from any static HTTPS host; the notes stay in each visitor's browser.

`tool/browser_smoke.cjs` drives the built app in Chrome: it saves a note and reloads, decodes the rendered QR code and receives the page in a second browser context. With the server above running:

```sh
npm install --no-save --prefix .dart_tool/browser-check playwright
node tool/browser_smoke.cjs
```

## Android

Minimum SDK 23, compile and target SDK 36, NDK `27.0.12077973`, AGP 8.12.1, Kotlin 2.2.0, Gradle 8.13 and Java 17 or a compatible newer JDK. The application ID is `nu.goodjob.pocklino`.

```sh
flutter build apk --debug
flutter build apk --release
```

The release manifest in `android/app/src/release` removes `INTERNET` and `ACCESS_NETWORK_STATE`, including the ones that the scanner dependencies bring along, so a release build cannot use the network. Debug builds keep networking for the Flutter tools. Check the merged permissions again after upgrading a dependency:

```sh
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

## Windows

Install the Visual Studio desktop C++ workload. With Visual Studio 2022, `flutter build windows --release` works as it is. Flutter 3.29.3 picks the wrong generator for Visual Studio 2026; `windows/build_release.ps1` works around that, as described in the [Windows notes](../windows/README.md). Keep the whole `Release` folder together: the DLLs and the `data` folder are required.

## iOS

The Xcode project, the icons and the camera usage text are included, with the bundle ID `nu.goodjob.pocklino`. Building needs a Mac with Xcode and a signing team. No iOS build has been made or tested.

## Releasing

Release builds for Android are signed with an upload key that is not in the repository. `android/app/build.gradle.kts` reads it from `android/key.properties`; when that file is missing, a release build falls back to the debug key, which is fine for local testing but must never be distributed.

The key lives in `android/app/upload-keystore.jks`, with its passwords in `android/key.properties`. Both are ignored by git. Keep a backup of both outside the repository: an app signed with a different key cannot update an installed one, so losing the key means everyone has to uninstall before the next version, and uninstalling removes their notes.

To create a key on another machine:

```powershell
keytool -genkeypair -v -keystore android\app\upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

and write `android/key.properties`:

```
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=upload-keystore.jks
```

GitHub Actions publishes releases. The key is stored as the repository secrets `ANDROID_KEYSTORE_BASE64` (the `.jks` file, base64 encoded), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD` and `ANDROID_KEY_ALIAS`. To release:

1. Bump `version` in `pubspec.yaml` and `appVersion` in `lib/settings.dart`; a test keeps the two in step. The number after `+` must grow with every release.
2. Write the notes for the version in `docs/release-notes/v<version>.md`. Without that file the notes are generated from the commits.
3. Commit, then push a tag named after the version:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow in `.github/workflows/release.yml` checks that the tag matches `pubspec.yaml`, builds the signed APK and the Windows ZIP, and attaches both with their checksums to a GitHub Release named after the tag. Running the workflow by hand from the Actions page builds the same two files as workflow artifacts and publishes nothing, which is a way to try a build before tagging.

## Icons and fonts

`python tool/generate_icons.py` redraws the launcher icons, the favicon and the logo files; it needs Pillow and fonttools. The app bundles static font files, one per weight, because Flutter picks a face by the weight stored in the file. `DMSans-Variable.ttf` and `Lora-Variable.ttf` in `assets/fonts` are sources for the icon tool and are not bundled.
