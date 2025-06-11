rockspec_format = "3.0"
package = "lual"
version = "1.0.3-1"
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
   modules = {
      lual = "lua/lual/init.lua",
      ["lual.logger"] = "lua/lual/logger.lua",
      ["lual.api"] = "lua/lual/api.lua",
      ["lual.loggers"] = "lua/lual/loggers/init.lua",
      ["lual.constants"] = "lua/lual/constants.lua",
      ["lual.levels"] = "lua/lual/levels/init.lua",
      ["lual.config"] = "lua/lual/config/init.lua",
      ["lual.config.command_line"] = "lua/lual/config/command_line.lua",
      ["lual.async"] = "lua/lual/async/init.lua",
      ["lual.utils.table"] = "lua/lual/utils/table.lua",
      ["lual.config.api"] = "lua/lual/config/api.lua",
      ["lual.config.defaults"] = "lua/lual/config/defaults.lua",
      ["lual.config.registry"] = "lua/lual/config/registry.lua",
      ["lual.config.validation"] = "lua/lual/config/validation.lua",
      ["lual.config.propagate"] = "lua/lual/config/propagate.lua",
      ["lual.loggers.config"] = "lua/lual/loggers/config.lua",
      ["lual.levels.config"] = "lua/lual/levels/config.lua",
      ["lual.pipelines.config"] = "lua/lual/pipelines/config.lua",
      ["lual.async.config"] = "lua/lual/async/config.lua",
      ["lual.pipelines.outputs"] = "lua/lual/pipelines/outputs/init.lua",
      ["lual.pipelines.presenters"] = "lua/lual/pipelines/presenters/init.lua",
      ["lual.pipelines.transformers"] = "lua/lual/pipelines/transformers/init.lua",
      ["lual.utils.fname_to_module"] = "lua/lual/utils/fname_to_module.lua"
   },
   copy_directories = {
      "docs"
   }
}
test_dependencies = {
   "busted >= 2.0.0"
}
test = {
   type = "busted"
} 