import { describe, expect, it } from "vitest";
import type { Firestore } from "firebase-admin/firestore";
import { registerItemTools } from "../src/tools/items.js";
import { registerQuickDraftItemTools } from "../src/tools/quick-draft-items.js";

function captureTools(register: (server: any, db: Firestore) => void) {
  const tools = new Map<string, { description: string; schema: Record<string, unknown> }>();
  const server = {
    tool(name: string, description: string, schema: Record<string, unknown>) {
      tools.set(name, { description, schema });
    },
    resource() {},
  };
  register(server, {} as Firestore);
  return tools;
}

describe("item image MCP schemas", () => {
  it("publishes safe primary, reorder, detach, and explicit destructive delete tools", () => {
    const tools = captureTools(registerItemTools);
    expect(tools.get("set_primary_item_image")?.schema).toHaveProperty("imageUrl");
    expect(tools.get("reorder_item_images")?.schema).toHaveProperty("orderedImageUrls");
    expect(tools.get("reorder_item_images")?.schema).toHaveProperty("primaryImageUrl");
    expect(tools.get("detach_item_image")?.schema).toHaveProperty("imageUrl");
    expect(tools.get("detach_item_image")?.description).toContain("non-destructive");
    expect(tools.get("delete_item_image")?.description.startsWith("[DESTRUCTIVE]")).toBe(true);
  });

  it("publishes attach position/primary and promotion primary selection", () => {
    const itemTools = captureTools(registerItemTools);
    expect(itemTools.get("attach_item_image")?.schema).toHaveProperty("isPrimary");
    expect(itemTools.get("attach_item_image")?.schema).toHaveProperty("position");

    const draftTools = captureTools(registerQuickDraftItemTools);
    expect(draftTools.get("create_quick_draft_item")?.schema).toHaveProperty("assignmentHint");
    expect(draftTools.get("create_quick_draft_item")?.schema).toHaveProperty("spaceId");
    expect(draftTools.get("update_quick_draft_item")?.schema).toHaveProperty("assignmentHint");
    expect(draftTools.get("promote_quick_draft_item")?.schema).toHaveProperty("primaryImageUrl");
    expect(draftTools.get("promote_quick_draft_item")?.description).toContain("draft originals are preserved");
  });
});
