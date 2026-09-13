--[[
    MiniMapMod — from scratch.

    One W_Element_MapImage on the viewport, driven by Map_Component.
    Zoom: mouse wheel, Ctrl+Num+/-, minimap_zoom_in/out.

    Pitfalls this rewrite avoids:
    - Palworld DekBasicMinimap pak (UE5) — do not load
    - CreateWidget of W_Element_Button / SetButtonContent — Fatal
    - ExecuteInGameThread inside LoopAsync — kills EngineTick hook
    - Parent to W_HUD.ConstantHud — HUD vis bindings hide the map
    - Create on main menu / loading — widget dies on world load
    - ShowingCursor / tablet pause — console looks like tablet, overlay collapses
    - Collapse Border — Image_Map can live inside it
    - Stretch Canvas_MapMarkers — covers the capture
    - CollapseChrome/FillInner every tick — fights widget Tick, map flickers off
    - HandleMapClosed while shown — blanks Image_Map
    - Destroy on toggle — flash / recreate
    - obj:Method without () — Lua parse error, commands never register
]]

local UEHelpers = require("UEHelpers")
require("config")

local Config = MiniMapConfig or {}
local GlobalAr = nil

local VIS_VISIBLE = 0
local VIS_COLLAPSED = 1
local VIS_HIDDEN = 2

local Overlay = nil
local OverlayName = nil
local LaidOut = false
local Creating = false
local PendingCreate = false
local LastWaitLog = 0
local LastKeybind = 0
local LoggedBind = false

local MAP_CLASS = "/Game/Interface/InGameMenu/Map/W_Element_MapImage.W_Element_MapImage_C"
local MAP_CDO = "/Game/Interface/InGameMenu/Map/W_Element_MapImage.Default__W_Element_MapImage_C"
local WIDGET_LIB = "/Script/UMG.Default__WidgetBlueprintLibrary"

-- Non-map chrome only. Never SizeBox/Border/Image_Map/canvases (that deleted the map).
local HIDE = {
    "MapZoomSlider",
    "W_Element_Button_Center",
    "Image_256",
    "Image_Rescue",
    "Marker_Rescue",
}

local function Log(msg)
    local line = "[MiniMapMod] " .. tostring(msg)
    print(line .. "\n")
    if GlobalAr and type(GlobalAr) == "userdata" then
        pcall(function() GlobalAr:Log(line) end)
    end
end

local function WithAr(Ar, fn)
    GlobalAr = Ar
    local ok, err = pcall(fn)
    GlobalAr = nil
    if not ok then Log("Error: " .. tostring(err)) end
    return true
end

local function SharedGet(key)
    local ok, v = pcall(function()
        if ModRef and ModRef.GetSharedVariable then return ModRef:GetSharedVariable(key) end
        return nil
    end)
    if ok then return v end
    return nil
end

local function SharedSet(key, value)
    pcall(function()
        if ModRef and ModRef.SetSharedVariable then ModRef:SetSharedVariable(key, value) end
    end)
end

local function ReloadConfig()
    package.loaded["config"] = nil
    local ok, err = pcall(function()
        require("config")
        Config = MiniMapConfig or {}
    end)
    if not ok then
        Log("Config reload failed: " .. tostring(err))
        return false
    end
    LaidOut = false
    Log(string.format("Config reloaded enabled=%s size=%s corner=%s offset=%s,%s zoom=%s",
        tostring(Config.enabled), tostring(Config.size_px), tostring(Config.corner),
        tostring(Config.offset_x), tostring(Config.offset_y), tostring(Config.zoom)))
    return true
end

local function IsU(obj)
    if not obj or type(obj) ~= "userdata" then return false end
    local ok, v = pcall(function() return obj:IsValid() end)
    return ok and v == true
end

local function FullName(obj)
    local ok, n = pcall(function() return obj:GetFullName() end)
    if ok and type(n) == "string" then return n end
    return ""
end

