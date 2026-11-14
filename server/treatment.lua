local config <const> = require 'config'
local states <const> = require 'shared.states'
local medics <const> = require 'server.medics'
local state <const> = require 'server.state'
local care <const> = require 'server.care'
local catalog <const> = require 'server.catalog'
local Cobalt <const> = exports.cobalt_core:GetCoreObject()

local TREAT_RANGE <const> = states.treatRange

---@param bodyPart BodyPart
---@return string
local function partLabel(bodyPart)
    return locale(('body_parts.%s'):format(bodyPart)):lower()
end

RegisterNetEvent('cobalt_ambulancejob:server:reportInjury', function(bodyPart, kind)
    local source <const> = source

    if not states.injuryKinds[kind] then return end

    state.addInjury(source, bodyPart, kind)
end)

---@type table<integer, integer> medic source to the os.time their current treatment ends
local busyUntil <const> = {}

AddEventHandler('playerDropped', function()
    busyUntil[source] = nil
end)

RegisterNetEvent('cobalt_ambulancejob:server:treat', function(target, bodyPart, item)
    local actor <const> = source
    local patient <const> = type(target) == 'number' and target or actor
    local def <const> = config.treatment[item]

    if not def or item == 'defibrillator' or not lib.table.contains(config.bodyParts, bodyPart) then return end
    if os.time() < (busyUntil[actor] or 0) then return end

    if not exports.cobalt_inventory:HasItem(actor, item, 1) then
        return medics.notify(actor, locale('treatment.no_item'), 'error')
    end

    if actor ~= patient and not medics.near(actor, patient, TREAT_RANGE) then
        return medics.notify(actor, locale('treatment.get_closer'), 'error')
    end

    local matched

    for _, kind in ipairs(def.injuries) do
        if state.hasInjury(patient, bodyPart, kind) then
            matched = kind
            break
        end
    end

    if not matched then
        return medics.notify(actor, locale('treatment.nothing_to_treat', partLabel(bodyPart)), 'error')
    end

    if def.consume and not exports.cobalt_inventory:RemoveItem(actor, item, 1) then return end

    busyUntil[actor] = os.time() + math.max(catalog.itemDuration(item) // 1000 - 1, 0)

    state.removeInjury(patient, bodyPart, matched)

    local citizenid <const> = medics.citizenid(patient)
    local medic <const> = medics.citizenid(actor)

    if citizenid and medic and actor ~= patient then
        care.noteInjury(citizenid, bodyPart, matched)
        care.noteItem(citizenid, medic, item, bodyPart, matched)
    end

    medics.notify(actor, locale('treatment.treated', partLabel(bodyPart)), 'success')

    if actor ~= patient then
        medics.notify(patient, locale('treatment.treated_by_medic', partLabel(bodyPart)), 'success')
    end
end)

lib.callback.register('cobalt_ambulancejob:treatmentSeconds', function(_, item)
    if type(item) ~= 'string' then return end

    return catalog.itemDuration(item)
end)

Cobalt.Commands.Add('injureme', locale('commands.injureme_help'), {
    { name = 'part', help = locale('commands.part_help') },
    { name = 'kind', help = locale('commands.kind_help') },
}, false, function(source, args)
    if source == 0 or not exports.cobalt_core:HasPermission(source, 'admin') then return end

    local bodyPart <const> = args[1] or 'left_arm'
    local kind <const> = args[2] or 'bleeding'

    if states.injuryKinds[kind] and state.addInjury(source, bodyPart, kind) then
        medics.notify(source, locale('commands.injured', kind, bodyPart))
    end
end, 'admin')
