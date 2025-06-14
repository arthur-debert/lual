-- Pipeline Filter
-- This module handles filtering eligible pipelines for a log record

-- Import the standalone debug module to avoid circular dependencies
local debug_module = require("lual.debug")

local M = {}

--- Gets the eligible pipelines for a log record from a logger
-- A pipeline is eligible if both the logger's effective level and the pipeline's level permit the record
-- @param logger table The logger to check
-- @param log_record table The log record to process
-- @return table Array of eligible pipelines
function M.get_eligible_pipelines(logger, log_record)
    debug_module._debug_print("Pipeline filter: checking logger '%s' for level %s (%d)",
        logger.name, log_record.level_name, log_record.level_no)

    local eligible_pipelines = {}

    -- First check if the logger's effective level permits this record
    local effective_level = logger:_get_effective_level()
    debug_module._debug_print("Pipeline filter: logger '%s' effective_level=%d, record_level=%d",
        logger.name, effective_level, log_record.level_no)

    if log_record.level_no >= effective_level then
        debug_module._debug_print("Pipeline filter: logger '%s' level check passed, checking %d pipelines",
            logger.name, #logger.pipelines)

        -- For each pipeline in the logger, check if its level permits the record
        for i, pipeline in ipairs(logger.pipelines) do
            local pipeline_level = pipeline.level or 0
            debug_module._debug_print("Pipeline filter: checking pipeline %d in logger '%s' (pipeline_level=%s)",
                i, logger.name, pipeline_level and tostring(pipeline_level) or "nil")

            -- Skip pipelines that have a level higher than the record
            if not (pipeline.level and
                    type(pipeline.level) == "number" and
                    pipeline.level > 0 and
                    log_record.level_no < pipeline.level) then
                debug_module._debug_print("Pipeline filter: pipeline %d in logger '%s' is ELIGIBLE", i, logger.name)
                -- Pipeline is eligible, add it with a reference to its owner logger
                table.insert(eligible_pipelines, {
                    pipeline = pipeline,
                    logger = logger
                })
            else
                debug_module._debug_print(
                    "Pipeline filter: pipeline %d in logger '%s' is REJECTED (level %d > record %d)",
                    i, logger.name, pipeline.level, log_record.level_no)
            end
        end
    else
        debug_module._debug_print("Pipeline filter: logger '%s' level check FAILED (effective %d > record %d)",
            logger.name, effective_level, log_record.level_no)
    end

    debug_module._debug_print("Pipeline filter: logger '%s' has %d eligible pipelines",
        logger.name, #eligible_pipelines)
    return eligible_pipelines
end

return M
