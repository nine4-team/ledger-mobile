import type { Firestore } from "firebase-admin/firestore";
import type { Item, Space } from "../types.js";
import { getDoc } from "./query.js";

export type DestinationSpaceAssignment = {
  itemId: string;
  spaceId: string;
};

export type DetachedSpaceAssignment = {
  itemId: string;
  spaceId: string;
  spaceProjectId: string | null;
  spaceFound: boolean;
};

export type SpaceAssignmentIssue = {
  message: string;
  guidance: string;
};

export type SpaceCache = Map<string, Space | null>;

function scopeId(value: string | null | undefined): string | null {
  return value ?? null;
}

async function loadSpace(
  db: Firestore,
  spaceId: string,
  cache: SpaceCache
): Promise<Space | null> {
  if (cache.has(spaceId)) return cache.get(spaceId) ?? null;
  const space = await getDoc<Space>(db, "spaces", spaceId);
  cache.set(spaceId, space);
  return space;
}

export async function validateItemSpaceTransition(
  db: Firestore,
  itemId: string,
  existing: Item,
  updates: Record<string, unknown>,
  callerProvidedSpaceId: boolean,
  cache: SpaceCache
): Promise<SpaceAssignmentIssue | null> {
  const finalProjectId = "projectId" in updates
    ? scopeId(updates.projectId as string | null | undefined)
    : scopeId(existing.projectId);
  const projectChanged = finalProjectId !== scopeId(existing.projectId);

  if (projectChanged && existing.spaceId && !callerProvidedSpaceId) {
    return {
      message: `Item ${itemId} changes project/inventory scope but has spaceId ${existing.spaceId}.`,
      guidance: "Pass spaceId: null to detach it, or pass a space that belongs to the resulting scope. Preserve a detached assignment from the correction receipt and pass it explicitly to a later sale when appropriate.",
    };
  }

  const finalSpaceId = "spaceId" in updates
    ? (updates.spaceId as string | null | undefined) ?? null
    : existing.spaceId ?? null;
  if (!finalSpaceId) return null;

  // Existing untouched assignments do not block unrelated field edits. Any
  // explicit space update or scope transition must establish valid final scope.
  if (!callerProvidedSpaceId && !projectChanged) return null;

  const space = await loadSpace(db, finalSpaceId, cache);
  if (!space) {
    return {
      message: `Space ${finalSpaceId} assigned to item ${itemId} does not exist.`,
      guidance: "Choose an existing space in the item's resulting scope, or pass spaceId: null.",
    };
  }

  const spaceProjectId = scopeId(space.projectId);
  if (spaceProjectId !== finalProjectId) {
    return {
      message: `Space ${finalSpaceId} belongs to ${spaceProjectId ?? "business inventory"}, but item ${itemId} would belong to ${finalProjectId ?? "business inventory"}.`,
      guidance: "Space assignments must match the item's resulting project/inventory scope.",
    };
  }
  return null;
}

export async function detachedSpaceAssignment(
  db: Firestore,
  itemId: string,
  existing: Item,
  updates: Record<string, unknown>,
  cache: SpaceCache
): Promise<DetachedSpaceAssignment | null> {
  if (!existing.spaceId || !("spaceId" in updates) || updates.spaceId != null) {
    return null;
  }
  const space = await loadSpace(db, existing.spaceId, cache);
  return {
    itemId,
    spaceId: existing.spaceId,
    spaceProjectId: scopeId(space?.projectId),
    spaceFound: space !== null,
  };
}

export async function validateDestinationSpaceAssignments(
  db: Firestore,
  itemIds: string[],
  destinationProjectId: string,
  assignments: DestinationSpaceAssignment[] | undefined
): Promise<
  | { ok: true; byItemId: Map<string, string> }
  | { ok: false; issue: SpaceAssignmentIssue }
> {
  const byItemId = new Map<string, string>();
  const itemIdSet = new Set(itemIds);

  for (const assignment of assignments ?? []) {
    if (!itemIdSet.has(assignment.itemId)) {
      return {
        ok: false,
        issue: {
          message: `Space assignment references item ${assignment.itemId}, which is not in this sale.`,
          guidance: "Every destination space assignment must reference exactly one itemId from the sale request.",
        },
      };
    }
    if (byItemId.has(assignment.itemId)) {
      return {
        ok: false,
        issue: {
          message: `Item ${assignment.itemId} has more than one destination space assignment.`,
          guidance: "Provide at most one destination space per item.",
        },
      };
    }
    byItemId.set(assignment.itemId, assignment.spaceId);
  }

  const cache: SpaceCache = new Map();
  for (const [itemId, spaceId] of byItemId) {
    const space = await loadSpace(db, spaceId, cache);
    if (!space) {
      return {
        ok: false,
        issue: {
          message: `Destination space ${spaceId} for item ${itemId} does not exist.`,
          guidance: "Choose a space returned by list_spaces/get_space for the destination project.",
        },
      };
    }
    if (scopeId(space.projectId) !== destinationProjectId) {
      return {
        ok: false,
        issue: {
          message: `Destination space ${spaceId} for item ${itemId} does not belong to project ${destinationProjectId}.`,
          guidance: "Use a destination-project space, or omit the assignment so the item lands unassigned.",
        },
      };
    }
  }

  return { ok: true, byItemId };
}
