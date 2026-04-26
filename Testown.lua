-- ============================================================================== --
-- // SKIBI DEFENSE - FLUENT MACRO EDITION V24 (CLASSIC STABLE + SMART TARGET)
-- // Logic: Classic Coordinate Fallback + Leaderstats Loop + No Auto-Close
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
    Title = "Skibi Macro V24",
    SubTitle = "Classic Stable Edition",
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
-- // 2. Helper Functions
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
-- // 🔥 ระบบ Auto Skip & Speed
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

-- 🔥 ไม้ตายแบบ Testown (10): ระบบค้นหาด้วยพิกัด ชัวร์ 100% ไม่มีหลง
local function GetUnitByPosition(targetName, targetPosCf)
    if not targetPosCf then return nil end
    local targetPos = targetPosCf.Position
    local bestUnit = nil
    local closestDist = 5 

    local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
    if targetFolder then
        for _, unit in ipairs(targetFolder:GetChildren()) do
            if string.find(unit.Name, targetName) or string.find(unit:GetAttribute("sID") or "", targetName) then
                local cf = unit.PrimaryPart and unit.PrimaryPart.CFrame or unit:GetModelCFrame()
                local dist = (cf.Position - targetPos).Magnitude
                if dist <= closestDist then
                    closestDist = dist
                    bestUnit = unit
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
-- // 3. ตัวแปรเก็บสถานะ Macro
-- ============================================================================== --
_G.MacroData = {}
local isRecording = false
local isReplaying = false
local recordStartTime = 0
local actionCount = 0
local instanceToId = {}
local posToId = {}
local instanceToLevel = {}
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
    instanceToLevel = {}
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
-- // 6. ลอจิกการอัด (Record)
-- ============================================================================== --
local function RecordAction(actionType, targetId, posCf, unitName, exactTime)
    actionCount = actionCount + 1
    local currentActionId = actionCount
    local currentWave = GetCurrentWave()
    
    -- นัล Level ที่ 1 เสมอ แก้บั๊ก 0
    local targetLevel = 1
    if actionType == "Place" then 
        instanceToLevel[tostring(targetId)] = 1
    elseif actionType == "Upgrade" then 
        instanceToLevel[tostring(targetId)] = (instanceToLevel[tostring(targetId)] or 1) + 1 
        targetLevel = instanceToLevel[tostring(targetId)]
    end
    
    local stepData = { type = actionType, targetID = tostring(targetId), time = exactTime, wave = currentWave, unit = unitName, cost = 0, level = targetLevel }
    if posCf then stepData.pos = FormatCFrame(posCf) end
    _G.MacroData[tostring(currentActionId)] = stepData

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
        local unitName = GetRealUnitName(newTower)
        local targetId = newTower.Name
        
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
    Fluent:Notify({ Title = "Recording Started", Content = "เริ่มอัดมาโคร! (ปลอดภัย 100%)", Duration = 3 })
    StartObserving()
end

-- ============================================================================== --
-- // 7. ลอจิกการเล่น (Play) แบบ Classic + Fallback
-- ============================================================================== --
local playInstanceMap = {} 

