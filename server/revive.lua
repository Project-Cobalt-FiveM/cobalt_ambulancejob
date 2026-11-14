local config <const> = require 'config'
local states <const> = require 'shared.states'
local medics <const> = require 'server.medics'
local hospitals <const> = require 'shared.hospitals'
local state <const> = require 'server.state'
local access <const> = require 'server.access'
local care <const> = require 'server.care'
local dispatch <const> = require 'server.dispatch'
local records <const> = require 'server.records'
local beds <const> = require 'server.beds'
local Cobalt <const> = exports.cobalt_core:GetCoreObject()

local REVIVE <const> = states.revive
local TREAT_RANGE <const> = states.treatRange
local ALIVE_HEALTH <const> = 100
local HEALTH_SYNC_MS <const> = 1000

local Revive <const> = {}

---@param source integer
---@return Hospital
function Revive.nearestHospital(source)
    local ped <const> = GetPlayerPed(source)

    return hospitals.nearest(ped == 0 and vec3(0.0, 0.0, 0.0) or GetEntityCoords(ped))
end

---@param source integer
---@param fee integer
---@param reason 'self'|'auto'|'admin'
function Revive.respawnAtHospital(source, fee, reason)
    local hospital <const> = Revive.nearestHospital(source)
    local injuries <const> = state.injuryList(source)

    state.setRevive(source, REVIVE.ALIVE)
    state.clearInjuries(source)
    TriggerClientEvent('cobalt_ambulancejob:client:respawnAt', source, hospital.respawn)

    exports.cobalt_core:LogPlayer(
        source,
        'ems.respawn',
        ('Respawned at %s'):format(hospital.label),
        { reason = reason, fee = fee }
    )

    local filed <const>, err <const> = pcall(records.fileRespawn, source, hospital, injuries, fee, reason)

    if not filed then
        lib.print.error(('Respawn report for %d failed: %s'):format(source, err))
    end
end

---@param source integer
local function stampFallbackInjury(source)
    for _, injury in ipairs(state.injuryList(source)) do
        if injury.kind == 'bleeding' then return end
    end

    state.addInjury(source, 'torso', 'bleeding')
end

---@param target integer
---@return boolean ok
---@return 'not_online'? err
function Revive.revivePlayer(target)
    local player <const> = medics.player(target)

    if not player then return false, 'not_online' end

    if state.revive(target).state ~= REVIVE.ALIVE then
        state.setRevive(target, REVIVE.ALIVE)
        TriggerClientEvent('cobalt_ambulancejob:client:reviveInPlace', target)
    end

    exports.cobalt_core:SetNeed(target, 'hunger', 100)
    exports.cobalt_core:SetNeed(target, 'thirst', 100)

    if GetResourceState('cobalt_hud') == 'started' then
        exports.cobalt_hud:SetStress(target, 0)
    end

    return true
end

---@param target integer
---@return boolean
function Revive.killPlayer(target)
    if state.revive(target).state == REVIVE.DEAD then return false end

    state.setRevive(target, REVIVE.DEAD)

    return true
end

---@param source integer
---@return boolean
local function isClearlyAlive(source)
    local ped <const> = GetPlayerPed(source)

    if ped == 0 or GetEntityHealth(ped) <= ALIVE_HEALTH then return false end

    Wait(HEALTH_SYNC_MS)

    return GetEntityHealth(GetPlayerPed(source)) > ALIVE_HEALTH
end

---@param source integer
local function enterDown(source)
    if state.revive(source).state ~= REVIVE.ALIVE then return end

    state.setRevive(source, REVIVE.DOWN)
    stampFallbackInjury(source)

    local citizenid <const> = medics.citizenid(source)

    if citizenid then
        for _, injury in ipairs(state.injuryList(source)) do
            care.noteInjury(citizenid, injury.bodyPart, injury.kind)
        end
    end
end

