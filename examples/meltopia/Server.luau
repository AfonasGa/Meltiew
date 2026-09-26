-- ServerScriptService.Game: lobby, rounds, roles, generators, the killer's moves, coins.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game.ReplicatedStorage
local SS = game.ServerStorage
local Shared = require(RS.Shared)

local State = RS.State
local Remotes = RS.Remotes
local Coins = game:GetService("DataStoreService"):GetDataStore("MeltopiaCoins")

-- ------------------------------------------------------------------------------------
-- Looks: nrz (fetched live, so the killer always wears what nrz wears) and plain Melly.
-- ------------------------------------------------------------------------------------

local killerLook = SS.Looks.Killer
local survivorLook = SS.Looks.Survivor

local function dressRig(rig, look)
	for _, key in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor", "Face", "Accessories" } do
		rig[key] = look[key]
	end
end

task.spawn(function()
	local ok, look = pcall(function()
		return Players:GetUserAppearanceAsync("nrz")
	end)
	if ok and look then
		look.Parent = SS.Looks
		killerLook = look
	else
		warn("nrz's look didn't load, using the saved one: " .. tostring(look))
	end
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby and lobby:FindFirstChild("KillerRig") then
		dressRig(lobby.KillerRig, killerLook)
	end
end)

-- ------------------------------------------------------------------------------------
-- Players: role, coins, stats
-- ------------------------------------------------------------------------------------

local round = nil -- the running round, or nil
local lastKiller = nil

local function value(parent, class, name, initial)
	local v = parent:FindFirstChild(name)
	if not v then
		v = Instance.new(class)
		v.Name = name
		v.Value = initial
		v.Parent = parent
	end
	return v
end

local function humanoidOf(player)
	local ch = player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function rootOf(player)
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function applyStats(player, stats)
	local hum = humanoidOf(player)
	if not hum then
		return
	end
	for k, v in stats do
		hum[k] = v
	end
	hum.Health = stats.MaxHealth
	hum.CanJump = true
end

local function roleOf(player)
	local r = player:FindFirstChild("Role")
	return r and r.Value or "lobby"
end

local function setRole(player, role)
	value(player, "StringValue", "Role", "lobby").Value = role
end

local function addCoins(player, amount)
	if amount <= 0 then
		return
	end
	local v = value(player, "NumberValue", "Coins", 0)
	v.Value += amount
	task.spawn(function()
		pcall(function()
			v.Value = Coins:IncrementAsync("u" .. player.UserId, amount)
		end)
	end)
end

local function notifyAll(key, ...)
	Remotes.Notify:FireAllClients(key, ...)
end

local function lobbySpawn()
	local spawn = workspace.Lobby.Spawn
	local a = math.random() * math.pi * 2
	return spawn.Position + Vector3.new(math.cos(a) * 5, 3, math.sin(a) * 5)
end

Players.PlayerAdded:Connect(function(player)
	setRole(player, "lobby")
	value(player, "NumberValue", "Coins", 0)
	value(player, "NumberValue", "Kills", 0)
	task.spawn(function()
		local ok, saved = pcall(function()
			return Coins:GetAsync("u" .. player.UserId)
		end)
		if ok and type(saved) == "number" then
			player.Coins.Value = saved
		end
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.1)
		local role = roleOf(player)
		if role == "killer" then
			applyStats(player, Shared.KILLER_STATS)
		elseif role == "survivor" then
			applyStats(player, Shared.SURVIVOR_STATS)
		else
			-- Back in the lobby (after being caught, or between rounds): your own look.
			player:ResetAppearance()
			applyStats(player, Shared.LOBBY_STATS)
		end
	end)
end)

-- ------------------------------------------------------------------------------------
-- Generators
-- ------------------------------------------------------------------------------------

local GEN_OFF = Color3.fromHex("#3a1f24")
local GEN_ON = Color3.fromHex("#6bffa8")
local GEN_WORK = Color3.fromHex("#ffcf5a")

local function genBase(gen)
	return gen:FindFirstChild("Base")
end

local function paintGen(gen, progress)
	for i = 1, Shared.GEN_STEPS do
		local bulb = gen:FindFirstChild("Bulb" .. i)
		if bulb then
			bulb.Color = i <= progress and GEN_ON or GEN_OFF
		end
	end
	local lamp = gen:FindFirstChild("Lamp")
	if lamp then
		local light = lamp:FindFirstChildOfClass("PointLight")
		local done = progress >= Shared.GEN_STEPS
		lamp.Color = done and GEN_ON or (progress > 0 and GEN_WORK or Color3.fromHex("#ff3b4f"))
		if light then
			light.Color = lamp.Color
			light.Brightness = done and 3 or 1.2
			light.Range = done and 22 or 9
		end
	end
end

