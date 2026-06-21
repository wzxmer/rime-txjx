local M = {}

function M.candidate_type(cand)
    if not cand then return nil end
    local cand_type = cand.type
    if cand.get_genuine then
        local ok, genuine = pcall(function() return cand:get_genuine() end)
        if ok and genuine and genuine.type then cand_type = genuine.type end
    end
    return cand_type
end

function M.is_real_candidate(cand)
    local cand_type = M.candidate_type(cand)
    return cand
        and cand.text
        and cand.text ~= ""
        and cand.text:sub(1, 1) ~= "~"
        and cand_type ~= "completion"
        and cand_type ~= "zzc_state"
        and cand_type ~= "zzc_make_word"
        and cand_type ~= "punct"
end

return M
