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

  useEffect(() => {
    orderedRef.current = ordered;
  }, [ordered]);

  useEffect(() => {
    setOrdered(bubbleNonDraggableToEnd(items));
  }, [items]);

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

  // Sync / animate positions whenever order changes.
  useEffect(() => {
    const activeId = activeIdRef.current;

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
      onReorder?.(orderedRef.current);
      return;
    }

    Animated.spring(v, { toValue: index * itemHeight, useNativeDriver: false, tension: 220, friction: 28 }).start(() => {
      activeIdRef.current = null;
      setActiveId(null);
      setDragging(false);
      onReorder?.(bubbleNonDraggableToEnd(orderedRef.current));
    });
  };

  const containerHeight = ordered.length * itemHeight;

  return (
    <View style={[styles.container, { height: containerHeight }, style]} accessibilityRole="none">
      {ordered.map((item, index) => {
        const id = getItemId(item);
        const isActive = id === activeId;
        const top = positions.get(id) ?? new Animated.Value(index * itemHeight);

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
            style={[
              styles.itemContainer,
              {
                top,
                height: itemHeight,
                zIndex: isActive ? 10 : 0,
                elevation: isActive ? 10 : 0,
                opacity: isActive ? 0.98 : 1,
                transform: [{ scale: isActive ? 1.01 : 1 }],
              },
            ]}
            pointerEvents={activeId && !isActive ? 'none' : 'auto'}
          >
            {renderItem({ item, index, isActive, dragHandleProps })}
          </Animated.View>
        );
      })}
    </View>
  );
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

