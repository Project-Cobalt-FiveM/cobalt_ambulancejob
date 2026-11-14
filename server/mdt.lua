local config <const> = require 'config'
local medics <const> = require 'server.medics'
local access <const> = require 'server.access'
local state <const> = require 'server.state'
local care <const> = require 'server.care'
local catalog <const> = require 'server.catalog'
local billing <const> = require 'server.billing'
local records <const> = require 'server.records'
local prescriptions <const> = require 'server.prescriptions'
local beds <const> = require 'server.beds'
local dispatch <const> = require 'server.dispatch'

---@class EmsMdtHandler
---@field fn fun(source: integer, data: table): any
---@field page? EmsPage
---@field permission? EmsPermission

local OK <const> = { ok = true }

---@param message string
---@return { ok: false, error: string }
local function fail(message)
    return { ok = false, error = message }
end

---@param id integer?
---@param err? string
---@return table
local function created(id, err)
    if not id then return fail(err or locale('mdt.not_saved')) end

    return { ok = true, id = id }
end

---@param value any
---@return string?
local function text(value)
    return type(value) == 'string' and value or nil
end

---@param value any
---@return integer?
local function int(value)
    return math.tointeger(tonumber(value))
end

---@param data table
---@return integer?
local function emsCallId(data)
    local id <const> = int(data.id)

    return id and dispatch.get(id) and id
end

---@param source integer
---@return string
local function onDutyDetail(source)
    local rank <const> = medics.job(source)?.gradeName or ''
    local vehicle <const> = GetVehiclePedIsIn(GetPlayerPed(source), false)
    local where

    if vehicle ~= 0 then
        where = GetVehicleType(vehicle) == 'heli' and locale('mdt.in_helicopter') or locale('mdt.in_ambulance')
    else
        where = medics.nearestHospitalShort(source)
    end

    return where and ('%s, %s'):format(rank, where) or rank
end

---@return table[]
local function onDutyList()
    local out <const> = {}

    for _, source in ipairs(exports.cobalt_core:GetPlayersByJob(config.job, true)) do
        out[#out + 1] = {
            citizenid = medics.citizenid(source),
            name = medics.name(source),
            callsign = medics.callsign(source),
            detail = onDutyDetail(source),
            status = medics.status(source),
        }
    end

    return out
end

---@param source integer
---@return table
local function dashboard(source)
    local calls <const> = dispatch.calls(source)
    local open, down = 0, 0

    for _, call in ipairs(calls) do
        if call.status == 'open' then
            open += 1

            if call.patient?.state == 'down' then
                down += 1
            end
        end
    end

    local onDuty <const> = onDutyList()
    local available, busy = 0, 0

    for _, medic in ipairs(onDuty) do
        if medic.status == 'available' then
            available += 1
        elseif medic.status ~= 'break' then
            busy += 1
        end
    end

    local invoices <const> = billing.totals()
    local training

    if config.traineeGrades[medics.job(source)?.grade or -1] then
        local filed <const> = MySQL.scalar.await(
            "SELECT COUNT(*) FROM ems_reports WHERE medic_citizenid = ? AND status = 'filed'",
            { medics.citizenid(source) }
        )

        training = { done = filed or 0, total = config.training.reports }
    end

    return {
        stats = {
            openCalls = open,
            patientsDown = down,
            medicsOnDuty = #onDuty,
            medicsAvailable = available,
            medicsOnCalls = busy,
            unpaidTotal = invoices.unpaid,
            unpaidCount = invoices.unpaidCount,
            overdueCount = invoices.overdueCount,
            training = training,
        },
        onDuty = onDuty,
        hospitals = beds.overview(),
    }
end

