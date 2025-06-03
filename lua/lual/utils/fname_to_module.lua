--- Module for converting file paths to Lua module paths.
-- This module handles the conversion of file paths to Lua-style module identifiers,
-- which is primarily used for logging to identify the source of a log message.
--
-- It implements a strategy to reliably determine a Lua-style module path (e.g., "my.module")
-- from a raw file path:
-- 1. Path Normalization: Raw source paths are cleaned and normalized
-- 2. Package Path Matching: The primary method for deriving a module name is to
--    match the normalized, absolute file path against the templates in Lua's
--    `package.path`. This mimics Lua's `require()` lookup logic in reverse.
-- 3. Robust Fallbacks: When `package.path` matching is not possible or doesn't yield a
--    result, several fallback strategies are employed.

local paths = require("lual.utils.paths")

local fname_to_module = {}

-- Cache for derived module names to avoid expensive recomputation
-- Key: absolute file path, Value: derived module name
local module_name_cache = {}

--- Attempts to match a file path against a single package.path template
-- @param abs_filepath (string) The absolute file path to match
-- @param template (string) The package.path template (e.g., "./?.lua")
-- @return string|nil The extracted module name if matched, nil otherwise
local function match_template(abs_filepath, template)
    -- Normalize the template path
    template = paths.normalize_path(template)

    -- Find the position of ? in the template
    local question_pos = template:find("?", 1, true)
    if not question_pos then
        return nil
    end

    -- Split template into prefix and suffix around the ?
    local template_prefix = template:sub(1, question_pos - 1)
    local template_suffix = template:sub(question_pos + 1)

    -- Create patterns based on the template type
    local pattern
    local module_part

    if template:match("/?/init%.lua$") then
        -- Special case for init.lua modules
        local directory_pattern = template_prefix:gsub("/?$", "/") .. "(.-)/init" .. template_suffix
        module_part = abs_filepath:match(directory_pattern)
        if module_part then
            return module_part:gsub("[/\\]", ".")
        end
    else
        -- Normal module pattern
        -- Convert template prefix to absolute path if it's relative
        local abs_template_prefix = paths.to_absolute_path(template_prefix)

        -- Check if the file path matches this template structure
        local escaped_prefix = paths.escape_lua_pattern(abs_template_prefix)
        local escaped_suffix = paths.escape_lua_pattern(template_suffix)

        -- Create pattern to capture the module part (what ? represents)
        pattern = "^" .. escaped_prefix .. "(.-)" .. escaped_suffix .. "$"
        module_part = abs_filepath:match(pattern)

        if module_part then
            -- Convert the captured part to module name
            local module_name = module_part:gsub("[/\\]", ".")

            -- Remove any leading/trailing dots
            module_name = module_name:gsub("^%.+", ""):gsub("%.+$", "")

            if module_name ~= "" then
                return module_name
            end
        end
    end

    return nil
end

--- Tries to match file path against all provided package path templates
-- @param abs_filepath (string) The absolute file path
-- @param path_templates (table) The list of package path templates
-- @return string|nil The module name if any template matches, nil otherwise
local function try_package_path_matching(abs_filepath, path_templates)
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
-- @return string|nil A fallback module name or nil
local function generate_fallback_name(abs_filepath)
    -- Extract basename from the file path
    local basename = paths.basename(abs_filepath)

    -- At this point, we should only have .lua files that weren't caught by early patterns
    -- Remove .lua extension and return the basename as the module name
    if basename:match("%.lua$") then
        return basename:gsub("%.lua$", "")
    end

    -- Fallback for any unexpected cases - return basename as-is
    return basename
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

    if file_path == "" then
        return nil, nil, nil
    end

    -- Store original filepath for pattern matching before normalization
    local original_filepath = file_path

    -- Remove leading @ if present (from debug.getinfo().source)
    if file_path:sub(1, 1) == "@" then
        file_path = file_path:sub(2)
        original_filepath = file_path
    end

    -- Early exit for clearly unresolvable paths
    if file_path == "(tail call)" or file_path == "=(tail call)" or
        file_path == "[C]" then
        return nil, nil, nil
    end

    -- Normalize paths for reliable matching
    local abs_filepath = paths.to_absolute_path(file_path)

    -- Extract basename for early pattern detection
    local basename = paths.basename(abs_filepath)
    if not basename then
        return nil, nil, nil
    end

    -- Early exit case 1: Non-lua files
    -- For non-lua files, we always use the full path converted to dots as fallback
    if not basename:match("%.lua$") then
        local full_path = abs_filepath
        -- Remove leading ./ if present
        full_path = full_path:gsub("^%./", "")
        -- Convert path separators to dots
        local fallback_name = full_path:gsub("[/\\]", ".")
        return abs_filepath, original_filepath, fallback_name
    end

    -- Early exit case 2: Special ./src/module.lua pattern
    if original_filepath:match("^%./src/[^/\\]+%.lua$") then
        local module_name = basename:gsub("%.lua$", "")
        return abs_filepath, original_filepath, module_name
    end

    -- Early exit case 3: init.lua files
    if basename == "init.lua" then
        local parent = abs_filepath:match("([^/\\]+)[/\\]init%.lua$")
        if parent then
            return abs_filepath, original_filepath, parent
        end
        return abs_filepath, original_filepath, nil
    end

    -- No early fallback detected, continue with normal processing
    return abs_filepath, original_filepath, nil
end

--- Converts a file path to a Lua-style module identifier
-- @param file_path (string) The file path to convert
-- @param path_templates (table) List of package path templates (optional, defaults to parsed package.path)
-- @return string|nil The module name if found, nil otherwise
function fname_to_module.get_module_path(file_path, path_templates)
    -- Transform path and validate, with early fallback detection
    local abs_filepath, original_filepath, early_fallback = process_path(file_path)
    if not abs_filepath then
        return nil
    end

    -- Check cache first to avoid expensive recomputation
    if module_name_cache[abs_filepath] then
        return module_name_cache[abs_filepath]
    end

    -- If we have an early fallback, use it directly (performance optimization)
    if early_fallback then
        module_name_cache[abs_filepath] = early_fallback
        return early_fallback
    end

    -- Use provided path templates or parse package.path if not provided
    if not path_templates or #path_templates == 0 then
        path_templates = {}
        local package_path = package.path or ""
        for template in package_path:gmatch("[^;]+") do
            if template and template ~= "" and template ~= ";;" then
                table.insert(path_templates, template)
            end
        end
    end

    -- Try to match against package path templates
    local module_name = try_package_path_matching(abs_filepath, path_templates)

    -- If no match found, use fallback strategy
    if not module_name then
        module_name = generate_fallback_name(abs_filepath)
    end

    -- Cache the result for future calls
    module_name_cache[abs_filepath] = module_name
    return module_name
end

--- Clears the module name cache
function fname_to_module.clear_cache()
    module_name_cache = {}
end

--- Gets the current cache size (for debugging/monitoring)
-- @return number The number of cached entries
function fname_to_module.get_cache_size()
    local count = 0
    for _ in pairs(module_name_cache) do
        count = count + 1
    end
    return count
end

-- Expose internal functions for testing
fname_to_module._match_template = match_template
fname_to_module._process_path = process_path
fname_to_module._generate_fallback_name = generate_fallback_name

return fname_to_module
