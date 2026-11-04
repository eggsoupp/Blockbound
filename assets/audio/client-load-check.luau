local SoundService = game:GetService("SoundService")
local Content = game:GetService("ContentProvider")
local Http = game:GetService("HttpService")
local bank = require(game.ReplicatedStorage.Shared.Audio.DownloadedSounds)
local folder = Instance.new("Folder")
folder.Name, folder.Parent = "AudioImportReview", SoundService
local results, pending = {}, 0
for key, id in pairs(bank) do
    pending += 1
    task.spawn(function()
        local sound = Instance.new("Sound")
        sound.Name, sound.SoundId, sound.Volume, sound.Parent = key, id, 0, folder
        local status
        local ok, err = pcall(function()
            Content:PreloadAsync({sound}, function(_, value) status=value.Name end)
        end)
        local deadline = os.clock() + 10
        while not sound.IsLoaded and os.clock() < deadline do task.wait(.1) end
        results[key] = {id=id, ok=ok, status=status, loaded=sound.IsLoaded,
            duration=sound.TimeLength, error=if not ok then tostring(err) else nil}
        pending -= 1
        SoundService:SetAttribute("AudioReviewResults", Http:JSONEncode(results))
        if pending == 0 then SoundService:SetAttribute("AudioReviewComplete", true) end
    end)
end
