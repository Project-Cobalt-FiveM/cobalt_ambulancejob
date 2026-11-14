local config <const> = require 'config'
local states <const> = require 'shared.states'
local patient <const> = require 'client.patient'
local hospitals <const> = require 'shared.hospitals'
local effects <const> = require 'client.effects'
local core <const> = exports.cobalt_core

local REVIVE <const> = states.revive
local KEYS <const> = config.death.keys
local LAST_STAND <const> = config.lastStand

local enteredDown = false
local looping = false
local lastDamageWeapon = 0
local lastDamageAt = 0

---@type { state: ReviveStateName, since: integer, emsCalled: boolean }?
local shown

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or args[1] ~= cache.ped then return end

    lastDamageWeapon = args[7] or 0
    lastDamageAt = GetGameTimer()
end)

CreateThread(function()
    exports.spawnmanager:setAutoSpawn(false)
    exports.spawnmanager:setAutoSpawnCallback(function() end)
end)

---@param ped integer
---@param health integer
local function resurrect(ped, health)
    if GetEntityHealth(ped) <= 0 or IsPedDeadOrDying(ped, true) then
        local coords <const> = GetEntityCoords(ped)

        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), 0, false)
    end

    SetEntityHealth(PlayerPedId(), health)
end

CreateThread(function()
    while true do
        Wait(500)

        local health <const> = GetEntityHealth(cache.ped)
        local revive <const> = patient.revive()

        if health <= 0 and not enteredDown and revive.state == REVIVE.ALIVE then
            enteredDown = true

            local fresh <const> = GetGameTimer() - lastDamageAt <= 1500

            if fresh and config.knockout.weapons[lastDamageWeapon] then
                TriggerServerEvent('cobalt_ambulancejob:server:enterKnockedOut')
            else
                TriggerServerEvent('cobalt_ambulancejob:server:enterDown')
            end
        elseif revive.state == REVIVE.DOWN and health < config.death.executedHpFloor then
            TriggerServerEvent('cobalt_ambulancejob:server:executed')
        end
    end
end)

---@param revive ReviveState
---@param emsCalled boolean
local function sendScreen(revive, emsCalled)
    if shown and shown.state == revive.state and shown.since == revive.since and shown.emsCalled == emsCalled then
        return
    end

    shown = { state = revive.state, since = revive.since, emsCalled = emsCalled }

    local now <const> = patient.now()
    local screen

    if revive.state == REVIVE.KNOCKED_OUT then
        screen = { kind = 'knockedout', endsAt = revive.since + config.knockout.seconds, now = now }
    elseif revive.state == REVIVE.DOWN then
        screen = {
            kind = 'laststand',
            endsAt = revive.since + config.death.bleedoutSeconds,
            total = config.death.bleedoutSeconds,
            now = now,
            callKey = KEYS.callEms.label,
            emsCalled = emsCalled,
        }
    else
        screen = {
            kind = 'dead',
            respawnAt = revive.since + config.death.deadSeconds,
            now = now,
            fee = config.death.selfRespawnFee,
            hospital = hospitals.nearest(GetEntityCoords(cache.ped)).short,
            respawnKey = KEYS.respawn.label,
            killKey = config.death.characterKill and KEYS.characterKill.label or nil,
        }
    end

    SendNUIMessage({ action = 'death', data = screen })
end

---@param holding boolean
local function sendHold(holding)
    SendNUIMessage({ action = 'deathHold', data = holding and config.death.requestEmsHoldMs or false })
end

local function hideScreen()
    shown = nil
    SendNUIMessage({ action = 'death', data = false })
end

---@param blocked boolean
local function blockActions(blocked)
    LocalPlayer.state:set('invBusy', blocked, false)

    if GetResourceState('npwd') ~= 'started' then return end

    if blocked then
        exports.npwd:setPhoneVisible(false)
    end

    exports.npwd:setPhoneDisabled(blocked)
end

local function clearDeathState()
    effects.clear()
    hideScreen()
    blockActions(false)
end

local function disableControls()
    DisableAllControlActions(0)

    for _, control in ipairs(LAST_STAND.allowedControls) do
        EnableControlAction(0, control, true)
    end

    if IsPauseMenuActive() then
        SetFrontendActive(false)
    end
end

---@param ped integer
---@param anim { dict: string, clip: string }
local function playLoop(ped, anim)
    if IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then return end

    lib.requestAnimDict(anim.dict)
    TaskPlayAnim(ped, anim.dict, anim.clip, 4.0, 4.0, -1, 1, 0.0, false, false, false)
    RemoveAnimDict(anim.dict)
end

---@param ped integer
local function crawl(ped)
    if not IsDisabledControlPressed(0, 32) then
        return playLoop(ped, LAST_STAND.idleAnim)
    end

    local heading <const> = GetEntityHeading(ped)
    local target <const> = GetGameplayCamRot(2).z
    local delta <const> = (target - heading + 540.0) % 360.0 - 180.0

    SetEntityHeading(ped, heading + delta * LAST_STAND.turnRate)
    playLoop(ped, LAST_STAND.crawlAnim)
