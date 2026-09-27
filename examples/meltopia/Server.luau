-- ServerScriptService.Game: lobby, rounds, roles, generators, the killer's moves, coins.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game.ReplicatedStorage
local SS = game.ServerStorage
local Shared = require(RS.Shared)

local State = RS.State
local Remotes = RS.Remotes
local Coins = game:GetService("DataStoreService"):GetDataStore("MeltopiaCoins")
-- Per player: { owned = { [id] = true }, killer = id } (the killer they play as).
local Chars = game:GetService("DataStoreService"):GetDataStore("MeltopiaChars")

-- ------------------------------------------------------------------------------------
-- Looks: nrz (fetched live, so the killer always wears what nrz wears) and plain Melly.
-- ------------------------------------------------------------------------------------

local killerLook = SS.Looks.Killer
local survivorLook = SS.Looks.Survivor
local altLook = SS.Looks.Alt
local shadowlessLook = SS.Looks.Shadowless

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
	-- In the round you only get told where players near you are (StarterPlayer.PlayerSyncRange),
	-- so a wallhack has nothing to show; the lobby, the caught and spectators see everyone.
	player.SyncAll = role ~= "killer" and role ~= "survivor"
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

-- Characters a player owns, and the ones they picked (shown to their app as values).
local chars = {} -- player -> { owned = {}, killer = id, survivor = id }

local function showChars(player)
	local c = chars[player]
	local owned = {}
	for id in c.owned do
		table.insert(owned, id)
	end
	table.sort(owned)
	value(player, "StringValue", "Owned", "").Value = table.concat(owned, ",")
	value(player, "StringValue", "KillerChar", "nrz").Value = c.killer
	value(player, "StringValue", "SurvivorChar", "melly").Value = c.survivor
end

-- A character by id: its info and "killer" / "survivor", or nil.
local function charInfo(id)
	for _, kind in { "killers", "survivors" } do
		for _, c in Shared.CHARACTERS[kind] do
			if c.id == id then
				return c, kind == "killers" and "killer" or "survivor"
			end
		end
	end
	return nil
end

local function owns(player, id)
	local info = charInfo(id)
	return info ~= nil and (info.price == 0 or (chars[player] and chars[player].owned[id] == true))
end

