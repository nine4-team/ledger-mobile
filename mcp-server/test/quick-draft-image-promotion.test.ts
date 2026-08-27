import { describe, expect, it } from "vitest";
import type { AttachmentRef, Item, ProtoItem } from "../src/types.js";
import {
  copyAttachmentsToItemNamespace,
  type ItemImageStorageOps,
} from "../src/util/item-image-storage.js";
import {
  documentedPromotionMergeOverrides,
  mergePromotedAttachments,
} from "../src/tools/quick-draft-items.js";

function storageUrl(path: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/ledger-nine4.firebasestorage.app/o/${encodeURIComponent(path)}?alt=media&token=test`;
}

function fakeStorageOps() {
  const sourceFiles = new Set([
    storageUrl("accounts/acc/protoItems/draft/photo-1.jpg"),
    storageUrl("accounts/acc/protoItems/draft/photo-2.jpg"),
    storageUrl("accounts/acc/protoItems/draft/photo-3.jpg"),
  ]);
  const created = new Map<string, Buffer>();
  const removed: string[] = [];
  const ops: ItemImageStorageOps = {
    async copy(sourceUrl, destinationPath) {
      if (!sourceFiles.has(sourceUrl)) throw new Error("missing source");
      const data = Buffer.from(sourceUrl);
      const url = storageUrl(destinationPath);
      created.set(url, data);
      return { url, path: destinationPath, data, contentType: "image/jpeg" };
    },
    async uploadVerified(destinationPath, data) {
      const url = storageUrl(destinationPath);
      created.set(url, data);
      return url;
    },
    async remove(url) {
      removed.push(url);
      created.delete(url);
    },
    async thumbnails(data) {
      return { sm: Buffer.from(`sm:${data.length}`), md: Buffer.from(`md:${data.length}`) };
    },
  };
  return { ops, sourceFiles, created, removed };
}

const draftPhotos: AttachmentRef[] = [
  { url: storageUrl("accounts/acc/protoItems/draft/photo-1.jpg"), fileName: "one.jpg", isPrimary: false },
  { url: storageUrl("accounts/acc/protoItems/draft/photo-2.jpg"), fileName: "two.jpg", isPrimary: true },
  { url: storageUrl("accounts/acc/protoItems/draft/photo-3.jpg"), fileName: "three.jpg", isPrimary: false },
];

describe("quick-draft image ownership", () => {
  it("copies full images and generated thumbnails into a new item's namespace", async () => {
    const fake = fakeStorageOps();
    const result = await copyAttachmentsToItemNamespace(draftPhotos, "acc", "item-new", undefined, fake.ops);
    expect(result.images).toHaveLength(3);
    expect(result.copiedPaths).toHaveLength(9);
    expect(result.copiedPaths.every((path) => path.startsWith("accounts/acc/items/item-new/"))).toBe(true);
    expect(result.images.every((image) => image.url.includes(encodeURIComponent("accounts/acc/items/item-new/")))).toBe(true);
    expect(result.images[0].fileName).toBe("two.jpg");
    expect(result.images[0].isPrimary).toBe(true);
    expect(fake.sourceFiles.size).toBe(3);
    expect(fake.removed).toEqual([]);
  });

  it("allows the caller to choose a different promoted primary", async () => {
    const fake = fakeStorageOps();
    const result = await copyAttachmentsToItemNamespace(
      draftPhotos,
      "acc",
      "item-new",
      draftPhotos[2].url,
      fake.ops
    );
    expect(result.images[0].fileName).toBe("three.jpg");
    expect(result.images.filter((image) => image.isPrimary)).toHaveLength(1);
  });

  it("cleans up destination copies and leaves sources intact if a required copy fails", async () => {
    const fake = fakeStorageOps();
    let copyCount = 0;
    const failingOps: ItemImageStorageOps = {
      ...fake.ops,
      async copy(sourceUrl, destinationPath) {
        copyCount += 1;
        if (copyCount === 2) throw new Error("copy failed");
        return fake.ops.copy(sourceUrl, destinationPath);
      },
    };
    await expect(copyAttachmentsToItemNamespace(draftPhotos, "acc", "item-new", undefined, failingOps))
      .rejects.toThrow("copy failed");
    expect(fake.created.size).toBe(0);
    expect(fake.sourceFiles.size).toBe(3);
  });

  it("merges promoted images ahead of and primary over an existing primary", () => {
    const existing = [{ url: "old", fileName: "old.jpg", isPrimary: true }];
    const promoted = [
      { url: "new-primary", fileName: "new.jpg", isPrimary: true },
      { url: "new-other", fileName: "other.jpg", isPrimary: false },
    ];
    const result = mergePromotedAttachments(existing, promoted);
    expect(result.map((image) => image.url)).toEqual(["new-primary", "new-other", "old"]);
    expect(result.filter((image) => image.isPrimary).map((image) => image.url)).toEqual(["new-primary"]);
    expect(result[2].fileName).toBe("old.jpg");
  });
});

describe("quick-draft merge overrides", () => {
  it("applies every documented item-field override", () => {
    const existing = { id: "item", sku: "old" } as Item;
    const draft = { id: "draft", sku: "draft-sku" } as ProtoItem;
    const result = documentedPromotionMergeOverrides(existing, draft, {
      name: "New name",
      notes: "New notes",
      quantity: 4,
      sku: "new-sku",
      status: "to return",
      source: "New vendor",
      purchasePriceCents: 100,
      projectPriceCents: 150,
      marketValueCents: 200,
      taxRatePct: 8.25,
      projectId: "project",
      transactionId: "transaction",
      budgetCategoryId: "category",
      spaceId: "space",
    });
    expect(result).toEqual({
      name: "New name",
      notes: "New notes",
      quantity: 4,
      sku: "new-sku",
      status: "to return",
      source: "New vendor",
      purchasePriceCents: 100,
      projectPriceCents: 150,
      marketValueCents: 200,
      taxRatePct: 8.25,
      projectId: "project",
      transactionId: "transaction",
      budgetCategoryId: "category",
      spaceId: "space",
    });
  });

  it("does not overwrite existing fields when no merge override is requested", () => {
    const result = documentedPromotionMergeOverrides(
      { id: "item", sku: "existing" } as Item,
      { id: "draft", sku: "draft" } as ProtoItem,
      {}
    );
    expect(result).toEqual({});
  });
});
