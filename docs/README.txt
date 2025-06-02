As the software is feature complete and soon to be released, we're working on the final 
documentation and  testing. In this process, we've found problems from minor to significant.

As the library grew organically, without a high level design, as the many refactors and renaming 
took place the code  has, in various places, become hard to understand , inconsistent and complex.


As a final push, we're doing : 

1. Design:  DONE
    We have a final design to follow. 
        - Foundational terms: docs/pre-release/glossary.txt
        - Tree/Names: docs/pre-release/logger-trees.txt
        - The design:   docs/pre-release/design.txt


2. Implementation Plan:

    Critical Note: There is no backwards compatibility layer. This library is
    unreleased. We will perform a full switch to the new design to avoid the
    costs of deprecation and multiple implementations. Existing tests will need
    to be updated or replaced to reflect the new, correct behavior.

        We should run the two designs in paralel while unfinished . Else, most test wil break at the very
    early phases of this work, and with most of the suite broken we either risk introducing many new bugs, or 
    having to fix them (which means implementting the new design). 

    we shall have in lual/v2/config -> all configuration related settins
    lual/v2/dispatch_loop -> the dispatch loop
    add a property to v2 to lual root so that lual.v2.logger() hits the new api, so does lual.v2.config()

    2.1. Logger and Configuration Structure Changes: DONE
        - Ensure `name` is not a configurable property within a logger's settings.
          It is an identifier.
        - Time configuration (e.g., UTC/local, format string) should be a property
          of Presenters, not a top-level logger or dispatcher setting.
          Refer to `new-design.txt` for details. DONE

    2.2. Introduce `lual.NOTSET` Level: DONE
        - Add this special level value (e.g., could be `0` or a unique table).
        - Non-root loggers will default to `level = lual.NOTSET`.
        - This signifies that the logger should inherit its effective level from
          its closest configured ancestor.

    2.3. Root Logger (`_root`): DONE
        - Implement the internal root logger, named `_root`.
        - Ensure user-defined logger names cannot start with `_`. If an auto-generated
          name (e.g., from module path) starts with `_`, it must be prefixed or altered.
        - `_root` is automatically created when `lual` is loaded and initialized with
          library defaults (e.g., level `lual.WARN`, a console dispatcher, default
          presenter, `propagate = true`).

    2.4. Implement `lual.config(config_table)`: DONE
        - This function is the HAPI for user configuration of the `_root` logger.
        - When called, it updates `_root`'s existing configuration with the values
          provided in `config_table`.
        - If `config_table` contains a `level` key, `_root.level` is updated.
        - If `config_table` contains a `dispatchers` key, `_root.dispatchers` are
          replaced with the new list.
        - Keys not present in `config_table` will leave `_root`'s corresponding
          settings unchanged from their current state (either library defaults or
          values from a previous `lual.config()` call).

    2.5. Implement Effective Level Calculation: DONE
        - Create a method or internal function for loggers, say `logger:_get_effective_level()`.
        - If `self.level` is not `lual.NOTSET`, return `self.level`.
        - Else, if `self` is `_root`, return `_root.level` (it must have an explicit level).
        - Else, recursively call `self.parent:_get_effective_level()`.

    2.6. Implement Non-Root Logger Configuration:
        - The `lual.logger("name", config_table)` API (and imperative methods like
          `logger:set_level()`, `logger:add_dispatcher()`) should only store the
          explicitly provided settings in the logger's internal config table.
        - Default initial state for a new non-root logger:
            - `level = lual.NOTSET`
            - `dispatchers = {}` (empty list)
            - `propagate = true`

    2.7. Implement the New Dispatch Loop Logic:
        - This is the core of event processing for each logger `L` in the hierarchy
          (from source up to `_root`).
        - For a given log event:
            1. Calculate `L`'s effective level using `L:_get_effective_level()`.
            2. If `event_level >= L.effective_level` (level match):
                a. For each dispatcher in `L`'s *own* `dispatchers` list:
                   i. (Optional) Process record through `L`'s transformers.
                   ii. Format record using the dispatcher's presenter.
                   iii. Send formatted output via the dispatcher.
                b. If `L` has no dispatchers, it produces no output itself.
            3. If `L.propagate` is `true` AND `L` is not `_root`:
                a. Pass the original event to `L.parent` to repeat this process.

        - Transitional Strategy: if the format is the new x, should pass thorugh the new dispartch
        - Write comprehensive tests for the new dispatch logic, specifically covering:
            - Correct `lual.NOTSET` level inheritance.
            - Dispatching only occurs if a logger has its own dispatchers AND the
              level matches.
            - Propagation logic (including `propagate = false`).
            - `lual.config()` behavior for `_root`.
            - Behavior of various logger configurations and their interactions.

    2.9. Final Switch & Test Suite Update:
        - Once the new implementation is verified by its dedicated tests:
            - Remove any old dispatch code paths.
            - Review the existing test suite:
                - Tests that validated old, incorrect behaviors should be deleted
                  (as new tests cover the correct design).
                - Tests that cover valid use cases but fail due to the new, correct
                  behavior should be updated to expect the new outcomes.

This plan provides a structured approach to refactoring the logging system
to the new, robust design.

Important: 

    * These imply quite large changes, the heavy settigs config / validation among all. 
    * In reality, there will be very little code new in this implementation, the bulkd of the work is about
