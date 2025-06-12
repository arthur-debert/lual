rockspec_format = "3.0"
package = "lual"
version = "1.0.11-1"
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
   install = {
      lua = {
         ["lual"]  = "lua/lual"
       }
   },
}
test_dependencies = {
   "busted >= 2.0.0"
}
test = {
   type = "busted"
} 