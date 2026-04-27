-- ============================================================================== --
-- // SKIBI DEFENSE - FLUENT MACRO EDITION V29 (FINAL GOD MODE)
-- // Fixes: Exact Money Parsing, Pure Level Sync, 40s Patience Timeout
-- ============================================================================== --

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local EventFolder = ReplicatedStorage:WaitForChild("Event")
local PlaceRemote = EventFolder:WaitForChild("placeTower")
local UpgradeRemote = EventFolder:WaitForChild("UpgradeTower")
local SellRemote = EventFolder:WaitForChild("RemoveTower")

-- ============================================================================== --
-- // 1. ตั้งค่า Fluent UI
-- ============================================================================== --
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local Window = Fluent:CreateWindow({
    Title = "Skibi Macro V29",
    SubTitle = "Final God Mode",
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
-- // 2. Helper Functions (🔥 ระบบดึงเงินแบบ Exact Value แม่นยำ 100%)
-- ============================================================================== --
local MoneyQueue = {}

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
    -- 🔥 ดึงจาก Leaderstats ก่อน จะได้เลขเป๊ะๆ แบบไม่ย่อ (เช่น 4216718 แทนที่จะเป็น 4.2M)
    local exactMoney = nil
    pcall(function()
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        local moneyObj = ls and (ls:FindFirstChild("Money") or ls:FindFirstChild("Cash"))
        if moneyObj then
            if type(moneyObj.Value) == "number" then exactMoney = math.floor(moneyObj.Value)
            else exactMoney = ParseMoney(tostring(moneyObj.Value)) end
        end
    end)
    if exactMoney then return exactMoney end
    
    -- สำรองดึงจาก GUI
    local guiMoney = 0
    pcall(function() guiMoney = ParseMoney(LocalPlayer.PlayerGui.Towers.Cash.Frame.TextLabel.Text) end)
    return guiMoney
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

local function GetUnitByPosition(targetName, targetPosCf)
    if not targetPosCf or not targetName then return nil end
    local targetPos = targetPosCf.Position
    local bestUnit = nil
    local closestDist = 35 -- 🔥 เพิ่มระยะให้ไททันตัวใหญ่แบบสุดๆ (35 Block)
    local searchName = CleanStr(targetName)

    local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
    if targetFolder then
        for _, unit in ipairs(targetFolder:GetChildren()) do
            local uName = CleanStr(unit.Name)
            local sId = CleanStr(unit:GetAttribute("sID") or "")
            
            if string.find(uName, searchName, 1, true) or string.find(sId, searchName, 1, true) then
                local cf = unit.PrimaryPart and unit.PrimaryPart.CFrame or unit:GetModelCFrame()
                if cf then
                    local dist = (cf.Position - targetPos).Magnitude
                    if dist <= closestDist then
                        closestDist = dist
                        bestUnit = unit
                    end
                end
            end
        end
    end
    return bestUnit
end

local function GetPosKey(pos) return string.format("%.1f_%.1f", pos.X, pos.Z) end
local function FormatCFrame(cf)
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:components()
    return string.format("%f, %f, %f, %d, %d, %d, %d, %d, %d, %d, %d, %d", x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
local function GetRealUnitName(towerModel)
    local sID = towerModel:GetAttribute("sID")
    if sID and sID ~= "" then return sID end
    return string.gsub(string.gsub(towerModel.Name, " Lvl?%.?%s*%d+", ""), " %(Lv.*%)", "")
end

-- ============================================================================== --
-- // 🔥 ระบบ Auto Skip & Speed
-- ============================================================================== --
task.spawn(function()
    while task.wait(0.5) do 
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
                local eventFolder = ReplicatedStorage:FindFirstChild("Event")
                if eventFolder and eventFolder:FindFirstChild("waveSkip") then eventFolder.waveSkip:FireServer(true) end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait(1) do 
        if Options.AutoSpeed and Options.AutoSpeed.Value ~= "Off" then
            pcall(function()
                local desiredSpeed = 1
                local val = Options.AutoSpeed.Value
                if val == "Pause" then desiredSpeed = 0 elseif string.match(val, "%d+") then desiredSpeed = tonumber(string.match(val, "%d+")) end
                
                local currentSpeed = -1
                local towersGui = LocalPlayer.PlayerGui:FindFirstChild("Towers")
                if towersGui then
                    local speedBtn = towersGui:FindFirstChild("speedButton")
                    if speedBtn then
                        if speedBtn:FindFirstChild("Pause") and speedBtn.Pause.Visible then currentSpeed = 0
                        else
                            for i = 1, 5 do
                                local child = speedBtn:FindFirstChild(tostring(i).."x")
                                if child and child:IsA("GuiObject") and child.Visible then currentSpeed = i break end
                            end
                        end
                    end
                end
                
                local gameRs = ReplicatedStorage:FindFirstChild("Game")
                if currentSpeed ~= desiredSpeed and currentSpeed ~= -1 then
                    if gameRs and gameRs:FindFirstChild("Speed") and gameRs.Speed:FindFirstChild("Change") then gameRs.Speed.Change:FireServer(desiredSpeed) end
                elseif currentSpeed == -1 then
                    if gameRs and gameRs:FindFirstChild("Speed") and gameRs.Speed:FindFirstChild("Change") then
                        gameRs.Speed.Change:FireServer(desiredSpeed)
                        task.wait(2)
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while not LocalPlayer:FindFirstChild("leaderstats") do task.wait(0.5) end
    local lastMoney = GetCurrentMoney()
    local isDropping = false
    local preDropMoney = 0
    
    while task.wait(0.05) do
        local curMoney = GetCurrentMoney()
        if curMoney < lastMoney then
            if not isDropping then isDropping = true; preDropMoney = lastMoney end
        elseif curMoney == lastMoney then
            if isDropping then
                local totalSpent = preDropMoney - curMoney
                if totalSpent > 0 then table.insert(MoneyQueue, { amount = totalSpent, time = tick(), claimed = false }) end
                isDropping = false
            end
        elseif curMoney > lastMoney then
            if isDropping then
                local totalSpent = preDropMoney - lastMoney
                if totalSpent > 0 then table.insert(MoneyQueue, { amount = totalSpent, time = tick(), claimed = false }) end
                isDropping = false
            end
        end
        lastMoney = curMoney
    end
end)

-- ============================================================================== --
-- // 3. ตัวแปรเก็บสถานะ Macro
-- ============================================================================== --
_G.MacroData = {}
local isRecording = false
local isReplaying = false
local recordStartTime = 0
local actionCount = 0
local instanceToId = {}
local posToId = {}
local activeConnections = {}

local function ClearConnections()
    for _, conn in ipairs(activeConnections) do if conn.Connected then conn:Disconnect() end end
    activeConnections = {}
end

local function WipeRecordingState()
    _G.MacroData = {}
    actionCount = 0
    instanceToId = {}
    posToId = {}
    for k in pairs(MoneyQueue) do MoneyQueue[k] = nil end 
    recordStartTime = tick()
    ClearConnections()
end

local function GetExactCost(unitName, actionType, upgradeLevel)
    if actionType == "Sell" then return 0 end
    local cost = 0
    pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local towerData = rs:FindFirstChild("TowerData") and rs.TowerData:FindFirstChild("Units")
        if towerData then
            local module = towerData:FindFirstChild(unitName) or towerData:FindFirstChild(unitName.."Unit")
            if module then
                local data = require(module)
                if actionType == "Place" then cost = data.Price or data.Cost or data.BasePrice or data.DeployCost or 0
                elseif actionType == "Upgrade" and data.Upgrades then
                    local upg = data.Upgrades[upgradeLevel]
                    if upg then cost = upg.Price or upg.Cost or upg.UpgradeCost or 0 end
                end
            end
        end
    end)
    return cost
end

-- ============================================================================== --
-- // 5. สร้าง UI หน้า Main 
-- ============================================================================== --
local StatusPara = Tabs.Main:AddParagraph({ Title = "Macro Status: None", Content = "Action: -\nType: -\nUnit: -\nWaiting for: -" })
local function UpdateStatus(status, action, actType, unit, waiting)
    StatusPara:SetTitle("Macro Status: " .. (status or "None"))
    StatusPara:SetDesc(string.format("Action: %s\nType: %s\nUnit: %s\nWaiting for: %s", tostring(action or "-"), tostring(actType or "-"), tostring(unit or "-"), tostring(waiting or "-")))
end

Tabs.Main:AddSection("File & Profiles")
if not isfolder("SkibiMacroData") then makefolder("SkibiMacroData") end

local function GetMacroFiles()
    local files = {}
    for _, v in ipairs(listfiles("SkibiMacroData")) do table.insert(files, string.match(v, "([^/\\]+)%.json$") or v) end
    if #files == 0 then table.insert(files, "None") end
    return files
end

local ProfileDrop = Tabs.Main:AddDropdown("MacroProfiles", { Title = "Macro Profiles", Values = GetMacroFiles(), Default = 1, Multi = false })
local NewProfileInput = Tabs.Main:AddInput("NewProfileName", { Title = "New macro profile", Default = "", Placeholder = "พิมพ์ชื่อไฟล์ใหม่ที่นี่..." })

Tabs.Main:AddButton({ Title = "Create new macro (Save)", Callback = function()
    local fName = Options.NewProfileName.Value
    if fName == "" then Fluent:Notify({ Title = "Error", Content = "พิมพ์ชื่อไฟล์ก่อนเซฟ!", Duration = 3 }) return end
    writefile("SkibiMacroData/" .. fName .. ".json", HttpService:JSONEncode(_G.MacroData or {}))
    Options.MacroProfiles:SetValues(GetMacroFiles())
    Options.MacroProfiles:SetValue(fName)
    Fluent:Notify({ Title = "Saved", Content = "สร้าง/บันทึกไฟล์ " .. fName .. ".json สำเร็จ!", Duration = 3 })
end})

Tabs.Main:AddButton({ Title = "Delete selected macro", Callback = function()
    local fName = Options.MacroProfiles.Value
    if fName == "None" or fName == "" then return end
    if isfile("SkibiMacroData/" .. fName .. ".json") then
        delfile("SkibiMacroData/" .. fName .. ".json")
        Fluent:Notify({ Title = "Deleted", Content = "ลบไฟล์สำเร็จ!", Duration = 3 })
        local files = GetMacroFiles()
        Options.MacroProfiles:SetValues(files)
        Options.MacroProfiles:SetValue(files[1]) 
    end
end})

Tabs.Main:AddSection("Macro Controls")
local AutoSkipToggle = Tabs.Main:AddToggle("AutoSkip", {Title = "Auto Skip Wave", Default = false })
local AutoReplayToggle = Tabs.Main:AddToggle("AutoReplay", {Title = "Auto Replay", Default = false })
local AutoReadyToggle = Tabs.Main:AddToggle("AutoReady", {Title = "Auto Ready", Default = false })
local RecordToggle = Tabs.Main:AddToggle("RecordMacro", {Title = "Record Macro", Default = false })
local PlayToggle = Tabs.Main:AddToggle("PlayMacro", {Title = "Play Macro", Default = false })
local AutoSpeedDrop = Tabs.Main:AddDropdown("AutoSpeed", { Title = "Auto Speed Lock", Values = {"Off", "Pause", "1x", "2x", "3x", "4x", "5x"}, Default = 1 })
Tabs.Main:AddSlider("StepDelay", { Title = "Step Delay", Default = 0.2, Min = 0.1, Max = 5, Rounding = 1 })
local PlayModes = Tabs.Main:AddDropdown("PlayModes", { Title = "Play Modes", Values = {"Time", "Wave", "Money"}, Multi = true, Default = {"Wave", "Money"} })

-- ============================================================================== --
-- // 6. ลอจิกการอัด (Record) 🔥 ดักจับ Network สปีดเกม
-- ============================================================================== --
local cachedPos = {}
local cachedName = {}
local lastUpgRecord = {}
local lastRecordedSpeed = -1 -- 🔥 เพิ่มตัวแปรเก็บสปีด

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
    _G.MacroData[tostring(currentActionId)] = stepData

    task.spawn(function()
        local exactCost = GetExactCost(unitName, actionType, specificLevel or 1)
        if exactCost == 0 and actionType ~= "Sell" and actionType ~= "Speed" then -- 🔥 ข้ามเช็คเงินถ้าปรับสปีด
            local passTime = 0
            while passTime < 1.5 do
                for _, drop in ipairs(MoneyQueue) do
                    if not drop.claimed and (tick() - drop.time) <= 3 then exactCost = drop.amount; drop.claimed = true; break end
                end
                if exactCost > 0 then break end
                task.wait(0.1); passTime = passTime + 0.1
            end
        end
        stepData.cost = exactCost
        
        local displayWait = "Cost: $" .. exactCost .. " | Lvl: " .. (specificLevel or 1)
        if actionType == "Speed" then displayWait = "Speed set to " .. (specificLevel == 0 and "Pause" or specificLevel.."x") end
        UpdateStatus("Recording", currentActionId, actionType, unitName, displayWait)
    end)
end

-- 🔥 วิชาสายแฮกเกอร์: ดักจับสัญญาณเปลี่ยนสปีดที่ถูกส่งไปเซิร์ฟเวอร์โดยตรง
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    
    if isRecording and method == "FireServer" then
        if self.Name == "Change" and self.Parent and self.Parent.Name == "Speed" then
            local args = {...}
            local speedVal = tonumber(args[1]) or 0
            
            task.spawn(function()
                if lastRecordedSpeed ~= speedVal then
                    lastRecordedSpeed = speedVal
                    local exactTime = tick() - recordStartTime
                    RecordAction("Speed", "GameSpeed", nil, "SpeedControl", exactTime, speedVal)
                end
            end)
        end
    end
    return oldNamecall(self, ...)
end))

local function StartObserving()
    local towerDataFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("TowerData")
    local towersFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
    if not towerDataFolder or not towersFolder then return end

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
                    posCf = unitModel.PrimaryPart and unitModel.PrimaryPart.CFrame or unitModel:GetModelCFrame()
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
        
        if unitModel then
            local posCf = unitModel.PrimaryPart and unitModel.PrimaryPart.CFrame or unitModel:GetModelCFrame()
            local unitName = GetRealUnitName(unitModel)
            
            cachedPos[targetId] = posCf
            cachedName[targetId] = unitName
            lastUpgRecord[targetId] = 1 
            
            RecordAction("Place", targetId, posCf, unitName, exactTime, 1)
            hookTowerData(tDataObj)
        end
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
    Fluent:Notify({ Title = "Recording Started", Content = "เริ่มอัดมาโคร! (ระบบดักสปีดทำงาน)", Duration = 3 })
    StartObserving()
end

-- ============================================================================== --
-- // 7. ลอจิกการเล่น (Play) 🔥 รองรับการเล่นสปีด
-- ============================================================================== --
local playInstanceMap = {} 
local currentPlaybackSession = 0 

local function PlayMacroData()
    if not isReplaying then return end
    
    currentPlaybackSession = currentPlaybackSession + 1
    local mySession = currentPlaybackSession 
    
    task.spawn(function()
        local useTime = Options.PlayModes.Value["Time"]
        local useWave = Options.PlayModes.Value["Wave"]
        local useMoney = Options.PlayModes.Value["Money"]
        local customDelay = Options.StepDelay.Value
        local playStartTime = tick()
        table.clear(playInstanceMap) 

        for i = 1, actionCount do
            if not isReplaying or mySession ~= currentPlaybackSession then return end 
            
            local step = _G.MacroData[tostring(i)]
            if not step then continue end

            local passed = 0
            while passed < customDelay do
                if not isReplaying or mySession ~= currentPlaybackSession then return end
                UpdateStatus("Playing", i, step.type, step.unit, string.format("Buffer (%.1fs)", customDelay - passed))
                task.wait(0.1); passed = passed + 0.1
            end

            if useTime then
                while (tick() - playStartTime) < step.time do
                    if not isReplaying or mySession ~= currentPlaybackSession then return end
                    UpdateStatus("Playing", i, step.type, step.unit, string.format("Global Time (%.1fs)", step.time - (tick() - playStartTime)))
                    task.wait(0.1)
                end
            end
            if useWave and step.wave then
                while GetCurrentWave() < step.wave do
                    if not isReplaying or mySession ~= currentPlaybackSession then return end
                    UpdateStatus("Playing", i, step.type, step.unit, "Wave " .. step.wave)
                    task.wait(1)
                end
            end
            
            local requiredMoney = ParseMoney(step.cost)
            if useMoney and requiredMoney > 0 and step.type ~= "Speed" then -- 🔥 สปีดไม่ต้องรอเงิน
                while GetCurrentMoney() < requiredMoney do
                    if not isReplaying or mySession ~= currentPlaybackSession then return end
                    UpdateStatus("Playing", i, step.type, step.unit, "Money ($" .. requiredMoney .. ")")
                    task.wait(0.5)
                end
            end
            
            if not isReplaying or mySession ~= currentPlaybackSession then return end 
            UpdateStatus("Playing", i, step.type, step.unit, "Executing...")

            local targetPosCf = nil
            if step.pos then
                local p = {}
                for num in string.gmatch(step.pos, "([^,]+)") do table.insert(p, tonumber(num)) end
                targetPosCf = CFrame.new(unpack(p))
            end

            -- 🔥 ระบบรันคำสั่งสปีดเกม
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
                repeat
                    pcall(function() PlaceRemote:FireServer(step.unit, targetPosCf, false) end)
                    task.wait(0.5) 
                    
                    local foundUnit = nil
                    local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
                    if targetFolder then
                        local searchNameClean = CleanStr(step.unit)
                        for _, unit in ipairs(targetFolder:GetChildren()) do
                            local alreadyOwned = false
                            for _, v in pairs(playInstanceMap) do if v == unit then alreadyOwned = true break end end
                            
                            if not alreadyOwned then
                                local uNameClean = CleanStr(unit.Name)
                                local sIdClean = CleanStr(unit:GetAttribute("sID") or "")
                                if string.find(uNameClean, searchNameClean, 1, true) or string.find(sIdClean, searchNameClean, 1, true) then
                                    local cf = unit.PrimaryPart and unit.PrimaryPart.CFrame or unit:GetModelCFrame()
                                    if cf and (cf.Position - targetPosCf.Position).Magnitude <= 35 then
                                        foundUnit = unit
                                        break
                                    end
                                end
                            end
                        end
                    end
                    
                    if not foundUnit then foundUnit = GetUnitByPosition(step.unit, targetPosCf) end
                    
                    if foundUnit then 
                        isPlaced = true 
                        playInstanceMap[step.targetID] = foundUnit 
                    end
                    attempts = attempts + 1
                until isPlaced or attempts >= 100 or not isReplaying or mySession ~= currentPlaybackSession

            elseif step.type == "Upgrade" then
                local attempts = 0
                local targetLvl = tonumber(step.level) or 1 
                
                repeat
                    local isUpgraded = false
                    local unitToUpgrade = playInstanceMap[step.targetID]
                    
                    if not unitToUpgrade or not unitToUpgrade.Parent then
                        unitToUpgrade = GetUnitByPosition(step.unit, targetPosCf)
                        if unitToUpgrade then playInstanceMap[step.targetID] = unitToUpgrade end
                    end
                    
                    if unitToUpgrade then
                        local currentIdStr = tostring(unitToUpgrade.Name)
                        local currentIdNum = tonumber(currentIdStr) or currentIdStr
                        
                        pcall(function() UpgradeRemote:FireServer(currentIdNum) end)
                        
                        local tData = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("TowerData") and Workspace.Scripted.TowerData:FindFirstChild(currentIdStr)
                        
                        if tData then
                            local currentUpgrades = tonumber(tData:GetAttribute("Upgrade")) or 0
                            if currentUpgrades >= targetLvl then
                                isUpgraded = true
                            end
                        end
                    end
                    
                    if not isUpgraded and attempts >= 100 then
                        isUpgraded = true 
                    end
                    
                    if not isUpgraded then task.wait(0.4) end
                    attempts = attempts + 1
                until isUpgraded or not isReplaying or mySession ~= currentPlaybackSession

            elseif step.type == "Sell" then
                local attempts = 0
                repeat
                    local isSold = false
                    local unitToSell = playInstanceMap[step.targetID]
                    if not unitToSell or not unitToSell.Parent then unitToSell = GetUnitByPosition(step.unit, targetPosCf) end
                    
                    if unitToSell then
                        local currentIdStr = tostring(unitToSell.Name)
                        local currentIdNum = tonumber(currentIdStr) or currentIdStr
                        pcall(function() SellRemote:FireServer(currentIdNum) end)
                        task.wait(0.4)
                        if not unitToSell.Parent then 
                            playInstanceMap[step.targetID] = nil 
                            isSold = true
                        end
                    end
                    
                    if not isSold and attempts >= 100 then isSold = true end
                    if not isSold then task.wait(0.4) end
                    attempts = attempts + 1
                until isSold or not isReplaying or mySession ~= currentPlaybackSession
            end
        end
        
        if isReplaying and mySession == currentPlaybackSession then
            UpdateStatus("Completed", "-", "-", "-", "Waiting for next match...")
            Fluent:Notify({ Title = "Complete", Content = "มาโครจบรอบนี้แล้ว! รอเริ่มรอบใหม่...", Duration = 5 })
        end
    end)
end

local function IsTrulyVisible(gui)
    if not gui then return false end
    if not gui.Visible then return false end
    local sg = gui:FindFirstAncestorWhichIsA("ScreenGui")
    if sg and not sg.Enabled then return false end
    
    local pos = gui.AbsolutePosition
    local size = gui.AbsoluteSize
    local view = Workspace.CurrentCamera.ViewportSize
    
    if size.X < 10 or size.Y < 10 then return false end
    if pos.Y >= view.Y - 10 or pos.X >= view.X - 10 then return false end
    if pos.Y + size.Y <= 0 or pos.X + size.X <= 0 then return false end
    
    return true
end

-- ============================================================================== --
-- // 🔥 ระบบ Automation Core ( Wave Trigger & UI Sync )
-- ============================================================================== --
local hasPlayedThisRound = false
local lastSeenWave = 0

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local currentWaveNum = GetCurrentWave()
            
            if currentWaveNum < lastSeenWave then
                hasPlayedThisRound = false 
                table.clear(playInstanceMap) 
                currentPlaybackSession = currentPlaybackSession + 1 
            end
            lastSeenWave = currentWaveNum

            local endGui = LocalPlayer.PlayerGui:FindFirstChild("GameEnded")
            local isEndedVisible = false
            if endGui then
                local frame = endGui:FindFirstChild("Frame")
                local replayBtn = frame and frame:FindFirstChild("replay")
                
                if IsTrulyVisible(frame) and IsTrulyVisible(replayBtn) then
                    isEndedVisible = true
                    hasPlayedThisRound = false 
                    table.clear(playInstanceMap)
                    currentPlaybackSession = currentPlaybackSession + 1 
                    
                    if Options.RecordMacro and Options.RecordMacro.Value then
                        Options.RecordMacro:SetValue(false)
                    end
                    if Options.AutoReplay and Options.AutoReplay.Value then
                        task.wait(3) 
                        ReplicatedStorage.Event:WaitForChild("ReplayCore"):FireServer()
                    end
                end
            end

            local startGui = LocalPlayer.PlayerGui:FindFirstChild("StartUI")
            local isStartVisible = false
            if startGui then
                local frame = startGui:FindFirstChild("Frame")
                local startBtn = frame and frame:FindFirstChild("Labels") and frame.Labels:FindFirstChild("startbutton")
                
                if IsTrulyVisible(frame) and IsTrulyVisible(startBtn) then
                    isStartVisible = true
                    hasPlayedThisRound = false 
                    table.clear(playInstanceMap)
                    currentPlaybackSession = currentPlaybackSession + 1 
                    
                    if Options.AutoReady and Options.AutoReady.Value then
                        task.wait(3) 
                        ReplicatedStorage:WaitForChild("GAME_START"):WaitForChild("readyButton"):FireServer(true)
                    end
                end
            end
            
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
-- // 8. เชื่อมปุ่ม (Event Handlers)
-- ============================================================================== --
RecordToggle:OnChanged(function(val)
    if val then
        local fName = Options.MacroProfiles.Value
        local hasData = false

        if fName ~= "None" and isfile("SkibiMacroData/" .. fName .. ".json") then
            local content = readfile("SkibiMacroData/" .. fName .. ".json")
            if content and content ~= "" then
                pcall(function()
                    local decoded = HttpService:JSONDecode(content)
                    for _ in pairs(decoded) do hasData = true; break end
                end)
            end
        end

        if hasData then
            Window:Dialog({
                Title = "พบข้อมูลมาโครเดิม",
                Content = "ไฟล์ '" .. fName .. "' มีข้อมูลอยู่แล้ว คุณต้องการอัดทับ (Overwrite) ข้อมูลเดิมหรือไม่?",
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
            UpdateStatus("Idle", "-", "-", "-", "-")
            Fluent:Notify({ Title = "Stopped", Content = "หยุดอัดมาโครแล้ว", Duration = 3 })
            
            local fName = Options.MacroProfiles.Value
            if fName ~= "None" and actionCount > 0 then
                 writefile("SkibiMacroData/" .. fName .. ".json", HttpService:JSONEncode(_G.MacroData or {}))
                 Fluent:Notify({ Title = "Auto Saved", Content = "บันทึกข้อมูลลง " .. fName .. " อัตโนมัติ", Duration = 3 })
            end
        end
    end
end)

PlayToggle:OnChanged(function(val)
    if val then
        if RecordToggle.Value then RecordToggle:SetValue(false) end
        local fName = Options.MacroProfiles.Value
        if fName == "None" or not isfile("SkibiMacroData/" .. fName .. ".json") then
            Fluent:Notify({ Title = "Error", Content = "เลือกไฟล์ Macro ก่อน!", Duration = 3 })
            PlayToggle:SetValue(false)
            return
        end
        
        _G.MacroData = HttpService:JSONDecode(readfile("SkibiMacroData/" .. fName .. ".json"))
        actionCount = 0
        for k, _ in pairs(_G.MacroData) do
            local num = tonumber(k)
            if num and num > actionCount then actionCount = num end
        end
        
        isReplaying = true
        hasPlayedThisRound = true 
        PlayMacroData()
    else
        isReplaying = false
        hasPlayedThisRound = false
        UpdateStatus("Idle", "-", "-", "-", "Stopped manually")
    end
end)
