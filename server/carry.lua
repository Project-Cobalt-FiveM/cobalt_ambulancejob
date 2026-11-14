local states <const> = require 'shared.states'
local medics <const> = require 'server.medics'
local state <const> = require 'server.state'

local CARRY <const> = states.carry
local CARRY_RANGE <const> = 2.5

---@param source integer
---@return CarryState
local function carryOf(source)
    return Player(source).state.fireCarry or { state = CARRY.NONE }
end

---@param source integer
---@param payload CarryState
local function setCarry(source, payload)
    Player(source).state:set('fireCarry', payload, true)
end

---@param carrier? integer
---@param victim? integer
local function detach(carrier, victim)
    if carrier then
        setCarry(carrier, { state = CARRY.NONE })
    end

    if victim then
        setCarry(victim, { state = CARRY.NONE })
    end
end

RegisterNetEvent('cobalt_ambulancejob:server:startCarry', function(target)
    local actor <const> = source

    if type(target) ~= 'number' or target == actor then return end

    if state.revive(actor).state ~= states.revive.ALIVE then
        return medics.notify(actor, locale('carry.while_down'), 'error')
    end

    if Player(actor).state.cuffed then return end
    if carryOf(actor).state ~= CARRY.NONE or carryOf(target).state ~= CARRY.NONE then return end

    if not state.isIncapacitated(target) and Player(target).state.cuffed == nil then
        return medics.notify(actor, locale('carry.can_walk'), 'error')
    end

    if not medics.near(actor, target, CARRY_RANGE) then
        return medics.notify(actor, locale('carry.get_closer'), 'error')
    end

    setCarry(actor, { state = CARRY.FIREMAN, victim = target })
    setCarry(target, { state = CARRY.FIREMAN, carrier = actor })
end)

RegisterNetEvent('cobalt_ambulancejob:server:stopCarry', function()
    local carry <const> = carryOf(source)

    if carry.state == CARRY.NONE then return end
    if carry.carrier and Player(source).state.cuffed then return end

    detach(carry.carrier or source, carry.victim or source)
end)

---@param source integer
local function release(source)
    local carry <const> = carryOf(source)

    if carry.state ~= CARRY.NONE then
        detach(carry.carrier or source, carry.victim or source)
    end
end

---@param bagName string
---@param value any
local function releaseIfCarrierDisabled(bagName, _, value)
    if not value then return end

    local source <const> = GetPlayerFromStateBagName(bagName)

    if source == 0 or not carryOf(source).victim then return end

    release(source)
end

AddStateBagChangeHandler('isDead', nil, releaseIfCarrierDisabled)
AddStateBagChangeHandler('cuffed', nil, releaseIfCarrierDisabled)

AddEventHandler('cobalt_core:Server:OnPlayerUnload', release)

AddEventHandler('playerDropped', function()
    release(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    for _, playerId in ipairs(GetPlayers()) do
        local id <const> = tonumber(playerId) --[[@as integer]]

        if Player(id).state.fireCarry then setCarry(id, nil) end
    end
end)
