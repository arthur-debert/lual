rockspec_format = "3.0"
package = "lual"
version = "1.0.15-1"
source = {
   url = "git+https://github.com/arthur-debert/lual.git"
}
description = {
   summary = "A focused but powerful and flexible logging library for Lua.",
   detailed = [[
      lual is a logging library inspired by Python's stdlib and loguru loggers. It provides hierarchical logging with propagation, multiple outputes (console, file, syslog), various presenter (text, color, JSON), and both imperative and config APIs. Designed with Lua's strengths in mind using functions and tables.
   ]],
   homepage = "https://github.com/arthur-debert/lual",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1",
}
build = {
   type = "builtin",
-- Generated module mappings for rockspec
modules = {
   ["lual.api"] = "lua/lual/api.lua",
   ["lual.async.backends.coroutines"] = "lua/lual/async/backends/coroutines.lua",
   ["lual.async.backends.libuv"] = "lua/lual/async/backends/libuv.lua",
   ["lual.async.config"] = "lua/lual/async/config.lua",
   ["lual.async.core"] = "lua/lual/async/core.lua",
   ["lual.async.schema"] = "lua/lual/async/schema.lua",
   ["lual.async"] = "lua/lual/async/init.lua",
   ["lual.config.api"] = "lua/lual/config/api.lua",
   ["lual.config.command_line_schema"] = "lua/lual/config/command_line_schema.lua",
   ["lual.config.command_line"] = "lua/lual/config/command_line.lua",
   ["lual.config.defaults"] = "lua/lual/config/defaults.lua",
   ["lual.config.live_level_schema"] = "lua/lual/config/live_level_schema.lua",
   ["lual.config.live_level"] = "lua/lual/config/live_level.lua",
   ["lual.config.propagate_schema"] = "lua/lual/config/propagate_schema.lua",
   ["lual.config.propagate"] = "lua/lual/config/propagate.lua",
   ["lual.config.registry"] = "lua/lual/config/registry.lua",
   ["lual.config.validation"] = "lua/lual/config/validation.lua",
   ["lual.config"] = "lua/lual/config/init.lua",
   ["lual.constants"] = "lua/lual/constants.lua",
   ["lual.debug"] = "lua/lual/debug.lua",
   ["lual.levels.config"] = "lua/lual/levels/config.lua",
   ["lual.levels.schema"] = "lua/lual/levels/schema.lua",
   ["lual.levels"] = "lua/lual/levels/init.lua",
   ["lual.log.get_logger_tree"] = "lua/lual/log/get_logger_tree.lua",
   ["lual.log.get_pipelines"] = "lua/lual/log/get_pipelines.lua",
   ["lual.log.log_record"] = "lua/lual/log/log_record.lua",
   ["lual.log.process"] = "lua/lual/log/process.lua",
   ["lual.log"] = "lua/lual/log/init.lua",
   ["lual.logger"] = "lua/lual/logger.lua",
   ["lual.loggers.config"] = "lua/lual/loggers/config.lua",
   ["lual.loggers.factory"] = "lua/lual/loggers/factory.lua",
   ["lual.loggers.schema"] = "lua/lual/loggers/schema.lua",
   ["lual.loggers.tree"] = "lua/lual/loggers/tree.lua",
   ["lual.loggers"] = "lua/lual/loggers/init.lua",
   ["lual.pipelines.config"] = "lua/lual/pipelines/config.lua",
   ["lual.pipelines.outputs.console"] = "lua/lual/pipelines/outputs/console.lua",
   ["lual.pipelines.outputs.file_schema"] = "lua/lual/pipelines/outputs/file_schema.lua",
   ["lual.pipelines.outputs.file"] = "lua/lual/pipelines/outputs/file.lua",
   ["lual.pipelines.outputs.syslog_schema"] = "lua/lual/pipelines/outputs/syslog_schema.lua",
   ["lual.pipelines.outputs.syslog"] = "lua/lual/pipelines/outputs/syslog.lua",
   ["lual.pipelines.outputs"] = "lua/lual/pipelines/outputs/init.lua",
   ["lual.pipelines.presenters.color"] = "lua/lual/pipelines/presenters/color.lua",
   ["lual.pipelines.presenters.json"] = "lua/lual/pipelines/presenters/json.lua",
   ["lual.pipelines.presenters.text"] = "lua/lual/pipelines/presenters/text.lua",
   ["lual.pipelines.presenters"] = "lua/lual/pipelines/presenters/init.lua",
   ["lual.pipelines.schema"] = "lua/lual/pipelines/schema.lua",
   ["lual.pipelines.transformers.noop"] = "lua/lual/pipelines/transformers/noop.lua",
   ["lual.pipelines.transformers"] = "lua/lual/pipelines/transformers/init.lua",
   ["lual.pipelines"] = "lua/lual/pipelines/init.lua",
   ["lual.utils.caller_info"] = "lua/lual/utils/caller_info.lua",
   ["lual.utils.component"] = "lua/lual/utils/component.lua",
   ["lual.utils.fname_to_module"] = "lua/lual/utils/fname_to_module.lua",
   ["lual.utils.paths"] = "lua/lual/utils/paths.lua",
   ["lual.utils.queue"] = "lua/lual/utils/queue.lua",
   ["lual.utils.schemer"] = "lua/lual/utils/schemer.lua",
   ["lual.utils.table"] = "lua/lual/utils/table.lua",
   ["lual.utils.time"] = "lua/lual/utils/time.lua",
   ["lual"] = "lua/lual/init.lua",
}
}
test_dependencies = {
   "busted >= 2.0.0",
   "luasocket",
   "dkjson",
}
test = {
   type = "busted"
} 
