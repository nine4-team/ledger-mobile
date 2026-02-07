# Budget Management Feature - Implementation Plan

## Context

This plan implements the complete budget management feature as specified in `docs/specs/budget-management.md`. The feature enables users to:
- Define account-wide budget categories with different types (general, itemized, fee)
- Allocate category-specific budgets per project
- Track spending progress against budgets in real-time
- Customize budget displays with pinning and collapsed/expanded views
- Manage categories with archiving, reordering, and metadata toggles

**Why this is needed**: The current implementation is approximately 30% complete with basic data services and a simple progress bar, but lacks the full UI components, management screens, proper calculation logic for canonical inventory sales, and several critical features from the spec.

**Current state analysis**:
- ✅ Basic data services exist (budgetCategoriesService, projectBudgetCategoriesService, projectPreferencesService)
- ✅ Simple BudgetProgress component exists
- ⚠️ Budget calculation logic incomplete (missing canonical inventory sale multipliers, category exclusions)
- ❌ Missing AccountPresets service
- ❌ Missing full Budget Progress Display with collapsed/expanded views
- ❌ Missing Budget Category Management screen
- ❌ Missing Project Budget Form
- ⚠️ Field naming inconsistencies (type vs transactionType, status vs isCanceled, inheritedBudgetCategoryId vs budgetCategoryId)
- ⚠️ Only 2 of 4 default categories seeded (missing Install, Storage & Receiving)
- ⚠️ Design Fee has wrong excludeFromOverallBudget setting (should be true, is false)

**User decisions**:
- Migrate to spec-compliant field names (transactionType, isCanceled, budgetCategoryId)
- Full implementation of all features
- No specific current pain points to prioritize

---

## Implementation Phases

### Phase 1: Data Model Migration & Fixes (Week 1)

**Goal**: Migrate field names to match spec, fix data models, and establish correct calculation logic

#### 1.1 Field Name Migration

**Critical files to modify**:

1. **Transaction type and all usages** (estimate: 15-20 files)
   - Update `/src/data/transactionsService.ts`:
     - Rename `type` → `transactionType` in type definition
     - Rename `status` → keep as-is, add `isCanceled` field (derived or explicit)
   - Find all Transaction usages: `grep -r "\.type" src/` and update to `.transactionType`
   - Find all status checks: `grep -r "status === 'canceled'" src/` and update to `isCanceled === true`

2. **Item type and all usages** (estimate: 8-10 files)
   - Update `/src/data/itemsService.ts`:
     - Rename `inheritedBudgetCategoryId` → `budgetCategoryId` in type definition
   - Find all usages: `grep -r "inheritedBudgetCategoryId" src/` and update to `budgetCategoryId`
   - Update form fields that set this value

**Migration strategy**:
- Create migration script for existing Firestore data (Cloud Function or admin script)
- Batch update all Transaction documents: add `transactionType` from `type`, add `isCanceled` based on status
- Batch update all Item documents: copy `inheritedBudgetCategoryId` → `budgetCategoryId`
- Verify migration with sample queries before deploying

**Rollback plan**:
- Keep old fields for 30 days after migration
- Client code reads new fields, falls back to old fields if missing
- Delete old fields after verification period

#### 1.2 Fix BudgetCategory Type

**File**: `/src/data/budgetCategoriesService.ts`

Changes needed:
```typescript
// Remove 'standard' from type, keep only spec-compliant values
export type BudgetCategoryType = 'general' | 'itemized' | 'fee';

// Add missing timestamp fields to type definition
export type BudgetCategory = {
  id: string;
  accountId: string;           // Add this
  projectId: null;             // Add this (always null for account-scoped)
  name: string;
  slug?: string | null;
  isArchived?: boolean | null;
  order?: number | null;
  metadata?: {
    categoryType?: BudgetCategoryType;
    excludeFromOverallBudget?: boolean;
    legacy?: Record<string, unknown> | null;
  } | null;
  createdAt?: unknown;         // Already stored, add to type
  updatedAt?: unknown;         // Already stored, add to type
  createdBy?: string;          // Already stored, add to type
  updatedBy?: string;          // Already stored, add to type
};
```

Remove normalization logic that converts 'general' → 'standard'. If any existing categories have 'standard', migrate them to 'general'.

#### 1.3 Create AccountPresets Service

**New file**: `/src/data/accountPresetsService.ts`

```typescript
export type AccountPresets = {
  id: 'default';
  accountId: string;
  defaultBudgetCategoryId?: string | null;
  budgetCategoryOrder?: string[] | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

export function subscribeToAccountPresets(
  accountId: string,
  onChange: (presets: AccountPresets | null) => void
): Unsubscribe {
  if (!isFirebaseConfigured || !db) {
    onChange(null);
    return () => {};
  }

  const ref = doc(db, `accounts/${accountId}/presets/default`);
  return onSnapshot(ref, (snapshot) => {
    onChange(snapshot.exists() ? (snapshot.data() as AccountPresets) : null);
  });
}

export async function refreshAccountPresets(
  accountId: string,
  mode: 'cache' | 'online' | 'offline'
): Promise<AccountPresets | null> {
  if (!isFirebaseConfigured || !db) return null;

  const ref = doc(db, `accounts/${accountId}/presets/default`);
  const snapshot = await getDoc(ref);
  return snapshot.exists() ? (snapshot.data() as AccountPresets) : null;
}

export async function updateAccountPresets(
  accountId: string,
  data: Partial<Omit<AccountPresets, 'id' | 'accountId'>>
): Promise<void> {
  if (!isFirebaseConfigured || !db) return;

  const ref = doc(db, `accounts/${accountId}/presets/default`);
  await setDoc(ref, {
    ...data,
    updatedAt: serverTimestamp(),
  }, { merge: true });
}
```

Pattern follows existing `vendorDefaultsService.ts`.

#### 1.4 Fix Budget Progress Calculation

**File**: `/src/data/budgetProgressService.ts`

