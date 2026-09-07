#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  existsSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { backgroundAuditScope } from "./supabase-conversion-ledger.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = resolve(scriptDirectory, "..");
export const checklistRelativePath =
  "docs/plans/ledger-accounting-redesign/conversion/product-behavior-checklist.json";
export const checklistPath = join(repositoryRoot, checklistRelativePath);

const legacyCatalogRelativePath =
  "docs/plans/ledger-accounting-redesign/conversion/target-product-story-catalog.json";
const legacyWorkflowDirectoryRelativePath =
  "docs/plans/ledger-accounting-redesign/conversion/workflow-records";
const legacyCrosswalkRelativePath =
  "docs/plans/ledger-accounting-redesign/conversion/product-authority-crosswalk.json";

function clone(value) {
  return structuredClone(value);
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function sortedUnique(values) {
  return [...new Set(values)].sort();
}

function stableJson(value) {
  if (Array.isArray(value)) return value.map(stableJson);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, stableJson(value[key])]),
    );
  }
  return value;
}

function exactJsonEqual(left, right) {
  return JSON.stringify(stableJson(left)) === JSON.stringify(stableJson(right));
}

function baselineTransitionReference(transition) {
  return `${transition.from} | ${transition.event} | ${transition.to}`;
}

export function currentBehaviorIds(currentProduct) {
  const ids = [];
  for (const journey of currentProduct?.uiJourneys ?? []) {
    for (const control of journey.controls ?? []) {
      ids.push(`${journey.journeyId}::control::${control.label}`);
      for (const option of control.options ?? []) {
        ids.push(`${journey.journeyId}::option::${control.label}::${option.label}`);
      }
    }
    for (const transition of journey.transitions ?? []) {
      ids.push(
        `${journey.journeyId}::transition::${baselineTransitionReference(transition)}`,
      );
    }
    for (const state of journey.states ?? []) {
      ids.push(`${journey.journeyId}::state::${state.name}`);
    }
  }
  return sortedUnique(ids);
}

export function loadProductChecklist(path = checklistPath) {
  return readJson(path);
}

export function loadLegacySnapshots() {
  const catalogPath = join(repositoryRoot, legacyCatalogRelativePath);
  const workflowDirectory = join(repositoryRoot, legacyWorkflowDirectoryRelativePath);
  const crosswalkPath = join(repositoryRoot, legacyCrosswalkRelativePath);
  const workflowFiles = readdirSync(workflowDirectory)
    .filter((name) => name.endsWith(".json"))
    .sort();
  const workflowRecords = workflowFiles.map((name) => ({
    path: `${legacyWorkflowDirectoryRelativePath}/${name}`,
    record: readJson(join(workflowDirectory, name)),
  }));
  const baselineEntry = workflowRecords.find(
    ({ record }) => record.workflowId === "current-app-ui-control-flow-baseline",
  );
  if (!baselineEntry) throw new Error("Legacy Product Behavior Catalog is missing.");

  return {
    catalog: readJson(catalogPath),
    currentProduct: baselineEntry.record,
    workflowRecords: workflowRecords
      .filter(({ record }) => record.workflowId !== baselineEntry.record.workflowId)
      .map(({ record }) => record),
    canonicalSpecs: readJson(crosswalkPath).canonicalTargetSpecs ?? [],
    sourceFiles: {
      catalog: { path: legacyCatalogRelativePath, sha256: sha256File(catalogPath) },
      currentProduct: {
        path: baselineEntry.path,
        sha256: sha256File(join(repositoryRoot, baselineEntry.path)),
      },
      authorityCrosswalk: {
        path: legacyCrosswalkRelativePath,
        sha256: sha256File(crosswalkPath),
      },
      workflowRecords: workflowRecords
        .filter(({ record }) => record.workflowId !== baselineEntry.record.workflowId)
        .map(({ path }) => ({ path, sha256: sha256File(join(repositoryRoot, path)) })),
    },
  };
}

function inverseDecisionIds(catalog, group) {
  const result = new Map();
  for (const entry of catalog?.decisionCoverage?.[group] ?? []) {
    for (const storyId of entry.storyIds ?? []) {
      const ids = result.get(storyId) ?? [];
      ids.push(entry.decisionId);
      result.set(storyId, ids);
    }
  }
  return result;
}

