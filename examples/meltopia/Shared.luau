-- ReplicatedStorage.Shared: the rules and numbers both sides agree on.
local Shared = {}

Shared.MIN_PLAYERS = 2
Shared.COUNTDOWN = 20 -- seconds in the lobby once enough players are here
Shared.ROUND_TIME = 180 -- seconds survivors must last
Shared.GEN_STEPS = 3 -- puzzles to finish one generator
Shared.GEN_BONUS = 25 -- seconds a finished generator takes off the clock
Shared.KILLER_DELAY = 8 -- survivors' head start
Shared.RESULTS_TIME = 8
Shared.REPAIR_RANGE = 8 -- how close to a generator you have to stand

-- Movement: the killer is quicker on a sprint and runs much longer.
Shared.LOBBY_STATS = { WalkSpeed = 5, SprintSpeed = 7, MaxStamina = 100, StaminaDrain = 20, StaminaRegen = 15, AutoHeal = true, MaxHealth = 100 }
Shared.SURVIVOR_STATS = { WalkSpeed = 5, SprintSpeed = 7.4, MaxStamina = 100, StaminaDrain = 22, StaminaRegen = 14, AutoHeal = false, MaxHealth = 100 }
Shared.KILLER_STATS = { WalkSpeed = 5.4, SprintSpeed = 8.4, MaxStamina = 220, StaminaDrain = 18, StaminaRegen = 24, AutoHeal = true, MaxHealth = 100000 }

-- The killer's moves.
Shared.PUNCH = { damage = 34, range = 7, cooldown = 1.1 }
Shared.SPIKE = { damage = 26, speed = 55, range = 95, cooldown = 6 }

-- Coins.
Shared.REWARD = { survive = 30, escapeDead = 8, genStep = 3, killerWin = 40, perKill = 10 }

-- Maps: how the night looks on each (the lobby has its own warm evening).
Shared.MAPS = {
	Camp = { title = "map_camp", fog = "#0b1119", fogEnd = 82, ambient = "#3a415e", sky = "#070a14", horizon = "#18203a", brightness = 0.4 },
	Factory = { title = "map_factory", fog = "#0d100f", fogEnd = 95, ambient = "#3a403d", sky = "#060807", horizon = "#1a221e", brightness = 0.36 },
}

-- The characters, one of each for now. `image` is the name of a StringValue in
-- ReplicatedStorage.Assets holding its picture's asset://id (4:3).
Shared.CHARACTERS = {
	killers = {
		{ id = "nrz", name = "nrz", image = "RenderKiller", color = "#ff4d6d", desc = "char_nrz_desc",
			abilities = { "ab_sprint", "ab_punch", "ab_spike" } },
	},
	survivors = {
		{ id = "melly", name = "Melly", image = "RenderSurvivor", color = "#7ee0c3", desc = "char_melly_desc",
			abilities = { "ab_repair", "ab_stamina" } },
	},
}

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
