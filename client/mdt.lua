local config <const> = require 'config'
local patient <const> = require 'client.patient'
local core <const> = exports.cobalt_core
local tablet <const> = require 'client.tablet'

local REQUESTS <const> = {
    'setStatus', 'search', 'getDashboard', 'getCalls', 'getDispatchSummary', 'respondCall', 'leaveCall', 'waypointCall',
    'assignCall', 'closeCall', 'markTransported', 'searchPatients', 'getPatient', 'savePatient',
    'getReports', 'getReport', 'newReport', 'saveReport', 'fileReport', 'shareReport',
    'getPrescriptions', 'createPrescription', 'renewPrescription', 'cancelPrescription',
    'getBilling', 'createInvoice', 'chargeInvoice', 'markInvoicePaid', 'voidInvoice',
    'getBeds', 'admit', 'discharge', 'moveBed', 'saveWardNotes', 'seePatient',
    'getRoster', 'saveStaff', 'getRanks', 'saveRank', 'getTreatments', 'getItems', 'saveTreatment', 'deleteTreatment',
    'getTemplates', 'saveTemplate', 'deleteTemplate', 'getSettings', 'saveSettings',
}

local Mdt <const> = { isOpen = false }

---@type table?
local latest

local respondKey, waypointKey

---@param page? string
---@param citizenid? string
function Mdt.open(page, citizenid)
    if Mdt.isOpen or patient.isIncapacitated() or LocalPlayer.state.cuffed then return end

    local session <const> = lib.callback.await('cobalt_ambulancejob:openMdt', false)

    if not session then
        return core:Notify({ description = locale('mdt.ems_only'), type = 'error' })
    end

    session.page = page
    session.citizenid = citizenid

    Mdt.isOpen = true
    tablet.hold()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = session })
end

function Mdt.close()
    if not Mdt.isOpen then return end

    Mdt.isOpen = false
    tablet.put()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

---@param call table
---@return table
local function located(call)
    local coords <const> = call.coords

    if not coords then
        call.distance = nil
        return call
    end

    call.distance = #(GetEntityCoords(cache.ped) - vec3(coords.x, coords.y, coords.z))

    if call.location ~= '' then return call end

    local street <const> = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
    local zone <const> = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))

    call.location = street ~= '' and ('%s, %s'):format(street, zone) or zone

    return call
end

for _, name in ipairs(REQUESTS) do
    RegisterNUICallback(name, function(data, cb)
        local reply <const> = lib.callback.await('cobalt_ambulancejob:mdt', false, name, data) or false

        if name == 'getCalls' and reply then
            for _, call in ipairs(reply) do
                located(call)
            end
        end

        cb(reply)
    end)
end

---@type table<string, string>?
local uiStrings

---@return table<string, string>
local function uiLocales()
    if uiStrings then return uiStrings end

    local strings <const> = {}

    for key, value in pairs(lib.getLocales()) do
        if key:sub(1, 3) == 'ui.' then strings[key] = value end
    end

    uiStrings = strings

    return strings
end

RegisterNUICallback('boot', function(_, cb)
    cb({ locales = uiLocales(), bleedoutSeconds = config.death.bleedoutSeconds })
end)

RegisterNUICallback('close', function(_, cb)
    Mdt.close()
    cb({ ok = true })
end)

---@param call table
local function clearAlert(call)
    if latest?.id ~= call.id then return end

    latest = nil
    respondKey:disable(true)
    waypointKey:disable(true)
    SendNUIMessage({ action = 'alertClear', data = { id = call.id } })
end

---@param call table
local function alert(call)
    local coords <const> = call.coords
    local distance <const> = coords and #(GetEntityCoords(cache.ped) - vec3(coords.x, coords.y, coords.z)) or 0

    latest = call
    respondKey:disable(false)
    waypointKey:disable(false)
    SendNUIMessage({
        action = 'alert',
        data = { call = call, distance = distance, seconds = config.dispatch.popupSeconds },
    })

    SetTimeout(config.dispatch.popupSeconds * 1000, function() clearAlert(call) end)
end

---@param raw table
---@param added boolean
local function forward(raw, added)
    if not lib.table.contains(raw.jobs or {}, 'ems') or not patient.isOnDutyMedic() then return end

    local call <const> = lib.callback.await('cobalt_ambulancejob:call', false, raw.id)

    if not call then return end

    located(call)

    SendNUIMessage({ action = added and 'callAdded' or 'callUpdated', data = call })

    if added and not Mdt.isOpen then
        alert(call)
    elseif call.status == 'closed' then
        clearAlert(call)
    end
end

RegisterNetEvent('cobalt_police:callAdded', function(call) forward(call, true) end)
RegisterNetEvent('cobalt_police:callUpdated', function(call) forward(call, false) end)

respondKey = lib.addKeybind({
    name = 'cobalt_ambulancejob_respond',
    description = locale('keybinds.respond'),
    defaultKey = config.dispatch.respondKey,
    disabled = true,
    onPressed = function()
        local call <const> = latest

        if not call or Mdt.isOpen then return end

        clearAlert(call)
        lib.callback.await('cobalt_ambulancejob:mdt', false, 'respondCall', { id = call.id })
        lib.callback.await('cobalt_ambulancejob:mdt', false, 'waypointCall', { id = call.id })
    end,
})

waypointKey = lib.addKeybind({
    name = 'cobalt_ambulancejob_waypoint',
    description = locale('keybinds.waypoint'),
    defaultKey = config.dispatch.waypointKey,
    disabled = true,
    onPressed = function()
        local call <const> = latest

        if not call or Mdt.isOpen then return end

        lib.callback.await('cobalt_ambulancejob:mdt', false, 'waypointCall', { id = call.id })
    end,
})

RegisterNetEvent('cobalt_ambulancejob:client:openMdt', Mdt.open)

RegisterNetEvent('cobalt_ambulancejob:client:bedsChanged', function()
    if Mdt.isOpen then SendNUIMessage({ action = 'bedsChanged' }) end
end)

RegisterNetEvent('cobalt_ambulancejob:client:waypoint', function(coords)
    SetNewWaypoint(coords.x, coords.y)
end)

RegisterNetEvent('cobalt_management:membershipChanged', function(job)
    if Mdt.isOpen and job?.name ~= config.job then
        Mdt.close()
    end
end)

AddStateBagChangeHandler('revive', ('player:%s'):format(cache.serverId), function(_, _, value)
    if Mdt.isOpen and value and value.state ~= 'alive' then
        Mdt.close()
    end
end)

AddStateBagChangeHandler('cuffed', ('player:%s'):format(cache.serverId), function(_, _, value)
    if value then Mdt.close() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == cache.resource and Mdt.isOpen then
        SetNuiFocus(false, false)
    end
end)

return Mdt
