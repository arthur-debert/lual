local outputs = {}

outputs.console_output = require("lual.outputs.console_output")
outputs.file_output = require("lual.outputs.file_output")
outputs.syslog_output = require("lual.outputs.syslog_output")

return outputs
