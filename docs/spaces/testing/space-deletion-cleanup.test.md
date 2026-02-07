# Space Deletion Cleanup Cloud Function Tests

## Overview
This document describes test scenarios for the `onSpaceArchived` Cloud Function that automatically clears `item.spaceId` when a space is soft-deleted (archived).

## Test Scenarios

### 1. Basic Cleanup (0-10 items)

**Setup:**
1. Create a space in a project
2. Create 5 items assigned to that space
3. Soft delete the space (set `isArchived = true`)

**Expected Behavior:**
- All 5 items should have `spaceId` set to `null` within 2-3 seconds
- Items should remain in their project
- Space should be marked as archived
- Cloud Function logs should show success

**Verification:**
```typescript
// Query items that should have been updated
const itemsRef = db.collection(`accounts/${accountId}/items`)
  .where('spaceId', '==', null)
  .where('projectId', '==', projectId);

const snapshot = await itemsRef.get();
console.log(`Updated ${snapshot.docs.length} items`); // Should be 5
```

### 2. No Items Edge Case

**Setup:**
1. Create a space in a project
2. Do NOT assign any items to the space
3. Soft delete the space

**Expected Behavior:**
- Cloud Function executes successfully
- No items are updated (none exist)
- Logs show "No items found for space"
- Space is marked as archived

**Verification:**
Check Cloud Function logs for:
```
[onSpaceArchived] No items found for space {spaceId}
```

### 3. Large Batch (100+ items)

**Setup:**
1. Create a space in a project
2. Create 150 items assigned to that space
3. Soft delete the space

**Expected Behavior:**
- All 150 items should have `spaceId` cleared
- Cloud Function should handle batching automatically (Firestore limit = 500)
- Process should complete within 5-10 seconds
- Logs should show batch count and success

**Verification:**
```typescript
// Verify all items were updated
const itemsRef = db.collection(`accounts/${accountId}/items`)
  .where('projectId', '==', projectId);

const snapshot = await itemsRef.get();
const itemsWithSpace = snapshot.docs.filter(doc => doc.data().spaceId === spaceId);

console.log(`Items still assigned to deleted space: ${itemsWithSpace.length}`); // Should be 0
```

### 4. Cross-Workspace Isolation (Project Context)

**Setup:**
1. Create Space A in Project 1
2. Create Space B in Project 2 (different project, same account)
3. Create 5 items in Project 1 assigned to Space A
4. Create 5 items in Project 2 assigned to Space B
5. Soft delete Space A (Project 1)

**Expected Behavior:**
- Only the 5 items in Project 1 should be updated
- The 5 items in Project 2 should remain unchanged
- Space B should remain intact
- Cloud Function should only query items in Project 1

**Verification:**
```typescript
// Verify Project 1 items were updated
const project1Items = await db.collection(`accounts/${accountId}/items`)
  .where('projectId', '==', project1Id)
  .where('spaceId', '==', null)
  .get();
console.log(`Project 1 items updated: ${project1Items.docs.length}`); // Should be 5

// Verify Project 2 items were NOT updated
const project2Items = await db.collection(`accounts/${accountId}/items`)
  .where('projectId', '==', project2Id)
  .where('spaceId', '==', spaceBId)
  .get();
console.log(`Project 2 items unchanged: ${project2Items.docs.length}`); // Should be 5
```

### 5. Cross-Workspace Isolation (Business Inventory Context)

**Setup:**
1. Create Space A in Business Inventory (projectId = null)
2. Create Space B in Project 1
3. Create 5 items in Business Inventory assigned to Space A
4. Create 5 items in Project 1 assigned to Space B
5. Soft delete Space A (Business Inventory)

**Expected Behavior:**
- Only the 5 items in Business Inventory should be updated
- The 5 items in Project 1 should remain unchanged
- Cloud Function should only query items where projectId = null

**Verification:**
```typescript
// Verify BI items were updated
const biItems = await db.collection(`accounts/${accountId}/items`)
  .where('projectId', '==', null)
  .where('spaceId', '==', null)
  .get();
console.log(`BI items updated: ${biItems.docs.length}`); // Should be 5

// Verify Project items were NOT updated
const projectItems = await db.collection(`accounts/${accountId}/items`)
  .where('projectId', '==', project1Id)
  .where('spaceId', '==', spaceBId)
  .get();
console.log(`Project items unchanged: ${projectItems.docs.length}`); // Should be 5
```

### 6. Already Archived Space

**Setup:**
1. Create a space that is already archived (isArchived = true)
2. Update some other field on the space (e.g., name)

**Expected Behavior:**
- Cloud Function should NOT trigger cleanup
- No items should be updated
- Function should exit early (logs show skip)

**Verification:**
Check Cloud Function logs - should NOT see:
```
[onSpaceArchived] Space {spaceId} archived, clearing items...
```

### 7. Un-archiving a Space

**Setup:**
1. Create a space and archive it (isArchived = true)
2. Some items have spaceId cleared
3. Un-archive the space (set isArchived = false)

**Expected Behavior:**
- Cloud Function should NOT re-assign items
- Items remain with spaceId = null
- Function should exit early (not a delete operation)

**Verification:**
- Items should still have `spaceId = null`
- Cloud Function logs should not show cleanup activity

### 8. Multiple Batches (500+ items)

**Setup:**
1. Create a space in a project
2. Create 1200 items assigned to that space
3. Soft delete the space

**Expected Behavior:**
- All 1200 items should have spaceId cleared
- Cloud Function should create 3 batches (500 + 500 + 200)
- All batches should commit successfully
- Logs should show batch count

