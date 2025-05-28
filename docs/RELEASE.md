# Release Process for lual

This document describes the release process for the lual LuaRocks package.

## Overview

We follow semantic versioning (MAJOR.MINOR.PATCH) and use LuaRocks' standard
release workflow with Git tags.

## Prerequisites

1. **LuaRocks Account**: You need an account at
   [luarocks.org](https://luarocks.org)
2. **API Key**: Generate one at
   [luarocks.org/settings/api-keys](https://luarocks.org/settings/api-keys)
3. **Git Repository**: Properly configured with remote origin
4. **Clean Working Directory**: All changes committed

## Release Workflow

### 1. Prepare for Release

```bash
# Ensure you're on the main branch
git checkout main
git pull origin main

# Ensure all tests pass
./bin/test.sh

# Update dependencies if needed
./bin/update-deps.sh
```

### 2. Create Release

Use the automated release script:

```bash
# Create a new release (e.g., version 0.2.0)
./bin/release.sh 0.2.0

# Or do a dry run first to see what would happen
./bin/release.sh 0.2.0 --dry-run
```

This script will:

- Validate the version format
- Create a new rockspec file
- Update the Git source URL and tag
- Commit the new rockspec
- Create and push a Git tag
- Build and pack the rock locally

### 3. Publish to LuaRocks

```bash
# Set your API key (do this once)
export LUAROCKS_API_KEY=your_api_key_here

# Publish the latest version
./bin/publish.sh

# Or publish a specific rockspec
./bin/publish.sh lual-0.2.0-1.rockspec

# Or do a dry run first
./bin/publish.sh --dry-run
```

### 4. Manual Process (Alternative)

If you prefer to do it manually:

```bash
# 1. Create new version
luarocks new_version lual-0.1.0-1.rockspec 0.2.0

# 2. Edit the new rockspec to fix source URL and tag
# Update source.url to: "git+https://github.com/arthur-debert/lual"
# Update source.tag to: "v0.2.0"

# 3. Validate
luarocks lint lual-0.2.0-1.rockspec

# 4. Commit and tag
git add lual-0.2.0-1.rockspec
git commit -m "Release v0.2.0"
git tag v0.2.0
git push origin v0.2.0
git push origin main

# 5. Build and test
luarocks build lual-0.2.0-1.rockspec

# 6. Pack and upload
luarocks pack lual-0.2.0-1.rockspec
luarocks upload lual-0.2.0-1.rockspec --api-key=YOUR_API_KEY
```

## Versioning Strategy

### Semantic Versioning

- **MAJOR** (1.0.0): Breaking changes
- **MINOR** (0.1.0): New features, backward compatible
- **PATCH** (0.0.1): Bug fixes, backward compatible

### LuaRocks Versioning

- LuaRocks appends a revision number: `0.1.0-1`
- The `-1` is the "rockspec revision"
- Increment it if you need to fix the rockspec without changing code
- Example: `0.1.0-1`, `0.1.0-2`, `0.1.0-3`

### Examples

```bash
# First release
./bin/release.sh 0.1.0

# Bug fix
./bin/release.sh 0.1.1

# New feature
./bin/release.sh 0.2.0

# Breaking change
./bin/release.sh 1.0.0

# Fix rockspec for same version
# Manually edit rockspec and change 0.1.0-1 to 0.1.0-2
```

## File Management

### Development

- Keep current development rockspec at root: `lual-X.Y.Z-1.rockspec`
- This is the "working" version

### Releases

- Each release creates a new rockspec file
- Old rockspec can be removed (optional)
- Git tags preserve access to old versions

### Directory Structure

```
lual/
├── lual-0.1.0-1.rockspec    # Current development version
├── bin/
│   ├── release.sh           # Release automation
│   └── publish.sh           # Publish automation
└── docs/
    └── RELEASE.md           # This file
```

## Best Practices

### Before Release

1. **Test thoroughly**: Run all tests
2. **Update documentation**: Ensure README and docs are current
3. **Check dependencies**: Verify all dependencies are correct
4. **Review changes**: Use `git log` to review what's changed

### Rockspec Quality

1. **Use rockspec format 3.0**: Enables modern features
2. **Proper source URL**: Point to your Git repository
3. **Correct Git tags**: Must match version numbers
4. **Complete metadata**: Fill in description, homepage, license
5. **Test dependencies**: Separate from runtime dependencies

### Git Workflow

1. **Clean commits**: Each release should be a clean commit
2. **Proper tags**: Use `v` prefix (e.g., `v0.1.0`)
3. **Push tags**: Don't forget to push tags to remote
4. **Branch protection**: Work on main/master branch

## Troubleshooting

### Common Issues

#### "Tag not found" Error

```bash
# Create and push the tag
git tag v0.1.0
git push origin v0.1.0
```

#### "Version already exists" Error

- You're trying to upload a version that already exists
- Increment the rockspec revision: `0.1.0-1` → `0.1.0-2`
- Or use a new version number

#### "Invalid API Key" Error

```bash
# Check your API key
echo $LUAROCKS_API_KEY

# Get a new one from luarocks.org/settings/api-keys
export LUAROCKS_API_KEY=your_new_key
```

#### "Rockspec validation failed" Error

```bash
# Check the rockspec
luarocks lint lual-X.Y.Z-1.rockspec

# Common issues:
# - Missing required fields
# - Invalid source URL
# - Syntax errors
```

#### "Build failed" Error

```bash
# Test local build
luarocks build lual-X.Y.Z-1.rockspec

# Check:
# - All source files exist
# - Module paths are correct
# - Dependencies are available
```

### Recovery

#### Rollback a Release

```bash
# Delete the tag locally and remotely
git tag -d v0.1.0
git push origin :refs/tags/v0.1.0

# Remove the rockspec
git rm lual-0.1.0-1.rockspec
git commit -m "Rollback release v0.1.0"
git push origin main
```

#### Fix a Published Release

- You cannot modify a published release
- Create a new version with fixes: `0.1.0-2` or `0.1.1`

## Environment Variables

```bash
# Required for publishing
export LUAROCKS_API_KEY=your_api_key

# Optional: Custom LuaRocks server
export LUAROCKS_SERVER=https://luarocks.org

# Optional: Custom rocks tree
export LUAROCKS_TREE=./local
```

## Automation

### GitHub Actions (Future)

Consider setting up GitHub Actions for:

- Automated testing on multiple Lua versions
- Automated releases on tag push
- Automated publishing to LuaRocks

### Example Workflow

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Lua
        uses: leafo/gh-actions-lua@v8
      - name: Setup LuaRocks
        uses: leafo/gh-actions-luarocks@v4
      - name: Publish to LuaRocks
        run: |
          luarocks upload *.rockspec --api-key=${{ secrets.LUAROCKS_API_KEY }}
```

## Resources

- [LuaRocks Documentation](https://github.com/luarocks/luarocks/wiki)
- [Rockspec Format](https://github.com/luarocks/luarocks/wiki/Rockspec-format)
- [Semantic Versioning](https://semver.org/)
- [LuaRocks Best Practices](https://martin-fieber.de/blog/create-build-publish-modules-for-lua/)
