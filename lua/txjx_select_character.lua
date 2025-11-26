-- 优化版select_character  来源：@浮生 https://github.com/wzxmer/rime-txjx
-- 以词定字

local kAccepted = 1
local kNoop = 2

local select = {}

function select.init(env)
    local config = env.engine.schema.config
    select.first_key = config:get_string('key_binder/select_first_character')
    select.last_key = config:get_string('key_binder/select_last_character')
end

function select.func(key, env)
    local engine = env.engine
    local context = env.engine.context

    if not key:release()
        and (context:is_composing() or context:has_menu())
        and (select.first_key or select.last_key)
    then
        local text = context.input
        if context:get_selected_candidate() then
            text = context:get_selected_candidate().text
        end
        
        if utf8.len(text) > 1 then
            if key:repr() == select.first_key then
                engine:commit_text(text:sub(1, utf8.offset(text, 2) - 1))
                context:clear()
                return kAccepted
            elseif key:repr() == select.last_key then
                engine:commit_text(text:sub(utf8.offset(text, -1)))
                context:clear()
                return kAccepted
            end
        end
    end
    
    return kNoop
end

return select
