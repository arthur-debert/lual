# lual API Reference

This section provides comprehensive technical reference documentation for lual v1.0.0.

## Reference Sections

### 1. **[API Documentation](api.md)**
Complete documentation of all functions, methods, and parameters.
- Core functions (`lual.logger()`, `lual.config()`)
- Logger methods (`:info()`, `:debug()`, etc.)
- Configuration functions
- Public utilities

### 2. **[Configuration Schema](configuration-schema.md)**
Detailed documentation of all configuration options.
- Root logger configuration
- Logger-specific configuration
- Pipeline configuration
- Component configuration

### 3. **[Built-in Components](built-in-components.md)**
Documentation for all included components.
- **Outputs**: Console, File
- **Presenters**: Text, JSON, Color
- **Transformers**: None, Audit
- **Levels**: Debug, Info, Warn, Error, Critical

### 4. **[Glossary](glossary.md)**
Definitions of all technical terms used in lual.
- Logger concepts
- Pipeline architecture
- Event flow terminology
- Component terminology

## How to Use This Reference

This reference is designed for looking up specific details when implementing lual in your application. If you're new to lual, we recommend starting with the [Getting Started](../getting-started/) guide first.

## Code Examples

Each reference page includes relevant code examples demonstrating the API in context. For more complete examples, see the [Examples](../examples/) section.

## Version Information

This reference documents lual v1.0.0. API changes between versions are noted in the [Changelog](../../CHANGELOG.md). 