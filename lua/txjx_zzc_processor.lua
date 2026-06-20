local core = require("txjx_zzc_core")

local kAccepted = 1
local kNoop = 2

local state = { active = false, stage = "off", items = {}, mode = "make", target_code = "", display_word = "", replaced_word = "", command_candidates = {}, shorten_idx = 1 }
local current_action_candidate
local first_candidate
local reset

local length_keys = {
    ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
    ["三"] = 3, ["四"] = 4, ["五"] = 5, ["六"] = 6,
    ["KP_3"] = 3, ["KP_4"] = 4, ["KP_5"] = 5, ["KP_6"] = 6,
    ["kp_3"] = 3, ["kp_4"] = 4, ["kp_5"] = 5, ["kp_6"] = 6,
}

local index_keys = {
    ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
    ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
    ["KP_1"] = 1, ["KP_2"] = 2, ["KP_3"] = 3, ["KP_4"] = 4, ["KP_5"] = 5,
    ["KP_6"] = 6, ["KP_7"] = 7, ["KP_8"] = 8, ["KP_9"] = 9,
    ["kp_1"] = 1, ["kp_2"] = 2, ["kp_3"] = 3, ["kp_4"] = 4, ["kp_5"] = 5,
    ["kp_6"] = 6, ["kp_7"] = 7, ["kp_8"] = 8, ["kp_9"] = 9,
}

local chinese_index_words = {
    ["一"] = 1, ["二"] = 2, ["三"] = 3, ["四"] = 4, ["五"] = 5,
    ["六"] = 6, ["七"] = 7, ["八"] = 8, ["九"] = 9,
}

local trigger_keys = {
    ["\\"] = true,
    ["backslash"] = true,
    ["Backslash"] = true,
    ["bar"] = true,
    ["|"] = true,
}

local function event_char(key_event)
    local code = key_event.keycode
    if code and code >= 0x20 and code < 0x7f then return string.char(code) end
    return nil
end

local function is_trigger(key, ch)
    if trigger_keys[ch or ""] or trigger_keys[key or ""] then return true end
    if type(key) == "string" then
        local clean = key:match("^[Ss]hift%+(.*)") or key
        return trigger_keys[clean] or trigger_keys[clean:lower()]
    end
    return false
end

local function is_code_char(ch)
    return type(ch) == "string" and ch:match("^[A-Za-z;']$") ~= nil
end

local key_code_char_map = {
    semicolon = ";",
    apostrophe = "'",
}

local function resolve_code_char(key, ch)
    if is_code_char(ch) then return ch end
    if type(key) ~= "string" then return nil end
    local clean = key:match("^[Ss]hift%+(.*)") or key
    if is_code_char(clean) then return clean end
    local lower = clean:lower()
    local mapped = key_code_char_map[lower]
    if mapped and is_code_char(mapped) then return mapped end
    return nil
end

local function strip_zzc_prefix(input)
    input = input or ""
    if input:sub(1, 1) == "\\" then return input:sub(2) end
    return input
end

local function is_space(key)
    return type(key) == "string" and key:lower() == "space"
end

local function is_less_key(key, ch)
    if ch == "<" or ch == "," or key == "less" or key == "Less" or key == "comma" then return true end
    if type(key) == "string" then
        local clean = key:match("^[Ss]hift%+(.*)") or key
        return clean == "<" or clean == "comma" or clean:lower() == "less" or key:match("^[Ss]hift%+comma$")
    end
    return false
end

local function is_minus_key(key, ch)
    if ch == "-" then return true end
    if type(key) ~= "string" then return false end
    local clean = key:match("^[Ss]hift%+(.*)") or key
    local lower = clean:lower()
    return lower == "minus" or lower == "hyphen" or clean == "-"
end

local function is_backspace(key)
    return type(key) == "string" and key:lower() == "backspace"
end

local function is_null_key(key)
    return key == "0x0000"
end

local function is_ascii_mode(ctx)
    return ctx and ctx.get_option and ctx:get_option("ascii_mode")
end

local symbol_keys = {
    ["\\"] = true,
    ["|"] = true,
    ["backslash"] = true,
    ["bar"] = true,
    ["Backslash"] = true,
    ["Escape"] = true,
    ["escape"] = true,
    ["Backspace"] = true,
    ["backspace"] = true,
    ["less"] = true,
    ["Less"] = true,
    ["<"] = true,
    ["minus"] = true,
    ["Minus"] = true,
    ["hyphen"] = true,
    ["Hyphen"] = true,
    ["-"] = true,
    ["space"] = true,
    ["Space"] = true,
    [" "] = true,
}

