-- 天行键 Lua 过滤管线驱动器
-- 把相邻的 Lua 过滤器阶段在 Lua 进程内串联：阶段之间用协程迭代器惰性喂候选，
-- 阶段语义（含截断 break/return、yield 顺序）与独立过滤器逐字一致，
-- 仅管线首尾保留 Lua↔C++ 边界，中间阶段不再跨界。
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-09-05

local M = {}

local function stage_input_iterator(co)
    return {
        iter = function()
            local done = false
            return function()
                if done then return nil end
                if coroutine.status(co) == "dead" then
                    done = true
                    return nil
                end
                local ok, value = coroutine.resume(co)
                if not ok then error(value, 0) end
                if coroutine.status(co) == "dead" then
                    done = true
                    return nil
                end
                return value
            end
        end,
    }
end

-- stages: { { func = filter_func, env = stage_env }, ... }，按链序排列。
-- 必须在 librime 过滤器的生成协程内调用：最终输出经全局 yield 交还引擎。
function M.run(stages, input)
    local prev = input
    for i = 1, #stages do
        local stage = stages[i]
        local stage_in = prev
        prev = stage_input_iterator(coroutine.create(function()
            stage.func(stage_in, stage.env)
        end))
    end
    for cand in prev:iter() do
        yield(cand)
    end
end

return M
