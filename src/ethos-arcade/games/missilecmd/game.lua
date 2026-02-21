local game = {}

local AIM_X_SOURCE_MEMBER = 3
local AIM_Y_SOURCE_MEMBER = 1
local FIRE_SOURCE_MEMBER = 0

local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local FIRE_BUTTON_VALUE = 96
local CONFIG_FILE = "missilecmd.cfg"
local CONFIG_VERSION = 1
local ENABLE_TONES = true
local ASSET_PATH_DEBUG = false
local ASSET_RETRY_INTERVAL = 2.0
local MISSILE_ROTATE_STEP_DEG = 10
local MISSILE_DRAW_SCALE = 1.00
local EXPLOSION_DRAW_SCALE = 1.5
local STRUCTURE_BOTTOM_MARGIN = 20
local MISSILE_PREBAKED_STEP_DEG = 10

local VISUAL_ASSETS = {
    {key = "buildingBitmap1", file = "building1.png", label = "building1"},
    {key = "buildingBitmap2", file = "building2.png", label = "building2"},
    {key = "buildingBitmap3", file = "building3.png", label = "building3"},
    {key = "buildingBitmap4", file = "building4.png", label = "building4"},
    {key = "buildingBitmap5", file = "building5.png", label = "building5"},
    {key = "buildingBitmap6", file = "building6.png", label = "building6"},
    {key = "buildingBitmap7", file = "building7.png", label = "building7"},
    {key = "baseLeftBitmap", file = "base-l.png", label = "base-l"},
    {key = "baseRightBitmap", file = "base-r.png", label = "base-r"},
    {key = "missileBitmap", file = "misile.png", label = "misile"},
    {key = "explosionBitmap", file = "explosion.png", label = "explosion"},
    {key = "explosionBitmap2", file = "explosion2.png", label = "explosion2"}
}

local BUILDING_BITMAP_KEYS = {
    "buildingBitmap1",
    "buildingBitmap2",
    "buildingBitmap3",
    "buildingBitmap4",
    "buildingBitmap5",
    "buildingBitmap6",
    "buildingBitmap7"
}

local BG_VARIANTS = {
    {slot = 1, file = "bg1.png", label = "bg1"},
    {slot = 2, file = "bg2.png", label = "bg2"},
    {slot = 3, file = "bg3.png", label = "bg3"}
}

local DIFFICULTY_EASY = "easy"
local DIFFICULTY_NORMAL = "normal"
local DIFFICULTY_HARD = "hard"

local DIFFICULTY_CHOICE_EASY = 1
local DIFFICULTY_CHOICE_NORMAL = 2
local DIFFICULTY_CHOICE_HARD = 3

local AIM_HEIGHT_HIGH = 1
local AIM_HEIGHT_MID = 2
local AIM_HEIGHT_LOW = 3

local DIFFICULTY_CHOICES_FORM = {
    {"Easy", DIFFICULTY_CHOICE_EASY},
    {"Normal", DIFFICULTY_CHOICE_NORMAL},
    {"Hard", DIFFICULTY_CHOICE_HARD}
}

local BASE_ARMOR_CHOICES_FORM = {
    {"1", 1},
    {"2", 2},
    {"3", 3}
}

local ACTIVE_RENDER_FPS = 20
local IDLE_RENDER_FPS = 12
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.60
local FRAME_SCALE_MAX = 1.90
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local AIM_MARGIN = 10
local AIM_DEADZONE = 40
local AIM_SMOOTH_X = 0.68
local AIM_SMOOTH_Y = 0.66
local AIM_INPUT_FILTER_ALPHA = 0.90
local FIRE_DEADZONE = 110
local FIRE_REARM_CENTER = 200
local FIRE_TRIGGER_HIGH = 520
local FIRE_COOLDOWN = 0.18

local STICK_SOURCE_IS_PERCENT = false
local STICK_RAW_ABS_LIMIT = 5000
local STICK_GLITCH_DELTA_LIMIT = 1900

