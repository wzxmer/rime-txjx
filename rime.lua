-- 天行键
-- txjx_filter: 单字模式 & 630 即 ss 词组提示
--- 修改自 @懒散 TsFreddie https://github.com/TsFreddie/jdc_lambda/blob/master/rime/lua/xkjdc_sbb_hint.lua
-- 可由 schema 的 danzi_mode 与 wxw_hint 开关控制
-- 详见 `lua/txjx_filter.lua`
txjx_filter = require("txjx_filter")
-- 顶功处理器
txjx_forTopUp = require("txjx_forTopUp")
-- 用 ' 作为次选键
txjx_smartTwo = require("txjx_smartTwo")
txjx_number = require("txjx_number")
txjx_calculator = require("txjx_calculator")
txjx_time = require("txjx_time")
--内嵌脚本
embeded_cands = require("embeded_cands")
--字母
txjx_zimu= require("txjx_zimu")