function headingReferencesByOutcome(catalog) {
  const result = new Map();
  for (const authority of catalog.authorityCoverage ?? []) {
    for (const heading of authority.headingCoverage ?? []) {
      if (heading.disposition !== "story") continue;
      for (const storyId of heading.storyIds ?? []) {
        const refs = result.get(storyId) ?? [];
        refs.push({
          path: authority.path,
          heading: heading.heading,
          occurrence: heading.occurrence,
        });
        result.set(storyId, refs);
      }
    }
  }
  return result;
}

export function migrateLegacySnapshots({
  catalog,
  currentProduct,
  workflowRecords,
  canonicalSpecs,
  sourceFiles,
}) {
  const deliveryProfileByStory = new Map();
  for (const requirement of catalog.deliveryRequirements ?? []) {
    for (const storyId of requirement.storyIds ?? []) {
      if (deliveryProfileByStory.has(storyId)) {
        throw new Error(`Target outcome ${storyId} has multiple delivery profiles.`);
      }
      deliveryProfileByStory.set(storyId, requirement.profile);
    }
  }

  const confirmedByStory = inverseDecisionIds(catalog, "confirmed");
  const headingRefs = headingReferencesByOutcome(catalog);

  const outcomes = (catalog.stories ?? []).map((story) => {
    const refs = headingRefs.get(story.storyId) ?? [];
    const authorityHeadingRefs = refs.filter((ref) => ref.path === story.authority.path);
    const companionAuthorityRefs = refs.filter((ref) => ref.path !== story.authority.path);
    const deliveryProfile = deliveryProfileByStory.get(story.storyId);
    if (!deliveryProfile) throw new Error(`Target outcome ${story.storyId} lacks a delivery profile.`);
    if (authorityHeadingRefs.length === 0) {
      throw new Error(`Target outcome ${story.storyId} lacks owning authority heading coverage.`);
    }
    return {
      ...clone(story),
      deliveryProfile,
      confirmedDecisionIds: confirmedByStory.get(story.storyId) ?? [],
      authorityHeadingRefs,
      companionAuthorityRefs,
    };
  });

  const authorityReviews = (catalog.authorityCoverage ?? []).map((entry) => {
    const review = {
      path: entry.path,
      canonicalTarget: canonicalSpecs.includes(entry.path),
      sourceHash: entry.sourceHash,
      auditStatus: entry.auditStatus,
    };
    if (entry.reason !== undefined) review.reason = entry.reason;
    if (entry.headingCoverage !== undefined) {
      review.supportingHeadings = entry.headingCoverage
        .map(clone)
        .filter((heading) => heading.disposition === "supporting_or_nonproduct");
    }
    return review;
  });

  const decisionReviews = Object.fromEntries(
    ["confirmed", "open"].map((group) => [
      group,
      (catalog.decisionCoverage?.[group] ?? []).map(({ storyIds: _storyIds, ...entry }) => clone(entry)),
    ]),
  );

  const deliveryProfiles = (catalog.deliveryRequirements ?? []).map(
    ({ storyIds: _storyIds, ...profile }) => clone(profile),
  );

  return {
    schemaVersion: 1,
    checklistId: "ledger-product-behavior-checklist",
    migration: {
      kind: "one_time_legacy_normalization",
      sourceAuditNotes: { completeness: clone(catalog.completeness), remainingAudit: clone(catalog.remainingAudit ?? []) },
      sourceFiles: clone(sourceFiles),
      conservation: {
        currentBehaviorIds: currentBehaviorIds(currentProduct).length,
        targetOutcomeIds: outcomes.length,
        executionRecordIds: workflowRecords.length,
      },
    },
    authorityIndex: catalog.authorityIndex,
    decisionLog: clone(catalog.decisionLog),
    auditAreas: [
      {
        auditAreaId: "current-ui-target-disposition",
        title: "Current UI behavior and target disposition",
        status: "partial",
        completionRule: "Every inventoried current control, option, transition and meaningful state has one preserved, redesigned or retired target disposition.",
        remainingGaps: [
          "The exact current UI catalog is complete, but target disposition review is not yet complete for every behavior.",
        ],
      },
      {
        auditAreaId: "indexed-specs-and-decisions",
        title: "Indexed product specs and decisions",
        status: "partial",
        completionRule: "Every indexed canonical product spec and every confirmed/open product decision is reviewed into an outcome, explicit blocker or supported nonproduct disposition.",
        remainingGaps: [
          "The inherited target catalog remains partial; preserve its remainingAudit list as the detailed gap record.",
        ],
      },
      {
        auditAreaId: "background-and-mcp-capabilities",
        capabilityDispositions: [],
        title: "Background and MCP capability reconciliation",
        status: "partial",
        completionRule: "Every inventoried background and MCP capability is preserved, redesigned or retired, including target-only security, migration and cutover outcomes.",
        remainingGaps: [
          "Account profile and MCP ingestion metadata/triage remain unaudited; no email intake pipeline was found in the inspected source.",
        ],
      },
    ],
    deliveryProfiles,
    authorityReviews,
    decisionReviews,
    currentProduct: clone(currentProduct),
    outcomes,
    executionRecords: clone(workflowRecords),
  };
}

