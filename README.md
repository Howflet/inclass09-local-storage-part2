# In-Class 09 / Local Storage Part II: Card Catalogue

**Student / course / pathway:** Kevon Fletcher / Mobile Application Development / **Undergraduate** (prompts 1-3 + AI Lab U1, U2)

**Flutter / Dart / target:** Flutter 3.47.2 (stable), Dart 3.13.2 on macOS (Apple Silicon). Target: Android emulator `Espresso_Pixel` (sdk gphone64 arm64, `emulator-5554`), the same emulator and installation used for Part I (In-Class 08).

**Packages:** unchanged from Part I. `pubspec.lock` is identical to the Part I lock file: sqflite 2.4.4+1, path_provider 2.1.6, path 1.9.1. I added no new dependencies. The only `pubspec.yaml` changes are the description and one asset entry (`assets/cards/card_back.png`).

**Database:** file `MyDatabase.db` (same name as Part I) in the app documents directory. Schema version **1 → 2**. Part I table `my_table(_id, name, age)` is kept and never dropped or recreated.

## Setup / run / build / test commands

```bash
flutter pub get
flutter emulators --launch Espresso_Pixel
flutter run -d emulator-5554                       # debug run
flutter analyze 2>&1 | tee evidence/analysis_output.txt
flutter build apk --release                         # -> build/app/outputs/flutter-apk/app-release.apk
```

No automated test suite is required for this pathway and none is included. All tests below were run by hand on the emulator.

## What changed from Part I

| Layer | File | What it does |
| --- | --- | --- |
| Schema / migration | `lib/database_helper.dart` | Version raised to 2 (`:9`). `onConfigure` runs `PRAGMA foreign_keys = ON` (`:34-35`). `onCreate` builds the Part I table and the catalogue tables (`:44`). `onUpgrade` only runs `createCatalogueTables` when `oldVersion < 2` (`:52-53`). `createCatalogueTables` (`:70`) creates `folders`, `cards` (FK `ON DELETE CASCADE`, `:86`) and `idx_cards_folder_id` (`:90`). `diagnostics()` (`:95`) is read-only. |
| Models | `lib/models/folder.dart`, `lib/models/card_record.dart` | `Folder` and `CardRecord` with explicit `fromMap`/`toMap`. `CardRecord` avoids clashing with Material's `Card`. |
| Repository | `lib/catalogue_repository.dart` | `insertFolder` (`:46`), `getFoldersWithCounts` (LEFT JOIN + COUNT, `:62`), `getFolder`, `deleteFolder` (transaction, `:84-85`), `getCards(folderId)` (`:108`), `getCard`, `insertCard` (`:129`), `updateCard` (`:134`), `deleteCard` (`:147`). Every value is bound with `?`/`whereArgs`. No SQL lives in a widget. |
| Screens | `lib/screens/folders_screen.dart`, `cards_screen.dart`, `card_form_screen.dart`, `diagnostics_screen.dart` | Folder list with counts, one folder's cards, one Add/Edit form, a read-only diagnostics screen. |
| Part I screen | `lib/screens/roster_screen.dart` | The Part I roster, moved out of `main.dart` unchanged. You open it from the people icon on the home app bar. |
| Image | `lib/widgets/card_image.dart`, `assets/cards/card_back.png` | Shows a bundled asset or URL, and a suit-symbol placeholder for null, blank, malformed, missing, or failed references. |

**Seeding:** none. The migration only creates empty tables, so nothing can be reseeded on relaunch. T2 started with zero folders.

**Delete rule:** `cards.folder_id → folders.id ON DELETE CASCADE`. In this lab a card belongs to its folder, so deleting the folder deletes its cards. The confirmation dialog says so and shows the card count. **Alternatives:** `ON DELETE RESTRICT` blocks deleting a folder that still has cards. Reassigning moves the cards to an "Unfiled" folder first. Archiving sets a `deleted_at` flag instead of deleting. Restrict or archive would be better whenever the children matter more than the grouping (e.g. invoices under a customer, or photos under an album the user might delete by mistake).

**Validation (UI, before any write):** the folder name is trimmed and must be non-empty. Duplicate names are caught from SQLite's UNIQUE error and shown in the dialog, with the input kept. `ConflictAlgorithm.replace` is never used. A card title is trimmed and must be non-empty. The suit must be exactly one of Hearts/Diamonds/Clubs/Spades. The folder must be an existing folder ID from the dropdown. Notes are stored as `''` when empty. A blank image reference is stored as SQL `NULL`.

**Async / busy / error handling:** each screen has one `_busy` flag that disables its buttons while a write is pending. The form has its own `_busy`, and `PopScope` blocks Back mid-write. `mounted` is checked after every `await`. A failed write keeps the input and shows `Save failed (...)`. A successful write whose re-read fails says `Saved, but refresh failed. Tap Refresh (do not save again).` A zero-row update or delete is reported as "no longer exists / not found", never as success.

