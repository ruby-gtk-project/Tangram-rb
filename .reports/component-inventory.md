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
- Port side today: `lib/tangram.rb` and `lib/tangram/application.rb` (a
  placeholder window with an `Adw.StatusPage` reading "The Ruby port has not
  been written yet"), plus `lib/tangram/rb/version.rb`. **No user-facing
  component is ported.**

The house shape from the pilot (`gnome-contacts-rb`) is flat `lib/<thing>.rb`
with one class per file, so the target paths below are flat. The one existing
file sits at `lib/tangram/application.rb` under the gem layout; it is the file
that becomes `lib/application.rb` (or keeps its path, if the gem layout is kept
— that decision belongs to the first port unit, not to this survey).

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| Component units | 13 | 1 (placeholder) |
| Distinct widget types | 23 | 5 |
| Distinct CSS classes applied | 5 (`suggested-action`, `destructive-action`, `pill`, `flat`, `tab-close-button`) | 0 |
| Window/app actions | 6 (`app.about`, `app.shortcuts`, `app.showInstance(s)`, `app.quit`, `app.tabs-bar`, `win.editTab`) | 0 |
| Keyboard shortcuts bound | 11 (8 via `Gtk.ShortcutController`, 3 via `set_accels_for_action`) | 0 |
| GSettings schemas | 2 (`re.sonny.Tangram`, `re.sonny.Tangram.Instance`) | 0 |
| `po/` catalogue | 21 languages, `re.sonny.Tangram.pot` | not set up |

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

| # | Upstream file(s) | Target `lib/*.rb` | Kind | Exists on `ruby`? |
|---:|---|---|---|---|
| 1 | `src/application.js`, `src/main.js`, `src/style.css` | `lib/application.rb` | application | partly — `lib/tangram/application.rb` is a placeholder window with a status page; no CSS, no actions, no views |
| 2 | `src/window.blp`, `src/window.js` | `lib/window.rb` | window | no |
| 3 | `src/ViewTabs.blp`, `src/ViewTabs.js` | `lib/view_tabs.rb` | page | no |
| 4 | `src/ViewNew.blp`, `src/ViewNew.js` | `lib/view_new.rb` | page | no |
| 5 | `src/tabs.js` | `lib/tabs.rb` | tab pages (repeater) | no |
| 6 | `src/ViewTabs.blp` (`menu menu_app`) | `lib/main_menu.rb` | menu | no |
| 7 | `src/instanceDialog.blp`, `src/instanceDialog.js` | `lib/instance_dialog.rb` | dialog | no |
| 8 | `src/instanceDialog.js` (`onDelete`) | `lib/delete_tab_dialog.rb` | alert dialog | no |
| 9 | `src/shortcuts.blp` | `lib/shortcuts_dialog.rb` | shortcuts window | no |
| 10 | `src/Shortcuts.js` | `lib/shortcuts.rb` | keyboard shortcuts | no |
| 11 | `src/Actions.js` | `lib/actions.rb` | actions | no |
| 12 | `src/AboutDialog.js` | `lib/about_dialog.rb` | dialog | no |
| 13 | `src/WebView.js` | `lib/web_view.rb` | widget | no |

Non-widget support files that the components above need, listed so they are not
mistaken for components:

| Upstream file(s) | Target `lib/*.rb` | Kind | Exists? |
|---|---|---|---|
| `src/instances.js` | `lib/instances.rb` | model | no |
| `src/state.js` | `lib/state.rb` | model | no |
| `src/env.js` | `lib/env.rb` | support | no |
| `src/util.js` (incl. `Settings`), `data/re.sonny.Tangram.gschema.xml` | `lib/settings.rb` | settings/schema | no |
| `src/utils.js` (`normalizeURL`, `isSameSite`) | `lib/url.rb` | support | no — note `src/utils.test.js` exists upstream and is the spec to port |
| `src/constants.js` | folded into `lib/web_view.rb` | support | no |
| `src/webapp/webapp.js`, `src/webapp/ephy.js` | `lib/web_app_info.rb` | support | no |
| `troll/src/util.js` (`persistWindowState`, version helpers) | folded into `lib/window.rb` / `lib/about_dialog.rb` | support | no — a git submodule, not checked out; its rows belong to the files that import it |
| `po/*` (21 languages) | translation setup | i18n | no |

## Blockers

1. **No WebKit binding.** Upstream is a WebKit browser — `src/WebView.js`,
   `src/ViewNew.js` and `src/tabs.js` are all built on `WebKit.WebView`
   (WebKit 6.0, the GTK4 ABI). Neither `Gemfile` nor `flake.nix` carries any
   WebKit input, and ruby-gnome's `webkit2-gtk` gem binds the GTK3-era
   WebKit2GTK 4.x, not WebKit 6.0. Without a WebKit 6.0 binding (a gem, or
   GObject-Introspection through `gobject-introspection`), components 3, 4, 5
   and 13 cannot reach parity and the app has no content area. This needs a
   decision before any port unit that touches a web view.
2. **Upstream ref name.** The task says `origin/master`; this clone has no such
   ref. Everything here was read from `origin/main`. Worth confirming that is
   the intended spec ref.
3. **`troll` submodule is not checked out.** `persistWindowState`, the
   `getGjsVersion`/`getGIRepositoryVersion` helpers and `promiseTask` live
   there, so their behaviour was inferred from call sites, not read. Window
   state persistence and the About dialog's `debug_info` need the real source
   before they can be matched exactly.
4. **Deprecated upstream widgets.** `Gtk.ShortcutsWindow` (component 9) and
   `Adw.AboutWindow` (component 12) are deprecated in current GTK/libadwaita.
   The pilot port uses `Adw.ShortcutsDialog`; the equivalent substitution for
   About is `Adw.AboutDialog`. These are intentional divergences to record
   rather than parity gaps.
5. **GSettings schemas are unported.** Two schemas with an enum
   (`re.sonny.Tangram`, `re.sonny.Tangram.Instance`) back the window state, the
   tabs-bar toggle, the instance list and every per-instance preference. The
   port has no schema and no compiled schema directory, so the Edit Tab dialog
   and the tabs-bar menu item have nothing to read or write yet.
6. **Gem layout vs. house layout.** The house shape is flat `lib/<thing>.rb`
   (as in `gnome-contacts-rb`), but this fork is packaged as a gem with
   `lib/tangram/application.rb` and `lib/tangram/rb/version.rb`. The target
   paths above are the flat form; whoever ports the first unit should settle
   whether the gem namespace stays.