local function IsLive(obj)
    if not IsU(obj) then return false end
    return not FullName(obj):find("Default__", 1, true)
end

local function Field(obj, name)
    local w
    pcall(function() w = obj[name] end)
    if IsU(w) then return w end
    return nil
end

local function Named(widget, name)
    local w = Field(widget, name)
    if w then return w end
    local tree = widget.WidgetTree
    if tree then return Field(tree, name) end
    return nil
end

local function FindOf(className)
    local list = {}
    local found
    pcall(function() found = FindAllOf(className) end)
    if not found then return list end
    for _, o in ipairs(found) do
        if IsLive(o) then table.insert(list, o) end
    end
    return list
end

local function FindPC()
    local pc
    pcall(function() pc = UEHelpers.GetPlayerController() end)
    if IsLive(pc) and FullName(pc):find("PC_Standard", 1, true) then return pc end
    return FindOf("PC_Standard_C")[1]
end

local function FindMapComp(pc)
    if IsU(pc) then
        local c = Field(pc, "Map_Component") or Field(pc, "MapComponent")
        if c then return c end
    end
    return FindOf("Map_Component_C")[1]
end

local function FindHudCanvas()
    local hud = FindOf("W_HUD_C")[1]
    if not hud then return nil, nil end
    local canvas = Field(hud, "ConstantHud")
        or (hud.WidgetTree and Field(hud.WidgetTree, "ConstantHud"))
    return hud, canvas
end

-- In-world only.
local function WorldReady()
    local pc = FindPC()
    if not pc then return false, "no PC_Standard" end
    if not FindMapComp(pc) then return false, "no Map_Component" end
    if not FindOf("W_HUD_C")[1] then return false, "no W_HUD" end
    return true, "ok"
end

local function FindMapClass()
    local o
    pcall(function() o = StaticFindObject(MAP_CLASS) end)
    if IsU(o) then return o end
    pcall(function() o = StaticFindObject(MAP_CDO) end)
    if IsU(o) then
        local c
        pcall(function() c = o:GetClass() end)
        if IsU(c) then return c end
    end
    local inst = FindOf("W_Element_MapImage_C")[1]
    if inst then
        local c
        pcall(function() c = inst:GetClass() end)
        if IsU(c) then return c end
    end
    return nil
end

local function CreateWidget(pc, class)
    local lib
    pcall(function() lib = StaticFindObject(WIDGET_LIB) end)
    if not IsU(lib) then return nil, "no WidgetBlueprintLibrary" end
    local w
    pcall(function() w = lib:Create(pc, class, pc) end)
    if IsU(w) then return w, "Create" end
    pcall(function()
        local p = { WorldContextObject = pc, WidgetType = class, OwningPlayer = pc }
        lib:ProcessEvent(lib.Create, p)
        w = p.ReturnValue
    end)
    if IsU(w) then return w, "ProcessEvent Create" end
    return nil, "Create failed"
end

local function SetVis(w, vis)
    if not IsU(w) then return end
    if not pcall(function() w:SetVisibility(vis) end) then
        pcall(function() w.Visibility = vis end)
    end
end

local function Vec2(x, y)
    return { X = x, Y = y }
end

local function SizePx()
    local n = tonumber(Config.size_px) or 192
    if n < 64 then n = 64 end
    if n > 512 then n = 512 end
    return n
end

local function Corner()
    local c = tostring(Config.corner or "bottom_right"):lower()
    local pad = tonumber(Config.padding_px) or 24
    local ox = tonumber(Config.offset_x) or 0
    local oy = tonumber(Config.offset_y) or 0
    if c == "bottom_left" then return 0, 1, 0, 1, pad + ox, -pad + oy end
    if c == "top_right" then return 1, 0, 1, 0, -pad + ox, pad + oy end
    if c == "top_left" then return 0, 0, 0, 0, pad + ox, pad + oy end
    return 1, 1, 1, 1, -pad + ox, -pad + oy
end

