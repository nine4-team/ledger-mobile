import SwiftUI
import UIKit

/// Full invoice import flow: select PDF → auto-detect vendor → parse → review → create transaction + items.
struct ImportInvoiceModal: View {
    let projectId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountContext.self) private var accountContext
    @Environment(ProjectContext.self) private var projectContext
    @Environment(MediaService.self) private var mediaService

    // MARK: - State

    @State private var isLoading = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    // PDF & parsing
    @State private var selectedFileData: Data?
    @State private var selectedFileName: String?
    @State private var detectedVendor: InvoiceVendor?
    @State private var amazonParseResult: AmazonInvoiceParser.ParseResult?
    @State private var wayfairParseResult: WayfairInvoiceParser.ParseResult?
    @State private var draftItems: [DraftLineItem] = []
    @State private var wrongVendorWarning: String?
    @State private var extractionStats: PdfTextExtractor.ExtractionStats?
    @State private var rawPdfText = ""
    @State private var extractedThumbnails: [PdfImageExtractor.ImagePlacement] = []

    // Review options
    @State private var selectedCategoryId: String?
    @State private var showCategoryPicker = false
    @State private var showDocumentPicker = false

    // MARK: - Computed

    private var hasParsed: Bool {
        amazonParseResult != nil || wayfairParseResult != nil
    }

    private var includedItems: [DraftLineItem] {
        draftItems.filter(\.isIncluded)
    }

    private var itemCount: Int {
        draftItems.count
    }

    private var categoryName: String? {
        guard let selectedCategoryId else { return nil }
        return projectContext.budgetCategories.first { $0.id == selectedCategoryId }?.name
    }

    private var parseResultJson: String {
        if let result = amazonParseResult {
            return amazonParseResultToJson(result)
        } else if let result = wayfairParseResult {
            return wayfairParseResultToJson(result)
        }
        return "{}"
    }

    // MARK: - Body

    var body: some View {
        Group {
            if hasParsed {
                reviewStep
            } else {
                selectStep
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { data, filename in
                showDocumentPicker = false
                selectedFileData = data
                selectedFileName = filename
                processSelectedPdf(data: data)
            } onDismiss: {
                showDocumentPicker = false
            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerList(
                categories: projectContext.budgetCategories,
                selectedId: selectedCategoryId,
                onSelect: { cat in selectedCategoryId = cat?.id }
            )
            .sheetStyle(.picker)
        }
    }

    // MARK: - Step 1: Select PDF

    private var selectStep: some View {
        FormSheet(
            title: "Import Invoice",
            description: "Select a vendor PDF to extract line items",
            primaryAction: FormSheetAction(
                title: "Select PDF",
                isLoading: isLoading
            ) {
                showDocumentPicker = true
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            },
            error: errorMessage
        ) {
            VStack(spacing: Spacing.lg) {
                // PDF drop zone visual
                Button {
                    showDocumentPicker = true
                } label: {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 40))
                            .foregroundStyle(BrandColors.primary)
                        Text("Select PDF Invoice")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text("Amazon and Wayfair invoices supported")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xxl)
                    .background(
                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            .foregroundStyle(BrandColors.border)
                    )
                }
                .buttonStyle(.plain)

                if isLoading {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("Extracting text from PDF...")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Review

    private var reviewStep: some View {
        FormSheet(
            title: "Import Invoice",
            description: "\(includedItems.count) items to import",
            primaryAction: FormSheetAction(
                title: "Create Transaction",
                isLoading: isCreating,
                isDisabled: includedItems.isEmpty
            ) {
                createTransaction()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            },
            error: errorMessage
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Parse summary
                    InvoiceParseSummary(
                        vendor: detectedVendor,
                        amazonResult: amazonParseResult,
                        wayfairResult: wayfairParseResult,
                        itemCount: itemCount
                    )

                    // Wrong vendor warning
                    if let warning = wrongVendorWarning {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                        .padding(Spacing.sm)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                    }

                    // Wayfair image extraction count
                    if detectedVendor == .wayfair, !extractedThumbnails.isEmpty {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "photo.on.rectangle")
                                .foregroundStyle(BrandColors.primary)
                            Text("\(extractedThumbnails.count) images extracted from PDF")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                    }

                    // Budget category picker
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Budget Category")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Button {
                            showCategoryPicker = true
                        } label: {
                            HStack {
                                Text(categoryName ?? "No Category")
                                    .font(Typography.body)
                                    .foregroundStyle(categoryName != nil ? BrandColors.textPrimary : BrandColors.textTertiary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                            .padding(Spacing.sm)
                            .background(BrandColors.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Draft items list
                    DraftItemsList(items: $draftItems)

                    // Select different PDF
                    Button {
                        resetParse()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Select Different PDF")
                        }
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.primary)
                    }

                    // Debug report
                    if let stats = extractionStats {
                        ParseDebugReport(
                            rawText: rawPdfText,
                            stats: stats,
                            parseResultJson: parseResultJson
                        )
                    }
                }
            }
        }
    }

    // MARK: - Parse Logic

    private func processSelectedPdf(data: Data) {
        isLoading = true
        errorMessage = nil

        // Run extraction off main thread
        Task.detached {
            let textResult = PdfTextExtractor.extractText(from: data)

            await MainActor.run {
                isLoading = false

                guard let textResult, !textResult.fullText.isEmpty else {
                    errorMessage = "Could not extract text from PDF. The file may be image-based or corrupted."
                    return
                }

                rawPdfText = textResult.fullText
                extractionStats = textResult.stats

                // Auto-detect vendor
                let vendor = InvoiceImportCalculations.detectVendor(textResult.fullText)
                detectedVendor = vendor

                switch vendor {
                case .amazon:
                    let result = AmazonInvoiceParser.parse(textResult.fullText)
                    amazonParseResult = result
                    draftItems = InvoiceImportCalculations.buildAmazonDraftItems(from: result)

                case .wayfair:
                    let result = WayfairInvoiceParser.parse(textResult.fullText)
                    wayfairParseResult = result
                    draftItems = InvoiceImportCalculations.buildWayfairDraftItems(from: result)

                    // Extract thumbnails in background
                    Task.detached {
                        let thumbnails = PdfImageExtractor.extractThumbnails(from: data)
                        await MainActor.run {
                            extractedThumbnails = thumbnails
                            InvoiceImportCalculations.attachThumbnails(thumbnails, to: &draftItems)
                        }
                    }

                case nil:
                    errorMessage = "Unrecognized vendor. Amazon and Wayfair invoices are supported."
                }
            }
        }
    }

    private func resetParse() {
        selectedFileData = nil
        selectedFileName = nil
        detectedVendor = nil
        amazonParseResult = nil
        wayfairParseResult = nil
        draftItems = []
        wrongVendorWarning = nil
        extractionStats = nil
        rawPdfText = ""
        extractedThumbnails = []
        errorMessage = nil
    }

    // MARK: - Create Transaction

    private func createTransaction() {
        guard let accountId = accountContext.currentAccountId else {
            errorMessage = "No account found"
            return
        }

        isCreating = true
        errorMessage = nil

        let transactionsService = TransactionsService(syncTracker: NoOpSyncTracker())
        let itemsService = ItemsService(syncTracker: NoOpSyncTracker())

        let source = InvoiceImportCalculations.sourceString(
            vendor: detectedVendor,
            amazonResult: amazonParseResult,
            wayfairResult: wayfairParseResult
        )

        let txDate = InvoiceImportCalculations.transactionDate(
            vendor: detectedVendor,
            amazonResult: amazonParseResult,
            wayfairResult: wayfairParseResult
        )

        let totalCents = InvoiceImportCalculations.totalCents(
            vendor: detectedVendor,
            amazonResult: amazonParseResult,
            wayfairResult: wayfairParseResult
        )

        do {
            // 1. Create items, collect IDs
            var itemIds: [String] = []
            var createdItemIds: [String] = []

            for draftItem in includedItems {
                var newItem = Item()
                newItem.projectId = projectId
                newItem.name = draftItem.description
                newItem.purchasePriceCents = InvoiceMoneyParsing.parseCentsFromDollarString(draftItem.unitPrice)
                newItem.quantity = draftItem.qty
                newItem.source = source
                newItem.sku = draftItem.sku
                newItem.status = "active"
                newItem.budgetCategoryId = selectedCategoryId

                // Wayfair: append attribute lines to notes
                if let attrs = draftItem.attributeLines, !attrs.isEmpty {
                    newItem.notes = attrs.joined(separator: "\n")
                }

                let id = try itemsService.createItem(accountId: accountId, item: newItem)
                itemIds.append(id)
                createdItemIds.append(id)
            }

            // 2. Create transaction with itemIds
            var tx = Transaction()
            tx.projectId = projectId
            tx.transactionType = "purchase"
            tx.source = source
            tx.transactionDate = txDate
            tx.amountCents = totalCents
            tx.status = "pending"
            tx.itemIds = itemIds
            tx.budgetCategoryId = selectedCategoryId

            let txId = try transactionsService.createTransaction(accountId: accountId, transaction: tx)

            // Dismiss immediately (optimistic UI)
            dismiss()

            // 3. Background: Upload receipt PDF
            if let fileData = selectedFileData {
                Task {
                    do {
                        let filename = "\(UUID().uuidString).pdf"
                        let path = mediaService.uploadPath(
                            accountId: accountId,
                            entityType: "transactions",
                            entityId: txId,
                            filename: filename
                        )
                        let url = try await mediaService.uploadData(fileData, path: path, contentType: "application/pdf")
                        let fields: [String: Any] = ["receiptImages": [["url": url, "kind": "pdf", "isPrimary": true] as [String: Any]]]
                        try await transactionsService.updateTransaction(
                            accountId: accountId,
                            transactionId: txId,
                            fields: fields
                        )
                    } catch {
                        // Non-critical: receipt upload failure doesn't block import
                    }
                }
            }

            // 4. Background: Upload Wayfair thumbnails (max 4)
            if detectedVendor == .wayfair, !extractedThumbnails.isEmpty {
                let thumbnailsToUpload = Array(zip(createdItemIds, extractedThumbnails).prefix(4))
                Task {
                    for (itemId, placement) in thumbnailsToUpload {
                        guard let pngData = UIImage(cgImage: placement.image).pngData() else { continue }
                        do {
                            let filename = "\(UUID().uuidString).png"
                            let path = mediaService.uploadPath(
                                accountId: accountId,
                                entityType: "items",
                                entityId: itemId,
                                filename: filename
                            )
                            let url = try await mediaService.uploadData(pngData, path: path, contentType: "image/png")
                            let fields: [String: Any] = ["images": [["url": url, "kind": "image", "isPrimary": true] as [String: Any]]]
                            try await itemsService.updateItem(
                                accountId: accountId,
                                itemId: itemId,
                                fields: fields
                            )
                        } catch {
                            // Non-critical
                        }
                    }
                }
            }
        } catch {
            isCreating = false
            errorMessage = "Failed to create transaction: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func amazonParseResultToJson(_ result: AmazonInvoiceParser.ParseResult) -> String {
        let dict: [String: Any?] = [
            "orderNumber": result.orderNumber,
            "orderPlacedDate": result.orderPlacedDate,
            "grandTotal": result.grandTotal,
            "tax": result.tax,
            "shipping": result.shipping,
            "itemCount": result.lineItems.count,
            "warnings": result.warnings,
        ]
        let filtered = dict.compactMapValues { $0 }
        guard let data = try? JSONSerialization.data(withJSONObject: filtered, options: .prettyPrinted) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func wayfairParseResultToJson(_ result: WayfairInvoiceParser.ParseResult) -> String {
        let dict: [String: Any?] = [
            "invoiceNumber": result.invoiceNumber,
            "orderDate": result.orderDate,
            "orderTotal": result.orderTotal,
            "subtotal": result.subtotal,
            "shippingDeliveryTotal": result.shippingDeliveryTotal,
            "taxTotal": result.taxTotal,
            "adjustmentsTotal": result.adjustmentsTotal,
            "itemCount": result.lineItems.count,
            "warnings": result.warnings,
        ]
        let filtered = dict.compactMapValues { $0 }
        guard let data = try? JSONSerialization.data(withJSONObject: filtered, options: .prettyPrinted) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
