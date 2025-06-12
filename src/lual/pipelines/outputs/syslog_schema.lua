--- Syslog Output Configuration Schema
-- Schema definition for syslog output configuration validation

local M = {}

-- Syslog facilities for validation
local FACILITY_NAMES = {
    "KERN", "USER", "MAIL", "DAEMON", "AUTH", "SYSLOG", "LPR", "NEWS",
    "UUCP", "CRON", "AUTHPRIV", "FTP", "LOCAL0", "LOCAL1", "LOCAL2",
    "LOCAL3", "LOCAL4", "LOCAL5", "LOCAL6", "LOCAL7"
}

-- Custom validator for facility (can be string or number)
local function validate_facility(facility)
    if type(facility) == "string" then
        -- Case insensitive facility name checking
        for _, name in ipairs(FACILITY_NAMES) do
            if string.upper(facility) == name then
                return true
            end
        end
        return false, "Unknown syslog facility: " .. facility
    elseif type(facility) == "number" then
        -- Valid facility numbers: 0-11, 16-23
        if (facility >= 0 and facility <= 11) or (facility >= 16 and facility <= 23) then
            return true
        else
            return false, "Invalid syslog facility number: " .. facility
        end
    else
        return false, "syslog facility must be a string or number"
    end
end

-- Syslog configuration schema
M.syslog_schema = {
    fields = {
        facility = {
            required = false,
            custom_validator = validate_facility
        },
        host = {
            type = "string",
            required = false,
            default = "localhost"
        },
        port = {
            type = "number",
            required = false,
            min = 1,
            max = 65535,
            default = 514
        },
        tag = {
            type = "string",
            required = false,
            default = "lual"
        },
        hostname = {
            type = "string",
            required = false
        }
    },
    on_extra_keys = "error"
}

return M
