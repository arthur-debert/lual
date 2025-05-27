You're right to think about file rotation. An infinitely growing log file is a
common pain point, especially for users who aren't yet familiar with external
tools like `logrotate`. Offering a basic, built-in rotation strategy is indeed
much more helpful for beginners.

Your suggestion to **rotate the file every time the process starts** is an
excellent starting point for a simple, effective strategy in a single-threaded
Lua environment.

Let's explore this and refine it slightly:

**Strategy: Rotate on Process Start with Limited Backups**

This is likely the best balance of simplicity, usefulness for beginners, and
implementability in pure Lua.

**How it Works:**

When the `FileHandler` (or `FileOutput` if you go with that name) is initialized
(typically when it's added to a logger and prepares to write its first message):

1.  **Check for Existing Backups:** Systematically rename older backup files to
    make space.
    - For example, if you configure it to keep `N` backups (e.g., `app.log.3`,
      `app.log.2`, `app.log.1`):
      - If `app.log.N` exists, delete it (or `app.log.(N-1)` becomes `app.log.N`
        in the next step, effectively overwriting).
      - Rename `app.log.(N-1)` to `app.log.N` (if `app.log.(N-1)` exists).
      - ...
      - Rename `app.log.1` to `app.log.2` (if `app.log.1` exists).
2.  **Rotate Current Log File:**
    - If the main log file (e.g., `app.log`) exists, rename it to the first
      backup name (e.g., `app.log.1`).
3.  **Open New Log File:**
    - The handler then opens the main log file path (e.g., `app.log`) fresh for
      writing new log entries.

**Example (keeping up to 3 backups: `app.log.1`, `app.log.2`, `app.log.3`):**

On application start, when the file handler for "app.log" initializes:

1.  Delete `app.log.3` if it exists.
2.  If `app.log.2` exists, rename it to `app.log.3`.
3.  If `app.log.1` exists, rename it to `app.log.2`.
4.  If `app.log` (the current log) exists, rename it to `app.log.1`.
5.  Open `app.log` as the new, empty log file.

**Pros:**

- **Simple to Implement:** Uses basic `os.rename` and `os.remove` (for the
  oldest backup), and `io.open`. No complex runtime logic, sizing checks, or
  date/time parsing during logging.
- **Clear Rotation Point:** Rotation occurs predictably at application startup.
- **No Runtime Logging Overhead:** Once the application is running, logging
  calls are not slowed down by rotation checks.
- **Helpful for Beginners:** Prevents the main log file from growing
  indefinitely across multiple application runs. Provides a history of recent
  logs.
- **Session-Specific Logs:** Each application run starts with a fresh log file,
  which can be very convenient for debugging specific sessions.
- **Pure Lua:** Doesn't require external libraries or C modules for this basic
  functionality.

**Cons:**

- **Long-Running Processes:** If an application instance runs for a very long
  time (days, weeks), the _current_ log file for that specific run can still
  grow very large. This strategy doesn't address runtime growth within a single
  process execution.
- **Basic Backup Management:** It's a simple numerical rotation. More advanced
  schemes (e.g., timestamped backups, size-then-count) are more complex.
- **Potential for Small Startup Delay:** The file renaming operations occur at
  startup. For a small number of backups, this is negligible, but it's a
  synchronous operation.

**Why this is good for a "simple" option:**

- It directly addresses the "infinitely growing file" problem across _restarts_,
  which is a major hurdle for less experienced users.
- It avoids the complexity and potential performance implications of runtime
  size/date checks in a single-threaded Lua environment (e.g., frequently
  calling `file:seek()`, `file:tell()`, or needing `LuaFileSystem` for file
  attributes).

**Implementation Notes:**

- The number of backups to keep should be configurable (e.g., a `max_backups`
  option for the file handler, defaulting to a sensible number like 3 or 5). If
  `max_backups` is 0, it would just delete the old log on startup and create a
  new one.
- Error handling for `os.rename` and `os.remove` is important (e.g., what if
  files are locked or permissions are denied?). At a minimum, log these errors
  to `io.stderr`.
- Ensure the order of renaming is correct to avoid accidentally overwriting
  files you mean to keep (e.g., rename `log.2` to `log.3` _before_ renaming
  `log.1` to `log.2`).

**Documentation is Key:**

When offering this, it's important to clearly document:

- How the rotation works (on startup, `N` backups).
- Its limitations (doesn't rotate long-running processes mid-run).
- That for more advanced scenarios (runtime size/time-based rotation,
  compression, complex archival), users should look to external tools like
  `logrotate`, `systemd-journald`, or platform-specific logging solutions.

This "rotate on start" approach provides a significant improvement over no
rotation at all, with minimal implementation complexity, making it a very
suitable default or optional feature for a file handler aimed at broad
usability.

This is the design we're going for with backup nums 5 file. file outputs should
receive a path , but always rotate to 5.
