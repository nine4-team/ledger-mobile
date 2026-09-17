import Testing

@Suite("Reused Budget labels")
struct BudgetLabelReuseTests {
    @Test func ordinaryCategoriesSortBeforeFeesThenByName() {
        #expect(BudgetDisplayCalculations.categoryComesBefore(name: "Zebra", isFee: false, otherName: "Alpha", otherIsFee: true))
        #expect(!BudgetDisplayCalculations.categoryComesBefore(name: "Alpha", isFee: true, otherName: "Zebra", otherIsFee: false))
        #expect(BudgetDisplayCalculations.categoryComesBefore(name: "alpha", isFee: false, otherName: "Zebra", otherIsFee: false))
        #expect(!BudgetDisplayCalculations.categoryComesBefore(name: "alpha", isFee: true, otherName: "ALPHA", otherIsFee: true))
    }
    @Test func existingLabelsRemainUnchanged() {
        #expect(BudgetDisplayCalculations.spentLabel(spentCents: 15099, isFeeCategory: false) == "$150 spent")
        #expect(BudgetDisplayCalculations.spentLabel(spentCents: 15099, isFeeCategory: true) == "$150 received")
        #expect(BudgetDisplayCalculations.remainingLabel(spentCents: 5000, budgetCents: 10000, isFeeCategory: false) == "$50 remaining")
        #expect(BudgetDisplayCalculations.remainingLabel(spentCents: 10000, budgetCents: 10000, isFeeCategory: false) == "$0 remaining")
        #expect(BudgetDisplayCalculations.remainingLabel(spentCents: 15000, budgetCents: 10000, isFeeCategory: false) == "$50 over")
        #expect(BudgetDisplayCalculations.remainingLabel(spentCents: 15000, budgetCents: 10000, isFeeCategory: true) == "$50 over received")
        #expect(BudgetDisplayCalculations.remainingLabel(spentCents: 15000, budgetCents: 0, isFeeCategory: true) == "$150 received")
        #expect(BudgetDisplayCalculations.remainingLabel(spentCents: -5000, budgetCents: 10000, isFeeCategory: false) == "$150 remaining")
    }
}
