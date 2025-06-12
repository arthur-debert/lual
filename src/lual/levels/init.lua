local levels = {}

levels.definition = {
    NOTSET = 0, -- Special level indicating inheritance from parent
    DEBUG = 10,
    INFO = 20,
    WARNING = 30,
    ERROR = 40,
    CRITICAL = 50,
    NONE = 100 -- To disable logging for a specific logger
}

-- Storage for custom levels
local _custom_levels = {}

local _level_names_cache = {} -- Cache for level number to name mapping

-- Helper function to clear level cache when custom levels change
local function clear_level_cache()
    _level_names_cache = {}
end

-- Helper function to get level name from level number
function levels.get_level_name(level_no)
    if _level_names_cache[level_no] then
        return _level_names_cache[level_no]
    end

    -- Check built-in levels first
    for name, number in pairs(levels.definition) do
        if number == level_no then
            _level_names_cache[level_no] = name
            return name
        end
    end

    -- Check custom levels
    for name, number in pairs(_custom_levels) do
        if number == level_no then
            _level_names_cache[level_no] = name:upper()
            return name:upper()
        end
    end

    return "UNKNOWN_LEVEL_NO_" .. tostring(level_no)
end

-- Validates a custom level name
-- Names must be valid lua identifiers in lowercase
function levels.validate_custom_level_name(name)
    if type(name) ~= "string" then
        return false, "Level name must be a string"
    end

    if name == "" then
        return false, "Level name cannot be empty"
    end

    -- Must be lowercase
    if name ~= name:lower() then
        return false, "Level name must be lowercase"
    end

    -- Must be a valid Lua identifier
    if not name:match("^[a-z_][a-z0-9_]*$") then
        return false, "Level name must be a valid Lua identifier (lowercase letters, numbers, and underscores only)"
    end

    -- Cannot start with underscore (reserved)
    if name:sub(1, 1) == "_" then
        return false, "Level names starting with '_' are reserved"
    end

    return true
end

-- Validates a custom level value
-- Must be between DEBUG and ERROR levels, not same as existing level
-- exclude_current_customs: if true, don't check against current custom levels (used during set_custom_levels)
function levels.validate_custom_level_value(value, exclude_current_customs)
    if type(value) ~= "number" then
        return false, "Level value must be a number"
    end

    if value ~= math.floor(value) then
        return false, "Level value must be an integer"
    end

    -- Must be between DEBUG and ERROR (exclusive)
    if value <= levels.definition.DEBUG or value >= levels.definition.ERROR then
        return false,
            "Level value must be between " .. (levels.definition.DEBUG + 1) .. " and " .. (levels.definition.ERROR - 1)
    end

    -- Cannot be same as existing built-in level
    for _, builtin_value in pairs(levels.definition) do
        if value == builtin_value then
            return false, "Level value " .. value .. " conflicts with a built-in level"
        end
    end

    -- Cannot be same as existing custom level (unless we're updating customs)
    if not exclude_current_customs then
        for _, custom_value in pairs(_custom_levels) do
            if value == custom_value then
                return false, "Level value " .. value .. " conflicts with an existing custom level"
            end
        end
    end

    return true
end

-- Sets custom levels (replaces all existing custom levels)
function levels.set_custom_levels(custom_levels_table)
    if type(custom_levels_table) ~= "table" then
        error("Custom levels must be a table")
    end

    -- Use the same schema validation that the config system uses (comprehensive and declarative)
    local schemer = require("lual.utils.schemer")
    local levels_schema_module = require("lual.levels.schema")

    -- Wrap data to match schema structure
    local errors = schemer.validate({ custom_levels = custom_levels_table },
        levels_schema_module.get_custom_levels_schema())
    if errors then
        -- Extract specific error code and convert to appropriate error message
        if errors.fields and errors.fields.custom_levels then
            local field_error = errors.fields.custom_levels[1]
            if field_error then
                local error_code = field_error[1]
                local error_message = field_error[2]

                -- Convert schema error codes to domain-specific error messages for backward compatibility
                if error_code == "DUPLICATE_VALUE" then
                    -- Extract duplicate value from the message
                    local duplicate_value = error_message:match("duplicate value '([^']+)'")
                    local locations = error_message:match("locations '([^']+)' and '([^']+)'")
                    error("Duplicate level value " .. duplicate_value .. " for levels '" .. locations .. "'")
                elseif error_code == "CUSTOM_VALIDATION_FAILED" then
                    -- For custom validation, extract the actual validation error
                    local actual_error = error_message:match("Field 'custom_levels': (.+)")
                    error(actual_error or error_message)
                end

                error(error_message)
            end
        end
        error("Invalid custom levels: " .. errors.error)
    end

    -- Clear existing custom levels
    _custom_levels = {}

    -- Set new custom levels
    for name, value in pairs(custom_levels_table) do
        _custom_levels[name] = value
    end

    -- Clear cache since levels changed
    clear_level_cache()
end

-- Gets all levels (built-in + custom)
function levels.get_all_levels()
    local all_levels = {}

    -- Add built-in levels
    for name, value in pairs(levels.definition) do
        all_levels[name] = value
    end

    -- Add custom levels (with uppercase names for consistency)
    for name, value in pairs(_custom_levels) do
        all_levels[name:upper()] = value
    end

    return all_levels
end

-- Gets only custom levels
function levels.get_custom_levels()
    local custom_copy = {}
    for name, value in pairs(_custom_levels) do
        custom_copy[name] = value
    end
    return custom_copy
end

-- Checks if a level name is a custom level
function levels.is_custom_level(name)
    if type(name) ~= "string" then
        return false
    end
    return _custom_levels[name:lower()] ~= nil
end

-- Gets the level number for a custom level name
function levels.get_custom_level_value(name)
    if type(name) ~= "string" then
        return nil
    end
    return _custom_levels[name:lower()]
end

-- Gets information about a custom level by name
-- @param name string The custom level name
-- @return string, number The level name (uppercase) and number, or nil if not found
function levels.get_custom_level(name)
    if type(name) ~= "string" then
        return nil, nil
    end

    local level_no = _custom_levels[name:lower()]
    if level_no then
        return name:upper(), level_no
    end

    return nil, nil
end

-- Gets level information by name (from both built-in and custom levels)
-- @param name string The level name
-- @return string, number The level name (uppercase) and number, or nil if not found
function levels.get_level_by_name(name)
    if type(name) ~= "string" then
        return nil, nil
    end

    -- First check built-in levels (case insensitive but return uppercase)
    local upper_name = name:upper()
    if levels.definition[upper_name] then
        return upper_name, levels.definition[upper_name]
    end

    -- Then check custom levels
    local level_no = _custom_levels[name:lower()]
    if level_no then
        return name:upper(), level_no
    end

    return nil, nil
end

return levels
