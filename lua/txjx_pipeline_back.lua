-- 天行键 后段过滤管线：txjx_reverse_hint + txjx_filter + txjx_opencc_filter + txjx_newline
-- 阶段语义与独立过滤器完全一致，仅在 Lua 内串联以减少 C++ 边界穿越。
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-09-05

local pipeline = require("common.txjx_pipeline")
local reverse_hint = require("txjx_reverse_hint")
local txjx_filter = require("txjx_filter")
local opencc = require("txjx_opencc_filter")
local newline = require("txjx_newline")

local M = {}

local function build_stages(env)
    local engine = env.engine
    return {
        { func = reverse_hint.func, env = { engine = engine } },
        { func = txjx_filter.func, env = { engine = engine } },
        { func = opencc.func, env = { engine = engine, name_space = "txjx_opencc_filter" } },
        { func = newline.func, env = { engine = engine } },
    }
end

function M.init(env)
    env._stages = build_stages(env)
    reverse_hint.init(env._stages[1].env)
    txjx_filter.init(env._stages[2].env)
    opencc.init(env._stages[3].env)
end

function M.func(input, env)
    pipeline.run(env._stages, input)
end

function M.fini(env)
    if env._stages then
        opencc.fini(env._stages[3].env)
        txjx_filter.fini(env._stages[2].env)
        reverse_hint.fini(env._stages[1].env)
    end
    env._stages = nil
end

return { init = M.init, func = M.func, fini = M.fini }
