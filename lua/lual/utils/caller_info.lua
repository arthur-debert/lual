--- Module for extracting caller information (filename, line number, and derived module path)
-- from the Lua debug stack. This is primarily used by logging libraries to identify
-- the source of a log message.
--
-- Design Philosophy:
-- The core challenge is to reliably determine a Lua-style module path (e.g., "my.module")
-- from a raw file path obtained via `debug.getinfo().source`. Lua itself doesn't
-- inherently track module names with loaded files in a way that's easily queryable
-- for this purpose. This module bridges that gap.
--
-- Strategy:
-- 1. Stack Introspection: It walks the debug stack to find the first relevant call
--    frame outside of the logging library's own internal functions.
-- 2. Path Normalization: Raw source paths (often starting with '@') are cleaned and
--    normalized (e.g., converting backslashes to forward slashes, resolving '.', '..')
--    to ensure consistent processing.
-- 3. Package Path Matching: The primary method for deriving a module name is to
--    match the normalized, absolute file path against the templates in Lua's
--    `package.path`. This mimics Lua's `require()` lookup logic in reverse.
-- 4. Robust Fallbacks: When `package.path` matching is not possible or doesn't yield a
--    result (e.g., for scripts run directly, files outside standard paths, or if
--    `package.path` is misconfigured), several fallback strategies are employed:
--    - Non-.lua files: For executable scripts without a .lua extension, the full
--      normalized path is converted into a dot-separated identifier. This ensures
--      that even non-standard Lua files can have a meaningful, albeit non-module,
--      identifier in logs.
--    - `init.lua` files: Automatically uses the parent directory name, adhering to
--      Lua's convention (e.g., `/path/to/mymodule/init.lua` becomes `mymodule`).
--    - Common project structures: Heuristics like recognizing `./src/module.lua`
--      to derive `module` can improve developer experience for common layouts.
--    - Basename extraction: As a final resort for .lua files, the filename itself
--      (without the extension) is used.
-- 5. Caching: Resolved module names are cached (keyed by absolute file path) to
--    mitigate the performance impact of repeated `debug.getinfo` calls and path
--    processing, which can be significant in high-frequency logging scenarios.
--
-- Why these fallbacks are important for logging:
-- A logging library should strive to provide the most useful context possible. If a
-- module path can't be determined via `package.path`, returning `nil` or a raw,
-- unhelpful file path is less desirable than a reasoned fallback. These fallbacks
-- ensure that:
--   - Scripts run directly (e.g., `lua my_script_without_extension`) still get a
--     stable identifier.
--   - The logging output remains informative even for less conventionally structured
--     projects.
--
-- Conditions leading to nil or basic fallback for module path:
-- - `debug.getinfo()` provides no source (e.g., end of stack, C-code boundary).
-- - Input `file_path` is fundamentally unresolvable (e.g., special debug strings
--   like "(tail call)", "[C]" which are handled by skipping the frame).
-- - `package.path` is not set or contains no usable templates.
-- - The file path does not match any `package.path` template, and specific
--   heuristics (like `init.lua` or `./src/` patterns) do not apply, leading to
--   general fallbacks (like basename for .lua files, or full path for non-.lua files).
-- - Internal path normalization or component extraction unexpectedly fails.

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
-- This function now only handles cases that couldn't be determined early in process_path()
-- @param abs_filepath (string) The absolute file path
-- @return string|nil A fallback module name or nil
local function generate_fallback_name(abs_filepath)
    -- Note: Most common early exit cases are now handled in process_path() for performance:
    -- - Non-lua files (converted to full path with dots)
    -- - init.lua files (use parent directory name)
    -- - ./src/module.lua pattern (use just basename)
    -- This function only handles remaining .lua files that need basename extraction

    -- Extract basename from the file path
    local basename = abs_filepath:match("([^/\\]+)$") or abs_filepath
    if not basename then
        return nil
    end

    -- At this point, we should only have .lua files that weren't caught by early patterns
    -- Remove .lua extension and return the basename as the module name
    if basename:match("%.lua$") then
        return basename:gsub("%.lua$", "")
    end

    -- Fallback for any unexpected cases - return basename as-is
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
    return generate_fallback_name(abs_filepath)
