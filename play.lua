-- play.lua - Advanced Music Player for ComputerCraft
-- Использование: play /folder [-loop] [-shuffle] [-monitor|-computer|-both]

local args = {...}

if #args == 0 then
    print("Usage:")
    print("  play /folder                   -- play all .dfpwm files")
    print("  play /folder -shuffle          -- random order")
    print("  play /folder -loop             -- loop playlist")
    print("  play /folder -loop -shuffle    -- loop + shuffle")
    print("  play /folder -monitor          -- show only on monitor")
    print("  play /folder -both             -- show on both computer and monitor")
    print("")
    print("Controls during playback:")
    print("  →   Next song")
    print("  ←   Previous song")
    print("  P   Pause / Resume")
    print("  R   Restart current song")
    print("  Q   Quit")
    return
end

-- ====================== ПАРСИНГ ======================

local speakers = {}
local playlist = {}
local isLoop = false
local isShuffle = false
local displayMode = "both"   -- both, computer, monitor

local folderPath = nil

-- Обработка флагов
for i = #args, 1, -1 do
    local a = args[i]:lower()
    if a == "-loop" then
        isLoop = true
        table.remove(args, i)
    elseif a == "-shuffle" then
        isShuffle = true
        table.remove(args, i)
    elseif a == "-monitor" then
        displayMode = "monitor"
        table.remove(args, i)
    elseif a == "-computer" then
        displayMode = "computer"
        table.remove(args, i)
    elseif a == "-both" then
        displayMode = "both"
        table.remove(args, i)
    end
end

-- Спикеры (если указаны)
for i = 1, #args do
    local arg = args[i]
    if peripheral.isPresent(arg) and peripheral.getType(arg) == "speaker" then
        local sp = peripheral.wrap(arg)
        if sp then table.insert(speakers, sp) end
    else
        folderPath = arg
        break
    end
end

-- Если спикеры не указаны — берём все
if #speakers == 0 then
    speakers = { peripheral.find("speaker") }
    if #speakers == 0 then
        print("Error: No speaker found!")
        return
    end
end

if not folderPath or folderPath:sub(1,1) ~= "/" then
    print("Error: Please specify a folder (example: /songs)")
    return
end

-- ====================== ЗАГРУЗКА ПЛЕЙЛИСТА ======================

if not fs.exists(folderPath) or not fs.isDir(folderPath) then
    print("Error: Folder '" .. folderPath .. "' not found!")
    return
end

local files = fs.list(folderPath)
for _, file in ipairs(files) do
    if file:lower():sub(-5) == ".dfpwm" then
        table.insert(playlist, fs.combine(folderPath, file))
    end
end

if #playlist == 0 then
    print("Error: No .dfpwm files found in " .. folderPath)
    return
end

if isShuffle then
    for i = #playlist, 2, -1 do
        local j = math.random(i)
        playlist[i], playlist[j] = playlist[j], playlist[i]
    end
end

-- ====================== МОНИТОР ======================

local monitor = peripheral.find("monitor")
if monitor then
    monitor.setTextScale(1)
end

