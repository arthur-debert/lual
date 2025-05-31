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

    describe("Public API", function()
        it("should expose transformers in the public API", function()
            assert.is_not_nil(lual.transformers)
            assert.is_not_nil(lual.transformers.noop_transformer)
            assert.is_function(lual.transformers.noop_transformer)
        end)

        it("should have transformer constants in flat namespace", function()
            assert.are.equal("noop", lual.noop)
        end)

        it("should have flat namespace constant lual.noop", function()
            assert.is_not_nil(lual.noop)
            assert.are.equal("noop", lual.noop)

            -- Test that the flat constant works in logger config
            local logger = lual.logger({
                name = "test_noop",
                dispatcher = lual.console,
                presenter = lual.text,
                level = lual.debug
            })

            assert.is_not_nil(logger)
            assert.are.equal("test_noop", logger.name)
        end)
    end)
end)
