# Window size (UI scale) — ticket AXI-24

Ticket: <https://tickets.ascensionffxi.com/?view=tickets&entry=AXI-24>. Shipped as
`2026.11.13a`.

## Why

Ashita 4.3 raised its default interface font from 14px to 18px. dlac was laid out
for the smaller font, so every window grew by more than a quarter on the same
screen; the Stable tab, the widest one, no longer fit comfortably at 1080p.

## What it does

- **Menu > Settings > Window size**: 70 / 80 / 90 / 100 / 110 / 125 / 150%. Saved per
  character in `uiflags.lua` (`uiscale`). 100% is the default, so nothing changes
  for anyone who does not touch it. 80% is close to the old size.
- **`/dl uiscale 85`** takes any size from 60 to 150; `/dl uiscale reset` returns to
  100%; bare `/dl uiscale` prints the current size.
- Changing the size also resizes the main window by the same factor, once.

## How it works

`ui/uiscale.lua` pushes a resized copy of the current font once per frame around
everything gearui's present hook draws, and pops it in the same frame. Text,
buttons, tabs, rows, popups and tooltips follow the font. Pixel counts written in
the source do not, so they go through `uiscale.px(n)` where they have been
converted.

| Surface | State |
|---|---|
| Text and text-sized widgets in every dlac window | Scaled |
| Main window default size and minimum size | Scaled |
| Stable tab (cards, portraits, roster slots, details pane, breakpoints, charge gauge) | Scaled |
| Fixed pixel widths in the other tabs and windows (about 400 call sites) | **Not converted yet**: they keep their size, so a column or button can be roomier than its text below 100% and tight above it |
| Item icons | Not scaled |
| Floating equipment window | Keeps its own slider (Equipped tab) |
| Ready / PLD / WHM gauges | Keep their own `/dl gauge scale` |

**Both Ashita versions.** The module picks one of two ways to resize the font:

| Client | Way |
|---|---|
| Ashita 4.3 / ImGui 1.92 (AscensionXI) | `PushFont(nil, size)`, as the `chains` addon does |
| Older Ashita (CatsEyeXI) | Set the current font's `Scale`, `PushFont(font)`, restore `Scale` at once. CatsEyeXI's own `partyfinder` and `fancychat` scale text through the same field (`imguiwrap.lua`) |

The older way is checked on its first push: if the font size did not move, the
push is taken back and the Settings row says "Not available on this Ashita
version" for the session. The older client draws from a fixed-size font image,
so text can look soft above 100%.

## Not checked in game

Built and tested headless only (`tests/uiscale.lua`, 86 checks). Owed in game, on
**both** clients (AscensionXI and CatsEyeXI):

1. Settings > Window size > 80%: text shrinks in the main window and the window
   itself gets smaller; the Stable tab shows more, smaller cards.
2. `/addon reload dlac`: the size is remembered.
3. The floating equipment window and the job gauges do not change size.
4. Other addons' windows do not change size (the font is popped every frame).
5. 125%: note any tab where a fixed-width button clips its text.

## Wiki text (DLAC page, Settings section)

> **Window size.** If dlac's windows are too large on your screen, open
> **Menu > Settings** and pick a **Window size** (70% to 150%), or type
> `/dl uiscale 80`. The floating equipment window and the job gauges have their
> own size settings.
