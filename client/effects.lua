local config <const> = require 'config'
local states <const> = require 'shared.states'

local REVIVE <const> = states.revive
local FX <const> = config.effects

local Effects <const> = {}

---@type ReviveStateName?
local current

---@type integer?
local heartbeat

local heartbeatVolume = 0.0

---@return boolean
local function soundReady()
    return GetResourceState('cobalt_sound') == 'started'
end

local function stopHeartbeat()
    local id <const> = heartbeat

    heartbeat = nil

    if id and soundReady() then
        exports.cobalt_sound:Stop(id)
    end
end

local function startHeartbeat()
    if heartbeat or not soundReady() then return end

    heartbeatVolume = FX.heartbeat.minVolume

    CreateThread(function()
        local id <const> = exports.cobalt_sound:Play({
            sound = FX.heartbeat.sound,
            player = cache.serverId,
            loop = true,
            volume = heartbeatVolume,
        })

        if not id then return end

        if current ~= REVIVE.DOWN then
            exports.cobalt_sound:Stop(id)
            return
        end

        heartbeat = id
    end)
end

---@param sound string
local function playOnce(sound)
    if soundReady() then
        exports.cobalt_sound:PlayFrontend(sound, FX.volume)
    end
end

---@param look { postfx?: string, timecycle?: string, strength?: number, shake?: string, shakeAmount?: number }
local function apply(look)
    AnimpostfxStopAll()
    StopGameplayCamShaking(true)

    if look.postfx then
        AnimpostfxPlay(look.postfx, 0, true)
    end

    if look.timecycle then
        SetTimecycleModifier(look.timecycle)
        SetTimecycleModifierStrength(look.strength or 1.0)
    else
        ClearTimecycleModifier()
    end

    if look.shake then
        ShakeGameplayCam(look.shake, look.shakeAmount or 1.0)
    end
end

---@param name ReviveStateName
function Effects.enter(name)
    if current == name then return end

    local first <const> = current == nil

    current = name

    if name == REVIVE.DOWN then
        apply(FX.lastStand)
        playOnce(FX.sounds.down)
        startHeartbeat()
    elseif name == REVIVE.DEAD then
        stopHeartbeat()
        apply(FX.dead)
        playOnce(FX.sounds.dead)
    else
        stopHeartbeat()
        apply(FX.knockedOut)
    end

    if first then
        AnimpostfxPlay(FX.impact, 0, false)
    end
end

---@param left number share of the bleed-out clock still to run, 1 to 0
function Effects.bleed(left)
    if current ~= REVIVE.DOWN then return end

    local look <const> = FX.lastStand
    local severity <const> = 1 - math.max(0.0, math.min(1.0, left))

    SetTimecycleModifierStrength(look.strength + (1.0 - look.strength) * severity)

    local volume <const> = FX.heartbeat.minVolume + (FX.heartbeat.maxVolume - FX.heartbeat.minVolume) * severity

    if heartbeat and math.abs(volume - heartbeatVolume) >= 0.05 then
        heartbeatVolume = volume
        exports.cobalt_sound:SetVolume(heartbeat, volume)
    end
end

function Effects.clear()
    current = nil
    stopHeartbeat()
    AnimpostfxStopAll()
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    StopGameplayCamShaking(true)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == cache.resource then
        Effects.clear()
    end
end)

return Effects