local function drawDisplay(currentIndex, paused)
    local currentFile = playlist[currentIndex]
    local nextFile = playlist[currentIndex % #playlist + 1]

    local currName = fs.getName(currentFile)
    local nextName = nextFile and fs.getName(nextFile) or "—"

    -- Computer
    if displayMode == "computer" or displayMode == "both" then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.cyan)
        print("=== MUSIC PLAYER ===")

        term.setTextColor(colors.yellow)
        print("\nNOW PLAYING:")
        term.setTextColor(colors.white)
        print("  " .. currName)

        term.setTextColor(colors.lightGray)
        print("\nNEXT:")
        print("  " .. nextName)

        if isLoop then print("  [LOOP]") end
        if isShuffle then print("  [SHUFFLE]") end
        if paused then print("  [PAUSED]") end
    end

    -- Monitor
    if (displayMode == "monitor" or displayMode == "both") and monitor then
        monitor.clear()
        monitor.setCursorPos(2, 2)
        monitor.setTextColor(colors.cyan)
        monitor.write("=== MUSIC PLAYER ===")

        monitor.setCursorPos(2, 4)
        monitor.setTextColor(colors.yellow)
        monitor.write("NOW PLAYING:")
        monitor.setCursorPos(2, 5)
        monitor.setTextColor(colors.white)
        monitor.write(currName)

        monitor.setCursorPos(2, 7)
        monitor.setTextColor(colors.lightGray)
        monitor.write("NEXT:")
        monitor.setCursorPos(2, 8)
        monitor.write(nextName)

        if isLoop then
            monitor.setCursorPos(2, 10)
            monitor.write("[LOOP]")
        end
        if isShuffle then
            monitor.setCursorPos(2, 11)
            monitor.write("[SHUFFLE]")
        end
        if paused then
            monitor.setCursorPos(2, 12)
            monitor.write("[PAUSED]")
        end
    end
end

-- ====================== ВОСПРОИЗВЕДЕНИЕ ======================

local dfpwm = require("cc.audio.dfpwm")
local decoder = dfpwm.make_decoder()

local function playSong(index)
    local filePath = playlist[index]
    local audioData = fs.open(filePath, "rb").readAll()
    local totalChunks = math.ceil(#audioData / 16384)
    local chunkCount = 0
    local paused = false

    drawDisplay(index, paused)

    local functions = {}
    for _, speaker in ipairs(speakers) do
        table.insert(functions, function()
            for pos = 1, #audioData, 16384 do
                while paused do
                    local ev = {os.pullEvent("key")}
                    if ev[1] == "key" and ev[2] == keys.p then
                        paused = false
                        drawDisplay(index, false)
                    end
                end

                local chunk = audioData:sub(pos, pos + 16383)
                local buffer = decoder(chunk)
                chunkCount = chunkCount + 1

                while not speaker.playAudio(buffer) do
                    os.pullEvent("speaker_audio_empty")
                end

                local progress = chunkCount / totalChunks
                if displayMode == "computer" or displayMode == "both" then
                    term.setCursorPos(1, 12)
                    term.clearLine()
                    term.write("Progress: [")
                    local bar = math.floor(40 * progress)
                    term.setTextColor(colors.lime)
                    term.write(string.rep("=", bar))
                    term.setTextColor(colors.gray)
                    term.write(string.rep("-", 40 - bar))
                    term.setTextColor(colors.white)
                    term.write("] " .. math.floor(progress*100) .. "%")
                end

                drawDisplay(index, paused)
            end
        end)
    end

    parallel.waitForAll(table.unpack(functions))
end

-- ====================== ГЛАВНЫЙ ЦИКЛ ======================

print("Starting music player... Controls: → ← P R Q")

local currentIndex = 1

repeat
    for i = currentIndex, #playlist do
        currentIndex = i
        playSong(i)

        local event, key = os.pullEvent(0.1)
        if event == "key" then
            if key == keys.q then
                term.clear()
                term.setCursorPos(1,1)
                print("Playback stopped.")
                if monitor then monitor.clear() end
                return
            elseif key == keys.right then
                -- next
            elseif key == keys.left then
                currentIndex = i - 1
                if currentIndex < 1 then currentIndex = #playlist end
                break
            elseif key == keys.r then
                i = i - 1
            elseif key == keys.p then
                -- pause будет обработан внутри playSong
            end
        end
    end

    if isShuffle and #playlist > 1 then
        for j = #playlist, 2, -1 do
            local k = math.random(j)
            playlist[j], playlist[k] = playlist[k], playlist[j]
        end
    end

    currentIndex = 1

until not isLoop

term.clear()
term.setCursorPos(1,1)
print("Playlist finished.")
if monitor then monitor.clear() end