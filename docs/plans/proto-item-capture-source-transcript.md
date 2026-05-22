# Proto Item Capture Source Transcript

Date saved: 2026-05-21

This transcript records the original conversation that drove the proto item / item quick draft design direction. It should be treated as source context for future spec updates, especially around transaction-linked captures, inventory-origin hints, photo grouping, review workflows, and low-friction designer capture.

## Transcript

OK, so we're gonna record the idea, just make sure microphone is off. Um, so my thought is that so far, a big pain point for my mom has been logging items tied to transactions. She's really good at logging the transactions that, like, it might take her a minute to get to it, but she's not bad at that. But she gets so frustrated with the items. So what I'm thinking is designing a way to make it easier for her. And I don't know if this is the right route, but my thought is what if when someone goes through and creates a transaction? Um, maybe we'll go to a transaction page, but my thought is instead of having other images, what if we had, like, sections where maybe we have a section that's like cart images, so you could just take a picture of like a bunch of things together, or like a pile of everything, just remember what's in the transaction? If we need, or we just bypass that completely, because so far I haven't seen my mom do that once. But then, I think, what if we had a little section where it's like, you can add a plus thing? And you take multiple images of the same item, because where, in the past, I've talked about maybe giving the pictures to AI to create, but then, when we take two pictures, one of the, um, tag and one of the image, or of the item, it doesn't know how to pair them. So, what if we created, like, a line item here to where we, like, can press, essentially, like, add an item, and she just takes the 2 pictures, and then she can go and add another item, take the 2 pictures, like, the item and the tag, another item, take the item and tag, and then, we were able to set it up to where either, like, a person, like, a VA could go in, and see the items, and add the details of, like, okay, it was purchased for this much. It corresponds with this line item in the receipt or maybe AI could do that if we pulled the data from the email. That matches the transaction, like date and amount. And source, and then it created all the items, and then it was able to say, okay, these are the pictures like in this picture. I see the same SKU matches, this item in the receipt.

Can you rewind a little bit?

To where?

I don't know. I got lost. Where I followed you up until you were like, hey, in images, we somehow treat, we have a section for images that actually means items, and we add items, but it's just images. And then a VA creates items.

Yeah, so, I feel like if we can have sessions to be like, okay, for this one item, here's all the pictures for it. Then, it would be easier to potentially hand that to AI and say, hey, create an item with this information, and, like, look at the picture, and see that the SKU is this, so then extract the, um, the, price, and, like, pair it to that. Yeah, because if we already pregroup them, that just might take the headache out from my mom. And then maybe for the, like the lines of the pictures, let's say, If we're in a transaction inside of inventory, maybe next to it. Um, there's like a little button over here where she can just press like sell and she doesn't have to put in any of the information yet for it.

rewind a little bit?

Yeah.

To where? So after we just finished talking about kind of grouping item images together, we'll just finish that. You're moving on to a new thing. Can you start that new thing over?

Yeah, so it was thinking if our process within a transaction is, like, you put in an item, you put all the pictures for that one thing. Then, like, if it's a transaction that a client paid for, that's super cut and dry. Right? Now, let's say we have that process in inventory. It'd be cool if, in inventory, she was able to go through, take the pictures, and then within that line that, like, you see the multiple pictures, maybe at the little edge, it had a button that was, like, sell this to a project, so she could just tap. Or, you know, select multiple and then sell them, and they don't have to be fully created where she goes in and puts all of the information of, like, how much it was purchased for, but it could go and be sold to the project.

Well, we need that information if we're gonna do a sale.

So, my thought was, what if we could sell it to the project, and that would be, like, what if... Stick with me here. It could go to a project, and then could be filled out in the project later. To say, okay, it was purchased for this. We want to make the project price this amount. And then it just updates numbers of like, All right, this sale ended up being $24.99. Yeah? So, and this is all just me brainstorming of how to make it easier on designers like my mom, because so far, the most headache she's had with the items, yeah.

That seems like a good design.

so much work.

Yeah. It seems like a good design. We'd have to change a bunch of stuff, but I think it'd probably be worth it, 'cause that's such a big point of friction. Yeah? Okay. Um... Okay, yeah, I think, so far, the things that are working really well are adding transactions seems to be going smoothly. Yeah. Um, adding items to spaces went really smoothly. Like, that was fucking awesome. Good Adding items to transactions. And then moving, like the, yeah, from inventory versus in the transaction, those have been rough. Yeah. I was, um, let me ask you this, and I don't know if this is something we should keep in the recording or not. I'll stop this thing. But I'll keep this. How is, um... So, uh... The flow you're talking about that, that really involves adding items in the context of transactions. you're in a transaction, and that's where you add items, as opposed to adding items a different way. Like just adding standalone items. Do you feel like, do you feel like? That's adding transactions is smooth enough that it's having that extra piece of friction where before you can add items, you gotta add transactions, add a transaction. Do you feel like that's fine?

I could see there being potential issues. Um, Yeah, I could see there being potential issues there, because I know sometimes my mom's, like, she'll do a bunch of shopping and get her in her car, and when she comes out, she might not know which transaction. It came from.

