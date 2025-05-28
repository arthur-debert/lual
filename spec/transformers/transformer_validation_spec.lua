describe("Transformer validation", function()
    local config_module
    local schema

    before_each(function()
        config_module = require("lual.config")
        schema = require("lual.schema")
    end)

    describe("Schema validation", function()
        it("should validate transformer schema with valid noop type", function()
            local transformer_config = {
                type = "noop"
            }

            local result = schema.validate_transformer(transformer_config)
            assert.is_true(next(result._errors) == nil)
            assert.are.equal("noop", result.data.type)
        end)

        it("should reject invalid transformer type", function()
            local transformer_config = {
                type = "invalid_type"
            }

            local result = schema.validate_transformer(transformer_config)
            assert.is_not_nil(result._errors.type)
            assert.matches("Invalid transformer type", result._errors.type)
        end)

        it("should require transformer type field", function()
            local transformer_config = {}

            local result = schema.validate_transformer(transformer_config)
            assert.is_not_nil(result._errors.type)
            assert.matches("Each transformer must have a 'type' string field", result._errors.type)
        end)
    end)

    describe("Dispatcher with transformers validation", function()
        it("should validate dispatcher with valid transformers array", function()
            local dispatcher_config = {
                type = "console",
                presenter = "text",
                transformers = {
                    { type = "noop" }
                }
            }

            local result = schema.validate_dispatcher(dispatcher_config)
            assert.is_true(next(result._errors) == nil)
            assert.are.equal(1, #result.data.transformers)
            assert.are.equal("noop", result.data.transformers[1].type)
        end)

        it("should validate dispatcher without transformers", function()
            local dispatcher_config = {
                type = "console",
                presenter = "text"
            }

            local result = schema.validate_dispatcher(dispatcher_config)
            assert.is_true(next(result._errors) == nil)
            assert.is_nil(result.data.transformers)
        end)

        it("should reject dispatcher with invalid transformer", function()
            local dispatcher_config = {
                type = "console",
                presenter = "text",
                transformers = {
                    { type = "invalid_transformer" }
                }
            }

            local result = schema.validate_dispatcher(dispatcher_config)
            assert.is_not_nil(result._errors["transformers[1]"])
            assert.matches("Invalid transformer type", result._errors["transformers[1]"].type)
        end)
    end)

    describe("Config processing with transformers", function()
        it("should process declarative config with transformers", function()
            local input_config = {
                name = "test_logger",
                level = "info",
                dispatchers = {
                    {
                        type = "console",
                        presenter = "text",
                        transformers = {
                            { type = "noop" }
                        }
                    }
                }
            }

            local canonical_config = config_module.process_config(input_config)

            assert.are.equal("test_logger", canonical_config.name)
            assert.are.equal(1, #canonical_config.dispatchers)
            assert.are.equal(1, #canonical_config.dispatchers[1].transformer_funcs)
            -- Check that it's a callable table (like presenters)
            local transformer = canonical_config.dispatchers[1].transformer_funcs[1]
            assert.is_true(type(transformer) == "table" or type(transformer) == "function")
            if type(transformer) == "table" then
                assert.is_not_nil(getmetatable(transformer))
                assert.is_not_nil(getmetatable(transformer).__call)
            end
        end)

        it("should process declarative config without transformers", function()
            local input_config = {
                name = "test_logger",
                level = "info",
                dispatchers = {
                    {
                        type = "console",
                        presenter = "text"
                    }
                }
            }

            local canonical_config = config_module.process_config(input_config)

            assert.are.equal("test_logger", canonical_config.name)
            assert.are.equal(1, #canonical_config.dispatchers)
            assert.are.equal(0, #canonical_config.dispatchers[1].transformer_funcs)
        end)

        it("should reject config with invalid transformer type", function()
            local input_config = {
                name = "test_logger",
                level = "info",
                dispatchers = {
                    {
                        type = "console",
                        presenter = "text",
                        transformers = {
                            { type = "invalid_transformer" }
                        }
                    }
                }
            }

            assert.has_error(function()
                config_module.process_config(input_config)
            end, "Invalid declarative config: Invalid transformer type: invalid_transformer. Valid values are: noop")
        end)
    end)
end)