local function VisName(v)
    local n = tonumber(v)
    if n == 0 then return "Visible" end
    if n == 1 then return "Collapsed" end
    if n == 2 then return "Hidden" end
    if n == 3 then return "HitTestInvisible" end
    if n == 4 then return "SelfHitTestInvisible" end
    return tostring(v)
end

local function ShortName(obj)
    local n = FullName(obj)
    local leaf = n:match("([%w_]+)$")
    return leaf or n
end

local function HideMapZoomSlider(widget)
    local sl = Named(widget, "MapZoomSlider")
    if not sl then return end
    SetVis(sl, VIS_COLLAPSED)
    pcall(function() sl:SetRenderOpacity(0) end)
    pcall(function() sl.bIsEnabled = false end)
    pcall(function() sl:SetIsEnabled(false) end)
    pcall(function() sl:SetVisibility(VIS_COLLAPSED) end)
end

-- Keep Image_Map and anything that parents it (Border/SizeBox wrap the map).
-- Collapse every other named widget. Do not resize.
local function CollectKeep(widget)
    local keep = {}
    local function mark(obj)
        local cur = obj
        for _ = 1, 20 do
            if not IsU(cur) then break end
            keep[FullName(cur)] = true
            keep[ShortName(cur)] = true
            local p
            pcall(function() p = cur:GetParent() end)
            cur = p
        end
    end
    mark(widget)
    mark(Named(widget, "Image_Map"))
    mark(Named(widget, "Canvas_MapViewport"))
    mark(Named(widget, "Canvas_MapContent"))
    mark(Named(widget, "PlayerIconCanvas"))
    mark(Named(widget, "Canvas_MapMarkers"))
    mark(Named(widget, "CanvasPanelRoot"))
    return keep
end

local function EachChild(panel, fn)
    if not IsU(panel) then return end
    local n = 0
    pcall(function() n = panel:GetChildrenCount() end)
    for i = 0, (n or 0) - 1 do
        local child
        pcall(function() child = panel:GetChildAt(i) end)
        if IsU(child) then fn(child) end
    end
end

local function HideSlider(widget)
    HideMapZoomSlider(widget)
    -- Keep player pin + machine/map markers. Do not force land icons off.
    local keep = CollectKeep(widget)
    local names = {
        "MapZoomSlider", "Image_256", "W_Element_Button_Center",
        "Image_Rescue", "Marker_Rescue",
    }
    for _, name in ipairs(names) do
        local w = Named(widget, name)
        if w and not keep[FullName(w)] then
            SetVis(w, VIS_COLLAPSED)
        end
    end
    -- SizeBox_98 is WidgetTree-only (Named misses it). Live dump: Image_Map
    -- parent chain is Content -> Viewport -> CanvasPanelRoot, so SizeBox
    -- does not wrap the map and is safe to collapse.
    local function hideIfSizeBox(child)
        if keep[FullName(child)] then return end
        local sn = ShortName(child)
        local cn = FullName(child)
        if sn:find("SizeBox", 1, true) or cn:find("SizeBox", 1, true) then
            SetVis(child, VIS_COLLAPSED)
            pcall(function() child:SetRenderOpacity(0) end)
        end
    end
    local vp = Named(widget, "Canvas_MapViewport")
    local root = Named(widget, "CanvasPanelRoot")
    if not IsU(root) and IsU(vp) then
        pcall(function() root = vp:GetParent() end)
    end
    EachChild(root, hideIfSizeBox)
    EachChild(widget, hideIfSizeBox)
    local sl = Named(widget, "MapZoomSlider")
    if IsU(sl) then
        local border
        pcall(function() border = sl:GetParent() end)
        if IsU(border) then
            EachChild(border, hideIfSizeBox)
            -- Border parents the slider; clear gray brush, do not collapse
            -- if it also sits above the map.
            if not keep[FullName(border)] then
                pcall(function()
                    border:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
                end)
            else
                pcall(function()
                    border:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
                end)
            end
        end
    end
    EachChild(root, function(child)
        if not keep[FullName(child)] then
            SetVis(child, VIS_COLLAPSED)
        end
    end)
