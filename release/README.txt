TXR Chase Camera 1.0 - camera overhaul for Tokyo Xtreme Racer (Steam)
=====================================================================

What it does
------------
- Loose chase camera: the camera trails behind the car in corners, so you
  see the side of the car (like Forza, Need for Speed or the older TXR games)
  instead of a camera glued to the bumper. Drifts still swing the camera as
  in the vanilla game.
- Right-stick orbit: look around the car in any direction, Forza/NFS style.
  The camera looks where the stick points and a half push turns it halfway.
  Release the stick and it returns behind the car.
- Sense of speed: a subtle shake that gets stronger and faster with speed
  (replacing most of the vanilla vertical bounce), a short kick when a boost
  starts, a lower nitro field of view (105 instead of 120), the camera
  falling back further when accelerating, and motion blur with speed.
- Close chase view sits a bit further back.
Cockpit and bonnet views are left as they are.


Requirements
------------
UE4SS experimental build v3.0.1-1212-gd4aebbf0. The stable UE4SS 3.0.1 does
NOT work with this game. Download UE4SS_v3.0.1-1212-gd4aebbf0.zip from:
  https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest


Install
-------
1. Install UE4SS: extract its zip so that dwmapi.dll and the ue4ss folder
   end up in
     <Steam>\steamapps\common\TokyoXtremeRacer\TokyoXtremeRacer\Binaries\Win64\
2. Copy both folders from this download (TXRChaseCam and TXRChaseCamInput)
   into
     ...\Binaries\Win64\ue4ss\Mods\
   Each contains an enabled.txt, so there's nothing to edit in mods.txt.
3. Start the game.

TXRChaseCamInput is a small helper that reads the right stick directly, for
the full-angle orbit. Without it (or on a different UE4SS version) the mod
still works, but the orbit only reacts to the game's 4 look directions.


Controller support
------------------
The full-angle orbit reads the controller through XInput: Xbox controllers,
and any controller Steam Input presents as one (e.g. DualSense with Steam
Input enabled). Other controllers get the 4-direction fallback.


Settings
--------
Edit ue4ss\Mods\TXRChaseCam\Scripts\config.lua (any text editor). Each
setting is explained there: how loose the chase camera is, the close view
distance, the orbit, nitro FOV, shake strength, acceleration pull-back,
motion blur and boost effects. Restart the game after changing it.
Motion blur also needs the game's own motion blur option turned on.

In game, Ctrl+F6 turns the mod off and on, to compare with the vanilla camera.


Uninstall
---------
Delete the TXRChaseCam and TXRChaseCamInput folders from ue4ss\Mods.
