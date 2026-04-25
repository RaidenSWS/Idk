-- ============================================================================== --
-- // SKIBI DEFENSE - FLUENT MACRO EDITION V21
-- // UI Design: All-in-One Main Tab + Safe Record System
-- // Logic: Perfect Cost V17 + ASTD Magnitude Checking + Smart Overwrite Dialog
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
    Title = "Skibi Macro V21",
    SubTitle = "Fluent Edition",
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
-- // 2. Helper Functions & Money Queue 
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
            isDropping = false
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

-- ============================================================================== --
-- // 3. สร้าง UI หน้า Main (รวม File & Profile ในหน้าเดียว)
-- ============================================================================== --
local StatusPara = Tabs.Main:AddParagraph({
    Title = "Macro Status: None",
    Content = "Action: -\nType: -\nUnit: -\nWaiting for: -"
})

local function UpdateStatus(status, action, actType, unit, waiting)
    StatusPara:SetTitle("Macro Status: " .. (status or "None"))
    StatusPara:SetDesc(string.format("Action: %s\nType: %s\nUnit: %s\nWaiting for: %s",
        tostring(action or "-"),
        tostring(actType or "-"),
        tostring(unit or "-"),
        tostring(waiting or "-")
    ))
end

-- [ ส่วนจัดการไฟล์ ]
Tabs.Main:AddSection("File & Profiles")

if not isfolder("SkibiMacroData") then makefolder("SkibiMacroData") end

local function GetMacroFiles()
    local files = {}
    for _, v in ipairs(listfiles("SkibiMacroData")) do
        table.insert(files, string.match(v, "([^/\\]+)%.json$") or v)
    end
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

-- [ ส่วนควบคุม ]
Tabs.Main:AddSection("Macro Controls")

local RecordToggle = Tabs.Main:AddToggle("RecordMacro", {Title = "Record Macro", Default = false })
local PlayToggle = Tabs.Main:AddToggle("PlayMacro", {Title = "Play Macro", Default = false })

Tabs.Main:AddSlider("StepDelay", {
    Title = "Step Delay",
    Description = "ดีเลย์ขั้นต่ำระหว่าง Playback",
    Default = 0.2,
    Min = 0.1,
    Max = 5,
    Rounding = 1
})

local PlayModes = Tabs.Main:AddDropdown("PlayModes", {
    Title = "Play Modes",
    Description = "เงื่อนไขที่ต้องรอก่อนรันสเต็ปถัดไป",
    Values = {"Time", "Wave", "Money"},
    Multi = true,
    Default = {"Time", "Wave", "Money"},
})

-- ============================================================================== --
-- // 4. Macro Logic (Record & Play)
-- ============================================================================== --
_G.MacroData = {}
local isRecording = false
local isReplaying = false
local recordStartTime = 0
local actionCount = 0
local instanceToId, posToId, instanceToLevel, activeConnections = {}, {}, {}, {}

local function ClearConnections()
    for _, conn in ipairs(activeConnections) do if conn.Connected then conn:Disconnect() end end
    activeConnections = {}
end

-- 🔥 ล้างสมองมาโคร (Clear Memory) เพื่อแก้บั๊กจำค่าเก่า
local function WipeRecordingState()
    _G.MacroData = {}
    actionCount = 0
    instanceToId = {}
    posToId = {}
    instanceToLevel = {}
    for k in pairs(MoneyQueue) do MoneyQueue[k] = nil end -- เคลียร์คิวเงินเก่าทิ้งให้เกลี้ยง
    recordStartTime = tick()
    ClearConnections()
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

