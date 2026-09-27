-- ReplicatedStorage.Shared: the rules and numbers both sides agree on.
local Shared = {}

Shared.MIN_PLAYERS = 2
Shared.COUNTDOWN = 20 -- seconds in the lobby once enough players are here
Shared.GEN_STEPS = 3 -- puzzles to finish one generator
Shared.KILLER_DELAY = 8 -- survivors' head start

-- The round scales with the number of survivors: one or two of them only have to
-- last a short night, and their generators take most of it off; a full server gets
-- a long night where the generators matter less, so the killer has time to find them.
function Shared.roundTime(survivors)
	return math.clamp(80 + 25 * survivors, 105, 300)
end

function Shared.genCount(survivors)
	return math.clamp(survivors + 1, 2, 8)
end

-- What all generators together take off the clock: 58% with one survivor, 26% with nine.
function Shared.genBonus(roundTime, gens, survivors)
	local share = math.clamp(0.62 - 0.04 * survivors, 0.25, 0.58)
	return math.floor(roundTime * share / math.max(gens, 1))
end

-- A survivor the killer hits gets a moment of speed to run.
Shared.HIT_BOOST = { speed = 1.35, time = 2.5 }

-- The killer's last resort: once, in the final seconds, see every survivor through walls.
Shared.REVEAL = { at = 25, duration = 10 }
Shared.RESULTS_TIME = 8
Shared.REPAIR_RANGE = 8 -- how close to a generator you have to stand

-- Movement: the killer is quicker on a sprint and runs much longer.
Shared.LOBBY_STATS = { WalkSpeed = 5, SprintSpeed = 7, MaxStamina = 100, StaminaDrain = 20, StaminaRegen = 15, AutoHeal = true, MaxHealth = 100 }
Shared.SURVIVOR_STATS = { WalkSpeed = 5, SprintSpeed = 7.4, MaxStamina = 100, StaminaDrain = 22, StaminaRegen = 14, AutoHeal = false, MaxHealth = 100 }
Shared.KILLER_STATS = { WalkSpeed = 5.4, SprintSpeed = 8.4, MaxStamina = 220, StaminaDrain = 18, StaminaRegen = 24, AutoHeal = true, MaxHealth = 100000 }

-- The killer's moves.
-- `facing`: how straight ahead the victim must be (1 = dead ahead, 0.55 = about 57° either side).
Shared.PUNCH = { damage = 25, range = 4.5, facing = 0.55, cooldown = 1.1 }
-- Chase music: danger rises from 0 at this distance to full at `near` (the server works it out).
Shared.DANGER = { far = 42, near = 16 }
Shared.SPIKE = { damage = 20, speed = 55, range = 95, cooldown = 6 }
-- Alt's turret: heals survivors near it; the killer breaks it with a few punches.
Shared.TURRET = { heal = 4, radius = 8, life = 40, hits = 3, cooldown = 45 }
-- shadowless's flight: up into the air, hang there, then swoop to where you click.
Shared.FLY = { rise = 14, riseTime = 1.1, hoverMax = 6, speed = 42, range = 95, cooldown = 30 }

-- Coins.
Shared.REWARD = { survive = 30, escapeDead = 8, genStep = 3, killerWin = 40, perKill = 10 }

-- Maps: how the night looks on each (the lobby has its own warm evening).
Shared.MAPS = {
	Camp = { title = "map_camp", fog = "#0b1119", fogEnd = 82, ambient = "#3a415e", sky = "#070a14", horizon = "#18203a", brightness = 0.4 },
	Factory = { title = "map_factory", fog = "#0d100f", fogEnd = 95, ambient = "#3a403d", sky = "#060807", horizon = "#1a221e", brightness = 0.36 },
}

-- The characters. `image` is the name of a StringValue in ReplicatedStorage.Assets
-- holding its picture's asset://id (4:3); `price` is in coins (0: everyone has it).
Shared.CHARACTERS = {
	killers = {
		{ id = "nrz", name = "nrz", image = "RenderKiller", color = "#ff4d6d", desc = "char_nrz_desc", price = 0,
			abilities = { "ab_sprint", "ab_punch", "ab_spike", "ab_reveal" } },
		-- The id stays "shadowless" (players' saved purchases use it); the name is what they see.
		{ id = "shadowless", name = "Shdls", image = "RenderShadowless", color = "#ff2a48", desc = "char_shadowless_desc", price = 1200,
			abilities = { "ab_sprint", "ab_punch", "ab_fly", "ab_reveal" } },
	},
	survivors = {
		{ id = "melly", name = "Melly", image = "RenderSurvivor", color = "#7ee0c3", desc = "char_melly_desc", price = 0,
			abilities = { "ab_repair", "ab_stamina" } },
		{ id = "alt", name = "Alt", image = "RenderAlt", color = "#4cc9f0", desc = "char_alt_desc", price = 800,
			abilities = { "ab_repair", "ab_turret", "ab_short_breath" }, stats = { MaxStamina = 70 } },
	},
}

function Shared.killer(id)
	for _, c in Shared.CHARACTERS.killers do
		if c.id == id then
			return c
		end
	end
	return Shared.CHARACTERS.killers[1]
end

function Shared.survivor(id)
	for _, c in Shared.CHARACTERS.survivors do
		if c.id == id then
			return c
		end
	end
	return Shared.CHARACTERS.survivors[1]
end

-- A survivor's movement: the shared numbers with the character's own changes on top.
function Shared.survivorStats(id)
	local out = table.clone(Shared.SURVIVOR_STATS)
	for k, v in Shared.survivor(id).stats or {} do
		out[k] = v
	end
	return out
end

-- The asset://id stored in ReplicatedStorage.Assets[name], or "" if it isn't set.
function Shared.asset(name)
	local folder = game.ReplicatedStorage:FindFirstChild("Assets")
	local v = folder and folder:FindFirstChild(name)
	return v and v.Value or ""
end

-- Built-in sounds to use until the place's own are uploaded.
local FALLBACK = {
	SfxGenDone = "win", SfxGenFail = "boing", SfxPunch = "hurt", SfxSpikeThrow = "whoosh", SfxSpikeHit = "hurt",
	SfxRoundStart = "whoosh", SfxSurvivorsWin = "win", SfxKillerWin = "hurt", SfxTick = "click",
}

-- A sound to play: the uploaded one, or a built-in stand-in ("" for music).
function Shared.sound(name)
	local id = Shared.asset(name)
	if id ~= "" then
		return id
	end
	return FALLBACK[name] or ""
end

-- Seconds -> "2:05".
function Shared.clock(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

return Shared
