# Project Stages (Custom Pipelines)

**Status:** Planned
**Created:** 2026-04-17

## Summary

Let users define an ordered list of project stages (a "pipeline") at the account level, then move projects through those stages. Stages display as badges on project cards and are filterable in the project list.

## Motivation

Projects follow a lifecycle (Lead → Design → Procurement → Install → Complete) but there's no way to track where a project sits in that flow. Users resort to mental tracking or external tools. This feature makes the pipeline visible and actionable inside the app.

## Data Model

### Stage Preset (Account-Level)

```
Firestore path: accounts/{accountId}/stagePresets/{presetId}

struct StagePreset: Codable, Identifiable {
    @DocumentID var id: String?
    var accountId: String?
    var name: String              // e.g. "Interior Design Pipeline"
    var stages: [StageDef]        // ordered list
    var isDefault: Bool           // for now, only one preset — enforce in UI
    var createdAt: Date?
    var updatedAt: Date?
}

struct StageDef: Codable, Hashable {
    var name: String              // e.g. "Procurement"
    var color: String?            // optional hex color for badge
}
```

### Project Field

```swift
// Added to existing Project struct
var stage: String?   // plain string matching a StageDef.name
```

The project stores the stage name as a plain string — no foreign key to the preset. If someone renames a stage in the preset later, existing projects keep their old label until explicitly moved. No cascade.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Stage is a plain string on Project, not an ID reference | Simpler reads, no joins, no broken references if preset changes |
| Separate `stagePresets` subcollection (not inline on Account doc) | Allows multiple presets later (residential vs commercial) without migration |
| One default preset for now | Keep UI simple. Enforce in the app layer, not Firestore rules |
| Stage colors are optional | Can ship without them, add later. Default to `BrandColors.primary` when nil |

## Implementation Plan

### Phase 1: Data Layer

1. **StagePreset model** — New `Models/StagePreset.swift` with `StagePreset` and `StageDef` structs
2. **Add `stage` field to Project** — One optional string field in `Models/Project.swift`
3. **StagePresetService** — CRUD + real-time listener for `accounts/{accountId}/stagePresets`
   - `subscribeToStagePresets()` — listen to all presets for the account
   - `createStagePreset(preset)` — create new preset
   - `updateStagePreset(preset)` — update name, reorder/add/remove stages
   - `deleteStagePreset(id)` — delete preset
4. **Firestore rules** — Read/write rules for `stagePresets` subcollection. Same pattern as other account subcollections (account members can read, admins can write)
5. **MCP server** — Add stage preset endpoints so Claude can read/write presets and set project stages

### Phase 2: Settings UI (Preset Editor)

6. **Stage Preset editor in Settings → Presets tab** — Admin-only section
   - List existing presets (just one for now)
   - Create new preset with name + ordered stage list
   - Reorder stages via drag handles
   - Add/remove/rename individual stages
   - Delete preset (with confirmation)
7. **Default stage colors** — Optional color picker per stage, or skip for v1

### Phase 3: Project Integration

8. **Project card badge** — Display current stage as a `CardBadge` on `ProjectCard`
   - Use stage color if defined, else `BrandColors.primary`
   - Show nothing if project has no stage set
9. **Project detail — stage selector** — Picker or segmented control to set/change stage
   - Populated from the account's default stage preset
   - Freely selectable (not forced linear progression) — users can jump to any stage
10. **Project list filtering** — Add stage to `FilterMenu` options in the project list
    - Multi-select: show projects matching any selected stage
    - Include "No stage" option

### Phase 4: Polish

11. **Bulk stage update** — Select multiple projects, assign a stage
12. **Stage badge colors** — If deferred from Phase 2, add here
13. **Empty state** — When no preset exists, prompt user to create one from project detail

## Open Questions (Deferred)

- **Multiple presets per account** — The data model supports it. UI to assign a preset per project would come later.
- **Stage change history** — Could log stage transitions as a timeline. Not in v1.
- **Automations** — e.g., "When all items are delivered, auto-advance to Install." Future feature.

## Files Expected to Change

| File | Change |
|------|--------|
| `Models/StagePreset.swift` | New file — StagePreset, StageDef structs |
| `Models/Project.swift` | Add `stage: String?` field |
| `Services/StagePresetService.swift` | New file — Firestore CRUD + listener |
| `State/StagePresetManager.swift` | New file — @Observable state for presets |
| `Components/ProjectCard.swift` | Add stage badge |
| `Views/Settings/PresetsView.swift` | Stage preset editor section |
| `Views/Projects/ProjectDetailView.swift` | Stage selector |
| `Views/Projects/ProjectsView.swift` | Stage filter option |
| `firebase/firestore.rules` | Rules for stagePresets subcollection |
| `mcp-server/` | Stage preset + project stage endpoints |
