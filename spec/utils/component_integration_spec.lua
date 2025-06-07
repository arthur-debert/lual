#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local component_utils = require("lual.utils.component")
local lual = require("lual.constants")
local all_outputs = lual.outputs
local all_presenters = lual.presenters
local all_transformers = lual.transformers

describe("Component Utils Integration", function()
    describe("with real outputs", function()
        it("should normalize console function", function()
            local result = component_utils.normalize_component(all_outputs.console,
                component_utils.DISPATCHER_DEFAULTS)

            assert.is_table(result)
            assert.are.equal(all_outputs.console, result.func)
            assert.is_table(result.config)
            assert.are.equal("local", result.config.timezone)
        end)

        it("should normalize console output with config", function()
            local input = {
                all_outputs.console,
                level = 30, -- ERROR level
                stream = io.stderr
            }

            local result = component_utils.normalize_component(input, component_utils.DISPATCHER_DEFAULTS)

            assert.is_table(result)
            assert.are.equal(all_outputs.console, result.func)
            assert.is_table(result.config)
            assert.are.equal(30, result.config.level)
            assert.are.equal(io.stderr, result.config.stream)
            assert.are.equal("local", result.config.timezone) -- Default preserved
        end)

        it("should normalize multiple outputs", function()
            local input = {
                all_outputs.console,
                { all_outputs.file, path = "/var/log/app.log", level = 20 }
            }

            local result = component_utils.normalize_components(input, component_utils.DISPATCHER_DEFAULTS)

            assert.are.equal(2, #result)
            assert.are.equal(all_outputs.console, result[1].func)
            assert.are.equal(all_outputs.file, result[2].func)
            assert.are.equal("/var/log/app.log", result[2].config.path)
            assert.are.equal(20, result[2].config.level)
        end)
    end)

    describe("with real presenters", function()
        it("should normalize text presenter function", function()
            local text_presenter = all_presenters.text()
            local result = component_utils.normalize_component(text_presenter, component_utils.PRESENTER_DEFAULTS)

            assert.is_table(result)
            assert.are.equal(text_presenter, result.func)
            assert.are.equal("local", result.config.timezone)
        end)

        it("should normalize text presenter with config", function()
            local text_presenter = all_presenters.text()
            local input = { text_presenter, timezone = "utc" }

            local result = component_utils.normalize_component(input, component_utils.PRESENTER_DEFAULTS)

            assert.is_table(result)
            assert.are.equal(text_presenter, result.func)
            assert.are.equal("utc", result.config.timezone)
        end)

        it("should normalize json presenter with config", function()
            local json_presenter = all_presenters.json()
            local input = { json_presenter, pretty = true, timezone = "utc" }

            local result = component_utils.normalize_component(input, component_utils.PRESENTER_DEFAULTS)

            assert.is_table(result)
            assert.are.equal(json_presenter, result.func)
            assert.is_true(result.config.pretty)
            assert.are.equal("utc", result.config.timezone)
        end)
    end)

    describe("with real transformers", function()
        it("should normalize noop transformer", function()
            local noop = all_transformers.noop()
            local result = component_utils.normalize_component(noop, component_utils.TRANSFORMER_DEFAULTS)

            assert.is_table(result)
            assert.are.equal(noop, result.func)
            assert.is_table(result.config)
        end)

        it("should normalize transformer with config", function()
            local noop = all_transformers.noop()
            local input = { noop, custom_field = "value" }

            local result = component_utils.normalize_component(input, component_utils.TRANSFORMER_DEFAULTS)

            assert.is_table(result)
            assert.are.equal(noop, result.func)
            assert.are.equal("value", result.config.custom_field)
        end)
    end)

    describe("integration across all component types", function()
        it("should build a complete logger configuration with normalized components", function()
            local console_disp = all_outputs.console
            local file_disp = all_outputs.file
            local text_presenter = all_presenters.text()
            local json_presenter = all_presenters.json()
            local noop = all_transformers.noop()

            local outputs = component_utils.normalize_components({
                console_disp,
                { file_disp, path = "/var/log/app.log", level = 20 }
            }, component_utils.DISPATCHER_DEFAULTS)

            local presenters = component_utils.normalize_components({
                text_presenter,
                { json_presenter, pretty = true }
            }, component_utils.PRESENTER_DEFAULTS)

            local transformers = component_utils.normalize_components({
                noop
            }, component_utils.TRANSFORMER_DEFAULTS)

            -- Now we can use these normalized components in a logger config
            assert.are.equal(2, #outputs)
            assert.are.equal(2, #presenters)
            assert.are.equal(1, #transformers)

            -- Verify first output
            assert.are.equal(console_disp, outputs[1].func)
            assert.are.equal("local", outputs[1].config.timezone)

            -- Verify second output
            assert.are.equal(file_disp, outputs[2].func)
            assert.are.equal("/var/log/app.log", outputs[2].config.path)
            assert.are.equal(20, outputs[2].config.level)

            -- Verify presenters
            assert.are.equal(text_presenter, presenters[1].func)
            assert.are.equal(json_presenter, presenters[2].func)
            assert.is_true(presenters[2].config.pretty)

            -- Verify transformers
            assert.are.equal(noop, transformers[1].func)
        end)
    end)
end)
