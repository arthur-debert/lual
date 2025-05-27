local handlers = {}

handlers.stream_handler = require("lual.handlers.stream_handler")
-- Placeholder for file_handler if we extract it next
-- handlers.file_handler = require("lual.handlers.file_handler")

return handlers
