-- 天行键统一按键处理器 (性能优化版)
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-02-16 使用请注明出处

local string_sub = string.sub
local string_match = string.match
local string_find = string.find
local string_char = string.char
local string_len = string.len
local type = type

local kAccepted = 1
local kNoop = 2

local ctx_option_handlers = setmetatable({}, { __mode = "k" })

local function _s2set(str)
    local t = {}
    if type(str) ~= "string" then return t end
    for i = 1, string_len(str) do t[string_sub(str,i,i)] = true end
    return t
end

local _SymCN = {
    ["slash"]      = { plain = "/", shift = "？" },
    ["backslash"]  = { plain = "、", shift = "·" },
    ["minus"]      = { plain = "-", shift = "——" },
    ["equal"]      = { plain = "＝", shift = "+" },
    ["semicolon"]  = { plain = "；", shift = "：" },
    ["apostrophe"] = { plain = "‘", shift = "“" },
    ["bracketleft"]  = { plain = "【", shift = "{" },
    ["bracketright"] = { plain = "】", shift = "}" },
    ["comma"]      = { plain = "，", shift = "《" },
    ["period"]     = { plain = "。", shift = "》" },
    ["grave"]      = { plain = "·", shift = "～" },
}

local _SmOff = {
    ["semicolon"]  = { plain = ";", shift = ":" },
    ["apostrophe"] = { plain = "'", shift = "\"" },
}

local _JsOff = { ["equal"] = { plain = "=", shift = "+" } }

local _KA = {
    ["/"] = "slash", ["?"] = "slash", ["slash"] = "slash", ["question"] = "slash",
    ["\\"] = "backslash", ["|"] = "backslash", ["backslash"] = "backslash", ["bar"] = "backslash",
    ["-"] = "minus", ["_"] = "minus", ["minus"] = "minus", ["underscore"] = "minus",
    [";"] = "semicolon", [":"] = "semicolon", ["semicolon"] = "semicolon", ["colon"] = "semicolon",
    ["'"] = "apostrophe", ["\""] = "apostrophe", ["apostrophe"] = "apostrophe", ["quotedbl"] = "apostrophe",
    ["="] = "equal", ["+"] = "equal", ["equal"] = "equal", ["plus"] = "equal",
    ["["] = "bracketleft", ["{"] = "bracketleft", ["bracketleft"] = "bracketleft",
    ["]"] = "bracketright", ["}"] = "bracketright", ["bracketright"] = "bracketright",
    ["braceleft"] = "bracketleft", ["braceright"] = "bracketright",
    [","] = "comma", ["<"] = "comma", ["comma"] = "comma", ["less"] = "comma",
    ["."] = "period", [">"] = "period", ["period"] = "period", ["greater"] = "period",
    ["`"] = "grave", ["~"] = "grave", ["grave"] = "grave",
    ["asciitilde"] = "grave", ["dead_tilde"] = "grave", ["dead_grave"] = "grave"
}

local _KC = {
    [0xBA] = "semicolon", [0xBB] = "equal", [0xBC] = "comma", [0xBD] = "minus",
    [0xBE] = "period", [0xBF] = "slash", [0xC0] = "grave", [0xDB] = "bracketleft",
    [0xDC] = "backslash", [0xDD] = "bracketright", [0xDE] = "apostrophe",
}

local _SN = {
    ["<"]=1, [">"]=1, ["?"]=1, ["|"]=1, ["{"]=1, ["}"]=1, [":"]=1, ["\""]=1,
    ["less"]=1, ["greater"]=1, ["question"]=1, ["bar"]=1,
    ["braceleft"]=1, ["braceright"]=1, ["colon"]=1, ["quotedbl"]=1,
    ["_"]=1, ["underscore"]=1, ["+"]=1, ["plus"]=1
}

local function _nk(key)
    if type(key) ~= "string" then return key end
    local l = key:lower()
    return _KA[l] or _KA[key] or l
end

