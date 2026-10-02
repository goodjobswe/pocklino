# Pocklino

**A little space for your life.**

Pocklino is a personal pocket for thoughts, plans, lists, movies, and small lovely things. The interface is the mark at full size: bright paper things kept in an ink-blue pocket. It has no account, cloud, or recurring subscription implied by the identity.

## Logo and icon

The original mark is a butter-colored note tucked inside an ink-blue pocket, with a coral dot representing a small discovery. The curved seam gives it a little warmth without making it a literal character.

- `assets/brand/mark.svg`: scalable mark with warm oat background.
- `assets/brand/logo.svg`: horizontal lockup with tagline. All letters are vector outlines; the file has no external font dependency.
- `assets/brand/app-icon.png`: opaque 1024 x 1024 master suitable for app stores.
- `PocketMark` and `Wordmark` in `lib/design.dart`: the equivalent Flutter vector painter and the lowercase name.

Give the mark clear space of at least one quarter of its width. Do not stretch it, add shadows to the artwork itself, or change individual colors. Launcher assets use a square opaque background because the platform supplies its own mask.

Regenerate icons with `python tool/generate_icons.py` after installing Pillow and fonttools. This builds the original artwork directly from shapes and the variable font sources in `assets/fonts`; it needs no network access. Generated launcher icons are included for Android, iOS, web, and Windows.

The mark keeps its own four colors: oat `#F8F6EF`, ink `#243C53`, butter `#F4E4AA` and coral `#DD7C65`.

## The idea: paper things in a pocket

Everything a pocket holds is made of paper, and every kind of page is cut like the thing it is. The shape says what a page is before any word is read, so cards carry no type icon.

| Page | Paper | Told apart by |
| --- | --- | --- |
| Note | Slip | A folded corner |
| Checklist | Receipt | A torn zigzag edge, a dashed rule and a tally |
| Movie | Ticket | Two notches and a perforated stub that says to watch or watched |
| Trip | Luggage tag | Cut corners and an eyelet |
| Letter | Envelope | A flap with a coral wax seal; a lock on the seal while it is closed |
| Collection | Folder | A tab |

A pinned page carries a coral pin. An example page carries a small stamp. A paper that is not there yet, such as an empty pocket or the tile for a new collection, is a dashed outline.

The pocket is the navigation. On a phone it is a bar along the bottom with a stitched, V-shaped edge; pages slide in behind it, and the coral button from the mark sits in the notch and creates something new. On a wide window the pocket is a panel down the left side with the same stitching.

The shapes are drawn by `PaperBorder` and `Paper` in `lib/paper.dart`; the bar and the side panel are in `lib/pocket.dart`.

## Surfaces

Shapes are flat. There are no gradients and no blurred shadows.

- By day a paper has a 1.3 px ink outline and a hard 3 px shadow. It sinks into the shadow when pressed and lifts a little under a pointer.
- In the evening a paper is a dark tint with a thin edge in its own color and no shadow.
- Papers have 6 px corners. Controls (buttons, fields, chips) have 10 to 12 px corners. Sheets rise from the bottom with 22 px corners.
- Stitching is a dashed butter line, 6 px on and 5 px off.

## Palette

| Role | Day | Evening |
| --- | --- | --- |
| Desk, behind everything | `#F4F0E6` | `#0E1822` |
| Ink: text, outlines, primary button by day | `#1D3145` | `#F1ECDF` |
| Secondary text | `#5E6D7A` | `#9FB0BF` |
| Sheets, dialogs, menus, fields | `#FFFDF7` | `#182634` |
| Pocket: bottom bar and side panel | `#243C53` | `#1A2A38` |
| Text on the pocket | `#F6F2E6` | `#F1ECDF` |
| Butter: stitching, selected, primary button in the evening | `#F8D873` | `#F8D873` |
| Coral: create button, seal, pin | `#E8785E` | `#E8785E` |

The six papers a page can be written on. A page stores the number, so the order must stay.

| Number | Paper | Day | Evening |
| --- | --- | --- | --- |
| 0 | Paper | `#FBF8EE` | `#27333F` |
| 1 | Butter | `#F8D873` | `#3A3420` |
| 2 | Mint | `#BCE2B6` | `#22382B` |
| 3 | Peach | `#F6B7A1` | `#41291F` |
| 4 | Sky | `#B2D8EE` | `#1E3545` |
| 5 | Lilac | `#D2C7F0` | `#2F2A45` |

