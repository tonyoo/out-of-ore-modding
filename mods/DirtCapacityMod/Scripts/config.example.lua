--[[ Backup example — copy over config.lua if you break it. ]]

DirtCapacityConfig = {
    enabled = true,
    active_preset = "double",
    apply_interval_seconds = 4,
    log_applies = true,
    compensate_weight = true,
    match_terrain_to_capacity = true,

    keybinds = {
        status = true,
        next_preset = true,
        prev_preset = true,
    },

    absolute_floors = {
        TotalFillVolumeM3Modifier = 1.0,
        DirtAcc = 1.0,
        TransDirtAccSize = 1.0,
        WeightModifier = 0.01,
        DirtToWorldModifier = 1.0,
        CutBoxModifier = 1.0,
        CutBulk = 1.0,
        LinearModifier = 1.0,
        VoxelToBulkMultiplier = 1.0,
        VoxelToOreMultiplier = 1.0,
    },

    presets = {
        vanilla = { dirt_capacity = 1.0 },
        double  = { dirt_capacity = 2.0 }, -- terrain auto 2.0, weight auto 0.5
        huge    = { dirt_capacity = 4.0 }, -- terrain auto 4.0, weight auto 0.25
    },
}
