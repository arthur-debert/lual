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


2. Implementation: 
    
    Critical : there is no backwards compatibility layer. This lib is unreleased and it will be crazy for it
    to pay the deprecation and multiple implementation costs just to avoid updating tests.
    We do full switch.

    2.1 Get the config schema correct: 
        - name is not part of the config
        - local should be moved to presenters (can be a variable to each one)
    
    2.2 Add UNSET level: 
        - at this point, just add it as the default for every non root logger.
        - don't change the code to use it.

    2.3 Root logger: 
        - validate that user logger's name cannot start with a _. note that a module can start with a _, so if it does, we must change that to something else.
        - change default logger name to _root.

    2.4. Implement Root Configure
        - the lual.config({}) call
        - only set keys with valid values should update the default root logger  
        - not that if multiple config() calls are made, we update always the default config with the given table (not the previously set config)

    2.5 Implement get_effective_level method for loggers

        - this will walk the tree returning the first non empty level value (UNSET) .

    2.6 Implement logger.will_dispatch: 
        - it uses get_effective_level for getting the level and level matching. 
        - if positive it looks at the loggers config for dispatchers (not parrents, must be set on this logger)
        - if both are true (effective_level >= log.level) and logger.dispatchers len >=1 returns true false otherwise

    2.7 Implement configuring non root loggers
        - alter the logger('name", config_table) api to only set keys passed in.
        - if not passed, propagate is inserted as true.
        - if not set, level is UNSET

    2.8 Alter the dispatch loop: 
        - create a new function , for now set it as a flag, and unless instructed it uses the old code (ingest)
        - does the tree walk, using will_dispatch, and effective levels.
        - write separate tests, most of the test suite should run as before
        - write good tests for the subtle details in this design (UNSET , dispatchers required to be set, etc)

    2.9 When we are happy with the result.
        - remove the old ingest code path.
        - look at tests failures. 
            - for tests that tested the old behavior, we can delete them (since our new tests cover this)
            - if they tested other wise, but the new behavior breaks them , fix them
        

    
