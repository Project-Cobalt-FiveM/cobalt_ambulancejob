local config <const> = require 'config'
local states <const> = require 'shared.states'
local hospitals <const> = require 'shared.hospitals'
local medics <const> = require 'server.medics'
local state <const> = require 'server.state'

local BED_RANGE <const> = 3.0
local LEFT_BED_RANGE <const> = 10.0
local SETTLE_SECONDS <const> = 15

---@alias BedUse 'checkIn'|'medic'|'rest'

---@class BedOccupant
---@field source integer
---@field hospital string
---@field index integer
---@field citizenid string
---@field name string
---@field since integer epoch seconds
---@field use BedUse
---@field treating boolean true while a check-in treatment runs, which the patient can't get up from

---@class BedView
---@field index integer
---@field label string
---@field occupant? { citizenid: string, name: string, since: integer, use: BedUse, state: ReviveStateName }

---@class HospitalBeds
---@field id string
---@field label string
---@field short string
---@field total integer
---@field occupied integer
---@field beds BedView[]

local Beds <const> = {}

---@type table<integer, BedOccupant>
local occupants <const> = {}

---@param hospitalId string
---@param index integer
---@return Bed?
local function usableBed(hospitalId, index)
    local bed <const> = hospitals.get(hospitalId)?.beds[index]

    if bed?.coords and bed.exit then return bed end
end

---@param hospitalId string
---@param index integer
---@return BedOccupant?
local function occupantAt(hospitalId, index)
    for _, occupant in pairs(occupants) do
        if occupant.hospital == hospitalId and occupant.index == index then return occupant end
    end
end

---@param source integer
local function vacate(source)
    occupants[source] = nil

    if DoesPlayerExist(source --[[@as string]]) then
        Player(source).state:set('bed', nil, true)
    end
end

---@param occupant BedOccupant
---@return boolean
local function stillInBed(occupant)
    local ped <const> = GetPlayerPed(occupant.source)
    local bed <const> = usableBed(occupant.hospital, occupant.index) --[[@as Bed]]

    return ped ~= 0 and #(GetEntityCoords(ped) - bed.coords.xyz) <= LEFT_BED_RANGE
end

local function prune()
    local now <const> = os.time()

    for source, occupant in pairs(occupants) do
        if now - occupant.since >= SETTLE_SECONDS and not stillInBed(occupant) then
            vacate(source)
        end
    end
end

---@param occupant BedOccupant
---@return table
local function occupantView(occupant)
    return {
        citizenid = occupant.citizenid,
        name = occupant.name,
        since = occupant.since,
        use = occupant.use,
        state = state.revive(occupant.source).state,
    }
end

---Every enabled hospital's usable beds and who lies in each.
---@return HospitalBeds[]
function Beds.overview()
    prune()

    local out <const> = {}

    for i, hospital in ipairs(hospitals.list()) do
        local views <const> = {}
        local occupied = 0

        for index, bed in ipairs(hospital.beds) do
            if usableBed(hospital.id, index) then
                local occupant <const> = occupantAt(hospital.id, index)

                if occupant then occupied += 1 end

                views[#views + 1] = { index = index, label = bed.label, occupant = occupant and occupantView(occupant) }
            end
        end

        out[i] = {
            id = hospital.id,
            label = hospital.label,
            short = hospital.short,
            total = #views,
            occupied = occupied,
            beds = views,
        }
    end

    return out
end

local function broadcast()
    local overview <const> = Beds.overview()

    for _, medic in ipairs(exports.cobalt_core:GetPlayersByJob(config.job, true)) do
        TriggerClientEvent('cobalt_ambulancejob:client:bedsChanged', medic, overview)
    end
end

---@param hospitalId string
---@param index integer
---@return boolean
local function isFree(hospitalId, index)
    return usableBed(hospitalId, index) ~= nil and not occupantAt(hospitalId, index)
end

---@param hospitalId string
---@param index integer
---@return boolean
function Beds.isFree(hospitalId, index)
    prune()

    return isFree(hospitalId, index)
end

---@param hospital Hospital
---@return integer? index
function Beds.firstFree(hospital)
    prune()

    for index in ipairs(hospital.beds) do
        if isFree(hospital.id, index) then return index end
    end
end

---@param source integer
---@param hospitalId string
---@param index integer
---@return boolean
function Beds.near(source, hospitalId, index)
    local bed <const> = usableBed(hospitalId, index)
    local ped <const> = GetPlayerPed(source)

    return bed ~= nil and ped ~= 0 and #(GetEntityCoords(ped) - bed.coords.xyz) <= BED_RANGE
end

---Lays the player in a free bed through their `bed` state bag, which their client follows.
---@param source integer
---@param hospitalId string
---@param index integer
---@param use BedUse
---@return BedOccupant? occupant nil when the bed is taken or unusable, or the player is already in one
function Beds.occupy(source, hospitalId, index, use)
    local citizenid <const> = medics.citizenid(source)

    if not citizenid or occupants[source] or not Beds.isFree(hospitalId, index) then return end

    local occupant <const> = {
        source = source,
        hospital = hospitalId,
        index = index,
        citizenid = citizenid,
        name = medics.name(source),
        since = os.time(),
        use = use,
        treating = false,
    }

    occupants[source] = occupant
    Player(source).state:set('bed', { hospital = hospitalId, index = index }, true)
    broadcast()

    return occupant
end

---@param source integer
---@return BedOccupant?
function Beds.occupantOf(source)
    return occupants[source]
end

---@param source integer
function Beds.release(source)
    if not occupants[source] then return end

    vacate(source)
    broadcast()
end

RegisterNetEvent('cobalt_ambulancejob:server:lieOnBed', function(hospitalId, index)
    local source <const> = source

    if type(hospitalId) ~= 'string' or math.type(index) ~= 'integer' then return end
    if state.revive(source).state ~= states.revive.ALIVE or Player(source).state.cuffed then return end
    if (Player(source).state.fireCarry?.state or states.carry.NONE) ~= states.carry.NONE then return end

    if not Beds.near(source, hospitalId, index) then
        return medics.notify(source, locale('beds.get_closer'), 'error')
    end

    if not Beds.occupy(source, hospitalId, index, 'rest') then
        medics.notify(source, locale('beds.taken'), 'error')
    end
end)

RegisterNetEvent('cobalt_ambulancejob:server:leaveBed', function()
    local occupant <const> = occupants[source]

    if not occupant or occupant.treating then return end

    Beds.release(source)
end)

AddEventHandler('cobalt_core:Server:OnPlayerUnload', Beds.release)

AddEventHandler('playerDropped', function()
    if not occupants[source] then return end

    occupants[source] = nil
    broadcast()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    for source in pairs(occupants) do vacate(source) end
end)

return Beds
