local stats = require("txjx_typing_stats")

return {
    init = stats.init_processor,
    func = stats.processor,
    fini = stats.fini_processor,
}
