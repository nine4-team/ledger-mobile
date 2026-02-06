/**
 * Budget Category Color Mapping
 *
 * Maps budget category names to their associated colors for badge display.
 * Colors are based on the legacy web app's category color scheme.
 */

export type BudgetCategoryColorMap = {
  [categoryName: string]: string;
};

/**
 * Default category color mappings from legacy web app
 */
export const DEFAULT_CATEGORY_COLORS: BudgetCategoryColorMap = {
  'Design Fee': '#f59e0b', // amber
  'Furnishings': '#eab308', // yellow
  'Property Management': '#f97316', // orange
  'Kitchen': '#fbbf24', // amber-200
  'Install': '#fde047', // yellow-200
  'Storage & Receiving': '#fb923c', // orange-200
  'Fuel': '#fcd34d', // amber-300
};

/**
 * Generates a consistent color for a category ID using a hash function
 * Useful for categories not in the predefined map
 */
export function generateCategoryColor(categoryId: string): string {
  // Simple hash function
  let hash = 0;
  for (let i = 0; i < categoryId.length; i++) {
    hash = categoryId.charCodeAt(i) + ((hash << 5) - hash);
  }

  // Predefined color palette (visually distinct colors)
  const colors = [
    '#f59e0b', // amber
    '#10b981', // green
    '#3b82f6', // blue
    '#8b5cf6', // purple
    '#ec4899', // pink
    '#f97316', // orange
    '#06b6d4', // cyan
    '#eab308', // yellow
    '#6366f1', // indigo
    '#14b8a6', // teal
  ];

  const index = Math.abs(hash) % colors.length;
  return colors[index];
}

/**
 * Gets the color for a budget category by ID
 * First checks the predefined mapping by name, then falls back to generated color
 */
export function getBudgetCategoryColor(
  categoryId: string | null | undefined,
  budgetCategories: Record<string, { name: string }>
): string | undefined {
  if (!categoryId) return undefined;

  const category = budgetCategories[categoryId];
  if (!category) {
    return generateCategoryColor(categoryId);
  }

  // Check if we have a predefined color for this category name
  const predefinedColor = DEFAULT_CATEGORY_COLORS[category.name];
  if (predefinedColor) {
    return predefinedColor;
  }

  // Generate a consistent color based on category ID
  return generateCategoryColor(categoryId);
}

/**
 * Updates the category color map with custom colors
 */
export function updateCategoryColorMap(
  customColors: BudgetCategoryColorMap
): BudgetCategoryColorMap {
  return {
    ...DEFAULT_CATEGORY_COLORS,
    ...customColors,
  };
}
