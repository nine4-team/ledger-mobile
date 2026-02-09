import React from 'react';
import { ScrollView, ScrollViewProps } from 'react-native';
import { StickyHeader } from './StickyHeader';

/**
 * Recursively flattens Fragment children to match ScrollView's internal child indexing.
 * React.Children.toArray does NOT flatten Fragments - it treats them as opaque elements.
 */
function flattenFragments(children: React.ReactNode): React.ReactNode[] {
  const result: React.ReactNode[] = [];
  React.Children.forEach(children, (child) => {
    if (React.isValidElement(child) && child.type === React.Fragment) {
      result.push(...flattenFragments(child.props.children));
    } else {
      result.push(child);
    }
  });
  return result;
}

/**
 * A ScrollView component with mobile-friendly defaults.
 * Hides scrollbars by default to prevent content overlay on mobile devices.
 * Scrollbars will still appear briefly during scrolling on iOS.
 *
 * Auto-detects StickyHeader children and computes stickyHeaderIndices automatically.
 * Explicit stickyHeaderIndices prop takes precedence over auto-detection.
 */
export const AppScrollView = React.forwardRef<ScrollView, ScrollViewProps>(
  ({ showsVerticalScrollIndicator = false, showsHorizontalScrollIndicator = false, children, stickyHeaderIndices, ...props }, ref) => {
    // Flatten Fragment children to match ScrollView's internal indexing
    const flatChildren = React.useMemo(() => flattenFragments(children), [children]);

    // Compute stickyHeaderIndices if not explicitly provided
    const computedIndices = React.useMemo(() => {
      // If explicit indices are provided, use those (backward compatible)
      if (stickyHeaderIndices !== undefined) {
        return stickyHeaderIndices;
      }

      // Auto-detect StickyHeader children
      const indices: number[] = [];

      flatChildren.forEach((child, index) => {
        if (
          React.isValidElement(child) &&
          child.type === StickyHeader
        ) {
          indices.push(index);
        }
      });

      return indices.length > 0 ? indices : undefined;
    }, [flatChildren, stickyHeaderIndices]);

    return (
      <ScrollView
        ref={ref}
        showsVerticalScrollIndicator={showsVerticalScrollIndicator}
        showsHorizontalScrollIndicator={showsHorizontalScrollIndicator}
        stickyHeaderIndices={computedIndices}
        {...props}
      >
        {flatChildren}
      </ScrollView>
    );
  }
);

AppScrollView.displayName = 'AppScrollView';
