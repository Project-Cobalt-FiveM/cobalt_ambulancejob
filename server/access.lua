local config <const> = require 'config'
local medics <const> = require 'server.medics'

---@alias EmsPermission
---| 'writeReports'
---| 'editOtherReports'
---| 'editPatients'
---| 'writePrescriptions'
---| 'prescribeControlled'
---| 'admitDischarge'
---| 'useDefib'
---| 'sendInvoices'
---| 'voidInvoices'
---| 'shareReports'
---| 'manageTreatments'
---| 'manageRoster'
---| 'manageTemplates'
---| 'manageSettings'
---| 'administrator'

---@alias EmsPage 'dashboard'|'dispatch'|'patients'|'reports'|'prescriptions'|'billing'|'beds'|'roster'|'management'

---@class EmsSettings
---@field medicShare integer percent of each paid bill that goes to the filing medic
---@field shareWithPolice boolean

local PERMISSIONS <const> = {
    'writeReports', 'editOtherReports', 'editPatients', 'writePrescriptions', 'prescribeControlled', 'admitDischarge',
    'useDefib', 'sendInvoices', 'voidInvoices', 'shareReports', 'manageTreatments', 'manageRoster', 'manageTemplates',
    'manageSettings', 'administrator',
}

---@type { page: EmsPage, permissions: EmsPermission[] }[]
local PAGES <const> = {
    { page = 'dashboard', permissions = {} },
    { page = 'dispatch', permissions = {} },
    { page = 'patients', permissions = {} },
    { page = 'reports', permissions = {} },
    { page = 'prescriptions', permissions = { 'writePrescriptions' } },
    { page = 'billing', permissions = { 'sendInvoices' } },
    { page = 'beds', permissions = {} },
    { page = 'roster', permissions = {} },
    { page = 'management', permissions = { 'manageRoster', 'manageTreatments', 'manageTemplates', 'manageSettings' } },
}

local Access <const> = { permissions = PERMISSIONS }

---@type EmsSettings?
local settings

---@type table<integer, table<EmsPermission, boolean>>
local rankCache <const> = {}

---@param value boolean
---@return table<EmsPermission, boolean>
local function filled(value)
    local out <const> = {}

    for _, key in ipairs(PERMISSIONS) do
        out[key] = value
    end

    return out
end

---@return EmsSettings
function Access.settings()
    if not settings then
        local stored <const> = MySQL.scalar.await('SELECT data FROM ems_settings WHERE id = 1')
        local data <const> = stored and json.decode(stored) or {}
        local defaults <const> = config.defaultSettings
        local share <const> = math.floor(tonumber(data.medicShare) or defaults.medicShare)

        settings = {
            medicShare = math.max(0, math.min(100, share)),
            shareWithPolice = data.shareWithPolice == nil and defaults.shareWithPolice or data.shareWithPolice == true,
        }
    end

    return settings
end

---@param data table
---@return EmsSettings
function Access.saveSettings(data)
    settings = {
        medicShare = math.max(0, math.min(100, math.floor(tonumber(data.medicShare) or 0))),
        shareWithPolice = data.shareWithPolice == true,
    }

    MySQL.update.await(
        'INSERT INTO ems_settings (id, data) VALUES (1, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { json.encode(settings) }
    )

    return settings
end

---@param grade integer
---@return table<EmsPermission, boolean>
function Access.rankPermissions(grade)
    if rankCache[grade] then return rankCache[grade] end

    local stored <const> = MySQL.scalar.await('SELECT permissions FROM ems_ranks WHERE grade = ?', { grade })
    local out <const> = filled(false)

    for key, value in pairs(stored and json.decode(stored) or config.rankDefaults[grade] or {}) do
        if out[key] ~= nil then
            out[key] = value == true
        end
    end

    rankCache[grade] = out

    return out
end

---@param grade integer
---@param permissions table
function Access.saveRank(grade, permissions)
    local out <const> = filled(false)

    for key in pairs(out) do
        out[key] = permissions[key] == true
    end

    MySQL.update.await([[
        INSERT INTO ems_ranks (grade, permissions) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE permissions = VALUES(permissions)
    ]], { grade, json.encode(out) })

    rankCache[grade] = out
end

---@param grade integer
---@return boolean
function Access.isBossGrade(grade)
    local job <const> = exports.cobalt_core:GetShared('Jobs', config.job)

    return job?.grades?[tostring(grade)]?.isboss == true
end

---@param source integer
---@return table<EmsPermission, boolean>
function Access.permissions(source)
    local job <const> = medics.job(source)

    if not job then return filled(false) end

    if job.isBoss then return filled(true) end

    local out <const> = table.clone(Access.rankPermissions(job.grade))

    if out.administrator then return filled(true) end

    return out
end

---@param source integer
---@param permission EmsPermission
---@return boolean
function Access.can(source, permission)
    local permissions <const> = Access.permissions(source)

    return permissions.administrator or permissions[permission] == true
end

---@param permissions table<EmsPermission, boolean>
---@param needed EmsPermission[]
---@return boolean
local function grants(permissions, needed)
    if #needed == 0 or permissions.administrator then return true end

    for _, permission in ipairs(needed) do
        if permissions[permission] then return true end
    end

    return false
end

---@return { grade: integer, name: string }[]
function Access.grades()
    local job <const> = exports.cobalt_core:GetShared('Jobs', config.job)
    local out <const> = {}

    for grade, data in pairs(job?.grades or {}) do
        out[#out + 1] = { grade = tonumber(grade) --[[@as integer]], name = data.name }
    end

    table.sort(out, function(a, b) return a.grade < b.grade end)

    return out
end

---@param needed EmsPermission[]
---@return string
local function lowestRankWith(needed)
    for _, rank in ipairs(Access.grades()) do
        if Access.isBossGrade(rank.grade) or grants(Access.rankPermissions(rank.grade), needed) then
            return rank.name
        end
    end

    return config.mdt.lockedRank
end

---@param source integer
---@return EmsPage[] pages
---@return { page: EmsPage, rank: string }[] locked
function Access.pages(source)
    local permissions <const> = Access.permissions(source)
    local pages <const>, locked <const> = {}, {}

    for _, entry in ipairs(PAGES) do
        if grants(permissions, entry.permissions) then
            pages[#pages + 1] = entry.page
        else
            locked[#locked + 1] = { page = entry.page, rank = lowestRankWith(entry.permissions) }
        end
    end

    return pages, locked
end

---@param source integer
---@param page EmsPage
---@return boolean
function Access.hasPage(source, page)
    local permissions <const> = Access.permissions(source)

    for _, entry in ipairs(PAGES) do
        if entry.page == page then return grants(permissions, entry.permissions) end
    end

    return false
end

return Access