Okay, let me think about that. Doesn't know which transaction it came from. But she just had the transaction.

Yeah, because I could see her, like, let's say she goes to 3 different stores and gets 10 items at each store, puts it in her car. She comes home. She takes those transactions. She has the receipts and she can upload those. And she's like, okay, this is good. But then when she goes to unload the items from her car, she doesn't necessarily remember which store she bought them from. And that's when she wants to create the items. It sounds like that's when she's been creating the items, is when she unloads it from her car, because she doesn't, okay. She told me multiple times, it's just so hard for her to, like, get pictures of all the items when she's in checkout.

Well, let's think this through then. If there, let's imagine she's, she doesn't know which transaction a bunch of items came from. She's unloading her car. And she wants to use this simple flow. How does that work?

Yeah, so, another thing, honestly, if it was, like, the most ideal, what would happen is she could just, take a picture of an item, and its tag, and have that created, and then, if AI could look at the tag and be like, okay, this is the Skew, it matches the Skew in this receipt. That would be the best. That would make it the most easy for her. That would just get really expensive.

Okay. Like, I get that it's easy. It's just really expensive.

Yeah. I don't think it makes sense. But that's where I think a VA might be able to go in and...

Well, Claude can do it. Through our subscription, probably.

You just said it gets really expensive.

There are different ways that you get billed. So like, let's say that we build AI into the app. That means that, that all the AI shit that's built into the app, it runs an API cost. But when we use a subscription, it's a fraction of that.

Okay, so what if the app part, because I like how you were like, let's differentiate app versus AI. If the app design allows you to have a space to easily, like take 2 pictures and be like, okay, add, like that's an item next, take 2 pictures, add, that's another item next. Take 2 pictures. Then, If Claude could go in and say, okay, in this picture, Here's the SKU. We also pulled the receipt data from our email and got all of the line items of like, here's all the skews in this receipt and could match those. If that part was AI, I think that could be really smooth.

Yeah, maybe. So, I mean, what we what we basically need is we need a junk drawer for items in a junk drawer for transactions. We currently have a junk drawer for transactions. It's the review tab. So we need one for items then. And then we need to do a bunch of stuff to tell so that we can, so that AI through the MCP or whatever, it can be like, It can... Yeah. Look. Look in the junk drawer for items that are potential candidates. That'd be really cool. I wonder if we can do some of this on device. But on device, I mean, you know how when you have an image on your phone, how you can select text. Mhm. Well, we can make the app use the same hardware and AI that lets you do that. Like, so that might be the way to do this. Is it maybe there's some way for us to use on-device AI to do this extraction so that When we make an item, it extracts shit. I just don't know how smart it is. Like, if it can just extract all the raw text, then it becomes a lot easier for clawed through the subscription to be like, Here's the parsed text from the images. for items and for receipts and it can do matchmaking a little bit more easily.

But honestly, when I had all of the, Um, you know how you took the receipt from the email and created all the items just based off the SQ number? When I had the image and of the item and the picture of the little tag, I was able to pretty easily go in and be like, okay, let me just like, add these pictures to this item.

I don't what that means. Um, do you remember how you had the?

Are you taking the pictures in this scenario? Um... Are you, like, being like, oh, here's this, here's the item that matches the skew in their seat and you take pictures? That was really easy. Because that's...

But my mom, but when I'm not around, like, it takes a very, it's a very slow process for my mom. And then if she's in trying to get designing and she's doing that and she's getting frustrated because something's wrong, like it just slows everything down. But if she was able to just take 2 pictures and have that be like, hey, this is going to be an item at some point, here's the pictures for it. Then if I was able to hop on remotely and be like, okay, here's the skew for that. Let me attach it to the item that was...

What do you mean by hop on remotely and say?

Uh, like from my computer, not in person.

Using clawed or visually in the app?

Visually in the app.

Can you walk me through it in detail? You mean like you have you have the junk drawer of items open, you have a transaction open and you're scrolling through the items and you're saying this one matches.

Um, not exactly. So what I'm thinking is, Um, I've got... the junk drawer of items which aren't actually items that are created. It's just saying here's 2 pictures that is going to be an item.

proto item.

Yeah, that. And then I've got a bunch of items over here that are already tied to transactions, but all we know about it is askew and a price because we extracted that from the email.

Oh, it's almost like merging. It's like, hey, these images go with this.

Yes. Like, turn, okay. That would be fucking awesome to be able to just search, like, I can look at the item and be like, oh, yeah, let me search this cue. Okay, here's the item. I can merge the pictures with this and I can say the name real quick.

Oh, that last part confused me.

Say the name real. Um, I can change the title, 'cause right now the title is like, it's like this funky 33 dash decorative accessory. I could be like, hey, this is a bluefish.

Uh, okay. I think I'm confusing myself by trying to imagine how to implement that. I'm like, oh, that just adds a whole other layer. that I haven't, I don't. I haven't clearly envisioned yet. So that's a little confusing. Adding the pictures, okay. Like, I get the main idea, I think, you've got a junk drawer of proto items that are just images. Maybe there's some metadata is what you call it pulled out, like skew and shit.

