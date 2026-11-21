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
- **Confirm**, **Back**, **Previous tab**, **Next tab** and **Next window** have
  defaults (A / B / LB / RB / Y on an XInput pad; Cross / Circle / L1 / R1 /
  Triangle on a PlayStation pad) and can each be rebound the same way.
- **Next window** (`2026.11.21a`) moves the cursor to the next open dlac window
  — the hobby bar, the lockstyle window, the main window — and wraps. From the
  Teleports menu it closes the menu and lands on the first one.
- The controller goes back to the game when the combination is pressed again,
  or by itself when no **dlac** window has the focus any more — a Teleports row
  was used, the menu was cancelled with Back, the window was closed, the
  interface was hidden.
- The combination also closes what the controller session opened: the
  Teleports menu, and every dlac window that came up after the combination was
  pressed (the lockstyle window opened from the menu, the main window). Windows
  that were up before stay. The hobby bar follows the same rule since `21c`
  (it was exempt in `21a`; `padnav.KEEP_OPEN` is the exemption list, now
  empty).
- **Previous tab / Next tab** act on the focused window: on the hobby bar they
  step through the hobbies that are switched on (`hobbybar.cycle`, `21c`),
  anywhere else through the main window's tabs. Stepping shows a hobby's
  controls; it does not switch the hobby on.
- While dlac has the controller a label at the top of the screen says so:
  "Controller: dlac" and the combination that hands it back.
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
| Which window has the focus | `lib/imguicompat` wraps `imgui.Begin` and calls `padnav.windowHook` before and after every dlac window. After the Begin, `IsWindowFocused(ChildWindows)` says whether the focus is in that window or a popup under it. |

The navigation flags are global to ImGui, so while dlac holds the pad other
addons' windows are walkable too.

## When the controller goes back (`2026.11.21a`)

The first release held the pad for as long as ImGui's `io.NavActive` was true.
That is true for ANY focused window, another addon's included, so after a
Teleports row was used the focus fell to the next window on screen and the pad
stayed with dlac (reported by Vellhart and Dyce, 2026-11-17 to 11-21). Now:

- Each addon has its own Lua state and its own `imgui` table, so the Begin
  wrapper sees dlac's windows and nobody else's. The pad is held only on a
  frame where one of them reported the focus; `IDLE_S` (0.4 s) without one
  releases it.
- A window's key is its ImGui id (after `###`, else after `##`). A window with
  no title (`##dlac_tray`, the gauges, the pad host) is a HUD piece: the focus
  resting on it holds nothing, a popup under it does. That is how the
  Teleports menu under the invisible host counts and the host does not.
- When the Teleports menu closes, the windows that were on screen the frame
  before its last one are noted (`quickKnown`). The frame before, because a
  row opens its window in the same frame it closes the menu and that window
  is drawn after the menu (`ui/gearui` draws the pad host early). `21a` took
  the list a frame late, so the window the player had just opened was on it
  and the pad left: the main window, the hobby bar and lockstyle all opened
  without the pad (Henrik's field round, 2026-11-21; fixed in `21b`). ImGui hands the focus back to whichever of them had it
  before; that is not a choice, so it does not hold the pad. A window the row
  OPENED (not in the list) does, and from then on the older ones count again.
- On release `SetNavCursorVisible(false)` is tried, so the highlight does not
  stay on a window the pad no longer drives.
- If the binding cannot answer `IsWindowFocused`, the old `NavActive` rule is
  used.
- With the game's interface hidden (Scroll Lock, `feature/gamehud`) the pad
  is released at once (`21b`).
- `/dl pad state` prints who has the pad, the focused dlac window, the
  windows Next window can reach, and the last button with the job it did.

The closing combination shuts a session-opened window by setting its open
flag to false at its next Begin, which every dlac window already treats as a
click on its own x. The request lives three frames.

## Panels tuned so far

Sets tab: the left panel, the slot grid, the slot's list and its rows; the
`+ Add` picker's list and rows, with the first piece under the cursor when the
picker opens. Add a prefix or suffix to `padnav.FLATTEN_PREFIX` /
`FLATTEN_SUFFIX` to tune another panel.

**Keeping the cursor when an item disappears.** ImGui's cursor sits on a
widget id; remove the row under it and the cursor falls back to the top of the
window. `padnav.focusHere()`, called just before a widget, moves the cursor
there (`SetKeyboardFocusHere`), and the widget gates its own click on
`padnav.pressAllowed()`, which is false for two frames afterwards in case a
binding ever treats "focus this" as "press this". Used so far, all on the Sets
tab: a removed row's `x` hands the cursor to the `x` that takes its place; a
piece added in the `+ Add` picker hands it to the row that takes its place;
picking a slot puts it on `+ Add`. Any other list whose rows come and go under
the pad needs the same.

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

Added with `2026.11.21a`, none checked in game:

- Use a Teleports row, and cancel the menu with Back: the pad is the game's
  again within half a second, with the hobby bar open and with it closed.
- The label shows while dlac has the pad and goes when it does not.
- Next window from the Teleports menu reaches the hobby bar; a hobby can be
  switched on and off there.
- Open the lockstyle window from the pad, then the combination: it closes.
- Whether `IsWindowFocused` and `SetNavCursorVisible` exist on this binding
  (the first has a fallback, the second is cosmetic).
- The blue frame Dyce saw around the screen: not reproduced and not
  explained. The likely cause is ImGui's highlight on a screen-sized window
  of another addon that took the focus; if so it is gone with this change.
