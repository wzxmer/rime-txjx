-- 天行键 内存释放哨兵（水位线分级）
-- Hamster(iOS) 键盘扩展收起前发送 XK_VoidSymbol(0xFFFFFF)，
-- 收到后按 Lua 堆水位线分级释放：低于 txjx/mem_watermark_mb（默认 50）时
-- 只清轻量动态缓存（反查句柄/提示缓存等），读音表等大表保持常驻，
-- 重开键盘零重载；达到水位线才升级为保守释放，堆上界可控不失控。
-- 事件只在非 composing 状态到达，不影响用户输入；桌面端不会出现该键码。
-- 机制参考 xmjd6 dict_search_trigger 的同款哨兵约定。
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-09-07

local registry = require("common.txjx_cache_registry")

local kAccepted = 1
local kNoop = 2

local CLEAR_CACHE_KEYCODE = 0xFFFFFF
local DEFAULT_WATERMARK_MB = 50

local function watermark_kb(env)
    local mb = DEFAULT_WATERMARK_MB
    local ok, config = pcall(function()
        return env.engine.schema.config
    end)
    if ok and config and config.get_int then
        local ok2, value = pcall(config.get_int, config, "txjx/mem_watermark_mb")
        if ok2 and type(value) == "number" and value > 0 then
            mb = value
        end
    end
    return mb * 1024
end

local function processor(key_event, env)
    if key_event:release() then return kNoop end
    if key_event.keycode == CLEAR_CACHE_KEYCODE then
        -- 水位线检查点：堆低于水位线保留大表常驻，达到才升级释放
        local over_watermark = (collectgarbage("count") or 0) >= watermark_kb(env)
        local gc_mode = over_watermark and "full" or "step"
        registry.clear_all(true, over_watermark, gc_mode)
        return kAccepted
    end
    return kNoop
end

return { func = processor }
