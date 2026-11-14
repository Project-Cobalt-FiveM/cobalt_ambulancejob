local medics <const> = require 'server.medics'
local state <const> = require 'server.state'
local care <const> = require 'server.care'

local Dispatch <const> = {}

---@type table<integer, string>
local patients <const> = {}

---@type integer?
local lastClosedAt

---@param calls PoliceCall[]
---@return table<string, string>
local function bloodTypes(calls)
    local ids <const> = {}

    for _, call in ipairs(calls) do
        ids[#ids + 1] = patients[call.id]
    end

    return exports.cobalt_core:GetMetaData(ids, 'bloodtype')
end

---@param citizenid string
---@param bloodType? string
---@return table
local function patientOf(citizenid, bloodType)
    local source <const> = medics.sourceOf(citizenid)
    local player <const> = source and medics.player(source)

    if not source or not player then
        return {
            citizenid = citizenid,
            name = locale('common.unknown'),
            bloodType = bloodType,
            state = 'alive',
            injuries = {},
        }
    end

    return {
        citizenid = citizenid,
        name = medics.name(source),
        bloodType = bloodType,
        state = state.revive(source).state,
        bleedsOutAt = state.bleedsOutAt(source),
        injuries = state.injuryList(source),
    }
end

---@param call PoliceCall
---@param types table<string, string>
---@return table
local function enrich(call, types)
    local out <const> = table.clone(call) --[[@as table]]
    local citizenid <const> = patients[call.id]

    out.jobs = nil
    out.blip = nil
    out.coords = call.coords and { x = call.coords.x, y = call.coords.y, z = call.coords.z } or nil
    out.patient = citizenid and patientOf(citizenid, types[citizenid]) or nil

    return out
end

---@param source integer
---@return table[]
function Dispatch.calls(source)
    local calls <const> = {}

    for _, call in ipairs(exports.cobalt_police:GetCalls(source)) do
        if lib.table.contains(call.jobs, 'ems') then
            calls[#calls + 1] = call
        end
    end

    local types <const> = bloodTypes(calls)

    for i, call in ipairs(calls) do
        calls[i] = enrich(call, types)
    end

    return calls
end

---@param id integer
---@return PoliceCall?
function Dispatch.get(id)
    local call <const> = exports.cobalt_police:GetCall(id)

    if call and lib.table.contains(call.jobs, 'ems') then return call end
end

---@param id integer
---@return table?
function Dispatch.call(id)
    local call <const> = Dispatch.get(id)

    return call and enrich(call, bloodTypes({ call }))
end

---@param source integer
---@param urgent boolean
---@return integer?
function Dispatch.requestEms(source, urgent)
    local citizenid <const> = medics.citizenid(source)
    local ped <const> = GetPlayerPed(source)

    if not citizenid or ped == 0 then return end

    for callId, patient in pairs(patients) do
        local call <const> = Dispatch.get(callId)

        if patient == citizenid and call?.status == 'open' then
            return callId
        end
    end

    local id <const> = exports.cobalt_police:SendDispatch({
        code = urgent and 'P1' or 'P2',
        title = urgent and locale('dispatch.patient_down_critical') or locale('dispatch.patient_down'),
        description = locale('dispatch.requested_while_down'),
        coords = GetEntityCoords(ped),
        priority = urgent and 1 or 2,
        jobs = { 'ems' },
        blip = 'medical',
        raisedBy = locale('dispatch.raised_by_patient'),
    })

    if id then
        patients[id] = citizenid
        care.linkCall(citizenid, id)
    end

    return id
end

---@param id integer
---@return boolean
function Dispatch.close(id)
    local closed <const> = exports.cobalt_police:CloseCall(id)

    if closed then
        lastClosedAt = os.time()
    end

    return closed
end

---@return integer?
function Dispatch.lastClosedAt()
    return lastClosedAt
end

---@param source integer
---@param id integer
---@return boolean
function Dispatch.respond(source, id)
    if not exports.cobalt_police:RespondToCall(source, id) then return false end

    medics.setStatus(source, 'enroute')

    return true
end

AddEventHandler('cobalt_police:dispatchSent', function(call)
    if call.status ~= 'open' then return end

    for id in pairs(patients) do
        if not Dispatch.get(id) then
            patients[id] = nil
        end
    end
end)

return Dispatch
