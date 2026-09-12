local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local _, CoreGui = pcall(function() return game:GetService("CoreGui") end)
local Mouse = LocalPlayer:GetMouse()

local spawnFn = task and task.spawn or spawn
local waitFn = task and task.wait or wait

local function sendAlert(message, hexColor, color3)
	spawnFn(function()
		local success = false
		pcall(function()
			local tcs = game:GetService("TextChatService")
			if tcs and tostring(tcs.ChatVersion) == "Enum.ChatVersion.TextChatService" then
				local textChannels = tcs:FindFirstChild("TextChannels")
				local channel = textChannels and (textChannels:FindFirstChild("RBXSystem") or textChannels:FindFirstChild("RBXGeneral"))
				if channel then
					channel:DisplaySystemMessage("<font color='" .. hexColor .. "'>" .. message .. "</font>")
					success = true
				end
			end
		end)

		if not success then
			local attempts = 0
			while not success and attempts < 15 do
				success = pcall(function()
					game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", {
						Text = message,
						Color = color3 or Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.SourceSansBold,
						TextSize = 18
					})
				end)
				if not success then
					waitFn(0.5)
					attempts = attempts + 1
				end
			end
		end
	end)
end

local materialMap = {
	SmoothPlastic = "smooth",
	Plastic = "plastic",
	Wood = "wood",
	WoodPlanks = "planks",
	Brick = "bricks",
	Glass = "glass",
	Slate = "stone",
	Cobblestone = "pebble",
	Marble = "marble",
	Ice = "ice",
	Grass = "grass",
	Sand = "sand",
	Snow = "snow",
	Granite = "granite",
	DiamondPlate = "steel",
	CorrodedMetal = "metal",
	Metal = "metal",
	Asphalt = "asphalt",
	Concrete = "concrete",
	Pavement = "pavement",
	Neon = "neon"
}

local function getMaterialStr(mat)
	local matName = ""
	if typeof(mat) == "EnumItem" then
		matName = mat.Name
	else
		matName = tostring(mat)
		local matchStr = matName:match("Enum%.Material%.(.+)")
		if matchStr then
			matName = matchStr
		end
	end

	if materialMap[matName] then
		return materialMap[matName]
	end

	for _, v in pairs(materialMap) do
		if v == string.lower(matName) then
			return v
		end
	end
	return "plastic"
end

local function getEvent(toolName)
	local bt = LocalPlayer.Backpack:FindFirstChild(toolName) or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild(toolName))
	if bt and bt:FindFirstChild("Script") and bt.Script:FindFirstChild("Event") then
		return bt.Script.Event
	end
	return nil
end

local antiGriefActive = false
local protectedGrid = {}
local lastRebuildAttempt = {}
local localPlayerModifications = {}

local function getPosKey(pos)
	return string.format("%.2f_%.2f_%.2f", pos.X, pos.Y, pos.Z)
end

local function markLocalModification(pos)
	local k = getPosKey(pos)
	localPlayerModifications[k] = tick()
end

-- Hook into the mouse to detect exactly when the local player clicks with a tool
Mouse.Button1Down:Connect(function()
	if not antiGriefActive then return end
	local char = LocalPlayer.Character
	if not char then return end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then return end
	local tName = string.lower(tool.Name)

	local target = Mouse.Target
	if target and target:IsDescendantOf(workspace) then
		if string.find(tName, "delete") or string.find(tName, "destroy") or string.find(tName, "paint") or string.find(tName, "btools") or string.find(tName, "shape") then
			markLocalModification(target.Position)
			-- Mark adjacent blocks to be safe for AoE tools
			for x = -4, 4, 4 do
				for y = -4, 4, 4 do
					for z = -4, 4, 4 do
						local k = getPosKey(target.Position + Vector3.new(x, y, z))
						localPlayerModifications[k] = tick()
					end
				end
			end
		end
	end
end)

local function getBlockOwner(part)
	if not part then return nil end
	for _, child in ipairs(part:GetDescendants()) do
		local cName = string.lower(child.Name)
		if cName == "owner" or cName == "creator" or cName == "player" or cName == "placer" then
			if child:IsA("ObjectValue") and child.Value then
				return child.Value.Name
			elseif child:IsA("StringValue") then
				return child.Value
			end
		end
	end
	if Players:FindFirstChild(part.Name) then
		return part.Name
	end
	if part.Parent and Players:FindFirstChild(part.Parent.Name) then
		return part.Parent.Name
	end
	return nil
end

local function restoreSize(part, savedSize, hrpPos)
	local resizeEvent = getEvent("Resize") or getEvent("Scale") or getEvent("Grow")
	if not resizeEvent then return end

	local axes = {
		{axis = "X", pNorm = Enum.NormalId.Right, nNorm = Enum.NormalId.Left},
		{axis = "Y", pNorm = Enum.NormalId.Top, nNorm = Enum.NormalId.Bottom},
		{axis = "Z", pNorm = Enum.NormalId.Back, nNorm = Enum.NormalId.Front}
	}

	for _, data in ipairs(axes) do
		local target = savedSize[data.axis]
		local attempts = 0
		local toggle = true
		while part and part.Parent and math.abs(part.Size[data.axis] - target) > 0.1 and attempts < 15 do
			local cur = part.Size[data.axis]
			local action = (cur < target) and "increase" or "decrease"
			local norm = toggle and data.pNorm or data.nNorm

			pcall(function()
				resizeEvent:FireServer(part, norm, hrpPos, action)
			end)

			toggle = not toggle
			task.wait(0.06)
			attempts = attempts + 1
		end
	end
