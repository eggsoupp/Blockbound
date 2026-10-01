--[[ This Script Handles Admin Commands

Current Commands:
/givestats Player Stat Amount

]]

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

function RandomID(Folder)
	local Chance = math.random(1,10000)
	if Folder:FindFirstChild(Chance) then
		return RandomID(Folder) -- reroll if exists
	end
	return Chance
end

function IsPlayerAdmin(Player) -- checks if user is allowed to use commands
	local IsGroupGame = game.CreatorType == Enum.CreatorType.Group
	local CreatorId = game.CreatorId

	if IsGroupGame then
		return Player:GetRankInGroup(CreatorId) >= 254 -- this is the rank you have to be in a group
	else
		return CreatorId == Player.UserId
	end
end

function FindPlayerFromName(PlayerName)
	for _, Player in Players:GetPlayers() do
		if string.lower(Player.Name) == PlayerName then
			return Player
		end
	end
end

--[[
	These two reach for a stats folder and a pet folder that this game does not
	have - Player.Data and ReplicatedStorage.Pets exist in neither the place nor
	the source. Indexing them directly threw, so an admin typing /givestats got
	a stack trace rather than a refusal.

	Looked up rather than indexed, so the commands simply do nothing until the
	systems they are written against exist.
]]
function FindStatFromStatName(Player, StatName)
	local data = Player:FindFirstChild("Data")
	if not data then
		return nil
	end

	for _, Stat in data:GetDescendants() do
		if string.lower(Stat.Name) == StatName then
			return Stat
		end
	end

	return nil
end

function FindPetFromPetName(_Player, PetName)
	local pets = ReplicatedStorage:FindFirstChild("Pets")
	if not pets then
		return nil
	end

	for _, Pet in pets:GetChildren() do
		if string.lower(Pet.Name) == PetName then
			return Pet
		end
	end

	return nil
end

function Main(Player) -- this code is called for each player joining
	if not IsPlayerAdmin(Player) then return end -- player is not an admin if this returns false
	Player.Chatted:Connect(function(Message)
		local SplittedMessage = string.split(Message, " ")
		local Command = string.lower(SplittedMessage[1])
		local PlayerName = string.lower(SplittedMessage[2])
		local Arg1 = string.lower(SplittedMessage[3]) or ""
		local Arg2 = SplittedMessage[4] and string.lower(SplittedMessage[4]) or ""
		
		if Command == "/givestats" then -- /givestats PlayerName StatName Amount
			local TargetPlayer = FindPlayerFromName(PlayerName)
			if TargetPlayer == nil then return end -- no player exists
			
			-- Also absent from this game. Indexed directly, this threw before
			-- the stat lookup below ever got a chance to refuse politely.
			local settings = ReplicatedStorage:FindFirstChild("Game Settings")
			local currencyName = settings and settings:FindFirstChild("CurrencyName")
			if currencyName and Arg1 == string.lower(currencyName.Value) then
				Arg1 = "currency"
			end
			
			local Stat = FindStatFromStatName(TargetPlayer, Arg1)
			if Stat == nil then return end -- stat does not exist
			
			if Stat:IsA("IntValue") or Stat:IsA("NumberValue") then
				Arg2 = tonumber(Arg2)
				if Arg2 == nil then return end
				
				Stat.Value = Arg2 -- set the stat to Arg2 if it's a number
			elseif Stat:IsA("BoolValue") then
				Stat.Value = Arg1 == "true" and true or false -- make it true if you put in True or true and the rest if false	
			elseif Stat:IsA("StringValue") then
				Stat.Value = Arg1
			end
		elseif Command == "/givepet" then -- /givepet PlayerName PetName
			local TargetPlayer = FindPlayerFromName(PlayerName)
			if TargetPlayer == nil then return end -- no player exists

			local Pet = FindPetFromPetName(TargetPlayer, Arg1)
			if Pet == nil then return end -- pet does not exist

			local NewPet = game.ReplicatedStorage.Assets.PetTemplate:Clone()
			NewPet.Name = RandomID(Player.Data.Pets)
			NewPet.PetName.Value = Pet.Name
			NewPet.Parent = TargetPlayer.Data.Pets
		end
	end)
end

Players.PlayerAdded:Connect(Main)