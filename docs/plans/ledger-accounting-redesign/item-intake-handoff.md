# Item Intake and Linking — Source Handoff

Status: incorporated into the Ledger Accounting Redesign program
Source task: `codex://threads/01a0550b-55ea-7d41-b091-63b53560f2cf`
Last synchronized: 2026-08-31

This file preserves the source conversation, implementation discoveries, and
artifact ownership for the Quick Add / proto-item redesign. The canonical
product behavior now lives in
[Item Creation and Accounting Link](../../specs/proto-item-capture.md). Program
sequencing lives in [Implementation Tracker](implementation-tracker.md).

Later user messages supersede earlier terminology and proposals. The current
authority is one unified Item-creation wizard plus **Unaccounted For Items /
Accounted For Items / Link**. This supersedes both **Needs Assignment / Items /
Assign** and **Unlinked Items / Linked Items**. The Link question has only
**Client paid** and **Business paid**.

## Raw User Product Messages

The following messages are preserved verbatim and in chronological order.
Delegation envelopes, environment context, and tool instructions are omitted.

### 1. Initial redesign request

```text
we have some thoughts around redesigning our proto-item and item situation.  "So another thought I have is for quick draft items. Usually when my mom goes in and like she's just recently bought them, she has an idea of whether it was purchased by her or by the client. It's not always accurate, but maybe in quick draft items, we can have options for like, was this purchased by you or by the client? And if it's anything from us or if it came from inventory, or even if it was like she bought everything,
&#x20;on that transaction for that client, but it was paid for by the business, then like when she's adding in the quick draft, she can just put it in either section. Or there's like something to say like, this was from the client, this was from us, and then they can just go into their own areas of transactions and invoices. I don't know, that one wasn't super clear of.*&#x20;We could probably get rid of quick drafts and just relax the requirements for item creation. And then just introduce maybe some things that help us track which items are complete or not. But if we were to simplify this, get rid of this quick draft item,There's this section where items get added in. This is what she's imagining. Oh, yeah. This is what I'm envisioning. So there's a section that has the items that get dumped into the car. And I'm trying to follow this with the process of at least our lead designer and what I imagine a lot of designers are probably doing, where if they're going shopping, they're bringing it in, and then they're taking items into the project.*
&#x20;They're going to have pictures of these items, and they can log them, and it's living almost in this middle section of like, hey, this is here at the project. And then after everything is in, that's when either the designer or an assistant can go and attach those items either to a transaction that the client paid for in the transaction section of the project, or identify that it's an inventory item and attach it to the invoice.
&#x20;And for context, another agent is working on a feature that is taking some of the work that currently is done in transactions and moving it over into invoices. So don't worry about that.&#x20;
&#x20;item idea. The main designer, they've gotten used to using the quick draft tool and so the process. And so we would want the process to be similar for the simplified item, the new flow for items. So it should look very similar and like maybe it would be a two-step thing where the first step is kind of the current item.
&#x20;It's a different quick draft process, but then maybe step two is more. I don't know. And we don't have to make it, make the new design preserve the old processes as much as I'm making it sound. We can and probably would make changes to the simplified process, but the goal would be let's deviate as little.
&#x20;We can and probably make it sound as possible as possible from the quick draft experience. So I think the current design, how the quick draft items are at the top of the item list and then the real items are below. The only thing I would change is the top is no longer quick draft items. Like they are actual items. We don't have to work on converting them. It's the same format. It's just those items live at the top because they haven't been tied to a transaction or an invoice yet. So when we...
&#x20;open it up, I think we should still see those uncategorized ones at the top and then once they've been assigned, they go down to the bottom and the goal will always be get all the items into the bottom section and then from the bottom section, you can go and assign them to spaces and everything like that. But I guess we should probably allow people to assign the top items to spaces as well. I don't want to prevent them from doing that just because they haven't assigned
&#x20;a transaction to it, but even if they're assigned to spaces, they should just live in that top section before they are assigned to a transaction or invoice.
```

### 2. Reconcile with the invoice-centered redesign

