# Technical notes

## Game facts
- Steam install: `C:\Program Files (x86)\Steam\steamapps\common\TokyoXtremeRacer`.
- Engine: **UE5**, 5.4 or later. The exe reports `UE5-CL-0`, and the IoStore TOC version is 8. Check the exact minor version in FModel.
- Content is IoStore (`pakchunk0/1/4-Windows.utoc/.ucas` plus small `.pak` stubs). Use FModel to browse and retoc to convert between IoStore and legacy pak.
- `TokyoXtremeRacer-Win64-Shipping.exe` has normal PE sections (`.text`, `.rdata`, ...) and isn't packed, unlike Minecraft Dungeons, so UE4SS can hook it.

## UE4SS
- Build: experimental `UE4SS_v3.0.1-1212-gd4aebbf0.zip` from the UE4SS-RE GitHub release `experimental-latest`, sha256 `8196a662...a566039`.
- `UE4SS-settings.ini` changes: `ConsoleEnabled`, `GuiConsoleEnabled`, `GuiConsoleVisible` and `EnableHotReloadSystem` all set to 1.

## Camera (probe run 1, RZ34 on `L_Shutoko_WP`)
- Player controller: `BP_VehiclePlayerControllerNew_C -> BP_SB_PlayerController_Base_C -> PC_ReplaySpectator -> PlayerController`.
- Car pawn: `BP_GV_RZ34_C -> BP_GameVehicle_C -> BP_CustomCar_C -> BP_BaseVehicleX_C -> ReplayDelayPawn -> Pawn`. Camera logic most likely lives in `BP_BaseVehicleX_C` or `BP_CustomCar_C`.
- Camera manager: plain native `PlayerCameraManager`, with no Blueprint subclass. The view target is the car, so the camera comes from the car's own camera components.
- Camera components on the car: `OutCamera`, `FarCamera`, `InShakeCamera`, `BonnetShakeCamera`, `RearCamera`. (Run 1 misread these as world-space: it scanned every car in the world, traffic and rivals included, and same-named components from different cars overwrote each other. Ignore those values.)
- **The default chase view is `OutCamera`**, attached to `CameraArm` (`BP_CameraArm_C`, a custom component rather than a SpringArm), which is attached to `BaseBody`. `FarCamera` sits on `CameraArmForFar` (also a `BP_CameraArm_C`). Camera FOV was 119.5 at speed (`default_camera_fov` 90, `nitro_camera_fov` 120).
- **How the swing works:** each tick `BP_CameraArm_C` sets its `RelativeRotation.Yaw` to its `slip_angle` variable, a clamped and smoothed version of the car's slip angle in degrees (`tmp_slip_angle` is the raw value). `CameraArm` mid-drift: tmp -29.2 → slip -28.4 → yaw -28.3. `CameraArmForFar` clamps at ±10. With grip, slip is near 0, so the camera sits dead behind the car. During a hard grip corner, slip reached about 10° and the arm yaw was -4.2.
- `BP_CameraArm_C` variables (CameraArm, run 3): `use_slip_angle` true, `start_slip_angle` 4 (the deadzone), `stop_slip_angle` 30 (the cap), `yaw_interp_speed` 5, `yaw_ignore_change_angle` 45, `yaw_offset` 0, `target_length` 449.5, `org_relative_location` (-448, 0, 142), `org_relative_rotation` pitch -4.7, `max_move_target_length` 10 with `acc_scale_for_x_move` 700 (pull-back on acceleration), and `max_roll` / `roll_interp_speed` both 0.
- `BP_CameraArm_C` functions: `SetYawOffset(Double)`, `SetTargetLengthOffset(Double)`, `SetRelativeLocationZOffset(Double)`, `SetShakeCoef(Double)`, `ClearOffset()`, `Reset()`, `ComputeFromTargetLocation()`, `ReceiveTick`. **`SetYawOffset` is the hook the mod uses.**
- The arm's rotation isn't absolute, so its yaw follows `BaseBody` exactly. The game's "lag" settings (`OutCameraLagSpeed` 5, `OutCameraLagRotSpeed` 5, getters on the car) don't produce any yaw trailing in grip (the measured gap is 0.0), so they must apply elsewhere or only to smoothing the arm's own offsets.
- Car getter values (Ctrl+F10): CamMaxYawOffset 30, CamMinYawOffset 2, CameraUseYawSlipAngleOffset true, CameraUseYawOffset false, CameraMoveLength min 0 / max 10 / AccScale 700, OutCameraTargetLocationZ 105. Getters that take an input (`GetCameraPos(type)` and similar) weren't called.
- Other arm variables: `abs_slip_angle`, `acc`, `target_v_inner`, `target_v_length`, `tmp_forward_kmph`, `shake_now_size`, `shake_z_scale`.

## TXRChaseCam (the mod)
- It hooks `<BP_CameraArm_C class path>:ReceiveTick` (the path is resolved at runtime from the first arm found) and runs once per frame on the player car's first arm.
- The camera heading follows the car heading through a first-order lag: `alpha = 1 - exp(-LagSpeed * dt)`. The trailing angle is clamped to `MaxOffset`, faded in between `MinSpeedKmh` and `FullSpeedKmh`, and scaled toward `DriftScale` as the main arm's own `slip_angle` approaches `GameSlipMax` (30). (Test 1 scaled on `drift_started` instead. That flag flips in one frame, so the offset halved instantly and the camera visibly snapped mid-drift.) The result goes to `SetYawOffset` on every arm of the player car.
- Verified in game (test 1): the class path is `/Game/VehicleCore/Blueprints/BP_CameraArm.BP_CameraArm_C`, and the RZ34 has 2 arms. `yaw_offset` is applied directly, with no extra smoothing, and with the expected sign: measured `cam-car` matches `offset` within about 0.3° in grip. A positive yaw rate gives a negative offset, so the camera trails. During drifts the game's slip swing adds on top (for example, offset -10 with cam-car -35).
- The menu or front end uses `BP_OutGamePawn_C`, which has no arms. That's harmless.
- Camera functions on `BP_GameVehicle_C` / `BP_BaseVehicleX_C`: `Get/SetOutCameraLagSpeed`, `Get/SetOutCameraLagRotSpeed`, `Get/SetCamMin/MaxYawOffset`, `Get/SetCameraUseYawSlipAngleOffset`, `Get/SetCameraUseYawOffset`, `Get/SetCameraMoveLengthMin/Max/AccScale`, `SettingCameraArm`, `RefrectionCameraParam(s)`, `StartDrift`/`StopDrift`/`UpdateDrift`, `UpdateFOV`.
- Car variables: `camera_ang_yaw_finterp_speed` = 10 (likely the yaw interpolation speed), `camera_use_yaw_offset` = false, `camera_relative_yaw` = 0, `drift_angle_threshold` = 20, `drift_need_speed` = 100, plus debug hooks `dbg_camera_yaw_offset` and `dgb_camera_arm_length_offset`.
- Grip: the camera-to-car yaw gap is **exactly 0.0** at every speed and through every steering input. There's no lag at all; it's rigidly locked to the heading.
- Drift: car variable `drift_started` turns true, and `slip_angle` (radians) grows. The camera-to-car gap grows to about 30° and holds there while slip is 60–85°, which is the `CameraArm` slip-angle offset described above, clamped near 30°.
- Other drift-time car variables: `current_front_max_steer_angle` 10 → 30 (the speed-based steering limit, not the camera).
