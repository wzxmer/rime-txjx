-- txjx_embeded_cands.lua
local embeded_cands_filter = {}

-- 核心模块
local core = {
    -- 由translator記録輸入串
    input_code = '',
    -- 由translator計算暫存串
    stashed_text = '',
    -- 基礎數據
    base_mem = nil,
    full_mem = nil,
    yuhao_mem = nil,
    -- 同步控制
    sync_at = 0,
    sync_bus = { switches = {} },
    -- 幫助命令
    helper_code = "zhelp",
    -- 開關類型
    switch_types = { switch = 1, radio = 2 },
    switch_names = {
        single_char = "single_char",
        fullcode_char = "fullcode_char",
        embeded_cands = "embeded_cands",
    }
}

-- 工具函數
function core.parse_conf_str(env, path, default)
    local str = env.engine.schema.config:get_string(env.name_space.."/"..path)
    return str or (default and #default ~= 0 and default)
end

function core.parse_conf_str_list(env, path, default)
    local list = {}
    local conf_list = env.engine.schema.config:get_list(env.name_space.."/"..path)
    if conf_list then
        for i = 0, conf_list.size-1 do
            table.insert(list, conf_list:get_value_at(i).value)
        end
    elseif default then
        list = default
    end
    return list
end

function core.single_smyh_seg(input)
    return string.match(input, "^[a-y][z;]$")       -- 一簡
        or string.match(input, "^[a-y][z;][z;]$")   -- 一簡詞
        or string.match(input, "^[a-y][a-y][z;]$")  -- 二簡詞
        or string.match(input, "^[a-y][a-y][a-y]$") -- 單字全碼
end

function core.valid_smyh_input(input)
    return string.match(input, "^[a-z;]*$") and not string.match(input, "^[z;]")
end

function core.get_switch_handler(env, option_name)
    local option = env.option or {}
    env.option = option
    return function(ctx, name)
        if name == option_name then
            option[name] = ctx:get_option(name) or true
        end
    end
end

function core.get_code_segs(input)
    local code_segs = {}
    while #input ~= 0 do
        if string.match(input:sub(1, 2), "[a-y][z;]") then
            if string.match(input:sub(1, 3), "[a-y][z;][z;]") then
                table.insert(code_segs, input:sub(1, 3))
                input = input:sub(4)
            else
                table.insert(code_segs, input:sub(1, 2))
                input = input:sub(3)
            end
        elseif string.match(input:sub(1, 3), "[a-y][a-y][a-z;]") then
            table.insert(code_segs, input:sub(1, 3))
            input = input:sub(4)
        else
            return code_segs, input
        end
    end
    return code_segs, input
end

function core.dict_lookup(mem, code, count, comp)
    count = count or 1
    comp = comp or false
    local result = {}
    if mem then
        code = code:gsub("z", ";")
        if mem:dict_lookup(code, comp, count) then
            for entry in mem:iter_dict() do
                table.insert(result, entry)
            end
        end
    end
    return result
end

function core.query_first_cand_list(mem, code_segs)
    local cand_list = {}
    for _, code in ipairs(code_segs) do
        local entries = core.dict_lookup(mem, code)
        table.insert(cand_list, entries[1] and entries[1].text or "")
    end
    return cand_list
end

function core.query_cand_list(mem, code_segs, skipfull)
    local index, cand_list = 1, {}
    while index <= #code_segs do
        for viewport = #code_segs, index, -1 do
            if not skipfull or viewport-index+1 < #code_segs then
                local code = table.concat(code_segs, "", index, viewport)
                local entries = core.dict_lookup(mem, code)
                if entries[1] then
                    table.insert(cand_list, entries[1].text)
                    index = viewport + 1
                    break
                elseif viewport == index then
                    table.insert(cand_list, "")
                    index = viewport + 1
                    break
                end
            end
        end
    end
    return cand_list
end

-- 候选嵌入功能
local index_indicators = {"¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹", "⁰"}
local first_format = "${Stash}[${候選}${Seq}]${Code}${Comment}"
local next_format = "${Stash}${候選}${Seq}${Comment}"
local separator = " "
local stash_placeholder = "~"

function embeded_cands_filter.init(env)
    env.config = {
        index_indicators = index_indicators,
        first_format = first_format,
        next_format = next_format,
        separator = separator,
        stash_placeholder = stash_placeholder,
        option_name = core.switch_names.embeded_cands
    }
    env.option = {}
    env.option[env.config.option_name] = env.engine.context:get_option(env.config.option_name)
    env.engine.context.option_update_notifier:connect(function(ctx, name)
        if name == env.config.option_name then
            env.option[name] = ctx:get_option(name)
        end
    end)
end

local function render_stashcand(env, seq, stash, text, digested)
    if #stash ~= 0 and text ~= stash and text:match("^"..stash) then
        if seq == 1 then
            digested = true
            text = text:sub(#stash+1)
        elseif not digested then
            digested = true
            stash, text = "["..stash.."]", text:sub(#stash+1)
        else
            local placeholder = env.config.stash_placeholder:gsub("%${Stash}", stash)
            stash, text = "", placeholder..text:sub(#stash+1)
        end
    else
        stash, text = "", text
    end
    return stash, text, digested
end

local function render_cand(env, seq, code, stashed, text, comment, digested)
    local cand = seq == 1 and env.config.first_format or env.config.next_format
    stashed, text, digested = render_stashcand(env, seq, stashed, text, digested)
    if seq ~= 1 and text == "" then return "", digested end
    
    local replacements = {
        ["%${Seq}"] = env.config.index_indicators[seq],
        ["%${Code}"] = code:gsub("%%", "%%%%"),
        ["%${Stash}"] = stashed:gsub("%%", "%%%%"),
        ["%${候選}"] = text:gsub("%%", "%%%%"),
        ["%${Comment}"] = comment:gsub("%%", "%%%%")
    }
    
    for pattern, repl in pairs(replacements) do
        cand = cand:gsub(pattern, repl)
    end
    return cand, digested
end

function embeded_cands_filter.func(input, env)
    if not env.option[env.config.option_name] then
        for cand in input:iter() do yield(cand) end
        return
    end
    
    local page_size = env.engine.schema.page_size
    local page_cands, page_rendered = {}, {}
    local index, first_cand, preedit = 0, nil, ""
    local digested = false
    
    local function refresh_preedit()
        if first_cand then
            first_cand.preedit = table.concat(page_rendered, env.config.separator)
            for _, c in ipairs(page_cands) do yield(c) end
        end
        first_cand, preedit = nil, ""
        page_cands, page_rendered = {}, {}
        digested = false
    end
    
    for cand in input:iter() do
        index = index + 1
        local gen_cand = cand:get_genuine()
        if index == 1 then first_cand = gen_cand end
        
        local input_code = cand.preedit or ""
        local stashed_text = ""
        preedit, digested = render_cand(env, index, input_code, stashed_text, 
                                      cand.text, cand.comment or "", digested)
        
        table.insert(page_cands, gen_cand)
        if #preedit ~= 0 then table.insert(page_rendered, preedit) end
        if index == page_size then refresh_preedit() end
    end
    refresh_preedit()
end

function embeded_cands_filter.fini(env)
    env.option = nil
end

return embeded_cands_filter
