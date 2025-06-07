local presenters = {}

presenters.text = require("lual.pipeline.presenters.text")
presenters.color = require("lual.pipeline.presenters.color")
presenters.json = require("lual.pipeline.presenters.json")

return presenters
