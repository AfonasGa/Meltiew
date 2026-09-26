-- StarterGui.Hud.Client: everything on screen. Status and timer, the role banner, the
-- character inventory, generator puzzles, the killer's buttons, results, spectating.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RS = game.ReplicatedStorage
local Shared = require(RS.Shared)
local State = RS.State
local Remotes = RS.Remotes

local me = Players.LocalPlayer
local gui = script.Parent
local cam = workspace.CurrentCamera
local touch = UIS.TouchEnabled

local INK = Color3.fromHex("#0f0d16")
local PANEL = Color3.fromHex("#16131f")
local TEXT = Color3.fromHex("#f4f1ec")
local MUTED = Color3.fromHex("#a39bb8")
local RED = Color3.fromHex("#ff4d6d")
local MINT = Color3.fromHex("#7ee0c3")
local GOLD = Color3.fromHex("#ffd166")
local VIOLET = Color3.fromHex("#b89cff")

-- ------------------------------------------------------------------------------------
-- Small UI kit
-- ------------------------------------------------------------------------------------

local function new(class, props, children)
	local o = Instance.new(class)
	for k, v in props or {} do
		o[k] = v
	end
	for _, c in children or {} do
		c.Parent = o
	end
	return o
end

local function corner(r)
	return new("UICorner", { CornerRadius = r or 14 })
end

local function stroke(color, thick, transp)
	return new("UIStroke", { Color = color or Color3.new(1, 1, 1), Thickness = thick or 2, Transparency = transp or 0.85 })
end

local function panel(props, children)
	props.BackgroundColor = props.BackgroundColor or PANEL
	props.BackgroundTransparency = props.BackgroundTransparency or 0.18
	local radius = props.Radius or 16
	props.Radius = nil
	local f = new("Frame", props, children)
	corner(radius).Parent = f
	return f
end

local function label(props)
	props.BackgroundTransparency = 1
	props.TextColor = props.TextColor or TEXT
	props.Font = props.Font or "Bold"
	props.TextSize = props.TextSize or 18
	return new("TextLabel", props)
end

local function button(text, color, props)
	props = props or {}
	props.Text = text
	props.BackgroundColor = color or VIOLET
	props.TextColor = props.TextColor or INK
	props.Font = props.Font or "Black"
	props.TextSize = props.TextSize or 18
	local radius = props.Radius or 14
	props.Radius = nil
	local b = new("TextButton", props)
	corner(radius).Parent = b
	return b
end

local function tween(obj, t, goal, style)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or "Quad", "Out"), goal)
	tw:Play()
	return tw
end

local function sound(name, volume)
	local id = Shared.sound(name)
	if id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.9
	s.Parent = script
	s:Play()
	task.delay(6, function()
		s:Destroy()
	end)
end

local function role()
	local r = me:FindFirstChild("Role")
	return r and r.Value or "lobby"
end

local function inRound()
	local r = role()
	return State.Phase.Value == "Round" and (r == "killer" or r == "survivor")
end

-- ------------------------------------------------------------------------------------
-- Status bar (top middle)
-- ------------------------------------------------------------------------------------

local status = panel({ Size = UDim2.fromOffset(340, 70), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 5 })
local statusBig = label({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 2), TextSize = 30, Font = "Black", ZIndex = 6, Parent = status })
local statusSmall = label({ Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 44), TextSize = 14, TextColor = MUTED, ZIndex = 6, Parent = status })
status.Parent = gui

local lastTick = -1

local function refreshStatus()
	local phase = State.Phase.Value
	local t = State.TimeLeft.Value
	if phase == "Round" then
		local sub
		if State.Release.Value > 0 then
			sub = Strings.get("st_release", State.Release.Value)
		else
			sub = Strings.get("st_round_sub", State.GensDone.Value, State.GensTotal.Value, State.Alive.Value)
		end
		statusBig.Text = Shared.clock(t)
		statusBig.TextColor = t <= 30 and RED or TEXT
		statusSmall.Text = inRound() and sub or Strings.get("st_watching", State.Alive.Value)
	elseif phase == "End" then
		statusBig.Text = Strings.get("st_end")
		statusBig.TextColor = TEXT
		statusSmall.Text = ""
	else
		local c = State.Countdown.Value
		statusBig.TextColor = TEXT
		if c > 0 then
			statusBig.Text = Strings.get("st_starting", c)
			statusSmall.Text = Strings.get("st_players", State.Waiting.Value)
			if c <= 5 and c ~= lastTick then
				lastTick = c
				sound("SfxTick", 0.6)
			end
		else
			statusBig.Text = Strings.get("st_waiting")
			statusSmall.Text = Strings.get("st_need", State.Waiting.Value, Shared.MIN_PLAYERS)
		end
	end
