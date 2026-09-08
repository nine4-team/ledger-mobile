import Foundation
import LedgerTargetCore
import LedgerTargetAppModel
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct LocalVendorDocumentReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var review: LocalVendorDocumentReview
    @State private var selectingFile = false
    @State private var fileError: String?
    @State private var loadingTask: Task<Void, Never>?
    @State private var showStats = false
    @State private var showRawText = false
    @State private var copyStatus: String?
    private let categoryWatch: (@Sendable () -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>)?

    init(review: LocalVendorDocumentReview,
         categoryWatch: (@Sendable () -> AsyncThrowingStream<BudgetCategoryReferenceSnapshot, Error>)? = nil) {
        self.review = review
        self.categoryWatch = categoryWatch
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review a vendor PDF locally. This does not create Items or record a payment.")
                    .foregroundStyle(.secondary)
                Button(review.document == nil ? "Select PDF" : "Select Different PDF") { selectingFile = true }
                    .accessibilityIdentifier("target-vendor-pdf-select")
                if let fileError { Text(fileError).foregroundStyle(.red) }
                switch review.state {
                case .empty:
                    Text("Select an Amazon or Wayfair PDF to review.")
                        .accessibilityIdentifier("target-vendor-pdf-empty")
                case .extracting:
                    ProgressView("Extracting text from PDF…")
                        .accessibilityIdentifier("target-vendor-pdf-extracting")
                case .failed(let failure):
                    Text(message(failure)).foregroundStyle(.red)
                        .accessibilityIdentifier("target-vendor-pdf-error")
                case .review:
                    if let document = review.document, let hash = review.documentHash {
                        Text(document.vendor.rawValue.capitalized).font(.title2.bold())
                        Picker("Budget Category", selection: Binding(
                            get: { review.selectedCategoryId }, set: { review.selectCategory($0) }
                        )) {
                            Text("No Category").tag(nil as BudgetCategoryID?)
                            ForEach(review.categories, id: \.id) { category in
                                Text(category.name.rawValue).tag(Optional(category.id))
                            }
                        }
                        .accessibilityIdentifier("target-vendor-pdf-category")
                        Text(review.categoryStatus).font(.caption).foregroundStyle(.secondary)
                        ForEach(document.fields.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: document.fields[key] ?? "")
                        }
                        ForEach(Array(document.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).foregroundStyle(.orange)
                        }
                        Text("Included rows: \(review.includedCount) of \(review.rows.count)")
                            .accessibilityIdentifier("target-vendor-pdf-included-count")
                        if review.rows.isEmpty {
                            Text("No line items were extracted. Choose another PDF or review the source document.")
                                .accessibilityIdentifier("target-vendor-pdf-no-rows")
                        }
                        ForEach(review.rows) { row in
                            VStack(alignment: .leading, spacing: 8) {
                                if let thumbnail = row.original.thumbnail {
                                    thumbnailView(thumbnail)
                                        .accessibilityIdentifier("target-vendor-pdf-thumbnail-\(row.id)")
                                } else if document.vendor == .wayfair {
                                    Text("No unambiguous source thumbnail for this row.").font(.caption)
                                }
                                Toggle("Include row \(row.id + 1)", isOn: binding(row, hash: hash, keyPath: \.included))
                                TextField("Description", text: binding(row, hash: hash, keyPath: \.description), axis: .vertical)
                                TextField("Quantity", text: binding(row, hash: hash, keyPath: \.quantity))
                                TextField("Unit price", text: binding(row, hash: hash, keyPath: \.unitPrice))
                                Text("Extracted line total: \(row.original.total)")
                                if let sku = row.original.sku { Text("SKU: \(sku)") }
                                ForEach(Array(row.original.attributes.enumerated()), id: \.offset) { _, value in Text(value) }
                                ForEach(row.original.details.keys.sorted(), id: \.self) { key in
                                    LabeledContent(key, value: row.original.details[key] ?? "")
                                }
                            }
                            .accessibilityIdentifier("target-vendor-pdf-row-\(row.id)")
                            Divider()
                        }
                        GroupBox("Debug Info") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Local document diagnostics only. Links and recognized sensitive lines are omitted.")
                                    .font(.caption)
                                Button(showStats ? "Hide Stats" : "Show Stats") { showStats.toggle() }
                                if showStats {
                                    Text("Pages: \(document.pageCount) · Characters: \(document.rawText.count) · Rows: \(document.rows.count)")
                                }
                                Button(showRawText ? "Hide Raw Text" : "Show Raw Text") { showRawText.toggle() }
                                if showRawText {
                                    Text(LocalVendorDocumentDiagnostics.redactedText(document.rawText))
                                        .font(.caption.monospaced()).textSelection(.enabled)
                                }
                                Button("Copy Debug JSON") { copyDiagnostics(document) }
                                    .accessibilityIdentifier("target-vendor-pdf-copy-debug")
                                if let copyStatus { Text(copyStatus).font(.caption) }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Review Vendor PDF")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { close(); dismiss() }
                    .accessibilityIdentifier("target-vendor-pdf-cancel")
            }
        }
        .fileImporter(isPresented: $selectingFile, allowedContentTypes: [.pdf]) { result in
            guard !review.isClosed else { return }
            switch result {
            case .success(let url):
                loadingTask?.cancel()
                fileError = nil
                loadingTask = Task { @MainActor in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let bytes = try await Task.detached { try Data(contentsOf: url) }.value
                        guard !Task.isCancelled else { return }
                        await review.load(bytes, parser: LocalVendorPDFParser())
                    } catch {
                        guard !Task.isCancelled else { return }
                        fileError = "The selected file could not be opened. Your current review has not changed."
                    }
                }
            case .failure(let error):
                let error = error as NSError
                if error.domain != NSCocoaErrorDomain || error.code != NSUserCancelledError {
                    fileError = "The file picker could not open the document. Try again."
                }
            }
        }
        .task {
            guard let categoryWatch else { review.categoriesUnavailable(); return }
            do {
                for try await snapshot in categoryWatch() {
                    guard !Task.isCancelled else { return }
                    review.receiveCategories(snapshot)
                }
                if !Task.isCancelled { review.categoriesUnavailable() }
            } catch {
                if !Task.isCancelled { review.categoriesUnavailable() }
            }
        }
        .onChange(of: review.documentHash) { _, _ in
            showStats = false; showRawText = false; copyStatus = nil
        }
    }

    private func binding<Value>(_ row: LocalVendorDocumentDraftRow, hash: ProtectedArtifactSHA256,
                                keyPath: WritableKeyPath<LocalVendorDocumentDraftRow, Value>) -> Binding<Value> {
        Binding(get: { (review.rows.first { $0.id == row.id } ?? row)[keyPath: keyPath] },
                set: { value in review.update(id: row.id, documentHash: hash) { $0[keyPath: keyPath] = value } })
    }

    private func close() {
        loadingTask?.cancel(); loadingTask = nil
        review.close()
    }

    @ViewBuilder
    private func thumbnailView(_ thumbnail: LocalVendorDocumentThumbnail) -> some View {
        #if os(macOS)
        if let image = NSImage(data: thumbnail.pngBytes) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 96, height: 96)
                .accessibilityLabel("Source document thumbnail")
        } else { Text("Thumbnail could not be displayed.").font(.caption) }
        #elseif os(iOS)
        if let image = UIImage(data: thumbnail.pngBytes) {
            Image(uiImage: image).resizable().scaledToFit().frame(width: 96, height: 96)
                .accessibilityLabel("Source document thumbnail")
        } else { Text("Thumbnail could not be displayed.").font(.caption) }
        #endif
    }

    private func copyDiagnostics(_ document: LocalVendorDocument) {
        do {
            let json = try LocalVendorDocumentDiagnostics.json(document)
            #if os(macOS)
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(json, forType: .string) else {
                copyStatus = "Could not copy diagnostics."; return
            }
            #elseif os(iOS)
            UIPasteboard.general.string = json
            #endif
            copyStatus = "Copied local document diagnostics."
        } catch { copyStatus = "Could not prepare diagnostics." }
    }

    private func message(_ failure: LocalVendorDocumentFailure) -> String {
        switch failure {
        case .corruptDocument: "The PDF could not be read. It may be corrupt or locked."
        case .imageOnlyDocument: "This PDF has no extractable text. Local review supports text PDFs."
        case .unsupportedVendor: "This PDF is not a supported Amazon or Wayfair document."
        case .ambiguousVendor: "The PDF contains conflicting vendor information. Review the original document."
        case .invalidRowIdentity: "The extracted rows could not be identified safely. Choose another document."
        }
    }
}
