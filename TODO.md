# V1 TODO

- [x] Ingest logs event loop
- [x] Basic stream format (plain_formatter)
- [x] Basic console output
- [x] Levels and level filtering
- [x] Correct log message log data capture
- [x] Correct dispatch on logger name + level

# V1 Future Enhancements / Missing from initial README v1 feature list

- [ ] Dedicated `file_output` module (takes filepath in config)
- [x] `color_formatter` module
- [x] Pattern matching for global `log.set_level()` and `log.add_output()`
      (e.g., "myapp.\*")
- [x] Review and update README.md for full accuracy against current
      implementation
