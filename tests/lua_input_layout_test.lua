package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local modules = {
    "input.txjx_key_event",
    "input.txjx_processor_state",
    "input.txjx_commit_guard",
    "input.txjx_ascii_input",
    "input.txjx_direct_symbols",
    "input.txjx_punctuation",
    "input.txjx_topup",
}

for _, name in ipairs(modules) do
    local loaded = require(name)
    assert(type(loaded) == "table", "module did not return table: " .. name)
end

for _, name in ipairs({
    "txjx_key_event",
    "txjx_processor_state",
    "txjx_commit_guard",
    "txjx_ascii_input",
    "txjx_direct_symbols",
    "txjx_punctuation",
    "txjx_topup",
}) do
    assert(package.searchpath(name, package.path) == nil, "legacy module path remains: " .. name)
end

local processor = require("txjx_processor")
assert(type(processor) == "table", "txjx_processor did not return table")
assert(type(processor.init) == "function", "txjx_processor.init missing")
assert(type(processor.func) == "function", "txjx_processor.func missing")
assert(type(processor.fini) == "function", "txjx_processor.fini missing")

local schema_file = assert(io.open("txjx.schema.yaml", "rb"))
local schema = schema_file:read("*a")
schema_file:close()
assert(not schema:find("uppercase:", 1, true), "uppercase recognizer would retain Caps preedit")
assert(schema:find("Shift_L: commit_code", 1, true), "left Shift must commit raw code")
assert(schema:find("Shift_R: commit_code", 1, true), "right Shift must commit raw code")

local custom_file = assert(io.open("txjx.custom.yaml", "rb"))
local custom = custom_file:read("*a")
custom_file:close()
assert(custom:find("Shift_L: commit_code", 1, true), "custom left Shift must commit raw code")
assert(custom:find("Shift_R: commit_code", 1, true), "custom right Shift must commit raw code")

print("lua_input_layout_test: PASS")
