import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { ProjectNote } from "../types.js";
import { subcollection, queryDocs } from "../util/query.js";
import { requireNonEmptyNote } from "../util/errors.js";

export function registerProjectNoteTools(server: McpServer, db: Firestore) {
  // ── add_project_note ────────────────────────────────────────────────────────
  server.tool(
    "add_project_note",
    "[mutating] Add a note to a project. Each note is a separate document in the project's notes subcollection with its own createdAt timestamp — no date prefix needed in the text.",
    {
      projectId: z.string().describe("Project document ID"),
      text: z.string().describe("The note content. Free-form, non-empty. createdAt is set automatically."),
    },
    async ({ projectId, text }) => {
      const noteError = requireNonEmptyNote(text, "add_project_note");
      if (noteError) return noteError;

      const ref = await subcollection(db, "projects", projectId, "notes").add({
        text,
        source: "mcp",
        createdBy: "mcp-agent",
        createdByName: "AI Assistant",
        createdAt: new Date(),
      });

      return { content: [{ type: "text", text: `Created note ${ref.id} on project ${projectId}` }] };
    }
  );

  // ── list_project_notes ──────────────────────────────────────────────────────
  server.tool(
    "list_project_notes",
    "List notes for a project, newest first.",
    {
      projectId: z.string().describe("Project document ID"),
      limit: z.number().default(50).describe("Max notes to return (default 50, max 200)"),
    },
    async ({ projectId, limit }) => {
      const n = Math.min(Math.max(limit, 1), 200);
      const notes = await queryDocs<ProjectNote>(
        subcollection(db, "projects", projectId, "notes")
          .orderBy("createdAt", "desc")
          .limit(n)
      );
      return { content: [{ type: "text", text: JSON.stringify(notes, null, 2) }] };
    }
  );

  // ── search_project_notes ──────────────────────────────────────────────────
  server.tool(
    "search_project_notes",
    "Search notes within a project by text substring (case-insensitive).",
    {
      projectId: z.string().describe("Project document ID"),
      query: z.string().describe("Search text"),
      limit: z.number().default(20).describe("Max results to return (default 20)"),
    },
    async ({ projectId, query, limit }) => {
      const allNotes = await queryDocs<ProjectNote>(
        subcollection(db, "projects", projectId, "notes")
      );
      const lower = query.toLowerCase();
      const matched = allNotes
        .filter((note) => note.text.toLowerCase().includes(lower))
        .slice(0, Math.max(limit, 1));
      return { content: [{ type: "text", text: JSON.stringify(matched, null, 2) }] };
    }
  );
}
