local core_levels = require("lual.core.levels")

local M = {}

-- =============================================================================
-- CONSTANTS
-- =============================================================================

-- Valid output types
local VALID_OUTPUT_TYPES = {
    console = true,
    file = true
}

-- Valid formatter types
local VALID_FORMATTER_TYPES = {
    text = true,
    color = true,
    json = true
}

-- =============================================================================
-- CANONICAL CONFIG SCHEMA
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
        parent = config.parent or nil,
        timezone = config.timezone or "local"  -- Default to local time
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
-- VALIDATION FUNCTIONS
-- =============================================================================

--- Validates output and formatter types
-- @param output_type string The output type to validate
-- @param formatter_type string The formatter type to validate
-- @return boolean, string True if valid, or false with error message
local function validate_output_formatter_types(output_type, formatter_type)
    -- Validate known output types
    if not VALID_OUTPUT_TYPES[output_type] then
        return false, "Unknown output type: " .. output_type .. ". Valid types are: console, file"
    end

    -- Validate known formatter types
    if not VALID_FORMATTER_TYPES[formatter_type] then
        return false, "Unknown formatter type: " .. formatter_type .. ". Valid types are: color, json, text"
    end

    return true
end

--- Validates a level value (string or number)
-- @param level The level to validate
-- @return boolean, string True if valid, or false with error message
local function validate_level(level)
    if level == nil then
        return true -- Level is optional
    end

    if type(level) == "string" then
        local valid_levels = {
            debug = true,
            info = true,
            warning = true,
            error = true,
            critical = true,
            none = true
        }
        if not valid_levels[string.lower(level)] then
            return false,
                "Invalid level string: " .. level .. ". Valid levels are: critical, debug, error, info, none, warning"
        end
    elseif type(level) == "number" then
        -- Allow numeric levels
    else
        return false, "Level must be a string or number"
    end

    return true
end

--- Validates a timezone value
-- @param timezone The timezone to validate
-- @return boolean, string True if valid, or false with error message
local function validate_timezone(timezone)
    if timezone == nil then
        return true -- Timezone is optional
    end

    if type(timezone) ~= "string" then
        return false, "Timezone must be a string"
    end

    local valid_timezones = {
        ["local"] = true,
        utc = true
    }

    if not valid_timezones[string.lower(timezone)] then
        return false, "Invalid timezone: " .. timezone .. ". Valid timezones are: local, utc"
    end

    return true
end

--- Validates a canonical config table
-- @param config (table) The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_canonical_config(config)
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

    -- Validate timezone
    local valid, err = validate_timezone(config.timezone)
    if not valid then
        return false, err
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

--- Validates basic config fields (name, propagate, timezone)
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_basic_fields(config)
    if config.name and type(config.name) ~= "string" then
        return false, "Config.name must be a string"
    end

    if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
        return false, "Config.propagate must be a boolean"
    end

    -- Validate timezone
    local valid, err = validate_timezone(config.timezone)
    if not valid then
        return false, err
    end

    return true
end

-- =============================================================================
-- SHORTCUT API FUNCTIONS
-- =============================================================================

--- Detects if a config uses the shortcut declarative format
-- @param config table The config to check
-- @return boolean True if it's a shortcut format
local function is_shortcut_config(config)
    if not config or type(config) ~= "table" then
        return false
    end
    return config.output ~= nil or config.formatter ~= nil
end

--- Validates shortcut config fields
-- @param config table The shortcut config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_shortcut_fields(config)
    -- Check for required fields in shortcut format
    if not config.output then
        return false, "Shortcut config must have an 'output' field"
    end

    if not config.formatter then
        return false, "Shortcut config must have a 'formatter' field"
    end

    -- Validate output type
    if type(config.output) ~= "string" then
        return false, "Shortcut config 'output' field must be a string"
    end

    -- Validate formatter type
    if type(config.formatter) ~= "string" then
        return false, "Shortcut config 'formatter' field must be a string"
    end
    -- Validate output and formatter types
    local valid, err = validate_output_formatter_types(config.output, config.formatter)
    if not valid then
        return false, err
    end

    -- Validate file-specific requirements
    if config.output == "file" then
        if not config.path or type(config.path) ~= "string" then
            return false, "File output in shortcut config must have a 'path' string field"
        end
    end

    -- Validate console-specific fields
    if config.output == "console" and config.stream then
        if type(config.stream) == "string" or type(config.stream) == "number" or type(config.stream) == "boolean" then
            return false, "Console output 'stream' field must be a file handle"
        end
    end

    return true
end

--- Validates that shortcut config doesn't contain unknown keys
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_shortcut_known_keys(config)
    local valid_keys = {
        name = true,
        level = true,
        output = true,
        formatter = true,
        propagate = true,
        timezone = true,
        -- File-specific fields
        path = true,
        -- Console-specific fields
        stream = true
    }

    for key, _ in pairs(config) do
        if not valid_keys[key] then
            return false, "Unknown shortcut config key: " .. tostring(key)
        end
    end

    return true
end

