# Architecture

Pocklino is a local Flutter application. Its features do not require a Pocklino backend or authentication service. The application code adds no analytics endpoint. External links open in the user's browser; sharing/export can hand a user-selected file to another application.

## Modules

| Module | Responsibility |
| --- | --- |
| `lib/main.dart` | Opens the notebook, offers retry without resetting data, applies appearance settings. |
| `lib/design.dart` | Brand palette, light/dark themes, bundled typography and vector pocket mark. |
| `lib/models.dart` | `PocketEntry`, immutable checklist items, JSON validation and the reveal-date predicate. |
| `lib/store.dart` | Local transactions, serialized mutations, collections, settings, duplication, import and backup merge. |
| `lib/storage/` | Conditional native Sembast file / web Sembast IndexedDB adapters. |
| `lib/home.dart` | Responsive board, collections, search/filtering, Later view and card actions. |
| `lib/editor.dart` | Type-specific editing, autosave, checklist operations, reveal-time UI. |
| `lib/sharing.dart` | Pass/receive sheets, QR playback/scanning, bounded file reads and portable file export. |
| `lib/transfer.dart` | Versioned single-page envelopes, integrity checks, QR fragmentation and reassembly. |
| `lib/settings.dart` | Local preferences, backup/restore, examples and privacy explanations. |
| `lib/ui_helpers.dart` | Type labels/stickers, date display and validated HTTP(S) link opening. |

## Data and commits

A `PocketEntry` is a note, checklist, movie, trip or letter. It contains stable IDs, creation/update timestamps, text, a collection, decoration, optional dates/link and checklist items. `received` distinguishes an imported copy from the sender's original. Examples are optional and explicitly marked; editing an example makes it the user's own page.

Native storage is `pocklino-v1.db` in the application documents directory. Web storage is the `pocklino-v1` IndexedDB database. The `pocklino` store's `state` record contains schema version 1, entries, collections and local preferences. There is no application-level database encryption.

`AppStore` serializes mutations through a future chain. Each action derives the next state, persists it in a Sembast transaction, then updates the in-memory notebook and notifies listeners. Failed writes leave the visible committed state unchanged; failed actions do not prevent later writes. Initialization validates stored data and can be retried without deleting it.

The editor debounces changes for 650 ms, keeps a revision counter so an earlier save cannot mark newer changes as saved, and serializes its save requests. Back navigation and passing await saving; inactive/paused lifecycle transitions also attempt a save. Abrupt process termination is not a guarantee of persisting keystrokes that have not reached a committed save.

The store caps a notebook at 10,000 pages and 1,000 collections. Models reject malformed types, invalid dates, duplicate item IDs and oversized fields. Imported pages receive fresh local page/item IDs and normalized flags, preserving the source content without overwriting an existing page.

## Single-page transfer, version 1

A transfer contains the actual page, not a URL to server-held content. It is uncompressed, readable data. Checksums detect damage; they do not establish sender identity or stop intentional alteration.

1. Validate the entry and remove internal `pinned`, `archived`, `received` and `isExample` flags.
2. Encode the entry map as UTF-8 JSON and compute its SHA-256 digest.
3. Build a JSON envelope with `e` (entry) and `h` (hex digest).
4. Encode that envelope with unpadded base64url and prefix `pocklino:1:`.

This full token is used for copied codes and `.pocklino` files. Its entry JSON limit is 64 KiB; the encoded token also has a 90,000-character limit. Optional default, empty and null fields are omitted and reconstructed by the decoder, reducing the size of short notes without changing the v1 format. A token up to 650 characters is displayed in one QR.

Longer tokens are split into 400-character payload fragments:

```text
pocklino-part:1:<transfer-id>:<one-based-index>:<frame-count>:<fragment>
```

The transfer ID is the first 16 hex characters of the full token's SHA-256 digest. At most 224 frames are accepted, with the same total encoded-size bound. The receiver also accepts the original v1 encoder's fragments up to 700 characters for compatibility. Playback loops every 650 ms and supports pause/manual advance. The assembler accepts frames in any order and ignores duplicates, rejects conflicting pieces or mixed transfers, then verifies the reconstructed token and envelope before showing a preview. The user can reset a partial transfer.

Receiving never silently saves content. A preview offers **Keep in my pocket**, which imports a new independent copy. There is no collaborative merge or background synchronization. Later changes stay on the device that made them.

## Open later

A received entry is locked in the interface when `received` is true and the local device clock is before `unlockAt`. The sender can still edit their own original. The interface hides a sealed letter's body, items and URL in previews and normal browsing/search; it retains the title and opening time. Passing or duplicating a received sealed entry is rejected by the relevant app operations.

This is a surprise convention, not cryptographic access control. The complete plaintext content exists in the transfer and local database, and readable backups may contain it. A recipient can inspect the data or change the clock. There is no trusted time server, deferred key delivery or notification scheduling.

Dates are serialized as UTC ISO-8601 values and displayed in the device's local timezone. Reveals are refreshed while the interface is active; no background service is required.

## Backups

A backup is JSON with `format: "pocklino-backup"`, `version: 1`, an export timestamp, entries, collections and preferences. Export/import is capped at 10 MB (10 x 1024 x 1024 bytes). File readers bound incoming data while reading it, and the store validates the entire document before committing.

Restore preserves existing entries. Equal IDs with identical serialized content are skipped; an equal ID with different content becomes a new page. Collections are combined. Preferences restore only into an empty notebook without an owner name. Invalid backups produce no partial merge. Backup files are readable and should be handled like the notes themselves.

## Platform boundaries

- Camera permission is requested only after **Open camera**. The scanner owns camera lifecycle/disposal. Native Android uses the plugin's bundled barcode implementation. Web explicitly uses the local ZXing JavaScript file at `web/assets/zxing.min.js`, without a decoder CDN request.
- Windows has no scanner implementation; receiving supports files and pasted codes. Mobile opens a native share sheet; desktop/web exports a file through the platform picker/download flow.
- Web release builds use `--no-web-resources-cdn` to bundle renderer assets. Fonts are bundled. Generated service-worker caching requires an initial load/activation and must be verified in the target browser; IndexedDB and cached app assets are separate storage concerns.
- Android release manifests remove `INTERNET` and `ACCESS_NETWORK_STATE` contributed by dependencies, so the release app process has no networking permission. Debug builds retain networking for Flutter tooling; bundled third-party scanner libraries can include diagnostics behavior. External links are delegated to a separate browser process.
- Android disables automatic application backup with `allowBackup="false"`. iOS operating-system backup remains subject to device settings. No claim of excluding every operating-system backup mechanism is made.
- There is no Pocklino server, account, automatic metadata lookup or advertising. Pocklino itself adds no analytics; this is not a claim that every transitive SDK lacks diagnostic code.
