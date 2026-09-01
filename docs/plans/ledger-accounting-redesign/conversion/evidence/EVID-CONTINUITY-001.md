# EVID-CONTINUITY-001 — Long-Running Goal and Compaction Continuity Guard

Date: 2026-09-01

Result: partial pass. The deterministic hook contract and conversion integrity
check pass locally. Codex must still present the new repository-local hook for a
one-time human trust review before lifecycle execution is proven in the app.

## Scope

- conversion control surface `FILE-208B7E9D7F47`;
- every future target implementation slice governed by the conversion control
  plane;
- `AGENTS.md` start/resume/compaction behavior;
- the long-running operating model in the conversion README;
- `.codex/hooks.json` plus
  `.codex/hooks/ledger-conversion-continuity.mjs`; and
- `.github/workflows/supabase-conversion-control.yml`.

No source or target data, hosted environment, credential, production system,
migration, release, or cutover was accessed or changed.

## Contract Proven

For a `SessionStart` event whose source is `compact`, the repository-local hook:

1. resolves the repository root from the supplied working directory;
2. reads the persisted execution-state version, checkpoint, and `Next Action`;
3. runs the deterministic conversion integrity check without mutating state;
4. returns bounded `SessionStart.additionalContext` for the immediate compacted
   continuation; and
5. tells the continuing agent to treat conversation summaries as advisory,
   inspect the diff and active dossier, and stop status advancement at failed or
   unauthorized gates.

The hook deliberately does not rewrite an execution plan, infer completion,
grant permission, auto-commit, change status, or block automatic compaction.
A mid-checkpoint failure is recovery information that the agent must resolve
before status advancement or handoff.

The pull-request workflow runs the conversion, capability, query, residual and
M0 checks under Node.js 22 and rejects generated-artifact rewrites. It becomes a
merge-enforcement boundary only after the repository administrator marks its
`Conversion state and traceability` job as a required branch-protection check.

## Commands and Results

Executed from the dirty shared `dev` worktree at source commit
`d83c64724fe4e92be27c62f425979bd30fcfc9bb`:

```bash
node -e 'JSON.parse(require("fs").readFileSync(".codex/hooks.json", "utf8")); console.log("hooks json: pass")'
printf '%s' '{"hook_event_name":"SessionStart","source":"compact","cwd":"/Users/benjaminmackenzie/Dev/ledger_mobile"}' | node .codex/hooks/ledger-conversion-continuity.mjs
printf '%s' '{"hook_event_name":"SessionStart","source":"compact","cwd":"/Users/benjaminmackenzie/Dev/ledger_mobile"}' | node .codex/hooks/ledger-conversion-continuity.mjs | node -e 'let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{const v=JSON.parse(s); const c=v.hookSpecificOutput?.additionalContext||""; if(!c.includes("Persisted state version: 25")||!c.includes("Persisted checkpoint: LONG-RUNNING-GOAL-CONTINUITY-GUARD")||!c.includes("Conversion integrity check at compaction: PASS")) process.exit(1); console.log("compact continuity contract: pass")})'
npm run conversion:check
npm run conversion:report
npm run conversion:capabilities:check
npm run conversion:queries:check
npm run conversion:residuals:check
npm run conversion:gate:m0
git diff --check
```

Observed results:

- hook JSON parsed successfully;
- the synthetic compact event returned valid JSON with persisted state version
  25, checkpoint `LONG-RUNNING-GOAL-CONTINUITY-GUARD`, the persisted
  `Next Action`, and a passing check summary;
- conversion check passed with 686 recorded surfaces, 674 currently discovered,
  zero errors, and zero warnings;
- generated conversion, capability, query and residual artifacts were current;
  M0 passed and later gates remain honestly gated; and
- `git diff --check` passed.

## Remaining Proof

Repository-local hooks are intentionally not trusted silently. Review and trust
this hook when Codex presents it, then confirm one real manual or automatic
compaction reports “Restoring Ledger conversion state” and supplies the same
bounded recovery context. Until then, this evidence remains `partial` rather
than claiming live lifecycle verification. The first pull request containing
the workflow must also pass, and branch protection must require its named job,
before merge enforcement is claimed.
