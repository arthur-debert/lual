--- Configuration transformation functions
-- This module contains all config transformation and manipulation logic

local core_levels = require("lual.core.levels")
local constants = require("lual.config.constants")
local schema = require("lual.schema")

local M = {}

--- Creates a canonical config table with default values
-- @param config (table, optional) Initial config values
-- @return table The canonical config
function M.create_canonical_config(config)
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
function M.clone_config(config)
    local cloned = {}
    for k, v in pairs(config) do
        if type(v) == "table" and k == "dispatchers" then
            -- Deep clone dispatchers array
            cloned[k] = {}
            for i, dispatcher in ipairs(v) do
                cloned[k][i] = {
                    dispatcher_func = dispatcher.dispatcher_func,
                    formatter_func = dispatcher.formatter_func,
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
function M.merge_configs(user_config, default_config)
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

--- Detects if a config uses the shortcut declarative format
-- @param config table The config to check
-- @return boolean True if it's a shortcut format
function M.is_shortcut_config(config)
    if not config or type(config) ~= "table" then
        return false
    end
    return config.dispatcher ~= nil or config.formatter ~= nil
end

--- Transforms shortcut config to standard declarative config format
-- @param shortcut_config table The shortcut config
-- @return table The standard declarative config
function M.shortcut_to_declarative_config(shortcut_config)
    -- Use schema validation instead of manual validation
    local result = schema.validate_shortcut(shortcut_config)

    -- Check for errors and convert to old error format
    if next(result._errors) then
        -- Convert first error to old format (single error string)
        for field, error_msg in pairs(result._errors) do
            if type(error_msg) == "table" then
                -- Handle nested errors
                for sub_field, sub_error in pairs(error_msg) do
                    error("Invalid shortcut config: " .. sub_error)
                end
            else
                error("Invalid shortcut config: " .. error_msg)
            end
        end
    end

    local validated_config = result.data
    local declarative_config = {
        name = validated_config.name,
        level = validated_config.level,
        propagate = validated_config.propagate,
        timezone = validated_config.timezone,
        dispatchers = {}
    }

    -- Create the single dispatcher entry
    local dispatcher_entry = {
        type = validated_config.dispatcher,
        formatter = validated_config.formatter
    }

    -- Add type-specific fields
    if validated_config.dispatcher == "file" then
        dispatcher_entry.path = validated_config.path
    elseif validated_config.dispatcher == "console" and validated_config.stream then
        dispatcher_entry.stream = validated_config.stream
    end

    table.insert(declarative_config.dispatchers, dispatcher_entry)

    return declarative_config
end

--- Converts a declarative config to canonical config format
-- @param declarative_config (table) The declarative config
-- @return table The canonical config
function M.declarative_to_canonical_config(declarative_config)
    local all_dispatchers = require("lua.lual.dispatchers.init")
    local all_formatters = require("lual.formatters.init")

    local canonical = {
        name = declarative_config.name,
        propagate = declarative_config.propagate,
        timezone = declarative_config.timezone,
        dispatchers = {}
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

    -- Convert dispatchers from declarative to canonical format
    if declarative_config.dispatchers then
        for _, dispatcher_config in ipairs(declarative_config.dispatchers) do
            local dispatcher_func
            local formatter_func
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
                    if k ~= "type" and k ~= "formatter" and k ~= "path" then
                        config[k] = v
                    end
                end
                dispatcher_func = file_factory(config)
            end

            -- Get formatter function
            if dispatcher_config.formatter == "text" then
                local text_factory = all_formatters.text
                formatter_func = text_factory()
            elseif dispatcher_config.formatter == "color" then
                local color_factory = all_formatters.color
                -- Extract color-specific config if present
                local formatter_config = {}
                if dispatcher_config.level_colors then
                    formatter_config.level_colors = dispatcher_config.level_colors
                end
                formatter_func = color_factory(formatter_config)
            elseif dispatcher_config.formatter == "json" then
                local json_factory = all_formatters.json
                -- Extract json-specific config if present
                local formatter_config = {}
                if dispatcher_config.pretty ~= nil then
                    formatter_config.pretty = dispatcher_config.pretty
                end
                formatter_func = json_factory(formatter_config)
            end

            table.insert(canonical.dispatchers, {
                dispatcher_func = dispatcher_func,
                formatter_func = formatter_func,
                dispatcher_config = config
            })
        end
    end

    return canonical
end

return M