**Image-reference choice:** **bundled asset** (`assets/cards/card_back.png`, a simple card-back pattern I generated for this project with a short Python script). It works offline and can't be deleted at runtime. The trade-off is that it adds to the APK size and changing it needs a new build. Most cards keep `image_ref = NULL` and show their suit symbol. `CardImage` can also render `https://` URLs with a loading spinner and an error fallback. However, the app manifest does not request the INTERNET permission, so in the release build any URL will simply show the fallback. No test depends on the network.

## Baseline before upgrade (Part I, version 1)

Captured before any version-2 code was installed. Source: `evidence/T1_before.png` and `evidence/T1_before_query.txt` (a read-only `sqlite3 -readonly` query of a copy of the device DB pulled with `adb exec-out run-as … cat`, saved in the local `../backup/` folder, not committed).

`PRAGMA user_version = 1`. `my_table`: **ID 2 River 35, ID 3 Acorn 0, ID 4 Oak 130. Count 3.**

## Test matrix (T1-T6), run 2026-10-09 on `emulator-5554`

| Test | Action / input | Expected | Observed IDs / values / counts | Result |
| --- | --- | --- | --- | --- |
| **T1a** Upgrade | Force-stopped the Part I app, then installed the v2 debug APK **over** it with `adb install -r` (keeps app data; no uninstall, no Clear storage). Launched, then opened Diagnostics and the Part I roster. | `user_version` 2, new tables and index exist, FK on, Part I IDs/values unchanged | Opened without an error screen. Diagnostics: `user_version: 2`, `foreign_keys: 1`, tables `cards, folders, my_table`, `foreign_key_list(cards)` → `folders(id)` `on_delete: CASCADE`, `index_list(cards)` → `idx_cards_folder_id`. `my_table`: **2 River 35, 3 Acorn 0, 4 Oak 130, count 3** (identical to baseline). Roster screen shows the same 3 rows. Evidence: `T1a_diagnostics.png`, `T1a_diagnostics_log.txt`, `T1a_roster_after_upgrade.png` | **Pass** |
| **T1b** Fresh create | Separate disposable target: secondary Android user profile `Disposable09` (user 10) on the same emulator, which has its own empty app data. Installed the **release** APK there (`adb install --user 10`). Opened Diagnostics, the roster, then created folder "Fresh" and opened it. | Both Part I and catalogue tables created; empty folder opens without a schema error | Path `/data/user/10/.../MyDatabase.db`, `user_version: 2`, `foreign_keys: 1`, same 3 tables / FK / index, `part_one_count: 0`. Roster: "Guests in database: 0". Folder "Fresh" got **ID 1** and opened to "No cards in this folder yet (folder ID 1)". Evidence: `T1b_fresh_diagnostics.png`, `T1b_fresh_diagnostics_log.txt`, `T1b_fresh_roster_empty.png`, `T1b_fresh_empty_folder.png` | **Pass** |
| **T2** Parent-child create | On the upgraded target: created "Moon", then "Lantern". Added "Echo" (Hearts, `image_ref = assets/cards/card_back.png`) and "Echo" (Spades, no image) to Moon. Added "Beacon" (Diamonds, image left blank → NULL) to Lantern. | 3 distinct card IDs, Moon 2, Lantern 1, each card only under its folder | Folders: **Moon = ID 1, Lantern = ID 2**. Cards: **Echo/Hearts = ID 1 (folder 1), Echo/Spades = ID 2 (folder 1), Beacon/Diamonds = ID 3 (folder 2, `image_ref` NULL)**. Moon shows 2 cards, Lantern 1. Query confirms `folder_id` values. Evidence: `T2_cards.png` (Moon), `T2_folders.png`, `query_log.txt` "T2" block | **Pass** |
| **T3** Edit identity | Opened card **ID 1**, changed the title to "Echo revised", added notes "Moonlit test note", Save. Opened card **ID 2**, typed " SHOULD NOT SAVE" into the title, Cancel. | Save affects 1 row; only ID 1 changes; Cancel writes nothing; counts stay 2/1 | "Updated card ID 1: 1 row affected." Then "Edit of card ID 2 cancelled; nothing was written." Query: ID 1 = Echo revised / Hearts / "Moonlit test note"; ID 2 still "Echo" / Spades / ''; ID 3 unchanged. Moon 2, Lantern 1. Evidence: `T3_save.png`, `T3_cancel.png`, `query_log.txt` "T3" block | **Pass** |
| **T4** Restart persistence | Before: Moon(1): cards 1 "Echo revised" Hearts + 2 "Echo" Spades; Lantern(2): card 3 "Beacon" Diamonds; counts 2/1; PID **16438**. Opened system **App info → Force stop → OK** (not Clear storage), went Home, relaunched from the launcher intent. | Same folders, IDs, values, counts; no duplicates | PID after force stop: none. PID after relaunch: **18204** (new process). Home: "Folders refreshed: 2 folder(s), 3 card(s)", Lantern ID 2 · 1 card, Moon ID 1 · 2 cards. Moon shows IDs 1 and 2 with the same titles/suits/notes; Lantern shows ID 3 Beacon. `sqlite_sequence`: cards 3, folders 2 (nothing reinserted). Part I rows still 2/3/4. Evidence: `T4_before.png`, `T4_after.png`, `T4_after_moon.png`, `T4_pids.txt`, `query_log.txt` "T4 BEFORE/AFTER" | **Pass** |
| **T5** Card delete & cascade | In Moon: Delete card ID 2 → **Cancel**. Delete card ID 2 → **Delete**. Home: Delete folder ID 1 "Moon" → **Cancel**. Then → **Delete folder**. | Cancels change nothing; card delete returns 1, Moon becomes 1; folder delete removes 1 parent and its remaining card; Lantern/Beacon intact; no card references Moon | "Delete of card ID 2 cancelled; nothing was written." (Moon still 2.) "Deleted card ID 2: 1 row affected." (Moon 1.) Folder dialog: 'Delete folder ID 1, "Moon"? Its 1 card(s) will also be deleted (ON DELETE CASCADE).' Cancel → "Delete of folder ID 1 cancelled; nothing was written." Confirm → "**Deleted folder ID 1: 1 folder row, 1 card(s) cascaded; 0 card(s) still reference ID 1.**" Query: folders = only Lantern (2); cards = only Beacon (3, folder 2); `cards WHERE folder_id = 1` → **0**; cards without a parent → **0**. Evidence: `T5_card_confirm.png`, `T5_card_deleted.png`, `T5_folder_confirm.png`, `T5_folder_deleted.png`, `query_log.txt` "T5" + orphan check | **Pass** |
| **T6** Validation & fallback | (a) Opened Beacon (ID 3, NULL image). (b) In the same edit form, typed `assets/cards/missing.png` into the image field to preview it, then Cancel. (c) Add card in Lantern with title "&nbsp;&nbsp;&nbsp;" (spaces only), suit Hearts. (d) New folder with name "&nbsp;&nbsp;" (spaces only). (e) New folder "Lantern". | Suit fallback for Beacon; every invalid attempt shows feedback and leaves rows/counts unchanged | (a) Large ♦ placeholder ("Diamonds placeholder (no image)"). (b) Preview switched to the ♦ placeholder ("asset missing"). Cancel → "Edit of card ID 3 cancelled; nothing was written." (c) "Enter a title (spaces alone do not count)." + "Not saved: fix the highlighted field(s)." (d) "Enter a folder name (spaces alone do not count). Not saved." (e) 'A folder named "Lantern" already exists. Not saved; choose a different name.' and the typed name stays in the field. After all of them: folders still 1 (Lantern ID 2), Lantern still 1 card (Beacon ID 3), `sqlite_sequence` unchanged (cards 3, folders 2). Evidence: `T6_beacon_fallback.png`, `T6_broken_ref_preview.png`, `T6_blank_title.png`, `T6_blank_folder.png`, `T6_duplicate_folder.png`, `query_log.txt` "T6" blocks | **Pass** |

