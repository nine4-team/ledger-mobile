# Ledger Specs — Feedback Log

## 2026-04-14

### Raw Feedback (sell-to-inventory regression)
"We need to restore the flow that allows us to sell to inventory… an item can originate as part of a project and we can sell it to inventory. So this is a… whenever this change happened, that was a huge deviation from spec. We need a plan to remediate that and we need a naming convention that makes it clear which direction one of these sale transactions corresponds to. The return thing is only relevant if an item comes from inventory into a project and then it goes back to inventory." Follow-up: "we already have source fields we can and should already be using for this" (origin detection). "The direction should be explicit, but it should not be in the form of a badge. I want you to propose a naming convention per my original ask."

### What I Did With It
- Restored `sellToInventory` in `InventoryOperationsService`. Added `moveToInventory` for origin-aware routing — items with `currentSource != source` take the Return path; items with `currentSource == source` (never touched inventory) take the Sale-to-Inventory path. Mixed batches write both atomically.
- Refactored `moveBetweenProjects` so hop 1 branches by origin (Return for from-inventory items, Sale-to-Inventory for originated-here items).
- Naming convention in `TransactionDisplayCalculations.displayName(for:)`:
  - Sale with `budgetCategoryId` set → `"Purchase from [source]"`
  - Sale without `budgetCategoryId` → `"Sale to [source]"`
  - Return → `"Return to [source]"`
- Direction is **implicit in the transaction shape**. No new field.
- Updated specs: `sale-transactions.md`, `inventory-as-store.md`.

---

## 2026-04-02

### Raw Feedback
The first change that I want to make is in the desktop app. This is in anywhere that has items and transactions. I really liked it when they were just stacked, not in the blocks. I think I rather the long block where there's only one per row. So I'm going to have that be the first item of feedback and I'm open to exploring if that doesn't make sense but I think it's easier when I'm trying to track things to be able to be like okay it's this one like this is before and after versus trying to remember the row and the column so rather than the tiles I like it in a just one per row. To be specific, I really liked the feel of it in the web app. And I think we should go back to having it look like that in the desktop app.

### Screenshots
None provided.

### What I Did With It
- Created `list-layout.md` spec covering the switch from tile/grid layout to single-column rows in the desktop app
- Set up initial specs folder structure, index, app map, and changelog

---

### Raw Feedback (follow-up)
Oh okay, I kind of really like that idea about having a little toggle to where a user can switch to grid or list mode. That's really cool. I know Apple does that with a lot of their stuff like in Finder where you can swap. That way it's like personal preference. So I like that idea. And then I think this just applies to the desktop mobile. We can't do um, we can't really do gallery anyways and mobile looks good. So just for the desktop app for this, but I really like that idea of being able to switch. So let's, let's add that. I will say it's not a must have. That would be a nice to have. So yeah, the little toggle thing, that's like an extra thing. If it's not too hard, they'd be so cool, but not a must have.

### What I Did With It
- Updated `list-layout.md`: added list/grid view toggle as a nice-to-have enhancement (inspired by Apple Finder), clarified scope to desktop app only, resolved open questions about gallery view and mobile

---

### Raw Feedback (color and styling)
Sweet. Okay, and this is a little silly, but I love the coloring of the web app, and I don't like the feel in the desktop app. So far, I think the mobile app looks better. There's still, Okay, I think the red that we used in the mobile app feels a little dingy. I can see where it was trying to feel like a more sophisticated red, but it just feels almost gloomy, which is silly. I don't know how to better describe it, but the coloring of like the coloring of the red and the green and yellow, I really liked it in the web app. And specifically on the desktop app, Some of the differences is it has like more harsh black lines outlining everything. And I don't like the feel of that. I really liked the lighter, just like dimensional looking colors in the web app. So if we can change. The like the color way to have not the black harsh lines around everything and. have it feel almost like a little sleeker and around the like around different toggles. There's like this extra thick black border. It's almost like it's showing through an accident. I don't love the look and feel of that. So I would like to go back to more of the look and feel of the buttons and the tiles and the background in the web app.

### Screenshots
None provided.

### What I Did With It
- Created `visual-style.md` spec covering color palette and border/outline styling changes for desktop and mobile apps, using the web app as the reference

---

