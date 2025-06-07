local outputs = {}

outputs.console_output = require("lual.pipeline.outputs.console_output")
outputs.file_output = require("lual.pipeline.outputs.file_output")
outputs.syslog_output = require("lual.pipeline.outputs.syslog_output")

return outputs
