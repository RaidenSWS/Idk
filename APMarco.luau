local ReplicatedStorage = game:GetService('ReplicatedStorage');
local vu = game:GetService('VirtualUser');
local UserInputService = game:GetService('UserInputService');
local Players = game:GetService('Players');
local HttpService = game:GetService('HttpService');
local localPlayer = Players.LocalPlayer
local PlayerGui = localPlayer:WaitForChild("PlayerGui")

local replaying = false
local autoVoteEnabled = true

local UnitInventory = PlayerGui:WaitForChild("UnitInventory")
local InventoryContent = UnitInventory:WaitForChild("Inventory"):WaitForChild("Content")
local Units = InventoryContent:WaitForChild("Units"):WaitForChild("UnitsListFrame"):WaitForChild("List")
local bottomFrame = PlayerGui:WaitForChild("MainHUD"):WaitForChild("BottomFrame"):WaitForChild("UnitsHolder")

local UnitFolder = game:GetService("ReplicatedStorage").Modules.Shared.Data.UnitData.Units

local dataUnit = {}

-- ?Anti-AFK
pcall(function()
	game:GetService("Players").LocalPlayer.Idled:Connect(function()
		vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
		task.wait(1)
		vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
	end)
end)

local function CheckCostUpgrade(UnitName, UpgradeLevel)
    local unitModule = require(UnitFolder:WaitForChild(UnitName))
    local upgradeStats = unitModule.UpgradeStats
    if upgradeStats and upgradeStats[UpgradeLevel] then
        return upgradeStats[UpgradeLevel].Cost or 0
    end
    return 0
end

local function AutoSkipVote()

    local gameHUD = localPlayer:WaitForChild("PlayerGui"):WaitForChild("GameHUD")
    local voteFrame = gameHUD:WaitForChild("VoteSkipFrame")
    local yesButton = voteFrame:WaitForChild("BTNs"):WaitForChild("Yes")

    local function safeFire(signal)
        for _,conn in pairs(getconnections(signal)) do
            if conn.Function then
                coroutine.resume(coroutine.create(conn.Function))
            end
        end
    end

    local function pressYes()
        if not autoVoteEnabled then return end

        safeFire(yesButton.Activated)
        safeFire(yesButton.MouseButton1Click)

        print("Auto Pressed Yes ✅")
    end

    voteFrame:GetPropertyChangedSignal("Visible"):Connect(function()
        if voteFrame.Visible and autoVoteEnabled then
            task.wait(0.25)
            pressYes()
        end
    end)

    if voteFrame.Visible and autoVoteEnabled then
        task.wait(0.25)
        pressYes()
    end
end

local function StopAutoSkipVote()
    autoVoteEnabled = false
    print("Auto Skip Vote Disabled.")
end

local function writefileData(name)
    if not isfolder("APMarcoData") then
        makefolder("APMarcoData")
    end
    local jsonData = HttpService:JSONEncode(dataUnit)
    writefile("APMarcoData/" .. name .. ".json", jsonData)
end

-------------------------------------------------
-- REPLAY SYSTEM
-------------------------------------------------
local replayRunning = false

local function findUnit(step)
	if not step.Position then return nil end
	
	local entities = workspace:WaitForChild("Entities")
	local targetPos = Vector3.new(unpack(step.Position))

	for attempt = 1, 30 do
		if workspace:GetAttribute("GameIntermission") == true then
			return nil
		end

		for _, child in ipairs(entities:GetChildren()) do
			if child:IsA("Model")
				and child:GetAttribute("Type") == "Unit"
				and child:GetAttribute("Unit") == step.Name then

				local towerPos = child:GetAttribute("TowerPosition")
				if towerPos and (towerPos - targetPos).Magnitude < 2 then
					return child
				end
			end
		end

		task.wait(0.15)
	end

	return nil
end


