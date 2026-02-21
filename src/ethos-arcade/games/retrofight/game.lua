local game = {}

local MOVE_X_SOURCE_MEMBER = 3
local JUMP_SOURCE_MEMBER = 1
local FIRE_SOURCE_MEMBER = 0

local CONFIG_BUTTON_CATEGORY = 0
local CONFIG_BUTTON_VALUE = 128
local FIRE_BUTTON_VALUE = 96
local CONFIG_FILE = "retrofight.cfg"
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

local TARGET_W = 784
local TARGET_H = 406

local ACTIVE_RENDER_FPS = 30
local IDLE_RENDER_FPS = 12
local FRAME_TARGET_DT = 1 / ACTIVE_RENDER_FPS
local FRAME_SCALE_MIN = 0.60
local FRAME_SCALE_MAX = 1.90
local ACTIVE_INVALIDATE_DT = 1 / ACTIVE_RENDER_FPS
local IDLE_INVALIDATE_DT = 1 / IDLE_RENDER_FPS

local MAX_HEALTH = 100
local PLAYER_SPEED = 2100
local ENEMY_SPEED = 1300
local MOVE_DEADZONE = 24
local GRAVITY = 4200
local JUMP_VELOCITY = 820
local ARENA_MARGIN = 40
local FLOOR_OFFSET = 46
local PUNCH_RANGE = 110
local PUNCH_TIME = 0.22
local PUNCH_HIT_TIME = 0.18
local PUNCH_COOLDOWN = 0.18
local HURT_TIME = 0.28
local FIRE_REARM_CENTER = 120
local FIRE_TRIGGER_HIGH = 120
local JUMP_REARM_LOW = 200
local JUMP_TRIGGER_HIGH = 520
local ENEMY_JUMP_COOLDOWN = 0.9
local ENEMY_JUMP_CHANCE = 0.8

