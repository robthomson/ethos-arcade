local game = {}

local HORIZONTAL_SOURCE_MEMBER = 3

local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local CONFIG_FILE = "luabreaks.cfg"
local CONFIG_VERSION = 1

local SPEED_EASY = "easy"
local SPEED_NORMAL = "normal"
local SPEED_HARD = "hard"
local SPEED_CHOICE_EASY = 1
local SPEED_CHOICE_NORMAL = 2
local SPEED_CHOICE_HARD = 3
local SPEED_CHOICES_FORM = {
    {"Easy", SPEED_CHOICE_EASY},
    {"Normal", SPEED_CHOICE_NORMAL},
    {"Hard", SPEED_CHOICE_HARD}
}

local ACTIVE_RENDER_FPS = 45
local IDLE_RENDER_FPS = 12
local GAME_SPEED_MULTIPLIER = 1.00
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.60
local FRAME_SCALE_MAX = 1.90
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local BRICK_ROWS = 8
local BRICK_COLS = 12
local BRICK_GAP = 2
local BRICK_TOP_PADDING = 8
local BRICK_BOTTOM_CLEARANCE = 70
local BRICK_AREA_HEIGHT_RATIO = 0.34
local BRICK_HEIGHT_MIN = 12
local BRICK_HEIGHT_MAX = 30
local MAX_LEVEL = 3

local STICK_SOURCE_IS_PERCENT = false
local STICK_RAW_ABS_LIMIT = 5000
local STICK_GLITCH_DELTA_LIMIT = 1900
local PADDLE_TRACK_BLEND_RATE = 18.0

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
    if keyMatches(value, KEY_EXIT_BREAK, KEY_EXIT_FIRST) then
        return true
    end
    return value == 35
end

local function normalizeSpeed(value)
    if value == SPEED_EASY then
        return SPEED_EASY
    end
    if value == SPEED_HARD then
        return SPEED_HARD
    end
    return SPEED_NORMAL
end

local function speedChoiceValue(speed)
    local normalized = normalizeSpeed(speed)
    if normalized == SPEED_EASY then
        return SPEED_CHOICE_EASY
    end
    if normalized == SPEED_HARD then
        return SPEED_CHOICE_HARD
    end
    return SPEED_CHOICE_NORMAL
end

local function speedFromChoice(choiceValue)
    if tonumber(choiceValue) == SPEED_CHOICE_EASY then
        return SPEED_EASY
    end
    if tonumber(choiceValue) == SPEED_CHOICE_HARD then
        return SPEED_HARD
    end
    return SPEED_NORMAL
end

local function speedLabel(speed)
    local normalized = normalizeSpeed(speed)
    if normalized == SPEED_EASY then
        return "Easy"
    end
    if normalized == SPEED_HARD then
        return "Hard"
    end
    return "Normal"
end

