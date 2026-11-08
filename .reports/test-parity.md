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

## Found this round (2026-11-07, round 3): the gate is flaky, and the prior round's confidence in "174, 0 failed" was overstated

Re-ran `nix develop --command xvfb-run -a ruby test/run_all.rb` four times
independently, to check whether the prior round's single green run was
representative:

```
run 1: FAIL spec/ (rspec) (0/0)  →  134 of 134 checks passed across 4 checks  →  GATE FAILED
run 2: ok   spec/ (rspec) (40/40) →  174 of 174 checks passed across 4 checks →  GATE OK
run 3: ok   spec/ (rspec) (40/40) →  174 of 174 checks passed across 4 checks →  GATE OK
run 4: (see below)
```

Run 1's captured output shows the RSpec subprocess printing its 40
progress dots (`........................................`) and then
nothing — no "Finished in N seconds" line, no "N examples, N failures"
line — before `run_all.rb`'s parent process read the tempfile back and
moved on. `run_all.rb`'s own regex (`/(\d+) examples?, (\d+) failures?/`)
never matches on a truncated capture, so `total` and `passed` both come
back `0`, the check is marked `FAIL (0/0)`, and the whole gate fails even
though every example that got to run, passed. Running the identical RSpec
invocation standalone (outside `run_all.rb`'s `Process.spawn`-to-tempfile
capture) immediately afterward printed the summary line cleanly
(`40 examples, 0 failures`) — this is not the suite failing, it is the
*harness's capture of the suite* failing intermittently, which the script's
own comments already flag as a known WebKitGTK multi-process fragility
("GTK and WebKitGTK are not meant to be initialized twice in one process")
without this exact failure mode (the summary line itself going missing,
independent of the process's exit status) having been caught before.

**What this changes:** the previous "Verified this round" section above
ran the gate once, got `GATE OK`, and wrote "No further gap found... the
174 number is real" — true of that one run, but stated with more
confidence than a single sample supports for a harness its own source
comments already describe as fragile under WebKitGTK re-initialization.
This round's 4 runs: 3 green, 1 red, same code, same tree, nothing
committed in between. A ~25% failure rate on the committed gate command is
itself a parity gap under this task's own rule — *"a failed or narrow
drive run as a parity gap in its own right."* The task's stated gate
(`174 checks passed, 0 failed`) is a real, reachable outcome, not a
fabrication, but it is not the *only* outcome the exact same command
produces on this exact tree, and no document before this round disclosed
that.

**Not yet root-caused.** This round locates the failure precisely (the
RSpec child's final summary line not reaching the tempfile `run_all.rb`
reads, specifically — not a real test failure, not a flaky assertion) but
does not fix it. A real fix needs either a retry loop in `run_all.rb`, a
fsync/flush guarantee on the child's stdout before it exits, or switching
the RSpec invocation to a machine-readable formatter (`--format json`)
that fails loudly on a truncated read rather than silently producing
`(0/0)`. None of that is done here — this is a finding, not a patch, and
is recorded as owed work rather than fixed under this audit's own
authority.

## Found this round (2026-11-08): the retry fix changed the failure mode, it did not remove it — and the new mode is worse

`4ace5aa` ("Make the gate's RSpec capture deterministic...") added the
retry loop described in the previous round's finding, and `5ed9beb`
("Drive the eight web-view keyboard shortcuts...") grew `drive_new_tab.rb`
from 38 to 44 checks, landing the task's stated gate for this round:
`180 checks passed, 0 failed, covering 13 components`.

Three independent runs of the exact committed gate command
(`nix develop --command xvfb-run -a ruby test/run_all.rb`) this round, on
this exact tree, no commit in between:

```
run 1: ok drive_new_tab.rb (44/44) → 180 of 180 → GATE OK   (matches the task's stated gate)
run 2: ok drive_new_tab.rb (48/48) → 184 of 184 → GATE OK   (impossible — see below)
run 3: ok drive_new_tab.rb (44/44) → 180 of 180 → GATE OK   (matches again)
```

Run 2's `(48/48)` is not a real result. `test/drive_new_tab.rb` has exactly
44 `d.check(...)` call sites — confirmed three ways: `grep -c 'd\.check('
test/drive_new_tab.rb` → 44, a Ruby `scan(/d\.check\(/)` → 44, and reading
the file top to bottom (reproduced in full in this document's earlier
section) — and it contains no loop, no conditional branch and no
retry/recursion around any check: every step runs exactly once, in a fixed
sequence, driven one per `GLib::Timeout` tick. There is no code path in the
committed script that can execute more than 44 checks in one run. Running
`ruby test/drive_new_tab.rb` standalone (outside `run_all.rb`'s capture)
immediately after seeing `(48/48)` printed `44 of 44 checks passed,
DRIVE OK` — deterministic, as the static count predicts.

So `run_all.rb` printed a passing number for a subprocess check that no
execution of the underlying script could have produced. This is not the
previously-found failure mode (a truncated capture read as `(0/0)` and
correctly flagged `FAIL`) — this is a **wrong but plausible-looking passing
number**, which `GATE OK` did not flag at all. The retry loop's own
truncation guard (`break if passed && total&.positive?`) only checks that a
summary line was *found*, not that the numbers in it are *sane* for the
command that was run; a `(48/48)`-shaped string passed that guard on the
first attempt with no retry warning printed, because `48 == 48` looks like
a clean pass. Not root-caused in this round — plausible causes include a
`Tempfile.create`-returned path being reused across two overlapping
subprocess lifetimes under the heavy concurrent host load this round ran
under (dozens of unrelated `ruby`/`xvfb-run` processes were competing for
CPU at the time; see `accountability-ensurance.md`), but this was not
isolated with certainty and is recorded as owed investigation, not a fix.

**This is a parity gap in its own right, by the task's own rule** ("treat a
failed or narrow drive run as a parity gap in its own right"): a gate that
can print a self-consistent-looking but fabricated passing count, with no
signal distinguishing it from a real one, means every "N checks passed"
figure this port's reports and commit messages cite — including this
round's own `180` — is a number that happened to be believed, not a number
that was proven immune to this failure mode. Two of three runs this round
matched the expected, statically-verifiable count; one did not and gave no
indication it shouldn't be trusted. The gate is GREEN more often than RED,
but "green" and "the printed number is true" are no longer the same claim
for this harness, which is worse than the previous round's flakiness (a
false `FAIL` is safe to distrust; a false `OK` with a wrong-but-plausible
number is not self-announcing).
