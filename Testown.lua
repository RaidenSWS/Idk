-- ============================================================================== --
-- // SKIBI DEFENSE - FLUENT MACRO EDITION V24 (REMOTE INTERCEPTOR)
-- // UI Design: All-in-One Main Tab + Safe Record System
-- // Logic: Namecall Interceptor (กันข้ามสเต็ป 100%) + Oracle Data Miner + Fast Exec
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
    SubTitle = "Interceptor Edition",
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
-- // 2. Helper Functions & Backup Money Queue 
-- ============================================================================== --
local MoneyQueue = {}

local function ParseMoney(val)
    local cleanVal = string.gsub(tostring(val), ",", "")
    local num = string.match(cleanVal, "%d+")
    return num and tonumber(num) or 0
end

local function GetCurrentMoney()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local moneyObj = ls and (ls:FindFirstChild("Money") or ls:FindFirstChild("Cash"))
    if moneyObj then return ParseMoney(moneyObj.Value) end
    return 0
end

local function GetCurrentWave()
    local currentWave = 1
    pcall(function()
        local waveText = LocalPlayer.PlayerGui.Data.Wave.Frame.TextLabel.Text
        local numStr = string.match(waveText, "%d+")
        if numStr then currentWave = tonumber(numStr) end
    end)
    return currentWave
end

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
local instanceToLevel = {}

local function WipeRecordingState()
    _G.MacroData = {}
    actionCount = 0
    instanceToLevel = {}
    for k in pairs(MoneyQueue) do MoneyQueue[k] = nil end 
    recordStartTime = tick()
end

-- ============================================================================== --
-- // 🔥 4. THE ORACLE: ระบบขุดราคาจากฐานข้อมูลเกม
-- ============================================================================== --
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
                if actionType == "Place" then
                    cost = data.Price or data.Cost or data.BasePrice or data.DeployCost or 0
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

Tabs.Main:AddSection("Macro Controls")
local RecordToggle = Tabs.Main:AddToggle("RecordMacro", {Title = "Record Macro", Default = false })
local PlayToggle = Tabs.Main:AddToggle("PlayMacro", {Title = "Play Macro", Default = false })

Tabs.Main:AddSlider("StepDelay", { Title = "Step Delay", Description = "ดีเลย์ขั้นต่ำระหว่าง Playback", Default = 0.2, Min = 0.1, Max = 5, Rounding = 1 })
local PlayModes = Tabs.Main:AddDropdown("PlayModes", { Title = "Play Modes", Description = "เงื่อนไขที่ต้องรอก่อนรันสเต็ปถัดไป", Values = {"Time", "Wave", "Money"}, Multi = true, Default = {"Wave", "Money"} })

-- ============================================================================== --
-- // 🔥 6. ลอจิกการอัด (Record) - Remote Interceptor (ดักฟัง 0.00 วิ)
-- ============================================================================== --
local function RecordAction(actionType, unitName, posCf, exactTime)
    actionCount = actionCount + 1
    local currentActionId = actionCount
    local currentWave = GetCurrentWave()
    
    local targetLevel = 0
    local posKey = posCf and GetPosKey(posCf.Position) or "UNKNOWN"
    
    if actionType == "Place" then 
        instanceToLevel[posKey] = 0
    elseif actionType == "Upgrade" then 
        instanceToLevel[posKey] = (instanceToLevel[posKey] or 0) + 1 
        targetLevel = instanceToLevel[posKey]
    end
    
    local stepData = { type = actionType, time = exactTime, wave = currentWave, unit = unitName, cost = 0 }
    if posCf then stepData.pos = FormatCFrame(posCf) end
    _G.MacroData[tostring(currentActionId)] = stepData

    task.spawn(function()
        local exactCost = GetExactCost(unitName, actionType, targetLevel)
        if exactCost == 0 and actionType ~= "Sell" then
            local passTime = 0
            while passTime < 1.5 do
                for _, drop in ipairs(MoneyQueue) do
                    if not drop.claimed and (tick() - drop.time) <= 3 then
                        exactCost = drop.amount; drop.claimed = true; break
                    end
                end
                if exactCost > 0 then break end
                task.wait(0.1); passTime = passTime + 0.1
            end
        end
        stepData.cost = exactCost
        UpdateStatus("Recording", currentActionId, actionType, unitName, "Cost: $" .. exactCost)
    end)
end

