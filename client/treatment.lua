local config <const> = require 'config'
local states <const> = require 'shared.states'
local patient <const> = require 'client.patient'
local core <const> = exports.cobalt_core

local REVIVE <const> = states.revive
local TREAT_RANGE <const> = states.treatRange

---@param bodyPart BodyPart
---@return string
local function partLabel(bodyPart)
    return locale(('body_parts.%s'):format(bodyPart))
end

---@param kind InjuryKind
---@return string
local function kindLabel(kind)
    return locale(('injuries.%s'):format(kind)):lower()
end

---@param serverId integer
---@return Injuries
local function injuriesOf(serverId)
    return Player(serverId).state.injuries or {}
end

---@param serverId integer
---@param item string
---@return { bodyPart: BodyPart, kind: InjuryKind }[]
local function treatable(serverId, item)
    local treats <const> = config.treatment[item].injuries
    local injuries <const> = injuriesOf(serverId)
    local out <const> = {}

    for _, bodyPart in ipairs(config.bodyParts) do
        for _, kind in ipairs(injuries[bodyPart] or {}) do
            if lib.table.contains(treats, kind) then
                out[#out + 1] = { bodyPart = bodyPart, kind = kind }
            end
        end
    end

    return out
end

---@param label string
---@param duration integer
---@param anim { dict: string, clip: string, flag?: integer }
---@return boolean
local function progress(label, duration, anim)
    return core:Progressbar({
        label = label,
        duration = duration,
        canCancel = true,
        disable = { move = true, combat = true, car = true },
        anim = { dict = anim.dict, clip = anim.clip, flag = anim.flag },
    })
end

---@param target integer
local function tryDefib(target)
    local state <const> = patient.stateOf(target)

    if state ~= REVIVE.DOWN then
        return core:Notify({
            description = state == REVIVE.DEAD and locale('defib.too_late') or locale('defib.not_down'),
            type = 'error',
        })
    end

    local def <const> = config.treatment.defibrillator

    lib.playAnim(cache.ped, def.anim.dict, def.anim.clip, 4.0, -4.0, def.seconds * 1000, def.anim.flag)

    local success <const> = core:SkillCheck('medium', { 'E' })

    StopAnimTask(cache.ped, def.anim.dict, def.anim.clip, 1.0)

    if not success then
        return core:Notify({ description = locale('defib.shock_failed'), type = 'error' })
    end

    TriggerServerEvent('cobalt_ambulancejob:server:defib', target)
end

---@param target integer
local function giveCpr(target)
    if progress(locale('cpr.giving'), config.cpr.seconds * 1000, config.cpr.anim) then
        TriggerServerEvent('cobalt_ambulancejob:server:cpr', target)
    end
end

---@param target integer
---@param item string
---@param injury { bodyPart: BodyPart, kind: InjuryKind }
local function treat(target, item, injury)
    local duration <const> = lib.callback.await('cobalt_ambulancejob:treatmentSeconds', false, item)
        or config.treatment[item].seconds * 1000
    local label <const> = locale('treatment.treating', partLabel(injury.bodyPart):lower())

    if progress(label, duration, config.treatment[item].anim) then
        TriggerServerEvent('cobalt_ambulancejob:server:treat', target, injury.bodyPart, item)
    end
end

---@param item string
local function useTreatment(item)
    if not config.treatment[item] then return end

    if item == 'defibrillator' then
        local target <const> = patient.closestPlayer(TREAT_RANGE)

        if not target then
            return core:Notify({ description = locale('treatment.no_patient'), type = 'error' })
        end

        return tryDefib(target)
    end

    local target <const> = patient.closestPlayer(TREAT_RANGE) or cache.serverId
    local list <const> = treatable(target, item)
    local yourself <const> = target == cache.serverId

    if #list == 0 then
        return core:Notify({
            description = yourself and locale('treatment.nothing_on_you') or locale('treatment.nothing_on_patient'),
            type = 'error',
        })
    end

    local options <const> = {}

    for i, injury in ipairs(list) do
        options[i] = {
            title = partLabel(injury.bodyPart),
            description = locale('treatment.treat_kind', kindLabel(injury.kind)),
            onSelect = function() treat(target, item, injury) end,
        }
    end

    core:RegisterContext({
        id = 'cobalt_ambulancejob:treat',
        title = yourself and locale('treatment.treat_yourself') or locale('treatment.treat_patient'),
        options = options,
    })
    core:ShowContext('cobalt_ambulancejob:treat')
end

exports('UseTreatment', function(event, item)
    if event == 'usedItem' then useTreatment(item.name) end
end)

---@param target integer
local function showInjuries(target)
    local injuries <const> = injuriesOf(target)
    local options <const> = {}

    for _, bodyPart in ipairs(config.bodyParts) do
        local list <const> = injuries[bodyPart]

        if list and #list > 0 then
            local kinds <const> = {}

            for i, kind in ipairs(list) do
                kinds[i] = kindLabel(kind)
            end

            options[#options + 1] = { title = partLabel(bodyPart), description = table.concat(kinds, ', ') }
        end
    end

    if #options == 0 then
        return core:Notify({ description = locale('treatment.no_injuries') })
    end

    core:RegisterContext({ id = 'cobalt_ambulancejob:injuries', title = locale('treatment.injuries_title'), options = options })
    core:ShowContext('cobalt_ambulancejob:injuries')
end

exports.ox_target:addGlobalPlayer({
    {
        name = 'cobalt_ambulancejob:check_injuries',
        label = locale('target.check_injuries'),
        icon = 'fas fa-stethoscope',
        distance = 2.0,
        canInteract = function(entity)
            return patient.isOnDutyMedic() and patient.otherPlayer(entity) ~= nil
        end,
        onSelect = function(data)
            local target <const> = patient.otherPlayer(data.entity)

            if target then
                showInjuries(target)
            end
        end,
    },
    {
        name = 'cobalt_ambulancejob:defib',
        label = locale('target.use_defib'),
        icon = 'fas fa-bolt',
        distance = 2.0,
        canInteract = function(entity)
            local target <const> = patient.otherPlayer(entity)

            if not target or not patient.isOnDutyMedic() then return false end

            return patient.stateOf(target) == REVIVE.DOWN and exports.cobalt_inventory:HasItem('defibrillator', 1)
        end,
        onSelect = function(data)
            local target <const> = patient.otherPlayer(data.entity)

            if target then
                tryDefib(target)
            end
        end,
    },
    {
        name = 'cobalt_ambulancejob:cpr',
        label = locale('target.give_cpr'),
        icon = 'fas fa-heart-pulse',
        distance = 2.0,
        canInteract = function(entity)
            local target <const> = patient.otherPlayer(entity)

            return target ~= nil and patient.stateOf(target) == REVIVE.DOWN
        end,
        onSelect = function(data)
            local target <const> = patient.otherPlayer(data.entity)

            if target then
                giveCpr(target)
            end
        end,
    },
})
