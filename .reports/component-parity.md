# Tangram-rb — component parity

Four axes — count, style, behaviour, text — judged per component, against
`origin/main` @ `d68f681` (see `component-identification.md` for why `main`
and not the task's named `master`). Gaps below are gaps: none is excused by
anything in this document or any other.

## Gaps found

### 1. `lib/web_view.rb` — three pieces of `src/WebView.js` not ported (behaviour axis)

The class comment names all three itself:

- `tangram-resource` URI scheme (`security_manager.register_uri_scheme_as_local`
  + `web_context.register_uri_scheme`, `src/WebView.js:97-104`) — **not
  present** in `lib/web_view.rb`. No code anywhere in `lib/` registers a URI
  scheme. This is a real gap in the *mechanism*, whether or not any resource
  is currently served through it upstream (no `.gresource.xml` was found in
  this upstream tree to confirm what, if anything, upstream serves over it
  today — but the registration itself is missing, not just an unused
  consumer of it).
- `initialize-notification-permissions` auto-grant (`src/WebView.js:109-116`)
  — not present. Upstream pre-grants the notification permission for a
  single-site tab's own origin so the web app never has to ask; the port's
  web view will prompt the user instead. User-visible behaviour change.
- The commented-out web-inspector block — dead code upstream, correctly not
  ported. Not a gap.

The scheme and the notification auto-grant **are** gaps; the comment in
`lib/web_view.rb:56-76` already says so honestly in its own prose, but
`.reports/component-inventory.md` (written in an earlier pass) contradicts
it and claims the scheme is ported. That contradiction is itself a finding —
see `accountability-ensurance.md`.

### 2. `src/style.css` — one CSS rule not ported (style axis)

`.tab-close-button` hides the tab-overview thumbnail close button. No
`Gtk::CssProvider` exists anywhere in `lib/`, so no port stylesheet is loaded
at all. Confirmed: `grep -rn CssProvider lib/` returns nothing. This is a
style-axis gap on `lib/view_tabs.rb`'s tab overview (component #3).

### 3. `lib/web_app_info.rb` — the title-priority fallback chain exists in code, but its behaviour is only exercised by one path (behaviour/text axis, feeds into test-parity)

The Ruby carries the same fallback order as `src/webapp/webapp.js`/`ephy.js`
(`application-name` → `apple-mobile-web-app-title` → `og:site_name` →
`<title>` → hostname; manifest `short_name`/`name`/`start_url` override). The
*code* has parity. What is missing is proof: see `test-parity.md` — 8 of the
9 upstream scenarios covering this exact priority chain have no Ruby
counterpart, driven or unit. A behaviour this is not a count/style gap but it
means the claim "ported" rests on reading the code, not on anything that ran.

### 4. `src/application.js`'s dev-only restart action — correspondence, not a gap

`app.restart` on `<Primary><Shift>Q` re-execs the Flatpak dev bundle a
checkout was built from. This port has no bundle to re-exec from — there is
nothing to port *to*, not a decision to skip something that exists. Recorded
here as a correspondence per `component-parity`'s own rule (a widget/action
that cannot exist in the port's run mode is not the same as one the port
chose not to build). Flagged in `accountability-ensurance.md` only because of
*how* the class comment phrases it, not because the omission itself is in
question.

### 5. GSettings schema → JSON store — correspondence

`lib/settings.rb` reproduces both upstream GSettings schemas' keys, defaults,
`observe`/`bind`/`create_action` against a JSON file rather than compiled
`.gschema.xml`. Same key surface, different storage. Spot-checked against
`data/re.sonny.Tangram.gschema.xml` — key set matches. Correspondence, not a
gap, same as `component-identification.md`'s existing note.

## What was checked and found clean

- Window/app actions (6), keyboard shortcuts (11), shortcuts-dialog rows (22):
  spot-checked against `src/Actions.js`, `src/Shortcuts.js`, `src/shortcuts.blp`
  — counts match what `component-inventory.md` already recorded.
- `Adw.ShortcutsDialog` for `GtkShortcutsWindow`, `Adw.AboutDialog` for
  `AdwAboutDialog` wrapper rename: correspondences, not gaps.
- `lib/instance_dialog.rb`/`lib/delete_tab_dialog.rb`: button CSS classes
  (`suggested-action`, `destructive-action`), the three `Adw.EntryRow`s, the
  `Adw.ComboRow` model: present, matches `src/instanceDialog.blp`.

## Totals

| Axis | Status |
|---|---|
| Count | clean, all 13 units present with matching widget counts (spot-checked) |
| Style | **1 gap** — `.tab-close-button` never loaded |
| Behaviour | **2 gaps** — `tangram-resource` scheme, notification auto-grant |
| Text | not separately audited here — see `translation-parity.md`, which is the authority on msgid survival and finds the condition this axis depends on (a catalogue existing at all) is not met |

