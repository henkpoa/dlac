# 0033 — A jump takes the tab, it does not ask for it

Accepted 2026-07-30. Changes `ui/uihost.lua`'s `selectTab` contract and adds `host.tabBarId`,
which `gearui` must now call instead of hardcoding its tab bar's ID. Nothing else about the
host registry, the tab roster or the panels changes.

## Context

dlac has a growing family of **shortcuts**: a control on one surface that puts you on another.
The Teleports quick menu's rows, the hobby bars' "open my panel" buttons, the E-Box Restock
nudge's right-click, `/dl restock`. Every one of them goes through the same two-step seam —
`gearui.openAutomation(key)`: set the destination panel's own view state, ask the host to
select the tab, show the window.

Step two never worked. Henrik, field 2026-07-30:

> *"I click e-box restock in teleport menu, in the gear helper tab it directs me to the correct
> menu, but when I open the GUI, I am still on the job helpers tab. So I think there's a step
> missing here (this goes for many other things as well)."*

`selectTab` was a **one-shot**: it recorded a label, and the next `renderTabs` pass handed
`ImGuiTabItemFlags_SetSelected` to that label's `BeginTabItem` and forgot. Two defects hid
inside each other:

* **ImGui applies a forced selection at the NEXT frame's `TabBarLayout`.** On the pass that
  carries the flag, `BeginTabItem` still returns false, because the tab is still closed. So the
  one-shot never had anything to observe — *honoured* and *ignored* produced identical
  behaviour on the only pass it looked at. That is hard rule 12 (a total failure and a typo
  must not look identical), and it is why this shipped broken and stayed broken for weeks
  across every shortcut in the addon.
* **`o == true` discarded a truthy non-boolean return.** When the forced tab *is* the open one,
  that skipped the content *and* `EndTabItem` — an unbalanced tab item, tearing the very bar it
  was trying to steer.

Then the deeper problem, found by fixing the first one and letting it report: **this build's
imgui binding does not carry the flag through to ImGui at all.** With the request held and
both plausible argument shapes tried, the give-up line printed. The C++ side was never in
doubt — the SDK header that ships with Ashita (`plugins\sdk\imgui.h`) declares
`BeginTabItem(const char* label, bool* p_open = nullptr, ImGuiTabItemFlags flags = 0)` and
`ImGuiTabItemFlags_SetSelected = 1 << 1`. What is not visible anywhere on disk is how Ashita's
hand-written Lua binding maps a `bool*`, and no sibling addon settles it either: they all call
the plain `(label, nil)` form, and the one that does pass flags (`ventures`) would look
identical to a player whether its flag lands or is dropped.

## Decision

**A jump is held until it takes, and if the binding will not do it, the host takes it.**

1. **Held, not one-shot.** `selectTab(label)` records a request that rides *every* `renderTabs`
   pass until that tab is observed OPEN, then clears at once — holding it one pass longer would
   refuse the player's next click. The budget counts **passes, not frames**, so a jump asked for
   while the main window is shut waits for it to open instead of expiring unseen.
   `host.pendingTab()` reports what it is trying to reach.
2. **Three rungs, cheapest first.**
   1. `(label, {true}, flags)` — p_open as a **table**, the shape `imgui.Begin` demonstrably
      honours in this addon (gearui's own window passes `isOpen` as a table and its X works).
   2. `(label, nil, flags)` — the header's own signature. Disproven on this install; kept
      because a correct binding lands the jump with no artifact at all.
   3. **The rebuild**, which needs no cooperation from the binding: a tab bar ImGui has never
      seen has no selection and adopts the **first tab submitted to it**. The bar's ID gets a
      new generation and the wanted tab is submitted first until it opens.
3. **`gearui` asks the host for the bar ID.** `host.tabBarId('##ffxilac_tabs')` — the caller may
   not cache it and may not hardcode it. The ID *is* the mechanism for rung 3.
4. **A jump that never lands says so**, once, naming the tab, after ~30 passes.

## Consequences

* **Shortcuts work.** Field-confirmed 2026-07-30 on the Teleports quick menu's E-Box Restock
  row; the same seam carries every other cross-link, so they all move with it.
* **The rebuild has a visible price**, and it is the right trade: for one frame the tabs sit in
  a different order (the target leftmost) and the body is empty while ImGui has nothing
  selected. Both revert as soon as the selection lands — about five frames after the click.
  Each rebuild also abandons one `ImGuiTabBar` inside ImGui; jumps are a handful per session.
* **The rebuild is armed at the END of a pass, never the start.** Deciding it up front bumps the
  generation on the very pass a working flag lands, and the next pass would hand gearui a bar
  ImGui has never seen — throwing away the selection it just won. Two of the four stub bindings
  in the tests exist to hold that line.
* **A build whose binding works never pays anything.** Rungs 1-2 land it in two passes with no
  reorder and no blank frame, and the generation is never bumped.
* **One assumption is not provable from anything on disk:** *a bar with nothing selected adopts
  the tab at index 0*. Only the interface header ships with Ashita, not `imgui_widgets.cpp`. It
  is field-confirmed here, and if it is ever false the symptom is specific and loud — an empty
  tab body until you click, plus the chat line.

## Records

`ui/uihost.lua` (the whole story is in its comments), `docs/reference/shortcuts-and-jumps.md`
(how to add one), `docs/architecture.md` (the uihost entry), `docs/history.md` ("the tab that
never moved"), smoke_ui `TAB1`–`TAB25` — four stub bindings (table-p_open, nil-p_open,
flag-blind, flag-blind-and-adopt-blind) against a stub that models ImGui's real tab-bar
semantics. Every rung was verified load-bearing by disabling it and watching the right checks
go red.
