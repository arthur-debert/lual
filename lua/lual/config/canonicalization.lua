--- Configuration canonicalization utilities
-- This module converts validated configs to runtime (canonical) format

local schema = require("lual.config.schema")
local table_utils = require("lual.utils.table")

local M = {}

-- =============================================================================
-- CANONICALIZATION FUNCTIONS
-- =============================================================================



--- Creates a canonical config with default values
-- @param config table Optional initial config values
-- @return table The canonical config
local function create_canonical_config(config)
    config = config or {}

    return {
        name = config.name or schema.DEFAULTS.name,
        level = config.level or schema.DEFAULTS.level,
        dispatchers = config.dispatchers or schema.DEFAULTS.dispatchers,
        propagate = config.propagate ~= false, -- Default to true unless explicitly false
        parent = config.parent or nil,
        timezone = config.timezone or schema.DEFAULTS.timezone
    }
end

--- Gets dispatcher function by type
-- @param dispatcher_type string The dispatcher type
-- @param config table Type-specific configuration
-- @return function The dispatcher function
local function get_dispatcher_function(dispatcher_type, config)
    local all_dispatchers = require("lual.dispatchers.init")

    if dispatcher_type == "console" then
        return all_dispatchers.console_dispatcher
    elseif dispatcher_type == "file" then
        -- File dispatcher is a callable module (factory pattern)
        local file_dispatcher = all_dispatchers.file_dispatcher
        local success, result = pcall(file_dispatcher, config)
        if success and type(result) == "function" then
            return result
        else
            error("Failed to create file dispatcher: " .. tostring(result))
        end
    end

    error("Unknown dispatcher type: " .. tostring(dispatcher_type))
end

--- Gets presenter function by type
-- @param presenter_type string The presenter type
-- @return function The presenter function
local function get_presenter_function(presenter_type)
    local all_presenters = require("lual.presenters.init")

    if presenter_type == "text" then
        return all_presenters.text()
    elseif presenter_type == "color" then
        return all_presenters.color()
    elseif presenter_type == "json" then
        return all_presenters.json()
    end

    error("Unknown presenter type: " .. tostring(presenter_type))
end

--- Gets transformer functions by type
-- @param transformers table Array of transformer configs
-- @return table Array of transformer functions
local function get_transformer_functions(transformers)
    if not transformers then
        return {}
    end

    local all_transformers = require("lual.transformers.init")
    local transformer_funcs = {}

    for _, transformer_config in ipairs(transformers) do
        if transformer_config.type == "noop" then
            table.insert(transformer_funcs, all_transformers.noop_transformer())
        else
            error("Unknown transformer type: " .. tostring(transformer_config.type))
        end
    end

    return transformer_funcs
end

--- Prepares type-specific config using mapping system
-- @param dispatcher_config table The dispatcher configuration
-- @return table The type-specific configuration
local function prepare_type_specific_config(dispatcher_config)
    local normalization = require("lual.config.normalization")
    local mappings = normalization.get_mappings()

    local dispatcher_type = dispatcher_config.type
    local type_config = {}

    -- Get type-specific field mappings
    local type_mappings = mappings.type_specific[dispatcher_type]
    if type_mappings then
        for convenience_field, mapping_config in pairs(type_mappings) do
            local target_field = mapping_config.target
            if dispatcher_config[target_field] ~= nil then
                type_config[target_field] = dispatcher_config[target_field]
            end
        end
    end

    -- Copy any other dispatcher-specific config (excluding core fields)
    local core_fields = { type = true, presenter = true, transformers = true }
    for k, v in pairs(dispatcher_config) do
        if not core_fields[k] and type_config[k] == nil then
            type_config[k] = v
        end
    end

    return type_config
end

--- Converts dispatchers config to canonical format
-- @param dispatchers_config table The dispatchers configuration
-- @return table Array of canonical dispatcher objects
local function convert_dispatchers_to_canonical(dispatchers_config)
    if not dispatchers_config then
        return {}
    end

    local canonical_dispatchers = {}

    for _, dispatcher_config in ipairs(dispatchers_config) do
        local dispatcher_type = dispatcher_config.type
        local presenter_type = dispatcher_config.presenter

        -- Prepare type-specific config using mapping system
        local type_config = prepare_type_specific_config(dispatcher_config)

        -- Get function instances
        local dispatcher_func = get_dispatcher_function(dispatcher_type, type_config)
        local presenter_func = get_presenter_function(presenter_type)
        local transformer_funcs = get_transformer_functions(dispatcher_config.transformers)

        table.insert(canonical_dispatchers, {
            dispatcher_func = dispatcher_func,
            presenter_func = presenter_func,
            transformer_funcs = transformer_funcs,
            dispatcher_config = type_config
        })
    end

    return canonical_dispatchers
