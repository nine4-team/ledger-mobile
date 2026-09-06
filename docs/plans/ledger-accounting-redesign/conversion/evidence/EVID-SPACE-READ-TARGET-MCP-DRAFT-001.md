# EVID-SPACE-READ-TARGET-MCP-DRAFT-001 — Deferred Target MCP Space Read Boundary

- Timestamp: 2026-09-06
- Class: DRAFT dependency record; not READY and not executable
- Reviewed base: `2297e8dbe7f7f0febb7e33b4da0be591d4c82ade`
- Target branch: `codex/supabase-powersync-implementation`
- Slice: `space-read-target-mcp`

## Outcome

The public source `list_spaces` and `get_space` tools include observable Item
count, Item-row and image behavior that the current target Space read model
cannot truthfully replace. O-007/O-015 still govern authoritative Item and
provenance shape; O-023 governs attachment lifecycle and visibility.

The two target MCP leaves therefore remain comment-only and unregistered. They
document a possible explicitly partial `space_core_only_v1` diagnostic contract,
but do not claim public tool parity, production registration or implementation
readiness. A future slice must either supply authoritative Item/media
dependencies or obtain explicit canonical product authority for a narrower new
diagnostic. Zero Item counts and empty Item/image arrays are not accepted as
substitutes for unavailable data.