RegisterNetEvent('cobalt_ambulancejob:server:enterDown', function()
    local source <const> = source

    if isClearlyAlive(source) then
        return exports.cobalt_core:LogPlayer(source, 'ems.fake_down', 'Asked to go down while alive', nil, 'security')
    end

    enterDown(source)
end)

local KNOCKOUT_HIT_WINDOW_MS <const> = 3000

---@type table<integer, integer> victim source to the GetGameTimer of their last knockout-weapon hit
local knockoutHits <const> = {}

AddEventHandler('weaponDamageEvent', function(_, data)
    if not config.knockout.weapons[data.weaponType] then return end

    for _, netId in ipairs(data.hitGlobalIds or { data.hitGlobalId }) do
        local entity <const> = NetworkGetEntityFromNetworkId(netId)
        local victim <const> = entity ~= 0 and IsPedAPlayer(entity) and NetworkGetEntityOwner(entity)

        if victim then knockoutHits[victim] = GetGameTimer() end
    end
end)

AddEventHandler('playerDropped', function()
    knockoutHits[source] = nil
end)

RegisterNetEvent('cobalt_ambulancejob:server:enterKnockedOut', function()
    local source <const> = source

    if state.revive(source).state ~= REVIVE.ALIVE then return end

    if isClearlyAlive(source) then
        return exports.cobalt_core:LogPlayer(source, 'ems.fake_down', 'Asked to be knocked out while alive', nil, 'security')
    end

    if GetGameTimer() - (knockoutHits[source] or -KNOCKOUT_HIT_WINDOW_MS) > KNOCKOUT_HIT_WINDOW_MS then
        enterDown(source)
        return TriggerClientEvent('cobalt_ambulancejob:client:enterDown', source)
    end

    knockoutHits[source] = nil
    state.setRevive(source, REVIVE.KNOCKED_OUT)

    SetTimeout(config.knockout.seconds * 1000, function()
        if state.revive(source).state ~= REVIVE.KNOCKED_OUT then return end

        state.setRevive(source, REVIVE.ALIVE)
        TriggerClientEvent('cobalt_ambulancejob:client:knockoutWake', source)
    end)
end)

---@param source integer
local function bleedOut(source)
    if not state.isDown(source) or state.deathState(source) ~= REVIVE.DEAD then return end

    state.setRevive(source, REVIVE.DEAD)
    exports.cobalt_core:LogPlayer(source, 'ems.bled_out', 'Bled out in last stand')
end

RegisterNetEvent('cobalt_ambulancejob:server:bledOut', function()
    bleedOut(source)
end)

RegisterNetEvent('cobalt_ambulancejob:server:selfRespawn', function()
    local source <const> = source
    local revive <const> = state.revive(source)

    if revive.state ~= REVIVE.DEAD or os.time() - revive.since < config.death.deadSeconds then
        return medics.notify(source, locale('respawn.not_yet'), 'error')
    end

    Revive.respawnAtHospital(source, config.death.selfRespawnFee, 'self')
end)

RegisterNetEvent('cobalt_ambulancejob:server:executed', function()
    local source <const> = source

    if state.revive(source).state ~= REVIVE.DOWN then return end
    if GetEntityHealth(GetPlayerPed(source)) >= config.death.executedHpFloor then return end

    state.setRevive(source, REVIVE.DEAD)
    exports.cobalt_core:LogPlayer(source, 'ems.executed', 'Killed while bleeding out')
end)

RegisterNetEvent('cobalt_ambulancejob:server:characterKill', function()
    local source <const> = source

    if not config.death.characterKill or state.revive(source).state ~= REVIVE.DEAD then return end

    local citizenid <const> = medics.citizenid(source)

    if not citizenid then return end

    exports.cobalt_core:LogPlayer(
        source,
        'ems.character_kill',
        ('Permanently deleted character %s'):format(citizenid),
        nil,
        'warn'
    )
    Cobalt.Player.ForceDeleteCharacter(citizenid)
end)

