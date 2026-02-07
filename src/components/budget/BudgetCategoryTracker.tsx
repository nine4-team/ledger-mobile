import React, { useMemo } from "react";
import { StyleSheet, View, TouchableOpacity, Platform, ActionSheetIOS, Alert } from "react-native";

import {
  getBudgetProgressColor,
  getOverflowColor,
} from "../../utils/budgetColors";
import { AppText } from "../AppText";

export type BudgetCategoryTrackerProps = {
  /**
   * Category name (e.g., "Furnishings", "Design Fee")
   */
  categoryName: string;

  /**
   * Category type determines display behavior
   * - "general": Standard spending category with "Budget" suffix
   * - "itemized": Itemized spending category with "Budget" suffix
   * - "fee": Fee/income category with no suffix and inverted colors
   */
  categoryType: "general" | "itemized" | "fee";

  /**
   * Amount spent/received in cents
   */
  spentCents: number;

  /**
   * Budget amount in cents
   * If null, shows as "No budget set"
   */
  budgetCents: number | null;

  /**
   * Whether to show a pin indicator
   * @default false
   */
  isPinned?: boolean;

  /**
   * Callback when category is tapped
   */
  onPress?: () => void;

  /**
   * Callback when category is long-pressed (for pin/unpin menu)
   */
  onLongPress?: () => void;

  /**
   * Whether this is the "Overall Budget" synthetic entry
   * @default false
   */
  isOverallBudget?: boolean;
};

/**
 * Format cents to currency string
 */
function formatCents(cents: number): string {
  const dollars = Math.abs(cents) / 100;
  return `$${dollars.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/**
 * Get display name with appropriate suffix
 */
function getDisplayName(
  categoryName: string,
  categoryType: "general" | "itemized" | "fee",
  isOverallBudget: boolean,
): string {
  if (isOverallBudget) return "Overall Budget";
  if (categoryType === "fee") return categoryName;
  return `${categoryName} Budget`;
}

/**
 * Get amount labels based on category type and state
 */
function getAmountLabels(
  categoryType: "general" | "itemized" | "fee",
  spentCents: number,
  budgetCents: number | null,
): { spentLabel: string; remainingLabel: string } {
  const isFee = categoryType === "fee";

  if (budgetCents === null) {
    return {
      spentLabel: isFee
        ? `${formatCents(spentCents)} received`
        : `${formatCents(spentCents)} spent`,
      remainingLabel: "No budget set",
    };
  }

  const remaining = budgetCents - spentCents;
  const isOver = spentCents > budgetCents;

  if (isFee) {
    return {
      spentLabel: `${formatCents(spentCents)} received`,
      remainingLabel: isOver
        ? `${formatCents(Math.abs(remaining))} over received`
        : `${formatCents(remaining)} remaining to receive`,
    };
  } else {
    return {
      spentLabel: `${formatCents(spentCents)} spent`,
      remainingLabel: isOver
        ? `${formatCents(Math.abs(remaining))} over`
        : `${formatCents(remaining)} remaining`,
    };
  }
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

  // Cap display percentage at 100% for the main bar
  const displayPercentage = Math.min(percentage, 100);

  const colors = useMemo(
    () => getBudgetProgressColor(percentage, isFeeCategory),
    [percentage, isFeeCategory],
  );

  const overflowColors = useMemo(() => getOverflowColor(), []);

  const { spentLabel, remainingLabel } = useMemo(
    () => getAmountLabels(categoryType, spentCents, budgetCents),
    [categoryType, spentCents, budgetCents],
  );

  const content = (
    <View style={styles.container}>
      {/* Title Row */}
      <View style={styles.titleRow}>
        <AppText variant="body" style={styles.title}>
          {displayName}
        </AppText>
        {isPinned && (
          <AppText variant="caption" style={styles.pinIndicator}>
            📌
          </AppText>
        )}
      </View>

      {/* Progress Bar */}
      <View style={styles.progressContainer}>
        <View style={styles.progressTrack}>
          {/* Main progress bar (capped at 100%) */}
          <View
            style={[
              styles.progressFill,
              {
                width: `${displayPercentage}%`,
                backgroundColor: colors.bar,
              },
            ]}
          />
          {/* Overflow indicator (dark red, shown when >100%) */}
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
        <AppText
          variant="caption"
          style={[styles.percentage, { color: colors.text }]}
        >
          {budgetCents !== null ? `${Math.round(percentage)}%` : "—"}
        </AppText>
      </View>

      {/* Amount Row */}
      <View style={styles.amountRow}>
        <AppText
          variant="caption"
          style={[styles.amountText, { color: colors.text }]}
        >
          {spentLabel}
        </AppText>
        <AppText
          variant="caption"
          style={[
            styles.amountText,
            isOverBudget && styles.overBudgetText,
            { color: isOverBudget ? overflowColors.text : colors.text },
          ]}
        >
          {remainingLabel}
        </AppText>
      </View>
    </View>
  );

  // If onPress or onLongPress is provided, wrap in TouchableOpacity
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
            // Android: use Alert
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
    gap: 8,
  },
  titleRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  title: {
    fontSize: 16,
    fontWeight: "500",
    color: "#111827", // text-gray-900
  },
  pinIndicator: {
    fontSize: 14,
  },
  progressContainer: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  progressTrack: {
    flex: 1,
    height: 8,
    backgroundColor: "#E5E7EB", // bg-gray-200
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
    transition: "width 300ms ease",
  },
  overflowIndicator: {
    position: "absolute",
    right: 0,
    top: 0,
    height: "100%",
    borderRadius: 9999,
  },
  percentage: {
    fontSize: 14,
    fontWeight: "500",
    minWidth: 40,
    textAlign: "right",
  },
  amountRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    gap: 8,
  },
  amountText: {
    fontSize: 14,
    color: "#6B7280", // text-gray-500
  },
  overBudgetText: {
    fontWeight: "700",
  },
});
