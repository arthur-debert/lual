-- Constants module for lual logger
-- This module centralizes all constants used across the lual library

-- Note: For direct execution with 'lua', use require("lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local core_levels = require("lual.levels")
local all_outputs = require("lual.pipelines.outputs.init")
local all_presenters = require("lual.pipelines.presenters.init")
local all_transformers = require("lual.pipelines.transformers.init")
local async_writer = require("lual.async")

local M = {}

-- Level constants
M.levels = core_levels.definition
M.notset = core_levels.definition.NOTSET
M.debug = core_levels.definition.DEBUG
M.info = core_levels.definition.INFO
M.warning = core_levels.definition.WARNING
M.error = core_levels.definition.ERROR
M.critical = core_levels.definition.CRITICAL
M.none = core_levels.definition.NONE

-- Add LEVELS mapping for external validation and use
M.LEVELS = {
    notset = core_levels.definition.NOTSET,
    debug = core_levels.definition.DEBUG,
    info = core_levels.definition.INFO,
    warning = core_levels.definition.WARNING,
    error = core_levels.definition.ERROR,
    critical = core_levels.definition.CRITICAL,
    none = core_levels.definition.NONE
}

-- Output constants (function references for config API)
M.outputs = all_outputs
M.console = all_outputs.console
M.file = all_outputs.file

-- Presenter constants (function references for config API)
M.presenters = all_presenters
M.text = all_presenters.text
M.color = all_presenters.color
M.json = all_presenters.json

-- Transformer constants
M.transformers = all_transformers
M.noop = all_transformers.noop

-- Timezone constants (still use strings for these)
M.local_time = "local"
M.utc = "utc"

-- Add the pipelines namespace to match the directory rename
M.pipelines = {
    outputs = all_outputs,
    presenters = all_presenters,
    transformers = all_transformers
}

-- Async constants
M.async = {
    -- Backend constants
    coroutines = "coroutines",
    libuv = "libuv",

    -- Overflow strategy constants
    drop_oldest = "drop_oldest",
    drop_newest = "drop_newest",
    block = "block",

    -- Default configuration
    defaults = {
        enabled = false,
        backend = "coroutines",
        batch_size = 50,
        flush_interval = 1.0,
        max_queue_size = 10000,
        overflow_strategy = "drop_oldest"
    },

    -- Statistics function
    get_stats = function()
        return async_writer.get_stats()
    end
}

return M
