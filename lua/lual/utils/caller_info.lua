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
-- @param use_dot_notation (boolean) If true, convert filename to dot notation (default: false)
-- @return string, number, string|nil The filename, line number, and lua_path, or nil if unavailable
function caller_info.get_caller_info(start_level, use_dot_notation)
    start_level = start_level or 2 -- Start at 2 to skip this function itself
    use_dot_notation = use_dot_notation or false

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

    -- Convert to dot notation if requested
    if use_dot_notation and filename then
        -- Remove file extension only for .lua files
        filename = string.gsub(filename, "%.lua$", "")
        -- Convert path separators to dots
        filename = string.gsub(filename, "[/\\]", ".")
        -- Remove leading dots (like ./ or ../) but preserve meaningful path components
        filename = string.gsub(filename, "^%.+", "")
        -- If empty after processing, return nil to indicate failure
        if filename == "" then
            filename = nil
        end
    end

    return filename, current_line, lua_path
end

--- Clears the module name cache in fname_to_module
function caller_info.clear_cache()
    fname_to_module.clear_cache()
end

--- Gets the current cache size from fname_to_module
-- @return number The number of cached entries
function caller_info.get_cache_size()
    return fname_to_module.get_cache_size()
end

--- Converts a file path to a Lua-style module identifier (wrapper for fname_to_module)
-- @param file_path (string) The file path to convert
-- @return string|nil The module name if found, nil otherwise
function caller_info.get_module_path(file_path)
    return fname_to_module.get_module_path(file_path)
end

--- Parse package.path templates (delegated to fname_to_module)
-- @param file_path (string) The file path to convert
-- @param template (string) The package.path template
-- @return string|nil The module name if matched, nil otherwise
function caller_info.match_template(file_path, template)
    -- This is now just a compatibility wrapper around fname_to_module
    return fname_to_module._match_template(file_path, template)
end

--- Generates a fallback module name (delegated to fname_to_module)
-- @param abs_filepath (string) The absolute file path
-- @return string|nil A fallback module name or nil
function caller_info.generate_fallback_name(abs_filepath)
    -- This is now just a compatibility wrapper around fname_to_module
    return fname_to_module._generate_fallback_name(abs_filepath)
end

--- Parses package.path into individual templates (no longer needed, kept for compatibility)
-- @return table Array of path templates from package.path
function caller_info.parse_package_path()
    -- Create a compatibility wrapper that returns the same format as before
    local path_templates = {}
    local package_path = package.path or ""
    for template in package_path:gmatch("[^;]+") do
        if template and template ~= "" and template ~= ";;" then
            table.insert(path_templates, template)
        end
    end
    return path_templates
end

return caller_info
