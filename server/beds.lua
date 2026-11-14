local config <const> = require 'config'
local medics <const> = require 'server.medics'
local hospitals <const> = require 'shared.hospitals'

---@class WaitingPatient
---@field id integer
---@field citizenid string
---@field name string
---@field reason string
---@field since integer
---@field hospital string
---@field source integer

local Beds <const> = {}

---@class BedReservation
---@field hospital string
---@field bed integer
---@field token integer
---@field citizenid string
---@field patientName string
---@field endsAt integer os.time when the front-desk treatment ends

---@type WaitingPatient[]
local waiting <const> = {}

---@type table<integer, BedReservation>
local reservations <const> = {}

local nextToken = 0

local nextWaitingId = 1

local SELECT <const> = [[
    SELECT a.id, a.citizenid, p.fullname, a.hospital, a.bed, a.reason, a.attending, a.report_id, a.notes,
        UNIX_TIMESTAMP(a.admitted_at) AS admitted_at, UNIX_TIMESTAMP(a.planned_discharge_at) AS planned_discharge_at,
        UNIX_TIMESTAMP(a.discharged_at) AS discharged_at
    FROM ems_admissions a LEFT JOIN players p ON p.citizenid = a.citizenid
]]

---@param id string
---@return Hospital?
function Beds.hospital(id)
    return hospitals.get(id)
end

local function broadcastChange()
    for _, medic in ipairs(exports.cobalt_core:GetPlayersByJob(config.job, true)) do
        TriggerClientEvent('cobalt_ambulancejob:client:bedsChanged', medic)
    end
end

---@param hospitalId string
---@param bed integer
---@return { citizenid: string, patientName: string, endsAt: integer }?
local function frontDeskAt(hospitalId, bed)
    for _, reservation in pairs(reservations) do
        if reservation.hospital == hospitalId and reservation.bed == bed then
            return {
                citizenid = reservation.citizenid,
                patientName = reservation.patientName,
                endsAt = reservation.endsAt,
            }
        end
    end
end

---@param row table
---@return table
local function format(row)
    return {
        id = row.id,
        citizenid = row.citizenid,
        patientName = row.fullname or locale('common.unknown'),
        hospital = row.hospital,
        bed = row.bed,
        reason = row.reason,
        attending = row.attending,
        admittedAt = row.admitted_at,
        plannedDischargeAt = row.planned_discharge_at,
        reportId = row.report_id,
        notes = row.notes,
        dischargedAt = row.discharged_at,
    }
end

---@return table[]
function Beds.current()
    local out <const> = {}

    for i, row in ipairs(MySQL.query.await(SELECT .. ' WHERE a.discharged_at IS NULL') or {}) do
        out[i] = format(row)
    end

    return out
end

---@param citizenid string
---@return table[]
function Beds.history(citizenid)
    local rows <const> = MySQL.query.await(
        SELECT .. ' WHERE a.citizenid = ? ORDER BY a.id DESC LIMIT 50',
        { citizenid }
    )
    local out <const> = {}

    for i, row in ipairs(rows or {}) do
        out[i] = format(row)
    end

    return out
end

---@return table hospitals
function Beds.overview()
    local byBed <const> = {}

    for _, admission in ipairs(Beds.current()) do
        byBed[('%s:%d'):format(admission.hospital, admission.bed)] = admission
    end

    local overview <const> = {}

    for i, hospital in ipairs(hospitals.list()) do
        local beds <const> = {}

        for index, bed in ipairs(hospital.beds) do
            local admission <const> = byBed[('%s:%d'):format(hospital.id, index)]

            beds[index] = {
                index = index,
                label = bed.label,
                admission = admission,
                frontDesk = not admission and frontDeskAt(hospital.id, index) or nil,
            }
        end

        overview[i] = { id = hospital.id, label = hospital.label, short = hospital.short, beds = beds }
    end

    return overview
end

---@return { id: string, label: string, free: integer, total: integer, admitted: integer }[]
function Beds.capacity()
    local out <const> = {}

    for i, hospital in ipairs(Beds.overview()) do
        local admitted = 0

        for _, bed in ipairs(hospital.beds) do
            if bed.admission or bed.frontDesk then admitted += 1 end
        end

        out[i] = {
            id = hospital.id,
            label = hospital.label,
            free = #hospital.beds - admitted,
            total = #hospital.beds,
            admitted = admitted,
        }
    end

    return out
end

---@param hospitalId string
---@param bed integer
---@return boolean
local function bedExists(hospitalId, bed)
    local hospital <const> = Beds.hospital(hospitalId)

    return hospital ~= nil and hospital.beds[bed] ~= nil