Final state of the upgraded install after T6: Part I `my_table` 2/River/35, 3/Acorn/0, 4/Oak/130 (count 3); `folders` = {2 Lantern}; `cards` = {3 Beacon, Diamonds, NULL image, folder 2}.

**How queries were captured:** the T1a/T1b `PRAGMA` results come from the app's own open connection (Diagnostics screen, also printed to logcat). That matters for `foreign_keys`, because the PRAGMA is per connection. The other query blocks in `evidence/query_log.txt` come from `sqlite3 -readonly` on a *copy* of the DB pulled with `adb exec-out run-as … cat` (debug build only). The device file was never written by anything but the app.

## Release APK smoke test

- **Build:** `flutter build apk --release` → `✓ Built build/app/outputs/flutter-apk/app-release.apk (51.5MB)`. Copied as `Activity09_Fletcher_Kevon.apk`. SHA-256 `0f52fd369f34047b1371cc66a8a85f5df982642d804d89cc6fe48c502c9fae76`.
- **Target:** disposable user profile `Disposable09` (user 10) on `Espresso_Pixel`, installed with `adb install --user 10`. The Part I / upgraded install in user 0 was **not** uninstalled or replaced by this APK.
- **Observed:** fresh DB at version 2 (see T1b). Created folder Fresh (ID 1) → empty state shown. Added card "Smoke" (Clubs, no image) → ID 1 with ♣ placeholder. Edited it to "Smoke edited" → "Updated card ID 1: 1 row affected." Added "Temp" (Hearts) → ID 2. Deleted ID 2 → "Deleted card ID 2: 1 row affected." Ran `am force-stop --user 10`, then relaunched: PID 21423 → 24708. Home showed "1 folder(s), 1 card(s)" and Fresh still held ID 1 "Smoke edited" Clubs. Evidence: `release_smoke_before_restart.png`, `release_smoke_after_restart.png`. **Pass.**

