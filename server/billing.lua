local config <const> = require 'config'
local access <const> = require 'server.access'
local medics <const> = require 'server.medics'
local state <const> = require 'server.state'

local SOCIETY <const> = ('society_%s'):format(config.job)
local BILL_RANGE <const> = 5.0

---@type table<integer, true>
local prompted <const> = {}

---@class InvoiceLine
---@field label string
---@field amount integer

---@class InvoiceInput
---@field citizenid string
---@field patientName string
---@field lines InvoiceLine[]
---@field reportId? integer
---@field summary? string
---@field medic? string citizenid of whoever sent it

local Billing <const> = {}

local SELECT <const> = [[
    SELECT id, citizenid, patient_name, report_id, summary, `lines`, amount, status, medic_citizenid,
        UNIX_TIMESTAMP(due_at) AS due_at, UNIX_TIMESTAMP(declined_at) AS declined_at,
        UNIX_TIMESTAMP(paid_at) AS paid_at, void_reason, UNIX_TIMESTAMP(created_at) AS created_at
    FROM ems_invoices
]]

---@param row table
---@return table
function Billing.format(row)
    local status = row.status

    if status == 'unpaid' and row.due_at < os.time() then
        status = 'overdue'
    end

    return {
        id = row.id,
        citizenid = row.citizenid,
        patientName = row.patient_name,
        reportId = row.report_id,
        summary = row.summary,
        lines = json.decode(row.lines or '[]') or {},
        amount = row.amount,
        status = status,
        dueAt = row.due_at,
        createdAt = row.created_at,
        declinedAt = row.declined_at,
        paidAt = row.paid_at,
        voidReason = row.void_reason,
    }
end

---@param where? string
---@param params? any[]
---@return table[]
function Billing.list(where, params)
    local rows <const> = MySQL.query.await(SELECT .. (where or '') .. ' ORDER BY id DESC LIMIT 500', params or {}) or {}
    local out <const> = {}

    for i, row in ipairs(rows) do
        out[i] = Billing.format(row)
    end

    return out
end

---@param id integer
---@return table?
local function row(id)
    return MySQL.single.await(SELECT .. ' WHERE id = ?', { id })
end

---@param lines any
---@return InvoiceLine[] lines
---@return integer total
function Billing.cleanLines(lines)
    local out <const> = {}
    local total = 0

    local limits <const> = config.mdt.invoiceLimits

    for _, line in ipairs(type(lines) == 'table' and lines or {}) do
        if #out >= limits.lines then break end

        local label <const> = type(line.label) == 'string' and line.label:sub(1, 80) or ''
        local amount <const> = math.min(math.floor(tonumber(line.amount) or 0), limits.lineAmount)

        if label ~= '' and amount > 0 then
            out[#out + 1] = { label = label, amount = amount }
            total += amount
        end
    end

    return out, total
end

---@param invoice table
---@return boolean ok
---@return string? error
local function collect(invoice)
    local title <const> = locale('billing.invoice_title', invoice.id)
    local description <const> = invoice.summary ~= '' and ('%s, %s'):format(title, invoice.summary) or title
    local ok <const>, err <const> = exports.cobalt_banking:Transfer(invoice.citizenid, SOCIETY, invoice.amount, {
        note = description:sub(1, 120),
        initiator = 'ems',
        bill = true,
    })

    if not ok then return false, err end

    local share <const> = math.floor(invoice.amount * access.settings().medicShare / 100)

    if share > 0 and invoice.medic_citizenid then
        exports.cobalt_banking:Transfer(SOCIETY, invoice.medic_citizenid, share, {
            note = locale('billing.share_note', invoice.id),
            initiator = 'ems',
        })
    end

    return true
end

---@param id integer
---@return boolean
function Billing.markPaid(id)
    return MySQL.update.await(
        "UPDATE ems_invoices SET status = 'paid', paid_at = NOW() WHERE id = ? AND status = 'unpaid'",
        { id }
    ) > 0
end

---@param id integer
---@return boolean ok
---@return string? error
function Billing.charge(id)
    if not Billing.markPaid(id) then return false, locale('billing.already_settled') end

    local invoice <const> = row(id) --[[@as table]]
    local ok <const>, err <const> = collect(invoice)

    if ok then
        exports.cobalt_core:Log(
            'ems.invoice',
            ('INV-%d paid, $%d'):format(id, invoice.amount),
            { citizenid = invoice.citizenid }
        )

        return true
    end

    MySQL.update.await(
        "UPDATE ems_invoices SET status = 'unpaid', paid_at = NULL, declined_at = NOW() WHERE id = ?",
        { id }
    )

    return false, err == 'Insufficient funds' and locale('billing.declined') or (err or locale('billing.charge_failed'))
end

---@param source integer
---@param id integer
---@return boolean
function Billing.payCash(source, id)
    local player <const> = exports.cobalt_core:GetPlayer(source)
    local account <const> = exports.cobalt_banking:GetAccount(SOCIETY)

    if not player or not account or not Billing.markPaid(id) then return false end

    local invoice <const> = row(id) --[[@as table]]
    local title <const> = locale('billing.invoice_title', id)

    if not player.Functions.RemoveMoney('cash', invoice.amount, title) then
        MySQL.update.await("UPDATE ems_invoices SET status = 'unpaid', paid_at = NULL WHERE id = ?", { id })
        return false
    end

    local deposited <const> = exports.cobalt_banking:Deposit(account.id, invoice.amount, {
        note = locale('billing.paid_in_cash', title),
        initiator = invoice.citizenid,
    })

    if not deposited then
        player.Functions.AddMoney('cash', invoice.amount, locale('billing.refund', title))
        MySQL.update.await("UPDATE ems_invoices SET status = 'unpaid', paid_at = NULL WHERE id = ?", { id })
        return false
    end

    exports.cobalt_core:Log('ems.invoice', ('INV-%d paid in cash, $%d'):format(id, invoice.amount), {
        citizenid = invoice.citizenid,
    })

    return true
end

---@param source integer
---@param id integer
---@return boolean
function Billing.chargeCashThenBank(source, id)
    return Billing.payCash(source, id) or (Billing.charge(id))
end

---@param id integer
local function decline(id)
    MySQL.update.await("UPDATE ems_invoices SET declined_at = NOW() WHERE id = ? AND status = 'unpaid'", { id })
end

---@param patient integer
---@param invoice table
---@return boolean
local function askToPay(patient, invoice)
    prompted[patient] = true

    local ok <const>, accepted <const> = pcall(lib.callback.await, 'cobalt_ambulancejob:confirmBill', patient, {
        amount = invoice.amount,
        summary = invoice.summary,
    })

    prompted[patient] = nil

    return ok and accepted == true
end

---@param medic integer
---@param id integer
---@return boolean ok
---@return string? error
function Billing.present(medic, id)
    local invoice <const> = row(id)

    if not invoice or invoice.status ~= 'unpaid' then return false, locale('billing.already_settled') end

    local patient <const> = medics.sourceOf(invoice.citizenid)

    if not patient or not medics.near(medic, patient, BILL_RANGE) then
        return false, locale('billing.patient_not_here')
    end

    if state.isIncapacitated(patient) then return false, locale('billing.patient_down') end
    if prompted[patient] then return false, locale('billing.already_prompted') end

    if not askToPay(patient, invoice) then
        decline(id)
        return false, locale('billing.turned_down')
    end

    return Billing.charge(id)
end

---@param medic integer
---@param id integer
function Billing.presentLater(medic, id)
    CreateThread(function()
        local ok <const>, err <const> = Billing.present(medic, id)

        if ok then
            medics.notify(medic, locale('billing.paid', id), 'success')
        else
            medics.notify(medic, locale('billing.stays_open', id, err), 'warning')
        end
    end)
end

---@param data InvoiceInput
---@return integer? id
---@return string? error
function Billing.create(data)
    local lines <const>, total <const> = Billing.cleanLines(data.lines)

    if total <= 0 then return nil, locale('billing.no_lines') end

    if total > config.mdt.invoiceLimits.total then
        return nil, locale('billing.too_large', config.mdt.invoiceLimits.total)
    end

    local id <const> = MySQL.insert.await([[
        INSERT INTO ems_invoices (citizenid, patient_name, report_id, summary, `lines`, amount, medic_citizenid, due_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? DAY))
    ]], {
        data.citizenid,
        data.patientName,
        data.reportId,
        (data.summary or ''):sub(1, 255),
        json.encode(lines),
        total,
        data.medic,
        config.mdt.invoiceDays,
    })

    return id
