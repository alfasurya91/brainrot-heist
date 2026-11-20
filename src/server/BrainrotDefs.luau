-- BrainrotDefs
-- Static catalogue of every brainrot in the game: 12 characters across 5 rarities.
-- A brainrot is a plain table: name, rarity, cost, moneyPerSecond, color ({r, g, b} 0-255).
-- This module holds no state; it is safe to require from anywhere.

local BrainrotDefs = {}

-- Rarities from cheapest to most expensive. Everything else derives its order from this list.
BrainrotDefs.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

local rarityRank = {}
for index = 1, #BrainrotDefs.RarityOrder do
	rarityRank[BrainrotDefs.RarityOrder[index]] = index
end
BrainrotDefs.RarityRank = rarityRank

-- The catalogue. cost grows with rarity; moneyPerSecond is about a tenth of cost.
local LIST = {
	-- Common: 3
	{ name = "Tung Tung Sahur", rarity = "Common", cost = 50, moneyPerSecond = 5, color = { 196, 154, 108 } },
	{ name = "Tralalero Tralala", rarity = "Common", cost = 100, moneyPerSecond = 10, color = { 58, 140, 214 } },
	{ name = "Chimpanzini Bananini", rarity = "Common", cost = 150, moneyPerSecond = 15, color = { 240, 200, 60 } },

	-- Rare: 3
	{ name = "Ballerina Cappuccina", rarity = "Rare", cost = 300, moneyPerSecond = 30, color = { 232, 176, 186 } },
	{ name = "Bombardiro Crocodilo", rarity = "Rare", cost = 450, moneyPerSecond = 45, color = { 86, 132, 60 } },
	{ name = "Lirili Larila", rarity = "Rare", cost = 600, moneyPerSecond = 60, color = { 120, 180, 96 } },

	-- Epic: 2
	{ name = "Brr Brr Patapim", rarity = "Epic", cost = 1200, moneyPerSecond = 120, color = { 110, 86, 58 } },
	{ name = "Frigo Camelo", rarity = "Epic", cost = 1800, moneyPerSecond = 180, color = { 198, 216, 226 } },

	-- Legendary: 2
	{ name = "Trippi Troppi", rarity = "Legendary", cost = 3000, moneyPerSecond = 300, color = { 238, 130, 118 } },
	{ name = "Cappuccino Assassino", rarity = "Legendary", cost = 4000, moneyPerSecond = 400, color = { 128, 84, 52 } },

	-- Mythic: 2
	{ name = "La Vaca Saturno Saturnita", rarity = "Mythic", cost = 6000, moneyPerSecond = 600, color = { 156, 120, 208 } },
	{ name = "Giraffa Celeste", rarity = "Mythic", cost = 12000, moneyPerSecond = 1200, color = { 126, 188, 236 } },
}

BrainrotDefs.List = LIST
BrainrotDefs.Count = #LIST

-- Indexes built once at require time, so lookups are O(1).
local byName = {}
local byRarity = {}

for index = 1, #LIST do
	local brainrot = LIST[index]
	byName[brainrot.name] = brainrot
	if byRarity[brainrot.rarity] == nil then
		byRarity[brainrot.rarity] = {}
	end
	table.insert(byRarity[brainrot.rarity], brainrot)
end

-- Returns the brainrot with this exact name, or nil when the name is unknown or not a string.
function BrainrotDefs.getByName(name)
	if type(name) ~= "string" then
		return nil
	end
	return byName[name]
end

-- Returns a new array of the brainrots of one rarity, cheapest first.
-- Returns an empty table (never nil) for an unknown rarity, so callers can loop safely.
function BrainrotDefs.getByRarity(rarity)
	local result = {}
	if type(rarity) ~= "string" then
		return result
	end
	local found = byRarity[rarity]
	if found == nil then
		return result
	end
	for index = 1, #found do
		result[index] = found[index]
	end
	return result
end

-- Returns true when the string is one of the five rarity names.
function BrainrotDefs.isRarity(rarity)
	if type(rarity) ~= "string" then
		return false
	end
	return rarityRank[rarity] ~= nil
end

-- Returns the rarity's position in RarityOrder, or 0 when unknown.
function BrainrotDefs.getRarityRank(rarity)
	if type(rarity) ~= "string" then
		return 0
	end
	return rarityRank[rarity] or 0
end

-- Returns a shallow copy of a random catalogue entry, or nil when the catalogue is empty.
-- The copy is a fresh table, so callers may attach instance ids without touching the catalogue.
function BrainrotDefs.getRandom(randomObject)
	if #LIST == 0 then
		return nil
	end
	local index
	if randomObject ~= nil then
		index = randomObject:NextInteger(1, #LIST)
	else
		index = math.random(1, #LIST)
	end
	local source = LIST[index]
	return {
		name = source.name,
		rarity = source.rarity,
		cost = source.cost,
		moneyPerSecond = source.moneyPerSecond,
		color = { source.color[1], source.color[2], source.color[3] },
	}
end

return BrainrotDefs
