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

--- Converts a file path to a Lua-style module identifier using package.path
-- This implements the core algorithm from the article: reversing require's lookup
-- by matching the file path against package.path templates
-- @param filepath (string) The file path to convert (should be absolute)
-- @return string|nil The module name if found, nil otherwise
local function convert_filepath_to_module_id_via_package_path(filepath)
    if not filepath or type(filepath) ~= "string" then
        return nil
    end

    -- Store original filepath for pattern matching before normalization
    local original_filepath = filepath

    -- Remove leading @ if present (from debug.getinfo().source)
    -- The article specifically mentions this prefix must be stripped
    if filepath:sub(1, 1) == "@" then
        filepath = filepath:sub(2)
        original_filepath = filepath
    end

    -- Check again after removing @ prefix
    if filepath == "" then
        return nil
    end

    -- Convert to absolute, normalized path for reliable matching
    -- The article emphasizes the importance of path canonicalization
    local abs_filepath = to_absolute_path(filepath)

    -- Check cache first to avoid expensive recomputation
    -- The article strongly recommends caching due to performance overhead
    if module_name_cache[abs_filepath] then
        return module_name_cache[abs_filepath]
    end

    -- Get current package.path - this is the source of truth for module loading
    -- The article advocates using package.path instead of hardcoded directories
    local package_path = package.path or ""

    -- Split package.path by semicolons to get individual templates
    -- Each template defines how module names map to file paths
    local path_templates = {}
    for template in package_path:gmatch("[^;]+") do
        if template and template ~= "" then
            table.insert(path_templates, template)
        end
    end

    -- Try to match against each template in package.path
    -- This reverses the process that require() uses to find modules
    for _, template in ipairs(path_templates) do
        -- Skip empty templates or the special ";;" default path marker
        if template == "" or template == ";;" then
            goto continue
        end

        -- Normalize the template path
        template = normalize_path(template)

        -- Find the position of ? in the template
        -- The ? represents where the module name goes
        local question_pos = template:find("?", 1, true)
        if not question_pos then
            goto continue
        end

        -- Split template into prefix and suffix around the ?
        local template_prefix = template:sub(1, question_pos - 1)
        local template_suffix = template:sub(question_pos + 1)

        -- Convert template prefix to absolute path if it's relative
        -- This ensures consistent matching regardless of current directory
        local abs_template_prefix = to_absolute_path(template_prefix)

        -- Check if the file path matches this template structure
        local escaped_prefix = escape_lua_pattern(abs_template_prefix)
        local escaped_suffix = escape_lua_pattern(template_suffix)

        -- Create pattern to capture the module part (what ? represents)
        local pattern = "^" .. escaped_prefix .. "(.-)" .. escaped_suffix .. "$"
        local module_part = abs_filepath:match(pattern)

        if module_part then
            -- Found a match! Convert the captured part to module name
            -- Replace directory separators with dots as per Lua convention
            local module_name = module_part:gsub("[/\\]", ".")

            -- Handle init.lua special case as described in the article
            -- If template was specifically for init.lua (?/init.lua), module_name is correct
            -- If template was general (?.lua) but matched init.lua, strip .init suffix
            if template_suffix == ".lua" and module_name:match("%.init$") then
                module_name = module_name:gsub("%.init$", "")
            end

            -- Remove any leading/trailing dots
            module_name = module_name:gsub("^%.+", ""):gsub("%.+$", "")

            if module_name ~= "" then
                -- Cache the result for future calls
                module_name_cache[abs_filepath] = module_name
                return module_name
            end
        end

        ::continue::
    end

    -- No match found in package.path - use fallback strategy
    -- The article suggests several fallback approaches for this case
    local fallback_name = nil

    -- For empty or very short paths, return nil
    if abs_filepath == "" or abs_filepath == ".lua" then
        module_name_cache[abs_filepath] = nil
        return nil
    end

    -- Try to extract a reasonable name from the file path
    local basename = abs_filepath:match("([^/\\]+)$") or abs_filepath
    if basename then
        -- For non-lua files, use the full path converted to dots
        if not basename:match("%.lua$") then
            local full_path = abs_filepath
            -- Remove leading ./ if present
            full_path = full_path:gsub("^%./", "")
            -- Convert path separators to dots
            fallback_name = full_path:gsub("[/\\]", ".")
        else
            -- For .lua files, try to be smarter about module extraction
            -- Remove .lua extension
            basename = basename:gsub("%.lua$", "")
            -- Handle init.lua case
            if basename == "init" then
                -- Use parent directory name
                local parent = abs_filepath:match("([^/\\]+)[/\\]init%.lua$")
                if parent then
                    fallback_name = parent
                end
            else
                -- Special case: if path is like "./src/module.lua", extract just "module"
                -- This handles common project structures where src/ is a source root
                if original_filepath:match("^%./src/[^/\\]+%.lua$") then
                    -- For "./src/module.lua" pattern, return just the module name
                    fallback_name = basename
                else
                    -- Default case
                    fallback_name = basename
                end
            end
        end
    end

    -- Cache the fallback result (might be nil)
    module_name_cache[abs_filepath] = fallback_name
    return fallback_name
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
            local lua_path = convert_filepath_to_module_id_via_package_path(source_path)

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

return caller_info

