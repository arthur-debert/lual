local ingest = require("lual.ingest")
local core_levels = require("lual.core.levels")
local caller_info = require("lual.core.caller_info")
local config_module = require("lual.config")

local _loggers_cache = {}
local get_logger                -- Forward-declared for ingest and M.get_logger mutual recursion
local create_logger_from_config -- Forward-declared
local logger = {}               -- Declare the logger prototype table

-- =============================================================================
-- LOGGER PROTOTYPE METHODS
-- =============================================================================

function logger:debug(...)
    self:log(core_levels.definition.DEBUG, ...)
end

function logger:info(...)
    self:log(core_levels.definition.INFO, ...)
end

function logger:warn(...)
    self:log(core_levels.definition.WARNING, ...)
end

function logger:error(...)
    self:log(core_levels.definition.ERROR, ...)
end

function logger:critical(...)
    self:log(core_levels.definition.CRITICAL, ...)
end

-- =============================================================================
-- CONFIG-BASED LOGGER CREATION
-- =============================================================================

--- Creates a logger from a canonical config table
-- @param config (table) The canonical config
-- @return table The logger instance
create_logger_from_config = function(config)
    local valid, err = config_module.validate_canonical_config(config)
    if not valid then
        error("Invalid logger config: " .. err)
    end

    local canonical_config = config_module.create_canonical_config(config)

    -- Create new logger object based on prototype
    local new_logger = {}
    for k, v in pairs(logger) do -- 'logger' now refers to the local prototype
        new_logger[k] = v
    end

    new_logger.name = canonical_config.name
    new_logger.level = canonical_config.level
    new_logger.outputs = canonical_config.outputs
    new_logger.propagate = canonical_config.propagate
    new_logger.parent = canonical_config.parent
    new_logger.timezone = canonical_config.timezone

    return new_logger
end


-- The rest of logger methods are defined on the 'local logger' table

function logger:log(level_no, ...)
    if not self:is_enabled_for(level_no) then
        return
    end

    local filename, lineno = caller_info.get_caller_info()

    local packed_varargs = table.pack(...)
    local msg_fmt_val
    local args_val
    local context_val = nil -- Initialize context as nil

    if packed_varargs.n > 0 and type(packed_varargs[1]) == "table" then
        -- This is Pattern 2: context_table, [message_format_string, ...format_args]
        context_val = packed_varargs[1]
        if packed_varargs.n >= 2 and type(packed_varargs[2]) == "string" then
            msg_fmt_val = packed_varargs[2]
            if packed_varargs.n >= 3 then
                args_val = table.pack(select(3, ...)) -- Args from 3rd element of original '...'
            else
                args_val = table.pack()               -- No further args for formatting
            end
        else
            -- Context only (Pattern 2b), or context + non-string second arg.
            -- message_fmt might be extracted from context_val.msg later if desired.
            msg_fmt_val = nil       -- Or extract from context_val.msg
            args_val = table.pack() -- No args for formatting
            if msg_fmt_val == nil and context_val and context_val.msg and type(context_val.msg) == "string" then
                -- Attempt to extract message_fmt from context.msg for Pattern 2b
                msg_fmt_val = context_val.msg
            end
        end
    else
        -- Pattern 1: String Formatting Only, or no arguments after level_no
        -- The first argument (packed_varargs[1]) is message_fmt, rest are args.
        -- context_val remains nil (as initialized).
        if packed_varargs.n > 0 and type(packed_varargs[1]) == "string" then
            msg_fmt_val = packed_varargs[1]
            if packed_varargs.n >= 2 then
                args_val = table.pack(select(2, ...)) -- Args from 2nd element of original '...'
            else
                args_val = table.pack()               -- No further args for formatting
            end
        elseif packed_varargs.n == 0 then             -- No arguments after level_no
            msg_fmt_val = ""                          -- Default to empty string if no message/context
            args_val = table.pack()
        else                                          -- First argument is not a table and not a string (e.g. a number or boolean)
            -- Treat as a single message to be stringified, no further args.
            msg_fmt_val = tostring(packed_varargs[1])
            args_val = table.pack()
        end
    end

    local log_record = {
        level_no = level_no,
        level_name = core_levels.get_level_name(level_no),
        message_fmt = msg_fmt_val,
        args = args_val,
        context = context_val,               -- Add the new context field
        timestamp = os.time(),
        timezone = self.timezone or "local", -- Add timezone configuration
        logger_name = self.name,
        source_logger_name = self.name,      -- Initially the same as logger_name
        filename = filename,
        lineno = lineno,
    }
    -- Note: 'get_logger' here will refer to the local variable defined at the top
    -- which will be assigned M.get_logger later.
    ingest.dispatch_log_event(log_record, get_logger, core_levels.definition)
end

function logger:set_level(level)
    -- Get current config, modify it, and recreate logger
    local current_config = self:get_config()
    current_config.level = level
    local new_logger = create_logger_from_config(current_config)

    -- Update the cache with the new logger
    _loggers_cache[self.name] = new_logger

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            self[k] = v
        end
    end
end

function logger:add_output(output_func, formatter_func, output_config)
    -- Get current config, modify it, and recreate logger
    local current_config = self:get_config()
    table.insert(current_config.outputs, {
        output_func = output_func,
        formatter_func = formatter_func,
        output_config = output_config or {},
    })
    local new_logger = create_logger_from_config(current_config)

    -- Update the cache with the new logger
    _loggers_cache[self.name] = new_logger

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            self[k] = v
        end
    end
end

