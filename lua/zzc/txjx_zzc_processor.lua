local core = require("zzc.txjx_zzc_core")
local zzc_state = require("zzc.txjx_zzc_state")

local kAccepted = 1
local kNoop = 2

local state = zzc_state.new()
local current_action_candidate
local first_candidate
local reset
local command_candidate_snapshot

local zzc_props = zzc_state.props
local probe_props = zzc_state.probe_props

local function reset_state_fields()
    zzc_state.reset_fields(state, core)
end

local function clear_props(ctx, props)
    zzc_state.clear_props(ctx, props)
end

local function snapshot_props(ctx, props)
    return zzc_state.snapshot_props(ctx, props)
end

local function restore_props(ctx, snapshot, props)
    zzc_state.restore_props(ctx, snapshot, props)
end

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

local function drop_last_utf8_char(text)
    text = tostring(text or "")
    if text == "" then return "" end
    local last = 1
    if utf8 and utf8.codes then
        for pos in utf8.codes(text) do
            last = pos
        end
        return text:sub(1, last - 1)
    end
    return text:sub(1, -2)
end

local function code_backslash_target(input)
    input = tostring(input or "")
    if #input > 1 and input:sub(-1) == "\\" then
        return input:sub(1, -2)
    end
    return nil
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

local function is_unshifted_equal_key(key, ch, shifted)
    if shifted then return false end
    if ch == "=" then return true end
    if type(key) ~= "string" then return false end
    local clean = key:match("^[Ss]hift%+(.*)") or key
    local lower = clean:lower()
    return lower == "equal" or clean == "="
end

local function is_plus_key(key, ch, shifted, keycode)
    if ch == "+" then return true end
    if type(key) ~= "string" then return false end
    local clean = key:match("^[Ss]hift%+(.*)") or key
    local lower = clean:lower()
    if key:match("^[Ss]hift%+") and (lower == "equal" or clean == "=") then return true end
    if shifted and (lower == "equal" or clean == "=" or keycode == 61 or keycode == 0xBB or keycode == 43) then return true end
    return lower == "plus"
        or lower == "kp_add"
        or lower == "kp_plus"
        or lower == "numpad_add"
        or lower == "numpad_plus"
        or lower == "add"
        or keycode == 61
        or keycode == 0xBB
        or keycode == 43
        or clean == "+"
end

local function is_bang_key(key, ch)
    if ch == "!" or ch == "！" then return true end
    if type(key) ~= "string" then return false end
    local clean = key:match("^[Ss]hift%+(.*)") or key
    return clean == "!" or clean == "！" or clean:lower() == "exclam"
end

local function is_backspace(key)
    return type(key) == "string" and key:lower() == "backspace"
end

local function is_enter_key(key)
    if type(key) ~= "string" then return false end
    local lower = key:lower()
    return lower == "return" or lower == "enter"
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
    reset_state_fields()
    clear_props(ctx)
    if ctx then ctx:clear() end
end

local function clear_state_only(ctx)
    reset_state_fields()
    clear_props(ctx)
end

local function sync_state(ctx)
    zzc_state.sync(ctx, state, core)
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

local function has_visible_menu(ctx)
    return ctx and ctx.has_menu and ctx:has_menu()
end

local function code_page_key_should_fallthrough(ctx, input, key, ch, shifted)
    if not has_visible_menu(ctx) then return false end
    local code = tostring(input or "")
    if code:sub(1, 1) == "\\" then code = code:sub(2) end
    if code:sub(-1) == "\\" then return false end
    if code == "" or not code:match("^[A-Za-z;']+$") then return false end
    return is_minus_key(key, ch) or is_unshifted_equal_key(key, ch, shifted)
end

local function set_pending_trigger(ctx, enabled)
    zzc_state.set_pending_trigger(ctx, enabled)
end

local function pending_trigger(ctx)
    return zzc_state.pending_trigger(ctx)
end

local function should_trace_key(ctx, key, ch)
    local input = ctx and ctx.input or ""
    if is_trigger(key, ch) or is_less_key(key, ch) then return true end
    if input == "\\" then return true end
    if code_backslash_target(input) ~= nil then return true end
    if pending_trigger(ctx) then return true end
    return state.active
end

local function trace_key(ctx, label, key, ch, extra)
end

local function diag(ctx, label, extra)
end

local function fallback_to_trigger(ctx)
    clear_state_only(ctx)
    set_pending_trigger(ctx, true)
    if ctx then
        ctx:clear()
        ctx.input = "\\"
    end
    refresh_context(ctx)
end

local function restore_state_from_context(ctx)
    return zzc_state.restore_from_context(ctx, state, core)
end

local function sync_state_from_context_if_needed(ctx)
    return zzc_state.sync_from_context_if_needed(ctx, state, core)
end

local function context_has_active_state(ctx)
    return zzc_state.context_has_active_state(ctx)
end

local function show_selected_code_notice(ctx, word, code)
    clear_state_only(ctx)
    if not (ctx and ctx.set_property) then return end
    ctx:set_property("_txjx_zzc_stage", "resolve_notice")
    ctx:set_property("_txjx_zzc_word", word or "")
    ctx:set_property("_txjx_zzc_target", code or "")
    ctx:set_property("_txjx_zzc_display", word or "")
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

local candidate_type = core.candidate_type
local is_real_candidate = core.is_real_candidate

local function is_collect_selectable_candidate(cand)
    if not cand or not cand.text or cand.text == "" then return false end
    return is_real_candidate(cand)
end

