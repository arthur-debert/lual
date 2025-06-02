local dispatchers = {}

dispatchers.console_dispatcher = require("lual.dispatchers.console_dispatcher")
dispatchers.file_dispatcher = require("lual.dispatchers.file_dispatcher")
dispatchers.syslog_dispatcher = require("lual.dispatchers.syslog_dispatcher")

return dispatchers
