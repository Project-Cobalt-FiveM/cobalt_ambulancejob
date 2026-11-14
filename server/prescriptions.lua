local config <const> = require 'config'

local Prescriptions <const> = {}

local SELECT <const> = [[
    SELECT rx.id, rx.citizenid, p.fullname, rx.medication, rx.dose, rx.reason, rx.refills, rx.fills,
        rx.last_pharmacy, UNIX_TIMESTAMP(rx.last_filled_at) AS last_filled_at, rx.controlled, rx.prescriber_name,
        rx.status, UNIX_TIMESTAMP(rx.ends_at) AS ends_at, UNIX_TIMESTAMP(rx.created_at) AS created_at
    FROM ems_prescriptions rx LEFT JOIN players p ON p.citizenid = rx.citizenid
]]

---@param rows table[]
---@return table[]
local function format(rows)
    local out <const> = {}
    local now <const> = os.time()

    for i, row in ipairs(rows) do
        out[i] = {
            id = row.id,
            citizenid = row.citizenid,
            patientName = row.fullname or locale('common.unknown'),
            medication = row.medication,
            dose = row.dose,
            reason = row.reason,
            refills = row.refills,
            refillsUsed = math.max(0, row.fills - 1),
            controlled = row.controlled == 1 or row.controlled == true,
            prescriber = row.prescriber_name,
            createdAt = row.created_at,
            endsAt = row.ends_at,
            status = row.status == 'active' and row.ends_at < now and 'expired' or row.status,
            lastFill = row.last_filled_at and { pharmacy = row.last_pharmacy, at = row.last_filled_at },
        }
    end

    return out
end

---@param citizenid string
---@return table[]
function Prescriptions.list(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return {} end

    return format(MySQL.query.await(SELECT .. ' WHERE rx.citizenid = ? ORDER BY rx.id DESC', { citizenid }) or {})
end

---@return table[]
function Prescriptions.recent()
    return format(MySQL.query.await(SELECT .. ' ORDER BY rx.id DESC LIMIT 500') or {})
end

---@param data table
---@param prescriber string citizenid
---@param prescriberName string
---@param canControl boolean
---@return integer? id
---@return string? error
function Prescriptions.create(data, prescriber, prescriberName, canControl)
    local citizenid <const> = type(data.citizenid) == 'string' and data.citizenid or nil
    local medication <const> = type(data.medication) == 'string' and data.medication:sub(1, 120) or ''

    if not citizenid then return nil, locale('mdt.pick_patient') end

    if medication == '' then return nil, locale('prescriptions.name_medication') end

    if data.controlled == true and not canControl then
        return nil, locale('prescriptions.no_controlled')
    end

    local days <const> = math.max(1, math.min(365, math.floor(tonumber(data.days) or config.mdt.prescriptionDays)))

    return MySQL.insert.await([[
        INSERT INTO ems_prescriptions
            (citizenid, medication, dose, reason, refills, controlled, prescriber_citizenid, prescriber_name, ends_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? DAY))
    ]], {
        citizenid,
        medication,
        tostring(data.dose or ''):sub(1, 160),
        tostring(data.reason or ''):sub(1, 160),
        math.max(0, math.min(12, math.floor(tonumber(data.refills) or 0))),
        data.controlled == true,
        prescriber,
        prescriberName,
        days,
    })
end

---@param id integer
---@return boolean
function Prescriptions.renew(id)
    return MySQL.update.await([[
        UPDATE ems_prescriptions SET status = 'active', fills = 0, ends_at = DATE_ADD(NOW(), INTERVAL ? DAY)
        WHERE id = ? AND status = 'active'
    ]], { config.mdt.prescriptionDays, id }) > 0
end

---@param id integer
---@return boolean
function Prescriptions.cancel(id)
    return MySQL.update.await(
        "UPDATE ems_prescriptions SET status = 'cancelled' WHERE id = ? AND status = 'active'",
        { id }
    ) > 0
end

---@param citizenid string
---@param id integer
---@param pharmacy string
---@return boolean
function Prescriptions.fill(citizenid, id, pharmacy)
    return MySQL.update.await([[
        UPDATE ems_prescriptions SET fills = fills + 1, last_pharmacy = ?, last_filled_at = NOW()
        WHERE id = ? AND citizenid = ? AND status = 'active' AND ends_at > NOW() AND fills <= refills
    ]], { pharmacy:sub(1, 120), id, citizenid }) == 1
end

return Prescriptions
