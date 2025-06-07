--- Pipeline Module
-- This module is deprecated. All functionality has been moved to the log module.

-- Print a deprecation warning
io.stderr:write("WARNING: The lual.pipelines module is deprecated and will be removed in a future version.\n")
io.stderr:write("         Please use the lual.log module or constants from lual.constants directly.\n")

-- Return a proxy that redirects to the log module
return setmetatable({}, {
    __index = function(_, key)
        -- Print a more specific warning for each accessed method
        io.stderr:write(string.format("WARNING: lual.pipelines.%s is deprecated. Use lual.log instead.\n", key))

        -- Redirect to log module
        local log_module = require("lual.log")
        return log_module[key]
    end
})