local function startReplay(name)
	if replayRunning then
		warn("Replay already running")
		return
	end

	replayRunning = true
    AutoSkipVote()

	task.spawn(function()
		while replayRunning do

			-------------------------------------------------
			-- WAIT GAME START
			-------------------------------------------------
			repeat task.wait(1)
			until workspace:GetAttribute("GameIntermission") == false
			or not replayRunning

			if not replayRunning then break end
			task.wait(2)

			-------------------------------------------------
			-- LOAD FILE
			-------------------------------------------------
			local path = "APMarcoData/" .. name .. ".json"

			if not isfile(path) then
				warn("Replay file not found:", path)
				replayRunning = false
				return
			end

			local content = readfile(path)
			local dataUnit = HttpService:JSONDecode(content)
			local placedUnits = {}

			-------------------------------------------------
			-- MAIN LOOP
			-------------------------------------------------
			for _, step in ipairs(dataUnit) do
				if not replayRunning then break end
				if workspace:GetAttribute("GameIntermission") == true then break end

				task.wait(0.35)

				-------------------------------------------------
				-- PLACE
				-------------------------------------------------
				if step.Action == "Place" then

					repeat task.wait(0.25)
					until workspace:GetAttribute("GameIntermission") == true
					or (localPlayer:GetAttribute("Yen")
						and localPlayer:GetAttribute("Yen") >= step.Cost)

					if workspace:GetAttribute("GameIntermission") == true then break end

					local args = {
						"Place",
						step.ID,
						Vector3.new(unpack(step.Position)),
						0
					}

					localPlayer.Character.CharacterHandler.Remotes.UnitAction:FireServer(unpack(args))

					local unitModel = findUnit(step)

					if unitModel then
						placedUnits[step.UnitKey] = unitModel
						print("Placed:", step.Name)
					else
						warn("Failed placement:", step.Name)
					end


				-------------------------------------------------
				-- UPGRADE
				-------------------------------------------------
				elseif step.Action == "Upgrade" then

					local unit = placedUnits[step.UnitKey]
					if not unit or not unit.Parent then
						warn("Unit missing:", step.UnitKey)
						continue
					end

					local currentLevel = unit:GetAttribute("Upgrades") or 0
					local targetLevel = step.Upgrades

					while currentLevel < targetLevel do
						if workspace:GetAttribute("GameIntermission") == true then break end

						local nextLevel = currentLevel + 1
						local cost = CheckCostUpgrade(step.Name, nextLevel)

						repeat task.wait(0.25)
						until workspace:GetAttribute("GameIntermission") == true
						or (localPlayer:GetAttribute("Yen")
							and localPlayer:GetAttribute("Yen") >= cost)

						if workspace:GetAttribute("GameIntermission") == true then break end

						local upgradeArgs = {"Upgrade", unit, true}
						localPlayer.Character.CharacterHandler.Remotes.UnitAction:FireServer(unpack(upgradeArgs))

						repeat task.wait(0.2)
							currentLevel = unit:GetAttribute("Upgrades") or 0
						until currentLevel >= nextLevel
						or workspace:GetAttribute("GameIntermission") == true
					end
				end
			end

			-------------------------------------------------
			-- WAIT ROUND END
			-------------------------------------------------
			repeat task.wait(2)
			until workspace:GetAttribute("GameIntermission") == true
			or not replayRunning

			print("Round finished.")
		end
	end)
end


local function stopReplay()
	replayRunning = false
    StopAutoSkipVote()
	print("Replay stopped.")
end


