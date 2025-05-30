--- Configuration canonicalization utilities
-- This module converts validated configs to runtime (canonical) format

local schema = require("lual.config.schema")

local M = {}

-- =============================================================================
-- CANONICALIZATION FUNCTIONS
-- =============================================================================

--- Deep clones a config table, specifically handling dispatchers
-- @param config table The config to clone
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
        -- File dispatcher is a factory, call it with config to get the actual function
        return all_dispatchers.file_dispatcher(config)
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

        -- Prepare type-specific config
        local type_config = {}
        if dispatcher_type == "file" then
            type_config.path = dispatcher_config.path
            -- Copy other file-specific config
            for k, v in pairs(dispatcher_config) do
                if k ~= "type" and k ~= "presenter" and k ~= "transformers" then
                    type_config[k] = v
                end
            end
        elseif dispatcher_type == "console" and dispatcher_config.stream then
            type_config.stream = dispatcher_config.stream
        end

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

--- Merges user config with default config, with user config taking precedence
-- @param user_config table The user's partial config
-- @param default_config table The default config
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

--- Clones a config table
-- @param config table The config to clone
-- @return table The cloned config
function M.clone_config(config)
    return clone_config(config)
end

--- Merges configs with user config taking precedence
-- @param user_config table The user config
-- @param default_config table The default config
-- @return table The merged config
function M.merge_configs(user_config, default_config)
    return merge_configs(user_config, default_config)
end

return M
