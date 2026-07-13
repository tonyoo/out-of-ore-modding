--[[
    VehicleSpeedMod configuration

    If storage containers / world interact break:
      1) Set enabled = false
      2) Restart game and reload an earlier save if needed

    scale_gears = true can break some machines; leave false unless testing.
]]

VehicleSpeedConfig = {
    -- DEFAULT OFF until vehicle tuning is proven safe in your save.
    -- Set true when you want speed mods again.
    enabled = false,

    active_preset = "sport",
    apply_interval_seconds = 5,
    log_applies = false,

    -- Dangerous on some vehicles; leave false
    scale_gears = false,

    keybinds = {
        next_preset = true,
        prev_preset = true,
        status = true,
    },

    absolute_floors = {
        MaxSpeedLimit = 100,
        DynamicMaxTorque = 4000,
        TargetAcceleration = 10,
        TargetSpeed = 100,
        VehicleMaxAngularVelocity = 15,
        IdleMaxRPM = 2800,
        TopSpeedF = 50,
        TopSpeedR = 25,
        HighGearSpeed = 50,
        LowGearSpeed = 25,
        EnginePower = 150,
        DriveTorqMultiplier = 1,
        MaxAccs = 8,
    },

    presets = {
        vanilla = {
            top_speed_forward = 1.0,
            top_speed_reverse = 1.0,
            high_gear_speed = 1.0,
            low_gear_speed = 1.0,
            gear_ratio_forward = 1.0,
            gear_ratio_reverse = 1.0,
            drivetrain_gear_modifier = 1.0,
            max_acceleration = 1.0,
            engine_power = 1.0,
            drive_torque_multiplier = 1.0,
            brake_force = 1.0,
            max_speed_limit = 1.0,
        },
        sport = {
            top_speed_forward = 1.5,
            top_speed_reverse = 1.3,
            high_gear_speed = 1.5,
            low_gear_speed = 1.3,
            max_acceleration = 1.35,
            engine_power = 1.5,
            drive_torque_multiplier = 1.5,
            max_speed_limit = 1.5,
        },
        insane = {
            top_speed_forward = 10.5,
            top_speed_reverse = 2.0,
            high_gear_speed = 10.5,
            low_gear_speed = 2.0,
            max_acceleration = 8.0,
            engine_power = 10.5,
            drive_torque_multiplier = 15.5,
            max_speed_limit = 10.5,
        },
    },

    class_overrides = {},
}
