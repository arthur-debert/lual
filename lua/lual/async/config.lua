--- Async Configuration Handler
-- This module handles the 'async' configuration key

local async_writer = require("lual.async")

local M = {}

-- Schema for async configuration
M.schema = {
    enabled = { type = "boolean", description = "Enable asynchronous logging mode" },
    backend = { type = "string", description = "Async backend ('coroutines', etc.)" },
    batch_size = { type = "number", description = "Number of messages to batch before writing" },
    flush_interval = { type = "number", description = "Time interval (seconds) to force flush batches" },
    max_queue_size = { type = "number", description = "Maximum number of messages in async queue" },
    overflow_strategy = { type = "string", description = "Queue overflow strategy" }
}

--- Validates async configuration
-- @param async_config table The async configuration to validate
-- @param full_config table The full configuration context
-- @return boolean, string True if valid, otherwise false and error message
function M.validate(async_config, full_config)
    if type(async_config) ~= "table" then
        return false, "Invalid type for 'async': expected table, got " .. type(async_config) .. ". Async configuration"
    end

    -- Check for unknown keys
    local table_utils = require("lual.utils.table")
    local key_diff = table_utils.key_diff(M.schema, async_config)
    if #key_diff.added_keys > 0 then
        local valid_keys = {}
        for valid_key, _ in pairs(M.schema) do
            table.insert(valid_keys, valid_key)
        end
        table.sort(valid_keys)
        return false, string.format(
            "Unknown async configuration key '%s'. Valid keys are: %s",
            tostring(key_diff.added_keys[1]),
            table.concat(valid_keys, ", ")
        )
    end

    -- Validate async sub-keys
    for async_key, async_value in pairs(async_config) do
        local expected_spec = M.schema[async_key]
        if expected_spec and expected_spec.type and type(async_value) ~= expected_spec.type then
            return false, string.format(
                "Invalid type for async.%s: expected %s, got %s. %s",
                async_key,
                expected_spec.type,
                type(async_value),
                expected_spec.description
            )
        end

        -- Additional validation for specific async keys
        if async_key == "batch_size" and async_value <= 0 then
            return false, "async.batch_size must be greater than 0"
        elseif async_key == "flush_interval" and async_value <= 0 then
            return false, "async.flush_interval must be greater than 0"
        elseif async_key == "max_queue_size" and async_value <= 0 then
            return false, "async.max_queue_size must be greater than 0"
        elseif async_key == "overflow_strategy" then
            local valid_strategies = { drop_oldest = true, drop_newest = true, block = true }
            if not valid_strategies[async_value] then
                return false, "async.overflow_strategy must be 'drop_oldest', 'drop_newest', or 'block'"
            end
        elseif async_key == "backend" then
            local valid_backends = { coroutines = true, libuv = true }
            if not valid_backends[async_value] then
                return false, "async.backend must be 'coroutines' or 'libuv'"
            end
        end
    end

    return true
end

--- Applies async configuration changes
-- @param async_config table The async configuration to apply
-- @param current_config table The current full configuration
-- @return table The async configuration to store
function M.apply(async_config, current_config)
    -- Handle async configuration - start/stop async writer as needed
    if async_config.enabled ~= nil then
        if async_config.enabled then
            async_writer.start({ async = async_config }, nil)
            -- Setup the dispatch function in pipeline module
            local pipeline_module = require("lual.pipelines")
            pipeline_module.setup_async_writer()
        else
            -- Stop async writer
            async_writer.stop()
        end
    end

    return async_config
end

return M