function legacyStory(outcome) {
  const {
    deliveryProfile: _deliveryProfile,
    confirmedDecisionIds: _confirmedDecisionIds,
    authorityHeadingRefs: _authorityHeadingRefs,
    companionAuthorityRefs: _companionAuthorityRefs,
    ...story
  } = outcome;
  return clone(story);
}

function projectAuthorityCoverage(checklist) {
  const refsByPath = new Map();
  for (const outcome of checklist.outcomes ?? []) {
    for (const ref of [
      ...(outcome.authorityHeadingRefs ?? []),
      ...(outcome.companionAuthorityRefs ?? []),
    ]) {
      const key = `${ref.path}\u0000${ref.heading}\u0000${ref.occurrence}`;
      const current = refsByPath.get(key) ?? { ...clone(ref), storyIds: [] };
      current.storyIds.push(outcome.storyId);
      refsByPath.set(key, current);
    }
  }

  return (checklist.authorityReviews ?? []).map((review) => {
      const entry = {
        path: review.path,
        sourceHash: review.sourceHash,
        auditStatus: review.auditStatus,
      };
      if (review.reason !== undefined) entry.reason = review.reason;
      const storyHeadings = [...refsByPath.values()]
        .filter((ref) => ref.path === review.path)
        .map((ref) => ({
          heading: ref.heading,
          occurrence: ref.occurrence,
          disposition: "story",
          storyIds: ref.storyIds,
        }));
      const headings = [
        ...(review.supportingHeadings ?? []).map(clone),
        ...storyHeadings,
      ];
      if (review.supportingHeadings !== undefined || storyHeadings.length > 0) {
        entry.headingCoverage = headings;
      }
      return entry;
    });
}

function projectDecisionCoverage(checklist, group) {
  return (checklist.decisionReviews?.[group] ?? []).map((review) => {
    if (group === "open") return clone(review);
    const storyIds = (checklist.outcomes ?? [])
      .filter((outcome) =>
        outcome.confirmedDecisionIds?.includes(review.decisionId),
      )
      .map((outcome) => outcome.storyId);
    return storyIds.length > 0 ? { ...clone(review), storyIds } : clone(review);
  });
}

export function projectLegacyStructures(checklist) {
  const auditComplete = (checklist.auditAreas ?? []).length > 0 &&
    checklist.auditAreas.every((area) => area.status === "reviewed" && area.remainingGaps?.length === 0) &&
    (checklist.authorityReviews ?? []).every((review) => review.auditStatus !== "partial") &&
    Object.values(checklist.decisionReviews ?? {}).flat().every((review) => review.auditStatus === "mapped");
  const catalog = {
    schemaVersion: 1,
    catalogId: "ledger-target-product-stories",
    authorityIndex: checklist.authorityIndex,
    decisionLog: clone(checklist.decisionLog),
    completeness: { status: auditComplete ? "complete" : "partial", reason: auditComplete ? "All audit areas, specs and decisions reviewed; outcome blockers remain independent." : "Audit areas or spec/decision reviews remain unfinished; see their direct gap records." },
    remainingAudit: (checklist.auditAreas ?? []).flatMap((area) => area.remainingGaps ?? []),
    deliveryRequirements: (checklist.deliveryProfiles ?? []).map((profile) => ({
      ...clone(profile),
      storyIds: (checklist.outcomes ?? [])
        .filter((outcome) => outcome.deliveryProfile === profile.profile)
        .map((outcome) => outcome.storyId),
    })),
    authorityCoverage: projectAuthorityCoverage(checklist),
    decisionCoverage: {
      confirmed: projectDecisionCoverage(checklist, "confirmed"),
      open: projectDecisionCoverage(checklist, "open"),
    },
    stories: (checklist.outcomes ?? []).map(legacyStory),
  };
  return {
    catalog,
    workflowRecords: [clone(checklist.currentProduct), ...clone(checklist.executionRecords ?? [])],
    canonicalSpecs: (checklist.authorityReviews ?? []).filter((review) => review.canonicalTarget === true).map((review) => review.path),
  };
}