end

for _, v in State:GetChildren() do
	v.Changed:Connect(refreshStatus)
end

-- ------------------------------------------------------------------------------------
-- Notifications (under the status)
-- ------------------------------------------------------------------------------------

local feed = new("Frame", { Size = UDim2.fromOffset(420, 200), Position = UDim2.new(0.5, 0, 0, 88), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 5, Parent = gui },
	{ new("UIListLayout", { Padding = 6, HorizontalAlignment = "Center" }) })

local function toast(text, color)
	local t = panel({ Size = UDim2.fromOffset(400, 34), BackgroundColor = INK, BackgroundTransparency = 0.25, ZIndex = 5 })
	label({ Text = text, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextSize = 16, TextColor = color or TEXT, ZIndex = 6, Parent = t })
	t.Parent = feed
	task.delay(3.5, function()
		tween(t, 0.4, { BackgroundTransparency = 1 })
		task.wait(0.45)
		t:Destroy()
	end)
end

-- ------------------------------------------------------------------------------------
-- Big center messages: role banner, caught, results
-- ------------------------------------------------------------------------------------

local banner = panel({ Size = UDim2.fromOffset(520, 150), Position = UDim2.fromScale(0.5, 0.38), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor = INK, BackgroundTransparency = 0.12, Visible = false, ZIndex = 20, Radius = 22 })
local bannerTitle = label({ Size = UDim2.new(1, -20, 0, 60), Position = UDim2.fromOffset(10, 8), TextSize = 40, Font = "Black", ZIndex = 21, Parent = banner })
local bannerSub = label({ Size = UDim2.new(1, -30, 0, 40), Position = UDim2.fromOffset(15, 68), TextSize = 17, TextColor = MUTED, Font = "Bold", ZIndex = 21, Parent = banner })
local bannerHint = label({ Size = UDim2.new(1, -30, 0, 24), Position = UDim2.fromOffset(15, 112), TextSize = 14, TextColor = MUTED, Font = "Regular", ZIndex = 21, Parent = banner })
local bannerStroke = stroke(RED, 3, 0.3)
bannerStroke.Parent = banner
banner.Parent = gui

local bannerToken = 0
local function showBanner(title, sub, hint, color, seconds)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor = color
	bannerSub.Text = sub
	bannerHint.Text = hint or ""
	bannerStroke.Color = color
	banner.Visible = true
	banner.BackgroundTransparency = 1
	tween(banner, 0.35, { BackgroundTransparency = 0.12 })
	if seconds then
		task.delay(seconds, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end
end

-- Red flash when hurt.
local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor = RED, BackgroundTransparency = 1, ZIndex = 1, Parent = gui })

Remotes.Hit.OnClientEvent:Connect(function(amount)
	flash.BackgroundTransparency = 0.55
	tween(flash, 0.6, { BackgroundTransparency = 1 })
	cam:Shake(3 + amount / 10, 0.35)
end)

-- ------------------------------------------------------------------------------------
-- Lobby side panel: coins, characters, spectate
-- ------------------------------------------------------------------------------------

local side = new("Frame", { Size = UDim2.fromOffset(190, 200), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Parent = gui },
	{ new("UIListLayout", { Padding = 8 }) })
local coinPill = panel({ Size = UDim2.fromOffset(190, 44), BackgroundColor = INK, LayoutOrder = 1, Parent = side })
local coinText = label({ Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextColor = GOLD, TextSize = 18, Font = "Black", Parent = coinPill })
local charsBtn = button(Strings.get("btn_characters"), VIOLET, { Size = UDim2.fromOffset(190, 48), LayoutOrder = 2, Parent = side })
local watchBtn = button(Strings.get("btn_watch"), MINT, { Size = UDim2.fromOffset(190, 48), LayoutOrder = 3, Visible = false, Parent = side })

