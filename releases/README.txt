luarocks release automates the entire process of releasing a LuaRocks rock.

It includes git integration and github releases (optional)

The most common use case: 

    ./bin/do-release.sh --bump patch

It expects this file structure


1. Gathering data
It should read the luaspec and extrac name and version (from the content, not the name)
it should ask user if he whished to release that version or bump (path, minot , major)

checks if version exists in luarocks, if so bails

2. Generate a new rockspect
it can now generate a rockspec

3. Prepare git: 
commit file, 
create git tag
builds package -> with or without rock, servers as validation

4. publishes to luarocks
