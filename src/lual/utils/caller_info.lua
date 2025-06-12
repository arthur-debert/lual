--- Module for extracting caller information (filename, line number, and derived module path)
-- from the Lua debug stack. This is primarily used by logging libraries to identify
-- the source of a log message.
--
-- This module focuses on two main tasks:
-- 1. Stack traversal to find the appropriate caller frame
-- 2. Leveraging the fname_to_module utility to convert file paths to module names

local fname_to_module = require("lual.utils.fname_to_module")
local caller_info = {}

--- Checks if a filename is part of the lual logging infrastructure.
-- This filtering ensures we don't identify internal logging functions as the caller
-- @param filename (string) The filename to check
-- @return boolean True if the file is part of lual logging infrastructure
local function is_lual_internal_file(filename)
    if not filename then
        return false
    end

    -- Only filter based on lual internal directory paths
    -- This allows init.lua files in user code to be processed normally
    local is_internal_path = string.find(filename, "/lual/") or
        string.find(filename, "\\lual\\") or
        string.find(filename, "%.luarocks/") or
        string.find(filename, "\\.luarocks\\")

    return is_internal_path or false
end

--- Finds the first stack frame that is eligible to be considered the caller.
-- An eligible frame is one that is not a special debug entry (like "[C]" or
-- "(tail call)") and not part of the lual logging library itself.
-- @param start_level (number) The stack level to start searching from.
-- @return table|nil The debug info table for the eligible frame, or nil if not found.
local function find_first_eligible_caller_frame(start_level)
    for level = start_level, 10 do -- Limit search to 10 levels to avoid infinite loops
        local info = debug.getinfo(level, "Sl")
        if not info then
            -- Reached end of stack
            return nil
        end

        local source_path = info.source or info.short_src

        -- Check for special debug entries that should be skipped
        local is_special_entry = source_path == "(tail call)" or
            source_path == "=(tail call)" or
            source_path == "[C]"

        -- Skip if special entry or internal to the lual library
        if not is_special_entry and not is_lual_internal_file(source_path) then
            -- If we reached here, this frame is eligible
            return info
        end
        -- Otherwise, continue to the next iteration of the loop
    end
    return nil -- No eligible frame found within the search depth
end

--- Extracts caller information from the debug stack.
-- Automatically finds the first stack level that's not part of the lual logging infrastructure.
-- Uses the fname_to_module utility for module path discovery.
-- @param start_level (number) The stack level to start searching from (default: 2)
-- @return string, number, string|nil The filename, line number, and lua_path, or nil if unavailable
function caller_info.get_caller_info(start_level)
    start_level = start_level or 2 -- Start at 2 to skip this function itself

    local eligible_frame_info = find_first_eligible_caller_frame(start_level)

    if not eligible_frame_info then
        return nil, nil, nil
    end

    -- Process the information from the eligible frame
    local source_path = eligible_frame_info.source or eligible_frame_info.short_src
    local filename = source_path
    local current_line = eligible_frame_info.currentline

    -- Attempt to get the Lua module path using fname_to_module
    local lua_path = fname_to_module.get_module_path(source_path)

    -- Clean the filename for display purposes
    if filename and string.sub(filename, 1, 1) == "@" then
        filename = string.sub(filename, 2)
    end

    -- Handle empty filename case - return as-is for backward compatibility
    if filename == "" then
        return filename, current_line, lua_path
    end

    return filename, current_line, lua_path
end

return caller_info
