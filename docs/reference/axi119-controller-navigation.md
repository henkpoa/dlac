# Controller navigation — ticket AXI-119

Ticket: <https://tickets.ascensionffxi.com/?view=tickets&entry=AXI-119>. First
shipped as `2026.11.17a`. AscensionXI's Ashita only for now; CatsEyeXI's older
Ashita is a later step (see "The older Ashita").

## What it does

- **Menu > Settings > Controller > Controller navigation**, off by default. Saved
  per character in `uiflags.lua` (`padnav`).
- **Open / close** is a two-button combination: hold one button, press another.
  It is captured from a real press (**Bind**, then do it on the pad), because
  button ids differ per pad.
- Pressing the combination hands the controller to dlac: buttons stop reaching
  the game and the d-pad moves a highlight through dlac's windows. With a dlac
  window already open it walks that window; with none open it opens the
  Teleports menu.
- **Confirm**, **Back**, **Previous tab** and **Next tab** have defaults (A / B /
  LB / RB on an XInput pad; Cross / Circle / L1 / R1 on a PlayStation pad) and
  can each be rebound the same way.
- The controller goes back to the game when the combination is pressed again
  (which also closes the Teleports menu, and the main window if this session
  opened it), or by itself when no ImGui window has the focus any more — a
  Teleports row was used, the window was closed, the interface was hidden.
- `/dl pad` prints what is bound. `/dl pad flatten all` is a field switch (this
  session only): walk straight through every dlac panel, to judge tabs that
  have not been tuned yet. `/dl pad flatten off` returns to the listed panels.

Typing (set names, search boxes) still needs a keyboard. Right-click actions
and drag-and-drop have no controller equivalent.

## How it works

`feature/padnav.lua`. Its header is the reference for the Ashita events; the
short version:

| Piece | Mechanism |
|---|---|
| Reading the pad | Ashita events `xinput_button` and `dinput_button`, one per press. `e.blocked = true` hides the press from the game. |
| XInput ids | Bit positions, the same on every pad: 0–3 d-pad, 4 Start, 5 Back, 6/7 L3/R3, 8/9 LB/RB, 12–15 A B X Y. `e.state` 1 / 0. |
| DirectInput ids | `DIJOFS` offsets: under 32 an axis, 32 the d-pad as an angle in `e.state` (0 / 9000 / 18000 / 27000, diagonals between, −1 or 65535 centred), 48 and up the buttons. `e.state` 128 / 0. The numbers are the pad maker's. |
| Which interface | A PlayStation pad arrives as DirectInput even with the game's XInput box ticked. Nothing assumes one interface: both handlers feed one token stream (`x12`, `d49`, `dU`). |
| Driving ImGui | `io.ConfigFlags` gets `NavEnableGamepad`, `io.BackendFlags` gets `HasGamepad`, and each press is `io:AddKeyEvent(ImGuiKey_Gamepad*, down)`. ImGui's own navigation does the rest. |
| Sticks | XInput: zeroed in `xinput_state`'s `state_modified` while dlac holds the pad. DirectInput: axes are **not** blocked — the game would keep the last value it saw, and a stick tilted at the moment of the combination would run the character until the pad came back. |
| A press the game saw | Its release always reaches the game, whatever mode dlac is in. The combination's hold button goes down before dlac owns the pad; blocking its release would leave the game holding it. |
| Panels | ImGui's navigation treats each child panel as a box to enter and leave. `lib/imguicompat`'s `BeginChild` wrapper asks `padnav.flatten(id)` and adds `ImGuiChildFlags_NavFlattened` for the listed panels, only while dlac holds the pad. |
| Tabs | `uihost.cycleTab(±1)` steps from the tab that was open on the last pass, through the existing `selectTab`. |
| Quick menu with nothing open | `padnav.drawHost` draws an empty, invisible window and opens `##dlac_teleports` under it. |

The navigation flags are global to ImGui, so while dlac holds the pad other
addons' windows are walkable too.

## Panels tuned so far

Sets tab: the left panel, the slot grid, the slot's list and its rows; the
`+ Add` picker's list and rows, with the first piece under the cursor when the
picker opens. Add a prefix or suffix to `padnav.FLATTEN_PREFIX` /
`FLATTEN_SUFFIX` to tune another panel.

**Keeping the cursor when an item disappears.** ImGui's cursor sits on a
widget id; remove the row under it and the cursor falls back to the top of the
window. The slot list's `x` therefore hands the cursor to the `x` that takes its
place (`ui._padRowFocus`, `SetKeyboardFocusHere` just before the button), and
that button ignores a press for two frames in case a binding ever treats "focus
this" as "press this". Any other list where rows are removed with the pad needs
the same.

## The older Ashita

CatsEyeXI's Ashita ships ImGui 1.80, which has no `AddKeyEvent`; its navigation
reads `io.NavInputs[]`, and whether that is reachable from Lua is untested.
`padnav.supported()` is false there, the Settings page says so, and nothing is
registered against the pad's behaviour.

## Field checks owed

- The combination opens and closes; the hold button does not stay stuck in the
  game after either.
- Teleports menu: walk it, use a row, the pad returns to the game.
- Sets tab: set, slot, `+ Add`, first piece under the cursor, Confirm adds it.
- L1 / R1 switch tabs, and still do when one of them is the hold button.
- Scrolling lists with a flattened panel (ImGui documents the flag as
  unreliable on a scrolling child in older versions).
- The left stick on a DirectInput pad while dlac holds the pad.