Update `normalizeSpendAmount` function:
```typescript
function normalizeSpendAmount(
  tx: Transaction,
  budgetCategories: Record<string, BudgetCategory>
): number {
  // Exclude canceled transactions
  if (tx.isCanceled === true) return 0;

  const amount = tx.amountCents ?? 0;
  const txType = tx.transactionType?.trim().toLowerCase();

  // Handle returns (negative amount)
  if (txType === 'return') {
    return -Math.abs(amount);
  }

  // Handle canonical inventory sales with direction-based multiplier
  if (tx.isCanonicalInventorySale && tx.inventorySaleDirection) {
    // project_to_business: subtract from spent (money back)
    // business_to_project: add to spent (money out)
    return tx.inventorySaleDirection === 'project_to_business'
      ? -Math.abs(amount)
      : Math.abs(amount);
  }

  // Default: purchases add to spent
  return amount;
}
```

Update `buildBudgetProgress` to handle exclusions:
```typescript
function buildBudgetProgress(
  transactions: Transaction[],
  budgetCategories: Record<string, BudgetCategory>
): BudgetProgress {
  const spentByCategory: Record<string, number> = {};
  let overallSpentCents = 0;

  transactions.forEach((tx) => {
    const categoryId = tx.budgetCategoryId?.trim();
    if (!categoryId) return;

    const amount = normalizeSpendAmount(tx, budgetCategories);
    if (amount === 0) return; // Skip canceled

    // Track per-category spending (always include)
    spentByCategory[categoryId] = (spentByCategory[categoryId] ?? 0) + amount;

    // Track overall spending (exclude if category has excludeFromOverallBudget)
    const category = budgetCategories[categoryId];
    const shouldExclude = category?.metadata?.excludeFromOverallBudget === true;
    if (!shouldExclude) {
      overallSpentCents += amount;
    }
  });

  return { spentCents: overallSpentCents, spentByCategory };
}
```

#### 1.5 Update ProjectBudgetCategory Type

**File**: `/src/data/projectBudgetCategoriesService.ts`

Add timestamp fields:
```typescript
export type ProjectBudgetCategory = {
  id: string;
  budgetCents: number | null;
  createdAt?: unknown;
  updatedAt?: unknown;
  createdBy?: string;
  updatedBy?: string;
};
```

Update `setProjectBudgetCategory` to write these fields.

#### 1.6 Fix Default Category Seeding

**Update Firebase Functions**: `firebase/functions/src/index.ts`

Change seed data:
```typescript
const BUDGET_CATEGORY_PRESET_SEED: BudgetCategorySeed[] = [
  {
    id: 'seed_furnishings',
    name: 'Furnishings',
    slug: 'furnishings',
    order: 0,
    metadata: { categoryType: 'itemized', excludeFromOverallBudget: false },
  },
  {
    id: 'seed_install',
    name: 'Install',
    slug: 'install',
    order: 1,
    metadata: { categoryType: 'general', excludeFromOverallBudget: false },
  },
  {
    id: 'seed_design_fee',
    name: 'Design Fee',
    slug: 'design-fee',
    order: 2,
    metadata: { categoryType: 'fee', excludeFromOverallBudget: true }, // CHANGED to true
  },
  {
    id: 'seed_storage_receiving',
    name: 'Storage & Receiving',
    slug: 'storage-receiving',
    order: 3,
    metadata: { categoryType: 'general', excludeFromOverallBudget: false },
  },
];
```

Also set Furnishings as default category in AccountPresets during seeding.

---

### Phase 2: Core UI Components (Week 2)

**Goal**: Build reusable atomic components for budget display

#### 2.1 Budget Category Tracker Component

**New file**: `/src/components/budget/BudgetCategoryTracker.tsx`

Single category display with progress bar, amounts, and color thresholds.

**Props**:
```typescript
type BudgetCategoryTrackerProps = {
  category: BudgetCategory;
  spentCents: number;
  budgetCents: number | null;
  compact?: boolean;
  isPinned?: boolean;
  showPinIndicator?: boolean;
  onPress?: () => void;
  onLongPress?: () => void; // Trigger pin menu
};
```

**Features**:
- Progress bar with color thresholds (green 0-49%, yellow 50-74%, red 75%+)
- Inverted thresholds for fee categories (green ≥75%, yellow 50-74%, red <50%)
- Overflow indicator (dark red bar) when >100%
- Amount labels: "spent/remaining" for general, "received/remaining to receive" for fees
- Title suffix: " Budget" for general/itemized, no suffix for fees
- Optional pin indicator icon

**Implementation details**:
```typescript
function getProgressColor(percentage: number, isFee: boolean): string {
  if (isFee) {
    if (percentage >= 75) return '#22C55E'; // green
    if (percentage >= 50) return '#EAB308'; // yellow
    return '#EF4444'; // red
  } else {
    if (percentage >= 75) return '#EF4444'; // red
    if (percentage >= 50) return '#EAB308'; // yellow
    return '#22C55E'; // green
  }
}

function getDisplayName(category: BudgetCategory): string {
  const isFee = category.metadata?.categoryType === 'fee';
  return isFee ? category.name : `${category.name} Budget`;
}

function getAmountLabels(spent: number, budget: number, isFee: boolean) {
  const remaining = budget - spent;
  const isOver = spent > budget;

  if (isFee) {
    return {
      spent: formatCurrency(spent) + ' received',
      remaining: isOver
        ? formatCurrency(Math.abs(remaining)) + ' over received'
        : formatCurrency(remaining) + ' remaining to receive'
    };
  } else {
    return {
      spent: formatCurrency(spent) + ' spent',
      remaining: isOver
        ? formatCurrency(Math.abs(remaining)) + ' over'
        : formatCurrency(remaining) + ' remaining'
    };
  }
}
```

Use theme colors from `@nine4/ui-kit` where possible.

#### 2.2 Budget Progress Display Component

**New file**: `/src/components/budget/BudgetProgressDisplay.tsx`

