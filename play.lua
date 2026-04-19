-- play.lua - Clean Music Player with better controls

local args = {...}

if #args == 0 then
    print("Usage: play /folder [-loop] [-shuffle] [-monitor|-computer|-both]")
    print("")
    print("Controls during playback:")
    print("  →  Next track")
    print("  ←  Previous track")
    print("  P  Pause / Resume")
    print("  R  Restart current track")
    print("  Q  Quit player")
    return
end

-- ====================== ПАРСИНГ АРГУМЕНТОВ ======================
local folderPath = nil
local isLoop = false
local isShuffle = false
local displayMode = "both"

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

folderPath = args[1]

if not folderPath or folderPath:sub(1,1) ~= "/" then
    print("Error: Usage: play /folder")
    return
end

-- ====================== ПОДКЛЮЧЕНИЕ ДИНАМИКОВ ======================
local speakers = {}
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "speaker" then
        local sp = peripheral.wrap(name)
        if sp then
            table.insert(speakers, sp)
            print("Found speaker: " .. name)
        end
    end
end

if #speakers == 0 then
    print("Error: No speaker found!")
    return
end

print("Using " .. #speakers .. " speaker(s)")

-- ====================== ЗАГРУЗКА ПЛЕЙЛИСТА ======================
if not fs.exists(folderPath) or not fs.isDir(folderPath) then
    print("Error: Folder '" .. folderPath .. "' not found!")
    return
end

print("Scanning folder: " .. folderPath)

local playlist = {}
local files = fs.list(folderPath)

for _, filename in ipairs(files) do
    if filename:lower():sub(-6) == ".dfpwm" then
        local fullPath = fs.combine(folderPath, filename)
        table.insert(playlist, {path = fullPath, name = filename})
        print("  + " .. filename)
    end
end

if #playlist == 0 then
    print("Error: No .dfpwm files found in " .. folderPath)
    return
end

print("Loaded " .. #playlist .. " tracks.")

if isShuffle then
    print("Shuffling playlist...")
    for i = #playlist, 2, -1 do
        local j = math.random(i)
        playlist[i], playlist[j] = playlist[j], playlist[i]
    end
end

-- ====================== ИНТЕРФЕЙС ======================
local monitor = peripheral.find("monitor")
if monitor then monitor.setTextScale(1) end

local function drawDisplay(index, paused)
    local track = playlist[index]
    local nextTrack = playlist[index % #playlist + 1] or {name = "—"}

    -- Computer screen
    if displayMode == "computer" or displayMode == "both" then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.cyan)
        print("=== MUSIC PLAYER ===")
        term.setTextColor(colors.yellow)
        print("\nNOW PLAYING:")
        term.setTextColor(colors.white)
        print("  " .. track.name)

        term.setTextColor(colors.lightGray)
        print("\nNEXT:")
        print("  " .. nextTrack.name)

        if isLoop then print("  [LOOP]") end
        if isShuffle then print("  [SHUFFLE]") end
        if paused then 
            term.setTextColor(colors.red)
            print("  [PAUSED]")
        end
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
        monitor.write(track.name:sub(1, 35))
    end
end

-- ====================== ВОСПРОИЗВЕДЕНИЕ ======================
local dfpwm = require("cc.audio.dfpwm")
local decoder = dfpwm.make_decoder()

local function playTrack(index)
    local track = playlist[index]
    local file = fs.open(track.path, "rb")
    if not file then return end
    local audioData = file.readAll()
    file.close()

    local paused = false
    drawDisplay(index, paused)

    local functions = {}
    for _, speaker in ipairs(speakers) do
        table.insert(functions, function()
            for pos = 1, #audioData, 16384 do
                -- Проверка паузы
                while paused do
                    os.pullEvent("key")
                end

                local chunk = audioData:sub(pos, pos + 16383)
                local buffer = decoder(chunk)

                while not speaker.playAudio(buffer) do
                    os.pullEvent("speaker_audio_empty")
                end
            end
        end)
    end

    parallel.waitForAll(table.unpack(functions))
end

-- ====================== ГЛАВНЫЙ ЦИКЛ С УЛУЧШЕННЫМ УПРАВЛЕНИЕМ ======================
local currentIndex = 1
local globalPaused = false

while true do
    if globalPaused then
        drawDisplay(currentIndex, true)
        local event, key = os.pullEvent("key")
        if key == keys.p then
            globalPaused = false
        elseif key == keys.q then
            break
        end
    else
        playTrack(currentIndex)
    end

    -- Обработка управления после трека или во время паузы
    local event, key = os.pullEvent(0.1)

    if event == "key" then
        if key == keys.q then
            break
        elseif key == keys.right then
            -- Next track
            currentIndex = currentIndex % #playlist + 1
        elseif key == keys.left then
            -- Previous track
            currentIndex = currentIndex - 1
            if currentIndex < 1 then currentIndex = #playlist end
        elseif key == keys.p then
            globalPaused = not globalPaused
        elseif key == keys.r then
            -- Restart current track
            -- просто продолжаем с того же индекса
        end
    end

    if not isLoop and currentIndex > #playlist then
        break
    end
end

-- ====================== ЗАВЕРШЕНИЕ ======================
term.clear()
term.setCursorPos(1, 1)
print("Music player stopped.")
if monitor then monitor.clear() end