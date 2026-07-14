# Category Type Migration Run

Mode: commit
Project: ledger-nine4
Accounts: 5
Remove legacy fields on commit: yes

## Totals

- Categories scanned: 27
- Categories needing write: 13
- Categories with supportedTypes: 13
- Categories with mixed supportedTypes: 0
- Categories missing metadata.categoryType: 0
- Categories with legacy standard: 0
- Categories with itemizationEnabled: 0
- Project category copies with behavior fields: 0
- Affected transactions: 0

## Proposed Category Types

- fee: 6
- general: 14
- itemized: 7

## Review Rows

- Install Supplies (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=3; completeness changes=0; risk=low; reviewed target: supplies stay general
- Additional Requests (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): itemized -> itemized; tx=1; completeness changes=0; risk=low; reviewed target: usually furnishings/add-ons
- Games and Entertainment (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): itemized -> itemized; tx=0; completeness changes=0; risk=low; reviewed target: itemized category
- Storage & Receiving (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=2; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- Design Fee (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): fee -> fee; tx=9; completeness changes=0; risk=low; reviewed target: business revenue/payment category
- Kitchen (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=4; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- Furnishings (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): itemized -> itemized; tx=547; completeness changes=0; risk=low; reviewed target: item rows expected
- Install Services (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=7; completeness changes=0; risk=low; reviewed target: labor/service cost
- Install (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=2; completeness changes=0; risk=low; reviewed target: install labor/service cost
- Fuel (1dd4fd75-8eea-4f7a-98e7-bf45b987ae94): general -> general; tx=13; completeness changes=0; risk=low; reviewed target: non-itemized project cost
- The (vUcrIZfFV0QaFaFMO84a): fee -> fee; tx=0; completeness changes=0; risk=low; existing valid metadata.categoryType
- Design Fee (vUcrIZfFV0QaFaFMO84a): fee -> fee; tx=0; completeness changes=0; risk=low; reviewed target: business revenue/payment category
- Storage & Receiving (vUcrIZfFV0QaFaFMO84a): general -> general; tx=0; completeness changes=0; risk=low; reviewed target: non-itemized project cost