Well, I don't even, I think we don't, we don't need to pull out the metadata yet from that. Maybe as AI gets better, we can, but if we just have the proto... Yeah. The images, then, do you remember how you took an email for a receipt and you parsed out all of the items? And it looked like...

I think I get what you're describing. I'm not confused about that.

Okay, cool. Because the items would literally look exactly like this. Like, I have no clue what this is.

I understand. But I could look at the picture and be like, oh, let me search this skew and then just be like, these pictures go into here. And then I could...

Sure, sure. No, I get it. I'm trying to pair this with... I understand the process you did before. What I'm trying to envision is the new process. That's where I'm getting confused. I understand what you did before. So you don't need to re explain it.

Okay. So I think the new process would literally just be, have a place where all of the pictures could go together.

Uh huh.

And then everything else initially could be manual.

And your mom's job is just take the pictures.

Yeah. Just capture them.

Yeah. That sounds like a good process. But capture them per project. So she's taking pictures in Sandra's, but then if she knows, like, okay, I know, because normally if she's bought something, she usually knows, like, oh, I got this.

Oh, it's per project. Oh.

Yeah. Would it ever not be per project?

Would she ever want to capture items and not know where it goes? Like, I don't know if this goes in inventory. I dont know if this goes on a project.

She never has an item where she's like, I'm not sure if it's gonna go to inventory or a project. Because if that's the case, it was, that means it's probably been bought by us. So then she could do that in inventory. And again have a little...

Sorry, I don't follow the last thing you said, when you as soon you start saying, because it's probably been bought by us, I think that's that confused me.

Yeah, so she knows who bought items typically. Okay. And if we bought something, that's the only time she's not gonna be sure which project it's gonna go into. So she can create it in inventory. But in this instance, like the bluefish, if she bought it for Sandra's, but she knows we bought it, she could go into inventory. Take the pictures. Yeah. And then have a little button that says, this, like, proto thing is going to be assigned to Sandra's project.

Okay. Because one thing she's told me multiple times is she's like, I don't like adding things to inventory. And then forgetting, like, she's like, I don't want to forget that it needs to be moved into this project.

Yeah, yeah, there are a few ways to make it work, right? She either, like, either she picks... It's for this project, or this project, or inventory, and then she takes the pictures. Um, And then if inventory, she picks like, where should it go? The, the, The other way would be, hey, where is it eventually gonna go and who bought it? Hmm.

Because what I want to avoid is for every single one, her hacking to make select, like, select things. That's why I want her to be able to go into Sandra's project. and be like, okay.

Well, are we not gonna use the universal ad button then for this? Here's what's getting here's what's getting confusing. Now we've added all these conveniences that make it complicated, the app. Like, we have this universal ad button, and now that we have that, we have to think about that. We have to be like, well, if we want someone to be able to use that, now we have to make sure that they enter all the information required in order for us not to lose this thing. Because if that's why I asked about the junk drawer, like, is there one where it's not scoped to a project or an inventory? Because if so, that means that when we use the universal add button, like she has to provide the information around where it goes. And if it's like, well, it goes to inventory, but then it's later going to go to Sandra's, that gets confusing.

Yeah. So... You're right. Maybe, and I'm sorry about this.

Okay, we can remove it.

Maybe the universal add is making it more complicated. Because I've just, I've realized, and I only learn this when I'm with her, that if she has to do too much when she's adding the items, it slows her down so much and she dreads it. She's like, that's the part that holds her back and she gets frustrated. But she it's not hard for her to be like, I just shopped for this project. I'll go into the project and I'll add the items.

Yeah, I don't think that's hard. Okay. And if we If, if we, if we're already in the project where the item's gonna get used, And we have this little cell button or whatever. Like, we can make it so that she just has to take the pictures, I think. And then figure everything else out later. I think, right?

Yeah, the only thing that might be good is if she was in a project. Let's say she's unloading stuff at a project and she's like, this is everything going in here. It would be cool if there was a way for her to just take pictures and be like, Oh, this came from our inventory. And she just tapped a little button that's, like, make sure this is sold from inventory.

You say that again.

Yes. So if she is in Sandra's house, she's unloaded everything she knows she wants in there. She's taking the pictures. If there's an item that she knows she bought, it would be cool if there was a little button that she could just tap and be like, Hey, this needs to be sold from art inventory. Because then we know, okay, we have to make sure it's tied to Like, it shows that it's coming from inventory and being sold over. Which means it might get tied to a receipt in inventory, and then it creates an inventory transaction.

Sorry, sorry, I was thinking, I was thinking about what you said earlier. My bad. didn't keep up with what you were saying. And I understand why that's useful. I'm just trying to think through like, It's not a source thing. It's like a way to say this, it comes from this specific source. It's like an inventory specific source quick button. is basically what it is.

Yes.

I could see that being very useful. Okay. Yeah, I like all that's buildable.

Oh, that's horrible. Cool. I know we'll probably take a little more thought on the design, but I think if we can make it more simple to add items, it's gonna be a huge relief using the app.

Yeah, yeah, yeah. I agree. I agree. All right, cool. I think we're good. Okay. That's a good idea. Good design. Did you say that? I'm trying to.
