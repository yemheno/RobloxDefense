-- StarterPlayerScripts/Modules/SoundManager.lua
--[[
    Client-side sound system.

    Manages three SoundGroup categories:
      • Music     — background music tracks (looped, crossfade)
      • SFX       — one-shot sound effects (attack, hit, skill, level up, etc.)
      • UI        — button clicks, panel open/close, toast notifications

    Volume is controlled per-group (0–1) and persisted in settings.
    Each group is a Roblox SoundGroup parented under SoundService.

    Public API:
      SoundManager.Init()
      SoundManager.PlaySFX(name)              — fire-and-forget one-shot
      SoundManager.PlayUI(name)               — fire-and-forget UI sound
      SoundManager.PlayMusic(name)            — crossfade to a music track
      SoundManager.StopMusic()                — fade out current music
      SoundManager.SetVolume(group, vol)      — "Music" | "SFX" | "UI", 0–1
      SoundManager.GetVolume(group)           → number 0–1
      SoundManager.SetMasterMute(bool)
      SoundManager.IsMuted() → bool

    Sound assets are defined in SOUND_LIBRARY below.
    When adding new sounds, just add an entry with a valid Roblox AssetId.
    Sounds that don't have an upload yet use placeholder "rbxassetid://0".
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SoundManager = {}

-- ── Volume defaults ────────────────────────────────────────────────────────
local DEFAULT_VOLUMES = {
    Music = 0.5,
    SFX   = 0.8,
    UI    = 0.7,
}

-- ── Sound Library ──────────────────────────────────────────────────────────
-- Each entry: { assetId, volume (optional, default 1), pitch (optional, default 1) }
-- Replace placeholder IDs (0) with real uploaded audio asset IDs.

local SOUND_LIBRARY = {
    -- ══ Music ══
    lobby_theme       = { id = "rbxassetid://0", volume = 0.6, loop = true },
    combat_theme      = { id = "rbxassetid://0", volume = 0.5, loop = true },
    boss_theme        = { id = "rbxassetid://0", volume = 0.6, loop = true },
    victory_theme     = { id = "rbxassetid://0", volume = 0.7, loop = false },
    defeat_theme      = { id = "rbxassetid://0", volume = 0.6, loop = false },

    -- ══ SFX ══
    sword_swing       = { id = "rbxassetid://0", volume = 0.8 },
    bow_shoot         = { id = "rbxassetid://0", volume = 0.7 },
    wand_cast         = { id = "rbxassetid://0", volume = 0.7 },
    hit_normal        = { id = "rbxassetid://0", volume = 0.6 },
    hit_crit          = { id = "rbxassetid://0", volume = 0.9 },
    enemy_death       = { id = "rbxassetid://0", volume = 0.5 },
    player_death      = { id = "rbxassetid://0", volume = 0.8 },
    level_up          = { id = "rbxassetid://0", volume = 1.0 },
    skill_activate    = { id = "rbxassetid://0", volume = 0.7 },
    wave_start        = { id = "rbxassetid://0", volume = 0.6 },
    wave_complete     = { id = "rbxassetid://0", volume = 0.7 },
    coin_pickup       = { id = "rbxassetid://0", volume = 0.5 },
    equip_item        = { id = "rbxassetid://0", volume = 0.6 },
    refine_success    = { id = "rbxassetid://0", volume = 0.8 },
    refine_fail       = { id = "rbxassetid://0", volume = 0.6 },
    tier_up           = { id = "rbxassetid://0", volume = 1.0 },
    achievement       = { id = "rbxassetid://0", volume = 0.9 },
    daily_login       = { id = "rbxassetid://0", volume = 0.8 },

    -- ══ UI ══
    ui_click          = { id = "rbxassetid://0", volume = 0.4 },
    ui_hover          = { id = "rbxassetid://0", volume = 0.2 },
    ui_open           = { id = "rbxassetid://0", volume = 0.5 },
    ui_close          = { id = "rbxassetid://0", volume = 0.4 },
    ui_error          = { id = "rbxassetid://0", volume = 0.5 },
    ui_success        = { id = "rbxassetid://0", volume = 0.5 },
    ui_toast          = { id = "rbxassetid://0", volume = 0.5 },
}

-- ── Internal state ─────────────────────────────────────────────────────────
local soundGroups  = {}          -- { Music = SoundGroup, SFX = SoundGroup, UI = SoundGroup }
local groupVolumes = {}          -- { Music = 0.5, SFX = 0.8, UI = 0.7 }
local masterMuted  = false
local currentMusic = nil         -- currently playing Sound instance
local musicName    = nil         -- name of currently playing track

local CROSSFADE_TIME = 1.5      -- seconds for music crossfade

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function SoundManager.Init()
    -- Create SoundGroups under SoundService
    for _, groupName in ipairs({"Music", "SFX", "UI"}) do
        local sg = Instance.new("SoundGroup")
        sg.Name   = groupName
        sg.Volume = DEFAULT_VOLUMES[groupName] or 1
        sg.Parent = SoundService
        soundGroups[groupName]  = sg
        groupVolumes[groupName] = sg.Volume
    end

end

-- ═══════════════════════════════════════════════════════════
-- VOLUME CONTROL
-- ═══════════════════════════════════════════════════════════

function SoundManager.SetVolume(group, vol)
    vol = math.clamp(vol or 1, 0, 1)
    groupVolumes[group] = vol
    local sg = soundGroups[group]
    if sg then
        sg.Volume = masterMuted and 0 or vol
    end
end

function SoundManager.GetVolume(group)
    return groupVolumes[group] or 1
end

function SoundManager.SetMasterMute(muted)
    masterMuted = muted
    for group, sg in pairs(soundGroups) do
        sg.Volume = muted and 0 or (groupVolumes[group] or 1)
    end
end

function SoundManager.IsMuted()
    return masterMuted
end

-- ═══════════════════════════════════════════════════════════
-- SOUND PLAYBACK
-- ═══════════════════════════════════════════════════════════

--- Create a one-shot Sound instance, play it, then destroy.
local function playOneShot(name, group)
    local entry = SOUND_LIBRARY[name]
    if not entry then
        warn("[SoundManager] Unknown sound:", name)
        return
    end
    if entry.id == "rbxassetid://0" then return end  -- placeholder, skip

    local sg = soundGroups[group]
    if not sg then return end

    local sound     = Instance.new("Sound")
    sound.SoundId   = entry.id
    sound.Volume    = entry.volume or 1
    sound.PlaybackSpeed = entry.pitch or 1
    sound.SoundGroup = sg
    sound.Parent     = sg

    sound:Play()
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
    -- Fallback: destroy after 15s if Ended never fires (broken/moderated asset)
    task.delay(15, function()
        if sound and sound.Parent then
            sound:Destroy()
        end
    end)
end

function SoundManager.PlaySFX(name)
    playOneShot(name, "SFX")
end

function SoundManager.PlayUI(name)
    playOneShot(name, "UI")
end

-- ═══════════════════════════════════════════════════════════
-- MUSIC PLAYBACK (crossfade)
-- ═══════════════════════════════════════════════════════════

function SoundManager.PlayMusic(name)
    if name == musicName and currentMusic and currentMusic.IsPlaying then
        return -- already playing
    end

    local entry = SOUND_LIBRARY[name]
    if not entry then
        warn("[SoundManager] Unknown music:", name)
        return
    end
    if entry.id == "rbxassetid://0" then return end  -- placeholder

    local sg = soundGroups.Music
    if not sg then return end

    -- Fade out old music
    if currentMusic and currentMusic.IsPlaying then
        local old = currentMusic
        TweenService:Create(old,
            TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Volume = 0 }
        ):Play()
        task.delay(CROSSFADE_TIME, function()
            old:Stop()
            old:Destroy()
        end)
    end

    -- Create and fade in new music
    local sound     = Instance.new("Sound")
    sound.SoundId   = entry.id
    sound.Volume    = 0
    sound.Looped    = entry.loop ~= false
    sound.SoundGroup = sg
    sound.Parent     = sg
    sound:Play()

    TweenService:Create(sound,
        TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { Volume = entry.volume or 0.5 }
    ):Play()

    currentMusic = sound
    musicName    = name
end

function SoundManager.StopMusic()
    if currentMusic and currentMusic.IsPlaying then
        local old = currentMusic
        TweenService:Create(old,
            TweenInfo.new(CROSSFADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Volume = 0 }
        ):Play()
        task.delay(CROSSFADE_TIME, function()
            old:Stop()
            old:Destroy()
        end)
    end
    currentMusic = nil
    musicName    = nil
end

--- Returns the name of the currently playing music track (or nil).
function SoundManager.GetCurrentMusic()
    return musicName
end

-- ═══════════════════════════════════════════════════════════
-- SOUND LIBRARY QUERY
-- ═══════════════════════════════════════════════════════════

function SoundManager.GetSoundNames()
    local names = {}
    for name, _ in pairs(SOUND_LIBRARY) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return SoundManager
