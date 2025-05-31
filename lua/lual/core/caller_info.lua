--- Module for extracting caller information from the debug stack.
-- This provides utilities to get filename and line number information
-- for logging purposes.
--
-- This implementation follows the recommendations from "Reliable Determination
-- of Calling Module Paths in Lua Logging Libraries" to provide robust
-- module path discovery using Lua's package.path system.

local caller_info = {}

-- Cache for derived module names to avoid expensive recomputation
-- Key: absolute file path, Value: derived module name
-- This is critical for performance as debug.getinfo and path processing
-- can be computationally expensive when called frequently
local module_name_cache = {}

--- Normalizes a file path to use forward slashes and removes redundant components
-- This is a simplified version of path normalization without external dependencies
-- @param path (string) The path to normalize
-- @return string The normalized path
local function normalize_path(path)
    if not path then
        return ""
    end

    -- Convert backslashes to forward slashes for consistent processing
    path = path:gsub("\\", "/")

    -- Remove redundant slashes
    path = path:gsub("//+", "/")

    -- Handle . and .. components (simplified version)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            else
                table.insert(parts, part)
            end
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end

    local result = table.concat(parts, "/")

    -- Preserve leading slash for absolute paths
    if path:sub(1, 1) == "/" then
        result = "/" .. result
    end

    return result
end

--- Converts a relative path to an absolute path
-- This is a simplified implementation without external dependencies
-- @param path (string) The path to convert
-- @return string The absolute path
local function to_absolute_path(path)
    if not path then
        return ""
    end

    -- If already absolute (starts with / or drive letter on Windows), return as-is
    if path:sub(1, 1) == "/" or path:match("^[A-Za-z]:") then
        return normalize_path(path)
    end

    -- For relative paths, we'll use a simple approach since we can't use external libs
    -- In a real implementation, this would use the current working directory
    -- For now, we'll just normalize and return the path as-is
    return normalize_path(path)
end

--- Escapes special Lua pattern characters in a string
-- This is needed when using file paths in Lua patterns for matching
-- @param str (string) The string to escape
-- @return string The escaped string
local function escape_lua_pattern(str)
    return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

--- Parses package.path into individual templates
-- @return table Array of path templates from package.path
local function parse_package_path()
    local package_path = package.path or ""
    local path_templates = {}
    for template in package_path:gmatch("[^;]+") do
        if template and template ~= "" and template ~= ";;" then
            table.insert(path_templates, template)
        end
    end
    return path_templates
end

--- Attempts to match a file path against a single package.path template
-- @param abs_filepath (string) The absolute file path to match
-- @param template (string) The package.path template (e.g., "./?.lua")
-- @return string|nil The extracted module name if matched, nil otherwise
local function match_template(abs_filepath, template)
    -- Normalize the template path
    template = normalize_path(template)

    -- Find the position of ? in the template
    local question_pos = template:find("?", 1, true)
    if not question_pos then
        return nil
    end

    -- Split template into prefix and suffix around the ?
    local template_prefix = template:sub(1, question_pos - 1)
    local template_suffix = template:sub(question_pos + 1)

    -- Convert template prefix to absolute path if it's relative
    local abs_template_prefix = to_absolute_path(template_prefix)

    -- Check if the file path matches this template structure
    local escaped_prefix = escape_lua_pattern(abs_template_prefix)
    local escaped_suffix = escape_lua_pattern(template_suffix)

    -- Create pattern to capture the module part (what ? represents)
    local pattern = "^" .. escaped_prefix .. "(.-)" .. escaped_suffix .. "$"
    local module_part = abs_filepath:match(pattern)

    if module_part then
        -- Convert the captured part to module name
        local module_name = module_part:gsub("[/\\]", ".")

        -- Handle init.lua special case as described in the article
        if template_suffix == ".lua" and module_name:match("%.init$") then
            module_name = module_name:gsub("%.init$", "")
        end

        -- Remove any leading/trailing dots
        module_name = module_name:gsub("^%.+", ""):gsub("%.+$", "")

        if module_name ~= "" then
            return module_name
        end
    end

    return nil
