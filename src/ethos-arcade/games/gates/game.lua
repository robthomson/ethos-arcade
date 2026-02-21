local game = {}

local ROLL_SOURCE_MEMBER = 3
local PITCH_SOURCE_MEMBER = 1
local THROTTLE_SOURCE_MEMBER = 2

local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local CONFIG_FILE = "gates.cfg"
local CONFIG_VERSION = 1

local ACTIVE_RENDER_FPS = 45
local ACTIVE_RENDER_FPS_PERF = 24
local IDLE_RENDER_FPS = 12
local GAME_SPEED_MULTIPLIER = 1.00
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.60
local FRAME_SCALE_MAX = 1.90
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local ACTIVE_INVALIDATE_DT_PERF = 1 / ACTIVE_RENDER_FPS_PERF
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local DIFFICULTY_EASY = "easy"
local DIFFICULTY_NORMAL = "normal"
local DIFFICULTY_HARD = "hard"

local DIFFICULTY_CHOICE_EASY = 1
local DIFFICULTY_CHOICE_NORMAL = 2
local DIFFICULTY_CHOICE_HARD = 3

local RACE_TIME_CHOICES = {20, 30, 45, 60}
local OBJECTS_AHEAD_CHOICES = {2, 3, 4, 5}

local DIFFICULTY_CHOICES_FORM = {
    {"Easy", DIFFICULTY_CHOICE_EASY},
    {"Normal", DIFFICULTY_CHOICE_NORMAL},
    {"Hard", DIFFICULTY_CHOICE_HARD}
}

local RACE_TIME_CHOICES_FORM = {
    {"20 sec", 20},
    {"30 sec", 30},
    {"45 sec", 45},
    {"60 sec", 60}
}

local OBJECTS_AHEAD_CHOICES_FORM = {
    {"2", 2},
    {"3", 3},
    {"4", 4},
    {"5", 5}
}

local DIFFICULTY_PROFILES = {
    [DIFFICULTY_EASY] = {
        trackW = 62,
        trackH = 92,
        gateW = 42,
        gateH = 40,
        zStep = 1400,
        minSpeed = 2.6,
        rollScale = 54,
        pitchScale = 11,
        throttleScale = 72
    },
    [DIFFICULTY_NORMAL] = {
        trackW = 52,
        trackH = 84,
        gateW = 36,
        gateH = 34,
        zStep = 1200,
        minSpeed = 2.9,
        rollScale = 46,
        pitchScale = 9,
        throttleScale = 62
    },
    [DIFFICULTY_HARD] = {
        trackW = 44,
        trackH = 76,
        gateW = 31,
        gateH = 30,
        zStep = 980,
        minSpeed = 3.1,
        rollScale = 38,
        pitchScale = 7,
        throttleScale = 52
    }
}

local STICK_SOURCE_IS_PERCENT = false
local STICK_RAW_ABS_LIMIT = 5000
local STICK_GLITCH_DELTA_LIMIT = 1900
local INPUT_DEADZONE = 0.08

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function boolValue(v, default)
    if v == nil then return default end
    if v == true or v == 1 or v == "1" or v == "true" then return true end
    if v == false or v == 0 or v == "0" or v == "false" then return false end
    return default
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

local function normalizeDifficulty(value)
    if value == DIFFICULTY_EASY then
        return DIFFICULTY_EASY
    end
    if value == DIFFICULTY_HARD then
        return DIFFICULTY_HARD
    end
    return DIFFICULTY_NORMAL
end

local function normalizeRaceTime(value)
    local numeric = tonumber(value)
    for _, choice in ipairs(RACE_TIME_CHOICES) do
        if numeric == choice then
            return choice
        end
    end
    return 30
end

local function normalizeObjectsAhead(value)
    local numeric = tonumber(value)
    for _, choice in ipairs(OBJECTS_AHEAD_CHOICES) do
        if numeric == choice then
            return choice
        end
    end
    return 3
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