local function PlayMacroData()
    if not isReplaying then return end
    
    task.spawn(function()
        local useTime = Options.PlayModes.Value["Time"]
        local useWave = Options.PlayModes.Value["Wave"]
        local useMoney = Options.PlayModes.Value["Money"]
        local customDelay = Options.StepDelay.Value
        local playStartTime = tick()
        table.clear(playInstanceMap) 

        for i = 1, actionCount do
            if not isReplaying then return end 
            local step = _G.MacroData[tostring(i)]
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
                local isPlaced = false
                local attempts = 0
                repeat
                    pcall(function() PlaceRemote:FireServer(step.unit, targetPosCf, false) end)
                    task.wait(0.5) 
                    
                    local foundUnit = nil
                    local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
                    if targetFolder then
                        for _, unit in ipairs(targetFolder:GetChildren()) do
                            local alreadyOwned = false
                            for _, v in pairs(playInstanceMap) do if v == unit then alreadyOwned = true break end end
                            
                            if not alreadyOwned and (string.find(unit.Name, step.unit) or string.find(unit:GetAttribute("sID") or "", step.unit)) then
                                local cf = unit.PrimaryPart and unit.PrimaryPart.CFrame or unit:GetModelCFrame()
                                if (cf.Position - targetPosCf.Position).Magnitude <= 3.5 then
                                    foundUnit = unit
                                    break
                                end
                            end
                        end
                    end
                    
                    -- 🔥 Fallback: ถ้ายังหาตัวใหม่ไม่เจอ ให้ใช้ระบบพิกัดคลาสสิกของ Testown 10 ชัวร์สุด
                    if not foundUnit then foundUnit = GetUnitByPosition(step.unit, targetPosCf) end
                    
                    if foundUnit then 
                        isPlaced = true 
                        playInstanceMap[step.targetID] = foundUnit 
                    end
                    attempts = attempts + 1
                until isPlaced or attempts >= 15 or not isReplaying

            elseif step.type == "Upgrade" then
                local attempts = 0
                local targetLvl = step.level or 2
                if targetLvl <= 1 then targetLvl = 2 end 
                
                repeat
                    local isUpgraded = false
                    local unitToUpgrade = playInstanceMap[step.targetID]
                    
                    -- 🔥 ระบบคลาสสิก: ถ้าลืมเป้าหมาย ให้ค้นหาด้วยพิกัดตำแหน่งเหมือน Testown 10 รับรองไม่พลาด
                    if not unitToUpgrade or not unitToUpgrade.Parent then
                        unitToUpgrade = GetUnitByPosition(step.unit, targetPosCf)
                        if unitToUpgrade then playInstanceMap[step.targetID] = unitToUpgrade end
                    end
                    
                    if unitToUpgrade then
                        local currentIdStr = tostring(unitToUpgrade.Name)
                        local currentIdNum = tonumber(currentIdStr) or currentIdStr
                        
                        -- บังคับยิง 1 รอบกันเหนียว
                        pcall(function() UpgradeRemote:FireServer(currentIdNum) end)
                        
                        local tData = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("TowerData") and Workspace.Scripted.TowerData:FindFirstChild(currentIdStr)
                        if tData and tData:GetAttribute("Upgrade") and tonumber(tData:GetAttribute("Upgrade")) >= targetLvl then
                            isUpgraded = true
                        end
                    else
                        isUpgraded = true -- ถ้ายูนิตโดนลบหรือหายไป ข้ามเลยจะได้ไม่บั๊กค้าง
                    end
                    
                    task.wait(0.4)
                    attempts = attempts + 1
                until isUpgraded or attempts >= 12 or not isReplaying

            elseif step.type == "Sell" then
                local attempts = 0
                repeat
                    local unitToSell = playInstanceMap[step.targetID]
                    if not unitToSell or not unitToSell.Parent then unitToSell = GetUnitByPosition(step.unit, targetPosCf) end
                    
                    if unitToSell then
                        local currentIdStr = tostring(unitToSell.Name)
                        local currentIdNum = tonumber(currentIdStr) or currentIdStr
                        pcall(function() SellRemote:FireServer(currentIdNum) end)
                        task.wait(0.4)
                        if not unitToSell.Parent then playInstanceMap[step.targetID] = nil break end
                    else break end
                    attempts = attempts + 1
                until attempts >= 15 or not isReplaying
            end
        end
        
        if isReplaying then
            UpdateStatus("Completed", "-", "-", "-", "Waiting for next match...")
            Fluent:Notify({ Title = "Complete", Content = "มาโครจบรอบนี้แล้ว! รอเริ่มรอบใหม่...", Duration = 5 })
        end
    end)
end

local hasPlayedThisRound = false
local currentLeaderstats = nil -- ตัวเก็บความจำ Leaderstats

