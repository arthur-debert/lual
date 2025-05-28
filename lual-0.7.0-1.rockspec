rockspec_format = "3.0"
package = "lual"
version = "0.7.0-1"
source = {
   url = "."
}
description = {
   summary = "A focused but powerful and flexible logging library for Lua.",
   detailed = [[
      lual is a logging library inspired by Python's stdlib and loguru loggers. It provides hierarchical logging with propagation, multiple output handlers (console, file, syslog), various formatters (text, color, JSON), and both imperative and declarative APIs. Designed with Lua's strengths in mind using functions and tables.
   ]],
   homepage = "https://github.com/arthur-debert/lual",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1",
   "dkjson >= 2.5",  
    "luasocket >= 3.0rc1-2" 
}
test_dependencies = {
   "busted >= 2.0.0"
}
build = {
   type = "builtin",
   modules = {
      ["lual"] = "lua/lual/logger.lua",
   },
   copy_directories = {"docs"}
}
test = {
   type = "busted",
   -- Additional test configuration can go here
}