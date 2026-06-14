--!nonstrict
--[[
	FileName    > PathfindingTest.luau
	Author      > AveryArk
	Contact     > Twitter: https://twitter.com/averyark_
	Created     > 14/06/2026
--]]

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Workspace = game:GetService("Workspace")
const RunService = game:GetService("RunService")

const Craftsman = require("@game/ReplicatedStorage/Packages/Craftsman")

local test = {}

function test:Init()
	Craftsman.PrintUtil:Print("PathfindingTest started - Waiting for player...")

	-- Wait for a player to join to spawn the dummy near them
	local player = game:GetService("Players"):GetPlayers()[1]
	if not player then
		player = game:GetService("Players").PlayerAdded:Wait()
	end

	local character = player.Character or player.CharacterAdded:Wait()
	task.wait(2) -- Let the character load into the world

	local dummyTemplate = ReplicatedStorage:FindFirstChild("R15")
	if not dummyTemplate then
		Craftsman.PrintUtil:Warn("R15 dummy not found in ReplicatedStorage. PathfindingTest skipped.")
		return
	end

	local dummy = dummyTemplate:Clone()
	dummy.Name = "PathfindingDummy"
	dummy.Parent = Workspace

	-- Position the dummy near the player
	local spawnPos = character:GetPivot().Position + Vector3.new(0, 0, -15)
	dummy:PivotTo(CFrame.new(spawnPos))

	for _, part in ipairs(dummy:GetDescendants()) do
		if part:IsA("BasePart") then
			part:SetNetworkOwner(nil)
		end
	end

	Craftsman.PrintUtil:Print("PathfindingTest dummy spawned at: " .. tostring(spawnPos))

	local chaserDummy = dummyTemplate:Clone()
	chaserDummy.Name = "PathfindingChaserDummy"
	chaserDummy.Parent = Workspace

	local chaserSpawnPos = character:GetPivot().Position + Vector3.new(15, 0, -15)
	chaserDummy:PivotTo(CFrame.new(chaserSpawnPos))

	for _, part in ipairs(chaserDummy:GetDescendants()) do
		if part:IsA("BasePart") then
			part:SetNetworkOwner(nil)
		end
	end

	-- Create a platform just in case
	local platform = Instance.new("Part")
	platform.Size = Vector3.new(100, 2, 100)
	platform.Position = spawnPos - Vector3.new(0, 3, 0)
	platform.Anchored = true
	platform.Parent = Workspace

	local targetPart = Instance.new("Part")
	targetPart.Name = "PathfindingTarget"
	targetPart.Size = Vector3.new(2, 2, 2)
	targetPart.Position = spawnPos + Vector3.new(30, 0, 0)
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.Color = Color3.fromRGB(0, 255, 0)
	targetPart.Material = Enum.Material.Neon
	targetPart.Parent = Workspace

	local pathfinder = Craftsman.Pathfind.new({
		Entity = dummy,
		Humanoid = dummy:FindFirstChild("Humanoid"),
		Config = {
			VISUALISE = true,
		}
	})

	local chaserPathfinder = Craftsman.Pathfind.new({
		Entity = chaserDummy,
		Humanoid = chaserDummy:FindFirstChild("Humanoid"),
		Config = {
			VISUALISE = true,
		}
	})

	-- Make the second dummy chase the player with a 5 stud stopping distance
	chaserPathfinder:Chase(character, 10)

	-- Continuous testing loop
	task.spawn(function()
		local obstructionsFolder = Instance.new("Folder")
		obstructionsFolder.Name = "PathfindingObstructions"
		obstructionsFolder.Parent = Workspace

		local movingParts = {}

		-- Hook up heartbeat for moving parts
		RunService.Heartbeat:Connect(function()
			local t = os.clock()
			for _, moving in ipairs(movingParts) do
				if moving.Part.Parent then
					local offset = math.sin(t * moving.Speed / moving.Distance + moving.TimeOffset) * moving.Distance
					moving.Part.CFrame = CFrame.new(moving.BasePos + (moving.OffsetDir * offset))
				end
			end
		end)

		local function generateObstructions(startPos: Vector3, endPos: Vector3)
			obstructionsFolder:ClearAllChildren()
			table.clear(movingParts)

			local direction = (endPos - startPos).Unit
			local right = direction:Cross(Vector3.new(0, 1, 0)).Unit

			-- 1. Create jumpable walls (Low enough to jump over, wide enough to block walking around)
			for i = 1, 2 do
				local wall = Instance.new("Part")
				wall.Size = Vector3.new(40, 2.5, 2)
				local pos = startPos:Lerp(endPos, 0.3 * i)

				-- Point Z towards the target so X spans left to right
				wall.CFrame = CFrame.new(pos, pos + direction)
				wall.Anchored = true
				wall.Color = Color3.fromRGB(50, 150, 255)
				wall.Material = Enum.Material.Wood
				wall.Parent = obstructionsFolder
			end

			-- 2. Create moving blocks that cross the path
			for i = 1, 4 do
				local obs = Instance.new("Part")
				obs.Size = Vector3.new(8, 10, 8)

				local alpha = math.random() * 0.6 + 0.2
				local basePos = startPos:Lerp(endPos, alpha)

				obs.Position = basePos
				obs.Anchored = true
				obs.Color = Color3.fromRGB(255, 50, 50)
				obs.Material = Enum.Material.Neon
				obs.Parent = obstructionsFolder

				table.insert(movingParts, {
					Part = obs,
					BasePos = basePos,
					OffsetDir = right,
					Speed = math.random(10, 25),
					Distance = math.random(10, 20),
					TimeOffset = math.random() * 10
				})
			end
		end

		while true do
			-- Pick a random new target position
			local targetPos = spawnPos + Vector3.new(math.random(-50, 50), 0, math.random(-50, 50))
			targetPart.Position = targetPos

			generateObstructions(dummy:GetPivot().Position, targetPos)

			Craftsman.PrintUtil:Print("PathfindingTest: Navigating to new random target")
			pathfinder:Goto(targetPos)

			-- Wait until the path completely ends (success or failure)
			pathfinder.OnPathEnded:Wait()

			Craftsman.PrintUtil:Print("PathfindingTest: Path finished! Generating new sequence in 2 seconds...")
			task.wait(2)
		end
	end)
end

return test
