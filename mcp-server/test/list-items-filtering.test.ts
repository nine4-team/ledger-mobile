import { describe, expect, test } from "vitest";
import type { ZodTypeAny } from "zod";
import { requestContext } from "../src/context.js";
import { registerItemTools } from "../src/tools/items.js";

type ItemRow = { id: string; [key: string]: unknown };

class FakeItemQuery {
  private filters: Array<{ field: string; value: unknown }> = [];
  private offsetValue = 0;
  private limitValue = Number.POSITIVE_INFINITY;

  constructor(private readonly rows: ItemRow[]) {}

  where(field: string, operator: string, value: unknown) {
    expect(operator).toBe("==");
    this.filters.push({ field, value });
    return this;
  }

  offset(value: number) {
    this.offsetValue = value;
    return this;
  }

  limit(value: number) {
    this.limitValue = value;
    return this;
  }

  async get() {
    const rows = this.rows
      .filter((row) => this.filters.every(({ field, value }) => row[field] === value))
      .slice(this.offsetValue, this.offsetValue + this.limitValue);
    return {
      docs: rows.map((row) => {
        const { id, ...data } = row;
        return { id, data: () => data };
      }),
    };
  }
}

describe("list_items source filtering", () => {
  test("exposes source in the input schema and applies an exact Firestore filter", async () => {
    const rows: ItemRow[] = [
      { id: "wayfair-1", name: "Wayfair chair", source: "Wayfair" },
      { id: "homegoods-1", name: "Terra-cotta pot", source: "HomeGoods" },
      { id: "wayfair-2", name: "Wayfair table", source: "Wayfair" },
    ];
    let schema: Record<string, ZodTypeAny> | undefined;
    let handler: ((args: Record<string, unknown>) => Promise<unknown>) | undefined;
    const server = {
      tool(
        name: string,
        _description: string,
        inputSchema: Record<string, ZodTypeAny>,
        toolHandler: (args: Record<string, unknown>) => Promise<unknown>
      ) {
        if (name === "list_items") {
          schema = inputSchema;
          handler = toolHandler;
        }
      },
    };
    const db = {
      collection: () => new FakeItemQuery(rows),
    };

    registerItemTools(server as never, db as never);

    expect(schema?.source).toBeDefined();
    expect(schema?.source.safeParse("Wayfair").success).toBe(true);

    const result = await requestContext.run(
      { accountId: "test-account", uid: "test-user" },
      () => handler!({
        source: "Wayfair",
        limit: 50,
        offset: 0,
        fetchAll: false,
        mode: "full",
      })
    );
    const text = (result as { content: Array<{ text: string }> }).content[0].text;
    const payload = JSON.parse(text) as { items: ItemRow[] };

    expect(payload.items.map((item) => item.id)).toEqual(["wayfair-1", "wayfair-2"]);
    expect(payload.items.every((item) => item.source === "Wayfair")).toBe(true);
  });
});
