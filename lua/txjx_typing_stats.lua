-- 天行键独立打字统计
-- 统计数据按方案分文件保存；=tj 显示今日、近 7 天和累计。

local registry = require("common.txjx_cache_registry")

local M = {}

local kNoop = 2
local STATS_FILE_SUFFIX = "_typing_stats.tsv"
local MAX_DAYS = 730
local FLUSH_EVERY = 20
local FLUSH_IDLE = 60
local XK_BACKSPACE = 0xff08
local IDLE_GAP = 5
local MIN_SPEED_SECS = 30

local function schema_id(env)
    local schema = env and env.engine and env.engine.schema
    local id = schema and schema.schema_id or ""
    if type(id) ~= "string" or id == "" then return "txjx" end
    return id:gsub("[^%w%._%-]", "_")
end

local function user_data_dir()
    local api = rime_api
    if not api or not api.get_user_data_dir then return nil end
    local ok, path = pcall(api.get_user_data_dir)
    if ok and type(path) == "string" and path ~= "" then return path end
    return nil
end

local function new_state(env)
    local base = user_data_dir()
    return {
        loaded = false,
        history = nil,
        today = nil,
        dirty = 0,
        last_flush = 0,
        last_key_time = nil,
        path = base and (base .. "/zzc_state/" .. schema_id(env) .. STATS_FILE_SUFFIX) or nil,
    }
end

local function state(env)
    _G.__txjx_typing_stats = _G.__txjx_typing_stats or {}
    local key = schema_id(env)
    local st = _G.__txjx_typing_stats[key]
    if not st then
        st = new_state(env)
        _G.__txjx_typing_stats[key] = st
    end
    return st
end

local function today_str()
    return os.date("%Y-%m-%d")
end

local function new_row(day)
    return {
        day = day,
        chars = 0,
        keys = 0,
        commits = 0,
        backspaces = 0,
        active_secs = 0,
        timed_chars = 0,
    }
end

