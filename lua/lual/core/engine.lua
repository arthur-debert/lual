local ingest = require("lual.ingest")
local core_levels = require("lual.core.levels")
local caller_info = require("lual.core.caller_info")
local unpack = unpack or table.unpack

local _loggers_cache = {}

-- =============================================================================
-- CONFIG SCHEMA AND UTILITIES
-- =============================================================================

--- Creates a canonical config table with default values
-- @param config (table, optional) Initial config values
-- @return table The canonical config
local function create_canonical_config(config)
    config = config or {}

    return {
        name = config.name or "root",
        level = config.level or core_levels.definition.INFO,
        outputs = config.outputs or {},
        propagate = config.propagate ~= false, -- Default to true unless explicitly false
        parent = config.parent or nil
    }
end

--- Deep clones a config table
-- @param config (table) The config to clone
-- @return table The cloned config
local function clone_config(config)
    local cloned = {}
    for k, v in pairs(config) do
        if type(v) == "table" and k == "outputs" then
            -- Deep clone outputs array
            cloned[k] = {}
            for i, output in ipairs(v) do
                cloned[k][i] = {
                    output_func = output.output_func,
                    formatter_func = output.formatter_func,
                    output_config = output.output_config or {}
                }
            end
        else
            cloned[k] = v
        end
    end
    return cloned
end

--- Validates a config table
-- @param config (table) The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    if config.name and type(config.name) ~= "string" then
        return false, "Config.name must be a string"
    end

    if config.level and type(config.level) ~= "number" then
        return false, "Config.level must be a number"
    end

    if config.outputs and type(config.outputs) ~= "table" then
        return false, "Config.outputs must be a table"
    end

    if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
        return false, "Config.propagate must be a boolean"
    end

    -- Validate outputs structure
    if config.outputs then
        for i, output in ipairs(config.outputs) do
            if type(output) ~= "table" then
                return false, "Each output must be a table"
            end
            if not output.output_func or type(output.output_func) ~= "function" then
                return false, "Each output must have an output_func function"
            end
            if not output.formatter_func or type(output.formatter_func) ~= "function" then
                return false, "Each output must have a formatter_func function"
            end
        end
    end

    return true
end

-- =============================================================================
-- VALIDATION FUNCTIONS
-- =============================================================================

--- Validates a level value (string or number)
-- @param level The level to validate
-- @return boolean, string True if valid, or false with error message
local function validate_level(level)
    if level == nil then
        return true -- Level is optional
    end

    if type(level) == "string" then
        -- Get LEVELS from main module to avoid circular dependency
        local lual = require("lual.logger")
        if not lual.LEVELS[string.lower(level)] then
            local valid_levels = {}
            for k, _ in pairs(lual.LEVELS) do
                table.insert(valid_levels, k)
            end
            table.sort(valid_levels)
            return false, "Invalid level string: " .. level .. ". Valid levels are: " .. table.concat(valid_levels, ", ")
        end
    elseif type(level) == "number" then
        -- Allow numeric levels
    else
        return false, "Config.level must be a string or number"
    end

    return true
end

--- Validates output type and formatter type
-- @param output_type string The output type to validate
-- @param formatter_type string The formatter type to validate
-- @return boolean, string True if valid, or false with error message
local function validate_output_and_formatter_types(output_type, formatter_type)
    -- Validate known output types
    local valid_output_types = { console = true, file = true }
    if not valid_output_types[output_type] then
        local types = {}
        for k, _ in pairs(valid_output_types) do
            table.insert(types, k)
        end
        table.sort(types)
        return false, "Unknown output type: " .. output_type .. ". Valid types are: " .. table.concat(types, ", ")
    end

    -- Validate known formatter types
    local valid_formatter_types = { text = true, color = true }
    if not valid_formatter_types[formatter_type] then
        local types = {}
        for k, _ in pairs(valid_formatter_types) do
            table.insert(types, k)
        end
        table.sort(types)
        return false, "Unknown formatter type: " .. formatter_type .. ". Valid types are: " .. table.concat(types, ", ")
    end

    return true
end

