--[[
	Notices

	What the notice board in the spawn village shows (NoticeBoardClient):
	three tabs, each a list of entries, newest first. Edit this file to post
	news; nothing else needs to change.

	  Updates     the big things that arrived
	  PatchNotes  smaller changes and fixes
	  Upcoming    what is being worked on

	An entry: { title = "...", date = "YYYY-MM-DD" (optional), lines = { "...", ... } }.
]]

return {
	Updates = {
		{
			title = "The Spawn Village",
			date = "2026-11-12",
			lines = {
				"Spawn is now a small village: start every journey here.",
				"Starfall Shrine: make a wish for aspects with your Wish Stars.",
				"Starfall Merchant: browse the Aspect Shop of permanent aspects.",
				"Trading Post: sit at a booth with a friend to trade.",
				"Training yard: test your weapons and abilities on the dummies.",
			},
		},
		{
			title = "Trading",
			date = "2026-11-12",
			lines = {
				"Trade stored aspects and unredeemed passes with other players.",
				"Both sides confirm, and the trade either completes in full or not at all.",
			},
		},
		{
			title = "A Living World",
			date = "2026-11-12",
			lines = {
				"Abandoned builds and mines in the open world slowly return to nature.",
				"The area around spawn is protected.",
				"Ore you mine does not grow back.",
			},
		},
		{
			title = "Aspects",
			date = "2026-11-11",
			lines = {
				"Abilities now come in 10 aspects. One aspect is in use at a time.",
				"Spare aspects wait in storage until you swap.",
			},
		},
		{
			title = "Decor",
			date = "2026-11-10",
			lines = {
				"83 pieces of furniture and curios to craft and place on your island.",
			},
		},
		{
			title = "Wings",
			date = "2026-11-07",
			lines = {
				"Wear wings to fly for a short while.",
			},
		},
	},

	PatchNotes = {
		{
			title = "Village polish",
			date = "2026-11-12",
			lines = {
				"Chairs, benches and beds seat you when you walk into them.",
				"Training dummies take hits like enemies and reset on their own.",
				"The well is bigger: it now fills 2x2 blocks.",
				"Trading happens at the Trading Post only; the trade button is gone.",
				"The Aspect Shop is a scrolling list; tap an aspect to see its abilities.",
			},
		},
		{
			title = "Faster terrain",
			date = "2026-11-10",
			lines = {
				"The world streams in faster, with fewer hitches while exploring.",
			},
		},
		{
			title = "Loading",
			date = "2026-11-07",
			lines = {
				"The loading screen is gone within about six seconds.",
			},
		},
		{
			title = "Combat",
			date = "2026-11-06",
			lines = {
				"Legendary weapons fire a projectile with every swing.",
				"New, punchier combat sounds.",
			},
		},
	},

	Upcoming = {
		{
			title = "Permanent aspects on sale",
			lines = {
				"Aspects in the Aspect Shop marked SOON can soon be bought to keep for good.",
			},
		},
		{
			title = "More to come",
			lines = {
				"New regions, enemies and bosses to explore. Check back here for news.",
			},
		},
	},
}