**Verification:**
```typescript
const itemsRef = db.collection(`accounts/${accountId}/items`)
  .where('projectId', '==', projectId);

const snapshot = await itemsRef.get();
const stillAssigned = snapshot.docs.filter(doc => doc.data().spaceId === spaceId);

console.log(`Items still assigned: ${stillAssigned.length}`); // Should be 0
console.log(`Total items updated: ${snapshot.docs.length}`); // Should be 1200
```

Check logs for:
```
[onSpaceArchived] Committing 3 batch(es) for space {spaceId}
```

### 9. Error Handling - Network Failure

**Setup:**
1. Simulate network failure or Firestore unavailability during batch commit
2. Soft delete a space with items

**Expected Behavior:**
- Cloud Function should catch the error
- Error should be logged but not thrown
- Space deletion should still succeed
- Items may retain invalid spaceId references

**Verification:**
Check logs for:
```
[onSpaceArchived] Failed to clear items for space {spaceId}: {error message}
```

### 10. Timestamp Updates

**Setup:**
1. Create a space with items
2. Note the current `updatedAt` timestamp on items
3. Soft delete the space
4. Wait for cleanup to complete

**Expected Behavior:**
- All items should have `updatedAt` timestamp refreshed
- New timestamp should be within 2-3 seconds of space deletion

**Verification:**
```typescript
const itemsRef = db.collection(`accounts/${accountId}/items`)
  .where('projectId', '==', projectId)
  .where('spaceId', '==', null);

const snapshot = await itemsRef.get();
snapshot.docs.forEach(doc => {
  const data = doc.data();
  const updatedAt = data.updatedAt?.toDate();
  console.log(`Item ${doc.id} updated at: ${updatedAt}`);
  // Should be recent (within last few seconds)
});
```

## Manual Testing Steps

### Prerequisites
1. Firebase Functions emulator running OR deployed functions
2. Test account with projects and business inventory
3. Firestore access to verify data

### Test Execution

1. **Deploy the function:**
   ```bash
   cd firebase/functions
   npm run build
   firebase deploy --only functions:onSpaceArchived
   ```

2. **Monitor logs:**
   ```bash
   firebase functions:log --only onSpaceArchived
   ```

3. **Create test data:**
   ```typescript
   // In your app or via Firebase console
   const spaceId = await createSpace(accountId, {
     name: 'Test Space',
     notes: 'For cleanup testing',
     projectId: 'test-project-id'
   });

   // Create items assigned to space
   for (let i = 0; i < 10; i++) {
     await createItem(accountId, {
       name: `Test Item ${i}`,
       projectId: 'test-project-id',
       spaceId: spaceId
     });
   }
   ```

4. **Trigger the function:**
   ```typescript
   // Soft delete the space
   await deleteSpace(accountId, spaceId);
   // This sets isArchived = true, triggering the function
   ```

5. **Verify cleanup:**
   ```typescript
   // Wait 2-3 seconds, then check items
   const items = await db.collection(`accounts/${accountId}/items`)
     .where('projectId', '==', 'test-project-id')
     .get();

   items.docs.forEach(doc => {
     const data = doc.data();
     console.log(`Item ${doc.id}: spaceId = ${data.spaceId}`);
     // Should be null for all items
   });
   ```

## Integration with Existing Tests

If you have existing integration tests for spaces, add these assertions:

```typescript
describe('Space Deletion Cleanup', () => {
  it('should clear spaceId from items when space is archived', async () => {
    // Create space
    const spaceId = await spacesService.createSpace(accountId, {
      name: 'Test Space',
      projectId: testProjectId
    });

    // Create items
    const itemIds = await Promise.all([
      itemsService.createItem(accountId, { name: 'Item 1', projectId: testProjectId, spaceId }),
      itemsService.createItem(accountId, { name: 'Item 2', projectId: testProjectId, spaceId })
    ]);

    // Delete space (soft delete)
    await spacesService.deleteSpace(accountId, spaceId);

    // Wait for Cloud Function to execute
    await new Promise(resolve => setTimeout(resolve, 3000));

    // Verify items were updated
    for (const itemId of itemIds) {
      const item = await itemsService.getItem(accountId, itemId);
      expect(item.spaceId).toBeNull();
    }
  });

  it('should not affect items in other projects', async () => {
    // Similar to Test Scenario 4
    // ...
  });
});
```

## Performance Benchmarks

| Item Count | Expected Duration | Batch Count |
|------------|------------------|-------------|
| 0          | < 1 second       | 0           |
| 1-10       | 1-2 seconds      | 1           |
| 100        | 2-3 seconds      | 1           |
| 500        | 3-5 seconds      | 1           |
| 1000       | 5-8 seconds      | 2           |
| 5000       | 20-30 seconds    | 10          |

## Troubleshooting

### Function Not Triggering
- Check that the space document path matches: `accounts/{accountId}/spaces/{spaceId}`
- Verify `isArchived` field changed from `false` to `true`
- Check Firebase Console Functions logs for errors

### Items Not Updating
- Verify items have matching `spaceId` and `projectId`
- Check Firestore indexes (may need composite index for queries)
- Look for batch commit errors in logs

### Partial Updates
- If some items update but not all, check for batch size issues
- Verify no concurrent updates are happening
- Check for Firestore quota limits

## Success Criteria

Phase 6 is complete when:
- ✅ Cloud Function deploys without errors
- ✅ All 10 test scenarios pass
- ✅ Cross-workspace isolation works correctly
- ✅ Large batches (500+) complete successfully
- ✅ Performance benchmarks are met
- ✅ Error handling prevents data loss
- ✅ Logs provide clear debugging information
