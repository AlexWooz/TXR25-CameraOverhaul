# TXR25 Camera Overhaul

A camera overhaul for **Tokyo Xtreme Racer** (2025, Steam, UE5), as a UE4SS mod:
- **Loose chase camera:** trails the car's heading, showing the car's side in corners the way Forza, NFS and the older TXR games do. The vanilla camera only does this while drifting.
- **Right-stick orbit:** the camera looks wherever the stick points, any angle, scaled by deflection. A small C++ helper (`TXRChaseCamInput`) reads the stick through XInput, because the game's own input layer never passes the analog stick to the engine.
- **Sense of speed:** a speed-ramped shake on the camera's rotation (stronger and faster with speed) instead of most of the vanilla vertical bounce, a boost kick, a lower nitro FOV, a wider acceleration pull-back, and speed motion blur.
- **Close view** sits 100 units further back.

Player install instructions are in [release/README.txt](release/README.txt); the release zip is built with `tools/package.ps1`.

## Settings and keys
Players edit `mod/TXRChaseCam/Scripts/config.lua` (shipped as `ue4ss/Mods/TXRChaseCam/Scripts/config.lua`). Every setting, with its explanation, is in the `Config` table at the top of `main.lua`, and any of them can go in `config.lua`.

In game, **Ctrl+F6** toggles the mod. With `DevKeys = true` in `config.lua`:

| Key | Action |
|---|---|
| Ctrl+F5 | Debug log (4x/s, game thread) |
| Ctrl+Up/Down | LagSpeed ±0.5 (higher = stiffer) |
| Ctrl+Right/Left | MaxOffset ±5° |
| Ctrl+PgUp/PgDn | Close-view distance ±25 |
| Ctrl+Home/End | Close-view height ±10 |
| Ctrl+Ins/Del | Nitro FOV ±5 |
| Ctrl+] / [ | Game's vertical shake scale ±0.1 |
| Ctrl+= / - | Speed shake strength ±0.1 |
| Ctrl+B | Motion blur + boost fringe/vignette on/off |

## Development setup
- UE4SS experimental `v3.0.1-1212-gd4aebbf0` (the stable v3.0.1 doesn't support UE 5.4+) in `TokyoXtremeRacer\Binaries\Win64`, with the GUI console and hot reload on.
- `.\tools\install.ps1` copies the Lua mod, the C++ helper and the probe into `ue4ss\Mods` and enables them in `mods.txt` (`-Mods TXRChaseCam` installs only the Lua mod; Ctrl+R hot-reloads it).
- The C++ helper's build (VS 2022 Build Tools, Rust, CMake, Epic-linked GitHub for UE4SS's Unreal headers) is described in [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Layout
| Path | Contents |
|---|---|
| `mod/TXRChaseCam/` | The Lua mod (`main.lua`) and player settings (`config.lua`) |
| `native/TXRChaseCamInput/` | C++ helper: registers `TXRGetRightStick()` for the Lua mod |
| `native/CMakeLists.txt` | Builds the helper against `native/RE-UE4SS` (UE4SS at `d4aebbf0`, git-ignored) |
| `discovery/TXRCamProbe/` | Dev-only UE4SS Lua mod used to work out the game's camera and input |
| `tools/install.ps1` | Installs into the game for development |
| `tools/package.ps1` | Builds `release/TXRChaseCam-<version>.zip` |
| `release/README.txt` | The readme shipped in the zip |
| `docs/TECHNICAL.md` | Game internals and how the mod works |
