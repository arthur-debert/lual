rockspec_format = "3.0"
package = "lualextras"
version = "0.9.0-1"
source = {
   url = "git+https://github.com/arthur-debert/lual.git"
}
description = {
   summary = "A focused but powerful and flexible logging library for Lua.",
   detailed = [[
      lual is a logging library inspired by Python's stdlib and loguru loggers. It provides hierarchical logging with propagation, multiple dispatcheres (console, file, syslog), various presenter (text, color, JSON), and both imperative and config APIs. Designed with Lua's strengths in mind using functions and tables.
   ]],
   homepage = "https://github.com/arthur-debert/lual",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1",
   "dkjson >= 2.5",
   "luasocket >= 3.0rc1-2",
   "busted >= 2.0.0"
}
build = {
   type = "builtin",
   modules = {
      lual = "lua/lual/logger.lua"
   },
   copy_directories = {
      "docs"
   }
}
test_dependencies = {
}
test = {
   type = "busted"
} 