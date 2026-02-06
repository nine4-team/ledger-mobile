/* eslint-disable react-hooks/refs */
import React, { useEffect, useRef, useState } from 'react';
import { Animated, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';

type Id = string;

export type DraggableCardListRenderItemInfo<TItem> = {
  item: TItem;
  index: number;
  isActive: boolean;
  dragHandleProps: Record<string, unknown>;
};

export type DraggableCardListProps<TItem> = {
  items: TItem[];
  getItemId: (item: TItem) => string;
  itemHeight: number;
  renderItem: (info: DraggableCardListRenderItemInfo<TItem>) => React.ReactNode;
  onReorder?: (nextItems: TItem[]) => void;
  /**
   * Optional hook for parent containers (e.g. ScrollView) to disable scrolling
   * while the user is dragging.
   */
  onDragActiveChange?: (isDragging: boolean) => void;
  /**
   * If provided, items where this returns false are treated as "not draggable".
   * They will be kept at the bottom and cannot be reordered via dragging.
   */
  isItemDraggable?: (item: TItem) => boolean;
  disabled?: boolean;
  style?: ViewStyle;
};

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

function move<T>(arr: T[], from: number, to: number) {
  const next = arr.slice();
  const [removed] = next.splice(from, 1);
  next.splice(to, 0, removed);
  return next;
}

function stablePartition<T>(arr: T[], predicate: (item: T) => boolean) {
  const yes: T[] = [];
  const no: T[] = [];
  for (const item of arr) {
    if (predicate(item)) yes.push(item);
    else no.push(item);
  }
  return yes.concat(no);
}

function areIdsEqual(a: Id[], b: Id[]) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i += 1) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function areItemsEqual<T>(a: T[], b: T[]) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i += 1) {
    if (JSON.stringify(a[i]) !== JSON.stringify(b[i])) return false;
  }
  return true;
}

function haveSameIdSet(a: Id[], b: Id[]) {
  if (a.length !== b.length) return false;
  const setA = new Set(a);
  if (setA.size !== a.length) return false;
  for (const id of b) {
    if (!setA.has(id)) return false;
  }
  return true;
}