end

local function confirmCharacterKill()
    local choice <const> = core:AlertDialog({
        header = locale('death.kill_header'),
        content = locale('death.kill_content'),
        labels = { confirm = locale('death.kill_confirm'), cancel = locale('common.cancel') },
        type = 'danger',
    })

    if choice == 'confirm' then
        TriggerServerEvent('cobalt_ambulancejob:server:characterKill')
    end
end

local function requestRespawn()
    local revive <const> = patient.revive()

    if revive.state ~= REVIVE.DEAD or patient.now() - revive.since < config.death.deadSeconds then return end

    TriggerServerEvent('cobalt_ambulancejob:server:selfRespawn')
end

local function downLoop()
    looping = true

    local holdStart
    local emsCalled = false
    local calling = false
    local bledOutSent = false

    while patient.isIncapacitated() do
        local revive <const> = patient.revive()
        local ped <const> = cache.ped

        if not patient.incapacitates(revive.state) then break end

        disableControls()
        sendScreen(revive, emsCalled)
        effects.enter(revive.state)

        if revive.state == REVIVE.KNOCKED_OUT then
            if not IsPedRagdoll(ped) then
                SetPedToRagdoll(ped, 1500, 1500, 0, true, true, false)
            end
        elseif revive.state == REVIVE.DOWN then
            if not cache.vehicle then
                crawl(ped)
            end

            if not emsCalled and not calling and IsDisabledControlPressed(0, KEYS.callEms.control) then
                if not holdStart then
                    holdStart = GetGameTimer()
                    sendHold(true)
                end

                if GetGameTimer() - holdStart >= config.death.requestEmsHoldMs then
                    holdStart = nil
                    calling = true
                    sendHold(false)

                    CreateThread(function()
                        emsCalled = lib.callback.await('cobalt_ambulancejob:requestEms', false) == true
                        calling = false
                    end)
                end
            elseif holdStart then
                holdStart = nil
                sendHold(false)
            end

            effects.bleed(1 - (patient.now() - revive.since) / config.death.bleedoutSeconds)

            if not bledOutSent and patient.now() - revive.since >= config.death.bleedoutSeconds then
                bledOutSent = true
                TriggerServerEvent('cobalt_ambulancejob:server:bledOut')
            end
        else
            if not cache.vehicle then
                playLoop(ped, config.deadAnim)
            end

            if IsDisabledControlJustReleased(0, KEYS.respawn.control) then
                requestRespawn()
            end

            if config.death.characterKill and IsDisabledControlJustReleased(0, KEYS.characterKill.control) then
                confirmCharacterKill()
            end
        end

        Wait(0)
    end

    looping = false
    hideScreen()
    effects.clear()
end

---@param value ReviveState?
local function onRevive(value)
    local name <const> = value?.state or REVIVE.ALIVE
    local down <const> = patient.incapacitates(name)
    local ped <const> = cache.ped

    SetEveryoneIgnorePlayer(cache.playerId, down)
    SetPedCanBeTargetted(ped, not down)
    blockActions(down)

    if down then
        resurrect(ped, name == REVIVE.DOWN and LAST_STAND.health or 100)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

        if name ~= REVIVE.KNOCKED_OUT then
            ClearPedTasksImmediately(ped)
        else
            SetPedToRagdoll(ped, 5000, 5000, 0, true, true, false)
        end

        if not looping then
            CreateThread(downLoop)
        end

        return
    end

    enteredDown = false
    ClearPedTasksImmediately(ped)
    clearDeathState()
end

AddStateBagChangeHandler('revive', ('player:%s'):format(cache.serverId), function(_, _, value, _, replicated)
    if replicated then return end

    if patient.revive().state == (value?.state or REVIVE.ALIVE) then return end

    SetTimeout(0, function() onRevive(value) end)
end)

RegisterNUICallback('respawn', function(_, cb)
    requestRespawn()
    cb({ ok = true })
end)

RegisterNetEvent('cobalt_ambulancejob:client:enterDown', function()
    enteredDown = true
end)

RegisterNetEvent('cobalt_ambulancejob:client:knockoutWake', function()
    enteredDown = false
end)

RegisterNetEvent('cobalt_ambulancejob:client:reviveInPlace', function()
    local ped <const> = cache.ped

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
end)

RegisterNetEvent('cobalt_ambulancejob:client:healed', function()
    local ped <const> = cache.ped

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
end)

RegisterNetEvent('cobalt_ambulancejob:client:respawnAt', function(coords)
    patient.behindFade(800, function()
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.w, 0, false)

        local ped <const> = PlayerPedId()

        ClearPedBloodDamage(ped)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(ped, coords.w)
        ClearPedTasksImmediately(ped)
    end)

    enteredDown = false
    clearDeathState()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource or not patient.isIncapacitated() then return end

    clearDeathState()
end)

CreateThread(function()
    if patient.isIncapacitated() then
        return onRevive(patient.revive())
    end

    effects.clear()

    if IsScreenFadedOut() or IsScreenFadingOut() then
        DoScreenFadeIn(500)
    end
end)
