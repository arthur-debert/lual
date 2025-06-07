local presenters = {}

presenters.text = require("lual.pipelines.presenters.text")
presenters.color = require("lual.pipelines.presenters.color")
presenters.json = require("lual.pipelines.presenters.json")

return presenters
