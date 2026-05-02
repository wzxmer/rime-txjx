-- 天行键反查读音/编码展示
-- 统一处理 ` / v / o 三种模式的单字候选注释，格式为 [读音 | 编码]。
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-05-02

local M = {}

local DEFAULT_LOOKUP_CACHE_LIMIT = 256
local MAX_LOOKUP_CACHE_LIMIT = 512
local MIN_LOOKUP_CACHE_LIMIT = 64
local DEFAULT_OPEN_RETRY_INTERVAL = 0.25
local DEFAULT_DICT_KEYWORDS = { "txjx" }
local DEFAULT_DICT_SUFFIX = {
    pron = "cx",
    erfen = "danzi",
    gbk = "gbk"
}

local shared_reverse_handles = {}
local shared_open_failed_at = {}
local shared_lookup_cache = {}
local shared_lookup_cache_count = 0
local active_envs = 0

local function clear_lookup_cache()
    shared_lookup_cache = {}
    shared_lookup_cache_count = 0
end

local function close_shared_reverse_handle(dict_name)
    if not dict_name then
        return
    end
    local handle = shared_reverse_handles[dict_name]
    if handle and handle.close then
        pcall(function() handle:close() end)
    end
    shared_reverse_handles[dict_name] = nil
end

local function release_all_shared_state()
    for dict_name in pairs(shared_reverse_handles) do
        close_shared_reverse_handle(dict_name)
    end
    shared_open_failed_at = {}
    clear_lookup_cache()
    collectgarbage("step", 64)
end

local function release_runtime_state(env)
    if env then
        env._last_mode = nil
    end
    release_all_shared_state()
end

local function trim(s)
    if type(s) ~= "string" then
        return nil
    end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return nil
    end
    return s
end

local function push_unique_value(list, seen, value)
    value = trim(value)
    if value and not seen[value] then
        list[#list + 1] = value
        seen[value] = true
    end
end

local function split_keywords(raw)
    if type(raw) ~= "string" then
        return {}
    end
    raw = raw:gsub("[，；|]+", ",")
    local keywords = {}
    local seen = {}
    for value in raw:gmatch("[^,%s]+") do
        push_unique_value(keywords, seen, value)
    end
    return keywords
end

local function build_default_dict_keywords(schema_id)
    local keywords = {}
    local seen = {}
    if schema_id and schema_id ~= "" and schema_id ~= DEFAULT_DICT_KEYWORDS[1] then
        push_unique_value(keywords, seen, schema_id)
    end
    for _, keyword in ipairs(DEFAULT_DICT_KEYWORDS) do
        push_unique_value(keywords, seen, keyword)
    end
    return keywords
end

local function build_dict_name(keyword, suffix)
    keyword = trim(keyword)
    suffix = trim(suffix)
    if not keyword or not suffix then
        return nil
    end
    return keyword .. "." .. suffix
end

local function build_dict_names(keywords, suffix)
    local dict_names = {}
    local seen = {}
    for _, keyword in ipairs(keywords or {}) do
        local dict_name = build_dict_name(keyword, suffix)
        if dict_name and not seen[dict_name] then
            dict_names[#dict_names + 1] = dict_name
            seen[dict_name] = true
        end
    end
    return dict_names
end

local function resolve_dict_names(config, config_key, shared_keywords, suffix)
    local explicit = trim(config:get_string(config_key))
    if explicit then
        return { explicit }
    end
    return build_dict_names(shared_keywords, suffix)
end

local function get_first_config_string(config, keys)
    for _, key in ipairs(keys or {}) do
        local value = trim(config:get_string(key))
        if value then
            return value
        end
    end
    return nil
end

local function extract_pron(lookup_result)
    if type(lookup_result) ~= "string" or lookup_result == "" then
        return nil
    end
    return trim(lookup_result:match("%(([^)]+)%)") or lookup_result:match("（([^）]+)）"))
end

local function normalize_code(code)
    code = trim(code)
    if not code then
        return nil
    end
    code = code:gsub("^%(([^)]+)%)%s*", "")
    code = code:gsub("^（([^）]+)）%s*", "")
    code = code:gsub("^%[", ""):gsub("%]$", "")
    code = code:gsub("%s+", " ")
    code = trim(code)
    if not code then
        return nil
    end
    code = code:gsub(" *, *", ", ")
    code = code:gsub(" +", ", ")
    return trim(code)
end

local function ensure_reverse_handle(dict_name, retry_interval, force_retry)
    if not dict_name or dict_name == "" then
        return nil
    end

    local handle = shared_reverse_handles[dict_name]
    if handle then
        return handle
    end

    local now = os.clock()
    local failed_at = shared_open_failed_at[dict_name]
    if not force_retry and failed_at and now - failed_at < retry_interval then
        return nil
    end

    local ok, db = pcall(ReverseLookup, dict_name)
    if ok and db then
        shared_reverse_handles[dict_name] = db
        shared_open_failed_at[dict_name] = nil
        return db
    end

    shared_open_failed_at[dict_name] = now
    return nil
end

local function ensure_any_reverse_handle(dict_names, retry_interval, force_retry)
    for _, dict_name in ipairs(dict_names or {}) do
        local handle = ensure_reverse_handle(dict_name, retry_interval, force_retry)
        if handle then
            return handle, dict_name
        end
    end
    return nil
end

local function lookup_value(dict_names, text, env)
    if not text or utf8.len(text) ~= 1 then
        return nil
    end

    for _, dict_name in ipairs(dict_names or {}) do
        local cache_key = dict_name .. "\0" .. text
        local cached = shared_lookup_cache[cache_key]
        if cached ~= nil then
            if cached then
                return cached
            end
        else
            local db = ensure_reverse_handle(dict_name, env._open_retry_interval, false)
            if db then
                local ok, value = pcall(function()
                    return db:lookup(text)
                end)
                if not ok then
                    close_shared_reverse_handle(dict_name)
                    shared_open_failed_at[dict_name] = os.clock()
                else
                    if shared_lookup_cache_count >= env._lookup_cache_limit then
                        clear_lookup_cache()
                    end
                    shared_lookup_cache[cache_key] = value or false
                    shared_lookup_cache_count = shared_lookup_cache_count + 1
                    if value and value ~= "" then
                        return value
                    end
                end
            end
        end
    end
    return nil
end

local function get_segment(env)
    local ctx = env.engine.context
    return ctx and ctx.composition and ctx.composition:back() or nil
end

local function segment_has_tag(seg, tag)
    if not seg or not tag or tag == "" then
        return false
    end
    if seg.has_tag then
        local ok, has_tag = pcall(function()
            return seg:has_tag(tag)
        end)
        if ok and has_tag then
            return true
        end
    end
    return seg.tag == tag
end

local function get_mode(env)
    local seg = get_segment(env)
    if not seg then
        return nil
    end
    if segment_has_tag(seg, "reverse_lookup") then
        return "reverse_lookup"
    end
    if segment_has_tag(seg, env.erfen_tag) then
        return "jderfen"
    end
    if segment_has_tag(seg, env.gbk_tag) then
        return "gbk"
    end
    return nil
end

local function get_code_dict_names(env, mode)
    if mode == "jderfen" then
        return env.erfen_code_dict_names
    end
    if mode == "gbk" then
        return env.gbk_code_dict_names
    end
    if mode == "reverse_lookup" then
        return env.reverse_code_dict_names
    end
    return nil
end

local function get_candidate_code(cand, env, mode)
    if mode == "reverse_lookup" then
        return normalize_code(cand.comment)
    end
    local code_dict_names = get_code_dict_names(env, mode)
    return normalize_code(lookup_value(code_dict_names, cand.text, env))
end

local function merge_comment(pron, code)
    if pron and code then
        return "[" .. pron .. " | " .. code .. "]"
    end
    if pron then
        return "[" .. pron .. "]"
    end
    if code then
        return "[" .. code .. "]"
    end
    return nil
end

function M.func(input, env)
    local mode = get_mode(env)
    if mode and mode ~= env._last_mode then
        ensure_any_reverse_handle(env.pron_dict_names, env._open_retry_interval, true)
        local code_dict_names = get_code_dict_names(env, mode)
        if mode ~= "reverse_lookup" then
            ensure_any_reverse_handle(code_dict_names, env._open_retry_interval, true)
        end
    end
    env._last_mode = mode

    if not mode then
        release_runtime_state(env)
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    for cand in input:iter() do
        if cand.text and utf8.len(cand.text) == 1 then
            local pron = extract_pron(lookup_value(env.pron_dict_names, cand.text, env))
            local code = get_candidate_code(cand, env, mode)
            local merged = merge_comment(pron, code)
            if merged then
                cand:get_genuine().comment = merged
            end
        end
        yield(cand)
    end
end

function M.fini(env)
    if env._update_conn then
        env._update_conn:disconnect()
        env._update_conn = nil
    end
    if env._commit_conn then
        env._commit_conn:disconnect()
        env._commit_conn = nil
    end
    env._last_mode = nil
    if active_envs > 0 then
        active_envs = active_envs - 1
    end
    if active_envs == 0 then
        release_all_shared_state()
    end
end

function M.init(env)
    local config = env.engine.schema.config
    local lookup_cache_limit = config:get_int("pron_cache_limit") or DEFAULT_LOOKUP_CACHE_LIMIT
    if lookup_cache_limit < MIN_LOOKUP_CACHE_LIMIT then
        lookup_cache_limit = MIN_LOOKUP_CACHE_LIMIT
    elseif lookup_cache_limit > MAX_LOOKUP_CACHE_LIMIT then
        lookup_cache_limit = MAX_LOOKUP_CACHE_LIMIT
    end

    env.schema_id = env.engine.schema.schema_id
    env.is_xmjd = env.schema_id and env.schema_id:find("xmjd", 1, true) ~= nil
    env.erfen_tag = env.is_xmjd and "quanpinerfen" or "jderfen"
    env.gbk_tag = get_first_config_string(config, { "gbk/tag" }) or "gbk"
    env.dict_keywords = split_keywords(get_first_config_string(config, { "dict_keywords", "reverse_dict_keywords" }))
    if #env.dict_keywords == 0 then
        env.dict_keywords = build_default_dict_keywords(env.schema_id)
    end

    env._lookup_cache_limit = lookup_cache_limit
    env._open_retry_interval = DEFAULT_OPEN_RETRY_INTERVAL
    env.pron_dict_names = resolve_dict_names(config, "reverse_hint/dictionary", env.dict_keywords, DEFAULT_DICT_SUFFIX.pron)
    env.reverse_code_dict_names = resolve_dict_names(config, "reverse_lookup/dictionary", env.dict_keywords, DEFAULT_DICT_SUFFIX.erfen)
    env.erfen_code_dict_names = resolve_dict_names(config, "jderfen_lookup/dictionary", env.dict_keywords, DEFAULT_DICT_SUFFIX.erfen)
    env.gbk_code_dict_names = resolve_dict_names(config, "gbk_lookup/dictionary", env.dict_keywords, DEFAULT_DICT_SUFFIX.gbk)
    env._last_mode = nil
    local ctx = env.engine.context
    env._update_conn = ctx.update_notifier:connect(function(context)
        if not context:is_composing() then
            release_runtime_state(env)
        end
    end)
    env._commit_conn = ctx.commit_notifier:connect(function()
        release_runtime_state(env)
    end)

    active_envs = active_envs + 1
end

return M
