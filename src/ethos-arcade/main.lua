local APP_NAME = "Ethos Arcade"
local DEBUG_EVENTS = false
local DEBUG_GC = true

local games = {
    {
        id = "luapong",
        name = "LuaPong",
        description = "Arcade paddle duel",
        modulePath = "games/luapong/game.lua",
        iconPath = "games/luapong/gfx/icon.png"
    },
    {
        id = "txtris",
        name = "TxTris",
        description = "Block stack challenge",
        modulePath = "games/txtris/game.lua",
        iconPath = "games/txtris/gfx/icon.png"
    },
    {
        id = "luasnake",
        name = "LuaSnake",
        description = "Classic snake maze",
        modulePath = "games/luasnake/game.lua",
        iconPath = "games/luasnake/gfx/icon.png"
    },
    {
        id = "luafrog",
        name = "LuaFrog",
        description = "Road-and-river crossing challenge",
        modulePath = "games/luafrog/game.lua",
        iconPath = "games/luafrog/gfx/icon.png"
    },
    {
        id = "luadefender",
        name = "LuaDefender",
        description = "Side-scroll alien defense",
        modulePath = "games/luadefender/game.lua",
        iconPath = "games/luadefender/gfx/icon.png"
    },
    {
        id = "retrofight",
        name = "Dojo",
        description = "8-bit stick-and-punch brawler",
        modulePath = "games/retrofight/game.lua",
        iconPath = "games/retrofight/gfx/icon.png"
    },
    {
        id = "luabreaks",
        name = "LuaBreaks",
        description = "Brick breaker blitz",
        modulePath = "games/luabreaks/game.lua",
        iconPath = "games/luabreaks/gfx/icon.png"
    },
    {
        id = "gates",
        name = "Gates",
        description = "FPV gate runner",
        modulePath = "games/gates/game.lua",
        iconPath = "games/gates/gfx/icon.png"
    },
    {
        id = "missilecmd",
        name = "MissileCmd",
        description = "Single-base interceptor defense",
        modulePath = "games/missilecmd/game.lua",
        iconPath = "games/missilecmd/gfx/icon.png"
    },
    {
        id = "gulaxian",
        name = "GaLuaxian",
        description = "Scrolling space shooter",
        modulePath = "games/gulaxian/game.lua",
        iconPath = "games/gulaxian/gfx/icon.png"
    }
}