local function refreshCoins()
	local c = me:FindFirstChild("Coins")
	coinText.Text = Strings.get("coins", c and c.Value or 0)
end

-- ------------------------------------------------------------------------------------
-- Characters (inventory): one killer, one survivor for now, with their pictures
-- ------------------------------------------------------------------------------------

local inv = panel({ Size = UDim2.fromOffset(660, 420), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor = INK, BackgroundTransparency = 0.05, Visible = false, ZIndex = 30, Radius = 24 })
inv.Parent = gui
label({ Text = Strings.get("inv_title"), Size = UDim2.new(1, -80, 0, 44), Position = UDim2.fromOffset(22, 12), TextSize = 28, Font = "Black", TextXAlignment = "Left", ZIndex = 31, Parent = inv })
local invClose = button("X", PANEL, { Size = UDim2.fromOffset(44, 44), Position = UDim2.new(1, -58, 0, 14), TextColor = TEXT, ZIndex = 31, Parent = inv })
invClose.Activated:Connect(function()
	inv.Visible = false
end)

local function characterCard(parent, info, kind, x)
	local color = Color3.fromHex(info.color)
	local card = panel({ Size = UDim2.fromOffset(300, 340), Position = UDim2.fromOffset(x, 64), BackgroundColor = PANEL, BackgroundTransparency = 0, ZIndex = 31, Radius = 18, Parent = parent })
	stroke(color, 2, 0.4).Parent = card
	-- The picture (4:3), or a colored stand-in until it's uploaded.
	local frame = new("Frame", { Size = UDim2.fromOffset(276, 207), Position = UDim2.fromOffset(12, 12), BackgroundColor = color, BackgroundTransparency = 0.6, ZIndex = 32, Parent = card }, { corner(12) })
	local img = Shared.asset(info.image)
	if img ~= "" then
		new("ImageLabel", { Image = img, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = "Crop", ZIndex = 33, Parent = frame }, { corner(12) })
	else
		label({ Text = info.name, Size = UDim2.fromScale(1, 1), TextSize = 40, Font = "Black", TextColor = color, ZIndex = 33, Parent = frame })
	end
	local tag = panel({ Size = UDim2.fromOffset(110, 26), Position = UDim2.fromOffset(20, 20), BackgroundColor = color, BackgroundTransparency = 0, ZIndex = 34, Radius = 13, Parent = card })
	label({ Text = Strings.get(kind == "killer" and "tag_killer" or "tag_survivor"), Size = UDim2.fromScale(1, 1), TextSize = 13, Font = "Black", TextColor = INK, ZIndex = 35, Parent = tag })
	label({ Text = info.name, Size = UDim2.fromOffset(200, 32), Position = UDim2.fromOffset(14, 222), TextSize = 22, Font = "Black", TextXAlignment = "Left", ZIndex = 32, Parent = card })
	label({ Text = Strings.get("equipped"), Size = UDim2.fromOffset(90, 28), Position = UDim2.fromOffset(196, 224), TextSize = 13, TextColor = color, TextXAlignment = "Right", ZIndex = 32, Parent = card })
	label({ Text = Strings.get(info.desc), Size = UDim2.fromOffset(272, 36), Position = UDim2.fromOffset(14, 252), TextSize = 13, TextColor = MUTED, Font = "Regular", TextXAlignment = "Left", TextYAlignment = "Top", ZIndex = 32, Parent = card })
	local lines = {}
	for _, a in info.abilities do
		table.insert(lines, Strings.get(a))
	end
	label({ Text = table.concat(lines, "\n"), Size = UDim2.fromOffset(272, 48), Position = UDim2.fromOffset(14, 288), TextSize = 12, TextColor = TEXT, Font = "Bold", TextXAlignment = "Left", TextYAlignment = "Top", ZIndex = 32, Parent = card })
end

characterCard(inv, Shared.CHARACTERS.killers[1], "killer", 22)
characterCard(inv, Shared.CHARACTERS.survivors[1], "survivor", 338)

