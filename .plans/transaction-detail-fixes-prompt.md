# Transaction Detail Screen Fixes

## Task

Fix three issues in `app/transactions/[id]/index.tsx`:

### 1. Replace warning icon with "Needs Review" badge

In the audit section header (lines 1151-1183), replace the red warning icon with a badge matching `TransactionCard.tsx` (lines 304-318):

- Import `Text` from react-native
- Replace the `MaterialIcons` warning (lines 1172-1179) with:
  ```tsx
  <View style={styles.reviewBadge}>
    <Text style={styles.reviewBadgeText} numberOfLines={1}>
      Needs Review
    </Text>
  </View>
  ```
- Add to styles (replace `warningIcon` at line 1604):
  ```tsx
  reviewBadge: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: 1,
    maxWidth: 160,
    marginLeft: 'auto',
    backgroundColor: '#b9452014',
    borderColor: '#b9452033',
  },
  reviewBadgeText: {
    fontSize: 12,
    fontWeight: '600',
    lineHeight: 16,
    color: '#b94520',
  },
  ```

### 2. Fix sticky headers

Line 1290: Change `stickySectionHeadersEnabled={true}` to `false`

Only the items toolbar should stick, not all section headers. The current `true` value makes all headers sticky when scrolling.

### 3. Reduce section spacing

Line 1477: Change `gap: 18` to `gap: 10`

Reduces excessive vertical space between section titles and content.

## Test

- Badge appears when `transaction.needsReview === true`, matches TransactionCard styling
- Section headers no longer stick when scrolling
- Spacing between titles and content is tighter
