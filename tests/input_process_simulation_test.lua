package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local processor = require("txjx_processor")
local processor_state = require("input.txjx_processor_state")

local kAccepted = 1
local kNoop = 2

local function equal(actual, expected, label)
    assert(actual == expected, string.format(
        "%s: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
end

local function candidate(text, candidate_type)
    return { text = text, type = candidate_type or "table" }
end

local Fixture = {}
Fixture.__index = Fixture

function Fixture.new(words, options)
    local self = setmetatable({
        words = words or {},
        options = options or {},
        properties = {},
        committed = {},
        trace = {},
        page_size = 5,
    }, Fixture)

    local menu = {}
    function menu:prepare(count)
        self.prepared = count
    end
    function menu:get_candidate_at(index)
        return self.owner:candidates()[index + 1]
    end
    menu.owner = self

    local segment = { menu = menu, selected_index = 0, _end = 0 }
    function segment:has_tag(tag)
        return tag == "abc"
    end

    local context = { input = "", selected_index = 0 }
    self.context = context
    self.segment = segment

    context.composition = {
        back = function()
            segment.selected_index = context.selected_index
            segment._end = #context.input
            return segment
        end,
    }

    function context:is_composing()
        return self.input ~= ""
    end
    function context:has_menu()
        return #self.fixture:candidates() > 0
    end
    function context:get_selected_candidate()
        return self.fixture:candidates()[self.selected_index + 1]
    end
    function context:get_option(name)
        return self.fixture.options[name] == true
    end
    function context:set_option(name, value)
        self.fixture.options[name] = value == true
    end
    function context:get_property(name)
        return self.fixture.properties[name] or ""
    end
    function context:set_property(name, value)
        self.fixture.properties[name] = value or ""
    end
    function context:push_input(text)
        self.input = self.input .. text
        self.selected_index = 0
    end
    function context:pop_input(count)
        self.input = self.input:sub(1, -(count or 1) - 1)
        self.selected_index = 0
    end
    function context:clear()
        self.input = ""
        self.selected_index = 0
    end

    local engine = { context = context, schema = { page_size = self.page_size } }
    self.engine = engine
    function engine:commit_text(text)
        self.fixture.committed[#self.fixture.committed + 1] = text
    end
    function context:commit()
        local selected = self:get_selected_candidate()
        if selected then
            engine:commit_text(selected.text)
        elseif self.input ~= "" then
            engine:commit_text(self.input)
        end
        self:clear()
    end

    context.fixture = self
    engine.fixture = self
    self.env = {
        engine = engine,
        _alpha = {},
        _tu_set = {},
        _tu_min = 4,
        _tu_max = 6,
        _tu_ac = true,
        _tu_cmd = false,
        _tu_streaming = false,
        _rx_prefix = {},
        _space_guard_enabled = true,
        _direct_symbols_fast_leaf = false,
        _append_input_key = "_txjx_append_input",
        _append_suffix_key = "_txjx_append_suffix",
    }
    for byte = string.byte("a"), string.byte("z") do
        self.env._alpha[string.char(byte)] = true
    end
    for key in ("avuio;"):gmatch(".") do
        self.env._tu_set[key] = true
    end
    processor_state.init(self.env)
    return self
end

function Fixture:candidates()
    return self.words[self.context.input] or {}
end

function Fixture:event(key, modifiers)
    modifiers = modifiers or {}
    local names = {
        space = { code = 32, repr = "space" },
        BackSpace = { code = 0xff08, repr = "BackSpace" },
        Escape = { code = 0xff1b, repr = "Escape" },
        Return = { code = 0xff0d, repr = "Return" },
        Shift_L = { code = 0xffe1, repr = "Shift_L" },
        Caps_Lock = { code = 0xffe5, repr = "Caps_Lock" },
        semicolon = { code = 59, repr = "semicolon" },
        apostrophe = { code = 39, repr = "apostrophe" },
        period = { code = 46, repr = "period" },
    }
    local named = names[key]
    local repr = named and named.repr or key
    local code = named and named.code or string.byte(key)
    return {
        keycode = code,
        repr = function() return repr end,
        release = function() return modifiers.release == true end,
        ctrl = function() return modifiers.ctrl == true end,
        alt = function() return modifiers.alt == true end,
        super = function() return modifiers.super == true end,
        shift = function() return modifiers.shift == true end,
        caps = function() return modifiers.caps == true end,
    }
end

function Fixture:native_process(key, event)
    if event:release() or event:ctrl() or event:alt() or event:super() then return end
    if key:match("^[A-Z]$") then
        self.engine:commit_text(key)
    elseif key:match("^[a-z]$") then
        self.context:push_input(key)
    elseif key == "space" then
        if self.context:is_composing() then self.context:commit() end
    elseif key:match("^%d$") and self.context:is_composing() then
        local ordinal = key == "0" and 10 or tonumber(key)
        if ordinal <= self.page_size and self:candidates()[ordinal] then
            self.context.selected_index = ordinal - 1
            self.context:commit()
        end
    elseif key == "BackSpace" then
        if self.context:is_composing() then self.context:pop_input(1) end
    elseif key == "Escape" then
        self.context:clear()
    end
end

function Fixture:press(key, modifiers)
    local event = self:event(key, modifiers)
    local result = processor.func(event, self.env)
    if result == kNoop then self:native_process(key, event) end
    self.trace[#self.trace + 1] = {
        key = key,
        result = result,
        input = self.context.input,
        committed = table.concat(self.committed, "|"),
    }
    return result
end

function Fixture:type_keys(keys)
    for _, key in ipairs(keys) do self:press(key) end
end

local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    print("PASS", name)
end

test("ordinary code commits first candidate with space", function()
    local sim = Fixture.new({ jk = { candidate("JK1"), candidate("JK2") } })
    sim:type_keys({ "j", "k" })
    equal(sim.context.input, "jk", "ordinary input")
    equal(sim.context:get_selected_candidate().text, "JK1", "ordinary first candidate")
    sim:press("space")
    equal(table.concat(sim.committed), "JK1", "space commit")
    equal(sim.context.input, "", "space clears composition")
end)

test("alphabet without candidates stays in composition", function()
    local sim = Fixture.new({})
    equal(sim:press("b"), kNoop, "first alphabet key returns to speller")
    sim:type_keys({ "c", "d" })
    equal(table.concat(sim.committed), "", "no candidate does not commit raw alphabet")
    equal(sim.context.input, "bcd", "no candidate alphabet remains composing")
end)

test("no-candidate topup starts the follow key as new composition", function()
    local sim = Fixture.new({})
    sim:press("a")
    equal(sim.context.input, "a", "topup prefix remains composing")
    equal(sim:press("b"), kNoop, "follow key returns to speller after auto clear")
    equal(table.concat(sim.committed), "", "topup without candidate commits no raw alphabet")
    equal(sim.context.input, "b", "follow key becomes the new composition")
end)

test("auto fallback commits candidate and keeps follow key composing", function()
    local sim = Fixture.new({ bc = { candidate("BC") } }, { auto_fallback = true })
    sim:type_keys({ "b", "c", "d" })
    equal(table.concat(sim.committed), "BC", "auto fallback commits only the valid candidate")
    equal(sim.context.input, "d", "auto fallback follow key remains composing")
end)

test("caps lock commits uppercase ascii and unlock restores code input", function()
    local sim = Fixture.new({ a = { candidate("A-CANDIDATE") } })
    equal(sim:press("A", { caps = true }), kNoop, "caps uppercase bypasses Rime composition")
    equal(table.concat(sim.committed), "A", "caps uppercase commit")
    equal(sim.context.input, "", "caps uppercase leaves no composition")

    sim:press("period", { caps = true })
    equal(table.concat(sim.committed), "A.", "caps uses half-width ascii punctuation")

    equal(sim:press("a", { caps = true, shift = true }), kAccepted,
        "caps shift lowercase remains a direct Lua commit")
    equal(table.concat(sim.committed), "A.a", "shift temporarily reverses caps to lowercase")

    sim:press("a")
    equal(table.concat(sim.committed), "A.a", "caps off does not commit ascii")
    equal(sim.context.input, "a", "caps off restores code input")
end)

test("caps lock finishes composition and passes through to the system lock", function()
    local sim = Fixture.new({ jk = { candidate("JK") } })
    sim:type_keys({ "j", "k" })
    equal(sim:press("Caps_Lock"), kNoop, "caps press reaches native lock handling")
    equal(table.concat(sim.committed), "JK", "caps commits active Chinese candidate")
    equal(sim.context.input, "", "caps clears the previous composition")
    equal(sim:press("Caps_Lock", { release = true }), kNoop, "caps release reaches native lock handling")
end)

test("shift-modified uppercase consumes release without disabling later topup", function()
    local sim = Fixture.new({ ba = { candidate("BA") } })
    equal(sim:press("Shift_L"), kNoop, "shift press reaches ascii composer")
    equal(sim:press("A"), kAccepted, "uppercase input is handled by Lua")
    equal(sim:press("Shift_L", { release = true }), kAccepted, "modified shift release cannot toggle mode")
    sim:press("Return")
    equal(table.concat(sim.committed), "A", "uppercase sequence commits")

    sim:type_keys({ "b", "a", "c" })
    equal(table.concat(sim.committed), "ABA", "topup still commits after uppercase sequence")
    equal(sim.context.input, "c", "topup follow key remains composing")
end)

test("smart shortcuts commit second and third candidates", function()
    local words = { cd = { candidate("CD1"), candidate("CD2"), candidate("CD3") } }
    local second = Fixture.new(words, { smarttwo = true })
    second:type_keys({ "c", "d", "semicolon" })
    equal(table.concat(second.committed), "CD2", "semicolon second candidate")

    local third = Fixture.new(words, { smarttwo = true })
    third:type_keys({ "c", "d", "apostrophe" })
    equal(table.concat(third.committed), "CD3", "apostrophe third candidate")
end)

test("native digit selection and overflow digit preserve intent", function()
    local native = Fixture.new({ ef = { candidate("EF1"), candidate("EF2") } })
    native:type_keys({ "e", "f", "2" })
    equal(table.concat(native.committed), "EF2", "native second candidate")

    local overflow = Fixture.new({ gh = { candidate("GH1") } })
    overflow:type_keys({ "g", "h", "3" })
    equal(#overflow.committed, 1, "overflow uses one commit record")
    equal(overflow.committed[1], "GH13", "overflow keeps digit")
    equal(overflow.context.input, "", "overflow clears composition")

    local hidden = Fixture.new({
        jk = {
            candidate("IJ1"), candidate("IJ2"), candidate("IJ3"),
            candidate("IJ4"), candidate("IJ5"), candidate("IJ6"),
        },
    })
    hidden:type_keys({ "j", "k", "6" })
    equal(#hidden.committed, 1, "hidden sixth candidate uses one commit record")
    equal(hidden.committed[1], "IJ16", "hidden sixth candidate does not swallow digit")
    equal(hidden.context.input, "", "hidden sixth candidate clears composition")
end)

test("topup commits current candidate then continues next code", function()
    local sim = Fixture.new({
        ba = { candidate("BA") },
        c = { candidate("C") },
    })
    sim:type_keys({ "b", "a", "c" })
    equal(table.concat(sim.committed), "BA", "topup commit")
    equal(sim.context.input, "c", "topup follow key")
    sim:press("space")
    equal(table.concat(sim.committed, "|"), "BA|C", "topup final output")
end)

test("backspace escape and enter maintain composition invariants", function()
    local sim = Fixture.new({ xy = { candidate("XY") } })
    sim:type_keys({ "x", "y", "BackSpace" })
    equal(sim.context.input, "x", "backspace input")
    sim:press("Escape")
    equal(sim.context.input, "", "escape input")
    sim:type_keys({ "x", "y", "Return" })
    equal(table.concat(sim.committed), "xy", "enter commits raw code")
    equal(sim.context.input, "", "enter clears composition")
end)

test("modified punctuation passes through without accidental commit", function()
    local sim = Fixture.new({ mn = { candidate("MN") } }, { smarttwo = true })
    sim:type_keys({ "m", "n" })
    equal(sim:press("semicolon", { ctrl = true }), kNoop, "Ctrl semicolon result")
    equal(table.concat(sim.committed), "", "Ctrl semicolon commit")
    equal(sim.context.input, "mn", "Ctrl semicolon composition")
end)

test("period commits candidate before punctuation", function()
    local sim = Fixture.new({ pq = { candidate("PQ") } })
    sim:type_keys({ "p", "q", "period" })
    equal(sim.committed[1], "PQ", "period candidate")
    equal(sim.committed[2], "\227\128\130", "period punctuation")
    equal(sim.context.input, "", "period clears composition")
end)

print(string.format("input_process_simulation_test: PASS (%d scenarios)", passed))
