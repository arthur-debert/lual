local outputs = {}

outputs.console = require("lual.pipelines.outputs.console")
outputs.file = require("lual.pipelines.outputs.file")
outputs.syslog = require("lual.pipelines.outputs.syslog")

return outputs
