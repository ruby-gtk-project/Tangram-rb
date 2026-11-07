# Tangram-rb — test parity

Upstream ref: `origin/main` @ `d68f681` (not `origin/master` — see
`component-identification.md`).

## Upstream census

`test-census.sh` returns **zero rows** against the upstream tree. That is
the script failing to recognise this suite's shape, not an absence of tests
— upstream has no `it(...)`/`Test.add_func`-style registrations; it writes
two flat scripts of bare `assert.is()` calls, run directly:

| File | Shape | Assertions |
|---|---|---|
| `src/utils.test.js` | 16 bare `assert.is()` calls testing `isSameSite` | 16 |
| `src/webapp/test.js` | 9 async IIFE scenarios (one with 2 assertions) feeding `getWebAppInfo`, run under a real `WebKit.WebView` against a local `Soup.Server` | 11 |

**Read the script's zero as a lead, not a verdict** (per the skill's own
instruction) — both files were opened and read directly. 27 upstream
assertions across 2 files, 2 "suites."

## Port census

`test-census.sh` against the port finds 4 files: `spec/url_spec.rb` (rspec,
17 examples) and three house-style drivers run via `check(...)` —
`test/check_models.rb` (57 checks), `test/drive_main_window.rb` (33 checks),
`test/drive_new_tab.rb` (38 checks).

### `src/utils.test.js` (16 assertions) → `test/check_models.rb`, section `# Url (upstream src/utils.test.js)`

Ran it: `nix develop --command xvfb-run -a ruby test/check_models.rb` prints
16 `same_site?(...)` lines matching the 16 upstream pairs value-for-value
(same hosts, same expected booleans, including the IPv6 literal and the
`ком.рус`/`кто.рф` public-suffix pair). **Ported, 16/16, verified by running
it.** `spec/url_spec.rb` additionally exercises the same `same_site?` cases
plus `normalize` behaviour upstream never tested — extra coverage, not a gap.

### `src/webapp/test.js` (9 scenarios, 11 assertions) → **1 of 9 scenarios covered, and only indirectly**

`lib/web_app_info.rb` carries the same fallback-priority logic (verified by
reading, see `component-parity.md`), but no Ruby test exercises it in
isolation. The only thing that touches `WebAppInfo#fetch` at all is
`test/drive_new_tab.rb`'s step `[6] the web app was identified`, which checks
two outcomes (`ok the manifest short name became the tab name`, `ok the
manifest start URL became the homepage`) against one real page that serves a
full manifest — upstream's *last* scenario only.

The 8 scenarios with no Ruby counterpart, named by the behaviour they pin:

| Upstream scenario (`src/webapp/test.js`) | Behaviour owed |
|---|---|
| `msapplication-starturl` meta present | URL comes from the meta tag, not the page's own location |
| no manifest, no title, no app-name metas | title falls back to the page's hostname |
| `og:url` meta present, no manifest | URL comes from the Open Graph tag |
| `application-name` meta + a `<title>` | title prefers the app-name meta over the title tag |
| `apple-mobile-web-app-title` + a `<title>` | title prefers the Apple meta over the title tag |
| `og:site_name` (property) + `application-name` + title | title prefers `og:site_name` over `application-name` |
| `og:site_name` as both `name` and `property` + `application-name` + title | the `property` variant of `og:site_name` wins over the `name` variant |
| plain `<title>` only | title falls back to the title tag when no meta is present |

These are exactly the fallback-order branches `TITLE_SCRIPT`/`URL_SCRIPT` in
`lib/web_app_info.rb` implement. The implementation exists; **no test proves
it**, for either side of the priority order. This is a gap, not a
partially-ported test wearing a pass — 1/9 scenarios, 2/11 assertions.

## Test counts

| | Upstream | Port |
|---|---:|---:|
| Assertions censused by hand | 27 | — |
| `isSameSite` — ported | 16 | 16 (`check_models.rb`) |
| `getWebAppInfo` fallback chain — ported | 11 | 2 (via one indirect driver step) |

**Test parity is not met.** 9 upstream assertions covering 8 distinct
fallback-priority branches of `WebAppInfo` have no Ruby test, driven or unit.

## The runtime gate, read as a lead not a verdict

The task's stated gate: `drive_ok=true, 128 checks passed, 0 failed, covering
11 components`. Reproduced exactly:

```
test/drive_main_window.rb → 33 of 33 checks passed, DRIVE OK
test/drive_new_tab.rb     → 38 of 38 checks passed, DRIVE OK
test/check_models.rb      → 57 checks, 0 failed
                             33 + 38 + 57 = 128