charsBtn.Activated:Connect(function()
	inv.Visible = not inv.Visible
end)

-- ------------------------------------------------------------------------------------
-- Spectating (when you're not in the round)
-- ------------------------------------------------------------------------------------

local watching = nil
local function stopWatching()
	watching = nil
	cam.CameraType = "Custom"
	cam.CameraSubject = nil
	watchBtn.Text = Strings.get("btn_watch")
end

local function watchNext()
	local list = {}
	for _, p in Players:GetPlayers() do
		local r = p:FindFirstChild("Role")
		if p ~= me and r and (r.Value == "killer" or r.Value == "survivor") and p.Character then
			table.insert(list, p)
		end
	end
	if #list == 0 then
		stopWatching()
		return
	end
	local idx = 1
	for i, p in list do
		if p == watching then
			idx = i % #list + 1
		end
	end
	watching = list[idx]
	cam.CameraType = "Follow"
	cam.CameraSubject = watching.Character
	cam.CameraOffset = Vector3.new(0, 7, 14)
	cam.Smoothing = 0.15
	watchBtn.Text = Strings.get("btn_watching", watching.DisplayName)
end

watchBtn.Activated:Connect(watchNext)
local stopBtn = button(Strings.get("btn_stop_watch"), PANEL, { Size = UDim2.fromOffset(190, 40), LayoutOrder = 4, TextColor = TEXT, Visible = false, Parent = side })
stopBtn.Activated:Connect(stopWatching)

-- ------------------------------------------------------------------------------------
-- Generators: the repair button and the puzzles
-- ------------------------------------------------------------------------------------

local function genProgress(gen)
	local n = 0
	for i = 1, Shared.GEN_STEPS do
		local b = gen:FindFirstChild("Bulb" .. i)
		if b and b.Color.G > 0.8 and b.Color.R < 0.6 then
			n += 1
		end
	end
	return n
end

local function myRoot()
	return me.Character and me.Character:FindFirstChild("HumanoidRootPart")
end

local function nearestGen()
	local map = workspace:FindFirstChild(State.Map.Value)
	local root = myRoot()
	if not map or not root or not map:FindFirstChild("Generators") then
		return nil
	end
	local best, bestD = nil, Shared.REPAIR_RANGE
	for _, gen in map.Generators:GetChildren() do
		local base = gen:FindFirstChild("Base")
		if base then
			local d = (base.Position - root.Position).Magnitude
			if d < bestD and genProgress(gen) < Shared.GEN_STEPS then
				best, bestD = gen, d
			end
		end
	end
	return best
end

local repairBtn = button("", Color3.fromHex("#ffcf5a"), { Size = UDim2.fromOffset(260, 58), Position = UDim2.new(0.5, 0, 1, -28), AnchorPoint = Vector2.new(0.5, 1), Visible = false, ZIndex = 8, Parent = gui })

local puzzle = panel({ Size = UDim2.fromOffset(440, 330), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor = INK, BackgroundTransparency = 0.05, Visible = false, ZIndex = 40, Radius = 22 })
puzzle.Parent = gui
local pzTitle = label({ Size = UDim2.new(1, -70, 0, 34), Position = UDim2.fromOffset(20, 12), TextSize = 22, Font = "Black", TextXAlignment = "Left", ZIndex = 41, Parent = puzzle })
local pzHint = label({ Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, 44), TextSize = 14, TextColor = MUTED, Font = "Regular", TextXAlignment = "Left", ZIndex = 41, Parent = puzzle })
local pzBarBack = new("Frame", { Size = UDim2.new(1, -40, 0, 8), Position = UDim2.fromOffset(20, 70), BackgroundColor = PANEL, ZIndex = 41, Parent = puzzle }, { corner(4) })
local pzBar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor = GOLD, ZIndex = 42, Parent = pzBarBack }, { corner(4) })
local pzBody = new("Frame", { Size = UDim2.new(1, -40, 1, -100), Position = UDim2.fromOffset(20, 88), BackgroundTransparency = 1, ZIndex = 41, Parent = puzzle })
local pzClose = button("X", PANEL, { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -54, 0, 12), TextColor = TEXT, ZIndex = 42, Parent = puzzle })