```text
we shoud look at the redesigned invoicing etc system in codex://threads/01a05033-f5e2-7582-8fa9-90e45c149338 before we finalize our design, because if we take an unassigned item and then select the operation that is supposed to send it through theappropriate path for items "sold" from business inventory to the project, then what that means inthe new system is that the item will go into the items section of our billables area (to invoice area) rather than going onto a 'canonical' sale transaction from inventory to project (like we have now).  does efverything i said make sense or are we not on teh same page w\.r.t. specs?  especially this notion that an unassigned item can be push-buttoned into the 'business selling to project' flow.
```

### 3. Reject backend-jargon explanation

```text
idk wtf this means: Resolve existing inventory evidence
or create the real inventory acquisition
&#x20;       ↓
```

### 4. Reject fabricated background-record explanation

```text
this also doesn' tmake any sense: If Ledger already knows about the Item in Business Inventory, it uses that Item. If not, Ledger creates the necessary background records.
```

### 5. Confirm one physical Item identity

```text
you're not referring to separate item records here, are you? Normal project Item
\+ billable Item in Invoicing

or are you?   unclear on the data structures here
```

### 6. Reject accounting-mechanics action label

```text
I'm not sure "Sell from Business Inventory" is the most user friendly phrase.   could easily lead to confusion
```

### 7. Request the complete interaction

```text
show me the full ui/ux flow for assignment q -> finish
```

### 8. Finalize the two Link branches

```text
Yeah, the basic flow is, for the first question, don't have the not sure yet option. If client paid, they just get prompted to pick the transaction. I like the optional space assignment. Yeah, that's great. But in your little example, it says from our inventory, which is wrong for this branch. And then for the we paid,
&#x20;or business paid would be better. Yeah. Use the word businesses instead of we. We should let them choose a transaction from business inventory, but they don't have to. Otherwise, I like what you're saying here.
```

### 9. Finalize user-facing taxonomy

```text
We can call items that have not yet been assigned to either a project transaction or to the list of billable items for the project. We can call those unlinked items.
&#x20;And then items that have, call them linked items. And then the primary action for unlinked items is link.
```

### 10. Unify Item creation, preserve production, and rename the sections

```text
Quick becomes a capture method, but not a separate capture method from items. I shouldn't say that they don't share part of the creation pathway. I think it makes sense to have a single wizard for creating items, whether it's single step or two step,
&#x20;but just make the items used for the proto item system that we're getting rid of. Make those be the required fields, make those be the fields that are at the top so the user sees those first so that the experience feels familiar. But if they want to add more stuff, they can. And then when you say accounting assignment, I think you just mean if the item is assigned to a transaction in a project or put into the billables section. So if that's what you mean, that's correct.&#x20;

Okay, now that we have the features we want to change, what I want to do is I want to be able to change these things and not have it affect the production system. So we need to identify any database changes that would interfere with pre-update users doing their work. So, like, we wouldn't want to delete the database
&#x20;structures that underlie our proto-items, for example, even though we're getting rid of those for this next version. So, I think that's my main concern is that we, is that if we
&#x20;touch the database, it's not in a way that is going to destroy any of the functioning features in the current production app. Otherwise, you know, I think our changes can just be local. I mean, even if we commit them, we should
&#x20;deploy them. Also, I think we've been working out a dev and what we should probably do is we should update prod and then go back to dev for this big update.

I think for the name of our item sections, instead of unlinked and linked, we should say unaccounted for and accounted for. Unaccounted for items and accounted for items.
```

## Current Product Model

- Item creation uses one wizard. **Quick** describes completing the lightweight
  top portion of that wizard, not a second object type or separate creation
  pathway.
- The former proto-item capture fields appear first and define the minimum
  savable Item; users may continue into optional details.
- The new version writes real Items. It does not create new proto items, expose
  a draft/conversion lifecycle, or require a later promotion step.
- **Unaccounted For Items** have not yet been connected to either a client-paid project
  Purchase or the project's billable Items list.
- **Accounted For Items** have reached one of those two destinations.
- **Link** is the primary action. Dismissing Link leaves the Item unaccounted
  for.
