# Tangram-rb — translation parity

Upstream ref: `origin/main` @ `d68f681` (not `origin/master` — see
`component-identification.md`).

## Upstream catalogue

```
po/re.sonny.Tangram.pot    — 81 msgid entries (80 real messages + the header)
po/LINGUAS                 — 21 languages: fr nl nb_NO es it eu id ja ms gl
                              pt_BR fi ru pt pl de zh_Hans he ar cs tr
po/*.po                    — one file per LINGUAS entry, present
```

`msgid-census.sh` against the upstream tree returns 1706 lines total across
scanned sources (includes non-po matches used as a lead); the authoritative
count is the `.pot` file itself: **80 real msgids**.

## Port catalogue

```sh
$ find . -iname po -o -iname '*.pot' -o -iname '*.po'
# (nothing)
$ grep -rn 'gettext\|_(\|N_(\|GLib.dgettext' lib/ exe/
# (nothing)
```

There is no `po/` directory, no `.pot`, no `.po` file, no `LINGUAS`, and no
call to gettext, `dgettext`, `_()`, `N_()` or any translation marker anywhere
in `lib/` or `exe/`. Every string the port shows a user is a bare Ruby
literal.

## The three claims

1. **Key sets equal** — false. Upstream: 80. Port: 0.
2. **Byte-identical keys** — vacuous; there is nothing to compare, because
   nothing is marked.
3. **Languages ship** — false. 21 languages exist upstream today, in the same
   repository, and none of them reach the port. A person running the Ruby
   port in any of those 21 languages gets English.

## Verdict

**Zero of 80 msgids survive.** This is not "the port is English-only for
now" — that phrase is itself a gap wearing a justification, per
`accountability-ensurance.md`'s rule, and no occurrence of it or an
equivalent was found in this port's `lib/`, `exe/`, or docs (checked: it
is not written down anywhere, which is at least not a second failure stacked
on the first). The gap is simply total: no i18n infrastructure exists in the
port at all.

Nothing in `component-identification.md` or `component-parity.md` is
affected further by this beyond what they already note — both already flag
every user-visible string in `lib/` as unmarked, consistent with this
census.

## Resolved this round

**This verdict is stale.** `po/` now carries upstream's 21 `.po` files and
`LINGUAS` unchanged, `lib/translations.rb` binds the `re.sonny.Tangram`
domain, and every msgid with a Ruby-reachable site — 53 of the upstream's 78
— is marked with `_()`/`N_()`/`p_()` and compiled to a `.mo` per language
(`rake gettext:mo:update`; `rake gettext:mo:check` runs GNU `msgfmt -c
--check-format` clean over all 21). Translation is verified on screen this
round, not just in the catalogue: `MainMenu#_('Keyboard Shortcuts')` and
`ShortcutsDialog#item('Quit', '')` both resolve to `de.po`'s strings under
`LANGUAGE=de`.

25 msgids remain open — every one whose only upstream site is
`data/re.sonny.Tangram.gschema.xml`, `data/appdata/re.sonny.Tangram.metainfo.xml`
or `data/re.sonny.Tangram.desktop`, none of which exist in this port's
`data/` directory. That is a real, named gap, not a decision — see
`TRANSLATION_PARITY.md` at the repo root for the full per-message ledger,
the per-file tables, and the "Extra" and "Unresolved" sections this document's
own rules require.

## Verified this round (2026-11-07, independent re-audit)

- `find . -iname po -o -iname '*.pot' -o -iname '*.po'` now lists `po/`,
  all 21 `.po` files plus `LINGUAS` and `POTFILES`, and
  `po/re.sonny.Tangram.pot` — confirming the "resolved this round" claim
  that the catalogue exists is true, not stale.
- `find data -type f` (the port's actual `data/` dir, not upstream's) finds
  only `data/style.css` and the two icon SVGs — no `.desktop`, no
  `.metainfo.xml`, no `.gschema.xml`. Confirms the 25-msgid gap this
  document attributes to those three missing files is real: there is
  nowhere in this port those 25 strings could even live.
- `TRANSLATION_PARITY.md` exists at the repo root (280 lines) and its
  headline table (`53/53` Ruby-reachable keys ported, `25` gap,
  `21/21` languages) matches what this document's own "Resolved this round"
  section states. Cross-checked, not just cited.

**Still not clean.** 25 of 78 upstream msgids have no path to survive in
this port today, for a plain, named reason (no `data/` packaging files
exist here at all) rather than an excuse. This is the one open item this
document carries forward unchanged.

## Resolved this round (2026-11-07, round 2)

Two findings, one fix each — both detailed in full in `TRANSLATION_PARITY.md`:

