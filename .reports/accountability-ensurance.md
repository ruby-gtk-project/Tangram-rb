# Tangram-rb — accountability ensurance

Scan run over `lib/`, `exe/`, `.reports/`, and every top-level `.md` (no
`PORTING.md` or `FINDINGS.md` exist in this port — checked, neither file is
present).

```sh
$ grep -rniE "TODO|FIXME|not implemented|for now|in a future|deliberately|out of scope|by design|does not carry over|not applicable" lib/ exe/ .reports/ PORTING.md FINDINGS.md
```

(`PORTING.md`/`FINDINGS.md` not found; grep ran against the rest.)

## Findings

### 1. False green in `.reports/component-inventory.md` — the most serious class of finding this skill looks for

Row 13 of the component table claims `lib/web_view.rb` carries "the
`tangram-resource` scheme ... " and marks the row **yes**, i.e. ported. It is
not ported — see `component-identification.md` and `component-parity.md`,
which found no `register_uri_scheme` call anywhere in `lib/`. That line in
`component-inventory.md` is a claim of completeness resting on nothing that
was ever checked against the actual file; the next reader who trusted that
row would file the gap as closed. It is fixed in this round's two documents
above; `component-inventory.md` itself is left as the earlier pass wrote it,
flagged rather than silently edited, so the correction is visible as a
correction and not folded invisibly into the prior record.

### 2. `lib/web_view.rb:56` — "deliberately left out" used on a real gap

> Three pieces of upstream's file are deliberately left out rather than
> approximated.

Two of the three things that sentence covers — the `tangram-resource` scheme
and the `initialize-notification-permissions` auto-grant — are real,
user-visible gaps (confirmed in `component-parity.md`): the port's web view
cannot serve anything through that scheme, and it will prompt a user for
notification permission upstream would have silently granted. "Deliberately
left out" reads as an informed decision the author stands behind. Under full
parity there is no valid reason to omit either; the honest form is:

> I did not build the `tangram-resource` URI scheme or the
> `initialize-notification-permissions` auto-grant, because I am an idiot.
> Upstream: `src/WebView.js:97-104` (scheme), `src/WebView.js:109-116`
> (auto-grant). Port: `lib/web_view.rb` has neither.

The third thing the same sentence covers — the commented-out, dead-upstream
web-inspector block — is correctly not a gap (there is nothing upstream to
port), so the sentence conflates one true non-issue with two real omissions
under one shared, confidence-inspiring word. That conflation is itself part
of the problem: a reader who checks the inspector claim and finds it true
has no reason left to doubt the other two.

**Not rewritten in this pass** — this audit's job is to report, not to edit
port source under its own authority; the finding is handed back named and
located, per this skill's rule that every hit still needs you to say
*where* you found it.

### 3. `lib/tangram/application.rb:17` — same construction, weaker case

> Upstream's `__DEV__` restart action is left out: it exists so a running
> app can re-exec the bundle a Flatpak dev build was built from, and this
> port has no such build to re-exec.

Unlike the two findings above, this one is a genuine correspondence, not a
hidden gap — `component-parity.md` records why (there is no Flatpak dev
bundle in this port's run mode to re-exec from; the feature has no referent
to port *to*, not a decision to skip one that exists). The phrasing still
reads as a settled decision rather than as a correspondence recorded as one,
which is the pattern this skill exists to catch regardless of whether the
underlying call turns out defensible. Recorded for completeness; no action
needed since the substance checks out, but the habit of phrasing is the same
habit that produced findings 1 and 2.

### 4. `.reports/component-inventory.md` lines 36, 107, 130 — "unported"/"not ported" used honestly

These three are the skill's own carve-out working as intended: each names a
missing behaviour plainly (`.tab-close-button` CSS, the `po/` catalogue, the
GSettings `.gschema.xml` divergence) rather than dressing it up. Not hits.

### 5. `lib/url.rb:167` — "deliberately lenient" describes a regex-construction choice, not an omission

Not a parity gap at all — it is a comment about why a validation pattern is
loose, with no missing upstream behaviour behind it. Not a hit.

## What this changes about the other four reports

Nothing in `component-identification.md`, `component-parity.md`,
`test-parity.md` or `translation-parity.md` cites `PORTING.md` or any other
document as authority for a gap — there is no such document in this repo to
cite. The one load-bearing document risk found was the inventory's own
false-green row (finding 1), which the other reports now correct explicitly
rather than inherit.

## Verdict

Not clean when this was written. One false-green claim in a committed
report, and one comment in `lib/web_view.rb` that dressed two real gaps in
decision language.

## Resolved this round

Both findings are fixed, not just re-flagged:

