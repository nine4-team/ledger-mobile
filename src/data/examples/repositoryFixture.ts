import { createRepository } from '@/data/repository';
import { ScopedListenerManager } from '@/data/listenerManager';

type ExampleItem = {
  id: string;
  title: string;
  updatedAtMs?: number;
};

export function createExampleRepository() {
  return createRepository<ExampleItem>('examples/items', 'offline');
}

export function exampleSubscriptions() {
  const repo = createExampleRepository();

  const unsubscribeDoc = repo.subscribe('example-id', () => {});
  const unsubscribeList = repo.subscribeList(() => {});

  return () => {
    unsubscribeDoc();
    unsubscribeList();
  };
}

/**
 * Example: Using scoped listener manager for lifecycle-aware listeners
 */
export function exampleScopedListeners() {
  const manager = new ScopedListenerManager();
  const scopeId = 'example:scope-123';
  const repo = createExampleRepository();

  // Attach listeners for a scope
  manager.attach(scopeId, () => {
    return repo.subscribeList((items) => {
      console.log('Items updated:', items);
    });
  });

  manager.attach(scopeId, () => {
    return repo.subscribe('example-id', (item) => {
      console.log('Item updated:', item);
    });
  });

  // Detach when done (e.g., navigating away)
  // manager.detach(scopeId);

  // Or remove entirely
  // manager.remove(scopeId);

  // Cleanup all listeners
  return () => {
    manager.cleanup();
  };
}
