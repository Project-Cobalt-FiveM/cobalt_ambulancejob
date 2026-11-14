local config <const> = require 'config'
local states <const> = require 'shared.states'
local patient <const> = require 'client.patient'
local hospitals <const> = require 'shared.hospitals'
local core <const> = exports.cobalt_core

local REVIVE <const> = states.revive
local CHECK_IN_KEY <const> = config.checkIn.key
local DESK_PROMPT_RANGE <const> = 2.0
local ALIVE_WAIT_MS <const> = 5000
local REVIVE_SETTLE_MS <const> = 250

---@type { hospital: string, index: integer, exit?: vector4 }?
local onBed

---@type table<string, integer>
local doctors <const> = {}

---@type integer[]
local blips <const> = {}

local recovering = false
local checkingIn = false

---@param hospitalId string
---@param index integer
---@return Bed?
local function bedOf(hospitalId, index)
    return hospitals.get(hospitalId)?.beds[index]
end

---@return boolean
local function waitUntilAlive()
    return pcall(lib.waitFor, function() return patient.revive().state == REVIVE.ALIVE or nil end, nil, ALIVE_WAIT_MS)
end

local function healFully()
    local ped <const> = cache.ped

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
end

---@param coords vector4
local function layOn(coords)
    local ped <const> = cache.ped

    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, coords.w)
    FreezeEntityPosition(ped, true)
    lib.playAnim(ped, config.bedAnim.dict, config.bedAnim.clip, 4.0, -4.0, -1, config.bedAnim.flag)
end

local function getOff()
    if not onBed then return end

    local exit <const> = onBed.exit
    local ped <const> = cache.ped

    onBed = nil
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)

    if not exit then return end

    SetEntityCoords(ped, exit.x, exit.y, exit.z, false, false, false, false)
    SetEntityHeading(ped, exit.w)
end

---@param hospitalId string
---@param index integer
---@param bed Bed
local function placeOnBed(hospitalId, index, bed)
    onBed = { hospital = hospitalId, index = index, exit = bed.exit }
    layOn(bed.coords --[[@as vector4]])
end

---@param hospital Hospital
---@param index integer
---@param bed Bed
local function layOnBed(hospital, index, bed)
    if onBed or patient.revive().state ~= REVIVE.ALIVE then return end

    placeOnBed(hospital.id, index, bed)
end

---@return string?
---@return boolean cancelled
local function askReason()
    if patient.isIncapacitated() or not lib.callback.await('cobalt_ambulancejob:medicsAvailable', false) then
        return nil, false
    end

    local answers <const> = core:InputDialog(locale('hospital.check_in'), {
        {
            type = 'input',
            label = locale('hospital.what_happened'),
            placeholder = locale('hospital.what_happened_placeholder'),
            required = true,
            max = 120,
        },
    })

    return answers?[1], answers == nil
end

---@param hospital Hospital
local function checkIn(hospital)
    if checkingIn or onBed then return end

    checkingIn = true

    local reason <const>, cancelled <const> = askReason()

    if cancelled then
        checkingIn = false
        return
    end

    local started <const>, seconds <const> = lib.callback.await('cobalt_ambulancejob:checkInStart', false, hospital.id)

    if started then
        local done <const> = core:Progressbar({
            label = locale('hospital.checking_in'),
            duration = seconds * 1000,
            canCancel = true,
            useWhileDead = true,
            disable = { move = true, combat = true, car = true },
        })
        local reply <const> = done and 'cobalt_ambulancejob:checkInFinish' or 'cobalt_ambulancejob:checkInCancel'

        lib.callback.await(reply, false, reason)
    end

    checkingIn = false
end

---@param hospital Hospital
local function spawnDoctor(hospital)
    local doctor <const> = hospital.doctor --[[@as { model: string, coords: vector4, scenario?: string }]]
    local coords <const> = doctor.coords
    local model <const> = lib.requestModel(doctor.model)
    local ped <const> = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)

    SetModelAsNoLongerNeeded(model)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)

    if doctor.scenario then
        TaskStartScenarioInPlace(ped, doctor.scenario, 0, true)
    end

    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'cobalt_ambulancejob:check_in',
            label = locale('hospital.check_in'),
            icon = 'fas fa-clipboard-user',
            canInteract = function() return not checkingIn and onBed == nil end,
            onSelect = function() checkIn(hospital) end,
        },
    })

    doctors[hospital.id] = ped
