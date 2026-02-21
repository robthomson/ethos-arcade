local game = {}

local PLAYER_SOURCE_MEMBER = 1
local PLAYER2_SOURCE_MEMBER = 2
local MAX_SCORE = 7
local ACTIVE_RENDER_FPS = 40
local IDLE_RENDER_FPS = 12
local GAME_SPEED_MULTIPLIER = 0.90
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.65
local FRAME_SCALE_MAX = 1.75
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local INPUT_DEADZONE = 0.035
local INPUT_SENSITIVITY = 1.00
local INPUT_FILTER_ALPHA = 0.18
local INPUT_FILTER_ALPHA_FAST = 0.55
local STICK_SOURCE_IS_PERCENT = false
local STICK_RAW_ABS_LIMIT = 5000
local STICK_GLITCH_DELTA_LIMIT = 1900

local MODE_SINGLE = "single"
local MODE_TWO_PLAYER = "two_player"
local DIFFICULTY_EASY = "easy"
local DIFFICULTY_HARD = "hard"
local CONFIG_FILE = "luapong.cfg"
local CONFIG_VERSION = 1
local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local MODE_CHOICE_SINGLE = 1
local MODE_CHOICE_TWO_PLAYER = 2
local DIFFICULTY_CHOICE_EASY = 1
local DIFFICULTY_CHOICE_HARD = 2

local MODE_CHOICES_FORM = {
    {"Single Player", MODE_CHOICE_SINGLE},
    {"Two Player", MODE_CHOICE_TWO_PLAYER}
}

local DIFFICULTY_CHOICES_FORM = {
    {"Easy", DIFFICULTY_CHOICE_EASY},
    {"Hard", DIFFICULTY_CHOICE_HARD}
}

