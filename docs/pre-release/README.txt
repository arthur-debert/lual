As the software is feature complete and soon to be released, we're working on the final 
documentation and  testing. In this process, we've found problems from minor to significant.

As the library grew organically, without a high level design, as the many refactors and renaming 
took place the code  has, in various places, become hard to understand , inconsistent and complex.


As a final push, we're doing : 

1. What we are building:
    This work is not about what the system is doing, but about what the system should do. 
    Reading the source code is helpful for more information, but should not be read as what needs to happen.

    1.1 The Glossary:  docs/glossary.txt
        A formal definition of the names and their concepts. This is paramount as currently the same 
        concepts are represented with multiple names and conflicting definitions.
    STATUS: WIP

    1.2. The log event flow: 
        A high level description of the expected behavior  from logger.log up to the final output for that event.

    1.3. Hierarchy and Propagation
        How multiple loggers interact.

    1.4. Configuration and the Chain
        How the hierarchy affects each logger's behavior.


2. The current system
    Here we document the code's behavior

    2.1 The log event flow

    2.2 Hierarchy and Propagation

    3.3 Configuration and Chain


All the material should be docs/pre-release to keep it a part from the older work.
All of it must be in plain text, no markdown. Follow the formatting from this file and glossary.txt for a ref.