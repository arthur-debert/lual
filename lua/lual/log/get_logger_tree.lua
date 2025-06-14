-- Logger Tree Builder
-- This module handles building a list of loggers that should process a log record

-- Import the standalone debug module to avoid circular dependencies
local debug_module = require("lual.debug")

local M = {}

--- Builds the logger tree for processing a log record
-- Returns an array of loggers in the hierarchy that should process the record
-- Stops at the first logger with propagate=false or at the root logger
-- @param source_logger table The logger that originated the log event
-- @return table Array of loggers to process
function M.get_logger_tree(source_logger)
    debug_module._debug_print("Logger tree walk: starting from logger '%s'", source_logger.name)

    local logger_tree = {}
    local current_logger = source_logger

    -- Process through the hierarchy (from source up to _root)
    while current_logger do
        debug_module._debug_print("Logger tree walk: processing logger '%s' (propagate=%s)",
            current_logger.name, tostring(current_logger.propagate))

        -- Add this logger to the tree
        table.insert(logger_tree, current_logger)

        -- Stop at root logger
        if current_logger.name == "_root" then
            debug_module._debug_print("Logger tree walk: reached root logger, stopping")
            break
        end

        -- Stop if propagate is false
        if not current_logger.propagate then
            debug_module._debug_print("Logger tree walk: propagate=false on '%s', stopping", current_logger.name)
            break
        end

        -- Continue to parent
        local parent_name = current_logger.parent and current_logger.parent.name or "nil"
        debug_module._debug_print("Logger tree walk: moving to parent '%s'", parent_name)
        current_logger = current_logger.parent
    end

    debug_module._debug_print("Logger tree walk: built tree with %d loggers: %s",
        #logger_tree,
        table.concat((function()
            local names = {}
            for _, logger in ipairs(logger_tree) do
                table.insert(names, logger.name)
            end
            return names
        end)(), " -> "))

    return logger_tree
end

return M
