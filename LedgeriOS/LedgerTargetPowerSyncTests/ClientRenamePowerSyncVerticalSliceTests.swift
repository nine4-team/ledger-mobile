// DRAFT scaffold only — the executable test suite is intentionally absent.
//
// Planned coverage is frozen in the Client-rename provider dossier: encrypted
// atomic acceptance/restart/replay; full UInt64 canonical bytes; local signed-
// storage boundaries; pending-create then rename FIFO; multiple offline rename
// chaining and stale-local refusal; immediate Client and Project optimism;
// rejection-specific cleanup; applied-waits-for-readback; stale readback cannot
// clear optimism; authoritative supersession; malformed CRUD/result refusal;
// queue isolation after durable rejection; transient failure retention; scoped
// credentials; Swift/MCP/Postgres canonical parity after O-043; replay of an
// earlier operation after later chained state; unknown terminal-code refusal;
// and no unauthorized local row after Sync authorization loss.
