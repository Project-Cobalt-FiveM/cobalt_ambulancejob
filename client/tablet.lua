local config <const> = require 'config'

local ANIM <const> = config.mdt.tablet

local Tablet <const> = {}

---@type integer?
local prop

function Tablet.hold()
    if prop then return end

    local ped <const> = cache.ped
    local attach <const> = ANIM.prop

    lib.playAnim(ped, ANIM.dict, ANIM.clip, 3.0, 3.0, -1, ANIM.flag)

    local model <const> = lib.requestModel(attach.model)
    local offset <const>, rotation <const> = attach.offset, attach.rotation

    prop = CreateObject(model, 1.0, 1.0, 1.0, false, false, false)
    AttachEntityToEntity(
        prop,
        ped,
        GetPedBoneIndex(ped, attach.bone),
        offset.x,
        offset.y,
        offset.z,
        rotation.x,
        rotation.y,
        rotation.z,
        true,
        true,
        false,
        true,
        2,
        true
    )
    SetModelAsNoLongerNeeded(model)
end

function Tablet.put()
    if not prop then return end

    if DoesEntityExist(prop) then
        DeleteEntity(prop)
    end

    prop = nil
    StopAnimTask(cache.ped, ANIM.dict, ANIM.clip, 1.0)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == cache.resource then
        Tablet.put()
    end
end)

return Tablet
