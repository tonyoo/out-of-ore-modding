--[[
    MiniMapMod config. Restart after editing (or minimap_reload).
]]

MiniMapConfig = {
    enabled = true,
    size_px = 192,
    corner = "bottom_right", -- bottom_right | bottom_left | top_right | top_left
    padding_px = 24,         -- gap from the chosen edges
    -- Extra pixels from that corner. +offset_x = right, +offset_y = down.
    offset_x = 0,
    offset_y = 0,
    zoom = 0.35,             -- 0.05 far .. 1 close
    zoom_step = 0.08,        -- change per Ctrl+Shift+Up/Down (minimap_zoom_step)
    update_hz = 8,
    z_order = 50,
    keybind = false,         -- use minimap_enable 0|1
    -- Zoom: Ctrl+Shift+Up / Ctrl+Shift+Down
}
