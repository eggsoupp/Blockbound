--[[
	FontController

	Puts Shared.UI.Theme.FontFamily on every piece of text in the game.

	WHY THIS EXISTS AT ALL

	Everything the game draws in code already asks Theme for its font, so that
	half changes on its own. What it cannot reach is the UI authored in Studio -
	the inventory grid, the volume slider, anything added to the place file
	later - because those labels carry whatever font was picked in the
	properties panel and no code ever touches them.

	So this walks the PlayerGui once and rewrites the FAMILY on everything it
	finds, then keeps watching for whatever appears afterwards.

	IT CHANGES THE FAMILY AND NOTHING ELSE

	Each label keeps its own weight and style. That matters: stamping one Font
	over everything would flatten the bold stack counts and headings the
	interface uses to separate one kind of text from another, and the point of a
	custom font is to change what the game looks like, not to throw away its
	typography.

	Inert while Theme.FontFamily is empty. It costs one connection and no work
	at all until there is an id to apply.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Theme")
)

local family = Theme.FontFamily
if type(family) ~= "string" or family == "" then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--[[
	One Font per weight/style pair, built once.

	A Font is a value type, so every label could have its own - but there are
	only a handful of combinations in any interface and this is applied to every
	label in the game, twice over on a respawn.
]]
local cache = {}

local function fontFor(weight: Enum.FontWeight, style: Enum.FontStyle): Font
	local key = weight.Value * 4 + style.Value

	local font = cache[key]
	if not font then
		font = Font.new(family, weight, style)
		cache[key] = font
	end

	return font
end

local function apply(instance: Instance)
	if
		not instance:IsA("TextLabel")
		and not instance:IsA("TextButton")
		and not instance:IsA("TextBox")
	then
		return
	end

	local current = instance.FontFace
	if current.Family == family then
		return
	end

	instance.FontFace = fontFor(current.Weight, current.Style)
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
	apply(descendant)
end

--[[
	Anything created later, which is most of this game's interface: the
	crafting window, the health bar, the ability panel and the mining bar are
	all built at run time, and a respawn rebuilds several of them.
]]
playerGui.DescendantAdded:Connect(apply)
