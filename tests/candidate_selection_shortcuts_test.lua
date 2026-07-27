package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local keys = require("zzc.txjx_zzc_keys")

local function equal(actual, expected, label)
    assert(actual == expected, string.format(
        "%s: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
end

equal(keys.resolve_collect_select_key("Tab"), 2, "Tab selects second candidate")
equal(keys.resolve_collect_select_key("semicolon", ";"), 2, "semicolon selects second candidate")
equal(keys.resolve_collect_select_key("apostrophe", "'"), 3, "apostrophe selects third candidate")
equal(keys.resolve_collect_select_key("Control_L"), nil, "Ctrl is not a candidate shortcut")
equal(keys.resolve_collect_select_key("Alt_L"), nil, "Alt is not a candidate shortcut")
equal(keys.resolve_collect_modifier_select_key, nil, "modifier shortcut resolver is removed")

local key_event_util = require("input.txjx_key_event")
local punctuation = require("input.txjx_punctuation")
local modified_commit_calls = 0
local modified_context = {
    input = "abc",
    has_menu = function() return true end,
    is_composing = function() return true end,
    clear = function() end,
    composition = {
        back = function()
            return {
                menu = {
                    get_candidate_at = function(_, index)
                        return { text = "candidate" .. tostring(index) }
                    end,
                },
            }
        end,
    },
}
local modified_env = {
    engine = {
        context = modified_context,
        commit_text = function() modified_commit_calls = modified_commit_calls + 1 end,
    },
    _tu_streaming = false,
}

local function ctrl_modified_symbol(name, keycode)
    local event = {
        keycode = keycode,
        repr = function() return "Control+" .. name end,
        ctrl = function() return true end,
        alt = function() return false end,
        super = function() return false end,
        shift = function() return false end,
        release = function() return false end,
    }
    local key_name, shift, clean_key = key_event_util.resolve(event, modified_env)
    equal(key_name, name, "Ctrl modifier keeps physical key name")
    equal(punctuation.process(event, modified_env, key_name, shift, clean_key, {
        smarttwo = true,
        direct_symbols = false,
        jisuanqi = false,
    }), 2, "Ctrl+" .. name .. " passes through")
end

ctrl_modified_symbol("semicolon", 0xBA)
ctrl_modified_symbol("apostrophe", 0xDE)
equal(modified_commit_calls, 0, "Ctrl punctuation never commits candidates")

local commit_calls = 0

package.loaded["common.txjx_config"] = {
    s2set = function() return {} end,
    collect_reverse_prefixes = function() return {} end,
}
package.loaded["common.txjx_state"] = { init_append = function() end }
package.loaded["common.txjx_cache_registry"] = { register = function() end }
package.loaded["input.txjx_key_event"] = {
    char_cache = {},
    resolve = function(key_event)
        local repr = key_event:repr()
        return repr, false, repr, repr
    end,
    is_reverse_input = function() return false end,
    passthrough_alpha = function() return false end,
    is_space = function() return false end,
    uppercase_char = function() return nil end,
    alpha_upper_char = function() return nil end,
}
package.loaded["input.txjx_processor_state"] = {
    init = function() end,
    reset = function() end,
    fini = function() end,
}
package.loaded["input.txjx_commit_guard"] = {
    clear_space = function() end,
    note_space = function() end,
    push_code_input = function() end,
    process_space = function() return nil end,
    commit_menu_index = function()
        commit_calls = commit_calls + 1
        return true
    end,
}
package.loaded["input.txjx_direct_symbols"] = {
    commit_unique_if_leaf = function() return false end,
    handle_alpha_press = function() return nil end,
    reset_cache = function() end,
}
package.loaded["input.txjx_ascii_input"] = {
    process_front = function()
        return nil, { ascii_mode = false, no_modifier = true, caps_on = false }
    end,
}
package.loaded["input.txjx_topup"] = {
    exec = function() return false, false, false end,
    plain_code_key = function() return nil end,
    eval_input = function()
        return { input_len = 0, first = "", prev = "", semicolon_input = false }
    end,
    auto_fallback = function() return nil end,
}
package.loaded["input.txjx_punctuation"] = { process = function() return nil end }
package.loaded["txjx_processor"] = nil

local processor = require("txjx_processor")
local context = {
    input = "abc",
    is_composing = function() return false end,
    get_option = function() return false end,
    has_menu = function() return true end,
}
local env = { engine = { context = context } }

local function modifier_release(name, keycode, ctrl, alt)
    local event = {
        keycode = keycode,
        repr = function() return name end,
        release = function() return true end,
        ctrl = function() return ctrl end,
        alt = function() return alt end,
    }
    equal(processor.func(event, env), 2, name .. " release passes through")
end

modifier_release("Control_L", 0xffe3, true, false)
modifier_release("Control_R", 0xffe4, true, false)
modifier_release("Alt_L", 0xffe9, false, true)
modifier_release("Alt_R", 0xffea, false, true)
equal(commit_calls, 0, "modifier releases never commit candidates")

print("candidate_selection_shortcuts_test: PASS")