- Link asks only **Client paid** or **Business paid**. There is no **Not sure
  yet** choice because remaining unaccounted for already represents that state.
- **Client paid** requires choosing the project Purchase that records the
  client's actual payment.
- **Business paid** may optionally associate the Item with a Business Inventory
  Purchase, then links the same physical Item to an open Item charge under
  Invoicing. It creates no project Transaction until Invoice collection.
- The physical Item and its billable charge are different records with different
  responsibilities. The charge references the one Item; Ledger does not create
  a second “billable Item.”
- Space is independent. An Item may be assigned to a Space before or after Link,
  and Space never determines linked state.
- Inventory-sale language describes hidden accounting provenance, not the
  designer's action. Do not label the action “Sell from Business Inventory.”

## Confirmed Versus Unresolved

### User-confirmed

- Use one Item-creation wizard. Put the familiar proto-item capture fields first
  as the minimum savable portion, then allow optional additional details.
- Stop new-version proto-item creation while preserving the legacy database
  collection and compatibility needed by pre-update users.
- Show unresolved Items above resolved Items.
- Use **Unaccounted For Items**, **Accounted For Items**, and **Link**.
- Link has Client-paid and Business-paid branches only.
- Client-paid Link immediately asks for a project Transaction.
- Business-paid Link may select a Business Inventory Transaction, but selection
  is optional.
- Business-paid Items enter Invoicing → Items rather than creating the legacy
  project inventory-movement Transaction.
- One physical Item identity is shown in Project Items and referenced by
  Invoicing; there are not two Item records.
- Space assignment is optional and independent.

### Derived implementation recommendations

- Keep legacy Firebase `protoItems` data, rules, indexes, readers, and current
  client writers functional before the hard-cutover source freeze. The target
  does not use `protoItems` for creation or runtime dual-read; rehearsed export
  migration resolves them into real target Items.
- Derive “missing information” guidance rather than persist one fragile
  `isComplete` flag. Only accounting Link state controls top-versus-bottom
  placement.
- Treat Match Existing Item as an explicit duplicate/evidence-reconciliation
  tool, not a mandatory step in normal Link.
- Preserve old enum/field decoding in source export/import fixtures while the
  isolated target is tested; do not add target semantics or readers to Firebase.

### Unresolved

- When Business paid is linked without selecting a Business Inventory Purchase,
  what exact record represents the still-missing acquisition evidence? The Link
  operation must not invent a vendor Purchase.
- Should Quick Add retain any optional, reversible payer hint, or defer the
  Client/Business choice entirely until Link? The provisional four-way hint is
  not final authority.
- What migration converts or resolves existing open `protoItems` into real
  Items, and when can old proto writers finally be rejected?
- What is the exact duplicate/matching workflow for a Quick Added Item that later
  overlaps receipt- or MCP-created evidence?

## Current-Code Constraints

- `ItemsService` currently requires a project Item to have a real project
  category. Persisting incomplete project Items directly would affect budget,
  reporting, billing, search, and inventory assumptions.
- `ProtoItem` is a separate collection ignored by authoritative Item and
  accounting calculations. The new version stops creating it, but compatibility
  code must keep existing documents and pre-update writers functional until a
  deliberate cutover.
- `Item.transactionId` currently overloads acquisition, project membership, and
  movement history. It cannot represent acquisition, placement, open billing,
  and paid membership in the target model.
- The shipped inventory-to-project writer creates a project Purchase and moves
  `item.transactionId`; the target must instead create an open Item charge and
  hidden provenance without a project Transaction.
- The current transaction picker searches one caller-supplied array; any scoped
  UI must enforce exact project or Business Inventory eligibility itself.
- Item project price is normalized to be at least purchase price. Target unpaid
  repricing must recalculate the open Item charge and any live Invoice while
  leaving vendor purchases and paid snapshots unchanged.
- Existing conversion paths perform multi-record writes atomically. Target Link
  must retain atomicity and idempotency across Item identity, acquisition link,
  charge/provenance creation, media transfer, category, and internal capture
  completion.

