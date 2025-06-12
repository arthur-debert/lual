-- Command Line Verbosity Configuration
-- This module handles command-line driven logging level configuration

-- Note: For direct execution with 'lua', use require("lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local core_levels = require("lual.levels")
local schemer = require("lual.utils.schemer")
local command_line_schema_module = require("lual.config.command_line_schema")

local M = {}

-- Validates command_line_verbosity configuration
local function validate(config, full_config)
    if type(config) ~= "table" then
        return false, "command_line_verbosity must be a table"
    end

    -- Use schemer for validation (includes defaults, custom validators, etc.)
    local errors = schemer.validate(config, command_line_schema_module.command_line_schema)
    if errors then
        -- Extract specific error message for backward compatibility with tests
        if errors.fields and errors.fields.mapping and errors.fields.mapping[1] then
            local error_code, error_message = errors.fields.mapping[1][1], errors.fields.mapping[1][2]
            if error_code == "CUSTOM_VALIDATION_FAILED" then
                -- Extract the actual custom error message from the formatted message
                -- Format: "Field 'mapping': actual_message"
                local actual_message = error_message:match("Field 'mapping': (.+)")
                if actual_message then
                    return false, actual_message
                end
            end
        end
        return false, errors.error
    end

    return true
end

-- Normalizes command_line_verbosity configuration using schemer
local function normalize(config)
    -- Schemer validation with defaults applied
    local errors, normalized = schemer.validate(config, command_line_schema_module.command_line_schema)
    if errors then
        -- This should not happen if validate() passed, but handle gracefully
        return config
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
                local level_value_or_name = mapping[flag]
                if level_value_or_name then
                    -- Handle both numeric values (from schemer normalization) and string names
                    if type(level_value_or_name) == "number" then
                        detected_level = level_value_or_name
                    else
                        -- String level name - convert to number
                        local _, level_value = core_levels.get_level_by_name(level_value_or_name:upper())
                        if level_value then
                            detected_level = level_value
                        end
                    end
                end
            end
            -- Check for -v, -vv, etc. format
        elseif arg_value:sub(1, 1) == "-" and arg_value:sub(2, 2) ~= "-" then
            local flag = arg_value:sub(2)

            -- Check for concatenated flags (e.g., -vvv)
            if flag:match("^(v+)$") then
                local level_value_or_name = mapping[flag]
                if level_value_or_name then
                    -- Handle both numeric values (from schemer normalization) and string names
                    if type(level_value_or_name) == "number" then
                        detected_level = level_value_or_name
                    else
                        -- String level name - convert to number
                        local _, level_value = core_levels.get_level_by_name(level_value_or_name:upper())
                        if level_value then
                            detected_level = level_value
                        end
                    end
                end
            else
                -- Check for other single flags
                local level_value_or_name = mapping[flag]
                if level_value_or_name then
                    -- Handle both numeric values (from schemer normalization) and string names
                    if type(level_value_or_name) == "number" then
                        detected_level = level_value_or_name
                    else
                        -- String level name - convert to number
                        local _, level_value = core_levels.get_level_by_name(level_value_or_name:upper())
                        if level_value then
                            detected_level = level_value
                        end
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
M.DEFAULT_MAPPING = command_line_schema_module.DEFAULT_MAPPING

return M
