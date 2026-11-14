local states <const> = require 'shared.states'
local patient <const> = require 'client.patient'
---@type { bones: table<integer, BodyPart>, weapons: table<integer, InjuryKind[]> }
local damage <const> = require 'data.damage'

local THROTTLE_MS <const> = 800

---@type table<string, integer>
local recent <const> = {}

---@param bodyPart BodyPart
---@param kind InjuryKind
---@return boolean
local function shouldReport(bodyPart, kind)
    local key <const> = bodyPart .. ':' .. kind
    local now <const> = GetGameTimer()

    if recent[key] and now - recent[key] < THROTTLE_MS then return false end

    recent[key] = now

    return true
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or args[1] ~= cache.ped then return end

    if patient.revive().state ~= states.revive.ALIVE then return end

    local hit <const>, bone <const> = GetPedLastDamageBone(cache.ped)
    local bodyPart <const> = hit and damage.bones[bone]

    if not bodyPart then return end

    local kinds <const> = damage.weapons[args[7]] or {}

    for _, kind in ipairs(kinds) do
        if shouldReport(bodyPart, kind) then
            TriggerServerEvent('cobalt_ambulancejob:server:reportInjury', bodyPart, kind)
        end
    end

    ClearPedLastDamageBone(cache.ped)
end)
