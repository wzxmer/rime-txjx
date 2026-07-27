package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local core = require("zzc.txjx_zzc_core")

local function equal(actual, expected, label)
    assert(actual == expected, string.format(
        "%s: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
end

local native_secondary = { type = "table", text = "新词", comment = "" }
local completion = { type = "completion", text = "补全词", comment = "~a" }
local zzc_completion = { type = "zzc_completion", text = "自造词补全", comment = "自造词" }
local other_code = { type = "table", text = "其他词", preedit = "other", comment = "" }

equal(core.snapshot_candidate_kind(native_secondary, "abcdaa", true), "normal",
    "exact probe accepts native candidate without preedit")
equal(core.snapshot_candidate_kind(completion, "abcdaa", true), nil,
    "exact probe rejects completion")
equal(core.snapshot_candidate_kind(zzc_completion, "abcdaa", true), nil,
    "exact probe rejects ZZZC completion")
equal(core.snapshot_candidate_kind(other_code, "abcdaa", false), nil,
    "normal snapshot still requires matching preedit")

print("zzc_exact_probe_test: PASS")
