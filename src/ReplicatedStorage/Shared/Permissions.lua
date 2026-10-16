--[[
	Permissions

	Who is allowed to run the developer commands.

		Permissions.isAdmin(player)

	One definition, because there are now two command sets asking - the debug
	console and the ability commands - and a second copy of the rank number is a
	second thing to get wrong the day it changes.

	IT IS NOT A SECURITY BOUNDARY ON ITS OWN

	Every caller is a SERVER script, and that is what makes this mean anything:
	the client is never asked whether it is an admin. Shared rather than
	server-only so an interface could grey out a command it cannot run, which is
	a presentation question and safe to answer on either side.
]]

local Permissions = {}

-- Group rank at or above which a member counts as an admin, for a group-owned
-- place. 254 is the conventional "high staff, below owner" rank.
Permissions.GroupRank = 254

--[[
	Named admins, by UserId, whoever owns the game. Asked first, so the
	developer is never locked out by a change of owner or a group-rank lookup
	that fails. Add a line to make someone an admin.
]]
Permissions.AdminUserIds = {
	[11814518684] = "saile_stone",
	[1879510219] = "lil_elias056",
}

function Permissions.isAdmin(player: Player?): boolean
	if not player then
		return false
	end

	if Permissions.AdminUserIds[player.UserId] then
		return true
	end

	-- A Studio playtest is only ever the developer at their own desk.
	-- IsStudio is false on every live server.
	if game:GetService("RunService"):IsStudio() then
		return true
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank >= Permissions.GroupRank
	end

	return game.CreatorId == player.UserId
end

return Permissions
