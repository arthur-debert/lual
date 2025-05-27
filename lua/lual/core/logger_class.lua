local ingest = require("lual.ingest")
local core_levels = require("lual.core.levels")
local unpack = unpack or table.unpack

local _loggers_cache = {}

local logger_prototype = {}

function logger_prototype:debug(message_fmt, ...)
    self:log(core_levels.definition.DEBUG, message_fmt, ...)
end

function logger_prototype:info(message_fmt, ...)
    self:log(core_levels.definition.INFO, message_fmt, ...)
end

function logger_prototype:warn(message_fmt, ...)
    self:log(core_levels.definition.WARNING, message_fmt, ...)
end

function logger_prototype:error(message_fmt, ...)
    self:log(core_levels.definition.ERROR, message_fmt, ...)
end

function logger_prototype:critical(message_fmt, ...)
    self:log(core_levels.definition.CRITICAL, message_fmt, ...)
end

function logger_prototype:log(level_no, message_fmt, ...)
    if not self:is_enabled_for(level_no) then
        return
    end

    local info = debug.getinfo(3, "Sl") -- Check stack level carefully
    local filename = info.short_src
    if filename and string.sub(filename, 1, 1) == "@" then
        filename = string.sub(filename, 2)
    end

    local log_record = {
        level_no = level_no,
        level_name = core_levels.get_level_name(level_no),
        message_fmt = message_fmt,
        args = table.pack(...), -- Use table.pack for varargs
        timestamp = os.time(),
        logger_name = self.name,
        source_logger_name = self.name, -- Initially the same as logger_name
        filename = filename,
        lineno = info.currentline
    }

    ingest.dispatch_log_event(log_record, get_logger, core_levels.definition) -- Pass get_logger and levels
end

function logger_prototype:set_level(level)
    self.level = level
end

function logger_prototype:add_output(output_func, formatter_func, output_config)
    table.insert(self.outputs, {
        output_func = output_func,
        formatter_func = formatter_func,
        output_config = output_config or {}
    })
end

function logger_prototype:is_enabled_for(message_level_no)
    if self.level == core_levels.definition.NONE then
        return message_level_no == core_levels.definition.NONE
    end
    return message_level_no >= self.level
end

function logger_prototype:get_effective_outputs()
    local effective_outputs = {}
    local current_logger = self

    while current_logger do
        for _, output_item in ipairs(current_logger.outputs or {}) do
            table.insert(effective_outputs, {
                output_func = output_item.output_func,
                formatter_func = output_item.formatter_func,
                output_config = output_item.output_config,
                owner_logger_name = current_logger.name,
                owner_logger_level = current_logger.level
            })
        end

        if not current_logger.propagate or not current_logger.parent then
            break
        end
        current_logger = current_logger.parent
    end
    return effective_outputs
end

local M = {}

function M.get_logger(name)
    local logger_name = name
    if name == nil or name == "" then
        logger_name = "root"
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

    -- Create new logger object based on prototype
    local new_logger = {}
    for k, v in pairs(logger_prototype) do
        new_logger[k] = v
    end

    new_logger.name = logger_name
    new_logger.level = core_levels.definition.INFO -- Default level
    new_logger.outputs = {}
    new_logger.propagate = true
    new_logger.parent = parent_logger

    _loggers_cache[logger_name] = new_logger
    return new_logger
end

-- Forward declaration for ingest's call to get_logger
get_logger = M.get_logger

function M.reset_cache()
    _loggers_cache = {}
end

return M
