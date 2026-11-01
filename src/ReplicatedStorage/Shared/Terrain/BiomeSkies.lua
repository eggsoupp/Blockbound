--[[
	BiomeSkies

	Which skybox each biome shows. Face keys name the purchased images (see
	assets/skybox); BiomeSky.client.lua puts them on the right Sky properties.

	A biome with no entry keeps the place's own sky (Cloudy Bright Day). All
	ids are group-owned uploads: a personal upload will not load in this game.
]]

local BiomeSkies = {}

BiomeSkies.Skies = {
	Swamp = {
		name = "Foggy day",
		Rt = "96484148741336", Lf = "137217956806996", Up = "74374414450867",
		Dn = "132337674229106", Bk = "83345835554846", Ft = "105831021623358",
	},
	Desert = {
		name = "Golden Hour",
		Rt = "77663101878302", Lf = "98537522136389", Up = "87060855624659",
		Dn = "86268627204269", Bk = "113397032198666", Ft = "76505161845482",
	},
	Snow = {
		name = "Northern lights",
		Rt = "137362410936968", Lf = "103493186183443", Up = "126645003654672",
		Dn = "93170134300668", Bk = "100362559867737", Ft = "139341886356292",
	},
	Hallow = {
		name = "Cotton Candy Morning",
		Rt = "102821321410799", Lf = "93751250836545", Up = "131706443890926",
		Dn = "110196442891363", Bk = "113830382374092", Ft = "112165174947824",
	},
	Crimson = {
		name = "Crimson Sunset",
		Rt = "111305514897055", Lf = "108929501303111", Up = "119281925253603",
		Dn = "81411302887947", Bk = "73171095040434", Ft = "129265222274246",
	},
	Corruption = {
		name = "Dark sunset",
		Rt = "134495899217974", Lf = "135179002289525", Up = "92269874316621",
		Dn = "105646906414604", Bk = "77989702677718", Ft = "99632951416960",
	},
}

return BiomeSkies
