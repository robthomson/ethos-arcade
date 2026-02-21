local game = {}

local DEBUG_EVENTS = false

local MOVE_X_SOURCE_MEMBER = 3
local MOVE_Y_SOURCE_MEMBER = 1

local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local CONFIG_FILE = "luafrog.cfg"
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

local GRID_COLS = 13
local GRID_ROWS = 11
local HOME_SLOT_COLS = {2, 4, 7, 10, 12}
local START_COL = math.floor((GRID_COLS + 1) * 0.5)
local START_ROW = GRID_ROWS

local ACTIVE_RENDER_FPS = 40
local IDLE_RENDER_FPS = 12
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.60
local FRAME_SCALE_MAX = 1.90
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local STICK_SOURCE_IS_PERCENT = false
local STICK_RAW_ABS_LIMIT = 5000
local STICK_GLITCH_DELTA_LIMIT = 1900
local ANALOG_DIRECTION_THRESHOLD = 340
local MOVE_COOLDOWN = 0.11

local SCORE_STEP_UP = 1
local SCORE_HOME = 60
local SCORE_LEVEL_CLEAR = 140

local ROAD_HIT_MARGIN = 0.36

local DIFFICULTY_PROFILES = {
    [DIFFICULTY_EASY] = {speedMul = 0.86, lives = 4, levelStep = 0.055},
    [DIFFICULTY_NORMAL] = {speedMul = 1.00, lives = 3, levelStep = 0.070},
    [DIFFICULTY_HARD] = {speedMul = 1.13, lives = 3, levelStep = 0.085}
}