local function _tdc(map, kn, sf, engine, ctx)
    local c = map[kn]
    if not c then return false end
    local sym = sf and c.shift or c.plain
    if not sym then return false end
    if ctx:is_composing() then ctx:commit() end
    engine:commit_text(sym)
    return true
end

local function _topup_exec(env)
    if env._tc then
        env._tc = env._tc + 1
        if env._tc > 80 and env._tc % 3 ~= 0 then return end
    elseif env._tc_pending then
        env._tc_pending = false
        local rv = env.engine.context:get_property("_rvk")
        if not rv or rv == "" then env._tc = 0 end
    end
    if not env.engine.context:get_selected_candidate() then
        if env._tu_ac then env.engine.context:clear() end
    else
        env.engine.context:commit()
    end
end

local function _resolve_key(key_event, env)
    local raw_key = key_event:repr()
    local clean_key = raw_key
    if type(raw_key) == "string" then clean_key = string_match(raw_key, "^[Ss]hift%+(.*)") or raw_key end
    local kn = _nk(clean_key)
    local keycode = key_event.keycode
    local kcn = _KC[keycode]
    if kcn then kn = kcn end
    local sf = key_event:shift()
    if not key_event:release() then
        if kcn then
            env._ks = env._ks or {}
            env._ks[keycode] = sf
        end
    else
        if env._ks and env._ks[keycode] ~= nil then
            sf = env._ks[keycode]
            env._ks[keycode] = nil
        end
    end
    if type(raw_key) == "string" and _SN[raw_key] then sf = true end
    if type(raw_key) == "string" then
        if string_find(raw_key, "tilde") or string_find(raw_key, "grave") then kn = "grave" end
    end
    if kn == "grave" and (raw_key == "~" or raw_key == "asciitilde" or raw_key == "dead_tilde" or (type(raw_key) == "string" and string_find(raw_key, "tilde"))) then
        sf = true
    end
    return kn, sf, clean_key, raw_key
end

