# Tangram-rb — upstream component inventory

Survey of the upstream app (a GJS/blueprint GTK4 + Libadwaita + WebKit app)
against what `lib/` on the `ruby` branch currently holds. No app code was
written in this step; this revises the previous survey (`fb78239`) against
`lib/` as of commit `e4a44d9` ("Port the window, its two views, the web view
and the tab repeater"), which finished every component the prior survey
listed as missing or partial.

## Correction (this round)

Two things below were wrong, both flagged already in
`accountability-ensurance.md` and now fixed rather than left standing:

1. **Row 13's "yes" cell claimed the `tangram-resource` scheme was ported.**
   It was not — no `register_uri_scheme` call existed anywhere in `lib/`.
   `lib/web_view.rb` now registers the scheme for real (serving out of this
   port's own `data/` directory, since there is no GResource bundle of JS
   modules here for it to serve instead — see that file's class comment for
   the full divergence). Row 13 and the CSS-classes/support tables below are
   corrected to say so.
2. **The "Distinct CSS classes applied" row and the `src/style.css` support
   row both still said no `Gtk::CssProvider` was loaded anywhere in `lib/`.**
   That stopped being true at `5392ea2` ("Port the tab-overview close-button
   CSS workaround"), two commits before this inventory was last written:
   `lib/tangram/application.rb#style_provider` loads `data/style.css` (which
   carries the `.tab-close-button` rule) and adds it to the display at
   `PRIORITY_APPLICATION` on `activate`. The rows below are corrected; this
   was a stale report, not a stale port.

- Upstream ref read: **`origin/main`** (the task named `origin/master`; that
  ref does not exist in this clone — `git ls-tree origin/master` fails.
  `origin/main` is the upstream JavaScript implementation and is what every
  path below is read from.)
- Upstream unit list: 5 blueprint roots (`window.blp`, `ViewNew.blp`,
  `ViewTabs.blp`, `instanceDialog.blp`, `shortcuts.blp`) — four of them
  **named top-level objects**, not `template`s, plus one `menu menu_app`
  declaration inside `ViewTabs.blp`. Each is loaded by a `Gtk.Builder` and
  destructured by id in the matching `.js` file, so the component is the
  `.blp` + `.js` pair.
- Port side today: 21 files under `lib/`, one per upstream file plus the gem
  scaffolding (`lib/tangram.rb`, `lib/tangram/rb.rb`, `lib/tangram/rb/version.rb`).
  **Every one of the 13 upstream component units now has a file**, and every
  support file upstream relies on (`env.js`, `util.js`, `state.js`,
  `instances.js`, `utils.js`, `webapp/webapp.js` + `webapp/ephy.js`,
  `constants.js`) has been ported or folded into its consumer. The three
  remaining gaps are not components: upstream's `src/style.css` rule, the
  `po/` catalogue, and the GSettings schema files being replaced by a JSON
  store rather than ported as `.gschema.xml`.

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| Component units | 13 | **13 — all present** |
| Distinct widget types | 23 | 23 (via `Adwaita`/`Gtk` wrappers; see per-file tables) |
| Distinct CSS classes applied | 5 (`suggested-action`, `destructive-action`, `pill`, `flat`, `tab-close-button`) | **5 — all present.** `tab-close-button` ships in `data/style.css`, loaded by a `Gtk::CssProvider` in `lib/tangram/application.rb` (see Correction above) |
| Window/app actions | 6 (`app.about`, `app.shortcuts`, `app.showInstance(s)`, `app.quit`, `app.tabs-bar`, `win.editTab`) | **6 — all present** (`lib/actions.rb`) |
| Keyboard shortcuts bound | 11 (8 via `Gtk.ShortcutController`, 3 via `set_accels_for_action`) | **11 — all present** (`lib/shortcuts.rb`) |
| Shortcuts-window rows listed | 22 | 22 (`lib/shortcuts_dialog.rb`, as `Adw.ShortcutsDialog`) |
| GSettings schemas | 2 (`re.sonny.Tangram`, `re.sonny.Tangram.Instance`) | both keysets reproduced in `lib/settings.rb`, JSON-backed, no `.gschema.xml` (deliberate divergence) |
| `po/` catalogue | 21 languages, `re.sonny.Tangram.pot` | not set up — no `po/`, every string is a literal |
| Specs | `src/utils.test.js` | `spec/url_spec.rb` ports it; no spec for the newly-landed window/view/tab/web-view files yet |

---

## Component list

Status re-read against `lib/` at commit `e4a44d9`.

| # | Upstream file(s) | Target `lib/*.rb` | Kind | Exists on `ruby`? |
|---:|---|---|---|---|
| 1 | `src/application.js`, `src/main.js` | `lib/tangram/application.rb` | application | **yes** — app id, window geometry (via `Window`), icon search path, the three app accels (via `Shortcuts`/`Actions`), four+ app actions, `Settings#persist_window_state`. Upstream's dev-only `app.restart` on `<Primary><Shift>Q` is deliberately left out (documented in the class comment: nothing to re-exec from a checkout). `src/style.css`'s one rule (`.tab-close-button`) **is** ported — `style_provider` is a `Gtk::CssProvider` loaded from `data/style.css` and added to the display on `activate` (see Correction above) |
| 2 | `src/window.blp`, `src/window.js` | `lib/window.rb` | window | **yes** — the `Gtk::Stack` of the two named views bound to `state.view`, the `Adw.Breakpoint`, `persist_window_state`, the six navigation callbacks, `add_tab`/`cancel_new_tab`, the notification builder, and `settings.observe('instances')` driving the empty-state view switch |
| 3 | `src/ViewTabs.blp`, `src/ViewTabs.js` | `lib/view_tabs.rb` | page | **yes** — both header bars, the tab overview/bar/view, the reload `GestureClick`, the breakpoint-driven bar reveal, the main menu wiring |
| 4 | `src/ViewNew.blp`, `src/ViewNew.js` | `lib/view_new.rb` | page | **yes** — the "add a tab" flow, the preview web view, the status page's first-tab copy, the flat header-bar toggle. The port adds one behaviour upstream only commented out: `replace_previous`, so a second address typed into a returning welcome page does not try to add a second `GtkStack` child under the same name |
| 5 | `src/tabs.js` | `lib/tabs.rb` | tab pages (repeater) | **yes** — `add_tab`/`remove_tab`/`select_tab`/`edit_tab`, the three property bindings, and the audio-playing indicator icon |
| 6 | `src/ViewTabs.blp` (`menu menu_app`) | `lib/main_menu.rb` | menu | **yes** — all three items, both sections, same actions |
| 7 | `src/instanceDialog.blp`, `src/instanceDialog.js` | `lib/instance_dialog.rb` | dialog | **yes** — dialog, toolbar view, header bar, three buttons with their CSS classes, three `Adw.EntryRow`s, the `Adw.ComboRow` and its four-string model, and the URL-gates-Update behaviour |
| 8 | `src/instanceDialog.js` (`onDelete`) | `lib/delete_tab_dialog.rb` | alert dialog | **yes** — same heading, body, two responses, destructive appearance and close response; the awaited `choose` becomes the `response` signal |
| 9 | `src/shortcuts.blp` | `lib/shortcuts_dialog.rb` | shortcuts window | **yes** — all 22 rows in three groups, as `Adw.ShortcutsDialog` (deliberate substitution — see Divergences). The two gesture rows carry the gesture in a subtitle because `Adw.ShortcutsItem` has no gesture type |
| 10 | `src/Shortcuts.js` | `lib/shortcuts.rb` | keyboard shortcuts | **yes** — both the three `set_accels_for_action` lines and the `Gtk.ShortcutController` with its eight web-view shortcuts, hand-built from keyval+modifiers because `Gtk.ShortcutTrigger.parse_string` is unbound in ruby-gnome |
| 11 | `src/Actions.js` | `lib/actions.rb` | actions | **yes** — `app.about`, `app.shortcuts`, `app.quit`, `app.showInstance` (string parameter, the notification's default action), `app.tabs-bar`, and `win.editTab` |
| 12 | `src/AboutDialog.js` | `lib/about_dialog.rb` | dialog | **yes** — as `Adw.AboutDialog` (deliberate substitution — see Divergences), with the credit section and a `debug_info` block reading the WebKit/Soup/Adwaita/GTK/GLib versions off the typelibs |
| 13 | `src/WebView.js` | `lib/web_view.rb` | widget | **yes, with one divergence and one real gap** — `TabWebView < WebKit::WebView`, a named subclass so the construct-only `network-session`/`web-context`/`user-content-manager` properties can be set; the `tangram-resource` scheme (now registered for real — serving `data/` rather than a GResource bundle of JS modules this port has no use for, see Divergences), TLS policy, cookie/spell-check/sandbox setup, and the `create`/`permission-request`/`show-notification`/`decide-policy` signal handlers. `src/constants.js`'s `MODES` is folded in here. **Not ported:** `initialize-notification-permissions` (see Divergences #4 — confirmed to segfault the Ruby binding, not merely skipped) |

Non-widget support files the components above need:

| Upstream file(s) | Target `lib/*.rb` | Kind | Exists? |
|---|---|---|---|
| `src/instances.js` | `lib/instances.rb` | model | **yes** — `Instance` and `Instances`, with create/attach/detach/destroy, the directories and the random id |
| `src/state.js` | `lib/state.rb` | model | **yes** — `get`/`set`/`notify`/`bind` |
| `src/env.js` | `lib/env.rb` | support | **yes** — flatpak/dev/host detection and the four directories |
| `src/util.js` (incl. `Settings`), `data/re.sonny.Tangram.gschema.xml` | `lib/settings.rb` | settings/schema | **yes, with a divergence** — both schemas' keys and defaults, `observe`, `bind`, `create_action` and `persist_window_state`, but backed by a JSON file under `Env.config_dir` keyed by dconf-style object paths rather than by a compiled GSettings schema (see Divergences) |
| `src/utils.js` (`normalizeURL`, `isSameSite`) | `lib/url.rb` | support | **yes** — libsoup 3 loaded through `GObjectIntrospection::Loader` for the public-suffix lookup; `spec/url_spec.rb` ports `src/utils.test.js` |
| `src/constants.js` | folded into `lib/web_view.rb` | support | **yes** |
| `src/webapp/webapp.js`, `src/webapp/ephy.js` | `lib/web_app_info.rb` | support | **yes** — the manifest/title/icon/URL probe `on_add_tab` awaits |
| `troll/src/util.js` (`persistWindowState`, version helpers), `troll/src/async.js` | folded into `lib/settings.rb` / `lib/about_dialog.rb` | support | **yes, inferred** — `persist_window_state` and the version readers exist; the `troll` submodule is still not checked out, so neither was read against its real source |
| `src/style.css` | `data/style.css`, loaded by `lib/tangram/application.rb` | stylesheet | **yes** — the `.tab-close-button` rule (hides the tab-overview thumbnail close buttons), loaded by a `Gtk::CssProvider` added to the display on `activate` |
| `po/*` (21 languages) | translation setup | i18n | **no** — no `po/`, no gettext call, every ported string is a Ruby literal |
| `src/utils.test.js` | `spec/url_spec.rb` | spec | **yes** — ports every `assert.is` line plus `normalize`/`allowed_for_navigation?`, which upstream never tested |
| `src/webapp/test.js` | `spec/web_app_info_spec.rb` | spec | **yes (this round)** — all 9 scenarios, run the way upstream ran them: a real `WebKit::WebView` loading real HTTP responses from a local server, fed to `WebAppInfo.fetch`. Previously only 1 of 9 was covered, indirectly, via one `test/drive_new_tab.rb` step; see `test-parity.md` |

## Divergences (deliberate, not gaps)

1. **Deprecated upstream widgets swapped for current ones.**
   `Gtk.ShortcutsWindow` (component 9) is deprecated in GTK 4.18+ and its Ruby
   binding raises `GtkWindow is not subtype of GtkShortcutsWindow`;
   `Adw.AboutWindow` (component 12) is deprecated too. The port uses
   `Adw.ShortcutsDialog` and `Adw.AboutDialog`, matching the pilot
   (`gnome-contacts-rb`)'s `ShortcutsDialog`.
2. **GSettings schemas replaced by a JSON store.** `lib/settings.rb` carries
   both schemas' keys with upstream's defaults but stores them in JSON under
   `Env.config_dir`, so no schema compilation/install step is needed to run
   from a checkout. `Gio::Settings.bind` and `create_action` semantics are
   reimplemented by hand rather than inherited from GLib.
3. **Gem layout vs. house layout.** Twenty of the twenty-one ported files are
   flat and un-namespaced (`lib/<thing>.rb`, top-level class), matching the
   pilot. `lib/tangram/application.rb` alone keeps the gem path and the
   `Tangram::` module — this is now the one holdout, since `window.rb` (which
   it requires) landed flat.
4. **`tangram-resource` now serves `data/`, not a GResource bundle.**
   Upstream's bundle holds its GJS *source modules*; this port loads its
   files with plain `require_relative` and has no such bundle, so the scheme
   is registered against the one real resource source this port has:
   `data/` (the icons and `style.css` `lib/tangram/application.rb` already
   reads off disk). See `lib/web_view.rb`'s class comment.
5. **`initialize-notification-permissions` has no port — confirmed, not
   assumed.** Calling `WebKit::WebContext#initialize_notification_permissions`
   with a non-empty list of `WebKit::SecurityOrigin` was tested directly
   against this port's own GI loader and segfaults every time (an empty list
   does not); there is no workaround available in the Ruby bindings as they
   stand. `permission-request` allows every notification request outright
   instead, which reaches the same end state for the one origin upstream
   pre-grants, but the mechanism itself — and the one difference it would
   make for an origin upstream never pre-granted — is simply absent, not
   approximated.

## Open items (not blockers — nothing here stops the app running)

1. **No `po/` / gettext.** 21 upstream catalogues, zero on `ruby`. Every
   string a widget shows is a Ruby literal. This is `translation-parity`'s
   job, not this survey's.
2. **`troll` submodule still not checked out.** `persist_window_state` and
   the version-reading helpers in `lib/settings.rb`/`lib/about_dialog.rb` are
   written from the call sites in `window.js`/`AboutDialog.js`, not checked
   against `troll/src/util.js` itself.
3. **`initialize-notification-permissions` has no port** — see Divergence 5
   above; listed here too because it is owed work this port cannot pay
   under the current Ruby bindings, not a settled decision.
4. **Gem-path holdout.** `lib/tangram/application.rb` is the only namespaced,
   nested file left; moving it to flat `lib/application.rb` with a top-level
   `Application` class would match every other ported file and the pilot's
   house shape exactly.

## History

- `de05d7e`/`fb78239` ("Inventory upstream components") — first survey, taken
  when `lib/` had 12 files and the window/views/tabs/web-view were all
  unported (upstream ref resolution and the WebKit-binding blocker were
  settled there; see that commit's report body in `git log -p` if needed).
- `e4a44d9` ("Port the window, its two views, the web view and the tab
  repeater") — landed components 2–5 and 13, closing every gap the first
  survey listed. This revision reflects that state: all 13 component units
  present, with the divergences and open items above being everything real
  that is left.
