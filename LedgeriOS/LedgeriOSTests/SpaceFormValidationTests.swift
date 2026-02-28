import Foundation
import Testing
@testable import LedgeriOS

@Suite("Space Form Validation Tests")
struct SpaceFormValidationTests {

    // MARK: - validateSpace

    @Test("Empty name fails validation")
    func emptyNameFails() {
        let errors = SpaceFormValidation.validateSpace(name: "")
        #expect(errors.contains(ValidationError(field: "name", message: "Name is required")))
    }

    @Test("Whitespace-only name fails validation")
    func trimmedWhitespaceFails() {
        let errors = SpaceFormValidation.validateSpace(name: "   ")
        #expect(errors.contains(ValidationError(field: "name", message: "Name is required")))
    }

    @Test("Tab and newline whitespace fails validation")
    func tabAndNewlineWhitespaceFails() {
        let errors = SpaceFormValidation.validateSpace(name: "\t\n  ")
        #expect(errors.contains(ValidationError(field: "name", message: "Name is required")))
    }

    @Test("Valid name passes with no errors")
    func validSpacePasses() {
        let errors = SpaceFormValidation.validateSpace(name: "Storage Room A")
        #expect(errors.isEmpty)
    }

    @Test("Name with leading/trailing whitespace is valid")
    func nameWithPaddingValid() {
        let errors = SpaceFormValidation.validateSpace(name: "  Storage Room  ")
        #expect(errors.isEmpty)
    }

    // MARK: - isValidSpace

    @Test("isValidSpace returns true for valid name")
    func isValidSpaceTrue() {
        #expect(SpaceFormValidation.isValidSpace(name: "Storage Room A"))
    }

    @Test("isValidSpace returns false for empty name")
    func isValidSpaceEmpty() {
        #expect(!SpaceFormValidation.isValidSpace(name: ""))
    }

    @Test("isValidSpace returns false for whitespace-only name")
    func isValidSpaceWhitespace() {
        #expect(!SpaceFormValidation.isValidSpace(name: "   "))
    }
}
