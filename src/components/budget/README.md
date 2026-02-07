# Budget Components

This directory contains components for the Budget Management system, implementing the specification from `/docs/specs/budget-management.md`.

## Phase 2.1: BudgetCategoryTracker

### Component: `BudgetCategoryTracker.tsx`

A single category display component with progress bar, amounts, and color thresholds.

#### Features

1. **Category Name Display**
   - General/Itemized categories: Shows name with " Budget" suffix (e.g., "Furnishings Budget")
   - Fee categories: Shows name without suffix (e.g., "Design Fee")
   - Overall Budget: Shows as "Overall Budget"

2. **Progress Bar with Color Thresholds**
   - **General/Itemized Categories:**
     - Green (0-49%): Healthy spending
     - Yellow (50-74%): Warning level
     - Red (75%+): Critical/over budget

   - **Fee Categories (Inverted):**
     - Red (0-49%): Low collection progress
     - Yellow (50-74%): Partial collection
     - Green (75%+): Good collection progress

3. **Overflow Indicator**
   - Dark red bar segment when spending exceeds 100% of budget
   - Visual indicator for over-budget categories

4. **Amount Labels**
   - **General/Itemized:** "spent" and "remaining" terminology
   - **Fee Categories:** "received" and "remaining to receive" terminology
   - **Over Budget:** Shows "over" instead of "remaining"

5. **Optional Features**
   - Pin indicator (📌 emoji)
   - Interactive callbacks (onPress, onLongPress)
   - Support for null budgetCents (shows "No budget set")

#### Props Interface

```typescript
type BudgetCategoryTrackerProps = {
  categoryName: string;
  categoryType: 'general' | 'itemized' | 'fee';
  spentCents: number;
  budgetCents: number | null;
  isPinned?: boolean;
  onPress?: () => void;
  onLongPress?: () => void;
  isOverallBudget?: boolean;
};
```

#### Usage Examples

See `BudgetCategoryTracker.example.tsx` for comprehensive examples.

**Basic General Category:**
```tsx
<BudgetCategoryTracker
  categoryName="Install"
  categoryType="general"
  spentCents={350000}    // $3,500
  budgetCents={1000000}  // $10,000
/>
```

**Fee Category with Pin:**
```tsx
<BudgetCategoryTracker
  categoryName="Design Fee"
  categoryType="fee"
  spentCents={425000}    // $4,250 received
  budgetCents={500000}   // $5,000 total
  isPinned={true}
/>
```

**Interactive Category:**
```tsx
<BudgetCategoryTracker
  categoryName="Furnishings"
  categoryType="itemized"
  spentCents={650000}
  budgetCents={1000000}
  onPress={() => navigateToCategoryDetail()}
  onLongPress={() => showPinMenu()}
/>
```

**Overall Budget:**
```tsx
<BudgetCategoryTracker
  categoryName="Overall"
  categoryType="general"
  spentCents={2320000}
  budgetCents={4000000}
  isOverallBudget={true}
/>
```

#### Design System

The component follows the visual design system from the specification:

- **Typography:** 16px title (medium weight), 14px amounts/percentage
- **Colors:** Uses `budgetColors` utility for consistent color application
- **Spacing:** 8px gap between elements
- **Progress Bar:** 8px height, full rounded corners
- **Layout:** Flexbox with space-between alignment

#### Dependencies

- `budgetColors.ts`: Utility for color calculation based on percentage and category type
- `AppText`: Themed text component
- React Native core components (View, Pressable, StyleSheet)

#### Accessibility

- Touch targets meet 44pt minimum when interactive
- Color coding supplemented with percentage text
- Semantic labeling for screen readers

#### Future Enhancements

Future phases will add:
- Phase 2.2: Budget progress container with collapsed/expanded modes
- Phase 2.3: Toggle functionality and pinning UI
- Phase 3: Full budget management screens

## Phase 2.3: BudgetProgressPreview

### Component: `BudgetProgressPreview.tsx`