local SPRITE_W = 160
local SPRITE_H = 220
local MIN_SEPARATION = 40
local EFFECT_SIZE = 80
local EFFECT_DURATION = 0.45
local DIFFICULTY_PROFILES = {
    [DIFFICULTY_EASY] = {enemySpeed = 0.70, enemyDamage = 8, enemyJump = 0.5},
    [DIFFICULTY_NORMAL] = {enemySpeed = 1.0, enemyDamage = 10, enemyJump = 0.8},
    [DIFFICULTY_HARD] = {enemySpeed = 1.25, enemyDamage = 14, enemyJump = 1.15}
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

local function closeSettingsForm(state, suppressExit)
    if suppressExit ~= false then
        suppressExitEvents(state)
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

    local infoLine = form.addLine("Dojo")
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

    local backLine = form.addLine("")
    local backAction = function()
        closeSettingsForm(state, true)
    end

    if form.addButton then
        form.addButton(backLine, nil, {text = "Back", press = backAction})
    elseif form.addTextButton then
        form.addTextButton(backLine, nil, "Back", backAction)
    end

    return true
end

local function playTone(freq, duration, pause)
    if not (system and system.playTone) then
        return
    end
    pcall(system.playTone, freq, duration or 30, pause or 0)
end

local function setColor(r, g, b, a)
    if not (lcd and lcd.color and lcd.RGB) then
        return
    end
    if a ~= nil then
        pcall(lcd.color, lcd.RGB(r, g, b, a))
        return
    end
    pcall(lcd.color, lcd.RGB(r, g, b))
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
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/retrofight/" .. CONFIG_FILE
    paths[#paths + 1] = "/scripts/ethos-arcade/games/retrofight/" .. CONFIG_FILE
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/retrofight/" .. CONFIG_FILE
    paths[#paths + 1] = "games/retrofight/" .. CONFIG_FILE
    return paths
end

local function clamp(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
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
    if normalizeDifficulty(difficulty) == DIFFICULTY_EASY then
        return DIFFICULTY_CHOICE_EASY
    end
    if normalizeDifficulty(difficulty) == DIFFICULTY_HARD then
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
    local config = {
        difficulty = normalizeDifficulty(values.difficulty)
    }
    return config
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
    f:close()
    return true
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
    return clamp(v, -1024, 1024)
end

local function assetPathCandidates(rel)
    local paths = {assetName = rel}
    if SCRIPT_DIR ~= "" then
        paths[#paths + 1] = SCRIPT_DIR .. "gfx/" .. rel
    end
    paths[#paths + 1] = "SCRIPTS:/ethos-arcade/games/retrofight/gfx/" .. rel
    paths[#paths + 1] = "/scripts/ethos-arcade/games/retrofight/gfx/" .. rel
    paths[#paths + 1] = "SD:/scripts/ethos-arcade/games/retrofight/gfx/" .. rel
    paths[#paths + 1] = "games/retrofight/gfx/" .. rel
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

local function refreshGeometry(state)
    local width, height = TARGET_W, TARGET_H
    if lcd and lcd.getWindowSize then
        local w, h = lcd.getWindowSize()
        if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
            width, height = w, h
        end
    end

    local scale = math.min(width / TARGET_W, height / TARGET_H)
    if scale <= 0 then
        scale = 1
    end

    local changed = (state.windowW ~= width or state.windowH ~= height or state.scale ~= scale)
    state.windowW = width
    state.windowH = height
    state.scale = scale
    state.offsetX = math.floor((width - (TARGET_W * scale)) * 0.5)
    state.offsetY = math.floor((height - (TARGET_H * scale)) * 0.5)

    state.floorY = TARGET_H - FLOOR_OFFSET
    state.arenaLeft = ARENA_MARGIN
    state.arenaRight = TARGET_W - ARENA_MARGIN

    if changed then
        forceInvalidate(state)
    end
end

local function drawBitmapScaled(state, bitmap, x, y, w, h)
    if not (bitmap and lcd and lcd.drawBitmap and state) then
        return false
    end

    local bx, by = x or 0, y or 0
    local bw, bh = w, h
    if not bw or not bh then
        bw, bh = bitmapSize(bitmap)
    end

    local sx = math.floor(state.offsetX + (bx * state.scale))
    local sy = math.floor(state.offsetY + (by * state.scale))
    local sw = bw and math.max(1, math.floor(bw * state.scale)) or nil
    local sh = bh and math.max(1, math.floor(bh * state.scale)) or nil

    if sw and sh then
        return pcall(lcd.drawBitmap, sx, sy, bitmap, sw, sh)
    end
    return pcall(lcd.drawBitmap, sx, sy, bitmap)
end

local function drawTextScaled(state, x, y, text)
    if not (lcd and lcd.drawText and state) then
        return
    end
    local sx = math.floor(state.offsetX + (x * state.scale))
    local sy = math.floor(state.offsetY + (y * state.scale))
    lcd.drawText(sx, sy, text)
end

local function drawRectScaled(state, x, y, w, h)
    if not (lcd and lcd.drawRectangle and state) then
        return
    end
    local sx = math.floor(state.offsetX + (x * state.scale))
    local sy = math.floor(state.offsetY + (y * state.scale))
    local sw = math.max(1, math.floor(w * state.scale))
    local sh = math.max(1, math.floor(h * state.scale))
    lcd.drawRectangle(sx, sy, sw, sh, 1)
end

local function drawFillScaled(state, x, y, w, h)
    if not (lcd and lcd.drawFilledRectangle and state) then
        return
    end
    local sx = math.floor(state.offsetX + (x * state.scale))
    local sy = math.floor(state.offsetY + (y * state.scale))
    local sw = math.max(1, math.floor(w * state.scale))
    local sh = math.max(1, math.floor(h * state.scale))
    lcd.drawFilledRectangle(sx, sy, sw, sh)
end

local function loadFighterAssets(prefix, flipped)
    local suffix = flipped and "_flipped" or ""
    return {
        idle = {
            loadBitmapAsset(assetPathCandidates(prefix .. "_idle_1" .. suffix .. ".png")),
            loadBitmapAsset(assetPathCandidates(prefix .. "_idle_2" .. suffix .. ".png"))
        },
        walk = {
            loadBitmapAsset(assetPathCandidates(prefix .. "_walk_1" .. suffix .. ".png")),
            loadBitmapAsset(assetPathCandidates(prefix .. "_walk_2" .. suffix .. ".png"))
        },
        punch = {
            loadBitmapAsset(assetPathCandidates(prefix .. "_punch_1" .. suffix .. ".png")),
            loadBitmapAsset(assetPathCandidates(prefix .. "_punch_2" .. suffix .. ".png"))
        },
        hurt = {loadBitmapAsset(assetPathCandidates(prefix .. "_hurt" .. suffix .. ".png"))},
        ko = {loadBitmapAsset(assetPathCandidates(prefix .. "_ko" .. suffix .. ".png"))}
    }
end

local function loadRandomBackground()
    local choices = {"bg.png", "bg2.png", "bg3.png"}
    local pick = choices[math.random(1, #choices)]
    return loadBitmapAsset(assetPathCandidates(pick))
end

local function loadAssets(state)
    state.assets = {
        bg = loadRandomBackground(),
        p1 = loadFighterAssets("p1", false),
        p1Flip = loadFighterAssets("p1", true),
        p2 = loadFighterAssets("p2", false),
        p2Flip = loadFighterAssets("p2", true),
        pow = loadBitmapAsset(assetPathCandidates("pow.png")),
        bam = loadBitmapAsset(assetPathCandidates("bam.png"))
    }
end

local function makeFighter(isPlayer)
    return {
        isPlayer = isPlayer,
        x = isPlayer and (TARGET_W * 0.72) or (TARGET_W * 0.28),
        y = TARGET_H - FLOOR_OFFSET - SPRITE_H,
        vy = 0,
        jumping = false,
        facing = isPlayer and -1 or 1,
        anim = "idle",
        animTime = 0,
        frameIndex = 1,
        punchTimer = 0,
        punchElapsed = 0,
        punchCooldown = 0,
        hurtTimer = 0,
        ko = false,
        health = MAX_HEALTH
    }
end

local function setAnim(fighter, anim)
    if fighter.anim ~= anim then
        fighter.anim = anim
        fighter.animTime = 0
        fighter.frameIndex = 1
    end
end

local function animFrame(frames, animTime, fps, looped)
    local count = #frames
    if count == 0 then
        return nil
    end
    local idx = math.floor(animTime * fps) + 1
    if looped then
        idx = ((idx - 1) % count) + 1
    else
        idx = clamp(idx, 1, count)
    end
    return frames[idx]
end

local function canFight(fighter)
    return fighter and not fighter.ko and fighter.health > 0
end

local function startPunch(state, fighter)
    fighter.punchTimer = PUNCH_TIME
    fighter.punchElapsed = 0
    playTone(980, 20, 0)
    setAnim(fighter, "punch")
    if state then
        state.punchEffect = {
            x = fighter.x + (SPRITE_W * 0.5) - (EFFECT_SIZE * 0.5),
            y = fighter.y - (EFFECT_SIZE * 0.65),
            timer = EFFECT_DURATION,
            usePow = (math.random() < 0.5)
        }
    end
end

local function applyDamage(target, amount)
    if not target or target.ko then
        return
    end
    target.health = math.max(0, target.health - amount)
    if target.health <= 0 then
        target.ko = true
        setAnim(target, "ko")
    else
        target.hurtTimer = HURT_TIME
        setAnim(target, "hurt")
    end

end

local function updateFighterAnimation(fighter, dt, framesByAnim)
    fighter.animTime = fighter.animTime + dt
    local anim = fighter.anim or "idle"
    local frames = framesByAnim[anim] or framesByAnim.idle or {}
    local fps = (anim == "walk") and 6 or 4
    local looped = (anim == "idle" or anim == "walk")
    fighter.frameIndex = animFrame(frames, fighter.animTime, fps, looped) and fighter.frameIndex or 1
end

local function updatePlayer(state, dt)
    local player = state.player
    local enemy = state.enemy
    if not canFight(player) then
        return
    end

    if player.hurtTimer > 0 then
        player.hurtTimer = math.max(0, player.hurtTimer - dt)
        if player.hurtTimer <= 0 and player.punchTimer <= 0 then
            setAnim(player, "idle")
        end
    end

    if player.punchCooldown > 0 then
        player.punchCooldown = math.max(0, player.punchCooldown - dt)
    end

    if player.punchTimer > 0 then
        player.punchTimer = math.max(0, player.punchTimer - dt)
        player.punchElapsed = player.punchElapsed + dt
        if player.punchElapsed >= PUNCH_HIT_TIME and not player.hitApplied then
            player.hitApplied = true
            if math.abs(player.x - enemy.x) <= PUNCH_RANGE then
                applyDamage(enemy, 12)
                local ex = enemy.x + (SPRITE_W * 0.5) - (EFFECT_SIZE * 0.5)
                local ey = enemy.y - (EFFECT_SIZE * 0.7)
                state.hitEffect = {
                    x = clamp(ex, 0, TARGET_W - EFFECT_SIZE),
                    y = clamp(ey, 0, TARGET_H - EFFECT_SIZE),
                    timer = EFFECT_DURATION,
                    usePow = (math.random() < 0.5)
                }
                state.frontSwap = true
            end
        end
        if player.punchTimer <= 0 then
            player.punchCooldown = PUNCH_COOLDOWN
            player.hitApplied = false
            setAnim(player, "idle")
        end
    end

    if state.fireRequested and player.punchCooldown <= 0 and player.punchTimer <= 0 then
        state.fireRequested = false
        player.hitApplied = false
        startPunch(state, player)
    end

    local moveX = normalizeStick(sourceValue(state.moveSourceX))
    if math.abs(moveX) < MOVE_DEADZONE then
        moveX = 0
    end
    if moveX ~= 0 then
        player.x = player.x + (moveX / 1024) * PLAYER_SPEED * dt
        player.x = clamp(player.x, state.arenaLeft, state.arenaRight - SPRITE_W)
        player.facing = moveX > 0 and 1 or -1
        if player.punchTimer <= 0 and player.hurtTimer <= 0 then
            setAnim(player, "walk")
        end
    else
        if player.punchTimer <= 0 and player.hurtTimer <= 0 then
            setAnim(player, "idle")
        end
    end

    -- Punch is driven by Page button events only.

    local jumpValue = normalizeStick(sourceValue(state.jumpSource))
    if jumpValue < JUMP_REARM_LOW then
        state.jumpArmed = true
    end
    if state.jumpArmed and jumpValue > JUMP_TRIGGER_HIGH and not player.jumping then
        state.jumpArmed = false
        player.jumping = true
        player.vy = -JUMP_VELOCITY
    end
end

local function updateEnemy(state, dt)
    local enemy = state.enemy
    local player = state.player
    if not canFight(enemy) then
        return
    end

    if enemy.hurtTimer > 0 then
        enemy.hurtTimer = math.max(0, enemy.hurtTimer - dt)
        if enemy.hurtTimer <= 0 and enemy.punchTimer <= 0 then
            setAnim(enemy, "idle")
        end
        return
    end

    if enemy.punchCooldown > 0 then
        enemy.punchCooldown = math.max(0, enemy.punchCooldown - dt)
    end
    if enemy.jumpCooldown and enemy.jumpCooldown > 0 then
        enemy.jumpCooldown = math.max(0, enemy.jumpCooldown - dt)
    end

    if enemy.punchTimer > 0 then
        enemy.punchTimer = math.max(0, enemy.punchTimer - dt)
        enemy.punchElapsed = enemy.punchElapsed + dt
        if enemy.punchElapsed >= PUNCH_HIT_TIME and not enemy.hitApplied then
            enemy.hitApplied = true
            if math.abs(enemy.x - player.x) <= PUNCH_RANGE then
                applyDamage(player, 10)
                local ex = player.x + (SPRITE_W * 0.5) - (EFFECT_SIZE * 0.5)
                local ey = player.y - (EFFECT_SIZE * 0.7)
                state.hitEffect = {
                    x = clamp(ex, 0, TARGET_W - EFFECT_SIZE),
                    y = clamp(ey, 0, TARGET_H - EFFECT_SIZE),
                    timer = EFFECT_DURATION,
                    usePow = (math.random() < 0.5)
                }
                state.frontSwap = false
            end
        end
        if enemy.punchTimer <= 0 then
            enemy.punchCooldown = PUNCH_COOLDOWN
            enemy.hitApplied = false
            setAnim(enemy, "idle")
        end
        return
    end

    local dist = player.x - enemy.x
    if math.abs(dist) <= PUNCH_RANGE and enemy.punchCooldown <= 0 then
        enemy.hitApplied = false
        startPunch(state, enemy)
        return
    end

    local dir = dist > 0 and 1 or -1
    enemy.x = enemy.x + dir * ENEMY_SPEED * dt
    enemy.x = clamp(enemy.x, state.arenaLeft, state.arenaRight - SPRITE_W)
    enemy.facing = dir
    setAnim(enemy, "walk")

    if not enemy.jumping and (enemy.jumpCooldown or 0) <= 0 then
        if math.random() < (ENEMY_JUMP_CHANCE * dt) then
            enemy.jumping = true
            enemy.vy = -JUMP_VELOCITY
            enemy.jumpCooldown = ENEMY_JUMP_COOLDOWN
        end
    end
end

local function updateVertical(state, fighter, dt)
    if not fighter then
        return
    end
    local groundY = TARGET_H - FLOOR_OFFSET - SPRITE_H
    if fighter.jumping or fighter.vy ~= 0 then
        fighter.vy = fighter.vy + (GRAVITY * dt)
        fighter.y = fighter.y + (fighter.vy * dt)
        if fighter.y >= groundY then
            fighter.y = groundY
            fighter.vy = 0
            fighter.jumping = false
        end
    else
        fighter.y = groundY
    end
end

local function updateGame(state, dt)
    updatePlayer(state, dt)
    updateEnemy(state, dt)
    updateVertical(state, state.player, dt)
    updateVertical(state, state.enemy, dt)
    if state.player then
        state.player.animTime = (state.player.animTime or 0) + dt
    end
    if state.enemy then
        state.enemy.animTime = (state.enemy.animTime or 0) + dt
    end
    if state.hitEffect and state.hitEffect.timer then
        state.hitEffect.timer = state.hitEffect.timer - dt
        if state.hitEffect.timer <= 0 then
            state.hitEffect = nil
        end
    end
    if state.punchEffect and state.punchEffect.timer then
        state.punchEffect.timer = state.punchEffect.timer - dt
        if state.punchEffect.timer <= 0 then
            state.punchEffect = nil
        end
    end

    if state.player and state.enemy then
        local dx = state.enemy.x - state.player.x
        local minDist = MIN_SEPARATION
        if math.abs(dx) < minDist then
            local push = (minDist - math.abs(dx)) * 0.35
            local dir = dx >= 0 and 1 or -1
            state.player.x = clamp(state.player.x - (push * dir), state.arenaLeft, state.arenaRight - SPRITE_W)
            state.enemy.x = clamp(state.enemy.x + (push * dir), state.arenaLeft, state.arenaRight - SPRITE_W)
        end
    end

    if (state.player.ko or state.enemy.ko) and state.running then
        state.running = false
        state.winner = state.player.ko and "Enemy" or "Player"
    end
end

local function drawHealthBar(state, x, y, label, value, colorValue)
    if not lcd then
        return
    end
    local barW = 220
    local barH = 16
    drawRectScaled(state, x, y, barW, barH)
    local fillW = math.floor((barW - 2) * (value / MAX_HEALTH))
    if fillW > 0 then
        drawFillScaled(state, x + 1, y + 1, fillW, barH - 2)
    end
    -- Put label/value below the bar to avoid overlap.
    drawTextScaled(state, x + 6, y + barH + 2, label .. " " .. value)
end

local function drawBackground(state)
    if state.assets and state.assets.bg then
        drawBitmapScaled(state, state.assets.bg, 0, 0, TARGET_W, TARGET_H)
    else
        drawFillScaled(state, 0, 0, TARGET_W, TARGET_H)
    end
    drawRectScaled(state, 0, state.floorY + SPRITE_H + 4, TARGET_W, 1)
end

local function drawFighter(state, fighter, frames)
    if not fighter then
        return
    end
    local anim = fighter.anim or "idle"
    local framesForAnim = frames[anim] or frames.idle or {}
    local fps = 4
    if anim == "walk" then
        fps = 6
    elseif anim == "punch" then
        fps = 12
    end
    local looped = (anim == "idle" or anim == "walk")
    local frame = animFrame(framesForAnim, fighter.animTime, fps, looped) or framesForAnim[1]
    if frame then
        drawBitmapScaled(state, frame, fighter.x, fighter.y, SPRITE_W, SPRITE_H)
    else
        drawRectScaled(state, fighter.x, fighter.y, SPRITE_W, SPRITE_H)
    end

end

local function drawHud(state)
    -- Player starts on the right, so swap HUD sides to match.
    drawHealthBar(state, 24, 18, "P2", state.enemy.health, 2)
    drawHealthBar(state, TARGET_W - 24 - 220, 18, "P1", state.player.health, 1)
end

local function drawOverlay(state)
    local centerX = TARGET_W * 0.5
    if not state.running then
        local boxW = 440
        local boxH = 140
        local boxX = math.floor(centerX - (boxW * 0.5))
        local boxY = 128
        if lcd and lcd.drawFilledRectangle then
            local sx = math.floor(state.offsetX + (boxX * state.scale))
            local sy = math.floor(state.offsetY + (boxY * state.scale))
            local sw = math.max(1, math.floor(boxW * state.scale))
            local sh = math.max(1, math.floor(boxH * state.scale))
            setColor(0, 0, 0, 0.9)
            lcd.drawFilledRectangle(sx, sy, sw, sh)
            if lcd.drawRectangle then
                setColor(255, 255, 255)
                lcd.drawRectangle(sx, sy, sw, sh, 1)
            end
        end
        setColor(255, 255, 255)
        if state.winner then
            drawTextScaled(state, centerX - 40, 140, "KO")
            drawTextScaled(state, centerX - 110, 168, state.winner .. " Wins")
            drawTextScaled(state, centerX - 140, 200, "Press Enter to restart")
        else
            drawTextScaled(state, centerX - 90, 140, "Dojo")
            drawTextScaled(state, centerX - 190, 168, "Aileron move | Rudder punch")
            drawTextScaled(state, centerX - 120, 194, "Elevator jump")
            drawTextScaled(state, centerX - 140, 218, "Enter start, Exit back")
        end
    end
end

local function resetRound(state)
    state.player = makeFighter(true)
    state.enemy = makeFighter(false)
    state.running = false
    state.winner = nil
    state.fireRequested = false
    state.frontSwap = false
end

local function createState()
    local state = {
        moveSourceX = resolveAnalogSource(MOVE_X_SOURCE_MEMBER),
        jumpSource = resolveAnalogSource(JUMP_SOURCE_MEMBER),
        fireSource = resolveAnalogSource(FIRE_SOURCE_MEMBER),
        fireArmed = true,
        jumpArmed = true,
        frameScale = 1,
        lastFrameTime = 0,
        nextInvalidateAt = 0,
        lastFocusKick = 0,
        suppressExitUntil = 0
    }

    refreshGeometry(state)
    loadAssets(state)
    resetRound(state)
    return state
end

function game.create()
    math.randomseed(os.time())
    return createState()
end

function game.wakeup(state)
    if not state then return end
    refreshGeometry(state)
    if not state.moveSourceX then
        state.moveSourceX = resolveAnalogSource(MOVE_X_SOURCE_MEMBER)
    end
    if not state.jumpSource then
        state.jumpSource = resolveAnalogSource(JUMP_SOURCE_MEMBER)
    end
    if not state.fireSource then
        state.fireSource = resolveAnalogSource(FIRE_SOURCE_MEMBER)
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

    if isSettingsOpenEvent(category, value) then
        return true
    end

    if category == EVT_CLOSE then
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

    if not state.running then
        if keyMatches(value, KEY_ENTER_FIRST, KEY_ENTER_BREAK, KEY_ENTER_LONG) then
            resetRound(state)
            state.running = true
            forceInvalidate(state)
            return true
        end
        return true
    end

    if isFireButtonEvent(category, value) then
        if state.player and canFight(state.player) then
            -- Always punch immediately, regardless of motion/cooldown.
            state.player.punchCooldown = 0
            state.player.hitApplied = false
            startPunch(state, state.player)
        end
        return true
    end

    return false
end

function game.paint(state)
    if not state then return end

    refreshGeometry(state)
    keepScreenAwake(state)
    updateFrameScale(state)

    local dt = FRAME_TARGET_DT * state.frameScale
    if state.running then
        updateGame(state, dt)
    end

    drawBackground(state)
    local p1Frames = state.assets.p1
    local p2Frames = state.assets.p2
    if state.player and state.player.facing == -1 and state.assets.p1Flip then
        p1Frames = state.assets.p1Flip
    end
    if state.enemy and state.enemy.facing == -1 and state.assets.p2Flip then
        p2Frames = state.assets.p2Flip
    end
    local playerFront = (state.player and state.player.punchTimer and state.player.punchTimer > 0)
    local enemyFront = (state.enemy and state.enemy.punchTimer and state.enemy.punchTimer > 0)
    if playerFront and not enemyFront then
        drawFighter(state, state.enemy, p2Frames)
        drawFighter(state, state.player, p1Frames)
    elseif enemyFront and not playerFront then
        drawFighter(state, state.player, p1Frames)
        drawFighter(state, state.enemy, p2Frames)
    elseif state.frontSwap then
        drawFighter(state, state.player, p1Frames)
        drawFighter(state, state.enemy, p2Frames)
    else
        drawFighter(state, state.enemy, p2Frames)
        drawFighter(state, state.player, p1Frames)
    end
    if state.hitEffect then
        local effect = state.hitEffect.usePow and state.assets.pow or state.assets.bam
        if effect then
            drawBitmapScaled(state, effect, state.hitEffect.x, state.hitEffect.y, EFFECT_SIZE, EFFECT_SIZE)
        end
    end
    if state.punchEffect then
        local effect = state.punchEffect.usePow and state.assets.pow or state.assets.bam
        if effect then
            local ex = clamp(state.punchEffect.x, 0, TARGET_W - EFFECT_SIZE)
            local ey = clamp(state.punchEffect.y, 0, TARGET_H - EFFECT_SIZE)
            drawBitmapScaled(state, effect, ex, ey, EFFECT_SIZE, EFFECT_SIZE)
        end
    end
    drawHud(state)
    drawOverlay(state)
    requestTimedInvalidate(state)
end

function game.close(state)
    return
end

return game
