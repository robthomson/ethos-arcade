local game = {}

local CONFIG_FILE = "shooter.cfg"
local CONFIG_VERSION = 1
local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128

local DIFFICULTY_EASY = 1
local DIFFICULTY_MEDIUM = 2
local DIFFICULTY_HARD = 3

local DIFFICULTY_CHOICES_FORM = {
    {"Easy", DIFFICULTY_EASY},
    {"Medium", DIFFICULTY_MEDIUM},
    {"Hard", DIFFICULTY_HARD}
}

local SOURCE_X_MEMBER = 3
local SOURCE_Y_MEMBER = 1

local STICK_SOURCE_IS_PERCENT = false
local INPUT_DEADZONE = 0.03
local INPUT_FILTER_ALPHA = 0.18

local AIM_PAD = 10
local SHOT_LIFE = 0.4

local BIRD_DEFS = {
    {id = "jeti", label = "Jeti", good = true},
    {id = "spektrum", label = "Spektrum", good = true},
    {id = "edgetx", label = "EdgeTX", good = true},
    {id = "vbar", label = "VBar", good = true},
    {id = "ethos", label = "FrSky", good = false}
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function nowSeconds()
    if os and os.clock then
        return os.clock()
    end
    return 0
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

local function isFireButtonEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end
    if keyMatches(value, KEY_PAGE_FIRST, KEY_PAGE_BREAK) then
        return true
    end
    return false
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

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function mapInputToArea(value, minValue, maxValue)
    return minValue + (maxValue - minValue) * ((value + 1024) / 2048)
end

local function setColor(r, g, b)
    if lcd and lcd.color and lcd.RGB then
        pcall(lcd.color, lcd.RGB(r, g, b))
        return
    end
    if lcd and lcd.setColor then
        pcall(lcd.setColor, r, g, b)
    end
end

local function bitmapSize(bitmap)
    if not bitmap then
        return nil, nil
    end
    if bitmap.width then
        local okW, w = pcall(bitmap.width, bitmap)
        local okH, h = pcall(bitmap.height, bitmap)
        if okW and okH then
            return w, h
        end
    end
    return nil, nil
end

local function assetPaths(rel)
    local paths = {}
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/shooter/gfx/" .. rel
    return paths
end

local function loadBitmapAsset(pathCandidates)
    if not (lcd and lcd.loadBitmap and pathCandidates) then
        return nil
    end

    for i = 1, #pathCandidates do
        local path = pathCandidates[i]
        local ok, bitmap = pcall(lcd.loadBitmap, path)
        if ok and bitmap then
            return bitmap
        end
    end
    return nil
end

local function loadConfig()
    local cfg = {version = CONFIG_VERSION, difficulty = DIFFICULTY_MEDIUM, bestScore = 0}
    local file = io.open(CONFIG_FILE, "r")
    if not file then
        return cfg
    end
    while true do
        local line = file:read("*l")
        if not line then
            break
        end
        local key, value = string.match(line, "^([%w_]+)%s*=%s*(.-)%s*$")
        if key == "difficulty" then
            cfg.difficulty = tonumber(value) or cfg.difficulty
        elseif key == "bestScore" then
            cfg.bestScore = tonumber(value) or cfg.bestScore
        elseif key == "version" then
            cfg.version = tonumber(value) or cfg.version
        end
    end
    file:close()
    return cfg
end

local function saveConfig(cfg)
    local file = io.open(CONFIG_FILE, "w")
    if not file then
        return
    end
    file:write("version=", tostring(CONFIG_VERSION), "\n")
    file:write("difficulty=", tostring(cfg.difficulty or DIFFICULTY_MEDIUM), "\n")
    file:write("bestScore=", tostring(cfg.bestScore or 0), "\n")
    file:close()
end

local function normalizeDifficulty(value)
    if value == DIFFICULTY_EASY then return DIFFICULTY_EASY end
    if value == DIFFICULTY_HARD then return DIFFICULTY_HARD end
    return DIFFICULTY_MEDIUM
end

local function difficultyChoiceValue(value)
    local norm = normalizeDifficulty(value)
    if norm == DIFFICULTY_EASY then return 1 end
    if norm == DIFFICULTY_HARD then return 3 end
    return 2
end

local function difficultyFromChoice(value)
    if tonumber(value) == 1 then return DIFFICULTY_EASY end
    if tonumber(value) == 3 then return DIFFICULTY_HARD end
    return DIFFICULTY_MEDIUM
end

local function difficultyLabel(value)
    if value == DIFFICULTY_EASY then return "Easy" end
    if value == DIFFICULTY_HARD then return "Hard" end
    return "Medium"
end

local function difficultyParams(value)
    local diff = normalizeDifficulty(value)
    if diff == DIFFICULTY_EASY then
        return {spawnInterval = 1.1, speedMin = 40, speedMax = 70, maxBirds = 4}
    elseif diff == DIFFICULTY_HARD then
        return {spawnInterval = 0.55, speedMin = 90, speedMax = 140, maxBirds = 7}
    end
    return {spawnInterval = 0.8, speedMin = 60, speedMax = 100, maxBirds = 5}
end

local function createBird(state)
    local params = difficultyParams(state.config.difficulty)
    local def = BIRD_DEFS[math.random(1, #BIRD_DEFS)]
    if state.spawnFlip == nil then
        state.spawnFlip = true
    end
    local direction = state.spawnFlip and 1 or -1
    state.spawnFlip = not state.spawnFlip
    local bitmapSet = state.assets[def.id] or {}
    local bitmap = (direction > 0) and bitmapSet.r or bitmapSet.l
    local bw, bh = bitmapSize(bitmap)
    bw = bw or 24
    bh = bh or 16
    local x
    if direction > 0 then
        x = -bw - 4
    else
        x = state.width + 4
    end

    local yMin = 20
    local yMax = math.max(40, math.floor(state.height * 0.55))
    local y = math.random(yMin, yMax)

    local speed = math.random(params.speedMin, params.speedMax) * direction

    return {
        def = def,
        bitmap = nil,
        x = x,
        y = y,
        w = bw,
        h = bh,
        vx = speed,
        alive = true,
        direction = direction
    }
end

local function resetRound(state)
    state.birds = {}
    state.shotsFx = {}
    state.score = 0
    state.shots = 0
    state.hits = 0
    state.lastSpawn = nowSeconds()
    state.running = true
    state.showIntro = false
end

local function updateAim(state, dt)
    if not (state.sourceX and state.sourceY) then
        return
    end

    local rawX = normalizeStick(sourceValue(state.sourceX))
    local rawY = normalizeStick(sourceValue(state.sourceY))

    local inputX = applyInputResponse(rawX)
    local inputY = applyInputResponse(rawY)

    local targetX = mapInputToArea(inputX, AIM_PAD, state.width - AIM_PAD)
    local targetY = mapInputToArea(inputY, state.height - AIM_PAD, AIM_PAD)

    local alpha = INPUT_FILTER_ALPHA
    state.aimX = lerp(state.aimX, targetX, clamp(dt * 10 * alpha, 0, 1))
    state.aimY = lerp(state.aimY, targetY, clamp(dt * 10 * alpha, 0, 1))
end

local function updateBirds(state, dt)
    if not state.running then
        return
    end

    local params = difficultyParams(state.config.difficulty)
    local now = nowSeconds()
    if (now - state.lastSpawn) >= params.spawnInterval and #state.birds < params.maxBirds then
        state.lastSpawn = now
        state.birds[#state.birds + 1] = createBird(state)
    end

    for i = #state.birds, 1, -1 do
        local bird = state.birds[i]
        bird.x = bird.x + bird.vx * dt
        bird.direction = (bird.vx >= 0) and 1 or -1

        if bird.x < -bird.w - 10 or bird.x > state.width + 10 then
            table.remove(state.birds, i)
        end
    end

    for i = #state.shotsFx, 1, -1 do
        local fx = state.shotsFx[i]
        fx.t = fx.t - dt
        if fx.t <= 0 then
            table.remove(state.shotsFx, i)
        end
    end

end

local function playTone(freq, duration, pause)
    if not (system and system.playTone) then
        return
    end
    pcall(system.playTone, freq, duration or 30, pause or 0)
end

local function handleShot(state)
    if not state.running then
        return
    end

    state.shots = state.shots + 1

    local hitIndex
    for i, bird in ipairs(state.birds) do
        local cx = bird.x + (bird.w * 0.5)
        local cy = bird.y + (bird.h * 0.5)
        local halfW = bird.w * 0.25
        local halfH = bird.h * 0.25
        if state.aimX >= (cx - halfW) and state.aimX <= (cx + halfW) and state.aimY >= (cy - halfH) and state.aimY <= (cy + halfH) then
            hitIndex = i
            break
        end
    end

    if hitIndex then
        local bird = state.birds[hitIndex]
        table.remove(state.birds, hitIndex)

        local shotBitmap = (bird.direction > 0) and state.shotBitmapR or state.shotBitmapL
        state.shotsFx[#state.shotsFx + 1] = {
            x = bird.x,
            y = bird.y,
            w = bird.w,
            h = bird.h,
            direction = bird.direction,
            bitmap = shotBitmap,
            t = SHOT_LIFE
        }

        if bird.def.good then
            state.hits = state.hits + 1
            state.score = state.score + 10
            playTone(1200, 60, 0)
        else
            state.score = state.score - 15
            playTone(240, 80, 0)
        end
    else
        state.score = state.score - 1
        playTone(240, 60, 0)
    end

    if state.score > (state.config.bestScore or 0) then
        state.config.bestScore = state.score
        saveConfig(state.config)
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

local function closeSettingsForm(state)
    state.settingsFormOpen = false
    state.pendingFormClear = true
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

    local infoLine = form.addLine("Shooter")
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
            state.config.difficulty = difficultyFromChoice(newValue)
            saveConfig(state.config)
        end
    )

    local backLine = form.addLine("")
    local backAction = function()
        closeSettingsForm(state)
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

    state.width = width
    state.height = height
    state.aimX = clamp(state.aimX or math.floor(width * 0.5), AIM_PAD, width - AIM_PAD)
    state.aimY = clamp(state.aimY or math.floor(height * 0.7), AIM_PAD, height - AIM_PAD)
end

local function render(state)
    if state.bgBitmap then
        lcd.drawBitmap(0, 0, state.bgBitmap)
    else
        setColor(20, 24, 28)
        lcd.drawFilledRectangle(0, 0, state.width, state.height)
    end

    for _, bird in ipairs(state.birds) do
        local bitmap = bird.bitmap
        if not bitmap then
            local bitmapSet = state.assets[bird.def.id] or {}
            bitmap = (bird.direction > 0) and bitmapSet.r or bitmapSet.l
        end
        if bitmap and (not bird.w or not bird.h or bird.w <= 0 or bird.h <= 0) then
            local bw, bh = bitmapSize(bitmap)
            if bw and bh then
                bird.w = bw
                bird.h = bh
            end
        end
        if bitmap then
            lcd.drawBitmap(math.floor(bird.x), math.floor(bird.y), bitmap)
        else
            setColor(200, 200, 200)
            lcd.drawRectangle(math.floor(bird.x), math.floor(bird.y), bird.w, bird.h)
        end
    end

    for _, fx in ipairs(state.shotsFx) do
        if fx.bitmap then
            lcd.drawBitmap(math.floor(fx.x), math.floor(fx.y), fx.bitmap)
        else
            setColor(255, 120, 120)
            lcd.drawRectangle(math.floor(fx.x), math.floor(fx.y), fx.w, fx.h)
        end
    end

    local cross = 12
    local ring = 14
    setColor(0, 0, 0)
    lcd.drawCircle(state.aimX, state.aimY, ring + 1)
    lcd.drawLine(state.aimX - cross - 1, state.aimY, state.aimX + cross + 1, state.aimY)
    lcd.drawLine(state.aimX, state.aimY - cross - 1, state.aimX, state.aimY + cross + 1)

    setColor(255, 230, 120)
    lcd.drawCircle(state.aimX, state.aimY, ring)
    lcd.drawLine(state.aimX - cross, state.aimY, state.aimX + cross, state.aimY)
    lcd.drawLine(state.aimX, state.aimY - cross, state.aimX, state.aimY + cross)
    lcd.drawRectangle(state.aimX - 3, state.aimY - 3, 6, 6)

    setColor(0, 0, 0)
    local scoreLine = string.format("Score %d  Best %d  Diff %s", state.score or 0, state.config.bestScore or 0, difficultyLabel(state.config.difficulty))
    local estimateW = #scoreLine * 6
    local scoreX = math.floor((state.width - estimateW) * 0.5)
    if scoreX < 2 then scoreX = 2 end
    lcd.drawText(scoreX, 2, scoreLine)

    if not state.running and state.showIntro then
        local boxW = math.floor(state.width * 0.78)
        local boxH = math.floor(state.height * 0.48)
        local boxX = math.floor((state.width - boxW) * 0.5)
        local boxY = math.floor((state.height - boxH) * 0.5)

        setColor(24, 28, 32)
        lcd.drawFilledRectangle(boxX, boxY, boxW, boxH)
        setColor(180, 190, 200)
        lcd.drawRectangle(boxX, boxY, boxW, boxH)

        setColor(255, 255, 255)
        lcd.drawText(boxX + 14, boxY + 14, "Shooter")
        lcd.drawText(boxX + 14, boxY + 38, "Make sure you shoot the right bird")
        lcd.drawText(boxX + 14, boxY + 64, "Aim: Aileron / Elevator")
        lcd.drawText(boxX + 14, boxY + 88, "Fire: Page")
        lcd.drawText(boxX + 14, boxY + 112, "Enter: start")
        lcd.drawText(boxX + 14, boxY + 136, "Exit: back to arcade")
        lcd.drawText(boxX + 14, boxY + 160, "Long Enter: settings")
    end

end

function game.create()
    local state = {
        config = loadConfig(),
        assets = {},
        birds = {},
        shotsFx = {},
        running = false,
        score = 0,
        shots = 0,
        hits = 0,
        lastSpawn = 0,
        showIntro = true,
        suppressExitUntil = 0,
        settingsFormOpen = false,
        pendingFormClear = false
    }

    math.randomseed(math.floor(nowSeconds() * 1000))

    state.sourceX = resolveAnalogSource(SOURCE_X_MEMBER)
    state.sourceY = resolveAnalogSource(SOURCE_Y_MEMBER)

    for _, def in ipairs(BIRD_DEFS) do
        state.assets[def.id] = {
            l = loadBitmapAsset(assetPaths(def.id .. "-l.png")),
            r = loadBitmapAsset(assetPaths(def.id .. "-r.png"))
        }
    end
    state.shotBitmapL = loadBitmapAsset(assetPaths("shot-l.png"))
    state.shotBitmapR = loadBitmapAsset(assetPaths("shot-r.png"))
    state.bgBitmap = loadBitmapAsset(assetPaths("back.png"))

    refreshGeometry(state)

    return state
end

function game.wakeup(state)
    if not state then
        return
    end

    refreshGeometry(state)

    if state.pendingFormClear and not state.settingsFormOpen then
        if safeFormClear() then
            state.pendingFormClear = false
        end
    end

    local now = nowSeconds()
    local last = state.lastFrame or now
    local dt = now - last
    if dt < 0 then dt = 0 end
    if dt > 0.2 then dt = 0.2 end
    state.lastFrame = now

    updateAim(state, dt)
    updateBirds(state, dt)

    if lcd and lcd.invalidate then
        pcall(lcd.invalidate)
    end
end

function game.event(state, category, value)
    if not state then
        return false
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
            state.showIntro = true
            suppressExitEvents(state)
            return true
        end
        return false
    end

    if isSettingsOpenEvent(category, value) then
        openSettingsForm(state)
        return true
    end

    if isKeyCategory(category) and keyMatches(value, KEY_ENTER_FIRST, KEY_ENTER_BREAK) then
        if not state.running then
            resetRound(state)
            return true
        end
    end

    if isFireButtonEvent(category, value) then
        handleShot(state)
        return true
    end

    if isExitKeyEvent(category, value) then
        if state.running then
            state.running = false
            state.showIntro = true
            suppressExitEvents(state)
            return true
        end
        return false
    end

    return false
end

function game.paint(state)
    if not state then
        return
    end
    render(state)
end

function game.close(state)
    if not state then
        return
    end
    if state.settingsFormOpen then
        closeSettingsForm(state)
    end
end

return game