export function DraggableCardList<TItem>({
  items,
  getItemId,
  itemHeight,
  renderItem,
  onReorder,
  onDragActiveChange,
  isItemDraggable,
  disabled = false,
  style,
}: DraggableCardListProps<TItem>) {
  const canDragItem = (item: TItem) => (isItemDraggable ? isItemDraggable(item) : true);
  const bubbleNonDraggableToEnd = (arr: TItem[]) => stablePartition(arr, canDragItem);

  const [ordered, setOrdered] = useState<TItem[]>(items);
  const orderedRef = useRef(ordered);
  const pendingOrderRef = useRef<Id[] | null>(null);
  const ignoreNextAnimationRef = useRef(false);

  useEffect(() => {
    orderedRef.current = ordered;
  }, [ordered]);

  useEffect(() => {
    const nextOrdered = bubbleNonDraggableToEnd(items);
    
    // Optimization: If the incoming items match our current state exactly (order and content),
    // skip the update. This prevents re-renders that can cause visual glitches (like shrinking/flickering)
    // when the backend syncs back the state we just optimisticly updated.
    if (areItemsEqual(nextOrdered, ordered)) {
      // Even if items are equal, we might need to clear the pending flag if it matches.
      // (e.g. we dragged, set pending, and now backend confirmed it)
      const nextIds = nextOrdered.map(getItemId);
      if (pendingOrderRef.current && areIdsEqual(nextIds, pendingOrderRef.current)) {
        pendingOrderRef.current = null;
      }
      return;
    }

    const nextIds = nextOrdered.map(getItemId);
    const pendingIds = pendingOrderRef.current;
    if (pendingIds) {
      if (areIdsEqual(nextIds, pendingIds)) {
        pendingOrderRef.current = null;
        // If IDs match pending, and we didn't return above, it means content differs.
        // We must update.
        ignoreNextAnimationRef.current = true;
        setOrdered(nextOrdered);
        return;
      }
      if (haveSameIdSet(nextIds, pendingIds)) {
        return;
      }
      pendingOrderRef.current = null;
    }
    setOrdered(nextOrdered);
  }, [items, getItemId]);

  const [positions, setPositions] = useState<Map<Id, Animated.Value>>(() => {
    const m = new Map<Id, Animated.Value>();
    items.forEach((it, idx) => {
      m.set(getItemId(it), new Animated.Value(idx * itemHeight));
    });
    return m;
  });

  const activeIdRef = useRef<Id | null>(null);
  const activeStartTopRef = useRef(0);
  const gestureStartPageYRef = useRef(0);
  const draggingRef = useRef(false);

  const prevIdsRef = useRef<Id[]>(ordered.map(getItemId));

  // Sync / animate positions whenever order changes.
  useEffect(() => {
    const activeId = activeIdRef.current;
    
    // Check if the order actually changed to avoid restarting animations
    // when only item content changed but position is same.
    const currentIds = ordered.map(getItemId);
    const orderChanged = !areIdsEqual(currentIds, prevIdsRef.current);
    
    if (ignoreNextAnimationRef.current) {
      ignoreNextAnimationRef.current = false;
      prevIdsRef.current = currentIds;
      return;
    }

    prevIdsRef.current = currentIds;

    setPositions((prev) => {
      let changed = false;
      const next = new Map(prev);
      const ids = new Set<Id>();

      ordered.forEach((it, idx) => {
        const id = getItemId(it);
        ids.add(id);
        if (!next.has(id)) {
          next.set(id, new Animated.Value(idx * itemHeight));
          changed = true;
        }
      });

      for (const id of next.keys()) {
        if (!ids.has(id)) {
          next.delete(id);
          changed = true;
        }
      }

      // Animate non-active items into position.
      ordered.forEach((it, idx) => {
        const id = getItemId(it);
        if (id === activeId) return;
        const v = next.get(id);
        if (!v) return;
        
        // Skip animation if the order of IDs hasn't changed.
        // This prevents "microadjustments" when the backend syncs the same order back.
        if (!orderChanged && !changed) {
          // Ensure it's at the right spot though (in case of initialization or slight drift?)
          // Actually, if we skip, we trust it's already there.
          // But if we just mounted, 'changed' would be true (new values added).
          return;
        }

        Animated.spring(v, {
          toValue: idx * itemHeight,
          useNativeDriver: false,
          tension: 220,
          friction: 28,
        }).start();
      });

      return changed ? next : prev;
    });
  }, [ordered, getItemId, itemHeight]);

  const [activeId, setActiveId] = useState<Id | null>(null);

  const setDragging = (next: boolean) => {
    if (draggingRef.current === next) return;
    draggingRef.current = next;
    onDragActiveChange?.(next);
  };

  const startDrag = (id: Id) => {
    if (disabled) return;
    const current = orderedRef.current;
    const index = current.findIndex((it) => getItemId(it) === id);
    if (index < 0) return;
    if (!canDragItem(current[index]!)) return;

    activeIdRef.current = id;
    setActiveId(id);
    setDragging(true);
    activeStartTopRef.current = index * itemHeight;
    positions.get(id)?.setValue(index * itemHeight);
  };

  const updateDrag = (dy: number) => {
    const id = activeIdRef.current;
    if (!id) return;
    const current = orderedRef.current;
    const currentIndex = current.findIndex((it) => getItemId(it) === id);
    if (currentIndex < 0) return;

    // Clamp within draggable region only (non-draggable items are pinned to the bottom).
    let lastDraggableIndex = -1;
    for (let i = current.length - 1; i >= 0; i--) {
      if (canDragItem(current[i]!)) {
        lastDraggableIndex = i;
        break;
      }
    }
    lastDraggableIndex = Math.max(0, lastDraggableIndex);
    
    const maxTop = lastDraggableIndex * itemHeight;
    const nextTop = clamp(activeStartTopRef.current + dy, 0, maxTop);
    positions.get(id)?.setValue(nextTop);

    const nextIndex = clamp(Math.floor((nextTop + itemHeight / 2) / itemHeight), 0, lastDraggableIndex);
    if (nextIndex !== currentIndex) {
      setOrdered((prev) => {
        const prevIndex = prev.findIndex((it) => getItemId(it) === id);
        if (prevIndex < 0) return prev;
        const moved = move(prev, prevIndex, nextIndex);
        return bubbleNonDraggableToEnd(moved);
      });
    }
  };

  const endDrag = () => {
    const id = activeIdRef.current;
    if (!id) return;
    const current = orderedRef.current;
    const index = current.findIndex((it) => getItemId(it) === id);
    if (index < 0) {
      activeIdRef.current = null;
      setActiveId(null);
      setDragging(false);
      return;
    }

    const v = positions.get(id);
    if (!v) {
      activeIdRef.current = null;
      setActiveId(null);
      setDragging(false);
      pendingOrderRef.current = orderedRef.current.map(getItemId);
      onReorder?.(orderedRef.current);
      return;
    }

    Animated.spring(v, { toValue: index * itemHeight, useNativeDriver: false, tension: 220, friction: 28 }).start(() => {
      activeIdRef.current = null;
      setActiveId(null);
      setDragging(false);
      const nextOrder = bubbleNonDraggableToEnd(orderedRef.current);
      pendingOrderRef.current = nextOrder.map(getItemId);
      onReorder?.(nextOrder);
    });
  };

  const containerHeight = ordered.length * itemHeight;

  const containerHeightStyle = { height: containerHeight };

  return (
    <View style={[styles.container, containerHeightStyle, style]} accessibilityRole="none">
      {ordered.map((item, index) => {
        const id = getItemId(item);
        const isActive = id === activeId;
        const top = positions.get(id) ?? new Animated.Value(index * itemHeight);
        const itemDynamicStyle = getItemDynamicStyle(top, itemHeight, isActive);

        const dragHandleProps: Record<string, unknown> = disabled || !canDragItem(item)
          ? {}
          : {
              // Make the handle a reliable responder target even inside a ScrollView.
              onStartShouldSetResponder: () => true,
              onMoveShouldSetResponder: () => true,
              onStartShouldSetResponderCapture: () => true,
              onMoveShouldSetResponderCapture: () => true,
              onResponderTerminationRequest: () => false,
              onResponderGrant: (e: any) => {
                gestureStartPageYRef.current = e?.nativeEvent?.pageY ?? 0;
                startDrag(id);
              },
              onResponderMove: (e: any) => {
                const pageY = e?.nativeEvent?.pageY ?? gestureStartPageYRef.current;
                updateDrag(pageY - gestureStartPageYRef.current);
              },
              onResponderRelease: endDrag,
              onResponderTerminate: endDrag,
            };

        return (
          <Animated.View
            key={id}
            style={[styles.itemContainer, itemDynamicStyle]}
            pointerEvents={activeId && !isActive ? 'none' : 'auto'}
          >
            {renderItem({ item, index, isActive, dragHandleProps })}
          </Animated.View>
        );
      })}
    </View>
  );
}

function getItemDynamicStyle(top: Animated.Value, itemHeight: number, isActive: boolean) {
  return {
    top,
    height: itemHeight,
    zIndex: isActive ? 10 : 0,
    elevation: isActive ? 10 : 0,
    opacity: isActive ? 0.98 : 1,
    transform: [{ scale: isActive ? 1.01 : 1 }],
  };
}

const styles = StyleSheet.create({
  container: {
    position: 'relative',
    width: '100%',
  },
  itemContainer: {
    position: 'absolute',
    left: 0,
    right: 0,
  },
});

