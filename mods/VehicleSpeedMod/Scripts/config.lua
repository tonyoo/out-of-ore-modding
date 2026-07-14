--[[
    VehicleSpeedMod configuration
    Edit, then: vehiclespeed_reload  (or restart game)

    Multipliers are relative to STOCK (vanilla).
    Cycling presets always restores stock first, then applies ONE mult.
]]

VehicleSpeedConfig = {
    enabled = true,
    active_preset = "sport",
    apply_interval_seconds = 5,
    log_applies = false, -- set true only while debugging

    scale_gears = true,

    keybinds = {
        next_preset = true, -- Ctrl+Shift+Right (debounced)
        prev_preset = true, -- Ctrl+Shift+Left
        status = true,      -- Ctrl+Shift+V
    },

    absolute_floors = {
        MaxSpeedLimit = 80,
        DynamicMaxTorque = 3500,
        TargetAcceleration = 8,
        TargetSpeed = 80,
        VehicleMaxAngularVelocity = 12,
        IdleMaxRPM = 2600,
        TopSpeedF = 45,
        TopSpeedR = 22,
        HighGearSpeed = 45,
        LowGearSpeed = 22,
        EnginePower = 120,
        DriveTorqMultiplier = 1,
        MaxAccs = 6,
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
            top_speed_forward = 2.5,
            top_speed_reverse = 2.0,
            high_gear_speed = 2.5,
            low_gear_speed = 2.0,
            max_acceleration = 2.0,
            engine_power = 2.2,
            drive_torque_multiplier = 2.2,
            max_speed_limit = 2.5,
        },
        -- WARNING: extreme. Can break physics / control. Cycle carefully.
        ["insane+"] = {
            top_speed_forward = 100.0,
            top_speed_reverse = 100.0,
            high_gear_speed = 100.0,
            low_gear_speed = 100.0,
            gear_ratio_forward = 100.0,
            gear_ratio_reverse = 100.0,
            drivetrain_gear_modifier = 100.0,
            max_acceleration = 100.0,
            engine_power = 100.0,
            drive_torque_multiplier = 100.0,
            brake_force = 10.0, -- a bit more brake so you can still stop sometimes
            max_speed_limit = 100.0,
        },
    },

    class_overrides = {},
}
