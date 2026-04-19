-- play.lua
-- Music Player for CC: Tweaked (поддержка нескольких динамиков)

local args = {...}

if #args == 0 then
    print("Usage: play <folder> [options]")
    print("Example: play /songs")
    print("         play /music -loop -shuffle")
    print("")
    print("Options:")
    print("  -loop      Repeat playlist")
    print("  -shuffle   Random order")
    print("  -monitor   Show only on monitor")
    print("  -computer  Show only on computer")
    print("  -both      Show on both (default)")
    print("")
    print("Controls during playback:")
    print("  →  Next track")
    print("  ←  Previous track")
    print("  P  Pause / Resume")
    print("  R  Restart current track")
    print("  Q  Quit")
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
    print("Error: First argument must be folder path starting with /")
    print("Example: play /songs")
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
    print("Error: No speakers found!")
    return
end

print("Using " .. #speakers .. " speaker(s)")

-- ====================== ЗАГРУЗКА ПЛЕЙЛИСТА ======================
if not fs.exists(folderPath) or not fs.isDir(folderPath) then
    print("Error: Folder '" .. folderPath .. "' not found!")
    return
end

print("Scanning folder: " .. folderPath)

local files = fs.list(folderPath)
local playlist = {}

for _, filename in ipairs(files) do
    local lowerName = filename:lower()
    if lowerName:sub(-6) == ".dfpwm" then
        local fullPath = fs.combine(folderPath, filename)
        table.insert(playlist, {path = fullPath, name = filename})
        print(" + " .. filename)
    end
end

if #playlist == 0 then
    print("Error: No .dfpwm files found in " .. folderPath)
    return
end

print("Loaded " .. #playlist .. " tracks.")

-- ====================== ШАФЛ ======================
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
    local nextTrack = playlist[index % #playlist + 1]
    
    if displayMode == "computer" or displayMode == "both" then
        term.clear()
        term.setCursorPos(1,1)
        term.setTextColor(colors.cyan)
        print("=== MUSIC PLAYER ===")
        term.setTextColor(colors.yellow)
        print("\nNOW PLAYING:")
        term.setTextColor(colors.white)
        print(" " .. track.name)
        term.setTextColor(colors.lightGray)
        print("\nNEXT:")
        print(" " .. (nextTrack and nextTrack.name or "—"))
        if isLoop then print(" [LOOP ON]") end
        if isShuffle then print(" [SHUFFLE]") end
        if paused then print(" [PAUSED]") end
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
        monitor.write(track.name:sub(1, 30))
    end
end

-- ====================== ВОСПРОИЗВЕДЕНИЕ ======================
local dfpwm = require("cc.audio.dfpwm")
local decoder = dfpwm.make_decoder()

local function playTrack(index)
    local track = playlist[index]
    local file = fs.open(track.path, "rb")
    local audioData = file.readAll()
    file.close()

    drawDisplay(index, false)

    local functions = {}
    for _, speaker in ipairs(speakers) do
        table.insert(functions, function()
            for pos = 1, #audioData, 16384 do
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

-- ====================== ГЛАВНЫЙ ЦИКЛ ======================
local currentIndex = 1
local paused = false

while true do
    playTrack(currentIndex)

    if not isLoop and currentIndex >= #playlist then
        break
    end

    currentIndex = currentIndex % #playlist + 1
end

term.clear()
term.setCursorPos(1,1)
print("Playlist finished.")
if monitor then monitor.clear() end