local function configPathCandidates()
    local paths = {}
    if SCRIPT_DIR ~= "" then
        paths[#paths + 1] = SCRIPT_DIR .. CONFIG_FILE
    end
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/gates/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/gates/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/ethos-arcade/games/gates/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/gates/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/gates/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/gates/" .. CONFIG_FILE
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
        raceTime = normalizeRaceTime(values.raceTime),
        objectsAhead = normalizeObjectsAhead(values.objectsAhead),
        showMarker = boolValue(values.showMarker, true),
        performance = boolValue(values.performance, false)
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
    f:write("raceTime=", normalizeRaceTime(state.config.raceTime), "\n")
    f:write("objectsAhead=", normalizeObjectsAhead(state.config.objectsAhead), "\n")
    f:write("showMarker=", state.config.showMarker and "1" or "0", "\n")
    f:write("performance=", state.config.performance and "1" or "0", "\n")

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
    if not (system and system.playTone) then
        return
    end
    pcall(system.playTone, freq, duration or 50, pause or 0)
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

local function activeInvalidateInterval(state)
    if state and state.config and state.config.performance then
        return ACTIVE_INVALIDATE_DT_PERF
    end
    return ACTIVE_INVALIDATE_DT
end

local function requestTimedInvalidate(state)
    if not (state and lcd and lcd.invalidate) then
        return
    end

    local now = nowSeconds()
    local interval = state.running and activeInvalidateInterval(state) or IDLE_INVALIDATE_DT

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

local function applyDeadzone(v, deadzoneNorm)
    local absV = math.abs(v)
    local dz = clamp(deadzoneNorm or 0, 0, 0.95) * 1024
    if absV <= dz then
        return 0
    end

    local sign = (v < 0) and -1 or 1
    local scaled = (absV - dz) / (1024 - dz)
    return sign * clamp(scaled * 1024, 0, 1024)
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
    state.horizonY = math.floor(height * 0.52)
    state.zScale = math.max(360, math.floor(width * 2.9))

    if changed then
        forceInvalidate(state)
    end
end

local function applyConfigSideEffects(state)
    if not (state and state.config) then
        return
    end

    state.config.difficulty = normalizeDifficulty(state.config.difficulty)
    state.config.raceTime = normalizeRaceTime(state.config.raceTime)
    state.config.objectsAhead = normalizeObjectsAhead(state.config.objectsAhead)
    state.config.showMarker = state.config.showMarker and true or false
    state.config.performance = state.config.performance and true or false

    local profile = DIFFICULTY_PROFILES[state.config.difficulty] or DIFFICULTY_PROFILES[DIFFICULTY_NORMAL]

    state.track.w = profile.trackW
    state.track.h = profile.trackH
    state.gate.w = profile.gateW
    state.gate.h = profile.gateH
    state.flag.w = math.max(4, math.floor(profile.gateW * 0.20 + 0.5))
    state.flag.h = profile.gateH

    state.zObjectsStep = profile.zStep
    state.minSpeed = profile.minSpeed
    state.rollScale = profile.rollScale
    state.pitchScale = profile.pitchScale
    state.throttleScale = profile.throttleScale

    state.objectsN = state.config.objectsAhead
    state.raceDuration = state.config.raceTime
end

local function resetPreviewScene(state)
    state.drone.x = 0
    state.drone.y = 0
    state.drone.z = 0
    state.speed.x = 0
    state.speed.y = 0
    state.speed.z = 0
    state.objectCounter = 0
    state.objects = {}
    for i = 1, state.objectsN do
        state.objects[i] = {
            x = 0,
            y = 0,
            z = i * state.zObjectsStep,
            t = "gateGround"
        }
    end
end

local function generateObject(state)
    state.objectCounter = state.objectCounter + 1

    local distance = state.objectCounter * state.zObjectsStep
    local object = {
        x = math.random(-state.track.w, state.track.w),
        y = 0,
        z = distance,
        t = "gateGround"
    }

    local typeId = math.random(1, 6)
    if typeId <= 2 then
        object.t = "gateGround"
    elseif typeId <= 4 then
        object.t = "gateAir"
    elseif typeId == 5 then
        object.t = "flagRight"
        object.x = -math.abs(object.x) - state.track.w
    else
        object.t = "flagLeft"
        object.x = math.abs(object.x) + state.track.w
    end

    return object
end

local function rebuildObjectQueue(state)
    state.objectCounter = 0
    state.objects = {}
    for i = 1, state.objectsN do
        state.objects[i] = generateObject(state)
    end
end

local function setConfigValue(state, key, value, skipSave)
    if not (state and state.config) then
        return
    end

    if key == "difficulty" then
        state.config.difficulty = normalizeDifficulty(value)
    elseif key == "raceTime" then
        state.config.raceTime = normalizeRaceTime(value)
    elseif key == "objectsAhead" then
        state.config.objectsAhead = normalizeObjectsAhead(value)
    elseif key == "showMarker" then
        state.config.showMarker = value and true or false
    elseif key == "performance" then
        state.config.performance = value and true or false
    else
        return
    end

    applyConfigSideEffects(state)

    if not state.running then
        resetPreviewScene(state)
        rebuildObjectQueue(state)
    end

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
    if not (form and form.clear and form.addLine and form.addChoiceField and form.addBooleanField) then
        return false
    end

    if not safeFormClear() then
        state.settingsFormOpen = false
        return false
    end
    state.settingsFormOpen = true

    local infoLine = form.addLine("Gates")
    if form.addStaticText then
        form.addStaticText(infoLine, nil, "Settings (Exit/Back to return)")
    end

    local difficultyLine = form.addLine("Difficulty")
    form.addChoiceField(
        difficultyLine,
        nil,
        DIFFICULTY_CHOICES_FORM,
        function()
            return difficultyChoiceValue(state.config.difficulty)
        end,
        function(newValue)
            setConfigValue(state, "difficulty", difficultyFromChoice(newValue))
        end
    )

    local raceTimeLine = form.addLine("Race time")
    form.addChoiceField(
        raceTimeLine,
        nil,
        RACE_TIME_CHOICES_FORM,
        function()
            return normalizeRaceTime(state.config.raceTime)
        end,
        function(newValue)
            setConfigValue(state, "raceTime", newValue)
        end
    )

    local objectsLine = form.addLine("Objects ahead")
    form.addChoiceField(
        objectsLine,
        nil,
        OBJECTS_AHEAD_CHOICES_FORM,
        function()
            return normalizeObjectsAhead(state.config.objectsAhead)
        end,
        function(newValue)
            setConfigValue(state, "objectsAhead", newValue)
        end
    )

    local markerLine = form.addLine("Guidance marker")
    form.addBooleanField(
        markerLine,
        nil,
        function()
            return state.config.showMarker
        end,
        function(newValue)
            setConfigValue(state, "showMarker", newValue)
        end
    )

    local perfLine = form.addLine("Performance mode")
    form.addBooleanField(
        perfLine,
        nil,
        function()
            return state.config.performance
        end,
        function(newValue)
            setConfigValue(state, "performance", newValue)
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

local function startRace(state)
    state.running = true
    state.gameStarted = true
    state.countdown = 3.0
    state.lastCountdownBeep = math.ceil(state.countdown)
    state.showGoTimer = 0
    state.elapsed = 0
    state.score = 0
    state.lastResult = nil
    state.isNewBest = false

    state.drone.x = 0
    state.drone.y = 0
    state.drone.z = 0
    state.speed.x = 0
    state.speed.y = 0
    state.speed.z = 0

    state.lastRawInputByAxis = {}

    rebuildObjectQueue(state)
    forceInvalidate(state)
end

local function finishRace(state)
    state.running = false
    state.lastResult = state.score

    if (state.bestScore == nil) or (state.lastResult > state.bestScore) then
        state.isNewBest = true
        state.bestScore = state.lastResult
        saveStateConfig(state)
        playTone(1250, 120, 30)
    else
        state.isNewBest = false
        if state.lastResult >= 0 then
            playTone(900, 100, 20)
        else
            playTone(320, 150, 20)
        end
    end

    resetPreviewScene(state)
    rebuildObjectQueue(state)
end

local function updateCountdown(state, dt)
    local previous = math.ceil(state.countdown)
    state.countdown = state.countdown - dt
    local current = math.ceil(math.max(0, state.countdown))

    if current < previous and current > 0 then
        playTone(1500, 80, 0)
    end

    if state.countdown <= 0 then
        state.countdown = 0
        state.showGoTimer = 0.7
        playTone(2250, 220, 0)
    end
end

local function updateDrone(state, dt)
    local rollRaw = sanitizeStickSample(state, sourceValue(state.rollSource), "roll")
    local pitchRaw = sanitizeStickSample(state, sourceValue(state.pitchSource), "pitch")
    local throttleRaw = sanitizeStickSample(state, sourceValue(state.throttleSource), "throttle")
    rollRaw = applyDeadzone(rollRaw, INPUT_DEADZONE)
    pitchRaw = applyDeadzone(pitchRaw, INPUT_DEADZONE)
    throttleRaw = applyDeadzone(throttleRaw, INPUT_DEADZONE * 0.65)

    state.speed.x = rollRaw / state.rollScale
    state.speed.z = (pitchRaw / state.pitchScale) + state.minSpeed
    state.speed.y = throttleRaw / state.throttleScale

    if state.speed.z < 0 then
        state.speed.z = 0
    end

    local tick = (dt or 0) * 60

    state.drone.y = state.drone.y - (state.speed.y * tick)
    if state.drone.y >= 0 then
        state.drone.y = 0
        state.speed.z = 0
        state.speed.x = 0
    end

    state.drone.z = state.drone.z + (state.speed.z * tick)
    state.drone.x = state.drone.x + (state.speed.x * tick)

    local xLimit = state.track.w * 3
    state.drone.x = clamp(state.drone.x, -xLimit, xLimit)
    state.drone.y = clamp(state.drone.y, -state.track.h, 0)
end

local function checkObjectPass(state, object)
    local dx = math.abs(object.x - state.drone.x)

    if object.t == "gateGround" then
        return (dx <= state.gate.w * 0.5) and (state.drone.y > -state.gate.h)
    end

    if object.t == "gateAir" then
        return (dx <= state.gate.w * 0.5) and (state.drone.y < -state.gate.h) and (state.drone.y > -2 * state.gate.h)
    end

    if object.t == "flagLeft" then
        return (object.x < state.drone.x) and (state.drone.y > -2 * state.gate.h)
    end

    if object.t == "flagRight" then
        return (object.x > state.drone.x) and (state.drone.y > -2 * state.gate.h)
    end

    return false
end

local function updateObjectPasses(state)
    for i = 1, #state.objects do
        local object = state.objects[i]
        if state.drone.z >= object.z then
            local success = checkObjectPass(state, object)
            if success then
                state.score = state.score + 1
                playTone(1000, 55, 5)
            else
                state.score = state.score - 1
                playTone(500, 140, 20)
            end
            state.objects[i] = generateObject(state)
        end
    end
end

local function updateRace(state, dt)
    if not state.running then
        return
    end

    if state.countdown > 0 then
        updateCountdown(state, dt)
        return
    end

    if state.showGoTimer > 0 then
        state.showGoTimer = math.max(0, state.showGoTimer - dt)
    end

    state.elapsed = state.elapsed + dt
    if state.elapsed >= state.raceDuration then
        finishRace(state)
        return
    end

    updateDrone(state, dt)
    updateObjectPasses(state)
end

local function drawLineClipped(state, x1, y1, x2, y2)
    if not state then
        return
    end

    local w = state.width
    local h = state.height

    if (x1 < 0 and x2 < 0) or (x1 >= w and x2 >= w) then
        return
    end
    if (y1 < 0 and y2 < 0) or (y1 >= h and y2 >= h) then
        return
    end

    x1 = clamp(math.floor(x1 + 0.5), 0, w - 1)
    y1 = clamp(math.floor(y1 + 0.5), 0, h - 1)
    x2 = clamp(math.floor(x2 + 0.5), 0, w - 1)
    y2 = clamp(math.floor(y2 + 0.5), 0, h - 1)

    lcd.drawLine(x1, y1, x2, y2)
end

local function projectPoint(state, x, y, z)
    local zRel = z - state.drone.z
    if zRel <= 1 then
        return nil, nil
    end

    local xRel = x - state.drone.x
    local yRel = y - state.drone.y

    local sx = ((xRel * state.zScale) / zRel) + (state.width * 0.5)
    local sy = ((yRel * state.zScale) / zRel) + state.horizonY
    return sx, sy
end

local function rounded(v)
    return math.floor((tonumber(v) or 0) + 0.5)
end

local function drawFilledTriangleSafe(state, x1, y1, x2, y2, x3, y3)
    if not (state and lcd and lcd.drawFilledTriangle) then
        drawLineClipped(state, x1, y1, x2, y2)
        drawLineClipped(state, x2, y2, x3, y3)
        drawLineClipped(state, x3, y3, x1, y1)
        return
    end

    local w = state.width
    local h = state.height

    local ok = pcall(
        lcd.drawFilledTriangle,
        clamp(rounded(x1), 0, w - 1),
        clamp(rounded(y1), 0, h - 1),
        clamp(rounded(x2), 0, w - 1),
        clamp(rounded(y2), 0, h - 1),
        clamp(rounded(x3), 0, w - 1),
        clamp(rounded(y3), 0, h - 1)
    )

    if not ok then
        drawLineClipped(state, x1, y1, x2, y2)
        drawLineClipped(state, x2, y2, x3, y3)
        drawLineClipped(state, x3, y3, x1, y1)
    end
end

local function drawQuadFilled(state, x1, y1, x2, y2, x3, y3, x4, y4)
    drawFilledTriangleSafe(state, x1, y1, x2, y2, x3, y3)
    drawFilledTriangleSafe(state, x1, y1, x3, y3, x4, y4)
end

local function drawThickSegment(state, x1, y1, x2, y2, thickness)
    if not (x1 and y1 and x2 and y2) then
        return
    end

    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt((dx * dx) + (dy * dy))
    local half = math.max(0.8, (thickness or 2.0) * 0.5)

    if length < 0.001 then
        if lcd and lcd.drawFilledRectangle then
            local x = rounded(x1 - half)
            local y = rounded(y1 - half)
            local s = math.max(1, rounded(half * 2))
            lcd.drawFilledRectangle(x, y, s, s)
        else
            drawLineClipped(state, x1, y1, x1, y1)
        end
        return
    end

    local nx = -dy / length
    local ny = dx / length
    local hx = nx * half
    local hy = ny * half

    drawQuadFilled(
        state,
        x1 - hx, y1 - hy,
        x1 + hx, y1 + hy,
        x2 + hx, y2 + hy,
        x2 - hx, y2 - hy
    )
end

local function objectDepth(state, z)
    local zRel = math.max(1, z - state.drone.z)
    local span = math.max(1, state.zObjectsStep * (state.objectsN + 0.6))
    local t = clamp(1 - (zRel / span), 0, 1)
    return zRel, t
end

local function segmentThickness(state, z)
    local zRel = objectDepth(state, z)
    return clamp((state.zScale / zRel) * 0.55, 2.0, 14.0)
end

local function setDepthColor(state, z, baseR, baseG, baseB, boost)
    local _, depth = objectDepth(state, z)
    local brightness = 0.40 + (depth * 0.60) + (boost or 0)
    setColor(
        math.floor(baseR * brightness + 0.5),
        math.floor(baseG * brightness + 0.5),
        math.floor(baseB * brightness + 0.5)
    )
end

local function drawMarker(state, x, y)
    local px = clamp(rounded(x), 2, state.width - 3)
    local py = clamp(rounded(y), 2, state.height - 3)

    setColor(250, 245, 120)
    if lcd and lcd.drawFilledRectangle then
        lcd.drawFilledRectangle(px - 2, py - 2, 5, 5)
    else
        lcd.drawLine(px - 1, py - 1, px - 1, py + 1)
        lcd.drawLine(px, py - 1, px, py + 1)
        lcd.drawLine(px + 1, py - 1, px + 1, py + 1)
    end

    setColor(40, 40, 20)
    if lcd and lcd.drawRectangle then
        lcd.drawRectangle(px - 2, py - 2, 5, 5, 1)
    end
end

local function drawObject(state, object, markerFlag)
    local gateW = state.gate.w
    local gateH = state.gate.h
    local flagW = state.flag.w

    if object.t == "gateGround" then
        local xLeftBottom, yBottom = projectPoint(state, object.x - gateW * 0.5, object.y, object.z)
        local xRightBottom, yBottom2 = projectPoint(state, object.x + gateW * 0.5, object.y, object.z)
        local xLeftTop, yTop = projectPoint(state, object.x - gateW * 0.5, object.y - gateH, object.z)
        local xRightTop, yTop2 = projectPoint(state, object.x + gateW * 0.5, object.y - gateH, object.z)

        if xLeftBottom then
            local t = segmentThickness(state, object.z)
            setDepthColor(state, object.z, 86, 210, 222)
            drawThickSegment(state, xLeftBottom, yBottom, xLeftTop, yTop, t)
            drawThickSegment(state, xRightBottom, yBottom2, xRightTop, yTop2, t)
            drawThickSegment(state, xLeftTop, yTop, xRightTop, yTop2, t)

            setDepthColor(state, object.z, 210, 244, 250, 0.12)
            drawLineClipped(state, xLeftBottom, yBottom, xLeftTop, yTop)
            drawLineClipped(state, xRightBottom, yBottom2, xRightTop, yTop2)
            drawLineClipped(state, xLeftTop, yTop, xRightTop, yTop2)
        end

        if markerFlag then
            local xm, ym = projectPoint(state, object.x, object.y - gateH * 0.5, object.z)
            if xm then
                drawMarker(state, xm, ym)
            end
        end
        return
    end

    if object.t == "gateAir" then
        local xLeftBottom, yBottom = projectPoint(state, object.x - gateW * 0.5, object.y, object.z)
        local xRightBottom, yBottom2 = projectPoint(state, object.x + gateW * 0.5, object.y, object.z)
        local xLeftMid, yMid = projectPoint(state, object.x - gateW * 0.5, object.y - gateH, object.z)
        local xRightMid, yMid2 = projectPoint(state, object.x + gateW * 0.5, object.y - gateH, object.z)
        local xLeftTop, yTop = projectPoint(state, object.x - gateW * 0.5, object.y - gateH * 2, object.z)
        local xRightTop, yTop2 = projectPoint(state, object.x + gateW * 0.5, object.y - gateH * 2, object.z)

        if xLeftBottom then
            local t = segmentThickness(state, object.z)
            setDepthColor(state, object.z, 114, 228, 152)
            drawThickSegment(state, xLeftBottom, yBottom, xLeftTop, yTop, t)
            drawThickSegment(state, xRightBottom, yBottom2, xRightTop, yTop2, t)
            drawThickSegment(state, xLeftTop, yTop, xRightTop, yTop2, t)
            drawThickSegment(state, xLeftMid, yMid, xRightMid, yMid2, t)

            setDepthColor(state, object.z, 214, 246, 226, 0.10)
            drawLineClipped(state, xLeftBottom, yBottom, xLeftTop, yTop)
            drawLineClipped(state, xRightBottom, yBottom2, xRightTop, yTop2)
            drawLineClipped(state, xLeftTop, yTop, xRightTop, yTop2)
            drawLineClipped(state, xLeftMid, yMid, xRightMid, yMid2)
        end

        if markerFlag then
            local xm, ym = projectPoint(state, object.x, object.y - gateH * 1.5, object.z)
            if xm then
                drawMarker(state, xm, ym)
            end
        end
        return
    end

    if object.t == "flagLeft" then
        local xLeftMid, yMid = projectPoint(state, object.x - flagW * 0.5, object.y - gateH, object.z)
        local xRightBottom, yBottom = projectPoint(state, object.x + flagW * 0.5, object.y, object.z)
        local xRightTop, yTop = projectPoint(state, object.x + flagW * 0.5, object.y - gateH * 2, object.z)
        local xLeftTop, yTop2 = projectPoint(state, object.x - flagW * 0.5, object.y - gateH * 2, object.z)

        if xLeftMid then
            local t = segmentThickness(state, object.z)
            setDepthColor(state, object.z, 244, 170, 84)
            drawThickSegment(state, xLeftMid, yMid, xLeftTop, yTop2, t)
            drawThickSegment(state, xRightBottom, yBottom, xRightTop, yTop, t)
            drawThickSegment(state, xLeftTop, yTop2, xRightTop, yTop, t)
            drawThickSegment(state, xLeftMid, yMid, xRightBottom, yBottom, t)
            drawFilledTriangleSafe(
                state,
                xRightTop, yTop,
                xRightTop + (t * 2.8), yTop + (t * 0.7),
                xRightTop, yTop + (t * 2.1)
            )

            setDepthColor(state, object.z, 255, 228, 170, 0.12)
            drawLineClipped(state, xLeftMid, yMid, xLeftTop, yTop2)
            drawLineClipped(state, xRightBottom, yBottom, xRightTop, yTop)
            drawLineClipped(state, xLeftTop, yTop2, xRightTop, yTop)
            drawLineClipped(state, xLeftMid, yMid, xRightBottom, yBottom)
        end

        if markerFlag then
            local xm, ym = projectPoint(state, object.x + flagW * 2, object.y - gateH * 1.5, object.z)
            if xm then
                drawMarker(state, xm, ym)
            end
        end
        return
    end

    if object.t == "flagRight" then
        local xLeftBottom, yBottom = projectPoint(state, object.x - flagW * 0.5, object.y, object.z)
        local xLeftTop, yTop = projectPoint(state, object.x - flagW * 0.5, object.y - gateH * 2, object.z)
        local xRightMid, yMid = projectPoint(state, object.x + flagW * 0.5, object.y - gateH, object.z)
        local xRightTop, yTop2 = projectPoint(state, object.x + flagW * 0.5, object.y - gateH * 2, object.z)

        if xLeftBottom then
            local t = segmentThickness(state, object.z)
            setDepthColor(state, object.z, 244, 170, 84)
            drawThickSegment(state, xLeftBottom, yBottom, xLeftTop, yTop, t)
            drawThickSegment(state, xRightMid, yMid, xRightTop, yTop2, t)
            drawThickSegment(state, xLeftTop, yTop, xRightTop, yTop2, t)
            drawThickSegment(state, xLeftBottom, yBottom, xRightMid, yMid, t)
            drawFilledTriangleSafe(
                state,
                xLeftTop, yTop,
                xLeftTop - (t * 2.8), yTop + (t * 0.7),
                xLeftTop, yTop + (t * 2.1)
            )

            setDepthColor(state, object.z, 255, 228, 170, 0.12)
            drawLineClipped(state, xLeftBottom, yBottom, xLeftTop, yTop)
            drawLineClipped(state, xRightMid, yMid, xRightTop, yTop2)
            drawLineClipped(state, xLeftTop, yTop, xRightTop, yTop2)
            drawLineClipped(state, xLeftBottom, yBottom, xRightMid, yMid)
        end

        if markerFlag then
            local xm, ym = projectPoint(state, object.x - flagW * 2, object.y - gateH * 1.5, object.z)
            if xm then
                drawMarker(state, xm, ym)
            end
        end
    end
end

local function drawLandscape(state)
    local z = state.zObjectsStep / 5
    local w = state.track.w * 2

    local yFar = state.horizonY + 1
    local yClose = ((-state.drone.y * state.zScale) / z) + state.horizonY - 1

    local xFarRight = state.width * 0.5 + 1
    local xCloseRight = (((w - state.drone.x) * state.zScale) / z) + state.width * 0.5

    local xFarLeft = state.width * 0.5 - 1
    local xCloseLeft = (((-w - state.drone.x) * state.zScale) / z) + state.width * 0.5

    drawLineClipped(state, xFarRight, yFar, xCloseRight, yClose)
    drawLineClipped(state, xFarLeft, yFar, xCloseLeft, yClose)
    drawLineClipped(state, 0, yFar, state.width - 1, yFar)
end

local function closestObjectIndex(state)
    local closestIndex = nil
    local closestDist = state.drone.z + (state.zObjectsStep * state.objectsN) + state.zObjectsStep

    for i = 1, #state.objects do
        local object = state.objects[i]
        if object.z > state.drone.z and object.z < closestDist then
            closestDist = object.z
            closestIndex = i
        end
    end

    return closestIndex
end

local function drawRaceScene(state)
    local sorted = {}
    for i = 1, #state.objects do
        sorted[i] = i
    end

    table.sort(sorted, function(a, b)
        return state.objects[a].z > state.objects[b].z
    end)

    local closest = closestObjectIndex(state)
    for _, index in ipairs(sorted) do
        local object = state.objects[index]
        if object.z > state.drone.z then
            drawObject(state, object, state.config.showMarker and (index == closest))
        end
    end

    drawLandscape(state)
end

local function drawHud(state)
    local remaining = math.max(0, math.ceil(state.raceDuration - state.elapsed))

    setFont(FONT_S_BOLD or FONT_STD)
    setColor(236, 242, 250)
    lcd.drawText(4, 2, string.format("Score %d", state.score))

    if state.bestScore ~= nil then
        lcd.drawText(4, 22, string.format("Best %d", state.bestScore))
    end

    local timerText = string.format("%02d", remaining)
    local tw, _ = getTextSize(timerText)
    lcd.drawText(state.width - tw - 6, 2, timerText)

    setFont(FONT_XXS or FONT_STD)
    setColor(170, 186, 206)
    lcd.drawText(4, state.height - 18, string.format("SPD %.1f ALT %.1f", state.speed.z, -state.drone.y))
end

local function drawRaceCenterMessages(state)
    if state.countdown > 0 then
        local countText = tostring(math.ceil(state.countdown))
        setFont(FONT_L_BOLD or FONT_STD)
        setColor(246, 248, 255)
        drawCenteredText(0, math.floor(state.height * 0.46), state.width, 28, countText)
        return
    end

    if state.showGoTimer > 0 then
        setFont(FONT_L_BOLD or FONT_STD)
        setColor(246, 248, 255)
        drawCenteredText(0, math.floor(state.height * 0.46), state.width, 28, "GO!")
    end
end

local function drawHomeOverlay(state)
    local boxW = math.floor(state.width * 0.72)
    local boxH = math.floor(state.height * 0.52)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(2, 10, 18)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(122, 154, 188)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(242, 250, 255)
    drawCenteredText(boxX, boxY + 8, boxW, 24, "Gates")

    setFont(FONT_XXS or FONT_STD)
    setColor(188, 210, 232)

    if state.lastResult ~= nil then
        drawCenteredText(boxX, boxY + 36, boxW, 18, string.format("Result: %d", state.lastResult))

        if state.isNewBest then
            drawCenteredText(boxX, boxY + 54, boxW, 18, "New best score!")
        elseif state.bestScore ~= nil then
            drawCenteredText(boxX, boxY + 54, boxW, 18, string.format("Best: %d", state.bestScore))
        end
    else
        drawCenteredText(boxX, boxY + 44, boxW, 18, "Fly through gates and flags")
    end

    drawCenteredText(boxX, boxY + 78, boxW, 18, string.format("Difficulty: %s", difficultyLabel(state.config.difficulty)))
    drawCenteredText(boxX, boxY + 96, boxW, 18, string.format("Race: %ds  Objects: %d", state.raceDuration, state.objectsN))

    drawCenteredText(boxX, boxY + 122, boxW, 18, "Press Enter to start")
    drawCenteredText(boxX, boxY + 140, boxW, 18, "Long Page for settings")
end

local function render(state)
    setColor(3, 9, 16)
    lcd.drawFilledRectangle(0, 0, state.width, state.height)

    setColor(10, 22, 34)
    lcd.drawFilledRectangle(0, state.horizonY + 1, state.width, state.height - state.horizonY - 1)

    setColor(214, 226, 242)
    drawRaceScene(state)

    if state.running then
        drawHud(state)
        drawRaceCenterMessages(state)
    else
        drawHomeOverlay(state)
    end
end

local function stopRaceToMenu(state, keepResult)
    if not state then
        return
    end

    state.running = false
    state.countdown = 0
    state.showGoTimer = 0
    state.elapsed = 0

    if not keepResult then
        state.lastResult = nil
        state.isNewBest = false
    end

    resetPreviewScene(state)
    rebuildObjectQueue(state)
end

local function createState()
    local config, bestScore = loadStateConfig()

    local state = {
        width = 480,
        height = 272,
        horizonY = 141,
        zScale = 1200,

        config = config,
        bestScore = bestScore,
        lastResult = nil,
        isNewBest = false,

        raceDuration = 30,
        objectsN = 3,

        track = {w = 52, h = 84},
        gate = {w = 30, h = 30},
        flag = {w = 6, h = 30},

        zObjectsStep = 1200,
        minSpeed = 3,
        rollScale = 34,
        pitchScale = 6,
        throttleScale = 44,

        drone = {x = 0, y = 0, z = 0},
        speed = {x = 0, y = 0, z = 0},

        running = false,
        gameStarted = false,
        countdown = 0,
        lastCountdownBeep = 0,
        showGoTimer = 0,
        elapsed = 0,
        score = 0,

        objectCounter = 0,
        objects = {},

        rollSource = resolveAnalogSource(ROLL_SOURCE_MEMBER),
        pitchSource = resolveAnalogSource(PITCH_SOURCE_MEMBER),
        throttleSource = resolveAnalogSource(THROTTLE_SOURCE_MEMBER),
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
    resetPreviewScene(state)
    rebuildObjectQueue(state)

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

    if not state.rollSource then
        state.rollSource = resolveAnalogSource(ROLL_SOURCE_MEMBER)
    end
    if not state.pitchSource then
        state.pitchSource = resolveAnalogSource(PITCH_SOURCE_MEMBER)
    end
    if not state.throttleSource then
        state.throttleSource = resolveAnalogSource(THROTTLE_SOURCE_MEMBER)
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
            stopRaceToMenu(state, false)
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
            startRace(state)
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

    if isExitKeyEvent(category, value) then
        stopRaceToMenu(state, false)
        suppressExitEvents(state)
        forceInvalidate(state)
        return true
    end

    if keyMatches(value, KEY_LEFT_FIRST, KEY_LEFT_BREAK, KEY_ROTARY_LEFT) then
        state.drone.x = clamp(state.drone.x - (state.track.w * 0.18), -state.track.w * 3, state.track.w * 3)
        return true
    end

    if keyMatches(value, KEY_RIGHT_FIRST, KEY_RIGHT_BREAK, KEY_ROTARY_RIGHT) then
        state.drone.x = clamp(state.drone.x + (state.track.w * 0.18), -state.track.w * 3, state.track.w * 3)
        return true
    end

    if keyMatches(value, KEY_UP_FIRST, KEY_UP_BREAK) then
        state.drone.y = clamp(state.drone.y - (state.gate.h * 0.22), -state.track.h, 0)
        return true
    end

    if keyMatches(value, KEY_DOWN_FIRST, KEY_DOWN_BREAK) then
        state.drone.y = clamp(state.drone.y + (state.gate.h * 0.22), -state.track.h, 0)
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

    local dt = (FRAME_TARGET_DT * state.frameScale) * GAME_SPEED_MULTIPLIER
    if state.running then
        updateRace(state, dt)
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
    if collectgarbage then
        pcall(collectgarbage, "collect")
        pcall(collectgarbage, "collect")
    end
end

return game
