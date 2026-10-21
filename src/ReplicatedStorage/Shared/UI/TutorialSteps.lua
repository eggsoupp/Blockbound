--[[
	TutorialSteps

	What the tutorial guide says, in order. The WORDS live here and nowhere
	else: Shared.UI.TutorialPanel draws whatever step it is handed, and
	StarterPlayerScripts.TutorialClient decides which one that is.

		TutorialSteps.Steps          the list, in the order they are meant to run
		TutorialSteps.byId("welcome") one step, or nil

	A step is

		{
			id    = "welcome",            -- stable; what progress will be saved under
			title = "WELCOME TO BLOCKBOUND",
			body  = "Your world is yours to shape.\n\nStart by finding a tree ...",
		}

	ADDING A STEP

	Add an entry to Steps. Give it an id that will never change - once progress
	is persisted, the id is the key it is saved under, so renaming one later
	means every returning player sees that step again. Titles are upper case by
	convention, because the panel draws them in the heading font the pixel
	windows use for their banners. Bodies may hold blank lines; the panel wraps
	and types them on as written.

	Nothing here decides WHEN a step shows. That is the controller's job, and
	is the part that will grow as the tutorial does: a step about gathering
	wood is finished by the inventory gaining wood, not by a timer in this file.
]]

local TutorialSteps = {}

TutorialSteps.Steps = {
	{
		id = "welcome",
		title = "WELCOME TO BLOCKBOUND",
		body = "Your world is yours to shape.\n\nStart by finding a tree and gathering wood.",
	},
}

local byId = {}
for index, step in ipairs(TutorialSteps.Steps) do
	assert(type(step.id) == "string" and step.id ~= "", "[TutorialSteps] step " .. index .. " has no id")
	assert(byId[step.id] == nil, "[TutorialSteps] two steps share the id " .. step.id)
	byId[step.id] = step
end

function TutorialSteps.byId(id: string)
	return byId[id]
end

return TutorialSteps