Players.PlayerAdded:Connect(function(player)
	setRole(player, "lobby")
	value(player, "NumberValue", "Coins", 0)
	value(player, "NumberValue", "Kills", 0)
	chars[player] = { owned = {}, killer = "nrz", survivor = "melly" }
	showChars(player)
	task.spawn(function()
		local ok, saved = pcall(function()
			return Coins:GetAsync("u" .. player.UserId)
		end)
		if ok and type(saved) == "number" then
			player.Coins.Value = saved
		end
		local okC, c = pcall(function()
			return Chars:GetAsync("u" .. player.UserId)
		end)
		if okC and type(c) == "table" and chars[player] then
			for id, v in (type(c.owned) == "table" and c.owned or {}) do
				if v == true then
					chars[player].owned[id] = true
				end
			end
			if type(c.killer) == "string" and owns(player, c.killer) then
				chars[player].killer = c.killer
			end
			if type(c.survivor) == "string" and owns(player, c.survivor) then
				chars[player].survivor = c.survivor
			end
			showChars(player)
		end
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.1)
		local role = roleOf(player)
		if role == "killer" then
			applyStats(player, Shared.KILLER_STATS)
			if round and round.killer == player and not round.over then
				if round.char.id == "nrz" and player.Character and not player.Character:FindFirstChild("Censor") then
					SS.Censor:Clone().Parent = player.Character
				end
				player:Teleport(round.map.Spawns.Killer.Position + Vector3.new(0, 3, 0))
			end
		elseif role == "survivor" then
			applyStats(player, Shared.survivorStats(chars[player] and chars[player].survivor))
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
			local hit = round.hitAt[player]
			onSurvivorDown(player, hit ~= nil and time() - hit < 10)
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

-- ------------------------------------------------------------------------------------
-- Map vote (in the lobby, before the round)
-- ------------------------------------------------------------------------------------

local votes = {} -- player -> map name

local function countVotes()
	local counts = {}
	for p, name in votes do
		if p.Parent then
			counts[name] = (counts[name] or 0) + 1
		end
	end
	for _, v in State.Votes:GetChildren() do
		v.Value = counts[v.Name] or 0
	end
	return counts
end

Remotes.Vote.OnServerEvent:Connect(function(player, name)
	if State.Phase.Value ~= "Lobby" or type(name) ~= "string" or not SS.Maps:FindFirstChild(name) then
		return
	end
	votes[player] = votes[player] ~= name and name or nil -- pressing your map again takes the vote back
	countVotes()
end)

-- The most voted map; a tie (or no votes) is settled by chance.
local function votedMap()
	local counts = countVotes()
	local best, pool = 0, {}
	for _, m in SS.Maps:GetChildren() do
		local n = counts[m.Name] or 0
		if n > best then
			best, pool = n, { m }
		elseif n == best then
			table.insert(pool, m)
		end
	end
	return pool[math.random(1, #pool)]
end

local function runRound(players)
	local map = votedMap():Clone()
	votes = {}
	countVotes()

	-- The night scales with the number of survivors (see Shared).
	local survivorCount = #players - 1
	local roundTime = Shared.roundTime(survivorCount)
	local gens = shuffle(map.Generators:GetChildren())
	local keep = math.min(Shared.genCount(survivorCount), #gens)
	for i = #gens, keep + 1, -1 do
		gens[i]:Destroy()
		table.remove(gens, i)
	end
	local genBonus = Shared.genBonus(roundTime, #gens, survivorCount)
	-- Into the world only now, so the generators left out never reach anyone.
	map.Parent = workspace

	local killer = pickKiller(players)
	lastKiller = killer
	-- The killer plays as the character they picked (and own).
	local char = Shared.killer(chars[killer] and owns(killer, chars[killer].killer) and chars[killer].killer or "nrz")
	round = { map = map, killer = killer, char = char, alive = {}, kills = 0, gens = {}, puzzles = {}, steps = {}, over = false,
		cooldowns = { punch = 0, spike = 0, fly = 0 }, released = false, timeLeft = roundTime, genBonus = genBonus, hitAt = {},
		revealed = false, fly = nil, survivor = {}, turrets = {}, turretCool = {}, boost = {} }

	for _, gen in gens do
		round.gens[gen] = 0
		paintGen(gen, 0)
	end

	State.Map.Value = map.Name
	State.KillerId.Value = killer.UserId
	State.KillerChar.Value = char.id
	State.GensDone.Value = 0
	State.GensTotal.Value = #gens
	State.TimeLeft.Value = roundTime
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
			if char.id == "shadowless" then
				-- His own face: that grin is the point.
				p:ApplyAppearance(shadowlessLook)
			else
				p:ApplyAppearance(killerLook)
				-- No face, just a black square that always looks at you.
				if p.Character and not p.Character:FindFirstChild("Censor") then
					SS.Censor:Clone().Parent = p.Character
				end
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
			local sid = chars[p] and owns(p, chars[p].survivor) and chars[p].survivor or "melly"
			round.survivor[p] = sid
			p:ApplyAppearance(sid == "alt" and altLook or survivorLook)
			applyStats(p, Shared.survivorStats(sid))
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
			if hum then
				hum.Floating = false
			end
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
	for turret in round.turrets do
		turret:Destroy()
	end
	map:Destroy()
	round = nil
	State.Map.Value = ""
	State.KillerId.Value = 0
	State.KillerChar.Value = ""
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
	chars[player] = nil
	if votes[player] then
		votes[player] = nil
		countVotes()
	end
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
	-- A little more room than the button needs: where the server last heard you were lags behind.
	return root and base and (root.Position - base.Position).Magnitude <= Shared.REPAIR_RANGE + 5
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
	-- The app waits about 2 s before sending; a solve faster than 1 s wasn't done by hand.
	if not p or p.gen ~= gen or time() - p.at < 1 or not canRepair(player, gen) then
		return
	end
	round.puzzles[player] = nil
	round.gens[gen] += 1
	round.steps[player] = (round.steps[player] or 0) + 1
	local progress = round.gens[gen]
	paintGen(gen, progress)
	if progress >= Shared.GEN_STEPS then
		round.timeLeft = math.max(1, round.timeLeft - round.genBonus)
		State.TimeLeft.Value = round.timeLeft
		State.GensDone.Value += 1
		playAt(genBase(gen), "SfxGenDone", 1.2)
		notifyAll("n_gen_done", round.genBonus)
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

-- Someone whose app went quiet is frozen where the server last heard of them: a hit
-- on that spot isn't a hit on them (they'd come back from a lag spike already dead).
local LAG_GRACE = 1.5

local function hittable(p)
	return p:GetNetworkIdle() < LAG_GRACE
end

local function hurt(victim, amount, sound)
	local hum = humanoidOf(victim)
	if not hum or hum.Health <= 0 then
		return
	end
	round.hitAt[victim] = time()
	hum:TakeDamage(amount)
	playAt(rootOf(victim), sound, 1.3)
	Remotes.Hit:FireClient(victim, amount)
	-- A kick in the back: a moment of speed to get away.
	if hum.Health > 0 and victim ~= round.killer then
		local stats = Shared.survivorStats(round.survivor[victim])
		local token = {}
		round.boost[victim] = token
		hum.WalkSpeed = stats.WalkSpeed * Shared.HIT_BOOST.speed
		hum.SprintSpeed = stats.SprintSpeed * Shared.HIT_BOOST.speed
		task.delay(Shared.HIT_BOOST.time, function()
			if round and round.boost[victim] == token and hum.Parent then
				round.boost[victim] = nil
				hum.WalkSpeed = stats.WalkSpeed
				hum.SprintSpeed = stats.SprintSpeed
			end
		end)
	end
end

local function punch(killer, dir)
	local root = rootOf(killer)
	if not root then
		return
	end
	local best, bestD = nil, math.huge
	for p in round.alive do
		if p ~= killer and hittable(p) then
			local r = rootOf(p)
			if r then
				local to = r.Position - root.Position
				local d = to.Magnitude
				local flat = Vector3.new(to.X, 0, to.Z)
				local facing = flat.Magnitude < 0.5 and 1 or flat.Unit:Dot(dir)
				if d <= Shared.PUNCH.range and facing > Shared.PUNCH.facing and math.abs(to.Y) < 4 and d < bestD then
					best, bestD = p, d
				end
			end
		end
	end
	if best then
		hurt(best, Shared.PUNCH.damage, "SfxPunch")
		return
	end
	-- Nobody in reach: a turret in front of the killer takes the hit.
	for turret in round.turrets do
		local base = turret:FindFirstChild("Head")
		if base then
			local to = base.Position - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude <= Shared.PUNCH.range + 1 and (flat.Magnitude < 0.5 or flat.Unit:Dot(dir) > Shared.PUNCH.facing) then
				round.turrets[turret] -= 1
				playAt(base, "SfxPunch", 1.2)
				if round.turrets[turret] <= 0 then
					round.turrets[turret] = nil
					turret:Destroy()
					notifyAll("n_turret_broken")
				else
					base.Color = Color3.fromHex("#ffcf5a")
					task.delay(0.25, function()
						if base.Parent then
							base.Color = Color3.fromHex("#6bffa8")
						end
					end)
				end
				return
			end
		end
	end
end

local spikeTemplate = SS.Spike

local function throwSpike(killer, aim)
	local root = rootOf(killer)
	if not root then
		return
	end
	-- Straight and level at chest height: the camera looks down at your character,
	-- and following its tilt sent spikes into the ground.
	local dir = flatDir(aim)
	if not dir then
		return
	end
	local pos = root.Position + Vector3.new(0, 1.7, 0) + dir * 1.4
	local spike = spikeTemplate:Clone()
	spike.Name = "Spike"
	spike.Rotation = Vector3.new(0, math.deg(math.atan2(dir.X, dir.Z)), 0)
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
			if p ~= killer and hittable(p) then
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
	elseif move == "spike" and round.char.id == "nrz" and now >= round.cooldowns.spike then
		round.cooldowns.spike = now + Shared.SPIKE.cooldown - 0.2
		throwSpike(player, aim)
	end
end)

-- Once a round, in the last seconds: the killer sees where every survivor is.
Remotes.Reveal.OnServerEvent:Connect(function(player)
	if not round or round.over or player ~= round.killer or not round.released or round.revealed then
		return
	end
	if round.timeLeft > Shared.REVEAL.at then
		return
	end
	round.revealed = true
	local list = {}
	for p in round.alive do
		if p ~= player and p.Parent then
			table.insert(list, p)
		end
	end
	-- The markers need to know where everyone is: the killer is told, for as long as they last.
	player.SyncAll = true
	task.delay(Shared.REVEAL.duration, function()
		if player.Parent and roleOf(player) == "killer" then
			player.SyncAll = false
		end
	end)
	Remotes.Reveal:FireClient(player, list, Shared.REVEAL.duration)
	for _, p in list do
		Remotes.Notify:FireClient(p, "n_revealed")
	end
end)

-- ------------------------------------------------------------------------------------
-- Characters: buy with coins, pick your killer
-- ------------------------------------------------------------------------------------

local shopBusy = {}

local function saveChars(player)
	local c = chars[player]
	if not c then
		return
	end
	pcall(function()
		Chars:SetAsync("u" .. player.UserId, { owned = c.owned, killer = c.killer, survivor = c.survivor })
	end)
end

Remotes.Shop.OnServerEvent:Connect(function(player, action, id)
	local c = chars[player]
	local info, kind = nil, nil
	if type(id) == "string" then
		info, kind = charInfo(id)
	end
	if not c or not info or shopBusy[player] then
		return
	end
	if action == "buy" and info.price > 0 and not c.owned[id] then
		shopBusy[player] = true
		-- Take the coins first; if that went below zero, it wasn't affordable: give them back.
		local ok, left = pcall(function()
			return Coins:IncrementAsync("u" .. player.UserId, -info.price)
		end)
		if ok and type(left) == "number" and left >= 0 then
			c.owned[id] = true
			c[kind] = id
			player.Coins.Value = left
			saveChars(player)
			showChars(player)
			Remotes.Notify:FireClient(player, "n_bought", info.name)
		else
			if ok and type(left) == "number" then
				pcall(function()
					player.Coins.Value = Coins:IncrementAsync("u" .. player.UserId, info.price)
				end)
			end
			Remotes.Notify:FireClient(player, "n_no_coins", info.price)
		end
		shopBusy[player] = nil
	elseif action == "equip" and owns(player, id) then
		c[kind] = id
		saveChars(player)
		showChars(player)
	end
end)

-- ------------------------------------------------------------------------------------
-- shadowless: up, hang there, then swoop to where you click
-- ------------------------------------------------------------------------------------

local function land(player)
	if not round or not round.fly then
		return
	end
	round.fly = nil
	round.cooldowns.fly = time() + Shared.FLY.cooldown
	local hum = humanoidOf(player)
	if hum then
		hum.Floating = false
	end
end

Remotes.Fly.OnServerEvent:Connect(function(player, step, target)
	if not round or round.over or player ~= round.killer or not round.released or round.char.id ~= "shadowless" then
		return
	end
	local root, hum = rootOf(player), humanoidOf(player)
	if not root or not hum then
		return
	end
	local now = time()
	if step == "up" and not round.fly and now >= round.cooldowns.fly then
		local token = {}
		round.fly = { phase = "up", at = now, token = token }
		hum.Floating = true
		player:Glide(root.Position + Vector3.new(0, Shared.FLY.rise, 0), Shared.FLY.riseTime)
		-- Nowhere picked in time: drop down.
		task.delay(Shared.FLY.riseTime + Shared.FLY.hoverMax, function()
			if round and round.fly and round.fly.token == token and round.fly.phase == "up" then
				land(player)
			end
		end)
	elseif step == "to" and round.fly and round.fly.phase == "up" and now - round.fly.at >= 0.4 and typeof(target) == "Vector3" then
		local from = root.Position
		local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
		if flat.Magnitude > Shared.FLY.range then
			flat = flat.Unit * Shared.FLY.range
		end
		local to = Vector3.new(from.X + flat.X, math.clamp(target.Y, from.Y - 60, from.Y + 4) + 2.5, from.Z + flat.Z)
		local t = math.clamp((to - from).Magnitude / Shared.FLY.speed, 0.35, 2.5)
		round.fly.phase = "going"
		local token = round.fly.token
		player:Glide(to, t)
		task.delay(t + 0.1, function()
			if round and round.fly and round.fly.token == token then
				land(player)
			end
		end)
	end
end)

-- ------------------------------------------------------------------------------------
-- Alt's turret: put down where he stands, heals survivors around it for a while
-- ------------------------------------------------------------------------------------

local function turretPart(parent, name, size, pos, color, material, extra)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = pos
	part.Color = Color3.fromHex(color)
	part.Material = material
	part.Anchored = true
	for k, v in extra or {} do
		part[k] = v
	end
	part.Parent = parent
	return part
end

Remotes.Turret.OnServerEvent:Connect(function(player)
	if not round or round.over or not round.alive[player] or player == round.killer or round.survivor[player] ~= "alt" then
		return
	end
	local now = time()
	-- Half a second of slack: the app counts the cooldown from its own press, a ping earlier.
	if now < (round.turretCool[player] or 0) - 0.5 then
		Remotes.Turret:FireClient(player, round.turretCool[player] - now)
		return
	end
	local root = rootOf(player)
	if not root then
		Remotes.Turret:FireClient(player, 0)
		return
	end
	-- On the ground under Alt.
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { player.Character }
	params.FilterType = "Exclude"
	params.RespectCanCollide = true
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	if not hit then
		Remotes.Turret:FireClient(player, 0)
		return
	end
	round.turretCool[player] = now + Shared.TURRET.cooldown
	-- The app's cooldown follows the server's answer, not its own guess.
	Remotes.Turret:FireClient(player, Shared.TURRET.cooldown)
	local at = hit.Position
	local model = Instance.new("Model")
	model.Name = "Turret"
	turretPart(model, "Base", Vector3.new(1.8, 0.4, 1.8), at + Vector3.new(0, 0.2, 0), "#2c3a4a", "Metal")
	turretPart(model, "Post", Vector3.new(0.5, 2.2, 0.5), at + Vector3.new(0, 1.5, 0), "#3a4a5c", "Metal")
	local head = turretPart(model, "Head", Vector3.new(1.2, 0.9, 1.2), at + Vector3.new(0, 3, 0), "#6bffa8", "Neon")
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("#6bffa8")
	light.Brightness = 2
	light.Range = Shared.TURRET.radius + 2
	light.Parent = head
	turretPart(model, "Area", Vector3.new(Shared.TURRET.radius * 2, 0.06, Shared.TURRET.radius * 2), at + Vector3.new(0, 0.04, 0), "#6bffa8", "Neon",
		{ Shape = "Cylinder", CanCollide = false, CanTouch = false, Transparency = 0.8, CastShadow = false })
	model.Parent = workspace
	round.turrets[model] = Shared.TURRET.hits
	notifyAll("n_turret", player.DisplayName)
	local myRound = round
	task.spawn(function()
		local left = Shared.TURRET.life
		while left > 0 and myRound == round and not round.over and round.turrets[model] do
			task.wait(1)
			left -= 1
			for p in round.alive do
				local r, hum = rootOf(p), humanoidOf(p)
				if p ~= round.killer and r and hum and hum.Health > 0 and (r.Position - head.Position).Magnitude <= Shared.TURRET.radius + 1.5 then
					hum.Health = math.min(hum.MaxHealth, hum.Health + Shared.TURRET.heal)
				end
			end
		end
		if myRound.turrets then
			myRound.turrets[model] = nil
		end
		if model.Parent then
			model:Destroy()
		end
	end)
end)

-- ------------------------------------------------------------------------------------
-- Chase music: how close the danger is, worked out here (apps don't know where the
-- others really are) and sent to each player when it changes
-- ------------------------------------------------------------------------------------

local sentDanger = {}
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, p in Players:GetPlayers() do
			local d = 0
			local myRoot = rootOf(p)
			if round and not round.over and round.alive[p] and myRoot and round.killer then
				local best = math.huge
				for other in round.alive do
					-- Survivors fear the killer; the killer hunts the nearest survivor.
					local counts = (p ~= round.killer and other == round.killer) or (p == round.killer and other ~= p)
					local r = counts and rootOf(other)
					if r then
						best = math.min(best, (r.Position - myRoot.Position).Magnitude)
					end
				end
				if best < math.huge then
					d = math.clamp((Shared.DANGER.far - best) / (Shared.DANGER.far - Shared.DANGER.near), 0, 1)
				end
			end
			d = math.floor(d * 10 + 0.5) / 10
			if sentDanger[p] ~= d then
				sentDanger[p] = d
				Remotes.Danger:FireClient(p, d)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	sentDanger[p] = nil
end)