function keyed(items, key) {
  return new Map((items ?? []).map((item) => [item[key], item]));
}

function normalizedAuthorityEntry(entry) {
  return {
    ...clone(entry),
    storyIds: sortedUnique(entry.storyIds ?? []),
    headingCoverage: (entry.headingCoverage ?? [])
      .map((heading) => ({
        ...clone(heading),
        storyIds: sortedUnique(heading.storyIds ?? []),
      }))
      .sort((left, right) =>
        `${left.heading}\u0000${left.occurrence}\u0000${left.disposition}`.localeCompare(
          `${right.heading}\u0000${right.occurrence}\u0000${right.disposition}`,
        ),
      ),
  };
}

function normalizedDecisionEntry(entry) {
  return { ...clone(entry), storyIds: sortedUnique(entry.storyIds ?? []) };
}

function normalizedProfile(entry) {
  return { ...clone(entry), storyIds: sortedUnique(entry.storyIds ?? []) };
}

function compareKeyed(errors, label, legacyItems, projectedItems, key, normalize = clone) {
  const legacy = keyed(legacyItems, key);
  const projected = keyed(projectedItems, key);
  if (!exactJsonEqual(sortedUnique(legacy.keys()), sortedUnique(projected.keys()))) {
    errors.push(`${label} IDs changed.`);
    return;
  }
  for (const id of legacy.keys()) {
    if (!exactJsonEqual(normalize(legacy.get(id)), normalize(projected.get(id)))) {
      errors.push(`${label} ${id} changed.`);
    }
  }
}

export function verifyLegacyConservation(legacy, checklist) {
  const projected = projectLegacyStructures(checklist);
  const errors = [];

  if (!exactJsonEqual(legacy.currentProduct, checklist.currentProduct)) {
    errors.push("Current Product Behavior Catalog detail changed.");
  }
  if (!exactJsonEqual(
    currentBehaviorIds(legacy.currentProduct),
    currentBehaviorIds(checklist.currentProduct),
  )) {
    errors.push("Current behavior IDs changed.");
  }
  if (!exactJsonEqual(sortedUnique(legacy.canonicalSpecs), sortedUnique(projected.canonicalSpecs))) {
    errors.push("Canonical spec registration changed.");
  }

  compareKeyed(errors, "Target outcome", legacy.catalog.stories, projected.catalog.stories, "storyId");
  compareKeyed(
    errors,
    "Delivery profile",
    legacy.catalog.deliveryRequirements,
    projected.catalog.deliveryRequirements,
    "profile",
    normalizedProfile,
  );
  compareKeyed(
    errors,
    "Authority review",
    legacy.catalog.authorityCoverage,
    projected.catalog.authorityCoverage,
    "path",
    normalizedAuthorityEntry,
  );
  for (const group of ["confirmed", "open"]) {
    compareKeyed(
      errors,
      `${group} decision review`,
      legacy.catalog.decisionCoverage?.[group],
      projected.catalog.decisionCoverage?.[group],
      "decisionId",
      normalizedDecisionEntry,
    );
  }
  compareKeyed(
    errors,
    "Execution record",
    legacy.workflowRecords,
    projected.workflowRecords.filter(
      (record) => record.workflowId !== checklist.currentProduct.workflowId,
    ),
    "workflowId",
  );

  if (errors.length > 0) throw new Error(`Checklist migration lost evidence:\n- ${errors.join("\n- ")}`);
  return {
    currentBehaviorIds: currentBehaviorIds(checklist.currentProduct).length,
    targetOutcomeIds: checklist.outcomes.length,
    authorityReviews: checklist.authorityReviews.length,
    confirmedDecisions: checklist.decisionReviews.confirmed.length,
    openDecisions: checklist.decisionReviews.open.length,
    deliveryProfiles: checklist.deliveryProfiles.length,
    executionRecords: checklist.executionRecords.length,
  };
}