Full-featured collapsed/expanded budget view for project detail screen.

**Props**:
```typescript
type BudgetProgressDisplayProps = {
  projectId: string;
  budgetCategories: BudgetCategory[];
  projectBudgetCategories: Record<string, ProjectBudgetCategory>;
  budgetProgress: BudgetProgress;
  pinnedCategoryIds: string[];
  accountPresets: AccountPresets | null;
  onPinToggle?: (categoryId: string) => void;
  onCategoryPress?: (categoryId: string) => void;
};
```

**State**:
```typescript
const [isExpanded, setIsExpanded] = useState(false);
```

**Logic**:
```typescript
// Determine enabled categories (has budget OR has spend)
const enabledCategories = useMemo(() => {
  return budgetCategories.filter(cat => {
    const hasProjectBudget = projectBudgetCategories[cat.id] !== undefined;
    const hasSpend = budgetProgress.spentByCategory[cat.id] !== 0;
    return (hasProjectBudget || hasSpend) && !cat.isArchived;
  });
}, [budgetCategories, projectBudgetCategories, budgetProgress]);

// Sort categories: pinned → custom order → alphabetical → fees last
const sortedCategories = useMemo(() => {
  const pinned = pinnedCategoryIds
    .map(id => enabledCategories.find(c => c.id === id))
    .filter(Boolean);

  const unpinned = enabledCategories.filter(
    c => !pinnedCategoryIds.includes(c.id) && c.metadata?.categoryType !== 'fee'
  );

  const fees = enabledCategories.filter(c => c.metadata?.categoryType === 'fee');

  // Sort unpinned by custom order or alphabetically
  const customOrder = accountPresets?.budgetCategoryOrder ?? [];
  unpinned.sort((a, b) => {
    const aIndex = customOrder.indexOf(a.id);
    const bIndex = customOrder.indexOf(b.id);
    if (aIndex !== -1 && bIndex !== -1) return aIndex - bIndex;
    if (aIndex !== -1) return -1;
    if (bIndex !== -1) return 1;
    return a.name.localeCompare(b.name);
  });

  return [...pinned, ...unpinned, ...fees];
}, [enabledCategories, pinnedCategoryIds, accountPresets]);

// Visible categories based on expanded state
const visibleCategories = useMemo(() => {
  if (!isExpanded) {
    // Collapsed: show pinned only (or empty if no pins)
    return sortedCategories.filter(c => pinnedCategoryIds.includes(c.id));
  } else {
    // Expanded: show all
    return sortedCategories;
  }
}, [isExpanded, sortedCategories, pinnedCategoryIds]);

// Calculate Overall Budget
const overallBudget = useMemo(() => {
  let totalBudgetCents = 0;
  enabledCategories.forEach(cat => {
    const shouldExclude = cat.metadata?.excludeFromOverallBudget === true;
    if (!shouldExclude) {
      const budget = projectBudgetCategories[cat.id]?.budgetCents ?? 0;
      totalBudgetCents += budget;
    }
  });
  return totalBudgetCents;
}, [enabledCategories, projectBudgetCategories]);

// Show toggle button if there's hidden content
const showToggle = useMemo(() => {
  const hasUnpinned = sortedCategories.some(c => !pinnedCategoryIds.includes(c.id));
  return hasUnpinned || overallBudget > 0;
}, [sortedCategories, pinnedCategoryIds, overallBudget]);
```

**Render**:
```tsx
return (
  <View style={styles.container}>
    {/* Collapsed: pinned categories or Overall Budget if no pins */}
    {!isExpanded && visibleCategories.length === 0 && (
      <BudgetCategoryTracker
        category={{ id: 'overall', name: 'Overall', metadata: null }}
        spentCents={budgetProgress.spentCents}
        budgetCents={overallBudget}
      />
    )}

    {/* Visible categories */}
    {visibleCategories.map(cat => (
      <BudgetCategoryTracker
        key={cat.id}
        category={cat}
        spentCents={budgetProgress.spentByCategory[cat.id] ?? 0}
        budgetCents={projectBudgetCategories[cat.id]?.budgetCents ?? null}
        isPinned={pinnedCategoryIds.includes(cat.id)}
        showPinIndicator={!isExpanded}
        onPress={() => onCategoryPress?.(cat.id)}
        onLongPress={() => onPinToggle?.(cat.id)}
      />
    ))}

    {/* Expanded: Overall Budget at end (before fees) */}
    {isExpanded && overallBudget > 0 && (
      <BudgetCategoryTracker
        category={{ id: 'overall', name: 'Overall', metadata: null }}
        spentCents={budgetProgress.spentCents}
        budgetCents={overallBudget}
      />
    )}

    {/* Toggle button */}
    {showToggle && (
      <TouchableOpacity onPress={() => setIsExpanded(!isExpanded)} style={styles.toggle}>
        <Text>{isExpanded ? '▲ Show Less' : '▼ Show All Budget Categories'}</Text>
      </TouchableOpacity>
    )}

    {/* Empty state */}
    {enabledCategories.length === 0 && (
      <View style={styles.empty}>
        <Text>No budget categories enabled for this project</Text>
        <AppButton title="Set Budget" onPress={onSetBudget} />
      </View>
    )}
  </View>
);
```

#### 2.3 Budget Progress Preview Component

**New file**: `/src/components/budget/BudgetProgressPreview.tsx`

Compact budget preview for project cards (no toggle, single line per category).

**Props**:
```typescript
type BudgetProgressPreviewProps = {
  budgetCategories: BudgetCategory[];
  projectBudgetCategories: Record<string, ProjectBudgetCategory>;
  budgetProgress: BudgetProgress;
  pinnedCategoryIds: string[];
  maxCategories?: number; // Default 2
};
```

**Logic**: Same pinned category logic as collapsed mode, but no interaction.

**Render**: Single line format: `Category: $X / $Y (Z%) [progress bar]`

---

### Phase 3: Management Screens (Week 3)

**Goal**: Build screens for category management and project budget allocation

