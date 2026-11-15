local config <const> = require 'config'
local hospitals <const> = require 'shared.hospitals'
local Cobalt <const> = exports.cobalt_core:GetCoreObject()

---@alias MedicStatus 'available'|'busy'|'enroute'|'onscene'|'break'

---@class MedicJob
---@field grade integer
---@field gradeName string
---@field onDuty boolean
---@field isBoss boolean

local STATUSES <const> = { available = true, busy = true, enroute = true, onscene = true, ['break'] = true }

local Medics <const> = {}

---@param source integer
---@return MedicJob?
function Medics.job(source)
    local job <const> = exports.cobalt_management:GetJob(source)

    if not job or job.name ~= config.job then return end

    return {
        grade = job.grade.level,
        gradeName = job.grade.name,
        onDuty = job.onduty == true,
        isBoss = job.isboss == true,
    }
end

---@param source integer
---@return boolean
function Medics.isMedic(source)
    return Medics.job(source) ~= nil
end

---@param source integer
---@return boolean
function Medics.isOnDuty(source)
    return Medics.job(source)?.onDuty == true
end

---@param source integer
---@return table?
function Medics.player(source)
    return Cobalt.Functions.GetPlayer(source)
end

---@param source integer
---@return string?
function Medics.citizenid(source)
    return Medics.player(source)?.PlayerData.citizenid
end

---@param source integer
---@return string
function Medics.name(source)
    return exports.cobalt_core:GetName(source) or locale('common.unknown')
end

---@param source integer
---@return string
function Medics.callsign(source)
    local callsign <const> = Medics.player(source)?.PlayerData.metadata.callsign

    return (callsign and callsign ~= 'NO CALLSIGN') and callsign or ''
end

---@param citizenid string
---@return integer?
function Medics.sourceOf(citizenid)
    return Cobalt.Functions.GetPlayerByCitizenId(citizenid, true)?.PlayerData.source
end

---@param source integer
---@return MedicStatus
function Medics.status(source)
    return Player(source).state.emsStatus or 'available'
end

---@param source integer
---@param status string
---@return boolean
function Medics.setStatus(source, status)
    if not STATUSES[status] then return false end

    Player(source).state:set('emsStatus', status, true)

    return true
end

---@param a integer
---@param b integer
---@param range number
---@return boolean
function Medics.near(a, b, range)
    local pedA <const> = GetPlayerPed(a)
    local pedB <const> = GetPlayerPed(b)

    if pedA == 0 or pedB == 0 then return false end

    return #(GetEntityCoords(pedA) - GetEntityCoords(pedB)) <= range
end

---@param source integer
---@param description string
---@param kind? 'success'|'error'|'inform'|'warning'
function Medics.notify(source, description, kind)
    Cobalt.Functions.Notify(source, { description = description, type = kind or 'inform' })
end

---@param source integer
---@return string?
function Medics.nearestHospitalShort(source)
    local ped <const> = GetPlayerPed(source)

    if ped == 0 then return end

    local coords <const> = GetEntityCoords(ped)

    for _, hospital in ipairs(hospitals.list()) do
        if #(coords - hospital.coords) < 80.0 then
            return hospital.short
        end
    end
end

return Medics
