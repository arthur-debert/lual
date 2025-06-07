--- output that writes log messages to a file with rotation.
--
-- On initialization, this output handler will:
-- 1. Rotate existing log files, keeping up to 5 backups.
--    - Example: app.log -> app.log.1, app.log.1 -> app.log.2, ..., app.log.4 -> app.log.5
--    - app.log.5 will be deleted if it exists before rotation.
-- 2. Open the main log file fresh for new entries.
--
-- @usage
-- local lual = require("lual")
-- local file_output_factory = require("lual.pipeline.outputs.file_output")
--
-- local logger = lual.logger("my_app")
-- logger:add_output(file_output_factory({ path = "app.log" }), lual.levels.INFO)
-- logger:info("This will be written to app.log after rotation.")

local MAX_BACKUPS = 5

--- Checks if a file exists by attempting to open it for reading.
-- @param path (string) The file path to check.
-- @return boolean True if file exists, false otherwise.
local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

--- Generates a list of file system operations needed for log rotation.
-- This function returns a list of commands without executing them,
-- allowing for validation and testing.
-- @param log_path (string) The path to the main log file.
-- @return table A list of operations, each with type, source, and target.
local function generate_rotation_commands(log_path)
    local commands = {}

    -- Step 1: Check if oldest backup exists and mark for removal
    local oldest_backup_path = log_path .. "." .. MAX_BACKUPS
    if file_exists(oldest_backup_path) then
        table.insert(commands, {
            type = "remove",
            target = oldest_backup_path
        })
    end

    -- Step 2: Generate shift commands for existing backups (from .4 down to .1)
    for i = MAX_BACKUPS - 1, 1, -1 do
        local current_backup_path = log_path .. "." .. i
        local next_backup_path = log_path .. "." .. (i + 1)

        if file_exists(current_backup_path) then
            table.insert(commands, {
                type = "rename",
                source = current_backup_path,
                target = next_backup_path
            })
        end
    end

    -- Step 3: Generate command to rotate current log to .1
    if file_exists(log_path) then
        local first_backup_path = log_path .. ".1"
        table.insert(commands, {
            type = "rename",
            source = log_path,
            target = first_backup_path
        })
    end

    return commands
end

--- Validates that a list of rotation commands is correct.
-- @param commands (table) List of commands from generate_rotation_commands.
-- @param log_path (string) The main log file path for validation context.
-- @return boolean, string True if valid, false and error message if invalid.
local function validate_rotation_commands(commands, log_path)
    local seen_targets = {}
    local backup_pattern = "^" .. log_path:gsub("([%.%-%+%*%?%[%]%^%$%(%)%%])", "%%%1") .. "%.%d+$"

    for i, cmd in ipairs(commands) do
        -- Validate command structure
        if type(cmd) ~= "table" then
            return false, string.format("Command %d is not a table", i)
        end

        if not cmd.type or (cmd.type ~= "remove" and cmd.type ~= "rename") then
            return false, string.format("Command %d has invalid type: %s", i, tostring(cmd.type))
        end

        -- Validate remove commands
        if cmd.type == "remove" then
            if not cmd.target then
                return false, string.format("Remove command %d missing target", i)
            end
            if not string.match(cmd.target, backup_pattern) then
                return false, string.format("Remove command %d target not a backup file: %s", i, cmd.target)
            end
        end

        -- Validate rename commands
        if cmd.type == "rename" then
            if not cmd.source or not cmd.target then
                return false, string.format("Rename command %d missing source or target", i)
            end

            -- Check for duplicate targets
            if seen_targets[cmd.target] then
                return false, string.format("Duplicate target in command %d: %s", i, cmd.target)
            end
            seen_targets[cmd.target] = true

            -- Validate that we're not overwriting the main log with a backup
            if cmd.target == log_path and cmd.source ~= log_path then
                return false, string.format("Command %d would overwrite main log with backup", i)
            end
        end
    end

    return true
end

--- Executes a list of validated rotation commands.
-- @param commands (table) List of commands from generate_rotation_commands.
local function execute_rotation_commands(commands)
    for _, cmd in ipairs(commands) do
        if cmd.type == "remove" then
            local removed, err_remove = os.remove(cmd.target)
            if not removed then
                local msg = string.format("lual: Failed to remove '%s': %s\n", cmd.target,
                    tostring(err_remove or "unknown error"))
                io.stderr:write(msg)
            end
        elseif cmd.type == "rename" then
            local renamed, err_rename = os.rename(cmd.source, cmd.target)
            if not renamed then
                local msg = string.format("lual: Failed to rename '%s' to '%s': %s\n",
                    cmd.source, cmd.target, tostring(err_rename or "unknown error"))
                io.stderr:write(msg)
            end
        end
    end
end

--- Performs log rotation by generating, validating, and executing commands.
-- @param log_path (string) The path to the main log file.
local function rotate_logs(log_path)
    local commands = generate_rotation_commands(log_path)
    local valid, err = validate_rotation_commands(commands, log_path)

    if not valid then
        io.stderr:write(string.format("lual: Invalid rotation commands: %s\n", tostring(err)))
        return
    end

    execute_rotation_commands(commands)
end

--- Creates a file output handler with log rotation.
-- @param config (table) Configuration for the file output.
--   Must contain `path` (string) - the path to the main log file.
-- @return function(record) The actual log writing function.
local function file_output_factory(config)
    if not config or not config.path or type(config.path) ~= "string" then
        io.stderr:write("lual: file_output_factory requires config.path (string)\n")
        return function() end -- Return a no-op function on error
    end

    local log_path = config.path

    -- Perform rotation when the factory is called
    rotate_logs(log_path)

    -- Return the function that will handle individual log records
    return function(record)
        local file, err_open = io.open(log_path, "a") -- Open in append mode for ongoing writes
        if not file then
            local msg = string.format("lual: Error opening log '%s' for append: %s\n", log_path,
                tostring(err_open or "unknown error"))
            io.stderr:write(msg)
            return
        end

        local success, err_write = pcall(function()
            -- Handle both string messages and record tables
            local message
            if type(record) == "string" then
                message = record
            else
                -- First try the message field for backward compatibility
                message = record.message or record.presented_message or record.formatted_message or record.message_fmt
                -- Add timestamp and level if available
                if record.timestamp and record.level_name then
                    local timestamp = os.date("%Y-%m-%d %H:%M:%S", record.timestamp)
                    message = string.format("%s %s [%s] %s",
                        timestamp,
                        record.level_name,
                        record.logger_name,
                        message)
                end
            end

            file:write(message)
            file:write("\n") -- Add a newline after the message for better readability
            file:flush()     -- Ensure the message is written immediately
            file:close()     -- Close the file after writing
        end)

        if not success then
            io.stderr:write(string.format("lual: Error writing to log file '%s': %s\n", log_path,
                tostring(err_write or "unknown error")))
        end
    end
end

-- Create module table with exported functions for testing
local module = setmetatable({
    _generate_rotation_commands = generate_rotation_commands,
    _validate_rotation_commands = validate_rotation_commands,
    _execute_rotation_commands = execute_rotation_commands
}, {
    __call = function(_, config)
        return file_output_factory(config)
    end
})

return module