## Analyzer

`flutter analyze` → `No issues found!` (`evidence/analysis_output.txt`). The pub "newer versions incompatible with constraints" lines in that file are informational, not analyzer findings.

## Known limitations (honest notes)

- **Order of builds:** T1a-T6 ran on a debug build. Afterwards I made one UI-only change in `folders_screen.dart` (`_openFolder`): it clears the home feedback line on return from a folder. Before that, the line could show a stale card total, e.g. "3 card(s)" after one had been deleted inside the folder. The list counts themselves were always correct. The release APK, T1b, and the smoke test include this change. No database code changed after T1a.
- **Second emulator:** the `Pixel_API_34` AVD would not boot (missing `kernel-ranchu`), so the "separate fresh target" is a secondary Android **user profile** on the same emulator. It has fully separate app data (`/data/user/10/...`).
- **T4 force stop on the release build** used `adb shell am force-stop --user 10` rather than tapping through App info. The upgraded-install T4 used the App info → Force stop button.
- **Validation is UI-only.** The schema would accept a whitespace title or an unknown suit if written directly. Folder-name uniqueness is case-sensitive ("Moon" ≠ "moon"), as the assignment says.
- **URL images:** supported in `CardImage`, but there's no INTERNET permission in the release manifest, so they always fall back. No offline caching.
- **No undo** after a confirmed folder cascade. No folder rename (not required).
- **Fault paths not injected:** read-failure / write-failure / zero-row paths exist in the source, but I didn't force them (not required).
- `debugPrint` diagnostics also run in the release build (only on the Diagnostics screen and on errors).

## Rubric map

| Criterion | Where to look |
| --- | --- |
| Schema & data preservation (25) | `lib/database_helper.dart:9, 34-35, 44-53, 70-90`. T1a row + `T1_before.png` / `T1_before_query.txt` vs `T1a_diagnostics_log.txt` / `T1a_roster_after_upgrade.png`. T1b row. T5 cascade + orphan check |
| Models, repository & CRUD (25) | `lib/models/*.dart`, `lib/catalogue_repository.dart`, `lib/screens/*.dart`. Rows T2, T3, T5, T6 |
| Image handling & usability (10) | `lib/widgets/card_image.dart`, `assets/cards/card_back.png`. `T2_cards.png` (asset), `T6_beacon_fallback.png`, `T6_broken_ref_preview.png`, `T1b_fresh_empty_folder.png` (empty state), confirmation dialogs in T5 |
| Testing & evidence (20) | Matrix above. `evidence/T1_before.png`, `T2_cards.png`, `T4_after.png`, `analysis_output.txt`, `query_log.txt`. Release smoke test section. Known limitations |
| Critical thinking & AI Lab (15) | Separate `Fletcher_Kevon_CriticalThinking.docx` (uploaded to iCollege, not in this repo) |
| README & delivery (5) | This README, `pubspec.yaml`, `pubspec.lock`. Repo URL in `github_link.txt`. `Activity09_Fletcher_Kevon.apk` uploaded separately |

## Attribution

- **Starter:** `lib/database_helper.dart` started as the course-supplied Part I helper. The Part I `_onCreate` SQL and CRUD methods are unchanged (now in `createPartOneTables`). The version-2 lifecycle (`onConfigure`/`onCreate`/`onUpgrade`) and the catalogue SQL follow the assignment's supplied patterns. `lib/screens/roster_screen.dart` is my Part I screen, moved unchanged.
- **Asset:** `assets/cards/card_back.png` was generated for this project (a plain geometric pattern written with Python's `zlib`/`struct`). No third-party image, no license needed.
- **References:** sqflite docs (pub.dev/packages/sqflite), Flutter SQLite cookbook (docs.flutter.dev/cookbook/persistence/sqlite), SQLite foreign-key docs (sqlite.org/foreignkeys.html).
- **AI assistance:** Claude Code (Anthropic, Claude Opus 5.5), 2026-10-09, helped write the version-2 code and this README. It also drove the emulator through `adb` (taps, text input, screenshots, read-only DB copies) to run T1-T6 and the release smoke test. Every ID, count, PID, and message above is copied from that real run's output and screenshots.
