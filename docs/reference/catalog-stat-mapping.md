# Catalog stat vocabulary repair, September 28, 2026

Warlock's Tabard (12642) carried `ENFEEBLE = 15` rather than
`EnfeeblingMagicSkill = 15`. Canonical skill weights therefore scored it as
zero. The row formatter independently hid it behind its four-stat budget.

The AscensionXI catalog now uses existing DLAC keys for 437 raw modifier
names, correcting 7,034 stat entries without changing their values or item
metadata. These mappings come from the established maintainer API stat map
and are recorded in `gear/modaliases.lua`. They include combat/magic/craft
skills, elemental resistances, status resistance, and job bonuses. Unknown
modifiers remain untouched: this repair does not certify their units or
interpretation.

Stat metadata and scoring accept the old names for saved weights and older
stat tables. Exact server `EVASION` means `EvasionSkill`; canonical `Evasion`
(including lowercase user input) remains the separate evasion stat.
Skill bonuses take precedence in compact rows; omitted master stats are
disclosed with a `(+N more)` indicator. Skill names are spaced for readability.

The external server pack generator must use the canonical vocabulary on
future refreshes. CI now rejects reintroduced raw aliases across the entire
catalog with `lua tests/catalog_stat_mapping.lua`. That test also checks every
legacy alias in both scoring directions, the tabard's tooltip and summary,
capped weights, and the evasion/wind skill distinctions.

Validation: catalog mapping regression, AscensionXI catalog/import regression,
pack lint, additional-effect formatting, headless suite, and UI smoke suite.
A differential check confirmed every catalog edit is solely a key rename.
The owner confirmed the patch works in the production client on September 28.
The PR preserves the newer Artifact/catalog changes already on main. Reload the addon to replace
cached catalog records and summaries: `/addon reload dlac`.
