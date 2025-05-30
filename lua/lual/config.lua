local core_levels = require("lual.core.levels")
local constants = require("lual.config.constants")

local M = {}

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
        dispatchers = config.dispatchers or {},
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
        if type(v) == "table" and k == "dispatchers" then
            -- Deep clone dispatchers array
            cloned[k] = {}
            for i, dispatcher in ipairs(v) do
                cloned[k][i] = {
                    dispatcher_func = dispatcher.dispatcher_func,
                    presenter_func = dispatcher.presenter_func,
                    transformer_funcs = dispatcher.transformer_funcs or {},
                    dispatcher_config = dispatcher.dispatcher_config or {}
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

--- Validates a level value (string or number)
-- @param level The level to validate
-- @return boolean, string True if valid, or false with error message
local function validate_level(level)
    if level == nil then
        return true -- Level is optional
    end

    if type(level) == "string" then
        local valid, err = constants.validate_against_constants(level, constants.VALID_LEVEL_STRINGS, true, "string")
        if not valid then
            return false, err
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

    local valid, err = constants.validate_against_constants(timezone, constants.VALID_TIMEZONES, true, "string")
    if not valid then
        return false, err
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

    if config.dispatchers and type(config.dispatchers) ~= "table" then
        return false, "Config.dispatchers must be a table"
    end

    if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
        return false, "Config.propagate must be a boolean"
    end

    -- Validate timezone
    local valid, err = validate_timezone(config.timezone)
    if not valid then
        return false, err
    end

    -- Validate dispatchers structure
    if config.dispatchers then
        for i, dispatcher in ipairs(config.dispatchers) do
            if type(dispatcher) ~= "table" then
                return false, "Each dispatcher must be a table"
            end
            if not dispatcher.dispatcher_func or type(dispatcher.dispatcher_func) ~= "function" then
                return false, "Each dispatcher must have an dispatcher_func function"
            end
            if not dispatcher.presenter_func or (type(dispatcher.presenter_func) ~= "function" and not (type(dispatcher.presenter_func) == "table" and getmetatable(dispatcher.presenter_func) and getmetatable(dispatcher.presenter_func).__call)) then
                return false, "Each dispatcher must have a presenter_func function"
            end
            -- Validate transformer_funcs if present
            if dispatcher.transformer_funcs then
                if type(dispatcher.transformer_funcs) ~= "table" then
                    return false, "Each dispatcher transformer_funcs must be a table"
                end
                for j, transformer_func in ipairs(dispatcher.transformer_funcs) do
                    if not (type(transformer_func) == "function" or (type(transformer_func) == "table" and getmetatable(transformer_func) and getmetatable(transformer_func).__call)) then
                        return false, "Each transformer must be a function or callable table"
                    end
                end
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
-- CONFIG SYNTAX PROCESSING
-- =============================================================================

--- Detects conflicting configuration syntax and normalizes convenience syntax to full syntax
-- @param config table The input config to check and normalize
-- @return table The normalized config (convenience syntax converted to full syntax)
local function normalize_config_format(config)
    local has_shortcut_fields = config.dispatcher ~= nil or config.presenter ~= nil
    local has_full_fields = config.dispatchers ~= nil

    -- Error if both shortcut and full form are used
    if has_shortcut_fields and has_full_fields then
        error("Invalid config: Cannot mix shortcut fields (dispatcher/presenter) with full form (dispatchers). " ..
            "Use either: {dispatcher='console', presenter='text'} OR {dispatchers={{type='console', presenter='text'}}}")
    end

    -- If convenience syntax is used, transform to full syntax
    if has_shortcut_fields then
        -- Validate unknown keys for convenience syntax
        local valid_shortcut_keys = {
            name = true,
            level = true,
            dispatcher = true,
            presenter = true,
            propagate = true,
            timezone = true,
            path = true,
            stream = true
        }

        for key, _ in pairs(config) do
            if not valid_shortcut_keys[key] then
                error("Invalid shortcut config: Unknown shortcut config key: " .. tostring(key))
            end
        end

        -- Validate that we have the required shortcut fields
        if not config.dispatcher then
            error("Invalid shortcut config: Shortcut config must have an 'dispatcher' field")
        end
        if not config.presenter then
            error("Invalid shortcut config: Shortcut config must have a 'presenter' field")
        end

        -- Validate dispatcher type
        local valid, err = constants.validate_against_constants(config.dispatcher, constants.VALID_dispatcher_TYPES,
            false, "string")
        if not valid then
            error("Invalid shortcut config: " .. err)
        end

        -- Validate presenter type
        valid, err = constants.validate_against_constants(config.presenter, constants.VALID_PRESENTER_TYPES, false,
            "string")
        if not valid then
            error("Invalid shortcut config: " .. err)
        end

        -- Validate basic fields for convenience syntax
        if config.name ~= nil and type(config.name) ~= "string" then
            error("Invalid shortcut config: Config.name must be a string")
        end

        if config.propagate ~= nil and type(config.propagate) ~= "boolean" then
            error("Invalid shortcut config: Config.propagate must be a boolean")
        end

        if config.timezone ~= nil then
            local valid, err = constants.validate_against_constants(config.timezone, constants.VALID_TIMEZONES, false,
                "string")
            if not valid then
                error("Invalid shortcut config: " .. err)
            end
        end

        if config.level ~= nil then
            if type(config.level) == "string" then
                local valid, err = constants.validate_against_constants(config.level, constants.VALID_LEVEL_STRINGS,
                    false, "string")
                if not valid then
                    error("Invalid shortcut config: " .. err)
                end
            elseif type(config.level) ~= "number" then
                error("Invalid shortcut config: Level must be a string or number")
            end
        end

        -- Create a copy of the config for transformation
        local normalized_config = {}
        for k, v in pairs(config) do
            normalized_config[k] = v
        end

        -- Transform convenience syntax to full syntax
        local dispatcher_entry = {
            type = normalized_config.dispatcher,
            presenter = normalized_config.presenter
        }

        -- Add type-specific fields with validation
        if normalized_config.dispatcher == "file" then
            if not normalized_config.path or type(normalized_config.path) ~= "string" then
                error("Invalid shortcut config: File dispatcher must have a 'path' string field")
            end
            dispatcher_entry.path = normalized_config.path
        elseif normalized_config.dispatcher == "console" and normalized_config.stream then
            -- Validate stream is a file handle (not string/number/boolean)
            if type(normalized_config.stream) == "string" or type(normalized_config.stream) == "number" or type(normalized_config.stream) == "boolean" then
                error("Invalid shortcut config: Console dispatcher 'stream' field must be a file handle")
            end
            dispatcher_entry.stream = normalized_config.stream
        end

        -- Create dispatchers array
        normalized_config.dispatchers = { dispatcher_entry }

        -- Remove shortcut fields
        normalized_config.dispatcher = nil
        normalized_config.presenter = nil
        normalized_config.path = nil
        normalized_config.stream = nil

        return normalized_config
    end

    -- Already in full syntax or no dispatcher config, return as-is
    return config
end

--- Validates a single transformer configuration
-- @param transformer table The transformer config to validate
-- @param index number The index of the transformer (for error messages)
-- @return boolean, string True if valid, or false with error message
local function validate_single_transformer(transformer, index)
    if type(transformer) ~= "table" then
        return false, "Each transformer must be a table"
    end

    if not transformer.type or type(transformer.type) ~= "string" then
        return false, "Each transformer must have a 'type' string field"
    end

    -- Validate known transformer types
    local valid, err = constants.validate_against_constants(transformer.type, constants.VALID_TRANSFORMER_TYPES, false,
        "string")
    if not valid then
        return false, err
    end

    return true
end

--- Validates a single dispatcher configuration
-- @param dispatcher table The dispatcher config to validate
-- @param index number The index of the dispatcher (for error messages)
-- @return boolean, string True if valid, or false with error message
local function validate_single_dispatcher(dispatcher, index)
    if type(dispatcher) ~= "table" then
        return false, "Each dispatcher must be a table"
    end

    if not dispatcher.type or type(dispatcher.type) ~= "string" then
        return false, "Each dispatcher must have a 'type' string field"
    end

    if not dispatcher.presenter or type(dispatcher.presenter) ~= "string" then
        return false, "Each dispatcher must have a 'presenter' string field"
    end

    -- Validate known dispatcher types
    local valid, err = constants.validate_against_constants(dispatcher.type, constants.VALID_dispatcher_TYPES, false,
        "string")
    if not valid then
        return false, err
    end

    -- Validate known presenter types
    valid, err = constants.validate_against_constants(dispatcher.presenter, constants.VALID_PRESENTER_TYPES, false,
        "string")
    if not valid then
        return false, err
    end

    -- Validate transformers if present
    if dispatcher.transformers then
        if type(dispatcher.transformers) ~= "table" then
            return false, "Dispatcher transformers must be a table"
        end

        for i, transformer in ipairs(dispatcher.transformers) do
            local valid, err = validate_single_transformer(transformer, i)
            if not valid then
                return false, err
            end
        end
    end

    -- Validate type-specific fields
    if dispatcher.type == "file" then
        if not dispatcher.path or type(dispatcher.path) ~= "string" then
            return false, "File dispatcher must have a 'path' string field"
        end
    end

    if dispatcher.type == "console" and dispatcher.stream then
        -- stream should be a file handle, but we can't easily validate that
        -- so we'll just check it's not a string/number/boolean
        if type(dispatcher.stream) == "string" or type(dispatcher.stream) == "number" or type(dispatcher.stream) == "boolean" then
            return false, "Console dispatcher 'stream' field must be a file handle"
        end
    end

    return true
end

--- Validates dispatchers array
-- @param dispatchers table The dispatchers array to validate
-- @return boolean, string True if valid, or false with error message
local function validate_dispatchers(dispatchers)
    if dispatchers == nil then
        return true -- dispatchers is optional
    end

    if type(dispatchers) ~= "table" then
        return false, "Config.dispatchers must be a table"
    end

    for i, dispatcher in ipairs(dispatchers) do
        local valid, err = validate_single_dispatcher(dispatcher, i)
        if not valid then
            return false, err
        end
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
        dispatchers = true,
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

--- Validates a config table (with string-based types)
-- @param config (table) The config to validate
-- @return boolean, string True if valid, or false with error message
local function validate_config(config)
    if type(config) ~= "table" then
        return false, "Config must be a table"
    end

    -- Check if this appears to be convenience syntax before normalization
    local was_shortcut_format = config.dispatcher ~= nil or config.presenter ~= nil

    -- Normalize config first (handle convenience syntax)
    local normalized_config
    local ok, result = pcall(normalize_config_format, config)
    if not ok then
        return false, result -- Return the error message from normalization
    end
    normalized_config = result

    -- Determine error prefix based on original format
    local error_prefix = was_shortcut_format and "Invalid shortcut config: " or "Invalid config: "

    -- Helper function to add prefix only if not already present
    local function add_error_prefix(err)
        -- Strip any existing "Invalid config: " prefix first
        local cleaned_err = string.gsub(err, "^Invalid config: ", "")

        if was_shortcut_format then
            return "Invalid shortcut config: " .. cleaned_err
        else
            return "Invalid config: " .. cleaned_err
        end
    end

    -- Validate unknown keys
    local valid, err = validate_known_keys(normalized_config)
    if not valid then
        return false, add_error_prefix(err)
    end

    -- Validate basic fields
    valid, err = validate_basic_fields(normalized_config)
    if not valid then
        return false, add_error_prefix(err)
    end

    -- Validate level
    valid, err = validate_level(normalized_config.level)
    if not valid then
        return false, add_error_prefix(err)
    end

    -- Validate dispatchers
    valid, err = validate_dispatchers(normalized_config.dispatchers)
    if not valid then
        return false, add_error_prefix(err)
    end

    return true
end

--- Converts a config to canonical config format
-- @param user_config (table) The user config
-- @return table The canonical config
local function config_to_canonical(user_config)
    local all_dispatchers = require("lual.dispatchers.init")
    local all_presenters = require("lual.presenters.init")
    local all_transformers = require("lual.transformers.init")

    local canonical = {
        name = user_config.name,
        propagate = user_config.propagate,
        timezone = user_config.timezone,
        dispatchers = {}
    }

    -- Convert level string to number if needed
    if user_config.level then
        if type(user_config.level) == "string" then
            local level_map = {
                debug = core_levels.definition.DEBUG,
                info = core_levels.definition.INFO,
                warning = core_levels.definition.WARNING,
                error = core_levels.definition.ERROR,
                critical = core_levels.definition.CRITICAL,
                none = core_levels.definition.NONE
            }
            canonical.level = level_map[string.lower(user_config.level)]
        else
            canonical.level = user_config.level
        end
    end

    -- Convert dispatchers to canonical format
    if user_config.dispatchers then
        for _, dispatcher_config in ipairs(user_config.dispatchers) do
            local dispatcher_func
            local presenter_func
            local transformer_funcs = {}
            local config = {}

            -- Get dispatcher function
            if dispatcher_config.type == "console" then
                dispatcher_func = all_dispatchers.console_dispatcher
                if dispatcher_config.stream then
                    config.stream = dispatcher_config.stream
                end
            elseif dispatcher_config.type == "file" then
                -- File dispatcher is a factory, so we need to call it with config to get the actual function
                local file_factory = all_dispatchers.file_dispatcher
                config.path = dispatcher_config.path
                -- Copy other file-specific config
                for k, v in pairs(dispatcher_config) do
                    if k ~= "type" and k ~= "presenter" and k ~= "path" and k ~= "transformers" then
                        config[k] = v
                    end
                end
                dispatcher_func = file_factory(config)
            end

            -- Get presenter function
            if dispatcher_config.presenter == "text" then
                presenter_func = all_presenters.text()
            elseif dispatcher_config.presenter == "color" then
                presenter_func = all_presenters.color()
            elseif dispatcher_config.presenter == "json" then
                presenter_func = all_presenters.json()
            end

            -- Get transformer functions
            if dispatcher_config.transformers then
                for _, transformer_config in ipairs(dispatcher_config.transformers) do
                    if transformer_config.type == "noop" then
                        table.insert(transformer_funcs, all_transformers.noop_transformer())
                    end
                end
            end

            table.insert(canonical.dispatchers, {
                dispatcher_func = dispatcher_func,
                presenter_func = presenter_func,
                transformer_funcs = transformer_funcs,
                dispatcher_config = config
            })
        end
    end

    return canonical
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--- Main function to process any config syntax and return a validated canonical config
-- @param input_config table The input config (can be convenience or full syntax)
-- @param default_config table Optional default config to merge with
-- @return table The validated canonical config
function M.process_config(input_config, default_config)
    local final_config = input_config

    -- Check if this uses convenience syntax and transform it if needed
    final_config = normalize_config_format(final_config)

    -- Validate the config
    local valid, err = validate_config(final_config)
    if not valid then
        error(err) -- Don't add prefix here since validate_config already handles it
    end

    -- Apply defaults if provided
    if default_config then
        final_config = merge_configs(final_config, default_config)
    end

    -- Convert to canonical format
    local canonical_config = config_to_canonical(final_config)

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

--- Validates a config
-- @param config table The config to validate
-- @return boolean, string True if valid, or false with error message
function M.validate_config(config)
    return validate_config(config)
end

--- Converts config to canonical format
-- @param config table The config
-- @return table The canonical config
function M.config_to_canonical(config)
    return config_to_canonical(config)
end

--- Merges configs with user config taking precedence
-- @param user_config table The user config
-- @param default_config table The default config
-- @return table The merged config
function M.merge_configs(user_config, default_config)
    return merge_configs(user_config, default_config)
end

--- Detects if a config uses convenience syntax (compatibility function)
-- @param config table The config to check
-- @return boolean True if convenience syntax
function M.is_shortcut_config(config)
    return config.dispatcher ~= nil or config.presenter ~= nil
end

--- Transforms convenience syntax to full syntax (compatibility function)
-- @param config table The config using convenience syntax
-- @return table The config in full syntax
function M.shortcut_to_full_config(config)
    local normalized = normalize_config_format(config)
    return normalized
end

return M
