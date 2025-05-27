local assert = require("luassert")
-- busted is expected to be a global or run via a CLI that provides describe, it, etc.
-- require("busted")

-- luacheck: globals describe it setup teardown before_each after_each

describe("lual.outputs.syslog_output", function()
    local syslog_output_factory
    local original_socket
    local mock_socket
    local mock_udp_socket
    local mock_dns
    local mock_io_stderr
    local original_io_stderr
    local mock_os_date
    local original_os_date

    -- Mock storage
    local mock_stderr_messages
    local mock_udp_calls
    local mock_dns_calls

    setup(function()
        -- Store originals
        original_io_stderr = io.stderr
        original_os_date = os.date

        -- Create mock objects
        mock_stderr_messages = {}
        mock_udp_calls = {}
        mock_dns_calls = {}

        mock_udp_socket = {
            settimeout = function(self, timeout)
                self._timeout = timeout
            end,
            sendto = function(self, data, host, port)
                table.insert(mock_udp_calls, {
                    data = data,
                    host = host,
                    port = port
                })
                return #data -- Return number of bytes sent
            end,
            _timeout = nil
        }

        mock_dns = {
            gethostname = function()
                table.insert(mock_dns_calls, "gethostname")
                return "test-hostname"
            end
        }

        mock_socket = {
            udp = function()
                return mock_udp_socket
            end,
            dns = mock_dns
        }

        mock_io_stderr = {
            write = function(self, msg)
                table.insert(mock_stderr_messages, msg)
            end
        }

        mock_os_date = function(format)
            if format == "%b %d %H:%M:%S" then
                return "Jan 15 14:30:45"
            end
            return original_os_date(format)
        end

        -- Replace globals
        io.stderr = mock_io_stderr
        os.date = mock_os_date

        -- Mock the socket module BEFORE requiring the syslog module
        package.loaded["socket"] = mock_socket

        -- Clear lual's cache if it's already loaded to get fresh mocks
        package.loaded["lual.outputs.syslog_output"] = nil
        syslog_output_factory = require("lual.outputs.syslog_output")
    end)

    before_each(function()
        -- Reset mock call arrays between tests
        mock_stderr_messages = {}
        mock_udp_calls = {}
        mock_dns_calls = {}

        -- Reset mock socket state
        mock_udp_socket._timeout = nil
        mock_udp_socket.sendto = function(self, data, host, port)
            table.insert(mock_udp_calls, {
                data = data,
                host = host,
                port = port
            })
            return #data -- Return number of bytes sent
        end

        -- Reset DNS mock
        mock_dns.gethostname = function()
            table.insert(mock_dns_calls, "gethostname")
            return "test-hostname"
        end

        -- Reset socket mock
        mock_socket.udp = function()
            return mock_udp_socket
        end
        package.loaded["socket"] = mock_socket
    end)

    teardown(function()
        -- Restore originals
        io.stderr = original_io_stderr
        os.date = original_os_date

        -- Clear mocks
        package.loaded["socket"] = nil
        mock_stderr_messages = nil
        mock_udp_calls = nil
        mock_dns_calls = nil
    end)

    describe("Configuration Validation", function()
        it("should require a config table", function()
            local handler = syslog_output_factory()
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "requires a config table"))
        end)

        it("should accept valid string facilities", function()
            local handler = syslog_output_factory({ facility = "LOCAL0" })
            assert.are.equal(0, #mock_stderr_messages)
        end)

        it("should accept valid numeric facilities", function()
            local handler = syslog_output_factory({ facility = 16 }) -- LOCAL0
            assert.are.equal(0, #mock_stderr_messages)
        end)

        it("should reject invalid string facilities", function()
            local handler = syslog_output_factory({ facility = "INVALID" })
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "Unknown syslog facility"))
        end)

        it("should reject invalid numeric facilities", function()
            local handler = syslog_output_factory({ facility = 999 })
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "Invalid syslog facility number"))
        end)

        it("should reject non-string hosts", function()
            local handler = syslog_output_factory({ host = 123 })
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "host must be a string"))
        end)

        it("should reject invalid ports", function()
            local handler = syslog_output_factory({ port = 0 })
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "port must be a number between 1 and 65535"))

            mock_stderr_messages = {}
            local handler2 = syslog_output_factory({ port = 70000 })
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "port must be a number between 1 and 65535"))
        end)

        it("should reject non-string tags", function()
            local handler = syslog_output_factory({ tag = 123 })
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "tag must be a string"))
        end)

        it("should reject non-string hostnames", function()
            local handler = syslog_output_factory({ hostname = 123 })
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "hostname must be a string"))
        end)
    end)

    describe("Level Mapping", function()
        it("should map lual levels to correct syslog severities", function()
            local map_func = syslog_output_factory._map_level_to_severity
            local severities = syslog_output_factory._SEVERITIES

            assert.are.equal(severities.DEBUG, map_func(10))    -- DEBUG
            assert.are.equal(severities.INFO, map_func(20))     -- INFO
            assert.are.equal(severities.WARNING, map_func(30))  -- WARNING
            assert.are.equal(severities.ERROR, map_func(40))    -- ERROR
            assert.are.equal(severities.CRITICAL, map_func(50)) -- CRITICAL
            assert.are.equal(severities.DEBUG, map_func(5))     -- Below DEBUG
        end)
    end)

    describe("Hostname Detection", function()
        it("should get hostname from socket.dns.gethostname", function()
            local hostname = syslog_output_factory._get_hostname()
            assert.are.equal("test-hostname", hostname)
            assert.are.equal(1, #mock_dns_calls)
        end)

        it("should fallback to localhost when hostname detection fails", function()
            mock_dns.gethostname = function()
                table.insert(mock_dns_calls, "gethostname")
                return nil -- Simulate failure
            end

            local hostname = syslog_output_factory._get_hostname()
            assert.are.equal("localhost", hostname)
            assert.are.equal(1, #mock_dns_calls)
        end)

        it("should fallback to localhost when hostname is empty", function()
            mock_dns.gethostname = function()
                table.insert(mock_dns_calls, "gethostname")
                return "" -- Simulate empty hostname
            end

            local hostname = syslog_output_factory._get_hostname()
            assert.are.equal("localhost", hostname)
            assert.are.equal(1, #mock_dns_calls)
        end)
    end)

    describe("Message Formatting", function()
        it("should format RFC 3164 compliant messages", function()
            local format_func = syslog_output_factory._format_syslog_message
            local facilities = syslog_output_factory._FACILITIES
            local severities = syslog_output_factory._SEVERITIES

            local record = {
                message = "Test log message",
                level = 20 -- INFO
            }

            local message = format_func(record, facilities.USER, "testhost", "myapp")

            -- Expected priority: USER (1) * 8 + INFO (6) = 14
            local expected = "<14>Jan 15 14:30:45 testhost myapp: Test log message"
            assert.are.equal(expected, message)
        end)

        it("should clean tag names", function()
            local format_func = syslog_output_factory._format_syslog_message
            local facilities = syslog_output_factory._FACILITIES

            local record = {
                message = "Test message",
                level = 20
            }

            local message = format_func(record, facilities.USER, "testhost", "my app with spaces")
            assert.truthy(string.find(message, "my_app_with_spaces:"))
        end)

        it("should truncate long tags", function()
            local format_func = syslog_output_factory._format_syslog_message
            local facilities = syslog_output_factory._FACILITIES

            local record = {
                message = "Test message",
                level = 20
            }

            local long_tag = string.rep("a", 50)
            local message = format_func(record, facilities.USER, "testhost", long_tag)
            local truncated_tag = string.rep("a", 32)
            assert.truthy(string.find(message, truncated_tag .. ":"))
        end)

        it("should handle missing level in record", function()
            local format_func = syslog_output_factory._format_syslog_message
            local facilities = syslog_output_factory._FACILITIES

            local record = {
                message = "Test message"
                -- No level field
            }

            local message = format_func(record, facilities.USER, "testhost", "myapp")
            -- Should default to INFO level (severity 6), so priority = 1*8 + 6 = 14
            assert.truthy(string.find(message, "<14>"))
        end)
    end)

    describe("Socket Operations", function()
        it("should create UDP socket with timeout", function()
            local handler = syslog_output_factory({})
            assert.are.equal(0.1, mock_udp_socket._timeout)
        end)

        it("should handle socket creation failure", function()
            mock_socket.udp = function()
                return nil -- Simulate socket creation failure
            end

            local handler = syslog_output_factory({})
            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "Failed to create UDP socket"))
        end)

        it("should send messages to correct host and port", function()
            local handler = syslog_output_factory({
                host = "log.example.com",
                port = 1514,
                facility = "LOCAL0",
                tag = "testapp"
            })

            local record = {
                message = "Test log entry",
                level = 30 -- WARNING
            }

            handler(record)

            assert.are.equal(1, #mock_udp_calls)
            local call = mock_udp_calls[1]
            assert.are.equal("log.example.com", call.host)
            assert.are.equal(1514, call.port)

            -- Check message format: LOCAL0 (16) * 8 + WARNING (4) = 132
            assert.truthy(string.find(call.data, "<132>"))
            assert.truthy(string.find(call.data, "testapp:"))
            assert.truthy(string.find(call.data, "Test log entry"))
        end)

        it("should use default host and port", function()
            local handler = syslog_output_factory({})

            local record = {
                message = "Default test",
                level = 20
            }

            handler(record)

            assert.are.equal(1, #mock_udp_calls)
            local call = mock_udp_calls[1]
            assert.are.equal("localhost", call.host)
            assert.are.equal(514, call.port)
        end)

        it("should handle sendto failures gracefully", function()
            mock_udp_socket.sendto = function(self, data, host, port)
                table.insert(mock_udp_calls, {
                    data = data,
                    host = host,
                    port = port
                })
                return nil, "Network unreachable" -- Simulate failure
            end

            local handler = syslog_output_factory({})
            local record = { message = "Test", level = 20 }

            handler(record)

            assert.are.equal(1, #mock_stderr_messages)
            assert.truthy(string.find(mock_stderr_messages[1], "Error sending syslog message"))
            assert.truthy(string.find(mock_stderr_messages[1], "Network unreachable"))
        end)
    end)

    describe("Integration", function()
        it("should work with all configuration options", function()
            local handler = syslog_output_factory({
                facility = "LOCAL7",
                host = "syslog.company.com",
                port = 5514,
                tag = "myservice",
                hostname = "web01.company.com"
            })

            local record = {
                message = "Service started successfully",
                level = 20 -- INFO
            }

            handler(record)

            assert.are.equal(1, #mock_udp_calls)
            local call = mock_udp_calls[1]

            assert.are.equal("syslog.company.com", call.host)
            assert.are.equal(5514, call.port)

            -- LOCAL7 (23) * 8 + INFO (6) = 190
            assert.truthy(string.find(call.data, "<190>"))
            assert.truthy(string.find(call.data, "web01%.company%.com"))
            assert.truthy(string.find(call.data, "myservice:"))
            assert.truthy(string.find(call.data, "Service started successfully"))
        end)

        it("should handle case-insensitive facility names", function()
            local handler = syslog_output_factory({ facility = "local0" })

            local record = { message = "Test", level = 20 }
            handler(record)

            assert.are.equal(1, #mock_udp_calls)
            -- LOCAL0 (16) * 8 + INFO (6) = 134
            assert.truthy(string.find(mock_udp_calls[1].data, "<134>"))
        end)

        it("should return no-op function on configuration errors", function()
            local handler = syslog_output_factory({ facility = "INVALID" })

            -- Should have logged error
            assert.are.equal(1, #mock_stderr_messages)

            -- Handler should be a no-op function
            local record = { message = "Test", level = 20 }
            handler(record)

            -- No UDP calls should have been made
            assert.are.equal(0, #mock_udp_calls)
        end)
    end)

    describe("Module Interface", function()
        it("should expose internal functions for testing", function()
            assert.is_function(syslog_output_factory._map_level_to_severity)
            assert.is_function(syslog_output_factory._get_hostname)
            assert.is_function(syslog_output_factory._format_syslog_message)
            assert.is_function(syslog_output_factory._validate_config)
            assert.is_table(syslog_output_factory._FACILITIES)
            assert.is_table(syslog_output_factory._SEVERITIES)
        end)

        it("should be callable as a function", function()
            local handler = syslog_output_factory({ facility = "USER" })
            assert.is_function(handler)
        end)
    end)
end)
