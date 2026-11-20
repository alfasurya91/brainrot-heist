-- Brainrot Heist: client HUD.
-- One ScreenGui floats over the 3D world: money at the top left, the conveyor shop on the
-- right, the base panel at the bottom left, and a wave warning across the top centre.
-- All text keeps clear of the Roblox menu button in the top-left corner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SHOP_REFRESH_SECONDS = 5
local SLOT_COUNT = 3

-- Colours
local INK = Color3.fromRGB(245, 245, 250)
local DIM = Color3.fromRGB(168, 174, 190)
local PANEL = Color3.fromRGB(22, 24, 32)
local ACCENT = Color3.fromRGB(120, 220, 140)
local WARN = Color3.fromRGB(255, 96, 96)

local RARITY_COLORS = {
	Common = Color3.fromRGB(190, 195, 205),
	Rare = Color3.fromRGB(110, 180, 255),
	Epic = Color3.fromRGB(190, 130, 255),
	Legendary = Color3.fromRGB(255, 190, 90),
	Mythic = Color3.fromRGB(255, 110, 170),
}

-- The shop the HUD draws before the server sends its own conveyor.
local CATALOGUE = {
	{ name = "Tung Tung Sahur", rarity = "Common", cost = 50, moneyPerSecond = 5 },
	{ name = "Tralalero Tralala", rarity = "Common", cost = 100, moneyPerSecond = 10 },
	{ name = "Chimpanzini Bananini", rarity = "Common", cost = 150, moneyPerSecond = 15 },
	{ name = "Ballerina Cappuccina", rarity = "Rare", cost = 300, moneyPerSecond = 30 },
	{ name = "Bombardiro Crocodilo", rarity = "Rare", cost = 450, moneyPerSecond = 45 },
	{ name = "Brr Brr Patapim", rarity = "Epic", cost = 1200, moneyPerSecond = 120 },
	{ name = "Trippi Troppi", rarity = "Legendary", cost = 3000, moneyPerSecond = 300 },
	{ name = "Giraffa Celeste", rarity = "Mythic", cost = 12000, moneyPerSecond = 1200 },
}

-- Plain state table: every label on screen is drawn from this.
local state = {
	money = 0,
	income = 0,
	baseCount = 0,
	maxSlots = 4,
	locked = false,
	shop = {},
	serverShop = false,
}

local buyRemote = nil
local stealRemote = nil
local lockRemote = nil
local waveRemote = nil

-- ---------------------------------------------------------------- small helpers

local function formatMoney(value)
	local number = math.floor(tonumber(value) or 0)
	if number < 0 then
		return "-" .. formatMoney(-number)
	end
	local text = tostring(number)
	local out = ""
	local count = 0
	for index = #text, 1, -1 do
		out = string.sub(text, index, index) .. out
		count = count + 1
		if count % 3 == 0 and index > 1 then
			out = "," .. out
		end
	end
	return out
end

local function newFrame(parent, name, size, position, anchor, color, transparency)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function newLabel(parent, name, size, position, textSize, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = color or INK
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

local function newButton(parent, name, size, position, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(14, 16, 22)
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent
	return button
end

-- ---------------------------------------------------------------- the ScreenGui

local previous = playerGui:FindFirstChild("BrainrotGui")
if previous ~= nil then
	previous:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 10
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Money: top left, but pushed down past the Roblox menu button.
local moneyPanel = newFrame(gui, "MoneyPanel", UDim2.fromOffset(240, 56), UDim2.fromOffset(28, 60), Vector2.new(0, 0), PANEL, 0.15)
local moneyTitle = newLabel(moneyPanel, "Title", UDim2.fromOffset(210, 16), UDim2.fromOffset(14, 6), 12, DIM)
moneyTitle.Text = "MONEY"
local moneyLabel = newLabel(moneyPanel, "Money", UDim2.fromOffset(210, 30), UDim2.fromOffset(14, 20), 24, ACCENT)
moneyLabel.Text = "$0"

-- Shop: right side of the screen.
local shopPanel = newFrame(gui, "ShopPanel", UDim2.fromOffset(300, 280), UDim2.new(1, -28, 0, 60), Vector2.new(1, 0), PANEL, 0.12)
local shopTitle = newLabel(shopPanel, "Title", UDim2.new(1, -24, 0, 24), UDim2.fromOffset(14, 8), 16, INK)
shopTitle.Text = "CONVEYOR SHOP"
local shopHint = newLabel(shopPanel, "Hint", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(14, 32), 12, DIM)
shopHint.Text = "Press B to buy the first offer"

local shopList = newFrame(shopPanel, "Offers", UDim2.new(1, -28, 0, 216), UDim2.fromOffset(14, 54), Vector2.new(0, 0), PANEL, 0)
shopList.BackgroundTransparency = 1

local shopRows = {}
for index = 1, SLOT_COUNT do
	local row = newFrame(shopList, "Offer" .. tostring(index), UDim2.new(1, 0, 0, 66), UDim2.fromOffset(0, (index - 1) * 72), Vector2.new(0, 0), Color3.fromRGB(34, 37, 48), 0)
	local nameLabel = newLabel(row, "Name", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 6), 15, INK)
	local rarityLabel = newLabel(row, "Rarity", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 28), 12, DIM)
	local statLabel = newLabel(row, "Stat", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 44), 12, ACCENT)
	shopRows[index] = { name = nameLabel, rarity = rarityLabel, stat = statLabel }
