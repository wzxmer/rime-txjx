local M = {}

M.props = {
    "_txjx_zzc_stage",
    "_txjx_zzc_word",
    "_txjx_zzc_items",
    "_txjx_zzc_len",
    "_txjx_zzc_pending",
    "_txjx_zzc_mode",
    "_txjx_zzc_target",
    "_txjx_zzc_origin",
    "_txjx_zzc_display",
    "_txjx_zzc_replaced",
    "_txjx_zzc_cmd_candidates",
    "_txjx_zzc_shorten_idx",
}

M.probe_props = {
    "_txjx_zzc_stage",
    "_txjx_zzc_word",
    "_txjx_zzc_items",
    "_txjx_zzc_len",
    "_txjx_zzc_pending",
    "_txjx_zzc_mode",
    "_txjx_zzc_target",
    "_txjx_zzc_origin",
    "_txjx_zzc_display",
    "_txjx_zzc_replaced",
}

function M.new()
    return {
        active = false,
        stage = "off",
        items = {},
        mode = "make",
        target_code = "",
        origin_input = "",
        display_word = "",
        replaced_word = "",
        command_candidates = {},
        shorten_idx = 1,
    }
end

function M.reset_fields(state, core)
    state.active = false
    state.stage = "off"
    state.items = {}
    state.mode = "make"
    state.target_code = ""
    state.origin_input = ""
    state.display_word = ""
    state.replaced_word = ""
    state.command_candidates = {}
    state.shorten_idx = 1
    core.set_state_items(state.items)
    core.set_current_stage(state.stage)
end

function M.clear_props(ctx, props)
    if not (ctx and ctx.set_property) then return end
    for _, name in ipairs(props or M.props) do
        ctx:set_property(name, "")
    end
end

function M.snapshot_props(ctx, props)
    local out = {}
    if not (ctx and ctx.get_property) then return out end
    for _, name in ipairs(props or M.props) do
        out[name] = ctx:get_property(name) or ""
    end
    return out
end

function M.restore_props(ctx, snapshot, props)
    if not (ctx and ctx.set_property) then return end
    for _, name in ipairs(props or M.props) do
        ctx:set_property(name, snapshot and snapshot[name] or "")
    end
end

function M.sync(ctx, state, core)
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
        ctx:set_property("_txjx_zzc_origin", state.origin_input or "")
        ctx:set_property("_txjx_zzc_display", state.display_word or "")
        ctx:set_property("_txjx_zzc_replaced", state.replaced_word or "")
        ctx:set_property("_txjx_zzc_cmd_candidates", table.concat(state.command_candidates or {}, "\n"))
        ctx:set_property("_txjx_zzc_shorten_idx", tostring(state.shorten_idx or 1))
    end
end

function M.set_pending_trigger(ctx, enabled)
    if not (ctx and ctx.set_property) then return end
    ctx:set_property("_txjx_zzc_pending", enabled and "1" or "")
end

function M.pending_trigger(ctx)
    return ctx and ctx.get_property and ctx:get_property("_txjx_zzc_pending") == "1"
end

function M.restore_from_context(ctx, state, core)
    if not (ctx and ctx.get_property) then return false end
    local prop_stage = ctx:get_property("_txjx_zzc_stage") or ""
    local prop_word = ctx:get_property("_txjx_zzc_word") or ""
    local prop_items = ctx:get_property("_txjx_zzc_items") or ""
    local prop_mode = ctx:get_property("_txjx_zzc_mode") or ""
    local prop_target = ctx:get_property("_txjx_zzc_target") or ""
    local prop_origin = ctx:get_property("_txjx_zzc_origin") or ""
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
    state.origin_input = prop_origin or ""
    state.display_word = prop_display ~= "" and prop_display or prop_word or ""
    state.replaced_word = prop_replaced or ""
    state.shorten_idx = prop_shorten_idx
    state.command_candidates = {}
    for line in tostring(prop_cmd_candidates or ""):gmatch("[^\n]+") do
        state.command_candidates[#state.command_candidates + 1] = line
    end
    core.set_state_items(state.items)
    core.set_current_stage(state.stage)
    return true
end

function M.sync_from_context_if_needed(ctx, state, core)
    if not (ctx and ctx.get_property) then return false end
    local prop_stage = ctx:get_property("_txjx_zzc_stage") or ""
    if prop_stage == "" then return false end
    if (not state.active) or state.stage ~= prop_stage then
        return M.restore_from_context(ctx, state, core)
    end
    return false
end

function M.context_has_active_state(ctx)
    if not (ctx and ctx.get_property) then return false end
    return (ctx:get_property("_txjx_zzc_stage") or "") ~= ""
        or (ctx:get_property("_txjx_zzc_word") or "") ~= ""
        or (ctx:get_property("_txjx_zzc_items") or "") ~= ""
end

return M
