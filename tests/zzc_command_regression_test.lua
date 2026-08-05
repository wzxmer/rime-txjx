package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local data_dir = assert(os.getenv("ZZC_TEST_DATA_DIR"), "missing ZZZC test data directory")
_G.rime_api = {
    get_user_data_dir = function() return data_dir end,
}

local core = require("zzc.txjx_zzc_core")

local function equal(actual, expected, label)
    assert(actual == expected, string.format(
        "%s: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
end

local function items(first, second, first_shape, second_shape)
    return {
        { text = first, parts = { s = "a", y = "b", p = first_shape or "a", code = "ab" .. (first_shape or "a") } },
        { text = second, parts = { s = "c", y = "d", p = second_shape or "i", code = "cd" .. (second_shape or "i") } },
    }
end

local function runtime_records()
    local out = {}
    local file = assert(io.open(data_dir .. "/zzc_state/runtime_ops.tsv", "r"))
    for line in file:lines() do
        local tx, op, word, code, mark = line:match(
            "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
        if tx then
            out[#out + 1] = { tx = tx, op = op, word = word, code = code, mark = mark }
        end
    end
    file:close()
    return out
end

local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function cover(code)
    return core.zzc_cover_for_input(code) or {
        rows = {}, append_rows = {}, hide_words = {}, restore_rows = {},
    }
end

assert(core.undo_all_pending())

local first_items = items("甲", "乙", "a", "i")
local second_items = items("丙", "丁", "o", "u")
local first_word = core.word_from_items(first_items)
local second_word = core.word_from_items(second_items)

assert(core.save_word_at_code(first_items, "abcd", nil, function() return nil end, function() return {} end))
local function append_probe(code)
    if code == "abcdou" then return { "六码原词", second_word } end
    return {}
end

local before_append = #runtime_records()
assert(core.append_word_at_code(second_items, "abcd", append_probe))
local current = cover("abcd")
equal(current.rows[1].word, first_word, "make remains normal candidate")
equal(current.append_rows[1].word, second_word, "append remains trailing candidate")
assert(cover("abcdou").hide_words[second_word], "append hides terminal duplicate")

local append_records = runtime_records()
equal(#append_records, before_append + 2, "append transaction record count")
equal(append_records[#append_records - 1].tx, append_records[#append_records].tx,
    "append duplicate cleanup transaction")
assert(core.undo_last_tx())
equal(#runtime_records(), before_append, "single undo removes append and duplicate cleanup")
assert(not cover("abcdou").hide_words[second_word], "undo restores terminal duplicate")

assert(core.append_word_at_code(second_items, "abcd", append_probe))
current = cover("abcd")

assert(core.reorder_words_at_code({ second_word, first_word }, "abcd"))
current = cover("abcd")
equal(current.rows[1].word, second_word, "order promotes selected append candidate")
equal(current.rows[2].word, first_word, "order preserves remaining candidate")

assert(core.delete_word_at_code(second_word, "abcd"))
current = cover("abcd")
assert(current.hide_words[second_word], "delete must hide exact word")
assert(core.restore_word_at_code(second_word, "abcd"))
current = cover("abcd")
equal(current.rows[1].word, second_word, "restore returns hidden candidate")

assert(core.undo_last_tx())
current = cover("abcd")
assert(current.hide_words[second_word], "single undo must remove restore transaction only")

local before_chain = #runtime_records()
assert(core.delete_word_at_code(first_word, "abcd", function(code)
    if code == "abcd" then return { first_word } end
    if code == "abcda" then return { second_word } end
    return {}
end))
local after_chain_records = runtime_records()
assert(#after_chain_records > before_chain + 1, "delete compaction must write multiple records")
local chain_tx = after_chain_records[#after_chain_records].tx
for index = before_chain + 1, #after_chain_records do
    equal(after_chain_records[index].tx, chain_tx, "compaction transaction")
end
assert(core.undo_last_tx())
equal(#runtime_records(), before_chain, "single undo removes full compaction chain")

assert(core.undo_all_pending())
equal(#runtime_records(), 0, "clear removes all runtime operations")

assert(core.save_word_at_code(first_items, "abcd", nil, function() return nil end, function() return {} end))
local flush_ok, flush_changed = core.flush_runtime_ops()
assert(flush_ok and flush_changed, "flush must clear a non-empty runtime batch")
for _, name in ipairs({ "runtime_ops.tsv", "runtime_exact.tsv" }) do
    local content = read_all(data_dir .. "/zzc_state/" .. name):gsub("\r\n", "\n")
    equal(content, "\n", name .. " keeps an iCloud-safe empty representation")
end
assert(core.undo_all_pending())
local effective_content = read_all(data_dir .. "/zzc_state/effective_state.tsv"):gsub("\r\n", "\n")
equal(effective_content, "\n", "effective_state.tsv keeps an iCloud-safe empty representation")

print("zzc_command_regression_test: PASS")
