--[[
	Remotes

	One place that knows where the remotes live, and on the server makes sure
	the ones the code needs exist.

		local craft = Remotes.ensure("RequestCraft", "RemoteEvent")  -- server
		local craft = Remotes.wait("RequestCraft")                   -- client
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- The client must WaitForChild, not FindFirstChild: requiring this before
-- ReplicatedStorage has replicated would leave `folder` nil forever.
local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

-- Server-only: a remote created on the client is invisible to the server.
function Remotes.ensure(name, className)
	assert(RunService:IsServer(), "[Remotes] ensure is server-only; use Remotes.wait on the client")
	assert(type(name) == "string" and name ~= "", "[Remotes] ensure needs a name")

	className = className or "RemoteEvent"

	local existing = folder:FindFirstChild(name)
	if existing then
		assert(
			existing:IsA(className),
			string.format(
				"[Remotes] '%s' already exists as a %s, but %s was expected.",
				name, existing.ClassName, className
			)
		)
		return existing
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

function Remotes.wait(name, timeout)
	return folder:WaitForChild(name, timeout)
end

return Remotes
