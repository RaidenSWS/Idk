-- ============================================================================== --
-- // SKIBI DEFENSE - FLUENT MACRO EDITION V25 (GOD TIER AUTOMATION)
-- // Features: Dynamic ID Target Lock, Relative Upgrading, Triple Safety Reset
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

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local Window = Fluent:CreateWindow({
    Title = "Skibi Macro V25",
    SubTitle = "Ultimate Edition",
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
-- // Helper Functions & Data
-- ============================================================================== --
local MoneyQueue = {}

local function ParseMoney(val)
    local cleanVal = string.gsub(tostring(val), ",", "")
    local num = string.match(cleanVal, "%d+")
    return num and tonumber(num) or 0
end

local function GetCurrentMoney()
    local guiMoney = nil
    pcall(function() guiMoney = ParseMoney(LocalPlayer.PlayerGui.Towers.Cash.Frame.TextLabel.Text) end)
    if guiMoney then return guiMoney end
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local moneyObj = ls and (ls:FindFirstChild("Money") or ls:FindFirstChild("Cash"))
    if moneyObj then return ParseMoney(moneyObj.Value) end
    return 0
end

local function GetCurrentWave()
    local currentWave = 1
    pcall(function()
        local numStr = string.match(LocalPlayer.PlayerGui.Data.Wave.Frame.TextLabel.Text, "%d+")
        if numStr then currentWave = tonumber(numStr) end
    end)
    return currentWave
end

-- ============================================================================== --
-- // Auto Features (Skip & Speed)
-- ============================================================================== --
task.spawn(function()
    while task.wait(1) do 
        if Options.AutoSkip and Options.AutoSkip.Value then
            pcall(function()
                local btn = LocalPlayer.PlayerGui.autoskip.auto
                if btn.BackgroundColor3.R > btn.BackgroundColor3.G then
                    if getconnections then
                        for _, conn in pairs(getconnections(btn.MouseButton1Click)) do conn:Fire() end
                        for _, conn in pairs(getconnections(btn.Activated)) do conn:Fire() end
                    elseif firesignal then
                        firesignal(btn.MouseButton1Click)
                        firesignal(btn.Activated)
                    end
                    local eventFolder = ReplicatedStorage:FindFirstChild("Event")
                    if eventFolder and eventFolder:FindFirstChild("waveSkip") then eventFolder.waveSkip:FireServer(true) end
                end
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
                if towersGui and towersGui:FindFirstChild("speedButton") then
                    local speedBtn = towersGui.speedButton
                    if speedBtn:FindFirstChild("Pause") and speedBtn.Pause.Visible then currentSpeed = 0
                    else
                        for i = 1, 5 do
                            local child = speedBtn:FindFirstChild(tostring(i).."x")
                            if child and child:IsA("GuiObject") and child.Visible then currentSpeed = i break end
                        end
                    end
                end
                
                local gameRs = ReplicatedStorage:FindFirstChild("Game")
                if currentSpeed ~= desiredSpeed and currentSpeed ~= -1 then
                    if gameRs and gameRs:FindFirstChild("Speed") and gameRs.Speed:FindFirstChild("Change") then gameRs.Speed.Change:FireServer(desiredSpeed) end
                elseif currentSpeed == -1 then
                    if gameRs and gameRs:FindFirstChild("Speed") and gameRs.Speed:FindFirstChild("Change") then gameRs.Speed.Change:FireServer(desiredSpeed) task.wait(2) end
                end
            end)
        end
    end
end)

task.spawn(function()
    while not LocalPlayer:FindFirstChild("leaderstats") do task.wait(0.5) end
    local lastMoney = GetCurrentMoney()
    local isDropping, preDropMoney = false, 0
    while task.wait(0.05) do
        local curMoney = GetCurrentMoney()
        if curMoney < lastMoney then
            if not isDropping then isDropping = true; preDropMoney = lastMoney end
        elseif curMoney == lastMoney then
            if isDropping then
                local spent = preDropMoney - curMoney
                if spent > 0 then table.insert(MoneyQueue, { amount = spent, time = tick(), claimed = false }) end
                isDropping = false
            end
        elseif curMoney > lastMoney then
            if isDropping then
                local spent = preDropMoney - lastMoney
                if spent > 0 then table.insert(MoneyQueue, { amount = spent, time = tick(), claimed = false }) end
                isDropping = false
            end
        end
        lastMoney = curMoney
    end
end)

local function GetUnitByPosition(targetName, targetPosCf, excludeMap)
    if not targetPosCf then return nil end
    local targetPos = targetPosCf.Position
    local bestUnit, closestDist = nil, 4.0 
    local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
    if targetFolder then
        for _, unit in ipairs(targetFolder:GetChildren()) do
            local isExcluded = false
            if excludeMap then for _, exId in pairs(excludeMap) do if exId == unit.Name then isExcluded = true break end end end
            if not isExcluded and (string.find(unit.Name, targetName) or string.find(unit:GetAttribute("sID") or "", targetName)) then
                local cf = unit.PrimaryPart and unit.PrimaryPart.CFrame or unit:GetModelCFrame()
                local dist = (cf.Position - targetPos).Magnitude
                if dist <= closestDist then closestDist = dist; bestUnit = unit end
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

local _G_MacroData = {}
local isRecording, isReplaying, recordStartTime, actionCount = false, false, 0, 0
local instanceToId, posToId, instanceToLevel, activeConnections = {}, {}, {}, {}

local function ClearConnections()
    for _, conn in ipairs(activeConnections) do if conn.Connected then conn:Disconnect() end end
    activeConnections = {}
end
local function WipeRecordingState()
    _G_MacroData, actionCount, instanceToId, posToId, instanceToLevel = {}, 0, {}, {}, {}
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
-- // UI Setup
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
    writefile("SkibiMacroData/" .. fName .. ".json", HttpService:JSONEncode(_G_MacroData or {}))
    Options.MacroProfiles:SetValues(GetMacroFiles())
    Options.MacroProfiles:SetValue(fName)
    Fluent:Notify({ Title = "Saved", Content = "สร้าง/บันทึกไฟล์สำเร็จ!", Duration = 3 })
end})

