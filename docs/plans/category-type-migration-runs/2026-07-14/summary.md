# Category Type Migration Run

Mode: dry-run
Project: ledger-nine4
Accounts: 1
Remove legacy fields on commit: no

## Totals

- Categories scanned: 10
- Categories needing write: 10
- Categories with supportedTypes: 10
- Categories with mixed supportedTypes: 0
- Categories missing metadata.categoryType: 8
- Categories with legacy standard: 0
- Categories with itemizationEnabled: 0
- Project category copies with behavior fields: 0
- Affected transactions: 3

## Proposed Category Types

- fee: 1
- general: 6
- itemized: 3

## Review Rows

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
