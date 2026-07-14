# SKU extraction architecture

`ItemTagExtraction` is a pure evidence generator. OCR is split into tokens before
normalization; each token is normalized independently and comparisons use exact
token equality. It emits accepted and rejected `ItemTagCandidate` values with OCR
engine, image, extraction method, confidence, supporting TJX department/price,
and rejection reason. Evidence for the same value is aggregated rather than
discarded, so cross-image and cross-engine agreement remains inspectable. Raw OCR,
accepted/rejected evidence, review flags, and engine events are persisted in the
proto-item extraction payload using additive optional fields.

Ranking is conservative: corroborated TJX barcode + visible fields ranks first,
then labeled fields, vendor-formatted receipt lines, and finally generic OCR.
Prices, date/FLS codes, dimensions, administrative fields, and known malformed
label fragments are rejected before ranking. Multiple strong values and engine
disagreement produce review flags rather than a selection.

TJX/HomeGoods decoding accepts a 14-digit `DD + SSSSSS + PPPPPP` barcode only
when visible tag vocabulary is present, `DEPT` agrees with `DD`, any visible
`STYLE` agrees with `SSSSSS`, and a visible price agrees with `PPPPPP`. Missing
corroboration stops extraction without guessing.

`ItemTagSkuSelectionPolicy` converts ranked evidence into a recommendation;
`ItemTagSkuMutationPolicy` is the only layer that turns that recommendation into
a field update. It can populate an empty SKU from one strong candidate, preserves equal
values, and sends every conflicting populated value to review. OCR alone never
overwrites an existing SKU, including barcode-backed or visually confirmed data.

Engine routing is explicit: Vision is primary for full-resolution phone photos
and table-photographed long receipts; the Tesseract/import adapter is primary for
clean scans, PDF renders, and tight crops. The iOS capture service currently has
Vision available in-process and records an explicit fallback event when a
Tesseract-primary profile reaches that target. The first pass is full-image only.
Only when it finds tag vocabulary or price evidence without a strong STYLE does a
second pass OCR orientation-normalized, upscaled tag/barcode-adjacent crops. An
exhausted retry returns a review flag and no guess.