end

local function hasModifyingTool(player)
	if not player or not player.Character then return false end
	local tool = player.Character:FindFirstChildOfClass("Tool")
	if not tool then return false end
	local name = string.lower(tool.Name)
	if string.find(name, "delete") or string.find(name, "destroy") or string.find(name, "paint") or string.find(name, "build") or string.find(name, "btools") or string.find(name, "edit") or string.find(name, "shape") or string.find(name, "hammer") or string.find(name, "remove") or string.find(name, "shovel") or string.find(name, "trowel") or string.find(name, "clone") or string.find(name, "f3x") or string.find(name, "stamper") or string.find(name, "wand") then
		return true
	end
	return false
end

local function getProbableModifierFast(pos, targetOwner, playerCache)
	local closestPlayer = nil
	local minDistance = 45

	for _, pData in ipairs(playerCache) do
		local dist = (pData.pos - pos).Magnitude

		-- Heavily bias towards the owner if they are reasonably close AND have a modifying tool equipped
		if targetOwner and pData.name == targetOwner and dist < 60 and pData.hasTool then
			return pData.player
		end

		if dist < minDistance then
			if not closestPlayer or pData.hasTool or not closestPlayer.hasTool then
				closestPlayer = pData
				minDistance = dist
			end
		end
	end

	return closestPlayer and closestPlayer.player or nil
end

local function getInfiniteBuildArgs(targetPos, root)
	local spoofPart = workspace:FindFirstChild("Beach") or workspace:FindFirstChild("Baseplate")
	if root then
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = {root.Parent}
		params.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(root.Position, Vector3.new(0, -20, 0), params)
		if result and result.Instance then
			spoofPart = result.Instance
		end
	end
	if not spoofPart then spoofPart = workspace.Terrain end
	
	return spoofPart, Enum.NormalId.Top, targetPos, nil
end

local function getAntiGriefBuildTool()
	if LocalPlayer.Backpack:FindFirstChild("Anti-Grief Build") then LocalPlayer.Backpack["Anti-Grief Build"]:Destroy() end
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Anti-Grief Build") then LocalPlayer.Character["Anti-Grief Build"]:Destroy() end

	local t = Instance.new("Tool")
	t.Name = "Anti-Grief Build"
	t.RequiresHandle = false

	local gui = Instance.new("ScreenGui")
	gui.Name = "AntiGriefBuildGui"
	gui.ResetOnSpawn = false

	local mf = Instance.new("Frame", gui)
	mf.Size = UDim2.new(0, 200, 0, 100)
	mf.Position = UDim2.new(0.5, -100, 1, -150)
	mf.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	local mfc = Instance.new("UICorner", mf); mfc.CornerRadius = UDim.new(0, 10)
	mf.Visible = false

	local title = Instance.new("TextLabel", mf)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "Build Anti-Grief"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = Color3.new(1, 1, 1)

	local toggleBtn = Instance.new("TextButton", mf)
	toggleBtn.Size = UDim2.new(0, 160, 0, 40)
	toggleBtn.Position = UDim2.new(0.5, -80, 0.5, -5)
	toggleBtn.BackgroundColor3 = antiGriefActive and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(200, 100, 100)
	local tbc = Instance.new("UICorner", toggleBtn); tbc.CornerRadius = UDim.new(0, 8)
	toggleBtn.Text = antiGriefActive and "ACTIVE" or "INACTIVE"
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextSize = 16
	toggleBtn.TextColor3 = Color3.new(1, 1, 1)

	t.Equipped:Connect(function()
		if pcall(function() gui.Parent = CoreGui:FindFirstChild("RobloxGui") or CoreGui end) then
			if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
		else
			gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
		end
		mf.Visible = true
	end)

	t.Unequipped:Connect(function()
		gui.Parent = nil
		mf.Visible = false
	end)

	toggleBtn.MouseButton1Click:Connect(function()
		antiGriefActive = not antiGriefActive
		if antiGriefActive then
			toggleBtn.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
			toggleBtn.Text = "ACTIVE"
			sendAlert("Build Anti-Grief active!", "#00FF00", Color3.fromRGB(0, 255, 0))

			spawnFn(function()
				local bricksFolder = workspace:FindFirstChild("Bricks")
				if not bricksFolder then return end

				local savedState = {}
				for _, p in ipairs(bricksFolder:GetDescendants()) do
					if p:IsA("BasePart") then
						savedState[p] = {
							Size = p.Size,
							Color = p.Color,
							Material = p.Material,
							Position = p.Position
						}
					end
				end

				while antiGriefActive do
					waitFn(0.5)
					local char = LocalPlayer.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if not root then continue end

					for p, state in pairs(savedState) do
						if not p.Parent then
							local buildEvent = getEvent("Build")
							if buildEvent then
								pcall(function()
									local tBlock, tNorm, tHit, spoofFallback = getInfiniteBuildArgs(state.Position, root)
									buildEvent:FireServer(tBlock, tNorm, tHit, "normal", spoofFallback)
								end)
							end
							savedState[p] = nil
						elseif p.Size ~= state.Size then
							restoreSize(p, state, root.Position)
							state.Size = p.Size
						end
					end

					for _, p in ipairs(bricksFolder:GetDescendants()) do
						if p:IsA("BasePart") and not savedState[p] then
							savedState[p] = {
								Size = p.Size,
								Color = p.Color,
								Material = p.Material,
								Position = p.Position
							}
						end
					end
				end
			end)
		else
			toggleBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
			toggleBtn.Text = "INACTIVE"
			sendAlert("Build Anti-Grief deactivated.", "#FF0000", Color3.fromRGB(255, 0, 0))
		end
	end)

	t.Parent = LocalPlayer.Backpack