```

That accounts for the "128 checks." Two things the gate's framing obscures:

1. **It excludes `spec/url_spec.rb` entirely.** Run separately:
   `31 examples, 0 failures`. The gate's 128 and the spec suite's 31 are
   disjoint — "128 checks passed" is not "the whole suite passed," it is
   "three specific scripts passed." The spec suite does pass, but nothing in
   the gate's own number says so; it had to be run separately to find out.
2. **"Covering 11 components" is accurate, and the other 2 of 13 component
   units are the ones worth naming, not waving past:**
   - `lib/tangram/application.rb` — no driver step exercises app-level
     behaviour (app id, icon search path, app-level accelerators) directly;
     it is exercised only as the thing that boots the window under test.
   - `lib/web_app_info.rb` — per above, 1 of 9 upstream scenarios covered.
     The inventory's own non-widget-support table lists this file as
     "ported," which is true of the code and not of anything that checks it.

A component no check exercises is unverified, not done — the task's own
standard. Both of the two uncovered units are support files feeding directly
into user-visible behaviour (what title a new tab gets, what the app does on
first run), not incidental plumbing.

## Relation to other ledgers

No binding limitation is in play for either gap in this document — nothing
here is excused or made easier by a ruby-gnome defect. Both are plain missing
test coverage for logic that already exists in `lib/`.

## Resolved this round

Both gaps above are closed, not just re-described:

1. **`spec/web_app_info_spec.rb` ports all 9 scenarios, 11 assertions,
   directly.** Each one runs a real `WebKit::WebView` against a real HTTP
   response from a local server (the same shape `test/drive_new_tab.rb`
   already used for its one indirect case), feeds `WebAppInfo.fetch`, and
   asserts the same title/URL outcome upstream pinned — including the two
   ordering assertions the table above only named as owed (`og:site_name`
   property-vs-`application-name`, and the `name`-vs-`property` variant of
   `og:site_name` against each other). 9/9 scenarios, 11/11 assertions.
2. **`lib/tangram/application.rb` now has a driver step of its own.**
   `test/drive_main_window.rb`'s new first step, "the application itself is
   set up," checks `app.app`/`app.icon_theme`/`app.style_provider`
   directly — application id, the three app-level accelerators
   `Shortcuts#build` installs, the icon search path, the PulseAudio env
   vars, and the loaded CSS provider — rather than only exercising
   `Application` as the thing that happens to boot the window under test.
3. **The gate now folds the RSpec suite in.** `test/run_all.rb` runs
   `check_models.rb`, both `drive_*.rb` scripts and the whole of `spec/` as
   four subprocesses (GTK/WebKit do not tolerate being initialized twice in
   one process, which an in-process-RSpec first draft of this script found
   out the hard way) and prints one combined total. As of this round:
   `174 of 174 checks passed across 4 checks` — `57 + 39 + 38` from the
   three scripts plus `40` RSpec examples (`url_spec.rb`'s 31 and
   `web_app_info_spec.rb`'s 9), with none of the four excluded from the
   headline figure.

`test/check_models.rb`'s and `test/drive_main_window.rb`'s own totals moved
(57 unchanged; `drive_main_window.rb` grew from 33 to 39 checks with the new
application-level step) — the "128" in the gate quoted above is now "174,"
and that number already includes the RSpec suite.

## Verified this round (2026-11-07, independent re-audit)

Actually ran the gate rather than trusting the committed number:

```
$ nix develop --command xvfb-run -a ruby test/run_all.rb
ok   check_models.rb (57/57)
ok   drive_main_window.rb (39/39)
ok   drive_new_tab.rb (38/38)
ok   spec/ (rspec) (40/40)
174 of 174 checks passed across 4 checks
GATE OK
```

Matches the task's stated gate (`drive_ok=true, 174 checks passed, 0
failed, covering 13 components`) exactly, and matches this document's own
"Resolved this round" figure (174, up from 128). "Covering 13 components" is
consistent with this document's own earlier finding that the prior 128-check
gate covered only 11 of 13: `drive_main_window.rb`'s new first step
exercises `lib/tangram/application.rb`, and `spec/web_app_info_spec.rb`
exercises `lib/web_app_info.rb`, bringing both previously-uncovered units
into the running suite — 11 + 2 = 13.

No further gap found. The suite was executed, not assumed; the 174 number is
real.