#### 3.1 Budget Category Management Screen

**New file**: `/src/screens/BudgetCategoryManagement.tsx`

Account-wide settings screen for managing budget categories.

**Features**:
- List all active categories with drag handles
- Default category dropdown at top
- Add/edit/archive actions
- Metadata toggles (itemize, fee, exclude from overall)
- Drag-and-drop reordering
- Archived section (collapsible)

**Structure**:
```tsx
export function BudgetCategoryManagement() {
  const accountId = useAccountContextStore(s => s.accountId);
  const [categories, setCategories] = useState<BudgetCategory[]>([]);
  const [accountPresets, setAccountPresets] = useState<AccountPresets | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const [editingCategory, setEditingCategory] = useState<BudgetCategory | null>(null);

  useEffect(() => {
    return subscribeToBudgetCategories(accountId, setCategories);
  }, [accountId]);

  useEffect(() => {
    return subscribeToAccountPresets(accountId, setAccountPresets);
  }, [accountId]);

  const activeCategories = categories.filter(c => !c.isArchived);
  const archivedCategories = categories.filter(c => c.isArchived);

  const handleReorder = async (orderedIds: string[]) => {
    await updateAccountPresets(accountId, { budgetCategoryOrder: orderedIds });
  };

  const handleArchive = async (categoryId: string) => {
    // Get transaction count (may need server-side function)
    const count = await getTransactionCount(accountId, categoryId);

    Alert.alert(
      'Archive category?',
      `This category has ${count} transactions. It will be hidden but can be restored later.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Archive',
          style: 'destructive',
          onPress: () => setBudgetCategoryArchived(accountId, categoryId, true)
        }
      ]
    );
  };

  return (
    <Screen title="Budget Categories">
      <View style={styles.section}>
        <Text style={styles.label}>Account-Wide Default</Text>
        <Picker
          selectedValue={accountPresets?.defaultBudgetCategoryId}
          onValueChange={(id) => updateAccountPresets(accountId, { defaultBudgetCategoryId: id })}
        >
          {activeCategories.map(cat => (
            <Picker.Item key={cat.id} label={cat.name} value={cat.id} />
          ))}
        </Picker>
      </View>

      <Text style={styles.sectionTitle}>Active Categories</Text>
      <DraggableFlatList
        data={activeCategories}
        onDragEnd={({ data }) => handleReorder(data.map(c => c.id))}
        renderItem={({ item, drag, isActive }) => (
          <CategoryRow
            category={item}
            onDrag={drag}
            isActive={isActive}
            onEdit={() => setEditingCategory(item)}
            onArchive={() => handleArchive(item.id)}
          />
        )}
        keyExtractor={(item) => item.id}
      />

      <AppButton title="+ Add Category" onPress={() => setEditingCategory({} as BudgetCategory)} />

      {archivedCategories.length > 0 && (
        <TouchableOpacity onPress={() => setShowArchived(!showArchived)} style={styles.archivedToggle}>
          <Text>{showArchived ? '▲' : '▼'} Archived ({archivedCategories.length})</Text>
        </TouchableOpacity>
      )}

      {showArchived && archivedCategories.map(cat => (
        <ArchivedCategoryRow
          key={cat.id}
          category={cat}
          onUnarchive={() => setBudgetCategoryArchived(accountId, cat.id, false)}
        />
      ))}

      {editingCategory && (
        <CategoryFormModal
          category={editingCategory}
          onClose={() => setEditingCategory(null)}
          onSave={async (data) => {
            if (editingCategory.id) {
              await updateBudgetCategory(accountId, editingCategory.id, data);
            } else {
              await createBudgetCategory(accountId, data.name, { metadata: data.metadata });
            }
            setEditingCategory(null);
          }}
        />
      )}
    </Screen>
  );
}
```

**Sub-components needed**:
- `CategoryRow.tsx` - Drag handle, name, metadata toggles, actions menu
- `ArchivedCategoryRow.tsx` - Grayed out row with unarchive action
- `CategoryFormModal.tsx` - Form for add/edit with validation

#### 3.2 Category Row Component

**New file**: `/src/components/budget/CategoryRow.tsx`

**Props**:
```typescript
type CategoryRowProps = {
  category: BudgetCategory;
  onDrag: () => void;
  isActive: boolean;
  onEdit: () => void;
  onArchive: () => void;
};
```

**Render**:
```tsx
<View style={[styles.row, isActive && styles.dragging]}>
  <TouchableOpacity onPressIn={onDrag} style={styles.dragHandle}>
    <Icon name="grip-vertical" />
  </TouchableOpacity>

  <View style={styles.content}>
    <Text style={styles.name}>{category.name}</Text>

    <View style={styles.metadata}>
      {category.metadata?.categoryType === 'itemized' && (
        <Text style={styles.badge}>Itemized</Text>
      )}
      {category.metadata?.categoryType === 'fee' && (
        <Text style={styles.badge}>Fee</Text>
      )}
      {category.metadata?.excludeFromOverallBudget && (
        <Text style={styles.badge}>Excluded from Overall</Text>
      )}
    </View>
  </View>

  <View style={styles.actions}>
    <TouchableOpacity onPress={onEdit}>
      <Icon name="edit" />
    </TouchableOpacity>
    <TouchableOpacity onPress={onArchive}>
      <Icon name="archive" />
    </TouchableOpacity>
  </View>