end

local function getWallBuilderTool()
	if LocalPlayer.Backpack:FindFirstChild("Wall Builder") then LocalPlayer.Backpack["Wall Builder"]:Destroy() end
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Wall Builder") then LocalPlayer.Character["Wall Builder"]:Destroy() end

	local t = Instance.new("Tool")
	t.Name = "Wall Builder"
	t.RequiresHandle = true

	local h = Instance.new("Part")
	h.Name = "Handle"
	h.Size = Vector3.new(1, 1, 1)
	h.Color = Color3.fromRGB(255, 150, 0)
	h.Material = Enum.Material.Neon
	h.Parent = t
	local currentShape = "square wall"
	local rotX, rotY = 0, 0
	local rsConnection = nil
	local hologramFolder = nil
	local hologramParts = {}

	local function clearHologram()
		if hologramFolder then
			hologramFolder:Destroy()
			hologramFolder = nil
		end
		hologramParts = {}
	end

	local function updateHologramShape()
		clearHologram()
		hologramFolder = Instance.new("Folder")
		hologramFolder.Name = "WallBuilderHolos"
		pcall(function() hologramFolder.Parent = workspace.CurrentCamera end)

		local offsets = {}

		if currentShape == "square wall" then
			for x = -2, 2 do
				for y = 0, 4 do
					table.insert(offsets, Vector3.new(x*4, y*4, 0))
				end
			end
		elseif currentShape == "square floor" then
			for x = -2, 2 do
				for z = -2, 2 do
					table.insert(offsets, Vector3.new(x*4, 0, z*4))
				end
			end
		elseif currentShape == "circle wall" then
			local radius = 2
			for x = -3, 3 do
				for y = 0, 5 do
					if (x^2 + (y-2.5)^2) <= radius^2 * 1.5 then
						table.insert(offsets, Vector3.new(x*4, y*4, 0))
					end
				end
			end
		elseif currentShape == "circle floor" then
			local radius = 2.5
			for x = -3, 3 do
				for z = -3, 3 do
					if (x^2 + z^2) <= radius^2 then
						table.insert(offsets, Vector3.new(x*4, 0, z*4))
					end
				end
			end
		elseif currentShape == "heart wall" then
			local h = {
				{0,0}, {-1,1}, {1,1}, {-2,2}, {2,2}, {-2,3}, {2,3}, {-1,4}, {1,4}
			}
			for _, v in ipairs(h) do
				table.insert(offsets, Vector3.new(v[1]*4, v[2]*4, 0))
			end
		elseif currentShape == "star floor" then
			table.insert(offsets, Vector3.new(0,0,0))
			for i=-2,2 do
				if i~=0 then table.insert(offsets, Vector3.new(i*4, 0, 0)) table.insert(offsets, Vector3.new(0, 0, i*4)) end
			end
		elseif currentShape == "diamond wall" then
			table.insert(offsets, Vector3.new(0,0,0))
			table.insert(offsets, Vector3.new(-1*4, 1*4, 0))
			table.insert(offsets, Vector3.new(1*4, 1*4, 0))
			table.insert(offsets, Vector3.new(0, 2*4, 0))
		elseif currentShape == "diamond floor" then
			table.insert(offsets, Vector3.new(0,0,0))
			table.insert(offsets, Vector3.new(-1*4, 0, 1*4))
			table.insert(offsets, Vector3.new(1*4, 0, 1*4))
			table.insert(offsets, Vector3.new(0, 0, 2*4))
		elseif currentShape == "hollow circle floor" then
			for x = -3, 3 do
				for z = -3, 3 do
					local d = x^2 + z^2
					if d >= 4 and d <= 10 then
						table.insert(offsets, Vector3.new(x*4, 0, z*4))
					end
				end
			end
		elseif currentShape == "3D cube" then
			for x = -1, 1 do
				for y = 0, 2 do
					for z = -1, 1 do
						table.insert(offsets, Vector3.new(x*4, y*4, z*4))
					end
				end
			end
		elseif currentShape == "sphere" then
			for x = -2, 2 do
				for y = -2, 2 do
					for z = -2, 2 do
						if x^2 + y^2 + z^2 <= 5 then
							table.insert(offsets, Vector3.new(x*4, (y+2)*4, z*4))
						end
					end
				end
			end
		elseif currentShape == "3D rectangle" then
			for x = -2, 2 do
				for y = 0, 1 do
					for z = -1, 1 do
						table.insert(offsets, Vector3.new(x*4, y*4, z*4))
					end
				end
			end
		elseif currentShape == "3D heart" then
			table.insert(offsets, Vector3.new(0,0,0))
		else
			table.insert(offsets, Vector3.new(0,0,0))
		end

		for _, off in ipairs(offsets) do
			local hp = Instance.new("Part")
			hp.Size = Vector3.new(4, 4, 4)
			hp.Anchored = true
			hp.CanCollide = false
			hp.Transparency = 0.5
			hp.Color = Color3.fromRGB(0, 150, 255)
			hp.Material = Enum.Material.Neon
			hp.Parent = hologramFolder
			table.insert(hologramParts, {part = hp, offset = off})
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WallBuilderGui"
	gui.ResetOnSpawn = false

	local mf = Instance.new("Frame", gui)
	mf.Size = UDim2.new(0, 150, 0, 260)
	mf.Position = UDim2.new(1, -160, 0.5, -130)
	mf.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	mf.BackgroundTransparency = 0.2
	local mfc = Instance.new("UICorner", mf); mfc.CornerRadius = UDim.new(0, 8)
	mf.Visible = false

	local catFrame = Instance.new("Frame", mf)
	catFrame.Size = UDim2.new(1, -10, 0, 25)
	catFrame.Position = UDim2.new(0, 5, 0, 5)
	catFrame.BackgroundTransparency = 1

	local catShapesBtn = Instance.new("TextButton", catFrame)
	catShapesBtn.Size = UDim2.new(0.5, -2, 1, 0)
	catShapesBtn.Position = UDim2.new(0, 0, 0, 0)
	catShapesBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
	catShapesBtn.Text = "Shapes"
	catShapesBtn.TextColor3 = Color3.new(1, 1, 1)
	catShapesBtn.Font = Enum.Font.GothamBold
	catShapesBtn.TextSize = 10
	local csc = Instance.new("UICorner", catShapesBtn); csc.CornerRadius = UDim.new(0, 4)

	local cat3DBtn = Instance.new("TextButton", catFrame)
	cat3DBtn.Size = UDim2.new(0.5, -2, 1, 0)
	cat3DBtn.Position = UDim2.new(0.5, 2, 0, 0)
	cat3DBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	cat3DBtn.Text = "3D Shapes"
	cat3DBtn.TextColor3 = Color3.new(1, 1, 1)
	cat3DBtn.Font = Enum.Font.GothamBold
	cat3DBtn.TextSize = 10
	local c3c = Instance.new("UICorner", cat3DBtn); c3c.CornerRadius = UDim.new(0, 4)

	local sf = Instance.new("ScrollingFrame", mf)
	sf.Size = UDim2.new(1, -10, 1, -125)
	sf.Position = UDim2.new(0, 5, 0, 35)
	sf.BackgroundTransparency = 1
	sf.ScrollBarThickness = 4

	local layout = Instance.new("UIListLayout", sf)
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local shapeCategories = {
		["Shapes"] = {"square wall", "square floor", "circle wall", "circle floor", "heart wall", "star floor", "diamond wall", "diamond floor", "hollow circle floor"},
		["3D Shapes"] = {"3D cube", "sphere", "3D rectangle", "3D heart"}
	}
	local currentCategory = "Shapes"

	local function populateShapes()
		for _, child in ipairs(sf:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		for i, shapeName in ipairs(shapeCategories[currentCategory]) do
			local btn = Instance.new("TextButton", sf)
			btn.Size = UDim2.new(1, -8, 0, 25)
			btn.BackgroundColor3 = (currentShape == shapeName) and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(60, 60, 60)
			btn.Text = shapeName
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Font = Enum.Font.GothamSemibold
			btn.TextSize = 11
			btn.LayoutOrder = i
			local btnc = Instance.new("UICorner", btn); btnc.CornerRadius = UDim.new(0, 5)

			btn.MouseButton1Click:Connect(function()
				currentShape = shapeName
				for _, child in ipairs(sf:GetChildren()) do
					if child:IsA("TextButton") then
						child.BackgroundColor3 = (child.Text == currentShape) and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(60, 60, 60)
					end
				end
				updateHologramShape()
			end)
		end
		sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
	end

	catShapesBtn.MouseButton1Click:Connect(function()
		currentCategory = "Shapes"
		catShapesBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		cat3DBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		populateShapes()
	end)

	cat3DBtn.MouseButton1Click:Connect(function()
		currentCategory = "3D Shapes"
		cat3DBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		catShapesBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		populateShapes()
	end)

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
	end)

	populateShapes()

	local rotFrame = Instance.new("Frame", mf)
	rotFrame.Size = UDim2.new(1, -10, 0, 50)
	rotFrame.Position = UDim2.new(0, 5, 1, -85)
	rotFrame.BackgroundTransparency = 1

	local function makeRotBtn(txt, p, s, action)
		local b = Instance.new("TextButton", rotFrame)
		b.Size = s
		b.Position = p
		b.Text = txt
		b.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 10
		local bc = Instance.new("UICorner", b); bc.CornerRadius = UDim.new(0, 4)
		b.MouseButton1Click:Connect(action)
	end
	makeRotBtn("Rot Up", UDim2.new(0, 0, 0, 0), UDim2.new(0.5, -2, 0.5, -2), function() rotX = (rotX + 90) % 360 end)
	makeRotBtn("Rot Dn", UDim2.new(0.5, 2, 0, 0), UDim2.new(0.5, -2, 0.5, -2), function() rotX = (rotX - 90) % 360 end)
	makeRotBtn("Rot L", UDim2.new(0, 0, 0.5, 2), UDim2.new(0.5, -2, 0.5, -2), function() rotY = (rotY + 90) % 360 end)
	makeRotBtn("Rot R", UDim2.new(0.5, 2, 0.5, 2), UDim2.new(0.5, -2, 0.5, -2), function() rotY = (rotY - 90) % 360 end)

	local buildBtn = Instance.new("TextButton", mf)
	buildBtn.Size = UDim2.new(1, -10, 0, 26)
	buildBtn.Position = UDim2.new(0, 5, 1, -31)
	buildBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
	buildBtn.Text = "Build"
	buildBtn.TextColor3 = Color3.new(1, 1, 1)
	buildBtn.Font = Enum.Font.GothamBold
	buildBtn.TextSize = 12
	local buildBtnc = Instance.new("UICorner", buildBtn); buildBtnc.CornerRadius = UDim.new(0, 5)

	buildBtn.MouseButton1Click:Connect(function()
		if #hologramParts == 0 then return end
		local buildEvent = getEvent("Build")
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if buildEvent then
			local positionsToBuild = {}
			for _, h in ipairs(hologramParts) do
				if h.part then
					table.insert(positionsToBuild, h.part.Position)
				end
			end

			spawnFn(function()
				for _, pos in ipairs(positionsToBuild) do
					pcall(function()
						local tBlock, tNorm, tHit, spoofFallback = getInfiniteBuildArgs(pos, root)
						buildEvent:FireServer(tBlock, tNorm, tHit, "normal", spoofFallback)
					end)
					waitFn(0.06)
				end
			end)
		end
	end)

	t.Equipped:Connect(function()
		pcall(function() gui.Parent = CoreGui:FindFirstChild("RobloxGui") or CoreGui end)
		if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
		mf.Visible = true

		updateHologramShape()

		rsConnection = game:GetService("RunService").RenderStepped:Connect(function()
			if not hologramFolder then return end
			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then return end

			local targetCFrame = root.CFrame * CFrame.new(0, 0, -6)
			local target = targetCFrame.Position

			local snapX = math.floor(target.X/4)*4
			local snapY = math.floor(target.Y/4)*4 + 2
			local snapZ = math.floor(target.Z/4)*4

			local rotationCFrame = CFrame.Angles(math.rad(rotX), math.rad(rotY), 0)

			for _, h in ipairs(hologramParts) do
				if h.part then
					local rotatedOffset = rotationCFrame * h.offset
					h.part.Position = Vector3.new(snapX + rotatedOffset.X, snapY + rotatedOffset.Y, snapZ + rotatedOffset.Z)
				end
			end
		end)
	end)

	t.Unequipped:Connect(function()
		gui.Parent = nil
		mf.Visible = false
		if rsConnection then rsConnection:Disconnect(); rsConnection = nil end
		clearHologram()
	end)

	t.Parent = LocalPlayer.Backpack
