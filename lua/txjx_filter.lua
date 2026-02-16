-- 优化版候选词过滤器 (修复版)
-- 功能：
--   1. 提示字（sbb_hint）：显示候选词的简码提示
--   2. 单字模式（danzi_mode）：只显示单字候选
--   3. 内存管理：全局引用计数缓存 + 按需加载 + 定期 GC
--   4. 通用适配：自动识别 txjx/xmjd6 方案ID
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-02-16

local reverse_cache = {}

local function acquire_reverse(dict_name)
    if not dict_name then return nil end
    local entry = reverse_cache[dict_name]
    if entry and entry.db then
        entry.ref = entry.ref + 1
        return entry.db
    end
    local db = ReverseLookup(dict_name)
    if db then
        reverse_cache[dict_name] = { db = db, ref = 1 }
        return db
    end
    return nil
end

local function release_reverse(db, dict_name)
    if not dict_name then return false end
    local entry = reverse_cache[dict_name]
    if not entry then return false end
    
    if entry.ref > 0 then
        entry.ref = entry.ref - 1
    end
    
    if entry.ref <= 0 then
        if entry.db and entry.db.close then
            pcall(function() entry.db:close() end)
        end
        reverse_cache[dict_name] = nil
        return true
    end
    return false
end

local function startswith(str, start)
    return string.sub(str, 1, #start) == start
end

local function extract_reading(s)
    if type(s) ~= "string" then return nil end
    local r = s:match("%(([^)]+)%)")
    if not r then
        r = s:match("（([^）]+)）")
    end
    return r
end

local function process_hint(cand, env, input_text)
    if not cand.text then return end
    
    local reverse = env.reverse_core or env.reverse_ext
    if not reverse then return end

    local lookup_result = reverse:lookup(cand.text)
    if not lookup_result then return end

    local lookup = " " .. lookup_result .. " "

    local short = string.match(lookup, env.p1) or
                  string.match(lookup, env.p2) or
                  string.match(lookup, env.p3) or
                  string.match(lookup, env.p4)

    if short then
        local short_len = utf8.len(short)
        local input_len = env._input_len_cache or utf8.len(input_text)

        if input_len > short_len and not startswith(short, input_text) then
            cand:get_genuine().comment = (cand.comment or "") .. " = " .. short
        end
    end
end

local function is_danzi(cand)
    return cand.text and utf8.len(cand.text) < 2
end

local function commit_hint(cand, hint_text)
    cand:get_genuine().comment = hint_text .. (cand.comment or "")
end

local ctx_commit_handlers = setmetatable({}, { __mode = "k" })
local ctx_update_handlers = setmetatable({}, { __mode = "k" })
local ctx_option_handlers = setmetatable({}, { __mode = "k" })

local function update_lazy_reverse(env, context, input_text)
    if not context then return end
    input_text = input_text or ""

    local want_reverse = false

    if input_text == "" then
        if env._reverse_sticky then
            env._reverse_sticky = false
            collectgarbage("collect")
        end
    else
        local len = #input_text
        if string.find(input_text, "`", 1, true) then
            env._reverse_sticky = true
        end
        if env._reverse_sticky then
            want_reverse = true
        else
            local first = string.sub(input_text, 1, 1)
            if (first == "v" or first == "o") and len > 1 then
                want_reverse = true
            elseif env.is_xmjd and first == "u" and len > 1 then
                want_reverse = true
            end
        end
        local seg = context.composition and context.composition:back()
        local tag = seg and seg.tag or ""
        if tag == "reverse_lookup" or tag == env.gbk_tag or tag == env.erfen_tag or tag == "pinyin_simp" then
            want_reverse = true
        end
    end

    local changed = false
    if context:get_option("reverse_lookup") ~= want_reverse then
        context:set_option("reverse_lookup", want_reverse)
        changed = true
    end
    if changed and context.is_composing and context:is_composing() then
        context:refresh_non_confirmed_composition()
    end
end

local function sync_reverse_core(env, on)
    if on then
        if not env.reverse_core then
            env.reverse_core = acquire_reverse(env.core_dict_name)
            if not env.reverse_core and env.dict_name then
                env.reverse_core = acquire_reverse(env.dict_name)
                env._core_using_dict = env.dict_name
            else
                env._core_using_dict = env.core_dict_name
            end
        end
    else
        if env.reverse_core then
            release_reverse(env.reverse_core, env._core_using_dict)
            env.reverse_core = nil
            env._core_using_dict = nil
        end
    end
end

local function sync_reverse_ext(env, on)
    if on then
        if not env.reverse_ext then
            env.reverse_ext = acquire_reverse(env.dict_name)
        end
    else
        if env.reverse_ext then
            if release_reverse(env.reverse_ext, env.dict_name) then
                collectgarbage("collect")
            end
            env.reverse_ext = nil
        end
    end
end

local function filter(input, env)
    local context = env.engine.context
    local input_text = context.input

    local sbb_on = context:get_option("sbb_hint")
    sync_reverse_core(env, sbb_on)
    sync_reverse_ext(env, context:get_option("completion"))

    local danzi_mode = context:get_option('danzi_mode')
    local hint_mode = (env.reverse_core ~= nil or env.reverse_ext ~= nil)

    local hint_text = env.hint_text
    local first = true

    env._input_len_cache = utf8.len(input_text)
    
    local show_commit_hint = false
    if env.s ~= "" and env.b ~= "" then
        local is_short_s = #input_text < 4 and input_text:match("^["..env.s.."]+$")
        local is_all_b = input_text:match("^["..env.b.."]+$")
        if is_short_s or is_all_b then
            show_commit_hint = true
        end
    end

    for cand in input:iter() do
        if first and show_commit_hint then
            commit_hint(cand, hint_text)
        end
        first = false

        if not danzi_mode or is_danzi(cand) then
            if hint_mode then
                local has_reading = extract_reading(cand.comment)
                if not has_reading then
                    process_hint(cand, env, input_text)
                end
            end

            yield(cand)
        end
    end

    env._input_len_cache = nil
end

local function init(env)
    collectgarbage("step", 200)

    local config = env.engine.schema.config
    
    env.schema_id = env.engine.schema.schema_id
    env.is_xmjd = string.find(env.schema_id, "xmjd") ~= nil
    env.gbk_tag = env.schema_id .. "gbk"
    if env.is_xmjd then
        env.erfen_tag = "quanpinerfen"
    else
        env.erfen_tag = "jderfen"
    end

    if env.reverse_core then release_reverse(env.reverse_core, env._core_using_dict) end
    if env.reverse_ext then release_reverse(env.reverse_ext, env.dict_name) end
    if env.reverse_cx then release_reverse(env.reverse_cx, env.cx_name) end
    env.reverse_core = nil
    env.reverse_ext = nil
    env.reverse_cx = nil

    env.dict_name = config:get_string("translator/dictionary")
    if env.dict_name and env.dict_name ~= "" then
        env.core_dict_name = env.dict_name:gsub("%.extended$", ".core")
    else
        env.core_dict_name = nil
    end
    env.b = config:get_string("topup/topup_with") or ""
    env.s = config:get_string("topup/topup_this") or ""
    env.hint_text = config:get_string('hint_text') or '🚫'

    if env.s ~= "" and env.b ~= "" then
        env.p1 = " ([" .. env.s .. "][" .. env.b .. "]+) "
        env.p2 = " ([" .. env.s .. "][" .. env.s .. "]) "
        env.p3 = " ([" .. env.s .. "][" .. env.s .. "][" .. env.b .. "]) "
        env.p4 = " ([" .. env.b .. "][" .. env.b .. "][" .. env.b .. "]) "
    else
        env.p1, env.p2, env.p3, env.p4 = "^$", "^$", "^$", "^$"
    end

    env.commit_counter = 0
    env.reverse_idle_count = 0

    local ctx = env.engine.context

    if env._lazy_rev_handler and ctx.update_notifier then
        pcall(function() ctx.update_notifier:disconnect(env._lazy_rev_handler) end)
    end
    if ctx_update_handlers[ctx] and ctx.update_notifier then
        pcall(function() ctx.update_notifier:disconnect(ctx_update_handlers[ctx]) end)
    end
    env._lazy_rev_handler = nil
    ctx_update_handlers[ctx] = nil

    if env._commit_handler and ctx.commit_notifier then
        pcall(function() ctx.commit_notifier:disconnect(env._commit_handler) end)
    end
    if ctx_commit_handlers[ctx] and ctx.commit_notifier then
        pcall(function() ctx.commit_notifier:disconnect(ctx_commit_handlers[ctx]) end)
    end
    env._commit_handler = nil
    ctx_commit_handlers[ctx] = nil

    if env._option_handler and ctx.option_update_notifier then
        pcall(function() ctx.option_update_notifier:disconnect(env._option_handler) end)
    end
    if ctx_option_handlers[ctx] and ctx.option_update_notifier then
        pcall(function() ctx.option_update_notifier:disconnect(ctx_option_handlers[ctx]) end)
    end
    env._option_handler = nil
    ctx_option_handlers[ctx] = nil

    sync_reverse_core(env, ctx:get_option("sbb_hint"))
    sync_reverse_ext(env, ctx:get_option("completion"))

    local function on_option(context, opname)
        if opname == "sbb_hint" then
            sync_reverse_core(env, context:get_option("sbb_hint"))
        elseif opname == "completion" then
            sync_reverse_ext(env, context:get_option("completion"))
        end
    end
    env._option_handler = on_option
    ctx_option_handlers[ctx] = on_option
    ctx.option_update_notifier:connect(on_option)

    if ctx.update_notifier then
        local function on_update(context)
            update_lazy_reverse(env, context, context.input)
        end
        env._lazy_rev_handler = on_update
        ctx_update_handlers[ctx] = on_update
        ctx.update_notifier:connect(on_update)
        update_lazy_reverse(env, ctx, ctx.input)
    end

    local function on_commit(context)
        env.commit_counter = (env.commit_counter or 0) + 1

        if env.reverse_cx then
            env.reverse_idle_count = (env.reverse_idle_count or 0) + 1
            if env.reverse_idle_count >= 1 then
                if release_reverse(env.reverse_cx, env.cx_name) then
                    collectgarbage("collect")
                end
                env.reverse_cx = nil
                env.reverse_idle_count = 0
                env.commit_counter = 0
            end
        end

        update_lazy_reverse(env, context, "")
    end

    env._commit_handler = on_commit
    ctx_commit_handlers[ctx] = on_commit
    ctx.commit_notifier:connect(on_commit)

    ctx:set_property("_rvk", tostring(os.time()))
end

local function fini(env)
    local ctx = env.engine and env.engine.context

    if ctx then
        if env._commit_handler and ctx.commit_notifier then
            pcall(function() ctx.commit_notifier:disconnect(env._commit_handler) end)
        end
        if env._lazy_rev_handler and ctx.update_notifier then
            pcall(function() ctx.update_notifier:disconnect(env._lazy_rev_handler) end)
        end
        if env._option_handler and ctx.option_update_notifier then
            pcall(function() ctx.option_update_notifier:disconnect(env._option_handler) end)
        end

        ctx_commit_handlers[ctx] = nil
        ctx_update_handlers[ctx] = nil
        ctx_option_handlers[ctx] = nil
    end

    env._commit_handler = nil
    env._lazy_rev_handler = nil
    env._option_handler = nil

    pcall(function()
        if ctx then update_lazy_reverse(env, ctx, "") end
    end)

    if env.reverse_core then release_reverse(env.reverse_core, env._core_using_dict) end
    if env.reverse_ext then release_reverse(env.reverse_ext, env.dict_name) end
    if env.reverse_cx then release_reverse(env.reverse_cx, env.cx_name) end
    
    env.reverse_core = nil
    env.reverse_ext = nil
    env.reverse_cx = nil
    env._core_using_dict = nil

    env.p1, env.p2, env.p3, env.p4 = nil, nil, nil, nil
    env.dict_name = nil
    env.core_dict_name = nil
    env.b = nil
    env.s = nil
    env.hint_text = nil
    env.commit_counter = nil
    env._input_len_cache = nil
    env.schema_id = nil
    env.cx_name = nil
    env.gbk_tag = nil
    env.erfen_tag = nil
    env.is_xmjd = nil

    collectgarbage("step", 200)
end

return { init = init, func = filter, fini = fini }