lib.callback.register('cobalt_ambulancejob:requestEms', function(source)
    if not state.isDown(source) then return false end

    return dispatch.requestEms(source, false) ~= nil
end)

RegisterNetEvent('cobalt_ambulancejob:server:cpr', function(target)
    local actor <const> = source

    if type(target) ~= 'number' or target == actor then return end

    if not state.isDown(target) then
        return medics.notify(actor, locale('cpr.not_down'), 'error')
    end

    if not medics.near(actor, target, TREAT_RANGE) then
        return medics.notify(actor, locale('treatment.get_closer'), 'error')
    end

    local last <const> = Player(target).state.cpr

    if last and os.time() - (last.at or 0) < config.cpr.windowSeconds then
        return medics.notify(actor, locale('cpr.too_soon'), 'error')
    end

    local revive <const> = state.revive(target)
    local since <const> = math.min(os.time(), revive.since + config.cpr.addsSeconds)

    state.setRevive(target, REVIVE.DOWN, since)
    Player(target).state:set('cpr', { at = os.time(), by = actor }, true)

    local citizenid <const> = medics.citizenid(target)
    local medic <const> = medics.citizenid(actor)

    if citizenid and medic then
        care.noteProcedure(citizenid, medic, 'CPR')
    end

    medics.notify(actor, locale('cpr.done'), 'success')
    medics.notify(target, locale('cpr.received'))
end)

---@param actor integer
---@return integer charges left after this use
---@return boolean ok
local function spendDefibCharge(actor)
    local item <const> = exports.cobalt_inventory:GetItemByName(actor, 'defibrillator')

    if not item then return 0, false end

    local charges <const> = (item.metadata?.uses or config.treatment.defibrillator.charges) - 1

    if charges <= 0 then
        exports.cobalt_inventory:RemoveItem(actor, 'defibrillator', 1)
        medics.notify(actor, locale('defib.used_up'), 'warning')
    else
        local inventory <const> = exports.cobalt_inventory:GetPlayerInvName(actor)

        if inventory and item.id then
            exports.cobalt_inventory:SetItemMetadata(inventory, item.id, 'uses', charges)
        end
    end

    return math.max(charges, 0), true
end

RegisterNetEvent('cobalt_ambulancejob:server:defib', function(target)
    local actor <const> = source

    if type(target) ~= 'number' or target == actor then return end

    if not medics.isOnDuty(actor) or not access.can(actor, 'useDefib') then
        return medics.notify(actor, locale('defib.no_rank'), 'error')
    end

    local revive <const> = state.revive(target)

    if revive.state == REVIVE.DEAD then
        return medics.notify(actor, locale('defib.too_late'), 'error')
    end

    if revive.state ~= REVIVE.DOWN then return end

    if not medics.near(actor, target, TREAT_RANGE) then
        return medics.notify(actor, locale('treatment.get_closer'), 'error')
    end

    local cpr <const> = Player(target).state.cpr

    local window <const> = config.cpr.windowSeconds

    if not cpr or os.time() - cpr.at > window then
        return medics.notify(actor, locale('defib.cpr_first', window), 'error')
    end

    local charges <const>, ok <const> = spendDefibCharge(actor)

    if not ok then
        return medics.notify(actor, locale('defib.missing'), 'error')
    end

    state.setRevive(target, REVIVE.ALIVE)
    TriggerClientEvent('cobalt_ambulancejob:client:reviveInPlace', target)
    local recovered <const>, recoverError <const> = pcall(beds.recover, target, medics.name(actor))

    if not recovered then
        lib.print.error(('Bed recovery for %d failed: %s'):format(target, recoverError))
    end

    local patient <const> = medics.citizenid(target)
    local medic <const> = medics.citizenid(actor)

    if medic then
        records.logRevive(medic, patient)

        if patient then
            care.noteProcedure(patient, medic, 'Defibrillator revive')
        end
    end

    medics.notify(actor, locale('defib.revived', charges), 'success')
    medics.notify(target, locale('defib.revived_by_medic'), 'success')

    exports.cobalt_core:LogPlayer(
        actor,
        'ems.defib',
        'Revived a patient with a defibrillator',
        { chargesLeft = charges },
        'info',
        target
    )
end)