local current = nil -- { gen, kind, started, deadline, done }

local function closePuzzle()
	current = nil
	puzzle.Visible = false
	for _, c in pzBody:GetChildren() do
		c:Destroy()
	end
end
pzClose.Activated:Connect(closePuzzle)

local function finish(ok)
	if not current or current.done then
		return
	end
	current.done = true
	local gen = current.gen
	if ok then
		local wait = 2.1 - (time() - current.started)
		pzHint.Text = Strings.get("pz_ok")
		pzHint.TextColor = MINT
		task.delay(math.max(0, wait), function()
			Remotes.GenSolve:FireServer(gen)
		end)
		task.delay(math.max(0.6, wait + 0.1), closePuzzle)
	else
		pzHint.Text = Strings.get("pz_fail")
		pzHint.TextColor = RED
		Remotes.GenFail:FireServer(gen)
		cam:Shake(2, 0.3)
		task.delay(1.1, closePuzzle)
	end
end

local WIRE_COLORS = { "#ff5a6e", "#4cc9f0", "#ffd166", "#7ee0c3" }

local function shuffled(t)
	local c = table.clone(t)
	for i = #c, 2, -1 do
		local j = math.random(1, i)
		c[i], c[j] = c[j], c[i]
	end
	return c
end

local function buildWires()
	pzTitle.Text = Strings.get("pz_wires")
	pzHint.Text = Strings.get("pz_wires_hint")
	local left = shuffled(WIRE_COLORS)
	local right = shuffled(WIRE_COLORS)
	local picked = nil
	local done = 0
	local leftButtons = {}
	for i, hex in left do
		local b = button("", Color3.fromHex(hex), { Size = UDim2.fromOffset(120, 42), Position = UDim2.fromOffset(10, (i - 1) * 52), ZIndex = 43, Parent = pzBody })
		local s = stroke(TEXT, 3, 1)
		s.Parent = b
		leftButtons[i] = { b = b, hex = hex, s = s }
		b.Activated:Connect(function()
			if current and not current.done and b.Text == "" then
				for _, lb in leftButtons do
					lb.s.Transparency = 1
				end
				s.Transparency = 0
				picked = leftButtons[i]
			end
		end)
	end
	for i, hex in right do
		local b = button("", Color3.fromHex(hex), { Size = UDim2.fromOffset(120, 42), Position = UDim2.new(1, -130, 0, (i - 1) * 52), ZIndex = 43, Parent = pzBody })
		b.Activated:Connect(function()
			if not current or current.done or not picked or b.Text ~= "" then
				return
			end
			if picked.hex == hex then
				picked.b.Text = "OK"
				b.Text = "OK"
				picked.s.Transparency = 1
				picked.b.BackgroundTransparency = 0.5
				b.BackgroundTransparency = 0.5
				picked = nil
				done += 1
				sound("SfxTick", 0.4)
				if done == #WIRE_COLORS then
					finish(true)
				end
			else
				finish(false)
			end
		end)
	end
	label({ Text = "- - - - - - - -", Size = UDim2.new(1, -280, 1, 0), Position = UDim2.fromOffset(140, 0), TextColor = MUTED, TextSize = 20, ZIndex = 42, Parent = pzBody })
end

local function buildOrder()
	pzTitle.Text = Strings.get("pz_order")
	pzHint.Text = Strings.get("pz_order_hint")
	local nums = shuffled({ 1, 2, 3, 4, 5, 6, 7, 8, 9 })
	local want = 1
	local pressed = {}
	for i, n in nums do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local b = button(tostring(n), PANEL, { Size = UDim2.fromOffset(110, 62), Position = UDim2.new(0.5, (col - 1) * 124 - 55, 0, row * 72), TextColor = TEXT, TextSize = 26, ZIndex = 43, Parent = pzBody })
		b.Activated:Connect(function()
			if not current or current.done or pressed[n] then
				return
			end
			if n == want then
				pressed[n] = true
				b.BackgroundColor = MINT
				b.TextColor = INK
				want += 1
				if want > 9 then
					finish(true)
				end
			else
				b.BackgroundColor = RED
				finish(false)
			end
		end)
	end
end

