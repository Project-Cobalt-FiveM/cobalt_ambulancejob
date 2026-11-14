local catalog <const> = require 'server.catalog'

---@class CareEntry
---@field bodyPart? BodyPart
---@field kind? InjuryKind
---@field treatmentId integer
---@field medic string citizenid
---@field at integer

---@class CareSession
---@field injuries { bodyPart: BodyPart, kind: InjuryKind }[]
---@field entries CareEntry[]
---@field callId? integer
---@field startedAt integer

local SESSION_SECONDS <const> = 3 * 3600
local PRUNE_MS <const> = 15 * 60000

local Care <const> = {}

---@type table<string, CareSession>
local sessions <const> = {}

---@param current CareSession
---@return boolean
local function expired(current)
    return os.time() - current.startedAt >= SESSION_SECONDS
end

---@param citizenid string
---@return CareSession?
function Care.get(citizenid)
    local current <const> = sessions[citizenid]

    if not current then return end

    if expired(current) then
        sessions[citizenid] = nil
        return
    end

    return current
end

---@param citizenid string
---@return CareSession
local function session(citizenid)
    local current <const> = Care.get(citizenid)

    if current then return current end

    sessions[citizenid] = { injuries = {}, entries = {}, startedAt = os.time() }

    return sessions[citizenid]
end

---@param citizenid string
---@param bodyPart BodyPart
---@param kind InjuryKind
function Care.noteInjury(citizenid, bodyPart, kind)
    local injuries <const> = session(citizenid).injuries

    for _, injury in ipairs(injuries) do
        if injury.bodyPart == bodyPart and injury.kind == kind then return end
    end

    injuries[#injuries + 1] = { bodyPart = bodyPart, kind = kind }
end

---@param citizenid string
---@param medic string
---@param item string
---@param bodyPart? BodyPart
---@param kind? InjuryKind
function Care.noteItem(citizenid, medic, item, bodyPart, kind)
    local treatment <const> = catalog.byItem(item)

    if not treatment then return end

    local entries <const> = session(citizenid).entries

    entries[#entries + 1] = {
        bodyPart = bodyPart,
        kind = kind,
        treatmentId = treatment.id,
        medic = medic,
        at = os.time(),
    }
end

---@param citizenid string
---@param medic string
---@param name string
function Care.noteProcedure(citizenid, medic, name)
    local treatment <const> = catalog.byName(name)

    if not treatment then return end

    local entries <const> = session(citizenid).entries

    for _, entry in ipairs(entries) do
        if entry.treatmentId == treatment.id then return end
    end

    entries[#entries + 1] = { treatmentId = treatment.id, medic = medic, at = os.time() }
end

---@param citizenid string
---@param callId integer
function Care.linkCall(citizenid, callId)
    session(citizenid).callId = callId
end

---@param citizenid string
function Care.clear(citizenid)
    sessions[citizenid] = nil
end

SetInterval(function()
    for citizenid, current in pairs(sessions) do
        if expired(current) then
            sessions[citizenid] = nil
        end
    end
end, PRUNE_MS)

return Care