end

---@param id integer
---@param reason string
---@return boolean
function Billing.void(id, reason)
    return MySQL.update.await(
        "UPDATE ems_invoices SET status = 'void', void_reason = ? WHERE id = ? AND status = 'unpaid'",
        { reason:sub(1, 255), id }
    ) > 0
end

---@return { billedWeek: integer, paidWeek: integer, overdue: integer }
function Billing.stats()
    local stats <const> = MySQL.single.await([[
        SELECT
            COALESCE(SUM(CASE WHEN status <> 'void' AND created_at >= NOW() - INTERVAL 7 DAY THEN amount END), 0)
                AS billed,
            COALESCE(SUM(CASE WHEN status = 'paid' AND paid_at >= NOW() - INTERVAL 7 DAY THEN amount END), 0)
                AS paid,
            COALESCE(SUM(CASE WHEN status = 'unpaid' AND due_at < NOW() THEN amount END), 0) AS overdue
        FROM ems_invoices
    ]]) or {}

    return { billedWeek = stats.billed or 0, paidWeek = stats.paid or 0, overdue = stats.overdue or 0 }
end

---@return { total: integer, count: integer, overdue: integer }
function Billing.unpaid()
    local stats <const> = MySQL.single.await([[
        SELECT COALESCE(SUM(amount), 0) AS total, COUNT(*) AS count, COALESCE(SUM(due_at < NOW()), 0) AS overdue
        FROM ems_invoices WHERE status = 'unpaid'
    ]]) or {}

    return { total = stats.total or 0, count = stats.count or 0, overdue = stats.overdue or 0 }
end

---@param citizenids string[]
---@return table<string, integer>
function Billing.balances(citizenids)
    local out <const> = {}

    if #citizenids == 0 then return out end

    local rows <const> = MySQL.query.await([[
        SELECT citizenid, SUM(amount) AS total FROM ems_invoices
        WHERE status = 'unpaid' AND citizenid IN (?)
        GROUP BY citizenid
    ]], { citizenids }) or {}

    for _, entry in ipairs(rows) do
        out[entry.citizenid] = math.floor(entry.total)
    end

    return out
end

AddEventHandler('playerDropped', function()
    prompted[source] = nil
end)

return Billing
