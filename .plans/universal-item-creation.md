# Universal Item Creation Flow

## Goal
Create a progressive-disclosure item creation flow (matching the transaction flow pattern) accessible from the universal add button.

## Steps

### Step 1: Destination — "Where does this belong?"
- Business Inventory (OptionCard)
- Project picker (ProjectPickerList)
- Required to proceed

### Step 2: Capture Method — "How do you want to start?"
- "Take a Photo" — opens camera/gallery, then goes to details with image pre-populated
- "Enter Details Manually" — goes straight to details form
- This step keeps the flow fast for designers in the field

### Step 3: Details Form
| Field | Component | Required? | Notes |
|-------|-----------|-----------|-------|
| Name | FormField | Conditional | Required if no image |
| Source | VendorPicker | No | Same as transaction flow |
| SKU | FormField | No | Free text |
| Purchase Price | FormField | No | decimal-pad keyboard |
| Project Price | FormField | No | Only if destination = project |
| Quantity | FormField | No | Default 1 |
| Space | SpaceSelector | No | Scoped to project if applicable |
| Photos | MediaGallerySection | Conditional | Required if no name |
| Notes | FormField (multiline) | No | |

### Validation
- Must have **name** OR at least **one image** (matches legacy web app)

### Post-Creation Navigation
- Navigate to item detail screen with `showNextSteps: 'true'`

## Files Changed
- `app/items/new-universal.tsx` — new screen (main deliverable)
- `app/(tabs)/_layout.tsx` — update add menu route
- `app/items/new.tsx` — kept as-is for contextual/deep-linked creation

## Architecture Notes
- Reuse OptionCard/StepSection/CompletedStepChip patterns inline (same as transaction flow)
- Offline-first: fire-and-forget createItem(), no await on Firestore writes
- Images via MediaGallerySection + saveLocalMedia
