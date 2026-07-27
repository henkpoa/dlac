# The Wishlist entry is an entity; its links are intentions, its ownership is a fact

Status: accepted (2026-07-27)

A **Wishlist entry** records an item the player means to acquire. It is keyed by item **Id**
and exists on its own — created from an All Equipment right-click, or as a side effect of
adding an unowned piece to a set, but never *owned* by either. Two properties shape
everything downstream, and both were live choices:

**Links are stored intentions; ownership is read.** A **Wishlist link** ("Dalmatica is for
WHM/Idle") is written on the entry and dlac never revokes it — you may link a piece to a
set you have not put it in, which is the point: the set stays clean while the intention is
recorded. Whether the piece is *actually* in that set is read from the set file each time
the window opens and shown beside the link, so the two halves can disagree without either
lying. Ownership follows the same rule in the other direction: it is never stored, only
read from the bags (by Id, via `ownedcache`), so selling a piece silently returns it to
wanted. The alternative — deriving links by scanning sets, or stamping `owned = true` —
was rejected because both create a reconcile step, and a wishlist that needs reconciling
is a wishlist that goes stale.

**Set files do not change.** An unowned name in a set already does the right thing:
`utils.BuildDynamicSets` cannot resolve it against `gear.lua`, skips it, and the slot's
real best-by-level pick wins — so a wishlisted piece can never shadow gear you own, and it
starts working by itself the moment you acquire it. The only problem was the warning
`warnMissingGear` prints for it. We considered marking the entry in the file
(`{ gear = 'Dalmatica', wish = true }`), which is self-describing but changes a format that
is shared, hand-edited and round-tripped through Commit. Instead the engine reads
`wishlist.lua` — a small per-character file beside `pinstate.lua`, a road already paved —
and stays silent for names on it. A missing name that is *not* wishlisted is still a typo
and still warns.

## Consequences

- Applying a wishlisted piece to a set is an explicit player action, never automatic —
  which is why the Wishlist window puts an **Apply** button on exactly the links whose fact
  does not yet match. Set totals therefore count only gear you own; an unowned row is inert.
- The engine gains a dependency on `wishlist.lua`. It is read-only, content-keyed like the
  other statefiles, and absent-file means "nothing wishlisted" — the old behaviour exactly.
- Keying by Id (not name) is load-bearing: the API drops possessive apostrophes, so the
  Catalog says `Arhats Gi` where the client says `Arhat's Gi`. Ownership questions are
  answered by Id; the separate name-resolution fix is recorded in the same change.
