#!/usr/bin/env lua
local lual = require("lual")
local core_levels = require("lual.levels")
local process = require("lual.log.process")

describe("lual.log.process", function()
    before_each(function()
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("process_pipeline() function", function()
        it("should process a pipeline with transformers, presenter, and outputs", function()
            local captured_record = nil
            local mock_output = function(record)
                captured_record = record
            end

            local logger = lual.logger("test", { level = core_levels.definition.INFO })

            -- Create a simple transformer function
            local mock_transformer = function(record)
                record.transformed = true
                return record
            end

            -- Create a simple presenter function
            local mock_presenter = function(record)
                return "PRESENTED: " .. record.message
            end

            -- Create a pipeline with the mock components
            local pipeline = {
                transformers = { mock_transformer },
                presenter = mock_presenter,
                outputs = { mock_output }
            }

            -- Create a pipeline entry with the logger and pipeline
            local pipeline_entry = {
                pipeline = pipeline,
                logger = logger
            }

            -- Create a mock log record
            local log_record = {
                level_no = core_levels.definition.INFO,
                level_name = "INFO",
                message = "Test message",
                formatted_message = "Test message",
                timestamp = os.time(),
                logger_name = "test",
                source_logger_name = "test"
            }

            -- Process the pipeline
            process.process_pipeline(log_record, pipeline_entry)

            -- Verify the transformers were applied
            assert.is_true(captured_record.transformed)

            -- Verify the presenter was applied
            assert.are.equal("PRESENTED: Test message", captured_record.message)

            -- Verify logger context was added
            assert.are.equal(logger.name, captured_record.owner_logger_name)
        end)

        it("should handle pipeline with no transformers", function()
            local captured_record = nil
            local mock_output = function(record)
                captured_record = record
            end

            local logger = lual.logger("test", { level = core_levels.definition.INFO })

            -- Create a pipeline with just presenter and output
            local pipeline = {
                presenter = function(record) return "PRESENTED: " .. record.message end,
                outputs = { mock_output }
            }

            -- Create a pipeline entry with the logger and pipeline
            local pipeline_entry = {
                pipeline = pipeline,
                logger = logger
            }

            -- Create a mock log record
            local log_record = {
                level_no = core_levels.definition.INFO,
                level_name = "INFO",
                message = "Test message",
                formatted_message = "Test message",
                timestamp = os.time(),
                logger_name = "test",
                source_logger_name = "test"
            }

            -- Process the pipeline
            process.process_pipeline(log_record, pipeline_entry)

            -- Verify the presenter was applied
            assert.are.equal("PRESENTED: Test message", captured_record.message)
        end)
    end)

    describe("process_pipelines() function", function()
        it("should process multiple pipelines", function()
            local captured_records = {}

            local logger1 = lual.logger("test1", { level = core_levels.definition.INFO })
            local logger2 = lual.logger("test2", { level = core_levels.definition.INFO })

            -- Create two mock outputs
            local mock_output1 = function(record)
                table.insert(captured_records, { output = 1, record = record })
            end

            local mock_output2 = function(record)
                table.insert(captured_records, { output = 2, record = record })
            end

            -- Create pipeline entries
            local pipeline_entries = {
                {
                    pipeline = {
                        outputs = { mock_output1 },
                        presenter = function(record) return "OUTPUT1: " .. record.message end
                    },
                    logger = logger1
                },
                {
                    pipeline = {
                        outputs = { mock_output2 },
                        presenter = function(record) return "OUTPUT2: " .. record.message end
                    },
                    logger = logger2
                }
            }

            -- Create a mock log record
            local log_record = {
                level_no = core_levels.definition.INFO,
                level_name = "INFO",
                message = "Test message",
                formatted_message = "Test message",
                timestamp = os.time(),
                logger_name = "test",
                source_logger_name = "test"
            }

            -- Process all pipelines
            process.process_pipelines(pipeline_entries, log_record)

            -- Verify both pipelines were processed
            assert.are.equal(2, #captured_records)
            assert.are.equal(1, captured_records[1].output)
            assert.are.equal("OUTPUT1: Test message", captured_records[1].record.message)
            assert.are.equal(2, captured_records[2].output)
            assert.are.equal("OUTPUT2: Test message", captured_records[2].record.message)
        end)
    end)
end)