end

local function DumpOverlay()
    if not IsU(Overlay) then
        Log("dump: no overlay")
        return
    end
    Log("dump overlay=" .. FullName(Overlay))
    local names = {
        "CanvasPanelRoot", "Canvas_MapViewport", "Canvas_MapContent", "Image_Map",
        "PlayerIconCanvas", "MapZoomSlider", "Image_256", "SizeBox_98", "Border",
        "W_Element_Button_Center", "Image_Rescue", "Marker_Rescue", "Canvas_MapMarkers",
    }
    for _, name in ipairs(names) do
        local w = Named(Overlay, name)
        if not w then
            Log("  " .. name .. " = MISSING")
        else
            local vis
            pcall(function() vis = w:GetVisibility() end)
            local parent = ""
            pcall(function()
                local p = w:GetParent()
                if p then parent = ShortName(p) end
            end)
            Log(string.format("  %s vis=%s parent=%s", name, VisName(vis), parent))
        end
    end
    local root = Named(Overlay, "CanvasPanelRoot")
    if not IsU(root) then
        local vp = Named(Overlay, "Canvas_MapViewport")
        if IsU(vp) then pcall(function() root = vp:GetParent() end) end
    end
    local count = 0
    if IsU(root) then
        pcall(function() count = root:GetChildrenCount() end)
        Log("  CanvasPanelRoot children=" .. tostring(count))
        for i = 0, (count or 0) - 1 do
            local child
            pcall(function() child = root:GetChildAt(i) end)
            if IsU(child) then
                local vis
                pcall(function() vis = child:GetVisibility() end)
                Log(string.format("    [%d] %s vis=%s", i, ShortName(child), VisName(vis)))
            end
        end
    end
end

local function LayoutOuterSlot(slot, size)
    if not IsU(slot) then return false end
    local ax, ay, alx, aly, px, py = Corner()
    pcall(function() slot.bAutoSize = false end)
    pcall(function() slot:SetAutoSize(false) end)
    pcall(function()
        slot:SetAnchors({ Minimum = Vec2(ax, ay), Maximum = Vec2(ax, ay) })
    end)
    pcall(function() slot:SetAlignment(Vec2(alx, aly)) end)
    pcall(function() slot:SetPosition(Vec2(px, py)) end)
    pcall(function() slot:SetSize(Vec2(size, size)) end)
    pcall(function() slot:SetZOrder(200) end)
    return true
end

local function ApplyViewportLayout(widget)
    local size = SizePx()
    local ax, ay, alx, aly, px, py = Corner()
    pcall(function() widget:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 1 }) end)
    pcall(function()
        widget:SetAnchorsInViewport({
            Minimum = Vec2(ax, ay),
            Maximum = Vec2(ax, ay),
        })
    end)
    pcall(function() widget:SetAlignmentInViewport(Vec2(alx, aly)) end)
    pcall(function() widget:SetPositionInViewport(Vec2(px, py), true) end)
    pcall(function() widget:SetDesiredSizeInViewport(Vec2(size, size)) end)
    -- ProcessEvent variants if colon-call FVector2D failed
    pcall(function()
        widget:ProcessEvent(widget.SetDesiredSizeInViewport, { Size = { X = size, Y = size } })
    end)
    pcall(function()
        widget:ProcessEvent(widget.SetPositionInViewport, {
            Position = { X = px, Y = py },
            bRemoveDPIScale = true,
        })
    end)
    pcall(function() widget.DesiredZoom = tonumber(Config.zoom) or 0.35 end)
    HideSlider(widget)
    LaidOut = true
end

