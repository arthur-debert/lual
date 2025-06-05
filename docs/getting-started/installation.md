# Installation

This guide covers how to install lual in your Lua environment.

## LuaRocks Installation (Recommended)

The easiest way to install lual is via LuaRocks:

```bash
luarocks install lual
```

This will automatically install lual and all its dependencies.

## Manual Installation

If you can't use LuaRocks, you can install lual manually:

1. Download the source from GitHub:

   ```bash
   git clone https://github.com/adilsondebert/lual.git
   ```

2. Copy the `lua/lual` directory to your Lua package path.

3. Ensure the package can be required:

   ```lua
   local lual = require("lual")
   ```

## Dependencies

lual has minimal dependencies:

- Lua 5.1+ or LuaJIT
- (Optional) LuaSocket for network capabilities
- (Optional) LuaFileSystem for advanced file operations

## Verifying Installation

To verify your installation:

```lua
local lual = require("lual")
local logger = lual.logger("test")
logger:info("lual is installed and working!")
```

If you see the log message, lual is correctly installed!

## Development Installation

For development work on lual itself:

```bash
git clone https://github.com/yourusername/lual.git
cd lual
luarocks make
```

## Next Steps

Now that lual is installed, let's learn how to use it:

- Continue to [Basic Concepts](basic-concepts.md)
- Try the [Quick Start](quick-start.md) examples