local function playAt(part, soundName, volume)
	local id = Shared.sound(soundName)
	if id == "" or not part then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.Parent = part
	s:Play()
	game:GetService("Debris"):AddItem(s, 6)
end

local function playForAll(soundName)
	Remotes.Sfx:FireAllClients(soundName)
end

-- ------------------------------------------------------------------------------------
-- Rounds
-- ------------------------------------------------------------------------------------

local function participants()
	if not round then
		return {}
	end
	local out = {}
	for p in round.alive do
		if p.Parent then
			table.insert(out, p)
		end
	end
	return out
end

local function survivorsAlive()
	if not round then
		return 0
	end
	local n = 0
	for p in round.alive do
		if p ~= round.killer and p.Parent then
			n += 1
		end
	end
	return n
end

local function endRound(winner)
	if not round or round.over then
		return
	end
	round.over = true
	round.winner = winner
end

local function onSurvivorDown(player, byKiller)
	if not round or not round.alive[player] or player == round.killer then
		return
	end
	round.alive[player] = nil
	setRole(player, "dead")
	if byKiller and round.killer and round.killer.Parent then
		round.kills += 1
		round.killer.Kills.Value += 1
	end
	notifyAll("n_caught", player.DisplayName)
	State.Alive.Value = survivorsAlive()
	if survivorsAlive() == 0 then
		endRound("killer")
	end
end

local function hookHumanoid(player)
	local hum = humanoidOf(player)
	if not hum then
		return
	end
	hum.Died:Connect(function()
		if round and round.alive[player] and player ~= round.killer then
			onSurvivorDown(player, true)
		end
	end)
end

