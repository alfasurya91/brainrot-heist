-- GameService
-- The whole server-side state of Brainrot Heist: players and their money, the four base plots,
-- the conveyor of brainrots on sale, locks, steal cooldowns and the wave hazard.
--
-- Nothing here touches Roblox instances, so the rules can be exercised without a running place.
-- Every public function validates its arguments and answers (false, message) when it cannot act,
-- so a bad RemoteEvent payload can never crash the server.
--
-- Usage:
--   local service = GameService.new()
--   service:addPlayer(player)        -- on PlayerAdded
--   service:buyBrainrot(player, 1)   -- on BuyBrainrot
--   service:collectIncome(player)    -- once per second
--   service:refreshConveyor()        -- once every 20 seconds
--   service:startWave()              -- once every 120 seconds, then :applyWave() after the warning

local BrainrotDefs = require(script.Parent.BrainrotDefs)

local GameService = {}
GameService.__index = GameService

-- Rules
local STARTING_MONEY = 100
local PLOT_COUNT = 4
local SLOTS_PER_PLOT = 4
local CONVEYOR_OFFERS = 3
local CONVEYOR_INTERVAL = 20
local STEAL_COOLDOWN = 30
local LOCK_DURATION = 20
local LOCK_COOLDOWN = 60
local WAVE_INTERVAL = 120
local WAVE_WARNING_TIME = 5
local WAVE_SAFE_RADIUS = 24
local WAVE_STEAL_PERCENT = 0.05
local WAVE_MIN_STEAL = 5
local MAX_INCOME_STEP = 60

GameService.STARTING_MONEY = STARTING_MONEY
GameService.PLOT_COUNT = PLOT_COUNT
GameService.SLOTS_PER_PLOT = SLOTS_PER_PLOT
GameService.CONVEYOR_INTERVAL = CONVEYOR_INTERVAL
GameService.STEAL_COOLDOWN = STEAL_COOLDOWN
GameService.LOCK_DURATION = LOCK_DURATION
GameService.LOCK_COOLDOWN = LOCK_COOLDOWN
GameService.WAVE_INTERVAL = WAVE_INTERVAL
GameService.WAVE_WARNING_TIME = WAVE_WARNING_TIME

-- ---------------------------------------------------------------- helpers

-- A stable key for a player: a Player instance, a positive number or a non-empty string.
-- Returns nil when the value cannot name a player.
local function keyOf(player, allowName)
	if type(player) == "string" then
		if player == "" then
			return nil
		end
		return player
	end
	if type(player) == "number" then
		if player ~= player or player <= 0 then
			return nil
		end
		return "user:" .. tostring(math.floor(player))
	end
	if type(player) == "table" and type(player.UserId) == "number" then
		return "user:" .. tostring(player.UserId)
	elseif type(player) == "userdata" and type(player.UserId) == "number" then
		return "user:" .. tostring(player.UserId)
	end
	if allowName and type(player) == "table" and type(player.Name) == "string" then
		return "name:" .. player.Name
	end
	return nil
end
GameService.keyOf = keyOf

-- A display name for messages, without trusting anything the caller sent us.
local function displayName(player, key)
	if type(player) == "table" and type(player.Name) == "string" then
		return player.Name
	elseif type(player) == "userdata" and type(player.Name) == "string" then
		return player.Name
	end
	return key
end

local function round(value)
	return math.floor(value + 0.5)
end

-- A fresh brainrot instance for a plot: a copy of the definition plus a unique instance id.
local function makeInstance(definition, nextId)
	return {
		id = nextId,
		name = definition.name,
		rarity = definition.rarity,
		cost = definition.cost,
		moneyPerSecond = definition.moneyPerSecond,
		color = { definition.color[1], definition.color[2], definition.color[3] },
	}
end

-- ---------------------------------------------------------------- constructor

-- Builds the service. `options.now` may pass a clock (seconds, monotonic); it defaults to os.clock.
function GameService.new(options)
	local self = setmetatable({}, GameService)
	self._now = os.clock
	if type(options) == "table" and type(options.now) == "function" then
		self._now = options.now
	end
	self._players = {}
	self._plots = {}
	self._conveyor = {}
	self._nextBrainrotId = 1
	self._waveCount = 0
	self._waveWarningUntil = nil
	self._waveApplied = true
	self._lastWaveAt = nil

	for index = 1, PLOT_COUNT do
		self._plots[index] = {
			id = index,
			ownerKey = nil,
			ownerName = nil,
			brainrots = {},
			lockUntil = 0,
			lockReadyAt = 0,
			position = { x = (index - (PLOT_COUNT + 1) / 2) * 60, z = 0 },
		}
	end

	self:refreshConveyor()
	return self
