--- Configuration API (backward compatibility module)
-- This module maintains backward compatibility by forwarding all calls to the new config system

-- Simply forward all calls to the new modular config system
return require("lual.config.init")