local function BindRT(widget, mapComp)
    local img = Named(widget, "Image_Map")
    if not img then return false end
    SetVis(img, VIS_VISIBLE)
    pcall(function() img.ColorAndOpacity = { R = 1, G = 1, B = 1, A = 1 } end)
    local rt = mapComp and Field(mapComp, "RuntimeMapRenderTarget")
    if not rt then return false end
    local ok = pcall(function() img:SetBrushFromTextureDynamic(rt, false) end)
    if not ok then
        ok = pcall(function() img:SetBrushFromTexture(rt, false) end)
    end
    return ok
end

local function KeepVisible(widget)
    SetVis(widget, VIS_VISIBLE)
    SetVis(Named(widget, "Image_Map"), VIS_VISIBLE)
    SetVis(Named(widget, "Canvas_MapViewport"), VIS_VISIBLE)
    SetVis(Named(widget, "Canvas_MapContent"), VIS_VISIBLE)
    SetVis(Named(widget, "PlayerIconCanvas"), VIS_VISIBLE)
    SetVis(Named(widget, "Canvas_MapMarkers"), VIS_VISIBLE)
    SetVis(Named(widget, "Marker_Rescue"), VIS_COLLAPSED)
    SetVis(Named(widget, "Image_Rescue"), VIS_COLLAPSED)
    local pin = Named(widget, "PlayerIconCanvas")
    EachChild(pin, function(child)
        local sn = ShortName(child)
        if sn:find("Rescue", 1, true) or sn:find("SOS", 1, true) then
            SetVis(child, VIS_COLLAPSED)
        end
    end)
    HideSlider(widget)
    HideMapZoomSlider(widget)
end

local function ClampZoom(z)
    z = tonumber(z) or 0.35
    if z < 0.05 then z = 0.05 end
    if z > 1 then z = 1 end
    return z
end

local function Drive(widget, mapComp)
    if not IsU(widget) then return end
    if IsU(mapComp) then
        pcall(function() widget.MapComponent = mapComp end)
        pcall(function() mapComp:EnsureMapRuntimeResources() end)
        pcall(function() mapComp:EnsureMapCaptureActor() end)
        local z = ClampZoom(Config.zoom)
        pcall(function() mapComp:SetZoomNormalized(z, false, { X = 0, Y = 0 }) end)
        pcall(function() mapComp:CenterOnControlledPawn() end)
        pcall(function() mapComp:ApplyCurrentView() end)
        local cap = Field(mapComp, "MapCaptureActor")
        if cap then pcall(function() cap:CaptureNow() end) end
    end
    pcall(function() widget:HandleMapOpened() end)
    pcall(function() widget:UpdateSize() end)
    pcall(function() widget:CaptureMapNow() end)
    local bound = BindRT(widget, mapComp)
    if not LoggedBind then
        LoggedBind = true
        local img = Named(widget, "Image_Map")
        local rt = mapComp and Field(mapComp, "RuntimeMapRenderTarget")
        Log(string.format("bind img=%s rt=%s ok=%s",
            IsU(img) and "yes" or "no",
            IsU(rt) and "yes" or "no",
            tostring(bound)))
    end
end

local function ApplyZoom(z)
    z = ClampZoom(z)
    Config.zoom = z
    if MiniMapConfig then MiniMapConfig.zoom = z end
    local mapComp = FindMapComp(FindPC())
    if IsU(mapComp) then
        pcall(function() mapComp:SetZoomNormalized(z, false, { X = 0, Y = 0 }) end)
        pcall(function() mapComp:CenterOnControlledPawn() end)
        pcall(function() mapComp:ApplyCurrentView() end)
        local cap = Field(mapComp, "MapCaptureActor")
        if cap then pcall(function() cap:CaptureNow() end) end
    end
    if IsU(Overlay) then
        pcall(function() Overlay.DesiredZoom = z end)
        pcall(function() Overlay:CaptureMapNow() end)
        BindRT(Overlay, mapComp)
    end
    Log(string.format("zoom=%.2f", z))
end

local function NudgeZoom(dir)
    ApplyZoom((tonumber(Config.zoom) or 0.35) + dir * (tonumber(Config.zoom_step) or 0.08))