local function keyMatches(value, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        if key and value == key then
            return true
        end
    end
    return false
end

local function debugEvent(state, category, value)
    if not DEBUG_EVENTS then
        return
    end

    local scope = "menu"
    if state and state.activeDef and state.activeDef.id then
        scope = state.activeDef.id
    end

    print(string.format("[arcade event] scope=%s category=%s value=%s", scope, tostring(category), tostring(value)))
end

local function isKeyCategory(category)
    if type(EVT_KEY) == "number" then
        return category == EVT_KEY
    end
    return category == 0
end

local function isCloseEvent(category)
    -- Close should primarily be detected from EVT_CLOSE category.
    if type(EVT_CLOSE) == "number" and category == EVT_CLOSE then
        return true
    end

    return false
end

local function isExitKeyEvent(category, value)
    if not isKeyCategory(category) then
        return false
    end

    if keyMatches(value, KEY_EXIT_FIRST, KEY_EXIT_BREAK) then
        return true
    end

    -- Fallback seen on some keypads/radios.
    return value == 35
end

local function nowSeconds()
    if os and os.clock then
        return os.clock()
    end
    return 0
end

local function suppressExitEvents(state, windowSeconds)
    if not state then
        return
    end
    state.suppressExitUntil = nowSeconds() + (windowSeconds or 0.35)
end

local function shouldSuppressExit(state)
    if not state or not state.suppressExitUntil then
        return false
    end
    return nowSeconds() < state.suppressExitUntil
end

local function loadIcon(path)
    local okMask, mask = pcall(lcd.loadMask, path)
    if okMask and mask then
        return mask
    end

    local okBitmap, bitmap = pcall(lcd.loadBitmap, path)
    if okBitmap and bitmap then
        return bitmap
    end

    return nil
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

local function loadGameModule(def)
    if not def then
        return nil, "Missing game definition"
    end

    if def.module then
        return def.module
    end

    local chunk, err = loadfile(def.modulePath)
    if not chunk then
        return nil, err
    end

    local ok, module = pcall(chunk)
    if not ok then
        return nil, module
    end

    if type(module) ~= "table" then
        return nil, "Module did not return a table"
    end

    def.module = module
    return module
end

local function clearMenuForm(state)
    if state then
        state.menuBuilt = false
        state.menuButtons = nil
        state.menuClearRequested = true
    end
end

local function releaseAssets(value, visited)
    if value == nil then
        return
    end
    local valueType = type(value)
    if valueType == "userdata" then
        return
    end
    if valueType ~= "table" then
        return
    end
    if not visited then
        visited = {}
    end
    if visited[value] then
        return
    end
    visited[value] = true

    for key, item in pairs(value) do
        local keyType = type(key)
        local itemType = type(item)
        local keyName = keyType == "string" and key:lower() or ""
        if itemType == "userdata" then
            value[key] = nil
        elseif itemType == "table" then
            if keyName:find("bitmap", 1, true) or keyName:find("mask", 1, true) or keyName:find("image", 1, true) then
                value[key] = nil
            else
                releaseAssets(item, visited)
            end
        elseif keyType == "string" and (keyName:find("bitmap", 1, true) or keyName:find("mask", 1, true) or keyName:find("image", 1, true)) then
            value[key] = nil
        end
    end
end

local function stopActiveGame(state)
    if not state then
        return
    end

    local memBefore
    if DEBUG_GC and collectgarbage then
        local ok, value = pcall(collectgarbage, "count")
        if ok then
            memBefore = value
        end
    end

    if state.activeModule and state.activeState and type(state.activeModule.close) == "function" then
        pcall(state.activeModule.close, state.activeState)
    end

    if state.activeState then
        releaseAssets(state.activeState)
    end

    if state.activeDef then
        state.activeDef.module = nil
    end

    state.activeDef = nil
    state.activeModule = nil
    state.activeState = nil
    clearMenuForm(state)

    if collectgarbage then
        pcall(collectgarbage, "collect")
        pcall(collectgarbage, "collect")
    end

    if DEBUG_GC and collectgarbage then
        local ok, after = pcall(collectgarbage, "count")
        if ok then
            local beforeText = memBefore and string.format("%.1f", memBefore) or "n/a"
            print(string.format("[arcade gc] before=%sKB after=%.1fKB", beforeText, after))
        end
    end

    if lcd and lcd.invalidate then
        pcall(lcd.invalidate)
    end
end

local function startGame(state, index)
    if not state then
        return false
    end

    local def = games[index]
    if not def then
        return false
    end

    local module, err = loadGameModule(def)
    if not module then
        state.lastError = string.format("%s: %s", def.name, tostring(err))
        clearMenuForm(state)
        return false
    end

    clearMenuForm(state)

    local gameState = {}
    if type(module.create) == "function" then
        local okCreate, created = pcall(module.create)
        if not okCreate then
            state.lastError = string.format("%s create() failed: %s", def.name, tostring(created))
            return false
        end
        if created ~= nil then
            gameState = created
        end
    end

    state.selectedIndex = index
    state.activeDef = def
    state.activeModule = module
    state.activeState = gameState

    if type(module.wakeup) == "function" then
        local okWake, wakeErr = pcall(module.wakeup, state.activeState)
        if not okWake then
            state.lastError = string.format("%s wakeup() failed: %s", def.name, tostring(wakeErr))
            stopActiveGame(state)
            return false
        end
    end

    state.lastError = nil
    return true
end

local function addMenuButton(rect, def, onPress)
    if form and form.addButton then
        return form.addButton(nil, rect, {
            text = def.name,
            icon = def.icon,
            options = FONT_S,
            paint = function() end,
            press = onPress
        })
    end

    if form and form.addTextButton then
        return form.addTextButton(nil, rect, def.name, onPress)
    end

    return nil
end

local function buildMenuForm(state)
    if state.activeModule or state.menuBuilt then
        return
    end

    if not (form and form.clear and form.addLine and form.addStaticText) then
        return
    end

    if not (form and form.clear) then
        return
    end
    form.clear()
    state.menuClearRequested = false

    local width = 480
    if lcd and lcd.getWindowSize then
        local w = lcd.getWindowSize()
        if type(w) == "number" and w > 0 then
            width = w
        end
    end

    local padding = 8
    local buttonSize = 110
    if width >= 620 then
        padding = 10
        buttonSize = 118
    elseif width < 420 then
        padding = 6
        buttonSize = 84
    end

    local perRow = math.max(1, math.floor((width - padding) / (buttonSize + padding)))

    local header = form.addLine("")
    form.addStaticText(header, {x = 0, y = 0, w = width, h = 28}, APP_NAME)
    state.menuButtons = {}

    local y = form.height() + padding
    local col = 0

    for i, def in ipairs(games) do
        if col >= perRow then
            col = 0
            y = y + buttonSize + padding
        end

        local x = padding + col * (buttonSize + padding)
        local button = addMenuButton({x = x, y = y, w = buttonSize, h = buttonSize}, def, function()
            state.selectedIndex = i
            startGame(state, i)
        end)

        state.menuButtons[i] = button

        if i == state.selectedIndex and button and button.focus then
            button:focus()
        end

        col = col + 1
    end

    if state.lastError then
        form.addLine("Last error: " .. tostring(state.lastError))
    end

    state.menuBuilt = true
end

local function handleActiveGameEvent(state, category, value)
    local module = state.activeModule
    if not module then
        return false
    end

    if type(module.event) == "function" then
        local okEvent, eventResult = pcall(module.event, state.activeState, category, value)
        if not okEvent then
            state.lastError = string.format("%s event() failed: %s", state.activeDef.name, tostring(eventResult))
            stopActiveGame(state)
            return true
        end
        if eventResult == true then
            return true
        end
    end

    if isCloseEvent(category) then
        suppressExitEvents(state)
        stopActiveGame(state)
        return true
    end

    -- Fallback only if the active game did not consume the event.
    if isExitKeyEvent(category, value) then
        suppressExitEvents(state)
        stopActiveGame(state)
        return true
    end

    return false
end

local function createState()
    local state = {
        selectedIndex = 1,
        activeDef = nil,
        activeModule = nil,
        activeState = nil,
        menuBuilt = false,
        menuButtons = nil,
        menuClearRequested = false,
        lastFocusKick = 0,
        lastError = nil,
        suppressExitUntil = 0
    }

    for _, def in ipairs(games) do
        def.icon = loadIcon(def.iconPath)
    end

    return state
end

local app = {}

function app.create()
    return createState()
end

function app.wakeup(state)
    if type(state) ~= "table" then
        return
    end

    if state.menuClearRequested and form and form.clear then
        pcall(form.clear)
        state.menuClearRequested = false
    end

    if state.activeModule and type(state.activeModule.wakeup) == "function" then
        local okWake, wakeErr = pcall(state.activeModule.wakeup, state.activeState)
        if not okWake then
            state.lastError = string.format("%s wakeup() failed: %s", state.activeDef.name, tostring(wakeErr))
            stopActiveGame(state)
            return
        end
    else
        keepScreenAwake(state)
        buildMenuForm(state)
    end
end

function app.event(state, category, value)
    if type(state) ~= "table" then
        return false
    end

    debugEvent(state, category, value)

    if state.activeModule then
        return handleActiveGameEvent(state, category, value)
    end

    if isExitKeyEvent(category, value) and shouldSuppressExit(state) then
        return true
    end

    -- In menu mode, let Ethos form widgets handle key navigation/press.
    return false
end

function app.paint(state)
    if type(state) ~= "table" then
        return
    end

    if state.activeModule and type(state.activeModule.paint) == "function" then
        local okPaint, paintErr = pcall(state.activeModule.paint, state.activeState)
        if not okPaint then
            state.lastError = string.format("%s paint() failed: %s", state.activeDef.name, tostring(paintErr))
            stopActiveGame(state)
        end
        return
    end

    keepScreenAwake(state)
end

function app.close(state)
    if type(state) ~= "table" then
        return
    end

    if state.activeModule then
        stopActiveGame(state)
    else
        clearMenuForm(state)
    end
end

local function loadToolIcon()
    local icon = loadIcon("gfx/icon.png")
    return icon or "gfx/icon.png"
end

local function init()
    system.registerSystemTool({
        name = APP_NAME,
        icon = loadToolIcon(),
        create = app.create,
        wakeup = app.wakeup,
        event = app.event,
        paint = app.paint,
        close = app.close
    })
end

return {init = init}
