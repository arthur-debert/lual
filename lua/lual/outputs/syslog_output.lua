--- output that sends log messages to syslog servers via UDP.
--
-- This handler implements RFC 3164 syslog protocol and supports:
-- - Local syslog (localhost:514) and remote syslog servers
-- - Configurable syslog facilities (e.g., LOCAL0-LOCAL7, USER, DAEMON, etc.)
-- - Automatic mapping of lual log levels to syslog severities
-- - Hostname detection or manual configuration
-- - UDP transport (TCP support can be added later)
--
-- @usage
-- local lual = require("lual")
-- local syslog_output_factory = require("lual.outputs.syslog_output")
--
-- -- Local syslog
-- local logger = lual.logger("my_app")
-- logger:add_output(syslog_output_factory({ facility = "LOCAL0" }), lual.levels.INFO)
--
-- -- Remote syslog
-- logger:add_output(syslog_output_factory({
--     host = "log.example.com",
--     port = 514,
--     facility = "USER"
-- }), lual.levels.INFO)

-- Socket module will be required lazily to allow for testing mocks

-- Syslog facilities as defined in RFC 3164
local FACILITIES = {
    KERN = 0,      -- kernel messages
    USER = 1,      -- user-level messages
    MAIL = 2,      -- mail system
    DAEMON = 3,    -- system daemons
    AUTH = 4,      -- security/authorization messages
    SYSLOG = 5,    -- messages generated internally by syslogd
    LPR = 6,       -- line printer subsystem
    NEWS = 7,      -- network news subsystem
    UUCP = 8,      -- UUCP subsystem
    CRON = 9,      -- clock daemon
    AUTHPRIV = 10, -- security/authorization messages
    FTP = 11,      -- FTP daemon
    LOCAL0 = 16,   -- local use facility 0
    LOCAL1 = 17,   -- local use facility 1
    LOCAL2 = 18,   -- local use facility 2
    LOCAL3 = 19,   -- local use facility 3
    LOCAL4 = 20,   -- local use facility 4
    LOCAL5 = 21,   -- local use facility 5
    LOCAL6 = 22,   -- local use facility 6
    LOCAL7 = 23,   -- local use facility 7
}

-- Syslog severities as defined in RFC 3164
local SEVERITIES = {
    EMERGENCY = 0, -- system is unusable
    ALERT = 1,     -- action must be taken immediately
    CRITICAL = 2,  -- critical conditions
    ERROR = 3,     -- error conditions
    WARNING = 4,   -- warning conditions
    NOTICE = 5,    -- normal but significant condition
    INFO = 6,      -- informational messages
    DEBUG = 7,     -- debug-level messages
}

--- Maps lual log levels to syslog severities.
-- @param level_no (number) The lual log level number.
-- @return number The corresponding syslog severity.
local function map_level_to_severity(level_no)
    if level_no >= 50 then     -- CRITICAL
        return SEVERITIES.CRITICAL
    elseif level_no >= 40 then -- ERROR
        return SEVERITIES.ERROR
    elseif level_no >= 30 then -- WARNING
        return SEVERITIES.WARNING
    elseif level_no >= 20 then -- INFO
        return SEVERITIES.INFO
    else                       -- DEBUG (10) and below
        return SEVERITIES.DEBUG
    end
end

--- Gets the local hostname.
-- @return string The hostname or "localhost" if detection fails.
local function get_hostname()
    -- Try to get hostname via socket.dns
    local success, socket = pcall(require, "socket")
    if success then
        local hostname = socket.dns.gethostname()
        if hostname and hostname ~= "" then
            return hostname
        end
    end

    -- Fallback to localhost
    return "localhost"
end

--- Formats a log record as an RFC 3164 syslog message.
-- @param record (table) The log record containing message, level, timestamp, etc.
-- @param facility (number) The syslog facility number.
-- @param hostname (string) The hostname to include in the message.
-- @param tag (string) The application tag/name.
-- @return string The formatted syslog message.
local function format_syslog_message(record, facility, hostname, tag)
    local severity = map_level_to_severity(record.level or 20)
    local priority = facility * 8 + severity

    -- Format timestamp as RFC 3164 expects (Mmm dd hh:mm:ss)
    local timestamp = os.date("%b %d %H:%M:%S")

    -- Ensure tag is valid (no spaces, reasonable length)
    local clean_tag = tag:gsub("%s+", "_"):sub(1, 32)

    -- RFC 3164 format: <priority>timestamp hostname tag: message
    return string.format("<%d>%s %s %s: %s",
        priority, timestamp, hostname, clean_tag, record.message)
