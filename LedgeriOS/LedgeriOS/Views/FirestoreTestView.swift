import SwiftUI
import FirebaseFirestore

struct FirestoreTestView: View {
    @State private var resultMessage: String?
    @State private var isSuccess = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Firestore Connectivity Test")
                .font(.headline)

            Button {
                testFirestoreConnection()
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Test Connection")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(BrandColors.primary)
                .foregroundStyle(.white)
                .cornerRadius(10)
            }
            .disabled(isLoading)
            .padding(.horizontal, 32)

            if let resultMessage {
                HStack(spacing: 8) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isSuccess ? .green : .red)
                    Text(resultMessage)
                        .font(.subheadline)
                        .foregroundStyle(isSuccess ? .green : .red)
                }
                .padding()
            }
        }
    }

    private func testFirestoreConnection() {
        isLoading = true
        resultMessage = nil

        Task {
            do {
                let db = Firestore.firestore()
                let snapshot = try await db.collection("accounts").limit(to: 1).getDocuments()

                if let doc = snapshot.documents.first {
                    print("[FirestoreTest] Fetched document: \(doc.documentID)")
                    resultMessage = "Connected. Document: \(doc.documentID)"
                } else {
                    print("[FirestoreTest] Query succeeded but no documents found.")
                    resultMessage = "Connected. No documents in collection."
                }
                isSuccess = true
            } catch {
                print("[FirestoreTest] Error: \(error.localizedDescription)")
                resultMessage = "Failed: \(error.localizedDescription)"
                isSuccess = false
            }

            isLoading = false
        }
    }
}

#Preview {
    FirestoreTestView()
}
