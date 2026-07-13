--[[
    DirtCapacityMod configuration
    Edit, then in-game: dirtcap_reload

    dirt_capacity          = bucket hold volume (1.0 = stock, 2.0 = double)
    terrain_manipulation   = how much terrain is cut/dumped per action.
                             If omitted, matches dirt_capacity so dig/dump keeps up with the bigger bucket.
    weight_scale           = dirt density. If omitted and compensate_weight = true,
                             uses (1 / dirt_capacity) so a full bucket stays liftable.
]]

DirtCapacityConfig = {
    enabled = true,
    active_preset = "double",
    apply_interval_seconds = 4,
    log_applies = true,

    -- Full bucket lift fix: scale weight density down when capacity goes up
    compensate_weight = true,

    -- Scale terrain cut/dump with capacity (default true via matching mult)
    match_terrain_to_capacity = true,

    keybinds = {
        status = true,       -- Ctrl+Shift+D
        next_preset = true,  -- Ctrl+Shift+]
        prev_preset = true,  -- Ctrl+Shift+[
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
        vanilla = {
            dirt_capacity = 1.0,
            -- terrain_manipulation auto = 1.0
        },
        double = {
            dirt_capacity = 2.0,
            -- terrain_manipulation auto = 2.0 (dig/dump matches volume)
            -- weight_scale auto = 0.5
        },
        huge = {
            dirt_capacity = 4.0,
            -- terrain_manipulation auto = 4.0
            -- weight_scale auto = 0.25
        },
        -- Example: big bucket but only slightly stronger dig:
        -- custom = { dirt_capacity = 3.0, terrain_manipulation = 2.0, weight_scale = 0.4 },
    },
}
