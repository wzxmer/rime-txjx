package.path = table.concat({
    "./lua/?.lua",
    "./lua/?/init.lua",
    "./lua/?/?.lua",
    package.path,
}, ";")

local core = require("zzc.txjx_zzc_core")
local store = require("zzc.txjx_zzc_store")

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "assert_eq") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
    end
end

local function assert_true(v, msg)
    if not v then error(msg or "assert_true") end
end

local function run()
    local pending = {
        { mark = "+", word = "甲", code = "abcd", tx = "1" },
        { mark = "+a", word = "乙", code = "abcd", tx = "2", append = true },
        { mark = "!", word = "甲", code = "abcd", tx = "3" },
        { mark = "^", word = "乙", code = "abcd", tx = "4" },
    }
    local cover = store.build_effective_projection("abcd", pending)
    assert_true(cover ~= nil, "cover nil")
    assert_true(cover.rows ~= nil, "rows nil")
    assert_true(cover.append_rows ~= nil, "append_rows nil")
    assert_true(cover.hide_words ~= nil, "hide_words nil")
    local snapshot = store.effective_state_snapshot("abcd", cover)
    assert_true(snapshot ~= nil, "snapshot nil")
    assert_true(#snapshot.lines >= 1, "snapshot lines empty")
    assert_eq(core.is_collect_selectable_candidate({ text = "甲", type = "table" }), true, "candidate gate")
    assert_eq(core.is_collect_selectable_candidate({ text = "~甲", type = "table" }), false, "tilde gate")
    assert_eq(core.candidate_visible_under_cover({ text = "甲", type = "table" }, { keep_words = { ["甲"] = true } }), false, "keep_words gate")
    assert_eq(core.candidate_visible_under_cover({ text = "乙", type = "table" }, { hide_words = { ["乙"] = true } }), false, "hide_words gate")
    assert_eq(core.candidate_visible_under_cover({ text = "丙", type = "table" }, {}), true, "visible default")
    assert_eq(
        (function()
            local f = loadfile("./lua/zzc/txjx_zzc_filter.lua")
            return type(f) == "function"
        end)(),
        true,
        "filter load"
    )
    return true
end

local ok, err = pcall(run)
if not ok then
    io.stderr:write(tostring(err), "\n")
    os.exit(1)
end
print("replay_check_ok")
