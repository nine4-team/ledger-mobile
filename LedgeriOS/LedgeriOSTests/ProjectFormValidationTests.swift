import Foundation
import Testing
@testable import LedgeriOS

@Suite("Project Form Validation Tests")
struct ProjectFormValidationTests {

    // MARK: - validateProject

    @Test("Empty name fails validation")
    func emptyNameFails() {
        let errors = ProjectFormValidation.validateProject(name: "", clientName: "Acme Corp")
        #expect(errors.contains(ValidationError(field: "name", message: "Name is required")))
    }

    @Test("Empty client name fails validation")
    func emptyClientNameFails() {
        let errors = ProjectFormValidation.validateProject(name: "Kitchen Reno", clientName: "")
        #expect(errors.contains(ValidationError(field: "clientName", message: "Client name is required")))
    }

    @Test("Whitespace-only name fails validation")
    func whitespaceOnlyNameFails() {
        let errors = ProjectFormValidation.validateProject(name: "   ", clientName: "Acme Corp")
        #expect(errors.contains(ValidationError(field: "name", message: "Name is required")))
    }

    @Test("Whitespace-only client name fails validation")
    func whitespaceOnlyClientNameFails() {
        let errors = ProjectFormValidation.validateProject(name: "Kitchen Reno", clientName: "  \t ")
        #expect(errors.contains(ValidationError(field: "clientName", message: "Client name is required")))
    }

    @Test("Both empty returns two errors")
    func bothEmptyReturnsTwoErrors() {
        let errors = ProjectFormValidation.validateProject(name: "", clientName: "")
        #expect(errors.count == 2)
    }

    @Test("Valid project passes with no errors")
    func validProjectPasses() {
        let errors = ProjectFormValidation.validateProject(name: "Kitchen Reno", clientName: "Acme Corp")
        #expect(errors.isEmpty)
    }

    @Test("Negative budget allocation fails validation")
    func negativeBudgetFails() {
        let errors = ProjectFormValidation.validateProject(
            name: "Kitchen Reno",
            clientName: "Acme Corp",
            budgetAllocations: ["materials": -500]
        )
        #expect(errors.contains(ValidationError(
            field: "budgetAllocations",
            message: "Budget allocations must be zero or greater"
        )))
    }

    @Test("Zero budget allocation passes")
    func zeroBudgetPasses() {
        let errors = ProjectFormValidation.validateProject(
            name: "Kitchen Reno",
            clientName: "Acme Corp",
            budgetAllocations: ["materials": 0]
        )
        #expect(errors.isEmpty)
    }

    @Test("Positive budget allocation passes")
    func positiveBudgetPasses() {
        let errors = ProjectFormValidation.validateProject(
            name: "Kitchen Reno",
            clientName: "Acme Corp",
            budgetAllocations: ["materials": 50000]
        )
        #expect(errors.isEmpty)
    }

    // MARK: - isValidProject

    @Test("isValidProject returns true for valid inputs")
    func isValidProjectTrue() {
        #expect(ProjectFormValidation.isValidProject(name: "Kitchen Reno", clientName: "Acme Corp"))
    }

    @Test("isValidProject returns false for empty name")
    func isValidProjectEmptyName() {
        #expect(!ProjectFormValidation.isValidProject(name: "", clientName: "Acme Corp"))
    }

    @Test("isValidProject returns false for empty client name")
    func isValidProjectEmptyClient() {
        #expect(!ProjectFormValidation.isValidProject(name: "Kitchen Reno", clientName: ""))
    }

    @Test("isValidProject returns false for whitespace-only inputs")
    func isValidProjectWhitespace() {
        #expect(!ProjectFormValidation.isValidProject(name: "  ", clientName: "  "))
    }
}