A compact budget preview component for project cards. This is a simpler, non-interactive version of BudgetProgressDisplay.

#### Features

1. **No Toggle, No Interaction**
   - Static display only (no expand/collapse)
   - No touch handlers or interactive elements
   - Designed for project list cards

2. **Single Line Format Per Category**
   - Compact layout with category name, amounts, percentage, and mini progress bar
   - Each category on one line with minimal vertical space

3. **Show Only Pinned Categories**
   - Displays pinned categories (max 2 by default via `maxCategories` prop)
   - Falls back to Overall Budget if no categories are pinned
   - Respects user's pinning preferences from ProjectPreferences

4. **Uses BudgetCategoryTracker Logic**
   - Same color thresholds and calculation logic
   - Fee categories use inverted colors
   - Handles excluded categories for overall budget calculation

#### Props Interface

```typescript
type BudgetProgressPreviewProps = {
  budgetCategories: BudgetCategory[];
  projectBudgetCategories: Record<string, ProjectBudgetCategory>;
  budgetProgress: BudgetProgress;
  pinnedCategoryIds: string[];
  maxCategories?: number; // Default 2
};
```

#### Usage Examples

**With Pinned Categories:**
```tsx
<BudgetProgressPreview
  budgetCategories={budgetCategories}
  projectBudgetCategories={projectBudgetCategoriesMap}
  budgetProgress={{ spentCents: 2320000, spentByCategory: {...} }}
  pinnedCategoryIds={['furnishings-id', 'install-id']}
  maxCategories={2}
/>
```

**No Pins (Shows Overall Budget):**
```tsx
<BudgetProgressPreview
  budgetCategories={budgetCategories}
  projectBudgetCategories={projectBudgetCategoriesMap}
  budgetProgress={{ spentCents: 2320000, spentByCategory: {...} }}
  pinnedCategoryIds={[]}
/>
```

**On Project Card:**
```tsx
<View style={styles.projectCard}>
  <Text style={styles.projectName}>{project.name}</Text>
  <Text style={styles.clientName}>{project.clientName}</Text>

  <BudgetProgressPreview
    budgetCategories={budgetCategories}
    projectBudgetCategories={projectBudgets}
    budgetProgress={budgetProgress}
    pinnedCategoryIds={pinnedIds}
    maxCategories={2}
  />
</View>
```

#### Design System

- **Typography:** Caption variant (smaller than BudgetCategoryTracker)
- **Progress Bar:** 4px height (thinner than full tracker for compact display)
- **Spacing:** 8px gap between categories, 4px gap between label and progress bar
- **Layout:** Horizontal layout with amounts and percentage on the right

#### Behavior

1. **Enabled Categories:** Categories are shown if they have a project budget OR have spending
2. **Pinned Order:** Categories appear in the order specified in `pinnedCategoryIds`
3. **Max Limit:** Shows at most `maxCategories` pinned categories (default 2)
4. **Fallback:** If no pins exist and overall budget > 0, shows "Overall Budget" line
5. **Empty State:** Returns null if no categories and no overall budget

#### Differences from BudgetProgressDisplay

| Feature | BudgetProgressDisplay | BudgetProgressPreview |
|---------|----------------------|----------------------|
| Toggle button | Yes (expand/collapse) | No |
| Interaction | Yes (tap, long-press) | No |
| Layout | Full width with detailed amounts | Compact single line |
| Categories shown | All enabled (expanded) / pinned (collapsed) | Pinned only (max 2) |
| Use case | Project detail screen | Project list cards |

#### Integration

This component is designed to be used in:
- Project list screens (card preview)
- Dashboard widgets
- Summary views
- Any location requiring compact budget status

## Phase 3.2: CategoryRow

### Component: `CategoryRow.tsx`

A row component for displaying budget categories in a draggable list with metadata badges and actions.

#### Features

1. **Drag Handle**
   - Visual drag indicator icon
   - Supports drag-and-drop reordering
   - Active state styling during drag

