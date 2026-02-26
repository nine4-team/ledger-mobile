# Quickstart: SwiftUI Component Library

## Prerequisites

- Xcode with iOS 17+ SDK
- Existing LedgeriOS project builds successfully
- All Tier 0 components present in `LedgeriOS/LedgeriOS/Components/`

## Build Verification (per WP)

After each work package, verify:

```bash
# 1. Build the project
xcodebuild -project LedgeriOS/LedgeriOS.xcodeproj \
  -scheme LedgeriOS \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  build 2>&1 | tail -5

# 2. Run tests
xcodebuild -project LedgeriOS/LedgeriOS.xcodeproj \
  -scheme LedgeriOS \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  test 2>&1 | tail -20

# 3. Check for hardcoded values (should return 0 matches in new files)
grep -rn "Color(" LedgeriOS/LedgeriOS/Components/NewFile.swift | grep -v "BrandColors\|StatusColors\|Color.clear\|Color.white\|Color.black"
```

## File Naming Conventions

- **Components**: `ComponentName.swift` in `LedgeriOS/LedgeriOS/Components/`
- **Logic**: `XxxCalculations.swift` in `LedgeriOS/LedgeriOS/Logic/`
- **Tests**: `XxxCalculationTests.swift` in `LedgeriOS/LedgeriOSTests/`

## Component Template

```swift
import SwiftUI

struct NewComponent: View {
    // Required props
    let title: String

    // Optional props with defaults
    var subtitle: String?
    var onPress: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
        .padding(Spacing.cardPadding)
    }
}

#Preview("Default") {
    NewComponent(title: "Sample")
}

#Preview("With Subtitle") {
    NewComponent(title: "Sample", subtitle: "Details here")
}
```

## Logic Template

```swift
import Foundation

enum NewComponentCalculations {
    static func computeSomething(input: Int) -> String {
        // Pure function — no SwiftUI import needed
        return "\(input)"
    }
}
```

## Test Template

```swift
import Foundation
import Testing
@testable import LedgeriOS

@Suite("New Component Calculation Tests")
struct NewComponentCalculationTests {

    @Test("Happy path description")
    func happyPath() {
        let result = NewComponentCalculations.computeSomething(input: 42)
        #expect(result == "42")
    }

    @Test("Edge case description")
    func edgeCase() {
        let result = NewComponentCalculations.computeSomething(input: 0)
        #expect(result == "0")
    }
}
```

## Tier Dependency Gate

Before starting a new tier, ALL components from the previous tier must compile:

| Gate | Prerequisite |
|------|-------------|
| Start WP2 | All 16 Tier 1 components build, all Tier 1 Logic tests pass |
| Start WP3 | All 4 Tier 2 components build, all Tier 2 Logic tests pass |
| Start WP4 | All 8 Tier 3 components build, all Tier 3 Logic tests pass |