end

--- Validates syslog configuration.
-- @param config (table) The configuration to validate.
-- @return boolean, string True if valid, false and error message if invalid.
local function validate_config(config)
    if not config then
        return false, "syslog_output_factory requires a config table"
    end

    -- Validate facility
    if config.facility then
        if type(config.facility) == "string" then
            if not FACILITIES[config.facility:upper()] then
                return false, string.format("Unknown syslog facility: %s", config.facility)
            end
        elseif type(config.facility) == "number" then
            local valid_facility = false
            for _, fac_num in pairs(FACILITIES) do
                if fac_num == config.facility then
                    valid_facility = true
                    break
                end
            end
            if not valid_facility then
                return false, string.format("Invalid syslog facility number: %d", config.facility)
            end
        else
            return false, "syslog facility must be a string or number"
        end
    end

    -- Validate host if provided
    if config.host and type(config.host) ~= "string" then
        return false, "syslog host must be a string"
    end

    -- Validate port if provided
    if config.port then
        if type(config.port) ~= "number" or config.port < 1 or config.port > 65535 then
            return false, "syslog port must be a number between 1 and 65535"
        end
    end

    -- Validate tag if provided
    if config.tag and type(config.tag) ~= "string" then
        return false, "syslog tag must be a string"
    end

    -- Validate hostname if provided
    if config.hostname and type(config.hostname) ~= "string" then
        return false, "syslog hostname must be a string"
    end

    return true
end

--- Creates a syslog output handler.
-- @param config (table) Configuration for the syslog output.
--   - facility (string|number, optional): Syslog facility (default: "USER")
--   - host (string, optional): Syslog server host (default: "localhost")
--   - port (number, optional): Syslog server port (default: 514)
--   - tag (string, optional): Application tag (default: "lual")
--   - hostname (string, optional): Hostname to include in messages (default: auto-detected)
-- @return function(record) The actual log sending function.
local function syslog_output_factory(config)
    local valid, err = validate_config(config)
    if not valid then
        io.stderr:write(string.format("lual: %s\n", err))
        return function() end -- Return a no-op function on error
    end

    -- Set defaults
    local facility_name = config.facility or "USER"
    local facility_num
    if type(facility_name) == "string" then
        facility_num = FACILITIES[facility_name:upper()]
    else
        facility_num = facility_name
    end

    local host = config.host or "localhost"
    local port = config.port or 514
    local tag = config.tag or "lual"
    local hostname = config.hostname or get_hostname()

    -- Load luasocket when needed
    local socket_success, socket = pcall(require, "socket")
    if not socket_success then
        error("Syslog output requires the 'luasocket' package. Install it with: luarocks install luasocket")
    end

    -- Create UDP socket
    local udp_socket = socket.udp()
    if not udp_socket then
        io.stderr:write("lual: Failed to create UDP socket for syslog\n")
        return function() end
    end

    -- Set socket to non-blocking to avoid hanging the application
    udp_socket:settimeout(0.1) -- 100ms timeout

    -- Return the function that will handle individual log records
    return function(record)
        local message = format_syslog_message(record, facility_num, hostname, tag)

        local success, err = pcall(function()
            local bytes, send_err = udp_socket:sendto(message, host, port)
            if not bytes then
                error(string.format("Failed to send to %s:%d: %s", host, port, tostring(send_err)))
            end
        end)

        if not success then
            io.stderr:write(string.format("lual: Error sending syslog message: %s\n", tostring(err)))
        end
    end
end

-- Create module table with exported functions for testing
local module = setmetatable({
    _FACILITIES = FACILITIES,
    _SEVERITIES = SEVERITIES,
    _map_level_to_severity = map_level_to_severity,
    _get_hostname = get_hostname,
    _format_syslog_message = format_syslog_message,
    _validate_config = validate_config
}, {
    __call = function(_, config)
        return syslog_output_factory(config)
    end
})

return module