--- Validates a single output configuration
-- @param output table The output config to validate
-- @param index number The index of the output (for error messages)
-- @return boolean, string True if valid, or false with error message
local function validate_single_output(output, index)
    if type(output) ~= "table" then
        return false, "Each output must be a table"
    end

    if not output.type or type(output.type) ~= "string" then
        return false, "Each output must have a 'type' string field"
    end

    if not output.formatter or type(output.formatter) ~= "string" then
        return false, "Each output must have a 'formatter' string field"
    end

    -- Validate output and formatter types
    local valid, err = validate_output_and_formatter_types(output.type, output.formatter)
    if not valid then
        return false, err
    end

    -- Validate type-specific fields
    if output.type == "file" then
        if not output.path or type(output.path) ~= "string" then
            return false, "File output must have a 'path' string field"
        end
    end

    if output.type == "console" and output.stream then
        -- stream should be a file handle, but we can't easily validate that
        -- so we'll just check it's not a string/number/boolean
        if type(output.stream) == "string" or type(output.stream) == "number" or type(output.stream) == "boolean" then
            return false, "Console output 'stream' field must be a file handle"
        end
    end

    return true
end

--- Validates outputs array for declarative format
-- @param outputs table The outputs array to validate
-- @return boolean, string True if valid, or false with error message
local function validate_outputs(outputs)
    if outputs == nil then
        return true -- Outputs is optional
    end

    if type(outputs) ~= "table" then
        return false, "Config.outputs must be a table"
    end

    for i, output in ipairs(outputs) do
        local valid, err = validate_single_output(output, i)
        if not valid then
            return false, err
        end
    end

    return true
end

--- Validates basic config fields (name, propagate)
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_basic_fields(config)
    if config.name and type(config.name) ~= "string" then
        return false, "Config.name must be a string"
    end

    if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
        return false, "Config.propagate must be a boolean"
    end

    return true
end

--- Validates that config doesn't contain unknown keys
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_known_keys(config)
    local valid_keys = {
        name = true,
        level = true,
        outputs = true,
        propagate = true
    }

    for key, _ in pairs(config) do
        if not valid_keys[key] then
            return false, "Unknown config key: " .. tostring(key)
        end
    end

    return true
end

--- Validates a declarative config table (with string-based types)
-- @param config (table) The declarative config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_declarative_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    -- Validate unknown keys
    local valid, err = validate_known_keys(config)
    if not valid then
        return false, err
    end

    -- Validate basic fields
    valid, err = validate_basic_fields(config)
    if not valid then
        return false, err
    end

    -- Validate level
    valid, err = validate_level(config.level)
    if not valid then
        return false, err
    end

    -- Validate outputs
    valid, err = validate_outputs(config.outputs)
    if not valid then
        return false, err
    end

    return true
end

--- Converts a declarative config to canonical config format
-- @param declarative_config (table) The declarative config
-- @return table The canonical config
local function declarative_to_canonical_config(declarative_config)
    local all_outputs = require("lual.outputs.init")
    local all_formatters = require("lual.formatters.init")

    local canonical = {
        name = declarative_config.name,
        propagate = declarative_config.propagate,
        outputs = {}
    }

    -- Convert level string to number if needed
    if declarative_config.level then
        if type(declarative_config.level) == "string" then
            local lual = require("lual.logger")
            canonical.level = lual.LEVELS[string.lower(declarative_config.level)]
        else
            canonical.level = declarative_config.level
        end
    end

    -- Convert outputs from declarative to canonical format
    if declarative_config.outputs then
        for _, output_config in ipairs(declarative_config.outputs) do
            local output_func
            local formatter_func
            local config = {}

            -- Get output function
            if output_config.type == "console" then
                output_func = all_outputs.console_output
                if output_config.stream then
                    config.stream = output_config.stream
                end
            elseif output_config.type == "file" then
                -- File output is a factory, so we need to call it with config to get the actual function
                local file_factory = all_outputs.file_output
                config.path = output_config.path
                -- Copy other file-specific config
                for k, v in pairs(output_config) do
                    if k ~= "type" and k ~= "formatter" and k ~= "path" then
                        config[k] = v
                    end
                end
                output_func = file_factory(config)
            end

            -- Get formatter function
            if output_config.formatter == "text" then
                formatter_func = all_formatters.text
            elseif output_config.formatter == "color" then
                formatter_func = all_formatters.color
            end

            table.insert(canonical.outputs, {
                output_func = output_func,
                formatter_func = formatter_func,
                output_config = config
            })
        end
    end

    return canonical
