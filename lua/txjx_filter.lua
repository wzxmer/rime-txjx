-- 优化版filter  来源：@浮生 https://github.com/wzxmer/rime-txjx
-- 常量定义（维护性提升）
local DEFAULT_HINT_TEXT = "🚫"
local CONFIG_KEYS = {
    TOPUP_THIS = "topup/topup_this",
    TOPUP_WITH = "topup/topup_with",
    DICT = "translator/dictionary",
    HINT_TEXT = "hint_text"
}

-- 局部化标准库函数（性能优化）
local string_gsub = string.gsub
local string_sub = string.sub
local string_match = string.match
local utf8_len = utf8.len

-- 模块容器
local M = {}

-- 性能常量
local MAX_CACHE_SIZE = 200  -- 缓存最大条目数，防止内存无限增长

--- 安全转义正则特殊字符（保持原始转义逻辑）
local function escape_pattern(s)
    return s and string_gsub(s, "([%-%]%^])", "%%%1") or ""
end

--- 字符串前缀匹配（保持原始逻辑）
local function startswith(str, start)
    if type(str) ~= "string" or type(start) ~= "string" then return false end
    if #start == 0 then return true end
    if #str < #start then return false end
    return string_sub(str, 1, #start) == start
end

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

    -- 直接使用 env 属性，避免创建临时 table
    local hint_text = env.cached_hint_text
    local s_escaped = env.cached_s_escaped
    local b_escaped = env.cached_b_escaped

    -- 提前计算提交提示状态（保持原始逻辑）
    local no_commit = (input_len < 4 and s_escaped ~= '' and string_match(input_text, "^["..s_escaped.."]+$")) or 
                     (b_escaped ~= '' and string_match(input_text, "^["..b_escaped.."]+$"))

    -- 性能优化：如果不需要任何处理，直接透传所有候选（学习 wanxiang）
    if not is_danzi_mode and not show_hint and not no_commit then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    -- 清空查询缓存（每次输入变化时重置）
    -- 性能优化：如果缓存过大，触发垃圾回收
    if env.lookup_cache and next(env.lookup_cache) then
        local count = 0
        for _ in pairs(env.lookup_cache) do count = count + 1 end
        if count > MAX_CACHE_SIZE then
            collectgarbage("step", 100)  -- 增量垃圾回收，不阻塞
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
    env.cached_reverse_lookup = ReverseLookup(config:get_string(CONFIG_KEYS.DICT) or "")
    
    -- 预转义字符（性能优化）
    env.cached_s_escaped = escape_pattern(env.cached_s)
    env.cached_b_escaped = escape_pattern(env.cached_b)
    
    -- 初始化查询缓存表（学习 wanxiang 的 memoization）
    env.lookup_cache = {}
end

-- 清理函数：释放资源并触发垃圾回收（学习 wanxiang）
function M.fini(env)
    env.cached_reverse_lookup = nil
    env.lookup_cache = nil
    env.cached_s = nil
    env.cached_b = nil
    env.cached_s_escaped = nil
    env.cached_b_escaped = nil
    env.cached_hint_text = nil
    collectgarbage("collect")  -- 主动触发完整垃圾回收
end

return { init = M.init, func = M.filter, fini = M.fini }