end

---@param hospital Hospital
local function addDoctorPoint(hospital)
    lib.points.new({
        coords = hospital.doctor.coords.xyz,
        distance = 60.0,
        onEnter = function() spawnDoctor(hospital) end,
        onExit = function()
            local ped <const> = doctors[hospital.id]

            if ped and DoesEntityExist(ped) then
                exports.ox_target:removeLocalEntity(ped)
                DeletePed(ped)
            end

            doctors[hospital.id] = nil
        end,
    })
end

---@param hospital Hospital
local function addDeskPrompt(hospital)
    local point <const> = hospital.checkIn or hospital.doctor?.coords.xyz

    if not point then return end

    local shown = false

    ---@param visible boolean
    local function show(visible)
        if visible == shown then return end

        shown = visible

        if visible then
            core:ShowTextUI(locale('hospital.check_in_prompt', CHECK_IN_KEY.label))
        else
            core:HideTextUI()
        end
    end

    lib.points.new({
        coords = point,
        distance = DESK_PROMPT_RANGE,
        nearby = function()
            local available <const> = patient.isIncapacitated() and not checkingIn and onBed == nil

            show(available)

            if available and IsDisabledControlJustReleased(0, CHECK_IN_KEY.control) then
                CreateThread(function() checkIn(hospital) end)
            end
        end,
        onExit = function() show(false) end,
    })
end

---@param hospital Hospital
local function addZones(hospital)
    if hospital.supplyStash then
        exports.ox_target:addSphereZone({
            coords = hospital.supplyStash.coords,
            radius = 1.2,
            options = {
                {
                    name = 'cobalt_ambulancejob:supplies',
                    label = locale('hospital.open_stash', hospital.supplyStash.label),
                    icon = 'fas fa-briefcase-medical',
                    distance = 2.0,
                    canInteract = patient.isMedic,
                    onSelect = function() TriggerServerEvent('cobalt_ambulancejob:server:openSupplies', hospital.id) end,
                },
            },
        })
    end

    if hospital.wardrobe then
        exports.ox_target:addSphereZone({
            coords = hospital.wardrobe,
            radius = 1.2,
            options = {
                {
                    name = 'cobalt_ambulancejob:wardrobe',
                    label = locale('hospital.open_wardrobe'),
                    icon = 'fas fa-shirt',
                    canInteract = patient.isMedic,
                    onSelect = function() TriggerEvent('qb-clothing:client:openMenu') end,
                },
            },
        })
    end

    if hospital.spawner then
        local options <const> = {}

        for i, vehicle in ipairs(hospital.spawner.vehicles) do
            options[i] = {
                name = ('cobalt_ambulancejob:spawn_%s'):format(vehicle.model),
                label = locale('hospital.take_vehicle', vehicle.label:lower()),
                icon = 'fas fa-truck-medical',
                canInteract = patient.isOnDutyMedic,
                onSelect = function()
                    TriggerServerEvent('cobalt_ambulancejob:server:spawnVehicle', hospital.id, vehicle.model)
                end,
            }
        end

        exports.ox_target:addSphereZone({ coords = hospital.spawner.coords, radius = 1.5, options = options })
    end

    for index, bed in ipairs(hospital.beds) do
        if bed.coords then
            exports.ox_target:addSphereZone({
                coords = bed.coords.xyz,
                radius = 1.0,
                options = {
                    {
                        name = ('cobalt_ambulancejob:bed_%s_%d'):format(hospital.id, index),
                        label = locale('hospital.lie_on_bed', bed.label:lower()),
                        icon = 'fas fa-bed',
                        canInteract = function() return onBed == nil and patient.revive().state == REVIVE.ALIVE end,
                        onSelect = function() layOnBed(hospital, index, bed) end,
                    },
                    {
                        name = ('cobalt_ambulancejob:bed_off_%s_%d'):format(hospital.id, index),
                        label = locale('hospital.get_off_bed'),
                        icon = 'fas fa-arrow-up-from-bracket',
                        canInteract = function()
                            return not recovering and onBed?.hospital == hospital.id and onBed?.index == index
                        end,
                        onSelect = getOff,
                    },
                },
            })
        end
    end
