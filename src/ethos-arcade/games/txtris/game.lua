local game = {}

local HORIZONTAL_SOURCE_MEMBER = 3
local ROTATE_SOURCE_MEMBER = 1
local DROP_SOURCE_MEMBER = 0
local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local CONFIG_FILE = "txtris.cfg"
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

local BOARD_WIDTH = 18
local BOARD_HEIGHT = 20
local PLAY_ZONE_WIDTH_RATIO = 0.50

local ACTIVE_RENDER_FPS = 36
local IDLE_RENDER_FPS = 12
local GAME_SPEED_MULTIPLIER = 1.00
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.60
local FRAME_SCALE_MAX = 1.90
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local DROP_INTERVAL_BASE_NORMAL = 0.72
local DROP_INTERVAL_BASE_SLOW = 0.90
local DROP_INTERVAL_BASE_FAST = 0.56
local DROP_INTERVAL_MIN = 0.09
local DROP_INTERVAL_STEP = 0.055
local SCORE_BY_LINES = {0, 40, 100, 300, 1200}

local STICK_SOURCE_IS_PERCENT = false
local STICK_RAW_ABS_LIMIT = 5000
local STICK_GLITCH_DELTA_LIMIT = 1900
local STICK_MOVE_THRESHOLD = 300
local STICK_MOVE_REPEAT_INITIAL = 0.16
local STICK_MOVE_REPEAT = 0.08
local STICK_ROTATE_THRESHOLD = 300
local STICK_DROP_THRESHOLD = 300

