local config <const> = require 'config'

---@alias TreatmentCategory 'injury'|'procedure'|'medication'|'fee'

---@class Treatment
---@field id integer
---@field name string
---@field category TreatmentCategory
---@field treats string[]
---@field item string?
---@field price integer
---@field seconds integer

local CATEGORIES <const> = { injury = true, procedure = true, medication = true, fee = true }
local TREATS <const> = { bleeding = true, fracture = true, burn = true, severed = true, down = true }

local INSERT_TREATMENT <const> = [[
    INSERT INTO ems_treatments (name, category, treats, item, price, seconds) VALUES (?, ?, ?, ?, ?, ?)
]]

local INSERT_TEMPLATE <const> = 'INSERT INTO ems_templates (name, narrative) VALUES (?, ?)'

local Catalog <const> = {}

---@type Treatment[]?
local treatments

---@param row table
---@return Treatment
local function treatmentFrom(row)
    return {
        id = row.id,
        name = row.name,
        category = row.category,
        treats = json.decode(row.treats or '[]') or {},
        item = row.item,
        price = row.price,
        seconds = row.seconds,
    }
end

---@return Treatment[]
function Catalog.treatments()
    if not treatments then
        local rows <const> = MySQL.query.await([[
            SELECT * FROM ems_treatments ORDER BY FIELD(category, 'injury', 'procedure', 'medication', 'fee'), name
        ]]) or {}

        treatments = {}

        for i, row in ipairs(rows) do
            treatments[i] = treatmentFrom(row)
        end
    end

    return treatments
end

---@param id integer
---@return Treatment?
function Catalog.treatment(id)
    for _, treatment in ipairs(Catalog.treatments()) do
        if treatment.id == id then return treatment end
    end
end

---@param name string
---@return Treatment?
function Catalog.byName(name)
    for _, treatment in ipairs(Catalog.treatments()) do
        if treatment.name == name then return treatment end
    end
end

---@param item string
---@return Treatment?
function Catalog.byItem(item)
    for _, treatment in ipairs(Catalog.treatments()) do
        if treatment.item == item then return treatment end
    end
end

---@param item string
---@return integer milliseconds
function Catalog.itemDuration(item)
    local treatment <const> = Catalog.byItem(item)
    local custom <const> = treatment and treatment.seconds > 0 and treatment.seconds
    local seconds <const> = custom or config.treatment[item]?.seconds or 5

    return seconds * 1000
end

---@param data table
---@return integer? id
---@return string? error
function Catalog.saveTreatment(data)
    local name <const> = type(data.name) == 'string' and data.name:sub(1, 100) or ''

    if name == '' then return nil, locale('catalog.name_treatment') end

    if not CATEGORIES[data.category] then return nil, locale('catalog.pick_category') end

    local treats <const> = {}

    for _, kind in ipairs(type(data.treats) == 'table' and data.treats or {}) do
        if TREATS[kind] then
            treats[#treats + 1] = kind
        end
    end

    local item <const> = type(data.item) == 'string' and data.item ~= '' and data.item:sub(1, 64) or nil
    local price <const> = math.max(0, math.floor(tonumber(data.price) or 0))
    local seconds <const> = math.max(0, math.min(600, math.floor(tonumber(data.seconds) or 0)))
    local values <const> = { name, data.category, json.encode(treats), item, price, seconds }
    local id = tonumber(data.id)

    if id then
        values[7] = id
        MySQL.update.await([[
            UPDATE ems_treatments SET name = ?, category = ?, treats = ?, item = ?, price = ?, seconds = ? WHERE id = ?
        ]], values)
    else
        id = MySQL.insert.await(INSERT_TREATMENT, values)
    end

    treatments = nil

    return id --[[@as integer]]
end

---@param id integer
function Catalog.deleteTreatment(id)
    MySQL.update.await('DELETE FROM ems_treatments WHERE id = ?', { id })
    treatments = nil
end

---@return { id: integer, name: string, narrative: string, uses: integer }[]
function Catalog.templates()
    return MySQL.query.await('SELECT id, name, narrative, uses FROM ems_templates ORDER BY uses DESC, name') or {}
end

---@param id integer
---@return { id: integer, name: string, narrative: string, uses: integer }?
function Catalog.useTemplate(id)
    local row <const> = MySQL.single.await('SELECT id, name, narrative, uses FROM ems_templates WHERE id = ?', { id })

    if row then
        MySQL.update.await('UPDATE ems_templates SET uses = uses + 1 WHERE id = ?', { id })
    end

    return row
end

---@param data table
---@return integer? id
---@return string? error
function Catalog.saveTemplate(data)
    local name <const> = type(data.name) == 'string' and data.name:sub(1, 100) or ''

    if name == '' then return nil, locale('catalog.name_template') end

    local narrative <const> = type(data.narrative) == 'string' and data.narrative:sub(1, 4000) or ''
    local id = tonumber(data.id)

    if id then
        MySQL.update.await('UPDATE ems_templates SET name = ?, narrative = ? WHERE id = ?', { name, narrative, id })
    else
        id = MySQL.insert.await(INSERT_TEMPLATE, { name, narrative })
    end

    return id --[[@as integer]]
end

---@param id integer
function Catalog.deleteTemplate(id)
    MySQL.update.await('DELETE FROM ems_templates WHERE id = ?', { id })
end

CreateThread(function()
    if MySQL.scalar.await('SELECT COUNT(*) FROM ems_templates') == 0 then
        for _, template in ipairs(config.defaultTemplates) do
            MySQL.insert.await(INSERT_TEMPLATE, { template.name, template.narrative })
        end
    end

    if MySQL.scalar.await('SELECT COUNT(*) FROM ems_treatments') > 0 then return end

    for _, treatment in ipairs(config.defaultTreatments) do
        MySQL.insert.await(INSERT_TREATMENT, {
            treatment.name,
            treatment.category,
            json.encode(treatment.treats),
            treatment.item,
            treatment.price,
            treatment.seconds,
        })
    end

    treatments = nil
end)

return Catalog
