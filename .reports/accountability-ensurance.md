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