local function is_zzc_reserved_key(key, ch)
    if symbol_keys[key or ""] or symbol_keys[ch or ""] then return true end
    if type(key) ~= "string" then return false end
    local clean = key:match("^[Ss]hift%+(.*)") or key
    return symbol_keys[clean] or symbol_keys[clean:lower()]
end

reset = function(ctx)
    state.active = false
    state.stage = "off"
    state.items = {}
    state.mode = "make"
    state.target_code = ""
    state.display_word = ""
    state.replaced_word = ""
    state.command_candidates = {}
    state.shorten_idx = 1
    core.set_state_items(state.items)
    core.set_current_stage(state.stage)
    if ctx and ctx.set_property then
        ctx:set_property("_txjx_zzc_stage", "")
        ctx:set_property("_txjx_zzc_word", "")
        ctx:set_property("_txjx_zzc_items", "")
        ctx:set_property("_txjx_zzc_len", "")
        ctx:set_property("_txjx_zzc_pending", "")
        ctx:set_property("_txjx_zzc_mode", "")
        ctx:set_property("_txjx_zzc_target", "")
        ctx:set_property("_txjx_zzc_display", "")
        ctx:set_property("_txjx_zzc_replaced", "")
        ctx:set_property("_txjx_zzc_cmd_candidates", "")
        ctx:set_property("_txjx_zzc_shorten_idx", "")
    end
    if ctx then ctx:clear() end
end

local function clear_state_only(ctx)
    state.active = false
    state.stage = "off"
    state.items = {}
    state.mode = "make"
    state.target_code = ""
    state.display_word = ""
    state.replaced_word = ""
    state.command_candidates = {}
    state.shorten_idx = 1
    core.set_state_items(state.items)
    core.set_current_stage(state.stage)
    if ctx and ctx.set_property then
        ctx:set_property("_txjx_zzc_stage", "")
        ctx:set_property("_txjx_zzc_word", "")
        ctx:set_property("_txjx_zzc_items", "")
        ctx:set_property("_txjx_zzc_len", "")
        ctx:set_property("_txjx_zzc_pending", "")
        ctx:set_property("_txjx_zzc_mode", "")
        ctx:set_property("_txjx_zzc_target", "")
        ctx:set_property("_txjx_zzc_display", "")
        ctx:set_property("_txjx_zzc_replaced", "")
        ctx:set_property("_txjx_zzc_cmd_candidates", "")
        ctx:set_property("_txjx_zzc_shorten_idx", "")
    end
end

local function sync_state(ctx)
    core.set_state_items(state.items)
    core.set_current_stage(state.stage)
    if ctx and ctx.set_property then
        ctx:set_property("_txjx_zzc_stage", state.stage ~= "off" and state.stage or "")
        local current_word = core.buffer_word() or ""
        if current_word == "" then current_word = state.display_word or "" end
        ctx:set_property("_txjx_zzc_word", current_word)
        ctx:set_property("_txjx_zzc_items", core.serialize_items(state.items))
        ctx:set_property("_txjx_zzc_mode", state.mode or "make")
        ctx:set_property("_txjx_zzc_target", state.target_code or "")
        ctx:set_property("_txjx_zzc_display", state.display_word or "")
        ctx:set_property("_txjx_zzc_replaced", state.replaced_word or "")
        ctx:set_property("_txjx_zzc_cmd_candidates", table.concat(state.command_candidates or {}, "\n"))
        ctx:set_property("_txjx_zzc_shorten_idx", tostring(state.shorten_idx or 1))
    end
end

local function refresh_context(ctx)
    if not ctx then return end
    pcall(function()
        if ctx.refresh_non_confirmed_composition then
            ctx:refresh_non_confirmed_composition()
        end
    end)
end

local function composition_empty(ctx)
    return not ctx or not ctx.composition or ctx.composition:empty()
end

local function set_pending_trigger(ctx, enabled)
    if not (ctx and ctx.set_property) then return end
    ctx:set_property("_txjx_zzc_pending", enabled and "1" or "")
end

local function pending_trigger(ctx)
    return ctx and ctx.get_property and ctx:get_property("_txjx_zzc_pending") == "1"
end