end

-- ---------------------------------------------------------------- players and plots

-- Registers a player with STARTING_MONEY and, when a plot is free, gives them one.
-- Returns (true, message) or (false, message) when the player is already known.
function GameService:addPlayer(player)
	local key = keyOf(player, true)
	if key == nil then
		return false, "Invalid player"
	end
	if self._players[key] ~= nil then
		return false, "Player already joined"
	end

	local plotId = nil
	for index = 1, PLOT_COUNT do
		local plot = self._plots[index]
		if plot.ownerKey == nil then
			plot.ownerKey = key
			plot.ownerName = displayName(player, key)
			plotId = index
			break
		end
	end

	self._players[key] = {
		money = STARTING_MONEY,
		plotId = plotId,
		stealReadyAt = 0,
		position = nil,
	}
	return true, "Welcome, you start with " .. tostring(STARTING_MONEY) .. " money"
end

-- Forgets a player. The plot stays owned by them so their brainrots are not lost by accident.
function GameService:removePlayer(player)
	local key = keyOf(player, true)
	if key == nil or self._players[key] == nil then
		return false, "Unknown player"
	end
	self._players[key] = nil
	return true, "Player removed"
end

-- Records where a player is, in studs, for the wave hazard. Safe to call every second.
function GameService:setPosition(player, x, z)
	local key = keyOf(player)
	if key == nil or self._players[key] == nil then
		return false, "Unknown player"
	end
	if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then
		return false, "Position must be two finite numbers"
	end
	self._players[key].position = { x = x, z = z }
	return true, "Position updated"
end

-- The plot a player owns, or nil.
function GameService:getPlayerPlot(player)
	local key = keyOf(player)
	if key == nil then
		return nil
	end
	local state = self._players[key]
	if state == nil or state.plotId == nil then
		return nil
	end
	return self._plots[state.plotId]
end

-- A player's money, or nil when they are unknown. Lets the leaderstats read without a full snapshot.
function GameService:getMoney(player)
	local key = keyOf(player)
	if key == nil then
		return nil
	end
	local state = self._players[key]
	if state == nil then
		return nil
	end
	return state.money
end

-- Where a plot sits on the ground, as {x, z}, or nil for an unknown plot id.
-- The server script uses this to place real parts and to send players home.
function GameService:getPlotPosition(plotId)
	if type(plotId) ~= "number" or plotId ~= math.floor(plotId) then
		return nil
	end
	local plot = self._plots[plotId]
	if plot == nil then
		return nil
	end
	return { x = plot.position.x, z = plot.position.z }
end

-- How many brainrots are already on a plot.
function GameService:getPlotCount(plot)
	if type(plot) ~= "table" or type(plot.brainrots) ~= "table" then
		return 0
	end
	local count = 0
	for _ in pairs(plot.brainrots) do
		count = count + 1
	end
	return count
end

-- ---------------------------------------------------------------- conveyor

-- One conveyor row for a catalogue entry.
local function makeOffer(slot, definition)
	return {
		slot = slot,
		name = definition.name,
		rarity = definition.rarity,
		cost = definition.cost,
		moneyPerSecond = definition.moneyPerSecond,
		color = definition.color,
		sold = false,
	}
end

