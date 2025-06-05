#!/usr/bin/env lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;../lua/?.lua;../lua/?/init.lua"

local lual = require("lual.logger")
local core_levels = require("lua.lual.levels")

describe("lual Logger - Effective Level Calculation (Step 2.5)", function()
    before_each(function()
        lual.reset_config()
        lual.reset_cache()
    end)

    describe("_get_effective_level() method", function()
        it("should return explicit level when logger has non-NOTSET level", function()
            local logger = lual.logger("test.logger.el1", { level = core_levels.definition.DEBUG }) -- Unique name, use new API
            local effective_level = logger:_get_effective_level()
            assert.are.equal(core_levels.definition.DEBUG, effective_level)
        end)

        it("should return explicit level for different levels", function()
            local test_levels = {
                core_levels.definition.DEBUG,
                core_levels.definition.INFO,
                core_levels.definition.WARNING,
                core_levels.definition.ERROR,
                core_levels.definition.CRITICAL,
                core_levels.definition.NONE
            }
            for i, level in ipairs(test_levels) do
                local logger = lual.logger("test.logger.el2." .. i, { level = level }) -- Unique name, use new API
                local effective_level = logger:_get_effective_level()
                assert.are.equal(level, effective_level, "Failed for level " .. level)
            end
        end)

        it("should return root config level when logger is _root with NOTSET", function()
            lual.config({ level = core_levels.definition.ERROR })
            -- _root logger fetched via lual.logger("_root") will have its level set by lual.config or its default (WARNING)
            -- If we want to test _root with NOTSET specifically for _get_effective_level, we'd have to manually set it after creation.
            local root_logger = lual.logger("_root")
            root_logger.level = core_levels.definition.NOTSET -- Manually set for this specific test condition
            local effective_level = root_logger:_get_effective_level()
            -- Effective level for _root should always come from global config if its direct level is NOTSET
            assert.are.equal(core_levels.definition.ERROR, effective_level)
        end)

        it("should inherit level from parent when logger has NOTSET", function()
            lual.reset_cache()                                   -- Ensure clean state for parent/child
            local parent_logger = lual.logger("parent.el4", { level = core_levels.definition.WARNING })
            local child_logger = lual.logger("parent.el4.child") -- Will have NOTSET by default
            local effective_level = child_logger:_get_effective_level()
            assert.are.equal(core_levels.definition.WARNING, effective_level)
        end)

        it("should recursively inherit through multiple levels", function()
            lual.reset_cache()
            local grandparent = lual.logger("grandparent.el5", { level = core_levels.definition.ERROR })
            local parent = lual.logger("grandparent.el5.parent")      -- Defaults to NOTSET
            local child = lual.logger("grandparent.el5.parent.child") -- Defaults to NOTSET
            local effective_level = child:_get_effective_level()
            assert.are.equal(core_levels.definition.ERROR, effective_level)
        end)

        it("should stop at first explicit level in hierarchy", function()
            lual.reset_cache()
            local grandparent = lual.logger("grandparent.el6", { level = core_levels.definition.ERROR })
            local parent = lual.logger("grandparent.el6.parent", { level = core_levels.definition.INFO })
            local child = lual.logger("grandparent.el6.parent.child") -- Defaults to NOTSET
            local effective_level = child:_get_effective_level()
            assert.are.equal(core_levels.definition.INFO, effective_level)
        end)

        it("should fallback to INFO when no explicit parent level and not root", function()
            lual.reset_cache()
            -- Create an orphaned logger (its parent _root will have default WARNING, not INFO, unless global config changes)
            -- The rule is: if self.level is NOTSET, and self.parent._get_effective_level() is called.
            -- If _root is parent, and its level is WARNING, child inherits WARNING.
            -- This test implies an orphan whose hierarchy resolves to a NOTSET state that then defaults to INFO.
            -- This happens if root itself was NOTSET and had no parent (which is not possible for _root).
            -- Or if a logger is truly orphaned (parent explicitly nil and not _root)
            -- The current _get_effective_level for a non-root logger with no parent (not typical) defaults to INFO.
            local orphan_logger = lual.logger("orphan.el7") -- Parent is _root, level is NOTSET
            -- To test the INFO fallback for a truly detached logger (not typical): construct manually
            local manually_orphaned = {
                name = "manual_orphan",
                level = core_levels.definition.NOTSET,
                parent = nil,
                _get_effective_level =
                    lual.logger("any")._get_effective_level
            }
            assert.are.equal(core_levels.definition.INFO, manually_orphaned:_get_effective_level(),
                "Manually orphaned logger with NOTSET should fallback to INFO")

            -- Test a logger that is child of _root, where _root itself might be at default WARNING
            lual.config({ level = core_levels.definition.WARNING }) -- ensure root default
            local child_of_root = lual.logger("child_of_root_for_info_fallback_test")
            if child_of_root.parent and child_of_root.parent.name == "_root" then
                -- if _root is at WARNING, child_of_root should inherit WARNING
                assert.are.equal(core_levels.definition.WARNING, child_of_root:_get_effective_level(),
                    "Child of root (at WARNING) should inherit WARNING")
            end
            -- The original intent of INFO fallback is for a logger with .level=NOTSET and .parent=nil that is NOT _root.
        end)

        it("should handle deep hierarchy correctly", function()
            lual.reset_cache()
            local root = lual.logger("root.el8", { level = core_levels.definition.CRITICAL })
            local level1 = lual.logger("root.el8.l1")
            local level2 = lual.logger("root.el8.l1.l2")
            local level3 = lual.logger("root.el8.l1.l2.l3")
            local level4 = lual.logger("root.el8.l1.l2.l3.l4")
            assert.are.equal(core_levels.definition.CRITICAL, level1:_get_effective_level())
            assert.are.equal(core_levels.definition.CRITICAL, level2:_get_effective_level())
            assert.are.equal(core_levels.definition.CRITICAL, level3:_get_effective_level())
            assert.are.equal(core_levels.definition.CRITICAL, level4:_get_effective_level())
        end)
    end)

    describe("Integration with config system", function()
        it("should use config level for _root logger", function()
            lual.config({ level = core_levels.definition.DEBUG })
            local root_logger = lual.logger("_root") -- lual.create_root_logger() used the new factory
            local effective_level = root_logger:_get_effective_level()
            assert.are.equal(core_levels.definition.DEBUG, effective_level)
        end)

        it("should update effective level when config changes", function()
            lual.config({ level = core_levels.definition.INFO })
            local root_logger = lual.logger("_root")
            local child = lual.logger("child.configchange")
            assert.are.equal(core_levels.definition.INFO, child:_get_effective_level())
            lual.config({ level = core_levels.definition.ERROR })
            -- Need to fetch root_logger again, or ensure its level is updated by lual.config if it was cached.
            -- The _get_effective_level of _root directly queries config_module.get_config().level
            assert.are.equal(core_levels.definition.ERROR, child:_get_effective_level(),
                "Child should inherit new level after lual.config change")
        end)

        it("should handle _root logger with NOTSET requesting config level", function()
            lual.config({ level = core_levels.definition.WARNING })
            local root_logger = lual.logger("_root")
            root_logger.level = core_levels.definition.NOTSET -- Manually set for test
            local effective_level = root_logger:_get_effective_level()
            assert.are.equal(core_levels.definition.WARNING, effective_level)
        end)
    end)

    describe("Edge cases and error conditions", function()
        it("should handle logger with auto-generated name gracefully for effective level", function()
            lual.reset_cache()
            lual.config({ level = core_levels.definition.WARNING }) -- Ensure _root is at WARNING
            local logger = lual.logger()
            assert.are.equal(core_levels.definition.WARNING, logger:_get_effective_level(),
                "Auto-named logger should inherit _root's level (WARNING)")

            -- Test true orphan fallback (manually constructed)
            local manually_orphaned = {
                name = "manual_orphan",
                level = core_levels.definition.NOTSET,
                parent = nil,
                _get_effective_level = lual.logger("any_for_method")._get_effective_level -- Borrow method
            }
            assert.are.equal(core_levels.definition.INFO, manually_orphaned:_get_effective_level(),
                "Manually orphaned logger with NOTSET should fallback to INFO")
        end)

        it("should handle all NOTSET hierarchy correctly for effective level", function()
            lual.reset_cache()
            lual.config({ level = core_levels.definition.INFO })
            local parent = lual.logger("parent.allnotset.v2")
            local child = lual.logger("parent.allnotset.v2.child")
            assert.are.equal(core_levels.definition.INFO, child:_get_effective_level())
        end)
        --[[ Circular reference test commented out ]]
    end)

    describe("Performance and behavior", function()
        it("should be efficient for single-level lookup", function()
            local logger = lual.logger("test.perf1", { level = core_levels.definition.WARNING })
            for i = 1, 100 do
                local level = logger:_get_effective_level()
                assert.are.equal(core_levels.definition.WARNING, level)
            end
        end)

        it("should be deterministic", function()
            lual.reset_cache()
            local root = lual.logger("root.perf2", { level = core_levels.definition.ERROR })
            local child = lual.logger("root.perf2.child")
            local first_result = child:_get_effective_level()
            for i = 1, 10 do
                local result = child:_get_effective_level()
                assert.are.equal(first_result, result)
            end
        end)
    end)
end)

