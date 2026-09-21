# Gear Vault sync efficiency investigation — 2026-09-20

Initial investigation followed by implementation of the first three recommendations
on September 20. Client changes are in this checkout; the server change is in
`C:/repos/axi-vault-atomic` on `codex/gear-vault-atomic-add-pin`. Neither the addon
nor a live server was reloaded. No live item operations or deployment occurred.
The remaining recommendations below are future work, especially authoritative
deltas and narrower invalidation.

## Implemented and verified

Test build version: `2026.09.20a`. Run `/addon reload dlac`, then `/dl check` to
verify the loaded addon version (not the engine file version). `/dl vault` shows
`pinned instance adds: one request` when HELLO advertises atomic support, or
`pinned adds: ADD then PIN` for the fallback. `server support: unchecked` means
negotiation has not completed. Client batching/coalescing works with either server.
The first implementation commit retained the old display version; this follow-up
corrects that omission and makes the negotiated behavior visible.

- `instanceAt` shares automatic lookup batches up to the negotiated maximum.
  Batches freeze when snapshotted, even if transport has not accepted the send.
  Explicit `requestLookup` callers retain their callback/result boundaries.
- Layout requests share an equivalent in-flight read. `invalidateLayout` tracks
  a separate epoch, rejects an invalidated page chain and schedules a follow-up.
  Inventory bursts settle for 250 ms, bounded to a one-second deferral. This
  bounds the start of a read, not completion during continuous mutation.
  Current-job requests stay current through queued and in-flight job changes.
- Lost-item results reuse the known revision/inventory epoch. An invalidated
  lost-list page chain is rejected and requested again.
- HELLO capability bit 1 (value 2) advertises atomic instance ADD; bit 0 still
  advertises instance IDs. `LAYOUT_SET2`, verb ADD, selector 0 stores hint and
  pin in the existing native insert and applies the active layout once.
  `requestLayoutSet` owns the ADD-to-PIN fallback for older servers and identity
  selection; the UI reports logical completion after both fallback operations.
  Partial ADD results survive a successful fallback PIN.
- Existing transport pacing, identity rejection, same-sequence retry, automatic
  cleanup policy and six-second post-edit full mirror refresh remain in place.

The original 16-slot probe now reports **one request, 0.200 simulated seconds,
two status transitions** through the normal API, equal to its explicit batch
case. `--budget` now passes and runs in CI with `tests/gearvault_sync.lua`.
The historical measurements below remain the before-change evidence.

Client verification: sync/probe, instances, counts, catalog, repair, native custom
equipment, icons, HELM and probe suites pass; UI smoke passes 1,603 checks. The
broad suite passes all 7,499 checks in the final working tree. Initially FGT23
failed because the local macrobook setting was ahead of this checkout's test.
Upstream PR #176 already contained that setting and its updated test; integrating
main resolved the mismatch. The local feature contents were preserved and verified
unchanged through that merge.

Server verification: 9/9 native `instance_ops` cases pass. Testing uses an isolated
runtime at `C:/repos/axi-vault-test-runtime`, source commit `37297e17fa`, the matching
available xi_test executable from `ascensionxi-02`, generated enums, mesh junctions
and the isolated `xidb_merge` configuration. Only the changed service/test Lua files
are overlaid from the delivery worktree. Earlier scratch attempts lacked matching
generated runtime assets and are not evidence for the feature. See the server
handoff `documentation/custom/gear-vault-atomic-add-pin.md` for exact reproduction.

Code review: Standards and Spec reviews completed. The queued-job regression and
redundant tombstone reads found during review were fixed and regression-tested;
server documentation was added. No remaining code findings. Client-visible timing
under actual packet delivery still needs playtesting.

## Evidence and limits

Client: this checkout, branch `codex/gear-vault-instances`. Server implementation
read from `C:/repos/ascensionxi-03`, HEAD `0b27d0d237`; that checkout implements the
instance protocol used by this client. The older `C:/repos/ascensionxi` checkout
does not. The running server build/settings were not verified. Existing user
changes in `servers/ascensionxi/features.lua` were left untouched.

Local evidence: `C:/AscensionXI/Ashita/config/addons/dlac/Mindlor_4/debug/`:

- `gear-vault-edits.log`: manual ADD followed by PIN for item 13522, instance 37,
  job 2, sequences 177/178 at 10:14:13–10:14:14 on September 20. Both succeeded.
- `gear-vault-wire.log`, lines 1104–1129: from that ADD enqueue to the final
  LOST_LIST reply, 10.781 seconds and 13 request/reply pairs:

| Operation | Requests |
| --- | ---: |
| LAYOUT_SET2 (ADD and PIN) | 2 |
| LAYOUT_LIST2 | 2 |
| HELLO | 1 |
| LIST2 | 2 |
| INSTANCE_LOOKUP | 5 |
| LOST_LIST | 1 |