-- Fills the conveyor with fresh offers, each with its own cost taken from the catalogue.
-- Cheaper rarities are likelier, and one slot always holds a brainrot a new player can afford,
-- so the shop is never a dead end. Called once on build, then every CONVEYOR_INTERVAL seconds.
function GameService:refreshConveyor()
	local catalogue = BrainrotDefs.List
	local weights = {}
	local total = 0
	local cheapest = nil
	for index = 1, #catalogue do
		local entry = catalogue[index]
		local rank = BrainrotDefs.getRarityRank(entry.rarity)
		-- Common weighs 5, Mythic 1: the rare ones stay a treat, not the usual offer.
		local weight = 6 - rank
		if weight < 1 then
			weight = 1
		end
		weights[index] = weight
		total = total + weight
		if cheapest == nil or entry.cost < cheapest.cost then
			cheapest = entry
		end
	end

	local offers = {}
	for slot = 1, CONVEYOR_OFFERS do
		local definition = nil
		if total > 0 then
			local roll = math.random(total)
			local running = 0
			for index = 1, #catalogue do
				running = running + weights[index]
				if roll <= running then
					definition = catalogue[index]
					break
				end
			end
		end
		if definition == nil then
			definition = BrainrotDefs.getRandom()
		end
		if definition ~= nil then
			offers[slot] = makeOffer(slot, definition)
		end
	end

	-- Keep one affordable row on the conveyor: replace the priciest offer with the cheapest entry.
	if cheapest ~= nil and cheapest.cost <= STARTING_MONEY then
		local affordable = false
		for slot = 1, #offers do
			if offers[slot] ~= nil and offers[slot].cost <= STARTING_MONEY then
				affordable = true
				break
			end
		end
		if not affordable and #offers > 0 then
			local target = 1
			local priciest = -1
			for slot = 1, #offers do
				if offers[slot] ~= nil and offers[slot].cost > priciest then
					priciest = offers[slot].cost
					target = slot
				end
			end
			offers[target] = makeOffer(target, cheapest)
		end
	end

	self._conveyor = offers
	return true, "Conveyor refreshed"
end

-- Buys the offer in `slot` and drops the brainrot on the buyer's first empty plot slot.
-- Fails when the player, the slot, the money or the room is missing.
function GameService:buyBrainrot(player, slot)
	local key = keyOf(player)
	if key == nil then
		return false, "Invalid player"
	end
	local state = self._players[key]
	if state == nil then
		return false, "Player has not joined"
	end
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > CONVEYOR_OFFERS then
		return false, "Invalid conveyor slot"
	end
	local offer = self._conveyor[slot]
	if offer == nil or offer.sold then
		return false, "That brainrot is already gone"
	end
	if state.money < offer.cost then
		return false, "Not enough money"
	end
	local plot = self:getPlayerPlot(player)
	if plot == nil then
		return false, "You have no plot"
	end
	if self:getPlotCount(plot) >= SLOTS_PER_PLOT then
		return false, "Your plot is full"
	end

	state.money = state.money - offer.cost
	self._nextBrainrotId = self._nextBrainrotId + 1
	local instance = makeInstance(offer, self._nextBrainrotId)
	table.insert(plot.brainrots, instance)
	offer.sold = true

	local message = "Bought " .. instance.name .. " for " .. tostring(instance.cost)
	return true, message
end

-- ---------------------------------------------------------------- plots

-- Places a brainrot by catalogue name on a plot. The plot defaults to the player's own.
-- Refuses a plot the player does not own, a full plot and an unknown name.
function GameService:placeOnPlot(player, brainrotName, plotId)
	local key = keyOf(player)
	if key == nil then
		return false, "Invalid player"
	end
	if self._players[key] == nil then
		return false, "Player has not joined"
	end
	local definition = BrainrotDefs.getByName(brainrotName)
	if definition == nil then
		return false, "Unknown brainrot"
	end

	local plot
	if plotId == nil then
		plot = self:getPlayerPlot(player)
	else
		if type(plotId) ~= "number" or plotId ~= math.floor(plotId) then
			return false, "Invalid plot"
		end
		plot = self._plots[plotId]
	end
	if plot == nil then
		return false, "Unknown plot"
	end
	if plot.ownerKey ~= key then
		return false, "That plot is not yours"
	end
	if self:getPlotCount(plot) >= SLOTS_PER_PLOT then
		return false, "That plot is full"
	end

	self._nextBrainrotId = self._nextBrainrotId + 1
	table.insert(plot.brainrots, makeInstance(definition, self._nextBrainrotId))
	return true, definition.name .. " placed on plot " .. tostring(plot.id)
end

