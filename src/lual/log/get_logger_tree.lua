-- Logger Tree Builder
-- This module handles building a list of loggers that should process a log record

local M = {}

--- Builds the logger tree for processing a log record
-- Returns an array of loggers in the hierarchy that should process the record
-- Stops at the first logger with propagate=false or at the root logger
-- @param source_logger table The logger that originated the log event
-- @return table Array of loggers to process
function M.get_logger_tree(source_logger)
    local logger_tree = {}
    local current_logger = source_logger

    -- Process through the hierarchy (from source up to _root)
    while current_logger do
        -- Add this logger to the tree
        table.insert(logger_tree, current_logger)

        -- Stop at root logger
        if current_logger.name == "_root" then
            break
        end

        -- Stop if propagate is false
        if not current_logger.propagate then
            break
        end

        -- Continue to parent
        current_logger = current_logger.parent
    end

    return logger_tree
end

return M
