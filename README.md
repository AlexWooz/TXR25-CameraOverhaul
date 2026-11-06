# TXR Chase Camera

A camera mod for **Tokyo Xtreme Racer** (Steam, UE5) that loosens the chase camera so it trails the car's heading, showing the car's side in corners the way Forza, NFS and the older TXR games do. The vanilla camera only does this while drifting.

Status: **first prototype**, a UE4SS Lua mod.

## Keys
| Key | Action |
|---|---|
| Ctrl+F6 | Toggle the mod on/off (compare with vanilla) |
| Ctrl+Up/Down | LagSpeed ±0.5 (higher = stiffer) |
| Ctrl+Right/Left | MaxOffset ±5° |
| Ctrl+F5 | Debug log |
| Ctrl+PgUp/PgDn | Close-view distance ±25 (default +100) |
| Ctrl+Home/End | Close-view height ±10 |
| Right stick | Orbit (chase/far views): the camera looks where the stick points; release returns behind the car. `OrbitMode = "spin"` spins instead |

Defaults live in the `Config` table at the top of `mod/TXRChaseCam/Scripts/main.lua`.

## Setup
- UE4SS experimental `v3.0.1-1212-gd4aebbf0` (the stable v3.0.1 doesn't support UE 5.4+) is installed in `TokyoXtremeRacer\Binaries\Win64`, with the GUI console and hot reload turned on.
- `.\tools\install.ps1` copies the mod and the probe into `ue4ss\Mods` and enables them (`-Mods TXRChaseCam` installs only the mod).

## Layout
| Path | Contents |
|---|---|
| `mod/TXRChaseCam/` | The camera mod |
| `discovery/TXRCamProbe/` | Dev-only UE4SS Lua mod that dumps the camera setup and diffs values between grip and drift |
| `tools/install.ps1` | Installs both into the game |
| `docs/TECHNICAL.md` | Game internals and how the mod works |