local function RecordAction(actionType, targetId, posCf, unitName, exactTime)
    actionCount = actionCount + 1
    local currentActionId = actionCount
    local currentWave = GetCurrentWave()
    
    local stepData = { type = actionType, targetID = tostring(targetId), time = exactTime, wave = currentWave, unit = unitName, cost = 0 }
    if posCf then stepData.pos = FormatCFrame(posCf) end
    _G.MacroData[tostring(currentActionId)] = stepData

    UpdateStatus("Recording", currentActionId, actionType, unitName, "Saving Cost...")

    task.spawn(function()
        local cost = 0
        if actionType ~= "Sell" then
            local passTime = 0
            while passTime < 1.5 do
                for _, drop in ipairs(MoneyQueue) do
                    if not drop.claimed and (tick() - drop.time) <= 5 then
                        cost = drop.amount; drop.claimed = true; break
                    end
                end
                if cost > 0 then break end
                task.wait(0.1); passTime = passTime + 0.1
            end
        end
        stepData.cost = cost
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
        
        -- 🔥 แก้ตรงนี้: ดึงพิกัดตอนขาย (posCf) มาเก็บไว้
        local posCf = oldTower.PrimaryPart and oldTower.PrimaryPart.CFrame or oldTower:GetModelCFrame()
        local posKey = GetPosKey(posCf.Position)
        
        if targetId then
            task.delay(0.4, function()
                local isUpgraded = false
                for inst, id in pairs(instanceToId) do if inst.Parent ~= nil and id == targetId then isUpgraded = true break end end
                if not isUpgraded then
                    -- 🔥 เปลี่ยนจาก nil เป็น posCf ตรงช่องที่ 3
                    RecordAction("Sell", targetId, posCf, GetRealUnitName(oldTower), exactTime)
                    posToId[posKey] = nil
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
    WipeRecordingState() -- 🔥 ล้างข้อมูลทั้งหมด
    UpdateStatus("Recording...", "-", "-", "-", "Start placing units")
    Fluent:Notify({ Title = "Recording Started", Content = "เริ่มอัดมาโคร! (หน่วยความจำถูกล้างใหม่หมด)", Duration = 3 })
    StartObserving()
end

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
                local prevTime = (i == 1) and 0 or _G.MacroData[tostring(i-1)].time
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

            -- 🔥 ระบบ FAST EXECUTION (ยิงคำสั่งปุ๊บ ไปสเต็ปต่อไปปั๊บ ไม่ยืนเอ๋อรอ)
            if step.type == "Place" then
                pcall(function() PlaceRemote:FireServer(step.unit, targetPosCf, false) end)
                -- รอให้โมเดลโหลดแป๊บเดียว (กันบั๊กเกมโหลดช้า) สูงสุด 1 วินาที
                for pass = 1, 10 do
                    if GetUnitByPosition(step.unit, targetPosCf) then break end
                    task.wait(0.1)
                end

            elseif step.type == "Upgrade" then
                local unitToUpgrade = GetUnitByPosition(step.unit, targetPosCf)
                if unitToUpgrade then
                    local idNum = tonumber(unitToUpgrade.Name)
                    if idNum then pcall(function() UpgradeRemote:FireServer(idNum) end) else pcall(function() UpgradeRemote:FireServer(unitToUpgrade.Name) end) end
                end
                -- อัพเกรดเสร็จโดดไปสเต็ปต่อไปทันที ไม่ต้องรอ!

            elseif step.type == "Sell" then
                local unitToSell = GetUnitByPosition(step.unit, targetPosCf)
                if unitToSell then
                    local idNum = tonumber(unitToSell.Name)
                    if idNum then pcall(function() SellRemote:FireServer(idNum) end) else pcall(function() SellRemote:FireServer(unitToSell.Name) end) end
                end
                -- รอให้โมเดลหายไปแป๊บเดียว สูงสุด 1 วินาที
                for pass = 1, 10 do
                    if not GetUnitByPosition(step.unit, targetPosCf) then break end
                    task.wait(0.1)
                end
            end
        end
        
        isReplaying = false
        PlayToggle:SetValue(false)
        UpdateStatus("Idle", "-", "-", "-", "Finished")
        Fluent:Notify({ Title = "Complete", Content = "Macro เล่นจบแล้ว!", Duration = 5 })
    end)
end

-- ============================================================================== --
-- // 5. เชื่อมปุ่ม (Event Handlers)
-- ============================================================================== --
RecordToggle:OnChanged(function(val)
    if val then
        local fName = Options.MacroProfiles.Value
        local hasData = false

        -- เช็คว่ามีไฟล์ที่เลือกอยู่ และในไฟล์มีข้อมูลไหม
        if fName ~= "None" and isfile("SkibiMacroData/" .. fName .. ".json") then
            local content = readfile("SkibiMacroData/" .. fName .. ".json")
            if content and content ~= "" then
                pcall(function()
                    local decoded = HttpService:JSONDecode(content)
                    for _ in pairs(decoded) do hasData = true; break end
                end)
            end
        end

        -- ถ้าไฟล์มีข้อมูลอยู่แล้ว ให้เด้ง Popup ถามก่อน
        if hasData then
            Window:Dialog({
                Title = "พบข้อมูลมาโครเดิม",
                Content = "ไฟล์ '" .. fName .. "' มีข้อมูลอยู่แล้ว คุณต้องการอัดทับ (Overwrite) ข้อมูลเดิมหรือไม่?",
                Buttons = {
                    {
                        Title = "ใช่ (อัดทับ)",
                        Callback = function() StartRecordingProcess() end
                    },
                    {
                        Title = "ยกเลิก",
                        Callback = function() RecordToggle:SetValue(false) end
                    }
                }
            })
        else
            -- ถ้าไฟล์ใหม่สะอาด หรือไม่ได้เลือกไฟล์ ให้เริ่มอัดเลย
            StartRecordingProcess()
        end
    else
        -- ถ้ากดหยุดอัด
        if isRecording then
            isRecording = false
            ClearConnections()
            UpdateStatus("Idle", "-", "-", "-", "-")
            Fluent:Notify({ Title = "Stopped", Content = "หยุดอัดมาโครแล้ว", Duration = 3 })
            
            -- Auto-Save ลงไฟล์ที่เลือกไว้อัตโนมัติ
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
