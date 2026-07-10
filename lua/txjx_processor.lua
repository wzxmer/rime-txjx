-- 天行键 统一按键处理器
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-07-10

local string_sub = string.sub
local string_byte = string.byte
local string_find = string.find
local type = type
local config_util = require("common.txjx_config")
local state = require("common.txjx_state")
local registry = require("common.txjx_cache_registry")
local key_event_util = require("txjx_key_event")
local processor_state = require("txjx_processor_state")
local commit_guard = require("txjx_commit_guard")
local direct_symbols = require("txjx_direct_symbols")
local ascii_input = require("txjx_ascii_input")
local topup = require("txjx_topup")
local punctuation = require("txjx_punctuation")

local kAccepted = 1
local kNoop = 2

local CHAR_CACHE = key_event_util.char_cache

local function _s2set(str)
    return config_util.s2set(str)
end

local function _config_bool(config, path, default)
    local value = config and config:get_bool(path)
    if value ~= nil then return value end
    local text = config and config:get_string(path)
    if text == "false" or text == "0" or text == "off" or text == "no" then return false end
    if text == "true" or text == "1" or text == "on" or text == "yes" then return true end
    return default
end

local function _collect_reverse_prefixes(config, schema_id, include_aux)
    return config_util.collect_reverse_prefixes(config, schema_id, include_aux)
end

local _commit_selected_non_completion = commit_guard.commit_selected_non_completion

local function _is_memory_tool_input(input)
    return input == "=mem" or input == "=mem!"
end

local _space_guard_clear = commit_guard.clear_space
local _space_guard_note = commit_guard.note_space
local _push_code_input = commit_guard.push_code_input

local _topup_exec = topup.exec
local _topup_clear_pending_key = topup.clear_pending
local _topup_clear_queued_keys = topup.clear_queued
local _topup_flush_key = topup.flush_key
local _topup_handle_queued_release = topup.handle_queued_release
local _topup_is_pending_key_event = topup.is_pending_event
local _topup_flush_plain_alpha_press = topup.flush_plain_alpha_press
local _topup_flush_pending_digit_press = topup.flush_pending_digit_press
local _plain_code_key = topup.plain_code_key
local _topup_push_key = topup.push_key

local _is_space_key = key_event_util.is_space
local _uppercase_char = key_event_util.uppercase_char
local _alpha_upper_char = key_event_util.alpha_upper_char

local _commit_direct_symbols_unique_if_leaf = direct_symbols.commit_unique_if_leaf

local function _handle_direct_symbols_alpha_press(env, ctx, key, clean_key, kc, opts)
    return direct_symbols.handle_alpha_press(env, ctx, key, clean_key, kc, opts, _topup_push_key)
end

local _topup_eval_input = topup.eval_input

local _space_guard_process = commit_guard.process_space

local _is_reverse_input = key_event_util.is_reverse_input
local _passthrough_alpha_key = key_event_util.passthrough_alpha

local _topup_auto_fallback = topup.auto_fallback

local _commit_menu_index = commit_guard.commit_menu_index