end

--- Merges user config with default config, with user config taking precedence
-- @param user_config (table) The user's partial config
-- @param default_config (table) The default config
-- @return table The merged config
local function merge_configs(user_config, default_config)
    local merged = {}

    -- Start with default config
    for k, v in pairs(default_config) do
        merged[k] = v
    end

    -- Override with user config
    for k, v in pairs(user_config) do
        merged[k] = v
    end

    return merged
end

-- =============================================================================
-- LOGGER PROTOTYPE
-- =============================================================================

local logger = {}

function logger:debug(message_fmt, ...)
    self:log(core_levels.definition.DEBUG, message_fmt, ...)
end

function logger:info(message_fmt, ...)
    self:log(core_levels.definition.INFO, message_fmt, ...)
end

function logger:warn(message_fmt, ...)
    self:log(core_levels.definition.WARNING, message_fmt, ...)
end

function logger:error(message_fmt, ...)
    self:log(core_levels.definition.ERROR, message_fmt, ...)
end

function logger:critical(message_fmt, ...)
    self:log(core_levels.definition.CRITICAL, message_fmt, ...)
end

function logger:log(level_no, message_fmt, ...)
    if not self:is_enabled_for(level_no) then
        return
    end

    local filename, lineno = caller_info.get_caller_info() -- Automatically find first non-lual file

    local log_record = {
        level_no = level_no,
        level_name = core_levels.get_level_name(level_no),
        message_fmt = message_fmt,
        args = table.pack(...), -- Use table.pack for varargs
        timestamp = os.time(),
        logger_name = self.name,
        source_logger_name = self.name, -- Initially the same as logger_name
        filename = filename,
        lineno = lineno
    }

    ingest.dispatch_log_event(log_record, get_logger, core_levels.definition) -- Pass get_logger and levels
end

function logger:set_level(level)
    -- Get current config, modify it, and recreate logger
    local current_config = self:get_config()
    current_config.level = level
    local new_logger = create_logger_from_config(current_config)

    -- Update the cache with the new logger
    _loggers_cache[self.name] = new_logger

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            self[k] = v
        end
    end
end

function logger:add_output(output_func, formatter_func, output_config)
    -- Get current config, modify it, and recreate logger
    local current_config = self:get_config()
    table.insert(current_config.outputs, {
        output_func = output_func,
        formatter_func = formatter_func,
        output_config = output_config or {}
    })
    local new_logger = create_logger_from_config(current_config)

    -- Update the cache with the new logger
    _loggers_cache[self.name] = new_logger

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            self[k] = v
        end
    end
end

function logger:set_propagate(propagate)
    -- Get current config, modify it, and recreate logger
    local current_config = self:get_config()
    current_config.propagate = propagate
    local new_logger = create_logger_from_config(current_config)

    -- Update the cache with the new logger
    _loggers_cache[self.name] = new_logger

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            self[k] = v
        end
    end
end

function logger:get_config()
    -- Return the current configuration as a canonical config table
    return create_canonical_config({
        name = self.name,
        level = self.level,
        outputs = self.outputs or {},
        propagate = self.propagate,
        parent = self.parent
    })
end

function logger:is_enabled_for(message_level_no)
    if self.level == core_levels.definition.NONE then
        return message_level_no == core_levels.definition.NONE
    end
    return message_level_no >= self.level
end

function logger:get_effective_outputs()
    local effective_outputs = {}
    local current_logger = self

    while current_logger do
        for _, output_item in ipairs(current_logger.outputs or {}) do
            table.insert(effective_outputs, {
                output_func = output_item.output_func,
                formatter_func = output_item.formatter_func,
                output_config = output_item.output_config,
                owner_logger_name = current_logger.name,
                owner_logger_level = current_logger.level
            })
        end

        if not current_logger.propagate or not current_logger.parent then
            break
        end
        current_logger = current_logger.parent
    end
    return effective_outputs
