/**
 * Budget Category Color Mapping
 *
 * Maps budget category names to their associated colors for badge display.
 * Colors match the legacy web app's Tailwind CSS category color scheme.
 */

export type CategoryBadgeColors = {
  bg: string;
  text: string;
  border: string;
};

export type BudgetCategoryColorMap = {
  [categoryName: string]: CategoryBadgeColors;
};

/**
 * Default category color mappings from legacy web app (Tailwind CSS equivalents)
 */
export const DEFAULT_CATEGORY_COLORS: BudgetCategoryColorMap = {
  'Design Fee': { bg: '#fef3c7', text: '#92400e', border: '#fde68a' },       // amber 100/800/200
  'Furnishings': { bg: '#fef9c4', text: '#854d0e', border: '#fef08a' },      // yellow 100/800/200
  'Property Management': { bg: '#ffedd5', text: '#9a3412', border: '#fed7aa' }, // orange 100/800/200
  'Kitchen': { bg: '#fde68a', text: '#78350f', border: '#fcd34d' },           // amber 200/900/300
  'Install': { bg: '#fef08a', text: '#713f12', border: '#fde047' },           // yellow 200/900/300
  'Storage & Receiving': { bg: '#fed7aa', text: '#7c2d12', border: '#fdba74' }, // orange 200/900/300
  'Fuel': { bg: '#fcd34d', text: '#78350f', border: '#fbbf24' },              // amber 300/900/400
};

/**
 * Generates badge colors from a base color (for categories not in the predefined map)
 */
function badgeColorsFromBase(baseColor: string): CategoryBadgeColors {
  return {
    bg: baseColor + '1A',
    text: baseColor,
    border: baseColor + '33',
  };
}

/**
 * Generates a consistent color for a category ID using a hash function
 * Useful for categories not in the predefined map
 */
export function generateCategoryColor(categoryId: string): CategoryBadgeColors {
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
  return badgeColorsFromBase(colors[index]);
}

/**
 * Gets the badge colors for a budget category by ID
 * First checks the predefined mapping by name, then falls back to generated color
 */
export function getBudgetCategoryColor(
  categoryId: string | null | undefined,
  budgetCategories: Record<string, { name: string }>
): CategoryBadgeColors | undefined {
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
