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

function Permissions.isAdmin(player: Player?): boolean
	if not player then
		return false
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank >= Permissions.GroupRank
	end

	return game.CreatorId == player.UserId
end

return Permissions
