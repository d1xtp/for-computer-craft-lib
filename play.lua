-- play.lua - Fixed Music Player (надёжный поиск файлов)

local args = {...}

if #args == 0 then
    print("Usage: play /folder [-loop] [-shuffle] [-monitor|-computer|-both]")
    print("Controls: → Next | ← Prev | P Pause | R Restart | Q Quit")
    return
end

-- ====================== ПАРСИНГ ======================

local speakers = {}
local playlist = {}
local isLoop = false
local isShuffle = false
local displayMode = "both"

local folderPath = nil

for i = #args, 1, -1 do
    local a = args[i]:lower()
    if a == "-loop" then isLoop = true; table.remove(args, i)
    elseif a == "-shuffle" then isShuffle = true; table.remove(args, i)
    elseif a == "-monitor" then displayMode = "monitor"; table.remove(args, i)
    elseif a == "-computer" then displayMode = "computer"; table.remove(args, i)
    elseif a == "-both" then displayMode = "both"; table.remove(args, i)
    end
end

if #speakers == 0 then
    speakers = { peripheral.find("speaker") }
    if #speakers == 0 then
        print("Error: No speaker found!")
        return
    end
end

folderPath = args[#args]  -- последний аргумент = путь

if not folderPath or folderPath:sub(1,1) ~= "/" then
    print("Error: Specify folder, example: play /songs")
    return
end

-- ====================== ЗАГРУЗКА ПЛЕЙЛИСТА (ИСПРАВЛЕНО) ======================

if not fs.exists(folderPath) or not fs.isDir(folderPath) then
    print("Error: Folder '" .. folderPath .. "' not found!")
    return
end

print("Scanning folder: " .. folderPath)

local files = fs.list(folderPath)
local foundCount = 0

for _, filename in ipairs(files) do
    local lowerName = filename:lower()
    if lowerName:sub(-5) == ".dfpwm" then
        local fullPath = fs.combine(folderPath, filename)
        table.insert(playlist, fullPath)
        foundCount = foundCount + 1
        print("  + " .. filename)
    elseif lowerName:sub(-4) == ".mp3" then
        print("  ! MP3 found: " .. filename .. " (convert to .dfpwm manually)")
    end
end

print("Found " .. foundCount .. " .dfpwm file(s)")

if #playlist == 0 then
    print("Error: No .dfpwm files found in " .. folderPath)
    print("Make sure files end with .dfpwm (lowercase or uppercase)")
    return
end

-- ====================== ШАФЛ ======================

if isShuffle then
    print("Shuffling playlist...")
    for i = #playlist, 2, -1 do
        local j = math.random(i)
        playlist[i], playlist[j] = playlist[j], playlist[i]
    end
end

-- ====================== ОСТАЛЬНОЙ КОД (интерфейс + воспроизведение) ======================

local monitor = peripheral.find("monitor")
if monitor then monitor.setTextScale(1) end

local function drawDisplay(currentIndex, paused)
    local curr = playlist[currentIndex]
    local nextFile = playlist[currentIndex % #playlist + 1]

    local currName = fs.getName(curr)
    local nextName = nextFile and fs.getName(nextFile) or "—"

    if displayMode == "computer" or displayMode == "both" then
        term.clear()
        term.setCursorPos(1,1)
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

    if (displayMode == "monitor" or displayMode == "both") and monitor then
        monitor.clear()
        monitor.setCursorPos(2,2)
        monitor.setTextColor(colors.cyan)
        monitor.write("=== MUSIC PLAYER ===")
        monitor.setCursorPos(2,4)
        monitor.setTextColor(colors.yellow)
        monitor.write("NOW PLAYING:")
        monitor.setCursorPos(2,5)
        monitor.setTextColor(colors.white)
        monitor.write(currName)

        monitor.setCursorPos(2,7)
        monitor.setTextColor(colors.lightGray)
        monitor.write("NEXT:")
        monitor.setCursorPos(2,8)
        monitor.write(nextName)
    end
end

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
                while paused do os.pullEvent("key") end

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
            end
        end)
    end

    parallel.waitForAll(table.unpack(functions))
end

-- ====================== ГЛАВНЫЙ ЦИКЛ ======================

print("Starting playback...")

local currentIndex = 1

repeat
    for i = currentIndex, #playlist do
        currentIndex = i
        playSong(i)

        local ev, key = os.pullEvent(0.1)
        if ev == "key" then
            if key == keys.q then
                term.clear()
                term.setCursorPos(1,1)
                print("Playback stopped.")
                if monitor then monitor.clear() end
                return
            elseif key == keys.right then
                -- next song
            elseif key == keys.left then
                currentIndex = i - 1
                if currentIndex < 1 then currentIndex = #playlist end
                break
            elseif key == keys.r then
                i = i - 1
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