local function restore_state_from_context(ctx)
    if not (ctx and ctx.get_property) then return false end
    local prop_stage = ctx:get_property("_txjx_zzc_stage") or ""
    local prop_word = ctx:get_property("_txjx_zzc_word") or ""
    local prop_items = ctx:get_property("_txjx_zzc_items") or ""
    local prop_mode = ctx:get_property("_txjx_zzc_mode") or ""
    local prop_target = ctx:get_property("_txjx_zzc_target") or ""
    local prop_display = ctx:get_property("_txjx_zzc_display") or ""
    local prop_replaced = ctx:get_property("_txjx_zzc_replaced") or ""
    local prop_cmd_candidates = ctx:get_property("_txjx_zzc_cmd_candidates") or ""
    local prop_shorten_idx = tonumber(ctx:get_property("_txjx_zzc_shorten_idx") or "") or 1
    if prop_stage == "" and prop_word == "" and prop_items == "" then return false end
    local items = core.deserialize_items(prop_items)
    if (not items or #items == 0) and prop_word ~= "" then
        items = core.items_from_text(prop_word) or {}
    end
    state.active = true
    state.stage = prop_stage ~= "" and prop_stage or "collect"
    state.items = items or {}
    state.mode = prop_mode ~= "" and prop_mode or "make"
    state.target_code = prop_target or ""
    state.display_word = prop_display ~= "" and prop_display or prop_word or ""
    state.replaced_word = prop_replaced or ""
    state.shorten_idx = prop_shorten_idx
    state.command_candidates = {}
    for line in prop_cmd_candidates:gmatch("[^\n]+") do
        state.command_candidates[#state.command_candidates + 1] = line
    end
    core.set_state_items(state.items)
    core.set_current_stage(state.stage)
    return true
end

local function recover_collect_items(ctx)
    if state.items and #state.items > 0 then return true end
    if core.state_items and #core.state_items > 0 then
        state.items = core.state_items
        return true
    end
    if ctx and ctx.get_property then
        local prop_items = ctx:get_property("_txjx_zzc_items") or ""
        local items = core.deserialize_items(prop_items)
        if items and #items > 0 then
            state.items = items
            core.set_state_items(state.items)
            return true
        end
        local prop_word = ctx:get_property("_txjx_zzc_word") or ""
        items = core.items_from_text(prop_word)
        if items and #items > 0 then
            state.items = items
            core.set_state_items(state.items)
            return true
        end
    end
    return false
end

local function menu_candidate_at(menu, index)
    local ok, cand = pcall(function() return menu:get_candidate_at(index) end)
    if not ok then return nil end
    return cand
end

first_candidate = function(ctx)
    if not ctx or not ctx.composition or ctx.composition:empty() then return nil end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu then return nil end
    return menu_candidate_at(menu, 0)
end

local function selected_candidate(ctx)
    if not ctx or not ctx.has_menu or not ctx:has_menu() then return nil end
    local ok, cand = pcall(function() return ctx:get_selected_candidate() end)
    return ok and cand or nil
end

local function candidate_type(cand)
    if not cand then return nil end
    local cand_type = cand.type
    if cand.get_genuine then
        local ok, genuine = pcall(function() return cand:get_genuine() end)
        if ok and genuine and genuine.type then cand_type = genuine.type end
    end
    return cand_type
end

local function is_real_candidate(cand)
    local cand_type = candidate_type(cand)
    return cand
        and cand.text
        and cand.text ~= ""
        and cand.text:sub(1, 1) ~= "~"
        and cand_type ~= "completion"
        and cand_type ~= "zzc_state"
        and cand_type ~= "zzc_make_word"
        and cand_type ~= "punct"
end

local function first_real_candidate(ctx)
    if not ctx or not ctx.composition or ctx.composition:empty() then return nil end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu then return nil end
    for i = 0, 9 do
        local cand = menu_candidate_at(menu, i)
        if not cand then break end
        if is_real_candidate(cand) then
            return cand
        end
    end
    return nil
end

current_action_candidate = function(ctx)
    local cand = selected_candidate(ctx)
    if is_real_candidate(cand) then return cand end
    return first_real_candidate(ctx)
end

local function probe_first_candidate(ctx, code)
    if not ctx or not code or code == "" then return nil end
    local cover = core.cover_for_probe and core.cover_for_probe(code, { ignore_order = true }) or nil
    if cover and cover.rows and cover.rows[1] and cover.rows[1].word then
        return cover.rows[1].word
    end
    local old_input = ctx.input or ""
    local old_stage = ctx.get_property and (ctx:get_property("_txjx_zzc_stage") or "") or ""
    local old_word = ctx.get_property and (ctx:get_property("_txjx_zzc_word") or "") or ""
    local old_items = ctx.get_property and (ctx:get_property("_txjx_zzc_items") or "") or ""
    local old_len = ctx.get_property and (ctx:get_property("_txjx_zzc_len") or "") or ""
    local old_pending = ctx.get_property and (ctx:get_property("_txjx_zzc_pending") or "") or ""
    local old_mode = ctx.get_property and (ctx:get_property("_txjx_zzc_mode") or "") or ""
    local old_target = ctx.get_property and (ctx:get_property("_txjx_zzc_target") or "") or ""
    local old_display = ctx.get_property and (ctx:get_property("_txjx_zzc_display") or "") or ""
    local old_replaced = ctx.get_property and (ctx:get_property("_txjx_zzc_replaced") or "") or ""
    local text = nil
    local ok = pcall(function()
        if ctx.set_property then
            ctx:set_property("_txjx_zzc_stage", "")
            ctx:set_property("_txjx_zzc_word", "")
            ctx:set_property("_txjx_zzc_items", "")
            ctx:set_property("_txjx_zzc_len", "")
            ctx:set_property("_txjx_zzc_pending", "")
            ctx:set_property("_txjx_zzc_mode", "")
            ctx:set_property("_txjx_zzc_target", "")
            ctx:set_property("_txjx_zzc_display", "")
            ctx:set_property("_txjx_zzc_replaced", "")
        end
        ctx.input = code
        refresh_context(ctx)
        if ctx.composition and not ctx.composition:empty() then
            local seg = ctx.composition:back()
            local menu = seg and seg.menu
            if menu then
                for i = 0, 9 do
                    local cand = menu_candidate_at(menu, i)
                    if not cand then break end
                    if is_real_candidate(cand)
                        and (not cover or not cover.hide_words or not cover.hide_words[cand.text]) then
                        text = cand.text
                        break
                    end
                end
            end
        end
    end)
    pcall(function()
        ctx:clear()
        ctx.input = old_input
        if ctx.set_property then
            ctx:set_property("_txjx_zzc_stage", old_stage)
            ctx:set_property("_txjx_zzc_word", old_word)
            ctx:set_property("_txjx_zzc_items", old_items)
            ctx:set_property("_txjx_zzc_len", old_len)
            ctx:set_property("_txjx_zzc_pending", old_pending)
            ctx:set_property("_txjx_zzc_mode", old_mode)
            ctx:set_property("_txjx_zzc_target", old_target)
            ctx:set_property("_txjx_zzc_display", old_display)
            ctx:set_property("_txjx_zzc_replaced", old_replaced)
        end
        refresh_context(ctx)
    end)
    return text
end

local function length_from_candidate_text(text)
    return length_keys[text or ""]
end

local function append_text(text, code_hint)
    local appended, err = core.append_candidate_text(text, code_hint)
    if not appended then return nil, err end
    state.items = core.state_items or state.items
    return appended
end

local function append_text_raw(text)
    local appended, err = core.append_candidate_text(text, nil)
    if not appended then return nil, err end
    state.items = core.state_items or state.items
    return appended
end

local function is_cjk_text(text)
    return text and text:match("[\228-\233][\128-\191][\128-\191]") ~= nil
end

local function capture_current_candidate(ctx)
    if not ctx then return nil end
    local code_hint = strip_zzc_prefix(ctx.input)
    local cand = current_action_candidate(ctx) or first_candidate(ctx)
    if not is_real_candidate(cand) then return nil end
    local text = cand.text
    if not text or text == "" or not is_cjk_text(text) then return nil end
    local appended
    if state.mode == "make" and (not state.target_code or state.target_code == "") then
        appended = append_text_raw(text)
    else
        appended = append_text(text, code_hint)
    end
    if not appended then return nil end
    state.display_word = core.buffer_word() or state.display_word
    ctx:clear()
    ctx.input = "\\"
    sync_state(ctx)
    return appended
end

local function capture_candidate_at(ctx, idx)
    if not ctx or not idx or idx < 1 or idx > 9 then return nil end
    if not ctx.composition or ctx.composition:empty() then return nil end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu then return nil end
    local cand = menu_candidate_at(menu, idx - 1)
    if not is_real_candidate(cand) then return nil end
    local text = cand.text
    if not text or text == "" or not is_cjk_text(text) then return nil end
    local code_hint = strip_zzc_prefix(ctx.input)
    local appended
    if state.mode == "make" and (not state.target_code or state.target_code == "") then
        appended = append_text_raw(text)
    else
        appended = append_text(text, code_hint)
    end
    if not appended then return nil end
    state.display_word = core.buffer_word() or state.display_word
    ctx:clear()
    ctx.input = "\\"
    sync_state(ctx)
    return appended
end

local function pending_input_code(ctx)
    local input = ctx and ctx.input or ""
    if input == "" or input == "\\" then return "" end
    return strip_zzc_prefix(input)
end

local function command_trigger_code(input)
    return tostring(input or "" ):match("^(.*)\\%-$")
end

local function shorten_trigger(input)
    return tostring(input or ""):match("^(.*)\\<([1-9]?)\\$")
end

local function command_candidate_snapshot(ctx, code)
    local out = {}
    local seen = {}
    local cover = core.zzc_cover_for_input and core.zzc_cover_for_input(code or "")
    if not ctx or not ctx.composition or ctx.composition:empty() then return out end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu then return out end
    for i = 0, 8 do
        local cand = menu_candidate_at(menu, i)
        if not cand then break end
        local cand_type = candidate_type(cand)
        if is_real_candidate(cand)
            and (cand.preedit == code or cand_type == "zzc_saved" or cand_type == "zzc_cover")
            and not seen[cand.text]
            and (not cover or not cover.hide_words or not cover.hide_words[cand.text]) then
            out[#out + 1] = cand.text
            seen[cand.text] = true
        end
    end
    return out
end

local function promote_candidate_at(ctx, target_code, idx)
    if not idx or idx < 1 or idx > 9 then return false end
    local snapshot = state.command_candidates
    if not snapshot or not snapshot[1] then
        snapshot = command_candidate_snapshot(ctx, target_code)
    end
    local word = snapshot[idx]
    if word and target_code and target_code ~= "" then
        local reordered = { word }
        for i, item in ipairs(snapshot) do
            if i ~= idx then reordered[#reordered + 1] = item end
        end
        core.reorder_words_at_code(reordered, target_code)
    end
    if ctx then ctx:clear() end
    reset(ctx)
    return true
end

local function shorten_candidate_at(ctx, source_code, idx)
    if not source_code or #source_code <= 1 then
        reset(ctx)
        return false
    end
    idx = idx or 1
    local snapshot = state.command_candidates
    if not snapshot or not snapshot[1] then
        snapshot = command_candidate_snapshot(ctx, source_code)
    end
    local word = snapshot[idx]
    local target_code = source_code:sub(1, -2)
    if word and target_code and target_code ~= "" then
        pcall(core.move_word_to_code, word, source_code, target_code, function(code)
            return probe_first_candidate(ctx, code)
        end, nil)
    end
    if ctx then ctx:clear() end
    reset(ctx)
    return true
end

local function startswith(text, prefix)
    return type(text) == "string" and type(prefix) == "string" and text:sub(1, #prefix) == prefix
end

local function resolve_length_key(key, ch)
    return length_keys[ch or ""] or length_keys[key or ""]
end

local function resolve_index_key(key, ch)
    return index_keys[ch or ""] or index_keys[key or ""]
end

local function default_length_for_items(items)
    local n = #(items or {})
    if n == 2 then return 4 end
    if n == 3 then return 3 end
    if n >= 4 then return 4 end
    return nil
end

local function commit_command_deletes(ctx)
    local digits = state.display_word or ""
    local code = state.target_code or ""
    for d in digits:gmatch("%d") do
        local idx = tonumber(d)
        if idx and idx >= 1 and idx <= 9 then
            local word = state.command_candidates and state.command_candidates[idx]
            if word and code ~= "" then
                core.delete_word_at_code(word, code)
            end
        end
    end
    reset(ctx)
    return kAccepted
end

local function commit_command_promote(ctx)
    local idx = tonumber(state.display_word or "")
    local code = state.target_code or ""
    if idx and idx >= 1 and idx <= 9 then
        promote_candidate_at(ctx, code, idx)
        return kAccepted
    end
    reset(ctx)
    return kAccepted
end

local function commit_code_choice(ctx, env, idx)
    local choice = state.command_candidates and state.command_candidates[idx]
    if not choice then
        return kAccepted
    end
    local word, code = choice:match("^([^\t]+)\t([^\t%s]+)")
    if not word or not code then
        return kAccepted
    end
    local items = state.items or {}
    if #items == 0 then items = core.raw_items_from_text(word) end
    local saved_code = core.save_word_at_code(items, code, nil, function(probe_code)
        return probe_first_candidate(ctx, probe_code)
    end)
    if not saved_code then
        state.stage = "collect"
        sync_state(ctx)
        return kAccepted
    end
    reset(ctx)
    if env and env.engine then env.engine:commit_text(word) end
    return kAccepted
end

local function finalize_current(ctx, env, opts)
    opts = opts or {}
    if #state.items < 1 then
        reset(ctx)
        return kAccepted
    end
    local word = core.buffer_word()
    local saved_code, err
    if state.mode == "replace" and state.target_code ~= "" then
        local promote_idx = chinese_index_words[word or ""]
        if promote_idx then
            promote_candidate_at(ctx, state.target_code, promote_idx)
            return kAccepted
        end
        saved_code, err = core.enqueue_replace(state.items, state.target_code, state.replaced_word, function(code)
            return probe_first_candidate(ctx, code)
        end)
    else
        local len = opts.len or default_length_for_items(state.items)
        if not len then return kAccepted end
        if #state.items < 2 then
            sync_state(ctx)
            return kAccepted
        end
        saved_code, err = core.enqueue_pending(state.items, len, function(code)
            return probe_first_candidate(ctx, code)
        end)
        if not saved_code and err == "missing_parts" then
            local choices, choice_err = core.code_choices_for_text(word, len, 9)
            if choices and choices[1] then
                state.stage = "resolve_code"
                state.mode = "make"
                state.target_code = ""
                state.display_word = word
                state.command_candidates = {}
                for _, choice in ipairs(choices) do
                    state.command_candidates[#state.command_candidates + 1] = choice.word .. "\t" .. choice.code
                end
                sync_state(ctx)
                refresh_context(ctx)
                return kAccepted
            end
        end
    end
    if not saved_code then
        state.stage = "collect"
        sync_state(ctx)
        return kAccepted
    end
    reset(ctx)
    if env and env.engine and word and word ~= "" then
        env.engine:commit_text(word)
    end
    return kAccepted
end

local function finalize_with_length(ctx, len, env)
    if not len then return kAccepted end
    if ctx and ctx.set_property then ctx:set_property("_txjx_zzc_len", tostring(len)) end
    if (ctx.input or "") ~= "" and (ctx.input or "") ~= "\\" then
        capture_current_candidate(ctx)
    end
    return finalize_current(ctx, env, { len = len })
end

local function push_code_char(ctx, ch)
    if not ctx or not ch or ch == "" then return end
    local pushed = false
    if type(ctx.push_input) == "function" then
        local ok = pcall(function()
            ctx:push_input(ch)
        end)
        pushed = ok and true or false
    end
    if not pushed then
        ctx.input = (ctx.input or "") .. ch
    end
end

local function activate_collect(ctx, first_char)
    state.active = true
    state.stage = "collect"
    state.items = {}
    state.mode = "make"
    state.target_code = ""
    state.display_word = ""
    state.replaced_word = ""
    if ctx then ctx:clear() end
    sync_state(ctx)
    if is_code_char(first_char) then
        push_code_char(ctx, first_char)
    end
end

local function processor(key_event, env)
    if key_event:release() or key_event:ctrl() or key_event:alt() then return kNoop end
    if not core.allowed(env) then return kNoop end
    local ctx = env.engine.context
    if state.active and core.current_stage() == "off" and not restore_state_from_context(ctx) then
        state.active = false
        state.stage = "off"
        state.items = core.state_items or {}
    end
    if ctx and ctx.get_property and ctx:get_property("_txjx_zzc_finalize") == "1" then
        clear_state_only(ctx)
        if ctx.set_property then ctx:set_property("_txjx_zzc_finalize", "") end
    end
    local key = key_event:repr()
    local ch = event_char(key_event)
    local code_char = resolve_code_char(key, ch)
    local direct_len = resolve_length_key(key, ch)
    local current_input = ctx and ctx.input or ""

    if current_input == "" and code_char and composition_empty(ctx) then
        local prop_stage = ctx and ctx.get_property and (ctx:get_property("_txjx_zzc_stage") or "") or ""
        if state.active or prop_stage ~= "" then
            clear_state_only(ctx)
            return kNoop
        end
    end

    if is_ascii_mode(ctx) then return kNoop end
    if state.stage == "resolve_code" then
        if is_backspace(key) or key == "Escape" or key == "escape" then
            reset(ctx)
            return kAccepted
        end
        local idx = resolve_index_key(key, ch)
        if idx and idx >= 1 and idx <= 9 then
            return commit_code_choice(ctx, env, idx)
        end
        return kAccepted
    end
    if state.stage == "command_wait" then
        if is_backspace(key) or key == "Escape" or key == "escape" then
            if is_backspace(key) and state.display_word and state.display_word ~= "" then
                state.display_word = state.display_word:sub(1, -2)
                sync_state(ctx)
                return kAccepted
            end
            reset(ctx)
            return kAccepted
        end
        if is_trigger(key, ch) then
            if state.mode == "delete" then
                return commit_command_deletes(ctx)
            end
            if state.mode == "promote" then
                return commit_command_promote(ctx)
            end
            if state.mode == "undo" and state.display_word == "-" then
                core.undo_last_tx()
                reset(ctx)
                return kAccepted
            end
            reset(ctx)
            return kAccepted
        end
        if state.mode == "undo" and is_minus_key(key, ch) and (not state.display_word or state.display_word == "") then
            state.display_word = "-"
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        local idx = resolve_index_key(key, ch)
        if idx and idx >= 1 and idx <= 9 then
            state.display_word = (state.display_word or "") .. tostring(idx)
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        return kAccepted
    end
    if state.stage == "shorten_wait" then
        if key == "Escape" or key == "escape" then
            reset(ctx)
            return kAccepted
        end
        if is_backspace(key) then
            if state.display_word and state.display_word ~= "" then
                state.display_word = ""
                sync_state(ctx)
                return kAccepted
            end
            reset(ctx)
            return kAccepted
        end
        if is_trigger(key, ch) or key == "backslash" or key == "Backslash" or ch == "\\" then
            local idx = tonumber(state.shorten_idx or 1) or 1
            shorten_candidate_at(ctx, state.target_code, idx)
            return kAccepted
        end
        local idx = resolve_index_key(key, ch)
        if idx and idx >= 1 and idx <= 9 then
            state.shorten_idx = idx
            local word = state.command_candidates and state.command_candidates[idx]
            if word and word ~= "" then state.display_word = word end
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        return kAccepted
    end

    if not state.active then
        if restore_state_from_context(ctx) then
        end
    end
    if not state.active then
        local command_code = command_trigger_code(current_input)
        if command_code then
            local code = command_code
            if code == "" then code = ctx and ctx.input or "" end
            state.active = true
            state.stage = "command_wait"
            state.items = {}
            state.mode = code == "" and "undo" or "delete"
            state.target_code = code
            state.display_word = ""
            state.replaced_word = ""
            state.command_candidates = command_candidate_snapshot(ctx, code)
            sync_state(ctx)
            return kAccepted
        end
        if current_input == "\\" then
            if is_backspace(key) or key == "Escape" or key == "escape" then
                set_pending_trigger(ctx, false)
                if ctx then ctx:clear() end
                return kAccepted
            end
            if code_char then
                set_pending_trigger(ctx, false)
                activate_collect(ctx, code_char)
                return kAccepted
            end
            set_pending_trigger(ctx, false)
            return kNoop
        end
        if #current_input > 1 and current_input:sub(-1) == "\\" then
            local target_code = current_input:sub(1, -2)
            local cand = current_action_candidate(ctx) or first_candidate(ctx)
            local idx = resolve_index_key(key, ch)
            if idx and idx >= 1 and idx <= 9 then
                state.active = true
                state.stage = "command_wait"
                state.items = {}
                state.mode = "promote"
                state.target_code = target_code
                state.display_word = tostring(idx)
                state.replaced_word = ""
                state.command_candidates = command_candidate_snapshot(ctx, target_code)
                sync_state(ctx)
                refresh_context(ctx)
                return kAccepted
            end
            state.active = true
            state.stage = "replace_wait"
            state.items = {}
            state.mode = "replace"
            state.target_code = target_code
            state.display_word = cand and cand.text or target_code
            state.replaced_word = cand and cand.text or ""
            state.command_candidates = command_candidate_snapshot(ctx, target_code)
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        if is_trigger(key, ch) and (ctx.input or "") == "" then
            set_pending_trigger(ctx, true)
            return kNoop
        end
        if pending_trigger(ctx) then
            if startswith(current_input, "\\") and #current_input > 1 then
                set_pending_trigger(ctx, false)
                state.active = true
                state.stage = "collect"
                state.items = {}
                state.mode = "make"
                state.target_code = ""
                state.display_word = ""
                state.replaced_word = ""
                sync_state(ctx)
                ctx.input = current_input:sub(2)
                return kAccepted
            end
            if code_char then
                set_pending_trigger(ctx, false)
                activate_collect(ctx, code_char)
                return kAccepted
            end
            if not is_trigger(key, ch) and not is_backspace(key) then
                set_pending_trigger(ctx, false)
            end
        end
        if is_trigger(key, ch) and (ctx.input or "") ~= "" then
            local cand = current_action_candidate(ctx) or first_candidate(ctx)
            state.active = true
            state.stage = "replace_wait"
            state.items = {}
            state.mode = "replace"
            state.target_code = ctx.input or ""
            state.display_word = cand and cand.text or (ctx.input or "")
            state.replaced_word = cand and cand.text or ""
            state.command_candidates = command_candidate_snapshot(ctx, state.target_code)
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        if core.current_stage() ~= "off" and (direct_len or is_space(key) or is_backspace(key) or key == "Escape" or key == "escape") then
            state.active = true
            state.stage = core.current_stage()
            state.items = core.state_items or state.items
        else
            return kNoop
        end
    end

    if key == "Escape" or key == "escape" then
        reset(ctx)
        return kAccepted
    end

    if state.active and is_null_key(key) then
        reset(ctx)
        return kAccepted
    end

    if state.stage == "replace_wait" then
        local replace_prefix = (state.target_code or "") .. "\\"
        local idx = resolve_index_key(key, ch)
        if idx and idx >= 1 and idx <= 9 then
            state.stage = "command_wait"
            state.mode = "promote"
            state.display_word = tostring(idx)
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        if is_less_key(key, ch) then
            state.stage = "shorten_wait"
            state.mode = "shorten"
            state.shorten_idx = 1
            state.display_word = (state.command_candidates and state.command_candidates[1]) or state.display_word or ""
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        if is_minus_key(key, ch) then
            state.stage = "command_wait"
            state.mode = "delete"
            state.display_word = ""
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        if startswith(current_input, replace_prefix) and #current_input > #replace_prefix then
            state.stage = "collect"
            state.display_word = core.buffer_word() or state.display_word
            ctx:clear()
            ctx.input = "\\" .. current_input:sub(#replace_prefix + 1)
            sync_state(ctx)
            return kAccepted
        end
        if is_backspace(key) then
            reset(ctx)
            return kAccepted
        end
        if is_trigger(key, ch) then
            reset(ctx)
            return kAccepted
        end
        if is_code_char(ch) then
            state.stage = "collect"
            state.display_word = core.buffer_word() or state.display_word
            ctx:clear()
            ctx.input = "\\"
            sync_state(ctx)
            return kNoop
        end
        return kAccepted
    end

    if state.stage == "collect" and (ctx.input or "") == "\\" and ch and ch ~= "" and not is_trigger(key, ch) then
        ctx:clear()
        return kNoop
    end

    if state.stage == "collect" and #current_input > 1 and current_input:sub(-1) == "\\" then
        local pending_code = current_input:sub(1, -2)
        ctx.input = pending_code
        if pending_code ~= "" then
            capture_current_candidate(ctx)
        end
        return finalize_current(ctx, env)
    end

    if state.stage == "collect" and (ctx.input or ""):sub(1, 1) == "\\" and #(ctx.input or "") > 1 then
        ctx.input = strip_zzc_prefix(ctx.input)
        return kNoop
    end

    if is_backspace(key) then
        if state.stage == "collect" then recover_collect_items(ctx) end
        if #state.items > 0 then
            table.remove(state.items)
            state.display_word = core.buffer_word() or ""
            if #state.items > 0 then
                ctx.input = "\\"
                sync_state(ctx)
                refresh_context(ctx)
            else
                reset(ctx)
            end
            return kAccepted
        end
        if ctx.input and ctx.input ~= "" then return kNoop end
        reset(ctx)
        return kAccepted
    end

    if state.stage == "collect" then
        local idx = resolve_index_key(key, ch)
        if idx and idx >= 1 and idx <= 9 then
            capture_candidate_at(ctx, idx)
            return kAccepted
        end
    end

    if direct_len and state.mode ~= "replace" then
        return finalize_with_length(ctx, direct_len, env)
    end

    if state.stage == "collect" then
        if is_trigger(key, ch) then
            local pending_code = pending_input_code(ctx)
            if pending_code ~= "" then
                capture_current_candidate(ctx)
            end
            return finalize_current(ctx, env)
        end
        if is_space(key) then
            if (ctx.input or "") == "" then return kNoop end
            local cand = current_action_candidate(ctx) or first_candidate(ctx)
            local cand_len = cand and length_from_candidate_text(cand.text)
            if cand_len then
                ctx:clear()
                return finalize_with_length(ctx, cand_len, env)
            end
            local text = capture_current_candidate(ctx)
            if not text then return kAccepted end
            return kAccepted
        end
        return kNoop
    end

    if is_zzc_reserved_key(key, ch) then
        return kAccepted
    end
    return kNoop
end

local function module_is_active(ctx)
    if state.active and (state.stage == "collect" or state.stage == "command_wait" or state.stage == "resolve_code" or state.stage == "shorten_wait") then return true end
    if ctx and ctx.get_property then
        return (ctx:get_property("_txjx_zzc_stage") or "") ~= ""
    end
    return false
end

local function module_capture_current_candidate(ctx)
    if not module_is_active(ctx) then return false end
    local text = capture_current_candidate(ctx)
    return text and true or false
end

return {
    func = processor,
    is_active = module_is_active,
    capture_current_candidate = module_capture_current_candidate,
}
