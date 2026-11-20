-- Brainrot Heist: server entry point.
-- Wires the pure rules in GameService to the running place: remote events, leaderstats,
-- the income / conveyor / wave loops, and each player's presence in the service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- GameService requires BrainrotDefs as its sibling, so both modules must be found next to this
-- script. Under Rojo an `init.server.luau` names its own folder, which makes the modules its
-- children; when the files sit in a plain folder they are siblings instead.
local function loadModule(name)
	local found = script:FindFirstChild(name)
	if found == nil and script.Parent ~= nil then
		found = script.Parent:FindFirstChild(name)
	end
	if found == nil then
		error("Brainrot Heist: missing module " .. name)
	end
	return require(found)
end

local BrainrotDefs = loadModule("BrainrotDefs")
local GameService = loadModule("GameService")

local service = GameService.new()

local INCOME_INTERVAL = 1
local CONVEYOR_INTERVAL = GameService.CONVEYOR_INTERVAL
local WAVE_INTERVAL = GameService.WAVE_INTERVAL
local WAVE_WARNING_TIME = GameService.WAVE_WARNING_TIME

-- ---------------------------------------------------------------- remote events

local remoteFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
if remoteFolder == nil then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "RemoteEvents"
	remoteFolder.Parent = ReplicatedStorage
end

local function makeRemote(name)
	local remote = remoteFolder:FindFirstChild(name)
	if remote == nil then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remoteFolder
	end
	return remote
end

local BuyBrainrot = makeRemote("BuyBrainrot")
local StealBrainrot = makeRemote("StealBrainrot")
local LockBase = makeRemote("LockBase")
local WaveWarning = makeRemote("WaveWarning")

-- ---------------------------------------------------------------- plots on the ground

-- The service holds plots as numbers; each one gets a real floor part so players can stand on it.
local plotParts = {}

local function buildPlot(plotId)
	local spot = service:getPlotPosition(plotId)
	if spot == nil then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Plot" .. tostring(plotId)
	part.Size = Vector3.new(32, 1, 32)
	part.Position = Vector3.new(spot.x, 0.5, spot.z)
	part.Anchored = true
	part.Color = Color3.fromRGB(70, 70, 78)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = workspace
	plotParts[plotId] = part
end

for plotId = 1, GameService.PLOT_COUNT do
	buildPlot(plotId)
end

-- ---------------------------------------------------------------- leaderstats

local function setupLeaderstats(player)
	local folder = player:FindFirstChild("leaderstats")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local money = folder:FindFirstChild("Money")
	if money == nil then
		money = Instance.new("IntValue")
		money.Name = "Money"
		money.Value = GameService.STARTING_MONEY
		money.Parent = folder
	end
	return money
end

-- Pushes the service's money into the player's leaderstats, if both still exist.
local function syncMoney(player)
	local folder = player:FindFirstChild("leaderstats")
	if folder == nil then
		return
	end
	local money = folder:FindFirstChild("Money")
	if money == nil then
		return
	end
	local amount = service:getMoney(player)
	if amount ~= nil then
		money.Value = amount
	end
end

-- Tells the player's own client what happened to their request.
local function reply(remote, player, ok, message)
	remote:FireClient(player, {
		ok = ok and true or false,
		message = message,
		state = service:getState(),
	})
end

local function trackPosition(player)
	local character = player.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	service:setPosition(player, root.Position.X, root.Position.Z)
end

local function onPlayerAdded(player)
	local ok, message = service:addPlayer(player)
	if not ok and message ~= "Player already joined" then
		warn("Brainrot Heist: " .. tostring(message))
	end
	setupLeaderstats(player)

	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root ~= nil then
			service:setPosition(player, root.Position.X, root.Position.Z)
		end
	end)
	trackPosition(player)
end

local function onPlayerRemoving(player)
	service:removePlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

-- ---------------------------------------------------------------- remote handlers

BuyBrainrot.OnServerEvent:Connect(function(player, slot)
	local ok, message = service:buyBrainrot(player, slot)
	syncMoney(player)
	reply(BuyBrainrot, player, ok, message)
end)

StealBrainrot.OnServerEvent:Connect(function(player, target, index)
	-- The client sends a UserId; the service accepts a number or a Player alike.
	local ok, message = service:trySteal(player, target, index)
	syncMoney(player)
	reply(StealBrainrot, player, ok, message)
end)

LockBase.OnServerEvent:Connect(function(player)
	local ok, message = service:lockBase(player)
	reply(LockBase, player, ok, message)
end)

-- ---------------------------------------------------------------- loops

-- Income: every second each brainrot on a plot pays its owner, and the HUD Money follows.
task.spawn(function()
	while true do
		task.wait(INCOME_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			service:collectIncome(player, INCOME_INTERVAL)
			trackPosition(player)
			syncMoney(player)
		end
	end
end)

-- Conveyor: fresh offers on sale every 20 seconds.
task.spawn(function()
	while true do
		task.wait(CONVEYOR_INTERVAL)
		service:refreshConveyor()
	end
end)

-- Waves: warn every 120 seconds, then push stragglers home once the warning has run out.
task.spawn(function()
	while true do
		task.wait(WAVE_INTERVAL)
		local started, warning = service:startWave()
		if started then
			WaveWarning:FireAllClients({
				message = warning,
				seconds = WAVE_WARNING_TIME,
			})
			task.delay(WAVE_WARNING_TIME, function()
				local applied, victims = service:applyWave()
				if not applied then
					return
				end

				-- victim.key is the same key the service builds for a Player, so map the keys once.
				local byKey = {}
				for _, player in ipairs(Players:GetPlayers()) do
					local key = GameService.keyOf(player)
					if key ~= nil then
						byKey[key] = player
					end
				end

				local caught = 0
				for _, victim in ipairs(victims) do
					caught = caught + 1
					local player = byKey[victim.key]
					if player ~= nil then
						syncMoney(player)
						local spot = service:getPlotPosition(victim.plotId)
						local character = player.Character
						if spot ~= nil and character ~= nil then
							local root = character:FindFirstChild("HumanoidRootPart")
							if root ~= nil then
								root.CFrame = CFrame.new(spot.x, 5, spot.z)
							end
						end
					end
				end

				WaveWarning:FireAllClients({
					message = "The wave hit! " .. tostring(caught) .. " player(s) were caught away from base.",
					seconds = 0,
				})
			end)
		end
	end
end)

print("Brainrot Heist server ready")