Writing on paper is ink by day and warm white in the evening. Small print on paper is the same color at 78 percent by day and 66 percent in the evening, which keeps it at a contrast of at least 4.5 to 1 on every paper. Text on butter and coral is always the dark ink. All of these values live in `PocketPalette` in `lib/design.dart`.

## Typography

- **Bricolage Grotesque** 700 for titles: 31 px page titles on phones and 38 px on wide windows, 19 px on cards, 26 to 31 px in the editor.
- **DM Sans** 400 to 700 for reading and controls: 13 px on cards, 16 px in the editor, 15 px on buttons.
- **DM Mono** 400 and 500 for small print, set in capitals with wide spacing at 10 to 11 px: collection names, dates, tallies and the status under an editor title.
- **Lora** 600 for the lowercase wordmark only, with -1 px tracking at 26 px, matching the logo.
- Roboto and Noto Emoji are fallbacks. Emoji are drawn in one color, like a rubber stamp.

Flutter picks a face by the weight stored inside each font file. A single variable file therefore drew every weight from the regular outlines, so each weight in use now has its own static file. They were cut with fontTools `instancer` from the variable sources: Bricolage Grotesque at `wght 700, opsz 24, wdth 100`; DM Sans at `wght 400, 500, 600, 700` with `opsz 14`; Lora at `wght 600`. DM Mono ships as static files.

- `assets/fonts/Bricolage-Bold.ttf`, family `Bricolage`
- `assets/fonts/DMSans-Regular.ttf`, `-Medium`, `-SemiBold`, `-Bold`, family `DMSans`
- `assets/fonts/DMMono-Regular.ttf`, `-Medium`, family `DMMono`
- `assets/fonts/Lora-SemiBold.ttf`, family `Lora`
- `assets/fonts/Roboto-Variable.ttf`, `NotoEmoji-Variable.ttf`, fallback families
- `assets/fonts/DMSans-Variable.ttf` and `Lora-Variable.ttf` are sources for the icon tool and are not bundled in the app.
- License texts: `Bricolage-OFL.txt`, `DMSans-OFL.txt`, `DMMono-OFL.txt`, `Lora-OFL.txt`, `Roboto-OFL.txt` and `NotoEmoji-OFL.txt`

All are under the SIL Open Font License. Original sources: https://github.com/google/fonts/tree/main/ofl/bricolagegrotesque , https://github.com/google/fonts/tree/main/ofl/dmsans , https://github.com/google/fonts/tree/main/ofl/dmmono and https://github.com/google/fonts/tree/main/ofl/lora .

Use sentence case. Reserve lowercase styling for the wordmark and capitals for the small print.

## Interface

The pocket has four places: Pocket, Collections, Open later and Archive. The home screen is a board of papers in two columns on a phone and up to four on a wide window. Its header is one line with the name of the place and a count, then search and a row of filters that show each kind by its paper shape. A single coral button starts new content, and its sheet offers the five kinds as the papers they will become.

A page opens as its own paper at full size. What is written on it (title, text, list items, a movie's watched switch, a trip's dates) sits on the paper; settings that are not part of the page, such as a link or a letter's opening time, lie on the desk below. The collection and the paper color are chosen above the page, and the state of saving is shown in small print under the title.

Use 16 px gutters on phones and 36 px on wide windows, an 8 px spacing rhythm, and large touch targets rather than decorative density. Movement is short and physical: a paper sinks when pressed. Respect the system's reduced-motion setting.

The app's voice is friendly and concrete: My pocket; Start with one little thing; Saved on this device; Keep in my pocket. Avoid accounts, follower counts, activity metrics, gamification, and invented personal activity.

Sharing is **Pass**, explained as **Share a copy**. Receiver previews content before keeping it, shown as the paper it will be. Tell users: You each keep your own copy. Later edits will not sync.

**Open later** is a local app convention: Pocklino hides the message until the chosen time using the receiving device's clock. It must not be described as tamper-proof encryption. The app should never promise reminders unless actual local notification scheduling is implemented.
