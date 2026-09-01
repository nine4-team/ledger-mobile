# EVID-CAPABILITY-001 — Capability Evolution Guidance and Service/MCP Catalog

- Timestamp: 2026-08-31
- Class: source characterization method and deterministic control tooling
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Environment: local source inspection only
- Production reads or mutations: none
- Supabase schema or product implementation: none
- Operator: Codex

## Outcome

The architecture and conversion guidance now require capability-level synthesis
before target mapping. Current source and production evidence answer what exists;
specs and decisions answer intended product behavior; architecture establishes
offline, security, failure and operational quality. A reviewed dossier must
classify preserved, corrected, improved, redesigned, retired and open behavior
without treating Firestore mechanics or stale specs as target requirements.

The generated service/MCP catalog assigns all 88 in-scope files:

- 41 Swift service/Auth files;
- 47 MCP source modules; and
- 11 initial user or operational capability groups.

Its source digest is
`584157a03aaf0aa3c5e93953bf4c6c5642d213fca0f85a2e95fa2c3b0adb176f`.
The generated JSON SHA-256 is
`e1e5b114b8bf31cacee35e053537289658086790220f503af47ec7090f772b05`;
the generated Markdown SHA-256 is
`56a6df77fe9fffe51d19328b899b3ffa9ef981d433a2bc7ad6e3fc1360bb11df`.

## Reviewed Artifacts

- `capability-evolution-method.md`
- `current-capability-register.md`
- `capability-surfaces.generated.json`
- `capability-surfaces.generated.md`
- `scripts/extract-current-capability-surfaces.mjs`
- architecture README, principles, backend-port rules and definition of done
- implementation tracker G0.5 capability-synthesis gate

## Commands

```bash
node --check scripts/extract-current-capability-surfaces.mjs
npm run conversion:capabilities:generate
npm run conversion:capabilities:check
```

All passed. The generator fails if an in-scope file cannot be assigned, and
check mode fails if source changes make either artifact stale.

## Limitations

This is the complete service/Auth/MCP source assignment, not a complete
capability dossier. UI callers, models, tests, Functions, data shapes and
operational/migration tools remain separate manifest surfaces to link during
review. Lexical signals do not prove runtime use or desired target behavior.
Production-shape conclusions remain blocked on the read-only Firebase profile.