function runSelfTest() {
  const checklist = loadProductChecklist();
  const projected = projectLegacyStructures(checklist);
  const syntheticLegacy = {
    catalog: projected.catalog,
    currentProduct: checklist.currentProduct,
    workflowRecords: checklist.executionRecords,
    canonicalSpecs: projected.canonicalSpecs,
  };
  const summary = verifyLegacyConservation(syntheticLegacy, checklist);
  const broken = clone(checklist);
  broken.currentProduct.uiJourneys[0].controls[0].label += " changed";
  let rejected = false;
  try {
    verifyLegacyConservation(syntheticLegacy, broken);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Conservation check accepted a changed behavior ID.");
  return summary;
}

function isMainModule() {
  return process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
}

if (isMainModule()) {
  const command = process.argv[2] ?? "--summary";
  if (command === "--migrate") {
    if (existsSync(checklistPath)) {
      throw new Error("Unified checklist already exists. Migration is one-time; do not overwrite live checklist work from historical snapshots.");
    }
    const legacy = loadLegacySnapshots();
    const checklist = migrateLegacySnapshots(legacy);
    const summary = verifyLegacyConservation(legacy, checklist);
    writeFileSync(checklistPath, `${JSON.stringify(checklist, null, 2)}\n`);
    console.log(`Wrote ${checklistRelativePath}: ${JSON.stringify(summary)}`);
  } else if (command === "--verify-legacy-conservation") {
    const summary = verifyLegacyConservation(loadLegacySnapshots(), loadProductChecklist());
    console.log(`Legacy conservation passed: ${JSON.stringify(summary)}`);
  } else if (command === "--self-test") {
    console.log(`Checklist loader self-test passed: ${JSON.stringify(runSelfTest())}`);
  } else if (command === "--summary") {
    if (!existsSync(checklistPath)) throw new Error(`Missing ${checklistRelativePath}.`);
    const checklist = loadProductChecklist();
    console.log(JSON.stringify({
      currentBehaviors: currentBehaviorIds(checklist.currentProduct).length,
      targetOutcomes: checklist.outcomes.length,
      executionRecords: checklist.executionRecords.length,
    }));
  } else if (command === "--audit") {
    const checklist = loadProductChecklist();
    const scope = backgroundAuditScope(readJson(join(repositoryRoot, "docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json")));
    console.log(JSON.stringify({
      status: projectLegacyStructures(checklist).catalog.completeness.status,
      backgroundSourceCount: scope.sources.length,
      areas: checklist.auditAreas,
      unreviewedSpecs: checklist.authorityReviews.filter((review) => review.auditStatus === "partial").map((review) => review.path),
      unreviewedDecisions: Object.values(checklist.decisionReviews).flat().filter((review) => review.auditStatus === "pending").map((review) => review.decisionId),
    }, null, 2));
  } else if (command === "--audit-sources") {
    const scope = backgroundAuditScope(readJson(join(repositoryRoot, "docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json")));
    const kind = process.argv[3];
    console.log(JSON.stringify(kind
      ? scope.sources.filter((surface) => surface.kind === kind).map((surface) => ({ id: surface.id, name: surface.name, sourceRefs: surface.sourceRefs }))
      : { digest: scope.digest, kinds: Object.fromEntries([...new Set(scope.sources.map((surface) => surface.kind))].sort().map((key) => [key, scope.sources.filter((surface) => surface.kind === key).length])) }, null, 2));
  } else if (command === "--outcome" || command === "--workflow") {
    const checklist = loadProductChecklist();
    const id = process.argv[3];
    const record = command === "--outcome"
      ? checklist.outcomes.find((outcome) => outcome.storyId === id)
      : checklist.executionRecords.find((workflow) => workflow.workflowId === id);
    if (!record) throw new Error(`Unknown ${command.slice(2)} ${id ?? "(missing ID)"}`);
    console.log(JSON.stringify(record, null, 2));
  } else {
    throw new Error(
      "Use --summary, --audit, --audit-sources [KIND], --outcome ID, --workflow ID, --self-test, --migrate, or --verify-legacy-conservation.",
    );
  }
}
