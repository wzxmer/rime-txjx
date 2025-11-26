-- 优化版filter  来源：@浮生 https://github.com/wzxmer/rime-txjx

-- 工具函数
local function escape_pattern(s)
    if not s then return "" end
    return s:gsub("([%-%]%^])", "%%%1")
end

local function startswith(str, prefix)
    if type(str) ~= "string" or type(prefix) ~= "string" then
        return false
    end
    return str:sub(1, #prefix) == prefix
end

-- 常量定义（维护性提升）
local DEFAULT_HINT_TEXT = "🚫"
local CONFIG_KEYS = {
    TOPUP_THIS = "topup/topup_this",
    TOPUP_WITH = "topup/topup_with",
    DICT = "translator/dictionary",
    HINT_TEXT = "hint_text"
}

-- 局部化标准库函数（性能优化）
local string_match = string.match
local utf8_len = utf8.len

-- 模块容器
local M = {}

-- 性能常量
local GC_INTERVAL = 200  -- 每处理 200 个候选词触发一次 GC

--- 带缓存的提示匹配（保持原始匹配顺序）
local function hint_optimized(cand, env)
    local cand_text = cand.text
    if utf8_len(cand_text) < 2 then return false end
    
    -- 性能优化：使用缓存避免重复查询同一个词
    if env.lookup_cache[cand_text] ~= nil then
        local cached_short = env.lookup_cache[cand_text]
        if cached_short then
            local genuine = cand:get_genuine()
            genuine.comment = (genuine.comment or "") .. " = " .. cached_short
            return true
        end
        return false
    end
    
    local context = env.engine.context
    
    -- 延迟创建 ReverseLookup 对象（仅在需要时创建）
    if not env.cached_reverse_lookup then
        local config = env.engine.schema.config
        env.cached_reverse_lookup = ReverseLookup(config:get_string(CONFIG_KEYS.DICT) or "")
    end
    local reverse = env.cached_reverse_lookup
    
    local s = env.cached_s_escaped or ''
    local b = env.cached_b_escaped or ''
    if s == '' and b == '' then 
        env.lookup_cache[cand_text] = false
        return false 
    end
    
    -- 添加 nil 检查，防止 lookup 返回 nil
    local lookup_result = reverse:lookup(cand_text)
    if not lookup_result then 
        env.lookup_cache[cand_text] = false
        return false 
    end
    local lookup = " " .. lookup_result .. " "
    local short
    
    -- 严格保持原始匹配顺序
    if #s > 0 and #b > 0 then
        short = string_match(lookup, " (["..s.."]["..s.."]["..b.."]) ") or
                string_match(lookup, " (["..b.."]["..b.."]["..b.."]) ") or
                string_match(lookup, " (["..s.."]["..b.."]+) ") or
                string_match(lookup, " (["..s.."]["..s.."]) ")
    elseif #s > 0 then
        short = string_match(lookup, " (["..s.."]["..s.."]) ")
    elseif #b > 0 then
        short = string_match(lookup, " (["..b.."]["..b.."]) ")
    end
    
    local input = context.input 
    if short and utf8_len(input) > utf8_len(short) and not startswith(short, input) then
        env.lookup_cache[cand_text] = short  -- 缓存成功的查询结果
        local genuine = cand:get_genuine()
        genuine.comment = (genuine.comment or "") .. " = " .. short
        return true
    end
    env.lookup_cache[cand_text] = false  -- 缓存失败的查询结果
    return false
end

--- 单字模式判断（保持原始逻辑）
local function is_danzi_candidate(cand)
    return utf8_len(cand.text) < 2
end

--- 提交提示处理（保持原始逻辑）
local function apply_commit_hint(cand, hint_text)
    cand:get_genuine().comment = hint_text .. (cand.comment or "")
end

function M.filter(input, env)
    -- 环境变量一次性读取（性能优化）
    local context = env.engine.context
    local is_danzi_mode = context:get_option('danzi_mode')
    local show_hint = context:get_option('sbb_hint')
    local input_text = context.input
    local input_len = #input_text

    -- 反查模式检测：如果在反查，禁用提示功能以节省内存
    local is_reverse_lookup = input_text:match("`")
    if is_reverse_lookup then
        -- 反查时直接透传，不处理提示
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    -- 直接使用 env 属性，避免创建临时 table
    local hint_text = env.cached_hint_text
    local s_escaped = env.cached_s_escaped
    local b_escaped = env.cached_b_escaped

    -- 提前计算提交提示状态（保持原始逻辑）
    local no_commit = (input_len < 4 and s_escaped ~= '' and string_match(input_text, "^["..s_escaped.."]+$")) or 
                     (b_escaped ~= '' and string_match(input_text, "^["..b_escaped.."]+$"))

    -- 性能优化：如果不需要任何处理，直接透传所有候选
    if not is_danzi_mode and not show_hint and not no_commit then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    -- 清空查询缓存（每次输入变化时重置）
    -- 激进的内存管理：彻底清空旧缓存
    if env.lookup_cache then
        for k in pairs(env.lookup_cache) do
            env.lookup_cache[k] = nil
        end
    end
    env.lookup_cache = {}

    -- 候选词处理（保持原始流程）
    local is_first = true
    for cand in input:iter() do
        
        -- 首候选提交提示
        if is_first and no_commit then
            apply_commit_hint(cand, hint_text)
        end
        is_first = false
        
        -- 单字模式过滤和提示处理
        if not is_danzi_mode or is_danzi_candidate(cand) then
            if show_hint then
                hint_optimized(cand, env)
            end
            yield(cand)
        end
    end
end

function M.init(env)
    local config = env.engine.schema.config
    
    -- 配置读取与缓存（保持原始功能）
    env.cached_s = config:get_string(CONFIG_KEYS.TOPUP_THIS) or ""
    env.cached_b = config:get_string(CONFIG_KEYS.TOPUP_WITH) or ""
    env.cached_hint_text = config:get_string(CONFIG_KEYS.HINT_TEXT) or DEFAULT_HINT_TEXT
    
    -- 清理旧的查询缓存（切换 APP 时释放内存）
    if env.lookup_cache then
        for k in pairs(env.lookup_cache) do
            env.lookup_cache[k] = nil
        end
    end
    env.lookup_cache = nil
    
    -- 清理旧的 ReverseLookup 对象（切换 APP 时释放内存）
    env.cached_reverse_lookup = nil
    
    -- 多次触发 GC，确保 C++ 对象被完全释放
    collectgarbage()
    collectgarbage()  -- 第二次确保 finalizer 执行完毕
    
    -- 预转义字符（性能优化）
    env.cached_s_escaped = escape_pattern(env.cached_s)
    env.cached_b_escaped = escape_pattern(env.cached_b)
    
    -- 初始化查询缓存表
    env.lookup_cache = {}
end

-- 清理函数：释放资源并触发垃圾回收
function M.fini(env)
    env.cached_reverse_lookup = nil
    env.lookup_cache = nil
    env.cached_s = nil
    env.cached_b = nil
    env.cached_s_escaped = nil
    env.cached_b_escaped = nil
    env.cached_hint_text = nil
    collectgarbage()
end

return { init = M.init, func = M.filter, fini = M.fini }

