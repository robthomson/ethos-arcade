local game = {}

local MOVE_X_SOURCE_PREFERRED = "Ail"
local MOVE_X_SOURCE_CANDIDATES = {"Ail", "Aileron", "Roll", "P1", "S1"}
local MOVE_Y_SOURCE_PREFERRED = "Ele"
local MOVE_Y_SOURCE_CANDIDATES = {"Ele", "Elevator", "Pitch", "P2", "S2"}
local FIRE_SOURCE_PREFERRED = "Rud"
local FIRE_SOURCE_CANDIDATES = {"Rud", "Rudder", "Yaw", "P4", "S4", "Thr", "Throttle", "THR", "Tht", "Gas", "P3", "S3"}

local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local FIRE_BUTTON_VALUE = 96
local CONFIG_FILE = "luadefender.cfg"
local CONFIG_VERSION = 1

local DIFFICULTY_EASY = "easy"
local DIFFICULTY_NORMAL = "normal"
local DIFFICULTY_HARD = "hard"

local DIFFICULTY_CHOICE_EASY = 1
local DIFFICULTY_CHOICE_NORMAL = 2
local DIFFICULTY_CHOICE_HARD = 3
local DIFFICULTY_CHOICES_FORM = {
    {"Easy", DIFFICULTY_CHOICE_EASY},
    {"Normal", DIFFICULTY_CHOICE_NORMAL},
    {"Hard", DIFFICULTY_CHOICE_HARD}
}

local ACTIVE_RENDER_FPS = 30
local IDLE_RENDER_FPS = 12
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.60
local FRAME_SCALE_MAX = 1.90
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local WORLD_WIDTH = 2100
local HUD_HEIGHT = 24

local SHIP_HALF_W = 12
local SHIP_HALF_H = 8
local PLAYER_HIT_RADIUS = 11
local PLAYER_MAX_VX = 430
local PLAYER_MAX_VY = 276
local PLAYER_ACCEL = 0.38
local PLAYER_DEADZONE = 60

local CAMERA_LEFT_SCREEN_RATIO = 0.43
local CAMERA_RIGHT_SCREEN_RATIO = 0.57
local CAMERA_FOLLOW_ALPHA = 0.22
local BACKGROUND_SCROLL_FACTOR = 1.0
local EXPLOSION_DRAW_SCALE = 1.5

local BULLET_SPEED = 440
local BULLET_TTL = 1.7
local FIRE_DEADZONE = 110
local FIRE_REARM_CENTER = 200
local FIRE_TRIGGER_HIGH = 520
local FIRE_COOLDOWN = 0.13
local BG_FILES = {"bg1.png", "bg2.png", "bg3.png", "bg4.png"}

local ENEMY_HALF_W = 11
local ENEMY_HALF_H = 7
local ENEMY_HIT_RADIUS = 10
local ENEMY_BULLET_SPEED = 195
local ENEMY_BULLET_TTL = 2.4

local ANALOG_GLITCH_ABS_LIMIT = 5000
local ANALOG_GLITCH_DELTA_LIMIT = 1900
local STICK_SOURCE_IS_PERCENT = false
local STAR_DENSITY_DIVISOR = 12000
local TERRAIN_STEP = 8
local ASSET_PATH_DEBUG = false

