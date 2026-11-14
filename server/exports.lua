local state <const> = require 'server.state'
local revive <const> = require 'server.revive'
local records <const> = require 'server.records'
local prescriptions <const> = require 'server.prescriptions'

exports('GetDeathState', state.deathState)
exports('RevivePlayer', revive.revivePlayer)
exports('KillPlayer', revive.killPlayer)
exports('GetPrescriptions', prescriptions.list)
exports('FillPrescription', prescriptions.fill)

exports('GetSharedReports', function(citizenid)
    return records.reports(" WHERE citizenid = ? AND status = 'filed' AND shared_with_police = 1", { citizenid }, 100)
end)