end

for _, hospital in ipairs(hospitals.list()) do
    local blip <const> = AddBlipForCoord(hospital.coords.x, hospital.coords.y, hospital.coords.z)

    SetBlipSprite(blip, hospital.blip.sprite)
    SetBlipColour(blip, hospital.blip.color)
    SetBlipScale(blip, hospital.blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(hospital.label)
    EndTextCommandSetBlipName(blip)

    blips[#blips + 1] = blip

    if hospital.doctor then
        addDoctorPoint(hospital)
    end

    addDeskPrompt(hospital)
    addZones(hospital)
end

RegisterNetEvent('cobalt_ambulancejob:client:bedTreatment', function(hospitalId, index, seconds)
    local bed <const> = bedOf(hospitalId, index)

    if not bed?.coords or type(seconds) ~= 'number' then return end

    recovering = true

    if not waitUntilAlive() then
        recovering = false
        return
    end

    Wait(REVIVE_SETTLE_MS)

    patient.behindFade(500, function()
        getOff()
        healFully()
        placeOnBed(hospitalId, index, bed)
    end)

    pcall(core.Progressbar, core, {
        label = locale('hospital.bed_treatment'),
        duration = seconds * 1000,
        canCancel = false,
        disable = { move = true, car = true, combat = true, mouse = false },
    })
end)

RegisterNetEvent('cobalt_ambulancejob:client:bedTreatmentDone', function()
    waitUntilAlive()
    healFully()
    recovering = false
    patient.behindFade(400, getOff)
end)

RegisterNetEvent('cobalt_ambulancejob:client:admitted', function(hospitalId, index)
    local bed <const> = bedOf(hospitalId, index)

    getOff()

    if not bed?.coords or #(GetEntityCoords(cache.ped) - bed.coords.xyz) > 50.0 then return end

    placeOnBed(hospitalId, index, bed)
end)

---@param hospitalId string
---@param index? integer
---@param seconds integer
local function recover(hospitalId, index, seconds)
    local hospital <const> = hospitals.get(hospitalId)
    local bed <const> = index and bedOf(hospitalId, index)

    if not hospital then return end

    recovering = true

    if not waitUntilAlive() then
        recovering = false
        return
    end

    local placed <const> = patient.behindFade(500, function()
        getOff()
        Wait(0)

        if bed and bed.coords then return placeOnBed(hospitalId, index --[[@as integer]], bed) end

        local ped <const> = cache.ped
        local respawn <const> = hospital.respawn

        SetEntityCoords(ped, respawn.x, respawn.y, respawn.z, false, false, false, false)
        SetEntityHeading(ped, respawn.w)
    end)

    if placed then
        pcall(core.Progressbar, core, {
            label = locale('hospital.recovering'),
            duration = seconds * 1000,
            canCancel = false,
            disable = { move = true, car = true, combat = true, mouse = false },
        })
    end

    recovering = false
    getOff()
    ClearPedTasks(cache.ped)
end

RegisterNetEvent('cobalt_ambulancejob:client:recover', function(hospitalId, index, seconds)
    if type(hospitalId) ~= 'string' or type(seconds) ~= 'number' then return end

    recover(hospitalId, index, seconds)
end)

RegisterNetEvent('cobalt_ambulancejob:client:discharged', function()
    if recovering then return end

    getOff()
end)

AddStateBagChangeHandler('revive', ('player:%s'):format(cache.serverId), function(_, _, value)
    if onBed and value and value.state ~= REVIVE.ALIVE then
        SetTimeout(0, getOff)
    end
end)

RegisterNetEvent('cobalt_core:Client:OnPlayerUnload', function()
    recovering = false
    getOff()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    getOff()

    for _, ped in pairs(doctors) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end

    for _, blip in ipairs(blips) do
        RemoveBlip(blip)
    end
end)
