local core <const> = exports.cobalt_core

local ANSWER_MS <const> = 60000

---@param bill { amount: integer, summary?: string }
---@return boolean
local function confirmBill(bill)
    local summary <const> = bill.summary ~= '' and bill.summary or locale('billing.default_summary')
    local choice <const> = core:AlertDialog({
        header = locale('billing.bill_header', locale('department.label')),
        content = locale('billing.bill_content', summary, bill.amount),
        centered = true,
        cancel = true,
        labels = { confirm = locale('billing.pay'), cancel = locale('billing.not_now') },
    }, ANSWER_MS)

    return choice == 'confirm'
end

lib.callback.register('cobalt_ambulancejob:confirmBill', confirmBill)
