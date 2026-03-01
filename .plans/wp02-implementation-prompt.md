# WP02 Implementation Prompt — Settings Budget Category Edit

## Your Mission

Add **change tracking** to the budget category edit modal in `settings.tsx`. When a user saves a category edit, only send the fields that actually changed to Firestore. If nothing changed, skip the write entirely.

**This is a small, focused WP**: 1 file to modify, ~20 lines of logic to add.

---

## Step 0: Enter the Worktree

```bash
cd /Users/benjaminmackenzie/Dev/ledger_mobile/.worktrees/001-architecture-critique-implementation-WP02
git branch --show-current
# → 001-architecture-critique-implementation-WP02
```

**ALL WORK HAPPENS IN THIS DIRECTORY. Not the main repo.**

---

## Step 1: Understand the Current Code

**File**: `app/(tabs)/settings.tsx`

The save handler you need to modify is `handleSaveCategoryDetails` (line ~517):

```typescript
// CURRENT CODE (lines 517-548):
const handleSaveCategoryDetails = () => {
  if (!accountId || !editingCategoryId) return;
  const existingCategory =
    editingCategoryId === 'new'
      ? null
      : budgetCategories.find((category) => category.id === editingCategoryId);
  const existingExclude = existingCategory?.metadata?.excludeFromOverallBudget;
  const trimmed = editingCategoryName.trim();
  if (!trimmed) {
    setCategorySaveError('Category name is required.');
    return;
  }
  setCategorySaveError('');
  const selectedCategoryType = editingCategoryType === 'standard' ? undefined : editingCategoryType;

  if (editingCategoryId === 'new') {
    createBudgetCategory(accountId, trimmed, {
      metadata: selectedCategoryType ? { categoryType: selectedCategoryType } : undefined,
    });
  } else {
    updateBudgetCategory(accountId, editingCategoryId, {
      name: trimmed,
      slug: trimmed.toLowerCase().replace(/\s+/g, '-'),
      metadata: {
        categoryType: editingCategoryType,
        ...(typeof existingExclude === 'boolean' ? { excludeFromOverallBudget: existingExclude } : {}),
      },
    });
  }

  handleCloseCategoryModal();
};
```

**Key observations:**
- The function handles BOTH create (new) and update (existing) paths
- For updates, it always sends all 3 fields: `name`, `slug`, `metadata`
- `slug` is derived from `name` (lowercased + hyphenated)
- `metadata` preserves `excludeFromOverallBudget` from the existing category
- `editingCategoryType` is the form state for the category type dropdown
- `handleCloseCategoryModal()` resets modal state and closes it

**Related state variables** (lines 138-141):
```typescript
const [editingCategoryId, setEditingCategoryId] = useState<string | null>(null);
const [editingCategoryName, setEditingCategoryName] = useState('');
const [editingCategoryType, setEditingCategoryType] = useState<'standard' | 'general' | 'itemized' | 'fee'>('standard');
```

**Service function signature** (`src/data/budgetCategoriesService.ts` line 156):
```typescript
export function updateBudgetCategory(
  accountId: string,
  categoryId: string,
  data: Partial<BudgetCategory>
): void
```

---

## Step 2: Implement Change Detection

Modify **only the `else` branch** (the update path) of `handleSaveCategoryDetails`. The create path stays untouched.

**What to change:**
1. Build the would-be update payload (same as current code)
2. Compare each field against the existing category
3. If nothing changed → skip write, just close modal
4. If changes exist → send only the changed fields

**Implementation approach:**

```typescript
// In the else branch (existing category update):
const newName = trimmed;
const newSlug = trimmed.toLowerCase().replace(/\s+/g, '-');
const newMetadata = {
  categoryType: editingCategoryType,
  ...(typeof existingExclude === 'boolean' ? { excludeFromOverallBudget: existingExclude } : {}),
};

// Build changed fields
const changedFields: Record<string, unknown> = {};

if (newName !== (existingCategory?.name || '')) {
  changedFields.name = newName;
}

if (newSlug !== (existingCategory?.slug || '')) {
  changedFields.slug = newSlug;
}

if (JSON.stringify(newMetadata) !== JSON.stringify(existingCategory?.metadata || {})) {
  changedFields.metadata = newMetadata;
}

// Skip write if nothing changed
if (Object.keys(changedFields).length > 0) {
  updateBudgetCategory(accountId, editingCategoryId, changedFields);
}
```

**Notes:**
- `slug` is derived from `name`, so if name changes, slug likely changes too — that's fine, both will be in `changedFields`
- The metadata comparison uses `JSON.stringify` — acceptable for this simple structure
- **DO NOT** modify the create path (`editingCategoryId === 'new'`)
- **DO NOT** modify `handleCloseCategoryModal` — it always runs regardless of changes
- The `updateBudgetCategory` call is already fire-and-forget (returns void) — no `.catch()` needed here since the service handles errors

---

## Step 3: Verify TypeScript Compilation

```bash
npx tsc --noEmit 2>&1 | grep "settings.tsx" | head -20
```

**Pre-existing errors in settings.tsx** (documented in MEMORY.md):
- `BudgetCategoryType` union mismatch — this is NOT your fault, ignore it

Fix only NEW errors you introduce. The `changedFields` type may need to be `Partial<BudgetCategory>` instead of `Record<string, unknown>` depending on what `updateBudgetCategory` accepts.

---

## Step 4: Commit and Finalize

```bash
# Verify changes
git diff

# Commit (quote the brackets in the path!)
git add "app/(tabs)/settings.tsx"
git commit -m "$(cat <<'EOF'
feat(WP02): add change tracking to budget category edit

Only send modified fields when saving budget category edits.
Skip Firestore write entirely when no fields changed.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Mark subtasks done
~/.local/bin/spec-kitty agent tasks mark-status T006 T007 T008 T009 T010 --status done

# Rebase on main (required before move-task)
git rebase main

# Move to review
~/.local/bin/spec-kitty agent tasks move-task WP02 --to for_review --note "Added change tracking to budget category edit. Saves skip write when no fields changed."
```

---

## Constraints & Guardrails

- **Offline-first**: `updateBudgetCategory` is already fire-and-forget (void return). Do NOT add `await`.
- **Preserve validation**: The `!trimmed` check and `setCategorySaveError` must remain.
- **Don't touch create path**: Only modify the `else` branch (existing category updates).
- **Don't modify other functions**: Only `handleSaveCategoryDetails` changes.
- **Pre-existing TSC errors**: Ignore errors in `__tests__/`, `SharedItemsList`, `SharedTransactionsList`, `resolveItemMove.ts`, `accountContextStore.ts`, and the `BudgetCategoryType` mismatch in settings.tsx itself.

---

## Success Criteria

1. Editing a category with no changes → no Firestore write, modal closes immediately
2. Changing only the name → update payload contains only `{name: "...", slug: "..."}` (slug derived from name)
3. Changing only the type → update payload contains only `{metadata: {...}}`
4. TypeScript compilation has no NEW errors
5. All changes committed to WP02 worktree branch
6. WP02 moved to `for_review` lane

---

## Reference Files

| File | Purpose |
|------|---------|
| `app/(tabs)/settings.tsx` | **THE file to modify** (line ~517) |
| `src/data/budgetCategoriesService.ts` | `updateBudgetCategory` signature (line 156) |
| `CLAUDE.md` | Offline-first coding rules |
| `MEMORY.md` | Pre-existing TSC errors to ignore |
| `kitty-specs/001-architecture-critique-implementation/tasks/WP02-settings-budget-category-edit.md` | Full WP02 spec |
