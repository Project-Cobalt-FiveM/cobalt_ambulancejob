local config <const> = require 'config'
local states <const> = require 'shared.states'

local REVIVE <const> = states.revive

local Patient <const> = {}

---@return ReviveState
function Patient.revive()
    return LocalPlayer.state.revive or { state = REVIVE.ALIVE, since = 0 }
end

---@param name ReviveStateName
---@return boolean
function Patient.incapacitates(name)
    return name == REVIVE.DOWN or name == REVIVE.DEAD or name == REVIVE.KNOCKED_OUT
end

---@return boolean
function Patient.isIncapacitated()
    return Patient.incapacitates(Patient.revive().state)
end

---True while the server has the player lying in a hospital bed.
---@return boolean
function Patient.inBed()
    return LocalPlayer.state.bed ~= nil
end

---Fades the screen out, runs `step`, and always fades back in, even when `step` errors or the fade stalls.
---@param ms integer
---@param step fun()
---@return boolean ok
function Patient.behindFade(ms, step)
    DoScreenFadeOut(ms)

    local deadline <const> = GetGameTimer() + ms + 2000

    while not IsScreenFadedOut() and GetGameTimer() < deadline do
        Wait(0)
    end

    local ok <const>, err <const> = pcall(step)

    if not ok then
        lib.print.error(err)
    end

    Wait(300)
    DoScreenFadeIn(ms)

    return ok
end

---@return integer
function Patient.now()
    return GetCloudTimeAsInt()
end

---@return boolean
function Patient.isMedic()
    return exports.cobalt_management:GetJob()?.name == config.job
end

---@return boolean
function Patient.isOnDutyMedic()
    return Patient.isMedic() and exports.cobalt_management:GetDuty()
end

---@param serverId integer
---@return ReviveStateName
function Patient.stateOf(serverId)
    return Player(serverId).state.revive?.state or REVIVE.ALIVE
end

---@param entity integer
---@return integer?
function Patient.otherPlayer(entity)
    if not entity or entity == 0 or entity == cache.ped or not IsPedAPlayer(entity) then return end

    local player <const> = NetworkGetPlayerIndexFromPed(entity)

    if player == -1 then return end

    return GetPlayerServerId(player)
end

---@param range number
---@return integer?
function Patient.closestPlayer(range)
    local player <const> = lib.getClosestPlayer(GetEntityCoords(cache.ped), range, false)

    return player and GetPlayerServerId(player)
end

return Patient
