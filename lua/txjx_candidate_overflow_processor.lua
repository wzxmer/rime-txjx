-- 普通候选数字越界续键
-- 必须位于 selector 之后：先让 selector 基于过滤后的最终候选选重，
-- 只有 selector 未消费数字时，才提交首选并保留该数字。

local key_event_util = require("input.txjx_key_event")
local commit_guard = require("input.txjx_commit_guard")

local kAccepted = 1
local kNoop = 2

local function processor(key_event, env)
    if not key_event or key_event:release()
        or key_event:ctrl() or key_event:alt() or key_event:super()
        or key_event:shift() then
        return kNoop
    end

    local ctx = env.engine.context
    if ctx:get_option("ascii_mode") or key_event_util.effective_caps_on(env, key_event) then
        return kNoop
    end

    local repr = key_event:repr()
    local digit = key_event_util.digit_char(repr, key_event.keycode, repr)
    if digit and commit_guard.commit_overflow_digit(ctx, env.engine, digit) then
        return kAccepted
    end
    return kNoop
end

return { func = processor }
