-- 万能符反查读音补全
-- 只在 reverse_lookup 模式下运行，把 txjx.cx.dict.yaml 中的单字读音拼入注释。
-- 作者：@浮生 https://github.com/wzxmer/rime-txjx
-- 更新：2026-04-29

local M = {}

local pron_cache

local function open_user_file(name)
    local sep = (package.config or "/"):sub(1, 1)
    local base = rime_api and rime_api.get_user_data_dir and rime_api.get_user_data_dir()
    if base and base ~= "" then
        local f = io.open(base .. sep .. name, "r")
        if f then
            return f
        end
    end
    return io.open(name, "r")
end

local function load_pron()
    if pron_cache then
        return pron_cache
    end

    local cache = {}
    local f = open_user_file("txjx.cx.dict.yaml")
    if not f then
        pron_cache = cache
        return cache
    end

    for line in f:lines() do
        local text, pron = line:match("^([^\t]+)\t%(([^%)]+)%)")
        if text and pron and utf8.len(text) == 1 then
            cache[text] = pron
        end
    end
    f:close()

    pron_cache = cache
    return cache
end

local function is_reverse_lookup(env)
    local ctx = env.engine.context
    local seg = ctx and ctx.composition and ctx.composition:back()
    if not seg then
        return false
    end
    if seg.has_tag and seg:has_tag("reverse_lookup") then
        return true
    end
    return seg.tag == "reverse_lookup"
end

local function merge_comment(pron, comment)
    comment = comment or ""
    if comment:find(" | ", 1, true) then
        return comment
    end
    if comment:match("^%[.*%]$") then
        return "[" .. pron .. " | " .. comment:sub(2, -2) .. "]"
    end
    if comment ~= "" then
        return "[" .. pron .. " | " .. comment .. "]"
    end
    return "[" .. pron .. "]"
end

function M.func(input, env)
    if not is_reverse_lookup(env) then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    local pron = load_pron()
    for cand in input:iter() do
        if cand.text and utf8.len(cand.text) == 1 then
            local p = pron[cand.text]
            if p then
                cand:get_genuine().comment = merge_comment(p, cand.comment)
            end
        end
        yield(cand)
    end
end

function M.fini(env)
end

return M