--- Validates a shortcut declarative config table
-- @param config table The shortcut config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_shortcut_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    -- Validate unknown keys
    local valid, err = validate_shortcut_known_keys(config)
    if not valid then
        return false, err
    end

    -- Validate basic fields (name, propagate)
    valid, err = validate_basic_fields(config)
    if not valid then
        return false, err
    end

    -- Validate level
    valid, err = validate_level(config.level)
    if not valid then
        return false, err
    end

    -- Validate shortcut-specific fields
    valid, err = validate_shortcut_fields(config)
    if not valid then
        return false, err
    end

    return true
end

--- Transforms shortcut config to standard declarative config format
-- @param shortcut_config table The shortcut config
-- @return table The standard declarative config
local function shortcut_to_declarative_config(shortcut_config)
    local declarative_config = {
        name = shortcut_config.name,
        level = shortcut_config.level,
        propagate = shortcut_config.propagate,
        timezone = shortcut_config.timezone,
        outputs = {}
    }

    -- Create the single output entry
    local output_entry = {
        type = shortcut_config.output,
        formatter = shortcut_config.formatter
    }

    -- Add type-specific fields
    if shortcut_config.output == "file" then
        output_entry.path = shortcut_config.path
    elseif shortcut_config.output == "console" and shortcut_config.stream then
        output_entry.stream = shortcut_config.stream
    end

    table.insert(declarative_config.outputs, output_entry)

    return declarative_config
end

-- =============================================================================
-- DECLARATIVE API FUNCTIONS
-- =============================================================================

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

    -- Validate known output types
    -- Validate output and formatter types
    local valid, err = validate_output_formatter_types(output.type, output.formatter)
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

--- Validates that declarative config doesn't contain unknown keys
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_declarative_known_keys(config)
    local valid_keys = {
        name = true,
        level = true,
        outputs = true,
        propagate = true,
        timezone = true
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
    local valid, err = validate_declarative_known_keys(config)
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
        timezone = declarative_config.timezone,
        outputs = {}
    }

    -- Convert level string to number if needed
    if declarative_config.level then
        if type(declarative_config.level) == "string" then
            local level_map = {
                debug = core_levels.definition.DEBUG,
                info = core_levels.definition.INFO,
                warning = core_levels.definition.WARNING,
                error = core_levels.definition.ERROR,
                critical = core_levels.definition.CRITICAL,
                none = core_levels.definition.NONE
            }
            canonical.level = level_map[string.lower(declarative_config.level)]
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
            elseif output_config.formatter == "json" then
                formatter_func = all_formatters.json
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

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--- Main function to process any config format and return a validated canonical config
-- @param input_config table The input config (can be shortcut, declarative, or partial canonical)
-- @param default_config table Optional default config to merge with
-- @return table The validated canonical config
function M.process_config(input_config, default_config)
    -- Handle nil or empty input config
    if not input_config then
        input_config = {}
    end

    local final_declarative_config = input_config

    -- Check if this is a shortcut config and transform it if needed
    if is_shortcut_config(input_config) then
        -- Validate the shortcut config
        local valid, err = validate_shortcut_config(input_config)
        if not valid then
            error("Invalid shortcut config: " .. err)
        end

        -- Transform shortcut to standard declarative format
        final_declarative_config = shortcut_to_declarative_config(input_config)
    else
        -- Validate the standard declarative config
        local valid, err = validate_declarative_config(input_config)
        if not valid then
            error("Invalid declarative config: " .. err)
        end
    end

    -- Apply defaults if provided
    if default_config then
        final_declarative_config = merge_configs(final_declarative_config, default_config)
    end

    -- Convert to canonical format
    local canonical_config = declarative_to_canonical_config(final_declarative_config)

    -- Validate the final canonical config
    local valid, err = validate_canonical_config(canonical_config)
    if not valid then
        error("Invalid canonical config: " .. err)
    end

    return canonical_config
end

--- Creates a canonical config with defaults
-- @param config table Optional initial config
-- @return table The canonical config
function M.create_canonical_config(config)
    return create_canonical_config(config)
end

--- Clones a config table
-- @param config table The config to clone
-- @return table The cloned config
function M.clone_config(config)
    return clone_config(config)
end

--- Validates a canonical config
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_canonical_config(config)
    return validate_canonical_config(config)
end

--- Detects if a config is in shortcut format
-- @param config table The config to check
-- @return boolean True if shortcut format
function M.is_shortcut_config(config)
    return is_shortcut_config(config)
end

--- Transforms shortcut config to declarative format
-- @param config table The shortcut config
-- @return table The declarative config
function M.shortcut_to_declarative_config(config)
    return shortcut_to_declarative_config(config)
end

--- Validates a declarative config
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_declarative_config(config)
    return validate_declarative_config(config)
end

--- Converts declarative config to canonical format
-- @param config table The declarative config
-- @return table The canonical config
function M.declarative_to_canonical_config(config)
    return declarative_to_canonical_config(config)
end

--- Merges configs with user config taking precedence
-- @param user_config table The user config
-- @param default_config table The default config
-- @return table The merged config
function M.merge_configs(user_config, default_config)
    return merge_configs(user_config, default_config)
end

return M
