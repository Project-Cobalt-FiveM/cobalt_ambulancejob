local config <const> = require 'config'
local states <const> = require 'shared.states'
local medics <const> = require 'server.medics'
local hospitals <const> = require 'shared.hospitals'
local state <const> = require 'server.state'
local beds <const> = require 'server.beds'
local billing <const> = require 'server.billing'
local records <const> = require 'server.records'

local DESK_RANGE <const> = 3.0
local PROGRESS_GRACE_MS <const> = 500

---@class PendingCheckIn
---@field hospital string
---@field startedAt integer

---@type table<integer, PendingCheckIn>
local pendingCheckIns <const> = {}

---@type table<integer, integer> medic source to the vehicle they last took out
local spawnedVehicles <const> = {}

RegisterNetEvent('cobalt_ambulancejob:server:spawnVehicle', function(hospitalId, model)
    local source <const> = source
    local spawner <const> = hospitals.get(hospitalId)?.spawner

    if not spawner or not medics.isOnDuty(source) then return end

    if #(GetEntityCoords(GetPlayerPed(source)) - spawner.coords) > 10.0 then return end

    for _, vehicle in ipairs(spawner.vehicles) do
        if vehicle.model == model then
            local previous <const> = spawnedVehicles[source]

            if previous and DoesEntityExist(previous) then DeleteEntity(previous) end

            spawnedVehicles[source] = exports.cobalt_core:SpawnVehicle(source, model, spawner.spawnCoords, true)
            return
        end
    end
end)

---@return boolean
local function checkInClosed()
    local checkIn <const> = config.checkIn

    return checkIn.disableWhenEmsOnDuty and exports.cobalt_management:GetDutyCount(config.job) >= checkIn.minEmsOnDuty
end

---@param source integer
---@param hospital Hospital
---@return boolean
local function atDesk(source, hospital)
    local point <const> = hospital.checkIn or hospital.doctor?.coords.xyz

    return point ~= nil and #(GetEntityCoords(GetPlayerPed(source)) - point) <= DESK_RANGE
end

---@param source integer
---@param citizenid string
---@param hospital Hospital
---@param injuries { bodyPart: BodyPart, kind: InjuryKind }[]
local function billTreatment(source, citizenid, hospital, injuries)
    local fee <const> = config.checkIn.fee
    local draft <const> = records.cleanDraft({
        citizenid = citizenid,
        patientName = medics.name(source),
        injuries = injuries,
        narrative = locale('hospital.front_desk_narrative', hospital.label),
        outcome = 'scene',
    })

    local frontDesk <const> = locale('records.front_desk')
    local reportId <const> = records.saveReport(draft, nil, frontDesk, 'filed')

    if fee <= 0 or not reportId then return end

    local invoice <const> = billing.create({
        citizenid = citizenid,
        patientName = draft.patientName,
        lines = { { label = locale('hospital.check_in_fee'), amount = fee } },
        reportId = reportId,
        summary = locale('hospital.front_desk_invoice', reportId),
        issuerName = frontDesk,
    })

    if not invoice then return end

    records.markBilled(reportId, fee)

    if not billing.pay(invoice.id) then
        medics.notify(source, locale('respawn.owe', fee), 'warning')
    end
end

---@param source integer
---@param hospital Hospital
---@param occupant BedOccupant
local function finishTreatment(source, hospital, occupant)
    if beds.occupantOf(source) ~= occupant then return end

    local citizenid <const> = medics.citizenid(source)
    local injuries <const> = state.injuryList(source)

    occupant.treating = false

    if state.revive(source).state ~= states.revive.ALIVE then
        state.setRevive(source, states.revive.ALIVE)
    end

    state.clearInjuries(source)
    TriggerClientEvent('cobalt_ambulancejob:client:bedTreatmentDone', source)
    medics.notify(source, locale('hospital.front_desk_done'), 'success')

    if citizenid then billTreatment(source, citizenid, hospital, injuries) end
end

---@param source integer
---@param hospital Hospital
---@return boolean
local function treatInBed(source, hospital)
    local seconds <const> = config.checkIn.treatmentSeconds
    local index <const> = beds.firstFree(hospital)
    local occupant <const> = index and beds.occupy(source, hospital.id, index, 'checkIn')

    if not occupant then
        medics.notify(source, locale('hospital.beds_full'), 'error')
        return false
    end

    occupant.treating = true

    if state.revive(source).state ~= states.revive.ALIVE then
        state.setRevive(source, states.revive.ALIVE)
    end

    TriggerClientEvent('cobalt_ambulancejob:client:bedTreatment', source, seconds)
    SetTimeout(seconds * 1000, function() finishTreatment(source, hospital, occupant) end)

    return true
end

lib.callback.register('cobalt_ambulancejob:checkInStart', function(source, hospitalId)
    local hospital <const> = type(hospitalId) == 'string' and hospitals.get(hospitalId)

    if not hospital or not atDesk(source, hospital) or beds.occupantOf(source) then return false end

    if checkInClosed() then
        medics.notify(source, locale('hospital.medics_on_duty'))
        return false
    end

    pendingCheckIns[source] = { hospital = hospital.id, startedAt = GetGameTimer() }

    return true, config.checkIn.checkInSeconds
end)

lib.callback.register('cobalt_ambulancejob:checkInFinish', function(source)
    local pending <const> = pendingCheckIns[source]

    pendingCheckIns[source] = nil

    if not pending then return false end

    local minimum <const> = config.checkIn.checkInSeconds * 1000 - PROGRESS_GRACE_MS

    if GetGameTimer() - pending.startedAt < minimum then return false end

    local hospital <const> = hospitals.get(pending.hospital) --[[@as Hospital]]

    if not atDesk(source, hospital) then return false end

    if checkInClosed() then
        medics.notify(source, locale('hospital.medics_on_duty'))
        return false
    end

    return treatInBed(source, hospital)
end)

lib.callback.register('cobalt_ambulancejob:checkInCancel', function(source)
    pendingCheckIns[source] = nil
end)

---@param vehicle integer
---@return boolean
local function occupied(vehicle)
    for _, playerId in ipairs(GetPlayers()) do
        if GetVehiclePedIsIn(GetPlayerPed(playerId), false) == vehicle then return true end
    end

    return false
end

---@param vehicle? integer
local function returnVehicle(vehicle)
    if vehicle and DoesEntityExist(vehicle) and not occupied(vehicle) then DeleteEntity(vehicle) end
end

AddEventHandler('playerDropped', function()
    returnVehicle(spawnedVehicles[source])
    spawnedVehicles[source] = nil
    pendingCheckIns[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    for _, vehicle in pairs(spawnedVehicles) do returnVehicle(vehicle) end
end)
