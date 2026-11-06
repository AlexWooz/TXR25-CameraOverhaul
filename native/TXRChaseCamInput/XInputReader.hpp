#pragma once

// Reads the right stick straight from XInput. TXR's own input layer (Genki's GkInputPlatform)
// handles the gamepad outside the engine, so PlayerInput never sees it; XInput is shared, so we
// can read the same controller alongside the game.
namespace TXRChaseCam
{
    struct StickState
    {
        float x;        // -1 (left) .. 1 (right)
        float y;        // -1 (down) .. 1 (up)
        bool connected;
    };

    StickState read_right_stick();
}