Median enqueue-to-reply latency was 0.163 seconds; these latencies summed to
2.369 seconds. Reply-to-next-enqueue gaps summed to 8.413 seconds, including gaps
of 3.278 and 1.403 seconds and ten gaps of roughly 0.35–0.38 seconds. This is an
observed sequence following one addition, not a CPU profile or proof of the trigger
for every read. Enqueue is injection into Ashita, not actual network transmission.
Wire logs do not record lookup payloads or inventory packets, so they cannot prove
which slots were looked up or precisely why the second layout read was requested.

More recent `Mindlor_2` logs also show successive identity reads, e.g. sequences
246–253 at 21:18:15–21:18:19, and layout/lost-list cycles without accompanying
layout edits. These support the general read-churn observation, not attribution
to a particular player action.

## Current paths

1. The Gear Vault UI queues ADD. When the manual entry is pinned it queues a
   separate PIN after ADD succeeds (`vaultui.lua:layoutEdit`). Server ADD ignores
   the request's pin/hint fields for instance selection; `layoutAddInstance`
   supplies `0, false` to the insertion. Both ADD and PIN call `gv.apply` for the
   active job. That routine prunes, reloads layout/registry, scans wardrobes and
   reconciles their contents. PIN can therefore repeat a full application.
2. A successful active-job ADD marks both views stale and schedules a full vault
   refresh after `SETTLE_JOB = 6`. The UI requests the layout immediately after
   its edit chain. Inventory packets 0x01D–0x020 clear the entire identity cache
   and mark the layout stale, regardless of container or whether the relevant
   assignment changed (`gearvault/init.lua` packet hook).
3. `vaultui` re-asks stale layouts on a three-second clock. `reconcile.tick`
   also asks when the current layout is stale, on its eight-second cadence.
   `requestLayout` coalesces a queued desire but does not recognize an equivalent
   request already in flight. A later desire can survive completion and cause
   another full read. Multi-page reads remain revision-checked.
4. `instanceAt` schedules one singleton lookup for each cache miss. Multiple
   consumers (worn-item protection, usage tracking and binding candidates) use it.
   Slot keys deduplicate identical pending demands, but distinct slots do not
   combine. The wire already supports up to 41 slots per lookup.
5. Lookup work has priority over the scheduled vault refresh. Every revision
   change also clears all identities. Stale in-flight lookups retry, up to three
   attempts. Consequently a refresh and inventory movement can trigger another
   wave of reads or delay the background mirror refresh.
6. Full vault refresh is HELLO plus LIST2 pages (13 rows per page). Layout pages
   hold 12 rows. Each completed full mirror or layout read requests LOST_LIST;
   its boolean queued desire may coalesce, but it is not gated on a lost-items
   revision. Even an empty lost list costs a request.
7. `vc.state()` returns `syncing` for *any* pending operation, including one-slot
   identity reads and writes. Between them it can return `fresh` or `stale`.
   This explains the flash pattern without requiring repeated full vault syncs.
   Reconciliation also uses this state to gate work, so status refactoring must
   separate display activity from actual mutation/read prerequisites.

The shared transport deliberately permits one outstanding request across vault
and HELM, then waits 350 ms after the reply. The client also checks a 350 ms send
interval; these overlap, rather than automatically adding to 700 ms. Historical
buffered-packet drops motivated the shared gate. Server source currently configures
50 ms in `settings/network.lua`; older DLAC notes mention 100 ms. Neither source
proves the live server setting. Do not reduce the delay based on stale prose alone.

## Reproducible comparison

From the DLAC root:

```powershell
lua tests/gearvault_sync_probe.lua
lua tests/gearvault_sync_probe.lua --budget
lua tests/gearvault_instances.lua
```

The probe uses the real vault client and shared transport with an injected clock,
60 present beats per second, 160 ms reply latency, stable revision and 16 demanded
slots after invalidation. It performs no network or game operations. The batch
case uses the already exposed `requestLookup` API; it does not implement an
automatic batching fix.

Observed output:

```text
normal instanceAt: requests=16 elapsed=8.083s status_transitions=32
batch API: requests=1 elapsed=0.200s status_transitions=2
```

At investigation time `--budget` deliberately failed because 16 simultaneously
demanded slots should fit one lookup request. It now passes and runs in CI.
Both paths verify all 16 returned mappings.
The existing instance protocol suite passes, including movement races, legacy
fallback, deposit verification, shared pacing and retry serialization. Simulated
times are for this isolated lookup workload, not a promised whole-addition speedup.

## Recommended implementation order

1. **Batch client lookups, using today's protocol.** Accumulate and deduplicate
   demanded slots until the pump can send, chunk by the negotiated maximum,
   snapshot the whole batch after inventory application, and fan out results to
   waiting consumers. Keep revision/epoch rejection, bounded retry, per-slot
   validation and write-time identity checks. The measured workload falls from
   16 requests to one (93.75% fewer).