### Raw Feedback (styling follow-up)
I kind of think it's like a bug that's leaking through because they're not consistent in thickness in the, at least in the toggles. They do look like they're a theme for the individual cards so that I would want to just change. But in the toggles specifically it looks like there's some black that's showing through and it just doesn't feel as... clean

### What I Did With It
- Updated `visual-style.md`: clarified that the toggle borders are likely a rendering bug (inconsistent thickness), while the card borders are intentional theming that should be restyled

---

### Raw Feedback (search details)
Sweet, another thing I'd like to add is more detail in the search section. currently when there's any item searched across the app in the designated search page, I can't see any details about where the item is located (project, space, inventory, etc.), which transaction it's tied to, who purchased it (if it says purchased by client, I don't know which client) so that would be nice to somehow incorporate more mapping details in there.

### Screenshots
None provided.

### What I Did With It
- Created `search-results.md` spec for adding contextual/mapping details to search results (location, transaction, purchaser/client info)

---

### Raw Feedback (search clarification)
Quick clarification, I think it's fine if the who it was purchased by stays being Client or business, as long as we can see which client's project it's in. And for the details, it doesn't even have to be in the search results, but if we click on the item itself, we should be able to see all the mapping and locations/details for it.

### What I Did With It
- Updated `search-results.md`: purchaser field can stay as "Client" or "Business" (no need to show specific client name) as long as the client's project is visible. Moved detailed mapping info from the search result row to the item detail view — clicking into an item should show all location/mapping details.

## 2026-04-03

### Raw Feedback
Okay, Claude, I have some...well, I have an idea around billing and transactions that I want to talk through with you, but I don't have it flushed out. So as I go through, I don't want you to just agree with me and say that it's good, but it kind of helped me figure out how to best design it, guide me through this process. And...yeah, help me. kind of flush out this idea but realized right now we currently have stuff that the design business either pays for or that we are selling from our inventory that's all going into a transaction per budget which I like so far but I'm realizing that if we are putting a ton of money out on some these projects, I don't want to have to wait till the end of a project to bill. Like, ideally, we'll build some things throughout. Like, for example, if we spend six grand on mattresses, I don't need to wait till the end to bill that. I can bill early on for the six grand. Oftentimes, we'll wait for some of the accessories to make sure that the clients actually like them. We don't have to do when it returns, but there might be instances where like we've already confirmed that they like some of the bigger items that we put in and we might want to build that sooner. And then it gets a little confusing in the app. Well, I can see how it would get confusing to be like, what has actually been collected on and what hasn't. So we were brainstorming how to go about that. And part of me is thinking we just kind of treat it like a tab. Like at a bar where. We start putting stuff over and then if throughout the project, I'm like, okay, you know what? It's time to bill on this. If we actually collect on it and close it, then that like closes that tab out and starts a new one when we bring items over from inventory. Um, so I'm not entirely sure how to go about that, but that's something. And then the other thing that I was thinking about that ties into this is right And now there's multiple ways to essentially say like the business paid for something. We can add stuff directly into the project and just say business own, like business purchased it and that the clients owe us. Or we can add things into inventory and then move it over. And then it's like a sale. And I would like to simplify it and make it to where there's just one path that items go. And if we do a shopping trip and we have a big transaction and every single item on that transaction is going towards this one project, I think instead of putting it in the project and marking it as the business paid for it and that they owe us, I think it should go into inventory and then have a section in inventory that says like, do you want to sell this whole transaction to a project or do you want to select items and sell to a project? Like while we're actually inputting it and then that way like it's just a one-step thing but it's still going through that same pathway of like into inventory first then selling to the clients. Where it gets a little tricky and confusing is when it comes to stuff like let's say fuel we were supposed to put fuel on their card but didn't have their cards we paid for it and need to reimburse for it or like an install crew. We paid them, but then we need to collect from our clients and it's not like a physical thing that we're selling. It's more of like a thing to complete the service. So I would actually love some ideas of how to kind of clean that up and then how we make it possible to build for some of those things in the middle of the project and have some of it at the end. I definitely need some guidance around how to map this out. But I think if we can get it really clean, it can make the app feel more simple and make it easier and less confusing how to track what we've actually build them for and what we still need to build them for while still seeing overall how much has essentially been spent in the project.

### Raw Feedback (follow-up, refining category-based routing)
So one thought about these two entry paths... I think that we can have different paths for different categories, like anything that is an itemized category, like furnishings or additional requests, that should be an inventory first and then move over. But things that don't get itemized should be able to go directly into. [...] what I want to avoid is Path A [direct to project for itemized items]. But keep Path B for itemized things. And then for anything like install crew or fuel and like items that are just expenses, not items, that could be going directly into the business. And maybe how we do it is on the transaction creation — the first thing is what category are we working in? And if it's an itemized category, then that gives us options for like, you know, like, we put in all the details and then at the bottom we confirm, like, is this inventory meaning we purchased it or is this going right into a project? And if it's inventory, that's when another thing comes up where it's like, do you want to sell this whole inventory transaction to a project or do you want to select any items and sell to a specific project? That would be really cool. But then at the beginning, if we don't select one of the itemized categories, but let's say we select install or fuel, then I think for those things, it shouldn't even be an option of like, does this go into inventory? We should just say which project does it go into? And that's where we have who purchased it so that we can either confirm if we need to build them for it or not.

### Raw Feedback (follow-up, billing approach)
What if everything that we sell to them on the physical things to sell side have ways that we can like essentially check from the transaction, like check all the items that have been approved that we want to bill for and then generate an invoice for that [...] everything comes over into one transaction when we're ready to bill for the items that have been approved because you're right some things will get approved before we know — smaller things we usually wait till end. So we go through, highlight the larger things that we have gotten approval on, select everything, and then can generate an invoice for that. And once that's been paid, it almost, I wonder if it could pull them out at that transaction and create a separate transaction of like, okay, this is paid for. And then we have one transaction that still has all the remaining stuff that can be paid by the end of the project or after we've got an approval for whatever phase we're doing.

### Raw Feedback (follow-up, invoice cascade and purchaser clarification)
When we select a bunch of items and invoice it, I want to be able to say like, yes, the client has paid and it automatically updates each of those items. I don't want to have to go in and physically change the item from invoice to paid because I can see that just not getting done. So I want to be able to select from the invoice like it has been paid and that updates it. [...] For the purchaser thing — if the business is eating it then we just won't log it in the project. There might be instances though where the client pays for something that we were going to actually pay for. It's rare, but has happened before. So I think that might be on a case by case basis, but most of the time it's just something the client owes the business.

### Raw Feedback (follow-up, invoicing and auto-payment detection)
I think [Ledger] can generate invoices actually, but it doesn't do like money collection. So I just take that invoice and can download it and attach it to our payment software [...] I was thinking there would need to be a manual step where we confirm that got paid. But I wonder if that can just connect to our email and when we get an email stating that an invoice has been paid it can update it — that would actually be really incredible if the MCP can like update those. Yeah, let's make sure we capture that idea.

### Screenshots
None provided.

### What I Did With It
- Created `item-entry-flow.md` spec covering category-based routing for transaction creation (itemized categories go through inventory, non-itemized expenses go directly to projects)
- Created `billing-invoicing.md` spec covering item-level billing status (unbilled → invoiced → paid), invoice generation from selected items, invoice-level payment marking with cascade to items, and stretch goal of auto-payment detection via email/MCP integration
- Updated `_app-map.md` with transaction/billing model notes
- Updated `_index.md` and `_changelog.md`

---

### Raw Feedback (typography / fonts)
I think we should do better fonts, make it feel more fancy. So I think we should follow the same brand guide in regards to fonts that we have for 1584 design. I think it's Playfair something and then Avineer, but we'll have to double check that. I think we should have the pretty Sarah font for our headers.

[Clarification after discussion: The "Sarah font" was a misunderstanding — not a separate font. The two fonts are Playfair Display and Avenir, matching the 1584 Design brand guide. User confirmed Playfair Display for headers and Avenir for body/UI text. After discussing the typography hierarchy, agreed on: Playfair Display for main screen titles only (the big text at the top of each screen), Avenir in various weights for everything else — section headers, body text, labels, captions, buttons, navigation, and dollar amounts. Restraint with Playfair keeps it feeling special and luxurious rather than overused.]

### Screenshots
None provided.

### What I Did With It
- Updated `visual-style.md` with a new Typography section specifying the two-font system: Playfair Display (screen titles) and Avenir (all other text)

---

### Raw Feedback (project charges and reporting)
Okay, so one thing I don't again have it all fleshed out, but I would like to talk through some of the reporting details. Um, so we already talked about making it to where we have stuff that we are planning on selling to them and getting it. Getting it reimbursed Let me see I'm a little all over the place so bear with me here But on top of that something I would like to have are these like I Think when I'm setting up a project I want to have set Amounts and transactions that I put in like for a design fee how much we're charging for? Like the install services and like certain things that I'm like oh, I know we need to set a side 5k for this and I know we need to set aside You know like the for the three different design fee In voices like I want to essentially create those but then be able to say like yes it's been paid for and no it hasn't so we already kind of started talking about that in the other one but then I want to be able to create a report at the end and have it say okay this is the whole project data not just furnishings but everything so I want it to be old categories and say okay in furnishings you spent this much you know you have your Project price was X, but market value was Y. You show how much you've saved and then I want it to be able to say in Like that's in the furnishings and in total on the full project it came in to X amount with everything that's including the design fees that install the furnishings all of that and then a section that says like here are the outstanding payments, but those outstanding payments have already been included in this overall amount. So then when our client gets the report, it knows that or they know that we stayed within the total budget. We just have a couple things that they need to pay us back for or we need to collect. And then that closes out the whole project. So I want your help kind of mapping what this looks like, but I essentially want to be able to put in probably at the beginning, like, hey, this is what we have set aside for X. And then once it's been collected, like we update that and that's good to go and anything that isn't collected by the end, it shows that nicely in the reports.

[Clarification after discussion: User confirmed the three-bucket model — inventory items, pass-through expenses, and service charges are distinct concepts. Service charges (design fees, bundled service costs like "5K for storage/install/delivery") are the business's own fees, not reimbursable expenses. They can be created at project start or anytime during the project. Sometimes multiple charges are lumped into one (e.g., "$5K to cover install, delivery, and storage combined"). The user also noted that some things might not be set at the very beginning — they might add charges mid-project as needs arise.]

[Clarification on report: Client-facing, polished. Should NOT break down non-itemized categories individually — just show a total for everything that isn't itemized. The hero metric is the savings (project cost vs. market value), with the narrative that the savings essentially covers the design fees. Outstanding amounts are shown but already included in the overall total. Goal: client sees it and thinks "wow, I got incredible value, stayed in budget, and they went above and beyond."]

### Screenshots
None provided.

### What I Did With It
- Created `project-charges.md` spec for service charges / planned costs (design fees, bundled service fees) — a third type of project cost distinct from inventory items and pass-through expenses
- Created `project-closeout-report.md` spec for the client-facing end-of-project report showing furnishings breakdown with savings, overall project total, and outstanding payments
- Updated `_index.md` and `_changelog.md`

---

### Raw Feedback (item detail view editing UX + status definitions)
Okay, so two things real quick when it comes to editing. This is in an item view when I'm looking at all the details. It feels annoying and frustrating that some of the little pen marks, oh and I'm in the web app right now. Some of the little pen marks are to the right, which I love because I can just edit it from there. but then others I have to go into the three dots up in the right corner and then there's like edit details, there's status. It feels like, I don't know, like I want a little more consistency with how we edit things and I think I don't love that. It's up in the top right corner in the header. I'd rather it be. somewhere else. Like maybe next to details there's like a spot where I can press the little pen button and then can adjust any of the things below. And if we want to be able to adjust the status more easily, maybe that's like in a separate place. I'm not entirely sure but I just don't love the way that feels. And then the other thing. Oh yeah, was when it comes to status. So my understanding is to purchase is for something that's like we're if a designer is putting stuff together and they're like okay I need to make sure I purchase all of these upcoming items it's like a way for them to let's check it off but when we move things over from inventory and they haven't actually paid us for them yet but they are like in the project and yeah I don't know if that should be marked as purchased or to purchase I don't really know and maybe with the other design that we're talking through that would make this but we probably need to get more clarity around what the statuses mean, especially because that could affect some reporting stuff. Maybe, I actually dont know for sure.

### Screenshots
None provided.

### Raw Feedback (follow-up, status clarification and editing scope)
Okay, real quick, and number two, I just wanna clarify after rereading that, I think a solution, or maybe not clarify, I thought of a solution after rereading your summary, and I think it makes sense to have stuff that's for the designer, which is, you know, okay, I did purchase this for the project, it gets physically here versus, you know, still need to place an order for that and then have a separate thing that's for like the reporting and billing and whoever is handling the invoicing stuff. Maybe that'll get confusing. I honestly don't know but that was just my thought. I was as I was reading this. And then for your questions, Let's see, I think the current statuses are, well, I'm pretty sure you can look at that, but I think it's to purchase, purchased and to return and returned. So it all kind of aligns with like, okay, what the designer needs to do or has done, which I like that. I think we just need to. have some maybe auto things set when something goes from inventory into a project like it automatically gets set as purchased because we just barely did some cleanup where some things that we moved over didn't get set to that. But yeah, definitely still need clarity around the distinction.

[Confirmed via Ledger API: item statuses are "to purchase", "purchased", "to return", "returned".]

[User did not directly answer web-only vs. cross-platform for the editing UX — will assume web app for now since that's where they were looking, and note cross-platform as an open question.]

### What I Did With It
- Created `item-detail-view.md` spec covering: (1) editing UX consolidation — pull edit and status actions out of the three-dot header menu, provide inline/section-level edit entry points near the content; (2) item status definitions — confirmed four statuses (to purchase, purchased, to return, returned) as designer workflow statuses, introduced two-track status model separating designer workflow from billing status; (3) auto-status on inventory-to-project move
- Updated `_app-map.md` with item detail view screen and item status model
- Updated `_index.md` and `_changelog.md`

---

### Raw Feedback (follow-up, two-track naming concern)
I guess part of me wonders if that's too much or if we have those two kind of workflows that you mentioned. Like are we over-complicating this? That's what I want to know. But if we have those two workflows, they probably would need to be titled something else rather than status on both of them. I'm just kind of unsure. These are just some thoughts for it that I could maybe use your feedback on.

[After discussion: User agreed the two tracks make sense conceptually (they map to real, separate questions the team already asks). Main concern is naming — both can't be "Status." Working direction is "Status" for designer workflow, "Billing" or "Payment" for financial track, but names are explicitly NOT finalized. User wants to workshop the naming further.]

### What I Did With It
- Updated `item-detail-view.md` with naming direction and open question — captured that names are a working idea, not a decision

---

### Raw Feedback (inventory transaction naming + source privacy)
Another thing we need to nail down is the naming convention for the transactions from Inventory. They are currently something weird, and the source is unmarked. I think the source should be "Business_Name Inventory" and that way we can filter for it in the transactions filters. Also, when an item is in inventory and we say the source is from somewhere (like Homegoods, ross, etc) I think it's nice to have that tracked in the inventory section, but once it's moved to the project it should probably be changed to source being from Business Inventory. Or maybe just a tag that let's us know that item came from our inventory, I'm unsure. But at least for anything that's customer facing, we don't want them to know where it came from before our inventory, especially if it's like from wayfair or any online source, we dont want them price checking the original source in case we did a mark up on it to cover our cost in accuiring/storing it.

[Clarification: User leans toward the source being dynamic — "[Business Name] Inventory" pulled from the account's business name setting — but is fine with a simpler "Business Inventory" if the dev team thinks that's cleaner/less breakable. Leaving this as a dev team call.

For original source tracking: the original vendor (Homegoods, Ross, etc.) must be preserved in the data — never destroyed — because items might need to be returned to the original store. User is open to keeping the original source visible internally for the designer, since they might need it. The hard requirement is that anything client-facing (reports, invoices, closeout reports) must NOT show the original acquisition source. The main thing the user wants is to be able to look at an item in a project and immediately know it came from inventory rather than thinking it was purchased directly from a store by the client.]

### Screenshots
None provided.

### What I Did With It
- Created `inventory-source-naming.md` spec covering transaction source labeling for inventory sales, original source preservation, and client-facing source masking
- Updated `item-entry-flow.md` to cross-reference the new naming spec
- Updated `_index.md`, `_changelog.md`, and `_app-map.md`

## 2026-04-05

### Raw Feedback
Issue with Google sign on - when someone does that they don't get a password, and when they need to use the app but google wont open (cause I thought it worked without internet) then someone can't sign in. we might wanna have a work around for that.

[Clarification: Ledger does have an email/password sign-in option alongside Google. User is unsure whether the app currently works offline — needs to check with the dev team.]

### Screenshots
None provided.

### What I Did With It
- Created `authentication-offline-access.md` spec covering the Google Sign-In lockout issue and fallback authentication for offline/degraded scenarios
- Updated `_index.md` and `_changelog.md`
