local game = {}

local DEFAULT_SETTINGS = {
    staticBackground = false,
    targetSideMotion = true,
    easyMode = false
}

local MENU_ITEMS = {
    {label = "Static background", key = "staticBackground"},
    {label = "Target side motion", key = "targetSideMotion"},
    {label = "Easy mode", key = "easyMode"}
}

local BACKGROUND_CHOICES = {
    {label = "Background 1", value = 1, file = "gfx/back1.png"},
    {label = "Background 2", value = 2, file = "gfx/back2.png"},
    {label = "Background 3", value = 3, file = "gfx/back3.png"},
    {label = "Background 4", value = 4, file = "gfx/back4.png"}
}

local TARGET_VARIANT_FILES = {
    {"gfx/target.png"},
    {"gfx/target2.png"},
    {"gfx/target3.png"},
    {"gfx/target4.png"}
}

local SOURCE_X_MEMBER = 3
local SOURCE_Y_MEMBER = 1

local CONFIG_FILE = "gulaxian.cfg"
local CONFIG_VERSION = 1
local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128

local INPUT_DEADZONE = 0.03
local INPUT_FILTER_ALPHA = 0.18
local INPUT_FILTER_ALPHA_FAST = 0.42
local SHIP_STEP_BASE = 18.0
local SHIP_STEP_EXTRA = 24.0
local STICK_SOURCE_IS_PERCENT = false

local TARGET_SPEED_NORMAL = 3.2
local TARGET_SPEED_EASY = 1.7
local PROJECTILE_SPEED = -8
local BACKGROUND_SPEED = 1.6
local FRAME_TARGET_DT = 1 / 60
local FRAME_SCALE_MIN = 0.65
local FRAME_SCALE_MAX = 1.75
local EXPLOSION_LIFE_FRAMES = 24

local function boolValue(v, default)
    if v == nil then return default end
    if v == true or v == 1 or v == "1" or v == "true" then return true end
    if v == false or v == 0 or v == "0" or v == "false" then return false end
    return default
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
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
    if not (src and src.value) then return 0 end
    local ok, value = pcall(src.value, src)
    if not ok then return 0 end
    if type(value) == "number" then return value end
    return tonumber(value) or 0
end

local function normalizeStick(v)
    if STICK_SOURCE_IS_PERCENT then
        v = v * 10.24
    end
    return clamp(v, -1024, 1024)
end

local function applyInputResponse(v)
    local absV = math.abs(v)
    local dz = INPUT_DEADZONE * 1024
    if absV <= dz then return 0 end

    local sign = (v < 0) and -1 or 1
    local norm = (absV - dz) / (1024 - dz)
    return sign * clamp(norm * 1024, 0, 1024)
end

local function mapInputToActionAreaPosition(value, newRangeStart, newRangeEnd)
    return newRangeStart + (newRangeEnd - newRangeStart) * ((value + 1024) / 2048)
end

local function approach(current, target, maxStep)
    local delta = target - current
    if delta > maxStep then
        return current + maxStep
    end
    if delta < -maxStep then
        return current - maxStep
    end
    return target
end

local function updateFrameScale(state)
    local now = (os and os.clock and os.clock()) or 0
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
        -- Ignore long frame gaps (menu pause, dialog open, task switch).
        state.frameScale = 1
        return
    end

    state.frameScale = clamp(dt / FRAME_TARGET_DT, FRAME_SCALE_MIN, FRAME_SCALE_MAX)
end

local function playTone(freq, duration, pause)
    pcall(system.playTone, freq, duration or 50, pause or 0)
end

local function playHaptic(duration)
    pcall(system.playHaptic, duration or 80)
end

local function keepScreenAwake(state)
    if not state then
        return
    end

    local now = (os and os.clock and os.clock()) or 0
    if state.lastFocusReset and (now - state.lastFocusReset) < 1.0 then
        return
    end
    state.lastFocusReset = now

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

    local dir = source:match("^(.*[/\\])")
    return dir
end

local SCRIPT_DIR = scriptDir() or ""