local CONFIG_MENU_ITEMS = {
    {
        key = "mode",
        label = "Mode",
        choices = {
            {label = "Single Player", value = MODE_SINGLE},
            {label = "Two Player", value = MODE_TWO_PLAYER}
        }
    },
    {
        key = "difficulty",
        label = "Difficulty",
        visible = function(state)
            return state.config and state.config.mode == MODE_SINGLE
        end,
        choices = {
            {label = "Easy", value = DIFFICULTY_EASY},
            {label = "Hard", value = DIFFICULTY_HARD}
        }
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
    if isConfigButtonEvent(category, value) then
        return true
    end
    return isKeyCategory(category) and keyMatches(value, KEY_ENTER_LONG)
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
    axisKey = axisKey or "p1"
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

local function applyInputResponse(v)
    local absV = math.abs(v)
    local dz = INPUT_DEADZONE * 1024
    if absV <= dz then
        return 0
    end

    local sign = (v < 0) and -1 or 1
    local norm = (absV - dz) / (1024 - dz)
    local adjusted = norm * (INPUT_SENSITIVITY + (1 - INPUT_SENSITIVITY) * norm)
    return sign * clamp(adjusted * 1024, 0, 1024)
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
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/luapong/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/luapong/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/ethos-arcade/games/luapong/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/luapong/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/luapong/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/luapong/" .. CONFIG_FILE
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

local function normalizeMode(value)
    if value == MODE_TWO_PLAYER then
        return MODE_TWO_PLAYER
    end
    return MODE_SINGLE
end

local function normalizeDifficulty(value)
    if value == DIFFICULTY_HARD then
        return DIFFICULTY_HARD
    end
    return DIFFICULTY_EASY
end

local function modeChoiceValue(mode)
    if normalizeMode(mode) == MODE_TWO_PLAYER then
        return MODE_CHOICE_TWO_PLAYER
    end
    return MODE_CHOICE_SINGLE
end

local function difficultyChoiceValue(difficulty)
    if normalizeDifficulty(difficulty) == DIFFICULTY_HARD then
        return DIFFICULTY_CHOICE_HARD
    end
    return DIFFICULTY_CHOICE_EASY
end

local function loadStateConfig()
    local values = readConfigFile()
    return {
        mode = normalizeMode(values.mode),
        difficulty = normalizeDifficulty(values.difficulty)
    }
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
    f:write("mode=", normalizeMode(state.config.mode), "\n")
    f:write("difficulty=", normalizeDifficulty(state.config.difficulty), "\n")
    f:close()
    return true
end

local function forceInvalidate(state)
    if not state then return end
    state.nextInvalidateAt = 0
    if lcd and lcd.invalidate then
        lcd.invalidate()
    end
end

local function requestTimedInvalidate(state)
    if not (state and lcd and lcd.invalidate) then return end
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
        -- Ignore large gaps (menu pause, tab switch, debugger stop).
        state.frameScale = 1
        return
    end

    state.frameScale = clamp(dt / FRAME_TARGET_DT, FRAME_SCALE_MIN, FRAME_SCALE_MAX)
end

local function setColor(r, g, b)
    if not (lcd and lcd.color and lcd.RGB) then
        return
    end
    pcall(lcd.color, lcd.RGB(r, g, b))
end

local function setFont(font)
    if not (lcd and lcd.font and font) then
        return
    end
    pcall(lcd.font, font)
end

local function playTone(freq, duration, pause)
    if not (system and system.playTone) then
        return
    end
    pcall(system.playTone, freq, duration or 25, pause or 0)
end

local function keepScreenAwake(state)
    if not state then return end
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

local function isTwoPlayerMode(state)
    return state and state.config and state.config.mode == MODE_TWO_PLAYER
end

local function leftPlayerLabel(state)
    if isTwoPlayerMode(state) then
        return "P2"
    end
    return "CPU"
end

local function rightPlayerLabel(state)
    if isTwoPlayerMode(state) then
        return "P1"
    end
    return "YOU"
end

local function modeLabel(state)
    if isTwoPlayerMode(state) then
        return "Two Player"
    end
    return "Single Player"
end

local function difficultyLabel(state)
    if state and state.config and state.config.difficulty == DIFFICULTY_HARD then
        return "Hard"
    end
    return "Easy"
end

local function resetAiBehavior(state)
    if not state then
        return
    end
    state.aiError = 0
    state.aiErrorTarget = 0
    state.aiMistakeTimer = 0
end

local function applyConfigSideEffects(state, key)
    if not (state and state.config) then
        return
    end

    if key == "mode" then
        state.config.mode = normalizeMode(state.config.mode)
        if state.config.mode == MODE_TWO_PLAYER and not state.player2Source then
            state.player2Source = resolveAnalogSource(PLAYER2_SOURCE_MEMBER)
        end
        resetAiBehavior(state)
    elseif key == "difficulty" then
        state.config.difficulty = normalizeDifficulty(state.config.difficulty)
        resetAiBehavior(state)
    end
end

local function setConfigValue(state, key, value, skipSave)
    if not (state and state.config) then
        return
    end

    if key == "mode" then
        state.config.mode = normalizeMode(value)
    elseif key == "difficulty" then
        state.config.difficulty = normalizeDifficulty(value)
    else
        return
    end

    applyConfigSideEffects(state, key)
    if not skipSave then
        saveStateConfig(state)
    end
end

local function aiDifficultyProfile(state)
    if state and state.config and state.config.difficulty == DIFFICULTY_HARD then
        return {
            speedScale = 0.96,
            missChance = 0.18,
            missAmount = 0.42,
            wobbleAmount = 0.10,
            minInterval = 0.20,
            maxInterval = 0.46,
            blendRate = 7.5
        }
    end

    return {
        speedScale = 0.78,
        missChance = 0.42,
        missAmount = 0.95,
        wobbleAmount = 0.24,
        minInterval = 0.12,
        maxInterval = 0.30,
        blendRate = 5.0
    }
end

local function centerBall(state)
    state.ballX = math.floor((state.width - state.ballSize) * 0.5)
    state.ballY = math.floor((state.height - state.ballSize) * 0.5)
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
    state.margin = math.max(8, math.floor(width * 0.04))
    state.paddleW = math.max(5, math.floor(width * 0.022))
    state.paddleH = math.max(24, math.floor(height * 0.22))
    state.ballSize = math.max(5, math.floor(math.min(width, height) * 0.03))
    state.playerX = width - state.margin - state.paddleW
    state.aiX = state.margin
    state.playerSpeed = height * 1.90
    state.aiSpeed = height * 1.45
    state.ballBaseSpeed = width * 1.05
    state.ballMaxSpeed = width * 2.00
    state.maxBounceY = height * 1.20
    state.keyNudge = math.max(6, math.floor(height * 0.06))
    state.playerStepBase = math.max(3.0, height * 0.030)
    state.playerStepExtra = math.max(1.0, height * 0.050)

    if changed then
        if not state.playerY then
            state.playerY = (height - state.paddleH) * 0.5
        end
        if not state.aiY then
            state.aiY = (height - state.paddleH) * 0.5
        end
        state.playerY = clamp(state.playerY, 0, height - state.paddleH)
        state.aiY = clamp(state.aiY, 0, height - state.paddleH)
        centerBall(state)
    end
end

local function resetRound(state, serveDir)
    centerBall(state)
    state.ballVX = 0
    state.ballVY = 0
    state.serveTimer = 0.55
    resetAiBehavior(state)
    if serveDir then
        state.serveDir = serveDir
    else
        state.serveDir = (math.random(0, 1) == 0) and -1 or 1
    end
end

local function startServe(state)
    state.ballVX = state.ballBaseSpeed * state.serveDir
    state.ballVY = (math.random() * 2 - 1) * state.ballBaseSpeed * 0.45
end

local function startMatch(state)
    state.playerScore = 0
    state.aiScore = 0
    state.winner = nil
    state.menuPage = false
    state.running = true
    state.playerY = (state.height - state.paddleH) * 0.5
    state.aiY = (state.height - state.paddleH) * 0.5
    state.filteredInput = nil
    state.filteredInputP2 = nil
    state.lastRawInputByAxis = {}
    resetAiBehavior(state)
    resetRound(state)
end

local function finishMatch(state, winner)
    state.running = false
    state.winner = winner
    state.ballVX = 0
    state.ballVY = 0
    state.serveTimer = 0
    centerBall(state)
    if winner == "player" then
        playTone(1100, 160, 60)
    else
        playTone(220, 160, 60)
    end
end

local function scorePoint(state, scorer)
    if scorer == "player" then
        state.playerScore = state.playerScore + 1
        playTone(1000, 40, 20)
        if state.playerScore >= state.maxScore then
            finishMatch(state, "player")
            return
        end
        resetRound(state, -1)
    else
        state.aiScore = state.aiScore + 1
        playTone(330, 40, 20)
        if state.aiScore >= state.maxScore then
            finishMatch(state, "ai")
            return
        end
        resetRound(state, 1)
    end
end

local function updatePlayerFromStick(state)
    local stick = sanitizeStickSample(state, sourceValue(state.playerSource), "p1")
    local raw = applyInputResponse(stick * -1)

    if state.filteredInput == nil then
        state.filteredInput = raw
    end

    local alpha = INPUT_FILTER_ALPHA + (INPUT_FILTER_ALPHA_FAST - INPUT_FILTER_ALPHA) * (math.abs(raw - state.filteredInput) / 1024)
    state.filteredInput = state.filteredInput + ((raw - state.filteredInput) * alpha)

    local targetY = mapInputToActionAreaPosition(state.filteredInput, 0, state.height - state.paddleH)
    local speedNorm = math.abs(state.filteredInput) / 1024
    local maxStep = (state.playerStepBase + (state.playerStepExtra * speedNorm)) * state.frameScale
    state.playerY = approach(state.playerY, targetY, maxStep)
end

local function updatePlayer2FromStick(state)
    if not state.player2Source then
        return false
    end

    local stick = sanitizeStickSample(state, sourceValue(state.player2Source), "p2")
    local raw = applyInputResponse(stick * -1)

    if state.filteredInputP2 == nil then
        state.filteredInputP2 = raw
    end

    local alpha = INPUT_FILTER_ALPHA + (INPUT_FILTER_ALPHA_FAST - INPUT_FILTER_ALPHA) * (math.abs(raw - state.filteredInputP2) / 1024)
    state.filteredInputP2 = state.filteredInputP2 + ((raw - state.filteredInputP2) * alpha)

    local targetY = mapInputToActionAreaPosition(state.filteredInputP2, 0, state.height - state.paddleH)
    local speedNorm = math.abs(state.filteredInputP2) / 1024
    local maxStep = (state.playerStepBase + (state.playerStepExtra * speedNorm)) * state.frameScale
    state.aiY = approach(state.aiY, targetY, maxStep)
    return true
end

local function updateAiMistake(state, dt, isBallApproaching)
    local profile = aiDifficultyProfile(state)

    state.aiMistakeTimer = (state.aiMistakeTimer or 0) - dt
    if state.aiMistakeTimer <= 0 then
        local intervalScale = isBallApproaching and 1.0 or 1.8
        local interval = profile.minInterval + (math.random() * (profile.maxInterval - profile.minInterval))
        state.aiMistakeTimer = interval * intervalScale

        local missChance = profile.missChance * (isBallApproaching and 1.0 or 0.5)
        local missMagnitude = state.paddleH * profile.missAmount
        local wobbleMagnitude = state.paddleH * profile.wobbleAmount

        if math.random() < missChance then
            state.aiErrorTarget = (math.random() * 2 - 1) * missMagnitude
        else
            state.aiErrorTarget = (math.random() * 2 - 1) * wobbleMagnitude
        end
    end

    local blend = clamp(dt * profile.blendRate, 0, 1)
    state.aiError = (state.aiError or 0) + ((state.aiErrorTarget or 0) - (state.aiError or 0)) * blend
end

local function updateAi(state, dt)
    local profile = aiDifficultyProfile(state)
    local isBallApproaching = (state.ballVX < 0)

    local targetY
    if isBallApproaching then
        targetY = (state.ballY + state.ballSize * 0.5) - (state.paddleH * 0.5)
    else
        targetY = (state.height - state.paddleH) * 0.5
    end

    updateAiMistake(state, dt, isBallApproaching)
    targetY = targetY + (state.aiError or 0)

    local step = (state.aiSpeed * profile.speedScale) * dt
    if targetY > state.aiY + step then
        state.aiY = state.aiY + step
    elseif targetY < state.aiY - step then
        state.aiY = state.aiY - step
    else
        state.aiY = targetY
    end
end

local function applyPaddleBounce(state, paddleY, direction)
    local ballCenter = state.ballY + state.ballSize * 0.5
    local paddleCenter = paddleY + state.paddleH * 0.5
    local normalized = clamp((ballCenter - paddleCenter) / (state.paddleH * 0.5), -1, 1)

    local currentSpeed = math.sqrt(state.ballVX * state.ballVX + state.ballVY * state.ballVY)
    local nextSpeed = math.min(state.ballMaxSpeed, math.max(state.ballBaseSpeed, currentSpeed * 1.05))

    local horizontal = math.max(nextSpeed * 0.45, state.ballBaseSpeed * 0.70)
    state.ballVX = direction * horizontal
    state.ballVY = clamp(normalized * state.maxBounceY, -state.maxBounceY, state.maxBounceY)

    playTone(700, 15, 0)
end

local function updateBall(state, dt)
    state.ballX = state.ballX + state.ballVX * dt
    state.ballY = state.ballY + state.ballVY * dt

    if state.ballY <= 0 then
        state.ballY = 0
        state.ballVY = math.abs(state.ballVY)
        playTone(500, 10, 0)
    elseif state.ballY + state.ballSize >= state.height then
        state.ballY = state.height - state.ballSize
        state.ballVY = -math.abs(state.ballVY)
        playTone(500, 10, 0)
    end

    local overlapsAi = (state.ballY + state.ballSize >= state.aiY and state.ballY <= state.aiY + state.paddleH)
    if state.ballVX < 0 and state.ballX <= state.aiX + state.paddleW and state.ballX + state.ballSize >= state.aiX and overlapsAi then
        state.ballX = state.aiX + state.paddleW
        applyPaddleBounce(state, state.aiY, 1)
    end

    local overlapsPlayer = (state.ballY + state.ballSize >= state.playerY and state.ballY <= state.playerY + state.paddleH)
    if state.ballVX > 0 and state.ballX + state.ballSize >= state.playerX and state.ballX <= state.playerX + state.paddleW and overlapsPlayer then
        state.ballX = state.playerX - state.ballSize
        applyPaddleBounce(state, state.playerY, -1)
    end

    if state.ballX + state.ballSize < 0 then
        scorePoint(state, "player")
    elseif state.ballX > state.width then
        scorePoint(state, "ai")
    end
end

local function updateMatch(state, dt)
    updatePlayerFromStick(state)
    if isTwoPlayerMode(state) and updatePlayer2FromStick(state) then
        resetAiBehavior(state)
    else
        updateAi(state, dt)
    end

    state.playerY = clamp(state.playerY, 0, state.height - state.paddleH)
    state.aiY = clamp(state.aiY, 0, state.height - state.paddleH)

    if state.serveTimer > 0 then
        state.serveTimer = state.serveTimer - dt
        if state.serveTimer <= 0 then
            state.serveTimer = 0
            startServe(state)
        end
        return
    end

    updateBall(state, dt)
end

local function drawCenterNet(state)
    local x = math.floor(state.width * 0.5) - 1
    setColor(110, 125, 145)
    for y = 0, state.height, 14 do
        lcd.drawFilledRectangle(x, y + 2, 2, 8)
    end
end

local function drawHud(state)
    setFont(FONT_L_BOLD or FONT_STD)
    setColor(230, 235, 240)
    lcd.drawText(math.floor(state.width * 0.34), 4, tostring(state.aiScore))
    lcd.drawText(math.floor(state.width * 0.62), 4, tostring(state.playerScore))

    setFont(FONT_XXS or FONT_STD)
    setColor(150, 165, 185)
    lcd.drawText(4, 4, leftPlayerLabel(state))
    lcd.drawText(state.width - 30, 4, rightPlayerLabel(state))
end

local function drawOverlay(state)
    local boxW = math.floor(state.width * 0.76)
    local boxH = math.floor(state.height * 0.56)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(6, 16, 28)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(140, 165, 195)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(232, 238, 246)
    lcd.drawText(boxX + 16, boxY + 12, "LuaPong")

    setFont(FONT_XXS or FONT_STD)
    setColor(185, 198, 218)
    if state.winner == "player" then
        if isTwoPlayerMode(state) then
            lcd.drawText(boxX + 16, boxY + 42, "P1 wins.")
        else
            lcd.drawText(boxX + 16, boxY + 42, "You win.")
        end
    elseif state.winner == "ai" then
        if isTwoPlayerMode(state) then
            lcd.drawText(boxX + 16, boxY + 42, "P2 wins.")
        else
            lcd.drawText(boxX + 16, boxY + 42, "CPU wins.")
        end
    else
        lcd.drawText(boxX + 16, boxY + 42, "Classic Pong for Ethos.")
    end

    lcd.drawText(boxX + 16, boxY + 58, "Mode: " .. modeLabel(state))

    if isTwoPlayerMode(state) then
        lcd.drawText(boxX + 16, boxY + 74, "P1: Elevator/Aileron stick")
        if state.player2Source then
            lcd.drawText(boxX + 16, boxY + 90, "P2: Throttle stick")
        else
            lcd.drawText(boxX + 16, boxY + 90, "P2 source missing (CPU fallback)")
        end
    else
        lcd.drawText(boxX + 16, boxY + 74, "Stick up/down: move paddle")
        lcd.drawText(boxX + 16, boxY + 90, "Difficulty: " .. difficultyLabel(state))
    end
    lcd.drawText(boxX + 16, boxY + 106, "Enter: start or restart")
    lcd.drawText(boxX + 16, boxY + 122, "Long-press Page: settings")
    lcd.drawText(boxX + 16, boxY + 138, string.format("First to %d points", state.maxScore))
end

local function drawServeCallout(state)
    local boxW = math.max(130, math.floor(state.width * 0.28))
    local boxH = math.max(28, math.floor(state.height * 0.11))
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor(state.height * 0.14)
    local text = "SERVE"

    setColor(7, 18, 32)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(152, 182, 214)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(220, 236, 254)

    local textW, textH = 0, 0
    if lcd and lcd.getTextSize then
        local ok, w, h = pcall(lcd.getTextSize, text)
        if not ok then
            ok, w, h = pcall(lcd.getTextSize)
        end
        if ok and type(w) == "number" then textW = w end
        if ok and type(h) == "number" then textH = h end
    end

    if textW <= 0 then
        textW = math.max(32, math.floor(boxW * 0.50))
    end
    if textH <= 0 then
        textH = math.max(12, math.floor(boxH * 0.52))
    end

    local textX = boxX + math.floor((boxW - textW) * 0.5)
    local textY = boxY + math.floor((boxH - textH) * 0.5)
    lcd.drawText(textX, textY, text)
end

local function visibleConfigItems(state)
    local items = {}
    for _, item in ipairs(CONFIG_MENU_ITEMS) do
        if (not item.visible) or item.visible(state) then
            items[#items + 1] = item
        end
    end
    return items
end

local function findChoiceIndex(item, value)
    for idx, choice in ipairs(item.choices) do
        if choice.value == value then
            return idx
        end
    end
    return 1
end

local function cycleConfigItem(state, direction)
    local items = visibleConfigItems(state)
    if #items == 0 then
        return
    end

    state.menuPosition = clamp(state.menuPosition or 1, 1, #items)
    local item = items[state.menuPosition]
    if not item then
        return
    end

    local currentValue = state.config[item.key]
    local idx = findChoiceIndex(item, currentValue)
    idx = idx + (direction or 1)
    if idx > #item.choices then idx = 1 end
    if idx < 1 then idx = #item.choices end

    setConfigValue(state, item.key, item.choices[idx].value)

    if item.key == "mode" then
        local visibleCount = #visibleConfigItems(state)
        state.menuPosition = clamp(state.menuPosition, 1, math.max(visibleCount, 1))
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
    if not state then
        return
    end
    state.suppressExitUntil = nowSeconds() + (windowSeconds or 0.25)
    killPendingKeyEvents(KEY_EXIT_BREAK)
    killPendingKeyEvents(KEY_EXIT_FIRST)
end

local function suppressEnterEvents(state, windowSeconds)
    if not state then
        return
    end
    state.suppressEnterUntil = nowSeconds() + (windowSeconds or 0.20)
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
    state.menuPage = false

    local infoLine = form.addLine("LuaPong")
    if form.addStaticText then
        form.addStaticText(infoLine, nil, "Settings (Exit/Back to return)")
    end

    local modeLine = form.addLine("Mode")
    form.addChoiceField(
        modeLine,
        nil,
        MODE_CHOICES_FORM,
        function()
            return modeChoiceValue(state.config.mode)
        end,
        function(newValue)
            if tonumber(newValue) == MODE_CHOICE_TWO_PLAYER then
                setConfigValue(state, "mode", MODE_TWO_PLAYER)
            else
                setConfigValue(state, "mode", MODE_SINGLE)
            end
        end
    )

    local difficultyLine = form.addLine("Difficulty")
    form.addChoiceField(
        difficultyLine,
        nil,
        DIFFICULTY_CHOICES_FORM,
        function()
            return difficultyChoiceValue(state.config.difficulty)
        end,
        function(newValue)
            if tonumber(newValue) == DIFFICULTY_CHOICE_HARD then
                setConfigValue(state, "difficulty", DIFFICULTY_HARD)
            else
                setConfigValue(state, "difficulty", DIFFICULTY_EASY)
            end
        end
    )

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

local function drawConfigMenu(state)
    local boxW = math.floor(state.width * 0.78)
    local boxH = math.floor(state.height * 0.62)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(6, 16, 28)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(140, 165, 195)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(232, 238, 246)
    lcd.drawText(boxX + 12, boxY + 10, "Configuration")

    local items = visibleConfigItems(state)
    if #items <= 0 then
        setFont(FONT_XXS or FONT_STD)
        setColor(185, 198, 218)
        lcd.drawText(boxX + 12, boxY + 38, "No configurable options.")
        return
    end

    state.menuPosition = clamp(state.menuPosition or 1, 1, #items)

    local y = boxY + 42
    for idx, item in ipairs(items) do
        local selected = (idx == state.menuPosition)
        if selected then
            setColor(70, 104, 148)
            lcd.drawFilledRectangle(boxX + 10, y - 2, boxW - 20, 18)
        end

        setFont(FONT_XXS or FONT_STD)
        setColor(selected and 245 or 188, selected and 250 or 198, selected and 255 or 214)

        local choice = item.choices[findChoiceIndex(item, state.config[item.key])]
        local valueLabel = choice and choice.label or "-"
        lcd.drawText(boxX + 16, y, item.label .. ": " .. valueLabel)
        y = y + 20
    end

    setFont(FONT_XXS or FONT_STD)
    setColor(176, 190, 210)
    lcd.drawText(boxX + 12, boxY + boxH - 42, "Up/Down: select  Enter: change")
    lcd.drawText(boxX + 12, boxY + boxH - 26, "Exit: close menu")
end

local function render(state)
    setColor(12, 22, 36)
    lcd.drawFilledRectangle(0, 0, state.width, state.height)

    drawCenterNet(state)
    drawHud(state)

    setColor(220, 235, 252)
    lcd.drawFilledRectangle(state.aiX, math.floor(state.aiY + 0.5), state.paddleW, state.paddleH)
    lcd.drawFilledRectangle(state.playerX, math.floor(state.playerY + 0.5), state.paddleW, state.paddleH)
    lcd.drawFilledRectangle(math.floor(state.ballX + 0.5), math.floor(state.ballY + 0.5), state.ballSize, state.ballSize)

    if state.menuPage then
        drawConfigMenu(state)
    elseif not state.running then
        drawOverlay(state)
    elseif state.serveTimer > 0 then
        drawServeCallout(state)
    end
end

local function nudgePlayer(state, direction)
    if direction == 0 then return end
    state.playerY = clamp(state.playerY + direction * state.keyNudge, 0, state.height - state.paddleH)
end

local function createState()
    local loadedConfig = loadStateConfig()
    local state = {
        width = 0,
        height = 0,
        running = false,
        winner = nil,
        playerScore = 0,
        aiScore = 0,
        maxScore = MAX_SCORE,
        serveTimer = 0,
        serveDir = 1,
        ballX = 0,
        ballY = 0,
        ballVX = 0,
        ballVY = 0,
        playerY = nil,
        aiY = nil,
        filteredInput = nil,
        filteredInputP2 = nil,
        aiError = 0,
        aiErrorTarget = 0,
        aiMistakeTimer = 0,
        menuPage = false,
        menuPosition = 1,
        config = loadedConfig,
        settingsFormOpen = false,
        pendingFormClear = false,
        suppressExitUntil = 0,
        suppressEnterUntil = 0,
        lastRawInputByAxis = {},
        frameScale = 1,
        lastFrameTime = 0,
        nextInvalidateAt = 0,
        playerSource = resolveAnalogSource(PLAYER_SOURCE_MEMBER),
        player2Source = resolveAnalogSource(PLAYER2_SOURCE_MEMBER),
        lastFocusKick = 0
    }

    refreshGeometry(state)
    setConfigValue(state, "mode", state.config.mode, true)
    setConfigValue(state, "difficulty", state.config.difficulty, true)
    resetRound(state)
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
    if not state.playerSource then
        state.playerSource = resolveAnalogSource(PLAYER_SOURCE_MEMBER)
    end
    if isTwoPlayerMode(state) and not state.player2Source then
        state.player2Source = resolveAnalogSource(PLAYER2_SOURCE_MEMBER)
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
        -- Let Ethos form widgets (including touch) handle all other events.
        return false
    end

    if category == EVT_CLOSE then
        if state.menuPage then
            state.menuPage = false
            suppressExitEvents(state)
            forceInvalidate(state)
            return true
        end
        if state.running then
            state.running = false
            state.winner = nil
            suppressExitEvents(state)
            forceInvalidate(state)
            return true
        end
        return false
    end

    if not isKeyCategory(category) then
        return false
    end

    if state.menuPage then
        local items = visibleConfigItems(state)
        if #items == 0 then
            state.menuPage = false
            forceInvalidate(state)
            return true
        end

        if keyMatches(value, KEY_UP_FIRST, KEY_UP_BREAK, KEY_PAGE_UP, KEY_ROTARY_LEFT, KEY_LEFT_FIRST, KEY_LEFT_BREAK) then
            state.menuPosition = state.menuPosition - 1
            if state.menuPosition < 1 then
                state.menuPosition = #items
            end
            forceInvalidate(state)
            return true
        end

        if keyMatches(value, KEY_DOWN_FIRST, KEY_DOWN_BREAK, KEY_PAGE_DOWN, KEY_ROTARY_RIGHT, KEY_RIGHT_FIRST, KEY_RIGHT_BREAK) then
            state.menuPosition = state.menuPosition + 1
            if state.menuPosition > #items then
                state.menuPosition = 1
            end
            forceInvalidate(state)
            return true
        end

        if keyMatches(value, KEY_ENTER_FIRST, KEY_ENTER_BREAK, KEY_ENTER_LONG) then
            cycleConfigItem(state, 1)
            forceInvalidate(state)
            return true
        end

        if isExitKeyEvent(category, value) then
            state.menuPage = false
            suppressExitEvents(state)
            forceInvalidate(state)
            return true
        end

        return true
    end

    if isSettingsOpenEvent(category, value) and not state.running then
        if openSettingsForm(state) then
            killPendingKeyEvents(KEY_ENTER_BREAK)
            forceInvalidate(state)
            return true
        end

        state.menuPage = true
        local count = #visibleConfigItems(state)
        state.menuPosition = clamp(state.menuPosition or 1, 1, math.max(count, 1))
        forceInvalidate(state)
        return true
    end

    if keyMatches(value, KEY_ENTER_FIRST, KEY_ENTER_BREAK) then
        startMatch(state)
        forceInvalidate(state)
        return true
    end

    if isExitKeyEvent(category, value) then
        if state.running then
            state.running = false
            state.winner = nil
            suppressExitEvents(state)
            forceInvalidate(state)
            return true
        end
        return false
    end

    if keyMatches(value, KEY_UP_FIRST, KEY_UP_BREAK, KEY_PAGE_UP, KEY_ROTARY_LEFT, KEY_LEFT_FIRST, KEY_LEFT_BREAK) then
        if state.running then
            nudgePlayer(state, -1)
            forceInvalidate(state)
            return true
        end
        return false
    end

    if keyMatches(value, KEY_DOWN_FIRST, KEY_DOWN_BREAK, KEY_PAGE_DOWN, KEY_ROTARY_RIGHT, KEY_RIGHT_FIRST, KEY_RIGHT_BREAK) then
        if state.running then
            nudgePlayer(state, 1)
            forceInvalidate(state)
            return true
        end
        return false
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
        updateMatch(state, dt)
    end

    render(state)
end

function game.close(state)
    if type(state) ~= "table" then
        return
    end
    state.running = false
    state.menuPage = false
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
