import LedgerTargetCore
import SwiftUI

/// Runtime binding for the original budget tracker, not a replacement tracker.
struct ProjectBudgetContent: View {
    let accountId: AccountID
    let projectId: ProjectID
    let currency: CurrencyCode
    let reader: any ProjectBudgetReading
    @State private var find = FindStateManager()
    @State private var snapshot: ProjectBudgetRead?
    @State private var generation = UUID()
    @State private var unavailable = false

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let snapshot {
                        if !snapshot.isCompleteForProjectBudget {
                            Text("Budget coverage is incomplete. Transfers and Additional Requests are not fully included yet.")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("target-budget-incomplete")
                        }
                        if !snapshot.localOperations.isEmpty {
                            Text("Financial changes are pending or need attention. Displayed amounts reflect downloaded accounting.")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("target-budget-pending")
                        }
                        categoryRows(snapshot, fees: false)
                        if snapshot.overallBudget.minorUnits > 0, snapshot.overallUnpaid.minorUnits >= 0,
                           let spent = Int(exactly: snapshot.overallRecognized.minorUnits),
                           let budget = Int(exactly: snapshot.overallBudget.minorUnits) {
                            Divider()
                            BudgetCategoryTracker(name: "Overall Budget", spentCents: spent, budgetCents: budget,
                                amountLabel: "Total \(format(snapshot.overallRecognized))")
                        }
                        categoryRows(snapshot, fees: true)
                        if snapshot.allocations.isEmpty {
                            Text("No budget categories are configured in the downloaded Project data.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(unavailable ? "Budget data is unavailable or not fully downloaded." : "Loading downloaded budget…")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Spacing.screenPadding)
            }
        }
        .navigationTitle("Budget")
        .environment(find)
        .task(id: [accountId.rawValue, projectId.rawValue, currency.rawValue]) {
            let visit = UUID()
            generation = visit; snapshot = nil; unavailable = false
            do {
                for try await value in reader.watchProjectBudget(accountId: accountId, projectId: projectId, currency: currency) {
                    guard !Task.isCancelled, generation == visit else { return }
                    guard value == nil || (value?.scope.accountId == accountId && value?.scope.projectId == projectId && value?.currency == currency) else {
                        snapshot = nil; unavailable = true; return
                    }
                    snapshot = value; unavailable = value == nil
                }
                if !Task.isCancelled, generation == visit { snapshot = nil; unavailable = true }
            } catch {
                if !Task.isCancelled, generation == visit { snapshot = nil; unavailable = true }
            }
        }
        .onDisappear { generation = UUID(); snapshot = nil }
    }

    private func format(_ value: Money) -> String {
        (Decimal(value.minorUnits) / 100).formatted(.currency(code: value.currency.rawValue))
    }

    @ViewBuilder
    private func categoryRows(_ snapshot: ProjectBudgetRead, fees: Bool) -> some View {
        ForEach(orderedAllocations(snapshot), id: \.categoryId) { allocation in
            if let segment = snapshot.segments.first(where: { $0.category.id == allocation.categoryId }),
               (segment.category.kind == .fee) == fees,
               let spent = Int(exactly: segment.recognized.minorUnits),
               let budget = Int(exactly: allocation.allocation?.minorUnits ?? 0) {
                if segment.invoicingUnpaid.minorUnits < 0 {
                    Text("\(segment.category.name.rawValue): pending-credit presentation is not yet available.")
                        .foregroundStyle(.secondary)
                } else {
                    BudgetCategoryTracker(name: segment.category.name.rawValue,
                        spentCents: spent, budgetCents: budget, isFeeCategory: fees,
                        amountLabel: "Total \(format(segment.recognized))",
                        remainingAmountLabel: BudgetTrackerCalculations.remainingLabel(
                            spentCents: spent, budgetCents: budget, isFeeCategory: false))
                    Text("Paid \(format(segment.clientPaid)) · Unpaid \(format(segment.invoicingUnpaid))")
                        .font(Typography.small).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func orderedAllocations(_ value: ProjectBudgetRead) -> [NullableCategoryAllocation] {
        let categories = Dictionary(uniqueKeysWithValues: value.segments.map { ($0.category.id, $0.category) })
        return value.allocations.sorted {
            guard let first = categories[$0.categoryId], let second = categories[$1.categoryId] else { return false }
            return BudgetDisplayCalculations.categoryComesBefore(name: first.name.rawValue, isFee: first.kind == .fee,
                otherName: second.name.rawValue, otherIsFee: second.kind == .fee)
        }
    }
}