-- การดักฟัง RemoteEvent แทนการมองหน้าจอ
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    
    if isRecording and method == "FireServer" then
        local args = {...}
        
        if self == PlaceRemote then
            local exactTime = tick() - recordStartTime
            local unitName = args[1]
            local posCf = args[2]
            task.spawn(function() RecordAction("Place", unitName, posCf, exactTime) end)
            
        elseif self == UpgradeRemote then
            local exactTime = tick() - recordStartTime
            local targetId = tostring(args[1])
            task.spawn(function()
                local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
                local unit = targetFolder and targetFolder:FindFirstChild(targetId)
                if unit then
                    local posCf = unit.PrimaryPart and unit.PrimaryPart.CFrame or unit:GetModelCFrame()
                    RecordAction("Upgrade", GetRealUnitName(unit), posCf, exactTime)
                end
            end)
            
        elseif self == SellRemote then
            local exactTime = tick() - recordStartTime
            local targetId = tostring(args[1])
            task.spawn(function()
                local targetFolder = Workspace:FindFirstChild("Scripted") and Workspace.Scripted:FindFirstChild("Towers")
                local unit = targetFolder and targetFolder:FindFirstChild(targetId)
                if unit then
                    local posCf = unit.PrimaryPart and unit.PrimaryPart.CFrame or unit:GetModelCFrame()
                    RecordAction("Sell", GetRealUnitName(unit), posCf, exactTime)
                end
            end)
        end
    end
    
    return oldNamecall(self, ...)
end)

local function StartRecordingProcess()
    if PlayToggle.Value then PlayToggle:SetValue(false) end
    isRecording = true
    WipeRecordingState()
    UpdateStatus("Recording...", "-", "-", "-", "Start placing units")
    Fluent:Notify({ Title = "Recording Started", Content = "เริ่มอัดมาโคร! ระบบดักจับเปิดใช้งานแล้ว", Duration = 3 })
end

-- ============================================================================== --
-- // 7. ลอจิกการเล่น (Play)
-- ============================================================================== --
local function PlayMacroData()
    task.spawn(function()
        local useTime = Options.PlayModes.Value["Time"]
        local useWave = Options.PlayModes.Value["Wave"]
        local useMoney = Options.PlayModes.Value["Money"]
        local customDelay = Options.StepDelay.Value

        for i = 1, actionCount do
            if not isReplaying then return end 
            local step = _G.MacroData[tostring(i)]
            if not step then continue end

            local waitTime = customDelay
            if useTime then
                local prevTime = 0
                for j = i - 1, 1, -1 do
                    if _G.MacroData[tostring(j)] then prevTime = _G.MacroData[tostring(j)].time; break end
                end
                local realTimeGap = step.time - prevTime
                if realTimeGap > customDelay then waitTime = realTimeGap end
            end

            local passed = 0
            while passed < waitTime do
                if not isReplaying then return end
                UpdateStatus("Playing", i, step.type, step.unit, string.format("Time (%.1fs)", waitTime - passed))
                task.wait(0.1); passed = passed + 0.1
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

            -- 🔥 FAST EXECUTION & 15 ATTEMPTS ANTI-LAG
            if step.type == "Place" then
                local isPlaced = false
                local attempts = 0
                repeat
                    pcall(function() PlaceRemote:FireServer(step.unit, targetPosCf, false) end)
                    task.wait(0.2)
                    if GetUnitByPosition(step.unit, targetPosCf) then isPlaced = true end
                    attempts = attempts + 1
                until isPlaced or attempts >= 15 or not isReplaying

            elseif step.type == "Upgrade" then
                local attempts = 0
                local preMoney = GetCurrentMoney()
                repeat
                    local unitToUpgrade = GetUnitByPosition(step.unit, targetPosCf)
                    if unitToUpgrade then
                        local idNum = tonumber(unitToUpgrade.Name)
                        if idNum then pcall(function() UpgradeRemote:FireServer(idNum) end) else pcall(function() UpgradeRemote:FireServer(unitToUpgrade.Name) end) end
                    end
                    task.wait(0.2)
                    attempts = attempts + 1
                until GetCurrentMoney() < preMoney or attempts >= 15 or not isReplaying

            elseif step.type == "Sell" then
                local attempts = 0
                repeat
                    local unitToSell = GetUnitByPosition(step.unit, targetPosCf)
                    if unitToSell then
                        local idNum = tonumber(unitToSell.Name)
                        if idNum then pcall(function() SellRemote:FireServer(idNum) end) else pcall(function() SellRemote:FireServer(unitToSell.Name) end) end
                    end
                    task.wait(0.2)
                    attempts = attempts + 1
                until GetUnitByPosition(step.unit, targetPosCf) == nil or attempts >= 15 or not isReplaying
            end
        end
        
        isReplaying = false
        PlayToggle:SetValue(false)
        UpdateStatus("Idle", "-", "-", "-", "Finished")
        Fluent:Notify({ Title = "Complete", Content = "Macro เล่นจบแล้ว!", Duration = 5 })
    end)
end

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
        PlayMacroData()
    else
        isReplaying = false
        UpdateStatus("Idle", "-", "-", "-", "Stopped manually")
    end
end)