end

local function Destroy()
    if IsU(Overlay) then
        pcall(function() Overlay:RemoveFromParent() end)
        pcall(function() Overlay:RemoveFromViewport() end)
    end
    Overlay = nil
    OverlayName = nil
    LaidOut = false
    Creating = false
    PendingCreate = false
    LoggedBind = false
end

local function Show()
    if not IsU(Overlay) then return end
    if not LaidOut then ApplyViewportLayout(Overlay) end
    KeepVisible(Overlay)
    Drive(Overlay, FindMapComp(FindPC()))
end

local function Ensure()
    if Config.enabled == false then return false, "disabled" end
    if IsU(Overlay) then return true, "existing" end
    if Creating then return false, "creating" end
    local ready, why = WorldReady()
    if not ready then return false, "wait: " .. tostring(why) end
    local class = FindMapClass()
    if not class then return false, "wait: map class (open tablet Map once if this persists)" end
    local pc = FindPC()
    Creating = true
    local w, how = CreateWidget(pc, class)
    if not IsU(w) then
        Creating = false
        return false, tostring(how)
    end
    Overlay = w
    OverlayName = FullName(w)
    local size = SizePx()
    local parentHow = "none"
    local _, canvas = FindHudCanvas()
    local slot
    if IsU(canvas) then
        pcall(function() slot = canvas:AddChild(w) end)
        if not IsU(slot) then
            pcall(function()
                local p = { Content = w }
                canvas:ProcessEvent(canvas.AddChild, p)
                slot = p.ReturnValue
            end)
        end
        if not IsU(slot) then slot = Field(w, "Slot") end
        if LayoutOuterSlot(slot, size) then
            parentHow = "ConstantHud"
        end
    end
    if parentHow == "none" then
        local z = tonumber(Config.z_order) or 50
        pcall(function() w:AddToViewport(z) end)
        pcall(function() w:AddToPlayerScreen(z) end)
        parentHow = "viewport-fallback"
        LayoutOuterSlot(Field(w, "Slot"), size)
        ApplyViewportLayout(w)
    else
        pcall(function() w:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 1 }) end)
        HideSlider(w)
        LaidOut = true
    end
    KeepVisible(w)
    Drive(w, FindMapComp(pc))
    Creating = false
    Log(string.format("Overlay %s parent=%s slot=%s size=%d",
        tostring(how), parentHow, IsU(slot) and "yes" or "no", size))
    DumpOverlay()
    return true, "created"
end

local function Tick()
    if Config.enabled == false then
        if IsU(Overlay) then SetVis(Overlay, VIS_COLLAPSED) end
        return
    end
    if Overlay and not IsU(Overlay) then
        Overlay = nil
        LaidOut = false
    end
    if not IsU(Overlay) then
        local ready, why = WorldReady()
        if not ready then
            local now = os.clock()
            if now - LastWaitLog > 5 then
                LastWaitLog = now
                Log("Waiting: " .. tostring(why))
            end
            return
        end
        if not Creating then
            local ok, how = Ensure()
            if not ok then
                local now = os.clock()
                if now - LastWaitLog > 5 then
                    LastWaitLog = now
                    Log("Waiting: " .. tostring(how))
                end
            elseif how == "created" then
                Log("GameThread ensure: created")
            end
        end
        return
    end
    if not LaidOut then ApplyViewportLayout(Overlay) end
    KeepVisible(Overlay)
    local mapComp = FindMapComp(FindPC())
    if IsU(mapComp) then
        pcall(function() mapComp:CenterOnControlledPawn() end)
    end
    BindRT(Overlay, mapComp)
end

local function Status()
    local pc = FindPC()
    local mc = FindMapComp(pc)
    Log(string.format(
        "enabled=%s overlay=%s laidOut=%s pc=%s mapComp=%s zoom=%.2f",
        tostring(Config.enabled),
        IsU(Overlay) and "yes" or "no",
        tostring(LaidOut),
        IsU(pc) and "yes" or "no",
        IsU(mc) and "yes" or "no",
        tonumber(Config.zoom) or 0
    ))
