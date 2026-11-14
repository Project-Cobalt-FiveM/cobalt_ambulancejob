---@meta

---@alias AmbulanceReviveStateName 'alive'|'knocked_out'|'down'|'dead'

---@alias AmbulanceMdtPage
---| 'dashboard'
---| 'dispatch'
---| 'patients'
---| 'reports'
---| 'prescriptions'
---| 'billing'
---| 'roster'
---| 'management'

---The `revive` player state bag, replicated to every client. `down` is last stand: the player crawls and bleeds out at `since + death.bleedoutSeconds`, then turns `dead`.
---@class AmbulanceReviveState
---@field state AmbulanceReviveStateName
---@field since integer epoch seconds when the state began, 0 when alive

---@class AmbulancePrescription
---@field id integer
---@field citizenid string
---@field patientName string
---@field medication string
---@field dose string
---@field reason string
---@field refills integer fills allowed after the first
---@field refillsUsed integer refills taken, 0 until the second fill
---@field controlled boolean
---@field prescriber string
---@field createdAt integer epoch seconds
---@field endsAt integer epoch seconds
---@field status 'active'|'expired'|'cancelled'
---@field lastFill? { pharmacy: string, at: integer } the latest pharmacy fill, `at` in epoch seconds; nil until first filled

---@class AmbulanceReportSummary
---@field id integer
---@field citizenid string?
---@field patientName string
---@field summary string
---@field medic string
---@field medicCitizenid string?
---@field outcome 'scene'|'transported'|'deceased'|'respawned'
---@field status 'draft'|'filed'
---@field billing 'pending'|'billed'|'waived'
---@field billed integer?
---@field createdAt integer epoch seconds

---@class CobaltAmbulanceExports
local CobaltAmbulanceExports = {}

---**Server.** The player's death state. `down` is last stand that can still be revived on scene; a player past bleed-out reads `dead`. Compare it for a yes/no, such as `~= 'alive'` for anyone incapacitated.
---@param source integer
---@return AmbulanceReviveStateName
function CobaltAmbulanceExports:GetDeathState(source) end

---**Server.** Revives the player in place and refills hunger, thirst and stress.
---@param target integer
---@return boolean ok
---@return 'not_online'? err
function CobaltAmbulanceExports:RevivePlayer(target) end

---**Server.** Kills the player outright, skipping last stand, from alive, knocked out or last stand. False when they are already dead.
---@param target integer
---@return boolean
function CobaltAmbulanceExports:KillPlayer(target) end

---**Server.** The character's prescriptions, newest first.
---@param citizenid string
---@return AmbulancePrescription[]
function CobaltAmbulanceExports:GetPrescriptions(citizenid) end

---**Server.** Records a pharmacy fill. Every fill after the first uses a refill, so a prescription fills `refills + 1` times.
---False when the prescription is cancelled, expired or out of refills.
---@param citizenid string
---@param id integer
---@param pharmacy string
---@return boolean
function CobaltAmbulanceExports:FillPrescription(citizenid, id, pharmacy) end

---**Server.** Filed reports a doctor has shared with police for this character.
---@param citizenid string
---@return AmbulanceReportSummary[]
function CobaltAmbulanceExports:GetSharedReports(citizenid) end

---**Server.** The `ems_tablet` item's server export. On `usedItem` it opens the EMS MDT, or cobalt_police's for police officers who aren't medics.
---@param event 'usingItem' | 'usedItem'
---@param item table
---@param inventory { id: string, source: integer }
function CobaltAmbulanceExports:UseMdt(event, item, inventory) end

---**Client.** The treatment items' client export (`bandage`, `splint`, `burn_dressing`, `tourniquet`, `defibrillator`). On `usedItem` it treats the closest patient, or the player, from a body-part menu; the defibrillator revives the closest patient.
---@param event 'usingItem' | 'usedItem'
---@param item { name: string }
function CobaltAmbulanceExports:UseTreatment(event, item) end

exports.cobalt_ambulancejob = CobaltAmbulanceExports
