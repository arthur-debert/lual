--- Factory that creates a no-op transformer function
-- @param config (table, optional) Configuration for the no-op transformer
-- @return function The transformer function with schema attached
local function noop_factory(config)
    config = config or {}

    -- Create the actual transformer function
    local function transformer_func(record)
        -- No-op: just return the record unchanged
        return record
    end

    -- Create a callable table with schema
    local transformer_with_schema = {
        schema = {} -- no-op transformer has no config options currently
    }

    -- Make it callable
    setmetatable(transformer_with_schema, {
        __call = function(_, record)
            return transformer_func(record)
        end
    })

    return transformer_with_schema
end

return noop_factory
