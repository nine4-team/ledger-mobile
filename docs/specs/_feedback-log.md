# Ledger Specs — Feedback Log

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