end

-- Base: bottom left.
local basePanel = newFrame(gui, "BasePanel", UDim2.fromOffset(300, 168), UDim2.new(0, 28, 1, -28), Vector2.new(0, 1), PANEL, 0.12)
local baseTitle = newLabel(basePanel, "Title", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(14, 8), 16, INK)
baseTitle.Text = "YOUR BASE"
local baseCountLabel = newLabel(basePanel, "Count", UDim2.new(1, -24, 0, 20), UDim2.fromOffset(14, 34), 14, INK)
local incomeLabel = newLabel(basePanel, "Income", UDim2.new(1, -24, 0, 20), UDim2.fromOffset(14, 56), 14, ACCENT)
local statusLabel = newLabel(basePanel, "Status", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(14, 80), 12, WARN)

local lockButton = newButton(basePanel, "LockButton", UDim2.fromOffset(130, 40), UDim2.fromOffset(14, 112), "Lock Base (L)", ACCENT)
local stealButton = newButton(basePanel, "StealButton", UDim2.fromOffset(130, 40), UDim2.fromOffset(154, 112), "Steal", Color3.fromRGB(255, 190, 90))

-- Wave warning: top centre, hidden until a wave comes.
local waveLabel = Instance.new("TextLabel")
waveLabel.Name = "WaveWarning"
waveLabel.Size = UDim2.fromOffset(560, 64)
waveLabel.Position = UDim2.new(0.5, 0, 0, 150)
waveLabel.AnchorPoint = Vector2.new(0.5, 0)
waveLabel.BackgroundColor3 = Color3.fromRGB(40, 10, 12)
waveLabel.BackgroundTransparency = 0.15
waveLabel.BorderSizePixel = 0
waveLabel.Font = Enum.Font.GothamBlack
waveLabel.TextSize = 30
waveLabel.TextColor3 = WARN
waveLabel.Text = ""
waveLabel.Visible = false
waveLabel.Parent = gui

-- ---------------------------------------------------------------- label updates

local function updateMoney()
	moneyLabel.Text = "$" .. formatMoney(state.money)
end

local function updateShop()
	for index = 1, SLOT_COUNT do
		local row = shopRows[index]
		local offer = state.shop[index]
		if offer == nil then
			row.name.Text = "Empty slot"
			row.rarity.Text = "-"
			row.rarity.TextColor3 = DIM
			row.stat.Text = "-"
		else
			row.name.Text = tostring(offer.name)
			row.rarity.Text = string.upper(tostring(offer.rarity))
			row.rarity.TextColor3 = RARITY_COLORS[offer.rarity] or DIM
			row.stat.Text = "$" .. formatMoney(offer.cost) .. "  -  $" .. formatMoney(offer.moneyPerSecond) .. "/s"
		end
	end
end

local function updateBase()
	baseCountLabel.Text = "Brainrots: " .. tostring(state.baseCount) .. " / " .. tostring(state.maxSlots)
	incomeLabel.Text = "Income: $" .. formatMoney(state.income) .. " / s"
	if state.locked then
		lockButton.Text = "Base Locked"
	else
		lockButton.Text = "Lock Base (L)"
	end
end