Component parity is **not clean**: 3 behaviour/style gaps located and named
above, plus the text axis failing wholesale per `translation-parity.md`.

## Resolved this round

Two of the three behaviour/style gaps above are closed:

- **Gap 1's `tangram-resource` scheme is now registered.**
  `lib/web_view.rb#web_context` calls
  `security_manager.register_uri_scheme_as_local('tangram-resource')` and
  `context.register_uri_scheme('tangram-resource') { ... }` for real, serving
  files out of this port's `data/` directory (the icons and `style.css`) —
  the one real resource source the port has, in place of upstream's
  GResource bundle of JS modules, which has no counterpart to serve here (the
  class comment explains the divergence in full). Verified by driving a real
  `WebKit::WebView` through it: `tangram-resource:///style.css` loads with
  `load-failed` never firing and `estimated_load_progress == 1.0`; a path
  that resolves outside `data/` (`tangram-resource:///../../etc/passwd`)
  resolves to nothing rather than escaping it.
  `initialize-notification-permissions` remains unported — calling
  `WebKit::WebContext#initialize_notification_permissions` with a non-empty
  origin list was re-confirmed to segfault the process directly against this
  port's GI loader, so this one piece of gap 1 stands; `lib/web_view.rb`'s
  comment now says so as owed work rather than a settled decision.
- **Gap 2 (`.tab-close-button`) was already fixed before this round — the
  grep this document ran was stale, not the port.** `5392ea2` ("Port the
  tab-overview close-button CSS workaround") added
  `lib/tangram/application.rb#style_provider`, a `Gtk::CssProvider` that
  loads `data/style.css` (which carries the rule) and is added to the
  display at `PRIORITY_APPLICATION` on `activate`. `grep -rn CssProvider
  lib/` now finds it. `component-inventory.md` is corrected to match.
- **Gap 3 (`web_app_info.rb`'s fallback chain had no dedicated test)** is
  closed by `spec/web_app_info_spec.rb` — see `test-parity.md`'s own
  "Resolved this round" section.

The only behaviour/style item still open is the one piece of gap 1 named
above (`initialize-notification-permissions`), plus the text axis, which
`translation-parity.md` still finds not met.

## Verified this round (2026-11-07, independent re-audit)

Reproduced rather than re-read:

- `grep -n "register_uri_scheme\|initialize_notification_permissions\|permission-request" lib/web_view.rb`
  confirms both: the scheme registration call is present at lines 183-184,
  and `initialize_notification_permissions` is *not* called anywhere —
  only described, in the class comment, as unported. The honest-gap
  language holds up against the code, not just against itself.
- `grep -n "CssProvider\|style.css" lib/tangram/application.rb` confirms
  `style_provider` loads `data/style.css` via `Gtk::CssProvider`, matching
  the "resolved this round" claim for the `.tab-close-button` gap.
- Did not re-attempt the `initialize_notification_permissions` segfault
  reproduction (calling a WebKit method already reported to crash the
  process is not worth re-running inside this audit's own session); taking
  the prior reproduction's account as read rather than independently
  re-crashing it is a real limit on this verification, noted rather than
  hidden.

No new behaviour/style/count gap found beyond what this document already
carries. Still not clean: the `initialize-notification-permissions`
auto-grant remains unported, and the text axis still fails per
`translation-parity.md`.

## Root-caused this round (2026-11-07, round 2)

The `initialize-notification-permissions` segfault is no longer just
reproduced, it is root-caused. Reading `gobject-introspection` 4.3.9's own C
source (`rb_gi_arguments_in_init_arg_ruby_list` in
`ext/gobject-introspection/rb-gi-arguments-in.c`) shows it always marshals a
`GList<interface>` Ruby-side argument with `RVAL2GOBJGLIST` and then checks
`G_TYPE_CHECK_INSTANCE_TYPE` on each element — both of which assume a
`GObject` header on every element. `WebKitSecurityOrigin` is a `GBoxed`, not
a `GObject`, so that is a real bug in the gem's general `GList`-of-boxed
marshalling, not anything specific to WebKit or to this method. Documented
in full, with the exact function and file, in `lib/web_view.rb`'s class
comment. An FFI bypass (calling `webkit_web_context_initialize_notification_permissions`
directly, past GI's broken marshaller for just this one call) was considered
and rejected: it would need a raw C pointer for the already-GI-wrapped
`WebContext`/`SecurityOrigin` Ruby objects, and neither `glib2` nor
`gobject-introspection` exposes one — there is no supported way to get a
pointer back out of an object they already wrap. A standalone reproduction
script, `test/webkit_notification_permissions_segfault_repro.rb`, now lives
in the repo for citing when this is filed against ruby-gnome, deliberately
excluded from `test/run_all.rb` because its entire point is to crash the
process. This remains the one open behaviour gap on this axis — now
precisely located rather than merely observed.
