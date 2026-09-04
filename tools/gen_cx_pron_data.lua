-- 生成万能反查读音预编译数据模块
-- 用法: lua tools/gen_cx_pron_data.lua [源词典] [输出文件]
-- 默认: lua tools/gen_cx_pron_data.lua txjx.cx.dict.yaml lua/txjx_cx_pron_data.lua
-- 解析逻辑必须与 lua/txjx_reverse_hint.lua 的 load_pron_map 保持一致：
--   行过滤 ^([^\t]+)\t\(([^%)]+)\) 、utf8_len==1、merge_pron 合并。
-- 生成的文件内嵌源词典 version；运行时校验不一致会自动回退现场解析。
local source = arg and arg[1] or "txjx.cx.dict.yaml"
local output = arg and arg[2] or "lua/txjx_cx_pron_data.lua"

local function utf8_len(text)
    if type(text) ~= "string" then return nil end
    return utf8.len(text)
end

local function merge_pron(old, new)
    if not old or old == "" then return new end
    if not new or new == "" then return old end
    if old:find(new, 1, true) then return old end
    return old .. "_" .. new
end

-- 提取源词典 version（YAML 头部 version: "..."）
local version = ""
local dict_count = 0
do
    local f = io.open(source, "r")
    if not f then
        io.stderr:write("cannot open source: " .. source .. "\n")
        os.exit(1)
    end
    local in_body = false
    for line in f:lines() do
        if not in_body then
            local v = line:match('^version:%s*"?([^"\r\n]+)"?')
            if v then version = v end
            if line:match("^%.%.%.%s*$") or line:match("^%.%.\r?$") then in_body = true end
        elseif line ~= "" and not line:match("^%s*#") then
            dict_count = dict_count + 1
        end
    end
    f:close()
end

local map = {}
local count = 0
local f = io.open(source, "r")
local in_body = false
for line in f:lines() do
    if not in_body then
        if line:match("^%.%.%.%s*$") then in_body = true end
    else
        local text, pron = line:match("^([^\t]+)\t%(([^%)]+)%)")
        if text and pron and utf8_len(text) == 1 then
            local merged = merge_pron(map[text], pron)
            if map[text] == nil then count = count + 1 end
            map[text] = merged
        end
    end
end
f:close()

local out = io.open(output, "w")
if not out then
    io.stderr:write("cannot write output: " .. output .. "\n")
    os.exit(1)
end
out:write("-- 万能反查读音预编译数据（由 tools/gen_cx_pron_data.lua 生成，勿手改）\n")
out:write("-- 源: " .. source .. " version=" .. version .. " 词条=" .. dict_count .. " 读音=" .. count .. "\n")
out:write("-- 若源词典读音变动，重新运行生成脚本；运行时 version 不一致会自动回退现场解析。\n\n")
out:write("return {\n")
out:write('    source_version = "' .. version .. '",\n')
out:write("    map = {\n")
local keys = {}
for k in pairs(map) do keys[#keys + 1] = k end
table.sort(keys, function(a, b) return a < b end)
for _, k in ipairs(keys) do
    out:write(string.format('        ["%s"]="%s",\n', k, map[k]))
end
out:write("    },\n}\n")
out:close()
print(string.format("generated %s: version=%s 读音=%d", output, version, count))
