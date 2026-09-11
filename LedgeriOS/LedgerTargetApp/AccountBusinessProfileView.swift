import LedgerTargetCore
import LedgerTargetAppModel
import SwiftUI

struct AccountBusinessProfileView: View {
    let accountId: AccountID
    let reader: any AccountBusinessProfileReading
    @State private var model = AccountBusinessProfileModel()
    @State private var refresh = UUID()

    init(accountId: AccountID, reader: any AccountBusinessProfileReading,
         model: AccountBusinessProfileModel = AccountBusinessProfileModel()) {
        self.accountId = accountId
        self.reader = reader
        _model = State(initialValue: model)
    }

    private struct Request: Equatable {
        let accountBytes: [UInt8]
        let refresh: UUID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading business profile…")
            case .unavailable:
                Text("Business profile unavailable. Refresh to try again.")
                    .accessibilityIdentifier("target-account-profile-unavailable")
            case .downloaded(let profile):
                if profile.accountId.rawValue.utf8.elementsEqual(accountId.rawValue.utf8) {
                    Text(profile.name.rawValue)
                        .font(.headline)
                        .accessibilityIdentifier("target-account-profile-name")
                    logo(profile.logo)
                    if profile.isStale {
                        Text("Showing saved business profile. Reconnect to check for changes.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("target-account-profile-stale")
                    }
                } else {
                    ProgressView("Loading business profile…")
                }
            }
            Button("Refresh") { refresh = UUID() }
                .accessibilityIdentifier("target-account-profile-refresh")
        }
        .task(id: Request(accountBytes: Array(accountId.rawValue.utf8), refresh: refresh)) {
            await model.load(accountId: accountId, reader: reader)
        }
        .onDisappear { model.clear() }
    }

    @ViewBuilder private func logo(_ logo: AccountBusinessProfile.Logo) -> some View {
        switch logo {
        case .absent:
            fallback("No business logo")
        case .notDownloaded:
            fallback("Business logo not downloaded. Reconnect and refresh to try again.")
        case .unavailable:
            fallback("Business logo unavailable. Refresh to try again.")
        case .downloaded(let bytes):
            if let native = AccountBusinessLogoImage.decode(bytes) {
                Image(decorative: native, scale: 1).resizable().scaledToFit().frame(maxHeight: 120)
                    .accessibilityLabel("Business logo")
            } else { fallback("Business logo unavailable. Refresh to try again.") }
        }
    }

    private func fallback(_ explanation: String) -> some View {
        Label(explanation, systemImage: "building.2")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("target-account-profile-logo-fallback")
    }
}