end

local function getDestroyerTool()
	if LocalPlayer.Backpack:FindFirstChild("Destroyer") then LocalPlayer.Backpack["Destroyer"]:Destroy() end
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Destroyer") then LocalPlayer.Character["Destroyer"]:Destroy() end

	local t = Instance.new("Tool")
	t.Name = "Destroyer"
	t.RequiresHandle = true

	local h = Instance.new("Part")
	h.Name = "Handle"
	h.Size = Vector3.new(1, 1, 1)
	h.Color = Color3.fromRGB(255, 0, 0)
	h.Material = Enum.Material.Neon
	h.Parent = t

	local mouseDownConn
	local mouseUpConn
	local startX, startY = 0, 0
	t.Equipped:Connect(function()
		mouseDownConn = Mouse.Button1Down:Connect(function()
			startX, startY = Mouse.X, Mouse.Y
		end)

		mouseUpConn = Mouse.Button1Up:Connect(function()
			local dist = math.sqrt((Mouse.X - startX)^2 + (Mouse.Y - startY)^2)
			if dist < 15 then
				local target = Mouse.Target
				local delEvent = getEvent("Delete")
				local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if target and target:IsDescendantOf(workspace:FindFirstChild("Bricks") or workspace) and delEvent and hrp then
					spawnFn(function()
						local char = LocalPlayer.Character
						local op = OverlapParams.new()
						local bricksFolder = workspace:FindFirstChild("Bricks")
						if bricksFolder then
							op.FilterDescendantsInstances = {bricksFolder}
							op.FilterType = Enum.RaycastFilterType.Include
						end

						local visited = {[target] = true}
						local currentLevel = {target}
						local limit = 25000
						local count = 0

						while #currentLevel > 0 and count < limit do
							local nextLevel = {}
							local nodeCount = 0

							for _, nodeBlock in ipairs(currentLevel) do
								nodeCount = nodeCount + 1
								if nodeCount % 20 == 0 then waitFn() end -- Yield periodically to prevent locking the main thread

								if nodeBlock.Parent then
									local bounds = workspace:GetPartBoundsInBox(nodeBlock.CFrame, nodeBlock.Size + Vector3.new(3, 3, 3), op)
									for _, neighbor in ipairs(bounds) do
										if neighbor:IsA("BasePart") and not visited[neighbor] then
											visited[neighbor] = true
											table.insert(nextLevel, neighbor)
										end
									end

									pcall(function()
										if localPlayerModifications and getPosKey then
											localPlayerModifications[getPosKey(nodeBlock.Position)] = tick()
										end
										delEvent:FireServer(nodeBlock, hrp.Position)
									end)
									count = count + 1
									if count >= limit then break end
								end
							end

							currentLevel = nextLevel
							waitFn(0.05)
						end
					end)
				end
			end
		end)
	end)

	t.Unequipped:Connect(function()
		if mouseDownConn then mouseDownConn:Disconnect() end
		if mouseUpConn then mouseUpConn:Disconnect() end
	end)

	t.Parent = LocalPlayer.Backpack