local function openPuzzle(gen)
	if current then
		return
	end
	Remotes.GenStart:FireServer(gen)
	local kind = math.random() < 0.5 and "wires" or "order"
	current = { gen = gen, kind = kind, started = time(), limit = kind == "wires" and 12 or 14, done = false }
	pzHint.TextColor = MUTED
	pzBar.Size = UDim2.fromScale(1, 1)
	if kind == "wires" then
		buildWires()
	else
		buildOrder()
	end
	puzzle.Visible = true
end

repairBtn.Activated:Connect(function()
	local gen = nearestGen()
	if gen and role() == "survivor" and inRound() then
		openPuzzle(gen)
	end
end)

-- ------------------------------------------------------------------------------------
-- The killer's buttons (phones) and keys (computers)
-- ------------------------------------------------------------------------------------

local cool = { punch = 0, spike = 0 }
local killerBar = new("Frame", { Size = UDim2.fromOffset(100, 220), Position = UDim2.new(1, -24, 0.5, -40), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1, Visible = false, ZIndex = 8, Parent = gui })

local function abilityButton(name, key, y, color)
	local b = button("", color, { Size = UDim2.fromOffset(96, 96), Position = UDim2.fromOffset(2, y), ZIndex = 9, Radius = 48, Parent = killerBar })
	stroke(TEXT, 3, 0.6).Parent = b
	label({ Text = Strings.get(name), Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 26), TextSize = 15, Font = "Black", TextColor = INK, ZIndex = 11, Parent = b })
	label({ Text = touch and "" or key, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 52), TextSize = 13, TextColor = INK, ZIndex = 11, Parent = b })
	local shade = new("Frame", { Size = UDim2.fromScale(1, 0), BackgroundColor = INK, BackgroundTransparency = 0.35, ZIndex = 10, Parent = b }, { corner(48) })
	return b, shade
end

local punchBtn, punchShade = abilityButton("ab_btn_punch", "LMB / F", 0, RED)
local spikeBtn, spikeShade = abilityButton("ab_btn_spike", "E", 112, Color3.fromHex("#ff8a3d"))

local function aim()
	local look = cam.LookVector
	return Vector3.new(look.X, look.Y, look.Z)
end

local function killerMove(move)
	if role() ~= "killer" or not inRound() or State.Release.Value > 0 then
		return
	end
	local now = time()
	if now < cool[move] then
		return
	end
	local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	if move == "punch" then
		cool.punch = now + Shared.PUNCH.cooldown
		if hum then
			hum:PlayAnimation("punch")
		end
		Remotes.Action:FireServer("punch", aim())
	else
		cool.spike = now + Shared.SPIKE.cooldown
		if hum then
			hum:PlayAnimation("throw")
		end
		task.delay(0.18, function()
			Remotes.Action:FireServer("spike", aim())
		end)
	end
end

punchBtn.Activated:Connect(function()
	killerMove("punch")
end)
spikeBtn.Activated:Connect(function()
	killerMove("spike")
end)

UIS.InputBegan:Connect(function(input, onUi)
	if onUi then
		return
	end
	local k = input.KeyCode
	if k == "F" or (input.UserInputType == "MouseButton1" and role() == "killer" and not touch) then
		killerMove("punch")
	elseif k == "E" then
		if role() == "killer" then
			killerMove("spike")
		elseif repairBtn.Visible and not current then
			local gen = nearestGen()
			if gen then
				openPuzzle(gen)
			end
		end
	elseif k == "Q" then
		killerMove("spike")
	end
end)

-- Where a survivor slipped up (only the killer sees this).
local function markNoise(pos)
	local t = Instance.new("Text3D")
	t.Text = "!"
	t.TextColor = RED
	t.TextSize = 140
	t.Billboard = true
	t.Position = pos + Vector3.new(0, 6, 0)
	t.Parent = workspace
	task.delay(5, function()
		t:Destroy()
	end)
end

-- ------------------------------------------------------------------------------------
-- Messages from the server
-- ------------------------------------------------------------------------------------

