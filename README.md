lual log: A New Lua Logging Library (Project [Placeholder Name])

Vision & Introduction

The Lua landscape for logging libraries presents an opportunity for a robust,
developer-friendly solution. Inspired by the power and flexibility of Python's
standard logging module, this project aims to create a new logging library for
Lua that is both powerful and intuitive.

Our vision is to develop a library that captures the essential features of a
modern logging system—configurability, different output handlers, customizable
formatting, and fine-grained level control—while adhering to Lua's idiomatic
style. We aim for a "slightly smaller" footprint than Python's comprehensive
module but one that effectively covers "most of the things" a developer needs
for effective application logging.

This document serves as a kickstarting guide for the development team, outlining
the core ideas, features, and principles that will guide our work.

Core Features

The library will be built around the following core features, designed from
first principles:

1.  Central Logging Engine:

    - Manages log messages, logger instances, and their hierarchy.
    - Filters messages based on logger names and severity levels.
    - Dispatches messages to the appropriate handlers.

2.  Loggers with Hierarchical Naming:

    - Loggers are named using dot-separated paths (e.g.,
      `myapp.module.submodule`).
    - Configuration (like log levels) can be applied to specific loggers or
      partial paths (e.g., `myapp.module.*`).

3.  Log Levels:

    - Standard severity levels (e.g., DEBUG, INFO, WARNING, ERROR, CRITICAL).
    - Ability to set log levels per logger or logger name pattern, controlling
      output verbosity.

4.  Handlers:

    - Responsible for dispatching log records to various destinations.
    - Initial simple handlers:
      - `StreamHandler`: Outputs to `io.stdout` (default) or `io.stderr`.
      - `FileHandler`: Outputs to a specified file.
    - Designed to be extensible with custom handlers.

5.  Formatters:

    - Control the layout of log records.
    - Initial simple formatters:
      - `PlainTextFormatter`: Outputs a clean, human-readable text format.
      - `ColorFormatter`: Outputs text with ANSI color codes for enhanced
        readability in terminals.
    - Designed to be extensible with custom formatters.

6.  Message Propagation:

    - Log messages will propagate upwards through the logger hierarchy by
      default (e.g., a message to `myapp.module` also goes to `myapp` and the
      root logger's handlers).
    - Propagation can be disabled on a per-logger basis.

7.  Contextual Information:

    - Timestamping: Log records will automatically include a timestamp generated
      at the time of the event.
    - Caller Information: The library will capture the source filename and line
      number where the log message was emitted, aiding in debugging.

8.  Robust Error Handling:
    - Errors occurring within handlers or formatters (e.g., file write error)
      will be caught and reported to `io.stderr`, preventing the logging system
      itself from crashing the application.

Design & Code Principles

To ensure a high-quality, maintainable, and easy-to-use library, we will adhere
to the following principles:

1.  Lua-Idiomatic Design:

    - Leverage Lua's strengths, such as first-class functions and flexible
      table-based structures.
    - Prefer functional approaches for components like handlers and formatters
      where appropriate, potentially reducing the need for complex object
      hierarchies if simple functions with defined signatures suffice.

2.  Modularity and Composability:

    - Design components (engine, loggers, handlers, formatters) with clear
      responsibilities.
    - Break down complex logic into smaller, well-defined functions. This
      enhances readability and allows components to be combined flexibly.

3.  Testability:

    - Prioritize writing code that is easy to test. Smaller functions and clear
      interfaces are key to this.
    - Aim for high unit test coverage to ensure reliability and catch
      regressions.

4.  Clarity and Simplicity:

    - The API should be intuitive and easy for developers to learn and use.
    - While powerful, the internal workings should strive for simplicity where
      possible without sacrificing essential functionality.

5.  Performance Awareness:

    - Logging can be performance-sensitive. While features like caller info
      capture are valuable, we should be mindful of potential overhead and
      consider optimizations or configurability for performance-critical
      sections if necessary.

6.  Extensibility:
    - Users should be able to easily create and integrate their own custom
      handlers and formatters. This will likely involve clear function
      signatures and registration mechanisms.

High-Level API Sneak Peek

The following illustrates a potential way users might interact with the library
(names and exact signatures are subject to refinement):

-- sample usage local log = require("your_logger_module_name") -- To be defined

      -- Basic Configuration (Example)
      log.set_level("myapp.network.*", log.levels.DEBUG) -- Set DEBUG for all network modules
      log.add_handler("*", log.handlers.stream_handler, log.formatters.color_formatter)
      log.add_handler("myapp.critical_ops", log.handlers.file_handler, log.formatters.plain_formatter, {
          filepath = "/var/log/myapp_critical.log"
      })

      -- Getting a logger instance
      local network_logger = log.get_logger("myapp.network.protocol")
      local ui_logger = log.get_logger("myapp.ui.events")

      -- Logging messages
      network_logger:debug("Packet received from %s", "10.0.0.1")
      ui_logger:info("User clicked button: %s", "submit_form")

      -- Or using direct logging functions (potentially operating on the root logger or a named logger)
      log.warn("global.config", "Old configuration value detected for 'timeout'.")
      log.error("myapp.database", "Failed to connect to database: %s", db_error_message)

-- lua