end

---@param hospitalId string
---@param bed integer
---@return boolean
local function isReserved(hospitalId, bed)
    for _, reservation in pairs(reservations) do
        if reservation.hospital == hospitalId and reservation.bed == bed then return true end
    end

    return false
end

---@param citizenid string
---@param hospitalId string
---@param bed integer
---@param recoverSeconds? integer
local function placeOnBed(citizenid, hospitalId, bed, recoverSeconds)
    local source <const> = medics.sourceOf(citizenid)

    if not source or not Beds.hospital(hospitalId)?.beds[bed]?.coords then return end

    if recoverSeconds then
        return TriggerClientEvent('cobalt_ambulancejob:client:recover', source, hospitalId, bed, recoverSeconds)
    end

    TriggerClientEvent('cobalt_ambulancejob:client:admitted', source, hospitalId, bed)
end

---@param data table
---@param attending string
---@param recoverSeconds? integer
---@return integer? id
---@return string? error
function Beds.admit(data, attending, recoverSeconds)
    local citizenid <const> = type(data.citizenid) == 'string' and data.citizenid or nil
    local bed <const> = math.tointeger(tonumber(data.bed))

    if not citizenid then return nil, locale('beds.pick_patient') end

    if not bed or not bedExists(data.hospital, bed) then return nil, locale('beds.pick_free_bed') end
    if isReserved(data.hospital, bed) then return nil, locale('beds.taken_or_admitted') end

    local hours <const> = math.max(0, tonumber(data.dischargeHours) or 0)
    local id

    local committed <const> = MySQL.startTransaction(function(query)
        local taken <const> = query([[
            SELECT COUNT(*) AS n FROM ems_admissions
            WHERE discharged_at IS NULL AND ((hospital = ? AND bed = ?) OR citizenid = ?) FOR UPDATE
        ]], { data.hospital, bed, citizenid })

        if taken[1].n > 0 then return false end

        id = query([[
            INSERT INTO ems_admissions (citizenid, hospital, bed, reason, attending, report_id, planned_discharge_at)
            VALUES (?, ?, ?, ?, ?, NULLIF(?, 0), IF(? = 0, NULL, DATE_ADD(NOW(), INTERVAL ? HOUR)))
        ]], {
            citizenid,
            data.hospital,
            bed,
            tostring(data.reason or ''):sub(1, 160),
            attending,
            math.tointeger(tonumber(data.reportId)) or 0,
            hours,
            hours,
        }).insertId

        return true
    end)

    if not committed then return nil, locale('beds.taken_or_admitted') end

    placeOnBed(citizenid, data.hospital, bed, recoverSeconds)
    broadcastChange()

    return id
end

---@param id integer
---@return boolean
function Beds.discharge(id)
    local changed <const> = MySQL.update.await(
        'UPDATE ems_admissions SET discharged_at = NOW() WHERE id = ? AND discharged_at IS NULL',
        { id }
    )

    if changed == 0 then return false end

    local citizenid <const> = MySQL.scalar.await('SELECT citizenid FROM ems_admissions WHERE id = ?', { id })
    local source <const> = medics.sourceOf(citizenid)

    if source then
        TriggerClientEvent('cobalt_ambulancejob:client:discharged', source)
    end

    broadcastChange()

    return true
end

---@param hospital Hospital
---@return integer?
local function freeBed(hospital)
    local taken <const> = {}

    for _, admission in ipairs(Beds.current()) do
        if admission.hospital == hospital.id then
            taken[admission.bed] = true
        end
    end

    for index, bed in ipairs(hospital.beds) do
        if bed.coords and bed.exit and not taken[index] and not isReserved(hospital.id, index) then return index end
    end
end

---@param source integer
---@param hospital Hospital
---@param seconds integer how long the front-desk treatment lasts
---@return BedReservation? reservation nil when every bed is taken
function Beds.reserve(source, hospital, seconds)
    local citizenid <const> = medics.citizenid(source)

    if not citizenid or reservations[source] then return end

    local bed <const> = freeBed(hospital)

    if not bed or reservations[source] then return end

    nextToken += 1
    reservations[source] = {
        hospital = hospital.id,
        bed = bed,
        token = nextToken,
        citizenid = citizenid,
        patientName = medics.name(source),
        endsAt = os.time() + seconds,
    }

    broadcastChange()

    return reservations[source]
end

---@param source integer
---@return BedReservation?
function Beds.reservation(source)
    return reservations[source]
end

