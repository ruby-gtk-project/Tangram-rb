# Tangram-rb — upstream component inventory

Survey of the upstream app (a GJS/blueprint GTK4 + Libadwaita + WebKit app)
against what `lib/` on the `ruby` branch currently holds. No app code was
written in this step.

- Upstream ref read: **`origin/main`** (the task named `origin/master`; that ref
  does not exist in this clone — `git ls-tree origin/master` fails. `origin/main`
  is the upstream JavaScript implementation and is what every path below is read
  from.)
- Upstream unit list: 5 blueprint roots (`window.blp`, `ViewNew.blp`,
  `ViewTabs.blp`, `instanceDialog.blp`, `shortcuts.blp`) — four of them
  **named top-level objects**, not `template`s, plus one `menu menu_app`
  declaration inside `ViewTabs.blp`. Each is loaded by a `Gtk.Builder` and
  destructured by id in the matching `.js` file, so the component is the
  `.blp` + `.js` pair.
- Port side today (re-surveyed after commit `775f442`, "Port the settings, tab
  model and the dialogs the menu opens"): 12 files in `lib/`. The support and
  model layer is in place (`env.rb`, `settings.rb`, `state.rb`, `url.rb`,
  `instances.rb`), as are the four chrome components the primary menu reaches
  (`main_menu.rb`, `about_dialog.rb`, `shortcuts_dialog.rb`) and the Edit Tab
  pair (`instance_dialog.rb`, `delete_tab_dialog.rb`). **Everything that holds
  web content is still unported** — no `window.rb`, no `view_tabs.rb`, no
  `view_new.rb`, no `tabs.rb`, no `web_view.rb` — and the window in
  `lib/tangram/application.rb` is still a single `Adw.StatusPage` standing in
  for `ViewNew`'s welcome state rather than the real two-view `Gtk.Stack`.

The house shape from the pilot (`gnome-contacts-rb`) is flat `lib/<thing>.rb`
with one class per file, and the ported files follow it. The one exception is
`lib/tangram/application.rb`, which kept the gem layout's namespaced path; it
is the file that would become `lib/application.rb` if the gem namespace is
dropped. That decision has now been made by use — every other ported file is
flat and un-namespaced — so the open item is only whether `application.rb`
moves to match.

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| Component units | 13 | 5 complete, 3 partial, 5 absent |
| Distinct widget types | 23 | 17 |
| Distinct CSS classes applied | 5 (`suggested-action`, `destructive-action`, `pill`, `flat`, `tab-close-button`) | 3 (`suggested-action`, `destructive-action`, `pill`) |
| Window/app actions | 6 (`app.about`, `app.shortcuts`, `app.showInstance(s)`, `app.quit`, `app.tabs-bar`, `win.editTab`) | 4 (`app.about`, `app.shortcuts`, `app.quit`, `app.tabs-bar`) |
| Keyboard shortcuts bound | 11 (8 via `Gtk.ShortcutController`, 3 via `set_accels_for_action`) | 3 (the `set_accels_for_action` trio) |
| Shortcuts-window rows listed | 22 | 22 |
| GSettings schemas | 2 (`re.sonny.Tangram`, `re.sonny.Tangram.Instance`) | both keysets reproduced in `lib/settings.rb`, JSON-backed, no `.gschema.xml` |
| `po/` catalogue | 21 languages, `re.sonny.Tangram.pot` | not set up — no `po/`, every string is a literal |
| Specs | `src/utils.test.js` | none — `spec/` holds only `spec_helper.rb`, although `lib/url.rb` names `spec/url_spec.rb` in its comment |

---

## src/window.blp + src/window.js — the application window and view switcher

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | — | — | resizable, 800×600 default, 360×360 minimum |
| `Adw.Breakpoint` | 1 | — | `apply`, `unapply` | `max-width: 460`; handed to `ViewTabs`, which flips the header bar to the bottom |
| `Gtk.Stack` | 1 | — | — | `stack_views`, hhomogeneous, crossfade; two named children `tabs` and `new`, bound to `state.view` |

Behaviour in `window.js` beyond the tree: `persistWindowState` (window
width/height/maximized/fullscreened in GSettings), `onNotification` (builds a
`Gio.Notification` per instance with the instance's `notifications-priority`
and a `app.showInstance('<id>')` default action), the navigation callbacks
`onReload`/`onStopLoading`/`onGoBack`/`onGoForward`/`onGoHome`/`onToggleWebInspector`,
`onAddTab` (reads the web-app manifest, attaches the instance, moves the
webview out of the new-tab stack into the tab view), `onCancelNewTab`, loading
instances at startup, and opening the tab overview when more than one instance
exists. Empty state: `observeSetting(settings, "instances")` calls `onNewTab()`
whenever the instance list goes empty.

## src/ViewNew.blp + src/ViewNew.js — the "add a tab" view

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` | 3 | — | — | root (vertical), header-bar start box, status-page content box |
| `Adw.HeaderBar` | 1 | `flat` (dynamic: added when this is the first tab, removed otherwise) | — | `centering-policy: strict` |
| `Gtk.Button` | 3 | `suggested-action` (`button_done`); `suggested-action`+`pill` (`button_go`) | `clicked` ×3 | `button_cancel` → `onCancelNewTab`; `button_done` → `onAddTab`; `button_go` → re-emits `entry_go`'s `activate` |
| `Adw.Clamp` | 1 | — | — | max 860, tightening 560, wraps the address entry |
| `Gtk.Entry` | 2 | — | `activate` ×2, `notify::text` (binding) | `entry_url` (address bar, `primary_icon_name` set to `channel-secure-symbolic` / `channel-insecure-symbolic` from TLS info); `entry_go` (placeholder `example.org`, text bound to `button_go.sensitive`) |
| `Gtk.Stack` | 1 | — | — | `stack_new`: page `statuspage`, plus a runtime-added `new-tab` page holding the preview webview |
| `Gtk.StackPage` | 1 | — | — | child wrapper, not a widget |
| `Adw.StatusPage` | 1 | — | — | first-tab state: icon `re.sonny.Tangram`, "Welcome to Tangram" / "Let's add your first web application."; blanked for later tabs |

Conditional: `entry_url` and `button_done` are hidden until a URL has been
entered; `button_cancel` is hidden when this is the first tab. `button_done`
is insensitive while the preview webview is loading.

## src/ViewTabs.blp + src/ViewTabs.js — the tabs view (both header bars)

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ToolbarView` | 1 | — | — | `view_tabs`; `top-bar-style` bound to `tab_overview.open` (FLAT/RAISED), bottom bar `raised_border`; top/bottom reveal swapped by the breakpoint |
| `Adw.HeaderBar` | 2 | — | — | `header_bar_content_top`, `header_bar_content_bottom` |
| `Gtk.Box` | 3 | — | — | top nav box (spacing 6), bottom nav box (spacing 6), tab-overview child box (vertical) |
| `Gtk.Button` | 10 | `suggested-action` (`button_add_tab`) | `clicked` ×7 | add-tab; back/forward/reload/home top; back/forward/home bottom; two `view-more-symbolic` "Edit Tab" buttons targeting `win.editTab` |
| `Adw.ButtonContent` | 2 | — | — | inside `button_add_tab` and the top title toggle |
| `Gtk.ToggleButton` | 2 | — | `active` bound bidirectionally to `tab_overview.open` | top (label `_Tangram`, `use-underline`) and bottom (icon only) |
| `Gtk.MenuButton` | 2 | — | — | both `primary: true`, both `menu-model: menu_app`; visibility inverted between overview open/closed |
| `Adw.TabOverview` | 1 | — | `notify::open` (via bindings) | search and title buttons disabled |
| `Adw.TabBar` | 1 | — | — | `visible` bound to GSettings `tabs-bar` |
| `Adw.TabView` | 1 | — | — | `shortcuts: all_shortcuts` |
| `Gtk.GestureClick` | 1 (controller) | — | `pressed` | on `button_reload_top`: primary click reloads (ctrl ⇒ bypass cache), stop-loads while loading; non-primary denied |

Dynamic: the reload button's icon alternates `view-refresh-symbolic` /
`process-stop-symbolic`; back/forward sensitivity tracks the webview's
back-forward list. `visible: bind tab_overview.open [inverted]` gates six of
these widgets — two visibility states of the same bar.

## src/ViewTabs.blp (`menu menu_app`) — the main menu

Three items, two sections: "Show Tabs Bar" → `app.tabs-bar` (a
`settings.create_action` toggle), then a section with "Keyboard Shortcuts" →
`app.shortcuts` and "About Tangram" → `app.about`.

## src/tabs.js — the tab pages

No `.blp`. Per tab it appends a webview to the `Adw.TabView` and drives the
`Adw.TabPage`: live thumbnail on, `favicon`→`icon`, instance `name`→`title`,
`is-loading`→`loading`, and an indicator icon
`audio-volume-high-symbolic` with tooltip "Playing Audio" on
`notify::is-playing-audio`. Signals: `notify::selected-page` (publishes the
current webview to state) and `close-page` (finishes the close, reopens the
overview, destroys the instance). A **repeater**: one component, one per
instance.

## src/instanceDialog.blp + src/instanceDialog.js — the Edit Tab dialog

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Dialog` | 1 | — | — | content width 640, title = instance name |
| `Adw.ToolbarView` | 1 | — | — | |
| `Adw.HeaderBar` | 1 | — | — | title buttons hidden |
| `Gtk.Button` | 3 | `suggested-action` (`button_save`); `destructive-action`+`pill` (`button_delete`) | `clicked` ×3 | Cancel closes; Update writes all four settings and closes; Delete Tab opens the confirm alert |
| `Adw.PreferencesPage` | 1 | — | — | |
| `Adw.PreferencesGroup` | 3 | — | — | name/URL, notifications/user-agent, delete |
| `Adw.EntryRow` | 3 | — | `changed` (URL only → gates `button_save`) | Name, Homepage (`input-purpose: url`), User agent |
| `Adw.ComboRow` | 1 | — | — | "Notifications priority", `Gtk.StringList` of Normal/Low/High/Urgent, selected from the instance's enum setting |

## src/instanceDialog.js (`onDelete`) — the delete confirmation

`Adw.AlertDialog`: heading "Delete Tab?", body "The Tab and locally saved data
will be gone.", responses `cancel` / `delete` with `delete` marked
`Adw.ResponseAppearance.DESTRUCTIVE`, `close_response: "cancel"`. On `delete`
it deletes the instance and force-closes the edit dialog.

## src/shortcuts.blp — the shortcuts window

`Gtk.ShortcutsWindow` (modal, hide-on-close), one `ShortcutsSection` with three
`ShortcutsGroup`s and **22 `ShortcutsShortcut` rows**: Tabs (10), Navigation (9,
two of them two-finger-swipe gestures), General (3). Presented transient-for
the window by `app.shortcuts`. Note `Gtk.ShortcutsWindow` is deprecated in
GTK 4.18+; the pilot's `ShortcutsDialog` uses `Adw.ShortcutsDialog` instead,
which is the shape to follow here.

## src/Shortcuts.js — the live key bindings

A `Gtk.ShortcutController` on the window with 8 shortcuts:
`<Alt>Home` home, `Escape` stop, `<Control>R`/`F5` reload,
`<Control><Shift>R`/`<Shift>F5` reload bypassing cache, `<Alt>Left` back,
`<Alt>Right` forward, `<Control><Shift>I` toggle inspector, `<Control>L` focus
address bar. Plus app accels `app.quit` → `<Primary>Q`, `app.inspector` →
`<Primary><Shift>D`, `app.shortcuts` → `<Primary>question`.

## src/Actions.js — the action set

`app.about`, `app.shortcuts`, `app.showInstance` (parameter type `s`),
`app.quit`, `app.tabs-bar` (from `settings.create_action`), and `win.editTab`.
The `win.editTab` action reads the current webview's instance and opens the
Edit Tab dialog.

## src/AboutDialog.js — the About dialog

`Adw.AboutWindow` (hide-on-close, memoized in a module-level `dialog`):
application name Tangram, developer Sonny Piers, copyright, GPL-3.0-only,
version, website, icon, issue URL, `translator-credits`, developers/designers/
artists lists, a "Contributors" credit section, and a `debug_info` block
listing WebKitGTK / GJS / Adw / GTK / GLib / libsoup / GStreamer versions.
`Adw.AboutWindow` is deprecated; `Adw.AboutDialog` is the current equivalent.

## src/WebView.js — the web view

No `.blp`. Builds the `WebKit.WebView` per instance together with its
`NetworkSession`, `WebContext`, `UserContentManager` and `Settings`: TLS errors
fail, spell checking on with the system languages, sandbox paths, the
`tangram-resource` URI scheme, notification permissions pre-granted for the
instance's origin, favicons on, cookies `NO_THIRD_PARTY` persisted to
`cookies.sqlite`, smooth scrolling, back/forward navigation gestures, developer
extras, and a user agent from the instance setting. Signals: `create`,
`permission-request`, `show-notification`, `decide-policy` (ctrl- or
middle-click opens in the default browser). Downloads open a
`Gtk.FileDialog` titled "Save File" for `blob:`/`file:` URIs and hand `http`
ones to the default application.

## src/application.js — the application object

`Adw.Application` with id `re.sonny.Tangram`; `activate` builds the window once
and presents it. Loads `src/style.css` (one rule, `.tab-close-button`, a
workaround hiding the tab-overview thumbnail close buttons). `src/main.js` adds
a dev-only `app.restart` action on `<Primary><Shift>Q` and sets the PulseAudio
properties.

---

## Component list

Status is re-read against `lib/` at commit `775f442`.

| # | Upstream file(s) | Target `lib/*.rb` | Kind | Exists on `ruby`? |
|---:|---|---|---|---|
| 1 | `src/application.js`, `src/main.js`, `src/style.css` | `lib/tangram/application.rb` | application | **partial** — app id, window geometry, icon search path, the three app accels, four app actions and `settings.persist_window_state` are in place. Missing: the two-view `Gtk.Stack` (it presents a bare `Adw.StatusPage`), `src/style.css`'s `.tab-close-button` rule, the `PULSE_PROP_*` env vars from `main.js`, and the dev-only `app.restart` on `<Primary><Shift>Q` |
| 2 | `src/window.blp`, `src/window.js` | `lib/window.rb` | window | **no** — no file. The window is inlined in `application.rb` without the `Gtk.Stack`, the `Adw.Breakpoint`, `onNotification`, the six navigation callbacks, `onAddTab`/`onCancelNewTab`, or the `observeSetting(settings, "instances")` empty-state hook |
| 3 | `src/ViewTabs.blp`, `src/ViewTabs.js` | `lib/view_tabs.rb` | page | **no** |
| 4 | `src/ViewNew.blp`, `src/ViewNew.js` | `lib/view_new.rb` | page | **no** — only the welcome `Adw.StatusPage`'s three strings survive, as the placeholder window's content |
| 5 | `src/tabs.js` | `lib/tabs.rb` | tab pages (repeater) | **no** |
| 6 | `src/ViewTabs.blp` (`menu menu_app`) | `lib/main_menu.rb` | menu | **yes** — all three items, both sections, same actions |
| 7 | `src/instanceDialog.blp`, `src/instanceDialog.js` | `lib/instance_dialog.rb` | dialog | **yes** — dialog, toolbar view, header bar, three buttons with their CSS classes, three `Adw.EntryRow`s, the `Adw.ComboRow` and its four-string model, and the URL-gates-Update behaviour |
| 8 | `src/instanceDialog.js` (`onDelete`) | `lib/delete_tab_dialog.rb` | alert dialog | **yes** — same heading, body, two responses, destructive appearance and close response; the awaited `choose` becomes the `response` signal |
| 9 | `src/shortcuts.blp` | `lib/shortcuts_dialog.rb` | shortcuts window | **yes** — all 22 rows in three groups, as `Adw.ShortcutsDialog` (the deliberate substitution; see blocker 4). The two gesture rows carry the gesture in a subtitle because `Adw.ShortcutsItem` has no gesture type |
| 10 | `src/Shortcuts.js` | `lib/shortcuts.rb` | keyboard shortcuts | **partial** — the three `set_accels_for_action` lines live in `Application::ACCELERATORS`. The `Gtk.ShortcutController` with its eight web-view shortcuts (`<Alt>Home`, `Escape`, `<Control>R`/`F5`, `<Control><Shift>R`/`<Shift>F5`, `<Alt>Left`, `<Alt>Right`, `<Control><Shift>I`, `<Control>L`) has no file and no code |
| 11 | `src/Actions.js` | `lib/actions.rb` | actions | **partial** — `app.about`, `app.shortcuts`, `app.quit` and `app.tabs-bar` are installed inline in `application.rb`. Missing: `app.showInstance` (parameter type `s`, the notification's default action) and `win.editTab`. No separate file yet |
| 12 | `src/AboutDialog.js` | `lib/about_dialog.rb` | dialog | **yes** — as `Adw.AboutDialog`, with the credit section and a `debug_info` block reading the WebKit/Soup/Adwaita/GTK/GLib versions off the typelibs |
| 13 | `src/WebView.js` | `lib/web_view.rb` | widget | **no** — blocked, see blocker 1 |

Non-widget support files the components above need:

| Upstream file(s) | Target `lib/*.rb` | Kind | Exists? |
|---|---|---|---|
| `src/instances.js` | `lib/instances.rb` | model | **yes** — `Instance` and `Instances`, with create/attach/detach/destroy, the directories and the random id |
| `src/state.js` | `lib/state.rb` | model | **yes** — `get`/`set`/`notify`/`bind` |
| `src/env.js` | `lib/env.rb` | support | **yes** — flatpak/dev/host detection and the four directories |
| `src/util.js` (incl. `Settings`), `data/re.sonny.Tangram.gschema.xml` | `lib/settings.rb` | settings/schema | **yes, with a divergence** — both schemas' keys and defaults, `observe`, `bind`, `create_action` and `persist_window_state`, but backed by a JSON file under `Env.config_dir` keyed by dconf-style object paths rather than by a compiled GSettings schema |
| `src/utils.js` (`normalizeURL`, `isSameSite`) | `lib/url.rb` | support | **yes** — libsoup 3 loaded through `GObjectIntrospection::Loader` for the public-suffix lookup. `src/utils.test.js` is **not** ported; `lib/url.rb` names `spec/url_spec.rb` but that file does not exist |
| `src/constants.js` | folded into `lib/web_view.rb` | support | **no** — the `MODES` pair arrives with the web view |
| `src/webapp/webapp.js`, `src/webapp/ephy.js` | `lib/web_app_info.rb` | support | **no** — the manifest/title/icon/URL probe `onAddTab` awaits |
| `troll/src/util.js` (`persistWindowState`, version helpers), `troll/src/async.js` | folded into `lib/settings.rb` / `lib/about_dialog.rb` | support | **yes, inferred** — `persist_window_state` and the version readers exist; the submodule is still not checked out, so neither was read against its source |
| `po/*` (21 languages) | translation setup | i18n | **no** — no `po/`, no gettext call, every ported string is a Ruby literal |

## Blockers

1. **No WebKit binding.** This is the one blocker that stops the port being an
   app rather than a chrome. Upstream is a WebKit browser — `src/WebView.js`,
   `src/ViewNew.js` and `src/tabs.js` are all built on `WebKit.WebView`
   (WebKit 6.0, the GTK4 ABI). Neither `Gemfile` nor `flake.nix` carries any
   WebKit input, and ruby-gnome's `webkit2-gtk` gem binds the GTK3-era
   WebKit2GTK 4.x, not WebKit 6.0. `lib/about_dialog.rb` does already reach
   WebKit 6.0 through `GObjectIntrospection::Loader.load('WebKit', WebKit)`
   purely to read its version, which suggests the same route could carry the
   widget — that needs proving before components 2, 3, 4, 5 and 13 can be
   planned.
2. **Upstream ref name.** The task says `origin/master`; this clone has no such
   ref (`git ls-tree origin/master` fails). Everything here is read from
   `origin/main`, whose tip is `d68f681`.
3. **`troll` submodule is not checked out.** `persistWindowState`, the
   `getGjsVersion`/`getGIRepositoryVersion` helpers and `promiseTask` live
   there. The port has written its own equivalents from the call sites, so the
   window-state and `debug_info` behaviour is plausible but unverified against
   the real source.
4. **Deprecated upstream widgets — resolved as deliberate divergences.**
   `Gtk.ShortcutsWindow` (component 9) is deprecated in GTK 4.18+ and its Ruby
   binding raises `GtkWindow is not subtype of GtkShortcutsWindow`;
   `Adw.AboutWindow` (component 12) is deprecated too. The port uses
   `Adw.ShortcutsDialog` and `Adw.AboutDialog`. Recorded here so a later
   parity check does not read them as gaps.
5. **GSettings schemas are replaced, not ported.** `lib/settings.rb` carries
   both schemas' keys with upstream's defaults but stores them in JSON under
   `Env.config_dir`, so no schema compilation is needed to run from a checkout.
   The consequence to track: `Gio::Settings.bind` and `create_action` semantics
   are reimplemented by hand, so anything upstream gets from GSettings for free
   needs a test rather than an assumption.
6. **No test or translation parity yet.** `src/utils.test.js` is upstream's only
   spec and is unported despite `lib/url.rb` pointing at `spec/url_spec.rb`;
   `po/` has 21 catalogues and the port has none. Both are separate parity
   steps, but the missing `spec/url_spec.rb` is a dangling reference today.
7. **Gem layout vs. house layout.** Eleven ported files are flat and
   un-namespaced; `lib/tangram/application.rb` alone keeps the gem path and the
   `Tangram::` module. Worth settling before `lib/window.rb` is written, since
   the window is what `application.rb` will require.