local function load(st)
    if st.loaded then return end
    st.history = {}
    st.today = nil
    local today = today_str()
    local f = st.path and io.open(st.path, "r") or nil
    if f then
        for line in f:lines() do
            local day, chars, keys, commits, backspaces, _, active_secs, timed_chars =
                line:match("^(%d%d%d%d%-%d%d%-%d%d)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t?(%d*)\t?(%d*)")
            if day then
                local timed = tonumber(timed_chars)
                local row = {
                    day = day,
                    chars = tonumber(chars) or 0,
                    keys = tonumber(keys) or 0,
                    commits = tonumber(commits) or 0,
                    backspaces = tonumber(backspaces) or 0,
                    active_secs = timed and (tonumber(active_secs) or 0) or 0,
                    timed_chars = timed or 0,
                }
                if day == today then
                    st.today = row
                else
                    st.history[#st.history + 1] = row
                end
            end
        end
        f:close()
    end
    st.today = st.today or new_row(today)
    st.loaded = true
end

local function flush(st)
    if not st.loaded or not st.path then return false end
    while #st.history >= MAX_DAYS do
        table.remove(st.history, 1)
    end
    local f = io.open(st.path, "w")
    if not f then return false end
    local function write_row(row)
        f:write(
            row.day, "\t", row.chars, "\t", row.keys, "\t", row.commits, "\t",
            row.backspaces, "\t0\t", row.active_secs or 0, "\t", row.timed_chars or 0, "\n"
        )
    end
    for _, row in ipairs(st.history) do write_row(row) end
    write_row(st.today)
    f:close()
    st.dirty = 0
    st.last_flush = os.time()
    return true
end

local function roll_day(st)
    local today = today_str()
    if st.today.day ~= today then
        st.history[#st.history + 1] = st.today
        st.today = new_row(today)
        flush(st)
    end
end

local function release_state(st)
    flush(st)
    st.loaded = false
    st.history = nil
    st.today = nil
    st.dirty = 0
    st.last_key_time = nil
end

local function count_han(text)
    local count = 0
    local ok = pcall(function()
        for _, cp in utf8.codes(text) do
            if (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF) then
                count = count + 1
            end
        end
    end)
    return ok and count or 0
end

local function is_ascii_mode(env)
    local ctx = env and env.engine and env.engine.context
    if not ctx or not ctx.get_option then return false end
    local ok, value = pcall(ctx.get_option, ctx, "ascii_mode")
    return ok and value == true
end

function M.processor(key, env)
    if not key or key:release() or key:ctrl() or key:alt() or key:super() then
        return kNoop
    end
    if is_ascii_mode(env) then return kNoop end

    local code = tonumber(key.keycode or 0) or 0
    local is_backspace = code == XK_BACKSPACE
    if not is_backspace and (code < 0x20 or code >= 0x7f) then return kNoop end

    local st = state(env)
    load(st)
    roll_day(st)

    local now = os.time()
    local gap = st.last_key_time and (now - st.last_key_time) or -1
    if gap >= 0 and gap <= IDLE_GAP then
        st.today.active_secs = st.today.active_secs + gap
    else
        st.today.active_secs = st.today.active_secs + 1
    end
    st.last_key_time = now

    if is_backspace then
        st.today.backspaces = st.today.backspaces + 1
    else
        st.today.keys = st.today.keys + 1
    end
    return kNoop
end

function M.on_commit(ctx, env)
    local st = state(env)
    if not st.loaded then return end
    local text = ""
    local ok, value = pcall(ctx.get_commit_text, ctx)
    if ok then text = tostring(value or "") end
    if text == "" then return end

    roll_day(st)
    local han = count_han(text)
    st.today.commits = st.today.commits + 1
    st.today.chars = st.today.chars + han
    st.today.timed_chars = st.today.timed_chars + han
    st.dirty = st.dirty + 1
    if st.dirty >= FLUSH_EVERY or os.time() - (st.last_flush or 0) >= FLUSH_IDLE then
        flush(st)
    end
end

function M.init_processor(env)
    local ctx = env and env.engine and env.engine.context
    if ctx and ctx.commit_notifier then
        env.commit_connection = ctx.commit_notifier:connect(function(commit_ctx)
            pcall(M.on_commit, commit_ctx, env)
        end)
    end
    registry.register("typing_stats", function()
        local all = _G.__txjx_typing_stats or {}
        for _, st in pairs(all) do release_state(st) end
        return true
    end)
end

function M.fini_processor(env)
    if env and env.commit_connection then
        pcall(function() env.commit_connection:disconnect() end)
        env.commit_connection = nil
    end
    release_state(state(env))
end

local function sum_rows(rows, from_day)
    local acc = new_row("")
    for _, row in ipairs(rows) do
        if not from_day or row.day >= from_day then
            acc.chars = acc.chars + row.chars
            acc.keys = acc.keys + row.keys
            acc.commits = acc.commits + row.commits
            acc.backspaces = acc.backspaces + row.backspaces
            acc.active_secs = acc.active_secs + (row.active_secs or 0)
            acc.timed_chars = acc.timed_chars + (row.timed_chars or 0)
        end
    end
    return acc
end

local function code_len(row)
    if row.chars == 0 then return "-" end
    return string.format("%.2f", row.keys / row.chars)
end

local function speed_str(row)
    local secs = row.active_secs or 0
    local timed = row.timed_chars or 0
    if secs < MIN_SPEED_SECS or timed == 0 then return "-" end
    local text = string.format("约%d字/分", math.floor(timed / secs * 60 + 0.5))
    if timed < row.chars then text = text .. "（可能不准）" end
    return text
end

function M.translator(input, seg, env)
    if input ~= "=tj" then return end
    local st = state(env)
    load(st)
    roll_day(st)

    local all = {}
    for _, row in ipairs(st.history) do all[#all + 1] = row end
    all[#all + 1] = st.today
    local week_from = os.date("%Y-%m-%d", os.time() - 6 * 86400)
    local rows = {
        { "今日", st.today },
        { "近7天", sum_rows(all, week_from) },
        { "累计", sum_rows(all) },
    }
    local first_day = st.history[1] and st.history[1].day or st.today.day
    for index, item in ipairs(rows) do
        local label, row = item[1], item[2]
        local text = string.format("%s %d 字 · 码长 %s", label, row.chars, code_len(row))
        local comment = string.format(
            "击键 %d · 上屏 %d · 退格 %d · 速度 %s",
            row.keys, row.commits, row.backspaces, speed_str(row)
        )
        if label == "累计" then comment = comment .. " · 自 " .. first_day end
        local cand = Candidate("stats", seg.start, seg._end, text, comment)
        cand.quality = 600000 - index
        yield(cand)
    end
end

return M