local PIECES = {
    {
        name = "I",
        color = {80, 220, 240},
        cells = {
            {{0, 1}, {1, 1}, {2, 1}, {3, 1}},
            {{2, 0}, {2, 1}, {2, 2}, {2, 3}},
            {{0, 2}, {1, 2}, {2, 2}, {3, 2}},
            {{1, 0}, {1, 1}, {1, 2}, {1, 3}}
        }
    },
    {
        name = "O",
        color = {240, 220, 80},
        cells = {
            {{1, 0}, {2, 0}, {1, 1}, {2, 1}},
            {{1, 0}, {2, 0}, {1, 1}, {2, 1}},
            {{1, 0}, {2, 0}, {1, 1}, {2, 1}},
            {{1, 0}, {2, 0}, {1, 1}, {2, 1}}
        }
    },
    {
        name = "T",
        color = {190, 90, 240},
        cells = {
            {{1, 0}, {0, 1}, {1, 1}, {2, 1}},
            {{1, 0}, {1, 1}, {2, 1}, {1, 2}},
            {{0, 1}, {1, 1}, {2, 1}, {1, 2}},
            {{1, 0}, {0, 1}, {1, 1}, {1, 2}}
        }
    },
    {
        name = "S",
        color = {120, 230, 120},
        cells = {
            {{1, 0}, {2, 0}, {0, 1}, {1, 1}},
            {{1, 0}, {1, 1}, {2, 1}, {2, 2}},
            {{1, 1}, {2, 1}, {0, 2}, {1, 2}},
            {{0, 0}, {0, 1}, {1, 1}, {1, 2}}
        }
    },
    {
        name = "Z",
        color = {240, 100, 100},
        cells = {
            {{0, 0}, {1, 0}, {1, 1}, {2, 1}},
            {{2, 0}, {1, 1}, {2, 1}, {1, 2}},
            {{0, 1}, {1, 1}, {1, 2}, {2, 2}},
            {{1, 0}, {0, 1}, {1, 1}, {0, 2}}
        }
    },
    {
        name = "J",
        color = {90, 130, 240},
        cells = {
            {{0, 0}, {0, 1}, {1, 1}, {2, 1}},
            {{1, 0}, {2, 0}, {1, 1}, {1, 2}},
            {{0, 1}, {1, 1}, {2, 1}, {2, 2}},
            {{1, 0}, {1, 1}, {0, 2}, {1, 2}}
        }
    },
    {
        name = "L",
        color = {245, 165, 80},
        cells = {
            {{2, 0}, {0, 1}, {1, 1}, {2, 1}},
            {{1, 0}, {1, 1}, {1, 2}, {2, 2}},
            {{0, 1}, {1, 1}, {2, 1}, {0, 2}},
            {{0, 0}, {1, 0}, {1, 1}, {1, 2}}
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

local function isExitKeyEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end
    if keyMatches(value, KEY_EXIT_BREAK, KEY_EXIT_FIRST) then
        return true
    end
    return value == 35
end

local function isHardDropEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end
    if keyMatches(value, KEY_ENTER_LONG) then
        return true
    end
    return false
end

local function isSettingsOpenEvent(category, value)
    return isConfigButtonEvent(category, value)
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

local function dropIntervalBaseForSpeed(speed)
    local normalized = normalizeSpeed(speed)
    if normalized == SPEED_SLOW then
        return DROP_INTERVAL_BASE_SLOW
    end
    if normalized == SPEED_FAST then
        return DROP_INTERVAL_BASE_FAST
    end
    return DROP_INTERVAL_BASE_NORMAL
end

local function computeDropInterval(state, level)
    local lvl = tonumber(level) or 1
    local base = dropIntervalBaseForSpeed(state and state.config and state.config.speed)
    return math.max(DROP_INTERVAL_MIN, base - ((lvl - 1) * DROP_INTERVAL_STEP))
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
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/txtris/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/txtris/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/ethos-arcade/games/txtris/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/txtris/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/txtris/" .. CONFIG_FILE
    paths[#paths + 1] = "scripts/txtris/" .. CONFIG_FILE
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
    return {
        speed = normalizeSpeed(values.speed)
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
    f:close()
    return true
end

local function applyConfigSideEffects(state)
    if not state then
        return
    end

    state.dropIntervalBase = dropIntervalBaseForSpeed(state.config and state.config.speed)
    state.dropInterval = computeDropInterval(state, state.level)
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
    state.nextInvalidateAt = 0
    if lcd and lcd.invalidate then
        lcd.invalidate()
    end
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

    local infoLine = form.addLine("TxTris")
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

local function playTone(freq, duration, pause)
    if not (system and system.playTone) then
        return
    end
    pcall(system.playTone, freq, duration or 20, pause or 0)
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
        state.frameScale = 1
        return
    end

    state.frameScale = clamp(dt / FRAME_TARGET_DT, FRAME_SCALE_MIN, FRAME_SCALE_MAX)
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

local function createEmptyRow()
    local row = {}
    for x = 1, BOARD_WIDTH do
        row[x] = 0
    end
    return row
end

local function resetBoard(state)
    state.board = {}
    for y = 1, BOARD_HEIGHT do
        state.board[y] = createEmptyRow()
    end
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

local function refillBag(state)
    state.bag = {}
    for i = 1, #PIECES do
        state.bag[i] = i
    end
    shuffle(state.bag)
end

local function popFromBag(state)
    if not state.bag or #state.bag == 0 then
        refillBag(state)
    end
    return table.remove(state.bag, 1)
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
    local playZoneW = math.floor(width * PLAY_ZONE_WIDTH_RATIO)
    local boardAreaH = height - (margin * 2)

    -- Use square cells for consistent piece proportions, widen via board columns.
    local cellSize = math.floor(math.min(playZoneW / BOARD_WIDTH, boardAreaH / BOARD_HEIGHT))
    if cellSize < 6 then
        cellSize = 6
    end

    state.cellW = cellSize
    state.cellH = cellSize
    state.playZoneX = margin
    state.playZoneW = playZoneW
    state.boardPixelW = state.cellW * BOARD_WIDTH
    state.boardPixelH = state.cellH * BOARD_HEIGHT
    state.boardX = margin + math.floor((playZoneW - state.boardPixelW) * 0.5)
    state.boardY = math.floor((height - state.boardPixelH) * 0.5)
    state.hudX = margin + playZoneW + margin
    state.hudY = state.boardY
    state.hudWidth = width - state.hudX - margin

    if changed then
        forceInvalidate(state)
    end
end

local function collides(state, piece, offsetX, offsetY, testRot)
    if not piece then return true end

    local cells = PIECES[piece.kind].cells[testRot or piece.rot]
    local ox = offsetX or 0
    local oy = offsetY or 0

    for i = 1, #cells do
        local c = cells[i]
        local x = piece.x + c[1] + ox
        local y = piece.y + c[2] + oy

        if x < 0 or x >= BOARD_WIDTH then
            return true
        end
        if y >= BOARD_HEIGHT then
            return true
        end
        if y >= 0 and state.board[y + 1][x + 1] ~= 0 then
            return true
        end
    end

    return false
end

local function onGameOver(state)
    state.running = false
    state.gameOver = true
    if state.score > state.bestScore then
        state.bestScore = state.score
    end
    playTone(210, 120, 50)
    forceInvalidate(state)
end

local function spawnPiece(state)
    local kind = state.nextKind
    if not kind then
        kind = popFromBag(state)
    end
    state.nextKind = popFromBag(state)

    state.active = {
        kind = kind,
        rot = 1,
        x = math.floor((BOARD_WIDTH - 4) * 0.5),
        y = -1
    }

    if collides(state, state.active, 0, 0, state.active.rot) then
        onGameOver(state)
        return false
    end

    return true
end

local function tryMove(state, dx, dy)
    if not state.active then
        return false
    end

    if collides(state, state.active, dx, dy, state.active.rot) then
        return false
    end

    state.active.x = state.active.x + dx
    state.active.y = state.active.y + dy
    return true
end

local function tryRotate(state, dir)
    if not state.active then
        return false
    end

    local nextRot = ((state.active.rot - 1 + dir) % 4) + 1
    local kicks = {
        {0, 0},
        {-1, 0}, {1, 0},
        {-2, 0}, {2, 0},
        {0, -1}
    }

    for i = 1, #kicks do
        local k = kicks[i]
        if not collides(state, state.active, k[1], k[2], nextRot) then
            state.active.rot = nextRot
            state.active.x = state.active.x + k[1]
            state.active.y = state.active.y + k[2]
            playTone(800, 10, 0)
            return true
        end
    end

    return false
end

local function mergeActivePiece(state)
    if not state.active then
        return
    end

    local cells = PIECES[state.active.kind].cells[state.active.rot]
    for i = 1, #cells do
        local c = cells[i]
        local x = state.active.x + c[1]
        local y = state.active.y + c[2]
        if y >= 0 and y < BOARD_HEIGHT and x >= 0 and x < BOARD_WIDTH then
            state.board[y + 1][x + 1] = state.active.kind
        end
    end
end

local function clearCompletedLines(state)
    local cleared = 0
    local y = BOARD_HEIGHT

    while y >= 1 do
        local full = true
        for x = 1, BOARD_WIDTH do
            if state.board[y][x] == 0 then
                full = false
                break
            end
        end

        if full then
            table.remove(state.board, y)
            table.insert(state.board, 1, createEmptyRow())
            cleared = cleared + 1
        else
            y = y - 1
        end
    end

    if cleared <= 0 then
        return
    end

    state.lines = state.lines + cleared
    state.level = 1 + math.floor(state.lines / 10)
    state.dropInterval = computeDropInterval(state, state.level)
    state.score = state.score + (SCORE_BY_LINES[cleared + 1] or 0) * state.level

    if state.score > state.bestScore then
        state.bestScore = state.score
    end

    if cleared >= 4 then
        playTone(1150, 45, 15)
    else
        playTone(750, 25, 5)
    end
end

local function lockActivePiece(state)
    mergeActivePiece(state)
    clearCompletedLines(state)
    state.active = nil
    spawnPiece(state)
end

local function hardDrop(state)
    if not state.active then
        return
    end

    local dropped = 0
    while tryMove(state, 0, 1) do
        dropped = dropped + 1
    end

    state.score = state.score + (dropped * 2)
    lockActivePiece(state)
    playTone(500, 12, 0)
end

local function softDropStep(state)
    if not state.active then
        return
    end

    if tryMove(state, 0, 1) then
        state.score = state.score + 1
        return
    end

    lockActivePiece(state)
end

local function startGame(state)
    resetBoard(state)
    state.bag = {}
    state.nextKind = nil
    state.active = nil

    state.running = true
    state.gameOver = false
    state.score = 0
    state.lines = 0
    state.level = 1
    state.dropInterval = computeDropInterval(state, state.level)
    state.gravityTimer = 0
    state.analogDir = 0
    state.analogRepeatTimer = 0
    state.rotateStickLatch = false
    state.dropStickLatch = false

    refillBag(state)
    spawnPiece(state)
    forceInvalidate(state)
end

local function updateAnalogControls(state, dt)
    if not state.running then
        return
    end

    local rawMove = sanitizeStickSample(state, sourceValue(state.moveSourceX), "move")
    local rawRotate = sanitizeStickSample(state, sourceValue(state.rotateSource), "rotate")
    local rawDrop = sanitizeStickSample(state, sourceValue(state.dropSource), "drop")

    if math.abs(rawRotate) >= STICK_ROTATE_THRESHOLD then
        if not state.rotateStickLatch then
            tryRotate(state, 1)
            forceInvalidate(state)
        end
        state.rotateStickLatch = true
    else
        state.rotateStickLatch = false
    end

    local direction = 0
    if rawMove > STICK_MOVE_THRESHOLD then
        direction = 1
    elseif rawMove < -STICK_MOVE_THRESHOLD then
        direction = -1
    end

    if direction == 0 then
        state.analogDir = 0
        state.analogRepeatTimer = 0
    elseif direction ~= state.analogDir then
        state.analogDir = direction
        state.analogRepeatTimer = STICK_MOVE_REPEAT_INITIAL
        tryMove(state, direction, 0)
        forceInvalidate(state)
    else
        state.analogRepeatTimer = state.analogRepeatTimer - dt
        while state.analogRepeatTimer <= 0 do
            tryMove(state, direction, 0)
            state.analogRepeatTimer = state.analogRepeatTimer + STICK_MOVE_REPEAT
            forceInvalidate(state)
        end
    end

    local dropActive = math.abs(rawDrop) >= STICK_DROP_THRESHOLD
    if dropActive then
        if not state.dropStickLatch then
            hardDrop(state)
            forceInvalidate(state)
        end
        state.dropStickLatch = true
    else
        state.dropStickLatch = false
    end
end

local function updateGame(state, dt)
    if not (state.running and state.active) then
        return
    end

    updateAnalogControls(state, dt)

    state.gravityTimer = state.gravityTimer + dt
    while state.gravityTimer >= state.dropInterval do
        state.gravityTimer = state.gravityTimer - state.dropInterval
        if not tryMove(state, 0, 1) then
            lockActivePiece(state)
            if not state.running then
                return
            end
        end
    end
end

local function pieceColor(kind, dim)
    local base = PIECES[kind].color
    local factor = dim and 0.35 or 1.00
    return
        clamp(math.floor(base[1] * factor), 0, 255),
        clamp(math.floor(base[2] * factor), 0, 255),
        clamp(math.floor(base[3] * factor), 0, 255)
end

local function drawCell(state, gx, gy, kind, dim)
    if gy < 0 or gy >= BOARD_HEIGHT then
        return
    end

    local px = state.boardX + (gx * state.cellW)
    local py = state.boardY + (gy * state.cellH)
    local r, g, b = pieceColor(kind, dim)

    if dim then
        setColor(r, g, b)
        lcd.drawRectangle(px + 1, py + 1, state.cellW - 2, state.cellH - 2, 1)
        return
    end

    setColor(r, g, b)
    lcd.drawFilledRectangle(px, py, state.cellW, state.cellH)
    setColor(r + 25, g + 25, b + 25)
    lcd.drawRectangle(px, py, state.cellW, state.cellH, 1)
end

local function ghostY(state, piece)
    if not piece then
        return nil
    end

    local y = piece.y
    local ghost = {kind = piece.kind, rot = piece.rot, x = piece.x, y = piece.y}
    while not collides(state, ghost, 0, 1, ghost.rot) do
        ghost.y = ghost.y + 1
        y = ghost.y
    end
    return y
end

local function drawPiece(state, piece, dim, overrideY)
    if not piece then
        return
    end

    local yBase = overrideY or piece.y
    local cells = PIECES[piece.kind].cells[piece.rot]
    for i = 1, #cells do
        local c = cells[i]
        drawCell(state, piece.x + c[1], yBase + c[2], piece.kind, dim)
    end
end

local function drawBoard(state)
    local shellX = state.playZoneX or state.boardX
    local shellY = state.boardY - 2
    local shellW = state.playZoneW or (state.boardPixelW + 4)
    local shellH = state.boardPixelH + 4

    setColor(10, 18, 30)
    lcd.drawFilledRectangle(shellX, shellY, shellW, shellH)
    setColor(58, 76, 104)
    lcd.drawRectangle(shellX, shellY, shellW, shellH, 1)

    local leftW = (state.boardX - 2) - shellX
    local rightX = state.boardX + state.boardPixelW + 2
    local rightW = (shellX + shellW) - rightX
    if leftW > 0 then
        setColor(14, 24, 40)
        lcd.drawFilledRectangle(shellX, shellY + 1, leftW, shellH - 2)
    end
    if rightW > 0 then
        setColor(14, 24, 40)
        lcd.drawFilledRectangle(rightX, shellY + 1, rightW, shellH - 2)
    end
    setColor(42, 58, 82)
    lcd.drawFilledRectangle(state.boardX - 3, shellY, 1, shellH)
    lcd.drawFilledRectangle(state.boardX + state.boardPixelW + 2, shellY, 1, shellH)

    setColor(8, 14, 24)
    lcd.drawFilledRectangle(state.boardX - 2, state.boardY - 2, state.boardPixelW + 4, state.boardPixelH + 4)
    setColor(95, 115, 145)
    lcd.drawRectangle(state.boardX - 2, state.boardY - 2, state.boardPixelW + 4, state.boardPixelH + 4, 2)

    for y = 1, BOARD_HEIGHT do
        local row = state.board[y]
        for x = 1, BOARD_WIDTH do
            local kind = row[x]
            if kind ~= 0 then
                drawCell(state, x - 1, y - 1, kind, false)
            end
        end
    end

    if state.active then
        local gy = ghostY(state, state.active)
        if gy and gy > state.active.y then
            drawPiece(state, state.active, true, gy)
        end
        drawPiece(state, state.active, false, state.active.y)
    end
end

local function drawNextPreview(state)
    if not state.nextKind then
        return
    end

    local startX = state.hudX + 12
    local startY = state.hudY + 116
    local previewCell = math.max(4, math.floor(math.min(state.cellW, state.cellH) * 0.80))
    local cells = PIECES[state.nextKind].cells[1]

    local minX, minY = 9, 9
    local maxX, maxY = -9, -9
    for i = 1, #cells do
        local c = cells[i]
        if c[1] < minX then minX = c[1] end
        if c[2] < minY then minY = c[2] end
        if c[1] > maxX then maxX = c[1] end
        if c[2] > maxY then maxY = c[2] end
    end

    local spanW = (maxX - minX + 1) * previewCell
    local frameW = math.max(spanW + 12, 58)
    local frameH = math.max((maxY - minY + 1) * previewCell + 12, 46)

    setColor(12, 20, 34)
    lcd.drawFilledRectangle(startX, startY, frameW, frameH)
    setColor(88, 110, 138)
    lcd.drawRectangle(startX, startY, frameW, frameH, 1)

    local px0 = startX + math.floor((frameW - spanW) * 0.5)
    local py0 = startY + math.floor((frameH - ((maxY - minY + 1) * previewCell)) * 0.5)
    local r, g, b = pieceColor(state.nextKind, false)

    for i = 1, #cells do
        local c = cells[i]
        local gx = c[1] - minX
        local gy = c[2] - minY
        local px = px0 + gx * previewCell
        local py = py0 + gy * previewCell
        setColor(r, g, b)
        lcd.drawFilledRectangle(px + 1, py + 1, previewCell - 1, previewCell - 1)
        setColor(r + 25, g + 25, b + 25)
        lcd.drawRectangle(px, py, previewCell, previewCell, 1)
    end
end

local function drawHud(state)
    local x = state.hudX + 6
    local y = state.hudY + 4

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(230, 237, 246)
    lcd.drawText(x, y, "TxTris")

    setFont(FONT_XXS or FONT_STD)
    setColor(180, 195, 214)
    lcd.drawText(x, y + 24, string.format("Score  %d", state.score))
    lcd.drawText(x, y + 40, string.format("Best   %d", state.bestScore))
    lcd.drawText(x, y + 56, string.format("Lines  %d", state.lines))
    lcd.drawText(x, y + 72, string.format("Level  %d", state.level))
    lcd.drawText(x, y + 88, string.format("Speed  %s", speedLabel(state.config and state.config.speed)))
    lcd.drawText(x, y + 96, "Next")

    drawNextPreview(state)

    setColor(145, 163, 190)
    lcd.drawText(x, state.hudY + state.boardPixelH - 86, "Aileron: Move")
    lcd.drawText(x, state.hudY + state.boardPixelH - 70, "Elevator: Rotate")
    lcd.drawText(x, state.hudY + state.boardPixelH - 54, "Rudder: Instant Drop")
    lcd.drawText(x, state.hudY + state.boardPixelH - 38, "Long Page: Settings")
end

local function drawOverlay(state)
    local boxW = math.floor(state.width * 0.70)
    local boxH = math.floor(state.height * 0.48)
    local boxX = math.floor((state.width - boxW) * 0.5)
    local boxY = math.floor((state.height - boxH) * 0.5)

    setColor(4, 14, 24)
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
    setColor(136, 166, 198)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, 2)

    setFont(FONT_L_BOLD or FONT_STD)
    setColor(235, 243, 255)

    if state.gameOver then
        drawCenteredText(boxX, boxY + 10, boxW, 24, "GAME OVER")
    else
        drawCenteredText(boxX, boxY + 10, boxW, 24, "TxTris")
    end

    setFont(FONT_XXS or FONT_STD)
    setColor(187, 204, 225)

    if state.gameOver then
        drawCenteredText(boxX, boxY + 46, boxW, 18, string.format("Score %d   Best %d", state.score, state.bestScore))
        drawCenteredText(boxX, boxY + 68, boxW, 18, string.format("Lines %d   Level %d", state.lines, state.level))
        drawCenteredText(boxX, boxY + 96, boxW, 18, "Press Enter to restart")
        drawCenteredText(boxX, boxY + 118, boxW, 18, string.format("Long Page: Settings (%s)", speedLabel(state.config and state.config.speed)))
    else
        drawCenteredText(boxX, boxY + 46, boxW, 18, "Classic Tetris for Ethos")
        drawCenteredText(boxX, boxY + 68, boxW, 18, "Move, rotate, clear lines")
        drawCenteredText(boxX, boxY + 96, boxW, 18, "Press Enter to start")
        drawCenteredText(boxX, boxY + 118, boxW, 18, string.format("Long Page: Settings (%s)", speedLabel(state.config and state.config.speed)))
    end
end

local function render(state)
    setColor(10, 18, 30)
    lcd.drawFilledRectangle(0, 0, state.width, state.height)

    drawBoard(state)
    drawHud(state)

    if not state.running then
        drawOverlay(state)
    end
end

local function createState()
    local loadedConfig = loadStateConfig()
    local state = {
        width = 0,
        height = 0,
        boardX = 0,
        boardY = 0,
        boardPixelW = 0,
        boardPixelH = 0,
        playZoneX = 0,
        playZoneW = 0,
        hudX = 0,
        hudY = 0,
        hudWidth = 0,
        cellW = 10,
        cellH = 10,
        board = {},
        bag = {},
        active = nil,
        nextKind = nil,
        running = false,
        gameOver = false,
        score = 0,
        bestScore = 0,
        lines = 0,
        level = 1,
        dropInterval = DROP_INTERVAL_BASE_NORMAL,
        dropIntervalBase = DROP_INTERVAL_BASE_NORMAL,
        gravityTimer = 0,
        frameScale = 1,
        lastFrameTime = 0,
        nextInvalidateAt = 0,
        config = loadedConfig,
        moveSourceX = resolveAnalogSource(HORIZONTAL_SOURCE_MEMBER),
        rotateSource = resolveAnalogSource(ROTATE_SOURCE_MEMBER),
        dropSource = resolveAnalogSource(DROP_SOURCE_MEMBER),
        settingsFormOpen = false,
        pendingFormClear = false,
        lastRawInputByAxis = {},
        analogDir = 0,
        analogRepeatTimer = 0,
        rotateStickLatch = false,
        dropStickLatch = false,
        lastFocusKick = 0,
        suppressExitUntil = 0,
        suppressEnterUntil = 0
    }

    refreshGeometry(state)
    resetBoard(state)
    setConfigValue(state, "speed", state.config.speed, true)
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
    if not state.rotateSource then
        state.rotateSource = resolveAnalogSource(ROTATE_SOURCE_MEMBER)
    end
    if not state.dropSource then
        state.dropSource = resolveAnalogSource(DROP_SOURCE_MEMBER)
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
            state.active = nil
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
        state.active = nil
        suppressExitEvents(state)
        forceInvalidate(state)
        return true
    end

    if keyMatches(value, KEY_LEFT_FIRST, KEY_LEFT_BREAK, KEY_ROTARY_LEFT) then
        tryMove(state, -1, 0)
        forceInvalidate(state)
        return true
    end

    if keyMatches(value, KEY_RIGHT_FIRST, KEY_RIGHT_BREAK, KEY_ROTARY_RIGHT) then
        tryMove(state, 1, 0)
        forceInvalidate(state)
        return true
    end

    if keyMatches(value, KEY_UP_FIRST, KEY_UP_BREAK) then
        tryRotate(state, 1)
        forceInvalidate(state)
        return true
    end

    if keyMatches(value, KEY_DOWN_FIRST, KEY_DOWN_BREAK) then
        softDropStep(state)
        forceInvalidate(state)
        return true
    end

    if isHardDropEvent(category, value) then
        hardDrop(state)
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

    local dt = (FRAME_TARGET_DT * state.frameScale) * GAME_SPEED_MULTIPLIER
    if state.running then
        updateGame(state, dt)
    end

    render(state)
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
