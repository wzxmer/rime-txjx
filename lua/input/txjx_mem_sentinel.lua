-- 天行键 内存释放哨兵
-- Hamster(iOS) 键盘扩展收起前发送 XK_VoidSymbol(0xFFFFFF)，
-- 收到后统一释放 cache_registry 注册的全部缓存并触发 GC。
-- 事件只在非 composing 状态到达，不影响用户输入；桌面端不会出现该键码。
-- 机制参考 xmjd6 dict_search_trigger 的同款哨兵约定。
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-09-05

local registry = require("common.txjx_cache_registry")

local kAccepted = 1
local kNoop = 2

local CLEAR_CACHE_KEYCODE = 0xFFFFFF

local function processor(key_event, env)
    if key_event:release() then return kNoop end
    if key_event.keycode == CLEAR_CACHE_KEYCODE then
        -- 保守释放：跳过热路径常驻缓存（自造词/opencc 等），
        -- 只释放低频或重载廉价的部分，避免重开键盘频繁重载
        registry.clear_all(true)
        return kAccepted
    end
    return kNoop
end

return { func = processor }