-- Adds one second (or `seconds`) of income from every brainrot on the player's plot.
-- Returns (amount, message); the amount is a whole number of money.
function GameService:collectIncome(player, seconds)
	local key = keyOf(player)
	if key == nil then
		return false, "Invalid player"
	end
	local state = self._players[key]
	if state == nil then
		return false, "Player has not joined"
	end
	local step = 1
	if seconds ~= nil then
		if type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 then
			return false, "Invalid income step"
		end
		step = math.min(seconds, MAX_INCOME_STEP)
	end
	local plot = self:getPlayerPlot(player)
	if plot == nil then
		return false, "You have no plot"
	end

	local rate = 0
	for index = 1, #plot.brainrots do
		rate = rate + plot.brainrots[index].moneyPerSecond
	end
	local amount = round(rate * step)
	if amount <= 0 then
		return false, "Nothing to collect yet"
	end

	state.money = state.money + amount
	return amount, "+" .. tostring(amount) .. " money"
end

-- ---------------------------------------------------------------- stealing

-- Takes a brainrot from another player's unlocked plot and puts it on the thief's plot.
-- `index` picks a brainrot on the victim's plot; nil takes the most valuable one.
-- One steal per STEAL_COOLDOWN seconds per player.
function GameService:trySteal(player, target, index)
	local thiefKey = keyOf(player)
	if thiefKey == nil then
		return false, "Invalid player"
	end
	local thief = self._players[thiefKey]
	if thief == nil then
		return false, "Player has not joined"
	end
	local targetKey = keyOf(target, true)
	if targetKey == nil then
		return false, "Invalid target"
	end
	if targetKey == thiefKey then
		return false, "You cannot steal from yourself"
	end
	local victim = self._players[targetKey]
	if victim == nil then
		return false, "That player has not joined"
	end
	local thiefPlot = self:getPlayerPlot(player)
	if thiefPlot == nil then
		return false, "You have no plot"
	end
	if self:getPlotCount(thiefPlot) >= SLOTS_PER_PLOT then
		return false, "Your plot is full"
	end

	local now = self._now()
	if now < thief.stealReadyAt then
		return false, "Steal cooling down for " .. tostring(round(thief.stealReadyAt - now)) .. "s"
	end

	local victimPlot = self:getPlayerPlot(target)
	if victimPlot == nil then
		return false, "That player has no plot"
	end
	if now < victimPlot.lockUntil then
		return false, "That base is locked"
	end
	local count = self:getPlotCount(victimPlot)
	if count == 0 then
		return false, "Nothing to steal there"
	end

	local pick = nil
	if index ~= nil then
		if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > count then
			return false, "Invalid brainrot on that plot"
		end
		pick = victimPlot.brainrots[index]
	else
		local bestRate = -1
		for position = 1, count do
			local candidate = victimPlot.brainrots[position]
			if candidate ~= nil and candidate.moneyPerSecond > bestRate then
				bestRate = candidate.moneyPerSecond
				pick = candidate
			end
		end
	end
	if pick == nil then
		return false, "Nothing to steal there"
	end

	-- Remove from the victim first, then add to the thief, so a failure never duplicates.
	for position = 1, #victimPlot.brainrots do
		if victimPlot.brainrots[position] == pick then
			table.remove(victimPlot.brainrots, position)
			break
		end
	end
	table.insert(thiefPlot.brainrots, pick)
	thief.stealReadyAt = now + STEAL_COOLDOWN

	local message = "Stole " .. pick.name .. " from " .. displayName(target, targetKey)
	return true, message
end

-- ---------------------------------------------------------------- base lock

-- Locks the player's own base for LOCK_DURATION seconds. No stealing from a locked base.
-- The ability's cooldown counts from activation, so a lock can start again LOCK_COOLDOWN
-- seconds after the last one began; between the lock expiring and the cooldown ending the
-- base is exposed.
function GameService:lockBase(player)
	local key = keyOf(player)
	if key == nil then
		return false, "Invalid player"
	end
	if self._players[key] == nil then
		return false, "Player has not joined"
	end
	local plot = self:getPlayerPlot(player)
	if plot == nil then
		return false, "You have no plot"
	end
	local now = self._now()
	if now < plot.lockUntil then
		return false, "Base is already locked for " .. tostring(round(plot.lockUntil - now)) .. "s"
	end
	if now < plot.lockReadyAt then
		return false, "Lock cooling down for " .. tostring(round(plot.lockReadyAt - now)) .. "s"
	end

	plot.lockUntil = now + LOCK_DURATION
	plot.lockReadyAt = now + LOCK_COOLDOWN
	return true, "Base locked for " .. tostring(LOCK_DURATION) .. "s"
