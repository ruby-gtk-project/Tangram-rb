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
