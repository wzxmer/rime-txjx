package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local chain = require("zzc.txjx_zzc_chain")
local candidates = require("zzc.txjx_zzc_candidates")

local passed = 0

local function equal(actual, expected, label)
    assert(actual == expected, string.format(
        "%s: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
end

local function record_signature(records)
    local out = {}
    for _, record in ipairs(records or {}) do
        out[#out + 1] = table.concat({
            record.mark, record.word, record.code,
        }, ":")
    end
    return table.concat(out, "|")
end

local function probe_from(rows, failures)
    return function(code)
        if failures and failures[code] then return nil, failures[code] end
        local out = {}
        for i, word in ipairs(rows[code] or {}) do out[i] = word end
        return out
    end
end

local function test(name, fn)
    fn()
    passed = passed + 1
    print("PASS", name)
end

test("delete recursively fills standard shape gaps", function()
    local records = assert(chain.plan_delete({ "知己" }, "fkjk", probe_from({
        fkjk = { "知己" },
        fkjka = { "织机" },
        fkjkaa = { "治绩" },
        fkjki = { "值机" },
    })))
    equal(record_signature(records), table.concat({
        "!:知己:fkjk",
        "-:织机:fkjk", "!:织机:fkjka",
        "-:治绩:fkjka", "!:治绩:fkjkaa",
    }, "|"), "recursive delete")
end)

test("same-code candidate prevents compaction", function()
    local records = assert(chain.plan_delete({ "峙棘" }, "fkjkiv", probe_from({
        fkjkiv = { "峙棘", "指基" },
    })))
    equal(record_signature(records), "!:峙棘:fkjkiv", "same-code")
end)

test("batch delete freezes original words", function()
    local records = assert(chain.plan_delete({ "甲", "乙" }, "abcd", probe_from({
        abcd = { "甲", "乙", "丙" },
        abcda = { "丁" },
    })))
    equal(record_signature(records), "!:甲:abcd|!:乙:abcd", "batch delete")
end)

test("three-code gap skips ineligible long word", function()
    local records = assert(chain.plan_delete({ "有意见" }, "yyj", probe_from({
        yyj = { "有意见" },
        yyja = { "四字词语", "演艺界" },
    })))
    equal(record_signature(records), table.concat({
        "!:有意见:yyj", "-:演艺界:yyj", "!:演艺界:yyja",
    }, "|"), "minimum length")
end)

test("probe failure stops before lower-priority child", function()
    local records, warning = chain.plan_delete({ "甲词" }, "abcd", probe_from({
        abcd = { "甲词" },
        abcdi = { "乙词" },
    }, {
        abcda = "candidate_scan_limit",
    }))
    equal(record_signature(records), "!:甲词:abcd", "probe failure")
    equal(warning, "candidate_scan_limit", "probe warning")
end)

test("deeper probe failure discards earlier compaction moves", function()
    local records, warning = chain.plan_delete({ "甲词" }, "abcd", probe_from({
        abcd = { "甲词" },
        abcda = { "乙词" },
    }, {
        abcdaa = "candidate_scan_limit",
    }))
    equal(record_signature(records), "!:甲词:abcd", "deep probe rollback")
    equal(warning, "candidate_scan_limit", "deep probe warning")
end)

test("nonstandard child codes never auto-promote", function()
    local records = assert(chain.plan_delete({ "原词" }, "gfmz", probe_from({
        gfmz = { "原词" },
        gfmzf = { "板蓝根冲剂" },
        gfmzx = { "小儿感冒清热颗粒" },
    })))
    equal(record_signature(records), "!:原词:gfmz", "nonstandard codes")
end)

test("replace relocates existing descendant without duplicate", function()
    local next_codes = {
        ["知己@fkjk"] = "fkjku",
        ["智己@fkjku"] = "fkjkua",
    }
    local records = assert(chain.plan_replace({
        word = "雉鸡",
        code = "fkjk",
        replaced_word = "知己",
        probe_words = probe_from({
            fkjku = { "智己" },
            fkjkua = { "雉鸡" },
        }),
        next_code = function(word, code) return next_codes[word .. "@" .. code] end,
        source_codes = { "fkjku", "fkjkua" },
    }))
    equal(record_signature(records), table.concat({
        "+:雉鸡:fkjk",
        "-:知己:fkjku", "!:知己:fkjk",
        "-:智己:fkjkua", "!:智己:fkjku",
        "!:雉鸡:fkjkua",
    }, "|"), "relocate")
end)

test("replace removes non-first duplicate and continues chain", function()
    local records = assert(chain.plan_replace({
        word = "新词",
        code = "abcd",
        replaced_word = "甲词",
        probe_words = probe_from({
            abcda = { "乙词", "新词" },
            abcdaa = {},
        }),
        next_code = function(word, code)
            if word == "甲词" and code == "abcd" then return "abcda" end
            if word == "乙词" and code == "abcda" then return "abcdaa" end
        end,
        source_codes = { "abcda", "abcdaa" },
    }))
    local signature = record_signature(records)
    assert(signature:find("!:新词:abcda", 1, true), signature)
    assert(signature:find("-:乙词:abcdaa", 1, true), signature)
end)

test("replace removes duplicate from terminal six-code bucket", function()
    local records = assert(chain.plan_replace({
        word = "新词",
        code = "abcd",
        replaced_word = "四码原词",
        probe_words = probe_from({
            abcda = { "五码原词" },
            abcdaa = { "六码原词", "新词" },
        }),
        next_code = function(word, code)
            if word == "四码原词" and code == "abcd" then return "abcda" end
            if word == "五码原词" and code == "abcda" then return "abcdaa" end
        end,
        source_codes = { "abcda", "abcdaa" },
    }))
    equal(record_signature(records), table.concat({
        "+:新词:abcd",
        "-:四码原词:abcda", "!:四码原词:abcd",
        "-:五码原词:abcdaa", "!:五码原词:abcda",
        "!:新词:abcdaa",
    }, "|"), "terminal duplicate")
    local signature = record_signature(records)
    assert(not signature:find("!:六码原词:abcdaa", 1, true), signature)
end)

test("replace compacts an unrelated vacated source branch", function()
    local records = assert(chain.plan_replace({
        word = "新词",
        code = "abcd",
        replaced_word = "甲词",
        probe_words = probe_from({
            abcda = {},
            abcdi = { "新词" },
            abcdiv = { "补位词" },
        }),
        next_code = function(word, code)
            if word == "甲词" and code == "abcd" then return "abcda" end
        end,
        source_codes = { "abcdi", "abcdiv" },
    }))
    local signature = record_signature(records)
    assert(signature:find("!:新词:abcdi", 1, true), signature)
    assert(signature:find("-:补位词:abcdi", 1, true), signature)
    assert(signature:find("!:补位词:abcdiv", 1, true), signature)
end)

test("move source on displacement path writes one delete", function()
    local records = assert(chain.plan_replace({
        word = "智己",
        code = "fkjk",
        op = "move",
        replaced_word = "知己",
        probe_words = probe_from({ fkjku = { "智己" } }),
        next_code = function(word, code)
            if word == "知己" and code == "fkjk" then return "fkjku" end
        end,
        source_codes = { "fkjku" },
    }))
    local deletes = 0
    for _, record in ipairs(records) do
        if record.mark == "!" and record.word == "智己"
            and record.code == "fkjku" then deletes = deletes + 1 end
    end
    equal(deletes, 1, "move source delete count")
end)

test("replace aborts on uncertain probe", function()
    local records, err = chain.plan_replace({
        word = "新词",
        code = "abcd",
        replaced_word = "甲词",
        probe_words = probe_from({}, { abcda = "candidate_scan_limit" }),
        next_code = function() return "abcda" end,
    })
    equal(records, nil, "uncertain replace records")
    equal(err, "candidate_scan_limit", "uncertain replace error")
end)

test("replace aborts when source compaction probe is uncertain", function()
    local records, err = chain.plan_replace({
        word = "新词",
        code = "abcd",
        replaced_word = "甲词",
        probe_words = probe_from({
            abcda = {},
            abcdi = { "新词" },
        }, {
            abcdia = "candidate_scan_limit",
        }),
        next_code = function() return "abcda" end,
        source_codes = { "abcdi" },
    })
    equal(records, nil, "source compaction records")
    equal(err, "candidate_scan_limit", "source compaction error")
end)

test("append removes only the matching terminal duplicate", function()
    local records = assert(chain.plan_append({
        word = "新词",
        code = "abcd",
        probe_words = probe_from({
            abcda = { "五码原词" },
            abcdaa = { "六码原词", "新词" },
        }),
        source_codes = { "abcda", "abcdaa" },
    }))
    equal(record_signature(records), table.concat({
        "+:新词:abcd",
        "!:新词:abcdaa",
    }, "|"), "append terminal duplicate")
end)

test("append compacts an emptied duplicate source", function()
    local records = assert(chain.plan_append({
        word = "新词",
        code = "abcd",
        probe_words = probe_from({
            abcda = { "新词" },
            abcdaa = { "补位词" },
        }),
        source_codes = { "abcda", "abcdaa" },
    }))
    equal(record_signature(records), table.concat({
        "+:新词:abcd",
        "!:新词:abcda",
        "-:补位词:abcda", "!:补位词:abcdaa",
    }, "|"), "append source compaction")
end)

test("append aborts on uncertain source probe", function()
    local records, err = chain.plan_append({
        word = "新词",
        code = "abcd",
        probe_words = probe_from({}, { abcda = "candidate_scan_limit" }),
        source_codes = { "abcda", "abcdaa" },
    })
    equal(records, nil, "uncertain append records")
    equal(err, "candidate_scan_limit", "uncertain append error")
end)

test("menu reader exposes one extra candidate", function()
    local menu = {
        values = { "甲", "乙", "丙" },
        prepare = function(self, count) self.prepared = count end,
        get_candidate_at = function(self, index)
            local value = self.values[index + 1]
            return value and { text = value } or nil
        end,
    }
    local rows, extra = candidates.menu_candidates(menu, 2)
    equal(#rows, 2, "menu rows")
    equal(extra.text, "丙", "menu extra")
    equal(menu.prepared, 3, "menu prepare")
end)

print(string.format("zzc_chain_test: %d passed", passed))
