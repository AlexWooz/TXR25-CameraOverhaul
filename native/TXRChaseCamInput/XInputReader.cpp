// Kept apart from dllmain.cpp so <Windows.h> never meets the UE4SS headers.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#include <Xinput.h>

#include "XInputReader.hpp"

namespace TXRChaseCam
{
    namespace
    {
        // XInputGetState on an empty slot is slow (it probes the device), so remember the
        // connected slot and only rescan once a second while none is found.
        int g_slot = -1;
        ULONGLONG g_last_scan = 0;

        float normalize(SHORT v)
        {
            float f = static_cast<float>(v) / 32767.0f;
            return f < -1.0f ? -1.0f : (f > 1.0f ? 1.0f : f);
        }
    }

    StickState read_right_stick()
    {
        XINPUT_STATE state{};
        if (g_slot >= 0)
        {
            if (XInputGetState(static_cast<DWORD>(g_slot), &state) == ERROR_SUCCESS)
            {
                return {normalize(state.Gamepad.sThumbRX), normalize(state.Gamepad.sThumbRY), true};
            }
            g_slot = -1;
        }

        ULONGLONG now = GetTickCount64();
        if (now - g_last_scan < 1000)
        {
            return {0.0f, 0.0f, false};
        }
        g_last_scan = now;
        for (DWORD i = 0; i < XUSER_MAX_COUNT; ++i)
        {
            if (XInputGetState(i, &state) == ERROR_SUCCESS)
            {
                g_slot = static_cast<int>(i);
                return {normalize(state.Gamepad.sThumbRX), normalize(state.Gamepad.sThumbRY), true};
            }
        }
        return {0.0f, 0.0f, false};
    }
}