</View>
```

#### 3.3 Category Form Modal

**New file**: `/src/components/budget/CategoryFormModal.tsx`

**Props**:
```typescript
type CategoryFormModalProps = {
  category: BudgetCategory | null; // null for new
  onClose: () => void;
  onSave: (data: { name: string; metadata: BudgetCategoryMetadata }) => Promise<void>;
};
```

**State**:
```typescript
const [name, setName] = useState(category?.name ?? '');
const [isItemized, setIsItemized] = useState(category?.metadata?.categoryType === 'itemized');
const [isFee, setIsFee] = useState(category?.metadata?.categoryType === 'fee');
const [excludeFromOverall, setExcludeFromOverall] = useState(category?.metadata?.excludeFromOverallBudget ?? false);
```

**Validation**:
```typescript
const validate = () => {
  if (!name.trim()) {
    Alert.alert('Error', 'Category name is required');
    return false;
  }
  if (name.length > 100) {
    Alert.alert('Error', 'Category name must be less than 100 characters');
    return false;
  }
  if (isItemized && isFee) {
    Alert.alert('Error', 'Category cannot be both itemized and fee');
    return false;
  }
  return true;
};
```

**Render**:
```tsx
<Modal visible onRequestClose={onClose}>
  <View style={styles.modal}>
    <Text style={styles.title}>{category?.id ? 'Edit Category' : 'Add Category'}</Text>

    <TextInput
      value={name}
      onChangeText={setName}
      placeholder="Category name"
      style={styles.input}
    />

    <View style={styles.toggles}>
      <Switch
        label="Itemize"
        value={isItemized}
        onValueChange={(val) => {
          setIsItemized(val);
          if (val) setIsFee(false); // Mutually exclusive
        }}
      />

      <Switch
        label="Fee Category"
        value={isFee}
        onValueChange={(val) => {
          setIsFee(val);
          if (val) setIsItemized(false); // Mutually exclusive
        }}
      />

      <Switch
        label="Exclude from Overall Budget"
        value={excludeFromOverall}
        onValueChange={setExcludeFromOverall}
      />
    </View>

    <View style={styles.actions}>
      <AppButton title="Cancel" variant="secondary" onPress={onClose} />
      <AppButton
        title="Save"
        onPress={async () => {
          if (!validate()) return;

          const categoryType = isFee ? 'fee' : isItemized ? 'itemized' : 'general';
          await onSave({
            name,
            metadata: { categoryType, excludeFromOverallBudget: excludeFromOverall }
          });
        }}
      />
    </View>
  </View>
</Modal>
```

#### 3.4 Project Budget Form Screen

**New file**: `/src/screens/ProjectBudgetForm.tsx`

Per-project budget allocation screen.

**Features**:
- Auto-calculated total budget display (prominent)
- Grid of category inputs (2-column on tablet, 1-column on mobile)
- Enable/disable categories
- Currency input formatting
- Save/cancel actions

**Structure**:
```tsx
export function ProjectBudgetForm({ projectId }: { projectId: string }) {
  const accountId = useAccountContextStore(s => s.accountId);
  const [budgetCategories, setBudgetCategories] = useState<BudgetCategory[]>([]);
  const [projectBudgets, setProjectBudgets] = useState<Record<string, number | null>>({});
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    return subscribeToBudgetCategories(accountId, setBudgetCategories);
  }, [accountId]);

  useEffect(() => {
    const unsubscribe = subscribeToProjectBudgetCategories(accountId, projectId, (pbs) => {
      const budgetsMap: Record<string, number | null> = {};
      pbs.forEach(pb => {
        budgetsMap[pb.id] = pb.budgetCents;
      });
      setProjectBudgets(budgetsMap);
    });
    return unsubscribe;
  }, [accountId, projectId]);

  const totalBudgetCents = useMemo(() => {
    return Object.values(projectBudgets).reduce((sum, val) => sum + (val ?? 0), 0);
  }, [projectBudgets]);

  const enabledCategories = budgetCategories.filter(c =>
    !c.isArchived && projectBudgets[c.id] !== undefined
  );

  const handleSave = async () => {
    setLoading(true);
    try {
      // Update all enabled categories
      for (const [categoryId, budgetCents] of Object.entries(projectBudgets)) {
        await setProjectBudgetCategory(accountId, projectId, categoryId, { budgetCents });
      }

      // TODO: Remove disabled categories (not in projectBudgets)

      Alert.alert('Success', 'Budget saved');
      // Navigate back
    } catch (error) {
      Alert.alert('Error', 'Failed to save budget');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Screen title="Project Budget">
      <View style={styles.totalCard}>
        <Text style={styles.totalLabel}>Total Budget</Text>
        <Text style={styles.totalAmount}>{formatCurrency(totalBudgetCents)}</Text>
      </View>

      <Text style={styles.sectionTitle}>Budget Categories</Text>

      <View style={styles.grid}>
        {enabledCategories.map(category => (
          <CategoryBudgetInput
            key={category.id}
            category={category}
            budgetCents={projectBudgets[category.id]}
            onChange={(cents) => setProjectBudgets({ ...projectBudgets, [category.id]: cents })}
          />
        ))}
      </View>

      <AppButton
        title="+ Enable More Categories"
        onPress={() => {
          // Open category selector modal
        }}
      />

      <View style={styles.actions}>
        <AppButton title="Cancel" variant="secondary" onPress={() => {/* navigate back */}} />
        <AppButton title="Save" onPress={handleSave} loading={loading} />
      </View>
    </Screen>
  );
}
```

**Styles for responsive grid**:
```typescript
const styles = StyleSheet.create({
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 16,
  },
  // On mobile: full width
  // On tablet: 2 columns
});
```

#### 3.5 Category Budget Input Component

**New file**: `/src/components/budget/CategoryBudgetInput.tsx`

**Props**:
```typescript
type CategoryBudgetInputProps = {
  category: BudgetCategory;
  budgetCents: number | null;
  onChange: (cents: number | null) => void;
};
```

**Implementation**:
```tsx
export function CategoryBudgetInput({ category, budgetCents, onChange }: CategoryBudgetInputProps) {
  const [inputValue, setInputValue] = useState(formatCurrency(budgetCents ?? 0));

  const handleBlur = () => {
    // Parse currency input
    const parsed = parseCurrency(inputValue);
    onChange(parsed);
    setInputValue(formatCurrency(parsed ?? 0));
  };

  return (
    <View style={styles.container}>
      <Text style={styles.label}>{category.name}</Text>
      <TextInput
        value={inputValue}
        onChangeText={setInputValue}
        onBlur={handleBlur}
        keyboardType="decimal-pad"
        placeholder="$0.00"
        style={styles.input}
      />
    </View>
  );
}

