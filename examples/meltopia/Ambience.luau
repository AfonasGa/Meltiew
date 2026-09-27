-- StarterPlayerScripts.Ambience: light and music for this player only.
-- Lobby: a warm evening and a cozy tune. In a round: night, fog, and music that
-- turns from quiet dread into a full chase as the killer comes close.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS = game.ReplicatedStorage
local Shared = require(RS.Shared)
local State = RS.State
local Lighting = game.Lighting

local me = Players.LocalPlayer

-- ------------------------------------------------------------------------------------
-- Light
-- ------------------------------------------------------------------------------------

local LOBBY = { ClockTime = 19.2, Brightness = 0.75, Ambient = "#5a4a6e", SkyTop = "#2a2f6b", SkyHorizon = "#f29a7a", FogEnabled = true, FogColor = "#3b2f4f", FogEnd = 260 }

local sky = Lighting:FindFirstChildOfClass("Sky")
local mode = ""

local function setLight(t)
	for k, v in t do
		if type(v) == "string" then
			Lighting[k] = Color3.fromHex(v)
		else
			Lighting[k] = v
		end
	end
end

local function applyMode(m)
	if m == mode then
		return
	end
	mode = m
	if m == "lobby" then
		setLight(LOBBY)
		if sky then
			sky.Preset = "Sunset"
			sky.StarsVisible = true
			sky.CloudsVisible = true
		end
	else
		local map = Shared.MAPS[m] or Shared.MAPS.Camp
		setLight({ ClockTime = 0.5, Brightness = map.brightness, Ambient = map.ambient, SkyTop = map.sky, SkyHorizon = map.horizon,
			FogEnabled = true, FogColor = map.fog, FogEnd = map.fogEnd })
		if sky then
			sky.Preset = "Night"
			sky.StarsVisible = true
			sky.CloudsVisible = false
		end
	end
end

local function role()
	local r = me:FindFirstChild("Role")
	return r and r.Value or "lobby"
end

local function playing()
	local r = role()
	return (State.Phase.Value == "Round" or State.Phase.Value == "End") and (r == "killer" or r == "survivor")
end

-- ------------------------------------------------------------------------------------
-- Music: three looping tracks, blended by volume
-- ------------------------------------------------------------------------------------

local function track(name)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = Shared.asset(name)
	s.Looped = true
	s.Volume = 0
	s.Parent = script
	return s
end

local music = { lobby = track("MusicLobby"), calm = track("MusicCalm"), chase = track("MusicChase") }
local level = { lobby = 0, calm = 0, chase = 0 }
local started = {}

local function want(name, target, dt, speed)
	local s = music[name]
	if s.SoundId == "" then
		return
	end
	local v = level[name]
	v += math.clamp(target - v, -speed * dt, speed * dt)
	level[name] = v
	if v > 0.01 and not started[name] then
		started[name] = true
		s:Play()
	elseif v <= 0.01 and started[name] then
		started[name] = false
		s:Stop()
	end
	s.Volume = v
end

-- How close danger is, 0 (far) to 1 (right here). The server works it out: this app
-- doesn't know where the other players really are.
local serverDanger = 0
RS.Remotes.Danger.OnClientEvent:Connect(function(d)
	serverDanger = tonumber(d) or 0
end)

local function danger()
	return serverDanger
end

-- ------------------------------------------------------------------------------------
-- Flickering lights (campfires, broken lamps): each player's own copy flickers.
-- ------------------------------------------------------------------------------------

local flickers = {}
local function scanFlickers()
	flickers = {}
	local map = workspace:FindFirstChild(State.Map.Value)
	for _, root in { map, workspace:FindFirstChild("Lobby") } do
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("PointLight") and d.Name == "Flicker" then
					table.insert(flickers, { light = d, base = d.Brightness })
				end
			end
		end
	end
end
State.Map.Changed:Connect(function()
	task.wait(1)
	scanFlickers()
end)
scanFlickers()

-- ------------------------------------------------------------------------------------

local tension = 0
local clock = 0
while true do
	local dt = task.wait(0.1)
	dt = typeof(dt) == "number" and dt or 0.1
	clock += dt
	local inGame = playing()
	applyMode(inGame and State.Map.Value ~= "" and State.Map.Value or "lobby")
	if inGame and State.Phase.Value == "Round" then
		tension += (danger() - tension) * math.min(1, dt * 2.5)
		want("lobby", 0, dt, 0.5)
		want("calm", 0.55 * (1 - tension), dt, 0.6)
		want("chase", 0.95 * math.clamp(tension * 1.4, 0, 1), dt, 1.6)
	elseif State.Phase.Value == "End" and inGame then
		want("calm", 0, dt, 0.3)
		want("chase", 0, dt, 0.4)
	else
		tension = 0
		want("calm", 0, dt, 0.5)
		want("chase", 0, dt, 0.8)
		want("lobby", 0.5, dt, 0.25)
	end
	for _, f in flickers do
		if f.light.Parent then
			f.light.Brightness = f.base * (0.75 + 0.25 * math.noise(clock * 3, f.base * 7) + 0.1 * math.random())
		end
	end
end
