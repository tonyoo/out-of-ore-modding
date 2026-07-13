--[[
    Backup example config for VehicleSpeedMod.
    Copy over config.lua if you break your settings.
]]

VehicleSpeedConfig = {
    enabled = true,
    active_preset = "sport",
    apply_interval_seconds = 3,
    log_applies = false,

    keybinds = {
        next_preset = true,
        prev_preset = true,
        status = true,
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
            max_acceleration = 1.25,
            engine_power = 1.35,
            drive_torque_multiplier = 1.35,
            max_speed_limit = 1.5,
        },
        insane = {
            top_speed_forward = 2.5,
            top_speed_reverse = 2.0,
            high_gear_speed = 2.5,
            low_gear_speed = 2.0,
            max_acceleration = 1.75,
            engine_power = 2.0,
            drive_torque_multiplier = 2.0,
            max_speed_limit = 2.5,
        },
    },

    class_overrides = {},
}