local DIFFICULTY_PROFILES = {
    [DIFFICULTY_EASY] = {
        lives = 4,
        enemyBase = 6,
        enemyStep = 2,
        enemySpeed = 62,
        enemyFireInterval = 1.45,
        levelRamp = 0.050,
        scorePerEnemy = 10
    },
    [DIFFICULTY_NORMAL] = {
        lives = 3,
        enemyBase = 8,
        enemyStep = 2,
        enemySpeed = 72,
        enemyFireInterval = 1.22,
        levelRamp = 0.065,
        scorePerEnemy = 12
    },
    [DIFFICULTY_HARD] = {
        lives = 3,
        enemyBase = 10,
        enemyStep = 3,
        enemySpeed = 82,
        enemyFireInterval = 0.98,
        levelRamp = 0.085,
        scorePerEnemy = 14
    }
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
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

local function loadBitmapAsset(pathCandidates)
    if not (lcd and lcd.loadBitmap and pathCandidates) then
        return nil
    end

    local assetName = "asset"
    if type(pathCandidates) == "table" and type(pathCandidates.assetName) == "string" then
        assetName = pathCandidates.assetName
    end

    for i = 1, #pathCandidates do
        local path = pathCandidates[i]
        if ASSET_PATH_DEBUG then
            print(string.format("[luadefender] try %s path: %s", assetName, tostring(path)))
        end
        local ok, bitmap = pcall(lcd.loadBitmap, path)
        if ok and bitmap then
            if ASSET_PATH_DEBUG then
                print(string.format("[luadefender] loaded %s path: %s", assetName, tostring(path)))
            end
            return bitmap
        end
        if ASSET_PATH_DEBUG then
            if ok then
                print(string.format("[luadefender] failed %s path: %s", assetName, tostring(path)))
            else
                print(string.format("[luadefender] error %s path: %s (%s)", assetName, tostring(path), tostring(bitmap)))
            end
        end
    end

    if ASSET_PATH_DEBUG then
        print(string.format("[luadefender] missing %s asset", assetName))
    end
    return nil
end

local function assetPathCandidates(filename)
    local paths = {}
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/luadefender/gfx/" .. filename
    paths[#paths + 1] = "/scripts/ethos-arcade/games/luadefender/gfx/" .. filename
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/luadefender/gfx/" .. filename
    return paths
end

local function backgroundPathCandidates(filename)
    local file = (type(filename) == "string" and filename ~= "") and filename or "bg.png"
    local paths = assetPathCandidates(file)
    paths.assetName = file
    return paths
end

local function playerLeftPathCandidates()
    local paths = assetPathCandidates("player-l.png")
    paths.assetName = "player-l"
    return paths
end

local function playerRightPathCandidates()
    local paths = assetPathCandidates("player-r.png")
    paths.assetName = "player-r"
    return paths
end

local function enemyPathCandidates()
    local paths = assetPathCandidates("enemy.png")
    paths.assetName = "enemy"
    return paths
end

local function enemy2PathCandidates()
    local paths = assetPathCandidates("enemy2.png")
    paths.assetName = "enemy2"
    return paths
end

local function explosionPathCandidates()
    local paths = {}
    if SCRIPT_DIR ~= "" then
        paths[#paths + 1] = SCRIPT_DIR .. "gfx/explosion.png"
        paths[#paths + 1] = SCRIPT_DIR .. "../missilecmd/gfx/explosion.png"
    end
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/luadefender/gfx/explosion.png"
    paths[#paths + 1] = "/scripts/ethos-arcade/games/luadefender/gfx/explosion.png"
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/luadefender/gfx/explosion.png"
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/missilecmd/gfx/explosion.png"
    paths[#paths + 1] = "/scripts/ethos-arcade/games/missilecmd/gfx/explosion.png"
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/missilecmd/gfx/explosion.png"
    paths[#paths + 1] = "games/missilecmd/gfx/explosion.png"
    paths.assetName = "explosion"
    return paths
end

local function explosion2PathCandidates()
    local paths = {}
    if SCRIPT_DIR ~= "" then
        paths[#paths + 1] = SCRIPT_DIR .. "gfx/explosion2.png"
        paths[#paths + 1] = SCRIPT_DIR .. "../missilecmd/gfx/explosion2.png"
    end
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/luadefender/gfx/explosion2.png"
    paths[#paths + 1] = "/scripts/ethos-arcade/games/luadefender/gfx/explosion2.png"
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/luadefender/gfx/explosion2.png"
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/missilecmd/gfx/explosion2.png"
    paths[#paths + 1] = "/scripts/ethos-arcade/games/missilecmd/gfx/explosion2.png"
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/missilecmd/gfx/explosion2.png"
    paths[#paths + 1] = "games/missilecmd/gfx/explosion2.png"
    paths.assetName = "explosion2"
    return paths
end

local function configPathCandidates()
    local paths = {}
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/luadefender/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/luadefender/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/luadefender/" .. CONFIG_FILE
    return paths
end

local function loadBackgroundForState(state)
    if not state then
        return
    end

    -- Only keep the currently-used background bitmap referenced.
    -- This avoids holding all variants in memory at once.
    state.bgBitmap = nil
    state.bgBitmapKey = nil

    if type(state.bgVariantKeys) ~= "table" then
        state.bgVariantKeys = {}
        for i = 1, #BG_FILES do
            state.bgVariantKeys[#state.bgVariantKeys + 1] = BG_FILES[i]
        end
    end

    local keys = state.bgVariantKeys
    if type(keys) == "table" and #keys > 0 then
        local start = math.random(1, #keys)
        for offset = 0, (#keys - 1) do
            local idx = ((start + offset - 1) % #keys) + 1
            local key = keys[idx]
            local bmp = loadBitmapAsset(backgroundPathCandidates(key))
            if bmp then
                state.bgBitmap = bmp
                state.bgBitmapKey = key
                return
            end
        end
    end

    local fallback = loadBitmapAsset(backgroundPathCandidates("bg.png"))
    state.bgBitmap = fallback
    state.bgBitmapKey = fallback and "bg.png" or nil
end

local function bitmapSize(bitmap)
    if not bitmap then
        return nil, nil
    end
    if not bitmap.width then
        return nil, nil
    end

    local okW, w = pcall(bitmap.width, bitmap)
    local okH, h = pcall(bitmap.height, bitmap)
    if not okW or not okH then
        return nil, nil
    end
    if type(w) ~= "number" or type(h) ~= "number" then
        return nil, nil
    end
    if w <= 0 or h <= 0 then
        return nil, nil
    end
    return w, h
end

local function refreshSpriteMetrics(state)
    if not state then
        return
    end

    local playerW = SHIP_HALF_W * 2
    local playerH = SHIP_HALF_H * 2
    local enemy1W = ENEMY_HALF_W * 2
    local enemy1H = ENEMY_HALF_H * 2
    local enemy2W = ENEMY_HALF_W * 2
    local enemy2H = ENEMY_HALF_H * 2

    local plw, plh = bitmapSize(state.playerLeftBitmap)
    local prw, prh = bitmapSize(state.playerRightBitmap)
    local pw, ph = plw, plh
    if prw and prh then
        if (not pw) or (not ph) then
            pw, ph = prw, prh
        else
            pw = math.max(pw, prw)
            ph = math.max(ph, prh)
        end
    end
    if pw and ph then
        playerW = pw
        playerH = ph
    end

    local ew, eh = bitmapSize(state.enemyBitmap)
    if ew and eh then
        enemy1W = ew
        enemy1H = eh
    end

    local ew2, eh2 = bitmapSize(state.enemy2Bitmap)
    if ew2 and eh2 then
        enemy2W = ew2
        enemy2H = eh2
    end

    state.playerHalfW = math.max(1, math.floor(playerW * 0.5 + 0.5))
    state.playerHalfH = math.max(1, math.floor(playerH * 0.5 + 0.5))
    state.enemyHalfW = math.max(1, math.floor(enemy1W * 0.5 + 0.5))
    state.enemyHalfH = math.max(1, math.floor(enemy1H * 0.5 + 0.5))
    state.enemy2HalfW = math.max(1, math.floor(enemy2W * 0.5 + 0.5))
    state.enemy2HalfH = math.max(1, math.floor(enemy2H * 0.5 + 0.5))

    state.playerHitRadius = math.max(6, math.floor(math.max(playerW, playerH) * 0.30 + 0.5))
    state.enemyHitRadius = math.max(6, math.floor(math.max(enemy1W, enemy1H) * 0.30 + 0.5))
    state.enemy2HitRadius = math.max(6, math.floor(math.max(enemy2W, enemy2H) * 0.30 + 0.5))
end

local function refreshRequiredAssets(state)
    if not state then
        return
    end

    if not state.bgBitmap then
        loadBackgroundForState(state)
    end
    if not state.playerLeftBitmap then
        state.playerLeftBitmap = loadBitmapAsset(playerLeftPathCandidates())
    end
    if not state.playerRightBitmap then
        state.playerRightBitmap = loadBitmapAsset(playerRightPathCandidates())
    end
    if not state.enemyBitmap then
        state.enemyBitmap = loadBitmapAsset(enemyPathCandidates())
    end
    if (not state.enemy2LoadAttempted) and (not state.enemy2Bitmap) then
        state.enemy2Bitmap = loadBitmapAsset(enemy2PathCandidates())
        state.enemy2LoadAttempted = true
    end
    if (not state.explosionLoadAttempted) and (not state.explosionBitmap) then
        state.explosionBitmap = loadBitmapAsset(explosionPathCandidates())
        state.explosionBitmap2 = loadBitmapAsset(explosion2PathCandidates())
        state.explosionLoadAttempted = true
    end
    if state.explosionBitmap then
        local w, h = bitmapSize(state.explosionBitmap)
        if w and h then
            state.explosionHalfW = math.max(1, math.floor(w * 0.5 + 0.5))
            state.explosionHalfH = math.max(1, math.floor(h * 0.5 + 0.5))
        end
    end
    if state.explosionBitmap2 then
        local w2, h2 = bitmapSize(state.explosionBitmap2)
        if w2 and h2 then
            state.explosion2HalfW = math.max(1, math.floor(w2 * 0.5 + 0.5))
            state.explosion2HalfH = math.max(1, math.floor(h2 * 0.5 + 0.5))
        end
    end

    refreshSpriteMetrics(state)

    local missing = {}
    if not state.bgBitmap then
        missing[#missing + 1] = "bg"
    end
    if not state.playerLeftBitmap then
        missing[#missing + 1] = "player-l"
    end
    if not state.playerRightBitmap then
        missing[#missing + 1] = "player-r"
    end
    if not state.enemyBitmap then
        missing[#missing + 1] = "enemy"
    end

    state.assetsReady = (#missing == 0)
    state.missingAssets = missing

    local signature = table.concat(missing, ",")
    if signature ~= (state.lastMissingAssetSignature or "") then
        state.lastMissingAssetSignature = signature
        if signature ~= "" then
            print("[luadefender] missing gfx: " .. signature)
        end
    end
end

local function releaseAssets(state)
    if not state then
        return
    end

    state.bgBitmap = nil
    state.bgBitmapKey = nil
    state.bgVariantKeys = nil

    state.playerLeftBitmap = nil
    state.playerRightBitmap = nil
    state.enemyBitmap = nil
    state.enemy2Bitmap = nil
    state.explosionBitmap = nil
    state.explosionBitmap2 = nil

    state.enemy2LoadAttempted = nil
    state.explosionLoadAttempted = nil
    state.explosionHalfW = nil
    state.explosionHalfH = nil
    state.explosion2HalfW = nil
    state.explosion2HalfH = nil

    state.assetsReady = false
    state.missingAssets = nil
    state.lastMissingAssetSignature = nil

    state.stars = nil
    state.bullets = nil
    state.enemies = nil
    state.explosions = nil
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
        bestScore = math.max(0, math.floor(bestScore))
    else
        bestScore = nil
    end

    local config = {
        difficulty = normalizeDifficulty(values.difficulty)
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
    if state.bestScore ~= nil then
        f:write("bestScore=", math.max(0, math.floor(state.bestScore)), "\n")
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
    if not (system and system.playTone) then
        return
    end
    pcall(system.playTone, freq, duration or 25, pause or 0)
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

local function resolveSource(candidates, preferredName)
    if type(preferredName) == "string" and preferredName ~= "" then
        local preferred = system.getSource(preferredName)
        if preferred then
            return preferred
        end
    end

    for _, name in ipairs(candidates) do
        local src = system.getSource(name)
        if src then
            return src
        end
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

    if math.abs(raw) > ANALOG_GLITCH_ABS_LIMIT then
        raw = last or 0
    elseif last ~= nil and math.abs(raw - last) > ANALOG_GLITCH_DELTA_LIMIT then
        raw = last
    end

    raw = normalizeStick(raw)
    state.lastRawInputByAxis[axisKey] = raw
    return raw
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

local function groundYAt(state, worldX)
    local x = (worldX % state.worldWidth) / state.worldWidth
    local y = state.playBottom - 30
    y = y - (16 * math.sin((x * math.pi * 2 * 2.0) + 0.35))
    y = y - (11 * math.sin((x * math.pi * 2 * 4.8) + 1.12))
    y = y - (8 * math.sin((x * math.pi * 2 * 9.7) + 2.65))
    return clamp(y, state.playTop + 70, state.playBottom - 12)
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

    state.hudHeight = HUD_HEIGHT
    state.playTop = state.hudHeight + 1
    state.playBottom = state.height - 2

    state.cameraX = clamp(state.cameraX or 0, 0, math.max(0, state.worldWidth - state.width))

    if state.player then
        state.player.x = clamp(state.player.x, 0, state.worldWidth)
        local ground = groundYAt(state, state.player.x)
        local playerHalfH = state.playerHalfH or SHIP_HALF_H
        state.player.y = clamp(state.player.y, state.playTop + 8, ground - (playerHalfH + 2))
    end

    if changed then
        forceInvalidate(state)
    end
end

local function applyConfigSideEffects(state)
    if not (state and state.config) then
        return
    end
    state.config.difficulty = normalizeDifficulty(state.config.difficulty)
    state.profile = DIFFICULTY_PROFILES[state.config.difficulty] or DIFFICULTY_PROFILES[DIFFICULTY_NORMAL]
end

local function setConfigValue(state, key, value, skipSave)
    if not (state and state.config) then
        return
    end

    if key == "difficulty" then
        state.config.difficulty = normalizeDifficulty(value)
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
    flushPendingFormClear(state)
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

    local infoLine = form.addLine("LuaDefender")
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

local function randomRange(minValue, maxValue)
    return minValue + (math.random() * (maxValue - minValue))
end

local function buildStars(state)
    state.stars = {}
    local count = math.max(16, math.floor(state.width * state.height / STAR_DENSITY_DIVISOR))

    for i = 1, count do
        state.stars[#state.stars + 1] = {
            x = math.random() * state.worldWidth,
            y = randomRange(state.playTop + 2, state.playBottom - 80),
            twinkle = math.random()
        }
    end
end

local function clearEntities(state)
    state.bullets = {}
    state.enemyBullets = {}
    state.enemies = {}
    state.explosions = {}
end

local function createExplosion(state, x, y)
    state.explosions[#state.explosions + 1] = {
        x = x,
        y = y,
        radius = 2,
        ttl = 0.36,
        maxTtl = 0.36
    }
end

local function spawnEnemy(state)
    local p = state.profile
    local y = randomRange(state.playTop + 18, state.playBottom - 120)
    local side = math.random() < 0.5 and -1 or 1

    local x
    if side < 0 then
        x = randomRange(50, state.worldWidth * 0.42)
    else
        x = randomRange(state.worldWidth * 0.58, state.worldWidth - 50)
    end

    local speed = p.enemySpeed * randomRange(0.88, 1.16)
    local useEnemy2 = state.enemy2Bitmap and (math.random() < 0.5)
    local enemyBitmap = useEnemy2 and state.enemy2Bitmap or state.enemyBitmap
    local enemyHalfW = useEnemy2 and (state.enemy2HalfW or state.enemyHalfW or ENEMY_HALF_W) or (state.enemyHalfW or ENEMY_HALF_W)
    local enemyHalfH = useEnemy2 and (state.enemy2HalfH or state.enemyHalfH or ENEMY_HALF_H) or (state.enemyHalfH or ENEMY_HALF_H)
    local enemyHitRadius = useEnemy2 and (state.enemy2HitRadius or state.enemyHitRadius or ENEMY_HIT_RADIUS) or (state.enemyHitRadius or ENEMY_HIT_RADIUS)

    state.enemies[#state.enemies + 1] = {
        x = x,
        y = y,
        vx = side * speed,
        vy = randomRange(-32, 32),
        reload = randomRange(0.35, p.enemyFireInterval),
        radius = enemyHitRadius,
        bitmap = enemyBitmap,
        halfW = enemyHalfW,
        halfH = enemyHalfH
    }
end

local function spawnWave(state, firstWave)
    if not firstWave then
        state.wave = state.wave + 1
        state.score = state.score + (28 + (state.wave * 4))
        playTone(1320, 70, 20)
    end

    state.enemySpawnCount = state.profile.enemyBase + ((state.wave - 1) * state.profile.enemyStep)
    state.enemySpeedMul = 1 + ((state.wave - 1) * state.profile.levelRamp)

    state.enemies = {}
    state.enemyBullets = {}

    for i = 1, state.enemySpawnCount do
        spawnEnemy(state)
    end
end

local function finishGame(state)
    state.running = false
    state.gameOver = true
    state.lastResult = state.score

    if state.bestScore == nil or state.score > state.bestScore then
        state.bestScore = state.score
        state.isNewBest = true
        saveStateConfig(state)
        playTone(1250, 150, 35)
    else
        state.isNewBest = false
        playTone(300, 180, 35)
    end
end

local function resetPlayer(state)
    state.player.x = clamp(state.cameraX + (state.width * 0.35), 40, state.worldWidth - 40)
    state.player.y = state.playTop + math.floor((state.playBottom - state.playTop) * 0.42)
    state.player.vx = 0
    state.player.vy = 0
    state.player.facing = 1
    state.player.invuln = 1.3

    local ground = groundYAt(state, state.player.x)
    local playerHalfH = state.playerHalfH or SHIP_HALF_H
    state.player.y = clamp(state.player.y, state.playTop + 10, ground - (playerHalfH + 3))
end

local function loseLife(state)
    if not state.running then
        return
    end

    state.lives = state.lives - 1
    if state.lives <= 0 then
        finishGame(state)
        return
    end

    playTone(280, 100, 15)
    resetPlayer(state)
end

local function startGame(state)
    loadBackgroundForState(state)
    refreshRequiredAssets(state)
    if not state.assetsReady then
        state.running = false
        state.gameOver = false
        forceInvalidate(state)
        return
    end

    state.running = true
    state.gameOver = false
    state.lastResult = nil
    state.isNewBest = false

    state.wave = 1
    state.score = 0
    state.fireArmed = false
    state.fireCooldown = 0
    state.lastRawInputByAxis = {}

    local profile = state.profile or DIFFICULTY_PROFILES[DIFFICULTY_NORMAL]
    state.lives = profile.lives

    clearEntities(state)
    resetPlayer(state)
    spawnWave(state, true)

    forceInvalidate(state)
end

local function stopRound(state, keepResult)
    state.running = false
    state.gameOver = false

    if not keepResult then
        state.lastResult = nil
        state.isNewBest = false
    end

    state.fireArmed = false
    state.fireCooldown = 0

    clearEntities(state)
end

local function tryFire(state)
    if not state.running then
        return false
    end
    if (state.fireCooldown or 0) > 0 then
        return false
    end

    local p = state.player
    local dir = p.facing or 1
    local vx = BULLET_SPEED * dir
    local vy = p.vy * 0.08

    state.bullets[#state.bullets + 1] = {
        x = p.x + (((state.playerHalfW or SHIP_HALF_W) + 2) * dir),
        y = p.y,
        vx = vx,
        vy = vy,
        ttl = BULLET_TTL,
        radius = 3
    }

    state.fireCooldown = FIRE_COOLDOWN
    playTone(980, 16, 0)
    return true
end

local function updateCamera(state)
    local cameraX = state.cameraX or 0
    local screenX = state.player.x - cameraX
    local leftBound = state.width * CAMERA_LEFT_SCREEN_RATIO
    local rightBound = state.width * CAMERA_RIGHT_SCREEN_RATIO

    local target = cameraX
    if screenX < leftBound then
        target = state.player.x - leftBound
    elseif screenX > rightBound then
        target = state.player.x - rightBound
    end

    target = clamp(target, 0, math.max(0, state.worldWidth - state.width))
    state.cameraX = cameraX + ((target - cameraX) * CAMERA_FOLLOW_ALPHA)
    state.cameraX = clamp(state.cameraX, 0, math.max(0, state.worldWidth - state.width))
end

local function updatePlayer(state, dt)
    local rawX = sanitizeStickSample(state, sourceValue(state.moveSourceX), "moveX")
    local rawY = sanitizeStickSample(state, sourceValue(state.moveSourceY), "moveY")
    rawX = applyDeadzone(rawX, PLAYER_DEADZONE)
    rawY = applyDeadzone(rawY, PLAYER_DEADZONE)

    if math.abs(rawX) > 120 then
        if rawX > 0 then
            state.player.facing = 1
        else
            state.player.facing = -1
        end
    end

    local targetVx = (rawX / 1024) * PLAYER_MAX_VX
    local targetVy = (-rawY / 1024) * PLAYER_MAX_VY

    state.player.vx = state.player.vx + ((targetVx - state.player.vx) * PLAYER_ACCEL)
    state.player.vy = state.player.vy + ((targetVy - state.player.vy) * PLAYER_ACCEL)

    state.player.x = state.player.x + (state.player.vx * dt)
    state.player.y = state.player.y + (state.player.vy * dt)

    state.player.x = clamp(state.player.x, 0, state.worldWidth)

    local ceiling = state.playTop + 8
    local floor = groundYAt(state, state.player.x) - ((state.playerHalfH or SHIP_HALF_H) + 2)
    if state.player.y > floor then
        state.player.y = floor
        state.player.vy = 0
        loseLife(state)
        return
    end
    state.player.y = clamp(state.player.y, ceiling, floor)

    state.fireCooldown = math.max(0, (state.fireCooldown or 0) - (dt or 0))

    local rawFire = sanitizeStickSample(state, sourceValue(state.fireSource), "fire")
    rawFire = applyDeadzone(rawFire, FIRE_DEADZONE)

    if math.abs(rawFire) <= FIRE_REARM_CENTER then
        state.fireArmed = true
    end

    if state.fireArmed and math.abs(rawFire) >= FIRE_TRIGGER_HIGH and state.fireCooldown <= 0 then
        tryFire(state)
        state.fireArmed = false
    end

    if state.player.invuln and state.player.invuln > 0 then
        state.player.invuln = math.max(0, state.player.invuln - dt)
    end

    updateCamera(state)
end

local function updateBullets(state, dt)
    for i = #state.bullets, 1, -1 do
        local b = state.bullets[i]
        b.x = b.x + (b.vx * dt)
        b.y = b.y + (b.vy * dt)
        b.ttl = b.ttl - dt

        if b.ttl <= 0 or b.x < -20 or b.x > (state.worldWidth + 20) or b.y < state.playTop or b.y > state.playBottom then
            table.remove(state.bullets, i)
        end
    end
end

local function spawnEnemyBullet(state, enemy)
    local dx = state.player.x - enemy.x
    local dy = state.player.y - enemy.y
    local dist = math.sqrt((dx * dx) + (dy * dy))
    if dist < 1 then
        dist = 1
    end

    local speed = ENEMY_BULLET_SPEED
    state.enemyBullets[#state.enemyBullets + 1] = {
        x = enemy.x,
        y = enemy.y,
        vx = (dx / dist) * speed,
        vy = (dy / dist) * speed,
        ttl = ENEMY_BULLET_TTL,
        radius = 3
    }
end

local function updateEnemies(state, dt)
    local p = state.profile
    local chaseWeight = 0.42
    local driftWeight = 0.24

    for i = #state.enemies, 1, -1 do
        local e = state.enemies[i]

        local dx = state.player.x - e.x
        local dy = state.player.y - e.y

        e.vx = e.vx + (clamp(dx, -240, 240) * chaseWeight * dt)
        e.vy = e.vy + (clamp(dy, -180, 180) * driftWeight * dt)

        local speedMax = (p.enemySpeed * state.enemySpeedMul)
        local speed = math.sqrt((e.vx * e.vx) + (e.vy * e.vy))
        if speed > speedMax and speed > 0 then
            local scale = speedMax / speed
            e.vx = e.vx * scale
            e.vy = e.vy * scale
        end

        e.x = e.x + (e.vx * dt)
        e.y = e.y + (e.vy * dt)

        if e.x < 0 then
            e.x = 0
            e.vx = math.abs(e.vx)
        elseif e.x > state.worldWidth then
            e.x = state.worldWidth
            e.vx = -math.abs(e.vx)
        end

        local top = state.playTop + 10
        local bottom = groundYAt(state, e.x) - 10
        if e.y < top then
            e.y = top
            e.vy = math.abs(e.vy)
        elseif e.y > bottom then
            e.y = bottom
            e.vy = -math.abs(e.vy)
        end

        e.reload = e.reload - dt
        if e.reload <= 0 then
            if math.abs(dx) < 360 then
                spawnEnemyBullet(state, e)
            end
            e.reload = randomRange(p.enemyFireInterval * 0.65, p.enemyFireInterval * 1.18)
        end
    end
end

local function updateEnemyBullets(state, dt)
    for i = #state.enemyBullets, 1, -1 do
        local b = state.enemyBullets[i]
        b.x = b.x + (b.vx * dt)
        b.y = b.y + (b.vy * dt)
        b.ttl = b.ttl - dt

        if b.ttl <= 0 or b.x < -20 or b.x > (state.worldWidth + 20) or b.y < state.playTop or b.y > state.playBottom then
            table.remove(state.enemyBullets, i)
        end
    end
end

local function updateExplosions(state, dt)
    for i = #state.explosions, 1, -1 do
        local e = state.explosions[i]
        e.ttl = e.ttl - dt
        e.radius = e.radius + (80 * dt)
        if e.ttl <= 0 then
            table.remove(state.explosions, i)
        end
    end
end

local function checkBulletEnemyHits(state)
    local scorePerEnemy = state.profile.scorePerEnemy

    for i = #state.bullets, 1, -1 do
        local b = state.bullets[i]
        local hitEnemyIndex = nil

        for j = #state.enemies, 1, -1 do
            local e = state.enemies[j]
            local dx = b.x - e.x
            local dy = b.y - e.y
            local r = b.radius + e.radius
            if (dx * dx) + (dy * dy) <= (r * r) then
                hitEnemyIndex = j
                break
            end
        end

        if hitEnemyIndex then
            local enemy = state.enemies[hitEnemyIndex]
            createExplosion(state, enemy.x, enemy.y)
            table.remove(state.enemies, hitEnemyIndex)
            table.remove(state.bullets, i)
            state.score = state.score + scorePerEnemy
            playTone(1180, 12, 0)
        end
    end
end

local function checkPlayerHits(state)
    if state.player.invuln and state.player.invuln > 0 then
        return
    end

    local px = state.player.x
    local py = state.player.y
    local pr = state.playerHitRadius or PLAYER_HIT_RADIUS

    for i = #state.enemyBullets, 1, -1 do
        local b = state.enemyBullets[i]
        local dx = px - b.x
        local dy = py - b.y
        local r = pr + b.radius
        if (dx * dx) + (dy * dy) <= (r * r) then
            createExplosion(state, px, py)
            table.remove(state.enemyBullets, i)
            loseLife(state)
            return
        end
    end

    for i = #state.enemies, 1, -1 do
        local e = state.enemies[i]
        local dx = px - e.x
        local dy = py - e.y
        local r = pr + e.radius
        if (dx * dx) + (dy * dy) <= (r * r) then
            createExplosion(state, px, py)
            loseLife(state)
            return
        end
    end
end

local function checkWaveProgress(state)
    if #state.enemies > 0 then
        return
    end
    if #state.enemyBullets > 0 then
        return
    end

    spawnWave(state, false)
end

local function updateGame(state, dt)
    if not state.running then
        return
    end

    updatePlayer(state, dt)
    if not state.running then
        return
    end

    updateBullets(state, dt)
    updateEnemies(state, dt)
    updateEnemyBullets(state, dt)
    updateExplosions(state, dt)

    checkBulletEnemyHits(state)
    checkPlayerHits(state)

    if state.running then
        checkWaveProgress(state)
    end
end

local function worldToScreenX(state, x)
    return x - state.cameraX
end

local function drawBackground(state)
    setColor(0, 0, 0)
    lcd.drawFilledRectangle(0, 0, state.width, state.height)

    if not (state.bgBitmap and lcd and lcd.drawBitmap) then
        return
    end

    local bmpW, bmpH = bitmapSize(state.bgBitmap)
    local drawW = state.width
    local drawH = state.height
    local useNative = (bmpW == state.width and bmpH == state.height)

    if useNative then
        drawW = bmpW
        drawH = bmpH
    end

    drawW = math.max(1, math.floor(tonumber(drawW) or state.width or 1))
    drawH = math.max(1, math.floor(tonumber(drawH) or state.height or 1))

    local scroll = ((state.cameraX or 0) * BACKGROUND_SCROLL_FACTOR) % drawW
    local x = -math.floor(scroll + 0.5)

    while x < state.width do
        local okDraw
        if useNative then
            okDraw = pcall(lcd.drawBitmap, x, 0, state.bgBitmap)
        else
            okDraw = pcall(lcd.drawBitmap, x, 0, state.bgBitmap, drawW, drawH)
        end

        if not okDraw then
            print("[luadefender] draw bg failed")
            return
        end

        x = x + drawW
    end
end

local function drawTerrain(state)
    local step = TERRAIN_STEP
    local prevX = nil
    local prevY = nil

    setColor(30, 70, 34)
    for sx = 0, state.width + step, step do
        local wx = state.cameraX + sx
        local gy = groundYAt(state, wx)
        local gyi = math.floor(gy)

        lcd.drawLine(sx, gyi, sx, state.playBottom)

        if prevX and ((sx / step) % 2 == 0) then
            setColor(120, 182, 106)
            lcd.drawLine(prevX, prevY, sx, gyi)
            setColor(30, 70, 34)
        end

        prevX = sx
        prevY = gyi
    end
end

local function drawPlayer(state)
    local p = state.player
    local playerHalfW = state.playerHalfW or SHIP_HALF_W
    local playerHalfH = state.playerHalfH or SHIP_HALF_H
    local sx = math.floor(worldToScreenX(state, p.x) + 0.5)
    local sy = math.floor(p.y + 0.5)

    if sx < -20 or sx > (state.width + 20) then
        return
    end

    local flashOff = p.invuln and p.invuln > 0 and (((math.floor(nowSeconds() * 14)) % 2) == 0)
    if flashOff then
        return
    end

    local dir = p.facing or 1
    local playerBitmap = (dir < 0) and state.playerLeftBitmap or state.playerRightBitmap
    if playerBitmap and lcd and lcd.drawBitmap then
        local okDraw = pcall(lcd.drawBitmap, sx - playerHalfW, sy - playerHalfH, playerBitmap)
        if not okDraw then
            print("[luadefender] draw player failed")
        end
    end
end

local function drawEnemies(state)
    if not (lcd and lcd.drawBitmap) then
        return
    end

    for i = 1, #state.enemies do
        local e = state.enemies[i]
        local sx = math.floor(worldToScreenX(state, e.x) + 0.5)
        local sy = math.floor(e.y + 0.5)
        local enemyBitmap = e.bitmap or state.enemyBitmap
        local enemyHalfW = e.halfW or state.enemyHalfW or ENEMY_HALF_W
        local enemyHalfH = e.halfH or state.enemyHalfH or ENEMY_HALF_H

        if enemyBitmap and sx >= -24 and sx <= (state.width + 24) then
            local okDraw = pcall(lcd.drawBitmap, sx - enemyHalfW, sy - enemyHalfH, enemyBitmap)
            if not okDraw then
                print("[luadefender] draw enemy failed")
            end
        end
    end
end

local function drawBullets(state)
    for i = 1, #state.bullets do
        local b = state.bullets[i]
        local sx = math.floor(worldToScreenX(state, b.x) + 0.5)
        local sy = math.floor(b.y + 0.5)
        if sx >= -6 and sx <= (state.width + 6) then
            setColor(142, 236, 255)
            lcd.drawFilledRectangle(sx - 1, sy - 1, 3, 3)
        end
    end

    for i = 1, #state.enemyBullets do
        local b = state.enemyBullets[i]
        local sx = math.floor(worldToScreenX(state, b.x) + 0.5)
        local sy = math.floor(b.y + 0.5)
        if sx >= -6 and sx <= (state.width + 6) then
            setColor(255, 140, 120)
            lcd.drawFilledRectangle(sx - 1, sy - 1, 3, 3)
        end
    end
end

local function drawExplosions(state)
    for i = 1, #state.explosions do
        local e = state.explosions[i]
        local sx = math.floor(worldToScreenX(state, e.x) + 0.5)
        local sy = math.floor(e.y + 0.5)
        local r = math.max(1, math.floor(e.radius + 0.5))

        if sx >= -32 and sx <= (state.width + 32) then
            local drewBitmap = false
            local maxTtl = math.max(0.001, e.maxTtl or 0.28)
            local t = 1 - (clamp(e.ttl / maxTtl, 0, 1))
            local explosionBitmap = state.explosionBitmap
            local halfW = state.explosionHalfW or 0
            local halfH = state.explosionHalfH or 0
            if state.explosionBitmap2 and t >= 0.56 then
                explosionBitmap = state.explosionBitmap2
                halfW = state.explosion2HalfW or halfW
                halfH = state.explosion2HalfH or halfH
            end

            if explosionBitmap and lcd and lcd.drawBitmap then
                local ok = pcall(lcd.drawBitmap, sx - halfW, sy - halfH, explosionBitmap)
                drewBitmap = ok and true or false
            end

            if not drewBitmap then
                setColor(255, 224, 128)
                if lcd and lcd.drawCircle then
                    lcd.drawCircle(sx, sy, r)
                    if r > 4 then
                        setColor(255, 248, 210)
                        lcd.drawCircle(sx, sy, math.max(1, r - 3))
                    end
                else
                    lcd.drawRectangle(sx - r, sy - r, r * 2, r * 2, 1)
                end
            end
        end
    end
end

local function drawHud(state)
    setColor(8, 14, 24)
    lcd.drawFilledRectangle(0, 0, state.width, state.hudHeight)
    setColor(66, 94, 126)
    lcd.drawLine(0, state.hudHeight - 1, state.width - 1, state.hudHeight - 1)

    setFont(FONT_XXS or FONT_STD)
    setColor(236, 244, 252)
    lcd.drawText(4, 2, string.format("Score %d", state.score))
    lcd.drawText(96, 2, string.format("Wave %d", state.wave))
    lcd.drawText(168, 2, string.format("Lives %d", state.lives))
    lcd.drawText(246, 2, string.format("Diff %s", difficultyLabel(state.config.difficulty)))

    if state.bestScore ~= nil then
        lcd.drawText(state.width - 110, 2, string.format("Best %d", state.bestScore))
    end
end

local function drawOverlay(state)
    local boxW = math.floor(state.width * 0.76)
    local boxH = math.floor(state.height * 0.56)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(5, 12, 22)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(120, 150, 184)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(246, 252, 255)
    drawCenteredText(boxX, boxY + 8, boxW, 24, "LuaDefender")

    setFont(FONT_XXS or FONT_STD)
    setColor(188, 210, 232)

    if not state.assetsReady then
        drawCenteredText(boxX, boxY + 34, boxW, 18, "Missing required graphics")
        drawCenteredText(boxX, boxY + 50, boxW, 18, "Need: bg.png, player-l.png, player-r.png, enemy.png")
        drawCenteredText(boxX, boxY + 66, boxW, 18, "Path: games/luadefender/gfx")
    elseif state.gameOver then
        drawCenteredText(boxX, boxY + 34, boxW, 18, "Ship destroyed")
        drawCenteredText(boxX, boxY + 50, boxW, 18, string.format("Result: %d", state.lastResult or 0))
        if state.isNewBest then
            drawCenteredText(boxX, boxY + 66, boxW, 18, "New best score!")
        elseif state.bestScore ~= nil then
            drawCenteredText(boxX, boxY + 66, boxW, 18, string.format("Best: %d", state.bestScore))
        end
    else
        drawCenteredText(boxX, boxY + 34, boxW, 18, "Side-scroll shooter defense")
    end

    drawCenteredText(boxX, boxY + 86, boxW, 18, "Aileron+Elevator move")
    drawCenteredText(boxX, boxY + 104, boxW, 18, "Fire: Rudder pulse or short Page")
    drawCenteredText(boxX, boxY + 122, boxW, 18, "Enter start, Long Page settings")
end

local function render(state)
    drawBackground(state)
    drawEnemies(state)
    drawBullets(state)
    drawExplosions(state)
    drawPlayer(state)
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

        worldWidth = WORLD_WIDTH,
        hudHeight = HUD_HEIGHT,
        playTop = HUD_HEIGHT + 1,
        playBottom = 270,
        cameraX = 0,

        config = config,
        profile = DIFFICULTY_PROFILES[DIFFICULTY_NORMAL],
        bestScore = bestScore,
        lastResult = nil,
        isNewBest = false,

        running = false,
        gameOver = false,

        wave = 1,
        score = 0,
        lives = 3,
        enemySpawnCount = 0,
        enemySpeedMul = 1,

        player = {
            x = 120,
            y = 120,
            vx = 0,
            vy = 0,
            facing = 1,
            invuln = 0
        },
        playerHalfW = SHIP_HALF_W,
        playerHalfH = SHIP_HALF_H,
        playerHitRadius = PLAYER_HIT_RADIUS,
        enemyHalfW = ENEMY_HALF_W,
        enemyHalfH = ENEMY_HALF_H,
        enemyHitRadius = ENEMY_HIT_RADIUS,
        enemy2HalfW = ENEMY_HALF_W,
        enemy2HalfH = ENEMY_HALF_H,
        enemy2HitRadius = ENEMY_HIT_RADIUS,

        bullets = {},
        enemyBullets = {},
        enemies = {},
        explosions = {},

        fireArmed = false,
        fireCooldown = 0,

        bgBitmap = nil,
        bgBitmapKey = nil,
        playerLeftBitmap = loadBitmapAsset(playerLeftPathCandidates()),
        playerRightBitmap = loadBitmapAsset(playerRightPathCandidates()),
        enemyBitmap = loadBitmapAsset(enemyPathCandidates()),
        enemy2Bitmap = loadBitmapAsset(enemy2PathCandidates()),
        enemy2LoadAttempted = true,
        explosionBitmap = loadBitmapAsset(explosionPathCandidates()),
        explosionBitmap2 = loadBitmapAsset(explosion2PathCandidates()),
        explosionLoadAttempted = true,
        assetsReady = false,
        missingAssets = {},
        lastMissingAssetSignature = "",
        stars = nil,

        moveSourceX = resolveSource(MOVE_X_SOURCE_CANDIDATES, MOVE_X_SOURCE_PREFERRED),
        moveSourceY = resolveSource(MOVE_Y_SOURCE_CANDIDATES, MOVE_Y_SOURCE_PREFERRED),
        fireSource = resolveSource(FIRE_SOURCE_CANDIDATES, FIRE_SOURCE_PREFERRED),
        lastRawInputByAxis = {},

        frameScale = 1,
        lastFrameTime = 0,
        nextInvalidateAt = 0,
        lastFocusKick = 0,

        settingsFormOpen = false,
        pendingFormClear = false,
        suppressExitUntil = 0,
        suppressEnterUntil = 0
    }

    applyConfigSideEffects(state)
    refreshGeometry(state)
    refreshRequiredAssets(state)
    buildStars(state)
    resetPlayer(state)

    return state
end

function game.create()
    math.randomseed(os.time())
    return createState()
end

function game.wakeup(state)
    if not state then return end

    flushPendingFormClear(state)
    refreshGeometry(state)

    if not state.stars then
        buildStars(state)
    end
    refreshRequiredAssets(state)

    if not state.moveSourceX then
        state.moveSourceX = resolveSource(MOVE_X_SOURCE_CANDIDATES, MOVE_X_SOURCE_PREFERRED)
    end
    if not state.moveSourceY then
        state.moveSourceY = resolveSource(MOVE_Y_SOURCE_CANDIDATES, MOVE_Y_SOURCE_PREFERRED)
    end
    if not state.fireSource then
        state.fireSource = resolveSource(FIRE_SOURCE_CANDIDATES, FIRE_SOURCE_PREFERRED)
    end

    if state.settingsFormOpen then
        return
    end

    keepScreenAwake(state)
    requestTimedInvalidate(state)
end

function game.event(state, category, value)
    if not state then return false end

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

    flushPendingFormClear(state)
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