local function visible_collect_cover(ctx)
    if state.stage ~= "collect" then return nil end
    local code = ctx and strip_zzc_prefix(ctx.input or "") or ""
    if not code or code == "" then return nil end
    return core.zzc_cover_for_input(code)
end

local function candidate_visible_under_cover(cand, cover)
    if not is_collect_selectable_candidate(cand) then return false end
    if not cover or not cand.text then return true end
    return (not cover.keep_words or not cover.keep_words[cand.text])
        and (not cover.hide_words or not cover.hide_words[cand.text])
end

local function first_real_candidate(ctx)
    if not ctx or not ctx.composition or ctx.composition:empty() then return nil end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu then return nil end
    local cover = visible_collect_cover(ctx)
    for i = 0, 29 do
        local cand = menu_candidate_at(menu, i)
        if not cand then break end
        if candidate_visible_under_cover(cand, cover) then
            return cand
        end
    end
    return nil
end

current_action_candidate = function(ctx)
    local cand = selected_candidate(ctx)
    if candidate_visible_under_cover(cand, visible_collect_cover(ctx)) then return cand end
    return first_real_candidate(ctx)
end

local function visible_collect_candidate_at(ctx, idx)
    if not ctx or not idx or idx < 1 then return nil end
    if not ctx.composition or ctx.composition:empty() then return nil end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu then return nil end
    local cover = visible_collect_cover(ctx)
    local visible_idx = 0
    for i = 0, 29 do
        local cand = menu_candidate_at(menu, i)
        if not cand then break end
        if candidate_visible_under_cover(cand, cover) then
            visible_idx = visible_idx + 1
            if visible_idx == idx then return cand end
        end
    end
    return nil
end

