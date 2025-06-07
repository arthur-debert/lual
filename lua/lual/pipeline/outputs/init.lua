local outputs = {}

outputs.console = require("lual.pipeline.outputs.console")
outputs.file = require("lual.pipeline.outputs.file")
outputs.syslog_output = require("lual.pipeline.outputs.syslog_output")

return outputs
