#!/usr/bin/env lua

-- Test file rotation implementation using TMPDIR
-- This tests the actual execution in a small context as requested

package.path = "./lua/?.lua;" .. package.path

local file_dispatcher_factory = require("lua.lual.dispatchers.file_dispatcher")
local os = require("os")

-- Get TMPDIR or use /tmp
local tmpdir = os.getenv("TMPDIR") or "/tmp"
local test_log_path = tmpdir .. "/test_rotation.log"

print("=== Testing file rotation in TMPDIR ===")
print("Test log path: " .. test_log_path)

-- Clean up any existing test files
for i = 1, 5 do
    os.remove(test_log_path .. "." .. i)
end
os.remove(test_log_path)

-- Create some test files to rotate
local function create_test_file(path, content)
    local file = io.open(path, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

-- Create test files
create_test_file(test_log_path, "Current log content\n")
create_test_file(test_log_path .. ".1", "Backup 1 content\n")
create_test_file(test_log_path .. ".2", "Backup 2 content\n")

print("\n=== Before rotation ===")
local function check_file_exists(path)
    local file = io.open(path, "r")
    if file then
        local content = file:read("*a")
        file:close()
        return true, content:gsub("\n", "")
    end
    return false, nil
end

for i = 5, 1, -1 do
    local exists, content = check_file_exists(test_log_path .. "." .. i)
    if exists then
        print(string.format("%s.%d: %s", test_log_path, i, content))
    end
end
local exists, content = check_file_exists(test_log_path)
if exists then
    print(string.format("%s: %s", test_log_path, content))
end

-- Test command generation
print("\n=== Generated commands ===")
local commands = file_dispatcher_factory._generate_rotation_commands(test_log_path)
for i, cmd in ipairs(commands) do
    if cmd.type == "remove" then
        print(string.format("%d: remove %s", i, cmd.target))
    elseif cmd.type == "rename" then
        print(string.format("%d: rename %s -> %s", i, cmd.source, cmd.target))
    end
end

-- Test validation
print("\n=== Validation ===")
local valid, err = file_dispatcher_factory._validate_rotation_commands(commands, test_log_path)
print("Valid:", valid)
if not valid then
    print("Error:", err)
end

-- Execute rotation
print("\n=== Executing rotation ===")
local handler = file_dispatcher_factory({ path = test_log_path })

print("\n=== After rotation ===")
for i = 5, 1, -1 do
    local exists, content = check_file_exists(test_log_path .. "." .. i)
    if exists then
        print(string.format("%s.%d: %s", test_log_path, i, content))
    end
end
local exists, content = check_file_exists(test_log_path)
if exists then
    print(string.format("%s: %s", test_log_path, content))
else
    print(test_log_path .. ": (new file, empty)")
end

-- Test writing to the new log
print("\n=== Testing log writing ===")
handler({ message = "New log entry after rotation" })

local exists, content = check_file_exists(test_log_path)
if exists then
    print(string.format("%s: %s", test_log_path, content))
end

-- Clean up
print("\n=== Cleaning up ===")
for i = 1, 5 do
    os.remove(test_log_path .. "." .. i)
end
os.remove(test_log_path)

print("Test completed!")