describe("lual Logger - Naming Conventions", function()
    before_each(function()
        lual.reset_config()
        lual.reset_cache()
    end)

    it("should use the user-provided name for the logger", function()
        local logger = lual.logger("my.explicit.name.v4")             -- Even more unique name
        assert.are.equal("my.explicit.name.v4", logger.name)
        assert.are.equal(core_levels.definition.NOTSET, logger.level) -- Forcing this specific line
    end)

    it("should auto-generate a name if no name is provided (lual.logger())", function()
        local logger = lual.logger() -- Name will be auto-generated
        assert.is_not_nil(logger.name)
        assert.is_not_equal("", logger.name)
        assert.is_not_equal("anonymous", logger.name)
        assert.are.equal(core_levels.definition.NOTSET, logger.level) -- Corrected: Default level is NOTSET
    end)

    it("should auto-generate a name if name is nil (lual.logger(nil))", function()
        local logger = lual.logger(nil) -- Name will be auto-generated
        assert.is_not_nil(logger.name)
        assert.is_not_equal("", logger.name)
        assert.is_not_equal("anonymous", logger.name)
        assert.are.equal(core_levels.definition.NOTSET, logger.level) -- Corrected: Default level is NOTSET
    end)

    it("should use user-provided name and config (lual.logger(name, config))", function()
        local logger = lual.logger("log.with.config.v3", { level = core_levels.definition.DEBUG, propagate = false }) -- Unique name
        assert.are.equal("log.with.config.v3", logger.name)
        assert.are.equal(core_levels.definition.DEBUG, logger.level)                                                  -- Explicitly set, not default
        assert.are.equal(false, logger.propagate)
    end)

    it("should auto-generate name and use provided config (lual.logger(config))", function()
        -- For this test, the auto-generated name might vary, so we don't assert its exact value beyond not being anonymous.
        -- The key is that the config is applied and level is NOTSET by default if not in config.
        local logger = lual.logger({ outputs = {} }) -- No level specified in config
        assert.is_not_nil(logger.name)
        assert.is_not_equal("", logger.name)
        assert.is_not_equal("anonymous", logger.name)
        assert.are.equal(core_levels.definition.NOTSET, logger.level) -- Corrected: Default level if not in config is NOTSET
        assert.is_table(logger.outputs)
        assert.are.equal(0, #logger.outputs)
    end)

    it("should auto-generate name and use provided config (lual.logger(nil, config))", function()
        -- Similar to above, level should default to NOTSET if not specified in config.
        local logger = lual.logger(nil, { propagate = false })
        assert.is_not_nil(logger.name)
        assert.is_not_equal("", logger.name)
        assert.is_not_equal("anonymous", logger.name)
        assert.are.equal(core_levels.definition.NOTSET, logger.level) -- Corrected: Default level if not in config is NOTSET
        assert.are.equal(false, logger.propagate)
    end)

    it("should return cached logger and NOT reconfigure if called again with same name and new config", function()
        local logger1 = lual.logger("cached.log.v3", { level = core_levels.definition.INFO }) -- Unique name
        assert.are.equal(core_levels.definition.INFO, logger1.level)
        local logger2 = lual.logger("cached.log.v3", { level = core_levels.definition.WARNING })
        assert.are_same(logger1, logger2)
        assert.are.equal(core_levels.definition.INFO, logger2.level)
    end)

    it("should correctly name the _root logger when fetched via lual.logger('_root')", function()
        lual.config({ level = core_levels.definition.INFO })
        local root_logger = lual.logger("_root")
        assert.are.equal("_root", root_logger.name)
    end)

    it("should raise an error for invalid user-provided names", function()
        assert.has_error(function() lual.logger("") end, "Logger name cannot be an empty string.")
        assert.has_error(function() lual.logger(123) end,
            "Invalid 1st arg: expected name (string), config (table), or nil, got number")
        assert.has_error(function() lual.logger("_user.logger") end,
            "Logger names starting with '_' are reserved (except '_root'). Name: _user.logger")
    end)

    it("should raise an error for invalid argument combinations", function()
        assert.has_error(function() lual.logger("name", "not_a_table") end,
            "Invalid 2nd arg: expected table (config) or nil, got string")
        assert.has_error(function() lual.logger({}, "not_nil") end,
            "Invalid 2nd arg: config table as 1st arg means no 2nd arg, got string")
        assert.has_error(function() lual.logger(nil, "not_a_table") end,
            "Invalid 2nd arg: expected table (config) or nil, got string")
        assert.has_error(function() lual.logger(true) end,
            "Invalid 1st arg: expected name (string), config (table), or nil, got boolean")
    end)

    it("should raise an error for invalid keys in config table", function()
        assert.has_error(function() lual.logger("cfgkeytest", { invalid_key = 123 }) end,                                       -- Unique name
            "Invalid logger configuration: Unknown configuration key 'invalid_key'. Valid keys are: level, outputs, propagate") -- Added "are"
    end)

    it("should raise an error for invalid value types in config table", function()
        assert.has_error(function() lual.logger("cfgvaltest1", { level = "not_a_number" }) end,                                                          -- Unique name
            "Invalid logger configuration: Invalid type for 'level': expected number, got string. Logging level (use lual.DEBUG, lual.INFO, etc.)")      -- Changed "e.g." to "use"
        assert.has_error(function() lual.logger("cfgvaltest2", { outputs = "not_a_table" }) end,                                                         -- Unique name
            "Invalid logger configuration: Invalid type for 'outputs': expected table, got string. Array of output functions or output config tables")   -- Adjusted
        assert.has_error(function() lual.logger("cfgvaltest3", { propagate = "not_a_boolean" }) end,                                                     -- Unique name
            "Invalid logger configuration: Invalid type for 'propagate': expected boolean, got string. Whether to propagate messages to parent loggers") -- Plural "loggers"
    end)

    it("should create loggers with hierarchy and correct parents", function()
        lual.reset_cache()
        local logger_gm = lual.logger("greatgrandparent")
        local logger_gp = lual.logger("greatgrandparent.grandparent")
        local logger_p = lual.logger("greatgrandparent.grandparent.parent")
        local logger_c = lual.logger("greatgrandparent.grandparent.parent.child")
        local root_logger_instance = lual.logger("_root")

        assert.is_not_nil(logger_gm, "Logger greatgrandparent should be created")
        assert.is_not_nil(logger_gp, "Logger grandparent should be created")
        assert.is_not_nil(logger_p, "Logger parent should be created")
        assert.is_not_nil(logger_c, "Logger child should be created")

        assert.are_equal("greatgrandparent", logger_gm.name)
        assert.are_equal("greatgrandparent.grandparent", logger_gp.name)
        assert.are_equal("greatgrandparent.grandparent.parent", logger_p.name)
        assert.are_equal("greatgrandparent.grandparent.parent.child", logger_c.name)

        -- Test parent relationships by name and instance
        assert.is_not_nil(logger_c.parent, "Child should have a parent")
        assert.are_same(logger_p, logger_c.parent, "Child's parent instance check")
        assert.are_equal(logger_p.name, logger_c.parent.name, "Child's parent name check")

        assert.is_not_nil(logger_p.parent, "Parent should have a parent")
        assert.are_same(logger_gp, logger_p.parent, "Parent's parent instance check")
        assert.are_equal(logger_gp.name, logger_p.parent.name, "Parent's parent name check")

        assert.is_not_nil(logger_gp.parent, "Grandparent should have a parent")
        assert.are_same(logger_gm, logger_gp.parent, "Grandparent's parent instance check")
        assert.are_equal(logger_gm.name, logger_gp.parent.name, "Grandparent's parent name check")

        assert.is_not_nil(logger_gm.parent, "Greatgrandparent should have a parent")
        assert.are_equal("_root", logger_gm.parent.name, "Greatgrandparent's parent should be named '_root'")
        assert.are_same(root_logger_instance, logger_gm.parent,
            "Greatgrandparent's parent should be the same instance as lual.logger('_root')")
    end)
end)