Remotes.Notify.OnClientEvent:Connect(function(key, arg)
	if key == "n_noise" then
		toast(Strings.get("n_noise"), GOLD)
		if typeof(arg) == "Vector3" then
			markNoise(arg)
		end
	elseif key == "n_caught" then
		toast(Strings.get("n_caught", arg), RED)
	elseif key == "n_gen_done" then
		toast(Strings.get("n_gen_done", arg), MINT)
	elseif key == "n_released" then
		toast(Strings.get(role() == "killer" and "n_released_you" or "n_released"), RED)
	end
end)

Remotes.Sfx.OnClientEvent:Connect(function(name)
	sound(name, 1)
end)

Remotes.Result.OnClientEvent:Connect(function(winner, won, coins, kills)
	closePuzzle()
	local title = Strings.get(winner == "killer" and "res_killer" or "res_survivors")
	local sub = Strings.get(won and "res_you_won" or "res_you_lost") .. "   " .. Strings.get("res_coins", coins)
	showBanner(title, sub, Strings.get("res_kills", kills), winner == "killer" and RED or MINT, Shared.RESULTS_TIME - 0.5)
end)

-- ------------------------------------------------------------------------------------
-- Role changes: banners and what's on screen
-- ------------------------------------------------------------------------------------

local function onRole()
	local r = role()
	if r == "killer" then
		stopWatching()
		inv.Visible = false
		local c = Shared.CHARACTERS.killers[1]
		showBanner(Strings.get("role_killer"), Strings.get("role_killer_goal", c.name), Strings.get(touch and "role_killer_touch" or "role_killer_keys"), RED, 7)
	elseif r == "survivor" then
		stopWatching()
		inv.Visible = false
		local c = Shared.CHARACTERS.survivors[1]
		showBanner(Strings.get("role_survivor"), Strings.get("role_survivor_goal", c.name), Strings.get(touch and "role_survivor_touch" or "role_survivor_keys"), MINT, 7)
	elseif r == "dead" then
		closePuzzle()
		showBanner(Strings.get("caught_title"), Strings.get("caught_sub"), "", RED, 5)
	end
end

local function hookPlayer()
	local r = me:WaitForChild("Role", 10)
	if r then
		r.Changed:Connect(onRole)
	end
	local c = me:WaitForChild("Coins", 10)
	if c then
		c.Changed:Connect(refreshCoins)
	end
	refreshCoins()
end
task.spawn(hookPlayer)

-- ------------------------------------------------------------------------------------
-- Every frame-ish: what to show
-- ------------------------------------------------------------------------------------

while true do
	task.wait(0.1)
	local r = role()
	local playing = inRound()
	local phase = State.Phase.Value
	side.Visible = not playing
	watchBtn.Visible = phase == "Round" and not playing
	stopBtn.Visible = watching ~= nil
	if watching and (phase ~= "Round" or not watching.Parent) then
		stopWatching()
	end
	killerBar.Visible = playing and r == "killer"
	if killerBar.Visible then
		local now = time()
		punchShade.Size = UDim2.fromScale(1, math.clamp((cool.punch - now) / Shared.PUNCH.cooldown, 0, 1))
		spikeShade.Size = UDim2.fromScale(1, math.clamp((cool.spike - now) / Shared.SPIKE.cooldown, 0, 1))
		local frozen = State.Release.Value > 0
		punchBtn.BackgroundTransparency = frozen and 0.6 or 0
		spikeBtn.BackgroundTransparency = frozen and 0.6 or 0
	end
	-- Repair button and the open puzzle.
	local gen = (playing and r == "survivor" and not current) and nearestGen() or nil
	repairBtn.Visible = gen ~= nil
	if gen then
		repairBtn.Text = Strings.get(touch and "btn_repair_touch" or "btn_repair", genProgress(gen), Shared.GEN_STEPS)
	end
	if current then
		local left = current.limit - (time() - current.started)
		pzBar.Size = UDim2.fromScale(math.clamp(left / current.limit, 0, 1), 1)
		pzBar.BackgroundColor = left < 4 and RED or GOLD
		local root = myRoot()
		local base = current.gen:FindFirstChild("Base")
		local away = not root or not base or (root.Position - base.Position).Magnitude > Shared.REPAIR_RANGE + 3
		if not current.done and left <= 0 then
			finish(false)
		elseif away or not playing then
			closePuzzle()
		end
	end
	refreshStatus()
end
