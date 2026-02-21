local game = {}

local HORIZONTAL_SOURCE_MEMBER = 3
local VERTICAL_SOURCE_MEMBER = 1

local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local CONFIG_FILE = "luasnake.cfg"
local CONFIG_VERSION = 1

local SPEED_SLOW = "slow"
local SPEED_NORMAL = "normal"
local SPEED_FAST = "fast"
local SPEED_CHOICE_SLOW = 1
local SPEED_CHOICE_NORMAL = 2
local SPEED_CHOICE_FAST = 3
local SPEED_CHOICES_FORM = {
    {"Slow", SPEED_CHOICE_SLOW},
    {"Normal", SPEED_CHOICE_NORMAL},
    {"Fast", SPEED_CHOICE_FAST}
}

local GRID_WIDTH = 22
local GRID_HEIGHT = 14

local ACTIVE_RENDER_FPS = 35
local IDLE_RENDER_FPS = 12
local GAME_SPEED_MULTIPLIER = 1.00
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.60
local FRAME_SCALE_MAX = 1.90
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local STEP_INTERVAL_SLOW = 0.22
local STEP_INTERVAL_NORMAL = 0.17
local STEP_INTERVAL_FAST = 0.13
local STEP_INTERVAL_MIN = 0.08

local STICK_SOURCE_IS_PERCENT = false
local STICK_RAW_ABS_LIMIT = 5000
local STICK_GLITCH_DELTA_LIMIT = 1900
local ANALOG_DIRECTION_THRESHOLD = 320

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
    if value == SPEED_SLOW then
        return SPEED_SLOW
    end
    if value == SPEED_FAST then
        return SPEED_FAST
    end
    return SPEED_NORMAL
end

local function speedChoiceValue(speed)
    local normalized = normalizeSpeed(speed)
    if normalized == SPEED_SLOW then
        return SPEED_CHOICE_SLOW
    end
    if normalized == SPEED_FAST then
        return SPEED_CHOICE_FAST
    end
    return SPEED_CHOICE_NORMAL
end

local function speedFromChoice(choiceValue)
    if tonumber(choiceValue) == SPEED_CHOICE_SLOW then
        return SPEED_SLOW
    end
    if tonumber(choiceValue) == SPEED_CHOICE_FAST then
        return SPEED_FAST
    end
    return SPEED_NORMAL
end

local function speedLabel(speed)
    local normalized = normalizeSpeed(speed)
    if normalized == SPEED_SLOW then
        return "Slow"
    end
    if normalized == SPEED_FAST then
        return "Fast"
    end
    return "Normal"
end

local function stepIntervalBaseForSpeed(speed)
    local normalized = normalizeSpeed(speed)
    if normalized == SPEED_SLOW then
        return STEP_INTERVAL_SLOW
    end
    if normalized == SPEED_FAST then
        return STEP_INTERVAL_FAST
    end
    return STEP_INTERVAL_NORMAL
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
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/luasnake/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/luasnake/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/ethos-arcade/games/luasnake/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/luasnake/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/luasnake/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/luasnake/" .. CONFIG_FILE
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

    state.stepIntervalBase = stepIntervalBaseForSpeed(state.config and state.config.speed)
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

    local infoLine = form.addLine("LuaSnake")
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

    local margin = math.max(6, math.floor(width * 0.02))
    local hudW = math.max(120, math.floor(width * 0.27))
    local boardAvailableW = width - (margin * 3) - hudW
    local boardAvailableH = height - (margin * 2)

    local cellSize = math.floor(math.min(boardAvailableW / GRID_WIDTH, boardAvailableH / GRID_HEIGHT))
    cellSize = math.max(8, cellSize)

    state.cellSize = cellSize
    state.boardPixelW = cellSize * GRID_WIDTH
    state.boardPixelH = cellSize * GRID_HEIGHT
    state.boardX = margin
    state.boardY = math.floor((height - state.boardPixelH) * 0.5)
    state.hudX = state.boardX + state.boardPixelW + margin
    state.hudY = state.boardY
    state.hudW = width - state.hudX - margin

    if changed then
        forceInvalidate(state)
    end
end

local function isOccupiedBySnake(state, x, y)
    for i = 1, #state.snake do
        local seg = state.snake[i]
        if seg.x == x and seg.y == y then
            return true
        end
    end
    return false
end

local function spawnFood(state)
    local freeCells = (GRID_WIDTH * GRID_HEIGHT) - #state.snake
    if freeCells <= 0 then
        state.running = false
        state.gameOver = true
        state.winRound = true
        if state.score > state.bestScore then
            state.bestScore = state.score
            saveStateConfig(state)
        end
        playTone(1280, 150, 40)
        return
    end

    local attempts = 0
    while attempts < 500 do
        attempts = attempts + 1
        local x = math.random(0, GRID_WIDTH - 1)
        local y = math.random(0, GRID_HEIGHT - 1)
        if not isOccupiedBySnake(state, x, y) then
            state.foodX = x
            state.foodY = y
            return
        end
    end

    for y = 0, GRID_HEIGHT - 1 do
        for x = 0, GRID_WIDTH - 1 do
            if not isOccupiedBySnake(state, x, y) then
                state.foodX = x
                state.foodY = y
                return
            end
        end
    end
