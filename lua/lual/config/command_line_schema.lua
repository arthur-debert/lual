--- Command Line Verbosity Configuration Schema
-- Schema definition for command-line driven logging level configuration

local core_levels = require("lual.levels")

local M = {}

-- Helper function to get level names for validation
local function get_level_names()
    local all_levels = core_levels.get_all_levels()
    local names = {}
    for name, _ in pairs(all_levels) do
        table.insert(names, name)
    end
    return names
end

-- Default mapping of command line flags to log levels
M.DEFAULT_MAPPING = {
    v = "warning",
    vv = "info",
    vvv = "debug",
    verbose = "info",
    quiet = "error",
    silent = "critical"
}

-- Custom validator for mapping that uses case insensitive level validation
local function validate_mapping(mapping)
    if type(mapping) ~= "table" then
        return false, "mapping must be a table"
    end

    for flag, level_name in pairs(mapping) do
        if type(flag) ~= "string" then
            return false, "mapping keys must be strings"
        end
        if type(level_name) ~= "string" then
            return false, "level names in mapping must be strings"
        end

        -- Use case insensitive level validation
        local level_names = get_level_names()
        local found = false
        for _, valid_name in ipairs(level_names) do
            if string.lower(valid_name) == string.lower(level_name) then
                found = true
                break
            end
        end

        if not found then
            return false, "unknown level name in mapping: " .. level_name
        end
    end

    return true
end

-- Command line verbosity configuration schema
M.command_line_schema = {
    fields = {
        mapping = {
            type = "table",
            required = false,
            default = M.DEFAULT_MAPPING,
            custom_validator = validate_mapping
        },
        auto_detect = {
            type = "boolean",
            required = false,
            default = true
        }
    }
}

return M
