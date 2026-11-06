// TXRChaseCamInput: gives the TXRChaseCam Lua mod the real right-stick position.
//
// Installed as its own mod (Mods/TXRChaseCamInput/dlls/main.dll). It can't share the Lua mod's
// folder: UE4SS d4aebbf0 std::moves the folder name into the LuaMod and then builds the CppMod
// from the moved-from (empty) string. When the TXRChaseCam Lua mod starts, this registers a
// global function in each of its Lua states, including the hook state that RegisterHook
// callbacks (our camera update) run in:
//
//   local x, y, connected = TXRGetRightStick()
//
// x/y are -1..1 (right/up positive), with no dead zone applied.

#include <Mod/CppUserModBase.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>

#include "XInputReader.hpp"

namespace
{
    int lua_get_right_stick(const RC::LuaMadeSimple::Lua& lua)
    {
        TXRChaseCam::StickState s = TXRChaseCam::read_right_stick();
        lua.set_number(s.x);
        lua.set_number(s.y);
        lua.set_bool(s.connected);
        return 3;
    }

    void register_functions(RC::LuaMadeSimple::Lua& lua)
    {
        lua.register_function("TXRGetRightStick", lua_get_right_stick);
    }
}

class TXRChaseCamNative : public RC::CppUserModBase
{
public:
    TXRChaseCamNative() : CppUserModBase()
    {
        ModName = STR("TXRChaseCamInput");
        ModVersion = STR("1.0");
        ModDescription = STR("Right-stick reader for the TXRChaseCam Lua mod");
        ModAuthors = STR("AlexWooz");
    }

    ~TXRChaseCamNative() override = default;

    // Runs for every Lua mod that starts (including hot reloads); we only serve TXRChaseCam.
    auto on_lua_start(RC::StringViewType mod_name,
                      RC::LuaMadeSimple::Lua& lua,
                      RC::LuaMadeSimple::Lua& main_lua,
                      RC::LuaMadeSimple::Lua& async_lua,
                      RC::LuaMadeSimple::Lua* hook_lua) -> void override
    {
        if (mod_name != STR("TXRChaseCam"))
        {
            return;
        }
        register_functions(lua);
        register_functions(main_lua);
        register_functions(async_lua);
        if (hook_lua)
        {
            register_functions(*hook_lua);
        }
    }
};

#define TXR_CHASECAM_API __declspec(dllexport)
extern "C"
{
    TXR_CHASECAM_API RC::CppUserModBase* start_mod()
    {
        return new TXRChaseCamNative();
    }

    TXR_CHASECAM_API void uninstall_mod(RC::CppUserModBase* mod)
    {
        delete mod;
    }
}