end

local function queueDirection(state, dx, dy)
    if not state.running then
        return
    end
    if dx == 0 and dy == 0 then
        return
    end

    local curX = state.dirX or 1
    local curY = state.dirY or 0
    if dx == -curX and dy == -curY then
        return
    end

    local nextX = state.nextDirX or curX
    local nextY = state.nextDirY or curY
    if dx == -nextX and dy == -nextY then
        return
    end

    state.nextDirX = dx
    state.nextDirY = dy
end

local function startGame(state)
    local startX = math.floor(GRID_WIDTH * 0.35)
    local startY = math.floor(GRID_HEIGHT * 0.5)

    state.running = true
    state.gameOver = false
    state.winRound = false
    state.gameStarted = true
    state.score = 0

    state.snake = {
        {x = startX, y = startY},
        {x = startX - 1, y = startY},
        {x = startX - 2, y = startY}
    }

    state.dirX = 1
    state.dirY = 0
    state.nextDirX = 1
    state.nextDirY = 0
    state.moveTimer = 0
    state.stepIntervalBase = stepIntervalBaseForSpeed(state.config and state.config.speed)
    state.stepInterval = state.stepIntervalBase
    state.lastRawInputByAxis = {}
    state.analogDirectionCooldown = 0

    spawnFood(state)
    forceInvalidate(state)
end

local function endRound(state, didWin)
    state.running = false
    state.gameOver = true
    state.winRound = didWin and true or false

    if state.score > state.bestScore then
        state.bestScore = state.score
        saveStateConfig(state)
    end

    if didWin then
        playTone(1180, 120, 40)
    else
        playTone(260, 140, 40)
    end
end

local function applyNextDirection(state)
    local nx = state.nextDirX or state.dirX
    local ny = state.nextDirY or state.dirY
    if nx == -state.dirX and ny == -state.dirY then
        return
    end
    state.dirX = nx
    state.dirY = ny
end

local function stepSnake(state)
    applyNextDirection(state)

    local head = state.snake[1]
    local nextX = head.x + state.dirX
    local nextY = head.y + state.dirY
    local willGrow = (nextX == state.foodX and nextY == state.foodY)

    if nextX < 0 or nextX >= GRID_WIDTH or nextY < 0 or nextY >= GRID_HEIGHT then
        endRound(state, false)
        return
    end

    local tailExclusion = willGrow and 0 or 1
    local collisionCheckCount = #state.snake - tailExclusion
    for i = 1, collisionCheckCount do
        local seg = state.snake[i]
        if seg.x == nextX and seg.y == nextY then
            endRound(state, false)
            return
        end
    end

    table.insert(state.snake, 1, {x = nextX, y = nextY})

    if willGrow then
        state.score = state.score + 1
        state.stepInterval = math.max(STEP_INTERVAL_MIN, state.stepIntervalBase - (state.score * 0.0028))
        playTone(820, 18, 0)
        spawnFood(state)
    else
        table.remove(state.snake)
    end
end

local function updateAnalogInput(state, dt)
    if not state.running then
        return
    end

    state.analogDirectionCooldown = math.max(0, (state.analogDirectionCooldown or 0) - (dt or 0))

    local rawX = sanitizeStickSample(state, sourceValue(state.moveSourceX), "moveX")
    local rawY = sanitizeStickSample(state, sourceValue(state.moveSourceY), "moveY")

    local absX = math.abs(rawX)
    local absY = math.abs(rawY)
    if absX < ANALOG_DIRECTION_THRESHOLD and absY < ANALOG_DIRECTION_THRESHOLD then
        return
    end
    if state.analogDirectionCooldown > 0 then
        return
    end

    if absX >= absY then
        if rawX > 0 then
            queueDirection(state, 1, 0)
        else
            queueDirection(state, -1, 0)
        end
    else
        if rawY > 0 then
            queueDirection(state, 0, -1)
        else
            queueDirection(state, 0, 1)
        end
    end

    state.analogDirectionCooldown = 0.08
end

local function updateGame(state, dt)
    if not state.running then
        return
    end

    updateAnalogInput(state, dt)

    state.moveTimer = (state.moveTimer or 0) + dt
    while state.moveTimer >= state.stepInterval do
        state.moveTimer = state.moveTimer - state.stepInterval
        stepSnake(state)
        if not state.running then
            return
        end
    end
end

local function drawBackground(state)
    setColor(4, 10, 18)
    lcd.drawFilledRectangle(0, 0, state.width, state.height)

    setColor(8, 18, 28)
    lcd.drawFilledRectangle(state.boardX - 3, state.boardY - 3, state.boardPixelW + 6, state.boardPixelH + 6)
    setColor(76, 102, 128)
    lcd.drawRectangle(state.boardX - 3, state.boardY - 3, state.boardPixelW + 6, state.boardPixelH + 6, 1)
end

