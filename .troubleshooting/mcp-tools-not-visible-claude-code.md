# Issue: Ledger MCP tools not visible in Claude Code (VS Code)

**Status:** Active
**Opened:** 2026-03-20
**Resolved:** _pending_

## Info
- **Symptom:** Ledger MCP tools don't appear in Claude Code's deferred tool list. GHL, GSC, and PageSpeed remote connectors all work. Ledger worked yesterday.
- **Affected area:** MCP configuration, Claude Code VS Code extension, Cloud Run remote MCP

### Background
- Cloud Run service is healthy: `/health` returns 200, OAuth discovery works, tool listing returns 20KB payload
- Cloud Run logs show successful `Claude-User` POST requests at 22:37 UTC (after re-auth) — auth passes, tools returned with 200
- `.mcp.json` in repo was emptied to `{ "mcpServers": {} }` (uncommitted change) — committed version has local stdio config
- Remote connector on claude.ai shows as connected with correct URL: `https://ledger-mcp-twpe4tgoja-uc.a.run.app`
- User re-authenticated after URL change, token exchange succeeded (200)
- User restarted Claude Code extension, still no tools
- The URL changed because a redeploy created a new service instead of updating the existing one

### Secondary goal
- Set up local `.mcp.json` for `/Users/benjaminmackenzie/1584_design/` project so it can also use the Ledger MCP (remote, hitting production Firestore)

## Experiments

### H1: Tools loaded at session start, re-auth happened mid-session
- **Rationale:** Deferred tools are populated when a Claude Code conversation starts. The re-auth happened during this conversation. Other connectors (GHL, GSC, PageSpeed) were already connected before this session started.
- **Experiment:** User starts a new Claude Code conversation and checks if ledger tools appear in deferred tool list.
- **Result:** User tested new conversation — still no Ledger tools in deferred list.
- **Verdict:** Ruled Out

### H2: `.mcp.json` empty prevents local stdio MCP (separate from remote)
- **Rationale:** The committed `.mcp.json` had a local stdio server config. It was emptied. This wouldn't affect the remote connector, but it means no LOCAL ledger MCP either.
- **Experiment:** Restore `.mcp.json` for local dev, verify tools appear when emulators are running.
- **Result:** _pending_
- **Verdict:** _pending_

## Resolution
_Do not fill this section until the fix is verified._
