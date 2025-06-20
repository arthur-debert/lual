-- Pipeline Processing
-- This module handles the processing of log records through pipelines

-- Note: For direct execution with 'lua', use require("lual.*")
-- For LuaRocks installed modules or busted tests, use require("lual.*")
local component_utils = require("lual.utils.component")
local core_levels = require("lual.levels")

-- Import the standalone debug module to avoid circular dependencies
local debug_module = require("lual.debug")

local M = {}

--- Processes a single transformer
-- @param record table The log record to process
-- @param transformer function|table The transformer function or config
-- @return table The transformed record, or nil and error message
local function process_transformer(record, transformer)
    -- Create a copy of the record for the transformer
    local transformed_record = {}
    for k, v in pairs(record) do
        transformed_record[k] = v
    end

    -- Normalize transformer to standard format
    local normalized = component_utils.normalize_component(transformer, component_utils.TRANSFORMER_DEFAULTS)
    local transformer_func = normalized.func
    local transformer_config = normalized.config

    -- Apply the transformer
    local ok, result = pcall(transformer_func, transformed_record, transformer_config)
    if not ok then
        return nil, "Transformer error: " .. tostring(result)
    end

    return result or transformed_record
end

--- Processes a single presenter
-- @param record table The log record to process
-- @param presenter function|table The presenter function or config
-- @return string|nil The presented message, or nil and error message
local function process_presenter(record, presenter)
    -- If the presenter is already a function, use it directly
    if type(presenter) == "function" then
        local ok, result = pcall(presenter, record)
        if not ok then
            io.stderr:write(string.format("LUAL: Error in presenter function: %s\n", tostring(result)))
            return nil, result
        end
        return result
    end

    -- Otherwise normalize presenter to standard format
    local normalized = component_utils.normalize_component(presenter, component_utils.PRESENTER_DEFAULTS)
    local presenter_func = normalized.func
    local presenter_config = normalized.config

    -- Apply the presenter
    local ok, result = pcall(presenter_func, record, presenter_config)
    if not ok then
        io.stderr:write(string.format("LUAL: Error in presenter function: %s\n", tostring(result)))
        return nil, result
    end

    return result
end

--- Processes a single output
-- @param log_record table The log record to process
-- @param output_entry table|function The output configuration or function
-- @param logger table The logger that owns this output
local function process_output(log_record, output_entry, logger)
    -- Create a copy of the log record for this output
    local output_record = {}
    for k, v in pairs(log_record) do
        output_record[k] = v
    end

    -- Normalize output to standard format
    local normalized = component_utils.normalize_component(output_entry, component_utils.DISPATCHER_DEFAULTS)
    local output_func = normalized.func
    local output_config = normalized.config

    -- Add logger context to the record
    output_record.owner_logger_name = logger.name
    output_record.owner_logger_level = logger.level
    output_record.owner_logger_propagate = logger.propagate

    -- Output the record
    local ok, err = pcall(function()
        output_func(output_record, output_config)
    end)
    if not ok then
        io.stderr:write(string.format("Error outputting log record: %s\n", err))
    end
end

--- Process a single pipeline
-- @param log_record table The log record to process
-- @param pipeline_entry table The pipeline and its owner logger
function M.process_pipeline(log_record, pipeline_entry)
    if not pipeline_entry or not pipeline_entry.pipeline then
        error("Invalid pipeline entry: missing pipeline")
    end

    local pipeline = pipeline_entry.pipeline
    local logger = pipeline_entry.logger

    debug_module._debug_print("Pipeline step: processing pipeline for logger '%s'", logger.name)

    -- Create a copy of the log record for this pipeline
    local pipeline_record = {}
    for k, v in pairs(log_record) do
        pipeline_record[k] = v
    end

    -- Add pipeline level to the record for informational purposes
    if pipeline.level then
        pipeline_record.pipeline_level = pipeline.level
        debug_module._debug_print("Pipeline step: pipeline has level=%d", pipeline.level)
    else
        pipeline_record.pipeline_level = core_levels.definition.NOTSET
        debug_module._debug_print("Pipeline step: pipeline has no level (using NOTSET)")
    end

    -- Apply transformers if configured
    if pipeline.transformers then
        debug_module._debug_print("Pipeline step: applying %d transformers", #pipeline.transformers)
        for i, transformer in ipairs(pipeline.transformers) do
            debug_module._debug_print("Pipeline step: processing transformer %d/%d", i, #pipeline.transformers)
            local transformed_record, error_msg = process_transformer(pipeline_record, transformer)
            if transformed_record then
                pipeline_record = transformed_record
                debug_module._debug_print("Pipeline step: transformer %d succeeded", i)
            else
                pipeline_record.transformer_error = error_msg
                debug_module._debug_print("Pipeline step: transformer %d FAILED: %s", i, error_msg)
                break -- Stop processing transformers if one fails
            end
        end
    else
        debug_module._debug_print("Pipeline step: no transformers configured")
    end

    -- Apply presenter if configured
    if pipeline.presenter and not pipeline_record.transformer_error then
        debug_module._debug_print("Pipeline step: applying presenter")
        local presented_message, error_msg = process_presenter(pipeline_record, pipeline.presenter)
        if presented_message then
            pipeline_record.presented_message = presented_message
            pipeline_record.message = presented_message -- Overwrite message with presented message
            debug_module._debug_print("Pipeline step: presenter succeeded")
        else
            pipeline_record.presenter_error = error_msg
            debug_module._debug_print("Pipeline step: presenter FAILED: %s", error_msg)
        end
    elseif pipeline.presenter then
        debug_module._debug_print("Pipeline step: skipping presenter due to transformer error")
    else
        debug_module._debug_print("Pipeline step: no presenter configured")
    end

    -- Process each output in the pipeline
    if pipeline.outputs and not pipeline_record.transformer_error and not pipeline_record.presenter_error then
        debug_module._debug_print("Pipeline step: processing %d outputs", #pipeline.outputs)
        for i, output in ipairs(pipeline.outputs) do
            debug_module._debug_print("Pipeline step: processing output %d/%d", i, #pipeline.outputs)
            process_output(pipeline_record, output, logger)
        end
        debug_module._debug_print("Pipeline step: completed all outputs")
    elseif not pipeline.outputs then
        debug_module._debug_print("Pipeline step: no outputs configured")
    else
        debug_module._debug_print(
        "Pipeline step: skipping outputs due to errors (transformer_error=%s, presenter_error=%s)",
            tostring(pipeline_record.transformer_error ~= nil),
            tostring(pipeline_record.presenter_error ~= nil))
    end

    debug_module._debug_print("Pipeline step: completed pipeline for logger '%s'", logger.name)
end

--- Process all eligible pipelines for a log record
-- @param eligible_pipelines table Array of eligible pipelines to process
-- @param log_record table The log record to process
function M.process_pipelines(eligible_pipelines, log_record)
    debug_module._debug_print("Pipeline processing: processing %d eligible pipelines", #eligible_pipelines)

    for i, pipeline_entry in ipairs(eligible_pipelines) do
        debug_module._debug_print("Pipeline processing: processing pipeline %d/%d (logger='%s')",
            i, #eligible_pipelines, pipeline_entry.logger.name)
        M.process_pipeline(log_record, pipeline_entry)
    end

    debug_module._debug_print("Pipeline processing: completed all %d pipelines", #eligible_pipelines)
end

-- Expose internal functions that are needed by other modules
M._process_transformer = process_transformer
M._process_presenter = process_presenter
M._process_output = process_output

return M