end

local infBtoolsActive = false
local infBtoolsConn = nil

local function toggleInfBtools(state)
	infBtoolsActive = state
	if infBtoolsActive then
		sendAlert("Infinite Btools Enabled! Works automatically with Delete, Build, and Paint tools.", "#00FF00", Color3.fromRGB(0, 255, 0))

		if not infBtoolsConn then
			infBtoolsConn = Mouse.Button1Down:Connect(function()
				if not infBtoolsActive then return end

				local char = LocalPlayer.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp then return end

				local currentTool = char:FindFirstChildOfClass("Tool")
				if not currentTool then return end

				local toolName = currentTool.Name
				local target = Mouse.Target
				local hit = Mouse.Hit

				if toolName == "Delete" then
					if target and target:IsDescendantOf(workspace) then
						local delEvent = getEvent("Delete")
						if delEvent then
							pcall(function()
								if localPlayerModifications and getPosKey then
									localPlayerModifications[getPosKey(target.Position)] = tick()
								end
								delEvent:FireServer(target, hrp.Position)
							end)
						end
					end
				elseif toolName == "Build" then
					if hit then
						local buildEvent = getEvent("Build")
						if buildEvent then
							pcall(function()
								local tBlock, tNorm, tHit, spoofFallback = getInfiniteBuildArgs(hit.Position, hrp)
								buildEvent:FireServer(tBlock, tNorm, tHit, "normal", spoofFallback)
							end)
						end
					end
				elseif toolName == "Paint" then
					if target and target:IsDescendantOf(workspace) then
						local paintEvent = getEvent("Paint")
						if paintEvent then
							pcall(function()
								local pColor = Color3.fromRGB(163, 162, 165)
								local pMat = "plastic"

								if currentTool:FindFirstChild("Color") and currentTool.Color:IsA("Color3Value") then
									pColor = currentTool.Color.Value
								elseif currentTool:FindFirstChild("BrickColor") and currentTool.BrickColor:IsA("BrickColorValue") then
									pColor = currentTool.BrickColor.Value.Color
								end

								if currentTool:FindFirstChild("Material") and currentTool.Material:IsA("StringValue") then
									pMat = currentTool.Material.Value
								end

								if localPlayerModifications and getPosKey then
									localPlayerModifications[getPosKey(target.Position)] = tick()
								end
								paintEvent:FireServer(target, Enum.NormalId.Top, hrp.Position, "both 🤝", pColor, pMat, "")
							end)
						end
					end
				end
			end)
		end
	else
		sendAlert("Infinite Btools Disabled.", "#FF0000", Color3.fromRGB(255, 0, 0))
		if infBtoolsConn then
			infBtoolsConn:Disconnect()
			infBtoolsConn = nil
		end
	end
