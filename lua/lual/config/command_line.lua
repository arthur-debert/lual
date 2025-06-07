-- Command Line Verbosity Configuration
-- This module handles command-line driven logging level configuration

-- Note: For direct execution with 'lua', use require("lua.lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local core_levels = require("lua.lual.levels")

local M = {}

-- Default mapping of command line flags to log levels
local DEFAULT_MAPPING = {
    v = "warning",
    vv = "info",
    vvv = "debug",
    verbose = "info",
    quiet = "error",
    silent = "critical"
}

-- Validates command_line_verbosity configuration
local function validate(config, full_config)
    if type(config) ~= "table" then
        return false, "command_line_verbosity must be a table"
    end

    -- Validate mapping if provided
    if config.mapping ~= nil then
        if type(config.mapping) ~= "table" then
            return false, "command_line_verbosity.mapping must be a table"
        end

        -- Validate each mapping entry
        for flag, level_name in pairs(config.mapping) do
            if type(flag) ~= "string" then
                return false, "mapping keys must be strings"
            end

            if type(level_name) ~= "string" then
                return false, "level names in mapping must be strings"
            end

            -- Verify level name is valid
            local level_valid, _ = core_levels.get_level_by_name(level_name:upper())
            if not level_valid then
                return false, "unknown level name in mapping: " .. level_name
            end
        end
    end

    -- Validate auto_detect if provided
    if config.auto_detect ~= nil and type(config.auto_detect) ~= "boolean" then
        return false, "auto_detect must be a boolean"
    end

    return true
end

-- Normalizes command_line_verbosity configuration
local function normalize(config)
    local normalized = {}

    -- Use provided mapping or default
    normalized.mapping = config.mapping or DEFAULT_MAPPING

    -- Default auto_detect to true if not specified
    if config.auto_detect == nil then
        normalized.auto_detect = true
    else
        normalized.auto_detect = config.auto_detect
    end

    return normalized
end

-- Applies command_line_verbosity configuration
local function apply(config, current_config)
    current_config.command_line_verbosity = config

    -- If auto_detect is enabled, immediately try to detect and apply CLI verbosity
    if config.auto_detect then
        local detected_level = M.detect_verbosity_from_cli(config.mapping)
        if detected_level then
            current_config.level = detected_level
        end
    end

    return current_config
end

-- Detects verbosity level from command line arguments
-- Returns the numeric level if a match is found, nil otherwise
function M.detect_verbosity_from_cli(mapping)
    -- Get command line arguments (global arg table)
    local args = _G.arg
    if not args or type(args) ~= "table" then
        return nil
    end

    local detected_level = nil

    -- Process all command line arguments
    for _, arg_value in ipairs(args) do
        -- Check for --flag format
        if arg_value:sub(1, 2) == "--" then
            local flag = arg_value:sub(3)

            -- Handle --flag=value format
            local flag_name, flag_value = flag:match("([^=]+)=(.+)")
            if flag_name and flag_value then
                -- Check if flag_value is a valid level name
                local _, level_value = core_levels.get_level_by_name(flag_value:upper())
                if level_value then
                    detected_level = level_value
                end
            else
                -- Check if flag matches a mapping
                local level_name = mapping[flag]
                if level_name then
                    local _, level_value = core_levels.get_level_by_name(level_name:upper())
                    if level_value then
                        detected_level = level_value
                    end
                end
            end
            -- Check for -v, -vv, etc. format
        elseif arg_value:sub(1, 1) == "-" and arg_value:sub(2, 2) ~= "-" then
            local flag = arg_value:sub(2)

            -- Check for concatenated flags (e.g., -vvv)
            if flag:match("^(v+)$") then
                local level_name = mapping[flag]
                if level_name then
                    local _, level_value = core_levels.get_level_by_name(level_name:upper())
                    if level_value then
                        detected_level = level_value
                    end
                end
            else
                -- Check for other single flags
                local level_name = mapping[flag]
                if level_name then
                    local _, level_value = core_levels.get_level_by_name(level_name:upper())
                    if level_value then
                        detected_level = level_value
                    end
                end
            end
        end
    end

    return detected_level
end

-- Expose functions
M.validate = validate
M.normalize = normalize
M.apply = apply
M.detect_verbosity_from_cli = M.detect_verbosity_from_cli
M.DEFAULT_MAPPING = DEFAULT_MAPPING

return M
