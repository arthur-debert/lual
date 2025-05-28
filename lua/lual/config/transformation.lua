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
        outputs = config.outputs or {},
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
    return config.output ~= nil or config.formatter ~= nil
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
        outputs = {}
    }

    -- Create the single output entry
    local output_entry = {
        type = validated_config.output,
        formatter = validated_config.formatter
    }

    -- Add type-specific fields
    if validated_config.output == "file" then
        output_entry.path = validated_config.path
    elseif validated_config.output == "console" and validated_config.stream then
        output_entry.stream = validated_config.stream
    end

    table.insert(declarative_config.outputs, output_entry)

    return declarative_config
end

--- Converts a declarative config to canonical config format
-- @param declarative_config (table) The declarative config
-- @return table The canonical config
function M.declarative_to_canonical_config(declarative_config)
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
                local text_factory = all_formatters.text
                formatter_func = text_factory()
            elseif output_config.formatter == "color" then
                local color_factory = all_formatters.color
                -- Extract color-specific config if present
                local formatter_config = {}
                if output_config.level_colors then
                    formatter_config.level_colors = output_config.level_colors
                end
                formatter_func = color_factory(formatter_config)
            elseif output_config.formatter == "json" then
                local json_factory = all_formatters.json
                -- Extract json-specific config if present
                local formatter_config = {}
                if output_config.pretty ~= nil then
                    formatter_config.pretty = output_config.pretty
                end
                formatter_func = json_factory(formatter_config)
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

return M
