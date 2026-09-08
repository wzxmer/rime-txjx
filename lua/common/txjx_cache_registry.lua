-- 天行键 缓存注册表模块
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-07-02

local M = {}

-- cleaners[name] = { { fn = 清理函数, essential = 释放分级, token = 不透明句柄 } }
-- essential=false/nil：哨兵每次释放（轻量动态缓存，重建廉价）；
-- essential="pressure"：水位线档——Lua 堆达到水位线才随哨兵释放，
--   低于水位线保持常驻，避免重开键盘反复重载大表；
-- essential=true：常驻档，仅手动 =mem! 全量释放（自造词/opencc 热数据）。
local cleaners = {}
local order = {}

local function trim_name(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return name
end

function M.register(name, cleaner, essential)
    name = trim_name(name)
    if not name or type(cleaner) ~= "function" then
        return false
    end
    if not cleaners[name] then
        order[#order + 1] = name
        cleaners[name] = {}
    end
    local token = {}
    cleaners[name][#cleaners[name] + 1] = {
        fn = cleaner,
        essential = essential or false,
        token = token,
    }
    return token
end

-- 传 register 返回的 token 只注销对应实例；传名称保留旧的整组注销语义。
function M.unregister(value)
    if type(value) == "table" then
        for name, entries in pairs(cleaners) do
            for index = #entries, 1, -1 do
                if entries[index].token == value then
                    table.remove(entries, index)
                    if #entries == 0 then
                        cleaners[name] = nil
                        for order_index = #order, 1, -1 do
                            if order[order_index] == name then
                                table.remove(order, order_index)
                            end
                        end
                    end
                    return true
                end
            end
        end
        return false
    end

    local name = trim_name(value)
    if not name or not cleaners[name] then return false end
    cleaners[name] = nil
    for order_index = #order, 1, -1 do
        if order[order_index] == name then
            table.remove(order, order_index)
        end
    end
    return true
end

-- conservative=true 时按分级跳过：essential=true 恒跳过；essential="pressure"
-- 仅在 over_watermark=true（哨兵报告 Lua 堆达到水位线）时释放。
-- gc_mode="step" 用增量 GC；省略时执行完整 GC（=mem! 的默认行为）。
function M.clear_all(conservative, over_watermark, gc_mode)
    local cleared = 0
    local failed = 0
    for _, name in ipairs(order) do
        local entries = cleaners[name]
        if entries then
            for _, entry in ipairs(entries) do
                local skip = false
                if conservative then
                    if entry.essential == true then
                        skip = true
                    elseif entry.essential == "pressure" then
                        skip = not over_watermark
                    end
                end
                if not skip then
                    local ok, did_clear = pcall(entry.fn)
                    if ok then
                        if did_clear ~= false then
                            cleared = cleared + 1
                        end
                    else
                        failed = failed + 1
                    end
                end
            end
        end
    end

    -- =mem! 保持完整回收；低水位哨兵传入 step，避免每次收起键盘都造成长暂停。
    if gc_mode == "step" then
        collectgarbage("step", 64)
    else
        collectgarbage("collect")
    end
    return cleared, failed
end

function M.names()
    local names = {}
    for _, name in ipairs(order) do
        if cleaners[name] and #cleaners[name] > 0 then
            names[#names + 1] = name
        end
    end
    return names
end

return M
