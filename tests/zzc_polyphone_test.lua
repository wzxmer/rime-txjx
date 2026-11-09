-- Run through zzc_polyphone_test.py; all writes stay inside its fixture directory.
local root, source = assert(arg[1]), assert(arg[2])
package.path = source .. '/lua/?.lua;' .. package.path
rime_api = { get_user_data_dir = function() return root end }
local core = require('zzc.txjx_zzc_core')

local native = { ebsy = { '水松' } }
local function probe(code)
    local cover = core.zzc_cover_for_input(code) or {}
    local out, seen = {}, {}
    local function add(word)
        if not seen[word] then out[#out + 1] = word; seen[word] = true end
    end
    for _, row in ipairs(cover.rows or {}) do add(row.word) end
    for _, word in ipairs(native[code] or {}) do
        if not (cover.hide_words or {})[word] then add(word) end
    end
    for _, row in ipairs(cover.append_rows or {}) do add(row.word) end
    return out
end
local function has(code, word)
    for _, text in ipairs(probe(code)) do if text == word then return true end end
    return false
end
local function items(word, code)
    -- Use the same resolved-code items as the processor's polyphone menu.
    for _, choice in ipairs(assert(core.code_choices_for_text(word, #code))) do
        if choice.code == code then return choice.items end
    end
    error('missing code choice: ' .. word .. ' ' .. code)
end
local function save(word, code, append)
    local parts = items(word, code)
    if append then
        assert(core.append_word_at_code(parts, code, probe))
    else
        assert(core.save_word_at_code(parts, code, probe(code)[1], nil, probe))
    end
end
local function reset(rows)
    assert(core.undo_all_pending())
    native = rows or {}
end

-- The reported sequence: another reading must not undo displacement at ebsy.
save('谁送', 'ebsy')
assert(has('ebsy', '谁送') and has('ebsya', '水松'))
save('谁送', 'ewsy')
assert(has('ebsy', '谁送'), 'adding ewsy removed the independent ebsy reading')
assert(has('ewsy', '谁送') and has('ebsya', '水松'))
assert(not has('ebsy', '水松'))
assert(core.undo_last_tx())
assert(has('ebsy', '谁送') and not has('ewsy', '谁送'))
save('谁送', 'ewsy')
assert(core.flush_runtime_ops())
core.clear_pending_cache()
assert(has('ebsy', '谁送') and has('ewsy', '谁送'), 'flush/reload lost a reading')

for _, append in ipairs({ false, true }) do
    reset({ ebsy = { '谁送' }, ewsyo = { '谁送' }, ewsy = { '水松' } })
    save('谁送', 'ewsy', append)
    assert(has('ebsy', '谁送') and has('ewsy', '谁送'))
    assert(not has('ewsyo', '谁送'), 'same-reading longer duplicate survived')
    if append then assert(probe('ewsy')[1] == '水松', 'append stole first place') end

    reset({ ebsy = { '谁送' }, ewsy = { '谁送', '水松' } })
    save('谁送', 'ewsyo', append)
    assert(has('ebsy', '谁送') and has('ewsyo', '谁送'))
    assert(not has('ewsy', '谁送'), 'same-reading shorter duplicate survived')

    reset({ ebsy = { '谁送' }, ewsy = { '水松', '谁送' }, ewsyo = { '谁送' } })
    save('谁送', 'ewsy', append)
    local count = 0
    for _, word in ipairs(probe('ewsy')) do if word == '谁送' then count = count + 1 end end
    assert(count == 1 and has('ebsy', '谁送') and not has('ewsyo', '谁送'))
end

-- Three-character words use three sound keys; punctuation is not a character.
for _, case in ipairs({
    { '谁送水', 'ese', 'eseo', 'esro' },
    { '谁送水松', 'eses', 'eseso', 'esrs' },
    { '谁，送。', 'ewsy', 'ewsyo', 'ebsy' },
}) do
    reset({ [case[3]] = { case[1] }, [case[4]] = { case[1] } })
    save(case[1], case[2])
    assert(has(case[2], case[1]) and not has(case[3], case[1]))
    assert(has(case[4], case[1]), 'deleted another sound stem')
end

-- A failed same-reading probe must not write a partial transaction.
reset()
local result = core.append_word_at_code(items('谁送', 'ewsy'), 'ewsy', function(code)
    if code == 'ewsyo' then return nil, 'probe_failed' end
    return {}
end)
assert(not result and not has('ewsy', '谁送'))
print('PASS: polyphone save/append, same-chain dedupe, displacement, undo, flush, punctuation, probe failure')