---@param source integer
function Beds.release(source)
    if not reservations[source] then return end

    reservations[source] = nil
    broadcastChange()
end

---@param source integer
---@param attending string
---@return boolean admitted false when every bed with coords is taken
function Beds.recover(source, attending)
    local citizenid <const> = medics.citizenid(source)
    local ped <const> = GetPlayerPed(source)

    if not citizenid or ped == 0 then return false end

    local hospital <const> = hospitals.nearest(GetEntityCoords(ped))
    local seconds <const> = config.recovery.seconds
    local bed <const> = freeBed(hospital)
    local id <const> = bed and Beds.admit({
        citizenid = citizenid,
        hospital = hospital.id,
        bed = bed,
        reason = locale('beds.recovery_reason'),
    }, attending, seconds)

    if not id then
        TriggerClientEvent('cobalt_ambulancejob:client:recover', source, hospital.id, nil, seconds)
        medics.notify(source, locale('beds.no_free_bed', hospital.short))

        return false
    end

    SetTimeout((seconds + 2) * 1000, function() Beds.discharge(id) end)

    return true
end

---@param id integer
---@param hospitalId string
---@param bed integer
---@return boolean ok
---@return string? error
function Beds.move(id, hospitalId, bed)
    if not bedExists(hospitalId, bed) then return false, locale('beds.pick_free_bed') end
    if isReserved(hospitalId, bed) then return false, locale('beds.taken') end

    local citizenid

    local committed <const> = MySQL.startTransaction(function(query)
        local taken <const> = query([[
            SELECT COUNT(*) AS n FROM ems_admissions
            WHERE discharged_at IS NULL AND hospital = ? AND bed = ? FOR UPDATE
        ]], { hospitalId, bed })

        if taken[1].n > 0 then return false end

        local moved <const> = query(
            'UPDATE ems_admissions SET hospital = ?, bed = ? WHERE id = ? AND discharged_at IS NULL',
            { hospitalId, bed, id }
        )

        if moved.affectedRows == 0 then return false end

        citizenid = query('SELECT citizenid FROM ems_admissions WHERE id = ?', { id })[1].citizenid

        return true
    end)

    if not committed then return false, locale('beds.taken') end

    placeOnBed(citizenid, hospitalId, bed)
    broadcastChange()

    return true
end

---@param id integer
---@param notes string
---@return boolean
function Beds.saveNotes(id, notes)
    return MySQL.update.await('UPDATE ems_admissions SET notes = ? WHERE id = ?', { notes:sub(1, 2000), id }) > 0
end

---@return WaitingPatient[]
function Beds.waiting()
    local out <const> = {}

    for i, entry in ipairs(waiting) do
        out[i] = {
            id = entry.id,
            citizenid = entry.citizenid,
            name = entry.name,
            reason = entry.reason,
            since = entry.since,
        }
    end

    return out
end

---@param source integer
---@param hospitalId string
---@param reason string
---@return boolean
function Beds.checkIn(source, hospitalId, reason)
    local citizenid <const> = medics.citizenid(source)

    if not citizenid then return false end

    for _, entry in ipairs(waiting) do
        if entry.citizenid == citizenid then return false end
    end

    waiting[#waiting + 1] = {
        id = nextWaitingId,
        citizenid = citizenid,
        name = medics.name(source),
        reason = reason,
        since = os.time(),
        hospital = hospitalId,
        source = source,
    }

    nextWaitingId += 1

    local message <const> = locale('beds.patient_checked_in', medics.name(source), Beds.hospital(hospitalId)?.short or hospitalId)

    for _, medic in ipairs(exports.cobalt_core:GetPlayersByJob(config.job, true)) do
        medics.notify(medic, message)
    end

    return true
end

---@param id integer
---@return WaitingPatient?
function Beds.see(id)
    for i, entry in ipairs(waiting) do
        if entry.id == id then
            table.remove(waiting, i)
            medics.notify(entry.source, locale('beds.medic_coming'))

            return entry
        end
    end
end

---@param source integer
local function forget(source)
    Beds.release(source)

    for i = #waiting, 1, -1 do
        if waiting[i].source == source then
            table.remove(waiting, i)
        end
    end
end

AddEventHandler('playerDropped', function()
    forget(source)
end)

AddEventHandler('cobalt_core:Server:OnPlayerUnload', forget)

CreateThread(function()
    MySQL.update.await(
        'UPDATE ems_admissions SET discharged_at = NOW() WHERE discharged_at IS NULL AND reason = ?',
        { locale('beds.recovery_reason') }
    )
end)

return Beds