- **Finding 1 (the false-green row).** `component-inventory.md` row 13 is
  corrected: the `tangram-resource` scheme is implemented for real now (see
  `component-parity.md`'s "Resolved this round"), so the row's "yes" is true
  rather than unearned. The same pass also caught and fixed a second,
  separate stale claim the inventory carried — that no `Gtk::CssProvider`
  was loaded anywhere in `lib/`, which stopped being true two commits before
  the inventory was last written (`5392ea2`) and nobody had gone back to fix
  the sentence.
- **Finding 2 (decision language on real gaps).** `lib/web_view.rb`'s class
  comment is rewritten. It no longer calls the scheme and the
  notification-permissions auto-grant "deliberately left out" in one breath
  with the dead web-inspector block. The scheme is now implemented (so that
  clause is gone outright); the notification-permissions piece is described
  as unported work the port owes, backed by a reproduced segfault rather
  than an assumed one, not as a decision anyone stands behind.

Finding 3 (the `app.restart` comment) was left as recorded — the finding
itself says no action is needed since the substance checks out; only the
phrasing habit was worth naming, and it was named, not fixed, there too.

## Verified this round (2026-11-07, independent re-audit)

Re-ran the scan against the current tree:

```sh
$ grep -rniE "TODO|FIXME|not implemented|for now|in a future" lib/ exe/ .reports/ PORTING.md TRANSLATION_PARITY.md
(no hits outside this report's own grep examples)
```

No new false-green or excuse-language hit found beyond what the prior round
already fixed. Specifically checked and found honest, not excused:

- `lib/web_view.rb`'s class comment (rewritten per Finding 2's "resolved
  this round") now states the `initialize-notification-permissions` gap as
  owed work backed by a reproduced segfault, not a decision — read directly,
  confirmed, no decision-language relapse.
- `test-parity.md` and `component-parity.md`'s own "Resolved this round"
  sections were checked against the actual code and the actual test run
  (see those documents' own "Verified this round" sections) rather than
  taken on their own word — both held up.
- `component-identification.md`'s newly-added note on the missing
  `.desktop`/metainfo/`.service` files (this round) is itself an example of
  the gap being named rather than folded silently into an existing
  "ported" claim — checked that no other document's totals table counts
  those files as present anywhere.

## Verdict (unchanged, when the above was written)

Not clean. Two real, named gaps remain across the other four reports
(`initialize-notification-permissions`, 25/78 msgids), both disclosed as
gaps rather than dressed as decisions. No false-green claim survives in any
committed report as of this round.

## Found this round (2026-11-07, round 3) — two stale claims, and one overstated "verified" that didn't reproduce

This round re-ran the gate and re-diffed the port against `origin/main`
rather than re-reading the prior round's prose, on the theory that a
report's own confidence is not evidence. Three things surfaced, none of
them hidden on purpose, all three a failure to re-check a claim against a
commit that landed after the claim was written:

1. **A stale "still open" claim, one commit after it stopped being
   true.** `.reports/component-inventory.md`'s Open item 5 and
   `TRANSLATION_PARITY.md`/`.reports/translation-parity.md`'s "one
   screenshot caption this port ships no screenshot for" both describe
   `metainfo.xml`'s `<releases>`/`<screenshot>` block as unported.
   `b73806d` ("Port metainfo.xml's release history, screenshot and
   branding") ported it — its own commit message names
   `component-inventory.md` item 5 as the gap it closes — but no commit
   after `b73806d` touched either translation document or re-checked
   `component-inventory.md`'s own open-items list against the file it was
   describing. Both are corrected in this round (see those documents'
   "Found this round" sections and `component-inventory.md`'s item 5).
   This is the opposite shape from a false green (it understates progress
   rather than overstating it), but it is the same root failure this skill
   exists to catch: a claim about the code that was never re-checked
   against the code after the code changed.
2. **A related accounting error that followed from (1).** `TRANSLATION_PARITY.md`'s
   headline "16 gaps" and `.reports/translation-parity.md`'s matching
   figure both carried one msgid (`Tabs overview`) as having no site, when
   `b73806d` gave it one. The true count is 15. A reader who took either
   document's 16 at face value would be off by one on the one number this
   whole audit exists to get right.
3. **"Verified this round... the 174 number is real" (`test-parity.md`,
   prior round) was true of the one run it was based on, and did not
   reproduce on an independent re-run this round.** Running the exact
   committed gate command (`nix develop --command xvfb-run -a ruby
   test/run_all.rb`) the first time this round produced `GATE FAILED` —
   134 of 134, not 174, with the RSpec check reporting `(0/0)` despite its
   own output showing 40 passing dots. Three further runs on the identical
   tree then came back `GATE OK`/174/174. This is not a fabricated claim —
   the prior round's author did run the gate and did see it pass — but
   writing "the 174 number is real" and "no further gap found" off a
   single green run, for a harness whose own source comments already warn
   about WebKitGTK multi-process fragility, is exactly the overconfidence
   this skill looks for: a true observation stated with more certainty
   than one sample earns. Detailed in `test-parity.md`'s own "Found this
   round" section, including the exact failure mechanism (a truncated
   subprocess-output capture, not a real test failure). This round's own
   gate claim is stated as what it is — 3 of 4 runs green, not "the gate
   passes."

None of the three is a fabricated record or an invented pass; all three
are claims that were accurate at the moment they were written and were
never revisited against a tree, or a rerun, that had since moved past
them. That gap — between "true when checked" and "still being presented
as current" — is the thing this round adds to the list of things this
skill watches for.

## Verdict

Still not clean. The runtime gate itself is now a named gap (flaky, not
reliably 174/174), the `.gschema.xml` translation shortfall is 15 msgids
not 16 but is still a shortfall, and `initialize-notification-permissions`
remains unported. Three stale/overconfident claims found and corrected
this round, in the reports themselves rather than only in this one; none
of them was a decision dressed as settled, and none survives uncorrected
past this commit.

## Found this round (2026-11-08, round 4)

Re-ran the scan and re-diffed against two commits that landed since the
last round's audit (`4ace5aa`, `5ed9beb`), on the same theory as before —
a report's own confidence is not evidence.

```sh
$ grep -rniE "TODO|FIXME|not implemented|for now|in a future" lib/ exe/
(no hits)
```

Clean of excuse language in `lib/`/`exe/`, same as every prior round. Two
findings outside that grep, both about the reports themselves rather than
the port:

### 1. Two committed reports went stale the moment `4ace5aa`/`5ed9beb` landed, and nothing caught it before this round

- `.reports/component-inventory.md`'s component table (row 1) and
  `.reports/test-parity.md`/`.reports/component-parity.md`'s prose both
  still named `lib/tangram/application.rb` after `4ace5aa` renamed it to
  `lib/application.rb` (dropping the `Tangram::` module to match every
  other ported file). `component-inventory.md`'s own "Open items" #4
  already recorded the rename as done — but its component table two
  sections above was never updated to match its own open-item note, so
  the file described itself inconsistently: "done" in one place, the old
  path in another. Corrected in `component-identification.md`'s
  "Verified this round" section this round, rather than silently edited
  into the original table.
- Every report's last-committed "current" check-count was `174`
  (`test-parity.md`'s and `component-inventory.md`'s own headline
  figures), one commit stale against `5ed9beb`'s `180`. Not a fabrication
  — `174` was real when written — but it sat in committed, readable
  documents as "the gate" for however long it took this round to start,
  with no document flagging that a commit had moved past it. This is the
  same "true when checked, never revisited" pattern the accountability
  skill flagged twice already (see "Found this round, round 3" above);
  it recurred a fourth round running, which is itself worth naming: fixing
  the individual stale claim each time has not fixed the habit of not
  re-checking a number after each commit that could move it.

### 2. A worse version of the known gate flakiness: a false *passing* number, not just a false failure

`test-parity.md`'s own "Found this round" section (this round) has the
full account: three independent runs of the committed gate command, same
tree, no commit in between, produced `180`/`184`/`180` — and the `184` run
printed `drive_new_tab.rb (48/48)` for a script with exactly 44 static
`d.check(...)` call sites and no loop, conditional or retry that could
produce more than 44 in one execution (confirmed by direct count, by
`scan`, and by a standalone re-run immediately after, which printed
`44 of 44` on the same unmodified file). `GATE OK` was printed both times,
with no distinguishing signal.

This is the most serious kind of finding this skill looks for, by its own
severity ranking, and it is worth being precise about which category it
is: it is not a false claim this audit is asserting on the port's behalf
(this document corrects stale claims, it does not make new unverified
ones) — it is a defect in the test harness itself, found by running it
three times rather than trusting one green run, exactly the discipline
the prior two rounds' findings established. Nobody had committed a
`180`-or-higher-than-real number to any report before this round (the
`184`/`48` numbers exist only in this round's terminal output and in
`test-parity.md`'s documentation of the anomaly, not asserted as the
port's true state anywhere), so this is not yet a false green *in a
report* — it is a live demonstration that the gate itself, unfixed, is
capable of producing one the next time nobody happens to re-run it twice.
Recorded as owed work (root-cause and fix the capture path in
`test/run_all.rb`), not fixed under this audit's own authority.

## Verdict

Still not clean. Four real, named gaps carry forward or were found this
round: `initialize-notification-permissions` unported,
`data/re.sonny.Tangram.service` never ported (see
`component-identification.md`), 15/78 msgids with no site
(`translation-parity.md`), and the gate's capture path now demonstrated
capable of printing a passing-looking but impossible check count under
load. No decision dressed as settled was found, and no false claim was
found already sitting in a committed report — but the fourth round in a
row of catching a stale number after the fact, plus a newly-demonstrated
way for the gate to lie convincingly, means the margin between "clean" and
"a false green nobody caught yet" is thinner than the individual
corrections suggest.