end

--- Tries to match file path against all package.path templates
-- @param abs_filepath (string) The absolute file path
-- @return string|nil The module name if any template matches, nil otherwise
local function try_package_path_matching(abs_filepath)
    local path_templates = parse_package_path()

    for _, template in ipairs(path_templates) do
        local module_name = match_template(abs_filepath, template)
        if module_name then
            return module_name
        end
    end

    return nil
end

--- Generates a fallback module name when package.path matching fails
-- @param abs_filepath (string) The absolute file path
-- @param original_filepath (string) The original file path before normalization
-- @return string|nil A fallback module name or nil
local function generate_fallback_name(abs_filepath, original_filepath)
    -- Note: Early exit cases are now handled in process_path()
    -- This function assumes abs_filepath is a valid, resolvable path

    -- Try to extract a reasonable name from the file path
    local basename = abs_filepath:match("([^/\\]+)$") or abs_filepath
    if not basename then
        return nil
    end

    -- For non-lua files, use the full path converted to dots
    if not basename:match("%.lua$") then
        local full_path = abs_filepath
        -- Remove leading ./ if present
        full_path = full_path:gsub("^%./", "")
        -- Convert path separators to dots
        return full_path:gsub("[/\\]", ".")
    end

    -- For .lua files, try to be smarter about module extraction
    basename = basename:gsub("%.lua$", "")

    -- Handle init.lua case
    if basename == "init" then
        local parent = abs_filepath:match("([^/\\]+)[/\\]init%.lua$")
        if parent then
            return parent
        end
        return nil
    end

    -- Special case: if path is like "./src/module.lua", extract just "module"
    if original_filepath:match("^%./src/[^/\\]+%.lua$") then
        return basename
    end

    -- Default case
    return basename
end

--- Internal function that performs the actual module path discovery
-- This implements the core algorithm from the article: reversing require's lookup
-- @param abs_filepath (string) The normalized absolute file path
-- @param original_filepath (string) The original file path before normalization
-- @return string|nil The module name if found, nil otherwise
local function _get_module_path(abs_filepath, original_filepath)
    -- First try to match against package.path templates
    local module_name = try_package_path_matching(abs_filepath)
    if module_name then
        return module_name
    end

    -- If no package.path match, use fallback strategy
    return generate_fallback_name(abs_filepath, original_filepath)
end

--- Processes and normalizes a file path for module discovery
-- Handles @ prefix removal, empty string checks, and path normalization
-- @param file_path (string) The raw file path to process
-- @return string|nil, string|nil The normalized absolute path and original path, or nil if invalid
local function process_path(file_path)
    -- Verify input parameters
    if not file_path or type(file_path) ~= "string" then
        return nil, nil
    end

    -- Store original filepath for pattern matching before normalization
    local original_filepath = file_path

    -- Remove leading @ if present (from debug.getinfo().source)
    -- The article specifically mentions this prefix must be stripped
    if file_path:sub(1, 1) == "@" then
        file_path = file_path:sub(2)
        original_filepath = file_path
    end

    -- Check for empty strings after @ removal
    if file_path == "" then
        return nil, nil
    end

    -- Early exit for clearly unresolvable paths
    -- These are common debug.getinfo() results that cannot be module paths
    if file_path == "(tail call)" or file_path == "=(tail call)" or
       file_path == "[C]" or file_path == ".lua" then
        return nil, nil
    end

    -- Normalize paths for reliable matching
    -- The article emphasizes the importance of path canonicalization
    local abs_filepath = to_absolute_path(file_path)

    return abs_filepath, original_filepath
end

--- Converts a file path to a Lua-style module identifier using package.path
-- This is the main entry point for module path discovery
-- @param file_path (string) The file path to convert
-- @return string|nil The module name if found, nil otherwise
local function get_module_path(file_path)
    -- Transform path and validate
    local abs_filepath, original_filepath = process_path(file_path)
    if not abs_filepath then
        return nil
    end

    -- Check cache first to avoid expensive recomputation
    -- The article strongly recommends caching due to performance overhead
    if module_name_cache[abs_filepath] then
        return module_name_cache[abs_filepath]
    end

    -- Find the module path using the core algorithm
    local result = _get_module_path(abs_filepath, original_filepath)

    -- Cache the result for future calls
    module_name_cache[abs_filepath] = result
    return result
