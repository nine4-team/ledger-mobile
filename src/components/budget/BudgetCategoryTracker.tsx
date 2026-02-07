import React, { useMemo } from "react";
import { StyleSheet, View, TouchableOpacity, Platform, ActionSheetIOS, Alert } from "react-native";

import {
  getBudgetProgressColor,
  getOverflowColor,
} from "../../utils/budgetColors";
import { useThemeContext } from "../../theme/ThemeProvider";
import { AppText } from "../AppText";

export type BudgetCategoryTrackerProps = {
  categoryName: string;
  categoryType: "general" | "itemized" | "fee";
  spentCents: number;
  budgetCents: number | null;
  isPinned?: boolean;
  onPress?: () => void;
  onLongPress?: () => void;
  isOverallBudget?: boolean;
};

function formatCents(cents: number): string {
  const dollars = Math.abs(cents) / 100;
  return `$${dollars.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`;
}

function getDisplayName(
  categoryName: string,
  categoryType: "general" | "itemized" | "fee",
  isOverallBudget: boolean,
): string {
  if (isOverallBudget) return "Overall Budget";
  if (categoryType === "fee") return categoryName;
  return `${categoryName} Budget`;
}

export function BudgetCategoryTracker({
  categoryName,
  categoryType,
  spentCents,
  budgetCents,
  isPinned = false,
  onPress,
  onLongPress,
  isOverallBudget = false,
}: BudgetCategoryTrackerProps) {
  const { theme, resolvedColorScheme } = useThemeContext();
  const isDark = resolvedColorScheme === "dark";

  const displayName = useMemo(
    () => getDisplayName(categoryName, categoryType, isOverallBudget),
    [categoryName, categoryType, isOverallBudget],
  );

  const percentage = useMemo(() => {
    if (budgetCents === null || budgetCents === 0) return 0;
    return (spentCents / budgetCents) * 100;
  }, [spentCents, budgetCents]);

  const isFeeCategory = categoryType === "fee";
  const isOverBudget = budgetCents !== null && spentCents > budgetCents;
  const overflowPercentage = isOverBudget
    ? ((spentCents - budgetCents) / budgetCents) * 100
    : 0;
  const displayPercentage = Math.min(percentage, 100);

  const colors = useMemo(
    () => getBudgetProgressColor(percentage, isFeeCategory, isDark),
    [percentage, isFeeCategory, isDark],
  );

  const overflowColors = useMemo(() => getOverflowColor(isDark), [isDark]);

  const spentLabel = isFeeCategory
    ? `${formatCents(spentCents)} received`
    : `${formatCents(spentCents)} spent`;

  const remainingLabel = useMemo(() => {
    if (budgetCents === null) return "No budget set";
    const remaining = budgetCents - spentCents;
    const isOver = spentCents > budgetCents;
    if (isFeeCategory) {
      return isOver
        ? `${formatCents(Math.abs(remaining))} over received`
        : `${formatCents(remaining)} remaining`;
    }
    return isOver
      ? `${formatCents(Math.abs(remaining))} over`
      : `${formatCents(remaining)} remaining`;
  }, [budgetCents, spentCents, isFeeCategory]);

  const remainingColor = budgetCents === null
    ? theme.colors.textSecondary
    : isOverBudget
      ? overflowColors.text
      : colors.text;

  const trackBg = isDark ? "#3A3A3C" : "#E5E7EB";

  const content = (
    <View style={styles.container}>
      {/* Title */}
      <View style={styles.titleRow}>
        <AppText variant="body" style={[styles.title, { color: theme.colors.text }]}>
          {displayName}
        </AppText>
        {isPinned && (
          <AppText variant="caption" style={styles.pinIndicator}>
            📌
          </AppText>
        )}
      </View>

      {/* Amounts: spent (left) / remaining (right) */}
      <View style={styles.amountRow}>
        <AppText
          variant="caption"
          style={[styles.amountText, { color: theme.colors.textSecondary }]}
        >
          {spentLabel}
        </AppText>
        <AppText
          variant="caption"
          style={[
            styles.remainingText,
            { color: remainingColor },
            isOverBudget && styles.overBudgetText,
          ]}
        >
          {remainingLabel}
        </AppText>
      </View>

      {/* Progress Bar */}
      <View style={[styles.progressTrack, { backgroundColor: trackBg }]}>
        <View
          style={[
            styles.progressFill,
            {
              width: `${displayPercentage}%`,
              backgroundColor: colors.bar,
            },
          ]}
        />
        {isOverBudget && (
          <View
            style={[
              styles.overflowIndicator,
              {
                width: `${Math.min(overflowPercentage, 100)}%`,
                backgroundColor: overflowColors.bar,
              },
            ]}
          />
        )}
      </View>
    </View>
  );

  if (onPress || onLongPress) {
    return (
      <TouchableOpacity
        onPress={onPress}
        onLongPress={() => {
          if (!onLongPress) return;

          if (Platform.OS === 'ios') {
            ActionSheetIOS.showActionSheetWithOptions(
              {
                options: [isPinned ? 'Unpin' : 'Pin to Top', 'Cancel'],
                cancelButtonIndex: 1,
              },
              (buttonIndex) => {
                if (buttonIndex === 0) onLongPress();
              }
            );
          } else {
            Alert.alert(
              isPinned ? 'Unpin category?' : 'Pin category?',
              '',
              [
                { text: 'Cancel', style: 'cancel' },
                { text: isPinned ? 'Unpin' : 'Pin', onPress: onLongPress }
              ]
            );
          }
        }}
        activeOpacity={0.7}
        style={styles.pressable}
      >
        {content}
      </TouchableOpacity>
    );
  }

  return content;
}

const styles = StyleSheet.create({
  pressable: {
    borderRadius: 8,
  },
  container: {
    gap: 4,
  },
  titleRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  title: {
    fontSize: 15,
    fontWeight: "500",
  },
  pinIndicator: {
    fontSize: 14,
  },
  amountRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  amountText: {
    fontSize: 13,
  },
  remainingText: {
    fontSize: 13,
  },
  overBudgetText: {
    fontWeight: "700",
  },
  progressTrack: {
    height: 8,
    borderRadius: 9999,
    overflow: "hidden",
    position: "relative",
  },
  progressFill: {
    position: "absolute",
    left: 0,
    top: 0,
    height: "100%",
    borderRadius: 9999,
  },
  overflowIndicator: {
    position: "absolute",
    right: 0,
    top: 0,
    height: "100%",
    borderRadius: 9999,
  },
});
