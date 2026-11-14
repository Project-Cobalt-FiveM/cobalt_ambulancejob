local config <const> = require 'config'
local states <const> = require 'shared.states'
local medics <const> = require 'server.medics'
local catalog <const> = require 'server.catalog'
local billing <const> = require 'server.billing'

---@alias ReportOutcome 'scene'|'transported'|'deceased'|'respawned'

---@class ReportInjury
---@field bodyPart BodyPart
---@field kind InjuryKind
---@field label string
---@field treatments integer[]
---@field treated boolean

---@class ReportDraft
---@field id? integer
---@field citizenid? string
---@field patientName string
---@field callId? integer
---@field occurredAt integer
---@field injuries ReportInjury[]
---@field medications integer[]
---@field extras integer[]
---@field narrative string
---@field outcome ReportOutcome

local OUTCOMES <const> = { scene = true, transported = true, deceased = true, respawned = true }

local Records <const> = {}

local REPORT_SELECT <const> = [[
    SELECT id, citizenid, patient_name, call_id, medic_citizenid, medic_name, injuries, medications, extras, narrative,
        summary, outcome, status, billing, billed, shared_with_police,
        UNIX_TIMESTAMP(occurred_at) AS occurred_at, UNIX_TIMESTAMP(created_at) AS created_at
    FROM ems_reports
]]

