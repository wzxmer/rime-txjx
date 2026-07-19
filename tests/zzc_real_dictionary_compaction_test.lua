package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local chain = require("zzc.txjx_zzc_chain")
local core = require("zzc.txjx_zzc_core")

local DICTIONARIES = {
    "txjx.dict.yaml",
    "txjx.fjcy.dict.yaml",
    "txjx.user.dict.yaml",
}

local function starts_with(text, prefix)
    return text:sub(1, #prefix) == prefix
end

local function load_root(root)
    local buckets, ordinal = {}, 0
    for _, path in ipairs(DICTIONARIES) do
        local file = assert(io.open(path, "r"))
        for line in file:lines() do
            local word, code = line:match("^([^#\t][^\t]*)\t([^\t%s]+)")
            if word and #code <= 6 and starts_with(code, root) then
                ordinal = ordinal + 1
                buckets[code] = buckets[code] or {}
                buckets[code][#buckets[code] + 1] = {
                    word = word, ordinal = ordinal,
                }
            end
        end
        file:close()
    end
    return buckets
end

local function words_probe(buckets)
    return function(code)
        local out = {}
        for i, entry in ipairs(buckets[code] or {}) do out[i] = entry.word end
        return out
    end
end

local function remove_word(bucket, word)
    for index, entry in ipairs(bucket or {}) do
        if entry.word == word then
            table.remove(bucket, index)
            return
        end
    end
end

local function apply_records(buckets, records)
    for _, record in ipairs(records) do
        buckets[record.code] = buckets[record.code] or {}
        if record.mark == "!" then
            remove_word(buckets[record.code], record.word)
        else
            table.insert(buckets[record.code], 1, {
                word = record.word, ordinal = -1,
            })
        end
    end
end

local function word_locations(buckets, word)
    local out = {}
    for code, entries in pairs(buckets) do
        for _, entry in ipairs(entries) do
            if entry.word == word then out[#out + 1] = code end
        end
    end
    table.sort(out)
    return out
end

local function standard_path(root, code)
    local allowed = { a = true, i = true, o = true, u = true, v = true }
    for index = #root + 1, #code do
        if not allowed[code:sub(index, index)] then return false end
    end
    return true
end

local function internal_gaps(buckets, root)
    local out, seen = {}, {}
    for code, entries in pairs(buckets) do
        if entries[1] and starts_with(code, root) and standard_path(root, code) then
            for length = #root, #code - 1 do
                local prefix = code:sub(1, length)
                if not seen[prefix] and not (buckets[prefix] and buckets[prefix][1]) then
                    seen[prefix] = true
                    out[#out + 1] = prefix
                end
            end
        end
    end
    table.sort(out)
    return table.concat(out, "|")
end

local function full_code_for(word, code)
    local hints = core.hints_for_word_code(word, code)
    local items = core.items_from_text(word, hints)
    local full = items and core.code_for_items(items, 6) or nil
    return full and starts_with(full, code) and full or code
end

local function next_code_for(word, code)
    local full = full_code_for(word, code)
    if #full <= #code then return nil end
    return full:sub(1, #code + 1)
end

local fkjk = load_root("fkjk")
local initial_count = 0
for _, entries in pairs(fkjk) do initial_count = initial_count + #entries end

local delete_records = assert(chain.plan_delete(
    { "知己" }, "fkjk", words_probe(fkjk)))
apply_records(fkjk, delete_records)
assert(fkjk.fkjk[1].word == "织机")
assert(fkjk.fkjka[1].word == "治绩")
assert(internal_gaps(fkjk, "fkjk") == "")

fkjk = load_root("fkjk")
local replace_records = assert(chain.plan_replace({
    word = "雉鸡",
    code = "fkjk",
    replaced_word = "知己",
    probe_words = words_probe(fkjk),
    next_code = next_code_for,
    source_codes = { "fkjku", "fkjkua" },
}))
apply_records(fkjk, replace_records)
assert(fkjk.fkjk[1].word == "雉鸡")
assert(fkjk.fkjku[1].word == "知己")
assert(fkjk.fkjkua[1].word == "智己")
assert(#word_locations(fkjk, "雉鸡") == 1)

local yyj = load_root("yyj")
local before_gaps = internal_gaps(yyj, "yyj")
local yyj_records = assert(chain.plan_delete(
    { "有意见" }, "yyj", words_probe(yyj)))
apply_records(yyj, yyj_records)
assert(yyj.yyj[1].word == "演艺界")
assert(yyj.yyja[1].word == "演绎出")
assert(yyj.yyjaa[1].word == "渔阳郡")
assert(internal_gaps(yyj, "yyj") == before_gaps)

print(string.format(
    "zzc_real_dictionary_compaction_test: PASS rows=%d existing_yyj_gaps=%s",
    initial_count, before_gaps ~= "" and before_gaps or "none"))