function parseCurrency(input: string): number | null {
  const cleaned = input.replace(/[$,]/g, '');
  const parsed = parseFloat(cleaned);
  return isNaN(parsed) ? null : Math.round(parsed * 100);
}
```

---

### Phase 4: Integration & Polish (Week 4)

**Goal**: Wire everything together and add finishing touches

#### 4.1 Update ProjectShell Screen

**File**: `/src/screens/ProjectShell.tsx`

Replace simple BudgetProgress component with full BudgetProgressDisplay.

**Changes**:
1. Remove lines 357-383 (old budget preview section)
2. Add subscriptions for accountPresets
3. Add pin toggle handler
4. Render BudgetProgressDisplay

```tsx
// Add subscription
const [accountPresets, setAccountPresets] = useState<AccountPresets | null>(null);

useEffect(() => {
  if (!accountId) return;
  return subscribeToAccountPresets(accountId, setAccountPresets);
}, [accountId]);

// Add pin toggle handler
const handlePinToggle = useCallback(async (categoryId: string) => {
  if (!userId || !projectId) return;

  const isPinned = pinnedBudgetCategoryIds.includes(categoryId);
  const nextPinned = isPinned
    ? pinnedBudgetCategoryIds.filter(id => id !== categoryId)
    : [...pinnedBudgetCategoryIds, categoryId];

  await updateProjectPreferences(accountId, userId, projectId, {
    pinnedBudgetCategoryIds: nextPinned
  });
}, [accountId, userId, projectId, pinnedBudgetCategoryIds]);

// Replace budget display section with:
<BudgetProgressDisplay
  projectId={projectId}
  budgetCategories={Object.values(budgetCategories)}
  projectBudgetCategories={projectBudgetCategories}
  budgetProgress={{ spentCents: budgetSpentCents, spentByCategory: budgetSpentByCategory }}
  pinnedCategoryIds={pinnedBudgetCategoryIds}
  accountPresets={accountPresets}
  onPinToggle={handlePinToggle}
  onCategoryPress={(categoryId) => {
    // Navigate to transactions filtered by category
  }}