local DIFFICULTY_PROFILES = {
    [DIFFICULTY_EASY] = {
        incomingBase = 8,
        waveStep = 1,
        spawnInterval = 1.05,
        missileSpeed = 58,
        interceptorSpeed = 275,
        explosionRadius = 32,
        explosionGrow = 100,
        explosionShrink = 76,
        ammoBase = 24
    },
    [DIFFICULTY_NORMAL] = {
        incomingBase = 10,
        waveStep = 2,
        spawnInterval = 0.86,
        missileSpeed = 70,
        interceptorSpeed = 300,
        explosionRadius = 28,
        explosionGrow = 104,
        explosionShrink = 84,
        ammoBase = 21
    },
    [DIFFICULTY_HARD] = {
        incomingBase = 13,
        waveStep = 3,
        spawnInterval = 0.72,
        missileSpeed = 84,
        interceptorSpeed = 325,
        explosionRadius = 24,
        explosionGrow = 112,
        explosionShrink = 92,
        ammoBase = 18
    }
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function frameAdjustedLerp(baseAlpha, dt)
    local a = clamp(tonumber(baseAlpha) or 0, 0, 1)
    local delta = tonumber(dt) or FRAME_TARGET_DT
    if delta <= 0 then
        return a
    end

    -- Keep control response consistent even when actual FPS differs from target FPS.
    local frameRatio = clamp(delta / FRAME_TARGET_DT, 0.35, 3.0)
    return 1 - ((1 - a) ^ frameRatio)
end

local function keyMatches(value, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        if key and value == key then
            return true
        end
    end
    return false
end

local function isKeyCategory(category)
    if type(EVT_KEY) == "number" then
        return category == EVT_KEY
    end
    return category == 0
end

local function isConfigButtonEvent(category, value)
    if type(EVT_KEY) == "number" then
        return category == EVT_KEY and value == CONFIG_BUTTON_VALUE
    end
    return category == CONFIG_BUTTON_CATEGORY and value == CONFIG_BUTTON_VALUE
end

local function isSettingsOpenEvent(category, value)
    return isConfigButtonEvent(category, value)
end

local function isFireButtonEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end
    if keyMatches(value, KEY_PAGE_FIRST, KEY_PAGE_BREAK) then
        return true
    end
    return value == FIRE_BUTTON_VALUE
end

local function isExitKeyEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end
    if keyMatches(value, KEY_EXIT_BREAK, KEY_EXIT_FIRST) then
        return true
    end
    return value == 35
end

local function normalizeDifficulty(value)
    if value == DIFFICULTY_EASY then
        return DIFFICULTY_EASY
    end
    if value == DIFFICULTY_HARD then
        return DIFFICULTY_HARD
    end
    return DIFFICULTY_NORMAL
end

local function normalizeBaseArmor(value)
    local n = tonumber(value) or 2
    return clamp(math.floor(n + 0.5), 1, 3)
end

local function normalizeAimHeight(value)
    local n = tonumber(value)
    if n == AIM_HEIGHT_HIGH then return AIM_HEIGHT_HIGH end
    if n == AIM_HEIGHT_LOW then return AIM_HEIGHT_LOW end
    return AIM_HEIGHT_MID
end

local function difficultyChoiceValue(difficulty)
    local normalized = normalizeDifficulty(difficulty)
    if normalized == DIFFICULTY_EASY then
        return DIFFICULTY_CHOICE_EASY
    end
    if normalized == DIFFICULTY_HARD then
        return DIFFICULTY_CHOICE_HARD
    end
    return DIFFICULTY_CHOICE_NORMAL
end

local function difficultyFromChoice(choice)
    if tonumber(choice) == DIFFICULTY_CHOICE_EASY then
        return DIFFICULTY_EASY
    end
    if tonumber(choice) == DIFFICULTY_CHOICE_HARD then
        return DIFFICULTY_HARD
    end
    return DIFFICULTY_NORMAL
end

local function difficultyLabel(difficulty)
    local normalized = normalizeDifficulty(difficulty)
    if normalized == DIFFICULTY_EASY then
        return "Easy"
    end
    if normalized == DIFFICULTY_HARD then
        return "Hard"
    end
    return "Normal"
end

local function aimHeightRatio(aimHeight)
    local normalized = normalizeAimHeight(aimHeight)
    if normalized == AIM_HEIGHT_HIGH then
        return 0.30
    end
    if normalized == AIM_HEIGHT_LOW then
        return 0.44
    end
    return 0.36
end

local function aimHeightLabel(aimHeight)
    local normalized = normalizeAimHeight(aimHeight)
    if normalized == AIM_HEIGHT_HIGH then
        return "High"
    end
    if normalized == AIM_HEIGHT_LOW then
        return "Low"
    end
    return "Mid"
end

local function aimYRange(state)
    local top = 12
    local bottom = state.groundY - 22
    if bottom <= top then
        return top, top
    end

    local mode = normalizeAimHeight(AIM_HEIGHT_LOW)
    if mode == AIM_HEIGHT_HIGH then
        bottom = clamp(state.groundY - 78, top + 24, bottom)
    elseif mode == AIM_HEIGHT_MID then
        bottom = clamp(state.groundY - 52, top + 24, bottom)
    else
        bottom = clamp(state.groundY - 30, top + 24, bottom)
    end

    return top, bottom
end

local function nowSeconds()
    if os and os.clock then
        return os.clock()
    end
    return 0
end

local function scriptDir()
    if not (debug and debug.getinfo) then
        return nil
    end

    local ok, info = pcall(debug.getinfo, 1, "S")
    if not ok or not info or type(info.source) ~= "string" then
        return nil
    end

    local source = info.source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end

    return source:match("^(.*[/\\])")
end

local SCRIPT_DIR = scriptDir() or ""

local function assetPathCandidates(filename)
    local paths = {}
    if SCRIPT_DIR ~= "" then
        paths[#paths + 1] = SCRIPT_DIR .. "gfx/" .. filename
    end
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "/scripts/ethos-arcade/games/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "games/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "gfx/" .. filename
    return paths
end

local function loadBitmapAsset(filename, label)
    if not (lcd and lcd.loadBitmap and filename) then
        return nil
    end

    for _, path in ipairs(assetPathCandidates(filename)) do
        if ASSET_PATH_DEBUG then
            print(string.format("[missilecmd] try %s: %s", tostring(label or filename), tostring(path)))
        end
        local ok, bmp = pcall(lcd.loadBitmap, path)
        if ok and bmp then
            if ASSET_PATH_DEBUG then
                print(string.format("[missilecmd] loaded %s: %s", tostring(label or filename), tostring(path)))
            end
            return bmp
        end
        if ASSET_PATH_DEBUG then
            if ok then
                print(string.format("[missilecmd] failed %s: %s", tostring(label or filename), tostring(path)))
            else
                print(string.format("[missilecmd] error %s: %s (%s)", tostring(label or filename), tostring(path), tostring(bmp)))
            end
        end
    end

    if ASSET_PATH_DEBUG then
        print(string.format("[missilecmd] missing %s", tostring(label or filename)))
    end
    return nil
end

local function bitmapSize(bitmap)
    if not bitmap or not bitmap.width or not bitmap.height then
        return nil, nil
    end

    local okW, w = pcall(bitmap.width, bitmap)
    local okH, h = pcall(bitmap.height, bitmap)
    if not okW or not okH or type(w) ~= "number" or type(h) ~= "number" then
        return nil, nil
    end
    if w <= 0 or h <= 0 then
        return nil, nil
    end
    return w, h
end

local function drawBitmapScaled(bitmap, x, y, w, h)
    if not (bitmap and lcd and lcd.drawBitmap) then
        return false
    end

    if w and h then
        local ok = pcall(lcd.drawBitmap, x, y, bitmap, w, h)
        if ok then
            return true
        end
    end

    return pcall(lcd.drawBitmap, x, y, bitmap)
end

local function normalizeDegrees(angle)
    local n = tonumber(angle) or 0
    n = n % 360
    if n < 0 then
        n = n + 360
    end
    return n
end

local function angleDegreesFromVector(dx, dy)
    if dx == 0 and dy == 0 then
        return 0
    end

    local rad = 0
    if math.atan2 then
        rad = math.atan2(dy, dx)
    elseif math.atan then
        local ok, value = pcall(math.atan, dy, dx)
        if ok and type(value) == "number" then
            rad = value
        else
            if dx == 0 then
                if dy >= 0 then
                    rad = math.pi * 0.5
                else
                    rad = -math.pi * 0.5
                end
            else
                rad = math.atan(dy / dx)
                if dx < 0 then
                    if dy >= 0 then
                        rad = rad + math.pi
                    else
                        rad = rad - math.pi
                    end
                end
            end
        end
    end

    return math.deg(rad)
end

local function rotatedBitmap(state, bitmap, cachePrefix, angleDegrees)
    if not bitmap then
        return nil
    end
    if not bitmap.rotate then
        return bitmap
    end

    local step = math.max(1, MISSILE_ROTATE_STEP_DEG)
    local snapped = math.floor((normalizeDegrees(angleDegrees) / step) + 0.5) * step
    snapped = snapped % 360

    if not state.rotatedBitmapCache then
        state.rotatedBitmapCache = {}
    end

    local key = string.format("%s:%d", tostring(cachePrefix or "bitmap"), snapped)
    local cached = state.rotatedBitmapCache[key]
    if cached == false then
        return bitmap
    end
    if cached then
        return cached
    end

    local ok, rotated = pcall(bitmap.rotate, bitmap, snapped)
    if ok and rotated then
        state.rotatedBitmapCache[key] = rotated
        return rotated
    end

    state.rotatedBitmapCache[key] = false
    return bitmap
end

local function loadPrebakedMissileFrames(state)
    if not state or state.missilePrebakedLoaded then
        return
    end

    state.missilePrebakedLoaded = true
    state.missilePrebaked = {}

    local step = math.max(1, MISSILE_PREBAKED_STEP_DEG)
    local firstFrame = nil
    for deg = 0, 350, step do
        local file = string.format("missile_%03d.png", deg)
        local bitmap = loadBitmapAsset(file, file)
        if bitmap then
            state.missilePrebaked[deg] = bitmap
            if not firstFrame then
                firstFrame = bitmap
            end
        end
    end

    state.missilePrebakedFallback = firstFrame
end

local function bitmapForDirection(state, bitmap, cachePrefix, dx, dy)
    local baseBitmap = bitmap
    if not baseBitmap and state then
        baseBitmap = state.missileBitmap or state.missilePrebakedFallback
    end

    if dx == 0 and dy == 0 then
        return baseBitmap
    end

    -- Asset is authored pointing "up"; convert vector angle to that basis.
    local angle = normalizeDegrees(angleDegreesFromVector(dx, dy) + 90)

    local prebaked = state and state.missilePrebaked
    if prebaked then
        local step = math.max(1, MISSILE_PREBAKED_STEP_DEG)
        local snapped = math.floor((angle / step) + 0.5) * step
        snapped = snapped % 360
        local preBitmap = prebaked[snapped]
        if preBitmap then
            return preBitmap
        end

        local nearestBitmap = nil
        local nearestDelta = 999
        for deg, candidate in pairs(prebaked) do
            local delta = math.abs(deg - snapped)
            delta = math.min(delta, 360 - delta)
            if delta < nearestDelta then
                nearestDelta = delta
                nearestBitmap = candidate
            end
        end
        if nearestBitmap then
            return nearestBitmap
        end
    end

    if baseBitmap then
        return rotatedBitmap(state, baseBitmap, cachePrefix, angle)
    end

    return nil
end

local function resolveMissileVisual(state, dx, dy, cachePrefix)
    local missileBitmap = bitmapForDirection(state, state.missileBitmap, cachePrefix, dx, dy)
    if not missileBitmap then
        return nil, nil, nil, nil, nil, false
    end

    local bw, bh = bitmapSize(missileBitmap)
    if not bw or not bh then
        return missileBitmap, nil, nil, nil, nil, true
    end

    local drawW = math.max(1, math.floor((bw * MISSILE_DRAW_SCALE) + 0.5))
    local drawH = math.max(1, math.floor((bh * MISSILE_DRAW_SCALE) + 0.5))
    local halfW = math.floor(drawW * 0.5)
    local halfH = math.floor(drawH * 0.5)
    local useNative = (drawW == bw and drawH == bh)

    return missileBitmap, drawW, drawH, halfW, halfH, useNative
end

local function loadVisualAssets(state)
    if not state then
        return
    end

    if state.assetsLoaded and state.assetsTotal and state.assetsLoaded >= state.assetsTotal then
        return
    end

    local t = nowSeconds()
    if state.nextAssetProbeAt and state.nextAssetProbeAt > t then
        return
    end
    state.nextAssetProbeAt = t + ASSET_RETRY_INTERVAL

    for i = 1, #VISUAL_ASSETS do
        local spec = VISUAL_ASSETS[i]
        if not state[spec.key] then
            state[spec.key] = loadBitmapAsset(spec.file, spec.label)
        end
    end

    local loaded = 0
    local missing = {}
    for i = 1, #VISUAL_ASSETS do
        local spec = VISUAL_ASSETS[i]
        if state[spec.key] then
            loaded = loaded + 1
        else
            missing[#missing + 1] = spec.file
        end
    end

    state.assetsLoaded = loaded
    state.assetsTotal = #VISUAL_ASSETS
    state.assetsMissing = missing
    state.cityBitmaps = {}
    for i = 1, #BUILDING_BITMAP_KEYS do
        local key = BUILDING_BITMAP_KEYS[i]
        if state[key] then
            state.cityBitmaps[#state.cityBitmaps + 1] = state[key]
        end
    end

    loadPrebakedMissileFrames(state)
    if not state.missileBitmap and state.missilePrebakedFallback then
        state.missileBitmap = state.missilePrebakedFallback
    end
end

local function releaseAssets(state)
    if not state then
        return
    end

    for i = 1, #VISUAL_ASSETS do
        local spec = VISUAL_ASSETS[i]
        state[spec.key] = nil
    end

    state.cityBitmaps = nil
    state.assetsLoaded = nil
    state.assetsTotal = nil
    state.assetsMissing = nil

    state.missilePrebaked = nil
    state.missilePrebakedLoaded = nil
    state.missilePrebakedFallback = nil
    state.rotatedBitmapCache = nil

    state.activeBgBitmap = nil
    state.activeBgSlot = nil

    state.incoming = nil
    state.interceptors = nil
    state.explosions = nil
end

local function loadBackgroundVariant(slot)
    local variant = BG_VARIANTS[slot]
    if not variant then
        return nil
    end

    local bitmap = loadBitmapAsset(variant.file, variant.label)
    if bitmap then
        return bitmap
    end

    if variant.fallback then
        return loadBitmapAsset(variant.fallback, variant.fallback)
    end
    return nil
end

local function activateBackgroundVariant(state, slot)
    if not state then
        return false
    end
    if state.activeBgBitmap and state.activeBgSlot == slot then
        return true
    end

    -- Keep only one background in memory: release current before loading next.
    if state.activeBgBitmap and state.activeBgSlot ~= slot then
        state.activeBgBitmap = nil
        state.activeBgSlot = nil
        if collectgarbage then
        pcall(collectgarbage, "collect")
        pcall(collectgarbage, "collect")
    end
    end

    local bitmap = loadBackgroundVariant(slot)
    if not bitmap then
        return false
    end

    state.activeBgBitmap = bitmap
    state.activeBgSlot = slot
    return true
end

local function selectRandomBackground(state, avoidCurrent)
    if not state then
        return false
    end

    local total = #BG_VARIANTS
    if total <= 0 then
        state.activeBgBitmap = nil
        state.activeBgSlot = nil
        return false
    end

    local previousSlot = state.activeBgSlot
    local current = state.activeBgSlot
    local start = math.random(1, total)
    local deferredCurrent = nil

    for step = 0, total - 1 do
        local slot = ((start + step - 1) % total) + 1
        if avoidCurrent and current and total > 1 and slot == current then
            deferredCurrent = slot
        else
            if activateBackgroundVariant(state, slot) then
                return true
            end
        end
    end

    if deferredCurrent and activateBackgroundVariant(state, deferredCurrent) then
        return true
    end

    -- Last-resort recovery: attempt to restore previously working background.
    if previousSlot and activateBackgroundVariant(state, previousSlot) then
        return true
    end

    return false
end

local function prepareBackgroundForNewRun(state)
    if not state then
        return
    end

    -- Force an immediate asset probe before selecting a run background.
    state.nextAssetProbeAt = 0
    loadVisualAssets(state)
    if selectRandomBackground(state, false) then
        return
    end

    if not state.activeBgBitmap then
        selectRandomBackground(state, false)
    end
end

local function configPathCandidates()
    local paths = {}
    if SCRIPT_DIR ~= "" then
        paths[#paths + 1] = SCRIPT_DIR .. CONFIG_FILE
    end
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/missilecmd/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/missilecmd/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/ethos-arcade/games/missilecmd/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/missilecmd/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/missilecmd/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/missilecmd/" .. CONFIG_FILE
    paths[#paths + 1] = CONFIG_FILE
    return paths
end

local function readConfigFile()
    local values = {}
    if not (io and io.open) then
        return values
    end

    local f
    for _, path in ipairs(configPathCandidates()) do
        f = io.open(path, "r")
        if f then
            break
        end
    end
    if not f then
        return values
    end

    while true do
        local okRead, line = pcall(f.read, f, "*l")
        if not okRead or not line then
            break
        end
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key and value and value ~= "" then
            values[key] = value
        end
    end

    pcall(f.close, f)
    return values
end

local function loadStateConfig()
    local values = readConfigFile()
    local bestScore = tonumber(values.bestScore)
    if bestScore then
        bestScore = math.floor(bestScore)
    else
        bestScore = nil
    end

    local config = {
        difficulty = normalizeDifficulty(values.difficulty),
        baseArmor = normalizeBaseArmor(values.baseArmor)
    }

    return config, bestScore
end

local function saveStateConfig(state)
    if not (state and state.config and io and io.open) then
        return false
    end

    local f
    for _, path in ipairs(configPathCandidates()) do
        f = io.open(path, "w")
        if f then
            break
        end
    end
    if not f then
        return false
    end

    f:write("version=", CONFIG_VERSION, "\n")
    f:write("difficulty=", normalizeDifficulty(state.config.difficulty), "\n")
    f:write("baseArmor=", normalizeBaseArmor(state.config.baseArmor), "\n")
    if state.bestScore ~= nil then
        f:write("bestScore=", math.floor(state.bestScore), "\n")
    end

    f:close()
    return true
end

local function setColor(r, g, b)
    if not (lcd and lcd.color and lcd.RGB) then
        return
    end
    pcall(lcd.color, lcd.RGB(clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255)))
end

local function setFont(font)
    if not (lcd and lcd.font and font) then
        return
    end
    pcall(lcd.font, font)
end

local function getTextSize(text)
    local s = text or ""
    local fallbackW = math.max(8, #s * 8)
    local fallbackH = 14

    if lcd and lcd.getTextSize then
        local ok, w, h = pcall(lcd.getTextSize, s)
        if ok and type(w) == "number" then
            return w, (type(h) == "number" and h or fallbackH)
        end

        ok, w, h = pcall(lcd.getTextSize)
        if ok and type(w) == "number" then
            return w, (type(h) == "number" and h or fallbackH)
        end
    end

    return fallbackW, fallbackH
end

local function drawCenteredText(x, y, w, h, text)
    local tw, th = getTextSize(text)
    local tx = x + math.floor((w - tw) * 0.5)
    local ty = y + math.floor((h - th) * 0.5)
    lcd.drawText(tx, ty, text)
end

local function playTone(freq, duration, pause)
    if not ENABLE_TONES then
        return
    end
    if not (system and system.playTone) then
        return
    end
    pcall(system.playTone, freq, duration or 30, pause or 0)
end

local function keepScreenAwake(state)
    if not state then
        return
    end

    local now = nowSeconds()
    if state.lastFocusKick and (now - state.lastFocusKick) < 1.0 then
        return
    end
    state.lastFocusKick = now

    if system and system.resetBacklightTimeout then
        pcall(system.resetBacklightTimeout)
    end

    if system and system.resetFocusTimeout then
        pcall(system.resetFocusTimeout)
        return
    end

    if resetFocusTimeout then
        pcall(resetFocusTimeout)
        return
    end

    if system and system.resetTimeout then
        pcall(system.resetTimeout)
    end
end

local function forceInvalidate(state)
    if not state then
        return
    end
    state.nextInvalidateAt = 0
    if lcd and lcd.invalidate then
        lcd.invalidate()
    end
end

local function requestTimedInvalidate(state)
    if not (state and lcd and lcd.invalidate) then
        return
    end

    local now = nowSeconds()
    local interval = state.running and ACTIVE_INVALIDATE_DT or IDLE_INVALIDATE_DT
    if (not state.nextInvalidateAt) or now >= state.nextInvalidateAt then
        state.nextInvalidateAt = now + interval
        lcd.invalidate()
    end
end

local function updateFrameScale(state)
    local now = nowSeconds()
    if (not state.lastFrameTime) or state.lastFrameTime <= 0 then
        state.lastFrameTime = now
        state.frameScale = 1
        return
    end

    local dt = now - state.lastFrameTime
    state.lastFrameTime = now

    if dt <= 0 then
        state.frameScale = 1
        return
    end

    if dt > 0.2 then
        state.frameScale = 1
        return
    end

    state.frameScale = clamp(dt / FRAME_TARGET_DT, FRAME_SCALE_MIN, FRAME_SCALE_MAX)
end

local function resolveAnalogSource(member)
    if not system or not system.getSource then
        return nil
    end
    local ok, src = pcall(system.getSource, {category = CATEGORY_ANALOG, member = member})
    if ok then
        return src
    end
    return nil
end

local function sourceValue(src)
    if not (src and src.value) then
        return 0
    end
    local ok, value = pcall(src.value, src)
    if not ok then
        return 0
    end
    if type(value) == "number" then
        return value
    end
    return tonumber(value) or 0
end

local function toSigned16(v)
    if v > 32767 then
        return v - 65536
    end
    if v < -32768 then
        return v + 65536
    end
    return v
end

local function normalizeStick(v)
    v = tonumber(v) or 0
    v = toSigned16(v)
    if STICK_SOURCE_IS_PERCENT then
        v = v * 10.24
    end
    return clamp(v, -1024, 1024)
end

local function applyDeadzone(v, deadzone)
    deadzone = math.floor(tonumber(deadzone) or 0)
    if deadzone < 0 then
        deadzone = 0
    end
    if deadzone >= 1024 then
        return 0
    end

    v = tonumber(v) or 0
    if math.abs(v) <= deadzone then
        return 0
    end

    local scaled
    if v > 0 then
        scaled = (v - deadzone) / (1024 - deadzone)
    else
        scaled = (v + deadzone) / (1024 - deadzone)
    end

    return clamp(scaled * 1024, -1024, 1024)
end

local function sanitizeStickSample(state, raw, axisKey)
    axisKey = axisKey or "main"
    raw = tonumber(raw) or 0
    raw = toSigned16(raw)
    if STICK_SOURCE_IS_PERCENT then
        raw = raw * 10.24
    end

    if not state.lastRawInputByAxis then
        state.lastRawInputByAxis = {}
    end
    local last = state.lastRawInputByAxis[axisKey]

    if math.abs(raw) > STICK_RAW_ABS_LIMIT then
        raw = last or 0
    elseif last ~= nil and math.abs(raw - last) > STICK_GLITCH_DELTA_LIMIT then
        raw = last
    end

    raw = normalizeStick(raw)
    state.lastRawInputByAxis[axisKey] = raw
    return raw
end

local function mapInputToActionRange(value, rangeStart, rangeEnd)
    return rangeStart + (rangeEnd - rangeStart) * ((value + 1024) / 2048)
end

local function killPendingKeyEvents(keyValue)
    if not (system and system.killEvents) then
        return
    end

    if keyValue ~= nil then
        local ok = pcall(system.killEvents, keyValue)
        if ok then
            return
        end
    end

    pcall(system.killEvents)
end

local function suppressExitEvents(state, windowSeconds)
    if not state then
        return
    end
    local now = nowSeconds()
    state.suppressExitUntil = now + (windowSeconds or 0.25)
    killPendingKeyEvents(KEY_EXIT_BREAK)
    killPendingKeyEvents(KEY_EXIT_FIRST)
end

local function suppressEnterEvents(state, windowSeconds)
    if not state then
        return
    end
    local now = nowSeconds()
    state.suppressEnterUntil = now + (windowSeconds or 0.20)
    killPendingKeyEvents(KEY_ENTER_BREAK)
    killPendingKeyEvents(KEY_ENTER_FIRST)
end

local function safeFormClear()
    if not (form and form.clear) then
        return false
    end
    return pcall(function()
        form.clear()
    end)
end

local function flushPendingFormClear(state, keepPendingOnFailure)
    if not state or not state.pendingFormClear then
        return true
    end
    if state.settingsFormOpen then
        return false
    end
    if safeFormClear() then
        state.pendingFormClear = false
        return true
    end
    if not keepPendingOnFailure then
        state.pendingFormClear = false
    end
    return false
end

local function refreshGeometry(state)
    local width, height = 480, 272
    if lcd and lcd.getWindowSize then
        local w, h = lcd.getWindowSize()
        if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
            width, height = w, h
        end
    end

    local changed = (state.width ~= width or state.height ~= height)
    state.width = width
    state.height = height

    state.groundHeight = math.max(28, math.floor(height * 0.22))
    state.groundY = height - state.groundHeight
    state.baseX = math.floor(width * 0.5)
    state.baseY = state.height - 1
    state.baseHalfW = math.max(9, math.floor(width * 0.03))
    state.baseHeight = math.max(10, math.floor(height * 0.08))
    state.baseHitRadius = math.max(state.baseHalfW + 4, math.floor(width * 0.06))

    state.aimMinY, state.aimMaxY = aimYRange(state)

    if state.aimX then
        state.aimX = clamp(state.aimX, AIM_MARGIN, state.width - AIM_MARGIN)
    end
    if state.aimY then
        state.aimY = clamp(state.aimY, state.aimMinY, state.aimMaxY)
    else
        local aimRatio = aimHeightRatio(AIM_HEIGHT_LOW)
        state.aimY = clamp(math.floor(height * aimRatio), state.aimMinY, state.aimMaxY)
    end

    if changed then
        forceInvalidate(state)
    end
end

local function refreshCityPositions(state)
    local cityCount = 5
    local padding = math.max(8, math.floor(state.width * 0.07))
    local segment = (state.width - (padding * 2)) / (cityCount - 1)
    local baseClearHalfWidth = math.max(state.baseHitRadius + 18, math.floor(state.width * 0.11))

    state.cityPositions = {}
    for i = 0, cityCount - 1 do
        local x = math.floor(padding + (segment * i))
        -- Keep the center area clear so no city appears behind the turret.
        if math.abs(x - state.baseX) > baseClearHalfWidth then
            state.cityPositions[#state.cityPositions + 1] = x
        end
    end
end

local function applyConfigSideEffects(state)
    if not (state and state.config) then
        return
    end

    state.config.difficulty = normalizeDifficulty(state.config.difficulty)
    state.config.baseArmor = normalizeBaseArmor(state.config.baseArmor)

    state.profile = DIFFICULTY_PROFILES[state.config.difficulty] or DIFFICULTY_PROFILES[DIFFICULTY_NORMAL]
    refreshGeometry(state)
end

local function setConfigValue(state, key, value, skipSave)
    if not (state and state.config) then
        return
    end

    if key == "difficulty" then
        state.config.difficulty = normalizeDifficulty(value)
    elseif key == "baseArmor" then
        state.config.baseArmor = normalizeBaseArmor(value)
    else
        return
    end

    applyConfigSideEffects(state)

    if not skipSave then
        saveStateConfig(state)
    end
end

local function closeSettingsForm(state, suppressExit, suppressEnter)
    if suppressExit ~= false then
        suppressExitEvents(state)
    end
    if suppressEnter then
        suppressEnterEvents(state)
    end

    state.settingsFormOpen = false
    state.pendingFormClear = true
    flushPendingFormClear(state, true)
    forceInvalidate(state)
end

local function openSettingsForm(state)
    if not (form and form.clear and form.addLine and form.addChoiceField) then
        return false
    end

    if not safeFormClear() then
        state.settingsFormOpen = false
        return false
    end
    state.settingsFormOpen = true

    local infoLine = form.addLine("MissileCmd")
    if form.addStaticText then
        form.addStaticText(infoLine, nil, "Settings (Exit/Back to return)")
    end

    local diffLine = form.addLine("Difficulty")
    form.addChoiceField(
        diffLine,
        nil,
        DIFFICULTY_CHOICES_FORM,
        function()
            return difficultyChoiceValue(state.config.difficulty)
        end,
        function(newValue)
            setConfigValue(state, "difficulty", difficultyFromChoice(newValue))
        end
    )

    local armorLine = form.addLine("Base armor")
    form.addChoiceField(
        armorLine,
        nil,
        BASE_ARMOR_CHOICES_FORM,
        function()
            return normalizeBaseArmor(state.config.baseArmor)
        end,
        function(newValue)
            setConfigValue(state, "baseArmor", newValue)
        end
    )

    local bestLine = form.addLine("Best score")
    local resetAction = function()
        state.bestScore = nil
        saveStateConfig(state)
    end

    if form.addButton then
        form.addButton(bestLine, nil, {text = "Reset", press = resetAction})
    elseif form.addTextButton then
        form.addTextButton(bestLine, nil, "Reset", resetAction)
    end

    local backLine = form.addLine("")
    local backAction = function()
        closeSettingsForm(state, true, true)
    end

    if form.addButton then
        form.addButton(backLine, nil, {text = "Back to Game", press = backAction})
    elseif form.addTextButton then
        form.addTextButton(backLine, nil, "Back to Game", backAction)
    end

    return true
end

local function clearEntities(state)
    state.incoming = {}
    state.interceptors = {}
    state.explosions = {}
end

local function rebuildSkyStars(state)
    state.stars = {}
    local count = math.max(16, math.floor(state.width * state.height / 9000))
    local skyMaxY = math.max(12, state.groundY - 30)

    for i = 1, count do
        state.stars[#state.stars + 1] = {
            x = math.random(2, math.max(2, state.width - 3)),
            y = math.random(2, skyMaxY),
            twinkle = math.random()
        }
    end
end

local function applyWaveSettings(state)
    local profile = state.profile or DIFFICULTY_PROFILES[DIFFICULTY_NORMAL]
    local waveIndex = math.max(1, state.wave)

    state.incomingToSpawn = profile.incomingBase + ((waveIndex - 1) * profile.waveStep)
    state.spawnInterval = math.max(profile.spawnInterval * 0.58, profile.spawnInterval - ((waveIndex - 1) * 0.022))
    state.spawnTimer = 0.42

    state.missileSpeed = profile.missileSpeed * (1 + ((waveIndex - 1) * 0.045))
    state.interceptorSpeed = profile.interceptorSpeed
    state.explosionMaxR = profile.explosionRadius
    state.explosionGrowRate = profile.explosionGrow
    state.explosionShrinkRate = profile.explosionShrink

    state.ammo = profile.ammoBase + math.floor((waveIndex - 1) * 0.75)
end

local function spawnIncoming(state)
    local margin = AIM_MARGIN
    local startX = math.random(margin, math.max(margin, state.width - margin))

    local targetX
    if math.random() < 0.26 then
        targetX = state.baseX + ((math.random() * 2 - 1) * (state.baseHitRadius * 1.3))
    else
        targetX = math.random(margin, math.max(margin, state.width - margin))
    end
    targetX = clamp(targetX, margin, state.width - margin)

    local dx = targetX - startX
    local dy = state.groundY
    local dist = math.sqrt((dx * dx) + (dy * dy))
    if dist < 1 then
        dist = 1
    end
    local missileBitmap, drawW, drawH, halfW, halfH, useNative = resolveMissileVisual(state, dx, dy, "missile-incoming")

    state.incoming[#state.incoming + 1] = {
        sx = startX,
        sy = 0,
        tx = targetX,
        ty = state.groundY,
        x = startX,
        y = 0,
        prevX = startX,
        prevY = 0,
        progress = 0,
        dist = dist,
        speed = state.missileSpeed,
        missileBitmap = missileBitmap,
        missileDrawW = drawW,
        missileDrawH = drawH,
        missileHalfW = halfW,
        missileHalfH = halfH,
        missileUseNative = useNative
    }

    state.incomingToSpawn = math.max(0, state.incomingToSpawn - 1)
end

local function createExplosion(state, x, y)
    state.explosions[#state.explosions + 1] = {
        x = x,
        y = y,
        r = 2,
        maxR = state.explosionMaxR,
        growing = true
    }
end

local function launchInterceptor(state)
    if state.ammo <= 0 then
        return false
    end

    state.ammo = state.ammo - 1

    local tx = state.aimX
    local ty = state.aimY

    local dx = tx - state.baseX
    local dy = ty - state.baseY
    local dist = math.sqrt((dx * dx) + (dy * dy))
    if dist < 1 then
        dist = 1
    end
    local missileBitmap, drawW, drawH, halfW, halfH, useNative = resolveMissileVisual(state, dx, dy, "missile-interceptor")

    state.interceptors[#state.interceptors + 1] = {
        sx = state.baseX,
        sy = state.baseY,
        tx = tx,
        ty = ty,
        x = state.baseX,
        y = state.baseY,
        progress = 0,
        dist = dist,
        speed = state.interceptorSpeed,
        missileBitmap = missileBitmap,
        missileDrawW = drawW,
        missileDrawH = drawH,
        missileHalfW = halfW,
        missileHalfH = halfH,
        missileUseNative = useNative
    }

    playTone(980, 20, 0)
    return true
end

local function tryFire(state)
    if not state then
        return false
    end
    if (state.fireCooldown or 0) > 0 then
        return false
    end
    if launchInterceptor(state) then
        state.fireCooldown = FIRE_COOLDOWN
        return true
    end
    return false
end

local function setupWave(state, firstWave)
    if not firstWave then
        state.wave = state.wave + 1
        state.score = state.score + (5 * state.wave)
        state.baseHitsRemaining = math.min(state.config.baseArmor, state.baseHitsRemaining + 1)
        playTone(1320, 70, 25)
    end

    applyWaveSettings(state)
end

local function stopRound(state, keepResult)
    state.running = false
    state.gameOver = false

    if not keepResult then
        state.lastResult = nil
        state.isNewBest = false
    end

    clearEntities(state)
    state.incomingToSpawn = 0
    state.spawnTimer = 0
end

local function finishGame(state)
    state.running = false
    state.gameOver = true
    state.lastResult = state.score

    if state.bestScore == nil or state.score > state.bestScore then
        state.bestScore = state.score
        state.isNewBest = true
        saveStateConfig(state)
        playTone(1250, 140, 35)
    else
        state.isNewBest = false
        playTone(300, 170, 30)
    end
end

local function startGame(state)
    prepareBackgroundForNewRun(state)

    state.running = true
    state.gameOver = false
    state.lastResult = nil
    state.isNewBest = false
    state.wave = 1
    state.score = 0
    state.baseHitsRemaining = state.config.baseArmor
    state.fireCooldown = 0
    state.fireArmed = false
    state.filteredAimX = nil
    state.filteredAimY = nil
    state.aimX = state.baseX
    local aimRatio = aimHeightRatio(AIM_HEIGHT_LOW)
    state.aimY = clamp(math.floor(state.height * aimRatio), state.aimMinY or 12, state.aimMaxY or (state.groundY - 22))
    state.lastRawInputByAxis = {}

    clearEntities(state)
    setupWave(state, true)
    forceInvalidate(state)
end

local function updateAimAndFire(state, dt)
    local rawAimX = sanitizeStickSample(state, sourceValue(state.aimXSource), "aimX")
    local rawAimY = sanitizeStickSample(state, sourceValue(state.aimYSource), "aimY")
    if state.filteredAimX == nil then
        state.filteredAimX = rawAimX
    else
        state.filteredAimX = state.filteredAimX + ((rawAimX - state.filteredAimX) * AIM_INPUT_FILTER_ALPHA)
    end
    if state.filteredAimY == nil then
        state.filteredAimY = rawAimY
    else
        state.filteredAimY = state.filteredAimY + ((rawAimY - state.filteredAimY) * AIM_INPUT_FILTER_ALPHA)
    end

    rawAimX = applyDeadzone(state.filteredAimX, AIM_DEADZONE)
    rawAimY = applyDeadzone(state.filteredAimY, AIM_DEADZONE)

    local aimMinY = state.aimMinY or 12
    local aimMaxY = state.aimMaxY or (state.groundY - 22)

    local targetX = mapInputToActionRange(rawAimX, AIM_MARGIN, state.width - AIM_MARGIN)
    local targetY = mapInputToActionRange(-rawAimY, aimMinY, aimMaxY)

    local aimSmoothX = frameAdjustedLerp(AIM_SMOOTH_X, dt)
    local aimSmoothY = frameAdjustedLerp(AIM_SMOOTH_Y, dt)
    state.aimX = state.aimX + ((targetX - state.aimX) * aimSmoothX)
    state.aimY = state.aimY + ((targetY - state.aimY) * aimSmoothY)
    state.aimX = clamp(state.aimX, AIM_MARGIN, state.width - AIM_MARGIN)
    state.aimY = clamp(state.aimY, aimMinY, aimMaxY)

    local rawFire = sanitizeStickSample(state, sourceValue(state.fireSource), "fire")
    rawFire = applyDeadzone(rawFire, FIRE_DEADZONE)

    state.fireCooldown = math.max(0, (state.fireCooldown or 0) - (dt or 0))

    if math.abs(rawFire) <= FIRE_REARM_CENTER then
        state.fireArmed = true
    end

    if state.fireArmed and math.abs(rawFire) >= FIRE_TRIGGER_HIGH and state.fireCooldown <= 0 then
        tryFire(state)
        state.fireArmed = false
    end
end

local function updateSpawner(state, dt)
    if state.incomingToSpawn <= 0 then
        return
    end

    state.spawnTimer = (state.spawnTimer or 0) - dt
    while state.spawnTimer <= 0 and state.incomingToSpawn > 0 do
        spawnIncoming(state)
        local jitter = 0.84 + (math.random() * 0.34)
        state.spawnTimer = state.spawnTimer + (state.spawnInterval * jitter)
    end
end

local function updateInterceptors(state, dt)
    for i = #state.interceptors, 1, -1 do
        local p = state.interceptors[i]
        p.progress = p.progress + ((p.speed * dt) / p.dist)

        if p.progress >= 1 then
            p.x = p.tx
            p.y = p.ty
            createExplosion(state, p.x, p.y)
            table.remove(state.interceptors, i)
        else
            p.x = p.sx + ((p.tx - p.sx) * p.progress)
            p.y = p.sy + ((p.ty - p.sy) * p.progress)
        end
    end
end

local function updateExplosions(state, dt)
    for i = #state.explosions, 1, -1 do
        local e = state.explosions[i]

        if e.growing then
            e.r = e.r + (state.explosionGrowRate * dt)
            if e.r >= e.maxR then
                e.r = e.maxR
                e.growing = false
            end
        else
            e.r = e.r - (state.explosionShrinkRate * dt)
            if e.r <= 0 then
                table.remove(state.explosions, i)
            end
        end
    end
end

local function handleExplosionHits(state)
    local kills = 0

    for i = #state.incoming, 1, -1 do
        local m = state.incoming[i]
        local hit = false

        for j = 1, #state.explosions do
            local e = state.explosions[j]
            local dx = m.x - e.x
            local dy = m.y - e.y
            if (dx * dx) + (dy * dy) <= (e.r * e.r) then
                hit = true
                break
            end
        end

        if hit then
            table.remove(state.incoming, i)
            state.score = state.score + 2
            kills = kills + 1
        end
    end

    if kills > 0 then
        playTone(1080, 15, 0)
    end
end

local function handleGroundHit(state, x)
    if math.abs(x - state.baseX) <= state.baseHitRadius then
        state.baseHitsRemaining = state.baseHitsRemaining - 1
        playTone(260, 90, 15)
        if state.baseHitsRemaining <= 0 then
            finishGame(state)
        end
        return
    end

    state.score = math.max(0, state.score - 1)
    playTone(420, 70, 10)
end

local function updateIncoming(state, dt)
    for i = #state.incoming, 1, -1 do
        local m = state.incoming[i]
        m.prevX = m.x
        m.prevY = m.y

        m.progress = m.progress + ((m.speed * dt) / m.dist)

        if m.progress >= 1 then
            m.x = m.tx
            m.y = m.ty
            handleGroundHit(state, m.x)
            table.remove(state.incoming, i)
        else
            m.x = m.sx + ((m.tx - m.sx) * m.progress)
            m.y = m.sy + ((m.ty - m.sy) * m.progress)
        end
    end
end

local function checkWaveProgress(state)
    if state.incomingToSpawn > 0 then
        return
    end
    if #state.incoming > 0 then
        return
    end
    if #state.interceptors > 0 then
        return
    end
    if #state.explosions > 0 then
        return
    end

    setupWave(state, false)
end

local function updateGame(state, dt)
    if not state.running then
        return
    end

    updateAimAndFire(state, dt)
    updateSpawner(state, dt)
    updateInterceptors(state, dt)
    updateExplosions(state, dt)
    handleExplosionHits(state)
    updateIncoming(state, dt)

    if state.running then
        checkWaveProgress(state)
    end
end

local function drawBackground(state)
    local bgBitmap = state.activeBgBitmap
    if not bgBitmap then
        state.nextAssetProbeAt = 0
        loadVisualAssets(state)
        selectRandomBackground(state, false)
        bgBitmap = state.activeBgBitmap
    end
    if bgBitmap then
        local bgW, bgH = bitmapSize(bgBitmap)
        local ok = drawBitmapScaled(
            bgBitmap,
            0,
            0,
            (bgW == state.width and bgH == state.height) and nil or state.width,
            (bgW == state.width and bgH == state.height) and nil or state.height
        )
        if ok then
            return
        end
    end

    setColor(8, 16, 34)
    lcd.drawFilledRectangle(0, 0, state.width, state.height)

    setColor(12, 26, 48)
    lcd.drawFilledRectangle(0, 0, state.width, math.floor(state.groundY * 0.5))

    setColor(20, 38, 62)
    lcd.drawFilledRectangle(0, math.floor(state.groundY * 0.5), state.width, state.groundY - math.floor(state.groundY * 0.5))

    setColor(138, 150, 172)
    if state.stars then
        local t = nowSeconds()
        for i = 1, #state.stars do
            local star = state.stars[i]
            if (star.twinkle + t * 0.8) % 1.0 > 0.35 then
                lcd.drawFilledRectangle(star.x, star.y, 1, 1)
            end
        end
    end

    setColor(26, 52, 30)
    lcd.drawFilledRectangle(0, state.groundY, state.width, state.groundHeight)
end

local function drawCities(state)
    if not state.cityPositions then
        return
    end

    local structureBaseY = math.max(0, state.height - STRUCTURE_BOTTOM_MARGIN)

    for i = 1, #state.cityPositions do
        local x = state.cityPositions[i]
        local drewBitmap = false
        local cityBitmap = nil
        if state.cityBitmaps and #state.cityBitmaps > 0 then
            cityBitmap = state.cityBitmaps[((i - 1) % #state.cityBitmaps) + 1]
        end

        if cityBitmap then
            local bw, bh = bitmapSize(cityBitmap)
            if bw and bh then
                local bx = x - math.floor(bw * 0.5)
                local by = math.max(0, structureBaseY - bh)
                drewBitmap = drawBitmapScaled(cityBitmap, bx, by)
            end
        end

        if not drewBitmap then
            local w = math.max(7, math.floor(state.width * 0.018))
            local h = math.max(5, math.floor(state.groundHeight * 0.38))
            local by = math.max(0, structureBaseY - h)
            setColor(84, 118, 92)
            lcd.drawFilledRectangle(x - math.floor(w * 0.5), by, w, h)
            setColor(124, 156, 132)
            lcd.drawRectangle(x - math.floor(w * 0.5), by, w, h, 1)
        end
    end
end

local function drawBase(state)
    local x = state.baseX
    local y = clamp(math.floor(state.baseY or (state.height - 1)), 0, state.height - 1)
    local baseBitmap = nil
    local aimX = tonumber(state.aimX) or x
    if state.baseLeftBitmap or state.baseRightBitmap then
        if aimX < x then
            baseBitmap = state.baseLeftBitmap or state.baseRightBitmap
        else
            baseBitmap = state.baseRightBitmap or state.baseLeftBitmap
        end
    else
        baseBitmap = state.baseBitmap
    end

    if baseBitmap then
        local bw, bh = bitmapSize(baseBitmap)
        if bw and bh then
            local bx = x - math.floor(bw * 0.5)
            local by = math.max(0, y - bh + 1)
            if drawBitmapScaled(baseBitmap, bx, by) then
                return
            end
        end
    end

    local halfW = state.baseHalfW
    local topY = y - state.baseHeight

    if state.baseHitsRemaining <= 1 then
        setColor(214, 74, 70)
    else
        setColor(160, 220, 132)
    end

    if lcd and lcd.drawFilledTriangle then
        lcd.drawFilledTriangle(x - halfW, y, x + halfW, y, x, topY)
    else
        lcd.drawLine(x - halfW, y, x + halfW, y)
        lcd.drawLine(x - halfW, y, x, topY)
        lcd.drawLine(x + halfW, y, x, topY)
    end

    setColor(232, 240, 236)
    if lcd and lcd.drawRectangle then
        lcd.drawRectangle(x - halfW, y - 2, halfW * 2, 3, 1)
    end
end

local function drawAimReticle(state)
    local x = math.floor(state.aimX + 0.5)
    local y = state.aimY
    local drewBitmap = false

    if state.reticleBitmap then
        local bw, bh = bitmapSize(state.reticleBitmap)
        if bw and bh then
            local bx = x - math.floor(bw * 0.5)
            local by = y - math.floor(bh * 0.5)
            if drawBitmapScaled(state.reticleBitmap, bx, by) then
                drewBitmap = true
            end
        end
    end

    if drewBitmap then
        setColor(8, 12, 18)
        if lcd and lcd.drawCircle then
            lcd.drawCircle(x, y, 8)
        end
        setColor(234, 248, 255)
        if lcd and lcd.drawCircle then
            lcd.drawCircle(x, y, 7)
        end
        setColor(255, 255, 255)
        lcd.drawFilledRectangle(x - 1, y - 1, 3, 3)
        return
    end

    -- High-contrast reticle for dark backgrounds.
    setColor(8, 12, 18)
    lcd.drawLine(x - 9, y, x + 9, y)
    lcd.drawLine(x, y - 9, x, y + 9)
    if lcd and lcd.drawRectangle then
        lcd.drawRectangle(x - 4, y - 4, 9, 9, 1)
    end

    setColor(52, 242, 255)
    lcd.drawLine(x - 7, y, x + 7, y)
    lcd.drawLine(x, y - 7, x, y + 7)
    if lcd and lcd.drawCircle then
        lcd.drawCircle(x, y, 5)
    end
    setColor(255, 255, 255)
    lcd.drawFilledRectangle(x - 1, y - 1, 3, 3)
end

local function drawIncoming(state)
    for i = 1, #state.incoming do
        local m = state.incoming[i]
        local x = math.floor(m.x + 0.5)
        local y = math.floor(m.y + 0.5)
        local drewBitmap = false
        local missileBitmap = m.missileBitmap
        if not missileBitmap then
            local drawW, drawH, halfW, halfH, useNative
            missileBitmap, drawW, drawH, halfW, halfH, useNative = resolveMissileVisual(state, m.tx - m.sx, m.ty - m.sy, "missile-incoming")
            m.missileBitmap = missileBitmap
            m.missileDrawW = drawW
            m.missileDrawH = drawH
            m.missileHalfW = halfW
            m.missileHalfH = halfH
            m.missileUseNative = useNative
        end
        if missileBitmap then
            if m.missileUseNative then
                drewBitmap = drawBitmapScaled(missileBitmap, x - (m.missileHalfW or 0), y - (m.missileHalfH or 0))
            elseif m.missileDrawW and m.missileDrawH then
                drewBitmap = drawBitmapScaled(missileBitmap, x - (m.missileHalfW or 0), y - (m.missileHalfH or 0), m.missileDrawW, m.missileDrawH)
            end
        end

        if not drewBitmap then
            setColor(255, 214, 172)
            lcd.drawFilledRectangle(x - 1, y - 1, 3, 3)
        end
    end
end

local function drawInterceptors(state)
    for i = 1, #state.interceptors do
        local p = state.interceptors[i]
        local x = math.floor(p.x + 0.5)
        local y = math.floor(p.y + 0.5)
        local drewBitmap = false
        local missileBitmap = p.missileBitmap
        if not missileBitmap then
            local drawW, drawH, halfW, halfH, useNative
            missileBitmap, drawW, drawH, halfW, halfH, useNative = resolveMissileVisual(state, p.tx - p.sx, p.ty - p.sy, "missile-interceptor")
            p.missileBitmap = missileBitmap
            p.missileDrawW = drawW
            p.missileDrawH = drawH
            p.missileHalfW = halfW
            p.missileHalfH = halfH
            p.missileUseNative = useNative
        end
        if missileBitmap then
            if p.missileUseNative then
                drewBitmap = drawBitmapScaled(missileBitmap, x - (p.missileHalfW or 0), y - (p.missileHalfH or 0))
            elseif p.missileDrawW and p.missileDrawH then
                drewBitmap = drawBitmapScaled(missileBitmap, x - (p.missileHalfW or 0), y - (p.missileHalfH or 0), p.missileDrawW, p.missileDrawH)
            end
        end
        if not drewBitmap then
            setColor(212, 244, 255)
            lcd.drawFilledRectangle(x - 1, y - 1, 3, 3)
        end
    end
end

local function drawExplosions(state)
    for i = 1, #state.explosions do
        local e = state.explosions[i]
        local cx = math.floor(e.x + 0.5)
        local cy = math.floor(e.y + 0.5)
        local r = math.max(1, math.floor(e.r + 0.5))
        local drewBitmap = false

        local explosionBitmap = state.explosionBitmap
        if state.explosionBitmap2 and r >= math.floor((state.explosionMaxR or 24) * 0.56) then
            explosionBitmap = state.explosionBitmap2
        end

        if explosionBitmap then
            local size = math.max(4, math.floor((r * 2 * EXPLOSION_DRAW_SCALE) + 0.5))
            local x = cx - math.floor(size * 0.5)
            local y = cy - math.floor(size * 0.5)
            drewBitmap = drawBitmapScaled(explosionBitmap, x, y, size, size)
        end

        if not drewBitmap then
            setColor(252, 220, 120)
            if lcd and lcd.drawCircle then
                lcd.drawCircle(cx, cy, r)
                if r > 4 then
                    setColor(255, 246, 198)
                    lcd.drawCircle(cx, cy, math.max(1, r - 3))
                end
            else
                lcd.drawRectangle(cx - r, cy - r, r * 2, r * 2, 1)
            end
        end
    end
end

local function drawHud(state)
    setFont(FONT_S_BOLD or FONT_STD)
    setColor(236, 244, 252)
    lcd.drawText(4, 2, string.format("Score %d", state.score))

    setFont(FONT_XXS or FONT_STD)
    setColor(178, 196, 214)
    lcd.drawText(4, 20, string.format("Wave %d", state.wave))
    lcd.drawText(84, 20, string.format("Ammo %d", state.ammo))
    lcd.drawText(164, 20, string.format("Base %d", state.baseHitsRemaining))

    if state.bestScore ~= nil then
        lcd.drawText(236, 20, string.format("Best %d", state.bestScore))
    end

    setColor(142, 168, 194)
    lcd.drawText(state.width - 74, 2, string.format("GFX %d/%d", state.assetsLoaded or 0, state.assetsTotal or #VISUAL_ASSETS))

    lcd.drawText(4, state.height - 16, string.format("Diff %s  Aim Low", difficultyLabel(state.config.difficulty)))
end

local function drawOverlay(state)
    local boxW = math.floor(state.width * 0.74)
    local boxH = math.floor(state.height * 0.56)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(4, 12, 20)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(122, 152, 186)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(245, 252, 255)
    drawCenteredText(boxX, boxY + 8, boxW, 24, "MissileCmd")

    setFont(FONT_XXS or FONT_STD)
    setColor(188, 210, 232)

    if state.gameOver then
        drawCenteredText(boxX, boxY + 34, boxW, 18, "Base destroyed")
        drawCenteredText(boxX, boxY + 50, boxW, 18, string.format("Result: %d", state.lastResult or 0))
        if state.isNewBest then
            drawCenteredText(boxX, boxY + 66, boxW, 18, "New best score!")
        elseif state.bestScore ~= nil then
            drawCenteredText(boxX, boxY + 66, boxW, 18, string.format("Best: %d", state.bestScore))
        end
    else
        drawCenteredText(boxX, boxY + 38, boxW, 18, "Defend a single launcher base")
        drawCenteredText(boxX, boxY + 56, boxW, 18, "Ail+Ele aim, fire: Rud pulse or short Page")
    end

    drawCenteredText(boxX, boxY + 88, boxW, 18, "Press Enter to start")
    drawCenteredText(boxX, boxY + 106, boxW, 18, "Long Page for settings")
    drawCenteredText(boxX, boxY + 124, boxW, 18, "Exit returns to arcade menu")
    drawCenteredText(boxX, boxY + 142, boxW, 16, string.format("GFX loaded: %d/%d", state.assetsLoaded or 0, state.assetsTotal or #VISUAL_ASSETS))
end

local function render(state)
    drawBackground(state)
    drawCities(state)
    drawIncoming(state)
    drawInterceptors(state)
    drawExplosions(state)
    drawBase(state)
    drawAimReticle(state)

    drawHud(state)

    if not state.running then
        drawOverlay(state)
    end
end

local function createState()
    local config, bestScore = loadStateConfig()

    local state = {
        width = 480,
        height = 272,

        config = config,
        bestScore = bestScore,
        lastResult = nil,
        isNewBest = false,

        running = false,
        gameOver = false,

        wave = 1,
        score = 0,
        ammo = 0,
        baseHitsRemaining = normalizeBaseArmor(config.baseArmor),

        incomingToSpawn = 0,
        spawnInterval = 0.9,
        spawnTimer = 0,

        missileSpeed = 70,
        interceptorSpeed = 280,
        explosionMaxR = 24,
        explosionGrowRate = 96,
        explosionShrinkRate = 80,

        incoming = {},
        interceptors = {},
        explosions = {},

        baseX = 240,
        baseY = 220,
        baseHalfW = 11,
        baseHeight = 16,
        baseHitRadius = 16,

        aimX = 240,
        aimY = 96,
        aimMinY = 12,
        aimMaxY = 180,
        filteredAimX = nil,
        filteredAimY = nil,

        fireArmed = false,
        fireCooldown = 0,

        cityPositions = nil,
        stars = nil,
        activeBgBitmap = nil,
        activeBgSlot = nil,
        buildingBitmap1 = nil,
        buildingBitmap2 = nil,
        buildingBitmap3 = nil,
        buildingBitmap4 = nil,
        buildingBitmap5 = nil,
        buildingBitmap6 = nil,
        buildingBitmap7 = nil,
        baseLeftBitmap = nil,
        baseRightBitmap = nil,
        cityBitmaps = nil,
        missileBitmap = nil,
        explosionBitmap = nil,
        explosionBitmap2 = nil,
        baseBitmap = nil,
        reticleBitmap = nil,
        missilePrebaked = nil,
        missilePrebakedFallback = nil,
        missilePrebakedLoaded = false,
        rotatedBitmapCache = nil,
        assetsLoaded = 0,
        assetsTotal = #VISUAL_ASSETS,
        assetsMissing = nil,
        nextAssetProbeAt = 0,

        aimXSource = resolveAnalogSource(AIM_X_SOURCE_MEMBER),
        aimYSource = resolveAnalogSource(AIM_Y_SOURCE_MEMBER),
        fireSource = resolveAnalogSource(FIRE_SOURCE_MEMBER),
        lastRawInputByAxis = {},

        frameScale = 1,
        lastFrameTime = 0,
        nextInvalidateAt = 0,
        lastFocusKick = 0,

        settingsFormOpen = false,
        pendingFormClear = false,
        suppressExitUntil = 0,
        suppressEnterUntil = 0,

        profile = DIFFICULTY_PROFILES[DIFFICULTY_NORMAL]
    }

    applyConfigSideEffects(state)
    loadVisualAssets(state)
    selectRandomBackground(state, false)
    refreshGeometry(state)
    refreshCityPositions(state)
    rebuildSkyStars(state)

    return state
end

function game.create()
    math.randomseed(os.time())
    return createState()
end

function game.wakeup(state)
    if not state then return end

    refreshGeometry(state)

    if not state.cityPositions then
        refreshCityPositions(state)
    end
    if not state.stars then
        rebuildSkyStars(state)
    end
    loadVisualAssets(state)
    if not state.activeBgBitmap then
        selectRandomBackground(state, false)
    end

    if not state.aimXSource then
        state.aimXSource = resolveAnalogSource(AIM_X_SOURCE_MEMBER)
    end
    if not state.aimYSource then
        state.aimYSource = resolveAnalogSource(AIM_Y_SOURCE_MEMBER)
    end
    if not state.fireSource then
        state.fireSource = resolveAnalogSource(FIRE_SOURCE_MEMBER)
    end

    if state.settingsFormOpen then
        return
    end

    keepScreenAwake(state)
    requestTimedInvalidate(state)
end

function game.event(state, category, value)
    if not state then return false end

    if state.pendingFormClear then
        if category == EVT_CLOSE or isKeyCategory(category) then
            flushPendingFormClear(state, true)
        end
    end

    local now = nowSeconds()
    if state.suppressExitUntil and now < state.suppressExitUntil then
        if category == EVT_CLOSE then
            return true
        end
        if isExitKeyEvent(category, value) then
            return true
        end
    elseif state.suppressExitUntil and state.suppressExitUntil ~= 0 then
        state.suppressExitUntil = 0
    end

    if state.suppressEnterUntil and now < state.suppressEnterUntil then
        if isKeyCategory(category) and keyMatches(value, KEY_ENTER_FIRST, KEY_ENTER_BREAK, KEY_ENTER_LONG) then
            return true
        end
        if isConfigButtonEvent(category, value) then
            return true
        end
    elseif state.suppressEnterUntil and state.suppressEnterUntil ~= 0 then
        state.suppressEnterUntil = 0
    end

    if state.settingsFormOpen then
        if category == EVT_CLOSE then
            closeSettingsForm(state)
            return true
        end
        if isExitKeyEvent(category, value) then
            closeSettingsForm(state)
            return true
        end
        return false
    end

    if category == EVT_CLOSE then
        if state.running then
            stopRound(state, false)
            suppressExitEvents(state)
            forceInvalidate(state)
            return true
        end
        return false
    end

    if not isKeyCategory(category) then
        return false
    end

    if not state.running then
        if isSettingsOpenEvent(category, value) then
            if openSettingsForm(state) then
                return true
            end
        end

        if keyMatches(value, KEY_ENTER_FIRST, KEY_ENTER_BREAK, KEY_ENTER_LONG) then
            startGame(state)
            return true
        end

        if isExitKeyEvent(category, value) then
            return false
        end

        return true
    end

    if isSettingsOpenEvent(category, value) then
        return true
    end

    if isFireButtonEvent(category, value) then
        tryFire(state)
        state.fireArmed = false
        return true
    end

    if isExitKeyEvent(category, value) then
        stopRound(state, false)
        suppressExitEvents(state)
        forceInvalidate(state)
        return true
    end

    return false
end

function game.paint(state)
    if not state then return end

    if state.settingsFormOpen then
        return
    end

    refreshGeometry(state)
    keepScreenAwake(state)
    updateFrameScale(state)

    local dt = FRAME_TARGET_DT * state.frameScale
    if state.running then
        updateGame(state, dt)
    end

    render(state)
    requestTimedInvalidate(state)
end

function game.close(state)
    if type(state) ~= "table" then
        return
    end

    state.running = false
    state.settingsFormOpen = false
    state.pendingFormClear = true
    state.suppressExitUntil = 0
    state.suppressEnterUntil = 0
    flushPendingFormClear(state)
    releaseAssets(state)
    if collectgarbage then
        pcall(collectgarbage, "collect")
        pcall(collectgarbage, "collect")
    end
end

return game
