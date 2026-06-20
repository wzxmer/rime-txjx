local core = require("txjx_zzc_core")

local length_inputs = {
    ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
    ["三"] = 3, ["四"] = 4, ["五"] = 5, ["六"] = 6,
}
local function split_length_input(input)
    input = input or ""
    local last_char = input
    local prefix = ""
    if utf8 and utf8.len and utf8.len(input) and utf8.len(input) > 1 then
        local start = utf8.offset(input, -1)
        last_char = start and input:sub(start) or input
        prefix = start and input:sub(1, start - 1) or ""
    elseif #input > 1 then
        last_char = input:sub(-1)
        prefix = input:sub(1, -2)
    end
    return prefix, length_inputs[last_char]
end

local function is_cjk_text(text)
    return text and text:match("[\228-\233][\128-\191][\128-\191]") ~= nil
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

local function maybe_finalize_from_input(ctx, input_text, env, input)
    local prefix, len = split_length_input(input_text)
    local prop_stage = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_stage") or ""
    local prop_word = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_word") or ""
    local prop_items = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_items") or ""
    if not len or (core.current_stage() == "off" and prop_stage == "" and prop_word == "") then return false end
    if ctx and ctx.set_property then ctx:set_property("_txjx_zzc_len", tostring(len)) end
    if (not core.state_items or #core.state_items == 0) and prop_items ~= "" then
        local items = core.deserialize_items(prop_items)
        if items and #items > 0 then
            core.set_state_items(items)
            if core.current_stage() == "off" then core.set_current_stage("collect") end
        end
    end
    if prefix:sub(1, 1) == "\\" then
        prefix = prefix:sub(2)
    end
    if prefix and prefix ~= "" then
        local current = core.buffer_word() or ""
        if current == "" or prefix:sub(1, #current) ~= current then
            if not input then return false end
            local first
            for cand in input:iter() do
                first = cand
                break
            end
            if not is_real_candidate(first) or not is_cjk_text(first.text) then return false end
            local ok = core.append_candidate_text(first.text, nil)
            if not ok then return false end
        end
    end
    local word = core.buffer_word() or ""
    if word == "" and prop_word ~= "" then
        word = prop_word
        if not core.state_items or #core.state_items == 0 then
            local items = core.items_from_text(word)
            if items then core.set_state_items(items) end
        end
    end
    if word == "" then return false end
    local code = core.enqueue_pending(core.state_items or {}, len)
    if not code then
        local choices = core.code_choices_for_text(word, len, 9)
        if choices and choices[1] then
            local rows = {}
            for _, choice in ipairs(choices) do
                rows[#rows + 1] = choice.word .. "\t" .. choice.code
            end
            if ctx and ctx.set_property then
                ctx:set_property("_txjx_zzc_stage", "resolve_code")
                ctx:set_property("_txjx_zzc_word", word)
                ctx:set_property("_txjx_zzc_items", core.serialize_items(core.state_items or {}))
                ctx:set_property("_txjx_zzc_len", tostring(len))
                ctx:set_property("_txjx_zzc_mode", "make")
                ctx:set_property("_txjx_zzc_cmd_candidates", table.concat(rows, "\n"))
            end
            core.set_current_stage("resolve_code")
            return false
        end
    end
    if not code then
        return false
    end
    ctx:clear()
    core.set_state_items({})
    core.set_current_stage("off")
    if ctx and ctx.set_property then
        ctx:set_property("_txjx_zzc_stage", "")
        ctx:set_property("_txjx_zzc_word", "")
        ctx:set_property("_txjx_zzc_items", "")
        ctx:set_property("_txjx_zzc_len", "")
        ctx:set_property("_txjx_zzc_finalize", "1")
    end
    env.engine:commit_text(word)
    return true
end

local function state_candidate(ctx, code)
    local prop_stage = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_stage") or ""
    local prop_word = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_word") or ""
    local prop_mode = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_mode") or ""
    local prop_display = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_display") or ""
    local prop_target = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_target") or ""
    local prop_items = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_items") or ""
    if core.current_stage() == "off" and prop_stage == "" and prop_word == "" then return nil end
    local word = core.buffer_word()
    if (prop_mode == "delete" or prop_mode == "promote") and prop_stage == "command_wait" and prop_target ~= "" then
        word = prop_target
    elseif prop_mode == "undo" and prop_stage == "command_wait" then
        word = prop_display ~= "" and prop_display or "-"
    elseif prop_mode == "shorten" and prop_display ~= "" and prop_stage == "shorten_wait" then
        word = prop_display
    elseif prop_mode == "replace" and prop_display ~= "" and (prop_stage == "replace_wait" or prop_items == "") then
        word = prop_display
    elseif word == "" then
        word = prop_word
    end
    if not word or word == "" then return nil end
    local text
    if prop_mode == "delete" and prop_stage == "command_wait" and prop_target ~= "" then
        text = prop_target .. "\\-" .. (prop_display or "")
    elseif prop_mode == "promote" and prop_stage == "command_wait" and prop_target ~= "" then
        text = prop_target .. "\\" .. (prop_display or "")
    elseif prop_mode == "undo" and prop_stage == "command_wait" then
        text = "\\-" .. (prop_display or "")
    elseif prop_mode == "shorten" and prop_display ~= "" and prop_stage == "shorten_wait" then
        text = word .. "\\<"
    elseif prop_mode == "replace" and prop_display ~= "" and (prop_stage == "replace_wait" or prop_items == "") then
        text = word .. "\\"
    else
        text = "\\" .. word
    end
    local end_pos = #code
    if end_pos < 1 then end_pos = 1 end
    local cand = Candidate("zzc_state", 0, end_pos, text, "自造词ing")
    cand.quality = 10000
    return cand
end

local function yield_code_choice_candidates(ctx, code)
    local prop_stage = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_stage") or ""
    if prop_stage ~= "resolve_code" then return false end
    local rows_text = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_cmd_candidates") or ""
    local idx = 0
    local yielded = false
    for line in rows_text:gmatch("[^\n]+") do
        local word, choice_code = line:match("^([^\t]+)\t([^\t%s]+)")
        if word and choice_code then
            idx = idx + 1
            local cand = Candidate("zzc_code_choice", 0, #code, word, choice_code)
            cand.quality = 10080 - idx
            yield(cand)
            yielded = true
        end
    end
    return yielded
end

local function yield_saved_candidates(input_text)
    local found = core.candidates_for_input(input_text)
    if not found or not found.rows or not found.rows[1] then return false end
    local rows = found.has_exact and found.exact_rows or found.rows
    for _, row in ipairs(rows) do
        local cand = Candidate("zzc_saved", 0, #input_text, row.word, "自造词")
        cand.quality = found.has_exact and 10050 or 9000
        yield(cand)
    end
    return true
end

local function yield_zzc_cover_candidates(input_text, cover)
    cover = cover or core.zzc_cover_for_input(input_text)
    if not cover then return nil end
    if cover.rows then
        for _, row in ipairs(cover.rows) do
            local cand = Candidate("zzc_cover", 0, #input_text, row.word, "自造词")
            cand.quality = 10060
            yield(cand)
        end
    end
    return cover
end

local function yield_input_candidates(input, skip_first, real_only)
    local skipped = false
    for cand in input:iter() do
        if not real_only or is_real_candidate(cand) then
            if skip_first and not skipped then
                skipped = true
            else
                yield(cand)
            end
        end
    end
end

local function yield_filtered_input_candidates(input, cover)
    for cand in input:iter() do
        if is_real_candidate(cand)
            and (not cover
            or not cand.text
            or (not cover.keep_words[cand.text] and not cover.hide_words[cand.text])) then
            yield(cand)
        end
    end
end

local function filter(input, env)
    if not core.allowed(env) then
        yield_input_candidates(input, false)
        return
    end
    local ctx = env.engine.context
    local code = ctx and ctx.input or ""
    local prop_stage = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_stage") or ""
    local prop_mode = ctx and ctx.get_property and ctx:get_property("_txjx_zzc_mode") or ""
    if maybe_finalize_from_input(ctx, code, env, input) then
        return
    end
    local state_cand = state_candidate(ctx, code)
    if yield_code_choice_candidates(ctx, code) then
        return
    end
    if state_cand and code == "" then
        yield(state_cand)
        return
    end
    if code == "\\" and state_cand then
        yield(state_cand)
        return
    end
    if state_cand and (prop_mode == "delete" or prop_mode == "promote" or prop_mode == "undo") and prop_stage == "command_wait" then
        yield(state_cand)
        return
    end
    if state_cand and prop_mode == "shorten" and prop_stage == "shorten_wait" then
        yield(state_cand)
        return
    end
    if state_cand and prop_mode == "replace" and prop_stage == "replace_wait" then
        yield(state_cand)
        return
    end
    if code ~= "" and not state_cand then
        local cover = core.zzc_order_for_input and core.zzc_order_for_input(code) or core.zzc_cover_for_input(code)
        if cover and cover.has_order then
            yield_zzc_cover_candidates(code, cover)
            yield_filtered_input_candidates(input, cover)
            return
        end
        local has_runtime = yield_saved_candidates(code)
        if has_runtime then
            yield_input_candidates(input, true, true)
            return
        end
        cover = yield_zzc_cover_candidates(code, cover)
        if cover then
            yield_filtered_input_candidates(input, cover)
            return
        end
    end
    if code == "" then
        if state_cand then yield(state_cand) end
        for cand in input:iter() do yield(cand) end
        return
    end
    for cand in input:iter() do yield(cand) end
end

return filter
