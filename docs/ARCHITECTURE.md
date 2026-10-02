# Architecture

Pocklino is a local Flutter application. Its features do not require a Pocklino backend or authentication service. The application code adds no analytics endpoint. External links open in the user's browser; sharing/export can hand a user-selected file to another application.

## Modules

| Module | Responsibility |
| --- | --- |
| `lib/main.dart` | Opens the notebook, offers retry without resetting data, applies appearance settings. |
| `lib/design.dart` | Day and evening palettes, themes, the three type voices, the vector pocket mark and the wordmark. |
| `lib/paper.dart` | The paper silhouettes (slip, receipt, ticket, tag, envelope, folder), the `Paper` widget that draws them, and small paper parts such as the pin, the seal and the tick box. |
| `lib/pocket.dart` | The pocket itself: the stitched bottom bar for phones, the side panel for wide windows and the coral create button. |
| `lib/models.dart` | `PocketEntry`, immutable checklist items, JSON validation and the reveal-date predicate. |
| `lib/store.dart` | Local transactions, serialized mutations, collections, settings, duplication, import and backup merge. |
| `lib/storage/` | Conditional native Sembast file / web Sembast IndexedDB adapters. |
| `lib/home.dart` | Responsive board of papers, the four places (Pocket, Collections, Open later, Archive), search/filtering, card actions and the create sheet. |
| `lib/editor.dart` | Type-specific editing on a full-size paper, autosave, checklist operations, reveal-time UI. |
| `lib/sharing.dart` | Pass/receive sheets, QR playback/scanning, bounded file reads and portable file export. |
| `lib/transfer.dart` | Versioned single-page envelopes, integrity checks, QR fragmentation and reassembly. |
| `lib/settings.dart` | Local preferences, backup/restore, examples and privacy explanations. |
| `lib/ui_helpers.dart` | Type labels, stickers and paper shapes, date display, the one-line text prompt and validated HTTP(S) link opening. |

## Data and commits

A `PocketEntry` is a note, checklist, movie, trip or letter. It contains stable IDs, creation/update timestamps, text, a collection, decoration, optional dates/link and checklist items. `received` distinguishes an imported copy from the sender's original. Examples are optional and explicitly marked; editing an example makes it the user's own page.

Native storage is `pocklino-v1.db` in the application documents directory. Web storage is the `pocklino-v1` IndexedDB database. The `pocklino` store's `state` record contains schema version 1, entries, collections and local preferences. There is no application-level database encryption.

`AppStore` serializes mutations through a future chain. Each action derives the next state, persists it in a Sembast transaction, then updates the in-memory notebook and notifies listeners. Failed writes leave the visible committed state unchanged; failed actions do not prevent later writes. Initialization validates stored data and can be retried without deleting it.

The editor debounces changes for 650 ms, keeps a revision counter so an earlier save cannot mark newer changes as saved, and serializes its save requests. Back navigation and passing await saving; inactive/paused lifecycle transitions also attempt a save. Abrupt process termination is not a guarantee of persisting keystrokes that have not reached a committed save.

The store caps a notebook at 10,000 pages and 1,000 collections. Models reject malformed types, invalid dates, duplicate item IDs and oversized fields. Imported pages receive fresh local page/item IDs and normalized flags, preserving the source content without overwriting an existing page.

## Single-page transfer

A transfer contains the actual page, not a URL to server-held content. It is readable data, not encrypted. Checksums detect damage; they do not establish sender identity or stop intentional alteration. There are two versions of the format: version 1 for copied codes and files, version 2 for QR codes. Both start from the same entry JSON:

1. Validate the entry and remove internal `pinned`, `archived`, `received` and `isExample` flags.
2. Omit optional default, empty and null fields, which the decoder reconstructs.
3. Encode the entry map as UTF-8 JSON, at most 64 KiB, and compute its SHA-256 digest.

### Version 1: copied codes and files

1. Build a JSON envelope with `e` (entry) and `h` (hex digest).
2. Encode that envelope with unpadded base64url and prefix `pocklino:1:`.

The token is uncompressed and has a 90,000-character limit. It contains no spaces or symbols that a text field or a messaging app could alter, and every release can read it, so copied codes and `.pocklino` files stay on this version.

Releases up to 1.0.1 also showed version 1 in their QR codes, as one code or as fragments:

```text
pocklino-part:1:<transfer-id>:<one-based-index>:<frame-count>:<fragment>
```

The transfer ID is the first 16 hex characters of the full token's SHA-256 digest. The receiver still accepts these codes, with fragments up to 700 characters.

### Version 2: QR codes

Version 1 fills a QR poorly: the text is uncompressed, wrapped twice, and its lowercase letters force the QR byte mode, which spends 8 bits on a character that carries 6. Version 2 sends the same entry JSON in about a third of the QR capacity:

1. Deflate the entry JSON (raw deflate, no zlib header).
2. Append the first 4 bytes of the JSON's SHA-256 digest.
3. Encode the result in base45 (RFC 9285) and prefix `POCKLINO:2:`.

The base45 alphabet is exactly the QR alphanumeric set, and the prefix is uppercase, so the whole code uses the alphanumeric mode at 5.5 bits a character. A token of up to 311 characters is one QR. A longer one is split into equal fragments of at most 276 characters:

```text
POCKLINO-PART:2:<transfer-id>:<one-based-index>:<frame-count>:<fragment>
```

The transfer ID is the first 8 hex characters, in uppercase, of the full token's SHA-256 digest. A fragment may itself contain colons, so a receiver splits on the first five only. Fragments are cut between base45 triplets and so never end in a space. At most 375 frames and 100,000 characters are accepted, which covers a 64 KiB entry that does not compress at all. The receiver stops inflating at 64 KiB, so a small crafted code cannot expand into a large allocation.

A receiver from release 1.0.1 or earlier cannot read version 2 QR codes; it can still receive the page through a copied code or file.

### Showing and scanning

No displayed code is denser than 57 by 57 modules (QR version 10): 311 alphanumeric characters at error-correction level M. Level M, not a higher one, because a code on a screen is lost to blur and resolution rather than to damage, and larger modules help more against those. Equal fragments mean every frame of a transfer gets the smallest code that the page allows. The code has a white quiet zone of four modules and is drawn on whole device pixels. It grows with the window, up to 440 logical pixels, and both single and animated codes can be enlarged to the full window; an enlarged animated code keeps playing.

Playback starts at one second per frame. A visible sharing-speed slider ranges from two seconds to 0.4 seconds per frame, and pause/manual advance remains available. Speed changes retain the same fragments so the receiver can keep its progress. The scanner examines a camera picture every 50 ms instead of the plugin's default 250 ms, which gives each frame of a moving code several attempts.

The assembler accepts frames in any order and ignores duplicates, rejects conflicting pieces or mixed transfers, then verifies the reconstructed token and its checksum before showing a preview. The receiver displays the number of collected pieces and remembers them across loops; the user can reset a partial transfer.

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
