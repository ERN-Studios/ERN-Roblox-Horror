"""Execute generic installer's generated lookup/update payloads in offline Luau.

Only the existing fake DataModel and HttpService serialization boundary are
stubbed. The real commands and UpdateSourceAsync callback run in Luau; no Studio
connection, manifest write, script creation or real source overwrite occurs.
"""

from pathlib import Path
import sys

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

import install_new_scripts as installer
import fakestudio

JSON_BOUNDARY = r'''
local hs = game:GetService("HttpService")
local meta, previous = getmetatable(hs), getmetatable(hs).__index
meta.__index = function(self, key)
    if key == "JSONEncode" then
        return function(_, value)
            if value.missing then return "MISSING" end
            return value.class .. "|" .. tohex(value.source)
        end
    end
    return previous(self, key)
end
'''


def main():
    assert fakestudio.LUAU.is_file(), "Set LUAU_BIN to the real Luau interpreter"
    checks = 0
    for path in ("ServerScriptService.Probe", 'ServerScriptService.Pr\u00f8ve "\U0001f600"'):
        studio = fakestudio.FakeStudio()
        studio.add_script(path, "ModuleScript", "baseline")
        for source in ("return 1\n", 'local s = "\u00e9 \u00e6\u00f8\u00e5 \U0001f600"\nreturn s\n',
                       'quotes " backslash \\ controls \x00\x01\x08\t\r\n\x7f end'):
            assert studio.execute(installer.lua_update(path, source)) == "ok"
            assert studio.source_of(path).encode("utf-8") == source.encode("utf-8")
            checks += 2
            actual = studio.execute(JSON_BOUNDARY + installer.lua_lookup(path))
            kind, encoded = actual.split("|", 1)
            assert kind == "ModuleScript" and bytes.fromhex(encoded) == source.encode("utf-8")
            checks += 1
        assert studio.execute(JSON_BOUNDARY + installer.lua_lookup(path + "Missing")) == "MISSING"
        checks += 1
    print(f"generic installer payloads: {checks} checks passed (actual offline Luau)")


if __name__ == "__main__":
    main()