---@param citizenid string
---@return table?
local function patientProfile(citizenid)
    local row <const> = MySQL.single.await(
        'SELECT citizenid, charinfo, fullname, phone_number FROM players WHERE citizenid = ?',
        { citizenid }
    )

    if not row then return end

    local profile <const> = records.patientSummaries({ row })[1]
    local detail <const> = MySQL.single.await('SELECT * FROM ems_patients WHERE citizenid = ?', { citizenid }) or {}
    local charinfo <const> = json.decode(row.charinfo or '{}') or {}
    local source <const> = medics.sourceOf(citizenid)

    profile.phone = row.phone_number or charinfo.phone or ''
    profile.emergencyContact = detail.emergency_contact or ''
    profile.notes = detail.notes or ''
    profile.injuries = source and state.injuryList(source) or {}
    profile.reports = records.reports(" WHERE citizenid = ? AND status = 'filed'", { citizenid }, 100)
    profile.prescriptions = prescriptions.list(citizenid)
    profile.invoices = billing.list(citizenid)

    return profile
end

---@param source integer
---@param data table
---@return table
local function newReport(source, data)
    local citizenid <const> = text(data.citizenid)
    local callId = int(data.callId)
    local injuries <const> = {}
    local extras <const> = {}
    local patientName = ''

    if citizenid then
        local target <const> = medics.sourceOf(citizenid)
        local session <const> = care.get(citizenid)
        local seen <const> = {}

        patientName = exports.cobalt_core:GetName(citizenid) or locale('common.unknown')

        local function addInjury(bodyPart, kind)
            local key <const> = bodyPart .. kind

            if seen[key] then return seen[key] end

            local entry <const> = { bodyPart = bodyPart, kind = kind, treatments = {} }

            seen[key] = entry
            injuries[#injuries + 1] = entry

            return entry
        end

        for _, injury in ipairs(session?.injuries or {}) do
            addInjury(injury.bodyPart, injury.kind)
        end

        if target then
            for _, injury in ipairs(state.injuryList(target)) do
                addInjury(injury.bodyPart, injury.kind)
            end
        end

        for _, entry in ipairs(session?.entries or {}) do
            if entry.bodyPart and entry.kind then
                local injury <const> = addInjury(entry.bodyPart, entry.kind)

                injury.treatments[#injury.treatments + 1] = entry.treatmentId
            elseif not lib.table.contains(extras, entry.treatmentId) then
                extras[#extras + 1] = entry.treatmentId
            end
        end

        callId = callId or session?.callId
    end

    local templateId <const> = int(data.templateId)
    local template <const> = templateId and catalog.useTemplate(templateId)

    local draft <const> = records.cleanDraft({
        citizenid = citizenid,
        patientName = patientName,
        callId = callId,
        injuries = injuries,
        medications = {},
        extras = extras,
        narrative = template?.narrative or '',
        outcome = 'scene',
    })

    draft.id = nil

    return draft
end

---@param source integer
---@param id integer
---@return boolean
local function canEditReport(source, id)
    local row <const> = records.reportRow(id)

    if not row or row.status ~= 'draft' then return false end

    return row.medic_citizenid == medics.citizenid(source) or access.can(source, 'editOtherReports')
end

---@param source integer
---@param data table
---@param status 'draft'|'filed'
---@return integer? id
---@return string? error
local function storeReport(source, data, status)
    local draft <const> = records.cleanDraft(data)

    if draft.patientName == '' then return nil, locale('mdt.name_patient') end

    if draft.id and not canEditReport(source, draft.id) then
        return nil, locale('mdt.cannot_edit_report')
    end

    local medic <const> = medics.citizenid(source)
    local id <const> = records.saveReport(draft, medic, medics.name(source), status)

    if not id then return nil, locale('mdt.report_not_saved') end

    if status == 'filed' then
        local sendInvoice <const> = data.sendInvoice == true and access.can(source, 'sendInvoices')

        local invoiceId <const> = records.bill(id, draft, sendInvoice, medic)

        if invoiceId then billing.presentLater(source, invoiceId) end

        if draft.citizenid then
            care.clear(draft.citizenid)
        end

        exports.cobalt_core:LogPlayer(
            source,
            'ems.report',
            ('Filed report T-%d'):format(id),
            { citizenid = draft.citizenid }
        )
    end

    return id
end

---@return { id: string, label: string }[]
local function certificationList()
    local out <const> = {}

    for i, id in ipairs(config.certifications) do
        out[i] = { id = id, label = locale(('certifications.%s'):format(id)) }
    end

    return out
end

---@param byJob any the character's metadata.certifications
---@return string[]
local function jobCertifications(byJob)
    return type(byJob) == 'table' and byJob[config.job] or {}
end

---@return table
local function roster()
    local employees <const> = exports.cobalt_management:GetEmployees(config.job)
    local ids <const> = {}

    for i, employee in ipairs(employees) do
        ids[i] = employee.citizenid
    end

    local callsigns <const> = exports.cobalt_core:GetMetaData(ids, 'callsign')
    local certifications <const> = exports.cobalt_core:GetMetaData(ids, 'certifications')
    local reports <const>, revives <const> = {}, {}

    if #ids > 0 then
        local filed <const> = MySQL.query.await([[
            SELECT medic_citizenid AS id, COUNT(*) AS n FROM ems_reports
            WHERE status = 'filed' AND medic_citizenid IN (?)
            GROUP BY medic_citizenid
        ]], { ids })

        for _, row in ipairs(filed or {}) do
            reports[row.id] = row.n
        end

        local revived <const> = MySQL.query.await([[
            SELECT medic_citizenid AS id, COUNT(*) AS n FROM ems_revives
            WHERE created_at >= NOW() - INTERVAL 30 DAY AND medic_citizenid IN (?)
            GROUP BY medic_citizenid
        ]], { ids })

        for _, row in ipairs(revived or {}) do
            revives[row.id] = row.n
        end
    end

    local dutyMinutes <const> = #ids > 0 and exports.cobalt_management:GetDutyMinutes(ids, config.job, 3650) or {}
    local staff <const> = {}

    for i, employee in ipairs(employees) do
        local source <const> = employee.source
        local callsign <const> = callsigns[employee.citizenid]
        local year <const>, month <const>, day <const> = (employee.joinedAt or ''):match('^(%d+)%-(%d+)%-(%d+)')

        staff[i] = {
            citizenid = employee.citizenid,
            name = employee.name,
            callsign = callsign ~= 'NO CALLSIGN' and callsign or '',
            grade = employee.grade,
            rank = employee.rank,
            certifications = jobCertifications(certifications[employee.citizenid]),
            status = employee.onDuty and source and medics.status(source) or 'offduty',
            online = employee.online,
            doctor = config.doctorGrades[employee.grade] == true,
            trainee = config.traineeGrades[employee.grade] == true,
            joinedAt = year and os.time({
                year = tonumber(year) --[[@as integer]],
                month = tonumber(month) --[[@as integer]],
                day = tonumber(day) --[[@as integer]],
                hour = 12,
            }) or nil,
            hoursOnDuty = math.floor((dutyMinutes[employee.citizenid] or 0) / 60),
            reportsFiled = reports[employee.citizenid] or 0,
            revivesMonth = revives[employee.citizenid] or 0,
        }
    end

    return { staff = staff, ranks = access.grades(), certifications = certificationList() }
end

---@param citizenid string
---@return { citizenid: string, grade: integer }?
local function staffMember(citizenid)
    for _, employee in ipairs(exports.cobalt_management:GetEmployees(config.job)) do
        if employee.citizenid == citizenid then return employee end
    end
end

---@param source integer
---@param data table
---@return table
local function saveStaff(source, data)
    local citizenid <const> = text(data.citizenid)
    local callsign <const> = text(data.callsign) or ''
    local grade <const> = int(data.grade)

    if not citizenid or #callsign > 16 then return fail(locale('mdt.callsign_too_long')) end

    local own <const> = medics.job(source) --[[@as MedicJob]]
    local employee <const> = staffMember(citizenid)

    if not employee then return fail(locale('mdt.not_staff')) end

    if not own.isBoss then
        if employee.grade >= own.grade then return fail(locale('mdt.rank_too_high')) end
        if grade and grade >= own.grade then return fail(locale('mdt.give_lower_rank')) end
    end

    exports.cobalt_core:SetMetaData(citizenid, 'callsign', callsign:upper())

    if grade then
        local ok <const>, err <const> = exports.cobalt_management:SetGrade(citizenid, config.job, grade)

        if not ok and err then return fail(err) end
    end

    local requested <const> = type(data.certifications) == 'table' and data.certifications or {}
    local certs <const> = {}

    for _, id in ipairs(config.certifications) do
        if lib.table.contains(requested, id) then
            certs[#certs + 1] = id
        end
    end

    local stored <const> = exports.cobalt_core:GetMetaData({ citizenid }, 'certifications')[citizenid]
    local byJob <const> = type(stored) == 'table' and stored or {}

    byJob[config.job] = certs
    exports.cobalt_core:SetMetaData(citizenid, 'certifications', byJob)

    return OK
end

---@return table[]
local function ranks()
    local holders <const> = {}

    for _, employee in ipairs(exports.cobalt_management:GetEmployees(config.job)) do
        holders[employee.grade] = (holders[employee.grade] or 0) + 1
    end

    local out <const> = {}

    for i, rank in ipairs(access.grades()) do
        local isBoss <const> = access.isBossGrade(rank.grade)
        local permissions <const> = table.clone(access.rankPermissions(rank.grade))

        if isBoss then
            for key in pairs(permissions) do
                permissions[key] = true
            end
        end

        out[i] = {
            grade = rank.grade,
            name = rank.name,
            holders = holders[rank.grade] or 0,
            isBoss = isBoss,
            permissions = permissions,
        }
    end

    return out
end

---@param source integer
---@param data table
---@return table[]
local function search(source, data)
    local query <const> = text(data.query) or ''

    if #query < 2 then return {} end

    local hits <const> = {}

    for _, patient in ipairs(records.searchPatients(query)) do
        if #hits >= 6 then break end

        hits[#hits + 1] = {
            kind = 'patient',
            citizenid = patient.citizenid,
            title = patient.name,
            detail = patient.citizenid,
        }
    end

    local lower <const> = query:lower()

    for _, call in ipairs(dispatch.calls(source)) do
        if call.title:lower():find(lower, 1, true) or call.location:lower():find(lower, 1, true) then
            hits[#hits + 1] = {
                kind = 'call',
                id = call.id,
                title = call.title,
                detail = ('#%d, %s'):format(call.id, call.location),
            }
        end
    end

    local id <const> = int(query:match('^[Tt]%-?(%d+)$') or query)
    local pattern <const> = records.likePattern(query)
    local found <const> = records.reports(
        ' WHERE id = ? OR patient_name LIKE ? OR summary LIKE ?',
        { id or 0, pattern, pattern },
        6
    )

    for _, report in ipairs(found) do
        hits[#hits + 1] = {
            kind = 'report',
            id = report.id,
            title = locale('mdt.report_hit', report.id, report.patientName),
            detail = report.summary,
        }
    end

    return hits
end

---@type table<string, EmsMdtHandler>
local handlers <const> = {
    setStatus = {
        fn = function(source, data)
            return medics.setStatus(source, data.status) and OK or fail(locale('mdt.unknown_status'))
        end,
    },
    search = { fn = search },
    getDashboard = { fn = dashboard },
    getCalls = { fn = dispatch.calls },
    getDispatchSummary = {
        fn = function()
            local available, onBreak = 0, 0

            for _, source in ipairs(exports.cobalt_core:GetPlayersByJob(config.job, true)) do
                local status <const> = medics.status(source)

                if status == 'available' then
                    available += 1
                elseif status == 'break' then
                    onBreak += 1
                end
            end

            return { available = available, onBreak = onBreak, lastClosedAt = dispatch.lastClosedAt() }
        end,
    },
    respondCall = {
        fn = function(source, data)
            local id <const> = emsCallId(data)

            return id and dispatch.respond(source, id) and OK or fail(locale('mdt.call_closed'))
        end,
    },
    leaveCall = {
        fn = function(source, data)
            if not exports.cobalt_police:LeaveCall(source, int(data.id) or 0) then
                return fail(locale('mdt.not_on_call'))
            end

            medics.setStatus(source, 'available')

            return OK
        end,
    },
    waypointCall = {
        fn = function(source, data)
            local call <const> = dispatch.get(int(data.id) or 0)

            if not call?.coords then return fail(locale('mdt.call_no_location')) end

            TriggerClientEvent('cobalt_ambulancejob:client:waypoint', source, call.coords)

            return OK
        end,
    },
    assignCall = {
        fn = function(_, data)
            local citizenid <const> = text(data.citizenid)
            local target <const> = citizenid and medics.sourceOf(citizenid)
            local id <const> = emsCallId(data)

            if not id then return fail(locale('mdt.call_closed')) end

            if not target or not medics.isOnDuty(target) then
                return fail(locale('mdt.medic_off_duty'))
            end

            local member <const> = {
                citizenid = citizenid,
                name = medics.name(target),
                callsign = medics.callsign(target),
            }

            if not exports.cobalt_police:AssignToCall(id, { member }) then
                return fail(locale('mdt.call_closed'))
            end

            medics.setStatus(target, 'enroute')
            medics.notify(target, locale('mdt.assigned_to_call', id))

            return OK
        end,
    },
    closeCall = {
        fn = function(_, data)
            local id <const> = emsCallId(data)

            return id and dispatch.close(id) and OK or fail(locale('mdt.call_already_closed'))
        end,
    },
    markTransported = {
        fn = function(source, data)
            local id <const> = emsCallId(data)

            if not id or not exports.cobalt_police:AddCallNote(source, id, locale('mdt.patient_transported')) then
                return fail(locale('mdt.call_not_found'))
            end

            medics.setStatus(source, 'busy')

            return OK
        end,
    },
    searchPatients = {
        fn = function(_, data)
            return records.searchPatients(text(data.query) or '')
        end,
    },
    getPatient = {
        fn = function(_, data)
            return patientProfile(text(data.citizenid) or '') or false
        end,
    },
    savePatient = {
        permission = 'editPatients',
        fn = function(_, data)
            local citizenid <const> = text(data.citizenid)

            if not citizenid or not exports.cobalt_core:GetName(citizenid) then
                return fail(locale('mdt.patient_not_found'))
            end

            local conditions <const> = {}

            for _, condition in ipairs(type(data.conditions) == 'table' and data.conditions or {}) do
                if type(condition) == 'string' and condition ~= '' and #conditions < 20 then
                    conditions[#conditions + 1] = condition:sub(1, 60)
                end
            end

            MySQL.update.await([[
                INSERT INTO ems_patients (citizenid, conditions, emergency_contact, notes)
                VALUES (?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE conditions = VALUES(conditions),
                    emergency_contact = VALUES(emergency_contact), notes = VALUES(notes)
            ]], {
                citizenid,
                json.encode(conditions),
                (text(data.emergencyContact) or ''):sub(1, 120),
                (text(data.notes) or ''):sub(1, 4000),
            })

            return OK
        end,
    },
    getReports = {
        fn = function()
            return records.reports()
        end,
    },
    getReport = {
        fn = function(_, data)
            return records.report(int(data.id) or 0) or false
        end,
    },
    newReport = { permission = 'writeReports', fn = newReport },
    saveReport = {
        permission = 'writeReports',
        fn = function(source, data)
            return created(storeReport(source, data, 'draft'))
        end,
    },
    fileReport = {
        permission = 'writeReports',
        fn = function(source, data)
            return created(storeReport(source, data, 'filed'))
        end,
    },
    shareReport = {
        permission = 'shareReports',
        fn = function(_, data)
            if not access.settings().shareWithPolice then return fail(locale('mdt.sharing_off')) end

            local changed <const> = MySQL.update.await(
                "UPDATE ems_reports SET shared_with_police = ? WHERE id = ? AND status = 'filed'",
                { data.shared == true, int(data.id) or 0 }
            )

            return changed > 0 and OK or fail(locale('mdt.share_filed_only'))
        end,
    },
    getPrescriptions = { page = 'prescriptions', fn = prescriptions.recent },
    createPrescription = {
        permission = 'writePrescriptions',
        fn = function(source, data)
            return created(prescriptions.create(
                data,
                medics.citizenid(source) --[[@as string]],
                medics.name(source),
                access.can(source, 'prescribeControlled')
            ))
        end,
    },
    renewPrescription = {
        permission = 'writePrescriptions',
        fn = function(_, data)
            return prescriptions.renew(int(data.id) or 0) and OK or fail(locale('mdt.renew_active_only'))
        end,
    },
    cancelPrescription = {
        permission = 'writePrescriptions',
        fn = function(_, data)
            return prescriptions.cancel(int(data.id) or 0) and OK or fail(locale('mdt.prescription_inactive'))
        end,
    },
    getBilling = {
        page = 'billing',
        fn = function()
            local totals <const> = billing.totals()

            return {
                stats = { billedWeek = totals.billed, paidWeek = totals.paid, overdue = totals.overdue },
                invoices = billing.list(),
            }
        end,
    },
    createInvoice = {
        permission = 'sendInvoices',
        fn = function(source, data)
            local citizenid <const> = text(data.citizenid)
            local patientName <const> = citizenid and exports.cobalt_core:GetName(citizenid)

            if not patientName then return fail(locale('mdt.pick_patient')) end

            local invoice <const>, err <const> = billing.create({
                citizenid = citizenid --[[@as string]],
                patientName = patientName,
                lines = data.lines,
                summary = locale('billing.medical_care'),
                medic = medics.citizenid(source),
            })

            if invoice then billing.presentLater(source, invoice.id) end

            return created(invoice?.id, err)
        end,
    },
    chargeInvoice = {
        permission = 'sendInvoices',
        fn = function(source, data)
            local ok <const>, err <const> = billing.present(source, int(data.id) or 0)

            return ok and OK or fail(err or locale('billing.charge_failed'))
        end,
    },
    markInvoicePaid = {
        permission = 'voidInvoices',
        fn = function(source, data)
            local id <const> = int(data.id) or 0

            local paid <const>, err <const> = billing.pay(id, 'manual')

            if not paid then return fail(err --[[@as string]]) end

            exports.cobalt_core:LogPlayer(source, 'ems.invoice_marked_paid', ('Marked INV-%d paid without a charge'):format(id))

            return OK
        end,
    },
    voidInvoice = {
        permission = 'voidInvoices',
        fn = function(source, data)
            local reason <const> = text(data.reason) or ''
            local id <const> = int(data.id) or 0

            if reason == '' then return fail(locale('mdt.give_reason')) end

            if not billing.void(id, reason) then
                return fail(locale('mdt.void_unpaid_only'))
            end

            exports.cobalt_core:LogPlayer(source, 'ems.invoice_void', ('Voided INV-%d'):format(id), { reason = reason })

            return OK
        end,
    },
    getRoster = { fn = roster },
    saveStaff = { permission = 'manageRoster', fn = saveStaff },
    getRanks = { permission = 'manageRoster', fn = ranks },
    saveRank = {
        permission = 'manageRoster',
        fn = function(source, data)
            local grade <const> = int(data.grade)

            if not grade or access.isBossGrade(grade) then
                return fail(locale('mdt.boss_rank'))
            end

            if type(data.permissions) ~= 'table' then return fail(locale('mdt.invalid_permissions')) end

            local own <const> = medics.job(source) --[[@as table]]

            if not own.isBoss and grade >= own.grade then return fail(locale('mdt.edit_lower_rank')) end

            local held <const> = access.permissions(source)
            local granted <const> = {}

            for key, value in pairs(data.permissions) do granted[key] = value == true and held[key] == true end

            access.saveRank(grade, granted)
            exports.cobalt_core:LogPlayer(
                source,
                'ems.rank',
                ('Changed permissions for grade %d'):format(grade),
                data.permissions
            )

            return OK
        end,
    },
    getTreatments = { fn = catalog.treatments },
    getItems = {
        fn = function()
            local out <const> = {}

            for item in pairs(config.treatment) do
                local def <const> = exports.cobalt_inventory:GetItemDef(item)

                out[#out + 1] = { name = item, label = def?.label or item }
            end

            table.sort(out, function(a, b) return a.label < b.label end)

            return out
        end,
    },
    saveTreatment = {
        permission = 'manageTreatments',
        fn = function(_, data)
            return created(catalog.saveTreatment(data))
        end,
    },
    deleteTreatment = {
        permission = 'manageTreatments',
        fn = function(_, data)
            catalog.deleteTreatment(int(data.id) or 0)

            return OK
        end,
    },
    getTemplates = { fn = catalog.templates },
    saveTemplate = {
        permission = 'manageTemplates',
        fn = function(_, data)
            return created(catalog.saveTemplate(data))
        end,
    },
    deleteTemplate = {
        permission = 'manageTemplates',
        fn = function(_, data)
            catalog.deleteTemplate(int(data.id) or 0)

            return OK
        end,
    },
    getSettings = { fn = access.settings },
    saveSettings = {
        permission = 'manageSettings',
        fn = function(_, data)
            access.saveSettings({ medicShare = data.medicShare, shareWithPolice = data.shareWithPolice == true })

            return OK
        end,
    },
}

lib.callback.register('cobalt_ambulancejob:mdt', function(source, name, data)
    local handler <const> = handlers[name]

    if not handler or not medics.isMedic(source) then return end
    if not medics.isOnDuty(source) then return fail(locale('mdt.clock_in')) end

    if handler.page and not access.hasPage(source, handler.page) then
        return fail(locale('mdt.page_locked'))
    end

    if handler.permission and not access.can(source, handler.permission) then
        return fail(locale('mdt.rank_cannot'))
    end

    return handler.fn(source, type(data) == 'table' and data or {})
end)

lib.callback.register('cobalt_ambulancejob:call', function(source, id)
    if not medics.isMedic(source) or type(id) ~= 'number' then return end

    return dispatch.call(id)
end)

---@param source integer
---@return table?
local function session(source)
    local job <const> = medics.job(source)

    if not job then return end

    local pages <const>, locked <const> = access.pages(source)

    return {
        medic = {
            citizenid = medics.citizenid(source),
            name = medics.name(source),
            callsign = medics.callsign(source),
            grade = job.grade,
            gradeName = job.gradeName,
            department = { label = locale('department.label'), subtitle = locale('department.subtitle') },
            status = medics.status(source),
            permissions = access.permissions(source),
            pages = pages,
            locked = locked,
            trainee = config.traineeGrades[job.grade] == true,
        },
        settings = access.settings(),
        keybinds = { respond = config.dispatch.respondKey, waypoint = config.dispatch.waypointKey },
    }
end

lib.callback.register('cobalt_ambulancejob:openMdt', session)

exports('UseMdt', function(event, _, inventory)
    if event ~= 'usedItem' then return end

    local source <const> = inventory.source
    local policeRunning <const> = GetResourceState('cobalt_police') == 'started'

    if not medics.isMedic(source) and policeRunning and exports.cobalt_management:GetJob(source)?.type == 'leo' then
        return exports.cobalt_police:OpenMdt(source)
    end

    TriggerClientEvent('cobalt_ambulancejob:client:openMdt', source)
end)
