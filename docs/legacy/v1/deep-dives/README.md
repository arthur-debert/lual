# lual Deep Dives

This section provides in-depth technical explanations of lual's internal architecture and advanced features. These guides are intended for developers who want to understand how lual works under the hood or who need to extend its functionality.

## Deep Dive Topics

### 1. **[Logger Hierarchy](logger-hierarchy.md)**
Detailed explanation of the logger tree system.
- Tree structure implementation
- Name resolution and parent-child relationships
- Effective level calculation algorithm
- Propagation mechanics

### 2. **[Pipeline System](pipeline-system.md)**
Comprehensive guide to the event processing pipeline.
- Pipeline architecture
- Transformers, presenters, and outputs
- Event flow from emission to output
- Component interface contracts
- Error handling and isolation

### 3. **[Configuration System](configuration-system.md)**
How configuration works internally.
- Root logger initialization
- Configuration normalization
- Schema validation
- Default values
- Merging and inheritance

### 4. **[Component Development](component-development.md)**
Guide to creating custom pipeline components.
- Transformer implementation
- Presenter development
- Output creation
- Component API contracts
- Testing components

## Target Audience

These deep dives are aimed at:
- **Library Maintainers**: Those contributing to lual itself
- **Advanced Users**: Developers extending lual with custom components
- **Integration Developers**: Those building lual into larger systems
- **Curious Developers**: Anyone who wants to understand the implementation details

## Prerequisites

To get the most from these guides, you should already be familiar with:
- Basic lual usage (see [Getting Started](../getting-started/))
- Lua programming language
- Software design patterns

## Related Resources

- **[API Reference](../reference/)** - Technical specifications
- **[Examples](../examples/custom-components.md)** - Working code examples
- **Source code** - The ultimate reference 