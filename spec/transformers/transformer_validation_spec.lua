package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"
local lualog = require("lual.logger")

describe("Transformer validation", function()
    local config_module
    local schema

    before_each(function()
        config_module = require("lual.config")
        schema = require("lual.schema")

        -- Reset the logger system for each test
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.logging"] = nil
        lualog = require("lual.logger")

        -- Reset the logger cache
        local engine = require("lual.core.logging")
        engine.reset_cache()
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
        it("should process config with transformers", function()
            local config = {
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

            local logger = lualog.logger("test.transformer", config)

            -- Verify transformer was properly set up
            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.are.same(1, #dispatcher.transformer_funcs)

            -- Check that it's a callable table (like presenters)
            local transformer = dispatcher.transformer_funcs[1]
            assert.is_true(type(transformer) == "table")
            assert.is_not_nil(getmetatable(transformer))
            assert.is_not_nil(getmetatable(transformer).__call)
        end)

        it("should process config without transformers", function()
            local config = {
                dispatchers = {
                    {
                        type = "console",
                        presenter = "text"
                    }
                }
            }

            local logger = lualog.logger("test.no.transformer", config)

            -- Verify no transformers are present
            assert.are.same(1, #logger.dispatchers)
            local dispatcher = logger.dispatchers[1]
            assert.are.same(0, #dispatcher.transformer_funcs)
        end)

        it("should reject invalid transformer type", function()
            assert.has_error(function()
                lualog.logger("test.invalid.transformer", {
                    dispatchers = {
                        {
                            type = "console",
                            presenter = "text",
                            transformers = {
                                { type = "invalid_transformer" }
                            }
                        }
                    }
                })
            end, "Invalid config: Invalid transformer type: invalid_transformer. Valid values are: noop")
        end)
    end)
end)