local function pickKiller(list)
	local pool = {}
	for _, p in list do
		if p ~= lastKiller or #list <= 1 then
			table.insert(pool, p)
		end
	end
	if #pool == 0 then
		pool = list
	end
	return pool[math.random(1, #pool)]
end

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local function runRound(players)
	local maps = SS.Maps:GetChildren()
	local template = maps[math.random(1, #maps)]
	local map = template:Clone()
	map.Parent = workspace

	local killer = pickKiller(players)
	lastKiller = killer
	round = { map = map, killer = killer, alive = {}, kills = 0, gens = {}, puzzles = {}, steps = {}, over = false,
		cooldowns = { punch = 0, spike = 0 }, released = false, timeLeft = Shared.ROUND_TIME }

	local gens = map.Generators:GetChildren()
	for _, gen in gens do
		round.gens[gen] = 0
		paintGen(gen, 0)
	end

	State.Map.Value = map.Name
	State.KillerId.Value = killer.UserId
	State.GensDone.Value = 0
	State.GensTotal.Value = #gens
	State.TimeLeft.Value = Shared.ROUND_TIME
	State.Release.Value = Shared.KILLER_DELAY
	State.Phase.Value = "Round"

	-- Roles, looks, places.
	local spawns = {}
	for _, s in map.Spawns:GetChildren() do
		if s.Name == "Survivor" then
			table.insert(spawns, s.Position)
		end
	end
	shuffle(spawns)
	for i, p in players do
		round.alive[p] = true
		p.Kills.Value = 0
		if p == killer then
			setRole(p, "killer")
			p:ApplyAppearance(killerLook)
			-- No face, just a black square that always looks at you.
			if p.Character and not p.Character:FindFirstChild("Censor") then
				SS.Censor:Clone().Parent = p.Character
			end
			applyStats(p, Shared.KILLER_STATS)
			local hum = humanoidOf(p)
			if hum then
				hum.WalkSpeed = 0
				hum.SprintSpeed = 0
				hum.CanJump = false
			end
			p:Teleport(map.Spawns.Killer.Position + Vector3.new(0, 3, 0))
		else
			setRole(p, "survivor")
			p:ApplyAppearance(survivorLook)
			applyStats(p, Shared.SURVIVOR_STATS)
			local at = spawns[((i - 1) % #spawns) + 1]
			p:Teleport(at + Vector3.new(math.random(-2, 2), 3, math.random(-2, 2)))
		end
		hookHumanoid(p)
	end
	State.Alive.Value = survivorsAlive()
	playForAll("SfxRoundStart")

	-- The killer waits while the survivors scatter.
	for s = Shared.KILLER_DELAY, 1, -1 do
		State.Release.Value = s
		task.wait(1)
		if round.over then
			break
		end
	end
	State.Release.Value = 0
	round.released = true
	if killer.Parent then
		applyStats(killer, Shared.KILLER_STATS)
	end
	notifyAll("n_released")

	-- The clock.
	while not round.over do
		task.wait(1)
		round.timeLeft -= 1
		State.TimeLeft.Value = math.max(0, round.timeLeft)
		if not killer.Parent then
			endRound("survivors")
		elseif survivorsAlive() == 0 then
			endRound("killer")
		elseif round.timeLeft <= 0 then
			endRound("survivors")
		end
	end

	-- Results and coins.
	State.Phase.Value = "End"
	local winner = round.winner
	for p in pairs(round.steps) do
		if p.Parent then
			addCoins(p, round.steps[p] * Shared.REWARD.genStep)
		end
	end
	for _, p in players do
		if p.Parent then
			local earned = 0
			if p == killer then
				earned = round.kills * Shared.REWARD.perKill + (winner == "killer" and Shared.REWARD.killerWin or 0)
			elseif winner == "survivors" then
				earned = round.alive[p] and Shared.REWARD.survive or Shared.REWARD.escapeDead
			end
			addCoins(p, earned)
			local won = (p == killer) == (winner == "killer")
			Remotes.Result:FireClient(p, winner, won, earned + (round.steps[p] or 0) * Shared.REWARD.genStep, round.kills)
		end
	end
	playForAll(winner == "killer" and "SfxKillerWin" or "SfxSurvivorsWin")
	task.wait(Shared.RESULTS_TIME)

	-- Everyone home.
	for _, p in players do
		if p.Parent then
			setRole(p, "lobby")
			p:ResetAppearance()
			local censor = p.Character and p.Character:FindFirstChild("Censor")
			if censor then
				censor:Destroy()
			end
			applyStats(p, Shared.LOBBY_STATS)
			local hum = humanoidOf(p)
			if hum and hum.Health > 0 then
				p:Teleport(lobbySpawn())
			end
		end
	end
	for _, s in workspace:GetChildren() do
		if s.Name == "Spike" then
			s:Destroy()
		end
	end
	map:Destroy()
	round = nil
	State.Map.Value = ""
	State.KillerId.Value = 0
	State.Phase.Value = "Lobby"
end

-- The lobby loop: wait for players, count down, play.
task.spawn(function()
	State.Phase.Value = "Lobby"
	while true do
		local ready = Players:GetPlayers()
		if #ready < Shared.MIN_PLAYERS then
			State.Countdown.Value = -1
			State.Waiting.Value = #ready
			task.wait(1)
		else
			local ok = true
			for s = Shared.COUNTDOWN, 1, -1 do
				State.Countdown.Value = s
				State.Waiting.Value = #Players:GetPlayers()
				if #Players:GetPlayers() < Shared.MIN_PLAYERS then
					ok = false
					break
				end
				task.wait(1)
			end
			State.Countdown.Value = -1
			if ok then
				local list = {}
				for _, p in Players:GetPlayers() do
					if humanoidOf(p) and humanoidOf(p).Health > 0 then
						table.insert(list, p)
					end
				end
				if #list >= Shared.MIN_PLAYERS then
					local okRun, err = pcall(runRound, list)
					if not okRun then
						warn("round failed: " .. tostring(err))
						if round and round.map then
							round.map:Destroy()
						end
						round = nil
						State.Phase.Value = "Lobby"
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if round and round.alive[player] then
		if player == round.killer then
			endRound("survivors")
		else
			onSurvivorDown(player, false)
		end
	end
end)

-- ------------------------------------------------------------------------------------
-- Generators: a survivor opens a puzzle, solves it, the generator moves on.
-- ------------------------------------------------------------------------------------

local function nearGen(player, gen)
	local root = rootOf(player)
	local base = gen and gen.Parent and genBase(gen)
	return root and base and (root.Position - base.Position).Magnitude <= Shared.REPAIR_RANGE + 2
end

local function canRepair(player, gen)
	return round and not round.over and round.alive[player] and player ~= round.killer
		and typeof(gen) == "Instance" and round.gens[gen] ~= nil and round.gens[gen] < Shared.GEN_STEPS
		and nearGen(player, gen)
end

Remotes.GenStart.OnServerEvent:Connect(function(player, gen)
	if canRepair(player, gen) then
		round.puzzles[player] = { gen = gen, at = time() }
	end
end)

Remotes.GenSolve.OnServerEvent:Connect(function(player, gen)
	local p = round and round.puzzles[player]
	if not p or p.gen ~= gen or time() - p.at < 2 or not canRepair(player, gen) then
		return
	end
	round.puzzles[player] = nil
	round.gens[gen] += 1
	round.steps[player] = (round.steps[player] or 0) + 1
	local progress = round.gens[gen]
	paintGen(gen, progress)
	if progress >= Shared.GEN_STEPS then
		round.timeLeft = math.max(1, round.timeLeft - Shared.GEN_BONUS)
		State.TimeLeft.Value = round.timeLeft
		State.GensDone.Value += 1
		playAt(genBase(gen), "SfxGenDone", 1.2)
		notifyAll("n_gen_done", Shared.GEN_BONUS)
	else
		playAt(genBase(gen), "SfxTick", 0.8)
	end
end)

-- A mistake makes a racket the killer hears, and points them to it.
Remotes.GenFail.OnServerEvent:Connect(function(player, gen)
	if not canRepair(player, gen) then
		return
	end
	local now = time()
	if round.lastNoise and now - round.lastNoise < 2 then
		return
	end
	round.lastNoise = now
	round.puzzles[player] = nil
	playAt(genBase(gen), "SfxGenFail", 1.6)
	if round.killer and round.killer.Parent then
		Remotes.Notify:FireClient(round.killer, "n_noise", genBase(gen).Position)
	end
end)

-- ------------------------------------------------------------------------------------
-- The killer's moves
-- ------------------------------------------------------------------------------------

local function flatDir(v)
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local d = Vector3.new(v.X, 0, v.Z)
	if d.Magnitude < 0.01 then
		return nil
	end
	return d.Unit
end

local function hurt(victim, amount, sound)
	local hum = humanoidOf(victim)
	if not hum or hum.Health <= 0 then
		return
	end
	hum:TakeDamage(amount)
	playAt(rootOf(victim), sound, 1.3)
	Remotes.Hit:FireClient(victim, amount)
end

local function punch(killer, dir)
	local root = rootOf(killer)
	if not root then
		return
	end
	local best, bestD = nil, math.huge
	for p in round.alive do
		if p ~= killer then
			local r = rootOf(p)
			if r then
				local to = r.Position - root.Position
				local d = to.Magnitude
				local flat = Vector3.new(to.X, 0, to.Z)
				local facing = flat.Magnitude < 0.5 and 1 or flat.Unit:Dot(dir)
				if d <= Shared.PUNCH.range and facing > 0.3 and math.abs(to.Y) < 5 and d < bestD then
					best, bestD = p, d
				end
			end
		end
	end
	if best then
		hurt(best, Shared.PUNCH.damage, "SfxPunch")
	end
end

local spikeTemplate = SS.Spike

local function throwSpike(killer, aim)
	local root = rootOf(killer)
	if not root then
		return
	end
	local dir = aim.Unit
	-- Mostly level, a little up or down with the camera.
	dir = Vector3.new(dir.X, math.clamp(dir.Y, -0.25, 0.25), dir.Z).Unit
	local pos = root.Position + Vector3.new(0, 2.7, 0) + flatDir(dir) * 1.4
	local spike = spikeTemplate:Clone()
	spike.Name = "Spike"
	local yaw = math.deg(math.atan2(dir.X, dir.Z))
	local pitch = -math.deg(math.asin(dir.Y))
	spike.Rotation = Vector3.new(pitch, yaw, 0)
	spike.Position = pos
	spike.Parent = workspace
	playAt(spike, "SfxSpikeThrow", 1.2)

	local ignore = { spike }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = ignore
	params.FilterType = "Exclude"
	params.RespectCanCollide = true

	local traveled = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not spike.Parent or not round or round.over then
			conn:Disconnect()
			if spike.Parent then
				spike:Destroy()
			end
			return
		end
		local step = Shared.SPIKE.speed * math.min(dt, 0.1)
		local from = spike.Position
		local to = from + dir * step
		-- Anyone along this stretch?
		for p in round.alive do
			if p ~= killer then
				local r = rootOf(p)
				if r then
					local c = r.Position + Vector3.new(0, 1.6, 0)
					local t = math.clamp((c - from):Dot(dir) / step, 0, 1)
					local closest = from + dir * step * t
					if (c - closest).Magnitude < 2.1 then
						conn:Disconnect()
						hurt(p, Shared.SPIKE.damage, "SfxSpikeHit")
						spike:Destroy()
						return
					end
				end
			end
		end
		local hit = workspace:Raycast(from, dir * step, params)
		if hit then
			conn:Disconnect()
			spike.Position = hit.Position - dir * 0.8
			playAt(spike, "SfxSpikeHit", 0.8)
			game:GetService("Debris"):AddItem(spike, 3)
			return
		end
		spike.Position = to
		traveled += step
		if traveled >= Shared.SPIKE.range then
			conn:Disconnect()
			spike:Destroy()
		end
	end)
end

Remotes.Action.OnServerEvent:Connect(function(player, move, aim)
	if not round or round.over or player ~= round.killer or not round.released then
		return
	end
	local dir = flatDir(aim)
	if not dir then
		return
	end
	local now = time()
	if move == "punch" and now >= round.cooldowns.punch then
		round.cooldowns.punch = now + Shared.PUNCH.cooldown - 0.1
		punch(player, dir)
	elseif move == "spike" and now >= round.cooldowns.spike then
		round.cooldowns.spike = now + Shared.SPIKE.cooldown - 0.2
		throwSpike(player, aim)
	end
end)
