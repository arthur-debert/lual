local ingest = require("lual.ingest")
local core_levels = require("lual.core.levels")
local caller_info = require("lual.core.caller_info")
local config_module = require("lual.config")
local unpack = unpack or table.unpack

local _loggers_cache = {}

-- =============================================================================
-- LOGGER PROTOTYPE
-- =============================================================================

local logger = {}

function logger:debug(message_fmt, ...)
	self:log(core_levels.definition.DEBUG, message_fmt, ...)
end

function logger:info(message_fmt, ...)
	self:log(core_levels.definition.INFO, message_fmt, ...)
end

function logger:warn(message_fmt, ...)
	self:log(core_levels.definition.WARNING, message_fmt, ...)
end

function logger:error(message_fmt, ...)
	self:log(core_levels.definition.ERROR, message_fmt, ...)
end

function logger:critical(message_fmt, ...)
	self:log(core_levels.definition.CRITICAL, message_fmt, ...)
end

function logger:log(level_no, message_fmt, ...)
	if not self:is_enabled_for(level_no) then
		return
	end

	local filename, lineno = caller_info.get_caller_info() -- Automatically find first non-lual file

	local log_record = {
		level_no = level_no,
		level_name = core_levels.get_level_name(level_no),
		message_fmt = message_fmt,
		args = table.pack(...), -- Use table.pack for varargs
		timestamp = os.time(),
		logger_name = self.name,
		source_logger_name = self.name, -- Initially the same as logger_name
		filename = filename,
		lineno = lineno,
	}

	ingest.dispatch_log_event(log_record, get_logger, core_levels.definition) -- Pass get_logger and levels
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
-- CONFIG-BASED LOGGER CREATION
-- =============================================================================

--- Creates a logger from a canonical config table
-- @param config (table) The canonical config
-- @return table The logger instance
function create_logger_from_config(config)
	local valid, err = config_module.validate_canonical_config(config)
	if not valid then
		error("Invalid logger config: " .. err)
	end

	local canonical_config = config_module.create_canonical_config(config)

	-- Create new logger object based on prototype
	local new_logger = {}
	for k, v in pairs(logger) do
		new_logger[k] = v
	end

	new_logger.name = canonical_config.name
	new_logger.level = canonical_config.level
	new_logger.outputs = canonical_config.outputs
	new_logger.propagate = canonical_config.propagate
	new_logger.parent = canonical_config.parent

	return new_logger
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

local M = {}

function M.get_logger(name)
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
		parent_logger = M.get_logger(parent_name) -- Recursive call
	end

	-- Create logger using config-based approach
	local config = {
		name = logger_name,
		level = core_levels.definition.INFO,
		outputs = {},
		propagate = true,
		parent = parent_logger,
	}

	local new_logger = create_logger_from_config(config)
	_loggers_cache[logger_name] = new_logger
	return new_logger
end

--- Creates a logger from a config table (new API for declarative usage)
-- @param config (table) The logger configuration
-- @return table The logger instance
function M.create_logger_from_config(config)
	return create_logger_from_config(config)
end

--- Creates a logger from a declarative config table (supports both standard and shortcut formats)
-- @param input_config (table) The declarative logger configuration
-- @return table The logger instance
function M.logger(input_config)
	-- Define default config
	local default_config = {
		name = "root",
		level = "info",
		outputs = {},
		propagate = true,
	}

	-- Use the config module to process the input config (handles shortcut, declarative, validation, etc.)
	local canonical_config = config_module.process_config(input_config, default_config)

	-- Check if logger already exists in cache
	if canonical_config.name and _loggers_cache[canonical_config.name] then
		return _loggers_cache[canonical_config.name]
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
		canonical_config.parent = M.get_logger(parent_name)
	end

	-- Create the logger
	local new_logger = create_logger_from_config(canonical_config)

	-- Cache the logger if it has a name
	if canonical_config.name then
		_loggers_cache[canonical_config.name] = new_logger
	end

	return new_logger
end

-- Export config module functions for backward compatibility and testing
M.config = config_module

-- Forward declaration for ingest's call to get_logger
get_logger = M.get_logger --  ignore lowercase-global

function M.reset_cache()
	_loggers_cache = {}
end

return M
