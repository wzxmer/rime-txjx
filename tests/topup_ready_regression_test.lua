package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local topup = require("input.txjx_topup")

local ctx = {
    get_property = function() return "" end,
    is_composing = function() return true end,
    clear = function() end,
}

local env = {}
for i = 1, 100 do
    assert(topup.ready(env, ctx), "topup ready failed at iteration " .. i)
end

print("topup_ready_regression_test: PASS")
