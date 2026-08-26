# 0036 — The imgui binding is a seam, not an assumption

Accepted 2026-08-26. Adds `lib/imguicompat.lua`, installed once from `dlac.lua` before the
first frame. No call site changes; nothing about the ImGui idioms the tree uses changes.

## Context

dlac was written against the ImGui generation CatsEyeXI's Ashita build binds. Vanaheim's
Ashita ships ImGui 1.90+, where three calls the tree makes everywhere changed shape at the
Lua-visible level:

* `BeginChild(id, size, border, windowFlags)` — the border **bool** became
  `ImGuiChildFlags` (an int; `true`'s meaning is now `ImGuiChildFlags_Borders`). ~85 dlac
  call sites pass a bool; sol rejects every one with *"no matching function call takes
  this number of arguments and the specified types"*, which is exactly the red banner
  Henrik hit on every tab (field, 2026-08-26, `ui/equippedui.lua:454` first).
* `ImageButton(...)` — grew a leading `str_id`, lost `framePadding` (style-driven now).
* `Image(...)` — lost its tint overload; `ImageWithBg(tex, size, uv0, uv1, bg, tint)`
  carries tint on the new binding.

An audit of every `imgui.*` name the tree calls against the new build's binding surface
(`addons/libs/annotations/SDK/IGuiManager.lua`) found **only** these three reshapes plus
one removal (`SetItemAllowOverlap`) that both call sites already feature-detect. The
widget vocabulary (Checkbox/Selectable/InputText/Combo/draw lists/table buffers) is
unchanged.

Rewriting every call site to the new shapes was rejected: it breaks the build the addon
was field-tested on, and it re-litigates the same choice at every future call site.

## Decision

**One shim, keyed on the BINDING, never the server.** `imguicompat.install()`:

1. Detects the generation by whether `ImGuiChildFlags_Borders` exists — the new build's
   `libs/imgui.lua` defines the enum globals, the old one predates the enum. No server
   pack involvement: if CEXI's Ashita updates tomorrow, the shim follows the binding it
   actually finds.
2. On the **old** binding it wraps **nothing** — zero overhead, zero risk to the
   field-tested install.
3. On the new one it rawsets three wrappers onto the required `imgui` table (which
   shadows its `__index = GetGuiManager()` metatable for every call site in this Lua
   state, dlac's own, the vendored modules' and the pack modules' alike), translating
   the OLD shapes the tree speaks: border bool → child flags; texture-first
   `ImageButton` → derived `str_id` (the texture was the old binding's widget identity,
   so identity semantics are preserved) with `framePadding` honoured via a
   `PushStyleVar` bracket; 5-arg `Image` → `ImageWithBg`. A call already speaking the
   new shape passes through.

The tree keeps writing the OLD shapes — that is the contract: the shim owns the
difference, call sites own nothing.

## Consequences

* Both builds render from one tree; the compat cost is one table lookup plus one pcall
  on the new binding only.
* A future binding change lands in ONE file, and the audit that found these three is
  repeatable (diff used `imgui.*` names against the annotations stub).
* The pure mapping halves are exported (`_childFlags`, `_imageButtonArgs`) and pinned
  headless (IMC0–IMC15), including that `install()` leaves an old binding untouched.
* One deliberate loss: on a new binding whose `ImGuiStyleVar_FramePadding` global is
  missing, an old call's framePadding is dropped silently — a border pixel is not worth
  a torn frame.

## Records

`lib/imguicompat.lua` (the whole story in its header), `docs/history.md` (the Vanaheim
field round), run_tests `IMC*`.
