-- 天行键 自造词编码链规划模块
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-07-19

local M = {}
local codec = require("zzc.txjx_zzc_codec")

M.shape_keys = { "a", "i", "o", "u", "v" }

local function utf8_length(text)
    local ok, length = pcall(function()
        local count = 0
        for _, codepoint in utf8.codes(text or "") do
            local ch = utf8.char(codepoint)
            if not codec.is_literal_punctuation(ch) then count = count + 1 end
        end
        return count
    end)
    return ok and length or nil
end

function M.word_min_code_length(word)
    local length = utf8_length(word)
    if length == 3 then return 3 end
    if length and length >= 2 then return 4 end
    return nil
end

local function visible_words(probe_exact, code, removed, added)
    if type(probe_exact) ~= "function" then return {} end
    local ok, probed, err = pcall(function() return probe_exact(code) end)
    if not ok then return nil, "probe_failed" end
    if probed == nil then return nil, err or "probe_failed" end
    local out, seen = {}, {}
    for _, word in ipairs(added[code] or {}) do
        if word and word ~= "" and not seen[word] then
            out[#out + 1] = word
            seen[word] = true
        end
    end
    for _, word in ipairs(probed or {}) do
        if word and word ~= "" and not seen[word]
            and not (removed[code] and removed[code][word]) then
            out[#out + 1] = word
            seen[word] = true
        end
    end
    return out
end

local function mark_removed(removed, code, word)
    removed[code] = removed[code] or {}
    removed[code][word] = true
end

local function mark_added(added, code, word)
    added[code] = added[code] or {}
    table.insert(added[code], 1, word)
end

local function compact_gap(records, initial_gap, probe_exact, removed, added)
    local warning
    local gap = initial_gap
    local visited = {}
    while #gap < 6 and not visited[gap] do
        visited[gap] = true
        local selected_word, source_code, source_words
        local probe_failed = false
        for _, shape in ipairs(M.shape_keys) do
            local child = gap .. shape
            local candidates, probe_err = visible_words(probe_exact, child, removed, added)
            if not candidates then
                warning = warning or probe_err
                probe_failed = true
                break
            end
            for _, word in ipairs(candidates) do
                local minimum = M.word_min_code_length(word)
                if minimum and #gap >= minimum then
                    selected_word = word
                    source_code = child
                    source_words = candidates
                    break
                end
            end
            if selected_word then break end
        end
        if probe_failed or not selected_word then break end

        mark_added(added, gap, selected_word)
        mark_removed(removed, source_code, selected_word)
        records[#records + 1] = {
            op = "move", mark = "-", word = selected_word, code = gap,
        }
        records[#records + 1] = {
            op = "delete", mark = "!", word = selected_word, code = source_code,
        }

        local source_has_remaining = false
        for _, word in ipairs(source_words or {}) do
            if word ~= selected_word
                and not (removed[source_code] and removed[source_code][word]) then
                source_has_remaining = true
                break
            end
        end
        if source_has_remaining then break end
        gap = source_code
    end
    return warning
end

function M.plan_delete(words, code, probe_exact)
    if not words or not words[1] then return nil, "missing_words" end
    if not code or code == "" then return nil, "missing_code" end
    if type(probe_exact) ~= "function" then return nil, "missing_probe" end

    local records, removed, added, seen_words = {}, {}, {}, {}
    for _, word in ipairs(words) do
        if word and word ~= "" and not seen_words[word] then
            seen_words[word] = true
            mark_removed(removed, code, word)
            records[#records + 1] = {
                op = "delete", mark = "!", word = word, code = code,
            }
        end
    end
    if not records[1] then return nil, "missing_words" end

    local warning
    local remaining, err = visible_words(probe_exact, code, removed, added)
    if not remaining then return records, err end
    if remaining[1] then return records end

    local delete_count = #records
    warning = compact_gap(records, code, probe_exact, removed, added)
    if warning then
        while #records > delete_count do table.remove(records) end
    end
    return records, warning
end

local function words_contain(words, word)
    for _, current in ipairs(words or {}) do
        if current == word then return true end
    end
    return false
end

local function append_delete_once(records, word, code)
    for _, record in ipairs(records) do
        if record.mark == "!" and record.word == word and record.code == code then return end
    end
    records[#records + 1] = {
        op = "delete", mark = "!", word = word, code = code,
    }
end

local function remove_source_duplicates(
    records, word, source_codes, probe_words, removed, added)
    local deleted_sources = {}
    for _, source_code in ipairs(source_codes or {}) do
        local source_words, probe_err = visible_words(
            probe_words, source_code, removed, added)
        if probe_words and not source_words then return nil, probe_err end
        if words_contain(source_words, word) then
            append_delete_once(records, word, source_code)
            mark_removed(removed, source_code, word)
            deleted_sources[#deleted_sources + 1] = source_code
        end
    end
    for _, source_code in ipairs(deleted_sources) do
        local remaining, probe_err = visible_words(
            probe_words, source_code, removed, added)
        if probe_words and not remaining then return nil, probe_err end
        if not remaining[1] then
            local warning = compact_gap(
                records, source_code, probe_words, removed, added)
            if warning then return nil, warning end
        end
    end
    return true
end

function M.plan_append(opts)
    opts = opts or {}
    local word = opts.word
    local code = opts.code
    if not word or word == "" then return nil, "missing_word" end
    if not code or code == "" then return nil, "missing_code" end
    if (opts.source_codes or {})[1]
        and type(opts.probe_words) ~= "function" then return nil, "missing_probe" end

    local records = {
        { op = "append", mark = "+", append = true, word = word, code = code },
    }
    local removed, added = {}, {}
    mark_added(added, code, word)
    local ok, err = remove_source_duplicates(
        records, word, opts.source_codes, opts.probe_words, removed, added)
    if not ok then return nil, err end
    return records
end

function M.plan_replace(opts)
    opts = opts or {}
    local word = opts.word
    local code = opts.code
    if not word or word == "" then return nil, "missing_word" end
    if not code or code == "" then return nil, "missing_code" end
    if type(opts.next_code) ~= "function" then return nil, "missing_next_code" end

    local records = {
        { op = opts.op or "make", mark = "+", word = word, code = code },
    }
    local removed, added = {}, {}
    local replaced_word = opts.replaced_word
    if (not replaced_word or replaced_word == "") and opts.probe_first then
        local ok, probed = pcall(function() return opts.probe_first(code) end)
        if ok and probed and probed ~= "" then replaced_word = probed end
    end

    local displaced_word = replaced_word
    local displaced_code = code
    local visiting = {}
    while displaced_word and displaced_word ~= ""
        and displaced_word ~= word and not visiting[displaced_word] do
        visiting[displaced_word] = true
        local next_code = opts.next_code(displaced_word, displaced_code)
        if not next_code then break end
        local next_words, probe_err = visible_words(
            opts.probe_words, next_code, removed, added)
        if opts.probe_words and not next_words then return nil, probe_err end
        records[#records + 1] = {
            op = "move", mark = "-", word = displaced_word, code = next_code,
        }
        append_delete_once(records, displaced_word, displaced_code)
        mark_added(added, next_code, displaced_word)
        mark_removed(removed, displaced_code, displaced_word)
        local next_word = next_words and next_words[1] or nil
        if words_contain(next_words, word) then
            append_delete_once(records, word, next_code)
            mark_removed(removed, next_code, word)
        end
        if not next_word and opts.probe_first then
            local ok, probed = pcall(function() return opts.probe_first(next_code) end)
            if ok and probed and probed ~= "" then next_word = probed end
        end
        if #next_code >= 6 then break end
        if not next_word or next_word == displaced_word or next_word == word then break end
        displaced_word = next_word
        displaced_code = next_code
    end

    mark_added(added, code, word)
    local ok, err = remove_source_duplicates(
        records, word, opts.source_codes, opts.probe_words, removed, added)
    if not ok then return nil, err end
    return records
end

return M