/>
```

#### 4.2 Update Project Preferences Seeding

**File**: `/src/data/projectPreferencesService.ts`

Update `ensureProjectPreferences` function to seed with Furnishings pinned by default (if enabled in project).

```typescript
export async function ensureProjectPreferences(
  accountId: string,
  projectId: string
): Promise<void> {
  if (!isFirebaseConfigured || !db) return;

  const uid = auth?.currentUser?.uid;
  if (!uid) return;

  const ref = doc(db, `accounts/${accountId}/users/${uid}/projectPreferences/${projectId}`);
  const snapshot = await getDoc(ref);

  // Only create if doesn't exist
  if (snapshot.exists()) return;

  // Find Furnishings category
  const budgetCategories = await refreshBudgetCategories(accountId, 'online');
  const furnishings = budgetCategories.find(c => c.name === 'Furnishings' && !c.isArchived);

  // Check if Furnishings is enabled in this project
  const projectBudgets = await refreshProjectBudgetCategories(accountId, projectId, 'online');
  const isFurnishingsEnabled = furnishings && projectBudgets.some(pb => pb.id === furnishings.id);

  const pinnedBudgetCategoryIds = isFurnishingsEnabled ? [furnishings.id] : [];

  await setDoc(ref, {
    id: projectId,
    accountId,
    userId: uid,
    projectId,
    pinnedBudgetCategoryIds,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
}
```

#### 4.3 Add Navigation Routes

Update navigation config to include:
- Settings → Budget Categories → navigate to `BudgetCategoryManagement` screen
- Project → Set Budget → navigate to `ProjectBudgetForm` screen

Use existing navigation patterns from the app.

#### 4.4 Add Pinning UI (Long-Press Context Menu)

**File**: `/src/components/budget/BudgetCategoryTracker.tsx`

Add long-press handler that shows action sheet:

```tsx
import { ActionSheetIOS, Platform } from 'react-native';

<TouchableOpacity
  onPress={onPress}
  onLongPress={() => {
    if (!onLongPress) return;

    if (Platform.OS === 'ios') {
      ActionSheetIOS.showActionSheetWithOptions(
        {
          options: [isPinned ? 'Unpin' : 'Pin to Top', 'Cancel'],
          cancelButtonIndex: 1,
        },
        (buttonIndex) => {
          if (buttonIndex === 0) onLongPress();
        }
      );
    } else {
      // Android: use Alert or custom modal
      Alert.alert(
        isPinned ? 'Unpin category?' : 'Pin category?',
        '',
        [
          { text: 'Cancel', style: 'cancel' },
          { text: isPinned ? 'Unpin' : 'Pin', onPress: onLongPress }
        ]
      );
    }
  }}
>
  {/* Category content */}
</TouchableOpacity>
```

#### 4.5 Implement Visual Design System

**New file**: `/src/utils/budgetColors.ts`

```typescript
export const BUDGET_COLORS = {
  standard: {
    green: { bar: '#22C55E', text: '#059669' },
    yellow: { bar: '#EAB308', text: '#CA8A04' },
    red: { bar: '#EF4444', text: '#DC2626' },
    overflow: { bar: '#991B1B', text: '#7F1D1D' },
  },
  fee: {
    green: { bar: '#22C55E', text: '#059669' },
    yellow: { bar: '#EAB308', text: '#CA8A04' },
    red: { bar: '#EF4444', text: '#DC2626' },
  },
};

export function getBudgetProgressColor(
  percentage: number,
  isFeeCategory: boolean
): { bar: string; text: string } {
  if (isFeeCategory) {
    // Inverted: green for high percentage (good)
    if (percentage >= 75) return BUDGET_COLORS.fee.green;
    if (percentage >= 50) return BUDGET_COLORS.fee.yellow;
    return BUDGET_COLORS.fee.red;
  } else {
    // Standard: red for high percentage (bad)
    if (percentage >= 75) return BUDGET_COLORS.standard.red;
    if (percentage >= 50) return BUDGET_COLORS.standard.yellow;
    return BUDGET_COLORS.standard.green;
  }
}

export function getOverflowColor(): { bar: string; text: string } {
  return BUDGET_COLORS.standard.overflow;
}
```

Use these constants in BudgetCategoryTracker component.

#### 4.6 Mobile Optimizations

**Touch targets**: Ensure all interactive elements have minimum 44pt height (iOS) / 48dp (Android)

**Responsive grid**: Use `useWindowDimensions` to switch between 1 and 2 columns

```tsx
import { useWindowDimensions } from 'react-native';

const { width } = useWindowDimensions();
const numColumns = width >= 768 ? 2 : 1; // Tablet: 2 cols, Mobile: 1 col
```

**Input font size**: Use 16px minimum for inputs to prevent iOS zoom

```typescript
const styles = StyleSheet.create({
  input: {
    fontSize: 16, // Prevents iOS zoom
    // ...
  }
});
```

---

### Phase 5: Testing & Edge Cases (Week 5)

**Goal**: Ensure robustness and handle all edge cases

#### 5.1 Unit Tests

**Create test files**:

1. `/src/data/__tests__/budgetProgressService.test.ts`

Test cases:
```typescript
describe('budgetProgressService', () => {
  test('excludes canceled transactions', () => {
    // Test with isCanceled: true
  });

  test('handles returns as negative amounts', () => {
    // Test with transactionType: 'Return'
  });

  test('handles canonical sales business_to_project', () => {
    // Test with isCanonicalInventorySale: true, direction: 'business_to_project'
  });

  test('handles canonical sales project_to_business', () => {
    // Test with isCanonicalInventorySale: true, direction: 'project_to_business'
  });

  test('excludes categories with excludeFromOverallBudget', () => {
    // Test that fee categories with excludeFromOverallBudget don't affect overall total
  });

  test('includes all transactions in per-category spending', () => {
    // Test that spentByCategory includes even excluded categories
  });
});
```

2. `/src/utils/__tests__/budgetColors.test.ts`

Test cases:
```typescript
describe('budgetColors', () => {
  test('standard categories: green at 0-49%', () => {
    expect(getBudgetProgressColor(25, false).bar).toBe('#22C55E');
  });

  test('standard categories: yellow at 50-74%', () => {
    expect(getBudgetProgressColor(60, false).bar).toBe('#EAB308');
  });

  test('standard categories: red at 75%+', () => {
    expect(getBudgetProgressColor(80, false).bar).toBe('#EF4444');
  });

  test('fee categories: inverted colors', () => {
    expect(getBudgetProgressColor(80, true).bar).toBe('#22C55E'); // green
    expect(getBudgetProgressColor(60, true).bar).toBe('#EAB308'); // yellow
    expect(getBudgetProgressColor(30, true).bar).toBe('#EF4444'); // red
  });
});
```

3. `/src/components/budget/__tests__/BudgetCategoryTracker.test.tsx`

Test cases:
```typescript
describe('BudgetCategoryTracker', () => {
  test('displays category name with " Budget" suffix for general', () => {
    // ...
  });

  test('displays category name without suffix for fee', () => {
    // ...
  });

  test('shows "spent" label for general categories', () => {
    // ...
  });

  test('shows "received" label for fee categories', () => {
    // ...
  });

  test('shows overflow indicator when >100%', () => {
    // ...
  });

  test('calculates percentage correctly', () => {
    // ...
  });
});
```

#### 5.2 Integration Tests

Manual test flows:

1. **Account Setup Flow**
   - Create new account
   - Verify 4 default categories created (Furnishings, Install, Design Fee, Storage & Receiving)
   - Verify Furnishings set as default
   - Verify Design Fee has excludeFromOverallBudget: true

2. **Project Setup Flow**
   - Create new project
   - Verify ProjectPreferences seeded with Furnishings pinned
   - Open budget form, set budgets for categories
   - Save and verify budgets appear in project detail

3. **Transaction Flow**
   - Add purchase transaction with budget category
   - Verify budget progress updates
   - Add return transaction
   - Verify spent decreases
   - Cancel transaction
   - Verify spent excludes canceled

4. **Canonical Inventory Sale Flow**
   - Move item from Business Inventory → Project
   - Verify canonical sale created
   - Verify budget spent increases
   - Move item from Project → Business Inventory
   - Verify budget spent decreases

5. **Category Management Flow**
   - Add new category
   - Edit category metadata
   - Reorder categories
   - Archive category with transactions
   - Verify category hidden from displays
   - Unarchive category

6. **Pinning Flow**
   - Long-press category to pin
   - Verify appears in collapsed view
   - Pin multiple categories
   - Verify order matches array order
   - Unpin category

#### 5.3 Edge Case Handling

**Implement graceful handling for**:

1. **No budget categories (account)**
   - Show empty state: "No budget categories created yet"
   - CTA: "Create Your First Category" → navigate to management screen

2. **No enabled categories (project)**
   - Show empty state: "No budget categories enabled for this project"
   - CTA: "Set Budget" → navigate to budget form

3. **No pinned categories**
   - Collapsed view shows Overall Budget only
   - Show hint: "Pin categories to customize this view"

4. **All categories archived**
   - Show: "All categories are archived. Unarchive or create new categories to track budgets."
   - CTA: "Manage Categories"

5. **Orphaned pinned category (deleted)**
   - Filter out from pinnedBudgetCategoryIds during render
   - Optional: Clean up on next save

6. **Orphaned pinned category (archived)**
   - Hide from collapsed view
   - Optionally show in expanded with archived styling

7. **Transaction with invalid budgetCategoryId**
   - Display as "Unknown Category" in UI
   - Exclude from budget calculations or show in "Other" bucket

8. **Offline mode**
   - Render from Firestore cache
   - Show offline banner
   - Disable editing actions (show toast: "Action requires internet connection")
   - Queue writes for sync on reconnect

9. **Negative budget amounts**
   - Validate on input: show error "Budget must be non-negative"
   - Prevent save

10. **Budget category name conflicts**
    - Validate uniqueness case-insensitively on create/edit
    - Show error: "Category name already exists"

11. **Very large budget amounts**
    - Cap at $21,474,836.47 (2^31 - 1 cents)
    - Validate on input

12. **Division by zero**
    - Handle budgetCents: null gracefully
    - Show "No budget set" instead of percentage

---

## Critical Files for Implementation

The following files are most critical and should be reviewed/modified in order:

### Phase 1 (Data Layer)
1. `/src/data/transactionsService.ts` - Migrate `type` → `transactionType`, add `isCanceled`
2. `/src/data/itemsService.ts` - Migrate `inheritedBudgetCategoryId` → `budgetCategoryId`
3. `/src/data/budgetProgressService.ts` - Fix calculation logic (canonical sales, exclusions)
4. `/src/data/budgetCategoriesService.ts` - Fix type, remove 'standard' normalization
5. `/src/data/accountPresetsService.ts` - Create new service
6. `firebase/functions/src/index.ts` - Update default category seeding

### Phase 2 (Core UI)
7. `/src/components/budget/BudgetCategoryTracker.tsx` - New atomic component
8. `/src/components/budget/BudgetProgressDisplay.tsx` - New full-featured component
9. `/src/utils/budgetColors.ts` - New color utilities

### Phase 3 (Management)
10. `/src/screens/BudgetCategoryManagement.tsx` - New management screen
11. `/src/screens/ProjectBudgetForm.tsx` - New allocation screen
12. `/src/components/budget/CategoryFormModal.tsx` - New modal for add/edit

### Phase 4 (Integration)
13. `/src/screens/ProjectShell.tsx` - Replace simple budget display with full component
14. `/src/data/projectPreferencesService.ts` - Update seeding logic

---

## Verification Plan

After implementation, verify the following end-to-end:

### Manual Verification Checklist

**Budget Progress Display**:
- [ ] Collapsed view shows only pinned categories
- [ ] Collapsed view shows Overall Budget if no pins
- [ ] Expanded view shows all categories + Overall Budget
- [ ] Toggle button appears/disappears correctly
- [ ] Fee categories displayed last
- [ ] Colors correct (green/yellow/red at right thresholds)
- [ ] Fee categories use inverted colors
- [ ] Overflow indicator shown when >100%
- [ ] Long-press to pin/unpin works

**Budget Calculations**:
- [ ] Purchase adds to spent
- [ ] Return subtracts from spent
- [ ] Canonical sale business→project adds to spent
- [ ] Canonical sale project→business subtracts from spent
- [ ] Canceled transaction excluded
- [ ] Category with excludeFromOverallBudget not in overall total
- [ ] Per-category budgets track all transactions

**Category Management**:
- [ ] Can create new category
- [ ] Can edit category name and metadata
- [ ] Can toggle itemize/fee/exclude (mutually exclusive validation works)
- [ ] Can drag-and-drop to reorder
- [ ] Can archive category (shows confirmation with count)
- [ ] Can unarchive category
- [ ] Default category dropdown works
- [ ] Archived section collapses/expands

**Project Budget Form**:
- [ ] Total budget auto-calculates correctly
- [ ] Currency inputs format properly
- [ ] Grid is 2-col on tablet, 1-col on mobile
- [ ] Can enable/disable categories
- [ ] Save persists to Firestore
- [ ] Budget display updates immediately

**Default Categories**:
- [ ] New account has 4 categories (Furnishings, Install, Design Fee, Storage & Receiving)
- [ ] Furnishings is itemized
- [ ] Design Fee is fee with excludeFromOverallBudget: true
- [ ] Install and Storage are general
- [ ] Furnishings is default category

**Edge Cases**:
- [ ] No categories: shows empty state
- [ ] No enabled categories: shows "Set Budget" CTA
- [ ] No pins: shows Overall Budget
- [ ] Archived category: hidden from displays
- [ ] Invalid category ID: shows "Unknown"
- [ ] Offline: shows cached data, disables editing

### Automated Tests

Run:
```bash
npm test src/data/__tests__/budgetProgressService.test.ts
npm test src/utils/__tests__/budgetColors.test.ts
npm test src/components/budget/__tests__/BudgetCategoryTracker.test.tsx
```

Verify all tests pass.

---

## Risks & Mitigation

**High Risk**:
1. **Field name migration breaking existing data** - Mitigate with migration script and backwards compatibility period
2. **Budget calculation errors** - Mitigate with comprehensive unit tests and manual QA
3. **Data migration for existing projects** - Mitigate with idempotent seeding and graceful handling of missing data

**Medium Risk**:
1. **Offline sync conflicts** - Firestore handles last-write-wins, optimistic UI updates
2. **Performance with many categories** - Use virtualized lists if >50 categories
3. **Mobile gesture discoverability** - Add tooltip on first use

**Low Risk**:
1. **Color threshold confusion** - Clear visual distinction, real data testing
2. **Archived category orphans** - Filter archived from UI

---

## Success Criteria

Implementation is complete when:
- ✅ All 4 default categories seed correctly on account creation
- ✅ Budget calculations handle all transaction types correctly (purchases, returns, canonical sales, canceled)
- ✅ Budget Progress Display shows collapsed/expanded views with pinning
- ✅ Budget Category Management screen allows CRUD operations
- ✅ Project Budget Form allows per-project allocation
- ✅ Field names match spec (transactionType, isCanceled, budgetCategoryId)
- ✅ Fee categories have inverted colors and "received" language
- ✅ All edge cases handled gracefully
- ✅ Unit tests pass
- ✅ Manual verification checklist complete