---@param source integer
---@param now integer
local function advance(source, now)
    local revive <const> = state.revive(source)

    if revive.since <= 0 then return end

    local elapsed <const> = now - revive.since

    if revive.state == REVIVE.DOWN and elapsed >= config.death.bleedoutSeconds then
        bleedOut(source)
    elseif revive.state == REVIVE.DEAD and elapsed > config.death.autoRespawnSeconds then
        Revive.respawnAtHospital(source, config.death.autoRespawnFee, 'auto')
    elseif revive.state == REVIVE.KNOCKED_OUT and elapsed > config.knockout.seconds + 5 then
        state.setRevive(source, REVIVE.ALIVE)
        TriggerClientEvent('cobalt_ambulancejob:client:knockoutWake', source)
    end
end

CreateThread(function()
    while true do
        Wait(5000)

        local now <const> = os.time()
        local timed <const> = {}

        for source in pairs(state.timed) do timed[#timed + 1] = source end

        for _, id in ipairs(timed) do
            local checked <const>, err <const> = pcall(advance, id, now)

            if not checked then
                lib.print.error(('Death clock for %s failed: %s'):format(id, err))
            end
        end
    end
end)

---@param source integer
---@param text string
---@param kind? 'success'|'error'|'inform'|'warning'
local function reply(source, text, kind)
    if source == 0 then
        return lib.print.info(text)
    end

    medics.notify(source, text, kind)
end

---@param source integer
---@param arg? string
---@return integer?
local function commandTarget(source, arg)
    if not arg or arg == '' or arg:lower() == 'me' then
        return source ~= 0 and source or nil
    end

    local target <const> = math.tointeger(tonumber(arg))

    return target and medics.player(target) and target or nil
end

---@param source integer
---@return string
local function missingTarget(source)
    return source == 0 and locale('commands.console_needs_id') or locale('commands.not_online')
end

Cobalt.Commands.Add('revive', locale('commands.revive_help'), {
    { name = 'id', help = locale('commands.id_help') },
}, false, function(source, args)
    local target <const> = commandTarget(source, args[1])

    if not target then return reply(source, missingTarget(source), 'error') end

    if not Revive.revivePlayer(target) then
        return reply(source, locale('commands.not_online'), 'error')
    end

    if target ~= source then
        reply(source, locale('commands.revived', target), 'success')
        medics.notify(target, locale('commands.revived_by_admin'))
    end
end, 'admin')

Cobalt.Commands.Add('kill', locale('commands.kill_help'), {
    { name = 'id', help = locale('commands.id_help') },
}, false, function(source, args)
    local target <const> = commandTarget(source, args[1])

    if not target then return reply(source, missingTarget(source), 'error') end

    if not Revive.killPlayer(target) then
        return reply(source, locale('commands.already_dead'), 'error')
    end

    if target ~= source then
        reply(source, locale('commands.killed', target), 'success')
        medics.notify(target, locale('commands.killed_by_admin'), 'error')
    end
end, 'admin')

Cobalt.Commands.Add('killme', locale('commands.killme_help'), {}, false, function(source)
    if source == 0 or not exports.cobalt_core:HasPermission(source, 'admin') then return end

    Revive.killPlayer(source)
end, 'admin')

Cobalt.Commands.Add('reviveme', locale('commands.reviveme_help'), {}, false, function(source)
    if source == 0 or not exports.cobalt_core:HasPermission(source, 'admin') then return end

    Revive.respawnAtHospital(source, 0, 'admin')
end, 'admin')

return Revive
