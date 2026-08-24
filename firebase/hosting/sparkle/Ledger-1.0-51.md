# Ledger 1.0 (51)

- Improves browsing responsiveness and stability in large projects by reducing repeated list work, duplicate listeners, and unnecessary Firestore decoding.
- Prevents full-size image decoding from blocking the macOS interface and limits the image viewer to loading the active image at full resolution.
- Improves image cache accounting and listener cleanup to reduce memory pressure during extended browsing.
- Counts client payments toward received fee budgets so project budget totals stay accurate.
- Checks for macOS updates promptly and continues checking automatically in the background.
