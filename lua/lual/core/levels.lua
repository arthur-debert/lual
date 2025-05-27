local levels = {}

levels.definition = {
    DEBUG = 10,
    INFO = 20,
    WARNING = 30,
    ERROR = 40,
    CRITICAL = 50,
    NONE = 100 -- To disable logging for a specific logger
}

local _level_names_cache = {} -- Cache for level number to name mapping

-- Helper function to get level name from level number
function levels.get_level_name(level_no)
    if _level_names_cache[level_no] then
        return _level_names_cache[level_no]
    end
    for name, number in pairs(levels.definition) do
        if number == level_no then
            _level_names_cache[level_no] = name
            return name
        end
    end
    return "UNKNOWN_LEVEL_NO_" .. tostring(level_no)
end

return levels