end

local function getWorldEditTool()
	if LocalPlayer.Backpack:FindFirstChild("World Edit") then LocalPlayer.Backpack["World Edit"]:Destroy() end
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("World Edit") then LocalPlayer.Character["World Edit"]:Destroy() end

	local t = Instance.new("Tool")
	t.Name = "World Edit"
	t.RequiresHandle = true

	local h = Instance.new("Part")
	h.Name = "Handle"
	h.Size = Vector3.new(0.2, 1.5, 0.2)
	h.Color = Color3.fromRGB(139, 69, 19)
	h.Material = Enum.Material.Wood
	h.Parent = t
	Instance.new("CylinderMesh", h)

	local ferrule = Instance.new("Part")
	ferrule.Name = "Ferrule"
	ferrule.Size = Vector3.new(0.25, 0.4, 0.25)
	ferrule.Color = Color3.fromRGB(192, 192, 192)
	ferrule.Material = Enum.Material.Metal
	ferrule.Massless = true
	ferrule.CanCollide = false
	ferrule.Parent = t
	Instance.new("CylinderMesh", ferrule)
	local fw = Instance.new("WeldConstraint")
	fw.Part0 = h
	fw.Part1 = ferrule
	fw.Parent = h
	ferrule.CFrame = h.CFrame * CFrame.new(0, 0.95, 0)

	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.3, 0.6, 0.1)
	tip.Color = Color3.fromRGB(255, 50, 50)
	tip.Material = Enum.Material.SmoothPlastic
	tip.Massless = true
	tip.CanCollide = false
	tip.Parent = t
	local tm = Instance.new("SpecialMesh", tip)
	tm.MeshType = Enum.MeshType.Sphere
	local tw = Instance.new("WeldConstraint")
	tw.Part0 = h
	tw.Part1 = tip
	tw.Parent = h
	tip.CFrame = h.CFrame * CFrame.new(0, 1.45, 0)

	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldEditGui"
	gui.ResetOnSpawn = false

	local toggleBtn = Instance.new("TextButton", gui)
	toggleBtn.Size = UDim2.new(0, 40, 0, 40)
	toggleBtn.Position = UDim2.new(1, -50, 0.1, 0)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	toggleBtn.Text = "WE"
	toggleBtn.TextColor3 = Color3.new(1, 1, 1)
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextSize = 14
	local tc = Instance.new("UICorner", toggleBtn); tc.CornerRadius = UDim.new(1, 0)

	local mainScroll = Instance.new("ScrollingFrame", gui)
	mainScroll.Size = UDim2.new(0, 100, 0, 150)
	mainScroll.Position = UDim2.new(1, -110, 0.1, 50)
	mainScroll.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	mainScroll.BackgroundTransparency = 0.2
	mainScroll.Visible = false
	mainScroll.ScrollBarThickness = 4
	local msc = Instance.new("UICorner", mainScroll); msc.CornerRadius = UDim.new(0, 6)

	local mainLayout = Instance.new("UIListLayout", mainScroll)
	mainLayout.Padding = UDim.new(0, 4)
	mainLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local linerBtn = Instance.new("TextButton", mainScroll)
	linerBtn.Size = UDim2.new(1, -8, 0, 30)
	linerBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	linerBtn.Text = "Liner"
	linerBtn.TextColor3 = Color3.new(1, 1, 1)
	linerBtn.Font = Enum.Font.GothamSemibold
	linerBtn.TextSize = 12
	local lbc = Instance.new("UICorner", linerBtn); lbc.CornerRadius = UDim.new(0, 4)

	local subScroll = Instance.new("ScrollingFrame", gui)
	subScroll.Size = UDim2.new(0, 100, 0, 150)
	subScroll.Position = UDim2.new(1, -220, 0.1, 50)
	subScroll.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	subScroll.BackgroundTransparency = 0.2
	subScroll.Visible = false
	subScroll.ScrollBarThickness = 4
	local ssc = Instance.new("UICorner", subScroll); ssc.CornerRadius = UDim.new(0, 6)

	local subLayout = Instance.new("UIListLayout", subScroll)
	subLayout.Padding = UDim.new(0, 4)
	subLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local setPosBtn = Instance.new("TextButton", subScroll)
	setPosBtn.Size = UDim2.new(1, -8, 0, 30)
	setPosBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	setPosBtn.Text = "Set pos"
	setPosBtn.TextColor3 = Color3.new(1, 1, 1)
	setPosBtn.Font = Enum.Font.GothamSemibold
	setPosBtn.TextSize = 12
	local spbc = Instance.new("UICorner", setPosBtn); spbc.CornerRadius = UDim.new(0, 4)

	local weActive = false
	local linerActive = false
	local posState = 0
	local anchorPos = nil
	local isSpoofing = false

	local holoFolder = nil
	local holoPool = {}
	local activeHolos = 0
	local rsConn = nil

	local function clearHolos()
		for _, p in ipairs(holoPool) do p.Parent = nil end
		activeHolos = 0
		if holoFolder then holoFolder:Destroy(); holoFolder = nil end
	end

	local function getSnap(pos)
		return Vector3.new(math.floor(pos.X/4)*4, math.floor(pos.Y/4)*4 + 2, math.floor(pos.Z/4)*4)
	end

	local function updateHolo(p1, p2)
		if not holoFolder then
			holoFolder = Instance.new("Folder")
			holoFolder.Name = "WEHolo"
			pcall(function() holoFolder.Parent = workspace.CurrentCamera end)
		end

		local minX = math.min(p1.X, p2.X)
		local maxX = math.max(p1.X, p2.X)
		local minY = math.min(p1.Y, p2.Y)
		local maxY = math.max(p1.Y, p2.Y)
		local minZ = math.min(p1.Z, p2.Z)
		local maxZ = math.max(p1.Z, p2.Z)

		local needed = {}
		for x = minX, maxX, 4 do
			for y = minY, maxY, 4 do
				for z = minZ, maxZ, 4 do
					table.insert(needed, Vector3.new(x, y, z))
					if #needed > 40000 then break end
				end
				if #needed > 40000 then break end
			end
			if #needed > 40000 then break end
		end

		local visualLimit = math.min(#needed, 2000)
		for i = 1, visualLimit do
			local hp = holoPool[i]
			if not hp then
				hp = Instance.new("Part")
				hp.Size = Vector3.new(4, 4, 4)
				hp.Anchored = true
				hp.CanCollide = false
				hp.Transparency = 0.5
				hp.Color = Color3.fromRGB(0, 255, 100)
				hp.Material = Enum.Material.Neon
				holoPool[i] = hp
			end
			hp.Position = needed[i]
			if hp.Parent ~= holoFolder then hp.Parent = holoFolder end
		end

		for i = visualLimit + 1, #holoPool do
			if holoPool[i].Parent then holoPool[i].Parent = nil end
		end
		activeHolos = #needed
		return needed
	end

	toggleBtn.MouseButton1Click:Connect(function()
		weActive = not weActive
		if weActive then
			toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
			mainScroll.Visible = true
		else
			toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			mainScroll.Visible = false
			subScroll.Visible = false
			linerActive = false
			linerBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			posState = 0
			setPosBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			setPosBtn.Text = "Set pos"
			clearHolos()
			if rsConn then rsConn:Disconnect(); rsConn = nil end
		end
	end)

	linerBtn.MouseButton1Click:Connect(function()
		linerActive = not linerActive
		if linerActive then
			linerBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
			subScroll.Visible = true
		else
			linerBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			subScroll.Visible = false
			posState = 0
			setPosBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			setPosBtn.Text = "Set pos"
			clearHolos()
			if rsConn then rsConn:Disconnect(); rsConn = nil end
		end
	end)

	local lastNeeded = {}
	setPosBtn.MouseButton1Click:Connect(function()
		if posState == 0 then
			posState = 1
			setPosBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
			setPosBtn.Text = "Build Box"

			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				anchorPos = getSnap(root.Position - Vector3.new(0, 3, 0))
			else
				anchorPos = getSnap(Vector3.new(0, 0, 0))
			end

			local lastSnapPos = nil
			if rsConn then rsConn:Disconnect() end
			rsConn = game:GetService("RunService").RenderStepped:Connect(function()
				local c = LocalPlayer.Character
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if r and anchorPos then
					local currentPos = getSnap(r.Position - Vector3.new(0, 3, 0))
					if currentPos ~= lastSnapPos then
						lastSnapPos = currentPos
						lastNeeded = updateHolo(anchorPos, currentPos)
						setPosBtn.Text = "Build (" .. tostring(#lastNeeded) .. ")"
					end
				end
			end)
		else
			posState = 0
			setPosBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			setPosBtn.Text = "Set pos"

			if rsConn then rsConn:Disconnect(); rsConn = nil end

			if #lastNeeded > 0 then
				local buildEvent = getEvent("Build")
				local char = LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")

				if buildEvent then
					local positionsToBuild = lastNeeded

					spawnFn(function()
						for _, pos in ipairs(positionsToBuild) do
							if not weActive then break end
							pcall(function()
								local tBlock, tNorm, tHit, spoofFallback = getInfiniteBuildArgs(pos, root)
								buildEvent:FireServer(tBlock, tNorm, tHit, "normal", spoofFallback)
							end)
							waitFn(0.06)
						end

						while true do
							if not weActive then break end
							waitFn(1.5)

							local occupied = {}
							local bricks = workspace:FindFirstChild("Bricks")
							if bricks then
								for _, p in ipairs(bricks:GetDescendants()) do
									if p:IsA("BasePart") then
										local px, py, pz = math.floor(p.Position.X + 0.5), math.floor(p.Position.Y + 0.5), math.floor(p.Position.Z + 0.5)
										occupied[px .. "" .. py .. "" .. pz] = true
									end
								end
							end

							local missingBlocks = {}
							for _, pos in ipairs(positionsToBuild) do
								local px, py, pz = math.floor(pos.X + 0.5), math.floor(pos.Y + 0.5), math.floor(pos.Z + 0.5)
								if not occupied[px .. "" .. py .. "" .. pz] then
									table.insert(missingBlocks, pos)
								end
							end

							if #missingBlocks > 0 and weActive then

								for _, pos in ipairs(missingBlocks) do
									if not weActive then break end
									pcall(function()
										local tBlock, tNorm, tHit, spoofFallback = getInfiniteBuildArgs(pos, root)
										buildEvent:FireServer(tBlock, tNorm, tHit, "normal", spoofFallback)
									end)
									waitFn(0.06)
								end
							else
								break
							end
						end
					end)
				end
			end

			clearHolos()
			lastNeeded = {}
		end
	end)

	t.Equipped:Connect(function()
		pcall(function() gui.Parent = CoreGui:FindFirstChild("RobloxGui") or CoreGui end)
		if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
	end)

	t.Unequipped:Connect(function()
		if isSpoofing then return end
		gui.Parent = nil
		weActive = false
		toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		mainScroll.Visible = false
		subScroll.Visible = false
		linerActive = false
		linerBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		posState = 0
		setPosBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		setPosBtn.Text = "Set pos"
		clearHolos()
		if rsConn then rsConn:Disconnect(); rsConn = nil end
	end)

	t.Parent = LocalPlayer.Backpack
end

LocalPlayer.Chatted:Connect(function(msg)
	if msg:lower() == "/antigriefd" then
		spawnFn(getAntiGriefBuildTool)
	elseif msg:lower() == "/worldedit" then
		spawnFn(getWorldEditTool)
	elseif msg:lower() == "/wallbuilder" then
		spawnFn(getWallBuilderTool)
	elseif msg:lower() == "/destroyer" then
		spawnFn(getDestroyerTool)
	elseif msg:lower() == "/infbtools" then
		toggleInfBtools(true)
	elseif msg:lower() == "/unfbtools" then
		toggleInfBtools(false)
	elseif msg:lower() == "/cmds" then
		sendAlert("Build Tools Loaded! Commands: /antigriefd, /worldedit, /wallbuilder, /destroyer, /infbtools, /unfbtools, /cmds", "#00FF00", Color3.fromRGB(0, 255, 0))
		sendAlert("created by:sofiakira", "#FF69B4", Color3.fromRGB(255, 105, 180))
	end
end)

sendAlert("Build Tools Loaded! Commands: /antigriefd, /worldedit, /wallbuilder, /destroyer, /infbtools, /unfbtools, /cmds", "#00FF00", Color3.fromRGB(0, 255, 0))
sendAlert("created by:sofiakira", "#FF69B4", Color3.fromRGB(255, 105, 180))
