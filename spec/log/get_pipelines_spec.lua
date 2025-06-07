#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")
local get_pipelines = require("lual.log.get_pipelines")

describe("lual.log.get_pipelines", function()
    before_each(function()
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("get_eligible_pipelines() function", function()
        it("should return an empty list if the logger's level is higher than the log record", function()
            local logger = lual.logger("test", { level = core_levels.definition.ERROR })

            -- Create a mock log record with INFO level
            local log_record = { level_no = core_levels.definition.INFO }

            local pipelines = get_pipelines.get_eligible_pipelines(logger, log_record)
            assert.are.equal(0, #pipelines)
        end)

        it("should return all pipelines if the logger's level permits and the pipelines have no level", function()
            local mock_output = function() end

            local logger = lual.logger("test", {
                level = core_levels.definition.INFO,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = lual.text
                    },
                    {
                        outputs = { mock_output },
                        presenter = lual.text
                    }
                }
            })

            -- Create a mock log record with WARNING level
            local log_record = { level_no = core_levels.definition.WARNING }

            local pipelines = get_pipelines.get_eligible_pipelines(logger, log_record)
            assert.are.equal(2, #pipelines)
        end)

        it("should filter pipelines based on their level", function()
            local mock_output = function() end

            local logger = lual.logger("test", {
                level = core_levels.definition.DEBUG,
                pipelines = {
                    {
                        level = core_levels.definition.DEBUG,
                        outputs = { mock_output },
                        presenter = lual.text
                    },
                    {
                        level = core_levels.definition.INFO,
                        outputs = { mock_output },
                        presenter = lual.text
                    },
                    {
                        level = core_levels.definition.WARNING,
                        outputs = { mock_output },
                        presenter = lual.text
                    },
                    {
                        level = core_levels.definition.ERROR,
                        outputs = { mock_output },
                        presenter = lual.text
                    }
                }
            })

            -- Create a mock log record with INFO level
            local log_record = { level_no = core_levels.definition.INFO }

            local pipelines = get_pipelines.get_eligible_pipelines(logger, log_record)
            assert.are.equal(2, #pipelines) -- Should include DEBUG and INFO pipelines
        end)

        it("should include the logger reference in each pipeline entry", function()
            local mock_output = function() end

            local logger = lual.logger("test", {
                level = core_levels.definition.INFO,
                pipelines = {
                    {
                        outputs = { mock_output },
                        presenter = lual.text
                    }
                }
            })

            -- Create a mock log record with INFO level
            local log_record = { level_no = core_levels.definition.INFO }

            local pipelines = get_pipelines.get_eligible_pipelines(logger, log_record)
            assert.are.equal(1, #pipelines)
            assert.are.equal(logger, pipelines[1].logger)
            assert.are.equal(logger.pipelines[1], pipelines[1].pipeline)
        end)

        it("should handle a logger with no pipelines", function()
            local logger = lual.logger("test", { level = core_levels.definition.INFO })

            -- Create a mock log record with INFO level
            local log_record = { level_no = core_levels.definition.INFO }

            local pipelines = get_pipelines.get_eligible_pipelines(logger, log_record)
            assert.are.equal(0, #pipelines)
        end)
    end)
end)
