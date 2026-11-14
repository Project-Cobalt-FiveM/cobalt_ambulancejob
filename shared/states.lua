---@alias ReviveStateName 'alive'|'knocked_out'|'down'|'dead'
---@alias BodyPart 'head'|'torso'|'left_arm'|'right_arm'|'left_leg'|'right_leg'
---@alias InjuryKind 'bleeding'|'fracture'|'burn'|'severed'
---@alias CarryStateName 'none'|'fireman'

---@class ReviveState
---@field state ReviveStateName
---@field since integer epoch seconds when the state began, 0 when untimed

---@class CarryState
---@field state CarryStateName
---@field victim? integer
---@field carrier? integer

---@alias Injuries table<BodyPart, InjuryKind[]>

return {
    revive = {
        ALIVE = 'alive',
        KNOCKED_OUT = 'knocked_out',
        DOWN = 'down',
        DEAD = 'dead',
    },
    carry = {
        NONE = 'none',
        FIREMAN = 'fireman',
    },
    ---@type table<InjuryKind, true>
    injuryKinds = { bleeding = true, fracture = true, burn = true, severed = true },
    treatRange = 3.0,
}