local function _smart_process(key_event, env, kn, sf, clean_key, opts)
    if key_event:alt() or key_event:super() then return kNoop end
    local ctx = env.engine.context
    local engine = env.engine

    if kn == "grave" and not sf and not key_event:ctrl() then
        if key_event:release() then
            return kAccepted
        end
        ctx:push_input("`")
        return kAccepted
    end

    if not key_event:release() and not sf then
        local input = ctx.input
        if type(input) == "string" and input == "-" then
            local ch = string_char(key_event.keycode)
            if string_match(ch, "^[0-9]$") then
                ctx:commit()
                engine:commit_text(ch)
                return kAccepted
            end
        end
    end

    local fs_on = opts.direct_symbols
    local ds_on = not fs_on

    if key_event:release() then
        env._hr = true
        if env._sw == kn then env._sw = nil; return kAccepted end
        if ds_on then
            if env._dc == kn then env._dc = nil; return kAccepted end
            if env._dc ~= kn then
                if _tdc(_SymCN, kn, sf, env.engine, ctx) then env._dc = kn; return kAccepted end
            end
            env._dc = nil
        end
        if not ds_on then
            local input = ctx.input
            if type(input) == "string" and string_match(input, "^;[a-z]$") then
                if ctx:has_menu() then
                    local comp = ctx.composition:back()
                    if comp and comp.menu then
                        if not comp.menu:get_candidate_at(1) then
                            local cand = ctx:get_selected_candidate()
                            local ct = cand and cand.text
                            if ct and ct ~= ";" and ct ~= "；" then ctx:commit(); return kAccepted end
                        end
                    end
                end
            end
        end
        return kNoop
    end

    env._dc = nil

    if not opts.smarttwo and not ds_on and not sf and kn == "semicolon" then
        local inp = ctx.input
        if type(inp) == "string" and inp ~= "" and not string_match(inp, ";") then
            if ctx:has_menu() and ctx:get_selected_candidate() then
                ctx:commit()
                ctx:push_input(";")
                env._sw = kn
                return kAccepted
            end
        end
    end

    if not ds_on then
        local inp = ctx.input
        if not env._hr and type(inp) == "string" and inp == ";" then
            if type(clean_key) == "string" and string_match(clean_key, "^[A-Za-z]$") then
                local ch = clean_key:lower()
                ctx:push_input(ch)
                if ctx:has_menu() then
                    local comp = ctx.composition:back()
                    local hs = comp and comp.menu and comp.menu:get_candidate_at(1) ~= nil
                    if not hs then
                        local cand = ctx:get_selected_candidate()
                        local ct = cand and cand.text
                        if ct and ct ~= ";" and ct ~= "；" then ctx:commit(); return kAccepted end
                    end
                end
                ctx:pop_input(1)
            end
        end
    end

    if ctx:has_menu() and opts.smarttwo then
        if (kn == "semicolon" or kn == "apostrophe") and not sf then
            if env._tu_streaming then
                return kNoop
            end
            local comp = ctx.composition:back()
            if comp then
                local ps = env.engine.schema.page_size or 5
                if ps == 0 then ps = 5 end
                local si = comp.selected_index
                local pst = math.floor(si / ps) * ps
                local idx = (kn == "semicolon") and 1 or 2
                if ctx:select(pst + idx) then ctx:commit(); return kAccepted end
                if not ctx:get_selected_candidate() then
                     if #ctx.input > 1 then ctx:commit(); return kAccepted end
                else
                     ctx:commit(); return kAccepted
                end
            end
        end
    end

    if ds_on then
        local skip = (kn == "equal" and not sf and opts.jisuanqi)
        if not skip then
            if _tdc(_SymCN, kn, sf, env.engine, ctx) then env._dc = kn; return kAccepted end
        end
    end

    if not opts.jisuanqi then
        if kn == "equal" or kn == "minus" then
            if ctx:has_menu() and not sf then
                return kNoop
            end
        end
        if _tdc(_JsOff, kn, sf, env.engine, ctx) then return kAccepted end
    end

    if not opts.smarttwo then
        if kn == "semicolon" and not sf then return kNoop end
        if _tdc(_SmOff, kn, sf, env.engine, ctx) then return kAccepted end
    end

    return kNoop
end

local function processor(key_event, env)
    local kn, sf, clean_key = _resolve_key(key_event, env)
    local ctx = env.engine.context
    
    local opts = env._opt or {
        smarttwo = ctx:get_option("smarttwo"),
        direct_symbols = ctx:get_option("direct_symbols"),
        jisuanqi = ctx:get_option("jisuanqi"),
        auto_fallback = ctx:get_option("auto_fallback"),
        danzi_mode = ctx:get_option("danzi_mode"),
    }

    local sm_result = _smart_process(key_event, env, kn, sf, clean_key, opts)
    if sm_result == kAccepted then return kAccepted end

    local kc = key_event.keycode
    if key_event:release() and (kc == 0xffe3 or kc == 0xffe4) then
        if ctx:has_menu() then
            if ctx:select(1) then ctx:commit() end
            return kAccepted
        end
    end
    if key_event:release() and (kc == 0xffe9 or kc == 0xffea) then
        if ctx:has_menu() then
            if ctx:select(2) then ctx:commit() end
            return kAccepted
        end
    end

    if key_event:release() or key_event:ctrl() or key_event:alt() then return kNoop end
    local ch = key_event.keycode
    if ch < 0x20 or ch >= 0x7f then return kNoop end
    local key = string_char(ch)

    if opts.auto_fallback and env._alpha[key] then
        local current_input = ctx.input
        if #current_input >= 1 and ctx:get_selected_candidate() then
            local skip_fb = false
            if opts.direct_symbols then
                if type(current_input) == "string" and current_input == ";" then skip_fb = true end
            end
            if not skip_fb then
                ctx:push_input(key)
                if ctx:get_selected_candidate() then return kAccepted end
                ctx:pop_input(1)
                ctx:commit()
                ctx:push_input(key)
                return kAccepted
            end
        end
    end

    if not env._tu_streaming and env._alpha[key] then
        local current_input = ctx.input
        local input_len = #current_input
        local min_len = env._tu_min
        if opts.danzi_mode then min_len = env._tu_min_dz end
        local prev = string_sub(current_input, -1)
        local first = string_sub(current_input, 1, 1)
        if #first == 0 then first = key end
        local is_tu = env._tu_set[key] or false
        local is_ptu = env._tu_set[prev] or false
        local is_ftu = env._tu_set[first] or false
        if not (env._tu_cmd and is_ftu) then
            local skip_tu = false
            if opts.direct_symbols then
                if input_len > 0 and string_sub(current_input, 1, 1) == ";" then skip_tu = true end
            end
            if not skip_tu then
                if is_ptu and not is_tu then
                    _topup_exec(env)
                elseif not is_ptu and not is_tu and input_len >= min_len then
                    _topup_exec(env)
                elseif input_len >= env._tu_max then
                    _topup_exec(env)
                end
            end
        end
    end

    return kNoop
