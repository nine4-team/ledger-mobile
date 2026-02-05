import React from 'react';
import { ScrollView, ScrollViewProps } from 'react-native';

/**
 * A ScrollView component with mobile-friendly defaults.
 * Hides scrollbars by default to prevent content overlay on mobile devices.
 * Scrollbars will still appear briefly during scrolling on iOS.
 */
export const AppScrollView = React.forwardRef<ScrollView, ScrollViewProps>(
  ({ showsVerticalScrollIndicator = false, showsHorizontalScrollIndicator = false, ...props }, ref) => {
    return (
      <ScrollView
        ref={ref}
        showsVerticalScrollIndicator={showsVerticalScrollIndicator}
        showsHorizontalScrollIndicator={showsHorizontalScrollIndicator}
        {...props}
      />
    );
  }
);

AppScrollView.displayName = 'AppScrollView';
