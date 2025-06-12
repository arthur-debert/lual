-- Pipeline Filter
-- This module handles filtering eligible pipelines for a log record

local M = {}

--- Gets the eligible pipelines for a log record from a logger
-- A pipeline is eligible if both the logger's effective level and the pipeline's level permit the record
-- @param logger table The logger to check
-- @param log_record table The log record to process
-- @return table Array of eligible pipelines
function M.get_eligible_pipelines(logger, log_record)
    local eligible_pipelines = {}

    -- First check if the logger's effective level permits this record
    local effective_level = logger:_get_effective_level()

    if log_record.level_no >= effective_level then
        -- For each pipeline in the logger, check if its level permits the record
        for _, pipeline in ipairs(logger.pipelines) do
            -- Skip pipelines that have a level higher than the record
            if not (pipeline.level and
                    type(pipeline.level) == "number" and
                    pipeline.level > 0 and
                    log_record.level_no < pipeline.level) then
                -- Pipeline is eligible, add it with a reference to its owner logger
                table.insert(eligible_pipelines, {
                    pipeline = pipeline,
                    logger = logger
                })
            end
        end
    end

    return eligible_pipelines
end

return M
