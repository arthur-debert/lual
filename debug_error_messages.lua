-- Debug script to understand error message format
package.path = "./lua/?.lua;" .. package.path

local file_output_factory = require("lual.outputs.file_output")

-- Mock stderr to capture messages
local messages = {}
local original_stderr = io.stderr
io.stderr = {
    write = function(msg)
        table.insert(messages, msg)
        print("STDERR:", type(msg), msg)
    end
}

-- Test invalid config
print("=== Testing invalid config ===")
file_output_factory({})

print("\n=== Messages captured ===")
for i, msg in ipairs(messages) do
    print(string.format("Message %d: type=%s, value=%s", i, type(msg), tostring(msg)))
end

-- Restore stderr
io.stderr = original_stderr