/**
 * Example usage of BudgetCategoryTracker component
 *
 * This file demonstrates the different states and configurations
 * of the BudgetCategoryTracker component according to Phase 2.1
 * of the budget management plan.
 */

import React from "react";
import { View, StyleSheet, ScrollView } from "react-native";
import { BudgetCategoryTracker } from "./BudgetCategoryTracker";
import { AppText } from "../AppText";

export function BudgetCategoryTrackerExamples() {
  return (
    <ScrollView style={styles.container}>
      <AppText variant="h1" style={styles.sectionTitle}>
        Budget Category Tracker Examples
      </AppText>

      {/* General Category - Healthy (Green) */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          General Category - Healthy (0-49%)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Install"
          categoryType="general"
          spentCents={350000} // $3,500
          budgetCents={1000000} // $10,000
        />
      </View>

      {/* General Category - Warning (Yellow) */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          General Category - Warning (50-74%)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Furnishings"
          categoryType="itemized"
          spentCents={650000} // $6,500
          budgetCents={1000000} // $10,000
          isPinned={true}
        />
      </View>

      {/* General Category - Critical (Red) */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          General Category - Critical (75-99%)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Storage & Receiving"
          categoryType="general"
          spentCents={850000} // $8,500
          budgetCents={1000000} // $10,000
        />
      </View>

      {/* General Category - Over Budget */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          General Category - Over Budget (100%+)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Install"
          categoryType="general"
          spentCents={1200000} // $12,000
          budgetCents={1000000} // $10,000
        />
      </View>

      {/* Fee Category - Low Progress (Red for fees) */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          Fee Category - Low Progress (0-49%)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Design Fee"
          categoryType="fee"
          spentCents={200000} // $2,000 received
          budgetCents={500000} // $5,000 total
        />
      </View>

      {/* Fee Category - Partial Progress (Yellow for fees) */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          Fee Category - Partial Progress (50-74%)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Design Fee"
          categoryType="fee"
          spentCents={325000} // $3,250 received
          budgetCents={500000} // $5,000 total
        />
      </View>

      {/* Fee Category - Good Progress (Green for fees) */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          Fee Category - Good Progress (75%+)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Design Fee"
          categoryType="fee"
          spentCents={425000} // $4,250 received
          budgetCents={500000} // $5,000 total
        />
      </View>

      {/* Overall Budget */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          Overall Budget
        </AppText>
        <BudgetCategoryTracker
          categoryName="Overall"
          categoryType="general"
          spentCents={2320000} // $23,200
          budgetCents={4000000} // $40,000
          isOverallBudget={true}
        />
      </View>

      {/* No Budget Set */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          No Budget Set (null budgetCents)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Miscellaneous"
          categoryType="general"
          spentCents={150000} // $1,500 spent
          budgetCents={null}
        />
      </View>

      {/* Interactive Example */}
      <View style={styles.section}>
        <AppText variant="h2" style={styles.exampleTitle}>
          Interactive (with callbacks)
        </AppText>
        <BudgetCategoryTracker
          categoryName="Furnishings"
          categoryType="itemized"
          spentCents={650000}
          budgetCents={1000000}
          isPinned={true}
          onPress={() => console.log("Pressed: Furnishings")}
          onLongPress={() =>
            console.log("Long pressed: Furnishings (show pin menu)")
          }
        />
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: "#FFFFFF",
  },
  sectionTitle: {
    marginBottom: 24,
    fontSize: 24,
    fontWeight: "bold",
  },
  section: {
    marginBottom: 32,
    padding: 16,
    backgroundColor: "#F9FAFB",
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#E5E7EB",
  },
  exampleTitle: {
    marginBottom: 12,
    fontSize: 16,
    fontWeight: "600",
    color: "#6B7280",
  },
});
