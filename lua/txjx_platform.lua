-- Rime 平台兼容工具
-- 统一处理 librime API 差异、候选刷新、分段标签等跨平台能力。
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-06-04

local M = {}

local type = type
local string_match = string.match

function M.should_defer_topup(_, ctx)
    if ctx and ctx:get_option("txjx_topup_defer") then return true end
    return false
end

function M.refresh(ctx, config)
    if not ctx or type(ctx.refresh_non_confirmed_composition) ~= "function" then
        return false
    end
    local override = config and config:get_string("txjx/platform/enable_refresh")
    if override == "false" or override == "0" or override == "no" then
        return false
    end
    local ok = pcall(function()
        ctx:refresh_non_confirmed_composition()
    end)
    return ok
end

function M.safe_connect(notifier, callback)
    if not notifier or type(callback) ~= "function" then return nil end
    local ok, conn = pcall(function()
        return notifier:connect(callback)
    end)
    if ok then return conn end
    return nil
end

function M.safe_disconnect(conn)
    if not conn then return end
    if type(conn.disconnect) == "function" then
        pcall(function() conn:disconnect() end)
    end
end

function M.safe_key_bool(key_event, name)
    if not key_event or type(key_event[name]) ~= "function" then return false end
    local ok, value = pcall(function()
        return key_event[name](key_event)
    end)
    return ok and value == true
end

function M.clean_repr(raw_key)
    if type(raw_key) ~= "string" then return raw_key end
    return string_match(raw_key, "^[Ss]hift%+(.*)") or raw_key
end

return M
