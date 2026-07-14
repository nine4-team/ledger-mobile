# Category Type Migration Run

Mode: dry-run
Project: ledger-nine4
Accounts: 5
Remove legacy fields on commit: no

## Totals

- Categories scanned: 27
- Categories needing write: 20
- Categories with supportedTypes: 13
- Categories with mixed supportedTypes: 0
- Categories missing metadata.categoryType: 15
- Categories with legacy standard: 2
- Categories with itemizationEnabled: 0
- Project category copies with behavior fields: 0
- Affected transactions: 3

## Proposed Category Types

- fee: 6
- general: 14
- itemized: 7

## Review Rows

- Install (10fef89a-13dc-4532-83dc-819d02111cec): general -> general; tx=0; completeness changes=0; risk=low; reviewed target: install labor/service cost
- Storage & Receiving (10fef89a-13dc-4532-83dc-819d02111cec): general -> general; tx=0; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- Install Supplies (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): itemized -> general; tx=3; completeness changes=3; risk=review; reviewed target: supplies stay general
- Additional Requests (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): itemized -> itemized; tx=1; completeness changes=0; risk=low; reviewed target: usually furnishings/add-ons
- Games and Entertainment (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> itemized; tx=0; completeness changes=0; risk=low; reviewed target: itemized category
- Storage & Receiving (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=2; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- Design Fee (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): fee -> fee; tx=9; completeness changes=0; risk=low; reviewed target: business revenue/payment category
- Kitchen (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=4; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- Furnishings (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): itemized -> itemized; tx=547; completeness changes=0; risk=low; reviewed target: item rows expected
- Install Services (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=7; completeness changes=0; risk=low; reviewed target: labor/service cost
- Install (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=2; completeness changes=0; risk=low; reviewed target: install labor/service cost
- Fuel (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=13; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- Storage & Receiving (2d612868-852e-4a80-9d02-9d10383898d4): general -> general; tx=3; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- Install (2d612868-852e-4a80-9d02-9d10383898d4): general -> general; tx=1; completeness changes=0; risk=low; reviewed target: install labor/service cost
- Install (bb0bf594-d31a-45b9-b56c-fb4722f74f54): general -> general; tx=0; completeness changes=0; risk=low; reviewed target: install labor/service cost
- Storage & Receiving (bb0bf594-d31a-45b9-b56c-fb4722f74f54): general -> general; tx=0; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- The (vUcrIZfFV0QaFaFMO84a): fee -> fee; tx=0; completeness changes=0; risk=low; temporary derivation from legacy supportedTypes
- Design Fee (vUcrIZfFV0QaFaFMO84a): fee -> fee; tx=0; completeness changes=0; risk=low; reviewed target: business revenue/payment category
- Install (vUcrIZfFV0QaFaFMO84a): general -> general; tx=0; completeness changes=0; risk=low; reviewed target: install labor/service cost
- Storage & Receiving (vUcrIZfFV0QaFaFMO84a): general -> general; tx=0; completeness changes=0; risk=low; reviewed target: non-itemized project cost