end

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

--- Extracts caller information from the debug stack.
-- Automatically finds the first stack level that's not part of the lual logging infrastructure.
-- Uses the enhanced module path discovery based on package.path analysis.
-- @param start_level (number) The stack level to start searching from (default: 2)
-- @param use_dot_notation (boolean) If true, convert filename to dot notation (default: false)
-- @return string, number, string|nil The filename, line number, and lua_path, or nil if unavailable
function caller_info.get_caller_info(start_level, use_dot_notation)
    start_level = start_level or 2 -- Start at 2 to skip this function itself
    use_dot_notation = use_dot_notation or false

    -- Search up the stack to find the first non-lual file
    for level = start_level, 10 do -- Limit search to 10 levels to avoid infinite loops
        -- Use "Sl" to get source and line information
        -- The article recommends using .source instead of .short_src for better reliability
        local info = debug.getinfo(level, "Sl")
        if not info then
            -- Reached end of stack
            return nil, nil, nil
        end

        -- Try to get source first (preferred), fall back to short_src for compatibility
        -- The article recommends .source for better path matching reliability
        local source_path = info.source or info.short_src
        local filename = source_path

        -- Skip special debug entries like "(tail call)", "[C]", etc.
        if source_path == "(tail call)" or source_path == "[C]" then
            -- Continue to next iteration (empty branch is intentional)
        elseif not is_lual_internal_file(source_path) then
            -- Found a non-lual file, this is our caller
            -- Attempt to get the Lua module path using the enhanced algorithm
            -- This now uses package.path parsing instead of hardcoded roots
            local lua_path = get_module_path(source_path)

            -- Clean the filename for display purposes
            if filename and string.sub(filename, 1, 1) == "@" then
                filename = string.sub(filename, 2)
            end

            -- Handle empty filename case - return as-is for backward compatibility
            if filename == "" then
                return filename, info.currentline, lua_path
            end

            -- Convert to dot notation if requested
            -- Note: This is separate from lua_path - filename shows the full dot-notation path
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

            return filename, info.currentline, lua_path
        end
    end

    -- If we get here, we couldn't find a non-lual file (shouldn't happen in normal usage)
    return nil, nil, nil
end

--- Clears the module name cache
-- This can be useful for testing or if package.path changes during runtime
function caller_info.clear_cache()
    module_name_cache = {}
end

--- Gets the current cache size (for debugging/monitoring)
-- @return number The number of cached entries
function caller_info.get_cache_size()
    local count = 0
    for _ in pairs(module_name_cache) do
        count = count + 1
    end
    return count
end

--- Converts a file path to a Lua-style module identifier
-- This is the main entry point for module path discovery
-- @param file_path (string) The file path to convert
-- @return string|nil The module name if found, nil otherwise
function caller_info.get_module_path(file_path)
    return get_module_path(file_path)
end

--- Parses package.path into individual templates (exposed for testing)
-- @return table Array of path templates from package.path
function caller_info.parse_package_path()
    return parse_package_path()
end

--- Attempts to match a file path against a single package.path template (exposed for testing)
-- @param abs_filepath (string) The absolute file path to match
-- @param template (string) The package.path template (e.g., "./?.lua")
-- @return string|nil The extracted module name if matched, nil otherwise
function caller_info.match_template(abs_filepath, template)
    return match_template(abs_filepath, template)
end

--- Generates a fallback module name when package.path matching fails (exposed for testing)
-- @param abs_filepath (string) The absolute file path
-- @param original_filepath (string) The original file path before normalization
-- @return string|nil A fallback module name or nil
function caller_info.generate_fallback_name(abs_filepath, original_filepath)
    return generate_fallback_name(abs_filepath, original_filepath)
end

return caller_info