---@param row table
---@return string
local function treatmentDetail(row)
    local ids <const> = {}

    for _, injury in ipairs(json.decode(row.injuries or '[]') or {}) do
        for _, id in ipairs(injury.treatments or {}) do
            ids[#ids + 1] = id
        end
    end

    for _, column in ipairs({ row.extras, row.medications }) do
        for _, id in ipairs(json.decode(column or '[]') or {}) do
            ids[#ids + 1] = id
        end
    end

    local order <const>, counts <const> = {}, {}

    for _, id in ipairs(ids) do
        local name <const> = catalog.treatment(id)?.name

        if name then
            if not counts[name] then
                order[#order + 1] = name
            end

            counts[name] = (counts[name] or 0) + 1
        end
    end

    local parts <const> = {}

    for i, name in ipairs(order) do
        parts[i] = counts[name] > 1 and ('%s x%d'):format(name, counts[name]) or name
    end

    return table.concat(parts, ', ')
end

---@param row table
---@return table
function Records.summary(row)
    return {
        id = row.id,
        citizenid = row.citizenid,
        patientName = row.patient_name,
        summary = row.summary,
        detail = treatmentDetail(row),
        medic = row.medic_name,
        medicCitizenid = row.medic_citizenid,
        outcome = row.outcome,
        status = row.status,
        billing = row.billing,
        billed = row.billed,
        createdAt = row.created_at,
    }
end

---@param where? string
---@param params? any[]
---@param limit? integer
---@return table[]
function Records.reports(where, params, limit)
    local rows <const> = MySQL.query.await(
        REPORT_SELECT .. (where or '') .. (' ORDER BY id DESC LIMIT %d'):format(limit or 300),
        params or {}
    ) or {}
    local out <const> = {}

    for i, row in ipairs(rows) do
        out[i] = Records.summary(row)
    end

    return out
end

---@param id integer
---@return table?
function Records.reportRow(id)
    return MySQL.single.await(REPORT_SELECT .. ' WHERE id = ?', { id })
end

---@param id integer
---@return table?
function Records.report(id)
    local row <const> = Records.reportRow(id)

    if not row then return end

    local out <const> = Records.summary(row)
    local citizenid <const> = row.citizenid

    out.callId = row.call_id
    out.occurredAt = row.occurred_at
    out.injuries = json.decode(row.injuries) or {}
    out.medications = json.decode(row.medications) or {}
    out.extras = json.decode(row.extras) or {}
    out.narrative = row.narrative
    out.sharedWithPolice = row.shared_with_police == 1 or row.shared_with_police == true
    out.bloodType = citizenid and exports.cobalt_core:GetMetaData({ citizenid }, 'bloodtype')[citizenid]
    out.invoice = billing.forReport(id)

    return out
end

---@param list any
---@return integer[]
local function treatmentIds(list)
    local out <const> = {}

    for _, value in ipairs(type(list) == 'table' and list or {}) do
        local id <const> = math.tointeger(tonumber(value))

        if id and catalog.treatment(id) then
            out[#out + 1] = id
        end
    end

    return out
end

---@param data table
---@return ReportDraft
function Records.cleanDraft(data)
    local injuries <const> = {}

    for _, injury in ipairs(type(data.injuries) == 'table' and data.injuries or {}) do
        if lib.table.contains(config.bodyParts, injury.bodyPart) and states.injuryKinds[injury.kind] then
            local treatments <const> = treatmentIds(injury.treatments)

            injuries[#injuries + 1] = {
                bodyPart = injury.bodyPart,
                kind = injury.kind,
                label = type(injury.label) == 'string' and injury.label:sub(1, 60) or locale(('injuries.%s'):format(injury.kind)),
                treatments = treatments,
                treated = #treatments > 0,
            }
        end
    end

    return {
        id = math.tointeger(tonumber(data.id)),
        citizenid = type(data.citizenid) == 'string' and data.citizenid ~= '' and data.citizenid or nil,
        patientName = type(data.patientName) == 'string' and data.patientName:sub(1, 120) or '',
        callId = math.tointeger(tonumber(data.callId)),
        occurredAt = math.tointeger(tonumber(data.occurredAt)) or os.time(),
        injuries = injuries,
        medications = treatmentIds(data.medications),
        extras = treatmentIds(data.extras),
        narrative = type(data.narrative) == 'string' and data.narrative:sub(1, 6000) or '',
        outcome = OUTCOMES[data.outcome] and data.outcome or 'scene',
    }
end

---@param draft ReportDraft
---@return string
function Records.summarise(draft)
    local parts <const> = {}

    for _, injury in ipairs(draft.injuries) do
        local part <const> = locale(('body_parts.%s'):format(injury.bodyPart)):lower()

        parts[#parts + 1] = locale('records.injury_on', injury.label:lower(), part)
    end

    if #parts == 0 then
        return draft.outcome == 'respawned' and locale('records.respawn_summary') or locale('records.no_injuries')
    end

    local text <const> = table.concat(parts, ', ')

    return (text:gsub('^%l', string.upper))
end

---@param lines { label: string, amount: integer }[]
---@param ids integer[]
local function addPriced(lines, ids)
    for _, id in ipairs(ids) do
        local treatment <const> = catalog.treatment(id) --[[@as Treatment]]

        if treatment.price > 0 then
            lines[#lines + 1] = { label = treatment.name, amount = treatment.price }
        end
    end
end

---@param draft ReportDraft
---@return { label: string, amount: integer }[]
function Records.billLines(draft)
    local lines <const> = {}
    local medications, medicationTotal = 0, 0

    for _, injury in ipairs(draft.injuries) do
        addPriced(lines, injury.treatments)
    end

    addPriced(lines, draft.extras)

    for _, id in ipairs(draft.medications) do
        local treatment <const> = catalog.treatment(id) --[[@as Treatment]]

        medications += 1
        medicationTotal += treatment.price
    end

    if medicationTotal > 0 then
        lines[#lines + 1] = { label = locale('records.medications_line', medications), amount = medicationTotal }
    end

    return lines
end

---@param draft ReportDraft
---@param medic? string citizenid
---@param medicName string
---@param status 'draft'|'filed'
---@return integer? id
function Records.saveReport(draft, medic, medicName, status)
    local values <const> = {
        draft.citizenid,
        draft.patientName,
        draft.callId or 0,
        json.encode(draft.injuries),
        json.encode(draft.medications),
        json.encode(draft.extras),
        draft.narrative,
        Records.summarise(draft),
        draft.outcome,
        status,
        draft.occurredAt or os.time(),
    }

    if draft.id then
        values[12] = draft.id

        local changed <const> = MySQL.update.await([[
            UPDATE ems_reports SET citizenid = ?, patient_name = ?, call_id = NULLIF(?, 0), injuries = ?,
                medications = ?, extras = ?, narrative = ?, summary = ?, outcome = ?, status = ?,
                occurred_at = FROM_UNIXTIME(?)
            WHERE id = ? AND status = 'draft'
        ]], values)

        return changed > 0 and draft.id or nil
    end

    values[12] = medic or ''
    values[13] = medicName or ''

    return MySQL.insert.await([[
        INSERT INTO ems_reports (citizenid, patient_name, call_id, injuries, medications, extras, narrative, summary,
            outcome, status, occurred_at, medic_citizenid, medic_name)
        VALUES (?, ?, NULLIF(?, 0), ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), NULLIF(?, ''), ?)
    ]], values)
end

---@param id integer
local function waive(id)
    MySQL.update.await("UPDATE ems_reports SET billing = 'waived' WHERE id = ?", { id })
end

---@param id integer
---@param amount integer
function Records.markBilled(id, amount)
    MySQL.update.await("UPDATE ems_reports SET billing = 'billed', billed = ? WHERE id = ?", { amount, id })
end

---@param id integer
---@param draft ReportDraft
---@param sendInvoice boolean
---@param medic? string
---@return integer? invoiceId
function Records.bill(id, draft, sendInvoice, medic)
    local lines <const> = Records.billLines(draft)

    if not sendInvoice or not draft.citizenid or #lines == 0 then
        return waive(id)
    end

    local invoice <const> = billing.create({
        citizenid = draft.citizenid,
        patientName = draft.patientName,
        lines = lines,
        reportId = id,
        summary = locale('records.invoice_summary', id, Records.summarise(draft):lower()),
        medic = medic,
    })

    if not invoice then return end

    Records.markBilled(id, invoice.amount)

    return invoice.id
end

---@param source integer
---@param hospital Hospital
---@param injuries { bodyPart: BodyPart, kind: InjuryKind }[]
---@param fee integer
---@param reason 'self'|'auto'|'admin'
function Records.fileRespawn(source, hospital, injuries, fee, reason)
    local citizenid <const> = medics.citizenid(source)

    if not citizenid then return end

    local respawnFee <const> = catalog.byName('Hospital respawn')
    local draft <const> = Records.cleanDraft({
        citizenid = citizenid,
        patientName = medics.name(source),
        injuries = injuries,
        extras = fee > 0 and respawnFee and { respawnFee.id } or {},
        narrative = locale(('respawn.narrative_%s'):format(reason), hospital.label),
        outcome = 'respawned',
    })
    local frontDesk <const> = locale('records.front_desk')
    local id <const> = Records.saveReport(draft, nil, frontDesk, 'filed')

    if not id then return end

    if fee <= 0 then
        return waive(id)
    end

    local invoice <const> = billing.create({
        citizenid = citizenid,
        patientName = draft.patientName,
        lines = { { label = locale('records.respawn_fee'), amount = fee } },
        reportId = id,
        summary = locale('records.respawn_invoice', id),
        issuerName = frontDesk,
    })

    if not invoice then return end

    Records.markBilled(id, fee)

    if not billing.pay(invoice.id, 'cash_or_bank') then
        medics.notify(source, locale('respawn.owe', fee), 'warning')
    end
end

---@param medic string
---@param patient? string
function Records.logRevive(medic, patient)
    MySQL.insert.await('INSERT INTO ems_revives (medic_citizenid, patient_citizenid) VALUES (?, ?)', { medic, patient })
end

---@param charinfo table
---@return 'male'|'female'|'other'
local function sexOf(charinfo)
    local gender <const> = tonumber(charinfo.gender)

    if gender == 0 then return 'male' end

    if gender == 1 then return 'female' end

    return 'other'
end

---@param birthdate? string
---@return integer?
local function ageOf(birthdate)
    local year <const>, month <const>, day <const> = tostring(birthdate or ''):match('^(%d+)%-(%d+)%-(%d+)')

    if not year then return end

    local now <const> = os.date('*t') --[[@as osdate]]
    local age = now.year - tonumber(year)

    if now.month < tonumber(month) or (now.month == tonumber(month) and now.day < tonumber(day)) then
        age -= 1
    end

    return age
end

---@param rows table[]
---@return table[]
function Records.patientSummaries(rows)
    local ids <const> = {}

    for i, row in ipairs(rows) do
        ids[i] = row.citizenid
    end

    local balances <const> = billing.totals(ids).owed
    local bloodTypes <const> = exports.cobalt_core:GetMetaData(ids, 'bloodtype')
    local conditions <const>, treated <const> = {}, {}

    if #ids > 0 then
        local patients <const> = MySQL.query.await(
            'SELECT citizenid, conditions FROM ems_patients WHERE citizenid IN (?)',
            { ids }
        )

        for _, row in ipairs(patients or {}) do
            conditions[row.citizenid] = json.decode(row.conditions)
        end

        local latest <const> = MySQL.query.await([[
            SELECT r.citizenid, r.summary, UNIX_TIMESTAMP(r.created_at) AS at FROM ems_reports r
            JOIN (
                SELECT citizenid, MAX(id) AS id FROM ems_reports
                WHERE status = 'filed' AND citizenid IN (?)
                GROUP BY citizenid
            ) last ON last.id = r.id
        ]], { ids })

        for _, row in ipairs(latest or {}) do
            treated[row.citizenid] = { at = row.at, summary = row.summary:lower() }
        end
    end

    local out <const> = {}

    for i, row in ipairs(rows) do
        local charinfo <const> = json.decode(row.charinfo or '{}') or {}
        local source <const> = medics.sourceOf(row.citizenid)
        local revive <const> = source and Player(source).state.revive

        out[i] = {
            citizenid = row.citizenid,
            name = row.fullname or locale('common.unknown'),
            sex = sexOf(charinfo),
            dob = charinfo.birthdate or '',
            age = ageOf(charinfo.birthdate),
            bloodType = bloodTypes[row.citizenid],
            state = revive?.state or 'alive',
            online = source ~= nil,
            balance = balances[row.citizenid] or 0,
            conditions = conditions[row.citizenid] or {},
            lastTreated = treated[row.citizenid],
        }
    end

    return out
end

---@param value string
---@return string
function Records.likePattern(value)
    return ('%%%s%%'):format(value:gsub('[\\%%_]', '\\%0'))
end

---@param query string
---@return table[]
function Records.searchPatients(query)
    if #query < 2 then
        local recent <const> = MySQL.query.await([[
            SELECT p.citizenid, p.charinfo, p.fullname FROM players p
            JOIN (
                SELECT citizenid, MAX(id) AS id FROM ems_reports WHERE citizenid IS NOT NULL GROUP BY citizenid
            ) r ON r.citizenid = p.citizenid
            ORDER BY r.id DESC LIMIT 25
        ]]) or {}

        return Records.patientSummaries(recent)
    end

    local prefix <const> = query:gsub('[\\%%_]', '\\%0') .. '%'
    local rows <const> = MySQL.query.await([[
        SELECT citizenid, charinfo, fullname FROM players
        WHERE citizenid LIKE ? OR phone_number LIKE ? OR fullname LIKE ? OR lastname LIKE ?
        LIMIT 25
    ]], { prefix, prefix, prefix, prefix }) or {}

    return Records.patientSummaries(rows)
end

return Records