Tabs.Main:AddButton({ Title = "Delete selected macro", Callback = function()
    local fName = Options.MacroProfiles.Value
    if fName == "None" or fName == "" then return end
    if isfile("SkibiMacroData/" .. fName .. ".json") then
        Window:Dialog({
            Title = "ยืนยันการลบไฟล์", Content = "คุณแน่ใจหรือไม่ว่าต้องการลบไฟล์ '" .. fName .. "' ทิ้ง?",
            Buttons = {
                { Title = "ใช่ (ลบเลย)", Callback = function()
                    delfile("SkibiMacroData/" .. fName .. ".json")
                    Fluent:Notify({ Title = "Deleted", Content = "ลบไฟล์สำเร็จ!", Duration = 3 })
                    Options.MacroProfiles:SetValues(GetMacroFiles())
                    Options.MacroProfiles:SetValue(GetMacroFiles()[1]) 
                end },
                { Title = "ยกเลิก", Callback = function() end }
            }
        })
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
-- // Record Logic
-- ============================================================================== --
local function RecordAction(actionType, targetId, posCf, unitName, exactTime)
    actionCount = actionCount + 1
    local currentActionId = actionCount
    local targetLevel = 1
    if actionType == "Place" then instanceToLevel[tostring(targetId)] = 1
    elseif actionType == "Upgrade" then 
        instanceToLevel[tostring(targetId)] = (instanceToLevel[tostring(targetId)] or 1) + 1 
        targetLevel = instanceToLevel[tostring(targetId)]
    end
    
    local stepData = { type = actionType, targetID = tostring(targetId), time = exactTime, wave = GetCurrentWave(), unit = unitName, cost = 0, level = targetLevel }
    if posCf then stepData.pos = FormatCFrame(posCf) end
    _G_MacroData[tostring(currentActionId)] = stepData

    task.spawn(function()
        local exactCost = GetExactCost(unitName, actionType, targetLevel)
        if exactCost == 0 and actionType ~= "Sell" then
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
        UpdateStatus("Recording", currentActionId, actionType, unitName, "Cost: $" .. exactCost)
    end)
end

local function StartObserving()
    local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
    if not targetFolder then return end

    local addConn = targetFolder.ChildAdded:Connect(function(newTower)
        if not isRecording or not newTower:IsA("Model") then return end
        local exactTime = tick() - recordStartTime 
        task.wait(0.05) 
        local posCf = newTower.PrimaryPart and newTower.PrimaryPart.CFrame or newTower:GetModelCFrame()
        local posKey = GetPosKey(posCf.Position)
        local unitName, targetId = GetRealUnitName(newTower), newTower.Name
        
        if posToId[posKey] then
            local oldId = posToId[posKey]
            instanceToId[newTower] = oldId
            RecordAction("Upgrade", oldId, posCf, unitName, exactTime)
        else
            posToId[posKey] = targetId
            instanceToId[newTower] = targetId
            RecordAction("Place", targetId, posCf, unitName, exactTime)
        end
    end)
    
    local remConn = targetFolder.ChildRemoved:Connect(function(oldTower)
        if not isRecording then return end
        local exactTime = tick() - recordStartTime 
        local targetId = instanceToId[oldTower]
        local posCf = oldTower.PrimaryPart and oldTower.PrimaryPart.CFrame or oldTower:GetModelCFrame()
        
        if targetId then
            task.delay(0.4, function()
                local isUpgraded = false
                for inst, id in pairs(instanceToId) do if inst.Parent ~= nil and id == targetId then isUpgraded = true break end end
                if not isUpgraded then
                    RecordAction("Sell", targetId, posCf, GetRealUnitName(oldTower), exactTime)
                    posToId[GetPosKey(posCf.Position)] = nil
                end
                instanceToId[oldTower] = nil
            end)
        end
    end)
    
    table.insert(activeConnections, addConn)
    table.insert(activeConnections, remConn)
end

local function StartRecordingProcess()
    if PlayToggle.Value then PlayToggle:SetValue(false) end
    isRecording = true
    WipeRecordingState()
    UpdateStatus("Recording...", "-", "-", "-", "Start placing units")
    StartObserving()
end

-- ============================================================================== --
-- // Playback Logic (V25 God Tier)
-- ============================================================================== --
local playInstanceMap = {} 

local function PlayMacroData()
    if not isReplaying then return end
    
    task.spawn(function()
        local useTime, useWave, useMoney = Options.PlayModes.Value["Time"], Options.PlayModes.Value["Wave"], Options.PlayModes.Value["Money"]
        local customDelay = Options.StepDelay.Value
        local playStartTime = tick()
        table.clear(playInstanceMap) 

        for i = 1, actionCount do
            if not isReplaying then return end 
            local step = _G_MacroData[tostring(i)]
            if not step then continue end

            local passed = 0
            while passed < customDelay do
                if not isReplaying then return end
                UpdateStatus("Playing", i, step.type, step.unit, string.format("Buffer (%.1fs)", customDelay - passed))
                task.wait(0.1); passed = passed + 0.1
            end

            if useTime then
                while (tick() - playStartTime) < step.time do
                    if not isReplaying then return end
                    UpdateStatus("Playing", i, step.type, step.unit, string.format("Global Time (%.1fs)", step.time - (tick() - playStartTime)))
                    task.wait(0.1)
                end
            end
            if useWave and step.wave then
                while GetCurrentWave() < step.wave do
                    if not isReplaying then return end
                    UpdateStatus("Playing", i, step.type, step.unit, "Wave " .. step.wave)
                    task.wait(1)
                end
            end
            if useMoney and step.cost and step.cost > 0 then
                while GetCurrentMoney() < step.cost do
                    if not isReplaying then return end
                    UpdateStatus("Playing", i, step.type, step.unit, "Money ($" .. step.cost .. ")")
                    task.wait(0.5)
                end
            end
            
            if not isReplaying then return end 
            UpdateStatus("Playing", i, step.type, step.unit, "Executing...")

            local targetPosCf = nil
            if step.pos then
                local p = {}
                for num in string.gmatch(step.pos, "([^,]+)") do table.insert(p, tonumber(num)) end
                targetPosCf = CFrame.new(unpack(p))
            end

            if step.type == "Place" then
                local isPlaced, attempts = false, 0
                repeat
                    pcall(function() PlaceRemote:FireServer(step.unit, targetPosCf, false) end)
                    task.wait(0.5) 
                    
                    local foundUnitName = nil
                    local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
                    if targetFolder then
                        for _, unit in ipairs(targetFolder:GetChildren()) do
                            local alreadyMapped = false
                            for _, mappedId in pairs(playInstanceMap) do if mappedId == unit.Name then alreadyMapped = true break end end
                            
                            if not alreadyMapped and (string.find(unit.Name, step.unit) or string.find(unit:GetAttribute("sID") or "", step.unit)) then
                                local cf = unit.PrimaryPart and unit.PrimaryPart.CFrame or unit:GetModelCFrame()
                                if (cf.Position - targetPosCf.Position).Magnitude <= 3.5 then
                                    foundUnitName = unit.Name
                                    break
                                end
                            end
                        end
                    end
                    
                    if foundUnitName then 
                        isPlaced = true 
                        playInstanceMap[step.targetID] = foundUnitName 
                    end
                    attempts = attempts + 1
                until isPlaced or attempts >= 15 or not isReplaying

            elseif step.type == "Upgrade" then
                local attempts = 0
                local currentIdStr = playInstanceMap[step.targetID]
                
                -- Fallback: If not mapped, find it manually
                if not currentIdStr then
                    local fallbackUnit = GetUnitByPosition(step.unit, targetPosCf, playInstanceMap)
                    if fallbackUnit then currentIdStr = fallbackUnit.Name end
                end

                if currentIdStr then
                    local currentIdNum = tonumber(currentIdStr) or currentIdStr
                    
                    -- 🔥 Relative Upgrade Logic (อ่านค่าปัจจุบัน แล้วบวก 1 เพื่อเป็นเป้าหมาย)
                    local startLvl = 0
                    local tData = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("TowerData") and Workspace.Scripted.TowerData:FindFirstChild(currentIdStr)
                    if tData and tData:GetAttribute("Upgrade") then startLvl = tonumber(tData:GetAttribute("Upgrade")) or 0 end
                    local goalLvl = startLvl + 1
                    
                    pcall(function() UpgradeRemote:FireServer(currentIdNum) end)
                    task.wait(0.3)
                    
                    repeat
                        local isUpgraded = false
                        local checkData = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("TowerData") and Workspace.Scripted.TowerData:FindFirstChild(currentIdStr)
                        if checkData and checkData:GetAttribute("Upgrade") then
                            if (tonumber(checkData:GetAttribute("Upgrade")) or 0) >= goalLvl then isUpgraded = true end
                        end
                        
                        if not isUpgraded then pcall(function() UpgradeRemote:FireServer(currentIdNum) end) end
                        task.wait(0.4)
                        attempts = attempts + 1
                    until isUpgraded or attempts >= 12 or not isReplaying
                end

            elseif step.type == "Sell" then
                local attempts = 0
                local currentIdStr = playInstanceMap[step.targetID]
                if not currentIdStr then
                    local fallbackUnit = GetUnitByPosition(step.unit, targetPosCf, nil)
                    if fallbackUnit then currentIdStr = fallbackUnit.Name end
                end

                if currentIdStr then
                    local currentIdNum = tonumber(currentIdStr) or currentIdStr
                    repeat
                        pcall(function() SellRemote:FireServer(currentIdNum) end)
                        task.wait(0.4)
                        local tData = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("TowerData") and Workspace.Scripted.TowerData:FindFirstChild(currentIdStr)
                        if not tData then playInstanceMap[step.targetID] = nil break end
                        attempts = attempts + 1
                    until attempts >= 15 or not isReplaying
                end
            end
        end
        
        if isReplaying then
            UpdateStatus("Completed", "-", "-", "-", "Waiting for next match...")
            Fluent:Notify({ Title = "Complete", Content = "มาโครจบรอบนี้แล้ว! รอเริ่มรอบใหม่...", Duration = 5 })
        end
    end)
end

-- ============================================================================== --
-- // Automation Core (Triple Safety Reset)
-- ============================================================================== --
local hasPlayedThisRound = false
local lastSeenWave = 0 

local function TriggerReset(reason)
    if hasPlayedThisRound then
        hasPlayedThisRound = false
        table.clear(playInstanceMap)
    end
end

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local currentWaveNum = GetCurrentWave()
            
            -- 1. Wave Drop Check
            if currentWaveNum < lastSeenWave then TriggerReset("Wave Drop") end
            lastSeenWave = currentWaveNum

            -- 2. Tower Clear Check
            local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
            if targetFolder and #targetFolder:GetChildren() == 0 then TriggerReset("Map Cleared") end

            -- 3. GameEnded UI
            local isEndedScreenVisible = false
            local gameEndedGui = LocalPlayer.PlayerGui:FindFirstChild("GameEnded")
            if gameEndedGui and (gameEndedGui.Enabled or gameEndedGui.Visible) then
                local frame = gameEndedGui:FindFirstChild("Frame")
                local replayBtn = frame and frame:FindFirstChild("replay")
                if replayBtn and replayBtn.Visible then
                    isEndedScreenVisible = true
                    TriggerReset("Game Over UI")
                    if Options.RecordMacro and Options.RecordMacro.Value then Options.RecordMacro:SetValue(false) end
                    if Options.AutoReplay and Options.AutoReplay.Value then
                        task.wait(3) 
                        ReplicatedStorage.Event:WaitForChild("ReplayCore"):FireServer()
                    end
                end
            end

            -- 4. StartUI
            local isStartScreenVisible = false
            local startGui = LocalPlayer.PlayerGui:FindFirstChild("StartUI")
            if startGui and (startGui.Enabled or startGui.Visible) then
                local frame = startGui:FindFirstChild("Frame")
                local startBtn = frame and frame:FindFirstChild("Labels") and frame.Labels:FindFirstChild("startbutton")
                if startBtn and startBtn.Visible then
                    isStartScreenVisible = true
                    TriggerReset("Start UI")
                    if Options.AutoReady and Options.AutoReady.Value then
                        task.wait(3) 
                        ReplicatedStorage:WaitForChild("GAME_START"):WaitForChild("readyButton"):FireServer(true)
                    end
                end
            end
            
            -- 5. Play Loop Trigger
            if isReplaying and not hasPlayedThisRound and currentWaveNum >= 1 then
                if not isEndedScreenVisible and not isStartScreenVisible then
                    task.wait(4)
                    if isReplaying and not hasPlayedThisRound then
                        hasPlayedThisRound = true
                        PlayMacroData()
                    end
                end
            end
        end)
    end
end)

-- ============================================================================== --
-- // Event Handlers
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
        else StartRecordingProcess() end
    else
        if isRecording then
            isRecording = false
            UpdateStatus("Idle", "-", "-", "-", "-")
            Fluent:Notify({ Title = "Stopped", Content = "หยุดอัดมาโครแล้ว", Duration = 3 })
            local fName = Options.MacroProfiles.Value
            if fName ~= "None" and actionCount > 0 then
                 writefile("SkibiMacroData/" .. fName .. ".json", HttpService:JSONEncode(_G_MacroData or {}))
                 Fluent:Notify({ Title = "Auto Saved", Content = "บันทึกอัตโนมัติ", Duration = 3 })
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
        
        _G_MacroData = HttpService:JSONDecode(readfile("SkibiMacroData/" .. fName .. ".json"))
        actionCount = 0
        for k, _ in pairs(_G_MacroData) do
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
