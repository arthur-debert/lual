-- Debug script to understand rotation behavior
package.path = "./lua/?.lua;" .. package.path

local file_output_factory = require("lual.outputs.file_output")

-- Mock the os and io functions to see what's happening
local calls = {}

local original_os_rename = os.rename
local original_os_remove = os.remove
local original_io_open = io.open

os.rename = function(old, new)
    table.insert(calls, {type = "os.rename", old = old, new = new})
    if old == new then
        -- Existence check - simulate .5 doesn't exist, others exist
        if string.match(old, "%.5$") then
            return nil, "No such file"
        end
        return true -- Others exist
    end
    return true -- Actual renames succeed
end

os.remove = function(path)
    table.insert(calls, {type = "os.remove", path = path})
    return true
end

io.open = function(path, mode)
    table.insert(calls, {type = "io.open", path = path, mode = mode})
    if mode == "r" then
        -- Simulate files .1-.4 and main log exist
        if string.match(path, "test_app%.log$") or string.match(path, "test_app%.log%.[1-4]$") then
            return {close = function() end}
        end
        return nil, "No such file"
    end
    return {write = function() end, flush = function() end, close = function() end}
end

-- Test the rotation
print("=== Testing rotation ===")
local handler = file_output_factory({path = "test_app.log"})

print("\n=== Calls made ===")
for i, call in ipairs(calls) do
    if call.type == "os.rename" then
        print(string.format("%d: os.rename('%s', '%s')", i, call.old, call.new))
    elseif call.type == "os.remove" then
        print(string.format("%d: os.remove('%s')", i, call.path))
    elseif call.type == "io.open" then
        print(string.format("%d: io.open('%s', '%s')", i, call.path, call.mode))
    end
end

-- Test command generation directly
print("\n=== Testing command generation ===")
local commands = file_output_factory._generate_rotation_commands("test_app.log")
for i, cmd in ipairs(commands) do
    if cmd.type == "remove" then
        print(string.format("%d: remove %s", i, cmd.target))
    elseif cmd.type == "rename" then
        print(string.format("%d: rename %s -> %s", i, cmd.source, cmd.target))
    end
end