--- Factory that creates a test transformer function that adds a prefix to message_fmt
-- @param config (table, optional) Configuration for the test transformer
-- @return function The transformer function with schema attached
local function test_transformer_factory(config)
    config = config or {}
    local prefix = config.prefix or "[TRANSFORMED] "

    -- Create the actual transformer function
    local function transformer_func(record)
        -- Create a copy of the record and modify the message_fmt
        local transformed_record = {}
        for k, v in pairs(record) do
            transformed_record[k] = v
        end

        if transformed_record.message_fmt then
            transformed_record.message_fmt = prefix .. transformed_record.message_fmt
        end

        return transformed_record
    end

    -- Create a callable table with schema
    local transformer_with_schema = {
        schema = {
            prefix = { type = "string", required = false }
        }
    }

    -- Make it callable
    setmetatable(transformer_with_schema, {
        __call = function(_, record)
            return transformer_func(record)
        end
    })

    return transformer_with_schema
end

return test_transformer_factory