end

-- =============================================================================
-- CONFIG-BASED LOGGER CREATION
-- =============================================================================

--- Creates a logger from a canonical config table
-- @param config (table) The canonical config
-- @return table The logger instance
function create_logger_from_config(config)
    local valid, err = validate_config(config)
    if not valid then
        error("Invalid logger config: " .. err)
    end

    local canonical_config = create_canonical_config(config)

    -- Create new logger object based on prototype
    local new_logger = {}
    for k, v in pairs(logger) do
        new_logger[k] = v
    end

    new_logger.name = canonical_config.name
    new_logger.level = canonical_config.level
    new_logger.outputs = canonical_config.outputs
    new_logger.propagate = canonical_config.propagate
    new_logger.parent = canonical_config.parent

    return new_logger
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

local M = {}

function M.get_logger(name)
    local logger_name = name
    if name == nil or name == "" then
        -- Auto-generate logger name from caller's filename
        local filename, _ = caller_info.get_caller_info(nil, true) -- Use dot notation conversion
        if filename then
            logger_name = filename
        else
            logger_name = "root"
        end
    end

    if _loggers_cache[logger_name] then
        return _loggers_cache[logger_name]
    end

    local parent_logger = nil
    if logger_name ~= "root" then
        local parent_name_end = string.match(logger_name, "(.+)%.[^%.]+$")
        local parent_name
        if parent_name_end then
            parent_name = parent_name_end
        else
            parent_name = "root"
        end
        parent_logger = M.get_logger(parent_name) -- Recursive call
    end

    -- Create logger using config-based approach
    local config = {
        name = logger_name,
        level = core_levels.definition.INFO,
        outputs = {},
        propagate = true,
        parent = parent_logger
    }

    local new_logger = create_logger_from_config(config)
    _loggers_cache[logger_name] = new_logger
    return new_logger
end

--- Creates a logger from a config table (new API for declarative usage)
-- @param config (table) The logger configuration
-- @return table The logger instance
function M.create_logger_from_config(config)
    return create_logger_from_config(config)
end

--- Creates a logger from a declarative config table
-- @param declarative_config (table) The declarative logger configuration
-- @return table The logger instance
function M.logger(declarative_config)
    -- Validate the declarative config
    local valid, err = validate_declarative_config(declarative_config)
    if not valid then
        error("Invalid declarative config: " .. err)
    end

    -- Define default config
    local default_config = {
        name = "root",
        level = "info",
        outputs = {},
        propagate = true
    }

    -- Merge user config with defaults
    local merged_config = merge_configs(declarative_config, default_config)

    -- Convert to canonical format
    local canonical_config = declarative_to_canonical_config(merged_config)

    -- Handle parent logger creation if needed
    if canonical_config.name and canonical_config.name ~= "root" then
        local parent_name_end = string.match(canonical_config.name, "(.+)%.[^%.]+$")
        local parent_name
        if parent_name_end then
            parent_name = parent_name_end
        else
            parent_name = "root"
        end
        canonical_config.parent = M.get_logger(parent_name)
    end

    -- Create the logger
    local new_logger = create_logger_from_config(canonical_config)

    -- Cache the logger if it has a name
    if canonical_config.name then
        _loggers_cache[canonical_config.name] = new_logger
    end

    return new_logger
end

--- Utility functions for config manipulation
M.create_canonical_config = create_canonical_config
M.clone_config = clone_config
M.validate_config = validate_config
M.validate_declarative_config = validate_declarative_config
M.declarative_to_canonical_config = declarative_to_canonical_config
M.merge_configs = merge_configs

-- Export standalone validation functions
M.validate_level = validate_level
M.validate_outputs = validate_outputs
M.validate_output_and_formatter_types = validate_output_and_formatter_types
M.validate_single_output = validate_single_output
M.validate_basic_fields = validate_basic_fields
M.validate_known_keys = validate_known_keys

-- Forward declaration for ingest's call to get_logger
get_logger = M.get_logger --  ignore lowercase-global

function M.reset_cache()
    _loggers_cache = {}
end

return M