end

RegisterConsoleCommandHandler("minimap", function(_, _, Ar)
    return WithAr(Ar, function()
        Config.enabled = true
        if MiniMapConfig then MiniMapConfig.enabled = true end
        ExecuteInGameThread(function()
            local ok, why = Ensure()
            if ok then Show() end
            Log("minimap: " .. tostring(why))
            Status()
        end)
    end)
end)

RegisterConsoleCommandHandler("minimap_enable", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local a = Parameters and Parameters[1]
        if a == "0" or a == "off" or a == "false" then
            Config.enabled = false
            if MiniMapConfig then MiniMapConfig.enabled = false end
            if IsU(Overlay) then SetVis(Overlay, VIS_COLLAPSED) end
            Log("Disabled")
        elseif a == "1" or a == "on" or a == "true" then
            Config.enabled = true
            if MiniMapConfig then MiniMapConfig.enabled = true end
            local ok, why = Ensure()
            if ok then Show() end
            Log("Enabled: " .. tostring(why))
        else
            Log("minimap_enable 0|1 (now " .. tostring(Config.enabled) .. ")")
        end
    end)
end)

RegisterConsoleCommandHandler("minimap_size", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local n = Parameters and tonumber(Parameters[1])
        if not n then
            Log("minimap_size <px> (now " .. tostring(Config.size_px) .. ")")
            return
        end
        Config.size_px = n
        if MiniMapConfig then MiniMapConfig.size_px = n end
        LaidOut = false
        if IsU(Overlay) then ApplyViewportLayout(Overlay) end
        Log("size_px=" .. tostring(n))
    end)
end)

RegisterConsoleCommandHandler("minimap_zoom", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local n = Parameters and tonumber(Parameters[1])
        if not n then
            Log("minimap_zoom <0-1> (now " .. tostring(Config.zoom) .. ")")
            return
        end
        ApplyZoom(n)
    end)
end)

RegisterConsoleCommandHandler("minimap_zoom_step", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local n = Parameters and tonumber(Parameters[1])
        if not n then
            Log("minimap_zoom_step <amount> (now " .. tostring(Config.zoom_step)
                .. ")  e.g. 0.05 small, 0.15 big")
            return
        end
        if n < 0.01 then n = 0.01 end
        if n > 0.5 then n = 0.5 end
        Config.zoom_step = n
        if MiniMapConfig then MiniMapConfig.zoom_step = n end
        Log("zoom_step=" .. tostring(n) .. " (Ctrl+Shift+Up/Down)")
    end)
end)

RegisterConsoleCommandHandler("minimap_zoom_in", function(_, _, Ar)
    return WithAr(Ar, function() NudgeZoom(1) end)
end)

RegisterConsoleCommandHandler("minimap_zoom_out", function(_, _, Ar)
    return WithAr(Ar, function() NudgeZoom(-1) end)
end)

RegisterConsoleCommandHandler("minimap_corner", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local a = Parameters and Parameters[1]
        local okc = {
            bottom_right = true, bottom_left = true,
            top_right = true, top_left = true,
        }
        if not a or not okc[a] then
            Log("minimap_corner bottom_right|bottom_left|top_right|top_left (now "
                .. tostring(Config.corner) .. ")")
            return
        end
        Config.corner = a
        if MiniMapConfig then MiniMapConfig.corner = a end
        LaidOut = false
        if IsU(Overlay) then ApplyViewportLayout(Overlay) end
        Log("corner=" .. a)
    end)
end)

