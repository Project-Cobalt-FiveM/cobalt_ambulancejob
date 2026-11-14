local config <const> = require 'config'
local access <const> = require 'server.access'
local medics <const> = require 'server.medics'
local state <const> = require 'server.state'

local BILL_RANGE <const> = 5.0
local INVOICE_LIMIT <const> = 500

---@type table<BankingFailure, string>
local FAILURES <const> = {
    insufficient_funds = 'billing.declined',
    settled = 'billing.already_settled',
    payer_offline = 'billing.patient_not_here',
}

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
---@field issuerName? string who the bank statement names as the sender, when no medic sent it

---@class EmsInvoice
---@field id integer
---@field citizenid string
---@field patientName string
---@field reportId? integer
---@field summary string
---@field lines InvoiceLine[]
---@field amount integer
---@field status BankingInvoiceStatus
---@field dueAt integer
---@field createdAt integer
---@field declinedAt? integer
---@field paidAt? integer
---@field voidReason? string

local Billing <const> = {}

---@param reason? BankingFailure
---@return string
local function failure(reason)
    return locale(FAILURES[reason] or 'billing.charge_failed')
end

---@param invoice BankingInvoice
---@return EmsInvoice
local function format(invoice)
    local data <const> = invoice.data

    return {
        id = invoice.id,
        citizenid = invoice.citizenid,
        patientName = data.patientName or invoice.payerName,
        reportId = data.reportId,
        summary = invoice.summary,
        lines = data.lines or {},
        amount = invoice.amount,
        status = invoice.status,
        dueAt = invoice.dueAt,
        createdAt = invoice.createdAt,
        declinedAt = invoice.declinedAt,
        paidAt = invoice.paidAt,
        voidReason = invoice.voidReason,
    }
end

---@param id integer
---@return BankingInvoice? invoice nil unless EMS sent it
local function own(id)
    local invoice <const> = exports.cobalt_banking:GetInvoice(id)

    if invoice?.issuer == config.job then return invoice end
end

---@param citizenid? string
---@return EmsInvoice[]
function Billing.list(citizenid)
    local invoices <const> = exports.cobalt_banking:GetInvoices({
        issuer = config.job,
        citizenid = citizenid,
        limit = INVOICE_LIMIT,
    })
    local out <const> = {}

    for i, invoice in ipairs(invoices) do
        out[i] = format(invoice)
    end

    return out
end

---@param reportId integer
---@return { id: integer, status: BankingInvoiceStatus }?
function Billing.forReport(reportId)
    local invoice <const> = exports.cobalt_banking:GetInvoices({
        issuer = config.job,
        data = { reportId = reportId },
        limit = 1,
    })[1]

    return invoice and { id = invoice.id, status = invoice.status }
end

---@param citizenids? string[] fills `owed` for these characters
---@return BankingInvoiceTotals
function Billing.totals(citizenids)
    return exports.cobalt_banking:GetInvoiceTotals({ issuer = config.job, citizenid = citizenids })
end

---@param lines any
---@return InvoiceLine[] lines
---@return integer total
local function cleanLines(lines)
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

---@param data InvoiceInput
---@return BankingInvoice? invoice
---@return string? error
function Billing.create(data)
    local lines <const>, total <const> = cleanLines(data.lines)

    if total <= 0 then return nil, locale('billing.no_lines') end

    if total > config.mdt.invoiceLimits.total then
        return nil, locale('billing.too_large', config.mdt.invoiceLimits.total)
    end

    local result <const> = exports.cobalt_banking:CreateInvoice({
        issuer = config.job,
        citizenid = data.citizenid,
        amount = total,
        summary = (data.summary or ''):sub(1, 255),
        issuerCitizenid = data.medic,
        issuerName = data.issuerName,
        dueDays = config.mdt.invoiceDays,
        data = { lines = lines, reportId = data.reportId, patientName = data.patientName },
    })

    if not result.ok then return nil, locale('mdt.not_saved') end

    return result.invoice
end

---@param id integer
---@param method? BankingInvoiceMethod default `bank`, the patient's bank account
---@return boolean ok
---@return string? error
function Billing.pay(id, method)
    if not own(id) then return false, locale('billing.charge_failed') end

    local result <const> = exports.cobalt_banking:PayInvoice(id, { method = method })

    if not result.ok then return false, failure(result.reason) end

    return true
end

---@param id integer
---@param reason string
---@return boolean
function Billing.void(id, reason)
    return own(id) ~= nil and exports.cobalt_banking:VoidInvoice(id, reason:sub(1, 255)).ok
end

---@param patient integer
---@param invoice BankingInvoice
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
    local invoice <const> = own(id)

    if not invoice or invoice.status == 'paid' or invoice.status == 'void' then
        return false, locale('billing.already_settled')
    end

    local patient <const> = medics.sourceOf(invoice.citizenid)

    if not patient or not medics.near(medic, patient, BILL_RANGE) then
        return false, locale('billing.patient_not_here')
    end

    if state.isIncapacitated(patient) then return false, locale('billing.patient_down') end
    if prompted[patient] then return false, locale('billing.already_prompted') end

    if not askToPay(patient, invoice) then
        exports.cobalt_banking:DeclineInvoice(id)
        return false, locale('billing.turned_down')
    end

    return Billing.pay(id)
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

AddEventHandler('cobalt_banking:invoicePaid', function(invoice, paidWith)
    if invoice.issuer ~= config.job or paidWith == 'manual' or not invoice.issuerCitizenid then return end

    local share <const> = math.floor(invoice.amount * access.settings().medicShare / 100)

    if share <= 0 then return end

    exports.cobalt_banking:Transfer(invoice.payee, invoice.issuerCitizenid, share, {
        note = locale('billing.share_note', invoice.id),
        initiator = 'ems',
    })
end)

AddEventHandler('playerDropped', function()
    prompted[source] = nil
end)

return Billing