2. **Give layout refresh one owner.** Coalesce UI/reconciler/edit requests by job
   and requested generation, recognizing an in-flight read. Dirty events during
   that read must request one follow-up if newer than its snapshot; do not simply
   discard all repeat requests. Debounce one inventory burst into one refresh,
   with a maximum wait so continuous traffic cannot starve completion. Fetch
   tombstones only when needed or when their own version changes.
3. **Make ADD + pin atomic on the server.** Honor pin/hint on insertion and apply
   the active layout once. Negotiate support so old servers keep the two-request
   fallback. Avoid a full apply for a pure pin change; a changed wardrobe hint
   may still require placement work. Multi-add workflows could similarly batch
   edits and apply once, retaining per-entry results and replay safety.
4. **Return authoritative deltas and completion.** A successful mutation reply
   should identify changed layout rows, vault rows and slot/instance locations,
   plus base/result revisions and whether movement is complete. Update those
   client views directly. Skip HELLO when capabilities are already established;
   keep it for initial negotiation/reconnection and supported probes. Replace
   the fixed six-second ordinary-edit delay with completion plus confirmation
   that client inventory packets have applied. Partial/unknown results, missed
   revisions, reconnects and page inconsistency retain a full-refresh fallback.
   Affected instance IDs alone, which today's ACK supplies, are insufficient.
5. **Narrow invalidation with trustworthy versions.** Track slot/container
   changes instead of clearing every identity for every packet. Separate layout,
   physical-location, vault-content and lost-item revisions or carry explicit
   changed scopes. A global revision change cannot safely be ignored: the current
   `entry.revision == M.revision` contract requires coordinated handling. Website,
   chat, job-change and non-DLAC mutations must participate in revision changes.
6. **Reduce server database and scan work.** `opList2` fetches the complete vault
   for each page then filters in Lua. `opLayoutList2` prunes, reads the registry
   and loads the complete layout for each page. `opInstanceLookup` builds the
   registry and calls `GearVaultProbe` per slot; the probe computes unrelated
   vault identity counts and performs instance queries. Add cursor/limit database
   reads, a lean mapping-only lookup, and reuse one consistent request/apply
   snapshot. Preserve consistent revision boundaries and external-write visibility.
   These are source-confirmed work multipliers; their CPU/SQL cost is unmeasured.
7. **Tune pacing and presentation after eliminating requests.** Negotiate a
   server-supported cooldown or handle explicit BUSY/retry-after, retain shared
   producer serialization/replay protection, and validate real server arrival
   logs. Show one stable user operation through completion; routine background
   identity checks need not paint the entire vault as syncing. UI smoothing alone
   saves no network work.

## Other local sync work

The owned-gear path is separate and makes local memory/file reads rather than
vault round trips. `syncflags` schedules an add-only scan five seconds after its
last inventory signal; a mirror commit arms the same path again. Job-change and
inventory deadlines are independent and can invoke `doSync` twice in one tick.
`gearimport.sync` first scans to detect new records, then `stage` scans again when
new records exist. `doSync` always calls the automation rescan, which rebuilds UI
indexes and regenerates the manifest even when no record was added. Owned counts
also invalidate every 240 present frames, independent of actual changes.

Reuse one scan result through import/staging, merge due sync reasons, and refresh
downstream consumers only for changes they depend on. Ownership, availability,
augment changes and job changes have different dependencies: `added == 0` alone
does not prove nothing relevant changed. Prefer a common monotonic wall clock to
mixed frame counters and `os.clock`. Preserve ADR 0005's all-container ownership
and narrower equip availability, and ADR 0013's shared oracle boundary.

## Next implementation and acceptance

The first stage is implemented in `vaultclient.lua` and its UI/glue consumers;
`tests/gearvault_sync.lua` and `tests/gearvault_instances.lua` cover batching,
movement, pagination, job transitions and protocol compatibility. Start the next
stage by designing authoritative mutation deltas and completion, before replacing
the six-second refresh delay or weakening global identity invalidation.

For live acceptance, reload only once changes are intentionally under playtest,
add one pinned vault item to the active layout in town, then compare matching
edit and wire timestamps. Record operation counts, repeat reads, retries,
time-to-final-slot visibility, UI busy duration and server rate-limit drops.
Repeat with multiple additions, a normal bag move, combat flag/count updates,
job changes, zoning and edits through another surface. Profile SQL separately;
client enqueue/reply time is not server execution time.

Current state: the batching, coalescing and atomic-instance-ADD stage is implemented
as described at the top. No running addon/server was reloaded. Reload DLAC to use
the client improvements; atomic ADD additionally needs the server change deployed
and a new HELLO negotiation (addon reload supplies it). Either side can be released
first: old clients keep sending their extra PIN and new clients retain fallback
against old servers. Revert the matching commits and reload to roll back. Keep the
packet cooldown until live evidence supports changing it. Full deltas and removal
of the six-second edit delay remain the next stage.
