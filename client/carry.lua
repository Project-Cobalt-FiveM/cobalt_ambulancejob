local states <const> = require 'shared.states'
local patient <const> = require 'client.patient'

local CARRY <const> = states.carry
local REVIVE <const> = states.revive
local CARRY_BONE <const> = 24818
local CARRY_OFFSET <const> = vec3(0.27, 0.20, 0.62)
local CARRY_ROTATION <const> = vec3(-50.0, 0.0, 0.0)
local CARRY_DICT <const> = 'anim@heists@box_carry@'
local CARRY_CLIP <const> = 'idle'
local KEY_DROP <const> = 38

local carrying = false

---@return CarryState
local function carry()
    return LocalPlayer.state.fireCarry or { state = CARRY.NONE }
end

local function dropLoop()
    while carry().victim do
        if IsControlJustReleased(0, KEY_DROP) then
            TriggerServerEvent('cobalt_ambulancejob:server:stopCarry')
        end

        Wait(0)
    end
end

---@param value CarryState?
local function onCarry(value)
    if not value or value.state == CARRY.NONE then
        if not carrying then return end

        carrying = false
        DetachEntity(cache.ped, true, false)
        ClearPedTasks(cache.ped)

        return
    end

    carrying = true

    if value.victim then
        lib.requestAnimDict(CARRY_DICT)
        TaskPlayAnim(cache.ped, CARRY_DICT, CARRY_CLIP, 8.0, -8.0, -1, 49, 0, false, false, false)
        RemoveAnimDict(CARRY_DICT)
        CreateThread(dropLoop)

        return
    end

    local carrier <const> = GetPlayerPed(GetPlayerFromServerId(value.carrier))

    if carrier == 0 then return end

    AttachEntityToEntity(
        cache.ped, carrier, GetPedBoneIndex(carrier, CARRY_BONE),
        CARRY_OFFSET.x, CARRY_OFFSET.y, CARRY_OFFSET.z,
        CARRY_ROTATION.x, CARRY_ROTATION.y, CARRY_ROTATION.z,
        false, false, false, false, 2, true
    )
end

AddStateBagChangeHandler('fireCarry', ('player:%s'):format(cache.serverId), function(_, _, value)
    SetTimeout(0, function() onCarry(value) end)
end)

---@param entity integer
---@param cuffedOnly boolean
---@return boolean
local function canCarry(entity, cuffedOnly)
    local target <const> = patient.otherPlayer(entity)

    if not target or patient.revive().state ~= REVIVE.ALIVE or carry().state ~= CARRY.NONE then return false end
    if LocalPlayer.state.cuffed then return false end

    local state <const> = patient.stateOf(target)

    if cuffedOnly then
        return Player(target).state.cuffed ~= nil and state == REVIVE.ALIVE
    end

    return state == REVIVE.DOWN or state == REVIVE.DEAD
end

---@param data { entity: integer }
local function startCarry(data)
    local target <const> = patient.otherPlayer(data.entity)

    if target then
        TriggerServerEvent('cobalt_ambulancejob:server:startCarry', target)
    end
end

exports.ox_target:addGlobalPlayer({
    {
        name = 'cobalt_ambulancejob:carry',
        label = locale('target.carry'),
        icon = 'fas fa-person-walking-luggage',
        distance = 2.0,
        canInteract = function(entity) return canCarry(entity, false) end,
        onSelect = startCarry,
    },
    {
        name = 'cobalt_ambulancejob:carry_suspect',
        label = locale('target.carry_suspect'),
        icon = 'fas fa-person-military-pointing',
        distance = 2.0,
        canInteract = function(entity) return canCarry(entity, true) end,
        onSelect = startCarry,
    },
})

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource or carry().state == CARRY.NONE then return end

    if IsEntityAttached(cache.ped) then DetachEntity(cache.ped, true, false) end

    ClearPedTasks(cache.ped)
end)