RegisterConsoleCommandHandler("minimap_pos", function(_, Parameters, Ar)
    return WithAr(Ar, function()
        local x = Parameters and tonumber(Parameters[1])
        local y = Parameters and tonumber(Parameters[2])
        if not x or not y then
            Log("minimap_pos <offset_x> <offset_y>  +x right, +y down (now "
                .. tostring(Config.offset_x) .. "," .. tostring(Config.offset_y) .. ")")
            return
        end
        Config.offset_x = x
        Config.offset_y = y
        if MiniMapConfig then
            MiniMapConfig.offset_x = x
            MiniMapConfig.offset_y = y
        end
        LaidOut = false
        if IsU(Overlay) then
            LayoutOuterSlot(Field(Overlay, "Slot"), SizePx())
            ApplyViewportLayout(Overlay)
        end
        Log("offset=" .. tostring(x) .. "," .. tostring(y))
    end)
end)

RegisterConsoleCommandHandler("minimap_reload", function(_, _, Ar)
    return WithAr(Ar, function()
        ReloadConfig()
        Destroy()
        if Config.enabled ~= false then
            local ok, why = Ensure()
            Log("Reloaded: " .. tostring(why))
        end
    end)
end)

RegisterConsoleCommandHandler("minimap_dump", function(_, _, Ar)
    return WithAr(Ar, function()
        DumpOverlay()
    end)
end)

RegisterConsoleCommandHandler("minimap_help", function(_, _, Ar)
    return WithAr(Ar, function()
        Log("minimap | enable 0|1 | size | pos | corner | zoom | zoom_step | zoom_in | zoom_out | dump | reload | help")
        Log("Zoom keys: Ctrl+Shift+Up / Ctrl+Shift+Down  step=" .. tostring(Config.zoom_step))
        Status()
    end)
end)

if SharedGet("MiniMapMod_Binds") ~= true then
    if Config.keybind ~= false then
        RegisterKeyBind(Key.N, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
            local now = os.clock()
            if now - LastKeybind < 0.4 then return end
            LastKeybind = now
            if Config.enabled == false or not IsU(Overlay) then
                Config.enabled = true
                if MiniMapConfig then MiniMapConfig.enabled = true end
                local ok, why = Ensure()
                if ok then Show() end
                Log("keybind show: " .. tostring(why))
            else
                Config.enabled = false
                if MiniMapConfig then MiniMapConfig.enabled = false end
                SetVis(Overlay, VIS_COLLAPSED)
                Log("keybind hide")
            end
        end)
    end
    SharedSet("MiniMapMod_Binds", true)
end

if SharedGet("MiniMapMod_ZoomBindsCS") ~= true then
    -- Same 3-arg RegisterKeyBind shape as VehicleScaleMod. 2-arg binds Fatal'd.
    local function ZoomKey(key, dir)
        pcall(function()
            RegisterKeyBind(key, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
                if Config.enabled == false then return end
                ExecuteInGameThread(function()
                    NudgeZoom(dir)
                end)
            end)
        end)
    end
    ZoomKey(Key.UP_ARROW, 1)
    ZoomKey(Key.DOWN_ARROW, -1)
    SharedSet("MiniMapMod_ZoomBindsCS", true)
    Log("Zoom keys: Ctrl+Shift+Up / Ctrl+Shift+Down")
end

if SharedGet("MiniMapMod_Loop") ~= true then
    SharedSet("MiniMapMod_Loop", true)
    local hz = tonumber(Config.update_hz) or 8
    if hz < 2 then hz = 2 end
    if hz > 15 then hz = 15 end
    local ms = math.floor(1000 / hz)
    if ms < 80 then ms = 80 end
    -- Stable callback (not a new closure every pulse). ExecuteInGameThread
    -- every tick with a throwaway function GC'd the EngineTick hook.
    local TickPending = false
    local function GameTick()
        TickPending = false
        pcall(Tick)
    end
    LoopAsync(ms, function()
        if TickPending then return false end
        TickPending = true
        ExecuteInGameThread(GameTick)
        return false
    end)
    Log("Tick every " .. tostring(ms) .. "ms (game thread)")
end

Log("Loaded. minimap | minimap_help   Zoom: Ctrl+Shift+Up / Ctrl+Shift+Down")
