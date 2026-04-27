-- ============================================================================== --
-- // SKIBI DEFENSE - FLUENT MACRO EDITION V36 [GROUND CLICK FIX]
-- // V36 Fix: AstroJugg place ใช้ตำแหน่ง mouse.Hit (จุดที่ user คลิก = พื้น)
-- //          เพราะ flying unit ต้อง spawn ที่พื้นแล้วเกมจะลอยขึ้นเอง
-- //          + เพิ่ม smart fallback ใช้ raycast หา ground Y
-- //          + เพิ่ม retry หลายตำแหน่งถ้า place ไม่สำเร็จ
-- // V35: ใช้ตำแหน่งจริง (ผิด - flying unit ลอยไปจากจุดวางจริง)
-- // V34: Money Debounce, Reverse Lookup, Safe JSON, Configurable
-- ============================================================================== --

-- ============================================================================== --
-- // 0. CONFIG (รวบรวม Magic Numbers ทั้งหมด)
-- ============================================================================== --
local CONFIG = {
    -- Timing
    MONEY_CACHE_DURATION = 0.1,          -- cache เงินกี่วินาที
    MONEY_CHECK_INTERVAL = 0.1,          -- เช็คเงินทุกกี่วินาที (V33 = 0.05 เร็วเกิน)
    AUTO_SKIP_INTERVAL = 0.5,
    AUTO_SPEED_INTERVAL = 1,
    PLACE_RETRY_DELAY = 0.5,
    UPGRADE_RETRY_DELAY = 0.4,
    SELL_RETRY_DELAY = 0.4,
    
    -- Limits & Timeouts
    MAX_PLACE_ATTEMPTS = 120,            -- 120 * 0.5s = 60s (V33 = 600 = 5 นาที!)
    MAX_UPGRADE_ATTEMPTS = 90,           -- 90 * 0.4s = 36s
    MAX_SELL_ATTEMPTS = 60,              -- 60 * 0.4s = 24s
    MONEY_QUEUE_TTL = 5,                 -- entry เก่าเกินกี่วิ ถือว่าหมดอายุ
    MONEY_QUEUE_MAX = 50,                -- จำกัดขนาด queue
    
    -- Logic
    MONEY_MARGIN_PCT = 0.05,             -- ยอมรับเงินขาด 5%
    ADAPTIVE_DELAY_THRESHOLD = 0.8,      -- เงินต่ำกว่า 80% ของเป้า → หน่วง
    ADAPTIVE_DELAY_MULTIPLIER = 1.5,
    UNIT_SEARCH_MAX_DIST = 999999,
    
    -- File
    MACRO_FOLDER = "SkibiMacroData",
    
    -- Debug
    DEBUG_LOG = false,                   -- เปิด print debug
}

local function dbg(...)
    if CONFIG.DEBUG_LOG then
        warn("[SkibiMacro V34]", ...)
    end
end

-- ============================================================================== --
-- // 1. SERVICES & REFERENCES
-- ============================================================================== --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local EventFolder = ReplicatedStorage:WaitForChild("Event")
local PlaceRemote = EventFolder:WaitForChild("placeTower")
local UpgradeRemote = EventFolder:WaitForChild("UpgradeTower")
local SellRemote = EventFolder:WaitForChild("RemoveTower")

