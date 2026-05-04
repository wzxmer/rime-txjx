-- 补全候选过滤器
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-05-04
local utf8_len = utf8.len
local type = type

return {
    init = function(env)
        local config = env.engine.schema.config
        env._danzi_first = not (config:get_bool("translator/enable_sentence") or false)
    end,

    func = function(input, env)
        local ctx = env.engine and env.engine.context
        local enabled = ctx and ctx:get_option("completion") or false
        local danzi = env._danzi_first
        local buffer = {}
        local buffer_size = 0
        local comp_count = 0

        for cand in input:iter() do
            if cand.type == "completion" then
                if not enabled then break end
                comp_count = comp_count + 1
                if comp_count > 30 then break end
            end
            if not danzi then
                yield(cand)
            else
                local c = cand.comment
                if c and type(c) == "string" and #c == 0 then
                    yield(cand)
                else
                    local text_len = utf8_len(cand.text)
                    if text_len == 1 then
                        yield(cand)
                    elseif text_len and text_len > 1 then
                        buffer_size = buffer_size + 1
                        buffer[buffer_size] = cand
                    end
                end
            end
        end

        for i = 1, buffer_size do
            yield(buffer[i])
        end
    end,

    fini = function(env)
        env._danzi_first = nil
    end
}
