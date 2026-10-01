# Pocklino

**A little space for your life.**

Pocklino is a personal pocket for thoughts, plans, lists, films, and small lovely things. Its identity combines the warmth of paper with a clear, practical interface. It has no account, cloud, or recurring subscription implied by the identity.

## Logo and icon

The original mark is a butter-colored note tucked inside an ink-blue pocket, with a coral dot representing a small discovery. The curved seam gives it a little warmth without making it a literal character.

- `assets/brand/mark.svg`: scalable mark with warm oat background.
- `assets/brand/logo.svg`: horizontal lockup with tagline. All letters are vector outlines; the file has no external font dependency.
- `assets/brand/app-icon.png`: opaque 1024 x 1024 master suitable for app stores.
- `PocketMark` in `lib/design.dart`: equivalent Flutter vector painter.

Give the mark clear space of at least one quarter of its width. Do not stretch it, add shadows to the artwork itself, or change individual colors. Launcher assets use a square opaque background because the platform supplies its own mask.

Regenerate icons with `python tool/generate_icons.py` after installing Pillow and fonttools. This builds the original artwork directly from shapes and the included fonts; it needs no network access. Generated launcher icons are included for Android, iOS, web, and Windows.

## Palette

| Role | Hex |
| --- | --- |
| Oat canvas | `#F8F6EF` |
| Warm white cards | `#FFFEFA` |
| Ink / primary action | `#243C53` |
| Body text | `#293A40` |
| Secondary text | `#6B777B` |
| Borders | `#E3E5DC` |
| Mint | `#DCE9D5` |
| Butter | `#F4E4AA` |
| Peach | `#F3D8C9` |
| Sky | `#DCEAF0` |
| Lavender | `#E6E1EF` |
| Coral decoration | `#DD7C65` |
| Success | `#426B52` |

Use navy text on pastel cards. Coral is a decorative accent; do not use it for small text on oat. Dark mode uses deep blue-gray surfaces, warm white text, and butter actions. Content cards should retain sufficient text contrast regardless of theme.

## Typography

Lora, weight 500, supplies editorial headings. The lowercase wordmark uses Lora 600 with -1 px tracking at 26 px, matching the app. DM Sans, weights 400-700, supplies body text, controls, and the tagline. Both are bundled locally under the SIL Open Font License. Roboto and Noto Emoji are also bundled as fallback fonts.

- `assets/fonts/Lora-Variable.ttf`, family `Lora`
- `assets/fonts/DMSans-Variable.ttf`, family `DMSans`
- `assets/fonts/Roboto-Variable.ttf`, family `Roboto`
- `assets/fonts/NotoEmoji-Variable.ttf`, family `NotoEmoji`
- License texts: `Lora-OFL.txt`, `DMSans-OFL.txt`, `Roboto-OFL.txt`, and `NotoEmoji-OFL.txt`

Original sources: https://github.com/google/fonts/tree/main/ofl/lora and https://github.com/google/fonts/tree/main/ofl/dmsans .

Headings use 34/40 px on typical phone pages, section headings 22/28, body 15/23, and metadata 12/18. Use sentence case. Reserve lowercase styling for the wordmark.

## Interface

Phone navigation: My pocket, Collections, Open later. Large screens use a left rail. The home screen is a personal board of notes, checklists, movie cards, trips, and little notes. Content type chips filter the board; a single Create action starts new content.

Use 24 px mobile gutters, an 8 px spacing rhythm, 22 px card radii, and restrained borders. Large touch targets matter more than decorative density. Use subtle transitions that respect the system's reduced-motion setting.

The app's voice is friendly and concrete: Your pocket; Start with one little thing; Saved on this device; Keep in my pocket. Avoid accounts, follower counts, activity metrics, gamification, and invented personal activity.

Sharing is **Pass**, explained as **Share a copy**. Receiver previews content before keeping it. Tell users: You each keep your own copy. Later edits will not sync.

**Open later** is a local app convention: Pocklino hides the message until the chosen time using the receiving device's clock. It must not be described as tamper-proof encryption. The app should never promise reminders unless actual local notification scheduling is implemented.
