package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local old_rime_api = rime_api
local old_candidate = Candidate
local old_yield = yield
local old_state = _G.__txjx_typing_stats
local suffix = tostring(os.time()) .. tostring(math.random(100000, 999999))
local schema_id = "typing_stats_test_" .. suffix
local stats_path = "./zzc_state/" .. schema_id .. "_typing_stats.tsv"

_G.__txjx_typing_stats = nil
rime_api = { get_user_data_dir = function() return "." end }

local emitted = {}
Candidate = function(kind, start_pos, end_pos, text, comment)
    return {
        type = kind,
        start = start_pos,
        _end = end_pos,
        text = text,
        comment = comment,
    }
end
yield = function(candidate)
    emitted[#emitted + 1] = candidate
end

package.loaded["txjx_typing_stats"] = nil
local stats = require("txjx_typing_stats")

local disconnected = false
local notify
local context = {
    get_option = function(_, name) return name == "ascii_mode" and false end,
    commit_notifier = {
        connect = function(_, callback)
            notify = callback
            return {
                disconnect = function() disconnected = true end,
            }
        end,
    },
}
local env = {
    engine = {
        context = context,
        schema = { schema_id = schema_id },
    },
}
local key = {
    keycode = string.byte("a"),
    release = function() return false end,
    ctrl = function() return false end,
    alt = function() return false end,
    super = function() return false end,
}

stats.init_processor(env)
assert(type(notify) == "function", "processor must subscribe to commit notifier")
assert(stats.processor(key, env) == 2, "stats processor must always pass through")
notify({ get_commit_text = function() return "天地A" end })
local stats_file = assert(io.open(stats_path, "r"), "stats file must be created after first commit")
stats_file:close()

stats.translator("=tj", { start = 0, _end = 3 }, env)
assert(#emitted == 3, "=tj must yield today, week and total rows")
assert(emitted[1].text:find("今日 2 字", 1, true), "Chinese commit count must be reflected")
assert(emitted[1].comment:find("击键 1", 1, true), "key count must be reflected")
assert(emitted[1].comment:find("上屏 1", 1, true), "commit count must be reflected")

stats.fini_processor(env)
assert(disconnected, "processor fini must disconnect commit notifier")
os.remove(stats_path)

local schema_file = assert(io.open("txjx.schema.yaml", "rb"))
local schema = schema_file:read("*a")
schema_file:close()
local stats_processor_pos = assert(schema:find("lua_processor@*txjx_typing_stats_processor", 1, true))
local zzc_processor_pos = assert(schema:find("lua_processor@*zzc.txjx_zzc_processor", 1, true))
local stats_translator_pos = assert(schema:find("lua_translator@*txjx_typing_stats_translator", 1, true))
local core_translator_pos = assert(schema:find("lua_translator@*txjx_core", 1, true))
assert(stats_processor_pos < zzc_processor_pos, "stats processor must precede ZZZC")
assert(stats_translator_pos < core_translator_pos, "stats translator must precede core translator")

local old_ext_core = package.loaded["txjx_ext_core"]
local old_ext_core_preload = package.preload["txjx_ext_core"]
package.loaded["txjx_ext_core"] = nil
package.preload["txjx_ext_core"] = function()
    error("=tj must not load txjx_ext_core")
end
package.loaded["txjx_core"] = nil
local core = require("txjx_core")
local core_env = {
    engine = {
        context = { get_option = function() return true end },
        schema = { schema_id = "txjx" },
    },
}
assert(pcall(core.func, "=tj", { start = 0, _end = 3 }, core_env), "=tj must bypass txjx_core")
package.preload["txjx_ext_core"] = old_ext_core_preload
package.loaded["txjx_ext_core"] = old_ext_core

rime_api = old_rime_api
Candidate = old_candidate
yield = old_yield
_G.__txjx_typing_stats = old_state

print("typing_stats_test: PASS")
