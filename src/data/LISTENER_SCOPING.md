# Listener Scoping Conventions

This document describes conventions for scoping Firestore listeners in offline-ready apps.

## Overview

The scoped listener manager (`ScopedListenerManager`) provides lifecycle-aware listener management for bounded scopes. It automatically detaches listeners when the app goes to background and reattaches them when the app resumes.

## Scope Naming Conventions

Scopes should follow a consistent naming pattern:

### Recommended Patterns

- **Project scope**: `project:{projectId}`
  - Example: `project:abc123`
  - Use for listeners scoped to a specific project

- **Account scope**: `account:{accountId}`
  - Example: `account:user-456`
  - Use for listeners scoped to an account/user

- **Inventory scope**: `inventory:{inventoryId}`
  - Example: `inventory:main`
  - Use for listeners scoped to inventory collections

- **User scope**: `user:{userId}`
  - Example: `user:xyz789`
  - Use for user-specific listeners (profile, settings, etc.)

### Scope Limits

**Recommended limits per scope:**
- **Maximum 5-10 listeners per scope** - Keep scopes focused
- **Maximum 1-2 scopes active at a time** - Avoid unbounded listener growth
- **Detach scopes when navigating away** - Don't accumulate inactive scopes

**Anti-patterns to avoid:**
- ❌ `global:*` - Never create unbounded global listeners
- ❌ `all-projects:*` - Don't listen to all projects at once
- ❌ `all-users:*` - Don't listen to all users at once

## Usage Examples

### Basic Usage with Hook

```typescript
import { useScopedListeners } from '@/data/useScopedListeners';
import { createRepository } from '@/data/repository';

function ProjectScreen({ projectId }: { projectId: string }) {
  const scopeId = `project:${projectId}`;
  const [items, setItems] = useState<Item[]>([]);

  useScopedListeners(scopeId, () => {
    const repo = createRepository<Item>(
      `projects/${projectId}/items`,
      'offline'
    );
    return repo.subscribeList((updatedItems) => {
      setItems(updatedItems);
    });
  });

  return <ItemList items={items} />;
}
```

### Multiple Listeners for One Scope

```typescript
import { useScopedListenersMultiple } from '@/data/useScopedListeners';
import { createRepository } from '@/data/repository';

function ProjectScreen({ projectId }: { projectId: string }) {
  const scopeId = `project:${projectId}`;
  const [items, setItems] = useState<Item[]>([]);
  const [requests, setRequests] = useState<Request[]>([]);

  useScopedListenersMultiple(scopeId, [
    () => {
      const repo = createRepository<Item>(
        `projects/${projectId}/items`,
        'offline'
      );
      return repo.subscribeList((updatedItems) => {
        setItems(updatedItems);
      });
    },
    () => {
      const repo = createRepository<Request>(
        `projects/${projectId}/requests`,
        'offline'
      );
      return repo.subscribeList((updatedRequests) => {
        setRequests(updatedRequests);
      });
    },
  ]);

  return (
    <View>
      <ItemList items={items} />
      <RequestList requests={requests} />
    </View>
  );
}
```

### Manual Management (Advanced)

```typescript
import { ScopedListenerManager } from '@/data/listenerManager';
import { createRepository } from '@/data/repository';

const manager = new ScopedListenerManager();

// Attach listeners
manager.attach('project:123', () => {
  const repo = createRepository('projects/123/items', 'offline');
  return repo.subscribeList((items) => {
    // handle updates
  });
});

// Detach when navigating away
manager.detach('project:123');

// Remove scope entirely
manager.remove('project:123');

// Cleanup on app unmount
manager.cleanup();
```

## Lifecycle Behavior

### App State Transitions

- **Active → Background**: All listeners are automatically detached
- **Background → Active**: All listeners are automatically reattached
- **Component Unmount**: Listeners for that scope are detached (but factories are preserved)

### Best Practices

1. **Scope per screen/feature**: Create a new scope when entering a screen that needs listeners
2. **Clean up on navigation**: Detach or remove scopes when navigating away
3. **Use hooks when possible**: `useScopedListeners` handles cleanup automatically
4. **Monitor listener count**: Use `manager.getListenerCount(scopeId)` for debugging

## Collection Path Conventions

When creating repositories for scoped listeners, use consistent collection paths:

- **Project-scoped**: `projects/{projectId}/items`
- **Account-scoped**: `accounts/{accountId}/items`
- **User-scoped**: `users/{userId}/items`
- **Inventory-scoped**: `accounts/{accountId}/inventory/items`

This aligns with Firestore security rules and makes scoping explicit.

## Debugging

### Check Active Scopes

```typescript
import { globalListenerManager } from '@/data/listenerManager';

const activeScopes = globalListenerManager.getActiveScopes();
console.log('Active scopes:', activeScopes);
```

### Check Listener Count

```typescript
const count = globalListenerManager.getListenerCount('project:123');
console.log(`Listeners for project:123: ${count}`);
```

### Check Attachment Status

```typescript
const isAttached = globalListenerManager.isAttached('project:123');
console.log(`Scope attached: ${isAttached}`);
```