## Artifact Inventory and Ownership

The source task materially edited the following files. Because multiple agents
share this working tree, do not revert any file wholesale; reconcile by hunk.

### Canonical/supporting documentation after central reconciliation

- `docs/specs/proto-item-capture.md` — canonical target behavior for unified Item
  creation, Unaccounted For/Accounted For, Link, and proto compatibility.
- `docs/specs/items.md` — supporting Item invariants and target-linking note.
- `docs/plans/ledger-accounting-redesign/item-intake-handoff.md` — source record
  and ownership map (this file).

### Provisional iOS implementation; not target-authoritative

- `LedgeriOS/LedgeriOS/Components/ItemDraftCard.swift`
- `LedgeriOS/LedgeriOS/Logic/TransactionMenuBuilder.swift`
- `LedgeriOS/LedgeriOS/Models/ProtoItem.swift`
- `LedgeriOS/LedgeriOS/Views/Creation/ItemDraftCaptureSheet.swift`
- `LedgeriOS/LedgeriOS/Views/Creation/NewItemView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ItemQuickDraftDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/ItemsTabView.swift`
- `LedgeriOS/LedgeriOS/Views/Projects/TransactionDetailView.swift`
- `LedgeriOS/LedgeriOS/Views/RootView.swift`
- `LedgeriOS/LedgeriOSTests/ModelCodableTests.swift`

These changes add `assignmentHint`, `spaceId`, scoped transaction selection,
friendlier language, and atomic promotion improvements. They were implemented
against the earlier separate Quick Add plus **Needs Assignment / Assign** model
and the legacy movement-Transaction writer. Preserve useful field ordering,
media capture, and atomic mechanics, but replace the separate creation path,
terminology, and accounting effect.

### Provisional MCP implementation; not target-authoritative

- `mcp-server/src/tools/quick-draft-items.ts`
- `mcp-server/src/tools/schema.ts`
- `mcp-server/src/types.ts`
- `mcp-server/src/util/enums.ts`
- `mcp-server/src/util/projections.ts`
- `mcp-server/test/item-image-tool-schema.test.ts`

These mirror the provisional hint/space model and still expose Quick Draft
concepts in places. They require compatibility-preserving Link terminology and
target accounting writers before deployment.

### Mixed/superseded documentation edits from the source task

- `docs/specs/_app-map.md`
- `docs/specs/_index.md`
- `docs/specs/data-model.md`
- earlier hunks in `docs/specs/items.md`
- earlier hunks in `docs/specs/proto-item-capture.md`

The central program and reconciled canonical specs supersede any wording in
these files that promises a project inventory-movement Transaction or uses
Needs Assignment as final terminology.

### Design artifact

- `/Users/benjaminmackenzie/.codex/visualizations/2026/08/30/01a0550b-55ea-7d41-b091-63b53560f2cf/item-assignment-flow.html`

This clickable mockup established the two branches and optional Business
Inventory transaction, but its **Needs Assignment / Assignment** labels are
superseded. It is reference material, not a product contract.

## Verification Already Performed on the Provisional Work

- Plain `LedgeriOS` iOS Simulator build passed.
- `ModelCodableTests` passed.
- MCP TypeScript build passed.
- MCP item-image/schema tests passed (2/2).

Those results prove that the provisional changes compiled at that point. They
do not verify the target invoice-centered Link behavior, migration, stale-client
compatibility, or production data.

## Integration Dependencies

Target Link implementation depends on:

1. the categorized No-Transaction real Item shape plus compatible accounting
   projections for Unaccounted For Items;
2. the Item charge/credit occurrence schema;
3. separation of Item acquisition, current placement, open billing, and paid
   membership;
4. the Invoice Items source and whole-Invoice collection writer;
5. the global Purchase/Return/Transfer taxonomy;
6. the Furnishings budget authority and unpaid/paid segment calculator;
7. compatibility rules for existing `protoItems`, `assignmentHint`, and old MCP
   writers; and
8. an explicit answer for Business-paid Link without selected acquisition
   evidence.