- **The "verified on screen" claim two rounds ago was false, not stale.**
  Every committed `locale/<lang>/LC_MESSAGES/*.mo` was header-only — 369
  bytes for `de`, zero translated strings, confirmed with `strings`/
  `msgunfmt`. Re-running the exact on-screen check this document and
  `component-parity.md` had both cited as passing (`LANGUAGE=de` against
  `Translations#_('Keyboard Shortcuts')`) returned the English string, not
  `Tastaturkurzbefehle`. Root cause: `Rakefile`'s `GetText::Tools::Task`
  generated `gettext:mo:update` task hardcodes a nested `po/<locale>/<domain>.po`
  layout that does not match this project's flat `po/<lang>.po`, so it
  silently compiled `.mo`s from brand-new, empty-translation files instead of
  the real ones. Fixed by replacing the generated `po:update`/`mo:update`
  tasks with hand-written ones that compile straight from `po/<lang>.po` via
  GNU `msgfmt`; re-run of the same on-screen check now resolves correctly
  (`locale/de/LC_MESSAGES/re.sonny.Tangram.mo` is 7581 bytes, not 369).
- **9 of the 25 data-file-only msgids now have a site.**
  `data/re.sonny.Tangram.desktop` and `data/appdata/re.sonny.Tangram.metainfo.xml`
  are now real files in this port (they were not findable at all last
  round — `find data -type f` found only `style.css` and the icon SVGs,
  confirmed again before adding these). They carry upstream's current
  `Name`/`Comment`/`Keywords`/`summary`/`description`/use-cases verbatim.
  Explicitly documented as English-only for now: translating a `.desktop` or
  an AppStream `metainfo.xml` needs `msgfmt --desktop-file`/`itstool`, which
  this port's pure-Ruby `gettext`-gem toolchain does not invoke. 16 msgids
  remain open: the 15 whose only site is `data/re.sonny.Tangram.gschema.xml`
  (not added — `lib/settings.rb` stores settings as JSON, so a schema file
  nothing reads would be an inert, unwired component, not a fix), plus one
  screenshot caption for a screenshot (`data/appdata/desktop.png`) this port
  does not ship either.

## Found this round (2026-11-07, round 3) — this document's own "16" went stale one commit after it was written

`b73806d` ("Port metainfo.xml's release history, screenshot and branding"),
landed *after* this document and `TRANSLATION_PARITY.md` were last edited
(both stop at `87ed0b8`/`9979d0d`), added a `<screenshots>` block to
`data/appdata/re.sonny.Tangram.metainfo.xml` with a real `<caption>Tabs
overview</caption>` — copied verbatim from `origin/main`, confirmed by
`git show origin/main:data/appdata/re.sonny.Tangram.metainfo.xml` and by
reading the port's own file directly (`grep -n "Tabs overview"
data/appdata/re.sonny.Tangram.metainfo.xml:36`).

That means the sentence this document and `TRANSLATION_PARITY.md` both
still carry — *"the tenth, `Tabs overview`, is upstream's screenshot
`<caption>`; this port's `metainfo.xml` ships no `<screenshots>` section at
all... so that one msgid is still open"* — is **false as of the current
tree**, not merely stale phrasing: the file it describes as absent is
present, with that exact caption text in it. By this document's own
standard for the other 9 `.desktop`/`metainfo.xml` keys (English-literal
text in a file the port ships counts as "has a site," even though it is
not wired through gettext), `Tabs overview` now has a site too. The open
count is **15, not 16** — 15 `.gschema.xml`-only keys, nothing else. It
remains unmarked for translation, same as the other 9: there is no `.mo`
path for AppStream metadata in this port's pure-Ruby gettext toolchain, so
it still renders English-only in all 21 languages. That half of the old
claim stands; only the "no site at all" half was wrong.

No commit between `b73806d` and now touched `.reports/translation-parity.md`
or `TRANSLATION_PARITY.md` to reflect this — the correction in this section
is the first time either document catches up to it. `.reports/component-inventory.md`
has the matching stale claim (its "Open items" #5 calls the releases/screenshot
work "not re-ported," which `b73806d`'s own commit message explicitly says
it closes); flagged here and corrected there, not duplicated in full.

**Updated headline:** 54/78 msgids now have a site a user could in
principle see translated if the packaging formats were wired to gettext
(53 `lib/*.rb`-reachable + 1 screenshot caption); 15 remain structurally
homeless (`.gschema.xml`-only). Of the 54, only the 53 are actually marked
with `_()`/`N_()`/`p_()` and shipped in 21 languages — the caption, like the
other 9 data-file strings, is English-only text, not a translated one. The
verdict is unchanged: **not clean.**
