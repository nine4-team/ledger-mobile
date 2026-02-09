# Subscription Loading Audit - Find "Spinners of Doom"

## Background

**Issue Found:** The edit project screen hung at "Loading project..." for 5-7 seconds on cold start (empty cache).

**Root Causes (both issues were present):**

1. **Missing cache-first reads:** `onSnapshot` waits for server response before first callback, even when cached data exists
2. **The "empty cache" anti-pattern (CRITICAL):** Cache-first reads only called `onChange` if cache was NOT empty:
   ```typescript
   // ❌ ANTI-PATTERN - causes 5-7 sec hang on cold start
   getDocsFromCache(query)
     .then(snapshot => {
       if (!snapshot.empty) {  // <-- THIS IS THE PROBLEM
         onChange(mapData(snapshot));
       }
     })
     .catch(() => {
       // onChange never called, loading stays true
     });
   ```

**Why this is catastrophic:**
- On cold start (empty cache), `onChange` is NEVER called
- Loading states stay `true` indefinitely
- UI waits 5-7+ seconds for `onSnapshot` to get server data
- Violates "no spinners of doom" principle

## Your Task: Comprehensive Audit

Search the entire codebase for similar patterns and violations. Focus on:

### 1. Find the "Empty Cache" Anti-Pattern (HIGHEST PRIORITY)

**This is the #1 cause of loading hangs. Search for:**

```bash
rg "if.*!.*snapshot\.empty" src/data/
rg "if.*snapshot\.exists" src/data/
```

**The Anti-Pattern:**
```typescript
// ❌ BROKEN - onChange only fires if cache is NOT empty
getDocsFromCache(query)
  .then(snapshot => {
    if (!snapshot.empty) {  // <-- REMOVE THIS CHECK
      onChange(mapData(snapshot));
    }
  })
  .catch(() => {}); // <-- Also bad: swallows errors silently
```

**The Fix:**
```typescript
// ✅ CORRECT - onChange ALWAYS fires immediately
getDocsFromCache(query)
  .then(snapshot => {
    // Always call onChange, even with empty array
    onChange(mapData(snapshot));
  })
  .catch(() => {
    // Cache miss: call onChange with empty data so UI renders
    onChange([]);
  });
```

**For single documents:**
```typescript
// ✅ CORRECT - onChange ALWAYS fires
getDocFromCache(docRef)
  .then(snapshot => {
    onChange(snapshot.exists ? mapData(snapshot) : null);
  })
  .catch(() => {
    onChange(null); // Let UI render with no data
  });
```

### 2. Find All `onSnapshot` Usages

**Search Pattern:**
```bash
rg "onSnapshot" -t ts -t tsx src/data/
```

For each `onSnapshot` usage, check:
- ✅ **GOOD:** Cache-first read before `onSnapshot` AND no empty check blocking `onChange`
- ❌ **BAD:** Direct `onSnapshot` without cache-first read
- ❌ **CRITICAL:** Has cache-first read BUT uses `if (!snapshot.empty)` check

### 3. Find Components with Permanent Loading States

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

### 4. Audit Service Files with Subscribe Functions

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

### 5. Check for Awaited Firestore Reads in Load Paths

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

### 6. Review All Screen/Page Loading Patterns

**Screens to audit:**
```bash
find app -name "*.tsx" -type f | grep -E "(index|edit|detail)"
```

For each screen:
- What triggers the initial data load?
- Is there a loading spinner?
- How long could the user stare at "Loading..." with no connectivity?
- Does it show cached data immediately or wait for server?

### 7. Check Conditional Rendering Blocking Patterns

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

**MOST IMPORTANT - Run these first:**

```bash
# 🚨 CRITICAL: Find the "empty cache" anti-pattern
rg "if.*!.*snapshot\.empty" src/data/ -A 3 -B 3
rg "if.*snapshot\.exists.*{" src/data/ -A 3 -B 3

# Find cache reads that might have the anti-pattern
rg "getDocsFromCache|getDocFromCache" src/data/ -A 5
```

**Then run these:**

```bash
# Find all onSnapshot usages
rg "onSnapshot" -t ts -t tsx src/data/

# Find components with loading states
rg "useState.*[Ll]oading.*true" app/

# Find subscribe functions
rg "^export function subscribe" src/data/

# Find screens with conditional loading returns
rg "if.*isLoading.*return" app/ -A 1

# Check for awaited Firestore reads
rg "await.*get[A-Z]" src/ -A 2 -B 2
```

## Quick Reference: The Fix Pattern

**For collections (arrays):**
```typescript
// Cache first
getDocsFromCache(query)
  .then(snapshot => {
    onChange(snapshot.docs.map(mapFn)); // NO if (!snapshot.empty) check
  })
  .catch(() => onChange([])); // Always call onChange

// Then real-time
return onSnapshot(query, snapshot => {
  onChange(snapshot.docs.map(mapFn));
}, onError);
```

**For documents (single):**
```typescript
// Cache first
getDocFromCache(docRef)
  .then(snapshot => {
    onChange(snapshot.exists ? mapData(snapshot) : null); // NO if (snapshot.exists) block
  })
  .catch(() => onChange(null)); // Always call onChange

// Then real-time
return onSnapshot(docRef, snapshot => {
  onChange(snapshot.exists ? mapData(snapshot) : null);
}, onError);
```

Good hunting! 🐛