-------------------------------------------------
-- SAVE SYSTEM
-------------------------------------------------
local function SavePlaceUnits()

	local monitoring = false
	local stepCounter = 0
	local connections = {}
	local dataUnit = {}

	-------------------------------------------------
	-- UPGRADE MONITOR
	-------------------------------------------------
	local function connectUpgradeMonitor(unitModel, unitName, unitId, unitKey)

		local lastLevel = unitModel:GetAttribute("Upgrades") or 0

		local conn
		conn = unitModel:GetAttributeChangedSignal("Upgrades"):Connect(function()

			if not monitoring then
				conn:Disconnect()
				return
			end

			local newLevel = unitModel:GetAttribute("Upgrades") or 0
			if newLevel == lastLevel then return end

			lastLevel = newLevel
			stepCounter += 1

			table.insert(dataUnit, {
				Step = stepCounter,
				Action = "Upgrade",
				UnitKey = unitKey,
				Name = unitName,
				ID = unitId,
				Upgrades = newLevel
			})

			print("Upgrade:", unitName, newLevel)
		end)

		table.insert(connections, conn)
	end


	-------------------------------------------------
	-- ENTITY MONITOR
	-------------------------------------------------
	local function monitorEntities()

		local entities = workspace:WaitForChild("Entities")

		local conn
		conn = entities.ChildAdded:Connect(function(child)

			if not monitoring then return end
			if not child:IsA("Model") then return end
			if child:GetAttribute("Type") ~= "Unit" then return end

			task.wait(0.2)

			local unitName = child:GetAttribute("Unit")
			local towerPosition = child:GetAttribute("TowerPosition")
			local totalCost = child:GetAttribute("TotalCost")
			local unitId = child:GetAttribute("GUID")

			if not (unitName and towerPosition and totalCost and unitId) then return end

			local unitKey = HttpService:GenerateGUID(false)

			stepCounter += 1

			table.insert(dataUnit, {
				Step = stepCounter,
				Action = "Place",
				UnitKey = unitKey,
				Name = unitName,
				ID = unitId,
				Position = {towerPosition.X, towerPosition.Y, towerPosition.Z},
				Cost = totalCost
			})

			print("Placed:", unitName)

			connectUpgradeMonitor(child, unitName, unitId, unitKey)
		end)

		table.insert(connections, conn)
	end


	-------------------------------------------------
	-- CONTROLLER
	-------------------------------------------------
	return {

		Start = function()
			if monitoring then return end

			monitoring = true
			dataUnit = {}
			stepCounter = 0

			monitorEntities()
			print("Monitoring started.")
		end,

		Stop = function()
			if not monitoring then return end

			monitoring = false

			for _, conn in ipairs(connections) do
				conn:Disconnect()
			end

			connections = {}

			print("Monitoring stopped.")
		end,

		GetData = function()
			return dataUnit
		end
	}
end


local savePlaceUnitsController = SavePlaceUnits()

local G2L = {};