local function speedProfile(speed)
    local normalized = normalizeSpeed(speed)
    if normalized == SPEED_EASY then
        return {ballSpeedScale = 0.86, lives = 4}
    end
    if normalized == SPEED_HARD then
        return {ballSpeedScale = 1.18, lives = 2}
    end
    return {ballSpeedScale = 1.00, lives = 3}
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
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/luabreaks/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/luabreaks/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/ethos-arcade/games/luabreaks/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/luabreaks/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/luabreaks/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/luabreaks/" .. CONFIG_FILE
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
    end

    return {
        speed = normalizeSpeed(values.speed),
        bestScore = best or 0
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
    f:write("speed=", normalizeSpeed(state.config.speed), "\n")
    f:write("bestScore=", math.max(0, math.floor(state.bestScore or 0)), "\n")
    f:close()
    return true
end

local function applyConfigSideEffects(state)
    if not state then
        return
    end

    state.profile = speedProfile(state.config and state.config.speed)
end

local function setConfigValue(state, key, value, skipSave)
    if not (state and state.config) then
        return
    end

    if key == "speed" then
        state.config.speed = normalizeSpeed(value)
    else
        return
    end

    applyConfigSideEffects(state)
    if not skipSave then
        saveStateConfig(state)
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
    local now = (os and os.clock and os.clock()) or 0
    state.suppressExitUntil = now + (windowSeconds or 0.25)
    killPendingKeyEvents(KEY_EXIT_BREAK)
    killPendingKeyEvents(KEY_EXIT_FIRST)
end

local function suppressEnterEvents(state, windowSeconds)
    if not state then
        return
    end
    local now = (os and os.clock and os.clock()) or 0
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

local function nowSeconds()
    if os and os.clock then
        return os.clock()
    end
    return 0
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

local function mapInputToActionRange(value, rangeStart, rangeEnd)
    return rangeStart + (rangeEnd - rangeStart) * ((value + 1024) / 2048)
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

    local infoLine = form.addLine("LuaBreaks")
    if form.addStaticText then
        form.addStaticText(infoLine, nil, "Settings (Exit/Back to return)")
    end

    local speedLine = form.addLine("Speed")
    form.addChoiceField(
        speedLine,
        nil,
        SPEED_CHOICES_FORM,
        function()
            return speedChoiceValue(state.config.speed)
        end,
        function(newValue)
            setConfigValue(state, "speed", speedFromChoice(newValue))
        end
    )

    local bestLine = form.addLine("Best score")
    local resetAction = function()
        state.bestScore = 0
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

    state.margin = math.max(6, math.floor(width * 0.02))
    state.headerH = math.max(22, math.floor(height * 0.12))
    state.playX = state.margin
    state.playY = state.margin + state.headerH
    state.playW = width - (state.margin * 2)
    state.playH = height - state.playY - state.margin

    state.paddleW = clamp(math.floor(state.playW * 0.16), 52, math.floor(state.playW * 0.28))
    state.paddleH = math.max(6, math.floor(state.playH * 0.035))
    state.ballSize = math.max(5, math.floor(math.min(width, height) * 0.024))

    state.paddleY = state.playY + state.playH - state.paddleH - 8
    state.paddleSpeed = math.max(165, state.playW * 1.85)
    state.keyNudge = math.max(9, math.floor(state.playW * 0.055))

    local maxBrickAreaH = state.paddleY - (state.playY + BRICK_TOP_PADDING) - BRICK_BOTTOM_CLEARANCE
    local ratioBrickAreaH = math.floor(state.playH * BRICK_AREA_HEIGHT_RATIO)
    local brickAreaH = math.max(32, math.min(maxBrickAreaH, ratioBrickAreaH))

    state.brickH = clamp(
        math.floor((brickAreaH - ((BRICK_ROWS - 1) * BRICK_GAP)) / BRICK_ROWS),
        BRICK_HEIGHT_MIN,
        BRICK_HEIGHT_MAX
    )
    state.brickW = math.max(10, math.floor((state.playW - ((BRICK_COLS + 1) * BRICK_GAP)) / BRICK_COLS))

    local brickTotalW = (state.brickW * BRICK_COLS) + ((BRICK_COLS + 1) * BRICK_GAP)
    state.brickStartX = state.playX + math.floor((state.playW - brickTotalW) * 0.5) + BRICK_GAP
    state.brickStartY = state.playY + BRICK_TOP_PADDING

    state.paddleMinX = state.playX
    state.paddleMaxX = state.playX + state.playW - state.paddleW

    if changed then
        if state.paddleX then
            state.paddleX = clamp(state.paddleX, state.paddleMinX, state.paddleMaxX)
        end
        forceInvalidate(state)
    end
end

local function brickRect(state, brick)
    local x = state.brickStartX + ((brick.col - 1) * (state.brickW + BRICK_GAP))
    local y = state.brickStartY + ((brick.row - 1) * (state.brickH + BRICK_GAP))
    return x, y, state.brickW, state.brickH
end

local function setupBricks(state)
    local bricks = {}
    local remaining = 0

    for row = 1, BRICK_ROWS do
        for col = 1, BRICK_COLS do
            remaining = remaining + 1
            bricks[#bricks + 1] = {
                row = row,
                col = col,
                alive = true,
                points = (BRICK_ROWS - row + 1) * 10,
                colorIndex = ((row - 1) % #state.brickColors) + 1
            }
        end
    end

    state.bricks = bricks
    state.bricksRemaining = remaining
end

local function baseBallSpeed(state)
    local profile = state.profile or speedProfile(state.config and state.config.speed)
    local base = math.max(140, state.playH * 1.05)
    local levelScale = 1 + ((state.level - 1) * 0.10)
    return base * profile.ballSpeedScale * levelScale
end

local function resetServe(state)
    state.ballOnPaddle = true
    state.serveTimer = 0.60
    state.ballVX = 0
    state.ballVY = 0
    state.ballX = state.paddleX + ((state.paddleW - state.ballSize) * 0.5)
    state.ballY = state.paddleY - state.ballSize - 1
end

local function launchBall(state)
    local speed = baseBallSpeed(state)
    local angleFactor = (math.random() * 0.9) - 0.45
    state.ballVX = speed * angleFactor
    state.ballVY = -math.sqrt(math.max(40, (speed * speed) - (state.ballVX * state.ballVX)))
    state.ballOnPaddle = false
    state.serveTimer = 0
    playTone(620, 18, 0)
end

local function startGame(state)
    state.profile = speedProfile(state.config and state.config.speed)
    state.running = true
    state.gameOver = false
    state.gameStarted = true
    state.winRound = false

    state.level = 1
    state.score = 0
    state.lives = state.profile.lives

    state.paddleX = state.playX + ((state.playW - state.paddleW) * 0.5)
    state.paddleTargetX = state.paddleX

    setupBricks(state)
    resetServe(state)

    state.lastRawInputByAxis = {}
    forceInvalidate(state)
end

local function finishRound(state, didWin)
    state.running = false
    state.gameOver = true
    state.winRound = didWin and true or false

    if state.score > state.bestScore then
        state.bestScore = state.score
        saveStateConfig(state)
    end

    if didWin then
        playTone(1240, 140, 40)
    else
        playTone(220, 150, 40)
    end
end

local function movePaddleFromStick(state, dt)
    local target = state.paddleX
    if state.moveSourceX then
        local raw = sanitizeStickSample(state, sourceValue(state.moveSourceX), "move")
        target = mapInputToActionRange(raw, state.paddleMinX, state.paddleMaxX)
    end

    state.paddleTargetX = target
    local blend = clamp((dt or 0) * PADDLE_TRACK_BLEND_RATE, 0, 1)
    state.paddleX = state.paddleX + ((state.paddleTargetX - state.paddleX) * blend)
    if math.abs(state.paddleTargetX - state.paddleX) < 0.5 then
        state.paddleX = state.paddleTargetX
    end
    state.paddleX = clamp(state.paddleX, state.paddleMinX, state.paddleMaxX)
end

local function nudgePaddle(state, dir)
    state.paddleX = clamp(state.paddleX + (state.keyNudge * dir), state.paddleMinX, state.paddleMaxX)
    if state.ballOnPaddle then
        state.ballX = state.paddleX + ((state.paddleW - state.ballSize) * 0.5)
    end
    forceInvalidate(state)
end

local function updateBallWallCollisions(state)
    local left = state.playX
    local right = state.playX + state.playW
    local top = state.playY

    if state.ballX <= left then
        state.ballX = left
        state.ballVX = math.abs(state.ballVX)
        playTone(420, 10, 0)
    elseif state.ballX + state.ballSize >= right then
        state.ballX = right - state.ballSize
        state.ballVX = -math.abs(state.ballVX)
        playTone(420, 10, 0)
    end

    if state.ballY <= top then
        state.ballY = top
        state.ballVY = math.abs(state.ballVY)
        playTone(500, 10, 0)
    end
end

local function updateBallPaddleCollision(state)
    if state.ballVY <= 0 then
        return
    end

    local ballLeft = state.ballX
    local ballRight = state.ballX + state.ballSize
    local ballTop = state.ballY
    local ballBottom = state.ballY + state.ballSize

    local paddleLeft = state.paddleX
    local paddleRight = state.paddleX + state.paddleW
    local paddleTop = state.paddleY
    local paddleBottom = state.paddleY + state.paddleH

    if ballRight < paddleLeft or ballLeft > paddleRight then
        return
    end
    if ballBottom < paddleTop or ballTop > paddleBottom then
        return
    end

    state.ballY = paddleTop - state.ballSize - 0.2

    local ballCenter = state.ballX + (state.ballSize * 0.5)
    local paddleCenter = state.paddleX + (state.paddleW * 0.5)
    local normalized = clamp((ballCenter - paddleCenter) / (state.paddleW * 0.5), -1, 1)

    local speed = math.sqrt((state.ballVX * state.ballVX) + (state.ballVY * state.ballVY))
    speed = math.max(baseBallSpeed(state), speed * 1.02)

    state.ballVX = normalized * speed * 0.95
    state.ballVY = -math.sqrt(math.max(20, (speed * speed) - (state.ballVX * state.ballVX)))
    playTone(760, 12, 0)
end

local function updateBallBrickCollision(state)
    local ballLeft = state.ballX
    local ballRight = state.ballX + state.ballSize
    local ballTop = state.ballY
    local ballBottom = state.ballY + state.ballSize

    for i = 1, #state.bricks do
        local brick = state.bricks[i]
        if brick.alive then
            local bx, by, bw, bh = brickRect(state, brick)
            local br = bx + bw
            local bb = by + bh

            if ballRight >= bx and ballLeft <= br and ballBottom >= by and ballTop <= bb then
                brick.alive = false
                state.bricksRemaining = state.bricksRemaining - 1
                state.score = state.score + brick.points

                local penLeft = ballRight - bx
                local penRight = br - ballLeft
                local penTop = ballBottom - by
                local penBottom = bb - ballTop
                local minPen = math.min(penLeft, penRight, penTop, penBottom)

                if minPen == penLeft or minPen == penRight then
                    state.ballVX = -state.ballVX
                else
                    state.ballVY = -state.ballVY
                end

                playTone(900, 8, 0)

                if state.bricksRemaining <= 0 then
                    if state.level >= MAX_LEVEL then
                        finishRound(state, true)
                        return
                    end

                    state.level = state.level + 1
                    setupBricks(state)
                    resetServe(state)
                    playTone(1120, 70, 20)
                end

                return
            end
        end
    end
end

local function loseLife(state)
    state.lives = state.lives - 1
    playTone(260, 80, 20)

    if state.lives <= 0 then
        finishRound(state, false)
        return
    end

    resetServe(state)
end

local function updateGame(state, dt)
    if not state.running then
        return
    end

    movePaddleFromStick(state, dt)

    if state.ballOnPaddle then
        state.ballX = state.paddleX + ((state.paddleW - state.ballSize) * 0.5)
        state.ballY = state.paddleY - state.ballSize - 1
        state.serveTimer = state.serveTimer - dt
        if state.serveTimer <= 0 then
            launchBall(state)
        end
        return
    end

    state.ballX = state.ballX + (state.ballVX * dt)
    state.ballY = state.ballY + (state.ballVY * dt)

    updateBallWallCollisions(state)
    updateBallPaddleCollision(state)
    updateBallBrickCollision(state)

    if not state.running then
        return
    end

    local bottom = state.playY + state.playH
    if state.ballY > bottom then
        loseLife(state)
    end
end

local function drawBackground(state)
    setColor(4, 10, 18)
    lcd.drawFilledRectangle(0, 0, state.width, state.height)

    setColor(10, 20, 34)
    lcd.drawFilledRectangle(state.playX - 2, state.playY - 2, state.playW + 4, state.playH + 4)
    setColor(86, 110, 138)
    lcd.drawRectangle(state.playX - 2, state.playY - 2, state.playW + 4, state.playH + 4, 1)
end

local function drawBricks(state)
    for i = 1, #state.bricks do
        local brick = state.bricks[i]
        if brick.alive then
            local bx, by, bw, bh = brickRect(state, brick)
            local color = state.brickColors[brick.colorIndex]

            setColor(color[1], color[2], color[3])
            lcd.drawFilledRectangle(bx, by, bw, bh)
            setColor(color[1] + 20, color[2] + 20, color[3] + 20)
            lcd.drawRectangle(bx, by, bw, bh, 1)
        end
    end
end

local function drawPaddleAndBall(state)
    setColor(214, 230, 245)
    lcd.drawFilledRectangle(math.floor(state.paddleX), state.paddleY, state.paddleW, state.paddleH)

    setColor(246, 208, 90)
    lcd.drawFilledRectangle(math.floor(state.ballX), math.floor(state.ballY), state.ballSize, state.ballSize)
end

local function drawHud(state)
    local y = state.margin + 1

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(228, 238, 248)
    lcd.drawText(state.margin, y, "LuaBreaks")

    setFont(FONT_XXS or FONT_STD)
    setColor(184, 200, 220)
    lcd.drawText(state.margin + 120, y + 2, string.format("Score %d", state.score or 0))
    lcd.drawText(state.margin + 200, y + 2, string.format("Best %d", state.bestScore or 0))
    lcd.drawText(state.margin + 280, y + 2, string.format("Lives %d", state.lives or 0))
    lcd.drawText(state.margin + 360, y + 2, string.format("L%d", state.level or 1))

    setColor(132, 154, 178)
    lcd.drawText(state.margin, state.margin + state.headerH - 12, string.format("Aileron move | Long Page settings | Speed %s", speedLabel(state.config and state.config.speed)))
end

local function drawOverlay(state)
    local boxW = math.floor(state.width * 0.64)
    local boxH = math.floor(state.height * 0.44)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(2, 10, 18)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(120, 152, 186)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(242, 250, 255)

    if state.gameOver then
        if state.winRound then
            drawCenteredText(boxX, boxY + 10, boxW, 24, "YOU WIN")
        else
            drawCenteredText(boxX, boxY + 10, boxW, 24, "GAME OVER")
        end
    else
        drawCenteredText(boxX, boxY + 10, boxW, 24, "LuaBreaks")
    end

    setFont(FONT_XXS or FONT_STD)
    setColor(186, 208, 230)

    if state.gameOver then
        drawCenteredText(boxX, boxY + 36, boxW, 18, string.format("Score: %d", state.score or 0))
    else
        drawCenteredText(boxX, boxY + 36, boxW, 18, "Break all bricks before you run out of lives")
    end

    drawCenteredText(boxX, boxY + 58, boxW, 18, "Press Enter to start")
    drawCenteredText(boxX, boxY + 78, boxW, 18, "Long Page for settings")
    drawCenteredText(boxX, boxY + 98, boxW, 18, "Exit returns to arcade menu")
end

local function render(state)
    drawBackground(state)
    drawHud(state)
    drawBricks(state)
    drawPaddleAndBall(state)

    if not state.running then
        drawOverlay(state)
    end
end

local function createState()
    local loaded = loadStateConfig()

    local state = {
        width = 480,
        height = 272,

        config = {
            speed = normalizeSpeed(loaded.speed)
        },

        bestScore = loaded.bestScore or 0,
        score = 0,

        running = false,
        gameOver = false,
        gameStarted = false,
        winRound = false,

        lives = 0,
        level = 1,

        paddleX = 0,
        paddleTargetX = 0,
        paddleY = 0,
        paddleW = 0,
        paddleH = 0,
        paddleSpeed = 0,
        keyNudge = 0,

        ballX = 0,
        ballY = 0,
        ballVX = 0,
        ballVY = 0,
        ballSize = 0,
        ballOnPaddle = true,
        serveTimer = 0,

        bricks = {},
        bricksRemaining = 0,
        brickColors = {
            {236, 100, 90},
            {241, 170, 86},
            {240, 230, 96},
            {120, 220, 124},
            {104, 158, 236}
        },

        moveSourceX = resolveAnalogSource(HORIZONTAL_SOURCE_MEMBER),
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
    state.paddleX = state.playX + ((state.playW - state.paddleW) * 0.5)
    resetServe(state)
    setupBricks(state)
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
        state.moveSourceX = resolveAnalogSource(HORIZONTAL_SOURCE_MEMBER)
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
            state.running = false
            state.gameOver = false
            state.winRound = false
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

    if isExitKeyEvent(category, value) then
        state.running = false
        state.gameOver = false
        state.winRound = false
        suppressExitEvents(state)
        forceInvalidate(state)
        return true
    end

    if keyMatches(value, KEY_LEFT_FIRST, KEY_LEFT_BREAK, KEY_ROTARY_LEFT) then
        nudgePaddle(state, -1)
        return true
    end

    if keyMatches(value, KEY_RIGHT_FIRST, KEY_RIGHT_BREAK, KEY_ROTARY_RIGHT) then
        nudgePaddle(state, 1)
        return true
    end

    if keyMatches(value, KEY_ENTER_FIRST, KEY_ENTER_BREAK) then
        if state.ballOnPaddle then
            launchBall(state)
            return true
        end
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