local LANE_TEMPLATES = {
    {row = 2, kind = "river", dir = 1, speed = 1.05, entities = {
        {x = -0.9, len = 4, color = 1},
        {x = 4.7, len = 3, color = 1},
        {x = 10.6, len = 4, color = 1}
    }},
    {row = 3, kind = "river", dir = -1, speed = 1.25, entities = {
        {x = 1.6, len = 3, color = 2},
        {x = 7.8, len = 4, color = 2}
    }},
    {row = 4, kind = "river", dir = 1, speed = 1.50, entities = {
        {x = -0.3, len = 2, color = 3},
        {x = 3.8, len = 2, color = 3},
        {x = 8.2, len = 2, color = 3},
        {x = 12.0, len = 2, color = 3}
    }},
    {row = 6, kind = "road", dir = -1, speed = 1.35, entities = {
        {x = 1.2, len = 2, color = 1},
        {x = 5.3, len = 2, color = 2},
        {x = 10.0, len = 2, color = 3}
    }},
    {row = 7, kind = "road", dir = 1, speed = 1.65, entities = {
        {x = -0.8, len = 3, color = 2},
        {x = 5.4, len = 3, color = 1},
        {x = 12.2, len = 3, color = 3}
    }},
    {row = 8, kind = "road", dir = -1, speed = 1.85, entities = {
        {x = 2.0, len = 2, color = 3},
        {x = 7.0, len = 2, color = 1},
        {x = 11.8, len = 2, color = 2}
    }},
    {row = 9, kind = "road", dir = 1, speed = 2.10, entities = {
        {x = -0.4, len = 2, color = 2},
        {x = 3.6, len = 2, color = 3},
        {x = 8.1, len = 2, color = 1},
        {x = 12.7, len = 2, color = 2}
    }}
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

local function isExitKeyEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end
    return value == 35
end

local function isPageKeyEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end
    return value == 96
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

local function debugEvent(state, category, value)
    if not DEBUG_EVENTS then
        return
    end

    local now = nowSeconds()
    local suppressLeft = 0
    if state and state.suppressExitUntil and now < state.suppressExitUntil then
        suppressLeft = state.suppressExitUntil - now
    end

    local keyCat = isKeyCategory(category)
    local isExit = isExitKeyEvent(category, value)
    local isClose = (type(EVT_CLOSE) == "number" and category == EVT_CLOSE)

    print(string.format(
        "[luafrog event] cat=%s val=%s key=%s exit=%s close=%s running=%s settings=%s suppress=%.3f",
        tostring(category),
        tostring(value),
        tostring(keyCat),
        tostring(isExit),
        tostring(isClose),
        tostring(state and state.running),
        tostring(state and state.settingsFormOpen),
        suppressLeft
    ))
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
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/luafrog/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/luafrog/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/ethos-arcade/games/luafrog/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/luafrog/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/luafrog/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/luafrog/" .. CONFIG_FILE
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
    local best = tonumber(values.bestScore)
    if best then
        best = math.max(0, math.floor(best))
    else
        best = nil
    end

    local config = {
        difficulty = normalizeDifficulty(values.difficulty)
    }

    return config, best
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
    killPendingKeyEvents(KEY_EXIT_BREAK)
    killPendingKeyEvents(KEY_EXIT_FIRST)
    killPendingKeyEvents(KEY_EXIT_LONG)
    killPendingKeyEvents(KEY_RTN_BREAK)
    killPendingKeyEvents(KEY_RTN_FIRST)
    killPendingKeyEvents(KEY_RTN_LONG)
    killPendingKeyEvents(KEY_BACK_BREAK)
    killPendingKeyEvents(KEY_BACK_FIRST)
    killPendingKeyEvents(KEY_BACK_LONG)
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

    state.hudH = 24
    state.playY = state.hudH + 2

    local boardWAvail = math.max(120, width - 8)
    state.cellW = math.max(12, math.floor(boardWAvail / GRID_COLS))
    state.boardW = state.cellW * GRID_COLS
    state.boardX = math.floor((width - state.boardW) * 0.5)

    local boardHAvail = math.max(120, height - state.playY - 2)
    state.rowH = math.max(12, math.floor(boardHAvail / GRID_ROWS))
    state.boardH = state.rowH * GRID_ROWS
    state.boardY = height - state.boardH - 2

    if state.frogXFloat then
        state.frogXFloat = clamp(state.frogXFloat, 1, GRID_COLS)
        state.frogCol = clamp(math.floor(state.frogXFloat + 0.5), 1, GRID_COLS)
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

    local infoLine = form.addLine("LuaFrog")
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

local function buildLanes(state)
    state.lanes = {}
    state.laneByRow = {}

    local profile = state.profile or DIFFICULTY_PROFILES[DIFFICULTY_NORMAL]
    local levelScale = 1 + ((math.max(1, state.level) - 1) * profile.levelStep)
    local speedScale = profile.speedMul * levelScale

    for i = 1, #LANE_TEMPLATES do
        local template = LANE_TEMPLATES[i]
        local lane = {
            row = template.row,
            kind = template.kind,
            dir = template.dir,
            speed = template.speed * speedScale,
            entities = {}
        }

        for j = 1, #template.entities do
            local e = template.entities[j]
            lane.entities[#lane.entities + 1] = {
                x = e.x,
                len = e.len,
                color = e.color
            }
        end

        state.lanes[#state.lanes + 1] = lane
        state.laneByRow[lane.row] = lane
    end
end

local function resetFrog(state)
    state.frogCol = START_COL
    state.frogRow = START_ROW
    state.frogXFloat = state.frogCol
    state.moveCooldown = 0.16
    state.highestRowReached = START_ROW
end

local function allHomesFilled(state)
    for i = 1, #HOME_SLOT_COLS do
        if not state.homesFilled[i] then
            return false
        end
    end
    return true
end

local function finishGame(state)
    state.running = false
    state.gameOver = true
    state.lastResult = state.score

    if state.bestScore == nil or state.score > state.bestScore then
        state.bestScore = state.score
        state.isNewBest = true
        saveStateConfig(state)
        playTone(1240, 120, 30)
    else
        state.isNewBest = false
        playTone(300, 170, 25)
    end
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

    playTone(260, 80, 10)
    resetFrog(state)
end

local function finishHome(state)
    state.score = state.score + SCORE_LEVEL_CLEAR + (state.level * 10)
    state.level = state.level + 1
    state.homesFilled = {}
    buildLanes(state)
    playTone(1450, 90, 35)
    resetFrog(state)
end

local function nearestHomeSlotIndex(x)
    local bestIndex = nil
    local bestDist = 10
    for i = 1, #HOME_SLOT_COLS do
        local dist = math.abs(x - HOME_SLOT_COLS[i])
        if dist < bestDist then
            bestDist = dist
            bestIndex = i
        end
    end
    if bestDist <= 0.66 then
        return bestIndex
    end
    return nil
end

local function handleHomeRow(state)
    if state.frogRow ~= 1 then
        return
    end

    local slotIndex = nearestHomeSlotIndex(state.frogXFloat)
    if not slotIndex then
        loseLife(state)
        return
    end
    if state.homesFilled[slotIndex] then
        loseLife(state)
        return
    end

    state.homesFilled[slotIndex] = true
    state.score = state.score + SCORE_HOME + (state.level * 6)
    playTone(960, 30, 0)

    if allHomesFilled(state) then
        finishHome(state)
        return
    end

    resetFrog(state)
end

local function attemptMove(state, dx, dy)
    if not state.running then
        return false
    end

    local newCol = clamp(state.frogCol + dx, 1, GRID_COLS)
    local newRow = clamp(state.frogRow + dy, 1, GRID_ROWS)
    if newCol == state.frogCol and newRow == state.frogRow then
        return false
    end

    state.frogCol = newCol
    state.frogRow = newRow
    state.frogXFloat = state.frogCol

    if dy < 0 and newRow < (state.highestRowReached or START_ROW) then
        state.highestRowReached = newRow
        state.score = state.score + SCORE_STEP_UP
    end

    playTone(760, 12, 0)

    if state.frogRow == 1 then
        handleHomeRow(state)
    end

    return true
end

local function laneEntityAtX(lane, x, hitMargin)
    if not lane then
        return nil
    end
    hitMargin = math.max(0, tonumber(hitMargin) or 0)
    for i = 1, #lane.entities do
        local e = lane.entities[i]
        local left = e.x + hitMargin
        local right = (e.x + e.len) - hitMargin - 0.02
        if x >= left and x <= right then
            return e
        end
    end
    return nil
end

local function clipRectX(leftX, rightX, x, w)
    if w <= 0 then
        return x, 0
    end
    if x < leftX then
        w = w - (leftX - x)
        x = leftX
    end
    local endX = x + w
    if endX > rightX then
        w = rightX - x
    end
    return x, w
end

local function updateLanes(state, dt)
    for i = 1, #state.lanes do
        local lane = state.lanes[i]
        local delta = lane.dir * lane.speed * dt
        for j = 1, #lane.entities do
            local e = lane.entities[j]
            e.x = e.x + delta
            if lane.dir > 0 then
                if e.x > GRID_COLS + 1 then
                    e.x = -e.len
                end
            else
                if e.x + e.len < 0 then
                    e.x = GRID_COLS + 1
                end
            end
        end
    end
end

local function updateAnalogInput(state, dt)
    if not state.running then
        return
    end

    state.moveCooldown = math.max(0, (state.moveCooldown or 0) - (dt or 0))

    local rawX = sanitizeStickSample(state, sourceValue(state.moveSourceX), "moveX")
    local rawY = sanitizeStickSample(state, sourceValue(state.moveSourceY), "moveY")

    local absX = math.abs(rawX)
    local absY = math.abs(rawY)
    if absX < ANALOG_DIRECTION_THRESHOLD and absY < ANALOG_DIRECTION_THRESHOLD then
        return
    end
    if state.moveCooldown > 0 then
        return
    end

    if absX >= absY then
        if rawX > 0 then
            attemptMove(state, 1, 0)
        else
            attemptMove(state, -1, 0)
        end
    else
        if rawY > 0 then
            attemptMove(state, 0, -1)
        else
            attemptMove(state, 0, 1)
        end
    end

    state.moveCooldown = MOVE_COOLDOWN
end

local function updateRoadCollision(state)
    if state.frogRow < 6 or state.frogRow > 9 then
        return
    end

    local lane = state.laneByRow[state.frogRow]
    if not lane then
        return
    end

    local hit = laneEntityAtX(lane, state.frogXFloat, ROAD_HIT_MARGIN)
    if hit then
        loseLife(state)
    end
end

local function updateRiverState(state, dt)
    if state.frogRow < 2 or state.frogRow > 4 then
        return
    end

    local lane = state.laneByRow[state.frogRow]
    if not lane then
        return
    end

    local carrier = laneEntityAtX(lane, state.frogXFloat, 0)
    if not carrier then
        loseLife(state)
        return
    end

    state.frogXFloat = state.frogXFloat + (lane.dir * lane.speed * dt)
    if state.frogXFloat < 1 or state.frogXFloat > GRID_COLS then
        loseLife(state)
        return
    end

    state.frogCol = clamp(math.floor(state.frogXFloat + 0.5), 1, GRID_COLS)
end

local function startGame(state)
    state.running = true
    state.gameOver = false
    state.lastResult = nil
    state.isNewBest = false
    state.score = 0
    state.level = 1
    state.homesFilled = {}
    state.moveCooldown = 0
    state.lastRawInputByAxis = {}

    local profile = state.profile or DIFFICULTY_PROFILES[DIFFICULTY_NORMAL]
    state.lives = profile.lives

    buildLanes(state)
    resetFrog(state)
    forceInvalidate(state)
end

local function stopRound(state, keepResult)
    state.running = false
    state.gameOver = false
    -- Exit key can be followed by an EVT_CLOSE on release; consume the next close so we land on overlay.
    state.swallowCloseOnce = true

    if not keepResult then
        state.lastResult = nil
        state.isNewBest = false
    end

    resetFrog(state)
end

local function updateGame(state, dt)
    if not state.running then
        return
    end

    updateAnalogInput(state, dt)
    updateLanes(state, dt)
    if not state.running then
        return
    end

    if state.frogRow == 1 then
        handleHomeRow(state)
        return
    end

    updateRoadCollision(state)
    if not state.running then
        return
    end

    updateRiverState(state, dt)
end

local function gridCellToPixel(state, x, y)
    local px = state.boardX + math.floor((x - 1) * state.cellW)
    local py = state.boardY + math.floor((y - 1) * state.rowH)
    return px, py
end

local function drawBoardBackground(state)
    setColor(5, 10, 16)
    lcd.drawFilledRectangle(0, 0, state.width, state.height)

    for row = 1, GRID_ROWS do
        local y = state.boardY + ((row - 1) * state.rowH)
        if row == 1 then
            setColor(18, 58, 28)
        elseif row >= 2 and row <= 4 then
            setColor(14, 42, 72)
        elseif row == 5 or row == 10 or row == 11 then
            setColor(34, 74, 44)
        else
            setColor(42, 42, 48)
        end
        lcd.drawFilledRectangle(state.boardX, y, state.boardW, state.rowH)

        setColor(10, 16, 22)
        lcd.drawLine(state.boardX, y, state.boardX + state.boardW - 1, y)
    end

    setColor(96, 116, 132)
    lcd.drawRectangle(state.boardX, state.boardY, state.boardW, state.boardH, 1)
end

local function drawHomeSlots(state)
    local slotY = state.boardY + math.floor(state.rowH * 0.16)
    local slotH = math.max(6, math.floor(state.rowH * 0.66))
    local slotW = math.max(6, math.floor(state.cellW * 0.58))

    for i = 1, #HOME_SLOT_COLS do
        local col = HOME_SLOT_COLS[i]
        local cx, _ = gridCellToPixel(state, col, 1)
        local sx = cx + math.floor((state.cellW - slotW) * 0.5)

        if state.homesFilled[i] then
            setColor(126, 232, 114)
            lcd.drawFilledRectangle(sx, slotY, slotW, slotH)
            setColor(34, 92, 34)
            lcd.drawRectangle(sx, slotY, slotW, slotH, 1)
        else
            setColor(6, 24, 12)
            lcd.drawFilledRectangle(sx, slotY, slotW, slotH)
            setColor(54, 114, 66)
            lcd.drawRectangle(sx, slotY, slotW, slotH, 1)
        end
    end
end

local function drawRiverLogs(state, lane, e)
    local y = state.boardY + ((lane.row - 1) * state.rowH)
    local px = state.boardX + math.floor((e.x - 1) * state.cellW + 0.5)
    local pw = math.max(4, math.floor(e.len * state.cellW))
    local py = y + math.floor(state.rowH * 0.18)
    local ph = math.max(6, math.floor(state.rowH * 0.64))

    px, pw = clipRectX(state.boardX, state.boardX + state.boardW, px, pw)
    if pw <= 0 then
        return
    end

    if e.color == 2 then
        setColor(138, 102, 68)
    elseif e.color == 3 then
        setColor(126, 92, 58)
    else
        setColor(146, 108, 72)
    end
    lcd.drawFilledRectangle(px, py, pw, ph)

    setColor(84, 56, 32)
    lcd.drawRectangle(px, py, pw, ph, 1)
end

local function drawRoadVehicle(state, lane, e)
    local y = state.boardY + ((lane.row - 1) * state.rowH)
    local px = state.boardX + math.floor((e.x - 1) * state.cellW + 0.5)
    local pw = math.max(4, math.floor(e.len * state.cellW))
    local py = y + math.floor(state.rowH * 0.22)
    local ph = math.max(6, math.floor(state.rowH * 0.56))

    px, pw = clipRectX(state.boardX, state.boardX + state.boardW, px, pw)
    if pw <= 0 then
        return
    end

    if e.color == 2 then
        setColor(228, 174, 70)
    elseif e.color == 3 then
        setColor(84, 188, 222)
    else
        setColor(232, 90, 90)
    end
    lcd.drawFilledRectangle(px, py, pw, ph)

    setColor(18, 24, 32)
    lcd.drawRectangle(px, py, pw, ph, 1)

    local cabinW = math.max(2, math.floor(pw * 0.33))
    local cabinH = math.max(2, math.floor(ph * 0.40))
    local cabinX = lane.dir > 0 and (px + pw - cabinW - 2) or (px + 2)
    local cabinY = py + 1
    if cabinW > (pw - 2) then
        cabinW = math.max(1, pw - 2)
    end
    cabinX, cabinW = clipRectX(px, px + pw, cabinX, cabinW)
    if cabinW <= 0 then
        return
    end
    setColor(214, 232, 246)
    lcd.drawFilledRectangle(cabinX, cabinY, cabinW, cabinH)
end

local function drawLaneEntities(state)
    for i = 1, #state.lanes do
        local lane = state.lanes[i]
        for j = 1, #lane.entities do
            local e = lane.entities[j]
            if lane.kind == "river" then
                drawRiverLogs(state, lane, e)
            else
                drawRoadVehicle(state, lane, e)
            end
        end
    end
end

local function drawFrog(state)
    local frogW = math.max(8, math.floor(state.cellW * 0.58))
    local frogH = math.max(8, math.floor(state.rowH * 0.58))
    local centerX = state.boardX + ((state.frogXFloat - 0.5) * state.cellW)
    local y = state.boardY + ((state.frogRow - 1) * state.rowH)
    local px = math.floor(centerX - (frogW * 0.5))
    local py = y + math.floor((state.rowH - frogH) * 0.5)

    setColor(102, 240, 88)
    lcd.drawFilledRectangle(px, py, frogW, frogH)
    setColor(28, 88, 34)
    lcd.drawRectangle(px, py, frogW, frogH, 1)

    setColor(18, 18, 18)
    local eyeY = py + math.max(1, math.floor(frogH * 0.20))
    lcd.drawFilledRectangle(px + math.max(1, math.floor(frogW * 0.22)), eyeY, 2, 2)
    lcd.drawFilledRectangle(px + frogW - math.max(3, math.floor(frogW * 0.22)), eyeY, 2, 2)
end

local function drawHud(state)
    setColor(8, 16, 24)
    lcd.drawFilledRectangle(0, 0, state.width, state.hudH)
    setColor(74, 100, 122)
    lcd.drawLine(0, state.hudH - 1, state.width - 1, state.hudH - 1)

    setFont(FONT_XXS or FONT_STD)
    setColor(230, 244, 252)
    lcd.drawText(4, 3, string.format("Score %d", state.score))
    lcd.drawText(94, 3, string.format("Level %d", state.level))
    lcd.drawText(170, 3, string.format("Lives %d", state.lives))

    if state.bestScore ~= nil then
        lcd.drawText(250, 3, string.format("Best %d", state.bestScore))
    end

    lcd.drawText(state.width - 108, 3, "LuaFrog")
    setColor(160, 188, 210)
    lcd.drawText(4, 13, "Diff " .. difficultyLabel(state.config.difficulty))
end

local function drawOverlay(state)
    local boxW = math.floor(state.width * 0.76)
    local boxH = math.floor(state.height * 0.56)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(6, 14, 24)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(124, 154, 186)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(246, 252, 255)
    drawCenteredText(boxX, boxY + 8, boxW, 24, "LuaFrog")

    setFont(FONT_XXS or FONT_STD)
    setColor(188, 210, 232)

    if state.gameOver then
        drawCenteredText(boxX, boxY + 34, boxW, 18, "Out of lives")
        drawCenteredText(boxX, boxY + 50, boxW, 18, string.format("Result: %d", state.lastResult or 0))
        if state.isNewBest then
            drawCenteredText(boxX, boxY + 66, boxW, 18, "New best score!")
        elseif state.bestScore ~= nil then
            drawCenteredText(boxX, boxY + 66, boxW, 18, string.format("Best: %d", state.bestScore))
        end
    else
        drawCenteredText(boxX, boxY + 34, boxW, 18, "Cross roads and river, fill all homes")
    end

    drawCenteredText(boxX, boxY + 88, boxW, 18, "Aileron / Elevator moves one step")
    drawCenteredText(boxX, boxY + 106, boxW, 18, "Press Enter to start")
    drawCenteredText(boxX, boxY + 124, boxW, 18, "Long Page for settings")
end

local function render(state)
    drawBoardBackground(state)
    drawHomeSlots(state)
    drawLaneEntities(state)
    drawFrog(state)
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
        hudH = 24,
        playY = 26,
        boardX = 0,
        boardY = 0,
        boardW = 0,
        boardH = 0,
        cellW = 24,
        rowH = 22,

        config = config,
        profile = DIFFICULTY_PROFILES[DIFFICULTY_NORMAL],
        bestScore = bestScore,
        lastResult = nil,
        isNewBest = false,

        running = false,
        gameOver = false,
        score = 0,
        level = 1,
        lives = 3,
        homesFilled = {},

        frogCol = START_COL,
        frogRow = START_ROW,
        frogXFloat = START_COL,
        highestRowReached = START_ROW,
        moveCooldown = 0,

        lanes = {},
        laneByRow = {},

        moveSourceX = resolveAnalogSource(MOVE_X_SOURCE_MEMBER),
        moveSourceY = resolveAnalogSource(MOVE_Y_SOURCE_MEMBER),
        lastRawInputByAxis = {},

	        frameScale = 1,
	        lastFrameTime = 0,
	        nextInvalidateAt = 0,
	        lastFocusKick = 0,

	        swallowCloseOnce = false,
	        settingsFormOpen = false,
	        pendingFormClear = false,
	        suppressExitUntil = 0,
	        suppressEnterUntil = 0
	    }

    applyConfigSideEffects(state)
    refreshGeometry(state)
    buildLanes(state)
    resetFrog(state)

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

    if not state.moveSourceX then
        state.moveSourceX = resolveAnalogSource(MOVE_X_SOURCE_MEMBER)
    end
    if not state.moveSourceY then
        state.moveSourceY = resolveAnalogSource(MOVE_Y_SOURCE_MEMBER)
    end

    if state.settingsFormOpen then
        return
    end

    keepScreenAwake(state)
    requestTimedInvalidate(state)
end

function game.event(state, category, value)
    if not state then return false end

    debugEvent(state, category, value)

    if not state.settingsFormOpen and isKeyCategory(category) and state.running then
        if value == 96 then
            resetFrog(state)
            forceInvalidate(state)
            return true
        end
        if value == 35 then
            stopRound(state, false)
            forceInvalidate(state)
            return true
        end
    end

    if state.swallowCloseOnce and category == EVT_CLOSE then
        state.swallowCloseOnce = false
        return true
    end

    local now = nowSeconds()
    if state.suppressExitUntil and now < state.suppressExitUntil then
        if category == EVT_CLOSE then
            return state.running and true or false
        end
        if isExitKeyEvent(category, value) then
            -- If we're already on the overlay (not running), allow Exit to bubble up to the arcade menu.
            return state.running and true or false
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
        if isKeyCategory(category) and value == 35 then
            closeSettingsForm(state)
            return true
        end
        return false
    end

    if category == EVT_CLOSE then
        if state.running then
            stopRound(state, false)
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

        if isKeyCategory(category) and value == 35 then
            return false
        end

        return true
    end

    if isSettingsOpenEvent(category, value) then
        return true
    end

    if keyMatches(value, KEY_UP_FIRST, KEY_UP_BREAK) then
        attemptMove(state, 0, -1)
        return true
    end
    if keyMatches(value, KEY_DOWN_FIRST, KEY_DOWN_BREAK) then
        attemptMove(state, 0, 1)
        return true
    end
    if keyMatches(value, KEY_LEFT_FIRST, KEY_LEFT_BREAK) then
        attemptMove(state, -1, 0)
        return true
    end
    if keyMatches(value, KEY_RIGHT_FIRST, KEY_RIGHT_BREAK) then
        attemptMove(state, 1, 0)
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
    if collectgarbage then
        pcall(collectgarbage, "collect")
        pcall(collectgarbage, "collect")
    end
end

return game
