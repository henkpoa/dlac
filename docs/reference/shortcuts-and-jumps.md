# Shortcuts and jumps — how a control on one surface opens another

**Audience:** whoever adds the next "click here, land there" control in dlac — a quick-menu
row, a floating nudge's click, a bar button, a `/dl` subcommand that should open a panel.

**Read this before writing one.** Every shortcut in the addon shares one seam and one set of
rules; the last time someone built one without them, the jump silently landed on the right
panel *behind the wrong tab* — in every shortcut dlac had, for weeks (ADR 0033).

---

## 1. What a shortcut is here

A control that takes you from where you are to a surface somewhere else. dlac has four kinds
today, and they all end up in the same place:

| Shortcut | Lives in | Opens |
|---|---|---|
| Teleports quick-menu rows | `ui/gearui.lua` (`renderQuickWindowRow`) | a window, or a Gear Helpers panel |
| Menu rows (Lockstyle, Macro book, Hobby bar…) | `ui/menuui.lua` (`ROWS` + `activate`) | a window |
| Floating nudge clicks (E-Box Restock) | the feature's own UI module | its own panel |
| `/dl <thing>` | `dispatch.lua` command handler | usually a panel |

---

## 2. The anatomy: a jump is three things, not one

Miss any one and it looks like a bug that "half works".

1. **WHAT** — the destination's own view state. A Gear Helpers panel is
   `automationsui.openDetail(key)`; a window is its module's visibility flag.
2. **WHERE** — the tab. `host.selectTab('<tab label>')`. This is the step that used to be
   missing, and its absence is invisible when the player happens to be on the right tab
   already.
3. **SHOW** — the main window itself: `gearui.M.visible = true`. A shortcut fired from a
   floating surface (the quick menu, a nudge) usually runs while the window is shut.

**Do not do these three by hand.** For anything on the Gear Helpers tab there is one door:

```lua
gearui.openAutomation('restock')   -- panel + tab + window, in that order
```

`/dl restock`, the restock nudge's right-click, the hobby bars' "open my panel" buttons and
the Teleports row all call it. One definition, so a fix reaches every caller at once — which
is exactly how the 2026-07-30 fix reached all of them.

---

## 3. Recipe: add a row to the Teleports quick menu

The quick menu doubles as the floating quick menu, so it is the right home for anything worth
reaching *mid-play*. Rows live at the bottom of `renderTeleportsPopup` in `ui/gearui.lua`:

```lua
renderQuickWindowRow('hobbybar', 'Hobby bar',
    'Show/hide the hobby bar -- Craft, HELM, Fishing and Chocobo controls in\none window.');
```

`renderQuickWindowRow(key, label, tip, icon, fn)`. The last two are **opt-outs**, both nil for
an ordinary row:

* **`key`** — by default this is *both* the art basename (`assets\<key>.png`) and the action:
  it is handed to `menuui.activate(key)`, so it must be a real Menu row key.
* **`icon`** — pass it when the art is not named after the key. The E-Box Restock row wears
  `ebox`, the crate its own nudge wears, so the two surfaces read as one feature.
* **`fn`** — pass it when the target is not a menuui row. The restock row passes
  `function() M.openAutomation('restock'); end`.

**Gating.** Put the condition around the row, not inside it, and gate on an *affirmative*
answer from the Central service — never on "not nil":

```lua
if gmode ~= nil and gmode.get() == 'CW' then     -- nil = unknown, which HIDES the row
    renderQuickWindowRow('restock', 'E-Box Restock', TIP, 'ebox',
        function() M.openAutomation('restock'); end);
end
```

**Order is the placement.** Rows render top to bottom in source order, under a `Separator`
below the travel tiers.

**Tests you must extend:** run_tests `SET55`–`SET59` parse the source and pin the row list,
its order, that every menu-routed key is a real Menu row, that every icon exists on disk, and
that a gated row is behind its gate. A new row means updating the expected list in `SET56`.

