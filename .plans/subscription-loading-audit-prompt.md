# Subscription Loading Audit - Find "Spinners of Doom"

## Background

**Issue Found:** The edit project screen (`app/project/[projectId]/edit.tsx`) hung at "Loading project..." with poor connectivity because subscription functions used `onSnapshot` without cache-first reads. The app waited 30+ seconds for server responses instead of showing cached data immediately.

**Root Cause:** `onSnapshot` in React Native Firebase waits for the first server response before firing its callback, even when cached data exists locally. This violates offline-first principles and creates "spinners of doom."

## Your Task: Comprehensive Audit

Search the entire codebase for similar patterns and violations. Focus on:

### 1. Find All `onSnapshot` Usages

**Search Pattern:**
```bash
grep -r "onSnapshot" --include="*.ts" --include="*.tsx" src/
```

For each `onSnapshot` usage, check:
- ✅ **GOOD:** Is there a cache-first read (`getDocFromCache` or `getDocsFromCache`) before the `onSnapshot` call?
- ❌ **BAD:** Does it directly call `onSnapshot` without trying cache first?
- ❌ **BAD:** Is there a loading state that stays `true` until the snapshot callback fires?

### 2. Find Components with Permanent Loading States

**Pattern to look for:**
```typescript
const [isLoading, setIsLoading] = useState(true);

useEffect(() => {
  const unsubscribe = someSubscribeFunction((data) => {
    setData(data);
    setIsLoading(false); // ❌ Only turns off when callback fires
  });
  return unsubscribe;
}, []);

if (isLoading) return <LoadingSpinner />; // ❌ Blocks until server responds
```

**Search for files that:**
- Import `onSnapshot` from Firebase
- Have loading states initialized to `true`
- Return early with loading UI before data is ready
- Use subscription functions from service files

### 3. Audit Service Files with Subscribe Functions

**Files to check:**
- `src/data/repository.ts` - Already fixed ✅
- `src/data/projectBudgetCategoriesService.ts` - Already fixed ✅
- `src/data/budgetCategoriesService.ts` - Already fixed ✅
- `src/data/transactionsService.ts` - CHECK THIS
- `src/data/projectsService.ts` - CHECK THIS
- `src/data/itemsService.ts` - CHECK THIS
- `src/data/accountsService.ts` - CHECK THIS
- Any other files in `src/data/` with `subscribe*` functions

For each subscribe function:
1. Does it use `onSnapshot`?
2. Does it attempt a cache-first read before setting up the listener?
3. Would poor connectivity cause the caller to hang?

### 4. Check for Awaited Firestore Reads in Load Paths

**Pattern to look for:**
```typescript
// ❌ BAD: Awaited read blocks UI
const loadProject = async () => {
  setIsLoading(true);
  const project = await getProject(id); // Blocks on server
  setProject(project);
  setIsLoading(false);
};
```

**Search strategy:**
- Find `async` functions that set loading state
- Look for `await get*` calls to Firestore service functions
- Check if those get functions use `mode: 'offline'` (cache-first)
- Verify no blocking server reads in initial load paths

### 5. Review All Screen/Page Loading Patterns

**Screens to audit:**
```bash
find app -name "*.tsx" -type f | grep -E "(index|edit|detail)"
```

For each screen:
- What triggers the initial data load?
- Is there a loading spinner?
- How long could the user stare at "Loading..." with no connectivity?
- Does it show cached data immediately or wait for server?

### 6. Check Conditional Rendering Blocking Patterns

**Pattern:**
```typescript
if (isLoadingA || isLoadingB || isLoadingC) {
  return <Text>Loading...</Text>; // ❌ All three must complete
}
```

This is especially problematic when ALL conditions must be false before showing content. One slow subscription hangs the entire screen.

## Offline-First Principles (Reference)

From `CLAUDE.md`:

> 1. **Never `await` Firestore write operations in UI code.** Use fire-and-forget with `.catch()`
> 2. **All `create*` service functions must return document IDs synchronously**
> 3. **Read operations in save/submit handlers must use cache-first mode** (`mode: 'offline'`)
> 4. **No "spinners of doom"** — never show loading states that block on server acknowledgment
> 5. **Only actual byte uploads (Firebase Storage) and Firebase Auth operations may require connectivity**
> 6. **All Firestore write service functions must call `trackPendingWrite()`**

**Focus especially on #4:** "No spinners of doom"

## Deliverables

Create a report with:

### Section 1: All `onSnapshot` Usages
- File path and line number
- Current implementation (cache-first? yes/no)
- Risk level: HIGH (causes loading hang), MEDIUM (could cause issues), LOW (already cache-first)

### Section 2: Screens with Loading State Issues
- Screen path
- What data it loads
- Loading pattern (blocks on server? shows cache?)
- Recommendation (fix now? monitor? ok as-is?)

### Section 3: Service Functions Needing Updates
- Function name and file
- Current pattern
- Recommended fix

### Section 4: Priority Recommendations
Rank the issues by user impact:
1. **Critical:** Screens that commonly hang (like edit project did)
2. **High:** Subscribe functions missing cache-first reads
3. **Medium:** Screens with multiple subscription dependencies
4. **Low:** Edge cases or rarely-used screens

## Test Case to Verify Fixes

After implementing fixes, test with Network Link Conditioner:
1. Enable "100% Loss" network profile
2. Open the app (should show cached data)
3. Navigate to fixed screens (should load instantly from cache)
4. Try editing/creating content (should work offline)
5. Re-enable network (should sync in background)

The user should NEVER see indefinite loading spinners when cached data exists.

---

## Search Commands to Get Started

```bash
# Find all onSnapshot usages
rg "onSnapshot" -t ts -t tsx src/

# Find components with loading states
rg "useState.*Loading.*true" -t ts -t tsx src/

# Find subscribe functions
rg "subscribe.*=.*\(" src/data/

# Find screens with conditional loading returns
rg "if.*isLoading.*return" -t ts -t tsx app/

# Check for awaited Firestore reads
rg "await.*get.*\(" src/ -A 2 -B 2
```

Good hunting! 🐛