-- Pick a fresh set of offers from the local catalogue.
local function rollShop()
	local pool = {}
	for index = 1, #CATALOGUE do
		pool[index] = CATALOGUE[index]
	end
	local picked = {}
	for slot = 1, SLOT_COUNT do
		if #pool == 0 then
			break
		end
		local pick = math.random(1, #pool)
		picked[slot] = pool[pick]
		table.remove(pool, pick)
	end
	state.shop = picked
end

-- ---------------------------------------------------------------- actions

local statusToken = 0

local function notify(text)
	statusLabel.Text = text
	statusToken = statusToken + 1
	local token = statusToken
	task.delay(4, function()
		if statusToken == token then
			statusLabel.Text = ""
		end
	end)
end

local function buyOffer(slot)
	if state.shop[slot] == nil then
		notify("No offer in that slot")
		return
	end
	if buyRemote == nil then
		notify("Shop is offline")
		return
	end
	buyRemote:FireServer(slot)
end

local function findStealTarget()
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			return other
		end
	end
	return nil
end

local function stealBrainrot()
	local target = findStealTarget()
	if target == nil then
		notify("No other base to steal from")
		return
	end
	if stealRemote == nil then
		notify("Steal is offline")
		return
	end
	stealRemote:FireServer(target.UserId)
end

local function lockBase()
	if lockRemote == nil then
		notify("Lock is offline")
		return
	end
	lockRemote:FireServer()
end

lockButton.MouseButton1Click:Connect(lockBase)
stealButton.MouseButton1Click:Connect(stealBrainrot)

-- ---------------------------------------------------------------- wave warning

local waveToken = 0

local function showWave(message, seconds)
	waveToken = waveToken + 1
	local token = waveToken
	local hold = tonumber(seconds) or 5
	if hold < 3 then
		hold = 3
	end

	waveLabel.Text = tostring(message)
	waveLabel.Visible = true
	waveLabel.TextTransparency = 0

	task.spawn(function()
		local elapsed = 0
		while elapsed < hold do
			if waveToken ~= token then
				return
			end
			waveLabel.TextTransparency = 0
			task.wait(0.4)
			if waveToken ~= token then
				return
			end
			waveLabel.TextTransparency = 0.45
			task.wait(0.4)
			elapsed = elapsed + 0.8
		end
		if waveToken == token then
			waveLabel.TextTransparency = 0
			waveLabel.Visible = false
		end
	end)
end

-- ---------------------------------------------------------------- server state

local function applyServerState(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	if type(snapshot.players) == "table" then
		local mine = snapshot.players["user:" .. tostring(player.UserId)]
		if type(mine) == "number" then
			state.money = mine
		end
	end

	if type(snapshot.conveyor) == "table" and #snapshot.conveyor > 0 then
		local offers = {}
		for index = 1, math.min(#snapshot.conveyor, SLOT_COUNT) do
			local offer = snapshot.conveyor[index]
			offers[index] = {
				name = offer.name,
				rarity = offer.rarity,
				cost = offer.cost,
				moneyPerSecond = offer.moneyPerSecond,
			}
		end
		state.shop = offers
		state.serverShop = true
	end

	if type(snapshot.plots) == "table" then
		for _, plot in ipairs(snapshot.plots) do
			if plot.ownerName == player.Name and type(plot.brainrots) == "table" then
				state.baseCount = #plot.brainrots
				local rate = 0
				for _, brainrot in ipairs(plot.brainrots) do
					rate = rate + (tonumber(brainrot.moneyPerSecond) or 0)
				end
				state.income = rate
				state.locked = plot.locked == true
			end
		end
	end

	updateMoney()
	updateShop()
	updateBase()
end

local function onReply(payload)
	if type(payload) ~= "table" then
		return
	end
	applyServerState(payload.state)
	if type(payload.message) == "string" and payload.message ~= "" then
		notify(payload.message)
	end
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	if folder ~= nil then
		buyRemote = folder:WaitForChild("BuyBrainrot", 10)
		stealRemote = folder:WaitForChild("StealBrainrot", 10)
		lockRemote = folder:WaitForChild("LockBase", 10)
		waveRemote = folder:WaitForChild("WaveWarning", 10)
	else
		waveRemote = ReplicatedStorage:WaitForChild("WaveWarning", 10)
	end

	if buyRemote ~= nil then
		buyRemote.OnClientEvent:Connect(onReply)
	end
	if stealRemote ~= nil then
		stealRemote.OnClientEvent:Connect(onReply)
	end
	if lockRemote ~= nil then
		lockRemote.OnClientEvent:Connect(onReply)
	end
	if waveRemote ~= nil then
		waveRemote.OnClientEvent:Connect(function(payload)
			if type(payload) == "table" then
				showWave(payload.message or "WAVE INCOMING", payload.seconds)
			elseif type(payload) == "string" then
				showWave(payload, 6)
			else
				showWave("WAVE INCOMING", 6)
			end
		end)
	end
end)

-- ---------------------------------------------------------------- money from leaderstats

task.spawn(function()
	local folder = player:WaitForChild("leaderstats", 20)
	if folder == nil then
		return
	end
	local money = folder:WaitForChild("Money", 20)
	if money == nil then
		return
	end
	local function sync()
		state.money = money.Value
		updateMoney()
	end
	money.Changed:Connect(sync)
	sync()
end)

-- ---------------------------------------------------------------- keybinds

-- ContextActionService only, so typing in chat never triggers a purchase.
local function onAction(actionName, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if actionName == "BuyFirstOffer" then
		buyOffer(1)
		return Enum.ContextActionResult.Sink
	elseif actionName == "LockTheBase" then
		lockBase()
		return Enum.ContextActionResult.Sink
	elseif actionName == "StealBrainrot" then
		stealBrainrot()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("BuyFirstOffer", onAction, false, Enum.KeyCode.B)
ContextActionService:BindAction("LockTheBase", onAction, false, Enum.KeyCode.L)
ContextActionService:BindAction("StealBrainrot", onAction, false, Enum.KeyCode.S)

-- ---------------------------------------------------------------- start

rollShop()
updateMoney()
updateShop()
updateBase()

-- The shop rerolls on its own timer until the server's conveyor takes over.
task.spawn(function()
	while true do
		task.wait(SHOP_REFRESH_SECONDS)
		if not state.serverShop then
			rollShop()
		end
		updateShop()
	end
end)

print("Brainrot Heist client ready")