-- 🔥 ฟังก์ชันตาทิพย์ของจริง: ตรวจสอบพิกัดว่า UI อยู่ตรงกลางจอให้เห็นจริงๆ ไม่ใช่ซ่อนตกขอบจอ
local function IsTrulyVisible(gui)
    if not gui then return false end
    if not gui.Visible then return false end
    local sg = gui:FindFirstAncestorWhichIsA("ScreenGui")
    if sg and not sg.Enabled then return false end
    
    local pos = gui.AbsolutePosition
    local size = gui.AbsoluteSize
    local view = Workspace.CurrentCamera.ViewportSize
    
    -- 1. ถ้าขนาด UI เล็กกว่า 10 พิกเซล = เกมซ่อนไว้
    if size.X < 10 or size.Y < 10 then return false end
    -- 2. ถ้าตำแหน่ง UI ทะลุความสูง/ความกว้างของจอไปแล้ว = ตกขอบจอ
    if pos.Y >= view.Y - 10 or pos.X >= view.X - 10 then return false end
    -- 3. ถ้าตำแหน่ง UI ติดลบจนหายไปด้านบนซ้าย = ตกขอบจอ
    if pos.Y + size.Y <= 0 or pos.X + size.X <= 0 then return false end
    
    return true
end

-- ============================================================================== --
-- // 🔥 ระบบ Automation Core ( Leaderstats Trigger + Smart Auto Save )
-- ============================================================================== --
task.spawn(function()
    while task.wait(1) do
        pcall(function()
            -- 🎯 1. ระบบจับ Leaderstats (ความแม่นยำ 100% ในการเริ่มด่านใหม่)
            local currentLsInGame = LocalPlayer:FindFirstChild("leaderstats")
            if currentLsInGame and currentLsInGame ~= currentLeaderstats then
                currentLeaderstats = currentLsInGame
                hasPlayedThisRound = false 
                table.clear(playInstanceMap) 
                
                if isReplaying then
                    task.wait(4) -- หน่วงให้แมพโหลด
                    hasPlayedThisRound = true
                    PlayMacroData()
                end
            elseif not currentLsInGame then
                currentLeaderstats = nil
            end

            -- 🎯 2. ตรวจจับหน้าจอตอนจบเกม (Auto Stop Record & Replay)
            local endGui = LocalPlayer.PlayerGui:FindFirstChild("GameEnded")
            if endGui then
                local frame = endGui:FindFirstChild("Frame")
                local replayBtn = frame and frame:FindFirstChild("replay")
                
                -- 🔥 ใช้ฟังก์ชันคำนวณพิกัด: กล่องต้องโผล่มากลางจอจริงๆ ถึงจะทำงาน
                if IsTrulyVisible(frame) and IsTrulyVisible(replayBtn) then
                    
                    -- หยุด Record และเซฟไฟล์อัตโนมัติเมื่อจบเกม
                    if Options.RecordMacro and Options.RecordMacro.Value then
                        Options.RecordMacro:SetValue(false)
                    end
                    
                    if Options.AutoReplay and Options.AutoReplay.Value then
                        task.wait(3) 
                        ReplicatedStorage.Event:WaitForChild("ReplayCore"):FireServer()
                    end
                end
            end

            -- 🎯 3. ตรวจจับหน้าจอตอนเริ่มเกม (Auto Ready)
            local startGui = LocalPlayer.PlayerGui:FindFirstChild("StartUI")
            if startGui then
                local frame = startGui:FindFirstChild("Frame")
                local startBtn = frame and frame:FindFirstChild("Labels") and frame.Labels:FindFirstChild("startbutton")
                
                -- 🔥 ใช้ฟังก์ชันคำนวณพิกัด: กล่อง Ready ต้องโผล่มากลางจอจริงๆ
                if IsTrulyVisible(frame) and IsTrulyVisible(startBtn) then
                    if Options.AutoReady and Options.AutoReady.Value then
                        task.wait(3) 
                        ReplicatedStorage:WaitForChild("GAME_START"):WaitForChild("readyButton"):FireServer(true)
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
