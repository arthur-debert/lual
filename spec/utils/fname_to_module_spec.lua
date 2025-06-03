describe("fname_to_module", function()
    local fname_to_module = require("lual.utils.fname_to_module")

    before_each(function()
        fname_to_module.clear_cache()
    end)

    describe("get_module_path", function()
        it("should handle nil and invalid inputs", function()
            assert.is_nil(fname_to_module.get_module_path(nil))
            assert.is_nil(fname_to_module.get_module_path(""))
            assert.is_nil(fname_to_module.get_module_path("[C]"))
            assert.is_nil(fname_to_module.get_module_path("(tail call)"))
        end)

        it("should remove @ prefix from debug.getinfo paths", function()
            local result = fname_to_module.get_module_path("@test.lua", { "./?.lua" })
            assert.is_not_nil(result)
            assert.equals("test", result)
        end)

        it("should handle normal .lua files with package path templates", function()
            local path_templates = {
                "./?.lua",
                "/usr/local/share/lua/5.1/?.lua"
            }

            assert.equals("my_module", fname_to_module.get_module_path("./my_module.lua", path_templates))
            local result = fname_to_module.get_module_path("/usr/local/share/lua/5.1/my/module.lua", path_templates)
            assert.equals("usr.local.share.lua.5.1.my.module", result)
        end)

        it("should handle init.lua files specially", function()
            local path_templates = { "./?.lua", "./?/init.lua" }

            assert.equals("mymodule", fname_to_module.get_module_path("./mymodule/init.lua", path_templates))
            local result = fname_to_module.get_module_path("./my/module/init.lua", path_templates)
            assert.equals("module", result)
        end)

        it("should handle special ./src pattern", function()
            assert.equals("utils", fname_to_module.get_module_path("./src/utils.lua", {}))
        end)

        it("should use fallback for non-.lua files", function()
            local result = fname_to_module.get_module_path("./path/to/script", {})
            assert.equals("path.to.script", result)
        end)

        it("should use file basename as fallback when no template matches", function()
            local result = fname_to_module.get_module_path("/some/path/module.lua", { "/different/path/?.lua" })
            assert.equals("module", result)
        end)

        it("should cache results for performance", function()
            assert.equals(0, fname_to_module.get_cache_size())

            local path = "/test/module.lua"
            fname_to_module.get_module_path(path, { "./?.lua" })

            assert.equals(1, fname_to_module.get_cache_size())

            -- Calling again should use cache
            fname_to_module.get_module_path(path, { "./?.lua" })
            assert.equals(1, fname_to_module.get_cache_size())
        end)
    end)

    describe("_match_template", function()
        it("should match paths against templates correctly", function()
            local match_template = fname_to_module._match_template

            assert.equals("test", match_template("/path/to/test.lua", "/path/to/?.lua"))
            assert.equals("my.module", match_template("/path/to/my/module.lua", "/path/to/?.lua"))
            local result = match_template("/path/to/module/init.lua", "/path/to/?/init.lua")
            assert.is_nil(result)
        end)
    end)

    describe("_process_path", function()
        it("should process paths correctly", function()
            local process_path = fname_to_module._process_path

            -- Test normal .lua file
            local abs_path, orig_path, early_fallback = process_path("./module.lua")
            assert.is_not_nil(abs_path)
            assert.equals("./module.lua", orig_path)
            assert.is_nil(early_fallback)

            -- Test init.lua file
            abs_path, orig_path, early_fallback = process_path("./my/module/init.lua")
            assert.is_not_nil(abs_path)
            assert.equals("./my/module/init.lua", orig_path)
            assert.equals("module", early_fallback)

            -- Test non-.lua file
            abs_path, orig_path, early_fallback = process_path("./script")
            assert.is_not_nil(abs_path)
            assert.equals("./script", orig_path)
            assert.equals("script", early_fallback)
        end)
    end)

    describe("_generate_fallback_name", function()
        it("should generate fallback names correctly", function()
            local generate_fallback = fname_to_module._generate_fallback_name

            assert.equals("module", generate_fallback("/path/to/module.lua"))
            assert.equals("script", generate_fallback("/path/to/script"))
        end)
    end)
end)