local function assetPathCandidates(rel)
    local paths = {}
    if type(rel) ~= "string" or rel == "" then
        return paths
    end

    if SCRIPT_DIR ~= "" then
        paths[#paths + 1] = SCRIPT_DIR .. rel
    end

    paths[#paths + 1] = "games/gulaxian/" .. rel
    paths[#paths + 1] = "scripts/ethos-arcade/games/gulaxian/" .. rel
    paths[#paths + 1] = "/scripts/ethos-arcade/games/gulaxian/" .. rel
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/gulaxian/" .. rel
    paths[#paths + 1] = "scripts/gulaxian/" .. rel
    paths[#paths + 1] = "/scripts/gulaxian/" .. rel
    paths[#paths + 1] = "SD:/scripts/gulaxian/" .. rel
    paths[#paths + 1] = rel

    return paths
end

local function loadBitmapAsset(rel)
    for _, path in ipairs(assetPathCandidates(rel)) do
        local ok, bmp = pcall(lcd.loadBitmap, path)
        if ok and bmp then
            return bmp
        end
    end
    return nil
end

local function loadBitmapFromPaths(paths)
    for i = 1, #paths do
        local ok, bmp = pcall(lcd.loadBitmap, paths[i])
        if ok and bmp then
            return bmp
        end
    end
    return nil
end

local function missileCmdExplosionPaths(filename)
    local paths = {}
    if SCRIPT_DIR ~= "" then
        paths[#paths + 1] = SCRIPT_DIR .. "../missilecmd/gfx/" .. filename
    end
    paths[#paths + 1] = "games/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "scripts/ethos-arcade/games/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "/scripts/ethos-arcade/games/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "scripts/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "/scripts/missilecmd/gfx/" .. filename
    paths[#paths + 1] = "SD:/scripts/missilecmd/gfx/" .. filename
    return paths
end

local function configPathCandidates()
    local paths = {}
    local dir = SCRIPT_DIR
    if dir ~= "" then
        paths[#paths + 1] = dir .. CONFIG_FILE
    end
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/gulaxian/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/gulaxian/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/ethos-arcade/games/gulaxian/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/gulaxian/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/gulaxian/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/gulaxian/" .. CONFIG_FILE
    paths[#paths + 1] = CONFIG_FILE
    return paths
end

local function readConfigFile()
    local values = {}
    if not (io and io.open) then return values end

    local f
    for _, path in ipairs(configPathCandidates()) do
        f = io.open(path, "r")
        if f then break end
    end
    if not f then return values end

    while true do
        local okRead, line = pcall(f.read, f, "*l")
        if not okRead or not line then break end
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key and value and value ~= "" then
            values[key] = value
        end
    end

    pcall(f.close, f)
    return values
end

local function loadStateConfig()
    local fileValues = readConfigFile()
    local settings = {}

    for key, default in pairs(DEFAULT_SETTINGS) do
        settings[key] = boolValue(fileValues[key], default)
    end

    local best = tonumber(fileValues.bestResult)
    if best then
        best = math.floor(best)
    else
        best = nil
    end

    return settings, best
end

local function saveStateConfig(state)
    if not (io and io.open) then return false end

    local f
    for _, path in ipairs(configPathCandidates()) do
        f = io.open(path, "w")
        if f then break end
    end
    if not f then return false end

    f:write("version=", CONFIG_VERSION, "\n")
    if state.bestResult ~= nil then
        f:write("bestResult=", math.floor(state.bestResult), "\n")
    end

    for _, item in ipairs(MENU_ITEMS) do
        f:write(item.key, "=", state.settings[item.key] and "1" or "0", "\n")
    end

    f:close()
    return true
end

local function activeTextColor(state)
    if state.scale <= 1 then
        return lcd.RGB(240, 240, 240)
    end
    return lcd.darkMode() and lcd.RGB(250, 250, 250) or lcd.RGB(30, 30, 30)
end

local function activeAccentColor(state)
    if state.scale <= 1 then
        return lcd.RGB(240, 240, 240)
    end
    return lcd.RGB(255, 180, 80)
end

local function activeDangerColor(state)
    if state.scale <= 1 then
        return lcd.RGB(240, 240, 240)
    end
    return lcd.RGB(255, 90, 90)
end

local function refreshSelectedBackground(state)
    if not state.backgroundBitmaps then
        state.backgroundDisabled = false
        state.backgroundBitmap = nil
        return
    end

    local available = {}
    for _, bg in ipairs(BACKGROUND_CHOICES) do
        if bg.value > 0 and state.backgroundBitmaps[bg.value] then
            available[#available + 1] = bg.value
        end
    end

    if #available > 0 then
        local selectedIndex = available[math.random(1, #available)]
        if #available > 1 and state.backgroundLastValue then
            local guard = 0
            while selectedIndex == state.backgroundLastValue and guard < 6 do
                selectedIndex = available[math.random(1, #available)]
                guard = guard + 1
            end
        end
        state.backgroundDisabled = false
        state.backgroundBitmap = state.backgroundBitmaps[selectedIndex]
        state.backgroundLastValue = selectedIndex
        return
    end

    state.backgroundDisabled = false
    state.backgroundBitmap = nil
end

local function drawBackgroundBitmap(state, y)
    if not state.backgroundBitmap then
        return
    end

    local bmpW = (state.backgroundBitmap.width and state.backgroundBitmap:width()) or 0
    local bmpH = (state.backgroundBitmap.height and state.backgroundBitmap:height()) or 0

    if bmpW == state.width and bmpH == state.height then
        lcd.drawBitmap(0, y, state.backgroundBitmap)
        return
    end

    lcd.drawBitmap(0, y, state.backgroundBitmap, state.width, state.height)
end

local function initBitmaps(state)
    state.shipBitmap = loadBitmapAsset("gfx/ship.png")

    state.backgroundBitmaps = {}
    for _, bg in ipairs(BACKGROUND_CHOICES) do
        if bg.file then
            state.backgroundBitmaps[bg.value] = loadBitmapAsset(bg.file)
        else
            state.backgroundBitmaps[bg.value] = nil
        end
    end

    state.targetBitmap = nil
    state.targetBitmap2 = nil
    state.targetBitmaps = {}

    for _, fileSet in ipairs(TARGET_VARIANT_FILES) do
        local bitmap = nil
        for i = 1, #fileSet do
            bitmap = loadBitmapAsset(fileSet[i])
            if bitmap then
                break
            end
        end
        if bitmap then
            state.targetBitmaps[#state.targetBitmaps + 1] = bitmap
            if not state.targetBitmap then
                state.targetBitmap = bitmap
            elseif not state.targetBitmap2 then
                state.targetBitmap2 = bitmap
            end
        end
    end

    state.explosionBitmap = loadBitmapFromPaths(missileCmdExplosionPaths("explosion.png"))
    state.explosionBitmap2 = loadBitmapFromPaths(missileCmdExplosionPaths("explosion2.png"))

    refreshSelectedBackground(state)
end

local function releaseAssets(state)
    if not state then
        return
    end

    state.shipBitmap = nil
    state.backgroundBitmaps = nil
    state.backgroundBitmap = nil
    state.targetBitmaps = nil
    state.targetBitmap = nil
    state.targetBitmap2 = nil
    state.explosionBitmap = nil
    state.explosionBitmap2 = nil

    state.projectiles = nil
    state.targets = nil
    state.explosions = nil
    state.backgrounds = nil
    state.lowBackgrounds = nil
end

local function initWithScale(state, scale)
    state.scale = scale

    state.shipWidth = 10 * scale
    state.shipHeight = 7 * scale
    state.projectileLength = scale * 4
    state.projectileWidth = scale * 2
    state.targetSideMotionAmplitude = math.max(1, math.floor(scale * 0.5 + 0.5))
    state.targetWidth = 4 * scale
    state.targetHeight = 4 * scale

    if state.shipBitmap and state.targetBitmap then
        state.shipWidth = math.floor(state.shipBitmap:width() * scale + 0.5)
        state.shipHeight = math.floor(state.shipBitmap:height() * scale + 0.5)
        state.targetWidth = math.floor(state.targetBitmap:width() * scale + 0.5)
        state.targetHeight = math.floor(state.targetBitmap:height() * scale + 0.5)
        state.shipCollisionMargin = math.floor(4 * scale)
    else
        state.shipCollisionMargin = 0
    end

    state.shipHalfWidth = state.shipWidth / 2
    state.targetHalfWidth = state.targetWidth / 2
    state.targetHalfHeight = state.targetHeight / 2

    state.actionAreaWidthStart = 0
    state.actionAreaHeightStart = 0
    state.actionAreaWidthEnd = state.width - state.shipWidth
    state.actionAreaHeightEnd = state.height - state.shipHeight

    state.projectileVelocity = PROJECTILE_SPEED * scale
    state.targetVelocityNormal = TARGET_SPEED_NORMAL * scale
    state.targetVelocityEasy = TARGET_SPEED_EASY * scale
    state.backgroundSpeed = BACKGROUND_SPEED
end

local function centerShip(state)
    state.shipPosition.x = (state.actionAreaWidthStart + state.actionAreaWidthEnd) * 0.5
    state.shipPosition.y = state.actionAreaHeightEnd
end

local function assignTargetVariant(state, target)
    if not (target and state and state.targetBitmaps and #state.targetBitmaps > 0) then
        target.bitmap = nil
        return
    end
    target.bitmap = state.targetBitmaps[math.random(1, #state.targetBitmaps)]
end

local function resetEntities(state)
    state.projectiles = {}
    state.targets = {}
    state.explosions = {}
    state.backgrounds = {}
    state.lowBackgrounds = {}

    for i = 0, state.projectileCount do
        state.projectiles[i] = {
            x = state.width / 2,
            y = -state.height,
            velocity = state.projectileVelocity,
            delay = i * -4
        }
    end

    for i = 0, state.targetCount do
        local direction = (math.random(0, 1) == 0) and -1 or 1
        state.targets[i] = {
            x = math.random(0, math.max(0, state.width - state.targetWidth)),
            y = math.random(0, math.max(0, state.height)),
            sideVelocity = state.scale * direction,
            sidePhase = math.random() * (math.pi * 2),
            velocity = state.targetVelocityNormal,
            dead = true
        }
        assignTargetVariant(state, state.targets[i])
    end

    for i = 0, state.backgroundCount do
        state.lowBackgrounds[i] = {
            x = math.random(0, state.width),
            y = math.random(0, state.height)
        }
    end

    state.backgrounds[0] = {y = -state.height}
    state.backgrounds[1] = {y = 0}
end

local function logWindowResolution(width, height, reason)
    local tag = reason or "size"
    pcall(print, string.format("[GaLuaxian] %s: %dx%d", tag, width, height))
end

local function createState()
    local width, height = lcd.getWindowSize()
    local loadedSettings, loadedBestResult = loadStateConfig()
    logWindowResolution(width, height, "init")

    local state = {
        width = width,
        height = height,

        projectileCount = 3,
        targetCount = 4,
        backgroundCount = 20,
        backgroundSpeed = BACKGROUND_SPEED,

        settings = loadedSettings,
        backgroundDisabled = false,
        shipPosition = {x = 0, y = 0},

        gameOver = true,
        gameStarted = false,
        hits = 0,
        bestResult = loadedBestResult,
        explosions = {},

        menuPage = false,
        menuPosition = 0,
        menuPadding = 2,
        menuOpened = false,
        settingsFormOpen = false,

        fpsCounter = 0,
        ignoreEnterBreak = false,

        frameScale = 1,
        lastFrameTime = 0,
        filteredInputX = nil,
        filteredInputY = nil,
        lastFocusReset = 0,
        suppressExitUntil = 0,
        suppressEnterUntil = 0,
        startOnNextEnterFirst = false,
        pendingFormClear = false,

        shipSourceX = resolveAnalogSource(SOURCE_X_MEMBER),
        shipSourceY = resolveAnalogSource(SOURCE_Y_MEMBER)
    }

    initBitmaps(state)

    local scale = (width >= 480) and 2 or 1
    initWithScale(state, scale)
    centerShip(state)
    resetEntities(state)

    return state
end

local function refreshGeometryIfNeeded(state)
    local width, height = lcd.getWindowSize()
    if width == state.width and height == state.height then return end

    state.width = width
    state.height = height
    logWindowResolution(width, height, "resize")

    local scale = (width >= 480) and 2 or 1
    initWithScale(state, scale)
    centerShip(state)
    resetEntities(state)
end

local function detectOverlap(xl1, yl1, xl2, yl2, xr1, yr1, xr2, yr2)
    if xl1 > xr2 or xl2 > xr1 then
        return false
    end

    if yr1 > yl2 or yr2 > yl1 then
        return false
    end
    return true
end

local function clearScreen(state)
    if lcd.darkMode() then
        lcd.color(lcd.RGB(10, 10, 10))
    else
        lcd.color(lcd.RGB(225, 230, 238))
    end
    lcd.drawFilledRectangle(0, 0, state.width, state.height)
end

local function drawBackground(state)
    local drawH = state.height

    if state.backgroundDisabled then
        return
    end

    if state.settings.staticBackground then
        if state.backgroundBitmap then
            drawBackgroundBitmap(state, 0)
            return
        end

        lcd.color(lcd.RGB(190, 190, 190))
        for i = 0, state.backgroundCount do
            local star = state.lowBackgrounds[i]
            lcd.drawPoint(math.floor(star.x), math.floor(star.y))
        end
        return
    end

    if not state.backgroundBitmap then
        lcd.color(lcd.RGB(190, 190, 190))
        for i = 0, state.backgroundCount do
            local star = state.lowBackgrounds[i]
            star.y = star.y + (state.backgroundSpeed * state.frameScale)
            if star.y >= drawH then
                star.y = star.y - drawH
            end
            lcd.drawPoint(math.floor(star.x), math.floor(star.y))
        end
        return
    end

    local bmpW = (state.backgroundBitmap.width and state.backgroundBitmap:width()) or 0
    local bmpH = (state.backgroundBitmap.height and state.backgroundBitmap:height()) or 0
    local needsScale = (bmpW ~= state.width or bmpH ~= state.height)
    if needsScale then
        drawBackgroundBitmap(state, 0)
        return
    end

    for i = 0, 1 do
        local bg = state.backgrounds[i]
        bg.y = bg.y + (state.backgroundSpeed * state.frameScale)
        if bg.y >= drawH then
            bg.y = bg.y - (drawH * 2)
        end
        drawBackgroundBitmap(state, math.floor(bg.y + 0.5))
    end
end

local function drawProjectile(state, projectile, x, y)
    if projectile.delay < 0 then
        projectile.delay = projectile.delay + state.frameScale
        return
    end

    if projectile.y <= (-state.projectileLength - 2) or projectile.y > state.height then
        projectile.y = y
        projectile.x = x
    else
        projectile.y = projectile.y + (projectile.velocity * state.frameScale)
    end

    lcd.color(activeTextColor(state))
    lcd.drawLine(math.floor(projectile.x + 0.5), math.floor(projectile.y + 0.5), math.floor(projectile.x + state.projectileWidth / 2 + 0.5), math.floor(projectile.y + state.projectileLength + 0.5))
    lcd.color(activeAccentColor(state))
    lcd.drawLine(math.floor(projectile.x + state.projectileWidth / 2 + 0.5), math.floor(projectile.y + state.projectileLength + 0.5), math.floor(projectile.x - state.projectileWidth / 2 + 0.5), math.floor(projectile.y + state.projectileLength + 0.5))
    lcd.color(activeTextColor(state))
    lcd.drawLine(math.floor(projectile.x - state.projectileWidth / 2 + 0.5), math.floor(projectile.y + state.projectileLength + 0.5), math.floor(projectile.x + 0.5), math.floor(projectile.y + 0.5))
    lcd.color(activeDangerColor(state))
    lcd.drawLine(math.floor(projectile.x + 0.5), math.floor(projectile.y + 0.5), math.floor(projectile.x + 0.5), math.floor(projectile.y + state.projectileLength + 0.5))
end

local function drawShip(state, x, y)
    if state.shipBitmap then
        lcd.drawBitmap(x, y, state.shipBitmap, state.shipWidth, state.shipHeight)
        return
    end

    lcd.color(activeTextColor(state))
    lcd.drawLine(x + state.shipHalfWidth, y, x + state.shipWidth, y + state.shipHeight)
    lcd.drawLine(x + state.shipWidth, y + state.shipHeight, x + state.shipHalfWidth, y + state.shipHeight * 0.75)
    lcd.drawLine(x + state.shipHalfWidth, y + state.shipHeight * 0.75, x, y + state.shipHeight)
    lcd.drawLine(x, y + state.shipHeight, x + state.shipHalfWidth, y)
end

local function drawTarget(state, x, y, target)
    local drawX = math.floor(x + 0.5)
    local drawY = math.floor(y + 0.5)
    local bitmap = target and target.bitmap or state.targetBitmap

    if bitmap then
        lcd.drawBitmap(drawX, drawY, bitmap, state.targetWidth, state.targetHeight)
        return
    end

    lcd.color(activeTextColor(state))
    lcd.drawLine(drawX, drawY, drawX + state.targetHalfWidth, drawY + state.targetHalfWidth)
    lcd.drawLine(drawX + state.targetHalfWidth, drawY + state.targetHalfWidth, drawX + state.targetWidth, drawY)
    lcd.drawLine(drawX + state.targetWidth, drawY, drawX + state.targetHalfWidth, drawY + state.targetHeight)
    lcd.drawLine(drawX + state.targetHalfWidth, drawY + state.targetHeight, drawX, drawY)
end

local function spawnExplosion(state, x, y)
    if not state.explosions then
        state.explosions = {}
    end

    state.explosions[#state.explosions + 1] = {
        x = x,
        y = y,
        life = EXPLOSION_LIFE_FRAMES,
        maxLife = EXPLOSION_LIFE_FRAMES
    }
end

local function drawTargets(state)
    for i = 0, state.targetCount do
        local target = state.targets[i]
        target.y = target.y + (target.velocity * state.frameScale)

        if state.settings.targetSideMotion then
            target.sidePhase = (target.sidePhase or 0) + (0.11 * state.frameScale)
            local sideJitter = math.sin(target.sidePhase) * state.targetSideMotionAmplitude * 0.35
            target.x = target.x + ((target.sideVelocity + sideJitter) * state.frameScale)

            if target.x <= state.shipHalfWidth or target.x + state.targetWidth > state.width - state.shipHalfWidth then
                target.sideVelocity = target.sideVelocity * -1
            end
        end
        local maxTargetX = math.max(state.shipHalfWidth, state.width - state.targetWidth - state.shipHalfWidth)
        target.x = clamp(target.x, state.shipHalfWidth, maxTargetX)

        for j = 0, state.projectileCount do
            local projectile = state.projectiles[j]
            if not target.dead
                and projectile.x >= target.x - 10
                and projectile.x + state.projectileWidth <= target.x + state.targetWidth + 10
                and projectile.y >= target.y - (state.projectileLength + projectile.velocity * -1)
                and projectile.y <= target.y + state.targetHeight + projectile.velocity * -1 then

                target.dead = true
                target.sideVelocity = target.sideVelocity * -1
                playTone(450, 50, 0)
                spawnExplosion(state, target.x + (state.targetWidth * 0.5), target.y + (state.targetHeight * 0.5))
                state.hits = state.hits + 1
            end
        end

        if not target.dead and detectOverlap(
            target.x + state.shipCollisionMargin,
            target.y,
            state.shipPosition.x,
            state.shipPosition.y + state.shipCollisionMargin,
            target.x + state.targetWidth - state.shipCollisionMargin,
            target.y - state.targetHeight,
            state.shipPosition.x + state.shipWidth - state.shipCollisionMargin,
            state.shipPosition.y + state.shipCollisionMargin - state.shipHeight
        ) then
            state.gameOver = true
            playHaptic(50)
        end

        if target.y >= state.height then
            local offset = state.shipHalfWidth
            target.y = -state.targetHeight
            local minX = math.floor(offset)
            local maxX = math.floor(math.max(offset, state.width - state.targetWidth - offset))
            target.x = math.random(minX, maxX)
            target.sidePhase = math.random() * (math.pi * 2)
            assignTargetVariant(state, target)
            if not target.dead then
                state.hits = state.hits - 1
                playTone(150, 50, 0)
            end
            target.dead = false
        end

        if not target.dead then
            drawTarget(state, target.x, target.y, target)
        end
    end
end

local function drawExplosions(state)
    if not state.explosions then
        return
    end

    for i = #state.explosions, 1, -1 do
        local e = state.explosions[i]
        local maxLife = math.max(1, e.maxLife or EXPLOSION_LIFE_FRAMES)
        e.life = (e.life or 0) - state.frameScale

        if e.life <= 0 then
            table.remove(state.explosions, i)
        else
            local t = 1 - (e.life / maxLife)
            local size = math.max(6, math.floor((state.targetWidth * (0.8 + (t * 2.2))) + 0.5))
            local drawX = math.floor((e.x or 0) - (size * 0.5) + 0.5)
            local drawY = math.floor((e.y or 0) - (size * 0.5) + 0.5)
            local bmp = (t > 0.55 and state.explosionBitmap2) or state.explosionBitmap
            local drawn = false

            if bmp then
                local ok = pcall(lcd.drawBitmap, drawX, drawY, bmp, size, size)
                drawn = ok and true or false
            end

            if not drawn then
                lcd.color(activeDangerColor(state))
                lcd.drawRectangle(drawX, drawY, size, size, 1)
            end
        end
    end
end

local function renderHome(state)
    local title = "GaLuaxian"

    if state.scale == 1 then
        lcd.font(FONT_S_BOLD)
        lcd.color(activeTextColor(state))

        if state.gameStarted then
            lcd.drawText(8, math.floor(state.height * 0.2), "Game Over")
            lcd.drawText(8, math.floor(state.height * 0.4), string.format("Points: %d", state.hits))
        else
            lcd.drawText(8, 4, title)
            lcd.font(FONT_XS)
            lcd.drawText(8, math.floor(state.height * 0.25), "SHOOT 'EM UP!")
            if state.bestResult then
                lcd.drawText(8, math.floor(state.height * 0.25) + 14, string.format("Best: %d", state.bestResult))
            end
        end

        lcd.font(FONT_XS_BOLD)
        lcd.drawText(6, state.height - 22, "Press Enter to start")
        lcd.font(FONT_XXS)
        lcd.drawText(6, state.height - 10, "Long Page for settings")
        return
    end

    local boxW = 230
    local boxH = 84
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.4)

    lcd.color(activeAccentColor(state))
    lcd.drawRectangle(boxX - 2, boxY - 2, boxW + 4, boxH + 4, 1)
    lcd.color(activeTextColor(state))
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 1)

    lcd.font(FONT_L_BOLD)
    lcd.color(activeTextColor(state))
    lcd.drawText(boxX + 16, boxY + 8, title)

    lcd.font(FONT_S)
    lcd.drawText(boxX + 16, boxY + 38, "SHOOT 'EM UP!")

    if state.gameStarted then
        lcd.font(FONT_M_BOLD)
        lcd.color(activeDangerColor(state))
        lcd.drawText(boxX + 16, boxY - 30, "Game Over")
        lcd.font(FONT_S_BOLD)
        lcd.color(activeTextColor(state))
        lcd.drawText(boxX + 16, boxY + boxH + 10, string.format("Points: %d", state.hits))
    elseif state.bestResult then
        lcd.font(FONT_S_BOLD)
        lcd.drawText(boxX + 16, boxY + boxH + 10, string.format("Best result: %d", state.bestResult))
    end

    lcd.font(FONT_S_BOLD)
    lcd.drawText(boxX, state.height - 44, "Press Enter to start")
    lcd.font(FONT_XS)
    lcd.drawText(boxX, state.height - 22, "Long Page for settings")
end

local function drawTick(x, y, color)
    lcd.color(color)
    lcd.drawLine(x + 2, y + 8, x + 7, y + 13)
    lcd.drawLine(x + 7, y + 13, x + 16, y + 4)
    lcd.drawLine(x + 2, y + 9, x + 7, y + 14)
    lcd.drawLine(x + 7, y + 14, x + 16, y + 5)
end

local function visibleMenuItems(state)
    return MENU_ITEMS
end

local function renderMenu(state)
    local items = visibleMenuItems(state)

    if state.menuPosition >= #items then
        state.menuPosition = #items - 1
    end
    if state.menuPosition < 0 then
        state.menuPosition = 0
    end

    if state.scale > 1 then
        lcd.color(activeAccentColor(state))
        lcd.drawFilledRectangle(0, 0, state.width, 34)
        lcd.color(lcd.RGB(0, 0, 0))
        lcd.font(FONT_M_BOLD)
        lcd.drawText(8, 6, "Settings")

        local rowH = 30
        local startY = 44

        for idx, item in ipairs(items) do
            local rowY = startY + (idx - 1) * rowH
            if idx - 1 == state.menuPosition then
                lcd.color(activeAccentColor(state))
                lcd.drawRectangle(4, rowY - 2, state.width - 8, rowH - 2, 1)
            end

            lcd.color(activeTextColor(state))
            lcd.font(FONT_S)
            lcd.drawText(10, rowY + 2, item.label)

            local boxX = state.width - 34
            local boxY = rowY + 2
            lcd.drawRectangle(boxX, boxY, 18, 18, 1)

            if state.settings[item.key] then
                drawTick(boxX, boxY, activeTextColor(state))
            end
        end
        return
    end

    lcd.font(FONT_S_BOLD)
    lcd.color(activeTextColor(state))
    lcd.drawText(2, 1, "Settings")

    local rowH = 12
    local startY = 12

    for idx, item in ipairs(items) do
        local rowY = startY + (idx - 1) * rowH

        if idx - 1 == state.menuPosition then
            lcd.color(activeAccentColor(state))
            lcd.drawRectangle(1, rowY - 1, state.width - 2, rowH, 1)
        end

        lcd.color(activeTextColor(state))
        lcd.font(FONT_XXS)
        lcd.drawText(4, rowY + 1, item.label)

        local boxX = state.width - 10
        lcd.drawRectangle(boxX, rowY + 1, 8, 8, 1)
        if state.settings[item.key] then
            lcd.drawLine(boxX + 1, rowY + 5, boxX + 3, rowY + 7)
            lcd.drawLine(boxX + 3, rowY + 7, boxX + 7, rowY + 2)
        end
    end
end

local function applySettingSideEffects(state, key)
    if key == "staticBackground" then
        if state.backgrounds then
            state.backgrounds[0].y = -state.height
            state.backgrounds[1].y = 0
        end
    end
end

local function safeFormClear()
    if not (form and form.clear) then
        return false
    end
    return pcall(function()
        form.clear()
    end)
end

local function flushPendingFormClear(state)
    if not state or not state.pendingFormClear then
        return
    end
    if state.settingsFormOpen then
        return
    end
    if safeFormClear() then
        state.pendingFormClear = false
    end
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
    if not state then return end
    local now = (os and os.clock and os.clock()) or 0
    state.suppressExitUntil = now + (windowSeconds or 0.25)

    killPendingKeyEvents(KEY_EXIT_BREAK)
    killPendingKeyEvents(KEY_EXIT_FIRST)
end

local function suppressEnterEvents(state, windowSeconds)
    if not state then return end
    local now = (os and os.clock and os.clock()) or 0
    state.suppressEnterUntil = now + (windowSeconds or 0.20)

    killPendingKeyEvents(KEY_ENTER_BREAK)
    killPendingKeyEvents(KEY_ENTER_FIRST)
end

local function closeSettingsForm(state, suppressExit, suppressEnter)
    if suppressExit ~= false then
        suppressExitEvents(state)
    end
    if suppressEnter then
        suppressEnterEvents(state)
    end
    if state.backgrounds then
        state.backgrounds[0].y = -state.height
        state.backgrounds[1].y = 0
    end
    state.lastFrameTime = 0
    state.settingsFormOpen = false
    state.ignoreEnterBreak = false
    state.startOnNextEnterFirst = true
    state.pendingFormClear = true
    flushPendingFormClear(state)
end

local function openSettingsForm(state)
    if not (form and form.clear and form.addLine and form.addBooleanField) then
        return false
    end

    if not safeFormClear() then
        state.settingsFormOpen = false
        return false
    end
    state.settingsFormOpen = true

    local infoLine = form.addLine("GaLuaxian")
    if form.addStaticText then
        form.addStaticText(infoLine, nil, "Settings (Exit/Back to return)")
    end

    for _, item in ipairs(MENU_ITEMS) do
        local line = form.addLine(item.label)
        form.addBooleanField(
            line,
            nil,
            function()
                return state.settings[item.key]
            end,
            function(newValue)
                state.settings[item.key] = newValue and true or false
                applySettingSideEffects(state, item.key)
                saveStateConfig(state)
            end
        )
    end

    local resetLine = form.addLine("Best score")
    local resetAction = function()
        state.bestResult = nil
        saveStateConfig(state)
    end

    if form.addButton then
        form.addButton(resetLine, nil, {text = "Reset", press = resetAction})
    elseif form.addTextButton then
        form.addTextButton(resetLine, nil, "Reset", resetAction)
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

local function applyInput(state)
    local rawX = applyInputResponse(normalizeStick(sourceValue(state.shipSourceX)))
    local rawY = applyInputResponse(normalizeStick(sourceValue(state.shipSourceY)) * -1)

    if state.filteredInputX == nil then state.filteredInputX = rawX end
    if state.filteredInputY == nil then state.filteredInputY = rawY end

    local alphaX = INPUT_FILTER_ALPHA + (INPUT_FILTER_ALPHA_FAST - INPUT_FILTER_ALPHA) * (math.abs(rawX - state.filteredInputX) / 1024)
    local alphaY = INPUT_FILTER_ALPHA + (INPUT_FILTER_ALPHA_FAST - INPUT_FILTER_ALPHA) * (math.abs(rawY - state.filteredInputY) / 1024)
    state.filteredInputX = state.filteredInputX + ((rawX - state.filteredInputX) * alphaX)
    state.filteredInputY = state.filteredInputY + ((rawY - state.filteredInputY) * alphaY)

    local mappedX = mapInputToActionAreaPosition(state.filteredInputX, state.actionAreaWidthStart, state.actionAreaWidthEnd)
    local mappedY = mapInputToActionAreaPosition(state.filteredInputY, state.actionAreaHeightStart, state.actionAreaHeightEnd)

    local speedNorm = math.max(math.abs(state.filteredInputX), math.abs(state.filteredInputY)) / 1024
    local maxStep = (SHIP_STEP_BASE + (SHIP_STEP_EXTRA * speedNorm)) * state.scale * state.frameScale

    local nextX = approach(state.shipPosition.x, mappedX, maxStep)
    local nextY = approach(state.shipPosition.y, mappedY, maxStep)
    state.shipPosition.x = math.floor(clamp(nextX, state.actionAreaWidthStart, state.actionAreaWidthEnd) + 0.5)
    state.shipPosition.y = math.floor(clamp(nextY, state.actionAreaHeightStart, state.actionAreaHeightEnd) + 0.5)
end

local function startGame(state)
    refreshSelectedBackground(state)

    state.gameOver = false
    state.gameStarted = true
    state.hits = 0

    for i = 0, state.targetCount do
        local target = state.targets[i]
        target.dead = true
        target.y = math.random(0, math.max(0, state.height))
        assignTargetVariant(state, target)
    end

    for i = 0, state.projectileCount do
        local p = state.projectiles[i]
        p.delay = i * -4
        p.y = -state.height
    end
end

local function toggleSetting(state)
    local items = visibleMenuItems(state)
    local item = items[state.menuPosition + 1]
    if not item then return end

    state.settings[item.key] = not state.settings[item.key]
    applySettingSideEffects(state, item.key)
    saveStateConfig(state)
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

local function isExitKeyEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end
    if keyMatches(value, KEY_EXIT_BREAK, KEY_EXIT_FIRST) then
        return true
    end
    return value == 35
end

function game.create()
    math.randomseed(os.time())
    return createState()
end

function game.wakeup(state)
    if not state then return end
    if state.settingsFormOpen then return end
    flushPendingFormClear(state)
    refreshGeometryIfNeeded(state)
    if lcd.isVisible and not lcd.isVisible() then return end
    keepScreenAwake(state)
    lcd.invalidate()
end

function game.event(state, category, value)
    if not state then return false end

    local now = (os and os.clock and os.clock()) or 0
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
        -- Let Ethos form widgets (including touch) handle all other events.
        return false
    end

    local isCloseEvent = (category == EVT_CLOSE and (value == 0 or value == 35))

    if isCloseEvent then
        if state.menuPage then
            state.menuPage = false
            state.menuOpened = false
            state.ignoreEnterBreak = false
            suppressExitEvents(state)
            return true
        end
        if not state.gameOver then
            state.gameOver = true
            suppressExitEvents(state)
            return true
        end
        return false
    end

    if not isKeyCategory(category) then return false end

    if isSettingsOpenEvent(category, value) and state.gameOver then
        state.startOnNextEnterFirst = false
        if openSettingsForm(state) then
            state.menuPage = false
            state.menuOpened = false
            state.ignoreEnterBreak = true
            killPendingKeyEvents(KEY_ENTER_BREAK)
            return true
        end

        state.menuPage = true
        state.menuOpened = false
        state.ignoreEnterBreak = true
        killPendingKeyEvents(KEY_ENTER_BREAK)
        return true
    end

    if state.menuPage then
        if keyMatches(value, KEY_ROTARY_LEFT, KEY_LEFT_FIRST, KEY_LEFT_BREAK, KEY_UP_FIRST, KEY_UP_BREAK, KEY_PAGE_UP) then
            local count = #visibleMenuItems(state)
            state.menuPosition = (state.menuPosition - 1 + count) % count
            return true
        end

        if keyMatches(value, KEY_ROTARY_RIGHT, KEY_RIGHT_FIRST, KEY_RIGHT_BREAK, KEY_DOWN_FIRST, KEY_DOWN_BREAK, KEY_PAGE_DOWN) then
            local count = #visibleMenuItems(state)
            state.menuPosition = (state.menuPosition + 1) % count
            return true
        end

        if keyMatches(value, KEY_ENTER_BREAK) then
            if state.ignoreEnterBreak then
                state.ignoreEnterBreak = false
                state.menuOpened = true
                return true
            end
            if state.menuOpened then
                toggleSetting(state)
            end
            state.menuOpened = true
            return true
        end

        if isExitKeyEvent(category, value) then
            state.menuPage = false
            state.menuOpened = false
            state.ignoreEnterBreak = false
            suppressExitEvents(state)
            return true
        end

        return true
    end

    if keyMatches(value, KEY_ENTER_FIRST) then
        if state.gameOver then
            state.ignoreEnterBreak = false
            state.startOnNextEnterFirst = false
            startGame(state)
            return true
        end
    end

    if keyMatches(value, KEY_ENTER_BREAK) then
        if state.gameOver then
            state.ignoreEnterBreak = false
            state.startOnNextEnterFirst = false
            startGame(state)
            return true
        end
        if state.ignoreEnterBreak then
            state.ignoreEnterBreak = false
            return true
        end
    end

    if isExitKeyEvent(category, value) then
        if not state.gameOver then
            state.gameOver = true
            suppressExitEvents(state)
            return true
        end
        return false
    end

    return false
end

function game.paint(state)
    if not state then return end

    if state.settingsFormOpen then return end
    flushPendingFormClear(state)
    refreshGeometryIfNeeded(state)
    keepScreenAwake(state)
    updateFrameScale(state)
    applyInput(state)

    if state.gameOver and state.gameStarted then
        if (not state.bestResult) or (state.hits > state.bestResult) then
            state.bestResult = state.hits
            saveStateConfig(state)
        end
    end

    if not state.gameOver and state.settings.easyMode and state.targetCount ~= 2 then
        for i = 0, state.targetCount do
            state.targets[i].velocity = state.targetVelocityEasy
        end
        state.targetCount = 2
    end

    if not state.gameOver and (not state.settings.easyMode) and state.targetCount ~= 4 then
        state.targetCount = 4
        for i = 0, state.targetCount do
            state.targets[i].velocity = state.targetVelocityNormal
        end
    end

    clearScreen(state)
    drawBackground(state)

    if state.gameOver then
        if state.menuPage then
            renderMenu(state)
        else
            renderHome(state)
        end
        return
    end

    lcd.color(activeTextColor(state))
    lcd.font(state.scale > 1 and FONT_S_BOLD or FONT_XXS)
    lcd.drawText(4, 2, string.format("TOTAL HITS: %d", state.hits))

    drawShip(state, state.shipPosition.x, state.shipPosition.y)

    for i = 0, state.projectileCount do
        local p = state.projectiles[i]
        drawProjectile(state, p, state.shipPosition.x + state.shipHalfWidth, state.shipPosition.y)
    end

    drawTargets(state)
    drawExplosions(state)
end

function game.close(state)
    if type(state) ~= "table" then
        return
    end

    state.menuPage = false
    state.menuOpened = false
    state.ignoreEnterBreak = false
    state.gameOver = true
    if state.settingsFormOpen then
        closeSettingsForm(state, false)
    end
    state.settingsFormOpen = false
    flushPendingFormClear(state)
    releaseAssets(state)
    if collectgarbage then
        pcall(collectgarbage, "collect")
        pcall(collectgarbage, "collect")
    end
end

return game
