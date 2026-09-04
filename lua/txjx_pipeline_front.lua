-- 天行键 前段过滤管线：zzc_filter + txjx_completion
-- 阶段语义与独立过滤器完全一致，仅在 Lua 内串联以减少 C++ 边界穿越。
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-09-05

local pipeline = require("common.txjx_pipeline")
local zzc_filter = require("zzc.txjx_zzc_filter")
local completion = require("txjx_completion")

local M = {}

local function build_stages(env)
    return {
        { func = zzc_filter.func, env = { engine = env.engine } },
        { func = completion.func, env = { engine = env.engine } },
    }
end

function M.init(env)
    env._stages = build_stages(env)
    zzc_filter.init(env._stages[1].env)
    completion.init(env._stages[2].env)
end

function M.func(input, env)
    pipeline.run(env._stages, input)
end

function M.fini(env)
    if env._stages then
        completion.fini(env._stages[2].env)
    end
    env._stages = nil
end

return { init = M.init, func = M.func, fini = M.fini }