local function processor(key_event, env)
    local kn, sf, clean_key, repr = key_event_util.resolve(key_event, env)
    local ctx = env.engine.context
    local kc = key_event.keycode
    if ctx:is_composing() and _is_memory_tool_input(ctx.input) and not key_event:release() then
        local alpha = _alpha_upper_char(clean_key, kc) or _uppercase_char(clean_key, kc)
        if _is_space_key(kc, clean_key, repr) or alpha then
            ctx:clear()
            _topup_clear_queued_keys(env)
            _space_guard_clear(env)
            return kNoop
        end
    end
    _topup_flush_pending_digit_press(env, ctx, key_event, sf, clean_key, kc, repr)
    local ascii_result, frame = ascii_input.process_front(key_event, env, kn, sf, clean_key, repr)
    if ascii_result then return ascii_result end
    local ascii_mode = frame.ascii_mode
    local no_modifier = frame.no_modifier
    local caps_on = frame.caps_on
    if no_modifier and not sf and not caps_on and not key_event:release()
        and _is_space_key(kc, clean_key, repr) then
        local had_pending = topup.has_pending(env)
        if had_pending then
            _topup_flush_key(env, ctx)
            if ctx:is_composing() and ctx:has_menu() and _commit_selected_non_completion(ctx) then
                env._space_commit_release_guard = true
                return kAccepted
            end
        end
    end
    local opts = {
        smarttwo = ctx:get_option("smarttwo"),
        direct_symbols = ctx:get_option("direct_symbols"),
        jisuanqi = ctx:get_option("jisuanqi"),
        auto_fallback = ctx:get_option("auto_fallback"),
    }

    local space_result = (not sf) and _space_guard_process(env, ctx, key_event, clean_key, repr, kc, no_modifier) or nil
    if space_result then return space_result end

    local sm_result = punctuation.process(key_event, env, kn, sf, clean_key, opts)
    if sm_result == kAccepted then
        _space_guard_clear(env)
        return kAccepted
    end

    if key_event:release() then
        if _topup_handle_queued_release(env, ctx, clean_key, kc) then return kAccepted end
        if ctx:has_menu() then
            if kc == 0xffe3 or kc == 0xffe4 then -- Ctrl
                 if _commit_menu_index(ctx, env.engine, 1) then return kAccepted end
                 return kAccepted
            elseif kc == 0xffe9 or kc == 0xffea then -- Alt
                 if _commit_menu_index(ctx, env.engine, 2) then return kAccepted end
                 return kAccepted
            end
        end
        return kNoop
    end

    if key_event:ctrl() or key_event:alt() then
        _topup_clear_pending_key(env)
        _space_guard_clear(env)
        return kNoop
    end
    if kc < 32 or kc >= 127 then
        _topup_clear_pending_key(env)
        if not _is_space_key(kc, clean_key, repr) then _space_guard_clear(env) end
        return kNoop
    end
    
    local raw_key = CHAR_CACHE[kc] or clean_key
    local plain_code_key = _plain_code_key(env, raw_key, clean_key, kc)
    local key = plain_code_key or raw_key
    local is_code_key = plain_code_key ~= nil or (env._alpha and env._alpha[key])
    if topup.has_pending(env) and not _topup_is_pending_key_event(env, key, kc) and not is_code_key then
        _topup_clear_pending_key(env)
    end
    if _topup_flush_plain_alpha_press(env, ctx, key_event, key, sf, caps_on) then
        return kAccepted
    end
    if _passthrough_alpha_key(env, ctx, sf, key, clean_key, kc) then
        return kNoop
    end

    if opts.direct_symbols and ctx.input == ";" and env._alpha[key] then
        _push_code_input(env, ctx, key)
        if _commit_direct_symbols_unique_if_leaf(env, ctx, env.engine) then return kAccepted end
        return kAccepted
    end

    local direct_symbols_result = _handle_direct_symbols_alpha_press(env, ctx, key, clean_key, kc, opts)
    if direct_symbols_result then return direct_symbols_result end

    if is_code_key and _topup_flush_key(env, ctx) then
        _push_code_input(env, ctx, key)
        return kAccepted
    end

    if _topup_auto_fallback(env, ctx, key, clean_key, kc, opts) then
        return kAccepted
    end

    if not env._tu_streaming and is_code_key then
        local current_input = ctx.input
        local eval = _topup_eval_input(current_input, opts)
        local input_len = eval.input_len
        local min_len = env._tu_min
        
        local prev = eval.prev
        local first = (input_len > 0) and eval.first or key
        
        local is_tu = env._tu_set[key]
        local is_ptu = env._tu_set[prev]
        local is_ftu = env._tu_set[first]

        if not eval.semicolon_input and not (env._tu_cmd and is_ftu) then
            if is_ptu and not is_tu then
                env._txjx_zzc_follow_key = key
                local executed, consumed_follow = _topup_exec(env)
                if not executed then return kAccepted end
                env._txjx_zzc_follow_key = nil
                if not consumed_follow then
                    _topup_push_key(env, ctx, key, clean_key, kc, input_len)
                end
                return kAccepted
            elseif not is_ptu and not is_tu and input_len >= min_len then
                env._txjx_zzc_follow_key = key
                local executed, consumed_follow = _topup_exec(env)
                if not executed then return kAccepted end
                env._txjx_zzc_follow_key = nil
                if not consumed_follow then
                    _topup_push_key(env, ctx, key, clean_key, kc, input_len)
                end
                return kAccepted
            elseif input_len >= env._tu_max then
                env._txjx_zzc_follow_key = key
                local executed, consumed_follow = _topup_exec(env)
                if not executed then return kAccepted end
                env._txjx_zzc_follow_key = nil
                if not consumed_follow then
                    _topup_push_key(env, ctx, key, clean_key, kc, input_len)
                end
                return kAccepted
            end
        end
    end

    if is_code_key and no_modifier and not sf and not caps_on and not _is_reverse_input(env, ctx.input) then
        _space_guard_note(env, ctx, ctx.input or "", key)
    else
        _space_guard_clear(env)
    end
    return kNoop
end

local function init(env)
    local config = env.engine.schema.config

    processor_state.init(env)
    
    local ab = config:get_string("speller/alphabet") or "abcdefghijklmnopqrstuvwxyz"
    env._alpha = {}
    for i = 1, #ab do
        local ch = string_sub(ab, i, i)
        env._alpha[ch] = true
    end
    
    env._tu_set = _s2set(config:get_string("topup/topup_with") or "")
    env._tu_min = config:get_int("topup/min_length") or 4
    env._tu_max = config:get_int("topup/max_length") or 6
    env._tu_ac = config:get_bool("topup/auto_clear") or false
    env._tu_cmd = config:get_bool("topup/topup_command") or false
    env._tu_streaming = config:get_bool("translator/enable_sentence") or false
    local schema_id = env.engine.schema.schema_id or ""
    env._rx_prefix = _collect_reverse_prefixes(config, schema_id, true)
    state.init_append(env, schema_id)
    env._space_guard_enabled = config:get_string("txjx/space_guard") ~= "off"
    env._direct_symbols_fast_leaf = _config_bool(config, "txjx/direct_symbols_fast_leaf", true)

    registry.register("processor", function()
        direct_symbols.reset_cache()
        processor_state.reset(env)
        return true
    end)

    collectgarbage("step", 80)
end

local function fini(env)
    processor_state.fini(env)
    -- 主动GC：释放资源后回收内存
    collectgarbage("step", 200)
end

return { init = init, func = processor, fini = fini }
