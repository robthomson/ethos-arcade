local game = assert(loadfile("game.lua"))()

local function loadToolIcon()
    local okMask, mask = pcall(lcd.loadMask, "gfx/icon.png")
    if okMask and mask then
        return mask
    end

    local okBitmap, bitmap = pcall(lcd.loadBitmap, "gfx/icon.png")
    if okBitmap and bitmap then
        return bitmap
    end

    return "gfx/icon.png"
end

local function init()
    system.registerSystemTool({
        name = "RetroFight",
        icon = loadToolIcon(),
        create = game.create,
        wakeup = game.wakeup,
        event = game.event,
        paint = game.paint,
        close = game.close
    })
end

return {init = init}