local function probe_first_candidate(ctx, code)
    if not ctx or not code or code == "" then return nil end
    local cover = core.cover_for_probe and core.cover_for_probe(code, { ignore_order = true }) or nil
    if cover and cover.rows and cover.rows[1] and cover.rows[1].word then
        return cover.rows[1].word
    end
    local old_input = ctx.input or ""
    local old_props = snapshot_props(ctx, probe_props)
    local text = nil
    local ok = pcall(function()
        clear_props(ctx, probe_props)
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
                        and (not cover
                            or ((not cover.keep_words or not cover.keep_words[cand.text])
                                and (not cover.hide_words or not cover.hide_words[cand.text]))) then
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
        restore_props(ctx, old_props, probe_props)
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

local function pending_collect_text(input)
    local text = tostring(input or "")
    if text:sub(1, 1) ~= "\\" or #text <= 1 then return false end
    local body = text:sub(2)
    return body ~= "" and is_cjk_text(body)
end

local function capture_current_candidate(ctx, next_input)
    local perf_start = core.perf_enabled and core.perf_enabled() and os.clock() or nil
    if not ctx then return nil end
    local code_hint = strip_zzc_prefix(ctx.input)
    local cand = current_action_candidate(ctx)
    if not is_collect_selectable_candidate(cand) then return nil end
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
    ctx.input = next_input ~= nil and next_input or "\\"
    sync_state(ctx)
    refresh_context(ctx)
    core.perf_log("processor", "capture_current_candidate", perf_start, { mode = state.mode, stage = state.stage, input_len = #(ctx.input or "") }, 30)
    return appended
end

local function capture_candidate_at(ctx, idx)
    local perf_start = core.perf_enabled and core.perf_enabled() and os.clock() or nil
    if not ctx or not idx or idx < 1 or idx > 9 then return nil end
    local cand = visible_collect_candidate_at(ctx, idx)
    if not is_collect_selectable_candidate(cand) then return nil end
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
    refresh_context(ctx)
    core.perf_log("processor", "capture_candidate_at", perf_start, { idx = idx, mode = state.mode, stage = state.stage, input_len = #(ctx.input or "") }, 30)
    return appended
end

local function pending_input_code(ctx)
    local input = ctx and ctx.input or ""
    if input == "" or input == "\\" then return "" end
    return strip_zzc_prefix(input)
end

local function current_direct_code(ctx)
    local code = pending_input_code(ctx)
    if code ~= "" and code:match("^[A-Za-z;']+$") then return code end
    return nil
end

local function command_trigger_code(input)
    return tostring(input or "" ):match("^(.*)\\%-$")
end

local function split_command_input(input)
    local prefix, directive = tostring(input or ""):match("^(.-)\\(.*)$")
    if prefix == nil then return nil, nil end
    return prefix, directive or ""
end

local function begin_command_wait(ctx, mode, target_code, display_word, command_candidates, do_refresh)
    state.active = true
    state.stage = "command_wait"
    state.items = {}
    state.mode = mode
    state.target_code = target_code or ""
    state.origin_input = (target_code and target_code ~= "") and (target_code .. "\\") or "\\"
    state.display_word = display_word or ""
    state.replaced_word = ""
    state.command_candidates = command_candidates or {}
    sync_state(ctx)
    if do_refresh then refresh_context(ctx) end
    return kAccepted
end

local function begin_undo_command(ctx)
    return begin_command_wait(ctx, "undo", "", "-", {}, true)
end

local function switch_command_wait(ctx, mode, display_word)
    state.stage = "command_wait"
    state.mode = mode
    state.origin_input = state.origin_input ~= "" and state.origin_input or ((state.target_code or "") ~= "" and ((state.target_code or "") .. "\\") or "\\")
    state.display_word = display_word or ""
    sync_state(ctx)
    refresh_context(ctx)
    return kAccepted
end

local function restore_plain_input(ctx, input)
    clear_state_only(ctx)
    set_pending_trigger(ctx, false)
    if ctx then
        ctx:clear()
        ctx.input = input or ""
    end
    refresh_context(ctx)
    return kAccepted
end

local function handle_command_wait_backspace(ctx)
    local display = state.display_word or ""
    if state.mode == "restore" then
        if display ~= "" then
            display = drop_last_utf8_char(display)
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        return restore_plain_input(ctx, (state.target_code or "") .. "\\+")
    end
    if state.mode == "promote" then
        if display ~= "" then
            display = drop_last_utf8_char(display)
            if display ~= "" then
                state.display_word = display
                sync_state(ctx)
                refresh_context(ctx)
                return kAccepted
            end
        end
        return restore_plain_input(ctx, (state.target_code or "") .. "\\")
    end
    if state.mode == "delete" then
        if display ~= "" then
            state.display_word = drop_last_utf8_char(display)
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        return restore_plain_input(ctx, (state.target_code or "") .. "\\")
    end
    if state.mode == "undo" then
        if display ~= "" then
            state.display_word = drop_last_utf8_char(display)
            sync_state(ctx)
            refresh_context(ctx)
            return kAccepted
        end
        return restore_plain_input(ctx, state.origin_input ~= "" and state.origin_input or "\\")
    end
    if display ~= "" then
        state.display_word = drop_last_utf8_char(display)
        sync_state(ctx)
        refresh_context(ctx)
        return kAccepted
    end
    reset(ctx)
    return kAccepted
end

local function restore_code_backslash_input(ctx)
    local origin = state.origin_input or ""
    if origin ~= "" then return restore_plain_input(ctx, origin) end
    local target = state.target_code or ""
    return restore_plain_input(ctx, target ~= "" and (target .. "\\") or "\\")
end

local function handle_shorten_wait_backspace(ctx)
    local idx = tonumber(state.shorten_idx or 1) or 1
    if idx > 1 then
        state.shorten_idx = 1
        set_default_shorten_display()
        sync_state(ctx)
        refresh_context(ctx)
        return kAccepted
    end
    return restore_code_backslash_input(ctx)
end

local function handle_collect_backspace(ctx)
    if state.stage == "collect" then
        recover_collect_items(ctx)
        if (not state.display_word or state.display_word == "") and ctx and ctx.get_property then
            state.display_word = core.buffer_word() or (ctx:get_property("_txjx_zzc_word") or "")
        end
    end
    if state.stage == "collect"
        and (state.mode == "append" or state.mode == "replace")
        and ctx.input == "\\"
        and #state.items == 0 then
        return restore_code_backslash_input(ctx)
    end
    if state.stage == "collect" and ctx.input and #ctx.input == 1 and ctx.input ~= "\\" then
        ctx.input = "\\"
        sync_state(ctx)
        refresh_context(ctx)
        return kAccepted
    end
    if state.stage == "collect" and ctx.input and ctx.input ~= "" and ctx.input ~= "\\" then
        return kNoop
    end
    if #state.items > 0 then
        table.remove(state.items)
        state.display_word = core.buffer_word() or ""
        if #state.items > 0 then
            ctx.input = "\\"
            sync_state(ctx)
            refresh_context(ctx)
        else
            if state.mode == "append" or state.mode == "replace" then
                return restore_code_backslash_input(ctx)
            else
                state.stage = "collect"
                state.active = true
                state.mode = "make"
                ctx.input = "\\"
                sync_state(ctx)
                refresh_context(ctx)
            end
        end
        return kAccepted
    end
    if ctx.input and ctx.input ~= "" then return kNoop end
    reset(ctx)
    return kAccepted
end

local function set_default_shorten_display()
    if state.command_candidates and state.command_candidates[1] then
        state.display_word = state.command_candidates[1]
    end
end

local function begin_shorten_wait(ctx, target_code)
    state.active = true
    state.stage = "shorten_wait"
    state.items = {}
    state.mode = "shorten"
    state.target_code = target_code
    state.origin_input = (target_code and target_code ~= "") and (target_code .. "\\") or "\\"
    state.display_word = ""
    state.replaced_word = ""
    state.command_candidates = command_candidate_snapshot(ctx, target_code)
    state.shorten_idx = 1
    set_default_shorten_display()
    sync_state(ctx)
    refresh_context(ctx)
    return kAccepted
end

local function switch_shorten_wait(ctx)
    state.stage = "shorten_wait"
    state.mode = "shorten"
    state.shorten_idx = 1
    state.display_word = (state.command_candidates and state.command_candidates[1]) or state.display_word or ""
    sync_state(ctx)
    refresh_context(ctx)
    return kAccepted
end

command_candidate_snapshot = function(ctx, code, opts)
    opts = opts or {}
    local out = {}
    local seen = {}
    local cover = core.zzc_cover_for_input and core.zzc_cover_for_input(code or "")
    local function add_cover_rows(rows)
        for _, row in ipairs(rows or {}) do
            local word = row and row.word
            if word and word ~= ""
                and not seen[word]
                and (not cover or not cover.hide_words or not cover.hide_words[word]) then
                out[#out + 1] = word
                seen[word] = true
            end
        end
    end
    local function collect_from_menu(menu)
        if not menu then return end
        for i = 0, 8 do
            local cand = menu_candidate_at(menu, i)
            if not cand then break end
            local cand_type = candidate_type(cand)
            local is_zzc_row_candidate = cand_type == "zzc_saved" or cand_type == "zzc_cover" or cand_type == "zzc_append"
            if is_real_candidate(cand)
                and (cand.preedit == code or is_zzc_row_candidate)
                and not seen[cand.text]
                and (not cover
                    or (is_zzc_row_candidate and (not cover.hide_words or not cover.hide_words[cand.text]))
                    or ((not cover.keep_words or not cover.keep_words[cand.text])
                        and (not cover.hide_words or not cover.hide_words[cand.text]))) then
                out[#out + 1] = cand.text
                seen[cand.text] = true
            end
        end
    end
    if cover and cover.rows then add_cover_rows(cover.rows) end
    if cover and cover.append_rows then add_cover_rows(cover.append_rows) end
    if ctx and ctx.composition and not ctx.composition:empty() then
        local seg = ctx.composition:back()
        collect_from_menu(seg and seg.menu)
    end
    diag(ctx, "command_snapshot", "code=" .. tostring(code) .. " out=" .. table.concat(out, "|"))
    if (out[1] and not opts.force_probe) or not ctx or not code or code == "" then return out end
    local old_input = ctx.input or ""
    local old_props = snapshot_props(ctx)
    local old_core_stage = core.current_stage and core.current_stage() or "off"
    pcall(function()
        if core.set_current_stage then core.set_current_stage("off") end
        clear_props(ctx)
        ctx.input = code
        refresh_context(ctx)
        if cover and cover.rows then add_cover_rows(cover.rows) end
        if cover and cover.append_rows then add_cover_rows(cover.append_rows) end
        if ctx.composition and not ctx.composition:empty() then
            local seg = ctx.composition:back()
            collect_from_menu(seg and seg.menu)
        end
    end)
    diag(ctx, "command_snapshot_probe", "code=" .. tostring(code) .. " out=" .. table.concat(out, "|"))
    pcall(function()
        ctx:clear()
        ctx.input = old_input
        if core.set_current_stage then core.set_current_stage(old_core_stage) end
        restore_props(ctx, old_props)
        refresh_context(ctx)
    end)
    return out
end

local function promote_candidate_at(ctx, target_code, idx)
    if not idx or idx < 1 or idx > 9 then return false end
    local snapshot = state.command_candidates
    if not snapshot or not snapshot[1] then
        snapshot = command_candidate_snapshot(ctx, target_code)
    end
    if not (snapshot and snapshot[idx]) then
        snapshot = command_candidate_snapshot(ctx, target_code, { force_probe = true })
    end
    local word = snapshot[idx]
    if not word and snapshot and #snapshot == 1 then
        word = snapshot[1]
    end
    if word and target_code and target_code ~= "" then
        local reordered = { word }
        for i, item in ipairs(snapshot) do
            if i ~= idx then reordered[#reordered + 1] = item end
        end
        local ok, err = core.reorder_words_at_code(reordered, target_code)
        diag(ctx, "promote_write", "code=" .. tostring(target_code) .. " idx=" .. tostring(idx) .. " word=" .. tostring(word) .. " ok=" .. tostring(ok) .. " err=" .. tostring(err))
    else
        diag(ctx, "promote_skip", "code=" .. tostring(target_code) .. " idx=" .. tostring(idx) .. " snapshot=" .. tostring(snapshot and #snapshot or 0) .. " word=" .. tostring(word))
    end
    if ctx then ctx:clear() end
    reset(ctx)
    return true
end

local function shorten_candidate_at(ctx, source_code, idx)
    if not source_code or #source_code <= 1 then
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

local function waiting_length_confirm(ctx)
    if state.stage ~= "collect" or state.mode == "replace" then return false end
    if (ctx and ctx.input or "") ~= "\\" then return false end
    recover_collect_items(ctx)
    return state.items and #state.items >= 2
end

local function ready_for_length(ctx)
    if state.stage ~= "collect" or state.mode == "replace" then return false end
    recover_collect_items(ctx)
    return state.items and #state.items >= 2
end

local function invalid_length_digit(idx, len)
    return idx and idx >= 1 and idx <= 9 and not len
end

local function selected_length_candidate(ctx, idx)
    if not ctx or not idx or idx < 1 or idx > 9 then return nil, nil end
    if not ctx.composition or ctx.composition:empty() then return nil, nil end
    local seg = ctx.composition:back()
    local menu = seg and seg.menu
    if not menu then return nil, nil end
    local cand = menu_candidate_at(menu, idx - 1)
    if not is_real_candidate(cand) then return nil, nil end
    local len = length_from_candidate_text(cand.text)
    if not len then return nil, cand.text end
    return len, cand.text
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
    if digits == "" then digits = "1" end
    local code = state.target_code or ""
    local snapshot = state.command_candidates
    for d in tostring(digits or ""):gmatch("%d") do
        local idx = tonumber(d)
        if idx and idx >= 1 and idx <= 9 then
            if not (snapshot and snapshot[idx]) and code ~= "" then
                snapshot = command_candidate_snapshot(ctx, code, { force_probe = true })
            end
            local word = snapshot and snapshot[idx]
            if word and code ~= "" then
                diag(ctx, "delete_write", "code=" .. tostring(code) .. " idx=" .. tostring(idx) .. " word=" .. tostring(word))
                core.delete_word_at_code(word, code)
            else
                diag(ctx, "delete_skip", "code=" .. tostring(code) .. " idx=" .. tostring(idx) .. " snapshot=" .. tostring(snapshot and #snapshot or 0))
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

local function commit_command_restore(ctx)
    local idx = tonumber(state.display_word or "")
    local code = state.target_code or ""
    local snapshot = state.command_candidates
    if idx and idx >= 1 and idx <= 9 then
        local word = snapshot and snapshot[idx]
        if word and code ~= "" then
            core.restore_word_at_code(word, code)
        end
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
    if ctx then ctx:clear() end
    show_selected_code_notice(ctx, word, code)
    if env and env.engine then env.engine:commit_text(word) end
    return kAccepted
end

local function selected_code_choice_index(ctx)
    local cand = selected_candidate(ctx)
    if candidate_type(cand) ~= "zzc_code_choice" then return 1 end
    local selected_code = cand.comment or ""
    for i, choice in ipairs(state.command_candidates or {}) do
        local _, code = choice:match("^([^\t]+)\t([^\t%s]+)")
        if code and code == selected_code then return i end
    end
    return 1
end

local function finalize_current(ctx, env, opts)
    opts = opts or {}
    if #state.items < 1 then
        reset(ctx)
        return kAccepted
    end
    local word = core.buffer_word()
    local saved_code, err
    if state.mode == "append" and state.target_code ~= "" then
        diag(ctx, "finalize_append_enter", {
            target_code = state.target_code,
            word = word,
            items = #state.items,
            input = ctx and ctx.input or "",
        })
        local saved_word_or_err
        saved_code, saved_word_or_err = core.append_word_at_code(state.items, state.target_code)
        if saved_code then
            err = nil
        else
            err = saved_word_or_err
        end
        diag(ctx, "finalize_append_result", {
            saved_code = saved_code,
            saved_word = saved_code and saved_word_or_err or "",
            err = err,
            word = word,
            items = #state.items,
        })
    elseif state.mode == "replace" and state.target_code ~= "" then
        local promote_idx = chinese_index_words[word or ""]
        if promote_idx then
            promote_candidate_at(ctx, state.target_code, promote_idx)
            return kAccepted
        end
        local replaced_word = state.replaced_word
        if (not replaced_word or replaced_word == "") and state.target_code ~= "" then
            replaced_word = probe_first_candidate(ctx, state.target_code)
        end
        diag(ctx, "finalize_replace_enter", {
            target_code = state.target_code,
            word = word,
            replaced_word = replaced_word,
            items = #state.items,
            input = ctx and ctx.input or "",
        })
        saved_code, err = core.enqueue_replace(state.items, state.target_code, replaced_word, function(code)
            return probe_first_candidate(ctx, code)
        end)
        diag(ctx, "finalize_replace_result", {
            saved_code = saved_code,
            err = err,
            word = word,
            replaced_word = replaced_word,
            items = #state.items,
        })
    else
        local len = opts.len or default_length_for_items(state.items)
        if not len then return kAccepted end
        if #state.items < 2 then
            sync_state(ctx)
            return kAccepted
        end
        local direct_code = opts.direct_code or current_direct_code(ctx)
        if direct_code and #direct_code == len then
            saved_code, err = core.save_word_at_code(state.items, direct_code, nil, function(code)
                return probe_first_candidate(ctx, code)
            end)
        else
            saved_code, err = core.enqueue_pending(state.items, len, function(code)
                return probe_first_candidate(ctx, code)
            end)
        end
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
    local direct_code = current_direct_code(ctx)
    if (ctx.input or "") ~= "" and (ctx.input or "") ~= "\\" then
        capture_current_candidate(ctx)
    end
    return finalize_current(ctx, env, { len = len, direct_code = direct_code })
end

local function handoff_length_to_filter(ctx, len, ch)
    if not ctx or not len then return kAccepted end
    if ctx.set_property then ctx:set_property("_txjx_zzc_len", tostring(len)) end
    local suffix = ch and ch ~= "" and ch or tostring(len)
    local word = core.buffer_word() or state.display_word or ""
    ctx.input = "\\" .. word .. suffix
    sync_state(ctx)
    refresh_context(ctx)
    return kAccepted
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
        refresh_context(ctx)
    end
end

local function begin_replace_collect(ctx, target_code, first_char)
    local cand = current_action_candidate(ctx) or first_candidate(ctx)
    local command_candidates = command_candidate_snapshot(ctx, target_code)
    local replaced_word = command_candidates[1] or (cand and cand.text) or ""
    state.active = true
    state.stage = "collect"
    state.items = {}
    state.mode = "replace"
    state.target_code = target_code or ""
    state.origin_input = (target_code and target_code ~= "") and (target_code .. "\\") or "\\"
    state.display_word = replaced_word ~= "" and replaced_word or (target_code or "")
    state.replaced_word = replaced_word
    state.command_candidates = command_candidates
    diag(ctx, "begin_replace_collect", {
        target_code = state.target_code,
        replaced_word = state.replaced_word,
        snapshot = #(state.command_candidates or {}),
        input = ctx and ctx.input or "",
    })
    if ctx then ctx:clear() end
    sync_state(ctx)
    if is_code_char(first_char) then
        push_code_char(ctx, first_char)
        refresh_context(ctx)
    end
end

local function begin_append_collect(ctx, target_code)
    diag(ctx, "begin_append_collect", {
        target_code = target_code,
        input = ctx and ctx.input or "",
    })
    state.active = true
    state.stage = "collect"
    state.items = {}
    state.mode = "append"
    state.target_code = target_code or ""
    state.origin_input = (target_code and target_code ~= "") and (target_code .. "\\") or "\\"
    state.display_word = ""
    state.replaced_word = ""
    state.command_candidates = {}
    if ctx then
        ctx:clear()
        ctx.input = "\\"
    end
    sync_state(ctx)
    refresh_context(ctx)
end

local function begin_restore_wait(ctx, target_code)
    local rows = core.restore_rows_for_input and core.restore_rows_for_input(target_code) or nil
    local candidates = {}
    for _, row in ipairs(rows or {}) do
        if row.word and row.word ~= "" then candidates[#candidates + 1] = row.word end
    end
    return begin_command_wait(ctx, "restore", target_code, "", candidates, true)
end

local function handle_replace_wait(ctx, current_input, key, ch, shifted, keycode)
    local replace_prefix = (state.target_code or "") .. "\\"
    local idx = resolve_index_key(key, ch)
    if idx and idx >= 1 and idx <= 9 then
        return switch_command_wait(ctx, "promote", tostring(idx))
    end
    if is_less_key(key, ch) then
        return switch_shorten_wait(ctx)
    end
    if is_minus_key(key, ch) then
        return switch_command_wait(ctx, "delete", "")
    end
    if is_plus_key(key, ch, shifted, keycode) then
        begin_append_collect(ctx, state.target_code)
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
        return restore_code_backslash_input(ctx)
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

local function handle_command_wait(ctx, key, ch)
    if is_backspace(key) or key == "Escape" or key == "escape" then
        if is_backspace(key) then
            return handle_command_wait_backspace(ctx)
        end
        reset(ctx)
        return kAccepted
    end
    if is_trigger(key, ch) then
        if state.mode == "delete" then
            return commit_command_deletes(ctx)
        end
        if state.mode == "restore" then
            return commit_command_restore(ctx)
        end
        if state.mode == "promote" then
            return commit_command_promote(ctx)
        end
        if state.mode == "undo" and state.display_word == "-" then
            core.undo_last_tx()
            reset(ctx)
            return kAccepted
        end
        if state.mode == "undo" and (state.display_word == "!!!" or state.display_word == "！！！") then
            core.undo_all_pending()
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
    if state.mode == "undo" and is_bang_key(key, ch) and (state.display_word == "" or (state.display_word and state.display_word:match("^[!！]*$"))) then
        local bang = ch == "！" and "！" or "!"
        state.display_word = (state.display_word or "") .. bang
        sync_state(ctx)
        refresh_context(ctx)
        return kAccepted
    end
    if state.mode == "delete" and is_minus_key(key, ch) and (not state.display_word or state.display_word == "") then
        state.display_word = "1"
        sync_state(ctx)
        return commit_command_deletes(ctx)
    end
    if state.mode == "restore" and is_plus_key(key, ch, false, nil) and (not state.display_word or state.display_word == "") then
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

local function processor(key_event, env)
    local perf_start = core.perf_enabled and core.perf_enabled() and os.clock() or nil
    if key_event:release() or key_event:ctrl() or key_event:alt() then return kNoop end
    if not core.allowed(env) then return kNoop end
    local ctx = env.engine.context
    if state.active and not context_has_active_state(ctx) then
        clear_state_only(ctx)
    end
    if ctx and ctx.get_property and ctx:get_property("_txjx_zzc_finalize") == "1" then
        clear_state_only(ctx)
        if ctx.set_property then ctx:set_property("_txjx_zzc_finalize", "") end
    end
    local key = key_event:repr()
    local ch = event_char(key_event)
    local shifted = key_event:shift()
    local keycode = key_event.keycode
    local code_char = resolve_code_char(key, ch)
    local direct_len = resolve_length_key(key, ch)
    local current_input = ctx and ctx.input or ""
    trace_key(ctx, "enter", key, ch, "code_char=" .. tostring(code_char) .. " direct_len=" .. tostring(direct_len))
    local function finish(result, label)
        core.perf_log("processor", label or "event", perf_start, {
            key = key,
            input_len = #current_input,
            stage = state.stage,
            mode = state.mode,
        }, 30)
        return result
    end

    sync_state_from_context_if_needed(ctx)

    if current_input == "" and code_char and composition_empty(ctx) then
        local prop_stage = ctx and ctx.get_property and (ctx:get_property("_txjx_zzc_stage") or "") or ""
        if state.active or prop_stage ~= "" then
            clear_state_only(ctx)
            return kNoop
        end
    end

    if is_ascii_mode(ctx) then return kNoop end
    if state.active and is_null_key(key) then
        reset(ctx)
        return kAccepted
    end
    if not state.active then
        restore_state_from_context(ctx)
    end
    if state.stage == "resolve_code" then
        if is_backspace(key) or key == "Escape" or key == "escape" then
            reset(ctx)
            return kAccepted
        end
        if is_space(key) then
            return commit_code_choice(ctx, env, selected_code_choice_index(ctx))
        end
        local idx = resolve_index_key(key, ch)
        if idx and idx >= 1 and idx <= 9 then
            return commit_code_choice(ctx, env, idx)
        end
        return kAccepted
    end
    if state.stage == "command_wait" then
        return handle_command_wait(ctx, key, ch)
    end
    if state.stage == "shorten_wait" then
        if key == "Escape" or key == "escape" then
            reset(ctx)
            return kAccepted
        end
        if is_backspace(key) then
            return handle_shorten_wait_backspace(ctx)
        end
        if is_trigger(key, ch) or key == "backslash" or key == "Backslash" or ch == "\\" or is_less_key(key, ch) then
            trace_key(ctx, "shorten-wait-confirm", key, ch, "idx=" .. tostring(state.shorten_idx or 1))
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
        local command_prefix, command_directive = split_command_input(current_input)
        if command_prefix ~= nil and is_trigger(key, ch) and (command_directive == "!!!" or command_directive == "！！！") then
            trace_key(ctx, "command-global-undo-all", key, ch, "prefix=" .. tostring(command_prefix))
            core.undo_all_pending()
            reset(ctx)
            return kAccepted
        end
        if command_prefix ~= nil and is_trigger(key, ch) and command_directive == "--" then
            trace_key(ctx, "command-global-undo", key, ch, "prefix=" .. tostring(command_prefix))
            core.undo_last_tx()
            reset(ctx)
            return kAccepted
        end
        local command_code = command_trigger_code(current_input)
        if command_code then
            local code = command_code
            if code == "" then code = ctx and ctx.input or "" end
            return begin_command_wait(ctx, code == "" and "undo" or "delete", code, "", command_candidate_snapshot(ctx, code), false)
        end
        if current_input == "\\" then
            trace_key(ctx, "single-backslash", key, ch)
            if is_enter_key(key) then
                trace_key(ctx, "single-backslash-enter-fallthrough", key, ch, "result=kNoop")
                set_pending_trigger(ctx, false)
                return kNoop
            end
            if is_backspace(key) or key == "Escape" or key == "escape" then
                trace_key(ctx, "single-backslash-exit", key, ch, "result=kAccepted")
                set_pending_trigger(ctx, false)
                if ctx then ctx:clear() end
                return kAccepted
            end
            if is_less_key(key, ch) then
                trace_key(ctx, "single-backslash-symbol-fallthrough", key, ch, "result=kNoop")
                set_pending_trigger(ctx, false)
                return kNoop
            end
            if is_minus_key(key, ch) then
                trace_key(ctx, "single-backslash-undo", key, ch)
                set_pending_trigger(ctx, false)
                return begin_command_wait(ctx, "undo", "", "", {}, true)
            end
            if is_bang_key(key, ch) then
                trace_key(ctx, "single-backslash-undo-all", key, ch)
                set_pending_trigger(ctx, false)
                return begin_command_wait(ctx, "undo", "", ch == "！" and "！" or "!", {}, true)
            end
            local idx = resolve_index_key(key, ch)
            if idx then
                trace_key(ctx, "single-backslash-digit-fallthrough", key, ch, "result=kNoop")
                set_pending_trigger(ctx, false)
                return kNoop
            end
            if code_char then
                trace_key(ctx, "single-backslash-collect", key, ch)
                set_pending_trigger(ctx, false)
                activate_collect(ctx, code_char)
                return kAccepted
            end
            trace_key(ctx, "single-backslash-fallthrough", key, ch, "result=kNoop")
            set_pending_trigger(ctx, false)
            return kNoop
        end
        local target_code = code_backslash_target(current_input)
        if target_code ~= nil then
            trace_key(ctx, "code-backslash", key, ch, "target_code=" .. tostring(target_code))
            if code_page_key_should_fallthrough(ctx, current_input, key, ch, shifted) then
                trace_key(ctx, "code-backslash-page-fallthrough", key, ch, "result=kNoop")
                return kNoop
            end
            if is_backspace(key) or key == "Escape" or key == "escape" then
                trace_key(ctx, "code-backslash-exit", key, ch, "result=kNoop")
                return kNoop
            end
            local idx = resolve_index_key(key, ch)
            if idx and idx >= 1 and idx <= 9 then
                trace_key(ctx, "code-backslash-promote", key, ch, "idx=" .. tostring(idx))
                return begin_command_wait(ctx, "promote", target_code, tostring(idx), command_candidate_snapshot(ctx, target_code), true)
            end
            if is_less_key(key, ch) then
                trace_key(ctx, "code-backslash-shorten", key, ch)
                return begin_shorten_wait(ctx, target_code)
            end
            if is_minus_key(key, ch) then
                trace_key(ctx, "code-backslash-delete", key, ch)
                return begin_command_wait(ctx, "delete", target_code, "", command_candidate_snapshot(ctx, target_code), true)
            end
            if is_bang_key(key, ch) then
                trace_key(ctx, "code-backslash-undo-all", key, ch)
                return begin_command_wait(ctx, "undo", target_code, ch == "！" and "！" or "!", {}, true)
            end
            if is_plus_key(key, ch, shifted, keycode) then
                trace_key(ctx, "code-backslash-append", key, ch)
                begin_append_collect(ctx, target_code)
                return kAccepted
            end
            if code_char then
                trace_key(ctx, "code-backslash-replace", key, ch, "code_char=" .. tostring(code_char))
                begin_replace_collect(ctx, target_code, code_char)
                return kAccepted
            end
            trace_key(ctx, "code-backslash-fallthrough", key, ch, "result=kNoop")
            return kNoop
        end
        if is_trigger(key, ch) and (ctx.input or "") == "" then
            trace_key(ctx, "set-pending-trigger", key, ch)
            set_pending_trigger(ctx, true)
            if ctx then
                ctx:clear()
                ctx.input = "\\"
                refresh_context(ctx)
            end
            return kAccepted
        end
        if pending_trigger(ctx) then
            trace_key(ctx, "pending-trigger", key, ch)
            if current_input == "" then
                set_pending_trigger(ctx, false)
                return kNoop
            end
            if code_page_key_should_fallthrough(ctx, current_input, key, ch, shifted) then
                trace_key(ctx, "pending-trigger-page-fallthrough", key, ch, "result=kNoop")
                set_pending_trigger(ctx, false)
                return kNoop
            end
            if is_less_key(key, ch) then
                trace_key(ctx, "pending-trigger-symbol-fallthrough", key, ch, "result=kNoop")
                set_pending_trigger(ctx, false)
                return kNoop
            end
            if pending_collect_text(current_input) then
                set_pending_trigger(ctx, false)
                return kNoop
            end
            local idx = resolve_index_key(key, ch)
            if idx or is_minus_key(key, ch) then
                trace_key(ctx, "pending-trigger-invalid-command", key, ch, "result=kAccepted")
                set_pending_trigger(ctx, false)
                if ctx then ctx:clear() end
                return kAccepted
            end
            if code_char then
                trace_key(ctx, "pending-trigger-collect-code", key, ch, "code_char=" .. tostring(code_char))
                set_pending_trigger(ctx, false)
                activate_collect(ctx, code_char)
                return kAccepted
            end
            if not is_trigger(key, ch) and not is_backspace(key) then
                trace_key(ctx, "pending-trigger-clear", key, ch)
                set_pending_trigger(ctx, false)
            end
        end
        if is_trigger(key, ch) and (ctx.input or "") ~= "" then
            return kNoop
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

    if state.stage == "replace_wait" then
        return handle_replace_wait(ctx, current_input, key, ch, shifted, keycode)
    end

    if state.stage == "collect" and (ctx.input or "") == "\\" and ch and ch ~= "" and not is_trigger(key, ch) then
        if state.mode == "append" and is_plus_key(key, ch, shifted, keycode) and state.target_code ~= "" then
            return begin_restore_wait(ctx, state.target_code)
        end
        local idx = resolve_index_key(key, ch)
        if waiting_length_confirm(ctx) and idx and idx >= 1 and idx <= 9 then
            if direct_len then
                return handoff_length_to_filter(ctx, direct_len, ch)
            end
            if invalid_length_digit(idx, direct_len) then
                reset(ctx)
                return kAccepted
            end
            return kAccepted
        end
        if is_zzc_reserved_key(key, ch) then
            trace_key(ctx, "collect-reserved-key", key, ch, "result=kAccepted")
            return kAccepted
        end
        ctx:clear()
        return kNoop
    end

    if state.stage == "collect"
        and (state.mode == "replace" or state.mode == "append")
        and is_trigger(key, ch)
        and (ctx.input or "") ~= ""
        and (ctx.input or "") ~= "\\" then
        diag(ctx, "collect_trigger_capture_before_finalize", {
            mode = state.mode,
            target_code = state.target_code,
            input = ctx.input,
            items = #state.items,
        })
        capture_current_candidate(ctx)
        diag(ctx, "collect_trigger_capture_after", {
            mode = state.mode,
            target_code = state.target_code,
            input = ctx.input,
            items = #state.items,
            word = core.buffer_word() or "",
        })
        if #state.items > 0 then
            return finalize_current(ctx, env, { direct_code = state.target_code })
        end
        reset(ctx)
        return kAccepted
    end

    if state.stage == "collect" and (ctx.input or ""):sub(1, 1) == "\\" and #(ctx.input or "") > 1 then
        ctx.input = strip_zzc_prefix(ctx.input)
        return kNoop
    end

    if state.stage == "collect" and code_page_key_should_fallthrough(ctx, ctx and ctx.input or "", key, ch, shifted) then
        return kNoop
    end

    if is_backspace(key) then
        return handle_collect_backspace(ctx)
    end

    if state.stage == "collect" then
        local idx = resolve_index_key(key, ch)
        if waiting_length_confirm(ctx) and idx and idx >= 1 and idx <= 9 then
            if direct_len then
                return handoff_length_to_filter(ctx, direct_len, ch)
            end
            if invalid_length_digit(idx, direct_len) then
                reset(ctx)
                return kAccepted
            end
            return kAccepted
        end
        if idx and idx >= 1 and idx <= 9 then
            if ready_for_length(ctx) then
                local cand_len, cand_text = selected_length_candidate(ctx, idx)
                if cand_len then
                    if ctx then ctx:clear() end
                    return handoff_length_to_filter(ctx, cand_len, cand_text)
                end
            end
            capture_candidate_at(ctx, idx)
            return kAccepted
        end
    end

    if direct_len and state.mode ~= "replace" and waiting_length_confirm(ctx) then
        return handoff_length_to_filter(ctx, direct_len, ch)
    end

    if state.stage == "collect" then
        if is_trigger(key, ch) then
            if state.mode == "replace" or state.mode == "append" then
                if (ctx.input or "") ~= "" and (ctx.input or "") ~= "\\" then
                    capture_current_candidate(ctx)
                end
                if #state.items > 0 then
                    return finalize_current(ctx, env, { direct_code = state.target_code })
                end
            elseif state.mode == "make" and #state.items > 0 then
                sync_state(ctx)
                refresh_context(ctx)
                return kAccepted
            end
            reset(ctx)
            return kAccepted
        end
        if is_space(key) then
            if (ctx.input or "") == "" then return kNoop end
            local cand = current_action_candidate(ctx)
            local cand_len = cand and length_from_candidate_text(cand.text)
            if cand_len and ready_for_length(ctx) then
                ctx:clear()
                return handoff_length_to_filter(ctx, cand_len, cand.text)
            end
            local text = capture_current_candidate(ctx)
            if not text then return kAccepted end
            return kAccepted
        end
        return kNoop
    end

    if is_zzc_reserved_key(key, ch) then
        return finish(kAccepted, "reserved_key")
    end
    return finish(kNoop, "noop_tail")
end

local function module_is_active(ctx)
    if state.active and (state.stage == "collect" or state.stage == "command_wait" or state.stage == "resolve_code" or state.stage == "shorten_wait") then return true end
    if ctx and ctx.get_property then
        return (ctx:get_property("_txjx_zzc_stage") or "") ~= ""
    end
    return false
end

local function module_capture_current_candidate(ctx, next_input)
    if not module_is_active(ctx) then return false end
    local text = capture_current_candidate(ctx, next_input)
    return text and true or false
end

return {
    func = processor,
    init = function()
        if core.flush_runtime_ops then core.flush_runtime_ops() end
    end,
    is_active = module_is_active,
    capture_current_candidate = module_capture_current_candidate,
}

