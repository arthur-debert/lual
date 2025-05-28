describe("Transformer pipeline integration", function()
    local lual
    local original_stderr

    before_each(function()
        -- Reset modules to ensure clean state
        package.loaded["lual.logger"] = nil
        package.loaded["lual.core.logging"] = nil
        package.loaded["lual.ingest"] = nil
        package.loaded["lual.transformers.init"] = nil
        package.loaded["lual.transformers.noop_transformer"] = nil
        package.loaded["lual.transformers.test_transformer"] = nil

        lual = require("lual.logger")

        -- Mock stderr to capture error messages
        original_stderr = io.stderr
        io.stderr = { write = function() end }
    end)

    after_each(function()
        if original_stderr then
            io.stderr = original_stderr
        end
    end)

    describe("No-op transformer", function()
        it("should not modify log records", function()
            local captured_records = {}

            -- Create a mock dispatcher that captures the record
            local function capture_dispatcher(record, config)
                table.insert(captured_records, record)
            end

            -- Create a simple presenter that returns the message_fmt
            local function simple_presenter(record)
                return record.message_fmt or ""
            end

            -- Create logger with transformer
            local logger = lual.logger({
                name = "test_logger",
                level = "debug",
                dispatchers = {
                    {
                        type = "console",
                        presenter = "text",
                        transformers = {
                            { type = "noop" }
                        }
                    }
                }
            })

            -- Add our test dispatcher manually to capture records
            logger:add_dispatcher(capture_dispatcher, simple_presenter, {})

            -- Log a message
            logger:info("Test message %s", "arg1")

            -- Verify the record was captured
            assert.are.equal(1, #captured_records)
            local record = captured_records[1]
            assert.are.equal("Test message %s", record.raw_message_fmt)
            assert.are.equal("arg1", record.raw_args[1])
        end)
    end)

    describe("Custom transformer", function()
        it("should modify log records", function()
            local captured_presenter_records = {}

            -- Create a test transformer that adds a prefix
            local test_transformer = require("lual.transformers.test_transformer")

            -- Create a mock presenter that captures the record
            local function capture_presenter(record)
                table.insert(captured_presenter_records, record)
                return record.message_fmt or ""
            end

            -- Create a mock dispatcher
            local function mock_dispatcher(record, config)
                -- Do nothing
            end

            -- Create logger without transformers first
            local logger = lual.logger({
                name = "test_logger",
                level = "debug",
                dispatchers = {}
            })

            -- Add dispatcher with custom transformer manually
            table.insert(logger.dispatchers, {
                dispatcher_func = mock_dispatcher,
                presenter_func = capture_presenter,
                transformer_funcs = { test_transformer() },
                dispatcher_config = {}
            })

            -- Log a message
            logger:info("Test message")

            -- Verify the record was transformed
            assert.are.equal(1, #captured_presenter_records)
            local record = captured_presenter_records[1]
            assert.are.equal("[TRANSFORMED] Test message", record.message_fmt)
        end)
    end)

    describe("Public API", function()
        it("should expose transformers in the public API", function()
            assert.is_not_nil(lual.transformers)
            assert.is_not_nil(lual.transformers.noop_transformer)
            assert.is_function(lual.transformers.noop_transformer)
        end)

        it("should expose transformer shortcuts in lib", function()
            assert.is_not_nil(lual.lib.noop)
            assert.is_true(type(lual.lib.noop) == "table" or type(lual.lib.noop) == "function")
        end)
    end)
end)
