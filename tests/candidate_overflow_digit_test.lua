package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local guard = require("input.txjx_commit_guard")

local function equal(actual, expected, label)
    assert(actual == expected, string.format(
        "%s: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
end

local function context(words, tags, input)
    local menu = {
        prepare = function(self, count) self.prepared = count end,
        get_candidate_at = function(_, index)
            local word = words[index + 1]
            return word and { type = "table", text = word } or nil
        end,
    }
    local segment = {
        menu = menu,
        has_tag = function(_, tag) return tags[tag] == true end,
    }
    local ctx = {
        input = input or "abcd",
        composition = { back = function() return segment end },
        is_composing = function() return true end,
        has_menu = function() return true end,
        get_property = function() return "" end,
        clear = function(self) self.cleared = true end,
    }
    return ctx, menu
end

local function engine(page_size)
    return {
        schema = { page_size = page_size or 5 },
        committed = {},
        commit_text = function(self, text) self.committed[#self.committed + 1] = text end,
    }
end

do
    local ctx, menu = context({ "甲", "乙" }, { abc = true })
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "2"), false, "valid second candidate passes through")
    equal(#output.committed, 0, "valid selection does not commit early")
    equal(menu.prepared, 2, "valid selection prepares requested ordinal")
end

do
    local ctx = context({ "甲", "乙", "丙" }, { abc = true })
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "3"), false, "valid third candidate passes through")
end

do
    local ctx, menu = context({ "甲", "乙" }, { abc = true })
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "3"), true, "missing third candidate overflows")
    equal(ctx.cleared, true, "overflow clears composition")
    equal(#output.committed, 1, "overflow uses one commit record")
    equal(output.committed[1], "甲3", "overflow commits first candidate and digit together")
    equal(menu.prepared, 3, "overflow prepares requested ordinal")
end

do
    local ctx = context({ "甲" }, { abc = true })
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "2"), true, "single candidate overflows on two")
    equal(#output.committed, 1, "single candidate uses one commit record")
    equal(output.committed[1], "甲2", "single candidate keeps digit")
end

do
    local ctx = context({ "甲", "乙", "丙", "丁", "戊" }, { abc = true })
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "5"), false,
        "fifth candidate remains selectable on five-item page")
end

do
    local ctx = context({ "甲", "乙", "丙", "丁" }, { abc = true })
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "5"), true,
        "missing fifth candidate overflows")
    equal(#output.committed, 1, "missing fifth candidate uses one commit record")
    equal(output.committed[1], "甲5", "missing fifth candidate keeps digit")
end

do
    local ctx = context({ "甲", "乙", "丙", "丁", "戊", "己" }, { abc = true })
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "6"), true,
        "sixth candidate overflows beyond five-item page")
    equal(#output.committed, 1, "sixth candidate overflow uses one commit record")
    equal(output.committed[1], "甲6", "sixth candidate overflow keeps digit")
end

do
    local ctx = context({ "甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸" }, { abc = true })
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "0"), true,
        "tenth candidate overflows beyond five-item page")
    equal(#output.committed, 1, "tenth candidate overflow uses one commit record")
    equal(output.committed[1], "甲0", "tenth candidate overflow keeps digit")
end

do
    local ctx = context({ "甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸" }, { abc = true })
    local output = engine(10)
    equal(guard.commit_overflow_digit(ctx, output, "0"), false,
        "tenth candidate remains selectable on ten-item page")
    equal(#output.committed, 0, "ten-item page does not commit early")
end

do
    local ctx = context({ "甲", "乙" }, { abc = true })
    ctx.composition:back().selected_index = 1
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "3"), false, "moved selection stays native")
end

for _, case in ipairs({
    { input = "=1+2", tags = { expression = true }, label = "calculator" },
    { input = "vabc", tags = { jderfen = true }, label = "reverse lookup" },
    { input = ";abc", tags = { abc = true }, label = "direct symbols" },
}) do
    local ctx = context({ "甲", "乙" }, case.tags, case.input)
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "3"), false, case.label .. " is excluded")
    equal(#output.committed, 0, case.label .. " remains untouched")
end

do
    local ctx = context({ "甲", "乙" }, { abc = true })
    ctx.get_property = function(_, name)
        return name == "_txjx_zzc_stage" and "collect" or ""
    end
    local output = engine()
    equal(guard.commit_overflow_digit(ctx, output, "3"), false, "ZZZC state is excluded")
end

do
    local overflow_calls = 0
    local punctuation_calls = 0
    package.loaded["common.txjx_config"] = {
        s2set = function() return {} end,
        collect_reverse_prefixes = function() return {} end,
    }
    package.loaded["common.txjx_state"] = { init_append = function() end }
    package.loaded["common.txjx_cache_registry"] = { register = function() end }
    package.loaded["input.txjx_key_event"] = {
        char_cache = {},
        resolve = function() return "3", false, "3", "3" end,
        digit_char = function() return "3" end,
        is_reverse_input = function() return false end,
        passthrough_alpha = function() return false end,
        is_space = function() return false end,
        uppercase_char = function() return nil end,
        alpha_upper_char = function() return nil end,
    }
    package.loaded["input.txjx_processor_state"] = {
        init = function() end, reset = function() end, fini = function() end,
    }
    package.loaded["input.txjx_commit_guard"] = {
        clear_space = function() end,
        note_space = function() end,
        push_code_input = function() end,
        process_space = function() return nil end,
        commit_overflow_digit = function()
            overflow_calls = overflow_calls + 1
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
    package.loaded["input.txjx_punctuation"] = {
        process = function()
            punctuation_calls = punctuation_calls + 1
            return nil
        end,
    }
    package.loaded["txjx_processor"] = nil

    local processor = require("txjx_processor")
    local ctx = {
        input = "abcd",
        is_composing = function() return true end,
        get_option = function() return false end,
    }
    local event = {
        keycode = 51,
        release = function() return false end,
        ctrl = function() return false end,
        alt = function() return false end,
    }
    equal(processor.func(event, { engine = { context = ctx } }), 1,
        "processor consumes overflow before punctuation")
    equal(overflow_calls, 1, "processor calls overflow guard")
    equal(punctuation_calls, 0, "punctuation does not swallow overflow digit")
end

print("candidate_overflow_digit_test: PASS")