end

--- Merges user config with default config using table diffing, with user config taking precedence
-- @param user_config table The user's partial config
-- @param default_config table The default config
-- @return table The merged config
local function merge_configs(user_config, default_config)
    -- Deep copy the default config to avoid modifying the original
    local merged = table_utils.deepcopy(default_config)

    -- Use table diff to understand what the user is changing/adding
    local diff = table_utils.key_diff(default_config, user_config)

    -- Apply user overrides for existing keys that changed
    for key, change_info in pairs(diff.changed_keys) do
        merged[key] = change_info.new_value
    end

    -- Add new keys that user provided (not in defaults)
    for _, key in ipairs(diff.added_keys) do
        merged[key] = user_config[key]
    end

    -- Keys that were removed (in default but not in user config) remain from default
    -- This preserves default values for unspecified user keys

    return merged
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--- Converts a validated config to canonical format
-- @param user_config table The validated user config
-- @return table The canonical config
function M.config_to_canonical(user_config)
    local canonical = {
        name = user_config.name,
        propagate = user_config.propagate,
        timezone = user_config.timezone
    }

    -- Convert level string to number if needed
    if user_config.level then
        canonical.level = schema.convert_level(user_config.level)
    end

    -- Convert dispatchers to canonical format
    canonical.dispatchers = convert_dispatchers_to_canonical(user_config.dispatchers)

    return canonical
end

--- Creates a canonical config with defaults
-- @param config table Optional initial config
-- @return table The canonical config
function M.create_canonical_config(config)
    return create_canonical_config(config)
end

--- Merges configs with user config taking precedence
-- @param user_config table The user config
-- @param default_config table The default config
-- @return table The merged config
function M.merge_configs(user_config, default_config)
    return merge_configs(user_config, default_config)
end

--- Formats config differences for readable debugging output
-- @param user_config table The user config
-- @param default_config table The default config
-- @return string Formatted diff information for debugging
function M.format_config_diff(user_config, default_config)
    local diff = table_utils.key_diff(default_config, user_config)

    local output = {}
    output[#output + 1] = "Config Diff Analysis:"

    if #diff.added_keys > 0 then
        output[#output + 1] = "\nAdded keys (new in user config):"
        for _, key in ipairs(diff.added_keys) do
            output[#output + 1] = "  + " .. key .. " = " .. tostring(user_config[key])
        end
    end

    if #diff.removed_keys > 0 then
        output[#output + 1] = "\nRemoved keys (missing from user config):"
        for _, key in ipairs(diff.removed_keys) do
            output[#output + 1] = "  - " .. key .. " = " .. tostring(default_config[key])
        end
    end

    if next(diff.changed_keys) then
        output[#output + 1] = "\nChanged keys:"
        for key, change_info in pairs(diff.changed_keys) do
            output[#output + 1] = "  ~ " .. key .. ":"
            output[#output + 1] = "    old: " .. tostring(change_info.old_value)
            output[#output + 1] = "    new: " .. tostring(change_info.new_value)
        end
    end

    if #diff.added_keys == 0 and #diff.removed_keys == 0 and not next(diff.changed_keys) then
        output[#output + 1] = "\nNo differences found."
    end

    return table.concat(output, "\n")
end

--- Validates that user config doesn't contain extraneous keys beyond schema
-- @param user_config table The user config to validate
-- @param schema_keys table Table of valid schema keys (set format)
-- @return boolean, table True if valid, or false with details about extra keys
function M.validate_no_extraneous_keys(user_config, schema_keys)
    -- Create a template with all valid keys set to placeholder values (since nil removes keys)
    local schema_template = {}
    for key, _ in pairs(schema_keys) do
        schema_template[key] = true
    end

    local diff = table_utils.key_diff(schema_template, user_config)

    if #diff.added_keys > 0 then
        return false, {
            extraneous_keys = diff.added_keys,
            message = "Config contains extraneous keys: " .. table.concat(diff.added_keys, ", ")
        }
    end

    return true, nil
end

return M