local function drawBoard(state)
    local cell = state.cellSize

    setColor(12, 28, 20)
    lcd.drawFilledRectangle(state.boardX, state.boardY, state.boardPixelW, state.boardPixelH)

    setColor(18, 46, 30)
    for y = 1, GRID_HEIGHT - 1 do
        local py = state.boardY + (y * cell)
        lcd.drawLine(state.boardX, py, state.boardX + state.boardPixelW - 1, py)
    end
    for x = 1, GRID_WIDTH - 1 do
        local px = state.boardX + (x * cell)
        lcd.drawLine(px, state.boardY, px, state.boardY + state.boardPixelH - 1)
    end

    local foodX = state.boardX + (state.foodX * cell)
    local foodY = state.boardY + (state.foodY * cell)
    setColor(232, 68, 74)
    lcd.drawFilledRectangle(foodX + 2, foodY + 2, cell - 4, cell - 4)

    for i = #state.snake, 1, -1 do
        local seg = state.snake[i]
        local px = state.boardX + (seg.x * cell)
        local py = state.boardY + (seg.y * cell)

        if i == 1 then
            setColor(120, 244, 138)
            lcd.drawFilledRectangle(px + 1, py + 1, cell - 2, cell - 2)
            setColor(38, 110, 52)
            lcd.drawRectangle(px + 1, py + 1, cell - 2, cell - 2, 1)
        else
            setColor(70, 186, 92)
            lcd.drawFilledRectangle(px + 1, py + 1, cell - 2, cell - 2)
        end
    end
end

local function drawHud(state)
    local x = state.hudX + 6
    local y = state.hudY + 2

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(228, 238, 248)
    lcd.drawText(x, y, "LuaSnake")

    setFont(FONT_XXS or FONT_STD)
    setColor(180, 200, 220)
    lcd.drawText(x, y + 22, string.format("Score  %d", state.score or 0))
    lcd.drawText(x, y + 38, string.format("Best   %d", state.bestScore or 0))
    lcd.drawText(x, y + 54, string.format("Speed  %s", speedLabel(state.config and state.config.speed)))

    setColor(136, 156, 176)
    lcd.drawText(x, state.boardY + state.boardPixelH - 68, "Ail/Ele: Move")
    lcd.drawText(x, state.boardY + state.boardPixelH - 52, "Arrows: Move")
    lcd.drawText(x, state.boardY + state.boardPixelH - 36, "Long Page: Settings")
end

local function drawOverlay(state)
    local boxW = math.floor(state.width * 0.64)
    local boxH = math.floor(state.height * 0.46)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(2, 10, 18)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(118, 150, 182)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(242, 250, 255)

    if state.gameOver then
        if state.winRound then
            drawCenteredText(boxX, boxY + 8, boxW, 22, "YOU WIN")
        else
            drawCenteredText(boxX, boxY + 8, boxW, 22, "GAME OVER")
        end
    else
        drawCenteredText(boxX, boxY + 8, boxW, 22, "LuaSnake")
    end

    setFont(FONT_XXS or FONT_STD)
    setColor(186, 208, 230)

    if state.gameOver then
        drawCenteredText(boxX, boxY + 34, boxW, 18, string.format("Score: %d", state.score or 0))
    else
        drawCenteredText(boxX, boxY + 34, boxW, 18, "Grow the snake and avoid walls")
    end

    drawCenteredText(boxX, boxY + 58, boxW, 18, "Press Enter to start")
    drawCenteredText(boxX, boxY + 78, boxW, 18, "Long Page for settings")
    drawCenteredText(boxX, boxY + 98, boxW, 18, "Exit returns to arcade menu")
end

local function render(state)
    drawBackground(state)
    drawBoard(state)
    drawHud(state)

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

        snake = {},
        foodX = 0,
        foodY = 0,
        dirX = 1,
        dirY = 0,
        nextDirX = 1,
        nextDirY = 0,
        moveTimer = 0,
        stepIntervalBase = stepIntervalBaseForSpeed(loaded.speed),
        stepInterval = stepIntervalBaseForSpeed(loaded.speed),

        moveSourceX = resolveAnalogSource(HORIZONTAL_SOURCE_MEMBER),
        moveSourceY = resolveAnalogSource(VERTICAL_SOURCE_MEMBER),
        lastRawInputByAxis = {},
        analogDirectionCooldown = 0,

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
    if not state.moveSourceY then
        state.moveSourceY = resolveAnalogSource(VERTICAL_SOURCE_MEMBER)
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
        queueDirection(state, -1, 0)
        return true
    end

    if keyMatches(value, KEY_RIGHT_FIRST, KEY_RIGHT_BREAK, KEY_ROTARY_RIGHT) then
        queueDirection(state, 1, 0)
        return true
    end

    if keyMatches(value, KEY_UP_FIRST, KEY_UP_BREAK) then
        queueDirection(state, 0, -1)
        return true
    end

    if keyMatches(value, KEY_DOWN_FIRST, KEY_DOWN_BREAK) then
        queueDirection(state, 0, 1)
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
