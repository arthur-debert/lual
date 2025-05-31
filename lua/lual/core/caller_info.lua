--- Module for extracting caller information from the debug stack.
-- This provides utilities to get filename and line number information
-- for logging purposes.

local caller_info = {}

--- Converts a file path to a Lua-style module identifier using configured module roots
-- @param filepath (string) The file path to convert
-- @param module_roots (table|nil) Array of root directory paths to try
-- @return string|nil The module name if found, nil otherwise
local function convert_filepath_to_module_id(filepath, module_roots)
    if not filepath or type(filepath) ~= "string" then
        return nil
    end

    -- Remove leading @ if present (from debug.getinfo)
    if filepath:sub(1, 1) == "@" then
        filepath = filepath:sub(2)
    end

    -- Normalize path separators to '/' for consistent processing
    filepath = filepath:gsub("\\", "/")

    local relative_path_found = nil
    local longest_match_len = 0

    -- Try to match against configured module roots
    if type(module_roots) == "table" then
        for _, root_orig in ipairs(module_roots) do
            if type(root_orig) == "string" then
                local root = root_orig:gsub("\\", "/") -- Normalize root separator
                -- Ensure root path ends with a slash for correct prefix matching
                if #root > 0 and root:sub(-1) ~= "/" then
                    root = root .. "/"
                end

                if filepath:sub(1, #root) == root then
                    if #root > longest_match_len then
                        relative_path_found = filepath:sub(#root + 1)
                        longest_match_len = #root
                    end
                end
            end
        end
    end

    local module_id_base
    if relative_path_found then
        module_id_base = relative_path_found
    else
        -- Fallback: No configured root matched, use relative to current working directory
        -- Strip leading slash to avoid ".Users.etc" style names
        if filepath:sub(1, 1) == "/" then
            module_id_base = filepath:sub(2)
        else
            module_id_base = filepath
        end
    end

    -- Remove .lua extension
    local module_id = module_id_base:gsub("%.lua$", "")

    -- Handle init.lua special case - convert foo/bar/init to foo.bar
    module_id = module_id:gsub("/init$", "")
    module_id = module_id:gsub("\\init$", "")

    -- Replace path separators with dots
    module_id = module_id:gsub("[/\\]", ".")

    return module_id ~= "" and module_id or nil
end

--- Gets default module roots for the current environment
-- @return table Array of root directory paths
local function get_default_module_roots()
    local roots = {}

    -- Add current working directory
    table.insert(roots, ".")

    -- Add common Lua source directories relative to current working directory
    table.insert(roots, "./src")
    table.insert(roots, "./lib")
    table.insert(roots, "./lua")

    return roots
end

--- Checks if a filename is part of the lual logging infrastructure.
-- With the new module root approach, we only filter based on path, not filename.
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

--- Extracts caller information from the debug stack.
-- Automatically finds the first stack level that's not part of the lual logging infrastructure.
-- @param start_level (number) The stack level to start searching from (default: 2, to skip this function)
-- @param use_dot_notation (boolean) If true, convert filename to dot notation for logger names (default: false)
-- @return string, number, string|nil The filename (possibly converted to dot notation), line number, and lua_path, or nil values if unavailable
function caller_info.get_caller_info(start_level, use_dot_notation)
    start_level = start_level or 2 -- Start at 2 to skip this function itself
    use_dot_notation = use_dot_notation or false

    -- Search up the stack to find the first non-lual file
    for level = start_level, 10 do -- Limit search to 10 levels to avoid infinite loops
        local info = debug.getinfo(level, "Sl")
        if not info then
            -- Reached end of stack
            return nil, nil, nil
        end

        local filename = info.short_src

        -- Skip special debug entries like "(tail call)", "[C]", etc.
        -- But allow nil filenames to be processed (they might be valid edge cases)
        if filename == "(tail call)" or filename == "[C]" then
            -- Continue to next iteration
        else
            if not is_lual_internal_file(filename) then
                -- Found a non-lual file, this is our caller
                local original_filename = filename
                local lua_path = nil

                -- Attempt to get the Lua module path
                lua_path = convert_filepath_to_module_id(original_filename, get_default_module_roots())

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

                return filename, info.currentline, lua_path
            end
        end
    end

    -- If we get here, we couldn't find a non-lual file (shouldn't happen in normal usage)
    return nil, nil, nil
end

return caller_info
