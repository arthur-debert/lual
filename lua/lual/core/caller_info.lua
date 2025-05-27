--- Module for extracting caller information from the debug stack.
-- This provides utilities to get filename and line number information
-- for logging purposes.

local caller_info = {}

--- Checks if a filename is part of the lual logging infrastructure.
-- @param filename (string) The filename to check
-- @return boolean True if the file is part of lual logging infrastructure
local function is_lual_internal_file(filename)
    if not filename then
        return false
    end

    -- Remove path and @ prefix for comparison
    local basename = filename
    if string.sub(basename, 1, 1) == "@" then
        basename = string.sub(basename, 2)
    end

    -- Extract just the filename part (remove directory path)
    basename = string.match(basename, "([^/\\]+)$") or basename

    -- Check if it's a lual internal file
    return string.find(basename, "lual", 1, true) ~= nil or
        basename == "caller_info.lua" or
        basename == "logger_class.lua" or
        basename == "ingest.lua"
end

--- Extracts caller information from the debug stack.
-- Automatically finds the first stack level that's not part of the lual logging infrastructure.
-- @param start_level (number) The stack level to start searching from (default: 2, to skip this function)
-- @param use_dot_notation (boolean) If true, convert filename to dot notation for logger names (default: false)
-- @return string, number The filename (possibly converted to dot notation) and line number, or nil values if unavailable
function caller_info.get_caller_info(start_level, use_dot_notation)
    start_level = start_level or 2 -- Start at 2 to skip this function itself
    use_dot_notation = use_dot_notation or false

    -- Search up the stack to find the first non-lual file
    for level = start_level, 10 do -- Limit search to 10 levels to avoid infinite loops
        local info = debug.getinfo(level, "Sl")
        if not info then
            -- Reached end of stack
            return nil, nil
        end

        local filename = info.short_src
        if not is_lual_internal_file(filename) then
            -- Found a non-lual file, this is our caller
            if filename and string.sub(filename, 1, 1) == "@" then
                filename = string.sub(filename, 2)
            end

            -- Convert to dot notation if requested
            if use_dot_notation and filename then
                -- Remove file extension
                filename = string.gsub(filename, "%.lua$", "")
                -- Convert path separators to dots
                filename = string.gsub(filename, "[/\\]", ".")
                -- Remove leading dots
                filename = string.gsub(filename, "^%.+", "")
                -- If empty after processing, return nil to indicate failure
                if filename == "" then
                    filename = nil
                end
            end

            return filename, info.currentline
        end
    end

    -- If we get here, we couldn't find a non-lual file (shouldn't happen in normal usage)
    return nil, nil
end

return caller_info
