-- TXR Chase Camera settings.
-- Change a value, save, and restart the game (or press Ctrl+R in the UE4SS console window).
-- Delete a line to go back to the mod's default; the UE4SS log reports typos and bad values.

return {
    -- Turn the whole mod on at start (Ctrl+F6 toggles it in game).
    Enabled = true,

    ---------------------------------------------------------------- Chase camera
    -- How quickly the camera swings back behind the car after a turn.
    -- Lower = looser (more side view in corners), higher = stiffer.
    LagSpeed = 2.5,
    -- Most the camera may trail behind the car's heading, in degrees.
    MaxOffset = 20,
    -- Extra distance / height for the close chase view (game units; 100 = about 1 m).
    CloseDistanceOffset = 100,
    CloseHeightOffset = 0,

    ---------------------------------------------------------------- Right-stick orbit
    -- Look around the car with the right stick (chase and far views).
    -- Needs the TXRChaseCamInput folder for full analog control with Xbox / Steam Input pads;
    -- without it the mod falls back to the game's 4-direction look signals.
    OrbitEnabled = true,
    -- true = a half push turns the camera halfway; false = any push turns it fully.
    OrbitScaleWithDeflection = true,
    -- Flip left/right.
    OrbitInvert = false,
    -- How fast the camera follows the stick, and how fast it returns behind the car.
    OrbitFollowSpeed = 10,
    OrbitReturnSpeed = 12,

    ---------------------------------------------------------------- Transitions
    -- Smoothly blend into the driving camera instead of the game's hard cut
    -- (e.g. at the end of the camera pan when leaving the garage).
    SmoothViewCuts = true,
    ViewCutBlendTime = 1.2,  -- seconds

    ---------------------------------------------------------------- Sense of speed
    -- Field of view while boosting (game default 120; normal driving is 90).
    NitroFov = 105,
    -- Extra field of view for a moment when a boost starts.
    BoostKickFov = 8,
    -- Speed shake strength (0 = off, 1 = default, 2 = double).
    ShakeStrength = 1.0,
    -- The game's own vertical camera bounce (1 = game default, 0 = off).
    VerticalShakeScale = 0.25,
    -- How far the camera falls back when accelerating / closes in when braking (game: 10 / 0).
    AccelPullback = 50,
    AccelPushIn = 15,
    -- Motion blur, colour fringe and darker corners while boosting (true / false).
    -- Motion blur also needs the game's own motion blur option turned on.
    PostFx = true,
    MotionBlurMax = 0.4,

    -- More settings (shake frequencies, boost details, orbit dead zone, ...) are listed with
    -- explanations in the Config table at the top of main.lua; any of them can be added here.
    -- DevKeys = true enables the tuning keys and Ctrl+F5 debug log (for modders).
}
