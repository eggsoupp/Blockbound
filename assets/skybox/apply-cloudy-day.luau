-- Apply after granting BlockBound access to these uploaded image assets.
-- Run in Studio edit mode. Abort without replacing the old sky if loading fails.
local Lighting = game:GetService('Lighting')
local candidate = Instance.new('Sky')
candidate.Name = 'Sky'
candidate.CelestialBodiesShown = false
-- Group-owned uploads. Roblox places Rt at -Z, Ft at +X, Bk at -X and Lf at +Z,
-- so the source faces are assigned to these properties to line up with Up.
local ids = {
    Rt = '94929358874497', -- Bk.png
    Ft = '78440684220539', -- Rt.png
    Bk = '73239727016074', -- Lf.png
    Lf = '107633688790514', -- Ft.png
    Up = '90682792022425',
}
candidate.SkyboxDn = game.Lighting:FindFirstChildOfClass('Sky').SkyboxDn
for face, id in ids do candidate['Skybox' .. face] = 'rbxassetid://' .. id end
candidate:SetAttribute('Preset', 'VoxelNest - Cloudy Bright Day')
local failed = {}
game:GetService('ContentProvider'):PreloadAsync({candidate}, function(id, status)
    if status ~= Enum.AssetFetchStatus.Success then table.insert(failed, id) end
end)
if #failed > 0 then
    candidate:Destroy()
    error('Skybox image access/loading failed: ' .. table.concat(failed, ', '))
end
local backup = game.ServerStorage:FindFirstChild('SkyboxBackup') or Instance.new('Folder')
backup.Name = 'SkyboxBackup'
backup.Parent = game.ServerStorage
for _, sky in Lighting:GetChildren() do
    if sky:IsA('Sky') then sky.Parent = backup end
end
candidate.Parent = Lighting
