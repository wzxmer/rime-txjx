-- txjx 自造词核心模块
-- 参考、借鉴、转载或发布衍生实现时，请明确说明出处来自天行键 txjx：
-- https://github.com/wzxmer/rime-txjx

local M = {}

local char_parts
local char_parts_full_loaded = false
local char_parts_missing = {}
local pending_cache = {}
local pending_loaded = false
local session_exact_cache = {}
local runtime_exact_cache = {}
local runtime_exact_loaded = false
local write_file_atomic
local allow_cache = {}
local build_replace_snapshot

local function data_dir()
    if rime_api and rime_api.get_user_data_dir then
        return rime_api.get_user_data_dir()
    end
    return "."
end

local function join_path(base, name)
    if not base or base == "" then return name end
    return base .. "/" .. name
end

local function path(name)
    return join_path(data_dir(), name)
end

local function hidden_stem()
    local k = 73
    local bytes = { 189, 193, 179, 193 }
    local out = {}
    for i, v in ipairs(bytes) do
        out[i] = string.char(v - k)
    end
    return table.concat(out)
end

function M.allowed(env)
    local id = env and env.engine and env.engine.schema and env.engine.schema.schema_id or ""
    if allow_cache[id] ~= nil then return allow_cache[id] end
    local mark = hidden_stem()
    local ok = type(id) == "string" and id:sub(1, #mark) == mark
    allow_cache[id] = ok
    return ok
end

local function read_fields(line)
    return line:match("^([^\t]+)\t([^\t%s]+)")
end

local function utf8_chars(text)
    local chars = {}
    local start = 1
    while text and start <= #text do
        local next_start = utf8.offset(text, 2, start)
        if next_start then
            chars[#chars + 1] = text:sub(start, next_start - 1)
            start = next_start
        else
            chars[#chars + 1] = text:sub(start)
            break
        end
    end
    return chars
end

local function same_parts(a, b)
    return a and b and a.s == b.s and a.y == b.y and a.p == b.p
end

local function push_unique_part(bucket, entry)
    for _, current in ipairs(bucket) do
        if same_parts(current, entry) then return end
    end
    bucket[#bucket + 1] = entry
end

local function hint_matches(entry, hint)
    if not hint then return true end
    if type(hint) == "string" then
        return entry.code and (entry.code:sub(1, #hint) == hint or hint:sub(1, #entry.code) == entry.code)
    end
    if hint.code_prefix and hint.code_prefix ~= "" then
        local prefix = hint.code_prefix
        if not entry.code or (entry.code:sub(1, #prefix) ~= prefix and prefix:sub(1, #entry.code) ~= entry.code) then
            return false
        end
    end
    if hint.s and hint.s ~= "" and entry.s ~= hint.s then return false end
    if hint.y and hint.y ~= "" and entry.y ~= hint.y then return false end
    if hint.p and hint.p ~= "" and entry.p ~= hint.p then return false end
    return true
end

local function collapse_options(options)
    local first = options and options[1]
    if not first then return nil end
    for i = 2, #options do
        if not same_parts(first, options[i]) then
            return nil
        end
    end
    return first
end

local function hint_list_for_word(word, code)
    local chars = utf8_chars(word)
    local n = #chars
    local len = #(code or "")
    local hints = {}
    if n == 1 then
        hints[1] = { code_prefix = code }
    elseif n == 2 then
        hints[1] = { s = code:sub(1, 1), y = code:sub(2, 2) }
        hints[2] = { s = code:sub(3, 3), y = code:sub(4, 4) }
        if len >= 5 then hints[1].p = code:sub(5, 5) end
        if len >= 6 then hints[2].p = code:sub(6, 6) end
    elseif n == 3 then
        hints[1] = { s = code:sub(1, 1) }
        hints[2] = { s = code:sub(2, 2) }
        hints[3] = { s = code:sub(3, 3) }
        if len >= 4 then hints[1].p = code:sub(4, 4) end
        if len >= 5 then hints[2].p = code:sub(5, 5) end
        if len >= 6 then hints[3].p = code:sub(6, 6) end
    elseif n >= 4 then
        hints[1] = { s = code:sub(1, 1) }
        hints[2] = { s = code:sub(2, 2) }
        hints[3] = { s = code:sub(3, 3) }
        hints[n] = { s = code:sub(4, 4) }
        if len >= 5 then hints[1].p = code:sub(5, 5) end
        if len >= 6 then hints[2].p = code:sub(6, 6) end
    end
    return hints
end

function M.hints_for_word_code(word, code)
    return hint_list_for_word(word, code)
end

function M.append_candidate_text(text, code_hint)
    if not text or text == "" then return nil, "empty_text" end
    local current_word = M.buffer_word() or ""
    local append_text_value = text
    if current_word ~= "" and text:sub(1, #current_word) == current_word then
        append_text_value = text:sub(#current_word + 1)
    end
    if append_text_value == "" then return current_word end
    local hints = code_hint and M.hints_for_word_code(append_text_value, code_hint) or nil
    local items, err = M.items_from_text(append_text_value, hints)
    if not items and err and tostring(err):match("^ambiguous_char:") then
        items = M.raw_items_from_text(append_text_value)
    end
    if not items then return nil, err end
    M.state_items = M.state_items or {}
    for _, item in ipairs(items) do
        M.state_items[#M.state_items + 1] = item
    end
    return append_text_value
end

local function add_char_part(text, s, y, p, code)
    local bucket = char_parts[text]
    if not bucket then
        bucket = {}
        char_parts[text] = bucket
    end
    push_unique_part(bucket, { s = s, y = y, p = p, code = code or (s .. y .. p) })
end

local function load_char_parts_from_tsv(target)
    local f = io.open(path("zzc/char_parts.tsv"), "r")
    if not f then return false end
    local found = false
    local seen_target = false
    for line in f:lines() do
        local text, s, y, p, code = line:match("^([^\t]+)\t([^\t])\t([^\t])\t([^\t])\t([^\t%s]+)")
        if not text then
            text, s, y, p = line:match("^([^\t]+)\t([^\t])\t([^\t])\t([^\t])")
        end
        if text and s and y and p then
            if not target or text == target then
                add_char_part(text, s, y, p, code)
                found = true
                if target then seen_target = true end
            elseif target and seen_target then
                break
            end
        end
    end
    f:close()
    return true, found
end

local function load_char_parts_from_dict(target)
    local f = io.open(path("txjx.danzi.dict.yaml"), "r")
    if not f then return false, false end
    local found = false
    for line in f:lines() do
        if not line:match("^%s*#") then
            local text, code = read_fields(line)
            if text and code and (not target or text == target) and utf8.len(text) == 1 and #code >= 3 then
                add_char_part(text, code:sub(1, 1), code:sub(2, 2), code:sub(3, 3), code)
                found = true
            end
        end
    end
    f:close()
    return true, found
end

function M.load_char_parts(target)
    if not char_parts then char_parts = {} end
    if target and (char_parts[target] or char_parts_missing[target]) then return char_parts end
    if target and char_parts_full_loaded then return char_parts end
    if not target and char_parts_full_loaded then return char_parts end
    local load_target = target
    local opened, found
    if target then
        opened, found = load_char_parts_from_tsv(nil)
        if opened then
            char_parts_full_loaded = true
            found = char_parts[target] ~= nil
        end
    else
        opened, found = load_char_parts_from_tsv(load_target)
    end
    if not opened then
        opened, found = load_char_parts_from_dict(load_target)
    end
    if target then
        if not found then char_parts_missing[target] = true end
    else
        char_parts_full_loaded = true
    end
    return char_parts
end

function M.parts_for_char(ch, hint)
    local options = M.load_char_parts(ch)[ch]
    if not options or not options[1] then return nil, "missing_char:" .. tostring(ch) end
    if #options == 1 then return options[1] end

    local matched = {}
    if hint then
        for _, entry in ipairs(options) do
            if hint_matches(entry, hint) then matched[#matched + 1] = entry end
        end
        if #matched == 1 then return matched[1] end
        local collapsed = collapse_options(matched)
        if collapsed then return collapsed end
    end

    local collapsed = collapse_options(options)
    if collapsed then return collapsed end
    return nil, "ambiguous_char:" .. tostring(ch)
end

function M.items_from_text(text, hints)
    local items = {}
    for index, ch in ipairs(utf8_chars(text)) do
        local hint = nil
        if type(hints) == "table" then
            if hints.code_prefix or hints.s or hints.y or hints.p then
                hint = index == 1 and hints or nil
            else
                hint = hints[index]
            end
        elseif index == 1 then
            hint = hints
        end
        local part, err = M.parts_for_char(ch, hint)
        if not part then return nil, err end
        items[#items + 1] = { text = ch, parts = part }
    end
    return items
end

function M.raw_items_from_text(text)
    local items = {}
    for _, ch in ipairs(utf8_chars(text)) do
        items[#items + 1] = { text = ch, parts = nil }
    end
    return items
end

local code_at

function M.code_choices_for_text(text, len, limit)
    limit = limit or 9
    len = tonumber(len)
    if not text or text == "" or not len then return nil, "bad_input" end
    local chars = utf8_chars(text)
    local n = #chars
    if n < 2 then return nil, "too_short" end
    if n == 2 and (len < 4 or len > 6) then return nil, "bad_length" end
    if n == 3 and (len < 3 or len > 6) then return nil, "bad_length" end
    if n >= 4 and (len < 4 or len > 6) then return nil, "bad_length" end

    local choices, seen = {}, {}
    local items = {}
    local function walk(index)
        if #choices >= limit then return end
        if index > n then
            local code = code_at(items, n):sub(1, len)
            if not seen[code] then
                seen[code] = true
                local frozen = {}
                for i, item in ipairs(items) do
                    frozen[i] = { text = item.text, parts = item.parts }
                end
                choices[#choices + 1] = { word = text, code = code, items = frozen }
            end
            return
        end
        local ch = chars[index]
        local options = M.load_char_parts(ch)[ch]
        if not options or not options[1] then return end
        for _, part in ipairs(options) do
            items[index] = { text = ch, parts = part }
            walk(index + 1)
            if #choices >= limit then break end
        end
        items[index] = nil
    end
    walk(1)
    if not choices[1] then return nil, "missing_or_ambiguous" end
    return choices
end

code_at = function(items, n)
    if n == 2 then
        return items[1].parts.s .. items[1].parts.y .. items[2].parts.s .. items[2].parts.y .. items[1].parts.p .. items[2].parts.p
    elseif n == 3 then
        return items[1].parts.s .. items[2].parts.s .. items[3].parts.s .. items[1].parts.p .. items[2].parts.p .. items[3].parts.p
    end
    return items[1].parts.s .. items[2].parts.s .. items[3].parts.s .. items[#items].parts.s .. items[1].parts.p .. items[2].parts.p
end

function M.code_for_items(items, len)
    local n = #items
    if n < 2 then return nil, "too_short" end
    len = tonumber(len)
    if not len then return nil, "bad_length" end
    if n == 2 and (len < 4 or len > 6) then return nil, "bad_length" end
    if n == 3 and (len < 3 or len > 6) then return nil, "bad_length" end
    if n >= 4 and (len < 4 or len > 6) then return nil, "bad_length" end
    for _, item in ipairs(items or {}) do
        if not item.parts then return nil, "missing_parts" end
    end
    return code_at(items, n):sub(1, len)
end

function M.word_from_items(items)
    local parts = {}
    for i, item in ipairs(items or {}) do parts[i] = item.text end
    return table.concat(parts)
end

function M.serialize_items(items)
    local rows = {}
    for _, item in ipairs(items or {}) do
        local parts = item.parts or {}
        rows[#rows + 1] = table.concat({
            item.text or "",
            parts.s or "",
            parts.y or "",
            parts.p or "",
            parts.code or "",
        }, "\t")
    end
    return table.concat(rows, "\n")
end

function M.deserialize_items(text)
    local items = {}
    for line in tostring(text or ""):gmatch("[^\n]+") do
        local ch, s, y, p, code = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if ch and ch ~= "" then
            local parts = nil
            if s ~= "" and y ~= "" and p ~= "" then
                parts = { s = s, y = y, p = p, code = code ~= "" and code or (s .. y .. p) }
            end
            items[#items + 1] = { text = ch, parts = parts }
        end
    end
    return items
end

local function ops_file()
    return path("txjx.zzc.dict.yaml")
end

local function pending_file()
    return ops_file()
end

local function runtime_exact_file()
    return path("zzc/runtime_exact.tsv")
end

local function new_tx()
    return os.date("%Y%m%d%H%M%S") .. string.format("%03d", math.floor((os.clock() * 1000) % 1000))
end

local function pending_record_from_line(line)
    local yaml_line = line
    if yaml_line:match("^%s*#") or yaml_line:match("^%s*$") or yaml_line:match("^%s*%.%.%.%s*$") or yaml_line:match("^%s*%-%-%-%s*$") then
        return nil
    elseif yaml_line:match("^%s*[%w_]+:") or yaml_line:match("^%s*%- ") then
        return nil
    end
    local word, code, mark, tx = yaml_line:match("^([^\t#]+)\t([^%s#]+)%s*#%s*([+%-!%^])%s+(%d+)%s*$")
    if word and code and mark then
        return { mark = mark, word = word, code = code, tx = tx }
    end
    word, code, mark = yaml_line:match("^([^\t#]+)\t([^%s#]+)%s*#%s*([+%-!%^])%s*$")
    if word and code and mark then
        return { mark = mark, word = word, code = code }
    end
    local mark, word, code = line:match("^([+%-!%^])\t([^\t]+)\t([^\t%s]+)$")
    if not mark or not word or not code then return nil end
    return { mark = mark, word = word, code = code }
end

local function pending_line_from_record(record)
    local mark = record.mark or "+"
    local tx = record.tx or new_tx()
    return table.concat({ record.word or "", (record.code or "") .. " #" .. mark .. " " .. tx }, "\t")
end

local function ops_header()
    return table.concat({
        "# Rime dictionary",
        "# encoding: utf-8",
        "---",
        "name: txjx.zzc",
        "version: \"2026-06-20\"",
        "sort: by_weight",
        "use_preset_vocabulary: false",
        "columns:",
        "  - text",
        "  - code",
        "..."
    }, "\n") .. "\n"
end

local function ensure_ops_file()
    local f = io.open(pending_file(), "r")
    if f then
        f:close()
        return
    end
    f = io.open(pending_file(), "w")
    if not f then return end
    f:write(ops_header())
    f:close()
end

local function update_runtime_exact_cache(record)
    if not record or not record.code or record.code == "" or not record.word or record.word == "" then return end
    for code, bucket in pairs(runtime_exact_cache) do
        local fresh_bucket = {}
        for _, row in ipairs(bucket) do
            if row.word ~= record.word then
                fresh_bucket[#fresh_bucket + 1] = row
            end
        end
        runtime_exact_cache[code] = fresh_bucket[1] and fresh_bucket or nil
    end
    if record.mark == "!" then return end
    local bucket = runtime_exact_cache[record.code]
    if not bucket then
        bucket = {}
        runtime_exact_cache[record.code] = bucket
    end
    table.insert(bucket, 1, { word = record.word, code = record.code, source = "runtime" })
end

local function load_runtime_exact_cache_record(record)
    if not record or not record.code or record.code == "" or not record.word or record.word == "" then return end
    for code, bucket in pairs(runtime_exact_cache) do
        local fresh_bucket = {}
        for _, row in ipairs(bucket) do
            if row.word ~= record.word then
                fresh_bucket[#fresh_bucket + 1] = row
            end
        end
        runtime_exact_cache[code] = fresh_bucket[1] and fresh_bucket or nil
    end
    if record.mark == "!" then return end
    local bucket = runtime_exact_cache[record.code]
    if not bucket then
        bucket = {}
        runtime_exact_cache[record.code] = bucket
    end
    bucket[#bucket + 1] = { word = record.word, code = record.code, source = "runtime" }
end

local function append_runtime_exact_file(record)
    local f = io.open(runtime_exact_file(), "a")
    if not f then
        return
    end
    f:write(record.word or "", "\t", record.code or "", "\n")
    f:close()
end

local function load_runtime_exact_cache()
    if runtime_exact_loaded then return runtime_exact_cache end
    runtime_exact_cache = {}
    local f = io.open(runtime_exact_file(), "r")
    if f then
        for line in f:lines() do
            local word, code = line:match("^([^\t]+)\t([^\t%s]+)$")
            if word and code then
                load_runtime_exact_cache_record({ word = word, code = code })
            end
        end
        f:close()
    end
    runtime_exact_loaded = true
    return runtime_exact_cache
end

local function update_session_exact_cache(record)
    if not record or not record.code or record.code == "" or not record.word or record.word == "" then return end
    for code, bucket in pairs(session_exact_cache) do
        local fresh_bucket = {}
        for _, row in ipairs(bucket) do
            if row.word ~= record.word then
                fresh_bucket[#fresh_bucket + 1] = row
            end
        end
        session_exact_cache[code] = fresh_bucket[1] and fresh_bucket or nil
    end
    if record.mark == "!" then return end
    local bucket = session_exact_cache[record.code]
    if not bucket then
        bucket = {}
        session_exact_cache[record.code] = bucket
    end
    table.insert(bucket, 1, { word = record.word, code = record.code, source = "session" })
end

local function load_pending_cache()
    if pending_loaded then return pending_cache end
    pending_cache = {}
    for _, file_path in ipairs({ ops_file() }) do
        local f = io.open(file_path, "r")
        if f then
            for line in f:lines() do
                local record = pending_record_from_line(line)
                if record and record.code and record.word then
                    pending_cache[#pending_cache + 1] = record
                end
            end
            f:close()
        end
    end
    pending_loaded = true
    return pending_cache
end

local function reload_pending_cache()
    pending_loaded = false
    pending_cache = {}
    return load_pending_cache()
end

local function append_pending_cache(record)
    if not pending_loaded then return end
    pending_cache[#pending_cache + 1] = {
        mark = record.mark or "+",
        word = record.word,
        code = record.code,
        tx = record.tx,
    }
end

local function reset_runtime_exact_cache()
    session_exact_cache = {}
    runtime_exact_cache = {}
    runtime_exact_loaded = true
end

local function rebuild_runtime_from_records(records)
    reset_runtime_exact_cache()
    for _, record in ipairs(records or {}) do
        if record.mark == "+" or record.mark == "-" then
            update_session_exact_cache(record)
            update_runtime_exact_cache(record)
        elseif record.mark == "!" then
            update_session_exact_cache(record)
            update_runtime_exact_cache(record)
        end
    end
    local f = io.open(runtime_exact_file(), "w")
    if not f then
        return nil, "runtime_open_failed"
    end
    for _, bucket in pairs(runtime_exact_cache) do
        for _, record in ipairs(bucket) do
            f:write(record.word or "", "\t", record.code or "", "\n")
        end
    end
    f:close()
    return true
end

local function rewrite_ops_records(records)
    local lines = {}
    local header = ops_header()
    for line in header:gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    for _, record in ipairs(records or {}) do
        lines[#lines + 1] = pending_line_from_record(record)
    end
    local ok, err = write_file_atomic(pending_file(), lines)
    if not ok then return nil, err end
    pending_cache = records or {}
    pending_loaded = true
    return rebuild_runtime_from_records(pending_cache)
end

local function append_ops_record(record)
    ensure_ops_file()
    local f = io.open(pending_file(), "a")
    if not f then return nil, "ops_open_failed" end
    f:write(pending_line_from_record(record), "\n")
    f:close()
    append_pending_cache(record)
    return true
end

local function append_ops_records(records)
    ensure_ops_file()
    local f = io.open(pending_file(), "a")
    if not f then return nil, "ops_open_failed" end
    local tx = new_tx()
    for _, record in ipairs(records or {}) do
        record.tx = record.tx or tx
        f:write(pending_line_from_record(record), "\n")
    end
    f:close()
    for _, record in ipairs(records or {}) do
        append_pending_cache(record)
    end
    return true
end

local function append_runtime_records(records)
    local runtime_rows = {}
    for _, record in ipairs(records or {}) do
        update_session_exact_cache(record)
        update_runtime_exact_cache(record)
        runtime_rows[#runtime_rows + 1] = record
    end
    if not runtime_rows[1] then return end
    local f = io.open(runtime_exact_file(), "a")
    if not f then
        return
    end
    for _, record in ipairs(runtime_rows) do
        f:write(record.word or "", "\t", record.code or "", "\n")
    end
    f:close()
end

local function word_valid_at_code(pending, word, code)
    if not word or word == "" or not code or code == "" then return false end
    for i = #(pending or {}), 1, -1 do
        local record = pending[i]
        if record.word == word and record.code == code and record.mark ~= "^" then
            return record.mark ~= "!"
        end
    end
    return true
end

local function hidden_words_for_code(pending, code)
    local hide_words, seen_words = {}, {}
    if not code or code == "" then return hide_words end
    for i = #(pending or {}), 1, -1 do
        local record = pending[i]
        if record.code == code and record.word and record.word ~= "" and not seen_words[record.word] and record.mark ~= "^" then
            if record.mark == "!" then hide_words[record.word] = true end
            seen_words[record.word] = true
        end
    end
    return hide_words
end

local function enqueue_snapshot(snapshot)
    local first_code, first_word
    local runtime_records = {}
    local ok, err = append_ops_records(snapshot or {})
    if not ok then return nil, err end
    for _, record in ipairs(snapshot or {}) do
        if record.mark == "+" or record.mark == "-" then
            runtime_records[#runtime_records + 1] = record
            if not first_code and record.mark == "+" then
                first_code = record.code
                first_word = record.word
            end
        end
    end
    append_runtime_records(runtime_records)
    return first_code, first_word
end

function M.enqueue_pending(items, len, probe_first)
    local code, err = M.code_for_items(items, len)
    if not code then return nil, err end
    return M.save_word(items, len, probe_first)
end

function M.enqueue_replace(items, target_code, replaced_word, probe_first)
    if not target_code or target_code == "" then return nil, "missing_target_code" end
    return M.save_word_at_code(items, target_code, replaced_word, probe_first)
end

function M.move_word_to_code(word, source_code, target_code, probe_first, replaced_word)
    if not word or word == "" then return nil, "missing_word" end
    if not source_code or source_code == "" then return nil, "missing_source_code" end
    if not target_code or target_code == "" then return nil, "missing_target_code" end
    local snapshot = build_replace_snapshot(word, target_code, replaced_word, probe_first)
    snapshot[#snapshot + 1] = { mark = "!", word = word, code = source_code }
    local saved_code, saved_word = enqueue_snapshot(snapshot)
    return saved_code, saved_word
end

function M.undo_last_tx()
    local records = load_pending_cache()
    local last_tx
    for i = #records, 1, -1 do
        if records[i].tx and records[i].tx ~= "" then
            last_tx = records[i].tx
            break
        end
    end
    if not last_tx then return nil, "missing_tx" end
    local kept = {}
    for _, record in ipairs(records) do
        if record.tx ~= last_tx then kept[#kept + 1] = record end
    end
    local ok, err = rewrite_ops_records(kept)
    if not ok then return nil, err end
    return true, last_tx
end

function M.delete_word_at_code(word, code)
    if not word or word == "" then return nil, "missing_word" end
    if not code or code == "" then return nil, "missing_code" end
    local record = { mark = "!", word = word, code = code, tx = new_tx() }
    local ok, err = append_ops_record(record)
    if not ok then return nil, err end
    local records = load_pending_cache()
    rebuild_runtime_from_records(records)
    return true, record.tx
end

function M.reorder_words_at_code(words, code)
    if not words or not words[1] then return nil, "missing_words" end
    if not code or code == "" then return nil, "missing_code" end
    local tx = new_tx()
    local records = {}
    local seen = {}
    local pending = reload_pending_cache()
    for _, word in ipairs(words or {}) do
        if word and word ~= "" and not seen[word] and word_valid_at_code(pending, word, code) then
            seen[word] = true
            records[#records + 1] = { mark = "^", word = word, code = code, tx = tx }
        end
    end
    if not records[1] then return nil, "missing_words" end
    local ok, err = append_ops_records(records)
    if not ok then return nil, err end
    return true, tx
end

function M.buffer_word()
    return M.word_from_items(M.state_items or {})
end

function M.set_state_items(items)
    M.state_items = items
end

function M.set_current_stage(stage)
    M._current_stage = stage
end

function M.current_stage()
    return M._current_stage or "off"
end

write_file_atomic = function(file_path, lines)
    local tmp = file_path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then
        return nil, "open_failed:" .. file_path
    end
    for _, line in ipairs(lines) do f:write(line, "\n") end
    f:close()
    local removed = os.remove(file_path)
    local renamed = os.rename(tmp, file_path)
    if not renamed then
        os.remove(tmp)
        return nil, "rename_failed:" .. file_path
    end
    return true
end

local function append_next_code(word, code)
    if #code >= 6 then return nil, "max_code" end
    local chars = utf8_chars(word)
    local n = #chars
    local len = #code
    local target_index
    local hint = {}
    if n == 2 then
        if len == 4 then
            target_index = 1
            hint = { s = code:sub(1, 1), y = code:sub(2, 2) }
        elseif len == 5 then
            target_index = 2
            hint = { s = code:sub(3, 3), y = code:sub(4, 4) }
        end
    elseif n == 3 then
        if len >= 3 and len <= 5 then
            target_index = len - 2
            hint = { s = code:sub(target_index, target_index) }
        end
    elseif n >= 4 then
        if len == 4 then
            target_index = 1
            hint = { s = code:sub(1, 1) }
        elseif len == 5 then
            target_index = 2
            hint = { s = code:sub(2, 2) }
        end
    end
    if not target_index or not chars[target_index] then return nil, "no_longer_code" end
    local options = M.load_char_parts(chars[target_index])[chars[target_index]]
    if not options or not options[1] then return nil, "missing_char:" .. tostring(chars[target_index]) end
    local p
    for _, entry in ipairs(options) do
        if hint_matches(entry, hint) then
            if not p then p = entry.p elseif p ~= entry.p then return nil, "ambiguous_char:" .. tostring(chars[target_index]) end
        end
    end
    if not p then return nil, "missing_char:" .. tostring(chars[target_index]) end
    return code .. p
end

local function build_direct_snapshot(word, code)
    return { { mark = "+", word = word, code = code } }
end

build_replace_snapshot = function(word, code, replaced_word, probe_first)
    local snapshot = build_direct_snapshot(word, code)
    if (not replaced_word or replaced_word == "") and probe_first then
        local ok, probed = pcall(function() return probe_first(code) end)
        if ok and probed and probed ~= "" then replaced_word = probed end
    end
    local displaced_word = replaced_word
    local displaced_code = code
    local visiting = {}
    while displaced_word and displaced_word ~= "" and displaced_word ~= word and not visiting[displaced_word] do
        visiting[displaced_word] = true
        local next_code = append_next_code(displaced_word, displaced_code)
        if next_code then
            snapshot[#snapshot + 1] = { mark = "-", word = displaced_word, code = next_code }
            snapshot[#snapshot + 1] = { mark = "!", word = displaced_word, code = displaced_code }
            if #next_code >= 6 then break end
            local next_word = nil
            if probe_first then
                local ok, probed = pcall(function() return probe_first(next_code) end)
                if ok and probed and probed ~= "" then next_word = probed end
            end
            if not next_word or next_word == displaced_word or next_word == word then break end
            displaced_word = next_word
            displaced_code = next_code
        else
            break
        end
    end
    return snapshot
end

function M.pending_candidates_for_input(input)
    local session_rows = session_exact_cache[input]
    if session_rows and session_rows[1] then
        return { rows = session_rows, exact_rows = session_rows, has_exact = true }
    end
    local runtime_exact_rows = load_runtime_exact_cache()[input]
    if runtime_exact_rows and runtime_exact_rows[1] then
        return { rows = runtime_exact_rows, exact_rows = runtime_exact_rows, has_exact = true }
    end
    return nil
end

local function save_word_to_code(items, code, replaced_word, probe_first)
    local word = M.word_from_items(items)
    if not code then
        return nil, "missing_code"
    end
    local snapshot = build_replace_snapshot(word, code, replaced_word, probe_first)
    local saved_code, err = enqueue_snapshot(snapshot)
    if not saved_code then
        return nil, err
    end
    return code, word
end

function M.save_word(items, len, probe_first)
    local code, err = M.code_for_items(items, len)
    if not code then
        return nil, err
    end
    return save_word_to_code(items, code, nil, probe_first)
end

function M.save_word_at_code(items, code, replaced_word, probe_first)
    return save_word_to_code(items, code, replaced_word, probe_first)
end

function M.zzc_cover_for_input(input, opts)
    if not input or input == "" then return nil end
    opts = opts or {}
    local keep_rows, keep_words, hide_words, seen_words = {}, {}, {}, {}
    local pending = load_pending_cache()
    local latest_order_tx = nil
    if not opts.ignore_order then
        for i = #pending, 1, -1 do
            local record = pending[i]
            if record.code == input and record.mark == "^" and record.tx and record.tx ~= "" then
                latest_order_tx = record.tx
                break
            end
        end
    end
    if latest_order_tx then
        local order_rows = {}
        hide_words = hidden_words_for_code(pending, input)
        for _, record in ipairs(pending) do
            if record.code == input and record.mark == "^" and record.tx == latest_order_tx and not seen_words[record.word] and word_valid_at_code(pending, record.word, input) then
                order_rows[#order_rows + 1] = { word = record.word, code = record.code, source = "zzc_order" }
                keep_words[record.word] = true
                seen_words[record.word] = true
            end
        end
        if order_rows[1] then
            return { rows = order_rows, keep_words = keep_words, hide_words = hide_words, has_order = true }
        end
    end
    for i = #pending, 1, -1 do
        local record = pending[i]
        if record.code == input then
            if not seen_words[record.word] and (record.mark == "+" or record.mark == "-") then
                keep_rows[#keep_rows + 1] = { word = record.word, code = record.code, source = "zzc" }
                keep_words[record.word] = true
                seen_words[record.word] = true
            elseif not seen_words[record.word] and record.mark == "!" then
                hide_words[record.word] = true
                seen_words[record.word] = true
            end
        end
    end
    if not keep_rows[1] then
        for _ in pairs(hide_words) do
            return { rows = keep_rows, keep_words = keep_words, hide_words = hide_words, has_delete_cover = true }
        end
        return nil
    end
    return { rows = keep_rows, keep_words = keep_words, hide_words = hide_words, has_exact_cover = true }
end

function M.zzc_order_for_input(input)
    if not input or input == "" then return nil end
    local pending = reload_pending_cache()
    local latest_order_tx = nil
    for i = #pending, 1, -1 do
        local record = pending[i]
        if record.code == input and record.mark == "^" and record.tx and record.tx ~= "" then
            latest_order_tx = record.tx
            break
        end
    end
    if not latest_order_tx then return nil end
    local rows, keep_words, seen_words = {}, {}, {}
    local hide_words = hidden_words_for_code(pending, input)
    for _, record in ipairs(pending) do
        if record.code == input and record.mark == "^" and record.tx == latest_order_tx and not seen_words[record.word] and word_valid_at_code(pending, record.word, input) then
            rows[#rows + 1] = { word = record.word, code = record.code, source = "zzc_order" }
            keep_words[record.word] = true
            seen_words[record.word] = true
        end
    end
    if not rows[1] then return nil end
    return { rows = rows, keep_words = keep_words, hide_words = hide_words, has_order = true }
end

function M.cover_for_probe(input, opts)
    local pending = M.pending_candidates_for_input(input)
    if pending and pending.rows and pending.rows[1] then return pending end
    return M.zzc_cover_for_input(input, opts)
end

function M.candidates_for_input(input)
    local out, words, codes, exact_rows = {}, {}, {}, {}
    local pending = M.pending_candidates_for_input(input)
    if pending and pending.rows then
        for _, row in ipairs(pending.rows) do
            out[#out + 1] = { word = row.word, code = row.code, source = row.source or "pending" }
            words[row.word] = true
            codes[row.code] = true
        end
        if pending.has_exact then
            for _, row in ipairs(pending.exact_rows) do
                exact_rows[#exact_rows + 1] = { word = row.word, code = row.code, source = row.source or "pending" }
            end
        end
    end
    if not out[1] then return nil end
    return { prefix = nil, rows = out, words = words, codes = codes, exact_rows = exact_rows, has_exact = #exact_rows > 0 }
end

return M