function logger:set_propagate(propagate)
    -- Get current config, modify it, and recreate logger
    local current_config = self:get_config()
    current_config.propagate = propagate
    local new_logger = create_logger_from_config(current_config)

    -- Update the cache with the new logger
    _loggers_cache[self.name] = new_logger

    -- Copy new logger properties to self (for existing references)
    for k, v in pairs(new_logger) do
        if k ~= "name" then -- Don't change the name
            self[k] = v
        end
    end
end

function logger:get_config()
    -- Return the current configuration as a canonical config table
    return config_module.create_canonical_config({
        name = self.name,
        level = self.level,
        outputs = self.outputs or {},
        propagate = self.propagate,
        parent = self.parent,
        timezone = self.timezone,
    })
end

function logger:is_enabled_for(message_level_no)
    if self.level == core_levels.definition.NONE then
        return message_level_no == core_levels.definition.NONE
    end
    return message_level_no >= self.level
end

function logger:get_effective_outputs()
    local effective_outputs = {}
    local current_logger = self

    while current_logger do
        for _, output_item in ipairs(current_logger.outputs or {}) do
            table.insert(effective_outputs, {
                output_func = output_item.output_func,
                formatter_func = output_item.formatter_func,
                output_config = output_item.output_config,
                owner_logger_name = current_logger.name,
                owner_logger_level = current_logger.level,
            })
        end

        if not current_logger.propagate or not current_logger.parent then
            break
        end
        current_logger = current_logger.parent
    end
    return effective_outputs
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

local M = {}

function M._get_logger_simple(name)
    local logger_name = name
    if name == nil or name == "" then
        -- Auto-generate logger name from caller's filename
        local filename, _ = caller_info.get_caller_info(nil, true) -- Use dot notation conversion
        if filename then
            logger_name = filename
        else
            logger_name = "root"
        end
    end

    if _loggers_cache[logger_name] then
        return _loggers_cache[logger_name]
    end

    local parent_logger = nil
    if logger_name ~= "root" then
        local parent_name_end = string.match(logger_name, "(.+)%.[^%.]+$")
        local parent_name
        if parent_name_end then
            parent_name = parent_name_end
        else
            parent_name = "root"
        end
        parent_logger = M._get_logger_simple(parent_name) -- Recursive call
    end

    -- Create logger using config-based approach
    local config = {
        name = logger_name,
        level = core_levels.definition.INFO,
        outputs = {},
        propagate = true,
        parent = parent_logger,
        timezone = "local", -- Default to local time
    }

    local new_logger = create_logger_from_config(config)
    _loggers_cache[logger_name] = new_logger
    return new_logger
end

--- Creates a logger from a config table (new API for declarative usage)
-- @param config (table) The logger configuration
-- @return table The logger instance
function M.create_logger_from_config(config)
    return create_logger_from_config(config) -- Calls the local create_logger_from_config
end

--- Creates a logger from a declarative config table (supports both standard and shortcut formats)
-- This is the primary API for creating loggers. Can be called with:
-- 1. No arguments or string name: lual.logger() or lual.logger("name") - simple logger creation
-- 2. Config table: lual.logger({name="app", level="debug", outputs={...}}) - declarative configuration
-- @param input_config (string|table|nil) The logger name or declarative configuration
-- @return table The logger instance
function M.logger(input_config)
    -- Handle simple cases: nil, empty string, or string name
    if input_config == nil or input_config == "" or type(input_config) == "string" then
        return M._get_logger_simple(input_config)
    end

    -- Handle table-based declarative configuration
    if type(input_config) ~= "table" then
        error("logger() expects nil, string, or table argument, got " .. type(input_config))
    end

    -- Define default config
    local default_config = {
        name = "root",
        level = "info",
        outputs = {},
        propagate = true,
        timezone = "local", -- Default to local time
    }

    -- Use the config module to process the input config (handles shortcut, declarative, validation, etc.)
    local canonical_config = config_module.process_config(input_config, default_config)

    -- Check if logger already exists in cache and if its configuration matches
    if canonical_config.name and _loggers_cache[canonical_config.name] then
        local cached_logger = _loggers_cache[canonical_config.name]
        local cached_config = cached_logger:get_config()

        -- Compare key configuration fields to see if we can reuse the cached logger
        if cached_config.level == canonical_config.level and
            cached_config.timezone == canonical_config.timezone and
            cached_config.propagate == canonical_config.propagate then
            -- For outputs, we'll do a simple length check for now
            -- A more sophisticated comparison could be added later if needed
            if #(cached_config.outputs or {}) == #(canonical_config.outputs or {}) then
                return cached_logger
            end
        end
        -- If configuration doesn't match, we'll create a new logger and update the cache
    end

    -- Handle parent logger creation if needed
    if canonical_config.name and canonical_config.name ~= "root" then
        local parent_name_end = string.match(canonical_config.name, "(.+)%.[^%.]+$")
        local parent_name
        if parent_name_end then
            parent_name = parent_name_end
        else
            parent_name = "root"
        end
        canonical_config.parent = M.logger(parent_name)
    end

    -- Create the logger
    local new_logger = create_logger_from_config(canonical_config)

    -- Cache the logger if it has a name
    if canonical_config.name then
        _loggers_cache[canonical_config.name] = new_logger
    end

    return new_logger
end

-- Backward compatibility alias - get_logger points to logger
M.get_logger = M.logger

-- Export config module functions for backward compatibility and testing
M.config = config_module

-- Assign M.logger to the local get_logger variable used by ingest and for mutual recursion.
-- This must be done after M.logger is defined.
get_logger = M.logger

function M.reset_cache()
    _loggers_cache = {}
end

return M