-- ============================================================================== --
-- // 2. FLUENT UI
-- ============================================================================== --
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local Window = Fluent:CreateWindow({
    Title = "Skibi Macro V36",
    SubTitle = "Ground Click Fix",
    TabWidth = 160,
    Size = UDim2.fromOffset(500, 480),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "play" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}
local Options = Fluent.Options

-- ============================================================================== --
-- // 3. STATE (ใช้ local แทน _G เพื่อความปลอดภัย)
-- ============================================================================== --
local MacroData = {}                     -- ⭐ เปลี่ยนจาก _G.MacroData เป็น local
local MoneyQueue = {}
local isRecording = false
local isReplaying = false
local recordStartTime = 0
local actionCount = 0
local activeConnections = {}
local hasPlayedThisRound = false
local lastSeenWave = 0

-- Caches
local cachedMoney = 0
local lastMoneyUpdate = 0
local unitNameCache = {}                 -- weak table จะดีกว่าแต่ Lua 5.1 weak ใช้ยาก

-- Recording state
local cachedPos = {}
local cachedName = {}
local lastUpgRecord = {}

-- Playback state
local playInstanceMap = {}               -- targetID → unit instance
local playInstanceReverse = {}           -- ⭐ unit → targetID (reverse lookup สำหรับ O(1))
local currentPlaybackSession = 0

-- ============================================================================== --
-- // 4. HELPER FUNCTIONS
-- ============================================================================== --
local function safeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then dbg("safeCall error:", err) end
    return ok
end

local function ParseMoney(val)
    if not val then return 0 end
    local cleanVal = string.upper(tostring(val))
    cleanVal = string.gsub(cleanVal, ",", "")
    cleanVal = string.gsub(cleanVal, "%$", "")
    
    local numStr = string.match(cleanVal, "[%d%.]+")
    if not numStr then return 0 end
    local num = tonumber(numStr) or 0
    
    if string.find(cleanVal, "K") then num = num * 1000
    elseif string.find(cleanVal, "M") then num = num * 1000000
    elseif string.find(cleanVal, "B") then num = num * 1000000000
    elseif string.find(cleanVal, "T") then num = num * 1000000000000 end
    
    return math.floor(num)
end

local function GetCurrentMoney()
    if tick() - lastMoneyUpdate < CONFIG.MONEY_CACHE_DURATION then
        return cachedMoney
    end
    
    local exactMoney = nil
    pcall(function()
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        local moneyObj = ls and (ls:FindFirstChild("Money") or ls:FindFirstChild("Cash"))
        if moneyObj then
            if type(moneyObj.Value) == "number" then
                exactMoney = math.floor(moneyObj.Value)
            else
                exactMoney = ParseMoney(tostring(moneyObj.Value))
            end
        end
    end)
    
    if not exactMoney then
        pcall(function()
            exactMoney = ParseMoney(LocalPlayer.PlayerGui.Towers.Cash.Frame.TextLabel.Text)
        end)
    end
    
    cachedMoney = exactMoney or 0
    lastMoneyUpdate = tick()
    return cachedMoney
end

local function GetCurrentWave()
    local currentWave = 1
    pcall(function()
        local numStr = string.match(LocalPlayer.PlayerGui.Data.Wave.Frame.TextLabel.Text, "%d+")
        if numStr then currentWave = tonumber(numStr) end
    end)
    return currentWave
end

local function CleanStr(s)
    return string.gsub(string.lower(tostring(s)), "[%s%p]", "")
end

local function GetCleanedName(unit)
    if unitNameCache[unit] then return unitNameCache[unit] end
    local cleaned = CleanStr(unit.Name)
    unitNameCache[unit] = cleaned
    return cleaned
end

-- ⭐ Custom GetModelCFrame (deprecated API replacement)
local function GetModelCFrame(model)
    if model.PrimaryPart then return model.PrimaryPart.CFrame end
    
    local sumX, sumY, sumZ, count = 0, 0, 0, 0
    for _, part in pairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            sumX = sumX + part.Position.X
            sumY = sumY + part.Position.Y
            sumZ = sumZ + part.Position.Z
            count = count + 1
        end
    end
    if count > 0 then
        return CFrame.new(sumX/count, sumY/count, sumZ/count)
    end
    return CFrame.new(0, 0, 0)
end

-- ⭐ Raycast หาความสูงพื้นแบบ reusable
local function RaycastGroundY(x, z, ignoreList)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList or {}
    
    local hit = Workspace:Raycast(
        Vector3.new(x, 1000, z),
        Vector3.new(0, -3000, 0),
        params
    )
    return hit and hit.Position.Y or nil
end

local function GetUnitByPosition(targetName, targetPosCf)
    if not targetPosCf or not targetName then return nil end
    local targetPos = targetPosCf.Position
    local bestUnit = nil
    local closestDist = CONFIG.UNIT_SEARCH_MAX_DIST
    local searchName = CleanStr(targetName)
    
    local targetFolder = Workspace:FindFirstChild("Scripted")
        and Workspace.Scripted:FindFirstChild("Towers")
    if not targetFolder then return nil end
    
    for _, unit in ipairs(targetFolder:GetChildren()) do
        local uName = GetCleanedName(unit)
        local sId = CleanStr(unit:GetAttribute("sID") or "")
        
        if string.find(uName, searchName, 1, true) or string.find(sId, searchName, 1, true) then
            local cf = unit.PrimaryPart and unit.PrimaryPart.CFrame or GetModelCFrame(unit)
            if cf then
                local dist = (cf.Position - targetPos).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    bestUnit = unit
                end
            end
        end
    end
    return bestUnit
end

local function FormatCFrame(cf)
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:components()
    return string.format("%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f",
        x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

local function ParseCFrameStr(str)
    if not str then return nil end
    local p = {}
    for num in string.gmatch(str, "([^,]+)") do
        table.insert(p, tonumber(num))
    end
    if #p < 3 then return nil end
    return p
end

local function GetRealUnitName(towerModel)
    local sID = towerModel:GetAttribute("sID")
    if sID and sID ~= "" then return sID end
    return string.gsub(string.gsub(towerModel.Name, " Lvl?%.?%s*%d+", ""), " %(Lv.*%)", "")
end

local function GetExactCost(unitName, actionType, targetLevel)
    if actionType == "Sell" or actionType == "Speed" then return 0 end
    local cost = 0
    pcall(function()
        local td = ReplicatedStorage:FindFirstChild("TowerData")
            and ReplicatedStorage.TowerData:FindFirstChild("Units")
        if not td then return end
        
        local searchName = CleanStr(unitName)
        local module = nil
        for _, child in ipairs(td:GetChildren()) do
            local cn = CleanStr(child.Name)
            if cn == searchName or cn == searchName .. "unit" then
                module = child
                break
            end
        end
        if not module then return end
        
        local data = require(module)
        if actionType == "Place" then
            cost = data.Price or data.Cost or data.BasePrice or data.DeployCost or 0
        elseif actionType == "Upgrade" and data.Upgrades then
            local lvl = tonumber(targetLevel)
            local upg = data.Upgrades[lvl]
                or data.Upgrades[lvl - 1]
                or data.Upgrades[tostring(lvl)]
                or data.Upgrades[tostring(lvl - 1)]
            
            if type(upg) == "number" then
                cost = upg
            elseif type(upg) == "table" then
                cost = upg.Price or upg.Cost or upg.UpgradeCost or 0
            end
        end
    end)
    return cost
end

-- ⭐ Helper จัดการ playInstanceMap แบบมี reverse-lookup
local function SetPlayInstance(targetID, unit)
    -- ลบของเดิมออกจาก reverse ก่อน
    local oldUnit = playInstanceMap[targetID]
    if oldUnit then playInstanceReverse[oldUnit] = nil end
    
    playInstanceMap[targetID] = unit
    if unit then playInstanceReverse[unit] = targetID end
end

local function ClearPlayInstanceMap()
    table.clear(playInstanceMap)
    table.clear(playInstanceReverse)
end

local function IsUnitOwned(unit)
    return playInstanceReverse[unit] ~= nil
end

-- ⭐ Money Queue cleanup
local function CleanupMoneyQueue()
    local now = tick()
    local i = 1
    while i <= #MoneyQueue do
        local entry = MoneyQueue[i]
        if entry.claimed or (now - entry.time) > CONFIG.MONEY_QUEUE_TTL then
            table.remove(MoneyQueue, i)
        else
            i = i + 1
        end
    end
    -- Hard cap กันโตเกิน
    while #MoneyQueue > CONFIG.MONEY_QUEUE_MAX do
        table.remove(MoneyQueue, 1)
    end
end

local function ClearConnections()
    for i = #activeConnections, 1, -1 do
        local conn = activeConnections[i]
        if conn and conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
        activeConnections[i] = nil
    end
end

-- ⭐ Safe JSON Decode
local function SafeJSONDecode(str)
    if not str or str == "" then return nil, "empty content" end
    local ok, result = pcall(HttpService.JSONDecode, HttpService, str)
    if ok then return result end
    return nil, tostring(result)
end

-- ============================================================================== --
-- // 5. AUTO SKIP / SPEED / MONEY TRACKER
-- ============================================================================== --
task.spawn(function()
    while task.wait(CONFIG.AUTO_SKIP_INTERVAL) do
        if Options.AutoSkip and Options.AutoSkip.Value then
            pcall(function()
                local skipGui = LocalPlayer.PlayerGui:FindFirstChild("skipWave")
                if skipGui and skipGui:IsA("ScreenGui") and skipGui.Enabled then
                    local frame = skipGui:FindFirstChild("Frame")
                    if frame and frame.Visible then
                        local yBtn = frame:FindFirstChild("Y")
                        if yBtn and yBtn.Visible then
                            if getconnections then
                                for _, conn in pairs(getconnections(yBtn.MouseButton1Click)) do conn:Fire() end
                                for _, conn in pairs(getconnections(yBtn.Activated)) do conn:Fire() end
                            elseif firesignal then
                                firesignal(yBtn.MouseButton1Click)
                                firesignal(yBtn.Activated)
                            end
                        end
                    end
                end
                local ef = ReplicatedStorage:FindFirstChild("Event")
                if ef and ef:FindFirstChild("waveSkip") then
                    ef.waveSkip:FireServer(true)
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait(CONFIG.AUTO_SPEED_INTERVAL) do
        if Options.AutoSpeed and Options.AutoSpeed.Value ~= "Off" then
            pcall(function()
                local desiredSpeed = 1
                local val = Options.AutoSpeed.Value
                if val == "Pause" then
                    desiredSpeed = 0
                elseif string.match(val, "%d+") then
                    desiredSpeed = tonumber(string.match(val, "%d+"))
                end
                
                local currentSpeed = -1
                local towersGui = LocalPlayer.PlayerGui:FindFirstChild("Towers")
                if towersGui then
                    local speedBtn = towersGui:FindFirstChild("speedButton")
                    if speedBtn then
                        if speedBtn:FindFirstChild("Pause") and speedBtn.Pause.Visible then
                            currentSpeed = 0
                        else
                            for i = 1, 5 do
                                local child = speedBtn:FindFirstChild(tostring(i) .. "x")
                                if child and child:IsA("GuiObject") and child.Visible then
                                    currentSpeed = i
                                    break
                                end
                            end
                        end
                    end
                end
                
                local gameRs = ReplicatedStorage:FindFirstChild("Game")
                if gameRs and gameRs:FindFirstChild("Speed") and gameRs.Speed:FindFirstChild("Change") then
                    if currentSpeed ~= desiredSpeed and currentSpeed ~= -1 then
                        gameRs.Speed.Change:FireServer(desiredSpeed)
                    elseif currentSpeed == -1 then
                        gameRs.Speed.Change:FireServer(desiredSpeed)
                        task.wait(2)
                    end
                end
            end)
        end
    end
end)

-- ⭐ Money Tracker — เลิกใช้ debounce ที่บั๊ก ใช้ flag กัน race ตอน insert เท่านั้น
task.spawn(function()
    while not LocalPlayer:FindFirstChild("leaderstats") do task.wait(0.5) end
    local lastMoney = GetCurrentMoney()
    local isDropping = false
    local preDropMoney = 0
    local cleanupCounter = 0
    
    while task.wait(CONFIG.MONEY_CHECK_INTERVAL) do
        local curMoney = GetCurrentMoney()
        
        if curMoney < lastMoney then
            if not isDropping then
                isDropping = true
                preDropMoney = lastMoney
            end
        elseif curMoney == lastMoney then
            if isDropping then
                local totalSpent = preDropMoney - curMoney
                if totalSpent > 0 then
                    table.insert(MoneyQueue, { amount = totalSpent, time = tick(), claimed = false })
                end
                isDropping = false
            end
        else  -- curMoney > lastMoney
            if isDropping then
                local totalSpent = preDropMoney - lastMoney
                if totalSpent > 0 then
                    table.insert(MoneyQueue, { amount = totalSpent, time = tick(), claimed = false })
                end
                isDropping = false
            end
        end
        
        lastMoney = curMoney
        
        -- Cleanup queue ทุก ~5 วินาที (50 รอบ × 0.1s)
        cleanupCounter = cleanupCounter + 1
        if cleanupCounter >= 50 then
            cleanupCounter = 0
            CleanupMoneyQueue()
        end
    end
end)

-- ============================================================================== --
-- // 6. UI: Macro Profiles & Controls
-- ============================================================================== --
local StatusPara = Tabs.Main:AddParagraph({
    Title = "Macro Status: None",
    Content = "Action: -\nType: -\nUnit: -\nWaiting for: -"
})

local function UpdateStatus(status, action, actType, unit, waiting)
    StatusPara:SetTitle("Macro Status: " .. (status or "None"))
    StatusPara:SetDesc(string.format(
        "Action: %s\nType: %s\nUnit: %s\nWaiting for: %s",
        tostring(action or "-"),
        tostring(actType or "-"),
        tostring(unit or "-"),
        tostring(waiting or "-")
    ))
end

Tabs.Main:AddSection("File & Profiles")
if not isfolder(CONFIG.MACRO_FOLDER) then makefolder(CONFIG.MACRO_FOLDER) end

local function GetMacroFiles()
    local files = {}
    for _, v in ipairs(listfiles(CONFIG.MACRO_FOLDER)) do
        local name = string.match(v, "([^/\\]+)%.json$")
        if name then table.insert(files, name) end
    end
    if #files == 0 then table.insert(files, "None") end
    return files
end

local ProfileDrop = Tabs.Main:AddDropdown("MacroProfiles", {
    Title = "Macro Profiles",
    Values = GetMacroFiles(),
    Default = 1,
    Multi = false
})
local NewProfileInput = Tabs.Main:AddInput("NewProfileName", {
    Title = "New macro profile",
    Default = "",
    Placeholder = "พิมพ์ชื่อไฟล์ใหม่ที่นี่..."
})

Tabs.Main:AddButton({
    Title = "Create new macro (Save)",
    Callback = function()
        local fName = Options.NewProfileName.Value
        if fName == "" then
            Fluent:Notify({ Title = "Error", Content = "พิมพ์ชื่อไฟล์ก่อนเซฟ!", Duration = 3 })
            return
        end
        local ok = pcall(function()
            writefile(CONFIG.MACRO_FOLDER .. "/" .. fName .. ".json", HttpService:JSONEncode(MacroData))
        end)
        if ok then
            Options.MacroProfiles:SetValues(GetMacroFiles())
            Options.MacroProfiles:SetValue(fName)
            Fluent:Notify({ Title = "Saved", Content = "บันทึก " .. fName .. ".json สำเร็จ!", Duration = 3 })
        else
            Fluent:Notify({ Title = "Error", Content = "บันทึกไฟล์ไม่สำเร็จ", Duration = 3 })
        end
    end
})

Tabs.Main:AddButton({
    Title = "Delete selected macro",
    Callback = function()
        local fName = Options.MacroProfiles.Value
        if fName == "None" or fName == "" then return end
        if isfile(CONFIG.MACRO_FOLDER .. "/" .. fName .. ".json") then
            pcall(function() delfile(CONFIG.MACRO_FOLDER .. "/" .. fName .. ".json") end)
            Fluent:Notify({ Title = "Deleted", Content = "ลบไฟล์สำเร็จ!", Duration = 3 })
            local files = GetMacroFiles()
            Options.MacroProfiles:SetValues(files)
            Options.MacroProfiles:SetValue(files[1])
        end
    end
})

Tabs.Main:AddSection("Macro Controls")
local AutoSkipToggle = Tabs.Main:AddToggle("AutoSkip", { Title = "Auto Skip Wave", Default = false })
local AutoReplayToggle = Tabs.Main:AddToggle("AutoReplay", { Title = "Auto Replay", Default = false })
local AutoReadyToggle = Tabs.Main:AddToggle("AutoReady", { Title = "Auto Ready", Default = false })
local RecordToggle = Tabs.Main:AddToggle("RecordMacro", { Title = "Record Macro", Default = false })
local PlayToggle = Tabs.Main:AddToggle("PlayMacro", { Title = "Play Macro", Default = false })
local AutoSpeedDrop = Tabs.Main:AddDropdown("AutoSpeed", {
    Title = "Auto Speed Lock (Record Speed Here!)",
    Values = { "Off", "Pause", "1x", "2x", "3x", "4x", "5x" },
    Default = 1
})
Tabs.Main:AddSlider("StepDelay", { Title = "Step Delay", Default = 0.2, Min = 0.1, Max = 5, Rounding = 1 })
local PlayModes = Tabs.Main:AddDropdown("PlayModes", {
    Title = "Play Modes",
    Values = { "Time", "Wave", "Money" },
    Multi = true,
    Default = { "Wave", "Money" }
})

-- Settings tab
Tabs.Settings:AddSection("Debug")
Tabs.Settings:AddToggle("DebugLog", { Title = "Enable Debug Log", Default = false }):OnChanged(function(v)
    CONFIG.DEBUG_LOG = v
end)

-- ⭐ V36: Force Ground Y สำหรับ flying units ที่ pos บันทึกผิด
Tabs.Settings:AddSection("Flying Unit Fix (AstroJugg etc.)")
Tabs.Settings:AddToggle("ForceGroundY", {
    Title = "Force Raycast Ground Y on Place",
    Default = true,  -- เปิด default เพราะแก้ปัญหา flying unit
    Description = "ใช้ Y ของพื้นแทน Y ที่บันทึก (สำหรับ AstroJugg)"
})

Tabs.Settings:AddSection("Diagnostic Tools")
Tabs.Settings:AddButton({
    Title = "Test Place AstroJugg (debug)",
    Callback = function()
        -- ทดสอบ place AstroJugg ที่ตำแหน่งกล้องตอนนี้
        local cam = Workspace.CurrentCamera
        local hit = Workspace:Raycast(
            cam.CFrame.Position,
            cam.CFrame.LookVector * 500,
            RaycastParams.new()
        )
        if hit then
            local testCf = CFrame.new(hit.Position.X, hit.Position.Y, hit.Position.Z)
            print("[V36 TEST] Trying to place AstroJugg at:", testCf.Position)
            local ok, err = pcall(function()
                PlaceRemote:FireServer("AstroJugg", testCf, false)
            end)
            print("[V36 TEST] Result:", ok, err)
            Fluent:Notify({
                Title = "Test fired",
                Content = "ดู console ว่า AstroJugg วางได้ไหม",
                Duration = 5
            })
        else
            Fluent:Notify({ Title = "Error", Content = "ไม่เจอจุดวาง ลองชี้กล้องลงพื้น", Duration = 3 })
        end
    end
})

Tabs.Settings:AddButton({
    Title = "Print Remote Info",
    Callback = function()
        print("===== PlaceRemote Info =====")
        print("Name:", PlaceRemote.Name)
        print("ClassName:", PlaceRemote.ClassName)
        print("Parent:", PlaceRemote:GetFullName())
        print("===========================")
        Fluent:Notify({ Title = "Printed", Content = "ดู console (F9)", Duration = 3 })
    end
})

-- ============================================================================== --
-- // 7. RECORDING LOGIC
-- ============================================================================== --
local function WipeRecordingState()
    table.clear(MacroData)
    actionCount = 0
    table.clear(MoneyQueue)
    recordStartTime = tick()
    ClearConnections()
end

local function RecordAction(actionType, targetId, posCf, unitName, exactTime, specificLevel)
    actionCount = actionCount + 1
    local currentActionId = actionCount
    
    local stepData = {
        type = actionType,
        targetID = tostring(targetId),
        time = exactTime,
        wave = GetCurrentWave(),
        unit = unitName,
        cost = 0,
        level = specificLevel or 1
    }
    if posCf then stepData.pos = FormatCFrame(posCf) end
    
    MacroData[tostring(currentActionId)] = stepData
    
    -- หา cost แบบ async ไม่บล็อก main thread
    task.spawn(function()
        local exactCost = GetExactCost(unitName, actionType, specificLevel or 1)
        if exactCost == 0 and actionType ~= "Sell" and actionType ~= "Speed" then
            local passTime = 0
            while passTime < 1.5 do
                for _, drop in ipairs(MoneyQueue) do
                    if not drop.claimed and (tick() - drop.time) <= 3 then
                        exactCost = drop.amount
                        drop.claimed = true
                        break
                    end
                end
                if exactCost > 0 then break end
                task.wait(0.1)
                passTime = passTime + 0.1
            end
        end
        stepData.cost = exactCost
        
        local displayWait = "Cost: $" .. exactCost .. " | Lvl: " .. (specificLevel or 1)
        if actionType == "Speed" then
            displayWait = "Speed set to " .. (specificLevel == 0 and "Pause" or specificLevel .. "x")
        end
        UpdateStatus("Recording", currentActionId, actionType, unitName, displayWait)
    end)
end

local mouse = LocalPlayer:GetMouse()
local lastGroundPos = nil

UserInputService.InputBegan:Connect(function(input, gpe)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and not gpe then
        pcall(function() lastGroundPos = mouse.Hit.Position end)
    end
end)

local function StartObserving()
    local towerDataFolder = Workspace:FindFirstChild("Scripted")
        and Workspace.Scripted:FindFirstChild("TowerData")
    local towersFolder = Workspace:FindFirstChild("Scripted")
        and Workspace.Scripted:FindFirstChild("Towers")
    if not towerDataFolder or not towersFolder then
        dbg("Cannot find TowerData/Towers folder")
        return
    end
    
    table.clear(cachedPos)
    table.clear(cachedName)
    table.clear(lastUpgRecord)
    
    local function hookTowerData(tDataObj)
        local upgConn = tDataObj:GetAttributeChangedSignal("Upgrade"):Connect(function()
            if not isRecording then return end
            local targetId = tDataObj.Name
            local currentLvl = tonumber(tDataObj:GetAttribute("Upgrade")) or 2
            
            if lastUpgRecord[targetId] == currentLvl then return end
            lastUpgRecord[targetId] = currentLvl
            
            local exactTime = tick() - recordStartTime
            local posCf = cachedPos[targetId]
            local unitName = cachedName[targetId] or "Unknown"
            
            if not posCf then
                local unitModel = towersFolder:FindFirstChild(targetId)
                if unitModel then
                    posCf = unitModel.PrimaryPart and unitModel.PrimaryPart.CFrame or GetModelCFrame(unitModel)
                    unitName = GetRealUnitName(unitModel)
                end
            end
            
            RecordAction("Upgrade", targetId, posCf, unitName, exactTime, currentLvl)
        end)
        table.insert(activeConnections, upgConn)
    end
    
    local addConn = towerDataFolder.ChildAdded:Connect(function(tDataObj)
        if not isRecording then return end
        task.wait(0.2)
        
        local exactTime = tick() - recordStartTime
        local targetId = tDataObj.Name
        local unitModel = towersFolder:FindFirstChild(targetId)
        local unitName = unitModel and GetRealUnitName(unitModel) or "Unknown"
        
        -- ⭐ V36 FIX: ใช้ mouse.Hit (จุดที่ user คลิกบนพื้น) เป็นหลัก
        -- เหตุผล: Flying units (AstroJugg) ต้อง place ที่พื้น แล้วเกมจะลอยขึ้นเอง
        -- ถ้าใช้ตำแหน่งจริงของ unit (ที่ลอยอยู่บนฟ้าแล้ว) → server reject
        local posCf = CFrame.new(0, 0, 0)
        
        if lastGroundPos then
            -- ⭐ Priority 1: ใช้จุดที่ user คลิกตรงๆ (ที่ราบในแผนที่)
            posCf = CFrame.new(lastGroundPos.X, lastGroundPos.Y, lastGroundPos.Z)
            lastGroundPos = nil
        elseif unitModel then
            -- Priority 2: หาตำแหน่ง unit แล้ว raycast ลงพื้น
            local mCf = unitModel.PrimaryPart and unitModel.PrimaryPart.CFrame or GetModelCFrame(unitModel)
            
            local ignoreList = { Workspace.Scripted }
            if LocalPlayer.Character then
                table.insert(ignoreList, LocalPlayer.Character)
            end
            
            -- raycast ลงพื้นจาก X,Z ของ unit เพื่อหา Y พื้นจริง
            local groundY = RaycastGroundY(mCf.X, mCf.Z, ignoreList)
            
            if groundY then
                -- เจอพื้น → ใช้ Y พื้น (รองรับ flying unit ที่ลอยไปแล้ว)
                posCf = CFrame.new(mCf.X, groundY, mCf.Z)
            else
                -- ไม่เจอพื้น → ใช้ Y ของ unit (อาจเป็น ground unit บนพื้นอยู่แล้ว)
                posCf = CFrame.new(mCf.X, mCf.Y, mCf.Z)
            end
        end
        
        cachedPos[targetId] = posCf
        cachedName[targetId] = unitName
        lastUpgRecord[targetId] = 1
        
        RecordAction("Place", targetId, posCf, unitName, exactTime, 1)
        hookTowerData(tDataObj)
    end)
    
    local remConn = towerDataFolder.ChildRemoved:Connect(function(tDataObj)
        if not isRecording then return end
        local exactTime = tick() - recordStartTime
        local targetId = tDataObj.Name
        local posCf = cachedPos[targetId]
        local unitName = cachedName[targetId] or "Unknown"
        RecordAction("Sell", targetId, posCf, unitName, exactTime, 0)
        
        cachedPos[targetId] = nil
        cachedName[targetId] = nil
        lastUpgRecord[targetId] = nil
    end)
    
    table.insert(activeConnections, addConn)
    table.insert(activeConnections, remConn)
    
    for _, child in ipairs(towerDataFolder:GetChildren()) do
        hookTowerData(child)
    end
end

local function StartRecordingProcess()
    if PlayToggle.Value then PlayToggle:SetValue(false) end
    isRecording = true
    WipeRecordingState()
    UpdateStatus("Recording...", "-", "-", "-", "Start placing units")
    Fluent:Notify({ Title = "Recording Started", Content = "เริ่มอัดมาโคร V36!", Duration = 3 })
    StartObserving()
end

-- ============================================================================== --
-- // 8. PLAYBACK LOGIC
-- ============================================================================== --
local function PlayMacroData()
    if not isReplaying then return end
    
    currentPlaybackSession = currentPlaybackSession + 1
    local mySession = currentPlaybackSession
    
    task.spawn(function()
        local modes = Options.PlayModes.Value or {}
        local useTime = modes["Time"]
        local useWave = modes["Wave"]
        local useMoney = modes["Money"]
        local playStartTime = tick()
        ClearPlayInstanceMap()
        
        local function shouldStop()
            return not isReplaying or mySession ~= currentPlaybackSession
        end
        
        for i = 1, actionCount do
            if shouldStop() then return end
            
            local step = MacroData[tostring(i)]
            if not step then continue end
            
            -- คำนวณเงินที่ต้องใช้
            local requiredMoney = ParseMoney(step.cost)
            if requiredMoney <= 0 and step.type ~= "Sell" and step.type ~= "Speed" then
                requiredMoney = GetExactCost(step.unit, step.type, step.level)
            end
            
            -- ⭐ Adaptive Delay: เช็คซ้ำในลูปเพื่อ dynamic adjustment
            local baseDelay = Options.StepDelay.Value
            local passed = 0
            while passed < baseDelay do
                if shouldStop() then return end
                
                -- ปรับ delay ตามสถานะเงินจริงในขณะนั้น
                local effectiveDelay = baseDelay
                if useMoney and requiredMoney > 0
                    and GetCurrentMoney() < requiredMoney * CONFIG.ADAPTIVE_DELAY_THRESHOLD then
                    effectiveDelay = baseDelay * CONFIG.ADAPTIVE_DELAY_MULTIPLIER
                end
                
                if passed >= effectiveDelay then break end
                
                UpdateStatus("Playing", i, step.type, step.unit,
                    string.format("Buffer (%.1fs)", effectiveDelay - passed))
                task.wait(0.1)
                passed = passed + 0.1
            end
            
            -- รอเวลา global
            if useTime then
                while (tick() - playStartTime) < step.time do
                    if shouldStop() then return end
                    UpdateStatus("Playing", i, step.type, step.unit,
                        string.format("Global Time (%.1fs)", step.time - (tick() - playStartTime)))
                    task.wait(0.1)
                end
            end
            
            -- รอ wave
            if useWave and step.wave then
                while GetCurrentWave() < step.wave do
                    if shouldStop() then return end
                    UpdateStatus("Playing", i, step.type, step.unit, "Wave " .. step.wave)
                    task.wait(1)
                end
            end
            
            -- รอเงิน
            if useMoney and requiredMoney > 0 and step.type ~= "Speed" then
                local margin = requiredMoney * CONFIG.MONEY_MARGIN_PCT
                while GetCurrentMoney() < (requiredMoney - margin) do
                    if shouldStop() then return end
                    UpdateStatus("Playing", i, step.type, step.unit, "Money ($" .. requiredMoney .. ")")
                    task.wait(0.5)
                end
            end
            
            if shouldStop() then return end
            UpdateStatus("Playing", i, step.type, step.unit, "Executing...")
            
            -- ⭐ V35 FIX: ใช้ตำแหน่งจริงจาก JSON ตรงๆ (ไม่ raycast ทับ)
            -- เหตุผล: AstroJugg เป็น flying unit Y สูง 78
            --        ถ้าไป raycast ลงพื้น จะได้ Y ผิด → server reject
            local targetPosCf = nil
            local p = ParseCFrameStr(step.pos)
            if p then
                pcall(function()
                    if step.type == "Place" then
                        -- ใช้ X, Y, Z ตรงๆ จาก JSON ไม่ปรับแต่ง
                        -- เพราะตอน record เราเก็บตำแหน่งจริงของ unit แล้ว
                        targetPosCf = CFrame.new(p[1] or 0, p[2] or 0, p[3] or 0)
                    else
                        -- Upgrade/Sell ใช้ CFrame เต็มถ้ามี
                        if #p >= 12 then
                            targetPosCf = CFrame.new(unpack(p))
                        else
                            targetPosCf = CFrame.new(p[1] or 0, p[2] or 0, p[3] or 0)
                        end
                    end
                end)
            end
            
            -- =========== EXECUTE ===========
            if step.type == "Speed" then
                local targetSpeed = tonumber(step.level) or 1
                pcall(function()
                    local gameRs = ReplicatedStorage:FindFirstChild("Game")
                    if gameRs and gameRs:FindFirstChild("Speed") and gameRs.Speed:FindFirstChild("Change") then
                        gameRs.Speed.Change:FireServer(targetSpeed)
                    end
                end)
                task.wait(0.2)
                
            elseif step.type == "Place" then
                local isPlaced = false
                local attempts = 0
                
                -- ⭐ V36: เตรียม fallback positions ไว้ลองหลายแบบ
                -- ถ้า pos จาก JSON ไม่ทำงาน (อาจเป็น Y ของ flying unit ที่ลอยขึ้นไปแล้ว)
                -- ลอง raycast ลงพื้นที่ X,Z เดียวกัน
                local fallbackPositions = {}
                local forceGround = Options.ForceGroundY and Options.ForceGroundY.Value
                
                if targetPosCf then
                    local ignoreList = { Workspace.Scripted }
                    if LocalPlayer.Character then
                        table.insert(ignoreList, LocalPlayer.Character)
                    end
                    local groundY = RaycastGroundY(targetPosCf.X, targetPosCf.Z, ignoreList)
                    
                    -- ⭐ ตัดสินใจลำดับลอง pos
                    if forceGround and groundY then
                        -- เปิด ForceGroundY → ลอง ground Y ก่อน เพราะ flying unit ต้องวางที่พื้น
                        table.insert(fallbackPositions, CFrame.new(targetPosCf.X, groundY, targetPosCf.Z))
                        table.insert(fallbackPositions, targetPosCf)  -- pos เดิมเป็น fallback
                        dbg(string.format("[Place %s] ForceGround ON, primary Y=%.2f, fallback Y=%.2f",
                            step.unit, groundY, targetPosCf.Y))
                    else
                        -- ลอง pos เดิมก่อน
                        table.insert(fallbackPositions, targetPosCf)
                        if groundY and math.abs(groundY - targetPosCf.Y) > 5 then
                            table.insert(fallbackPositions, CFrame.new(targetPosCf.X, groundY, targetPosCf.Z))
                        end
                    end
                end
                
                local fallbackIdx = 1
                
                repeat
                    -- ⭐ สลับใช้ตำแหน่ง fallback ทุกๆ 15 attempts
                    local currentTryPos = fallbackPositions[fallbackIdx] or targetPosCf
                    if attempts > 0 and attempts % 15 == 0 and #fallbackPositions > 1 then
                        fallbackIdx = (fallbackIdx % #fallbackPositions) + 1
                        currentTryPos = fallbackPositions[fallbackIdx]
                        dbg(string.format("[Place %s] Switching to fallback #%d Y=%.2f",
                            step.unit, fallbackIdx, currentTryPos.Y))
                    end
                    
                    pcall(function() PlaceRemote:FireServer(step.unit, currentTryPos, false) end)
                    task.wait(CONFIG.PLACE_RETRY_DELAY)
                    
                    -- ⭐ ใช้ reverse lookup O(1) แทนที่จะวน playInstanceMap
                    local foundUnit = nil
                    local targetFolder = Workspace:FindFirstChild("Scripted")
                        and Workspace.Scripted:FindFirstChild("Towers")
                    
                    if targetFolder then
                        local searchNameClean = CleanStr(step.unit)
                        local bestDist = CONFIG.UNIT_SEARCH_MAX_DIST
                        local bestUnit = nil
                        
                        for _, unit in ipairs(targetFolder:GetChildren()) do
                            if not IsUnitOwned(unit) then  -- O(1) check
                                local uNameClean = GetCleanedName(unit)
                                local sIdClean = CleanStr(unit:GetAttribute("sID") or "")
                                if string.find(uNameClean, searchNameClean, 1, true)
                                    or string.find(sIdClean, searchNameClean, 1, true) then
                                    local cf = unit.PrimaryPart and unit.PrimaryPart.CFrame or GetModelCFrame(unit)
                                    if cf and currentTryPos then
                                        local dx = cf.Position.X - currentTryPos.Position.X
                                        local dz = cf.Position.Z - currentTryPos.Position.Z
                                        local dist = math.sqrt(dx*dx + dz*dz)
                                        if dist < bestDist then
                                            bestDist = dist
                                            bestUnit = unit
                                        end
                                    end
                                end
                            end
                        end
                        foundUnit = bestUnit
                    end
                    
                    if not foundUnit then
                        foundUnit = GetUnitByPosition(step.unit, currentTryPos)
                    end
                    
                    if foundUnit then
                        isPlaced = true
                        SetPlayInstance(step.targetID, foundUnit)  -- ⭐ ใช้ helper
                    end
                    
                    if not isPlaced then
                        UpdateStatus("Playing", i, step.type, step.unit,
                            string.format("Place retry (%d/%d) [pos #%d]",
                                attempts, CONFIG.MAX_PLACE_ATTEMPTS, fallbackIdx))
                    end
                    attempts = attempts + 1
                until isPlaced or attempts >= CONFIG.MAX_PLACE_ATTEMPTS or shouldStop()
                
                if not isPlaced then
                    dbg("Place timeout for", step.unit)
                    UpdateStatus("Playing", i, step.type, step.unit, "Place TIMEOUT - skipping")
                    task.wait(0.5)
                end
                
            elseif step.type == "Upgrade" then
                local attempts = 0
                local targetLvl = tonumber(step.level) or 1
                local isUpgraded = false
                
                repeat
                    local unitToUpgrade = playInstanceMap[step.targetID]
                    
                    if not unitToUpgrade or not unitToUpgrade.Parent then
                        unitToUpgrade = GetUnitByPosition(step.unit, targetPosCf)
                        if unitToUpgrade then SetPlayInstance(step.targetID, unitToUpgrade) end
                    end
                    
                    if unitToUpgrade then
                        local currentIdStr = tostring(unitToUpgrade.Name)
                        local currentIdNum = tonumber(currentIdStr)
                        
                        pcall(function() UpgradeRemote:FireServer(currentIdStr) end)
                        if currentIdNum then
                            pcall(function() UpgradeRemote:FireServer(currentIdNum) end)
                        end
                        
                        local tData = Workspace:FindFirstChild("Scripted")
                            and Workspace.Scripted:FindFirstChild("TowerData")
                            and Workspace.Scripted.TowerData:FindFirstChild(currentIdStr)
                        if tData then
                            local currentUpgrades = tonumber(tData:GetAttribute("Upgrade")) or 0
                            if currentUpgrades >= targetLvl then
                                isUpgraded = true
                            end
                        end
                    else
                        -- ⭐ Early exit: ถ้าหา unit ไม่เจอเลย พยายามต่อก็ไม่มีผล
                        if attempts > 10 then
                            dbg("Upgrade unit not found, giving up:", step.unit)
                            break
                        end
                    end
                    
                    if not isUpgraded then
                        UpdateStatus("Playing", i, step.type, step.unit,
                            string.format("Upgrade retry (%d/%d)", attempts, CONFIG.MAX_UPGRADE_ATTEMPTS))
                        task.wait(CONFIG.UPGRADE_RETRY_DELAY)
                    end
                    attempts = attempts + 1
                until isUpgraded or attempts >= CONFIG.MAX_UPGRADE_ATTEMPTS or shouldStop()
                
            elseif step.type == "Sell" then
                local attempts = 0
                local isSold = false
                
                repeat
                    local unitToSell = playInstanceMap[step.targetID]
                    if not unitToSell or not unitToSell.Parent then
                        unitToSell = GetUnitByPosition(step.unit, targetPosCf)
                    end
                    
                    if unitToSell then
                        local currentIdStr = tostring(unitToSell.Name)
                        local currentIdNum = tonumber(currentIdStr)
                        
                        pcall(function() SellRemote:FireServer(currentIdStr) end)
                        if currentIdNum then
                            pcall(function() SellRemote:FireServer(currentIdNum) end)
                        end
                        
                        task.wait(CONFIG.SELL_RETRY_DELAY)
                        if not unitToSell.Parent then
                            SetPlayInstance(step.targetID, nil)
                            isSold = true
                        end
                    else
                        -- ถ้าไม่เจอ unit แล้ว ถือว่าขายแล้ว
                        isSold = true
                    end
                    
                    if not isSold then
                        UpdateStatus("Playing", i, step.type, step.unit,
                            string.format("Sell retry (%d/%d)", attempts, CONFIG.MAX_SELL_ATTEMPTS))
                        task.wait(CONFIG.SELL_RETRY_DELAY)
                    end
                    attempts = attempts + 1
                until isSold or attempts >= CONFIG.MAX_SELL_ATTEMPTS or shouldStop()
            end
        end
        
        if isReplaying and mySession == currentPlaybackSession then
            UpdateStatus("Completed", "-", "-", "-", "Waiting for next match...")
            Fluent:Notify({ Title = "Complete", Content = "มาโครจบรอบนี้แล้ว!", Duration = 5 })
        end
    end)
end

-- ============================================================================== --
-- // 9. AUTOMATION CORE
-- ============================================================================== --
local function IsTrulyVisible(gui)
    if not gui then return false end
    if not gui.Visible then return false end
    local sg = gui:FindFirstAncestorWhichIsA("ScreenGui")
    if sg and not sg.Enabled then return false end
    
    local pos = gui.AbsolutePosition
    local size = gui.AbsoluteSize
    local view = Workspace.CurrentCamera.ViewportSize
    
    if size.X < 1 or size.Y < 1 then return false end
    if pos.Y >= view.Y - 10 or pos.X >= view.X - 10 then return false end
    if pos.Y + size.Y <= 0 or pos.X + size.X <= 0 then return false end
    
    return true
end

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local currentWaveNum = GetCurrentWave()
            
            -- รีเซ็ตเมื่อ wave ลดลง หรือกลับมาเวฟ 1
            if (currentWaveNum < lastSeenWave or currentWaveNum == 1) and hasPlayedThisRound then
                dbg("New round detected (wave reset)")
                hasPlayedThisRound = false
                ClearPlayInstanceMap()
                currentPlaybackSession = currentPlaybackSession + 1
            end
            lastSeenWave = currentWaveNum
            
            -- เกมจบ
            local endGui = LocalPlayer.PlayerGui:FindFirstChild("GameEnded")
            local isEndedVisible = false
            if endGui then
                local frame = endGui:FindFirstChild("Frame")
                local replayBtn = frame and frame:FindFirstChild("replay")
                
                if IsTrulyVisible(frame) and IsTrulyVisible(replayBtn) then
                    isEndedVisible = true
                    if hasPlayedThisRound then
                        hasPlayedThisRound = false
                        ClearPlayInstanceMap()
                        currentPlaybackSession = currentPlaybackSession + 1
                    end
                    
                    if Options.RecordMacro and Options.RecordMacro.Value then
                        Options.RecordMacro:SetValue(false)
                    end
                    if Options.AutoReplay and Options.AutoReplay.Value then
                        task.wait(3)
                        pcall(function()
                            ReplicatedStorage.Event:WaitForChild("ReplayCore"):FireServer()
                        end)
                    end
                end
            end
            
            -- หน้าเริ่มเกม
            local startGui = LocalPlayer.PlayerGui:FindFirstChild("StartUI")
            local isStartVisible = false
            if startGui then
                local frame = startGui:FindFirstChild("Frame")
                local startBtn = frame and frame:FindFirstChild("Labels")
                    and frame.Labels:FindFirstChild("startbutton")
                
                if IsTrulyVisible(frame) and IsTrulyVisible(startBtn) then
                    isStartVisible = true
                    if hasPlayedThisRound then
                        hasPlayedThisRound = false
                        ClearPlayInstanceMap()
                        currentPlaybackSession = currentPlaybackSession + 1
                    end
                    
                    if Options.AutoReady and Options.AutoReady.Value then
                        task.wait(3)
                        pcall(function()
                            ReplicatedStorage:WaitForChild("GAME_START")
                                :WaitForChild("readyButton"):FireServer(true)
                        end)
                    end
                end
            end
            
            -- เริ่มเล่นมาโครรอบใหม่
            if isReplaying and not hasPlayedThisRound and currentWaveNum >= 1 then
                if not isEndedVisible and not isStartVisible then
                    task.wait(4)
                    if not hasPlayedThisRound then
                        hasPlayedThisRound = true
                        PlayMacroData()
                    end
                end
            end
        end)
    end
end)

-- ============================================================================== --
-- // 10. EVENT HANDLERS
-- ============================================================================== --
RecordToggle:OnChanged(function(val)
    if val then
        local fName = Options.MacroProfiles.Value
        local hasData = false
        
        if fName ~= "None" and isfile(CONFIG.MACRO_FOLDER .. "/" .. fName .. ".json") then
            local content = nil
            pcall(function() content = readfile(CONFIG.MACRO_FOLDER .. "/" .. fName .. ".json") end)
            local decoded, err = SafeJSONDecode(content)
            if decoded then
                for _ in pairs(decoded) do hasData = true; break end
            else
                dbg("JSON decode failed:", err)
            end
        end
        
        if hasData then
            Window:Dialog({
                Title = "พบข้อมูลมาโครเดิม",
                Content = "ไฟล์ '" .. fName .. "' มีข้อมูลอยู่แล้ว ต้องการอัดทับหรือไม่?",
                Buttons = {
                    { Title = "ใช่ (อัดทับ)", Callback = function() StartRecordingProcess() end },
                    { Title = "ยกเลิก", Callback = function() RecordToggle:SetValue(false) end }
                }
            })
        else
            StartRecordingProcess()
        end
    else
        if isRecording then
            isRecording = false
            ClearConnections()  -- ⭐ disconnect ทันทีเมื่อหยุด
            UpdateStatus("Idle", "-", "-", "-", "-")
            Fluent:Notify({ Title = "Stopped", Content = "หยุดอัดมาโครแล้ว", Duration = 3 })
            
            local fName = Options.MacroProfiles.Value
            if fName ~= "None" and actionCount > 0 then
                local ok = pcall(function()
                    writefile(CONFIG.MACRO_FOLDER .. "/" .. fName .. ".json", HttpService:JSONEncode(MacroData))
                end)
                if ok then
                    Fluent:Notify({ Title = "Auto Saved", Content = "บันทึกข้อมูลลง " .. fName, Duration = 3 })
                end
            end
        end
    end
end)

PlayToggle:OnChanged(function(val)
    if val then
        if RecordToggle.Value then RecordToggle:SetValue(false) end
        local fName = Options.MacroProfiles.Value
        if fName == "None" or not isfile(CONFIG.MACRO_FOLDER .. "/" .. fName .. ".json") then
            Fluent:Notify({ Title = "Error", Content = "เลือกไฟล์ Macro ก่อน!", Duration = 3 })
            PlayToggle:SetValue(false)
            return
        end
        
        -- ⭐ Safe load JSON
        local content = nil
        local readOk = pcall(function()
            content = readfile(CONFIG.MACRO_FOLDER .. "/" .. fName .. ".json")
        end)
        if not readOk or not content then
            Fluent:Notify({ Title = "Error", Content = "อ่านไฟล์ไม่ได้!", Duration = 3 })
            PlayToggle:SetValue(false)
            return
        end
        
        local decoded, err = SafeJSONDecode(content)
        if not decoded then
            Fluent:Notify({ Title = "Error", Content = "ไฟล์ JSON เสีย: " .. tostring(err), Duration = 5 })
            PlayToggle:SetValue(false)
            return
        end
        
        MacroData = decoded
        actionCount = 0
        for k, _ in pairs(MacroData) do
            local num = tonumber(k)
            if num and num > actionCount then actionCount = num end
        end
        
        if actionCount == 0 then
            Fluent:Notify({ Title = "Error", Content = "ไฟล์ว่างเปล่า!", Duration = 3 })
            PlayToggle:SetValue(false)
            return
        end
        
        isReplaying = true
        hasPlayedThisRound = true
        PlayMacroData()
    else
        isReplaying = false
        hasPlayedThisRound = false
        currentPlaybackSession = currentPlaybackSession + 1  -- ⭐ kill running session
        UpdateStatus("Idle", "-", "-", "-", "Stopped manually")
    end
end)

Options.AutoSpeed:OnChanged(function(val)
    if val == "Off" then return end
    
    local desiredSpeed = 1
    if val == "Pause" then
        desiredSpeed = 0
    elseif string.match(val, "%d+") then
        desiredSpeed = tonumber(string.match(val, "%d+"))
    end
    
    pcall(function()
        local gameRs = ReplicatedStorage:FindFirstChild("Game")
        if gameRs and gameRs:FindFirstChild("Speed") and gameRs.Speed:FindFirstChild("Change") then
            gameRs.Speed.Change:FireServer(desiredSpeed)
        end
    end)
    
    if isRecording then
        local exactTime = tick() - recordStartTime
        RecordAction("Speed", "GameSpeed", nil, "SpeedControl", exactTime, desiredSpeed)
        Fluent:Notify({ Title = "Speed Recorded", Content = "บันทึกสปีด: " .. val, Duration = 2 })
    end
end)

-- ============================================================================== --
-- // 11. CLEANUP ON UNLOAD (ถ้า player ออก/destroy)
-- ============================================================================== --
LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        ClearConnections()
        ClearPlayInstanceMap()
        table.clear(unitNameCache)
    end
end)

dbg("SkibiMacro V36 loaded successfully!")
Fluent:Notify({
    Title = "Loaded V36",
    Content = "Flying Unit Fix - ถ้า AstroJugg ยังวางไม่ได้ ดู Settings → Diagnostic Tools",
    Duration = 5
})