-- StarterGui.AP
G2L["1"] = Instance.new("ScreenGui", game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"));
G2L["1"]["Name"] = [[AP]];
G2L["1"]["ZIndexBehavior"] = Enum.ZIndexBehavior.Sibling;


-- StarterGui.AP.UIControl
G2L["2"] = Instance.new("LocalScript", G2L["1"]);
G2L["2"]["Name"] = [[UIControl]];


-- StarterGui.AP.MainScript
G2L["3"] = Instance.new("LocalScript", G2L["1"]);
G2L["3"]["Name"] = [[MainScript]];


-- StarterGui.AP.MainFrame
G2L["4"] = Instance.new("Frame", G2L["1"]);
G2L["4"]["BorderSizePixel"] = 0;
G2L["4"]["BackgroundColor3"] = Color3.fromRGB(21, 21, 21);
G2L["4"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["4"]["Size"] = UDim2.new(0, 500, 0, 300);
G2L["4"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);
G2L["4"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["4"]["Name"] = [[MainFrame]];
G2L["4"]["BackgroundTransparency"] = 0.1;


-- StarterGui.AP.MainFrame.UICorner
G2L["5"] = Instance.new("UICorner", G2L["4"]);
G2L["5"]["CornerRadius"] = UDim.new(0.02, 0);


-- StarterGui.AP.MainFrame.UIStroke
G2L["6"] = Instance.new("UIStroke", G2L["4"]);
G2L["6"]["Color"] = Color3.fromRGB(255, 255, 255);


-- StarterGui.AP.MainFrame.CloseBTN
G2L["7"] = Instance.new("TextButton", G2L["4"]);
G2L["7"]["TextWrapped"] = true;
G2L["7"]["BorderSizePixel"] = 0;
G2L["7"]["TextSize"] = 14;
G2L["7"]["TextScaled"] = true;
G2L["7"]["TextColor3"] = Color3.fromRGB(255, 0, 0);
G2L["7"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["7"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["7"]["BackgroundTransparency"] = 1;
G2L["7"]["Size"] = UDim2.new(0.06061, 0, 0.10119, 0);
G2L["7"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["7"]["Text"] = [[X]];
G2L["7"]["Name"] = [[CloseBTN]];
G2L["7"]["Position"] = UDim2.new(0.93, 0, 0.02, 0);


-- StarterGui.AP.MainFrame.RecordBTN
G2L["8"] = Instance.new("TextButton", G2L["4"]);
G2L["8"]["BorderSizePixel"] = 0;
G2L["8"]["TextSize"] = 14;
G2L["8"]["TextColor3"] = Color3.fromRGB(0, 0, 0);
G2L["8"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["8"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["8"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["8"]["Size"] = UDim2.new(0.2815, 0, 0.16667, 0);
G2L["8"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["8"]["Text"] = [[]];
G2L["8"]["Name"] = [[RecordBTN]];
G2L["8"]["Position"] = UDim2.new(0.18075, 0, 0.82, 0);


-- StarterGui.AP.MainFrame.RecordBTN.UICorner
G2L["9"] = Instance.new("UICorner", G2L["8"]);
G2L["9"]["CornerRadius"] = UDim.new(0.1, 0);


-- StarterGui.AP.MainFrame.RecordBTN.TextLabel
G2L["a"] = Instance.new("TextLabel", G2L["8"]);
G2L["a"]["TextWrapped"] = true;
G2L["a"]["TextStrokeTransparency"] = 0;
G2L["a"]["BorderSizePixel"] = 0;
G2L["a"]["TextSize"] = 14;
G2L["a"]["TextScaled"] = true;
G2L["a"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["a"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["a"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["a"]["BackgroundTransparency"] = 1;
G2L["a"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["a"]["Size"] = UDim2.new(0.7, 0, 0.7, 0);
G2L["a"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["a"]["Text"] = [[Start Record]];
G2L["a"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- StarterGui.AP.MainFrame.Status
G2L["b"] = Instance.new("TextLabel", G2L["4"]);
G2L["b"]["TextWrapped"] = true;
G2L["b"]["BorderSizePixel"] = 0;
G2L["b"]["TextSize"] = 14;
G2L["b"]["TextScaled"] = true;
G2L["b"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["b"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["b"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["b"]["BackgroundTransparency"] = 1;
G2L["b"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["b"]["Size"] = UDim2.new(0.49904, 0, 0.16667, 0);
G2L["b"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["b"]["Text"] = [[Wait for Start Recording]];
G2L["b"]["Name"] = [[Status]];
G2L["b"]["Position"] = UDim2.new(0.49848, 0, 0.27333, 0);


-- StarterGui.AP.MainFrame.SaveBTN
G2L["c"] = Instance.new("TextButton", G2L["4"]);
G2L["c"]["BorderSizePixel"] = 0;
G2L["c"]["TextSize"] = 14;
G2L["c"]["TextColor3"] = Color3.fromRGB(0, 0, 0);
G2L["c"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["c"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["c"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["c"]["Size"] = UDim2.new(0.28102, 0, 0.16667, 0);
G2L["c"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["c"]["Text"] = [[]];
G2L["c"]["Name"] = [[SaveBTN]];
G2L["c"]["Position"] = UDim2.new(0.49651, 0, 0.82, 0);


-- StarterGui.AP.MainFrame.SaveBTN.UICorner
G2L["d"] = Instance.new("UICorner", G2L["c"]);
G2L["d"]["CornerRadius"] = UDim.new(0.1, 0);


-- StarterGui.AP.MainFrame.SaveBTN.TextLabel
G2L["e"] = Instance.new("TextLabel", G2L["c"]);
G2L["e"]["TextWrapped"] = true;
G2L["e"]["TextStrokeTransparency"] = 0;
G2L["e"]["BorderSizePixel"] = 0;
G2L["e"]["TextSize"] = 14;
G2L["e"]["TextScaled"] = true;
G2L["e"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["e"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["e"]["TextColor3"] = Color3.fromRGB(0, 255, 0);
G2L["e"]["BackgroundTransparency"] = 1;
G2L["e"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["e"]["Size"] = UDim2.new(0.7, 0, 0.7, 0);
G2L["e"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["e"]["Text"] = [[Save]];
G2L["e"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- StarterGui.AP.MainFrame.ReplayBTN
G2L["f"] = Instance.new("TextButton", G2L["4"]);
G2L["f"]["BorderSizePixel"] = 0;
G2L["f"]["TextSize"] = 14;
G2L["f"]["TextColor3"] = Color3.fromRGB(0, 0, 0);
G2L["f"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["f"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["f"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["f"]["Size"] = UDim2.new(0.28102, 0, 0.16667, 0);
G2L["f"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["f"]["Text"] = [[]];
G2L["f"]["Name"] = [[ReplayBTN]];
G2L["f"]["Position"] = UDim2.new(0.81651, 0, 0.82, 0);


-- StarterGui.AP.MainFrame.ReplayBTN.UICorner
G2L["10"] = Instance.new("UICorner", G2L["f"]);
G2L["10"]["CornerRadius"] = UDim.new(0.1, 0);


-- StarterGui.AP.MainFrame.ReplayBTN.TextLabel
G2L["11"] = Instance.new("TextLabel", G2L["f"]);
G2L["11"]["TextWrapped"] = true;
G2L["11"]["TextStrokeTransparency"] = 0;
G2L["11"]["BorderSizePixel"] = 0;
G2L["11"]["TextSize"] = 14;
G2L["11"]["TextScaled"] = true;
G2L["11"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["11"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["11"]["TextColor3"] = Color3.fromRGB(0, 255, 255);
G2L["11"]["BackgroundTransparency"] = 1;
G2L["11"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["11"]["Size"] = UDim2.new(0.7, 0, 0.7, 0);
G2L["11"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["11"]["Text"] = [[Start Replay]];
G2L["11"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- StarterGui.AP.MainFrame.LocalScript
G2L["12"] = Instance.new("LocalScript", G2L["4"]);



-- StarterGui.AP.MainFrame.HideBTN
G2L["13"] = Instance.new("TextButton", G2L["4"]);
G2L["13"]["TextWrapped"] = true;
G2L["13"]["BorderSizePixel"] = 0;
G2L["13"]["TextSize"] = 14;
G2L["13"]["TextScaled"] = true;
G2L["13"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["13"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["13"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["13"]["BackgroundTransparency"] = 1;
G2L["13"]["Size"] = UDim2.new(0.06061, 0, 0.10119, 0);
G2L["13"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["13"]["Text"] = [[-]];
G2L["13"]["Name"] = [[HideBTN]];
G2L["13"]["Position"] = UDim2.new(0.868, 0, 0.02, 0);


-- StarterGui.AP.MainFrame.SaveBox
G2L["14"] = Instance.new("TextBox", G2L["4"]);
G2L["14"]["Visible"] = false;
G2L["14"]["CursorPosition"] = -1;
G2L["14"]["Name"] = [[SaveBox]];
G2L["14"]["BorderSizePixel"] = 0;
G2L["14"]["TextWrapped"] = true;
G2L["14"]["TextSize"] = 14;
G2L["14"]["TextColor3"] = Color3.fromRGB(0, 0, 0);
G2L["14"]["TextScaled"] = true;
G2L["14"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["14"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["14"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["14"]["PlaceholderText"] = [[Enter Name]];
G2L["14"]["Size"] = UDim2.new(0.49904, 0, 0.1171, 0);
G2L["14"]["Position"] = UDim2.new(0.49848, 0, 0.49855, 0);
G2L["14"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["14"]["Text"] = [[]];


-- StarterGui.AP.MainFrame.SaveBox.UICorner
G2L["15"] = Instance.new("UICorner", G2L["14"]);
G2L["15"]["CornerRadius"] = UDim.new(0.2, 0);


-- StarterGui.AP.MainFrame.TextLabel
G2L["16"] = Instance.new("TextLabel", G2L["4"]);
G2L["16"]["TextWrapped"] = true;
G2L["16"]["BorderSizePixel"] = 0;
G2L["16"]["TextSize"] = 14;
G2L["16"]["TextXAlignment"] = Enum.TextXAlignment.Left;
G2L["16"]["TextScaled"] = true;
G2L["16"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["16"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["16"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["16"]["BackgroundTransparency"] = 1;
G2L["16"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["16"]["Size"] = UDim2.new(0.23696, 0, 0.05051, 0);
G2L["16"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["16"]["Text"] = [[Dev by AsiyaKung]];
G2L["16"]["Position"] = UDim2.new(0.13048, 0, 0.14333, 0);


-- StarterGui.AP.MainFrame.TextLabel
G2L["17"] = Instance.new("TextLabel", G2L["4"]);
G2L["17"]["TextWrapped"] = true;
G2L["17"]["BorderSizePixel"] = 0;
G2L["17"]["TextSize"] = 14;
G2L["17"]["TextXAlignment"] = Enum.TextXAlignment.Left;
G2L["17"]["TextScaled"] = true;
G2L["17"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["17"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["17"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["17"]["BackgroundTransparency"] = 1;
G2L["17"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["17"]["Size"] = UDim2.new(0.4, 0, 0.07644, 0);
G2L["17"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["17"]["Text"] = [[Marco Anime Paradox]];
G2L["17"]["Position"] = UDim2.new(0.212, 0, 0.06963, 0);


-- StarterGui.AP.Logo
G2L["18"] = Instance.new("TextButton", G2L["1"]);
G2L["18"]["TextWrapped"] = true;
G2L["18"]["BorderSizePixel"] = 0;
G2L["18"]["TextSize"] = 14;
G2L["18"]["TextScaled"] = true;
G2L["18"]["TextColor3"] = Color3.fromRGB(0, 0, 0);
G2L["18"]["BackgroundColor3"] = Color3.fromRGB(21, 21, 21);
G2L["18"]["FontFace"] = Font.new([[rbxasset://fonts/families/SourceSansPro.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["18"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["18"]["Size"] = UDim2.new(0.03724, 0, 0.06519, 0);
G2L["18"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["18"]["Text"] = [[]];
G2L["18"]["Name"] = [[Logo]];
G2L["18"]["Visible"] = false;
G2L["18"]["Position"] = UDim2.new(0.71554, 0, 0.33572, 0);


-- StarterGui.AP.Logo.LocalScript
G2L["19"] = Instance.new("LocalScript", G2L["18"]);



-- StarterGui.AP.Logo.UICorner
G2L["1a"] = Instance.new("UICorner", G2L["18"]);
G2L["1a"]["CornerRadius"] = UDim.new(1, 0);


-- StarterGui.AP.Logo.TextLabel
G2L["1b"] = Instance.new("TextLabel", G2L["18"]);
G2L["1b"]["TextWrapped"] = true;
G2L["1b"]["TextStrokeTransparency"] = 0;
G2L["1b"]["BorderSizePixel"] = 0;
G2L["1b"]["TextSize"] = 14;
G2L["1b"]["TextScaled"] = true;
G2L["1b"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["1b"]["FontFace"] = Font.new([[rbxasset://fonts/families/FredokaOne.json]], Enum.FontWeight.Regular, Enum.FontStyle.Normal);
G2L["1b"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["1b"]["BackgroundTransparency"] = 1;
G2L["1b"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["1b"]["Size"] = UDim2.new(0.7, 0, 0.7, 0);
G2L["1b"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["1b"]["Text"] = [[AP]];
G2L["1b"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- StarterGui.AP.Logo.UIStroke
G2L["1c"] = Instance.new("UIStroke", G2L["18"]);
G2L["1c"]["ApplyStrokeMode"] = Enum.ApplyStrokeMode.Border;
G2L["1c"]["Color"] = Color3.fromRGB(255, 255, 255);


-- StarterGui.AP.Logo.UIAspectRatioConstraint
G2L["1d"] = Instance.new("UIAspectRatioConstraint", G2L["18"]);
G2L["1d"]["AspectRatio"] = 1.01731;


-- StarterGui.AP.UIControl
local function C_2()
local script = G2L["2"];
	local Logo = script.Parent.Logo
	local MainFrame = script.Parent.MainFrame
	local CloseBTN = MainFrame.CloseBTN
	local HideBTN = MainFrame.HideBTN
	
	HideBTN.MouseButton1Click:Connect(function()
		if MainFrame.Visible == true then
			MainFrame.Visible = false
			Logo.Visible = true
		end
	end)
	
	Logo.MouseButton1Click:Connect(function()
		if MainFrame.Visible == false then
			MainFrame.Visible = true
			Logo.Visible = false
		end
	end)
	
	CloseBTN.MouseButton1Click:Connect(function()
		script.Parent:Destroy()
	end)
end;
task.spawn(C_2);
-- StarterGui.AP.MainScript
local function C_3()
local script = G2L["3"];
	local MainFrame = script.Parent.MainFrame
	local RecordBTN = MainFrame.RecordBTN
	local Status = MainFrame.Status
	local SaveBTN = MainFrame.SaveBTN
	local ReplayBTN = MainFrame.ReplayBTN
	
	local SaveBox = MainFrame.SaveBox
	
	RecordBTN.MouseButton1Click:Connect(function()
		local Text = RecordBTN.TextLabel.Text
		if Text == "Start Record" then
			RecordBTN.TextLabel.Text = "Stop Recording"
			savePlaceUnitsController:Start()
			Status.Text = "Recording..."
		else
			RecordBTN.TextLabel.Text = "Start Recording"
			savePlaceUnitsController:Stop()
			Status.Text = "Stopped Recording"
		end
	end)
	
	SaveBTN.MouseButton1Click:Connect(function()
	
		local currentText = SaveBTN.TextLabel.Text
	
		if currentText == "Save" then
	
			Status.Text = "Waiting for Enter Name..."
			SaveBTN.TextLabel.Text = "Confirm to save"
			SaveBox.Visible = true
	
		elseif currentText == "Confirm to save" then
	
			if SaveBox.Text ~= "" then
	
				Status.Text = "Saving..."
				SaveBox.Visible = false
				writefileData(SaveBox.Text)
	
				task.wait(1)
	
				Status.Text = "Saved!"
				SaveBTN.TextLabel.Text = "Save"
			else
				Status.Text = "Please enter a name!"
			end
	
		end
	
	end)
	
	ReplayBTN.MouseButton1Click:Connect(function()
	
		local currentText = ReplayBTN.TextLabel.Text
	
		-------------------------------------------------
		-- START
		-------------------------------------------------
		if currentText == "Start Replay" then
	
			Status.Text = "Waiting for Enter Name..."
			ReplayBTN.TextLabel.Text = "Confirm to Replay"
			SaveBox.Visible = true
	
			-------------------------------------------------
			-- CONFIRM
			-------------------------------------------------
		elseif currentText == "Confirm to Replay" then
	
			if SaveBox.Text ~= "" then
	
				Status.Text = "Replaying..."
				SaveBox.Visible = false
				ReplayBTN.TextLabel.Text = "Stop Replay"
	
				startReplay(SaveBox.Text) -- ✅ ไม่ต้อง spawn ซ้อน
	
			else
				Status.Text = "Please enter a name!"
			end
	
			-------------------------------------------------
			-- STOP
			-------------------------------------------------
		elseif currentText == "Stop Replay" then
	
			stopReplay()
	
			ReplayBTN.TextLabel.Text = "Start Replay"
			Status.Text = "Replay Stopped"
			SaveBox.Visible = false
	
		end
	end)
end;
task.spawn(C_3);
-- StarterGui.AP.MainFrame.LocalScript
local function C_12()
local script = G2L["12"];
	local frame = script.Parent
	
	local dragging = false
	local dragInput, dragStart, startPos
	
	local function update(input)
		if not dragging then return end
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
	
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
	
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	
	frame.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
	end)
	
	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput then update(input) end
	end)
	
end;
task.spawn(C_12);
-- StarterGui.AP.Logo.LocalScript
local function C_19()
local script = G2L["19"];
	local frame = script.Parent
	
	local dragging = false
	local dragInput, dragStart, startPos
	
	local function update(input)
		if not dragging then return end
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
	
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
	
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	
	frame.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
	end)
	
	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput then update(input) end
	end)
	
end;
task.spawn(C_19);

return G2L["1"], require;