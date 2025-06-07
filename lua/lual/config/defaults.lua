--- Configuration Defaults
-- This module handles default configuration setup and initialization

local core_levels = require("lua.lual.levels")

local M = {}

-- Default configuration
local _default_config = {
    level = core_levels.definition.WARNING,
    propagate = true,
    pipelines = {}
}

--- Helper function to create default pipelines
-- @return table Array of default pipeline configurations
local function create_default_pipelines()
    -- Return a default pipeline with console output and text presenter
    return {
        {
            level = core_levels.definition.WARNING,
            outputs = {
                {
                    func = require("lual.pipeline.outputs.console"),
                    config = {}
                }
            },
            presenter = require("lual.pipeline.presenters.text")()
        }
    }
end

--- Initialize default configuration with console output pipeline
-- @return table The initialized default configuration
function M.create_default_config()
    -- Initialize with the console output pipeline
    local console = require("lual.pipeline.outputs.console")
    local text_presenter = require("lual.pipeline.presenters.text")
    local component_utils = require("lual.utils.component")

    -- Create a copy of default config
    local config = {}
    for key, value in pairs(_default_config) do
        config[key] = value
    end

    -- Create a normalized output
    local normalized_output = component_utils.normalize_component(
        console,
        component_utils.DISPATCHER_DEFAULTS
    )

    -- Create a default pipeline with the normalized output
    local default_pipeline = {
        level = core_levels.definition.WARNING,
        outputs = { normalized_output },
        presenter = text_presenter()
    }

    -- Add it to the config
    config.pipelines = { default_pipeline }

    return config
end

--- Get base default configuration (without pipelines initialized)
-- @return table The base default configuration
function M.get_base_defaults()
    local config = {}
    for key, value in pairs(_default_config) do
        config[key] = value
    end
    return config
end

return M