end

-- True while the player's base is locked. False for anything invalid, never an error.
function GameService:isBaseLocked(player)
	local plot = self:getPlayerPlot(player)
	if plot == nil then
		return false
	end
	return self._now() < plot.lockUntil
end

-- ---------------------------------------------------------------- waves

-- Starts a wave: warns everyone and schedules the hazard for WAVE_WARNING_TIME later.
-- The caller runs :applyWave() after that delay. Returns (true, warning) or (false, reason).
function GameService:startWave()
	if not self._waveApplied then
		return false, "A wave is already on its way"
	end
	local now = self._now()
	self._waveCount = self._waveCount + 1
	self._waveWarningUntil = now + WAVE_WARNING_TIME
	self._waveApplied = false
	self._lastWaveAt = now

	local warning = "WAVE " .. tostring(self._waveCount) .. " incoming! Get back to your base"
	return true, warning
end

-- Applies the pending wave hazard: players far from their base are pushed home and lose a
-- little money (WAVE_STEAL_PERCENT of it, at least WAVE_MIN_STEAL). Doing nothing is safe.
-- Returns (summary, table) where the table lists what happened to each player.
function GameService:applyWave()
	if self._waveApplied then
		return false, "No wave is pending"
	end
	local now = self._now()
	if self._waveWarningUntil ~= nil and now < self._waveWarningUntil then
		return false, "The warning has not finished yet"
	end
	self._waveApplied = true

	local summary = {}
	for key, state in pairs(self._players) do
		local plot = nil
		if state.plotId ~= nil then
			plot = self._plots[state.plotId]
		end
		local distance = math.huge
		if plot ~= nil and state.position ~= nil then
			local dx = state.position.x - plot.position.x
			local dz = state.position.z - plot.position.z
			distance = math.sqrt(dx * dx + dz * dz)
		end
		if distance > WAVE_SAFE_RADIUS then
			local stolen = math.min(state.money, math.max(WAVE_MIN_STEAL, round(state.money * WAVE_STEAL_PERCENT)))
			state.money = state.money - stolen
			if plot ~= nil then
				state.position = { x = plot.position.x, z = plot.position.z }
			end
			table.insert(summary, { key = key, plotId = state.plotId, money = stolen, pushed = true })
		end
	end
	return true, summary
end

-- ---------------------------------------------------------------- state snapshot

-- A plain deep copy of the state the UI reads. No functions, no shared tables.
function GameService:getState()
	local now = self._now()
	local plots = {}
	for index = 1, PLOT_COUNT do
		local plot = self._plots[index]
		local brainrots = {}
		for position = 1, #plot.brainrots do
			local brainrot = plot.brainrots[position]
			brainrots[position] = {
				id = brainrot.id,
				name = brainrot.name,
				rarity = brainrot.rarity,
				cost = brainrot.cost,
				moneyPerSecond = brainrot.moneyPerSecond,
				color = { brainrot.color[1], brainrot.color[2], brainrot.color[3] },
			}
		end
		local lockRemaining = 0
		if plot.lockUntil > now then
			lockRemaining = round(plot.lockUntil - now)
		end
		plots[index] = {
			id = plot.id,
			ownerName = plot.ownerName,
			locked = plot.lockUntil > now,
			lockRemaining = lockRemaining,
			position = { x = plot.position.x, z = plot.position.z },
			brainrots = brainrots,
		}
	end

	local offers = {}
	for index = 1, #self._conveyor do
		local offer = self._conveyor[index]
		offers[index] = {
			slot = offer.slot,
			name = offer.name,
			rarity = offer.rarity,
			cost = offer.cost,
			moneyPerSecond = offer.moneyPerSecond,
			color = { offer.color[1], offer.color[2], offer.color[3] },
			sold = offer.sold,
		}
	end

	local money = {}
	for key, state in pairs(self._players) do
		money[key] = state.money
	end

	return {
		players = money,
		plots = plots,
		conveyor = offers,
		waveTimer = WAVE_INTERVAL,
		wave = {
			count = self._waveCount,
			active = not self._waveApplied,
			secondsUntilHazard = 0,
		},
	}
end

return GameService
