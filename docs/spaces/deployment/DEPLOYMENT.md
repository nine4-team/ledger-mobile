# Space Deletion Cleanup Function - Deployment Guide

## Overview
The `onSpaceArchived` Cloud Function automatically clears `item.spaceId` fields when a space is soft-deleted (archived). This ensures items don't retain references to deleted spaces.

## Function Details

**Trigger:** Firestore document update
- **Path:** `accounts/{accountId}/spaces/{spaceId}`
- **Event:** `onDocumentUpdated`

**Behavior:**
- Detects when `isArchived` changes from `false` to `true`
- Queries all items with matching `spaceId` and `projectId`
- Clears `spaceId` field in batches (handles 500+ items)
- Updates `updatedAt` timestamp on each item

## Deployment

### 1. Build the Functions

```bash
cd firebase/functions
npm run build
```

This compiles TypeScript to JavaScript in the `lib/` directory.

### 2. Deploy Only the Space Cleanup Function

```bash
firebase deploy --only functions:onSpaceArchived
```

### 3. Deploy All Functions

```bash
firebase deploy --only functions
```

### 4. Verify Deployment

Check the Firebase Console:
- Go to Functions section
- Look for `onSpaceArchived` function
- Status should be "Active"

## Testing with Emulator

### Start the Emulator

```bash
cd firebase/functions
npm run serve
```

This starts the Firebase Functions emulator with Firestore.

### Connect App to Emulator

In your app, configure Firebase to use the emulator:

```typescript
// firebase/firebase.ts
if (__DEV__) {
  firestore().useEmulator('localhost', 8080);
  functions().useEmulator('localhost', 5001);
}
```

### Test the Function

1. Create a space with items
2. Soft delete the space (set `isArchived = true`)
3. Check emulator logs in terminal
4. Verify items have `spaceId = null`

## Monitoring

### View Function Logs

```bash
# All functions
firebase functions:log

# Just the space cleanup function
firebase functions:log --only onSpaceArchived

# Follow logs in real-time
firebase functions:log --only onSpaceArchived --follow
```

### Expected Log Messages

**Success:**
```
[onSpaceArchived] Space abc123 archived, clearing items...
[onSpaceArchived] Found 25 items to update for space abc123
[onSpaceArchived] Committing 1 batch(es) for space abc123
[onSpaceArchived] Successfully cleared spaceId from 25 items for space abc123
```

**No Items:**
```
[onSpaceArchived] No items found for space abc123
```

**Error:**
```
[onSpaceArchived] Failed to clear items for space abc123: {error message}
```

## Performance Considerations

### Batch Limits
- Firestore batch limit: 500 operations
- Function automatically handles batching
- Large spaces (500+ items) may take several seconds

### Timeout
- Default Cloud Function timeout: 60 seconds
- Should be sufficient for spaces with up to ~10,000 items
- If you have larger spaces, increase timeout in function config

### Cost
- Each function invocation costs based on:
  - Execution time
  - Memory used
  - Number of Firestore reads/writes
- Typical cost: < $0.01 per space deletion with 100 items

## Troubleshooting

### Function Not Triggering

**Check 1:** Verify the document path
```
Expected: accounts/{accountId}/spaces/{spaceId}
```

**Check 2:** Verify `isArchived` field exists and changes
```typescript
// Before update
{ isArchived: false }

// After update
{ isArchived: true }
```

**Check 3:** Check function deployment
```bash
firebase functions:list
```

### Items Not Updating

**Check 1:** Verify items have matching `spaceId`
```typescript
const items = await db.collection(`accounts/${accountId}/items`)
  .where('spaceId', '==', spaceId)
  .get();
console.log(`Found ${items.docs.length} items with spaceId`);
```

**Check 2:** Check Firestore indexes
The function queries items by `spaceId` and `projectId`. You may need a composite index:

```
Collection: items
Fields:
  - spaceId (Ascending)
  - projectId (Ascending)
```

Firebase will show an index creation link in the error logs if needed.

**Check 3:** Check function logs for errors
```bash
firebase functions:log --only onSpaceArchived
```

### Partial Updates

If only some items update:
1. Check for concurrent updates (other code modifying items)
2. Verify batch commit succeeded (check logs)
3. Check Firestore quotas (may be throttled)

### Performance Issues

If cleanup takes too long:
1. Reduce number of items per space
2. Increase function timeout
3. Consider pagination for very large spaces (>1000 items)

## Rollback

If you need to rollback the function:

```bash
# Deploy previous version
firebase deploy --only functions:onSpaceArchived

# Or disable the function
firebase functions:delete onSpaceArchived
```

**Note:** Disabling the function won't cause errors, but items won't be cleaned up automatically. You'll need to manually clear `spaceId` fields.

## Production Checklist

Before deploying to production:

- [ ] Test with emulator
- [ ] Test with 0, 1, 10, 100, 500+ items
- [ ] Test cross-workspace isolation (project vs BI)
- [ ] Verify logs show success/failure
- [ ] Check Firestore indexes created
- [ ] Monitor function costs for 24 hours
- [ ] Set up alerting for function errors
- [ ] Document for team

## Security & Permissions

The function runs with Firebase Admin SDK privileges:
- Can read/write all items in the account
- Scoped by `accountId` from document path
- No additional authentication needed
- Respects Firestore security rules for client access

## Future Enhancements

Potential improvements (not in Phase 6 scope):
- Add retry logic for failed batch commits
- Send notification to user when cleanup completes
- Archive lineage edges when space is deleted
- Support for "undo" space deletion (restore spaceId)
