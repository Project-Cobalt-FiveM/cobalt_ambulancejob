local config <const> = require 'config'
local states <const> = require 'shared.states'
local medics <const> = require 'server.medics'

local REVIVE <const> = states.revive

local State <const> = {}

---Players whose revive clock is running: knocked out, down or dead.
---@type table<integer, true>
State.timed = {}

---@param source integer
---@return ReviveState
function State.revive(source)
    return medics.player(source)?.PlayerData.metadata.revive or { state = REVIVE.ALIVE, since = 0 }
end

---@param source integer
---@param name ReviveStateName
---@param since? integer epoch seconds, now when left out
function State.setRevive(source, name, since)
    local payload <const> = { state = name, since = name == REVIVE.ALIVE and 0 or since or os.time() }
    local bag <const> = Player(source).state

    bag:set('revive', payload, true)
    bag:set('isDead', name ~= REVIVE.ALIVE, true)
    State.timed[source] = name ~= REVIVE.ALIVE or nil

    local player <const> = medics.player(source)

    if player then
        player.Functions.SetMetaData('revive', payload)
        player.Functions.SetMetaData('isdead', name == REVIVE.DEAD)
        player.Functions.SetMetaData('inlaststand', name == REVIVE.DOWN or name == REVIVE.KNOCKED_OUT)
    end
end

---@param source integer
---@return boolean
function State.isDown(source)
    return State.revive(source).state == REVIVE.DOWN
end

---@param source integer
---@return boolean
function State.isIncapacitated(source)
    local name <const> = State.revive(source).state

    return name == REVIVE.DOWN or name == REVIVE.DEAD
end

---@param source integer
---@return ReviveStateName
function State.deathState(source)
    local revive <const> = State.revive(source)

    if revive.state == REVIVE.DOWN and os.time() - revive.since >= config.death.bleedoutSeconds then
        return REVIVE.DEAD
    end

    return revive.state
end

---@param source integer
---@return integer?
function State.bleedsOutAt(source)
    local revive <const> = State.revive(source)

    if revive.state ~= REVIVE.DOWN then return end

    return revive.since + config.death.bleedoutSeconds
end

---@param source integer
---@return Injuries
function State.injuries(source)
    return medics.player(source)?.PlayerData.metadata.injuries or {}
end

---@param source integer
---@param injuries Injuries
function State.setInjuries(source, injuries)
    Player(source).state:set('injuries', injuries, true)
    medics.player(source)?.Functions.SetMetaData('injuries', injuries)
end

---@param source integer
---@return { bodyPart: BodyPart, kind: InjuryKind }[]
function State.injuryList(source)
    local injuries <const> = State.injuries(source)
    local out <const> = {}

    for _, bodyPart in ipairs(config.bodyParts) do
        for _, kind in ipairs(injuries[bodyPart] or {}) do
            out[#out + 1] = { bodyPart = bodyPart, kind = kind }
        end
    end

    return out
end

---@param source integer
---@param bodyPart BodyPart
---@param kind InjuryKind
---@return boolean
function State.hasInjury(source, bodyPart, kind)
    return lib.table.contains(State.injuries(source)[bodyPart] or {}, kind)
end

---@param source integer
---@param bodyPart BodyPart
---@param kind InjuryKind
---@return boolean
function State.addInjury(source, bodyPart, kind)
    if not lib.table.contains(config.bodyParts, bodyPart) then return false end

    local injuries <const> = State.injuries(source)
    local list <const> = injuries[bodyPart] or {}

    if lib.table.contains(list, kind) then return true end

    list[#list + 1] = kind
    injuries[bodyPart] = list
    State.setInjuries(source, injuries)

    return true
end

---@param source integer
---@param bodyPart BodyPart
---@param kind InjuryKind
---@return boolean
function State.removeInjury(source, bodyPart, kind)
    local injuries <const> = State.injuries(source)
    local list <const> = injuries[bodyPart] or {}

    for i = #list, 1, -1 do
        if list[i] == kind then
            table.remove(list, i)
            injuries[bodyPart] = #list > 0 and list or nil
            State.setInjuries(source, injuries)

            return true
        end
    end

    return false
end

---@param source integer
function State.clearInjuries(source)
    State.setInjuries(source, {})
end

AddEventHandler('cobalt_core:Server:PlayerLoaded', function(player)
    local source <const> = player.PlayerData.source
    local metadata <const> = player.PlayerData.metadata or {}
    local revive <const> = metadata.revive or { state = REVIVE.ALIVE, since = 0 }
    local bag <const> = Player(source).state

    bag:set('revive', revive, true)
    bag:set('isDead', revive.state ~= REVIVE.ALIVE, true)
    bag:set('injuries', metadata.injuries or {}, true)
    bag:set('fireCarry', { state = states.carry.NONE }, true)
    State.timed[source] = revive.state ~= REVIVE.ALIVE or nil
end)

AddEventHandler('cobalt_core:Server:OnPlayerUnload', function(source)
    State.timed[source] = nil
end)

AddEventHandler('playerDropped', function()
    State.timed[source] = nil
end)

for _, id in ipairs(GetPlayers()) do
    local source <const> = tonumber(id) --[[@as integer]]

    if State.revive(source).state ~= REVIVE.ALIVE then State.timed[source] = true end
end

return State