end

local function init(env)
    local config = env.engine.schema.config
    local ctx = env.engine.context

    if env._option_handler and ctx.option_update_notifier then
        pcall(function() ctx.option_update_notifier:disconnect(env._option_handler) end)
    end
    if ctx_option_handlers[ctx] and ctx.option_update_notifier then
        pcall(function() ctx.option_update_notifier:disconnect(ctx_option_handlers[ctx]) end)
    end
    env._option_handler = nil
    ctx_option_handlers[ctx] = nil

    local function read_opt(name, default)
        local v = ctx:get_option(name)
        if v == nil then return default end
        return v
    end
    
    env._opt = {
        smarttwo = read_opt("smarttwo", false),
        direct_symbols = read_opt("direct_symbols", false),
        jisuanqi = read_opt("jisuanqi", false),
        auto_fallback = read_opt("auto_fallback", false),
        danzi_mode = read_opt("danzi_mode", false),
    }

    if ctx.option_update_notifier then
        local function on_option(context, name)
            if name == "smarttwo" or name == "direct_symbols" or name == "jisuanqi"
                or name == "auto_fallback" or name == "danzi_mode" then
                env._opt[name] = context:get_option(name)
            end
        end
        env._option_handler = on_option
        ctx_option_handlers[ctx] = on_option
        ctx.option_update_notifier:connect(on_option)
    end

    env._ks = {}
    env._hr = false
    env._sw = nil
    env._dc = nil
    local ab = config:get_string("speller/alphabet") or "abcdefghijklmnopqrstuvwxyz"
    env._alpha = {}
    for i = 1, #ab do env._alpha[string_sub(ab,i,i)] = true end
    env._tu_set = _s2set(config:get_string("topup/topup_with") or "")
    env._tu_min = config:get_int("topup/min_length") or 4
    env._tu_min_dz = config:get_int("topup/min_length_danzi") or env._tu_min
    env._tu_max = config:get_int("topup/max_length") or 6
    env._tu_ac = config:get_bool("topup/auto_clear") or false
    env._tu_cmd = config:get_bool("topup/topup_command") or false
    env._tu_streaming = config:get_bool("translator/enable_sentence") or false
    env._tc = nil
    env._tc_pending = true
end

local function fini(env)
    local ctx = env.engine and env.engine.context
    if ctx then
        if env._option_handler and ctx.option_update_notifier then
            pcall(function() ctx.option_update_notifier:disconnect(env._option_handler) end)
        end
        ctx_option_handlers[ctx] = nil
    end
    env._option_handler = nil
    env._opt = nil

    env._ks = nil
    env._dc = nil
    env._hr = nil
    env._sw = nil
    env._alpha = nil
    env._tu_set = nil
    env._tu_min = nil
    env._tu_min_dz = nil
    env._tu_max = nil
    env._tu_ac = nil
    env._tu_cmd = nil
    env._tu_streaming = nil
    env._tc = nil
    env._tc_pending = nil
end

return { init = init, func = processor, fini = fini }