2. **Category Name Display**
   - Primary category name
   - Dimmed styling for archived categories

3. **Metadata Badges**
   - "Itemized" badge for itemized categories
   - "Fee" badge for fee categories
   - "Excluded" badge for categories excluded from overall budget
   - Compact badge styling with themed colors

4. **Action Buttons**
   - Edit button (pencil icon)
   - Archive/Unarchive button (archive icon)
   - Touch-friendly hit areas

#### Props Interface

```typescript
type CategoryRowProps = {
  id: string;
  name: string;
  isItemized?: boolean;
  isFee?: boolean;
  excludeFromOverallBudget?: boolean;
  isArchived?: boolean;
  isActive?: boolean;
  dragHandleProps?: Record<string, unknown>;
  onEdit?: () => void;
  onArchive?: () => void;
  style?: ViewStyle;
};
```

#### Usage Example

```tsx
<CategoryRow
  id="furnishings"
  name="Furnishings"
  isItemized={true}
  excludeFromOverallBudget={false}
  onEdit={() => handleEdit('furnishings')}
  onArchive={() => handleArchive('furnishings')}
/>
```

## Phase 3.3: CategoryFormModal

### Component: `CategoryFormModal.tsx`

A modal form component for creating and editing budget categories with validation.

#### Features

1. **Form Fields**
   - Name input field (text input)
   - Itemized toggle switch
   - Fee toggle switch
   - Exclude from Overall Budget toggle switch

2. **Validation**
   - Required name field
   - Max 100 character limit for name
   - Mutually exclusive itemized/fee toggles
   - Real-time validation feedback
   - Error messages display

3. **Modal UI**
   - Uses FormBottomSheet component
   - Save/Cancel action buttons
   - Loading state during save
   - Disabled state when invalid
   - Helper text for each toggle

4. **Behavior**
   - Auto-reset form on modal open
   - Prevents both itemized and fee from being true
   - Auto-turns off fee when itemized is enabled (and vice versa)
   - Trims whitespace from name on save

#### Props Interface

```typescript
type CategoryFormData = {
  name: string;
  isItemized: boolean;
  isFee: boolean;
  excludeFromOverallBudget: boolean;
};

type CategoryFormModalProps = {
  visible: boolean;
  onRequestClose: () => void;
  mode: 'create' | 'edit';
  initialData?: Partial<CategoryFormData>;
  onSave: (data: CategoryFormData) => void | Promise<void>;
  isSaving?: boolean;
  error?: string;
};
```

#### Usage Examples

**Create Mode:**
```tsx
<CategoryFormModal
  visible={isModalOpen}
  onRequestClose={() => setIsModalOpen(false)}
  mode="create"
  onSave={handleCreateCategory}
  isSaving={isSaving}
/>
```

**Edit Mode:**
```tsx
<CategoryFormModal
  visible={isModalOpen}
  onRequestClose={() => setIsModalOpen(false)}
  mode="edit"
  initialData={{
    name: "Furnishings",
    isItemized: true,
    isFee: false,
    excludeFromOverallBudget: false,
  }}
  onSave={handleUpdateCategory}
  isSaving={isSaving}
/>
```

#### Validation Rules

1. **Name Validation:**
   - Must not be empty (after trimming whitespace)
   - Maximum 100 characters
   - Shows error message below field

2. **Category Type Validation:**
   - Itemized and Fee cannot both be true
   - Automatically enforced by toggle logic
   - Shows error message when violated

#### Integration

These components are designed to be used together in the budget category management screen:
- CategoryRow displays each category in a list
- CategoryFormModal handles creating/editing categories
- Both follow the established design patterns from the codebase

## Testing

Run examples:
```bash
# Import and render BudgetCategoryTrackerExamples in your app
# to see all component states
```

## References

- [Budget Management Spec](/docs/specs/budget-management.md)
- [Budget Management Implementation Plan](/docs/plans/budget-management-implementation.md)
- [Budget Colors Utility](/src/utils/budgetColors.ts)
