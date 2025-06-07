local outputs = {}

outputs.console = require("lual.pipeline.outputs.console")
outputs.file = require("lual.pipeline.outputs.file")
outputs.syslog = require("lual.pipeline.outputs.syslog")

return outputs
