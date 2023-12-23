-- 记录开关状态
local enabled = false
return {
    init = function(env)
        -- 开关名
        local option_name = "completion"
        -- 回调函数
        local handler = function(ctx, opname)
            if opname == option_name then
                -- 查询当前 switch 值
                enabled = ctx:get_option(opname) and true or false
            end
        end
        -- 添加通知回调, 当开关变动时, 调用 handler 函数
        env.engine.context.option_update_notifier:connect(handler)
    end,
    func = function(input, env)
        if enabled then
            -- 启用补全时, 直接送出候选
            for cand in input:iter() do
                yield(cand)
            end
        else
            -- 禁用补全时, 若遍历到「补全类」候选, 则终止并丢弃后续的候选
            for cand in input:iter() do
                -- 候选类型为 completion, 表明其来源于编码补全
                if cand.type == "completion" then
                    return
                else
                    yield(cand)
                end
            end
        end
    end,
    fini = function()
    end,
}
