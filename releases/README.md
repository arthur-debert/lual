# Rockspec Template System

This directory contains the template system for managing lual and lualextras rockspecs.

## Files

- `VERSION` - Contains the current version number (e.g., `0.8.2`)
- `lual.spec.template` - Template for lual rockspec with `@@VERSION` placeholder
- `lualextras.spec.template` - Template for lualextras rockspec with `@@VERSION` placeholder

## Usage

### Generate Rockspecs

To generate rockspecs from templates:

```bash
./bin/create-specs
```

This script:
1. Reads the version from `releases/VERSION`
2. Substitutes `@@VERSION` in both templates
3. Generates `lual-<version>-1.rockspec` and `lualextras-<version>-1.rockspec` in project root
4. Validates the generated rockspecs with `luarocks lint`

### Update Version

To release a new version:

1. Edit `releases/VERSION` with the new version number
2. Run `./bin/create-specs` to generate new rockspecs
3. Test and upload the rockspecs manually

### Example Workflow

```bash
# Update version
echo "0.8.3" > releases/VERSION

# Generate rockspecs
./bin/create-specs

# Test locally
luarocks install lual-0.8.3-1.rockspec
luarocks install lualextras-0.8.3-1.rockspec

# Upload to LuaRocks
luarocks upload lual-0.8.3-1.rockspec --api-key=YOUR_KEY
luarocks upload lualextras-0.8.3-1.rockspec --api-key=YOUR_KEY
```

## Benefits

- **Simple version management**: Single file (`VERSION`) controls both rockspecs
- **Easy template updates**: Modify templates once, generate many versions
- **Validation included**: Automatic `luarocks lint` checking
- **No auto-upload**: Manual control over publishing
- **Version consistency**: Both packages always use the same version number 