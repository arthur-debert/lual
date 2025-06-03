--- Path utility functions for the lual library.
-- This module provides path handling functionality used across the library,
-- particularly for normalizing and converting between different path formats.

local paths = {}

--- Normalizes a file path to use forward slashes and removes redundant components
-- @param path (string) The path to normalize
-- @return string The normalized path
function paths.normalize_path(path)
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
-- @param path (string) The path to convert
-- @return string The absolute path
function paths.to_absolute_path(path)
    if not path then
        return ""
    end

    -- If already absolute (starts with / or drive letter on Windows), return as-is
    if path:sub(1, 1) == "/" or path:match("^[A-Za-z]:") then
        return paths.normalize_path(path)
    end

    -- For relative paths, we'll use a simple approach since we can't use external libs
    -- In a real implementation, this would use the current working directory
    -- For now, we'll just normalize and return the path as-is
    return paths.normalize_path(path)
end

--- Escapes special Lua pattern characters in a string
-- @param str (string) The string to escape
-- @return string The escaped string
function paths.escape_lua_pattern(str)
    return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

--- Extracts the basename (filename) from a path
-- @param path (string) The path to extract the basename from
-- @return string|nil The basename if found, or nil if path is invalid
function paths.basename(path)
    if not path or path == "" then
        return nil
    end

    -- Extract basename from the file path
    local basename = path:match("([^/\\]+)$") or path
    return basename
end

return paths
