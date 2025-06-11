#!/usr/bin/env bash

# test-rockspec.sh - Comprehensive rockspec testing script
# This script helps catch installation and functionality issues before users encounter them

set -e # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ROCKSPEC_FILE="${1:-lual-1.0.1-1.rockspec}"
TEST_TREE=".test-luarocks"
TEMP_TEST_DIR="temp-test-$$"

echo -e "${BLUE}🧪 Testing rockspec: ${ROCKSPEC_FILE}${NC}"

# Function to cleanup on exit
cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up...${NC}"
    rm -rf "${TEST_TREE}"
    rm -rf "${TEMP_TEST_DIR}"
}
trap cleanup EXIT

# Check if rockspec exists
if [[ ! -f "${ROCKSPEC_FILE}" ]]; then
    echo -e "${RED}❌ Rockspec file not found: ${ROCKSPEC_FILE}${NC}"
    exit 1
fi

echo -e "${BLUE}📋 Step 1: Validating rockspec format${NC}"
luarocks lint "${ROCKSPEC_FILE}"

echo -e "${BLUE}📦 Step 2: Installing from rockspec${NC}"
luarocks install "${ROCKSPEC_FILE}" --tree "${TEST_TREE}"

echo -e "${BLUE}🔍 Step 3: Testing basic module loading${NC}"
lua -e "
package.path = '${TEST_TREE}/share/lua/5.4/?.lua;' .. package.path;
package.cpath = '${TEST_TREE}/lib/lua/5.4/?.so;' .. package.cpath;

print('Testing basic require...');
local lual = require('lual');
print('✓ lual module loaded successfully');

print('Testing API availability...');
assert(type(lual) == 'table', 'lual should be a table');
print('✓ lual API is available');

print('Testing basic logging methods...');
-- Test that basic methods exist
local methods = {'debug', 'info', 'warn', 'error', 'critical'};
for _, method in ipairs(methods) do
    if lual[method] then
        print('✓ Method ' .. method .. ' is available');
    else
        error('✗ Method ' .. method .. ' is missing');
    end
end

print('Testing constants...');
local constants = {'debug', 'info', 'warning', 'error', 'critical'};
for _, const in ipairs(constants) do
    if lual[const] then
        print('✓ Constant ' .. const .. ' is available');
    else
        error('✗ Constant ' .. const .. ' is missing');
    end
end

print('All basic tests passed!');
"

echo -e "${BLUE}📝 Step 4: Testing actual logging functionality${NC}"
lua -e "
package.path = '${TEST_TREE}/share/lua/5.4/?.lua;' .. package.path;
package.cpath = '${TEST_TREE}/lib/lua/5.4/?.so;' .. package.cpath;

local lual = require('lual');
print('Testing logging output...');

-- Test basic logging
lual.info('Test info message from installed lual');
lual.warn('Test warning message from installed lual');

-- Test configuration
lual.config({
    level = lual.debug,
    pipelines = {{
        outputs = { lual.console },
        presenters = { lual.text }
    }}
});

lual.debug('Test debug message after config');
print('✓ Logging functionality works');
"

echo -e "${BLUE}🧪 Step 5: Running test suite against installed version${NC}"
# Create a temporary test directory with custom setup
mkdir -p "${TEMP_TEST_DIR}"

# Create a busted config that uses the installed version
cat >"${TEMP_TEST_DIR}/busted_config.lua" <<EOF
return {
    default = {
        lua = function()
            package.path = '${PWD}/${TEST_TREE}/share/lua/5.4/?.lua;' .. package.path
            package.cpath = '${PWD}/${TEST_TREE}/lib/lua/5.4/?.so;' .. package.cpath
            return 'lua'
        end
    }
}
EOF

# Run a subset of critical tests
echo "Running critical import/require tests..."
cd "${TEMP_TEST_DIR}"
busted --config-file=busted_config.lua ../spec/config/ --pattern="_spec%.lua$" --verbose || {
    echo -e "${RED}❌ Some tests failed with installed version${NC}"
    exit 1
}
cd ..

echo -e "${BLUE}🎯 Step 6: Testing module completeness${NC}"
lua -e "
package.path = '${TEST_TREE}/share/lua/5.4/?.lua;' .. package.path;
package.cpath = '${TEST_TREE}/lib/lua/5.4/?.so;' .. package.cpath;

-- Test that all major modules can be required
local modules = {
    'lual',
    'lual.logger',
    'lual.api', 
    'lual.loggers',
    'lual.constants',
    'lual.levels',
    'lual.config',
    'lual.utils.table',
    'lual.utils.schemer',
    'lual.pipelines.outputs',
    'lual.pipelines.presenters',
    'lual.pipelines.transformers'
};

for _, module in ipairs(modules) do
    local success, result = pcall(require, module);
    if success then
        print('✓ Module ' .. module .. ' loads successfully');
    else
        error('✗ Module ' .. module .. ' failed to load: ' .. tostring(result));
    end
end

print('All modules load successfully!');
"

echo -e "${GREEN}✅ All tests passed! Your rockspec is ready for distribution.${NC}"
echo -e "${YELLOW}💡 Remember to run this script whenever you:${NC}"
echo -e "${YELLOW}   - Modify the rockspec${NC}"
echo -e "${YELLOW}   - Add/remove/move Lua files${NC}"
echo -e "${YELLOW}   - Change module structure${NC}"
echo -e "${YELLOW}   - Before creating releases${NC}"
