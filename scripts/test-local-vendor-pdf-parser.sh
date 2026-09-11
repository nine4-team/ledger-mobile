#!/bin/bash
# Actual PDFKit/adapter fixtures; no application, network, or backend involved.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo 'Requires Apple Silicon macOS with Xcode command-line tools.' >&2
  exit 1
fi
fixture_dir="$(mktemp -d "$repo_dir/.local-vendor-pdf-fixtures.XXXXXX")"
trap 'rm -rf -- "$fixture_dir"' EXIT
# Compile the dependency-free Core directly. No SwiftPM resolution or app build;
# current source is used even when an existing package cache is stale.
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macosx14.0 \
  -whole-module-optimization -Onone -module-name LedgerTargetCore \
  -emit-module -emit-module-path "$fixture_dir/LedgerTargetCore.swiftmodule" \
  -emit-object LedgeriOS/LedgerTargetCore/*.swift -o "$fixture_dir/LedgerTargetCore.o"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macosx14.0 \
  -I "$fixture_dir" -module-name LedgerTargetAppModel \
  -emit-module -emit-module-path "$fixture_dir/LedgerTargetAppModel.swiftmodule" \
  -emit-object LedgeriOS/LedgerTargetAppModel/LocalVendorDocumentReview.swift \
  -o "$fixture_dir/LocalVendorDocumentReview.o"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macosx14.0 \
  -I "$fixture_dir" \
  LedgeriOS/LedgerTargetApp/LocalVendorPDFParser.swift \
  LedgeriOS/LedgerTargetApp/LocalVendorPDFThumbnailExtractor.swift \
  LedgeriOS/LedgeriOS/Logic/AmazonInvoiceParser.swift \
  LedgeriOS/LedgeriOS/Logic/WayfairInvoiceParser.swift \
  LedgeriOS/LedgeriOS/Logic/InvoiceMoneyParsing.swift \
  LedgeriOS/LedgeriOS/Logic/InvoiceDateParsing.swift \
  LedgeriOS/LedgeriOS/Logic/PdfTextExtractor.swift \
  scripts/tests/LocalVendorPDFParserFixtureTests.swift \
  "$fixture_dir/LocalVendorDocumentReview.o" \
  "$fixture_dir/LedgerTargetCore.o" \
  -o "$fixture_dir/local-vendor-pdf-fixtures"
"$fixture_dir/local-vendor-pdf-fixtures"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macosx14.0 \
  LedgeriOS/LedgerTargetApp/LocalVendorPDFThumbnailExtractor.swift \
  scripts/tests/LocalVendorPDFThumbnailFixtureTests.swift \
  -o "$fixture_dir/local-vendor-thumbnail-fixtures"
"$fixture_dir/local-vendor-thumbnail-fixtures"
