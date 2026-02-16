-- 补全候选过滤器（Completion Filter）
-- 功能：根据开关控制是否显示编码补全候选词
-- 特点：
--   1. 支持动态开关（completion）监听
--   2. 优化内存管理，正确断开监听器防止泄漏
--   3. 候选排序：带"~"的单字立即输出，其他候选延迟输出
--   4. 采用立即输出策略，显著降低卡顿
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx 
-- 更新：2026-02-16 使用请注明出处

local ctx_handlers = setmetatable({}, { __mode = "k" })

return {
    init = function(env)
        local ctx = env.engine.context
        if env._completion_handler and ctx.option_update_notifier then
            pcall(function() ctx.option_update_notifier:disconnect(env._completion_handler) end)
        end
        if ctx_handlers[ctx] and ctx.option_update_notifier then
            pcall(function() ctx.option_update_notifier:disconnect(ctx_handlers[ctx]) end)
        end
        env._completion_handler = nil
        ctx_handlers[ctx] = nil

        env.completion_enabled = ctx:get_option("completion")
        if env.completion_enabled == nil then
            env.completion_enabled = false
        end

        local handler = function(context, opname)
            if opname == "completion" then
                env.completion_enabled = context:get_option(opname)
            end
        end

        env._completion_handler = handler
        ctx_handlers[ctx] = handler
        ctx.option_update_notifier:connect(handler)
    end,

    func = function(input, env)
        if not env.completion_enabled then
            local seen_non_completion = false
            local after_non_completion_count = 0

            for cand in input:iter() do
                if cand.type == "completion" then
                    if seen_non_completion then
                        after_non_completion_count = after_non_completion_count + 1
                        if after_non_completion_count > 30 then
                            return
                        end
                    end
                else
                    seen_non_completion = true
                    yield(cand)
                end
            end
            return
        end

        local processed = 0
        local MAX_PROCESS = 100
        local deferred = {}
        local deferred_count = 0

        for cand in input:iter() do
            processed = processed + 1
            if processed > MAX_PROCESS then break end

            local comment = cand.comment
            local is_hint = comment and type(comment) == "string" and #comment > 0 and string.byte(comment, 1) == 126

            if is_hint then
                local text = cand.text
                if not text or #text <= 4 then
                    local text_len = text and utf8.len(text)
                    if text_len == 1 or text_len == nil then
                        yield(cand)
                    elseif text_len > 1 and deferred_count < 100 then
                        deferred_count = deferred_count + 1
                        deferred[deferred_count] = cand
                    end
                elseif deferred_count < 100 then
                    deferred_count = deferred_count + 1
                    deferred[deferred_count] = cand
                end
            else
                yield(cand)
            end
        end

        for i = 1, deferred_count do
            yield(deferred[i])
            deferred[i] = nil
        end
    end,

    fini = function(env)
        local ctx = env.engine and env.engine.context
        if ctx then
            if env._completion_handler and ctx.option_update_notifier then
                pcall(function() ctx.option_update_notifier:disconnect(env._completion_handler) end)
            end
            ctx_handlers[ctx] = nil
        end
        env._completion_handler = nil
        env.completion_enabled = nil
    end
}
