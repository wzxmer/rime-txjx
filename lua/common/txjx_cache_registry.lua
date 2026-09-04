-- 天行键 缓存注册表模块
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-07-02

local M = {}

-- cleaners[name] = { fn = 清理函数, essential = 热路径常驻标记 }
-- essential=true 的清理器只在手动 =mem! 全量释放时执行；
-- 哨兵等自动触发的保守释放会跳过它们，避免频繁重载伤体验。
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
    end
    cleaners[name] = { fn = cleaner, essential = essential and true or false }
    return true
end

function M.unregister(name)
    name = trim_name(name)
    if not name or not cleaners[name] then
        return false
    end
    cleaners[name] = nil
    return true
end

-- conservative=true 时跳过 essential（热路径常驻）清理器
function M.clear_all(conservative)
    local cleared = 0
    local failed = 0
    for _, name in ipairs(order) do
        local entry = cleaners[name]
        if entry then
            if conservative and entry.essential then
                -- 保守模式：保留热路径常驻缓存
            else
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
    collectgarbage("collect")
    return cleared, failed
end

function M.names()
    local names = {}
    for _, name in ipairs(order) do
        if cleaners[name] then
            names[#names + 1] = name
        end
    end
    return names
end

return M
