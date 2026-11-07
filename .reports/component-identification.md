# Tangram-rb — component identification

Audit pass, read-only. Upstream ref used: **`origin/main`** — the task text
says `origin/master`, but that ref does not exist in this clone
(`git show origin/master:README.md` → `fatal: invalid object name`). `origin/main`
is the GJS/blueprint implementation and is the only candidate upstream in this
fork (`git branch -r` lists no `master`). Upstream read via a detached
worktree at `/tmp/claude-1001/upstream-tangram` (`origin/main` @ `d68f681`).

This audit does **not** re-walk every file from scratch — `.reports/component-inventory.md`
(committed on `ruby` already, last revised against port commit `e4a44d9`) did
that work and its per-file table is accurate on the point that matters most to
an audit: file-to-file mapping and per-file existence. What follows corrects
and sharpens it; it does not replace it.

## Unit list (unchanged from the existing inventory)

13 component units, 5 `.blp` roots (4 named top-level objects + 1 `template`-less
menu), matching `.js` pairs, all 13 present as a `lib/*.rb` file:

1. `src/application.js`,`src/main.js` → `lib/tangram/application.rb`
2. `src/window.blp`,`src/window.js` → `lib/window.rb`
3. `src/ViewTabs.blp`,`src/ViewTabs.js` → `lib/view_tabs.rb`
4. `src/ViewNew.blp`,`src/ViewNew.js` → `lib/view_new.rb`
5. `src/tabs.js` → `lib/tabs.rb`
6. `src/ViewTabs.blp` (`menu menu_app`) → `lib/main_menu.rb`
7. `src/instanceDialog.blp`,`src/instanceDialog.js` → `lib/instance_dialog.rb`
8. `src/instanceDialog.js` (`onDelete`) → `lib/delete_tab_dialog.rb`
9. `src/shortcuts.blp` → `lib/shortcuts_dialog.rb`
10. `src/Shortcuts.js` → `lib/shortcuts.rb`
11. `src/Actions.js` → `lib/actions.rb`
12. `src/AboutDialog.js` → `lib/about_dialog.rb`
13. `src/WebView.js` (+ `src/constants.js`) → `lib/web_view.rb`

Support files: `instances.js`→`lib/instances.rb`, `state.js`→`lib/state.rb`,
`env.js`→`lib/env.rb`, `util.js`+gschema→`lib/settings.rb`, `utils.js`→`lib/url.rb`,
`webapp/webapp.js`+`webapp/ephy.js`→`lib/web_app_info.rb`. All present.

## Correction to the existing inventory: a false-green cell

`.reports/component-inventory.md`, row 13 (`src/WebView.js` →
`lib/web_view.rb`), states the port carries **"the `tangram-resource` scheme,
TLS policy, cookie/spell-check/sandbox setup"** and marks the row **yes**.

Read against the actual file: `lib/web_view.rb` has no
`register_uri_scheme`/`register_uri_scheme_as_local` call, and no occurrence
of the string `tangram-resource` anywhere in `lib/`. The class's own comment
block (lines 56–65) says the opposite of the inventory row — it names the
scheme as one of three pieces "deliberately left out rather than
approximated." The inventory row is wrong; the code comment is the honest
account. See `component-parity.md` and `accountability-ensurance.md` for the
consequences of this contradiction.

Everything else the inventory row claims (TLS policy, cookie/spell-check/sandbox
setup, the notification *forwarding* signal) is present and was spot-checked
directly against `lib/web_view.rb`.

## Not re-derived here

Widget type/CSS-class/signal/action tallies per file, the GSettings schema
comparison, and the shortcuts/menu enumeration in the existing inventory were
spot-checked (not fully re-counted) and found consistent with the source.
`component-parity.md` carries the four-axis judgement; this document is the
unit list and file map only.

## Verified this round (2026-11-07, independent re-audit)

Re-checked from scratch, not just re-read:

- `git show origin/master:README.md` → `fatal: invalid object name` (still
  true); `git branch -r` lists no `master`. `origin/main` @ `d68f681` is
  confirmed the only candidate upstream, same as this document already
  concluded.
- The 13-unit list and the 21-file `lib/` map were re-walked against
  `git ls-tree -r --name-only origin/main` and `find lib -type f`. No new
  upstream unit found, no port file missing.
- The "false-green cell" this document flagged in `component-inventory.md`
  row 13 is now actually fixed: `lib/web_view.rb:183-184` registers
  `tangram-resource` for real (`register_uri_scheme_as_local` +
  `register_uri_scheme`), confirmed by reading the lines directly.

One thing this document and `component-inventory.md` both leave unsaid,
surfaced here rather than silently added to either: upstream ships
`data/re.sonny.Tangram.desktop`, `data/appdata/re.sonny.Tangram.metainfo.xml`
and `data/re.sonny.Tangram.service` (D-Bus activation) — `git ls-tree -r
--name-only origin/main | grep ^data/` lists all three. None exist anywhere
in this port (`find . -iname '*.desktop' -o -iname '*metainfo*'` → nothing).
This is not scored as a 14th component unit — the task's own component axes
(window/dialog/page/menu/shortcut/preference/action/empty-state/error-state)
are in-app GUI surface, and the `translation-parity` skill's own worked
example (`gnome-contacts-rb`) treats a missing `data/` directory the same
way: a translation-catalogue gap, not a missing window. Recorded here only
so the omission is visible from the component side too, not just inherited
through `translation-parity.md`'s msgid ledger.
