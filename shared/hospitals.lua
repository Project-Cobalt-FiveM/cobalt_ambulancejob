local config <const> = require 'config'

local Hospitals <const> = {}

---@type Hospital[]
local enabled <const> = {}

---@type table<string, Hospital>
local byId <const> = {}

for _, hospital in ipairs(config.hospitals) do
    if hospital.enabled ~= false then
        enabled[#enabled + 1] = hospital
        byId[hospital.id] = hospital
    end
end

---@return Hospital[]
function Hospitals.list()
    return enabled
end

---@param id string
---@return Hospital?
function Hospitals.get(id)
    return byId[id]
end

---@param coords vector3
---@return Hospital
function Hospitals.nearest(coords)
    local best, bestDistance = enabled[1], math.huge

    for _, hospital in ipairs(enabled) do
        local distance <const> = #(coords - hospital.respawn.xyz)

        if distance < bestDistance then
            best, bestDistance = hospital, distance
        end
    end

    return best
end

return Hospitals
