-- Starts the Starfall banner. Everything is in the WishService module, which
-- QuestService and Bestiary also require to award Wish Stars.
require(game:GetService("ServerScriptService"):WaitForChild("WishService"))