---

## 4. Recipe: jump to a tab from anywhere else

```lua
require('dlac\\ui\\uihost').selectTab('Gear Helpers');
```

**The label is the contract.** `selectTab` matches the tab's registered `label` string
exactly. Rename a tab and every jump to it goes silently nowhere — so rename both, and check
`docs/architecture.md`, which says the same thing next to the tab roster.

What happens after you call it (ADR 0033, and you do not need to think about any of it):

* the request is **held** until that tab is observed open, then clears immediately;
* the selection flag is tried in two argument shapes, then the host **rebuilds the tab bar**
  under a new ID with your tab submitted first — because this build's imgui binding drops the
  flag entirely;
* it costs about five frames, one of which shows the tabs reordered and the body empty;
* if it never lands, it says so in chat, once, naming the tab.

`host.pendingTab()` tells you what it is currently trying to reach.

---

## 5. Hard rules

1. **Never hardcode the main tab bar's ID.** `gearui` calls
   `imgui.BeginTabBar(host.tabBarId('##ffxilac_tabs'), …)` and must not cache the result. That
   ID *is* the rebuild mechanism; hardcoding it again silently disables the only rung that
   works on this install. Pinned by smoke_ui `TAB25`.
2. **Route the action through the existing seam.** menuui rows go through `menuui.activate`;
   Gear Helpers panels go through `gearui.openAutomation`. A shortcut that pokes the
   destination's internals directly is a second definition of "what this row does", and the
   two drift.
3. **Set the panel AND the tab.** Setting only the panel is invisible whenever the player is
   already on the right tab — which is exactly how this class of bug survives review.
4. **Gate on an affirmative mode read.** `gamemode.get() == 'CW'`, never `~= nil`. Unknown
   hides the row.
5. **Icons are `assets\<name>.png`, and a missing one fails silently** into a blank cell of
   the right width. That is correct behaviour and invisible in game, so the *tests* assert the
   file exists. Reuse the feature's existing art rather than minting a second look for it.
6. **Tooltips are `printf` format strings** like every other imgui text call — a literal `%`
   must be escaped or it prints a heap address. (`ui/panelkit.lua` escapes at its funnels;
   raw `imgui.SetTooltip` does not.)
7. **A shortcut that cannot work should not be drawn.** Hide the row, do not draw it disabled
   and explain in a hover — the player cannot act on a surface for content they do not have.

---

## 6. When it goes wrong

| Symptom | Cause |
|---|---|
| Right panel, wrong tab | `selectTab` not called, or the label does not match a registered tab |
| Row does nothing | `key` is not a Menu row key and no `fn` was passed (`menuui.activate` returns false and no-ops) |
| Blank cell where the icon should be | no `assets\<name>.png` — check `icon`, not `key` |
| Row missing entirely | its gate read unknown (`gamemode.get()` before the entity is rendered) |
| `[dlac] could not switch to the "X" tab…` in chat | the jump exhausted every rung; the panel is set, the tab is not. Report it — it means both the flag *and* the rebuild failed on that build |

---

## 7. Where the tests live

* **smoke_ui `TAB1`–`TAB25`** — the jump itself, driven against four stub bindings
  (table-p_open, nil-p_open, flag-blind, flag-blind-and-adopt-blind) with a stub that models
  ImGui's real tab-bar semantics: a bar is identified by the ID passed to `BeginTabBar`, an
  unseen ID resets the selection, a flag lands at the *next* layout, and a bar with nothing
  selected adopts index 0. Extend these if you change `renderTabs`.
* **run_tests `SET55`–`SET59`** — the quick-menu rows, parsed out of `ui/gearui.lua` source
  because neither the action nor the art is reachable from a load test.
* **smoke_ui `S10b`** — the tab label `gearui.openAutomation` passes.

Related: **ADR 0033** (a jump takes the tab, it does not ask for it), **ADR 0017** (the shared
hobby bar), `docs/architecture.md` → uihost.