end

--- Processes and normalizes a file path for module discovery
-- Handles @ prefix removal, empty string checks, path normalization, and early fallback detection
-- @param file_path (string) The raw file path to process
-- @return string|nil, string|nil, string|nil The normalized absolute path, original path,
--   and early fallback name (if determinable), or nil if invalid
local function process_path(file_path)
    -- Verify input parameters
    if not file_path or type(file_path) ~= "string" then
        return nil, nil, nil
    end

    -- Store original filepath for pattern matching before normalization
    local original_filepath = file_path

    -- Remove leading @ if present (from debug.getinfo().source)
    -- The article specifically mentions this prefix must be stripped
    if file_path:sub(1, 1) == "@" then
        file_path = file_path:sub(2)
        original_filepath = file_path
    end

    -- Early exit for clearly unresolvable paths
    -- These are common debug.getinfo() results that cannot be module paths
    if file_path == "(tail call)" or file_path == "=(tail call)" or
        file_path == "[C]" then
        return nil, nil, nil
    end

    -- Normalize paths for reliable matching
    -- The article emphasizes the importance of path canonicalization
    local abs_filepath = to_absolute_path(file_path)

    -- Early fallback detection: Check for patterns that can be resolved without package.path matching
    -- This optimization avoids expensive package.path processing for common cases

    -- Extract basename for early pattern detection
    local basename = abs_filepath:match("([^/\\]+)$") or abs_filepath
    if not basename then
        return nil, nil, nil
    end

    -- Early exit case 1: Non-lua files
    -- For non-lua files, we always use the full path converted to dots as fallback
    -- This can be determined immediately without trying package.path matching
    if not basename:match("%.lua$") then
        local full_path = abs_filepath
        -- Remove leading ./ if present
        full_path = full_path:gsub("^%./", "")
        -- Convert path separators to dots
        local fallback_name = full_path:gsub("[/\\]", ".")
        return abs_filepath, original_filepath, fallback_name
    end

    -- Early exit case 2: Special ./src/module.lua pattern
    -- Files directly in ./src/ directory get just the basename as module name
    -- This is a common project structure pattern that can be detected early
    if original_filepath:match("^%./src/[^/\\]+%.lua$") then
        local module_name = basename:gsub("%.lua$", "")
        return abs_filepath, original_filepath, module_name
    end

    -- Early exit case 3: init.lua files
    -- init.lua files should use their parent directory name as module name
    -- This follows Lua's convention where require("mymodule") loads mymodule/init.lua
    if basename == "init.lua" then
        local parent = abs_filepath:match("([^/\\]+)[/\\]init%.lua$")
        if parent then
            return abs_filepath, original_filepath, parent
        end
        -- If we can't extract parent, return nil fallback (will be handled later)
        return abs_filepath, original_filepath, nil
    end

    -- No early fallback detected, continue with normal processing
    return abs_filepath, original_filepath, nil
end

--- Converts a file path to a Lua-style module identifier using package.path
-- This is the main entry point for module path discovery
-- @param file_path (string) The file path to convert
-- @return string|nil The module name if found, nil otherwise
local function get_module_path(file_path)
    -- Transform path and validate, with early fallback detection
    local abs_filepath, original_filepath, early_fallback = process_path(file_path)
    if not abs_filepath then
        return nil
    end

    -- Check cache first to avoid expensive recomputation
    -- The article strongly recommends caching due to performance overhead
    if module_name_cache[abs_filepath] then
        return module_name_cache[abs_filepath]
    end

    -- If we have an early fallback, use it directly (performance optimization)
    -- This avoids expensive package.path processing for common patterns
    if early_fallback then
        module_name_cache[abs_filepath] = early_fallback
        return early_fallback
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
-- Uses the enhanced module path discovery based on package.path analysis.
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

    -- Attempt to get the Lua module path using the enhanced algorithm
    local lua_path = get_module_path(source_path)

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
    return generate_fallback_name(abs_filepath)
end

return caller_info
