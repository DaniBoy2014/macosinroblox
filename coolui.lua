local RunService = game:GetService("RunService")
local Playersvar = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui") 

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")
local slap = nil
function findslap()
	local function searchForEvent(parent)
		for _, v in ipairs(parent:GetDescendants()) do
			if v.Name == "Event" and v:IsA("RemoteEvent") then
				return v.Parent
			end
		end
		return nil
	end

	-- Priority 1: Check LocalPlayer
	local localPlr = game.Players.LocalPlayer
	local slaptool = searchForEvent(localPlr.Character or localPlr.CharacterAdded:Wait()) or searchForEvent(localPlr.Backpack)

	if slaptool then return slaptool end

	-- Priority 2: Game-specific check (Silver Slap Giver)
	if game.PlaceId == 122892536380985 then
		local giver = workspace:FindFirstChild("GearGivers") and workspace.GearGivers:FindFirstChild("SilverSlapGiver")
		if giver then
			firetouchinterest(giver.MainPart, localPlr.Character.HumanoidRootPart, 1)
			task.wait(0.1)
			firetouchinterest(giver.MainPart, localPlr.Character.HumanoidRootPart, 0)
			task.wait(0.5) -- Wait for tool to be given
			slaptool = searchForEvent(localPlr.Backpack)
			if slaptool then return slaptool end
		end
	end

	-- Priority 3: "Steal" from other players
	for _, otherPlr in ipairs(game.Players:GetPlayers()) do
		if otherPlr ~= localPlr and otherPlr.Character then
			slaptool = searchForEvent(otherPlr.Character) or searchForEvent(otherPlr.Backpack)
			if slaptool then
				return slaptool
			end
		end
	end

	return nil
end

function hit(plr)
	local args = {
		"slash",
		game:GetService("Players"):WaitForChild(plr.Name).Character,
		Vector3.new(8,4,8)
	}
	task.spawn(function()
		slap.Event:FireServer(unpack(args))
	end)
end

function hardhit(plr)
	local args = {
		"slash",
		game:GetService("Players"):WaitForChild(plr.Name).Character,
		Vector3.new(50,50,50)
	}
	task.spawn(function()
		slap.Event:FireServer(unpack(args))
	end)
end

-- ==========================================
-- ASSET HOSTING
-- Everything the script downloads lives in one GitHub repo (upload the
-- coolui-github folder). Change these two lines if your repo or branch
-- name is different. Each download falls back to its old source if the
-- repo doesn't have the file yet.
-- ==========================================
local ASSET_REPO = "DaniBoy2014/macosinroblox"
local ASSET_BRANCH = "main"
local ASSET_BASE_URL = "https://raw.githubusercontent.com/" .. ASSET_REPO .. "/" .. ASSET_BRANCH .. "/assets/"

-- Downloads from the first URL that returns a real file (GitHub answers a
-- missing file with a tiny "404: Not Found" page, which is skipped)
local function downloadAsset(urls, minBytes)
	local lastProblem
	for _, url in ipairs(urls) do
		local ok, data = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(data) == "string" and #data >= (minBytes or 1024) then
			return data
		end
		lastProblem = if ok then string.format("%s returned %d bytes", url, #tostring(data)) else tostring(data)
	end
	error("download failed: " .. tostring(lastProblem))
end

-- ==========================================
-- MUSIC PLAYER (replaces the dead ENJOY library)
-- Downloads each mp3 once, caches it in the executor
-- workspace, and plays it through a local Sound.
-- ==========================================
local MUSIC_FOLDER = "coolui_music"
local MUSIC_BACKUP_URL = "https://raw.githubusercontent.com/DaniBoy2014/music/refs/heads/main/"
local activeSounds = {}
local musicEnabled = true

local function getMusicAsset(fileName)
	local path = MUSIC_FOLDER .. "/" .. fileName
	if not isfile(path) then
		local data = downloadAsset({ASSET_BASE_URL .. "music/" .. fileName, MUSIC_BACKUP_URL .. fileName})
		if not isfolder(MUSIC_FOLDER) then
			makefolder(MUSIC_FOLDER)
		end
		writefile(path, data)
	end
	return getcustomasset(path)
end

local function playMusic(fileName, volume, looped)
	if not musicEnabled then return nil end
	local ok, assetId = pcall(getMusicAsset, fileName)
	if not ok then
		warn("[coolui] couldn't load " .. fileName .. ": " .. tostring(assetId))
		return nil
	end
	-- The UI may have closed while we were downloading
	if not musicEnabled then return nil end

	local sound = Instance.new("Sound")
	sound.Name = "coolui_" .. fileName
	sound.SoundId = assetId
	sound.Volume = volume or 1
	sound.Looped = looped == true
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	table.insert(activeSounds, sound)
	return sound
end

-- fadeTime (optional): fade the volume out over this many seconds first
local function stopMusic(fadeTime)
	musicEnabled = false
	local function stopSound(sound, destroyAfter)
		if not sound.Parent then return end
		if fadeTime and fadeTime > 0 and sound.IsPlaying then
			local fade = TweenService:Create(sound, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Volume = 0})
			fade.Completed:Once(function()
				sound:Stop()
				if destroyAfter then sound:Destroy() end
			end)
			fade:Play()
		else
			sound:Stop()
			if destroyAfter then sound:Destroy() end
		end
	end
	for _, sound in ipairs(activeSounds) do
		stopSound(sound, true)
	end
	table.clear(activeSounds)
	-- Studio copy of the shop music: stop it but keep the instance
	local shopmusic = game.SoundService:FindFirstChild("shopmusic")
	if shopmusic then
		stopSound(shopmusic, false)
	end
end

-- Warm the cache in the background so the sounds are ready on cue
task.spawn(function()
	pcall(getMusicAsset, "loadingsuccess.mp3")
	pcall(getMusicAsset, "shopmusic.mp3")
end)

-- ==========================================
-- 1. SAVE STATE & ANCHOR PLAYER
-- ==========================================
rootPart.Anchored = true

-- Anti-AFK: Roblox kicks after 20 minutes without input, which would end
-- macOS for anyone who leaves it open. Whenever Roblox reports the player
-- idle (every 2 minutes or so), a virtual right click resets the timer.
-- It's switched off again when the script ends.
local antiAfk = player.Idled:Connect(function()
	pcall(function()
		local VirtualUser = game:GetService("VirtualUser")
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.zero)
	end)
end)

local tempfolder = Instance.new("Folder")
tempfolder.Name = "Temp"
tempfolder.Parent = game.ReplicatedStorage

local originalLighting = {
	Ambient = game.Lighting.Ambient,
	Brightness = game.Lighting.Brightness,
	ColorShift_Bottom = game.Lighting.ColorShift_Bottom,
	ColorShift_Top = game.Lighting.ColorShift_Top,
	EnvironmentDiffuseScale = game.Lighting.EnvironmentDiffuseScale,
	EnvironmentSpecularScale = game.Lighting.EnvironmentSpecularScale,
	OutdoorAmbient = game.Lighting.OutdoorAmbient,
	ClockTime = game.Lighting.ClockTime,
	GeographicLatitude = game.Lighting.GeographicLatitude,
	ExposureCompensation = game.Lighting.ExposureCompensation,
	FogColor = game.Lighting.FogColor,
	FogEnd = game.Lighting.FogEnd,
	FogStart = game.Lighting.FogStart
}

local storedSoundVolumes = {}

-- Look through Workspace and SoundService for playing sounds
local containersToCheck = {workspace, game:GetService("SoundService")}

for _, container in ipairs(containersToCheck) do
	for _, instance in ipairs(container:GetDescendants()) do
		if instance:IsA("Sound") then
			-- Save the original volume to the dictionary
			storedSoundVolumes[instance] = instance.Volume
			-- Mute it
			instance.Volume = 0
		end
	end
end

local oldSky = game.Lighting:FindFirstChildOfClass("Sky")
if oldSky then
	oldSky.Parent = tempfolder
end

-- The game's own haze, clouds and screen effects would tint the scene
-- differently in every game (and the desktop's Liquid Glass is matched to the
-- plain scene), so they're switched off until the end
local oldAtmosphere = game.Lighting:FindFirstChildOfClass("Atmosphere")
if oldAtmosphere then
	oldAtmosphere.Parent = tempfolder
end
local disabledEffects = {}
for _, container in {game.Lighting, workspace.CurrentCamera, workspace.Terrain} do
	for _, effect in container:GetChildren() do
		if (effect:IsA("PostEffect") or effect:IsA("Clouds")) and effect.Enabled then
			effect.Enabled = false
			table.insert(disabledEffects, effect)
		end
	end
end

-- ==========================================
-- 2. CLEAR WORKSPACE & SETUP SCENE
-- ==========================================
for _, v in workspace:GetChildren() do
	if not v:IsA("Camera") and not v:IsA("Terrain") and not Players:GetPlayerFromCharacter(v) then
		task.spawn(function()
			v.Parent = tempfolder
		end)
	end
end

local campart = Instance.new("Part")
campart.Name = "CamPart"
campart.Reflectance = 0
campart.Color = Color3.fromRGB(163, 162, 165)
campart.Anchored = true
campart.Locked = false
campart.Size = Vector3.new(3, 3, 3)
campart.CanCollide = true
campart.Transparency = 1
campart.CFrame = CFrame.new(97.413063, 53.2785454, 52.6675339, 0.92602092, -0.0913926959, -0.366241306, 0.047168836, 0.990658641, -0.12794745, 0.374513596, 0.101206839, 0.921681464)
campart.Parent = workspace

local sky = Instance.new("Sky")
sky.SkyboxBk, sky.SkyboxDn, sky.SkyboxFt = "rbxassetid://792209302", "rbxassetid://792208824", "rbxassetid://792209541"
sky.SkyboxLf, sky.SkyboxRt, sky.SkyboxUp = "rbxassetid://792208652", "rbxassetid://792209063", "rbxassetid://792209747"
sky.Parent = game.Lighting

local bloom = Instance.new("BloomEffect")
bloom.Intensity, bloom.Size, bloom.Threshold = 0.5, 56, 0.2
bloom.Parent = game.Lighting

local blur = Instance.new("BlurEffect")
blur.Size = 8
blur.Parent = game.Lighting

local correction = Instance.new("ColorCorrectionEffect")
correction.Brightness, correction.Contrast, correction.Saturation = 0.07, 0.21, -0.2
correction.Parent = game.Lighting

local sunrays = Instance.new("SunRaysEffect")
sunrays.Intensity, sunrays.Spread = 0.05, 1
sunrays.Parent = game.Lighting

game.Lighting.Ambient = Color3.fromRGB(70, 70, 70)
game.Lighting.Brightness = 3
game.Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
game.Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
game.Lighting.EnvironmentDiffuseScale = 1
game.Lighting.EnvironmentSpecularScale = 1
game.Lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 70)
game.Lighting.ClockTime = 14.5
game.Lighting.ExposureCompensation = 0.1
game.Lighting.FogColor = Color3.fromRGB(255, 255, 255)
game.Lighting.FogEnd = 100000
game.Lighting.FogStart = 0

-- ==========================================
-- 3. SETUP GUI (HIDE OLD & CREATE NEW)
-- ==========================================
local storedGuiStates = {}
for _, gui in player.PlayerGui:GetChildren() do
	if gui:IsA("ScreenGui") then
		storedGuiStates[gui] = gui.Enabled 
		gui.Enabled = false 
	end
end

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = player:WaitForChild("PlayerGui")
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
-- Stay on top of the game's own GUIs, which come back while the goodbye screen is still up
ScreenGui.DisplayOrder = 1000

local LoadingFrame = Instance.new("Frame", ScreenGui)
LoadingFrame.Name = "LoadingFrame"
LoadingFrame.AnchorPoint = Vector2.new(0.5, 0.5)
LoadingFrame.BackgroundTransparency = 1
LoadingFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
LoadingFrame.Size = UDim2.new(1, 0, 1, 0)
LoadingFrame.ZIndex = 8

local background = Instance.new("ImageLabel", LoadingFrame)
background.Name = "background"
background.AnchorPoint = Vector2.new(0.5, 0.5)
background.BackgroundTransparency = 1
background.Position = UDim2.new(0.5, 0, 0.5, 0)
background.Size = UDim2.new(1, 0, 1, 0)
background.Image = "rbxassetid://91999160841553"
background.ImageColor3 = Color3.fromRGB(85, 96, 255)
background.ImageTransparency = 1 

local Spinner = Instance.new("ImageLabel", LoadingFrame)
Spinner.Name = "Spinner"
Spinner.AnchorPoint = Vector2.new(0.5, 0.5)
Spinner.BackgroundTransparency = 1
Spinner.Position = UDim2.new(0.5, 0, 0.5, 0)
Spinner.Size = UDim2.new(0, 40, 0, 40)
Spinner.ZIndex = 4
Spinner.Image = "rbxassetid://10723433935"
Spinner.ImageTransparency = 1 

local link = Instance.new("Frame", LoadingFrame)
link.Name = "link"
link.AnchorPoint = Vector2.new(0.5, 0.5)
link.BackgroundTransparency = 1
link.Position = UDim2.new(0.5, 0, 0.5, 0)
link.Visible = false

local Description = Instance.new("TextLabel", link)
Description.Name = "Description"
Description.AnchorPoint = Vector2.new(0.5, 0.5)
Description.BackgroundTransparency = 1
Description.Position = UDim2.new(0.5, 0, 0.621, 0)
Description.Size = UDim2.new(0, 454, 0, 52)
Description.ZIndex = 2
Description.Font = Enum.Font.Unknown
Description.LineHeight = 1.100
Description.RichText = true
Description.Text = '<font color="rgb(54, 61, 162)">Lithora Studios</font>'
Description.TextColor3 = Color3.fromRGB(255, 255, 255)
Description.TextSize = 14.000
Description.TextWrapped = true
Description.TextTransparency = 1 

-- ==========================================
-- EXACT INJECTION FROM new_gui.txt
-- ==========================================
local Onboarding = Instance.new("Frame")
local Installment = Instance.new("ImageLabel")
local Studio = Instance.new("ImageLabel")
local add = Instance.new("ImageButton")
local TextLabel = Instance.new("TextLabel")
local Price = Instance.new("TextLabel")
local Header = Instance.new("TextLabel")
local Included = Instance.new("TextLabel")
local backgroundgradient = Instance.new("ImageLabel")
local Header_2 = Instance.new("TextLabel")
local Header_3 = Instance.new("TextLabel")
local close = Instance.new("TextButton")
local ShadowImage = Instance.new("ImageLabel")
local UIScale = Instance.new("UIScale")

-- ==========================================
-- WINDOW POP ANIMATION
-- Each window's rounded background is moved onto a "host" image that also
-- clips the window's contents. Only the host (and the shadow) are resized,
-- so the text and buttons never squish; they're revealed as the host grows.
-- The host can stretch past full size and settle back for a springy pop.
-- Opening: a thin line pops out on X, then the window pops open on Y.
-- Closing: the reverse (Y collapses to a line, then X).
-- ==========================================
local POP_LINE_HEIGHT = 4
local popXOpenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local popYOpenInfo = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local popYCloseInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local popXCloseInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local popWindows = {}

local function makePopWindow(panel, shadow)
	local fullW, fullH = panel.Size.X.Offset, panel.Size.Y.Offset
	local shadowFull = shadow.Size

	local host = Instance.new("ImageLabel")
	host.Name = panel.Name .. "Host"
	host.BackgroundTransparency = 1
	host.Image = panel.Image
	host.ImageColor3 = panel.ImageColor3
	host.ScaleType = panel.ScaleType
	host.SliceCenter = panel.SliceCenter
	host.ClipsDescendants = true
	host.AnchorPoint = panel.AnchorPoint
	host.Position = panel.Position
	host.ZIndex = panel.ZIndex
	host.Parent = panel.Parent

	-- The host draws the background now; the panel just carries the contents
	panel.ImageTransparency = 1
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Parent = host

	local window = {
		host = host,
		shadow = shadow,
		x = Instance.new("NumberValue"), -- 0 = closed, 1 = full width (overshoots past 1)
		y = Instance.new("NumberValue"), -- 0 = thin line, 1 = full height (overshoots past 1)
	}
	local function apply()
		local sx, sy = math.max(window.x.Value, 0), math.max(window.y.Value, 0)
		host.Size = UDim2.fromOffset(fullW * sx, POP_LINE_HEIGHT + (fullH - POP_LINE_HEIGHT) * sy)
		shadow.Size = UDim2.new(shadowFull.X.Scale * sx, shadowFull.X.Offset * sx, shadowFull.Y.Scale * sy, shadowFull.Y.Offset * sy)
	end
	window.x.Changed:Connect(apply)
	window.y.Changed:Connect(apply)
	apply()
	table.insert(popWindows, window)
	return window
end

local function tweenWindows(windows, axis, info, target)
	for _, window in ipairs(windows) do
		TweenService:Create(window[axis], info, {Value = target}):Play()
	end
	task.wait(info.Time)
end

-- Pops the windows closed: Y collapses to a line, then the line shrinks on X
local function popClose(windows)
	tweenWindows(windows, "y", popYCloseInfo, 0)
	tweenWindows(windows, "x", popXCloseInfo, 0)
end

Onboarding.Name = "Onboarding"
Onboarding.Parent = ScreenGui
Onboarding.AnchorPoint = Vector2.new(0.5, 0.5)
Onboarding.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Onboarding.BackgroundTransparency = 1.000
Onboarding.BorderColor3 = Color3.fromRGB(0, 0, 0)
Onboarding.BorderSizePixel = 0
Onboarding.Position = UDim2.new(0.5, 0, 0.5, 0)
Onboarding.Size = UDim2.new(0, 431, 0, 442)
Onboarding.Visible = false -- Hidden initially

Installment.Name = "Installment"
Installment.Parent = Onboarding
Installment.AnchorPoint = Vector2.new(0.5, 0.5)
Installment.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Installment.BackgroundTransparency = 1.000
Installment.BorderColor3 = Color3.fromRGB(0, 0, 0)
Installment.BorderSizePixel = 0
Installment.Position = UDim2.new(0.222,0,0.495)
Installment.Size = UDim2.new(0, 307, 0, 442) -- fixed size; its pop window host does the open/close animation
Installment.ZIndex = 3
Installment.Image = "rbxassetid://99562943404134"
Installment.ImageColor3 = Color3.fromRGB(16, 18, 22)
Installment.ScaleType = Enum.ScaleType.Slice
Installment.SliceCenter = Rect.new(366, 520, 658, 520)

Studio.Name = "Studio"
Studio.Parent = Installment
Studio.AnchorPoint = Vector2.new(0.5, 0.5)
Studio.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Studio.BackgroundTransparency = 1.000
Studio.BorderColor3 = Color3.fromRGB(0, 0, 0)
Studio.BorderSizePixel = 0
Studio.Position = UDim2.new(0.5, 0, 0.777371049, 0)
Studio.Size = UDim2.new(0, 197, 0, 19)
Studio.Image = "rbxassetid://117785155287319"
Studio.ImageTransparency = 0.500
Studio.ScaleType = Enum.ScaleType.Crop

add.Name = "add"
add.Parent = Installment
add.Active = false
add.AnchorPoint = Vector2.new(0.5, 0.5)
add.BackgroundColor3 = Color3.fromRGB(0, 76, 255)
add.BackgroundTransparency = 1.000
add.BorderColor3 = Color3.fromRGB(0, 0, 0)
add.BorderSizePixel = 0
add.Position = UDim2.new(0.5, 0, 0.86152488, 0)
add.Size = UDim2.new(0, 252, 0, 31)
add.ZIndex = 8
add.AutoButtonColor = false
add.Image = "rbxassetid://99562943404134"
add.ImageColor3 = Color3.fromRGB(0, 76, 255)
add.ScaleType = Enum.ScaleType.Slice
add.SliceCenter = Rect.new(461, 207, 563, 817)

TextLabel.Parent = add
TextLabel.AnchorPoint = Vector2.new(0.5, 0.5)
TextLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
TextLabel.BackgroundTransparency = 1.000
TextLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
TextLabel.BorderSizePixel = 0
TextLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
TextLabel.Size = UDim2.new(0.899999976, 0, 0.899999976, 0)
TextLabel.Font = Enum.Font.Unknown
TextLabel.Text = "Load macOS"
TextLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
TextLabel.TextSize = 18.000

Price.Name = "Price"
Price.Parent = Installment
Price.AnchorPoint = Vector2.new(0.5, 0.5)
Price.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Price.BackgroundTransparency = 1.000
Price.BorderColor3 = Color3.fromRGB(0, 0, 0)
Price.BorderSizePixel = 0
Price.Position = UDim2.new(0.5, 0, 0.23490043, 0)
Price.Size = UDim2.new(0, 259, 0, 54)
Price.Font = Enum.Font.Unknown
Price.Text = "R$ 0 - Final price, including tax"
Price.TextColor3 = Color3.fromRGB(255, 255, 255)
Price.TextSize = 18.000
Price.TextTransparency = 0.400
Price.TextWrapped = true

Header.Name = "Header"
Header.Parent = Installment
Header.AnchorPoint = Vector2.new(0.5, 0.5)
Header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Header.BackgroundTransparency = 1.000
Header.BorderColor3 = Color3.fromRGB(0, 0, 0)
Header.BorderSizePixel = 0
Header.Position = UDim2.new(0.5, 0, 0.438579172, 0)
Header.Size = UDim2.new(0, 326, 0, 50)
Header.Font = Enum.Font.Unknown
Header.Text = "What's Included?"
Header.TextColor3 = Color3.fromRGB(255, 255, 255)
Header.TextSize = 26.000
Header.TextWrapped = true

Included.Name = "Included"
Included.Parent = Installment
Included.AnchorPoint = Vector2.new(0.5, 0.5)
Included.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Included.BackgroundTransparency = 1.000
Included.BorderColor3 = Color3.fromRGB(0, 0, 0)
Included.BorderSizePixel = 0
Included.Position = UDim2.new(0.5, 0, 0.552579284, 0)
Included.Size = UDim2.new(0, 324, 0, 52)
Included.ZIndex = 2
Included.Font = Enum.Font.Unknown
Included.Text = "- macOS style desktop\n- More coming soon"
Included.TextColor3 = Color3.fromRGB(255, 255, 255)
Included.TextSize = 14.000
Included.TextTransparency = 0.200
Included.TextWrapped = true

backgroundgradient.Name = "backgroundgradient"
backgroundgradient.Parent = Installment
backgroundgradient.AnchorPoint = Vector2.new(0.5, 0.5)
backgroundgradient.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
backgroundgradient.BackgroundTransparency = 1.000
backgroundgradient.BorderColor3 = Color3.fromRGB(0, 0, 0)
backgroundgradient.BorderSizePixel = 0
backgroundgradient.Position = UDim2.new(0.496519685, 0, 0.523269176, 0)
backgroundgradient.Size = UDim2.new(0.955916405, 0, 0.603886902, 0)
backgroundgradient.ZIndex = 0
backgroundgradient.Image = "rbxassetid://91558168273841"
backgroundgradient.ImageTransparency = 1.000
backgroundgradient.ScaleType = Enum.ScaleType.Crop

Header_2.Name = "Header"
Header_2.Parent = Installment
Header_2.AnchorPoint = Vector2.new(0.5, 0.5)
Header_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Header_2.BackgroundTransparency = 1.000
Header_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
Header_2.BorderSizePixel = 0
-- Narrower and a bit higher so it stays inside the window's rounded bottom corners
Header_2.Position = UDim2.new(0.5, 0, 0.935, 0)
Header_2.Size = UDim2.new(0, 250, 0, 30)
Header_2.Font = Enum.Font.Unknown
Header_2.Text = "By clicking Load macOS you accept all Terms of Service and Privacy Policy."
Header_2.TextColor3 = Color3.fromRGB(255, 255, 255)
Header_2.TextSize = 10.000
Header_2.TextTransparency = 0.730
Header_2.TextWrapped = true

Header_3.Name = "Header"
Header_3.Parent = Installment
Header_3.AnchorPoint = Vector2.new(0.5, 0.5)
Header_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Header_3.BackgroundTransparency = 1.000
Header_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
Header_3.BorderSizePixel = 0
Header_3.Position = UDim2.new(0.50232017, 0, 0.117312193, 0)
Header_3.Size = UDim2.new(0, 326, 0, 50)
Header_3.Font = Enum.Font.Unknown
Header_3.Text = "macOS loader"
Header_3.TextColor3 = Color3.fromRGB(255, 255, 255)
Header_3.TextSize = 26.000
Header_3.TextWrapped = true

close.Name = "close"
close.Parent = Installment
close.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
close.BackgroundTransparency = 1.000
close.BorderColor3 = Color3.fromRGB(0, 0, 0)
close.BorderSizePixel = 0
close.Position = UDim2.new(0.835266829, 0, 0.085972853, 0)
close.Size = UDim2.new(0, 46, 0, 47)
close.Font = Enum.Font.SourceSans
close.Text = "X"
close.TextColor3 = Color3.fromRGB(31, 31, 31)
close.TextSize = 58.000

ShadowImage.Name = "ShadowImage"
ShadowImage.Parent = Onboarding
ShadowImage.AnchorPoint = Vector2.new(0.5, 0.5)
ShadowImage.BackgroundTransparency = 1.000
ShadowImage.Position = UDim2.new(0.222, 0, 0.534, 0)
ShadowImage.Size = UDim2.new(1.13,0,1.5,0)
ShadowImage.ZIndex = 0
ShadowImage.Image = "rbxassetid://16389432702"
ShadowImage.ImageColor3 = Color3.fromRGB(0, 0, 0)
ShadowImage.SliceCenter = Rect.new(0, 0, 1024, 1024)

UIScale.Parent = Onboarding

-- Button Effects: hover brightens, pressing squishes + darkens,
-- releasing bounces back so every click visibly registers.
local hoverTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local pressTweenInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local releaseTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function addButtonEffects(button, baseColor, hoverColor)
	local pressColor = baseColor:Lerp(Color3.new(0, 0, 0), 0.25)
	local scale = Instance.new("UIScale")
	scale.Name = "pressScale"
	scale.Parent = button
	local hovering = false

	local function settle(tweenInfo)
		TweenService:Create(scale, tweenInfo, {Scale = if hovering then 1.03 else 1}):Play()
		TweenService:Create(button, hoverTweenInfo, {ImageColor3 = if hovering then hoverColor else baseColor}):Play()
	end

	button.MouseEnter:Connect(function()
		hovering = true
		settle(hoverTweenInfo)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		settle(hoverTweenInfo)
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, pressTweenInfo, {Scale = 0.93}):Play()
		TweenService:Create(button, pressTweenInfo, {ImageColor3 = pressColor}):Play()
	end)
	button.MouseButton1Up:Connect(function()
		settle(releaseTweenInfo)
	end)
end

addButtonEffects(add, Color3.fromRGB(0, 76, 255), Color3.fromRGB(0, 96, 255))

-- ==========================================
-- SECONDARY PANEL (HD Admin Rank Viewer)
-- ==========================================
local Installment2 = Instance.new("ImageLabel")
local Studio2 = Instance.new("ImageLabel")
local Price2 = Instance.new("TextLabel")
local backgroundgradient2 = Instance.new("ImageLabel")
local Header_Side2 = Instance.new("TextLabel")

Installment2.Name = "Installment2"
Installment2.Parent = Onboarding
Installment2.AnchorPoint = Vector2.new(0.5, 0.5)
Installment2.BackgroundTransparency = 1.000
Installment2.Position = UDim2.new(1.333, 0, 0.5, 0)
Installment2.Size = UDim2.new(0, 395, 0, 442) -- fixed size; its pop window host does the open/close animation
Installment2.ZIndex = 3
Installment2.Image = "rbxassetid://99562943404134"
Installment2.ImageColor3 = Color3.fromRGB(16, 18, 22)
Installment2.ScaleType = Enum.ScaleType.Slice
Installment2.SliceCenter = Rect.new(366, 520, 658, 520)

Studio2.Name = "Studio"
Studio2.Parent = Installment2
Studio2.AnchorPoint = Vector2.new(0.5, 0.5)
Studio2.BackgroundTransparency = 1.000
Studio2.Position = UDim2.new(0.5, 0, 0.777371049, 0)
Studio2.Size = UDim2.new(0, 197, 0, 19)
Studio2.Image = "rbxassetid://117785155287319"
Studio2.ImageTransparency = 0.500
Studio2.ScaleType = Enum.ScaleType.Crop

Price2.Name = "Price"
Price2.Parent = Installment2
Price2.AnchorPoint = Vector2.new(0.5, 0.5)
Price2.BackgroundTransparency = 1.000
Price2.Position = UDim2.new(0.5, 0, 0.23490043, 0)
Price2.Size = UDim2.new(0, 259, 0, 54)
Price2.Font = Enum.Font.Unknown
Price2.Text = "R$ 0 - Final price, including tax"
Price2.TextColor3 = Color3.fromRGB(255, 255, 255)
Price2.TextSize = 18.000
Price2.TextTransparency = 0.400
Price2.TextWrapped = true

backgroundgradient2.Name = "backgroundgradient"
backgroundgradient2.Parent = Installment2
backgroundgradient2.AnchorPoint = Vector2.new(0.5, 0.5)
backgroundgradient2.BackgroundTransparency = 1.000
backgroundgradient2.Position = UDim2.new(0.496519685, 0, 0.523269176, 0)
backgroundgradient2.Size = UDim2.new(0.955916405, 0, 0.603886902, 0)
backgroundgradient2.ZIndex = 0
backgroundgradient2.Image = "rbxassetid://91558168273841"
backgroundgradient2.ImageTransparency = 1.000
backgroundgradient2.ScaleType = Enum.ScaleType.Crop

Header_Side2.Name = "Header"
Header_Side2.Parent = Installment2
Header_Side2.AnchorPoint = Vector2.new(0.5, 0.5)
Header_Side2.BackgroundTransparency = 1.000
Header_Side2.Position = UDim2.new(0.50232017, 0, 0.117312193, 0)
Header_Side2.Size = UDim2.new(0, 326, 0, 50)
Header_Side2.Font = Enum.Font.Unknown
Header_Side2.Text = "HD admin rank viewer"
Header_Side2.TextColor3 = Color3.fromRGB(255, 255, 255)
Header_Side2.TextScaled = true
Header_Side2.TextWrapped = true

-- Gui to Lua
-- Version: 3.2

-- Instances:

local add1 = Instance.new("ImageButton")
local TextLabel = Instance.new("TextLabel")

--Properties:

add1.Name = "add"
add1.Parent = Installment2
add1.Active = false
add1.AnchorPoint = Vector2.new(0.5, 0.5)
add1.BackgroundColor3 = Color3.fromRGB(0, 76, 255)
add1.BackgroundTransparency = 1.000
add1.BorderColor3 = Color3.fromRGB(0, 0, 0)
add1.BorderSizePixel = 0
add1.Position = UDim2.new(0.511747301, 0, 0.856999993, 0)
add1.Size = UDim2.new(0, 252, 0, 31)
add1.ZIndex = 8
add1.AutoButtonColor = false
add1.Image = "rbxassetid://99562943404134"
add1.ImageColor3 = Color3.fromRGB(0, 76, 255)
add1.ScaleType = Enum.ScaleType.Slice
add1.SliceCenter = Rect.new(461, 207, 563, 817)

TextLabel.Parent = add1
TextLabel.AnchorPoint = Vector2.new(0.5, 0.5)
TextLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
TextLabel.BackgroundTransparency = 1.000
TextLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
TextLabel.BorderSizePixel = 0
TextLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
TextLabel.Size = UDim2.new(0.899999976, 0, 0.899999976, 0)
TextLabel.Font = Enum.Font.Unknown
TextLabel.Text = "Refresh"
TextLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
TextLabel.TextSize = 18.000

-- Gui to Lua
-- Version: 3.2

-- Instances:

local ShadowImage1 = Instance.new("ImageLabel")

--Properties:

ShadowImage1.Name = "ShadowImage1"
ShadowImage1.Parent = Onboarding
ShadowImage1.AnchorPoint = Vector2.new(0.5, 0.5)
ShadowImage1.BackgroundTransparency = 1.000
ShadowImage1.Position = UDim2.new(1.31, 0,0.495, 0)
ShadowImage1.Size = UDim2.new(1.381,0,1.5,0)
ShadowImage1.ZIndex = 0
ShadowImage1.Image = "rbxassetid://16389432702"
ShadowImage1.ImageColor3 = Color3.fromRGB(0, 0, 0)
ShadowImage1.SliceCenter = Rect.new(0, 0, 1024, 1024)

-- Both windows start closed and pop open in Step D
local loaderWindow = makePopWindow(Installment, ShadowImage)
local rankWindow = makePopWindow(Installment2, ShadowImage1)

-- Gui to Lua
-- Version: 3.2

-- Instances:

local Playerslist = Instance.new("ScrollingFrame")
local UIListLayout = Instance.new("UIListLayout")
local Templates = Instance.new("Folder")
local DaniBoyNov2014 = Instance.new("ImageButton")
local profile = Instance.new("ImageLabel")
local corner = Instance.new("UICorner")
local role = Instance.new("TextLabel")
local padding = Instance.new("UIPadding")
local corner_2 = Instance.new("UICorner")
local display = Instance.new("TextLabel")
local list = Instance.new("UIListLayout")
local corner_3 = Instance.new("UICorner")
local util = Instance.new("Folder")
local badge = Instance.new("Frame")
local selection = Instance.new("ImageLabel")
local scale = Instance.new("UIScale")
local padding_2 = Instance.new("UIPadding")

--Properties:

Playerslist.Name = "Playerslist"
Playerslist.Parent = Installment2
Playerslist.Active = true
Playerslist.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Playerslist.BackgroundTransparency = 1.000
Playerslist.BorderColor3 = Color3.fromRGB(0, 0, 0)
Playerslist.BorderSizePixel = 0
Playerslist.Position = UDim2.new(0.0895411745, 0, 0.289592773, 0)
Playerslist.Size = UDim2.new(0.829787254, 0, 0.46606335, 0)

UIListLayout.Parent = Playerslist
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

Templates.Name = "Templates"
Templates.Parent = Playerslist

-- Gui to Lua
-- Version: 3.2

-- Instances:

-- Gui to Lua
-- Version: 3.2

-- Instances:

local DaniBoyNov2014 = Instance.new("ImageButton")
local profile = Instance.new("ImageLabel")
local corner = Instance.new("UICorner")
local role = Instance.new("TextLabel")
local padding = Instance.new("UIPadding")
local corner_2 = Instance.new("UICorner")
local display = Instance.new("TextLabel")
local list = Instance.new("UIListLayout")
local corner_3 = Instance.new("UICorner")
local util = Instance.new("Folder")
local badge = Instance.new("Frame")
local selection = Instance.new("ImageLabel")
local scale = Instance.new("UIScale")
local padding_2 = Instance.new("UIPadding")

--Properties:

DaniBoyNov2014.Name = "DaniBoyNov2014"
DaniBoyNov2014.Parent = Templates
DaniBoyNov2014.AnchorPoint = Vector2.new(0.5, 1)
DaniBoyNov2014.BackgroundColor3 = Color3.fromRGB(27, 27, 27)
DaniBoyNov2014.BorderColor3 = Color3.fromRGB(0, 0, 0)
DaniBoyNov2014.BorderSizePixel = 0
DaniBoyNov2014.ClipsDescendants = true
DaniBoyNov2014.Size = UDim2.new(0.949999988, 0, 0.07, 0)
DaniBoyNov2014.AutoButtonColor = false
DaniBoyNov2014.ImageColor3 = Color3.fromRGB(27, 27, 27)
DaniBoyNov2014.ScaleType = Enum.ScaleType.Crop
DaniBoyNov2014.SliceCenter = Rect.new(512, 512, 512, 512)
DaniBoyNov2014.SliceScale = 0.040

profile.Name = "profile"
profile.Parent = DaniBoyNov2014
profile.AnchorPoint = Vector2.new(0, 0.5)
profile.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
profile.BorderColor3 = Color3.fromRGB(0, 0, 0)
profile.BorderSizePixel = 0
profile.LayoutOrder = 1
profile.Position = UDim2.new(0, 0, 0.5, 0)
profile.Size = UDim2.new(0.116959065, 0, 0.588235259, 0)
profile.Image = "rbxthumb://type=AvatarHeadShot&id=3681686378&w=420&h=420"
profile.ScaleType = Enum.ScaleType.Crop

corner.CornerRadius = UDim.new(1, 0)
corner.Name = "corner"
corner.Parent = profile

-- Gui to Lua
-- Version: 3.2

-- Instances:

local roleBG = Instance.new("TextLabel")
local padding = Instance.new("UIPadding")
local corner = Instance.new("UICorner")
local role = Instance.new("TextLabel")
local padding_2 = Instance.new("UIPadding")
local corner_2 = Instance.new("UICorner")

--Properties:

roleBG.Name = "roleBG"
roleBG.Parent = DaniBoyNov2014
roleBG.AnchorPoint = Vector2.new(0.5, 0)
roleBG.BackgroundColor3 = Color3.fromRGB(41, 61, 74)
roleBG.BackgroundTransparency = 1.000
roleBG.BorderColor3 = Color3.fromRGB(0, 0, 0)
roleBG.BorderSizePixel = 0
roleBG.LayoutOrder = 3
roleBG.Position = UDim2.new(0.946619451, 0, 0.280768365, 0)
roleBG.Size = UDim2.new(0.476210892, 0, 0.438463867, 0)
roleBG.Font = Enum.Font.Unknown
roleBG.Text = ""
roleBG.TextColor3 = Color3.fromRGB(117, 137, 150)
roleBG.TextSize = 11.000
roleBG.TextXAlignment = Enum.TextXAlignment.Left

padding.Name = "padding"
padding.Parent = roleBG
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)

corner.CornerRadius = UDim.new(0, 20)
corner.Name = "corner"
corner.Parent = roleBG

role.Name = "role"
role.Parent = roleBG
role.AnchorPoint = Vector2.new(0.5, 0)
role.BackgroundColor3 = Color3.fromRGB(41, 61, 74)
role.BorderColor3 = Color3.fromRGB(0, 0, 0)
role.BorderSizePixel = 0
role.LayoutOrder = 3
role.Position = UDim2.new(0.5, 0, -0.0174913034, 0) -- centered so the name gets more room
role.Size = UDim2.new(0.837648153, 0, 1, 0)
role.Font = Enum.Font.Unknown
role.Text = "Owner"
role.TextColor3 = Color3.fromRGB(117, 137, 150)
role.TextSize = 11.000
role.TextXAlignment = Enum.TextXAlignment.Center

padding_2.Name = "padding"
padding_2.Parent = role
padding_2.PaddingLeft = UDim.new(0, 8)
padding_2.PaddingRight = UDim.new(0, 8)

corner_2.CornerRadius = UDim.new(0, 20)
corner_2.Name = "corner"
corner_2.Parent = role

display.Name = "display"
display.Parent = DaniBoyNov2014
display.AnchorPoint = Vector2.new(0.5, 0)
display.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
display.BackgroundTransparency = 1.000
display.BorderColor3 = Color3.fromRGB(0, 0, 0)
display.BorderSizePixel = 0
display.LayoutOrder = 2
display.Position = UDim2.new(0.5, 0, 0, 0)
display.Size = UDim2.new(0.57, 0, 0.977, 0)
display.Font = Enum.Font.Unknown
display.Text = "Account_deleted"
display.TextColor3 = Color3.fromRGB(255, 255, 255)
display.TextSize = 13.000
display.TextXAlignment = Enum.TextXAlignment.Left
display.TextTruncate = Enum.TextTruncate.AtEnd -- long names end in "..." instead of running into the badge

list.Name = "list"
list.Parent = DaniBoyNov2014
list.FillDirection = Enum.FillDirection.Horizontal
list.SortOrder = Enum.SortOrder.LayoutOrder
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.Padding = UDim.new(0, 8)

corner_3.CornerRadius = UDim.new(0, 20)
corner_3.Name = "corner"
corner_3.Parent = DaniBoyNov2014

util.Name = "util"
util.Parent = DaniBoyNov2014

badge.Name = "badge"
badge.Parent = util
badge.AnchorPoint = Vector2.new(1, 0.5)
badge.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
badge.BackgroundTransparency = 1.000
badge.BorderColor3 = Color3.fromRGB(0, 0, 0)
badge.BorderSizePixel = 0
badge.Position = UDim2.new(1, 40, 0.5, 0)
badge.Size = UDim2.new(0.18,0,0.638,0)

selection.Name = "selection"
selection.Parent = badge
selection.AnchorPoint = Vector2.new(0.5, 0.5)
selection.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
selection.BackgroundTransparency = 1.000
selection.BorderColor3 = Color3.fromRGB(0, 0, 0)
selection.BorderSizePixel = 0
selection.Position = UDim2.new(0.5, 0, 0.5, 0)
selection.Size = UDim2.new(0, 20, 0, 20)
selection.Image = "rbxassetid://91811711741572"
selection.ImageColor3 = Color3.fromRGB(0, 140, 255)
selection.ImageTransparency = 1.000
selection.ScaleType = Enum.ScaleType.Fit

scale.Name = "scale"
scale.Parent = selection
scale.Scale = 0.800

-- Own instance: padding_2 above was re-declared for the role pill,
-- so reusing it here moved the role's padding onto the row.
local rowPadding = Instance.new("UIPadding")
rowPadding.Name = "padding"
rowPadding.Parent = DaniBoyNov2014
rowPadding.PaddingBottom = UDim.new(0, 8)
rowPadding.PaddingLeft = UDim.new(0, 12)
rowPadding.PaddingRight = UDim.new(0, 50)
rowPadding.PaddingTop = UDim.new(0, 8)

-- The rank window has no terms text at the bottom, so nudge everything in it
-- down to even out the space above the title and below the Refresh button
local RANK_WINDOW_CONTENT_SHIFT = 24
for _, child in ipairs(Installment2:GetChildren()) do
	if child:IsA("GuiObject") then
		child.Position += UDim2.fromOffset(0, RANK_WINDOW_CONTENT_SHIFT)
	end
end

-- Let the title fill the space the shift opened up at the top. On one line it
-- can't get much bigger without hitting the rounded edges, so it's split over
-- two lines and its scaled box runs from near the top down to the price text.
-- (Keep TextWrapped on: turning it off also turns TextScaled off.)
local RANK_WINDOW_HEIGHT = 442
local rankPriceTop = Price2.Position.Y.Scale * RANK_WINDOW_HEIGHT + Price2.Position.Y.Offset - Price2.Size.Y.Offset / 2
local rankTitleTop = 20
local rankTitleBottom = rankPriceTop - 6
Header_Side2.Text = "HD admin\nrank viewer"
Header_Side2.LineHeight = 0.9
Header_Side2.Position = UDim2.new(0.5, 0, 0, (rankTitleTop + rankTitleBottom) / 2)
Header_Side2.Size = UDim2.new(0, 330, 0, rankTitleBottom - rankTitleTop)

-- ==========================================
-- HD ADMIN RANK VIEWER
-- Supports three setups:
--  * HD Admin v1: ReplicatedStorage.HDAdminHDClient.Signals
--  * HD Admin v2: ReplicatedStorage["HD Admin"], read through its
--    clientUser stores ("ServerMembers" + "RoleInfo")
--  * Attribute ranks (e.g. HD Admin Playground): each player
--    has an "AdminRank" number attribute
-- ==========================================

-- Lets each row pop in when the list refreshes
local popScale = Instance.new("UIScale")
popScale.Name = "popScale"
popScale.Parent = DaniBoyNov2014

-- Built-in rank order used by HD Admin Playground (rank number = index).
-- Custom roles sit between built-in ranks with fractional numbers (e.g. 1.1);
-- their names only come from the server, so they show as "Custom role".
local ATTRIBUTE_RANK_NAMES = {[0] = "NonAdmin", "Free", "Member", "VIP", "Admin", "Staff", "Owner"}

local function attributeRankName(level)
	if level ~= math.floor(level) then
		return "Custom role"
	end
	return ATTRIBUTE_RANK_NAMES[level] or ("Rank " .. level)
end

local rankListConnections = {}

-- Returns { [Player] = { name = string, level = number, color = Color3? } }.
-- Players missing from the table aren't shown. Stays nil when this game
-- has no rank system we can read.
local fetchRanks = nil

local classicHD = ReplicatedStorage:FindFirstChild("HDAdminHDClient")
local hdAdminV2 = ReplicatedStorage:FindFirstChild("HD Admin")

local function getHDAdminV2ClientUser()
	local ok, clientUser = pcall(function()
		return require(hdAdminV2.Core.MainModule.Value.Modules.References.clientUser)
	end)
	if ok and type(clientUser) == "table" and type(clientUser.everyone) == "table" then
		return clientUser
	end
	warn("[coolui] couldn't read HD Admin v2: " .. tostring(clientUser))
	return nil
end

local function anyPlayerHasAttributeRank()
	for _, plr in ipairs(Players:GetPlayers()) do
		if type(plr:GetAttribute("AdminRank")) == "number" then
			return true
		end
	end
	return false
end

if classicHD then
	local Signals = classicHD:WaitForChild("Signals")

	-- Fetch the master rank list once
	-- (pcall so a failed server call can't kill the script after the world was cleared)
	local rankMap = {}
	local gotRanks, ranksInfo = pcall(function()
		return Signals:WaitForChild("RetrieveRanksInfo", 5):InvokeServer()
	end)
	if gotRanks and type(ranksInfo) == "table" and ranksInfo["Ranks"] then
		for _, rankData in pairs(ranksInfo["Ranks"]) do
			rankMap[rankData[1]] = rankData[2]
		end
	else
		warn("[coolui] couldn't fetch HD Admin ranks: " .. tostring(ranksInfo))
	end

	fetchRanks = function()
		local ranks = {}
		local ok, serverRanks = pcall(function()
			return Signals:WaitForChild("RetrieveServerRanks", 5):InvokeServer()
		end)
		if not ok or type(serverRanks) ~= "table" then
			error("HD Admin didn't return server ranks: " .. tostring(serverRanks))
		end
		for _, playerData in pairs(serverRanks) do
			local plr = playerData["Player"]
			local rankId = playerData["RankId"]
			if typeof(plr) == "Instance" and rankId ~= nil then
				ranks[plr] = {
					name = rankMap[rankId] or "NonAdmin",
					level = tonumber(rankId) or 0,
				}
			end
		end
		return ranks
	end
elseif hdAdminV2 and getHDAdminV2ClientUser() then
	local clientUser = getHDAdminV2ClientUser() -- require() is cached, so this is cheap

	fetchRanks = function()
		local ranks = {}
		local okInfo, roleInfo = clientUser.everyone:fetchAsync("RoleInfo")
		local okMembers, members = clientUser.everyone:fetchAsync("ServerMembers")
		if not okInfo or type(roleInfo) ~= "table" or not okMembers or type(members) ~= "table" then
			error("HD Admin v2 didn't return role data")
		end

		for _, plr in ipairs(Players:GetPlayers()) do
			local member = members[plr.UserId] or members[tostring(plr.UserId)]
			if type(member) == "table" then
				-- A player can hold several roles; show the highest visible one
				local best = nil
				for _, list in ipairs({member.roleKeys or {}, member.permanentRoleKeys or {}}) do
					for _, key in ipairs(list) do
						local role = roleInfo[key]
						if type(role) == "table" and not role.internal and not role.hide
							and (best == nil or (role.rank or 0) > (best.rank or 0)) then
							best = role
						end
					end
				end
				-- Rank 1 is the default "Player" role everyone gets, so skip it
				if best and (best.rank or 0) > 1 then
					ranks[plr] = {
						name = best.name or best.key or "?",
						level = best.rank or 0,
						color = if typeof(best.color) == "Color3" then best.color else nil,
					}
				end
			end
		end
		return ranks
	end
elseif anyPlayerHasAttributeRank() then
	fetchRanks = function()
		local ranks = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			local level = plr:GetAttribute("AdminRank")
			if type(level) == "number" then
				ranks[plr] = {
					name = attributeRankName(level),
					level = level,
				}
			end
		end
		return ranks
	end
end

local rowPopTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- smooth, no bounce
local refreshing = false
local refreshQueued = false

-- Rebuilds the list. Returns how many admins are shown, or nil if it
-- couldn't refresh. animate = pop the rows in (used for manual refreshes).
local function refreshRankList(animate)
	if not fetchRanks then return nil end
	if refreshing then
		refreshQueued = true
		return nil
	end
	refreshing = true
	local ok, ranks = pcall(fetchRanks)
	refreshing = false
	if refreshQueued then
		-- Something asked for a refresh while we were busy; run it next
		refreshQueued = false
		task.defer(refreshRankList, false)
	end
	-- The UI may have closed while we were waiting on the server
	if not ScreenGui.Parent then return nil end
	if not ok then
		warn("[coolui] rank refresh failed: " .. tostring(ranks))
		return nil
	end

	for _, child in ipairs(Playerslist:GetChildren()) do
		if child:IsA("ImageButton") then
			child:Destroy()
		end
	end

	local shown = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local rank = ranks[plr]
		if rank and rank.name ~= "NonAdmin" then
			local row = DaniBoyNov2014:Clone()
			row.Name = plr.Name
			-- Highest ranks at the top (x100 because LayoutOrder is a whole
			-- number and custom roles use ranks like 1.1)
			row.LayoutOrder = -math.floor(rank.level * 100)
			row.profile.Image = "rbxthumb://type=AvatarHeadShot&id=" .. plr.UserId .. "&w=420&h=420"
			row.profile.Visible = true
			row.display.Text = plr.DisplayName
			local roleLabel = row.roleBG.role
			roleLabel.Text = rank.name
			if rank.color then
				roleLabel.TextColor3 = rank.color:Lerp(Color3.new(1, 1, 1), 0.35)
				roleLabel.BackgroundColor3 = rank.color:Lerp(Color3.new(0, 0, 0), 0.72)
			end
			row.Parent = Playerslist
			table.insert(shown, row)
		end
	end

	if animate then
		-- Pop rows in top to bottom so a refresh is easy to see
		table.sort(shown, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i, row in ipairs(shown) do
			local scale = row.popScale
			scale.Scale = 0.92
			task.delay((i - 1) * 0.04, function()
				-- A newer refresh may have replaced this row already
				if scale.Parent then
					TweenService:Create(scale, rowPopTweenInfo, {Scale = 1}):Play()
				end
			end)
		end
	end

	return #shown
end

-- Refresh button: click effect + status text so you can tell it worked
local refreshLabel = add1:FindFirstChildOfClass("TextLabel")
local REFRESH_IDLE_TEXT = refreshLabel.Text
local REFRESH_IDLE_COLOR = refreshLabel.TextColor3
local refreshFeedbackId = 0

local function setRefreshStatus(text, color)
	refreshLabel.Text = text
	refreshLabel.TextColor3 = color or REFRESH_IDLE_COLOR
end

local function onRefreshClicked()
	if refreshing then return end
	refreshFeedbackId += 1
	local myId = refreshFeedbackId
	setRefreshStatus("Refreshing...")

	local started = os.clock()
	local count = refreshRankList(true)
	-- Keep "Refreshing..." up long enough to read, even when it's instant
	local elapsed = os.clock() - started
	if elapsed < 0.35 then
		task.wait(0.35 - elapsed)
	end
	if not ScreenGui.Parent or refreshFeedbackId ~= myId then return end

	if count == nil then
		setRefreshStatus("Couldn't refresh", Color3.fromRGB(255, 120, 120))
	elseif count == 0 then
		setRefreshStatus("No admins in server", Color3.fromRGB(255, 210, 120))
	else
		setRefreshStatus("Updated: " .. count .. (if count == 1 then " admin" else " admins"), Color3.fromRGB(140, 255, 170))
	end
	task.delay(1.6, function()
		if refreshFeedbackId == myId and ScreenGui.Parent then
			setRefreshStatus(REFRESH_IDLE_TEXT)
		end
	end)
end

if fetchRanks then
	addButtonEffects(add1, Color3.fromRGB(0, 76, 255), Color3.fromRGB(0, 96, 255))
	-- Fill the list right away, then keep it current
	task.spawn(refreshRankList, false)
	add1.MouseButton1Click:Connect(onRefreshClicked)
	table.insert(rankListConnections, Players.PlayerAdded:Connect(function()
		-- The server can take a few seconds to hand a new player their rank,
		-- so check soon and then once more a bit later
		task.wait(1)
		refreshRankList(false)
		task.wait(4)
		refreshRankList(false)
	end))
	table.insert(rankListConnections, Players.PlayerRemoving:Connect(function()
		-- Wait until the leaving player is out of GetPlayers()
		task.delay(0.5, refreshRankList, false)
	end))
else
	task.spawn(function()
		Header_Side2.Text = "HD Admin wasn't found, closing panel..."
		task.wait(12)
		-- Skip if the whole UI was already closed
		if not ScreenGui.Parent or not Onboarding.Visible then return end
		-- Take it out of the shared list first so the main close skips it
		table.remove(popWindows, table.find(popWindows, rankWindow))
		popClose({rankWindow})
		rankWindow.host:Destroy()
		rankWindow.shadow:Destroy()
		-- Glide the remaining window to the center
		local glide = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		TweenService:Create(loaderWindow.host, glide, {Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
		TweenService:Create(ShadowImage, glide, {Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
	end)
end


-- Spinner Animation Loop
local isSpinning = true
task.spawn(function()
	while isSpinning do
		if not Spinner or not Spinner.Parent then break end
		Spinner.Rotation = Spinner.Rotation + 2
		task.wait()
	end
end)

-- ==========================================
-- 4. START CAMERA SWAY
-- ==========================================
local SENSITIVITY = 0.0003 
local SMOOTHNESS = 0.05    

camera.CameraType = Enum.CameraType.Scriptable

local function updateCameraSway()
	if not campart then return end
	local centerScreenX = camera.ViewportSize.X / 2
	local centerScreenY = camera.ViewportSize.Y / 2
	local offsetAngleX = (mouse.X - centerScreenX) * SENSITIVITY
	local offsetAngleY = (mouse.Y - centerScreenY) * SENSITIVITY
	local targetCFrame = campart.CFrame * CFrame.Angles(-offsetAngleY, -offsetAngleX, 0)
	camera.CFrame = camera.CFrame:Lerp(targetCFrame, SMOOTHNESS)
end

RunService:BindToRenderStep("CustomCameraSway", Enum.RenderPriority.Camera.Value + 1, updateCameraSway)

-- ==========================================
-- MACOS LOADER (Tahoe-style lock screen)
-- ==========================================
-- Optional: a direct link to a wallpaper image (.png or .jpg). Leave empty to
-- use the built-in recreation of the Tahoe wallpaper.
local MACOS_WALLPAPER_URL = ""
-- Password that unlocks the lock screen. Leave empty to accept any password.
local MACOS_PASSWORD = ""

local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")

local MACOS_FOLDER = "coolui_assets"
-- Roboto is the closest Roblox font to Apple's San Francisco
local MACOS_FONT = "rbxasset://fonts/families/Roboto.json"
local MACOS_ICONS = {
	wifi = "rbxassetid://103207294085786", -- full signal
	wifi2 = "rbxassetid://129119142020935", -- 2 bars
	wifi1 = "rbxassetid://72640587060825", -- 1 bar
	wifi0 = "rbxassetid://75345813057180", -- no bars
	wifiOff = "rbxassetid://78076709917160", -- off, or not connected
	ethernet = "rbxassetid://89943686239470",
	batteryUnknown = "rbxassetid://114344327318728",
	submit = "rbxassetid://10709768226", -- Lucide "arrow-right-circle"
	wallpaper = "rbxassetid://10723415040", -- Lucide "image"
	scene = "rbxassetid://10734897956", -- Lucide "mountain"
}
local macFadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Lock screen background: "wallpaper" (the Tahoe recreation) or "scene" (the
-- live 3D scene with the mouse-driven camera). The last choice is remembered.
local MAC_BACKGROUND_FILE = "coolui_assets/lockscreen_background.txt"
local function loadMacBackgroundChoice()
	local ok, value = pcall(function()
		return if isfile(MAC_BACKGROUND_FILE) then readfile(MAC_BACKGROUND_FILE) else nil
	end)
	return if ok and value == "scene" then "scene" else "wallpaper"
end
local function saveMacBackgroundChoice(mode)
	pcall(function()
		if not isfolder("coolui_assets") then
			makefolder("coolui_assets")
		end
		writefile(MAC_BACKGROUND_FILE, mode)
	end)
end

local function macFont(weight)
	return Font.new(MACOS_FONT, weight)
end

-- ---------- Wi-Fi and battery status ----------
-- Roblox can't see the computer's real network or battery. The "Wi-Fi
-- network" is the game you're in, its signal bars follow your ping to the
-- server, and the battery shows as unknown. The Wi-Fi switch is just for
-- show: with it off you're "on Ethernet", since the game is still connected.
local macNetwork = {wifiOn = true, gameName = nil, listeners = {}}
task.spawn(function()
	local ok, info = pcall(function()
		return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
	end)
	macNetwork.gameName = if ok and type(info) == "table" and info.Name and info.Name ~= "" then info.Name else nil
end)

local function macGameName()
	return macNetwork.gameName or "Roblox"
end

-- {wifiOn, connected, ping (ms or nil), bars (0-3)}
local function macReadNetwork()
	local connected = true
	pcall(function()
		connected = game:GetService("NetworkClient"):FindFirstChildOfClass("ClientReplicator") ~= nil
	end)
	local ping = nil
	local ok, seconds = pcall(function()
		return player:GetNetworkPing()
	end)
	if ok and type(seconds) == "number" then
		ping = math.round(seconds * 1000)
	end
	local bars = 0
	if ping then
		bars = if ping <= 120 then 3 elseif ping <= 250 then 2 elseif ping <= 500 then 1 else 0
	end
	return {wifiOn = macNetwork.wifiOn, connected = connected, ping = ping, bars = bars}
end

local function macWifiIcon(state)
	if not state.wifiOn or not state.connected then
		return MACOS_ICONS.wifiOff
	end
	return ({[0] = MACOS_ICONS.wifi0, MACOS_ICONS.wifi1, MACOS_ICONS.wifi2, MACOS_ICONS.wifi})[state.bars]
end

-- fn() runs when the Wi-Fi switch changes; returns a function that stops it
local function macOnNetwork(fn)
	table.insert(macNetwork.listeners, fn)
	return function()
		local i = table.find(macNetwork.listeners, fn)
		if i then
			table.remove(macNetwork.listeners, i)
		end
	end
end

local function macSetWifi(on)
	if macNetwork.wifiOn == on then
		return
	end
	macNetwork.wifiOn = on
	for _, fn in ipairs(table.clone(macNetwork.listeners)) do
		task.spawn(fn)
	end
end

-- The Wi-Fi icon, filling `holder`: the lit bars over a faint full icon, so
-- unlit bars show greyed out like on a Mac. set(state, showEthernet) updates
-- it; with showEthernet, Wi-Fi off but still connected shows Ethernet.
local function macWifiGlyph(holder, color)
	local back = Instance.new("ImageLabel")
	back.BackgroundTransparency = 1
	back.Size = UDim2.fromScale(1, 1)
	back.Image = MACOS_ICONS.wifi
	back.ImageColor3 = color
	back.ImageTransparency = 0.68
	back.Parent = holder
	local front = back:Clone()
	front.ImageTransparency = 0
	front.Parent = holder
	local glyph = {}
	function glyph.set(state, showEthernet)
		local ethernet = showEthernet and not state.wifiOn and state.connected
		front.Image = if ethernet then MACOS_ICONS.ethernet else macWifiIcon(state)
		back.Visible = not ethernet and state.wifiOn and state.connected and state.bars < 3
	end
	function glyph.setColor(value)
		back.ImageColor3 = value
		front.ImageColor3 = value
	end
	glyph.set(macReadNetwork())
	return glyph
end


-- ---------- Soft glow image, generated as a PNG at runtime ----------
-- Roblox has no radial gradients, so the wallpaper's soft shapes use this
-- white-to-transparent circle, tinted and stretched.
local MAC_CRC_TABLE = {}
for i = 0, 255 do
	local c = i
	for _ = 1, 8 do
		if bit32.band(c, 1) == 1 then
			c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
		else
			c = bit32.rshift(c, 1)
		end
	end
	MAC_CRC_TABLE[i] = c
end

local function macCrc32(s)
	local c = 0xFFFFFFFF
	for i = 1, #s do
		c = bit32.bxor(MAC_CRC_TABLE[bit32.band(bit32.bxor(c, s:byte(i)), 0xFF)], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function macAdler32(s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return b * 65536 + a
end

local function macPngChunk(kind, data)
	return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", macCrc32(kind .. data))
end

-- PNG from raw scanlines (each row already starts with its filter byte).
-- The image data is stored uncompressed: no deflate needed, just framing.
local function macMakePng(width, height, colorType, raw)
	local parts = {"\120\1"} -- zlib header
	local pos, total = 1, #raw
	repeat
		local len = math.min(65535, total - pos + 1)
		local final = pos + len > total
		table.insert(parts, (if final then "\1" else "\0") .. string.pack("<I2<I2", len, bit32.bxor(len, 0xFFFF)))
		table.insert(parts, string.sub(raw, pos, pos + len - 1))
		pos += len
	until final
	table.insert(parts, string.pack(">I4", macAdler32(raw)))
	return "\137PNG\r\n\26\n"
		.. macPngChunk("IHDR", string.pack(">I4>I4", width, height) .. string.char(8, colorType, 0, 0, 0))
		.. macPngChunk("IDAT", table.concat(parts))
		.. macPngChunk("IEND", "")
end

local function makeGlowPng(size)
	local rows = table.create(size)
	for y = 0, size - 1 do
		local row = table.create(size + 1)
		row[1] = "\0" -- PNG filter type: none
		for x = 0, size - 1 do
			local dx = (x + 0.5) / size * 2 - 1
			local dy = (y + 0.5) / size * 2 - 1
			local t = 1 - math.min(1, math.sqrt(dx * dx + dy * dy))
			local alpha = math.floor(255 * t * t * (3 - 2 * t) + 0.5) -- smoothstep falloff
			row[#row + 1] = "\255" .. string.char(alpha)
		end
		rows[y + 1] = table.concat(row)
	end
	return macMakePng(size, size, 4, table.concat(rows)) -- 4 = gray + alpha
end

local function ensureMacFolder()
	if not isfolder(MACOS_FOLDER) then
		makefolder(MACOS_FOLDER)
	end
end

local function getMacGlowAsset()
	local path = MACOS_FOLDER .. "/softglow.png"
	if not isfile(path) then
		ensureMacFolder()
		writefile(path, makeGlowPng(128))
	end
	return getcustomasset(path)
end

local function getMacWallpaperAsset()
	if MACOS_WALLPAPER_URL == "" then
		return nil
	end
	local ext = if MACOS_WALLPAPER_URL:lower():match("%.jpe?g") then "jpg" else "png"
	local path = MACOS_FOLDER .. "/wallpaper." .. ext
	local urlPath = MACOS_FOLDER .. "/wallpaper_url.txt"
	-- Re-download only when the link changes
	if not (isfile(path) and isfile(urlPath) and readfile(urlPath) == MACOS_WALLPAPER_URL) then
		local data = game:HttpGet(MACOS_WALLPAPER_URL)
		if #data < 1024 then
			error("wallpaper download looks broken (" .. #data .. " bytes)")
		end
		ensureMacFolder()
		writefile(path, data)
		writefile(urlPath, MACOS_WALLPAPER_URL)
	end
	return getcustomasset(path)
end

-- ---------- Wallpaper ----------
-- Recreates the look of the Tahoe wallpaper: a blue-to-beige sky with a big
-- blue glass wave sweeping from the bottom-left to the top-right. Everything
-- is described by this one table, which both builds the UI and powers
-- macWallpaperSampler (the exact color at any pixel, used by Liquid Glass).
local MAC_WALL = {
	-- Top-to-bottom sky gradient
	sky = {
		{0, Color3.fromRGB(100, 155, 215)}, {0.22, Color3.fromRGB(160, 170, 204)}, {0.4, Color3.fromRGB(212, 200, 160)},
		{0.75, Color3.fromRGB(206, 200, 166)}, {1, Color3.fromRGB(175, 196, 212)},
	},
	-- Soft glows {centerX, centerY, width, height (screen scale), color, transparency, rotation}
	skyGlows = {
		{0.07, 0.55, 0.5, 0.22, Color3.fromRGB(30, 150, 205), 0.05, -6}, -- teal hill
		{0.05, 0.68, 0.55, 0.15, Color3.fromRGB(35, 108, 215), 0.2, -4},
	},
	-- The wave is the inside of a huge circle off the bottom-right corner,
	-- fitted to the wave edge in the reference (sizes in screen heights)
	wave = {centerX = 4.139, centerY = 5.257, radius = 6.0, color = Color3.fromRGB(22, 92, 220)},
	waveGlows = {
		{0.63, 0.6, 0.55, 0.75, Color3.fromRGB(100, 170, 235), 0.35, -25}, -- light hump in the middle
		{0.93, 0.82, 0.42, 1.1, Color3.fromRGB(200, 214, 225), 0, -32}, -- pale shape, bottom-right
		{0.22, 1.03, 0.62, 0.42, Color3.fromRGB(175, 200, 222), 0, 8}, -- pale shape, bottom-left
		{0.86, 0.1, 0.62, 0.17, Color3.fromRGB(150, 215, 215), 0.2, -22}, -- cyan streak, top-right
		{0.97, 0.3, 0.42, 0.17, Color3.fromRGB(85, 175, 230), 0.3, -25},
		{0.47, 0.45, 0.45, 0.22, Color3.fromRGB(10, 60, 200), 0.45, -38}, -- deep blue along the edge
	},
	-- Rings around the wave's edge, bottom to top: start this far inside the
	-- edge and run outward for `thickness` (screen heights)
	rings = {
		{inset = 0.024, thickness = 0.016, color = Color3.fromRGB(10, 65, 205), transparency = 0.5}, -- deep band
		{inset = 0.006, thickness = 0.006, color = Color3.fromRGB(70, 145, 235), transparency = 0.35}, -- edge light
		{inset = 0, thickness = 0.0024, color = Color3.fromRGB(232, 243, 255), transparency = 0.1}, -- bright glass rim
	},
}

-- `offsetScale` (optional): a function giving the UIScale the wallpaper sits
-- under, for small previews inside the scaled desktop
local function buildMacWallpaper(parent, glowId, imageId, offsetScale)
	local wall = Instance.new("Frame")
	wall.Name = "Wallpaper"
	wall.Size = UDim2.fromScale(1, 1)
	wall.BackgroundColor3 = Color3.new(1, 1, 1)
	wall.BorderSizePixel = 0
	wall.ClipsDescendants = true
	wall.Parent = parent

	if imageId then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Crop
		image.Image = imageId
		image.Parent = wall
		return wall
	end

	local skyKeypoints = {}
	for _, p in ipairs(MAC_WALL.sky) do
		table.insert(skyKeypoints, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	local skyGradient = Instance.new("UIGradient")
	skyGradient.Rotation = 90
	skyGradient.Color = ColorSequence.new(skyKeypoints)
	skyGradient.Parent = wall

	local function glow(zIndex, spec)
		if not glowId then return end
		local g = Instance.new("ImageLabel")
		g.BackgroundTransparency = 1
		g.Image = glowId
		g.ImageColor3 = spec[5]
		g.ImageTransparency = spec[6]
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(spec[1], spec[2])
		g.Size = UDim2.fromScale(spec[3], spec[4])
		g.Rotation = spec[7] or 0
		g.ZIndex = zIndex
		g.Parent = wall
	end
	local function circle(name, zIndex)
		local c = Instance.new("Frame")
		c.Name = name
		c.BorderSizePixel = 0
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.ZIndex = zIndex
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = c
		c.Parent = wall
		return c
	end

	for _, spec in ipairs(MAC_WALL.skyGlows) do
		glow(1, spec)
	end
	local wave = circle("Wave", 2)
	wave.BackgroundColor3 = MAC_WALL.wave.color
	for _, spec in ipairs(MAC_WALL.waveGlows) do
		glow(3, spec)
	end
	local rings = {}
	for i, spec in ipairs(MAC_WALL.rings) do
		local ring = circle("Ring" .. i, 3 + i)
		ring.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = spec.color
		stroke.Transparency = spec.transparency
		pcall(function()
			stroke.BorderStrokePosition = Enum.BorderStrokePosition.Outer -- grows outward from the circle
		end)
		stroke.Parent = ring
		rings[i] = {frame = ring, stroke = stroke, spec = spec}
	end

	local w = MAC_WALL.wave
	local function layout()
		local h = wall.AbsoluteSize.Y / (if offsetScale then offsetScale() else 1)
		local center = UDim2.fromOffset(w.centerX * h, w.centerY * h)
		wave.Size = UDim2.fromOffset(2 * w.radius * h, 2 * w.radius * h)
		wave.Position = center
		for _, ring in ipairs(rings) do
			local radius = (w.radius - ring.spec.inset) * h
			ring.frame.Size = UDim2.fromOffset(2 * radius, 2 * radius)
			ring.frame.Position = center
			ring.stroke.Thickness = math.max(1, ring.spec.thickness * h)
		end
	end
	layout()
	wall:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	return wall
end

-- Returns a function (x, y) -> r, g, b (0-1) giving the wallpaper's color at
-- a pixel, for a wallpaper of size width x height. Mirrors buildMacWallpaper.
local function macWallpaperSampler(width, height)
	local function prepGlows(list)
		local prepared = {}
		for _, spec in ipairs(list) do
			local rotation = math.rad(spec[7] or 0)
			table.insert(prepared, {
				x = spec[1] * width, y = spec[2] * height,
				invHalfW = 2 / (spec[3] * width), invHalfH = 2 / (spec[4] * height),
				cos = math.cos(rotation), sin = math.sin(rotation),
				r = spec[5].R, g = spec[5].G, b = spec[5].B,
				alpha = 1 - spec[6],
			})
		end
		return prepared
	end
	local skyGlows, waveGlows = prepGlows(MAC_WALL.skyGlows), prepGlows(MAC_WALL.waveGlows)
	local sky = MAC_WALL.sky
	local w = MAC_WALL.wave
	local waveX, waveY, waveRadius = w.centerX * height, w.centerY * height, w.radius * height
	local waveR, waveG, waveB = w.color.R, w.color.G, w.color.B
	local rings = {}
	for _, spec in ipairs(MAC_WALL.rings) do
		local inner = (w.radius - spec.inset) * height
		table.insert(rings, {
			inner = inner, outer = inner + math.max(1, spec.thickness * height),
			r = spec.color.R, g = spec.color.G, b = spec.color.B, alpha = 1 - spec.transparency,
		})
	end

	local function blendGlows(list, x, y, r, g, b)
		for _, glow in ipairs(list) do
			local dx, dy = x - glow.x, y - glow.y
			local u = (dx * glow.cos + dy * glow.sin) * glow.invHalfW
			local v = (dy * glow.cos - dx * glow.sin) * glow.invHalfH
			local d2 = u * u + v * v
			if d2 < 1 then
				local t = 1 - math.sqrt(d2)
				local a = t * t * (3 - 2 * t) * glow.alpha
				r += (glow.r - r) * a
				g += (glow.g - g) * a
				b += (glow.b - b) * a
			end
		end
		return r, g, b
	end

	return function(x, y)
		local t = math.clamp(y / height, 0, 1)
		local r, g, b
		for i = 2, #sky do
			if t <= sky[i][1] or i == #sky then
				local a, c = sky[i - 1], sky[i]
				local f = math.clamp((t - a[1]) / (c[1] - a[1]), 0, 1)
				r = a[2].R + (c[2].R - a[2].R) * f
				g = a[2].G + (c[2].G - a[2].G) * f
				b = a[2].B + (c[2].B - a[2].B) * f
				break
			end
		end
		r, g, b = blendGlows(skyGlows, x, y, r, g, b)
		local dx, dy = x - waveX, y - waveY
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist <= waveRadius then
			r, g, b = waveR, waveG, waveB
		end
		r, g, b = blendGlows(waveGlows, x, y, r, g, b)
		for _, ring in ipairs(rings) do
			if dist >= ring.inner and dist <= ring.outer then
				r += (ring.r - r) * ring.alpha
				g += (ring.g - g) * ring.alpha
				b += (ring.b - b) * ring.alpha
			end
		end
		return r, g, b
	end
end

-- ---------- Liquid Glass ----------
-- Apple's Liquid Glass: a rim that bends and magnifies what's behind it (with
-- color fringing), a lightly frosted interior, and a bright fresnel rim with
-- glare glints. The math follows boatbomber's GlassmorphicUI (MPL-2.0,
-- github.com/boatbomber/GlassmorphicUI). GlassmorphicUI re-samples the screen
-- and re-renders every frame; here the backdrop is our own wallpaper, so each
-- glass shape is rendered once into a PNG and then costs nothing per frame.
-- Works for rounded frames (bakeMacGlass) and for text (the clock digits).
local MAC_GLASS = {
	thickness = 0.35, -- how far the lensing rim reaches in (fraction of the short side)
	refraction = 2.1, -- refractive index; 1 = no bending
	aberration = 0.2, -- color fringing in the rim
	frost = 0.06, -- blur radius (fraction of the short side)
	tint = Color3.new(1, 1, 1),
	tintAlpha = 0.12,
	fresnelSize = 0.1, fresnelHardness = 0.4, fresnelIntensity = 0.25,
	glareSize = 0.2, glareHardness = 0.4, glareIntensity = 0.7,
	glareConvergence = 0.9, glareOpposite = 0.5, glareAngle = -50,
}
-- Glass for text: lengths are fractions of the font size in pixels
local MAC_TEXT_GLASS = {
	thickness = 0.07, refraction = 2.1, aberration = 0.25, frost = 0.04, room = 0.08,
	tint = Color3.new(1, 1, 1), tintAlpha = 0.42,
	fresnelReach = 0.035, fresnelHardness = 0.4, fresnelIntensity = 0.5,
	glareReach = 0.055, glareHardness = 0.4, glareIntensity = 0.9,
	glareConvergence = 0.9, glareOpposite = 0.5, glareAngle = -50,
}
-- Glass for the Wi-Fi and battery menus: the Dock's clear glass, with the
-- lengths scaled down so the rim is about as wide as the Dock's (the menus
-- are about twice as tall), plus a little more frost behind the text
local MAC_MENU_GLASS = {
	thickness = 0.18, refraction = 2.1, aberration = 0.2,
	frost = 0.05,
	tint = Color3.new(1, 1, 1), tintAlpha = 0.12,
	fresnelSize = 0.05, fresnelHardness = 0.4, fresnelIntensity = 0.25,
	glareSize = 0.1, glareHardness = 0.4, glareIntensity = 0.7,
	glareConvergence = 0.9, glareOpposite = 0.5, glareAngle = -50,
}
-- Over the bright 3D sky clear glass all but disappears, so there the menus
-- use the frosted glass macOS gives its menus: a light tint, more blur, and
-- dark text
local MAC_MENU_FROSTED_GLASS = {
	thickness = 0.18, refraction = 2.1, aberration = 0.2,
	frost = 0.1,
	tint = Color3.fromRGB(246, 246, 248), tintAlpha = 0.55,
	fresnelSize = 0.05, fresnelHardness = 0.4, fresnelIntensity = 0.3,
	glareSize = 0.1, glareHardness = 0.4, glareIntensity = 0.6,
	glareConvergence = 0.9, glareOpposite = 0.5, glareAngle = -50,
}
local MAC_GLASS_DISPLACEMENT = 0.05 * math.sqrt(2) * 1000 -- px per unit of bend
local MAC_GLASS_VERSION = 4 -- bump when the look changes so cached images refresh

local macSamplers = {}
local function macSamplerFor(width, height)
	local key = width .. "x" .. height
	macSamplers[key] = macSamplers[key] or macWallpaperSampler(width, height)
	return macSamplers[key]
end

-- The optics of one glass pixel, shared by the baked glass and the live glass
-- on the 3D scene. Returns optics(depth, nx, ny, reach) -> bend, light:
-- how far (px) the rim shifts what's seen through it, and how much rim light
-- (fresnel glow plus glare glints, 0-1) it catches. `depth` is how deep the
-- pixel is inside the shape, (nx, ny) its outward normal, and `reach` how far
-- a fetch may go (see p.reach). `p` holds pixel lengths (see macRoundedRectGlass).
local function macGlassOptics(p)
	local invRefraction = 1 / p.refraction
	local thickness = p.thickness
	local function edgeFactor(depth)
		if depth < 0 or depth >= thickness then
			return 0
		end
		local x = 1 - depth / thickness
		local sinI = x * x
		return math.tan(math.asin(sinI) - math.asin(sinI * invRefraction))
	end
	local maxScale = edgeFactor(0) * MAC_GLASS_DISPLACEMENT
	local function rimFactor(depth, k, hardness)
		local base = 1 + hardness - depth * k
		if base <= 0 then
			return 0
		end
		local b2 = base * base
		return math.min(b2 * b2 * base, 1)
	end
	local glareExponent = 0.1 + p.glareConvergence * 2
	local glareBias = math.rad(p.glareAngle) - math.pi / 4
	return function(depth, nx, ny, reach)
		local scale = edgeFactor(depth) * MAC_GLASS_DISPLACEMENT
		if maxScale > reach then
			scale = scale * math.max(0, reach) / maxScale
		end
		local wf = if p.fresnelK then rimFactor(depth, p.fresnelK, p.fresnelHardness) * p.fresnelIntensity * 0.7 else 0
		local wg = 0
		if p.glareK and (nx ~= 0 or ny ~= 0) then
			local geo = rimFactor(depth, p.glareK, p.glareHardness)
			if geo > 0 then
				local angle = math.atan2(-ny, nx)
				if angle < 0 then
					angle += 2 * math.pi
				end
				local a = (angle + glareBias) * 2
				local farside = (a > 1.5 * math.pi and a < 3.5 * math.pi) or a < -0.5 * math.pi
				local af = (0.5 + math.sin(a) * 0.5) * 1.2 * (if farside then p.glareOpposite else 1) * p.glareIntensity
				wg = math.clamp(af ^ glareExponent, 0, 1) * geo
			end
		end
		return scale, wf + wg - wf * wg
	end
end

-- The shared glass shader. `shapeAt(px, py)` gives, for pixel (px, py) of the
-- w x h image, how deep inside the shape it is (negative outside) and the
-- outward surface normal. `p` holds pixel lengths (see the wrappers below).
-- Returns the PNG file contents.
local function renderMacGlass(x0, y0, w, h, shapeAt, sample, p)
	local optics = macGlassOptics(p)
	local tintR, tintG, tintB = p.tint.R * p.tintAlpha, p.tint.G * p.tintAlpha, p.tint.B * p.tintAlpha
	local keep = 1 - p.tintAlpha

	-- Backdrop grid over the shape (plus room for the blur), sampled once and
	-- frosted with a separable gaussian
	local blurRadius = math.max(1, p.blur)
	local step = p.step
	local margin = math.ceil(blurRadius) + 2 * step
	local gridX, gridY = x0 - margin, y0 - margin
	local gridW = math.ceil((w + 2 * margin) / step) + 1
	local gridH = math.ceil((h + 2 * margin) / step) + 1
	local channels = {table.create(gridW * gridH), table.create(gridW * gridH), table.create(gridW * gridH)}
	for j = 0, gridH - 1 do
		for i = 0, gridW - 1 do
			local r, g, b = sample(gridX + i * step, gridY + j * step)
			local index = j * gridW + i + 1
			channels[1][index], channels[2][index], channels[3][index] = r, g, b
		end
	end
	local sigma = blurRadius / 3 / step
	if sigma > 0.3 then
		local kernelRadius = math.ceil(sigma * 3)
		local weights, total = {}, 0
		for k = -kernelRadius, kernelRadius do
			local weight = math.exp(-(k * k) / (2 * sigma * sigma))
			weights[k] = weight
			total += weight
		end
		for k = -kernelRadius, kernelRadius do
			weights[k] /= total
		end
		for c = 1, 3 do
			local src, tmp = channels[c], table.create(gridW * gridH)
			for j = 0, gridH - 1 do
				for i = 0, gridW - 1 do
					local sum = 0
					for k = -kernelRadius, kernelRadius do
						sum += src[j * gridW + math.clamp(i + k, 0, gridW - 1) + 1] * weights[k]
					end
					tmp[j * gridW + i + 1] = sum
				end
			end
			for j = 0, gridH - 1 do
				for i = 0, gridW - 1 do
					local sum = 0
					for k = -kernelRadius, kernelRadius do
						sum += tmp[math.clamp(j + k, 0, gridH - 1) * gridW + i + 1] * weights[k]
					end
					src[j * gridW + i + 1] = sum
				end
			end
		end
	end
	-- Bilinear read of one channel from the frosted grid at a screen position
	local function fetch(channel, x, y)
		local fx = math.clamp((x - gridX) / step, 0, gridW - 1.001)
		local fy = math.clamp((y - gridY) / step, 0, gridH - 1.001)
		local ix, iy = math.floor(fx), math.floor(fy)
		local tx, ty = fx - ix, fy - iy
		local data = channels[channel]
		local i00 = iy * gridW + ix + 1
		local top = data[i00] + (data[i00 + 1] - data[i00]) * tx
		local bottom = data[i00 + gridW] + (data[i00 + gridW + 1] - data[i00 + gridW]) * tx
		return top + (bottom - top) * ty
	end

	local aberrationR, aberrationB = 1 + p.aberration, 1 - p.aberration
	local rows = table.create(h)
	local char, floor = string.char, math.floor
	for py = 0, h - 1 do
		local row = table.create(w + 1)
		row[1] = "\0"
		for px = 0, w - 1 do
			local depth, nx, ny = shapeAt(px, py)
			local coverage = math.clamp(depth + 0.5, 0, 1)
			if coverage <= 0 then
				row[px + 2] = "\255\255\255\0"
			else
				-- Refraction: rim pixels show content from further inside
				local scale, white = optics(depth, nx, ny, p.reach(px, py, nx, ny))
				local x, y = x0 + px + 0.5, y0 + py + 0.5
				local r, g, b
				if scale > 0 then
					local dx, dy = -nx * scale, -ny * scale
					r = fetch(1, x + dx * aberrationR, y + dy * aberrationR)
					g = fetch(2, x + dx, y + dy)
					b = fetch(3, x + dx * aberrationB, y + dy * aberrationB)
				else
					r, g, b = fetch(1, x, y), fetch(2, x, y), fetch(3, x, y)
				end
				r, g, b = r * keep + tintR, g * keep + tintG, b * keep + tintB
				-- Rim light: fresnel glow plus two glare glints, mixed toward white
				r, g, b = r + (1 - r) * white, g + (1 - g) * white, b + (1 - b) * white
				row[px + 2] = char(
					floor(math.clamp(r, 0, 1) * 255 + 0.5),
					floor(math.clamp(g, 0, 1) * 255 + 0.5),
					floor(math.clamp(b, 0, 1) * 255 + 0.5),
					floor(coverage * 255 + 0.5)
				)
			end
		end
		rows[py + 1] = table.concat(row)
	end
	return macMakePng(w, h, 6, table.concat(rows)) -- 6 = RGBA
end

-- Shape and pixel lengths of a w x h rounded-rect glass (a pill by default):
-- returns shapeAt, p for renderMacGlass / macGlassOptics
local function macRoundedRectGlass(w, h, opts)
	local minAxis = math.min(w, h)
	local halfMin = minAxis / 2
	local radius = math.min(opts.cornerRadius or halfMin, halfMin)
	local halfW, halfH = w / 2, h / 2
	local innerX, innerY = halfW - radius, halfH - radius
	local room = 0.9 * halfMin
	local function rimK(size)
		return if size > 0 then (500 / size) ^ 2 / 1500 else nil
	end
	return function(px, py)
		local lx, ly = px + 0.5 - halfW, py + 0.5 - halfH
		local sx, sy = if lx < 0 then -1 else 1, if ly < 0 then -1 else 1
		local qx, qy = math.abs(lx) - innerX, math.abs(ly) - innerY
		if qx > 0 and qy > 0 then
			local len = math.sqrt(qx * qx + qy * qy)
			return radius - len, qx / len * sx, qy / len * sy
		elseif qx > qy then
			return radius - qx, sx, 0
		end
		return radius - qy, 0, sy
	end, {
		thickness = math.clamp(opts.thickness * minAxis, 1, minAxis),
		refraction = opts.refraction, aberration = opts.aberration,
		blur = opts.frost * minAxis,
		-- Fine enough that sharp backdrop edges (like the wave's rim) don't stair-step
		step = math.clamp(math.floor(minAxis / 32), 1, 4),
		-- Fetches may reach through the center to `room` beyond it, no further
		reach = function(px, py, nx, ny)
			return (px + 0.5 - halfW) * nx + (py + 0.5 - halfH) * ny + room
		end,
		tint = opts.tint, tintAlpha = opts.tintAlpha,
		fresnelK = rimK(opts.fresnelSize * minAxis), fresnelHardness = opts.fresnelHardness, fresnelIntensity = opts.fresnelIntensity,
		glareK = rimK(opts.glareSize * minAxis), glareHardness = opts.glareHardness, glareIntensity = opts.glareIntensity,
		glareConvergence = opts.glareConvergence, glareOpposite = opts.glareOpposite, glareAngle = opts.glareAngle,
	}
end

-- Glass for a rounded rect (a pill by default) at x0, y0, size w x h
local function renderMacGlassPng(x0, y0, w, h, sample, opts)
	local shapeAt, p = macRoundedRectGlass(w, h, opts or MAC_GLASS)
	return renderMacGlass(x0, y0, w, h, shapeAt, sample, p)
end

-- Just the rim light of a w x h rounded-rect glass, as white with alpha. The
-- live glass on the 3D scene only redraws what's behind it; this sharp layer
-- goes on top. Cached by size, since it doesn't depend on the backdrop.
local function bakeMacGlassRim(name, w, h, opts)
	w, h = math.max(2, math.round(w)), math.max(2, math.round(h))
	local path = string.format("%s/glassrim_v%d_%s_%dx%d_r%d.png", MACOS_FOLDER, MAC_GLASS_VERSION, name, w, h, math.round((opts.cornerRadius or 0) * 10))
	if not isfile(path) then
		local shapeAt, p = macRoundedRectGlass(w, h, opts)
		local optics = macGlassOptics(p)
		local rows = table.create(h)
		for py = 0, h - 1 do
			local row = table.create(w + 1)
			row[1] = "\0"
			for px = 0, w - 1 do
				local depth, nx, ny = shapeAt(px, py)
				local coverage = math.clamp(depth + 0.5, 0, 1)
				local alpha = 0
				if coverage > 0 then
					local _, white = optics(depth, nx, ny, p.reach(px, py, nx, ny))
					alpha = math.floor(white * coverage * 255 + 0.5)
				end
				row[px + 2] = "\255" .. string.char(alpha)
			end
			rows[py + 1] = table.concat(row)
		end
		ensureMacFolder()
		writefile(path, macMakePng(w, h, 4, table.concat(rows))) -- 4 = gray + alpha
	end
	return getcustomasset(path)
end

-- Renders glass for a rect of a width x height wallpaper and returns an asset
-- id for an ImageLabel covering exactly that rect. Use for any frame that sits
-- on the wallpaper.
local function bakeMacGlass(name, x0, y0, w, h, width, height, opts)
	x0, y0, w, h = math.round(x0), math.round(y0), math.max(2, math.round(w)), math.max(2, math.round(h))
	local path = string.format("%s/glass_v%d_%s_%dx%d_%dx%d_%d_%d.png", MACOS_FOLDER, MAC_GLASS_VERSION, name, width, height, w, h, x0, y0)
	if not isfile(path) then
		ensureMacFolder()
		writefile(path, renderMacGlassPng(x0, y0, w, h, macSamplerFor(width, height), opts))
	end
	return getcustomasset(path)
end

-- Where the lock screen's password field sits on a width x height screen
-- (mirrors the field's Position/Size in showMacLockScreen)
local function macPasswordFieldRect(width, height)
	local w, h = 0.17 * height, 0.032 * height
	return width * 0.5 - w / 2, height * 0.946 - h / 2, w, h
end

-- ---------- Liquid Glass text ----------
-- Glass needs each letter's real outline, which TextLabels don't expose. So
-- the clock downloads the open-source Inter Bold font (SIL Open Font License,
-- the closest free match to Apple's SF Pro) and reads the digit outlines
-- straight from the TrueType file.
-- The font comes from the asset repo (assets/fonts/Inter-Bold.ttf); this is the backup
local MACOS_CLOCK_FONT_BACKUP_URL = "https://cdn.jsdelivr.net/fontsource/fonts/inter@latest/latin-700-normal.ttf"
local MAC_CLOCK_CENTER_Y = 0.192 -- clock's vertical center (fraction of screen height)
local MAC_CLOCK_DIGIT_HEIGHT = 0.102 -- digit height (fraction of screen height), as in Tahoe
local macClockFont = nil -- parsed font, loaded by loadMacClockFont

-- Minimal TrueType reader: glyph outlines and advance widths, nothing more
local function parseTrueType(data)
	local function u8(o) return string.byte(data, o + 1) end
	local function i8(o) return (string.unpack(">i1", data, o + 1)) end
	local function u16(o) return (string.unpack(">I2", data, o + 1)) end
	local function i16(o) return (string.unpack(">i2", data, o + 1)) end
	local function u32(o) return (string.unpack(">I4", data, o + 1)) end

	local tables = {}
	for i = 0, u16(4) - 1 do
		local record = 12 + 16 * i
		tables[string.sub(data, record + 1, record + 4)] = u32(record + 8)
	end
	local head, hhea, hmtx = tables.head, tables.hhea, tables.hmtx
	local cmap, loca, glyf = tables.cmap, tables.loca, tables.glyf
	assert(head and hhea and hmtx and cmap and loca and glyf, "not a TrueType font")
	local unitsPerEm = u16(head + 18)
	local longLoca = i16(head + 50) == 1
	local numHMetrics = u16(hhea + 34)

	local format4
	for i = 0, u16(cmap + 2) - 1 do
		local offset = cmap + u32(cmap + 4 + 8 * i + 4)
		if u16(offset) == 4 then
			format4 = offset
			break
		end
	end
	assert(format4, "font has no format 4 character map")
	local segCountX2 = u16(format4 + 6)
	local ends = format4 + 14
	local starts = ends + segCountX2 + 2
	local deltas = starts + segCountX2
	local rangeOffsets = deltas + segCountX2

	local function glyphIndex(code)
		for seg = 0, segCountX2 / 2 - 1 do
			if code <= u16(ends + 2 * seg) then
				local start = u16(starts + 2 * seg)
				if code < start then
					return 0
				end
				local delta = i16(deltas + 2 * seg)
				local rangeOffset = u16(rangeOffsets + 2 * seg)
				if rangeOffset == 0 then
					return (code + delta) % 65536
				end
				local g = u16(rangeOffsets + 2 * seg + rangeOffset + 2 * (code - start))
				return if g == 0 then 0 else (g + delta) % 65536
			end
		end
		return 0
	end

	local function glyphOffsets(g)
		if longLoca then
			return glyf + u32(loca + 4 * g), glyf + u32(loca + 4 * g + 4)
		end
		return glyf + u16(loca + 2 * g) * 2, glyf + u16(loca + 2 * g + 2) * 2
	end

	-- Appends the glyph's contours (lists of {x, y, onCurve}, font units) to `contours`
	local function readGlyph(g, contours, dx, dy, scale, depth)
		local o, finish = glyphOffsets(g)
		if finish <= o or depth > 4 then return end
		local numContours = i16(o)
		if numContours >= 0 then
			local endPoints = {}
			for c = 0, numContours - 1 do
				endPoints[c + 1] = u16(o + 10 + 2 * c)
			end
			local numPoints = (endPoints[numContours] or -1) + 1
			local p = o + 10 + 2 * numContours
			p += 2 + u16(p) -- skip the hinting instructions
			local flags = {}
			while #flags < numPoints do
				local flag = u8(p)
				p += 1
				table.insert(flags, flag)
				if bit32.band(flag, 8) ~= 0 then -- repeated flag
					local count = u8(p)
					p += 1
					for _ = 1, count do
						table.insert(flags, flag)
					end
				end
			end
			local xs, ys = {}, {}
			local v = 0
			for i = 1, numPoints do
				local f = flags[i]
				if bit32.band(f, 2) ~= 0 then
					local b = u8(p)
					p += 1
					v += if bit32.band(f, 16) ~= 0 then b else -b
				elseif bit32.band(f, 16) == 0 then
					v += i16(p)
					p += 2
				end
				xs[i] = v
			end
			v = 0
			for i = 1, numPoints do
				local f = flags[i]
				if bit32.band(f, 4) ~= 0 then
					local b = u8(p)
					p += 1
					v += if bit32.band(f, 32) ~= 0 then b else -b
				elseif bit32.band(f, 32) == 0 then
					v += i16(p)
					p += 2
				end
				ys[i] = v
			end
			local first = 1
			for c = 1, numContours do
				local contour = {}
				for i = first, endPoints[c] + 1 do
					table.insert(contour, {xs[i] * scale + dx, ys[i] * scale + dy, bit32.band(flags[i], 1) ~= 0})
				end
				first = endPoints[c] + 2
				if #contour > 1 then
					table.insert(contours, contour)
				end
			end
		else
			-- Composite glyph (like ":"): place each component (offset + scale)
			local p = o + 10
			repeat
				local flag = u16(p)
				local component = u16(p + 2)
				p += 4
				local a, b
				if bit32.band(flag, 1) ~= 0 then
					a, b = i16(p), i16(p + 2)
					p += 4
				else
					a, b = i8(p), i8(p + 1)
					p += 2
				end
				local s = 1
				if bit32.band(flag, 8) ~= 0 then
					s = i16(p) / 16384
					p += 2
				elseif bit32.band(flag, 64) ~= 0 then
					s = i16(p) / 16384
					p += 4
				elseif bit32.band(flag, 128) ~= 0 then
					s = i16(p) / 16384
					p += 8
				end
				if bit32.band(flag, 2) == 0 then
					a, b = 0, 0 -- point-matched placement isn't supported
				end
				readGlyph(component, contours, dx + a * scale, dy + b * scale, scale * s, depth + 1)
			until bit32.band(flag, 32) == 0
		end
	end

	return {
		unitsPerEm = unitsPerEm,
		-- Returns the character's contours (font units, y up) and advance width
		glyph = function(character)
			local g = glyphIndex(utf8.codepoint(character))
			local contours = {}
			readGlyph(g, contours, 0, 0, 1, 0)
			return contours, u16(hmtx + 4 * math.min(g, numHMetrics - 1))
		end,
	}
end

local function loadMacClockFont()
	if macClockFont then
		return macClockFont
	end
	local path = MACOS_FOLDER .. "/clockfont_inter700.ttf"
	if not isfile(path) then
		local data = downloadAsset({ASSET_BASE_URL .. "fonts/Inter-Bold.ttf", MACOS_CLOCK_FONT_BACKUP_URL}, 10000)
		if string.sub(data, 1, 4) ~= "\0\1\0\0" then
			error("clock font download looks broken (" .. #data .. " bytes)")
		end
		ensureMacFolder()
		writefile(path, data)
	end
	macClockFont = parseTrueType(readfile(path))
	return macClockFont
end

-- Signed-distance field of a glyph at a pixel size: for each pixel, how deep
-- inside the letter it is (negative outside) and the outward normal. Exact
-- within `band` px of the outline (where glass bends light), flat further in.
local function macGlyphField(contours, unitsPerEm, fontPx, band)
	local s = fontPx / unitsPerEm
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, contour in ipairs(contours) do
		for _, pt in ipairs(contour) do
			minX, maxX = math.min(minX, pt[1]), math.max(maxX, pt[1])
			minY, maxY = math.min(minY, pt[2]), math.max(maxY, pt[2])
		end
	end
	if minX == math.huge then
		return nil -- empty glyph (a space)
	end
	local margin = 3
	local w = math.ceil((maxX - minX) * s) + 2 * margin
	local h = math.ceil((maxY - minY) * s) + 2 * margin
	local offX, offY = margin - minX * s, margin + maxY * s -- pixel = (fx * s + offX, offY - fy * s)

	-- Flatten the outline (straight lines + quadratic curves) into segments
	local segments = {}
	local function addSegment(x1, y1, x2, y2)
		if x1 ~= x2 or y1 ~= y2 then
			table.insert(segments, {x1, y1, x2, y2})
		end
	end
	for _, contour in ipairs(contours) do
		local points = {}
		for i, pt in ipairs(contour) do
			points[i] = {pt[1] * s + offX, offY - pt[2] * s, pt[3]}
		end
		-- Two off-curve points in a row imply an on-curve point between them
		local expanded = {}
		local n = #points
		for i = 1, n do
			local current, nextPoint = points[i], points[i % n + 1]
			table.insert(expanded, current)
			if not current[3] and not nextPoint[3] then
				table.insert(expanded, {(current[1] + nextPoint[1]) / 2, (current[2] + nextPoint[2]) / 2, true})
			end
		end
		local m = #expanded
		local start
		for i = 1, m do
			if expanded[i][3] then
				start = i
				break
			end
		end
		if start then
			local i = start
			local x, y = expanded[start][1], expanded[start][2]
			local guard = 0
			repeat
				local j = i % m + 1
				local q = expanded[j]
				if q[3] then
					addSegment(x, y, q[1], q[2])
					x, y, i = q[1], q[2], j
				else
					local k = j % m + 1
					local e = expanded[k]
					local length = math.abs(q[1] - x) + math.abs(q[2] - y) + math.abs(e[1] - q[1]) + math.abs(e[2] - q[2])
					local steps = math.clamp(math.ceil(length / 3), 2, 16)
					local lx, ly = x, y
					for t = 1, steps do
						local u = t / steps
						local a, b, c = (1 - u) * (1 - u), 2 * (1 - u) * u, u * u
						local cx, cy = a * x + b * q[1] + c * e[1], a * y + b * q[2] + c * e[2]
						addSegment(lx, ly, cx, cy)
						lx, ly = cx, cy
					end
					x, y, i = e[1], e[2], k
				end
				guard += 1
			until i == start or guard > m + 2
		end
	end

	-- Nearest outline point for every pixel within `band` of a segment
	local count = w * h
	local best, toX, toY = table.create(count, math.huge), table.create(count, 0), table.create(count, 0)
	for _, sg in ipairs(segments) do
		local x1, y1, x2, y2 = sg[1], sg[2], sg[3], sg[4]
		local ex, ey = x2 - x1, y2 - y1
		local len2 = ex * ex + ey * ey
		local ix0 = math.max(0, math.floor(math.min(x1, x2) - band))
		local ix1 = math.min(w - 1, math.ceil(math.max(x1, x2) + band))
		local iy0 = math.max(0, math.floor(math.min(y1, y2) - band))
		local iy1 = math.min(h - 1, math.ceil(math.max(y1, y2) + band))
		for iy = iy0, iy1 do
			local cy = iy + 0.5
			local rowStart = iy * w + 1
			for ix = ix0, ix1 do
				local cx = ix + 0.5
				local t = ((cx - x1) * ex + (cy - y1) * ey) / len2
				if t < 0 then
					t = 0
				elseif t > 1 then
					t = 1
				end
				local qx, qy = x1 + ex * t - cx, y1 + ey * t - cy
				local d2 = qx * qx + qy * qy
				local index = rowStart + ix
				if d2 < best[index] then
					best[index], toX[index], toY[index] = d2, qx, qy
				end
			end
		end
	end

	-- Inside/outside by scanline (non-zero winding), then signed depth + normal
	local depth, normalX, normalY = table.create(count, 0), table.create(count, 0), table.create(count, 0)
	for iy = 0, h - 1 do
		local cy = iy + 0.5
		local crossings = {}
		for _, sg in ipairs(segments) do
			local y1, y2 = sg[2], sg[4]
			if (y1 <= cy and cy < y2) or (y2 <= cy and cy < y1) then
				table.insert(crossings, {sg[1] + (cy - y1) * (sg[3] - sg[1]) / (y2 - y1), if y2 > y1 then 1 else -1})
			end
		end
		table.sort(crossings, function(a, b)
			return a[1] < b[1]
		end)
		local winding, ci = 0, 1
		for ix = 0, w - 1 do
			local cx = ix + 0.5
			while crossings[ci] and crossings[ci][1] <= cx do
				winding += crossings[ci][2]
				ci += 1
			end
			local index = iy * w + ix + 1
			local inside = winding ~= 0
			local d = math.sqrt(best[index])
			if d == math.huge then
				depth[index] = if inside then band + 1 else -(band + 1)
			else
				depth[index] = if inside then d else -d
				if d > 1e-6 then
					-- toward the outline is outward for inside pixels
					local sign = if inside then 1 / d else -1 / d
					normalX[index], normalY[index] = toX[index] * sign, toY[index] * sign
				end
			end
		end
	end
	return {w = w, h = h, originX = offX, baselineY = offY, depth = depth, normalX = normalX, normalY = normalY}
end

-- Where each clock character goes for `text` on a width x height screen
local function macClockLayout(text, width, height)
	local font = loadMacClockFont()
	local zero = font.glyph("0")
	local digitTop = 0
	for _, contour in ipairs(zero) do
		for _, pt in ipairs(contour) do
			digitTop = math.max(digitTop, pt[2])
		end
	end
	local digitHeight = MAC_CLOCK_DIGIT_HEIGHT * height
	local fontPx = math.round(digitHeight / (digitTop / font.unitsPerEm))
	local scale = fontPx / font.unitsPerEm
	local baselineY = height * MAC_CLOCK_CENTER_Y + digitHeight / 2
	local advances, total = {}, 0
	for i = 1, #text do
		local _, advance = font.glyph(string.sub(text, i, i))
		advances[i] = advance * scale
		total += advances[i]
	end
	local placements, x = {}, width / 2 - total / 2
	for i = 1, #text do
		table.insert(placements, {char = string.sub(text, i, i), fontPx = fontPx, originX = x, baselineY = baselineY})
		x += advances[i]
	end
	return placements
end

local macGlyphFields = {}
-- Renders one clock character in glass at its screen spot. Returns the asset
-- id and the image's position and size, or nil for an empty glyph.
local function bakeMacClockGlyph(placement, width, height)
	local font = loadMacClockFont()
	local fontPx = placement.fontPx
	local band = math.ceil(math.max(MAC_TEXT_GLASS.thickness, MAC_TEXT_GLASS.fresnelReach, MAC_TEXT_GLASS.glareReach) * fontPx) + 2
	local key = placement.char .. "_" .. fontPx
	local field = macGlyphFields[key]
	if field == nil then
		local contours = font.glyph(placement.char)
		field = macGlyphField(contours, font.unitsPerEm, fontPx, band) or false
		macGlyphFields[key] = field
	end
	if not field then
		return nil
	end
	local x0 = math.round(placement.originX - field.originX)
	local y0 = math.round(placement.baselineY - field.baselineY)
	local name = if placement.char == ":" then "colon" else placement.char
	local path = string.format("%s/glass_v%d_clock_%s_%d_%dx%d_%d_%d.png", MACOS_FOLDER, MAC_GLASS_VERSION, name, fontPx, width, height, x0, y0)
	if not isfile(path) then
		local t = MAC_TEXT_GLASS
		local w, depthMap, normalX, normalY = field.w, field.depth, field.normalX, field.normalY
		local room = t.room * fontPx
		ensureMacFolder()
		writefile(path, renderMacGlass(x0, y0, field.w, field.h, function(px, py)
			local index = py * w + px + 1
			return depthMap[index], normalX[index], normalY[index]
		end, macSamplerFor(width, height), {
			thickness = t.thickness * fontPx, refraction = t.refraction, aberration = t.aberration,
			blur = t.frost * fontPx, step = 2,
			reach = function()
				return room
			end,
			tint = t.tint, tintAlpha = t.tintAlpha,
			fresnelK = (1 + t.fresnelHardness) / (t.fresnelReach * fontPx), fresnelHardness = t.fresnelHardness, fresnelIntensity = t.fresnelIntensity,
			glareK = (1 + t.glareHardness) / (t.glareReach * fontPx), glareHardness = t.glareHardness, glareIntensity = t.glareIntensity,
			glareConvergence = t.glareConvergence, glareOpposite = t.glareOpposite, glareAngle = t.glareAngle,
		}))
	end
	return getcustomasset(path), x0, y0, field.w, field.h
end

-- ---------- Lock screen ----------
-- Shows the lock screen on the session's ScreenGui (see createMacSession) and
-- returns once it's unlocked. `boot`: fade in from black (Restart); the first
-- lock screen fades in out of the loader instead.
local function showMacLockScreen(session, boot)
	local gui = session.gui
	local assets = session.assets

	local alive = true
	local connections = {}

	local backgroundMode = session.mode

	local ui = Instance.new("Frame")
	ui.Name = "LockScreen"
	ui.BackgroundTransparency = 1
	ui.Size = UDim2.fromScale(1, 1)
	ui.ZIndex = 3
	ui.Parent = gui

	local function label(text, weight, centerY, height, width)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, centerY)
		l.Size = UDim2.fromScale(width, height)
		l.FontFace = macFont(weight)
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Parent = ui
		return l
	end

	-- Date and the big glass clock
	local dateLabel = label("", Enum.FontWeight.SemiBold, 0.107, 0.034, 0.5)
	dateLabel.TextTransparency = 0.04
	-- Roblox caps text at size 100, so the clock is drawn at 100 and scaled up
	-- to match Tahoe (digits about 10% of the screen height)
	local clock = label("", Enum.FontWeight.Bold, 0.192, 0, 0)
	clock.TextScaled = false
	clock.TextSize = 100
	clock.Size = UDim2.fromOffset(420, 118)
	clock.TextTransparency = 0.06
	local clockScale = Instance.new("UIScale")
	clockScale.Parent = clock
	local function layoutClock()
		clockScale.Scale = gui.AbsoluteSize.Y * 0.1435 / 100
	end
	layoutClock()
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutClock))
	local clockGlass = Instance.new("UIGradient")
	clockGlass.Rotation = 90
	clockGlass.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(208, 222, 242))
	clockGlass.Transparency = NumberSequence.new(0, 0.28)
	clockGlass.Parent = clock
	local clockRim = Instance.new("UIStroke")
	clockRim.Color = Color3.new(1, 1, 1)
	clockRim.Transparency = 0.55
	clockRim.Thickness = 1.5
	clockRim.Parent = clock

	-- Liquid Glass clock: every digit is real glass, rendered from the font's
	-- outlines against the wallpaper. Falls back to the text clock above if
	-- the font couldn't load (or a custom wallpaper image is in use).
	local glassClock = Instance.new("Frame")
	glassClock.Name = "GlassClock"
	glassClock.BackgroundTransparency = 1
	glassClock.Size = UDim2.fromScale(1, 1)
	glassClock.Parent = ui
	local glassClockOn = assets.clockFont == true and assets.glow ~= nil and assets.wallpaper == nil
	local glassClockKey = nil
	local glassDigits = {}
	-- The glass is rendered against the wallpaper, so over the 3D scene the
	-- frosted text clock is used instead. `time`: crossfade the two clocks
	-- (along with the background) instead of switching at once.
	local clockFade = 0
	local function applyClockStyle(time)
		local useGlass = glassClockOn and backgroundMode == "wallpaper"
		clockFade += 1
		local fadeId = clockFade
		local function settle()
			glassClock.Visible = useGlass
			clock.Visible = not useGlass
			for _, image in ipairs(glassDigits) do
				image.ImageTransparency = 0
			end
			clock.TextTransparency = 0.06
			clockRim.Transparency = 0.55
		end
		if not time or (glassClock.Visible == useGlass and clock.Visible ~= useGlass) then
			settle()
			return
		end
		local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local glassTarget = if useGlass then 0 else 1
		if useGlass then
			for _, image in ipairs(glassDigits) do
				image.ImageTransparency = 1
			end
		else
			clock.TextTransparency = 1
			clockRim.Transparency = 1
		end
		glassClock.Visible = true
		clock.Visible = true
		for _, image in ipairs(glassDigits) do
			TweenService:Create(image, info, {ImageTransparency = glassTarget}):Play()
		end
		TweenService:Create(clock, info, {TextTransparency = if useGlass then 1 else 0.06}):Play()
		TweenService:Create(clockRim, info, {Transparency = if useGlass then 1 else 0.55}):Play()
		task.delay(time, function()
			if fadeId == clockFade and alive then
				settle()
			end
		end)
	end
	applyClockStyle()
	local function useTextClock(reason)
		warn("[coolui] glass clock unavailable, using the text clock: " .. tostring(reason))
		glassClockOn = false
		applyClockStyle()
	end
	local function updateGlassClock()
		if not glassClockOn then return end
		local size = gui.AbsoluteSize
		local text = DateTime.now():FormatLocalTime("h:mm", "en-us")
		local key = text .. "@" .. size.X .. "x" .. size.Y
		if key == glassClockKey then return end
		glassClockKey = key
		task.spawn(function()
			local ok, results = pcall(function()
				local placed = {}
				for _, placement in ipairs(macClockLayout(text, size.X, size.Y)) do
					local id, x, y, w, h = bakeMacClockGlyph(placement, size.X, size.Y)
					if id then
						table.insert(placed, {id, x, y, w, h})
					end
					task.wait() -- spread any new renders over several frames
				end
				return placed
			end)
			if glassClockKey ~= key or not alive then return end -- a newer time/size took over
			if not ok then
				useTextClock(results)
				return
			end
			for i, r in ipairs(results) do
				local image = glassDigits[i]
				if not image then
					image = Instance.new("ImageLabel")
					image.BackgroundTransparency = 1
					image.Parent = glassClock
					glassDigits[i] = image
				end
				image.Image = r[1]
				image.Position = UDim2.fromOffset(r[2], r[3])
				image.Size = UDim2.fromOffset(r[4], r[5])
			end
			for i = #results + 1, #glassDigits do
				glassDigits[i]:Destroy()
				glassDigits[i] = nil
			end
		end)
	end

	local function updateClock()
		local now = DateTime.now()
		clock.Text = now:FormatLocalTime("h:mm", "en-us")
		dateLabel.Text = now:FormatLocalTime("ddd MMM D", "en-us")
		updateGlassClock()
	end
	updateClock()
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGlassClock))
	task.spawn(function()
		while alive do
			task.wait(1)
			if alive then
				updateClock()
			end
		end
	end)

	-- Top-right status items: keyboard input source, Wi-Fi, battery
	local statusBar = Instance.new("Frame")
	statusBar.BackgroundTransparency = 1
	statusBar.AnchorPoint = Vector2.new(1, 0)
	statusBar.Position = UDim2.new(1, -14, 0, 6)
	statusBar.Size = UDim2.fromScale(0.4, 0.022)
	statusBar.Parent = ui
	local statusList = Instance.new("UIListLayout")
	statusList.FillDirection = Enum.FillDirection.Horizontal
	statusList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	statusList.VerticalAlignment = Enum.VerticalAlignment.Center
	statusList.SortOrder = Enum.SortOrder.LayoutOrder
	statusList.Padding = UDim.new(0, 12)
	statusList.Parent = statusBar
	local inputSource = Instance.new("TextLabel")
	inputSource.BackgroundTransparency = 1
	inputSource.AutomaticSize = Enum.AutomaticSize.X
	inputSource.Size = UDim2.fromScale(0, 1)
	inputSource.FontFace = macFont(Enum.FontWeight.SemiBold)
	inputSource.Text = "U.S."
	inputSource.TextColor3 = Color3.new(1, 1, 1)
	inputSource.LayoutOrder = 1
	inputSource.Parent = statusBar
	local wifiHolder = Instance.new("Frame")
	wifiHolder.BackgroundTransparency = 1
	wifiHolder.Size = UDim2.fromScale(0.78, 0.78)
	wifiHolder.SizeConstraint = Enum.SizeConstraint.RelativeYY
	wifiHolder.LayoutOrder = 2
	wifiHolder.Parent = statusBar
	local wifiGlyph = macWifiGlyph(wifiHolder, Color3.new(1, 1, 1))
	-- Roblox can't read the battery, so it's always the "unknown" battery
	local battery = Instance.new("ImageLabel")
	battery.BackgroundTransparency = 1
	battery.Image = MACOS_ICONS.batteryUnknown
	battery.ImageColor3 = Color3.new(1, 1, 1)
	battery.Size = UDim2.fromScale(1.1, 1.1)
	battery.SizeConstraint = Enum.SizeConstraint.RelativeYY
	battery.LayoutOrder = 3
	battery.Parent = statusBar
	task.spawn(function()
		while alive do
			task.wait(1)
			if alive then
				wifiGlyph.set(macReadNetwork())
			end
		end
	end)
	local function layoutStatus()
		inputSource.TextSize = math.max(10, math.floor(gui.AbsoluteSize.Y * 0.016))
	end
	layoutStatus()
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutStatus))

	-- Bottom: profile picture, name, and the password hint/field
	local avatar = Instance.new("ImageLabel")
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.Position = UDim2.fromScale(0.5, 0.873)
	avatar.Size = UDim2.fromScale(0.052, 0.052)
	avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
	avatar.BackgroundColor3 = Color3.fromRGB(175, 188, 205)
	avatar.BorderSizePixel = 0
	avatar.Image = assets.avatar or ""
	avatar.Parent = ui
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatar

	local nameLabel = label(player.DisplayName, Enum.FontWeight.Bold, 0.915, 0.0145, 0.4)
	local hint = label("Touch ID or Enter Password", Enum.FontWeight.Medium, 0.937, 0.0125, 0.4)
	hint.TextTransparency = 0.12

	-- Password field: a Liquid Glass pill that appears when you click or press a key
	-- (position/size must match macPasswordFieldRect)
	local field = Instance.new("Frame")
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	field.Position = UDim2.fromScale(0.5, 0.946)
	field.Size = UDim2.fromScale(0.17, 0.032)
	field.SizeConstraint = Enum.SizeConstraint.RelativeYY
	field.BackgroundColor3 = Color3.new(1, 1, 1)
	field.Visible = false
	field.Parent = ui
	local fieldCorner = Instance.new("UICorner")
	fieldCorner.CornerRadius = UDim.new(1, 0)
	fieldCorner.Parent = field
	local fieldRim = Instance.new("UIStroke")
	fieldRim.Color = Color3.new(1, 1, 1)
	fieldRim.Parent = field

	-- The glass is rendered once against the wallpaper. With a custom wallpaper
	-- image we can't know what's behind it, so that falls back to a frosted pill.
	local glassPane = Instance.new("ImageLabel")
	glassPane.Name = "GlassPane"
	glassPane.BackgroundTransparency = 1
	glassPane.Size = UDim2.fromScale(1, 1)
	glassPane.ZIndex = 0
	glassPane.Parent = field
	local glassReady = false
	-- Fill, rim and glass-pane transparency: Liquid Glass on the wallpaper,
	-- a frosted pill over the 3D scene (or when the glass isn't available)
	local function fieldStyle()
		if glassReady and backgroundMode == "wallpaper" then
			return 1, 1, 0
		end
		return 0.78, 0.6, 1
	end
	local function setGlass(id)
		glassPane.Image = id
		glassReady = true
	end
	local function bakeFieldGlass()
		if assets.wallpaper or not assets.glow then return end
		local size = gui.AbsoluteSize
		local ok, id = pcall(function()
			if assets.fieldGlass and assets.fieldGlass.size == size then
				return assets.fieldGlass.id
			end
			local x, y, w, h = macPasswordFieldRect(size.X, size.Y)
			return bakeMacGlass("field", x, y, w, h, size.X, size.Y)
		end)
		if ok then
			setGlass(id)
		else
			warn("[coolui] liquid glass failed: " .. tostring(id))
		end
	end
	bakeFieldGlass()
	-- `time`: crossfade to the new style along with the background
	local function applyFieldStyle(time)
		local fill, rim, pane = fieldStyle()
		if time then
			local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			TweenService:Create(field, info, {BackgroundTransparency = fill}):Play()
			TweenService:Create(fieldRim, info, {Transparency = rim}):Play()
			TweenService:Create(glassPane, info, {ImageTransparency = pane}):Play()
			return
		end
		field.BackgroundTransparency = fill
		fieldRim.Transparency = rim
		glassPane.ImageTransparency = pane
	end
	applyFieldStyle()
	-- Re-render the glass if the screen size changes
	local rebakeQueued = false
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if rebakeQueued then return end
		rebakeQueued = true
		task.delay(0.4, function()
			rebakeQueued = false
			if alive then
				bakeFieldGlass()
			end
		end)
	end))

	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(1, 1)
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "Enter Password"
	box.PlaceholderColor3 = Color3.fromRGB(232, 238, 250)
	box.TextColor3 = Color3.new(1, 1, 1)
	box.FontFace = macFont(Enum.FontWeight.Medium)
	box.TextScaled = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = field
	local boxPadding = Instance.new("UIPadding")
	boxPadding.PaddingLeft = UDim.new(0.09, 0)
	boxPadding.PaddingRight = UDim.new(0.2, 0)
	boxPadding.PaddingTop = UDim.new(0.24, 0)
	boxPadding.PaddingBottom = UDim.new(0.24, 0)
	boxPadding.Parent = box

	local submit = Instance.new("ImageButton")
	submit.BackgroundTransparency = 1
	submit.AnchorPoint = Vector2.new(1, 0.5)
	submit.Position = UDim2.new(1, -4, 0.5, 0)
	submit.Size = UDim2.fromScale(0.76, 0.76)
	submit.SizeConstraint = Enum.SizeConstraint.RelativeYY
	submit.Image = MACOS_ICONS.submit
	submit.ImageColor3 = Color3.new(1, 1, 1)
	submit.ImageTransparency = 0.15
	submit.Visible = false
	submit.Parent = field

	-- Mask what's typed with dots; the real characters are kept in `typed`
	local DOT = "•"
	local typed = {}
	local masking = false
	local function setMasked()
		masking = true
		box.Text = string.rep(DOT, #typed)
		box.CursorPosition = #box.Text + 1
		masking = false
		submit.Visible = #typed > 0
	end
	table.insert(connections, box:GetPropertyChangedSignal("Text"):Connect(function()
		if masking then return end
		local text = box.Text
		local newChars = text:gsub(DOT, "")
		local _, dotCount = text:gsub(DOT, "")
		while #typed > dotCount do
			table.remove(typed)
		end
		for _, code in utf8.codes(newChars) do
			table.insert(typed, utf8.char(code))
		end
		setMasked()
	end))

	local fieldShown = false
	local unlocked = false
	local fieldHome = field.Position

	local function showField()
		if unlocked then return end
		if not fieldShown then
			fieldShown = true
			hint.Visible = false
			field.Visible = true
			local fill, rim, pane = fieldStyle()
			field.BackgroundTransparency = 1
			fieldRim.Transparency = 1
			glassPane.ImageTransparency = 1
			TweenService:Create(field, TweenInfo.new(0.2), {BackgroundTransparency = fill}):Play()
			TweenService:Create(fieldRim, TweenInfo.new(0.2), {Transparency = rim}):Play()
			TweenService:Create(glassPane, TweenInfo.new(0.2), {ImageTransparency = pane}):Play()
		end
		box:CaptureFocus()
	end
	local function hideField()
		fieldShown = false
		table.clear(typed)
		setMasked()
		box:ReleaseFocus()
		field.Visible = false
		hint.Visible = true
	end
	-- The macOS "wrong password" shake
	local function shake()
		task.spawn(function()
			for _, dx in ipairs({-14, 12, -9, 7, -4, 0}) do
				TweenService:Create(field, TweenInfo.new(0.05), {Position = fieldHome + UDim2.fromOffset(dx, 0)}):Play()
				task.wait(0.05)
			end
		end)
	end
	local function submitPassword()
		if unlocked then return end
		local entered = table.concat(typed)
		if #typed == 0 or (MACOS_PASSWORD ~= "" and entered ~= MACOS_PASSWORD) then
			table.clear(typed)
			setMasked()
			shake()
			box:CaptureFocus()
			return
		end
		unlocked = true
		box:ReleaseFocus()
	end
	table.insert(connections, box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitPassword()
		end
	end))
	table.insert(connections, submit.MouseButton1Click:Connect(submitPassword))
	-- Background switch (bottom-right): Tahoe wallpaper <-> the live 3D scene
	local switch = Instance.new("TextButton")
	switch.Name = "BackgroundSwitch"
	switch.AutoButtonColor = false
	switch.Text = ""
	switch.AnchorPoint = Vector2.new(1, 1)
	switch.Position = UDim2.new(1, -18, 1, -18)
	switch.Size = UDim2.fromScale(0.15, 0.034)
	switch.SizeConstraint = Enum.SizeConstraint.RelativeYY
	switch.BackgroundColor3 = Color3.new(1, 1, 1)
	switch.BackgroundTransparency = 0.8
	switch.Parent = ui
	local switchCorner = Instance.new("UICorner")
	switchCorner.CornerRadius = UDim.new(1, 0)
	switchCorner.Parent = switch
	local switchRim = Instance.new("UIStroke")
	switchRim.Color = Color3.new(1, 1, 1)
	switchRim.Transparency = 0.6
	switchRim.Parent = switch
	local switchIcon = Instance.new("ImageLabel")
	switchIcon.BackgroundTransparency = 1
	switchIcon.AnchorPoint = Vector2.new(0, 0.5)
	switchIcon.Position = UDim2.fromScale(0.08, 0.5)
	switchIcon.Size = UDim2.fromScale(0.58, 0.58)
	switchIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	switchIcon.ImageColor3 = Color3.new(1, 1, 1)
	switchIcon.Parent = switch
	local switchLabel = Instance.new("TextLabel")
	switchLabel.BackgroundTransparency = 1
	switchLabel.AnchorPoint = Vector2.new(0, 0.5)
	switchLabel.Position = UDim2.fromScale(0.25, 0.5)
	switchLabel.Size = UDim2.fromScale(0.68, 0.46)
	switchLabel.FontFace = macFont(Enum.FontWeight.Medium)
	switchLabel.TextScaled = true
	switchLabel.TextXAlignment = Enum.TextXAlignment.Left
	switchLabel.TextColor3 = Color3.new(1, 1, 1)
	switchLabel.Parent = switch
	local function updateSwitch()
		-- Shows what clicking switches to
		if backgroundMode == "wallpaper" then
			switchIcon.Image = MACOS_ICONS.scene
			switchLabel.Text = "Show 3D scene"
		else
			switchIcon.Image = MACOS_ICONS.wallpaper
			switchLabel.Text = "Show wallpaper"
		end
	end
	table.insert(connections, switch.MouseEnter:Connect(function()
		TweenService:Create(switch, TweenInfo.new(0.15), {BackgroundTransparency = 0.68}):Play()
	end))
	table.insert(connections, switch.MouseLeave:Connect(function()
		TweenService:Create(switch, TweenInfo.new(0.15), {BackgroundTransparency = 0.8}):Play()
	end))

	-- The 3D scene's sky is nearly white, so a soft shade at the top keeps the
	-- white date, clock and status icons readable (3D scene only)
	local sceneShade = Instance.new("Frame")
	sceneShade.Name = "SceneShade"
	sceneShade.BackgroundColor3 = Color3.new(0, 0, 0)
	sceneShade.BorderSizePixel = 0
	sceneShade.Size = UDim2.fromScale(1, 1)
	sceneShade.ZIndex = 0
	sceneShade.Parent = ui
	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Rotation = 90
	shadeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.22, 0.62),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	shadeGradient.Parent = sceneShade

	-- The session swaps the wallpaper and the 3D scene; the lock screen restyles
	-- its clock, password field and shade to match, crossfading along with it
	local function applyBackground(mode, animate)
		backgroundMode = mode
		updateSwitch()
		local shadeTransparency = if mode == "wallpaper" then 1 else 0
		if not animate then
			sceneShade.BackgroundTransparency = shadeTransparency
			applyClockStyle()
			applyFieldStyle()
			return
		end
		TweenService:Create(sceneShade, TweenInfo.new(session.fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {BackgroundTransparency = shadeTransparency}):Play()
		applyClockStyle(session.fadeTime)
		applyFieldStyle(session.fadeTime)
	end
	applyBackground(backgroundMode, false)
	local stopBackground = session.onBackground(applyBackground)
	table.insert(connections, switch.MouseButton1Click:Connect(function()
		if unlocked then return end
		task.spawn(session.setBackground, if backgroundMode == "wallpaper" then "scene" else "wallpaper", true)
	end))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if unlocked then return end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			-- Clicks on buttons (like the background switch) don't open the field
			if processed then return end
			showField()
		elseif kind == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				if fieldShown then
					hideField()
				end
			elseif not fieldShown then
				showField()
			end
		end
	end))

	-- Coming in: out of the loader (its backdrop fades away), up from black
	-- (Restart), or over the desktop's background (Lock Screen, Log Out) -
	-- while the date and clock settle into place
	if session.veil then
		local veil = session.veil
		session.veil = nil
		local fade = TweenService:Create(veil, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {ImageTransparency = 1})
		fade:Play()
		fade.Completed:Once(function()
			veil:Destroy()
		end)
	elseif boot then
		session.cover.BackgroundTransparency = 0
		TweenService:Create(session.cover, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	else
		-- The whole lock screen fades in as one layer, then goes back to plain frames
		local fader = Instance.new("CanvasGroup")
		fader.BackgroundTransparency = 1
		fader.Size = UDim2.fromScale(1, 1)
		fader.ZIndex = ui.ZIndex
		fader.GroupTransparency = 1
		fader.Parent = gui
		ui.Parent = fader
		local fade = TweenService:Create(fader, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = 0})
		fade:Play()
		fade.Completed:Once(function()
			if ui.Parent == fader then
				ui.Parent = gui
			end
			fader:Destroy()
		end)
	end
	local settle = TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local clockHome, dateHome = clock.Position, dateLabel.Position
	clock.Position = clockHome - UDim2.fromScale(0, 0.02)
	dateLabel.Position = dateHome - UDim2.fromScale(0, 0.02)
	glassClock.Position = UDim2.fromScale(0, -0.02)
	TweenService:Create(clock, settle, {Position = clockHome}):Play()
	TweenService:Create(dateLabel, settle, {Position = dateHome}):Play()
	TweenService:Create(glassClock, settle, {Position = UDim2.fromScale(0, 0)}):Play()

	repeat
		task.wait()
	until unlocked or not gui.Parent

	-- Unlock: the lock screen lifts away and the wallpaper eases forward; the
	-- desktop then settles it back as the menu bar and Dock slide in
	clockFade += 1 -- a clock crossfade still finishing mustn't undo the lift
	local lift = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, l in ipairs({dateLabel, clock, nameLabel, hint}) do
		TweenService:Create(l, lift, {TextTransparency = 1, Position = l.Position - UDim2.fromScale(0, 0.03)}):Play()
	end
	TweenService:Create(glassClock, lift, {Position = UDim2.fromScale(0, -0.03)}):Play()
	for _, image in ipairs(glassDigits) do
		TweenService:Create(image, lift, {ImageTransparency = 1}):Play()
	end
	TweenService:Create(clockRim, lift, {Transparency = 1}):Play()
	TweenService:Create(avatar, lift, {ImageTransparency = 1, BackgroundTransparency = 1}):Play()
	TweenService:Create(field, lift, {BackgroundTransparency = 1}):Play()
	TweenService:Create(fieldRim, lift, {Transparency = 1}):Play()
	TweenService:Create(glassPane, lift, {ImageTransparency = 1}):Play()
	TweenService:Create(box, lift, {TextTransparency = 1}):Play()
	TweenService:Create(submit, lift, {ImageTransparency = 1}):Play()
	TweenService:Create(switch, lift, {BackgroundTransparency = 1}):Play()
	TweenService:Create(sceneShade, lift, {BackgroundTransparency = 1}):Play()
	TweenService:Create(switchRim, lift, {Transparency = 1}):Play()
	TweenService:Create(switchIcon, lift, {ImageTransparency = 1}):Play()
	TweenService:Create(switchLabel, lift, {TextTransparency = 1}):Play()
	-- The status icons fade too; the desktop's menu bar brings its own
	for _, item in ipairs(statusBar:GetDescendants()) do
		if item:IsA("TextLabel") then
			TweenService:Create(item, lift, {TextTransparency = 1}):Play()
		elseif item:IsA("ImageLabel") then
			TweenService:Create(item, lift, {ImageTransparency = 1}):Play()
		end
	end
	TweenService:Create(session.wallScale, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.03}):Play()
	task.wait(0.45)

	alive = false
	stopBackground()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	ui:Destroy()
end

-- ==========================================
-- MACOS DESKTOP
-- After unlocking: a menu bar, a Liquid Glass Dock and working apps (Finder
-- for the executor's workspace folder, Notes, Terminal, Music, System
-- Settings). Works on both backgrounds: on the wallpaper the Dock's glass is
-- rendered once; over the 3D scene it is redrawn live as the camera moves.
-- ==========================================
local AssetService = game:GetService("AssetService")

local MAC_DESKTOP_ICONS = {
	apple = "rbxassetid://10709761889",
	finder = "rbxassetid://10734964441", -- Lucide "smile"
	folder = "rbxassetid://10723387563",
	file = "rbxassetid://10723374641",
	fileText = "rbxassetid://10723367380",
	fileImage = "rbxassetid://10723357790",
	fileAudio = "rbxassetid://10723355148",
	fileCode = "rbxassetid://10723356507",
	music = "rbxassetid://10734905958",
	play = "rbxassetid://10734923549",
	pause = "rbxassetid://10734919336",
	skipForward = "rbxassetid://10734961809",
	skipBack = "rbxassetid://10734961526",
	settings = "rbxassetid://10734950309",
	terminal = "rbxassetid://10734982144",
	notes = "rbxassetid://10734972463", -- Lucide "sticky-note"
	trash = "rbxassetid://10747362241", -- Lucide "trash-2"
	close = "rbxassetid://10747384394", -- Lucide "x"
	minus = "rbxassetid://10734896206",
	plus = "rbxassetid://10734924532",
	back = "rbxassetid://10709791281", -- Lucide "chevron-left"
	forward = "rbxassetid://10709791437", -- Lucide "chevron-right"
	home = "rbxassetid://10723407389",
	laptop = "rbxassetid://10723423881",
	image = "rbxassetid://10723415040",
	search = "rbxassetid://10734943674",
	check = "rbxassetid://10709790644",
	info = "rbxassetid://10723415903",
	wifi = MACOS_ICONS.wifi,
	battery = "rbxassetid://10709774206", -- Lucide "battery-full" (the Battery settings icon)
}

local MAC_COLORS = {
	ink = Color3.fromRGB(29, 29, 31),
	inkSoft = Color3.fromRGB(118, 118, 124),
	accent = Color3.fromRGB(0, 122, 255),
	window = Color3.fromRGB(247, 247, 249),
	sidebar = Color3.fromRGB(233, 234, 238),
	menu = Color3.fromRGB(240, 240, 243),
	zebra = Color3.fromRGB(244, 245, 247),
	terminalText = Color3.fromRGB(232, 232, 232),
	terminalError = Color3.fromRGB(255, 120, 110),
	terminalAccent = Color3.fromRGB(120, 220, 140),
}

-- The desktop is laid out in points for a screen this many points tall,
-- then scaled to the real screen
local MAC_DESK = {
	height = 1080,
	menuHeight = 30,
	dockIcon = 56, dockPadding = 8, dockGap = 6, dockSeparator = 17, dockBottom = 8, dockRadius = 22,
	titleBar = 52, windowRadius = 16, shadowBlur = 44,
}

-- Dock apps, left to right (the Trash goes after a separator)
local MAC_APPS = {
	{id = "finder", name = "Finder", icon = MAC_DESKTOP_ICONS.finder, top = Color3.fromRGB(110, 198, 255), bottom = Color3.fromRGB(18, 110, 238)},
	{id = "notes", name = "Notes", icon = MAC_DESKTOP_ICONS.notes, top = Color3.fromRGB(255, 228, 120), bottom = Color3.fromRGB(247, 184, 34)},
	{id = "music", name = "Music", icon = MAC_DESKTOP_ICONS.music, top = Color3.fromRGB(255, 110, 132), bottom = Color3.fromRGB(236, 34, 76)},
	{id = "terminal", name = "Terminal", icon = MAC_DESKTOP_ICONS.terminal, top = Color3.fromRGB(76, 76, 82), bottom = Color3.fromRGB(26, 26, 30)},
	{id = "settings", name = "System Settings", icon = MAC_DESKTOP_ICONS.settings, top = Color3.fromRGB(178, 180, 188), bottom = Color3.fromRGB(110, 112, 122)},
}
local MAC_TRASH = {
	id = "trash", name = "Trash", icon = MAC_DESKTOP_ICONS.trash,
	top = Color3.fromRGB(238, 240, 244), bottom = Color3.fromRGB(196, 200, 210), glyph = Color3.fromRGB(88, 92, 102),
}
-- Menu bar names for windows that aren't Dock apps
local MAC_APP_NAMES = {about = "Finder", preview = "Preview"}
for _, app in ipairs(MAC_APPS) do
	MAC_APP_NAMES[app.id] = app.name
end

-- Where the Dock sits on a width x height screen, in pixels, plus its corner
-- radius (mirrors the Dock in createMacDesktop, so the loader can pre-render
-- its glass)
local function macDockRect(width, height)
	local d = MAC_DESK
	local s = height / d.height
	local w = (2 * d.dockPadding + (#MAC_APPS + 1) * d.dockIcon + (#MAC_APPS - 1) * d.dockGap + d.dockSeparator) * s
	local h = (d.dockIcon + 2 * d.dockPadding) * s
	return (width - w) / 2, height - d.dockBottom * s - h, w, h, d.dockRadius * s
end

-- ---------- Small UI helpers ----------
local function macNew(className, props)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function macCorner(parent, radius)
	return macNew("UICorner", {CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius), Parent = parent})
end

local function macStroke(parent, color, transparency, thickness)
	return macNew("UIStroke", {
		Color = color, Transparency = transparency, Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end

local function macLabel(parent, text, size, weight, color, props)
	local label = macNew("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = size, FontFace = macFont(weight or Enum.FontWeight.Regular),
		TextColor3 = color or MAC_COLORS.ink, TextXAlignment = Enum.TextXAlignment.Left, Parent = parent,
	})
	for key, value in pairs(props or {}) do
		label[key] = value
	end
	return label
end

local function macButton(parent, props)
	local button = macNew("TextButton", {AutoButtonColor = false, Text = "", BackgroundTransparency = 1, BorderSizePixel = 0, Parent = parent})
	for key, value in pairs(props or {}) do
		button[key] = value
	end
	return button
end

local function macImage(parent, image, size, color, props)
	local icon = macNew("ImageLabel", {
		BackgroundTransparency = 1, Image = image, ImageColor3 = color or Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(size, size), Parent = parent,
	})
	for key, value in pairs(props or {}) do
		icon[key] = value
	end
	return icon
end

-- A macOS-style app icon: a rounded square with a gradient and a glyph
local function macAppTile(parent, app, size)
	local tile = macNew("Frame", {Size = UDim2.fromOffset(size, size), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = parent})
	macCorner(tile, UDim.new(0.24, 0))
	macNew("UIGradient", {Rotation = 90, Color = ColorSequence.new(app.top, app.bottom), Parent = tile})
	macStroke(tile, Color3.new(0, 0, 0), 0.88, 1)
	macImage(tile, app.icon, math.round(size * 0.56), app.glyph or Color3.new(1, 1, 1), {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	})
	return tile
end

-- A macOS switch; onChange(on) runs when it's clicked
local function macToggle(parent, on, onChange)
	local offColor = Color3.fromRGB(214, 214, 220)
	local track = macButton(parent, {
		Size = UDim2.fromOffset(34, 20), BackgroundTransparency = 0,
		BackgroundColor3 = if on then MAC_COLORS.accent else offColor,
	})
	macCorner(track, UDim.new(1, 0))
	local knob = macNew("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, if on then 16 else 2, 0.5, 0), Size = UDim2.fromOffset(16, 16), Parent = track,
	})
	macCorner(knob, UDim.new(1, 0))
	macStroke(knob, Color3.new(0, 0, 0), 0.9, 1)
	local toggle = {button = track, on = on}
	function toggle.set(value)
		if value == toggle.on then
			return
		end
		toggle.on = value
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(track, info, {BackgroundColor3 = if value then MAC_COLORS.accent else offColor}):Play()
		TweenService:Create(knob, info, {Position = UDim2.new(0, if value then 16 else 2, 0.5, 0)}):Play()
	end
	track.MouseButton1Click:Connect(function()
		toggle.set(not toggle.on)
		onChange(toggle.on)
	end)
	return toggle
end

-- ---------- Live glass on the 3D scene ----------
-- Everything in the world is hidden while this UI is up, so the 3D scene is
-- just the skybox seen through the moving camera (plus blur and color
-- effects). That makes real Liquid Glass over it cheap: each glass pixel
-- looks up the sky in its own view direction, no screen capture needed. The
-- six sky images are read once (EditableImage), shrunk, and color-graded to
-- match the scene's effects.
local MAC_SKY_FACE_SIZE = 256
-- Approximates the scene's ColorCorrection and exposure on the raw sky
-- How the skybox looks once Roblox has rendered it with the scene's lighting,
-- fitted to screenshots. The bloom brightens the bright sky a lot; here it's
-- approximated per pixel (brightness above `bloomThreshold` is boosted).
local MAC_SCENE_GRADE = {exposure = 0.52, brightness = -0.15, contrast = 0.02, saturation = -0.07, bloom = 1.17, bloomThreshold = 0.3}
local macSky = nil -- {size = n, Ft = buffer, ...}: RGB bytes per face

local function macGradeSceneColor(r, g, b)
	local grade = MAC_SCENE_GRADE
	local gain = 2 ^ grade.exposure
	r, g, b = r * gain, g * gain, b * gain
	local gray = r * 0.299 + g * 0.587 + b * 0.114
	local saturation = 1 + grade.saturation
	r, g, b = gray + (r - gray) * saturation, gray + (g - gray) * saturation, gray + (b - gray) * saturation
	local contrast = 1 + grade.contrast
	r = (r - 0.5) * contrast + 0.5 + grade.brightness
	g = (g - 0.5) * contrast + 0.5 + grade.brightness
	b = (b - 0.5) * contrast + 0.5 + grade.brightness
	r, g, b = math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1)
	local glow = grade.bloom * math.max(0, r * 0.299 + g * 0.587 + b * 0.114 - grade.bloomThreshold)
	return math.min(1, r + glow), math.min(1, g + glow), math.min(1, b + glow)
end

-- Reads the six images of `skyInstance` (a Sky) into macSky
local function loadMacSky(skyInstance)
	local n = MAC_SKY_FACE_SIZE
	local faces = {size = n}
	local readu8, writeu8 = buffer.readu8, buffer.writeu8
	for _, name in ipairs({"Ft", "Bk", "Lf", "Rt", "Up", "Dn"}) do
		local image = AssetService:CreateEditableImageAsync(Content.fromUri(skyInstance["Skybox" .. name]))
		local size = image.Size
		local source = image:ReadPixelsBuffer(Vector2.zero, size)
		image:Destroy()
		local w, h = size.X, size.Y
		local stepX, stepY = w / n, h / n
		local out = buffer.create(n * n * 3)
		for j = 0, n - 1 do
			-- Average 2x2 samples spread over each source block
			local y0 = math.floor(j * stepY)
			local y1 = math.min(h - 1, math.floor((j + 0.5) * stepY))
			for i = 0, n - 1 do
				local x0 = math.floor(i * stepX)
				local x1 = math.min(w - 1, math.floor((i + 0.5) * stepX))
				local a, b, c, d = (y0 * w + x0) * 4, (y0 * w + x1) * 4, (y1 * w + x0) * 4, (y1 * w + x1) * 4
				local r = (readu8(source, a) + readu8(source, b) + readu8(source, c) + readu8(source, d)) / 1020
				local g = (readu8(source, a + 1) + readu8(source, b + 1) + readu8(source, c + 1) + readu8(source, d + 1)) / 1020
				local bl = (readu8(source, a + 2) + readu8(source, b + 2) + readu8(source, c + 2) + readu8(source, d + 2)) / 1020
				r, g, bl = macGradeSceneColor(r, g, bl)
				local o = (j * n + i) * 3
				writeu8(out, o, r * 255 + 0.5)
				writeu8(out, o + 1, g * 255 + 0.5)
				writeu8(out, o + 2, bl * 255 + 0.5)
			end
			if j % 64 == 63 then
				task.wait()
			end
		end
		faces[name] = out
	end
	macSky = faces
end

-- Sky color (0-255 per channel) in world direction (x, y, z). Roblox's
-- skybox layout, measured in game: Ft faces -Z, Bk +Z, Lf +X, Rt -X; Up and
-- Dn have their image's right edge toward -Z.
local function macSkyColor(sky, x, y, z)
	local ax, ay, az = math.abs(x), math.abs(y), math.abs(z)
	local face, s, t
	if ax >= ay and ax >= az then
		if x > 0 then
			face, s, t = sky.Lf, z / x, y / x
		else
			face, s, t = sky.Rt, z / x, -y / x
		end
	elseif ay >= az then
		if y > 0 then
			face, s, t = sky.Up, -z / y, x / y
		else
			face, s, t = sky.Dn, z / y, x / y
		end
	elseif z < 0 then
		face, s, t = sky.Ft, -x / z, -y / z
	else
		face, s, t = sky.Bk, -x / z, y / z
	end
	local n = sky.size
	local fx = (s + 1) * 0.5 * n - 0.5
	local fy = (1 - t) * 0.5 * n - 0.5
	if fx < 0 then fx = 0 elseif fx > n - 1.001 then fx = n - 1.001 end
	if fy < 0 then fy = 0 elseif fy > n - 1.001 then fy = n - 1.001 end
	local ix, iy = fx // 1, fy // 1
	local tx, ty = fx - ix, fy - iy
	local o = (iy * n + ix) * 3
	local o2 = o + n * 3
	local readu8 = buffer.readu8
	local a, b = readu8(face, o), readu8(face, o2)
	local top = a + (readu8(face, o + 3) - a) * tx
	local red = top + (b + (readu8(face, o2 + 3) - b) * tx - top) * ty
	a, b = readu8(face, o + 1), readu8(face, o2 + 1)
	top = a + (readu8(face, o + 4) - a) * tx
	local green = top + (b + (readu8(face, o2 + 4) - b) * tx - top) * ty
	a, b = readu8(face, o + 2), readu8(face, o2 + 2)
	top = a + (readu8(face, o + 5) - a) * tx
	local blue = top + (b + (readu8(face, o2 + 5) - b) * tx - top) * ty
	return red, green, blue
end

local MAC_LIVE_GLASS = {
	resolution = 0.35, -- of screen pixels: what's behind the glass is soft, so this is plenty
	gridStep = 8, -- screen pixels between sky lookups (interpolated in between)
	minTurn = math.rad(0.03), -- camera turn that triggers a redraw
	maxRate = 40, -- redraws per second, at most
}

-- Live Liquid Glass drawn into `target` (an ImageLabel with a UICorner for
-- its outline). Only the bent, frosted backdrop is drawn here; the tint and
-- the sharp rim light are separate layers on top. The optics are worked out
-- once per size, so a redraw is just sky lookups and interpolation.
local function createMacLiveGlass(target, opts)
	local live = {enabled = false}
	local editable, pixels, ow, oh
	local model = nil
	local R, G, B, T = {}, {}, {}, {}
	local lastLook, lastFov, lastOrigin, lastRender = nil, nil, nil, 0
	local minTurnCos = math.cos(MAC_LIVE_GLASS.minTurn)
	local dirty = true

	function live.layout(newOpts)
		opts = newOpts or opts
		local size = target.AbsoluteSize
		local w, h = math.max(2, math.round(size.X)), math.max(2, math.round(size.Y))
		local nw = math.max(2, math.ceil(w * MAC_LIVE_GLASS.resolution))
		local nh = math.max(2, math.ceil(h * MAC_LIVE_GLASS.resolution))
		if not editable or nw ~= ow or nh ~= oh then
			if editable then
				editable:Destroy()
			end
			editable = AssetService:CreateEditableImage({Size = Vector2.new(nw, nh)})
			target.ImageContent = Content.fromObject(editable)
			ow, oh = nw, nh
			pixels = buffer.create(ow * oh * 4)
			for k = 0, ow * oh - 1 do
				buffer.writeu8(pixels, k * 4 + 3, 255)
			end
		end
		local shapeAt, p = macRoundedRectGlass(w, h, opts)
		local optics = macGlassOptics(p)
		local step = MAC_LIVE_GLASS.gridStep
		local blur = math.max(1, p.blur)
		local margin = math.ceil(blur) + 2 * step
		local gw = math.ceil((w + 2 * margin) / step) + 1
		local gh = math.ceil((h + 2 * margin) / step) + 1
		-- Where each output pixel reads the backdrop grid, per color channel
		-- (the channels bend by slightly different amounts: color fringing)
		local count = ow * oh
		local index, fracX, fracY = {}, {}, {}
		for c = 1, 3 do
			index[c], fracX[c], fracY[c] = table.create(count), table.create(count), table.create(count)
		end
		local bends = {1 + p.aberration, 1, 1 - p.aberration}
		for j = 0, oh - 1 do
			for i = 0, ow - 1 do
				local px, py = (i + 0.5) / ow * w, (j + 0.5) / oh * h
				local depth, nx, ny = shapeAt(px - 0.5, py - 0.5)
				local scale = 0
				if depth > -0.5 then
					scale = optics(depth, nx, ny, p.reach(px - 0.5, py - 0.5, nx, ny))
				end
				local k = j * ow + i + 1
				for c = 1, 3 do
					local gx = math.clamp((px - nx * scale * bends[c] + margin) / step, 0, gw - 1.001)
					local gy = math.clamp((py - ny * scale * bends[c] + margin) / step, 0, gh - 1.001)
					local ix, iy = math.floor(gx), math.floor(gy)
					index[c][k] = iy * gw + ix + 1
					fracX[c][k] = gx - ix
					fracY[c][k] = gy - iy
				end
			end
		end
		-- Gaussian weights for the frost, in grid steps (skipped when tiny)
		local weights, radius = nil, 0
		local sigma = blur / 3 / step
		if sigma > 0.3 then
			radius = math.ceil(sigma * 3)
			weights = {}
			local total = 0
			for k = -radius, radius do
				weights[k] = math.exp(-(k * k) / (2 * sigma * sigma))
				total += weights[k]
			end
			for k = -radius, radius do
				weights[k] /= total
			end
		end
		model = {gw = gw, gh = gh, margin = margin, step = step, index = index, fracX = fracX, fracY = fracY, weights = weights, radius = radius}
		dirty = true
	end

	local function frost(channel)
		local m = model
		local weights, radius, gw, gh = m.weights, m.radius, m.gw, m.gh
		for j = 0, gh - 1 do
			local row = j * gw
			for i = 0, gw - 1 do
				local sum = 0
				for k = -radius, radius do
					local x = i + k
					if x < 0 then x = 0 elseif x >= gw then x = gw - 1 end
					sum += channel[row + x + 1] * weights[k]
				end
				T[row + i + 1] = sum
			end
		end
		for j = 0, gh - 1 do
			for i = 0, gw - 1 do
				local sum = 0
				for k = -radius, radius do
					local y = j + k
					if y < 0 then y = 0 elseif y >= gh then y = gh - 1 end
					sum += T[y * gw + i + 1] * weights[k]
				end
				channel[j * gw + i + 1] = sum
			end
		end
	end

	-- Where the glass is on screen. AbsolutePosition is measured from below
	-- Roblox's top bar, but the camera's viewport starts at the very top, so
	-- go by the ScreenGui's origin (which sits at -inset when it ignores the
	-- inset)
	local function screenPosition()
		local screenGui = target:FindFirstAncestorOfClass("ScreenGui")
		return if screenGui then target.AbsolutePosition - screenGui.AbsolutePosition else target.AbsolutePosition
	end

	local function render(camera)
		local m = model
		local cf = camera.CFrame
		local viewport = camera.ViewportSize
		local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
		local tanX = tanY * viewport.X / viewport.Y
		local look, right, up = cf.LookVector, cf.RightVector, cf.UpVector
		local lx, ly, lz = look.X, look.Y, look.Z
		local rx, ry, rz = right.X, right.Y, right.Z
		local ux, uy, uz = up.X, up.Y, up.Z
		local origin = screenPosition()
		local x0, y0 = origin.X - m.margin, origin.Y - m.margin
		local sky, step, gw = macSky, m.step, m.gw
		-- The sky behind each grid point, from the camera ray through it
		local n = 0
		for j = 0, m.gh - 1 do
			local v = (1 - 2 * (y0 + j * step) / viewport.Y) * tanY
			local bx, by, bz = lx + ux * v, ly + uy * v, lz + uz * v
			for i = 0, gw - 1 do
				local u = (2 * (x0 + i * step) / viewport.X - 1) * tanX
				n += 1
				R[n], G[n], B[n] = macSkyColor(sky, bx + rx * u, by + ry * u, bz + rz * u)
			end
		end
		if m.weights then
			frost(R)
			frost(G)
			frost(B)
		end
		local iR, iG, iB = m.index[1], m.index[2], m.index[3]
		local xR, xG, xB = m.fracX[1], m.fracX[2], m.fracX[3]
		local yR, yG, yB = m.fracY[1], m.fracY[2], m.fracY[3]
		local writeu8 = buffer.writeu8
		local buf = pixels
		for k = 1, ow * oh do
			local i, tx, ty = iR[k], xR[k], yR[k]
			local a, c = R[i], R[i + gw]
			local top = a + (R[i + 1] - a) * tx
			local red = top + (c + (R[i + gw + 1] - c) * tx - top) * ty
			i, tx, ty = iG[k], xG[k], yG[k]
			a, c = G[i], G[i + gw]
			top = a + (G[i + 1] - a) * tx
			local green = top + (c + (G[i + gw + 1] - c) * tx - top) * ty
			i, tx, ty = iB[k], xB[k], yB[k]
			a, c = B[i], B[i + gw]
			top = a + (B[i + 1] - a) * tx
			local blue = top + (c + (B[i + gw + 1] - c) * tx - top) * ty
			local o = (k - 1) * 4
			writeu8(buf, o, red + 0.5)
			writeu8(buf, o + 1, green + 0.5)
			writeu8(buf, o + 2, blue + 0.5)
		end
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(ow, oh), buf)
	end

	-- Call every frame; redraws only when the camera turned or the glass moved
	function live.update(camera)
		if not live.enabled or not macSky or not model then
			return
		end
		local look = camera.CFrame.LookVector
		local fov = camera.FieldOfView
		local origin = screenPosition()
		local now = os.clock()
		if not dirty and lastLook then
			if now - lastRender < 1 / MAC_LIVE_GLASS.maxRate then
				return
			end
			if look:Dot(lastLook) > minTurnCos and fov == lastFov and origin == lastOrigin then
				return
			end
		end
		dirty = false
		lastLook, lastFov, lastOrigin, lastRender = look, fov, origin, now
		render(camera)
	end

	function live.invalidate()
		dirty = true
	end

	function live.destroy()
		live.enabled = false
		model = nil
		if editable then
			editable:Destroy()
			editable = nil
		end
	end

	live.layout()
	return live
end

-- ---------- Session ----------
-- One ScreenGui shared by the lock screen and the desktop, plus the
-- background (wallpaper or 3D scene) that both sit on
local function createMacSession(assets)
	local gui = macNew("ScreenGui", {
		Name = "macOS", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1001,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
	})
	local session = {gui = gui, assets = assets, mode = loadMacBackgroundChoice(), fadeTime = 0.45}
	local listeners = {}
	session.wall = buildMacWallpaper(gui, assets.glow, assets.wallpaper)
	session.wallScale = macNew("UIScale", {Parent = session.wall})
	-- Black cover for restarting
	session.cover = macNew("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 50, Parent = gui,
	})
	-- A copy of the loader's opaque backdrop on top, so macOS is built out of
	-- sight; the first lock screen fades it away, straight out of the loader
	session.veil = background:Clone()
	session.veil.ImageTransparency = 0
	session.veil.ZIndex = 51
	session.veil.Parent = gui

	-- fn(mode, animate) runs whenever the background changes. When animated,
	-- the crossfade takes session.fadeTime.
	function session.onBackground(fn)
		table.insert(listeners, fn)
		return function()
			local i = table.find(listeners, fn)
			if i then
				table.remove(listeners, i)
			end
		end
	end

	local switching = false
	function session.setBackground(mode, animate)
		if switching then
			return
		end
		if mode ~= session.mode then
			saveMacBackgroundChoice(mode)
		end
		session.mode = mode
		local showWall = mode == "wallpaper"
		-- The Lithora backdrop in the main UI would dim the 3D scene, so clear it
		local backdropTransparency = if showWall then 0.1 else 1
		for _, fn in ipairs(table.clone(listeners)) do
			task.spawn(fn, mode, animate)
		end
		if not animate then
			session.wall.Visible = showWall
			background.ImageTransparency = backdropTransparency
			return
		end
		switching = true
		-- Crossfade: the wallpaper rides in a CanvasGroup just for the fade
		local info = TweenInfo.new(session.fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local fader = macNew("CanvasGroup", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			GroupTransparency = if showWall then 1 else 0, Parent = gui,
		})
		session.wall.Visible = true
		session.wall.Parent = fader
		TweenService:Create(background, info, {ImageTransparency = backdropTransparency}):Play()
		local fade = TweenService:Create(fader, info, {GroupTransparency = if showWall then 0 else 1})
		fade:Play()
		fade.Completed:Wait()
		session.wall.Parent = gui
		session.wall.Visible = showWall
		fader:Destroy()
		switching = false
	end

	function session.fadeCover(transparency, time)
		local fade = TweenService:Create(session.cover, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {BackgroundTransparency = transparency})
		fade:Play()
		fade.Completed:Wait()
	end

	session.setBackground(session.mode, false)
	return session
end

-- ---------- Desktop ----------
local MAC_NOTES_FILE = MACOS_FOLDER .. "/Notes.txt"
local MAC_TRASH_PATH = "::trash"
local MAC_TEXT_EXTENSIONS = {
	txt = true, lua = true, luau = true, json = true, md = true, log = true, cfg = true, ini = true,
	csv = true, xml = true, html = true, css = true, js = true, toml = true, yaml = true, yml = true,
}
local MAC_IMAGE_EXTENSIONS = {png = true, jpg = true, jpeg = true}
local MAC_AUDIO_EXTENSIONS = {mp3 = true, ogg = true, wav = true}

local function macExtension(name)
	return (name:match("%.([%w]+)$") or ""):lower()
end

-- Kind text and icon for a file in Finder
local function macFileKind(name, isFolder)
	if isFolder then
		return "Folder", MAC_DESKTOP_ICONS.folder
	end
	local ext = macExtension(name)
	if MAC_IMAGE_EXTENSIONS[ext] then
		return ext:upper() .. " image", MAC_DESKTOP_ICONS.fileImage
	elseif MAC_AUDIO_EXTENSIONS[ext] then
		return ext:upper() .. " audio", MAC_DESKTOP_ICONS.fileAudio
	elseif ext == "lua" or ext == "luau" then
		return "Luau script", MAC_DESKTOP_ICONS.fileCode
	elseif ext == "ttf" or ext == "otf" then
		return "Font", MAC_DESKTOP_ICONS.file
	elseif MAC_TEXT_EXTENSIONS[ext] then
		return "Plain text", MAC_DESKTOP_ICONS.fileText
	end
	return if ext ~= "" then ext:upper() .. " file" else "Document", MAC_DESKTOP_ICONS.file
end

-- Entries of a workspace folder ("" = the workspace itself), folders first
local function macListFolder(path)
	local entries = {}
	for _, item in ipairs(listfiles(path)) do
		local itemPath = item:gsub("\\", "/"):gsub("^%./", ""):gsub("/$", "")
		local ok, folder = pcall(isfolder, itemPath)
		table.insert(entries, {name = itemPath:match("([^/]+)$") or itemPath, path = itemPath, folder = ok and folder == true})
	end
	table.sort(entries, function(a, b)
		if a.folder ~= b.folder then
			return a.folder
		end
		return a.name:lower() < b.name:lower()
	end)
	return entries
end

local function createMacDesktop(session)
	local gui, assets = session.gui, session.assets
	local D, C, I = MAC_DESK, MAC_COLORS, MAC_DESKTOP_ICONS
	local desktop = {}
	local alive = true
	local connections = {}
	local pendingAction = nil
	local function connect(signal, fn)
		local connection = signal:Connect(fn)
		table.insert(connections, connection)
		return connection
	end
	local function tween(instance, time, props, style, direction)
		local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out), props)
		t:Play()
		return t
	end
	local function finish(action)
		pendingAction = action
	end

	-- Laid out in points (see MAC_DESK.height) and scaled to the real screen
	local root = macNew("Frame", {Name = "Desktop", BackgroundTransparency = 1, ZIndex = 2, Visible = false, Parent = gui})
	local rootScale = macNew("UIScale", {Parent = root})
	local s = 1 -- screen pixels per point
	local screenW = 0 -- screen width in points (the height is always D.height)
	local layoutCallbacks = {}
	local function relayout()
		local size = gui.AbsoluteSize
		if size.Y < 1 then
			return
		end
		s = size.Y / D.height
		screenW = size.X / s
		rootScale.Scale = s
		root.Size = UDim2.fromOffset(screenW, D.height)
		for _, fn in ipairs(layoutCallbacks) do
			task.spawn(fn)
		end
	end
	local function getScale()
		return s
	end

	-- Over the bright 3D sky, a soft shade keeps the white menu bar readable
	local shade = macNew("Frame", {
		Name = "SceneShade", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 120), BackgroundTransparency = 1, Parent = root,
	})
	macNew("UIGradient", {
		Rotation = 90, Parent = shade,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.5, 0.82), NumberSequenceKeypoint.new(1, 1),
		}),
	})
	local windowLayer = macNew("Frame", {Name = "Windows", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = root})
	local overlay = macNew("Frame", {Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = root})

	local refreshDock, refreshMenuBar, openApp, dockIconCenter, closeMenu
	local dock
	local openMenu = nil -- {panel, catcher, button}

	local dockHeight = D.dockIcon + 2 * D.dockPadding
	local dockWidth = 2 * D.dockPadding + (#MAC_APPS + 1) * D.dockIcon + (#MAC_APPS - 1) * D.dockGap + D.dockSeparator
	local function dockTop()
		return D.height - D.dockBottom - dockHeight
	end
	-- Free area between the menu bar and the Dock, in points
	local function workArea()
		return 10, D.menuHeight + 8, screenW - 20, dockTop() - D.menuHeight - 18
	end
	-- Where an object is on screen, in pixels from the very top. Its
	-- AbsolutePosition is measured from below Roblox's top bar, which this
	-- gui covers (it ignores the inset), as does the mouse location.
	local function screenPos(object)
		return object.AbsolutePosition - gui.AbsolutePosition
	end
	local function pointIn(object, point)
		local p, size = screenPos(object), object.AbsoluteSize
		return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + size.X and point.Y <= p.Y + size.Y
	end

	-- ---------- Windows ----------
	local windows = {} -- open windows, back to front
	local frontWindow = nil
	local zCounter = 10
	local cascade = 0
	local drag = nil -- {win, start, origin} while a title bar is dragged

	local function windowsOf(appId)
		local list = {}
		for _, win in ipairs(windows) do
			if win.app == appId then
				table.insert(list, win)
			end
		end
		return list
	end

	local function topVisibleWindow()
		for i = #windows, 1, -1 do
			if not windows[i].minimized then
				return windows[i]
			end
		end
		return nil
	end

	local function setWindowActive(win, active)
		win.active = active
		win.shadow.ImageTransparency = if active then 0.5 else 0.72
		win.paintLights()
	end

	local function focusWindow(win)
		if win.closed then
			return
		end
		if frontWindow and frontWindow ~= win and not frontWindow.closed then
			setWindowActive(frontWindow, false)
		end
		local i = table.find(windows, win)
		if i then
			table.remove(windows, i)
		end
		table.insert(windows, win)
		zCounter += 1
		win.frame.ZIndex = zCounter
		-- Mid-animation the window rides in a CanvasGroup, which has to come forward too
		local group = win.frame.Parent
		if group and group:IsA("CanvasGroup") then
			group.ZIndex = zCounter
		end
		frontWindow = win
		setWindowActive(win, true)
		refreshMenuBar()
	end

	-- Fades, scales and moves a window as one piece by riding it in a
	-- CanvasGroup; it goes back to a plain frame afterwards so text stays sharp.
	-- `from`/`to`: {scale, transparency, center (points)}; center defaults to
	-- the window's own.
	local function animateWindow(win, info, from, to)
		local frame = win.frame
		local pad = D.shadowBlur + 24
		local size = Vector2.new(frame.Size.X.Offset, frame.Size.Y.Offset)
		-- Already animating (closed or minimized while it was still opening):
		-- carry on from where that animation is, toward the same home spot
		local current = frame.Parent
		if current and current:IsA("CanvasGroup") and win.home then
			local currentScale = current:FindFirstChildOfClass("UIScale")
			from = {
				scale = from.scale or (currentScale and currentScale.Scale),
				transparency = from.transparency or current.GroupTransparency,
				center = from.center or Vector2.new(current.Position.X.Offset, current.Position.Y.Offset),
			}
		else
			win.home = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset) + size / 2
		end
		local home = win.home
		local start = from.center or home
		local group = macNew("CanvasGroup", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size.X + 2 * pad, size.Y + 2 * pad), Position = UDim2.fromOffset(start.X, start.Y),
			GroupTransparency = from.transparency or 0, ZIndex = frame.ZIndex, Parent = windowLayer,
		})
		local scale = macNew("UIScale", {Scale = from.scale or 1, Parent = group})
		frame.Position = UDim2.fromOffset(pad, pad)
		frame.Parent = group
		frame.Visible = true
		TweenService:Create(scale, info, {Scale = to.scale or 1}):Play()
		local target = to.center or home
		local motion = TweenService:Create(group, info, {GroupTransparency = to.transparency or 0, Position = UDim2.fromOffset(target.X, target.Y)})
		motion:Play()
		motion.Completed:Wait()
		if frame.Parent == group then
			frame.Parent = windowLayer
			frame.Position = UDim2.fromOffset(home.X - size.X / 2, home.Y - size.Y / 2)
			win.home = nil
		end
		group:Destroy()
	end

	-- spec: {app, title, width, height, build(win), background?, dark?,
	-- sidebarWidth?, titleLeft?, fixedSize?, onClose?, menuName?}
	local function openWindow(spec)
		local win = {app = spec.app, minimized = false, zoomed = false, closed = false, active = false, cleanup = {}}
		local ax, ay, aw, ah = workArea()
		local width, height = math.min(spec.width, aw), math.min(spec.height, ah)
		local x = math.floor(ax + (aw - width) / 2 + cascade * 24)
		local y = math.floor(ay + math.max(0, (ah - height) / 2 - 30) + cascade * 24)
		cascade = (cascade + 1) % 5

		local frame = macNew("Frame", {
			Name = spec.title, BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, height), Parent = windowLayer,
		})
		-- Soft drop shadow: the glow image as a 9-slice
		local blur = D.shadowBlur
		local shadow = macNew("ImageLabel", {
			Name = "Shadow", BackgroundTransparency = 1, Image = assets.glow or "", ImageColor3 = Color3.new(0, 0, 0),
			ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(63, 63, 65, 65), SliceScale = blur / 63,
			Position = UDim2.fromOffset(12 - blur, 26 - blur), Size = UDim2.new(1, 2 * blur - 24, 1, 2 * blur - 24),
			ImageTransparency = 0.5, Parent = frame,
		})
		-- The body is a button so clicks on empty parts of the window don't fall through
		local body = macButton(frame, {
			Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0,
			BackgroundColor3 = spec.background or C.window, ZIndex = 2,
		})
		macCorner(body, D.windowRadius)
		macStroke(body, Color3.new(0, 0, 0), if spec.dark then 0.4 else 0.86, 1)
		win.frame, win.body, win.shadow = frame, body, shadow

		-- Title bar: drag to move, double-click to zoom
		local handle = macButton(body, {Name = "TitleBar", Size = UDim2.new(1, 0, 0, D.titleBar), ZIndex = 1})
		local lastTitleClick = 0
		handle.MouseButton1Down:Connect(function()
			focusWindow(win)
			local now = os.clock()
			if now - lastTitleClick < 0.35 and not spec.fixedSize then
				lastTitleClick = 0
				win.zoom()
				return
			end
			lastTitleClick = now
			drag = {win = win, start = UserInputService:GetMouseLocation(), origin = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)}
		end)

		local titleLabel = macLabel(body, spec.title, 14, Enum.FontWeight.SemiBold,
			if spec.dark then Color3.fromRGB(205, 205, 210) else C.ink, {ZIndex = 3, TextTruncate = Enum.TextTruncate.AtEnd})
		if spec.titleLeft then
			titleLabel.Position = UDim2.fromOffset(spec.titleLeft, 0)
			titleLabel.Size = UDim2.new(1, -spec.titleLeft - 16, 0, D.titleBar)
		else
			titleLabel.Position = UDim2.fromOffset(84, 0)
			titleLabel.Size = UDim2.new(1, -168, 0, D.titleBar)
			titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		end
		-- The Window menu lists windows by title (`menuName` for untitled ones)
		win.title = if spec.title ~= "" then spec.title else spec.menuName or MAC_APP_NAMES[spec.app] or spec.app
		function win.setTitle(text)
			titleLabel.Text = text
			win.title = text
		end

		-- Traffic lights: close, minimize, zoom (symbols show on hover)
		local lightsFrame = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 19), Size = UDim2.fromOffset(54, 14), ZIndex = 6, Parent = body})
		local lightDefs = {
			{Color3.fromRGB(255, 95, 87), I.close, Color3.fromRGB(110, 10, 6), true},
			{Color3.fromRGB(254, 188, 46), I.minus, Color3.fromRGB(140, 80, 0), true},
			{Color3.fromRGB(40, 200, 64), I.plus, Color3.fromRGB(0, 100, 10), not spec.fixedSize},
		}
		local lights = {}
		local hoveringLights = false
		for i, def in ipairs(lightDefs) do
			local light = macButton(lightsFrame, {
				Position = UDim2.fromOffset((i - 1) * 20, 0), Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 0, BackgroundColor3 = def[1], ZIndex = 6,
			})
			macCorner(light, UDim.new(1, 0))
			macStroke(light, Color3.new(0, 0, 0), 0.86, 1)
			local glyph = macImage(light, def[2], 10, def[3], {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ImageTransparency = 1, ZIndex = 7,
			})
			lights[i] = {button = light, glyph = glyph, color = def[1], enabled = def[4]}
		end
		-- Unlit buttons are grey: light on light windows, dark on dark ones
		local unlit = if spec.dark then Color3.fromRGB(74, 74, 80) else Color3.fromRGB(206, 206, 210)
		function win.paintLights()
			for _, light in ipairs(lights) do
				local lit = light.enabled and (win.active or hoveringLights)
				light.button.BackgroundColor3 = if lit then light.color else unlit
				light.glyph.ImageTransparency = if hoveringLights and light.enabled then 0.25 else 1
			end
		end
		lightsFrame.MouseEnter:Connect(function()
			hoveringLights = true
			win.paintLights()
		end)
		lightsFrame.MouseLeave:Connect(function()
			hoveringLights = false
			win.paintLights()
		end)
		lights[1].button.MouseButton1Click:Connect(function()
			win.close()
		end)
		lights[2].button.MouseButton1Click:Connect(function()
			win.minimize()
		end)
		lights[3].button.MouseButton1Click:Connect(function()
			if lights[3].enabled then
				win.zoom()
			end
		end)

		-- Content sits under the title bar; a sidebar (Tahoe: a rounded panel
		-- floating inside the window) takes the left side from the top
		win.content = macNew("Frame", {
			Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, D.titleBar),
			Size = UDim2.new(1, 0, 1, -D.titleBar), ZIndex = 2, Parent = body,
		})
		if spec.sidebarWidth then
			win.sidebar = macNew("Frame", {
				Name = "Sidebar", BackgroundColor3 = C.sidebar, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 8),
				Size = UDim2.new(0, spec.sidebarWidth, 1, -16), ZIndex = 2, Parent = body,
			})
			macCorner(win.sidebar, D.windowRadius - 6)
			win.content.Position = UDim2.fromOffset(spec.sidebarWidth + 16, D.titleBar)
			win.content.Size = UDim2.new(1, -(spec.sidebarWidth + 16), 1, -D.titleBar)
		end

		local function forget()
			if drag and drag.win == win then
				drag = nil
			end
			local i = table.find(windows, win)
			if i then
				table.remove(windows, i)
			end
		end

		function win.close(instant)
			if win.closed then
				return
			end
			win.closed = true
			for _, item in ipairs(win.cleanup) do
				if typeof(item) == "RBXScriptConnection" then
					item:Disconnect()
				else
					pcall(item)
				end
			end
			if spec.onClose then
				task.spawn(spec.onClose)
			end
			forget()
			if frontWindow == win then
				frontWindow = nil
				local nextWindow = topVisibleWindow()
				if nextWindow then
					focusWindow(nextWindow)
				end
			end
			refreshDock()
			refreshMenuBar()
			if instant or win.minimized or not root.Visible then
				frame:Destroy()
				return
			end
			task.spawn(function()
				animateWindow(win, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {}, {scale = 0.92, transparency = 1})
				frame:Destroy()
			end)
		end

		function win.minimize()
			if win.minimized or win.closed then
				return
			end
			win.minimized = true
			if drag and drag.win == win then
				drag = nil
			end
			if frontWindow == win then
				frontWindow = nil
				setWindowActive(win, false)
				local nextWindow = topVisibleWindow()
				if nextWindow then
					focusWindow(nextWindow)
				else
					refreshMenuBar()
				end
			end
			refreshDock()
			local target = dockIconCenter(win.app)
			task.spawn(function()
				animateWindow(win, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {}, {scale = 0.08, transparency = 1, center = target})
				if win.minimized and not win.closed then
					frame.Visible = false
				end
			end)
		end

		function win.restore()
			if not win.minimized or win.closed then
				return
			end
			win.minimized = false
			focusWindow(win)
			refreshDock()
			task.spawn(animateWindow, win, TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {scale = 0.08, transparency = 1, center = dockIconCenter(win.app)}, {})
		end

		function win.zoom()
			if win.closed or spec.fixedSize then
				return
			end
			if win.zoomed then
				win.zoomed = false
				tween(frame, 0.3, {Position = win.normalPosition, Size = win.normalSize})
			else
				win.zoomed = true
				win.normalPosition, win.normalSize = frame.Position, frame.Size
				local zx, zy, zw, zh = workArea()
				tween(frame, 0.3, {Position = UDim2.fromOffset(zx, zy), Size = UDim2.fromOffset(zw, zh)})
			end
		end

		table.insert(windows, win)
		focusWindow(win)
		local ok, err = pcall(spec.build, win)
		if not ok then
			warn("[coolui] " .. tostring(spec.title) .. " failed to open: " .. tostring(err))
			macLabel(win.content, "Something went wrong opening this window.", 14, Enum.FontWeight.Medium, C.inkSoft, {
				Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
		refreshDock()
		task.spawn(animateWindow, win, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {scale = 0.94, transparency = 1}, {})
		return win
	end

	-- Dragging windows by the title bar
	connect(UserInputService.InputChanged, function(input)
		if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local win = drag.win
		if win.closed or win.minimized or win.frame.Parent ~= windowLayer then
			return
		end
		local delta = (UserInputService:GetMouseLocation() - drag.start) / s
		local x = math.clamp(drag.origin.X + delta.X, 80 - win.frame.Size.X.Offset, screenW - 80)
		local y = math.clamp(drag.origin.Y + delta.Y, D.menuHeight, D.height - 60)
		win.frame.Position = UDim2.fromOffset(x, y)
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			drag = nil
		end
	end)
	-- Clicking anywhere on a window brings it to the front
	connect(UserInputService.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not root.Visible then
			return
		end
		local point = UserInputService:GetMouseLocation()
		if openMenu or point.Y <= D.menuHeight * s or pointIn(dock, point) then
			return
		end
		for i = #windows, 1, -1 do
			local win = windows[i]
			if not win.minimized and win.frame.Parent == windowLayer and pointIn(win.body, point) then
				if win ~= frontWindow then
					focusWindow(win)
				end
				return
			end
		end
	end)

	-- ---------- Menu bar ----------
	local white = Color3.new(1, 1, 1)
	local menuBar = macNew("Frame", {Name = "MenuBar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, D.menuHeight), ZIndex = 4, Parent = root})
	local menuLeft = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.7, 0, 1, 0), Parent = menuBar})
	macNew("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = menuLeft,
	})
	-- Roblox's own buttons stay in the top-left corner (they can't be hidden),
	-- so the Apple menu starts just to the right of them
	local robloxGui = game:GetService("GuiService")
	local function layoutMenuLeft()
		local inset = robloxGui.TopbarInset
		menuLeft.Position = UDim2.fromOffset(if inset.Min.X > 0 then inset.Min.X / s + 8 else 10, 0)
	end
	table.insert(layoutCallbacks, layoutMenuLeft)
	connect(robloxGui:GetPropertyChangedSignal("TopbarInset"), layoutMenuLeft)

	function closeMenu()
		if not openMenu then
			return
		end
		openMenu.panel:Destroy()
		openMenu.catcher:Destroy()
		if openMenu.button.Parent then
			openMenu.button.BackgroundTransparency = 1
		end
		openMenu = nil
	end

	-- Opens an empty dropdown under a menu bar item. Returns the frame its
	-- rows go in (they stack top to bottom) and the dropdown itself.
	local function openPanel(button, width, radius)
		closeMenu()
		local catcher = macButton(overlay, {Size = UDim2.fromScale(1, 1), ZIndex = 1})
		catcher.MouseButton1Down:Connect(closeMenu)
		local x = math.max(6, math.min(button.AbsolutePosition.X / s - 4, screenW - width - 6))
		local panel = macNew("Frame", {
			BackgroundColor3 = C.menu, BackgroundTransparency = 0.04, BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, D.menuHeight + 3), Size = UDim2.fromOffset(width, 0),
			AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 2, Active = true, Parent = overlay,
		})
		macCorner(panel, radius or 11)
		macStroke(panel, Color3.new(0, 0, 0), 0.86, 1)
		local rows = macNew("Frame", {
			Name = "Rows", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 3, Parent = panel,
		})
		macNew("UIPadding", {
			PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5),
			PaddingRight = UDim.new(0, 5), Parent = rows,
		})
		macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = rows})
		button.BackgroundTransparency = 0.72
		openMenu = {panel = panel, catcher = catcher, button = button}
		return rows, panel
	end

	-- Colors for a dropdown's contents: dark on the frosted menus, white on
	-- the clear glass ones (like the menu bar)
	local MENU_STYLE = {ink = C.ink, soft = C.inkSoft, softFade = 0, line = Color3.new(0, 0, 0), lineFade = 0.88}
	local CLEAR_STYLE = {ink = white, soft = white, softFade = 0.3, line = white, lineFade = 0.7}

	local function menuSeparator(parent, order, style)
		style = style or MENU_STYLE
		local separator = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 11), LayoutOrder = order, Parent = parent})
		macNew("Frame", {
			BackgroundColor3 = style.line, BackgroundTransparency = style.lineFade, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -18, 0, 1), Parent = separator,
		})
	end

	-- item: {text, action (nil = greyed out), checked = bool}. `textLeft`
	-- leaves room for the check mark (status menus have none).
	local function menuItem(parent, item, order, textLeft, style)
		textLeft = textLeft or 26
		style = style or MENU_STYLE
		local action = item[2]
		local row = macButton(parent, {Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, BackgroundColor3 = C.accent, ZIndex = 3})
		macCorner(row, 6)
		local text = macLabel(row, item[1], 14, Enum.FontWeight.Regular, style.ink, {
			Position = UDim2.fromOffset(textLeft, 0), Size = UDim2.new(1, -textLeft - 6, 1, 0), ZIndex = 4,
			TextTransparency = if action then 0 else 0.6, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local check = nil
		if item.checked then
			check = macImage(row, I.check, 14, style.ink, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 7, 0.5, 0), ZIndex = 4})
		end
		if action then
			row.MouseEnter:Connect(function()
				row.BackgroundTransparency = 0
				text.TextColor3 = white
				if check then
					check.ImageColor3 = white
				end
			end)
			row.MouseLeave:Connect(function()
				row.BackgroundTransparency = 1
				text.TextColor3 = style.ink
				if check then
					check.ImageColor3 = style.ink
				end
			end)
			row.MouseButton1Click:Connect(function()
				closeMenu()
				task.spawn(action)
			end)
		end
	end

	-- items: list of {text, action (nil = greyed out), checked = bool} or "-"
	local function showMenu(button, items)
		local panel = openPanel(button, 260)
		for i, item in ipairs(items) do
			if item == "-" then
				menuSeparator(panel, i)
			else
				menuItem(panel, item, i)
			end
		end
	end

	local menuTitles = {}
	local function menuTitle(text, weight, order, items, icon)
		local button = macButton(menuLeft, {
			Size = UDim2.fromOffset(if icon then 38 else 0, 24), AutomaticSize = if icon then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
			BackgroundColor3 = white, LayoutOrder = order, FontFace = macFont(weight), TextSize = 14,
			TextColor3 = white, Text = text,
		})
		macCorner(button, 6)
		if icon then
			macImage(button, icon, 17, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48)})
		else
			macNew("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = button})
		end
		button.MouseButton1Down:Connect(function()
			if openMenu and openMenu.button == button then
				closeMenu()
			else
				showMenu(button, items())
			end
		end)
		-- Like macOS: with a menu open, moving across the titles opens the others
		button.MouseEnter:Connect(function()
			if openMenu and openMenu.button ~= button then
				showMenu(button, items())
			end
		end)
		return button
	end

	local function frontAction(method)
		local win = frontWindow
		if not win then
			return nil
		end
		return function()
			if not win.closed then
				win[method]()
			end
		end
	end

	menuTitle("", Enum.FontWeight.Bold, 1, function()
		return {
			{"About This Mac", function()
				openApp("about")
			end},
			"-",
			{"System Settings…", function()
				openApp("settings")
			end},
			"-",
			{"Restart…", function()
				finish("restart")
			end},
			{"Shut Down…", function()
				finish("shutdown")
			end},
			"-",
			{"Lock Screen", function()
				finish("lock")
			end},
			{"Log Out " .. player.DisplayName .. "…", function()
				finish("logout")
			end},
		}
	end, I.apple)

	local standardMenus = {
		{"File", function()
			return {
				{"New Finder Window", function()
					openApp("finder", {newWindow = true})
				end},
				{"Open Notes", function()
					openApp("notes")
				end},
				"-",
				{"Close Window", frontAction("close")},
			}
		end},
		{"Edit", function()
			return {{"Undo"}, {"Redo"}, "-", {"Cut"}, {"Copy"}, {"Paste"}, {"Select All"}}
		end},
		{"View", function()
			return {
				{"Tahoe Wallpaper", function()
					session.setBackground("wallpaper", true)
				end, checked = session.mode == "wallpaper"},
				{"3D Scene", function()
					session.setBackground("scene", true)
				end, checked = session.mode == "scene"},
			}
		end},
		{"Window", function()
			local items = {
				{"Minimize", frontAction("minimize")},
				{"Zoom", frontAction("zoom")},
				"-",
				{"Bring All to Front", if #windows > 0 then function()
					for _, win in ipairs(table.clone(windows)) do
						if win.minimized then
							win.restore()
						else
							focusWindow(win)
						end
					end
				end else nil},
			}
			if #windows > 0 then
				table.insert(items, "-")
				for _, win in ipairs(windows) do
					table.insert(items, {win.title, function()
						if win.minimized then
							win.restore()
						elseif not win.closed then
							focusWindow(win)
						end
					end, checked = win == frontWindow})
				end
			end
			return items
		end},
		{"Help", function()
			return {{"macOS Help"}}
		end},
	}

	function refreshMenuBar()
		-- The titles are rebuilt, so close a menu that hangs off one of them
		if openMenu and table.find(menuTitles, openMenu.button) then
			closeMenu()
		end
		for _, button in ipairs(menuTitles) do
			button:Destroy()
		end
		table.clear(menuTitles)
		local appId = if frontWindow then frontWindow.app else "finder"
		local appName = MAC_APP_NAMES[appId] or "Finder"
		table.insert(menuTitles, menuTitle(appName, Enum.FontWeight.Bold, 2, function()
			local items = {{"About " .. appName, function()
				openApp("about")
			end}}
			if appId ~= "finder" and appId ~= "about" then
				table.insert(items, "-")
				table.insert(items, {"Quit " .. appName, function()
					for _, win in ipairs(windowsOf(appId)) do
						win.close()
					end
				end})
			end
			return items
		end))
		for i, menu in ipairs(standardMenus) do
			table.insert(menuTitles, menuTitle(menu[1], Enum.FontWeight.Medium, 2 + i, menu[2]))
		end
	end

	-- ---------- Status menus (battery, Wi-Fi) ----------
	local function panelHeader(parent, title, order, style)
		local row = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, Parent = parent})
		macLabel(row, title, 14, Enum.FontWeight.Bold, style.ink, {Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -18, 1, 0)})
		return row
	end

	-- (12, not 13: at 13 Roblox clips the tail of a final "y")
	local function panelText(parent, text, order, style, size, weight)
		local row = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order, Parent = parent})
		return macLabel(row, text, size or 12, weight or Enum.FontWeight.Regular, style.soft, {
			Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -18, 1, 0), TextTransparency = style.softFade,
		})
	end

	-- The current network: its icon in a circle (blue while connected), its
	-- name and status. update() refreshes it.
	local function panelNetwork(parent, order, style)
		local row = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = order, Parent = parent})
		local circle = macNew("Frame", {
			BackgroundColor3 = C.accent, BorderSizePixel = 0, Position = UDim2.fromOffset(7, 6), Size = UDim2.fromOffset(28, 28), Parent = row,
		})
		macCorner(circle, UDim.new(1, 0))
		local holder = macNew("Frame", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16), Parent = circle,
		})
		local glyph = macWifiGlyph(holder, white)
		local title = macLabel(row, "", 14, Enum.FontWeight.Medium, style.ink, {
			Position = UDim2.fromOffset(44, 4), Size = UDim2.new(1, -52, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local status = macLabel(row, "", 12, Enum.FontWeight.Regular, style.soft, {
			Position = UDim2.fromOffset(44, 21), Size = UDim2.new(1, -52, 0, 15), TextTransparency = style.softFade,
		})
		local network = {}
		function network.update()
			local state = macReadNetwork()
			glyph.set(state, true)
			circle.BackgroundColor3 = if state.connected then C.accent else Color3.fromRGB(150, 150, 158)
			title.Text = if state.wifiOn then macGameName() else "Ethernet"
			status.Text = if not state.connected then "Not Connected"
				elseif state.ping then "Connected · " .. state.ping .. " ms"
				else "Connected"
		end
		network.update()
		return network
	end

	-- Clear Liquid Glass behind a status menu, like the Dock: rendered against
	-- the wallpaper (cached per size and place, so only the very first opening
	-- renders it) or drawn live over the 3D scene. Returns the colors for the
	-- menu's contents: white on the glass, dark on the frosted menu used when
	-- there's no glass (a custom wallpaper image).
	local STATUS_RADIUS = 14
	local STATUS_HEIGHT = 150 -- about how tall the status menus are, in points
	local menuGlass = nil -- the open status menu's live glass

	-- How see-through (0-1) the shade under the menu bar is, `y` points from
	-- the top of the screen
	local function shadeAt(y)
		local f = math.clamp(y / shade.Size.Y.Offset, 0, 1)
		local points = shade:FindFirstChildOfClass("UIGradient").Transparency.Keypoints
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			if f <= b.Time then
				return a.Value + (b.Value - a.Value) * (f - a.Time) / (b.Time - a.Time)
			end
		end
		return points[#points].Value
	end

	-- How bright (0-1) the backdrop is behind a rect (pixels from the top of
	-- the screen). Clear glass over something bright gets dark text, like on
	-- a Mac, since white text would vanish into a bright sky.
	local function backdropBrightness(x, y, w, h)
		local camera = workspace.CurrentCamera
		local sample = if session.mode == "wallpaper" then macSamplerFor(gui.AbsoluteSize.X, gui.AbsoluteSize.Y) else nil
		local total, count = 0, 0
		for j = 0, 4 do
			for i = 0, 6 do
				local px, py = x + w * (i + 0.5) / 7, y + h * (j + 0.5) / 5
				local r, g, b
				if sample then
					r, g, b = sample(px, py)
				else
					-- The 3D sky, darkened by the shade under the menu bar
					local d = camera:ViewportPointToRay(px, py).Direction
					local dim = shadeAt(py / s) / 255
					r, g, b = macSkyColor(macSky, d.X, d.Y, d.Z)
					r, g, b = r * dim, g * dim, b * dim
				end
				total += r * 0.299 + g * 0.587 + b * 0.114
				count += 1
			end
		end
		return total / count
	end

	local function addMenuGlass(panel, name)
		local baked = session.mode == "wallpaper" and not assets.wallpaper and assets.glow ~= nil
		local live = session.mode == "scene" and macSky ~= nil
		if not baked and not live then
			return MENU_STYLE
		end
		-- Over the 3D scene: frosted glass (always dark text) with a faint
		-- outline against the bright sky. On the wallpaper: clear glass.
		local bright = live
		if not live then
			pcall(function()
				bright = backdropBrightness(panel.Position.X.Offset * s, panel.Position.Y.Offset * s, panel.Size.X.Offset * s, STATUS_HEIGHT * s) > 0.6
			end)
		end
		local stroke = panel:FindFirstChildOfClass("UIStroke")
		panel.BackgroundTransparency = 1
		stroke.Transparency = if live then 0.9 else 1
		task.spawn(function()
			RunService.RenderStepped:Wait() -- let the menu size itself first
			if not panel.Parent then
				return
			end
			local layers = {}
			local ok, err = pcall(function()
				-- AbsolutePosition starts below the top bar; the wallpaper starts at the top
				local pos, size = panel.AbsolutePosition - gui.AbsolutePosition, panel.AbsoluteSize
				local opts = table.clone(if live then MAC_MENU_FROSTED_GLASS else MAC_MENU_GLASS)
				opts.cornerRadius = STATUS_RADIUS * s
				local pane = macNew("ImageLabel", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageTransparency = 1, ZIndex = 1, Parent = panel})
				macCorner(pane, STATUS_RADIUS)
				table.insert(layers, {pane, "ImageTransparency", 0})
				if baked then
					local screen = gui.AbsoluteSize
					pane.Image = bakeMacGlass("clearmenu_" .. name, pos.X, pos.Y, size.X, size.Y, screen.X, screen.Y, opts)
				else
					local tint = macNew("Frame", {
						BackgroundColor3 = opts.tint, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
						ZIndex = 2, Parent = panel,
					})
					macCorner(tint, STATUS_RADIUS)
					local rim = macNew("ImageLabel", {
						BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageTransparency = 1, ZIndex = 2,
						Image = bakeMacGlassRim("frostedmenu", size.X, size.Y, opts), Parent = panel,
					})
					table.insert(layers, {tint, "BackgroundTransparency", 1 - opts.tintAlpha})
					table.insert(layers, {rim, "ImageTransparency", 0})
					-- The live glass draws the bare sky, but behind the menu the
					-- sky is darkened by the shade under the menu bar: copy the
					-- part of that shade the menu covers
					local top, height = panel.Position.Y.Offset, size.Y / s
					local keypoints = {}
					for i = 0, 10 do
						table.insert(keypoints, NumberSequenceKeypoint.new(i / 10, shadeAt(top + height * i / 10)))
					end
					local shadeCopy = macNew("Frame", {
						BackgroundColor3 = shade.BackgroundColor3, BackgroundTransparency = 1, BorderSizePixel = 0,
						Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = panel,
					})
					macCorner(shadeCopy, STATUS_RADIUS)
					macNew("UIGradient", {Rotation = 90, Transparency = NumberSequence.new(keypoints), Parent = shadeCopy})
					table.insert(layers, {shadeCopy, "BackgroundTransparency", shade.BackgroundTransparency})
					local glass = createMacLiveGlass(pane, opts)
					glass.enabled = true
					glass.update(workspace.CurrentCamera)
					menuGlass = glass
					panel.Destroying:Connect(function()
						glass.destroy()
						if menuGlass == glass then
							menuGlass = nil
						end
					end)
				end
				local images = {}
				for _, layer in ipairs(layers) do
					table.insert(images, layer[1])
				end
				ContentProvider:PreloadAsync(images)
			end)
			if not panel.Parent then
				return
			end
			if not ok then
				-- A frosted fill behind the text instead (dark under white text)
				warn("[coolui] menu glass failed: " .. tostring(err))
				panel.BackgroundColor3 = if bright then C.menu else Color3.fromRGB(44, 44, 50)
				panel.BackgroundTransparency = if bright then 0.04 else 0.15
				return
			end
			for _, layer in ipairs(layers) do
				tween(layer[1], 0.12, {[layer[2]] = layer[3]}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
		end)
		return if bright then MENU_STYLE else CLEAR_STYLE
	end

	local function showWifiMenu(button)
		local panel, frame = openPanel(button, 290, STATUS_RADIUS)
		local style = addMenuGlass(frame, "wifi")
		local header = panelHeader(panel, "Wi-Fi", 1, style)
		local toggle = macToggle(header, macNetwork.wifiOn, macSetWifi)
		toggle.button.AnchorPoint = Vector2.new(1, 0.5)
		toggle.button.Position = UDim2.new(1, -8, 0.5, 0)
		local body, network = nil, nil
		local function fill()
			if body then
				body:Destroy()
			end
			toggle.set(macNetwork.wifiOn)
			body = macNew("Frame", {
				BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0),
				LayoutOrder = 2, Parent = panel,
			})
			macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = body})
			menuSeparator(body, 1, style)
			-- With Wi-Fi off the game is still connected, so it must be wired
			panelText(body, if macNetwork.wifiOn then "Known Network" else "Other Connections", 2, style, 12, Enum.FontWeight.SemiBold)
			network = panelNetwork(body, 3, style)
			menuSeparator(body, 4, style)
			menuItem(body, {"Wi-Fi Settings…", function()
				openApp("settings", {pane = "Wi-Fi"})
			end}, 5, 9, style)
		end
		fill()
		panel.Destroying:Connect(macOnNetwork(function()
			if panel.Parent then
				fill()
			end
		end))
		task.spawn(function()
			while panel.Parent do
				task.wait(1)
				if panel.Parent then
					network.update()
				end
			end
		end)
	end

	local function showBatteryMenu(button)
		local panel, frame = openPanel(button, 290, STATUS_RADIUS)
		local style = addMenuGlass(frame, "battery")
		local header = panelHeader(panel, "Battery", 1, style)
		macLabel(header, "Unknown", 14, Enum.FontWeight.Regular, style.soft, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -9, 0, 0), Size = UDim2.new(0.5, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = style.softFade,
		})
		-- (a gap under the header: right below it Roblox cut off the line's top)
		macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 2, Parent = panel})
		panelText(panel, "Power Source: Unknown", 3, style)
		menuSeparator(panel, 4, style)
		panelText(panel, "No Apps Using Significant Energy", 5, style)
		menuSeparator(panel, 6, style)
		menuItem(panel, {"Battery Settings…", function()
			openApp("settings", {pane = "Battery"})
		end}, 7, 9, style)
	end

	-- Right side: battery, Wi-Fi, Spotlight, date and time
	local menuRight = macNew("Frame", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0), Parent = menuBar,
	})
	macNew("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4), Parent = menuRight,
	})
	local function statusItem(width, order, open)
		local button = macButton(menuRight, {Size = UDim2.fromOffset(width, 24), BackgroundColor3 = white, LayoutOrder = order})
		macCorner(button, 6)
		button.MouseButton1Down:Connect(function()
			if openMenu and openMenu.button == button then
				closeMenu()
			else
				open(button)
			end
		end)
		button.MouseEnter:Connect(function()
			if openMenu and openMenu.button ~= button then
				open(button)
			end
		end)
		return button
	end
	local batteryButton = statusItem(40, 1, showBatteryMenu)
	macImage(batteryButton, MACOS_ICONS.batteryUnknown, 22, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
	local wifiButton = statusItem(32, 2, showWifiMenu)
	local menuWifi = macWifiGlyph(macNew("Frame", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16), Parent = wifiButton,
	}), white)
	local searchHolder = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(31, 24), LayoutOrder = 3, Parent = menuRight})
	macImage(searchHolder, I.search, 15, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
	local clockLabel = macLabel(menuRight, "", 14, Enum.FontWeight.Medium, white, {
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), LayoutOrder = 4,
	})
	macNew("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = clockLabel})
	local function refreshStatus()
		menuWifi.set(macReadNetwork())
	end
	local stopNetwork = macOnNetwork(refreshStatus)

	-- ---------- Dock ----------
	dock = macNew("Frame", {
		Name = "Dock", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -D.dockBottom),
		Size = UDim2.fromOffset(dockWidth, dockHeight), BackgroundColor3 = white, BackgroundTransparency = 0.78,
		ZIndex = 3, Parent = root,
	})
	macCorner(dock, D.dockRadius)
	local dockRim = macStroke(dock, white, 0.6, 1)
	-- Glass layers: rendered once on the wallpaper, or live on the 3D scene
	-- (backdrop + tint + rim light). Frosted fill and rim when neither works.
	local bakedPane = macNew("ImageLabel", {Name = "Glass", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageTransparency = 1, ZIndex = 1, Parent = dock})
	local livePane = macNew("ImageLabel", {Name = "LiveGlass", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageTransparency = 1, ZIndex = 1, Parent = dock})
	macCorner(livePane, D.dockRadius)
	local liveTint = macNew("Frame", {BackgroundColor3 = MAC_GLASS.tint, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = dock})
	macCorner(liveTint, D.dockRadius)
	local liveRim = macNew("ImageLabel", {Name = "Rim", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageTransparency = 1, ZIndex = 3, Parent = dock})
	local bakedReady = false
	local glassKey = nil
	local liveGlass = nil

	local function glassOpts()
		local opts = table.clone(MAC_GLASS)
		opts.cornerRadius = D.dockRadius * s
		return opts
	end

	-- `time`: crossfade to the new glass along with the background
	local dockFade = 0
	local function applyDockStyle(time)
		local useBaked = session.mode == "wallpaper" and bakedReady
		local useLive = session.mode == "scene" and liveGlass ~= nil
		local glass = useBaked or useLive
		local targets = {
			{dock, "BackgroundTransparency", if glass then 1 else 0.78},
			{dockRim, "Transparency", if glass then 1 else 0.6},
			{bakedPane, "ImageTransparency", if useBaked then 0 else 1},
			{livePane, "ImageTransparency", if useLive then 0 else 1},
			{liveTint, "BackgroundTransparency", if useLive then 1 - MAC_GLASS.tintAlpha else 1},
			{liveRim, "ImageTransparency", if useLive then 0 else 1},
		}
		for _, t in ipairs(targets) do
			if time then
				tween(t[1], time, {[t[2]] = t[3]}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			else
				t[1][t[2]] = t[3]
			end
		end
		dockFade += 1
		local fadeId = dockFade
		if liveGlass then
			if useLive or not time then
				liveGlass.enabled = useLive
				liveGlass.invalidate()
			else
				-- Keep the live glass drawing while it fades out
				task.delay(time, function()
					if fadeId == dockFade and liveGlass then
						liveGlass.enabled = false
					end
				end)
			end
		end
	end

	local function layoutDockGlass()
		local size = gui.AbsoluteSize
		local key = size.X .. "x" .. size.Y
		if key == glassKey or not root.Visible then
			return
		end
		glassKey = key
		local x, y, w, h = macDockRect(size.X, size.Y)
		if not assets.wallpaper and assets.glow then
			local ok, id = pcall(function()
				if assets.dockGlass and assets.dockGlass.size == size then
					return assets.dockGlass.id
				end
				return bakeMacGlass("dock", x, y, w, h, size.X, size.Y, glassOpts())
			end)
			if ok then
				bakedPane.Image = id
				bakedReady = true
			else
				warn("[coolui] dock glass failed: " .. tostring(id))
			end
		end
		if macSky then
			local ok, err = pcall(function()
				liveRim.Image = bakeMacGlassRim("dock", w, h, glassOpts())
				if liveGlass then
					liveGlass.layout(glassOpts())
				else
					liveGlass = createMacLiveGlass(livePane, glassOpts())
				end
			end)
			if not ok then
				warn("[coolui] live dock glass failed: " .. tostring(err))
				if liveGlass then
					liveGlass.destroy()
					liveGlass = nil
				end
			end
		end
		applyDockStyle()
	end
	table.insert(layoutCallbacks, layoutDockGlass)

	-- App name tooltip above the Dock
	local tooltip = macNew("Frame", {
		BackgroundColor3 = C.menu, BackgroundTransparency = 0.04, AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Visible = false, ZIndex = 6, Parent = root,
	})
	macCorner(tooltip, 8)
	macStroke(tooltip, Color3.new(0, 0, 0), 0.88, 1)
	macNew("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = tooltip})
	local tooltipText = macLabel(tooltip, "", 14, Enum.FontWeight.Medium, C.ink, {
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), ZIndex = 7,
	})

	local dockItems = {}
	function dockIconCenter(appId)
		local item = dockItems[appId] or dockItems.finder
		local p, size = screenPos(item.button), item.button.AbsoluteSize
		return Vector2.new((p.X + size.X / 2) / s, (p.Y + size.Y / 2) / s)
	end

	-- The launch bounce
	local function bounce(appId)
		local item = dockItems[appId]
		if not item or item.bouncing then
			return
		end
		item.bouncing = true
		task.spawn(function()
			for _ = 1, 2 do
				local up = TweenService:Create(item.holder, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 1, -18)})
				up:Play()
				up.Completed:Wait()
				local down = TweenService:Create(item.holder, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(0.5, 0, 1, 0)})
				down:Play()
				down.Completed:Wait()
			end
			item.bouncing = false
		end)
	end

	local function addDockItem(app, x)
		local button = macButton(dock, {Name = app.id, Position = UDim2.fromOffset(x, D.dockPadding), Size = UDim2.fromOffset(D.dockIcon, D.dockIcon), ZIndex = 4})
		local holder = macNew("Frame", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromScale(1, 1), Parent = button,
		})
		local scale = macNew("UIScale", {Parent = holder})
		macAppTile(holder, app, D.dockIcon)
		-- Running indicator
		local dot = macNew("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = Color3.fromRGB(36, 36, 42), BackgroundTransparency = 0.1, BorderSizePixel = 0,
			Visible = false, Parent = button,
		})
		macCorner(dot, UDim.new(1, 0))
		button.MouseEnter:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.08}):Play()
			tooltipText.Text = app.name
			local center = dockIconCenter(app.id)
			tooltip.Position = UDim2.fromOffset(center.X, dockTop() - 10)
			tooltip.Visible = true
		end)
		button.MouseLeave:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
			if tooltipText.Text == app.name then
				tooltip.Visible = false
			end
		end)
		button.MouseButton1Click:Connect(function()
			tooltip.Visible = false
			closeMenu()
			openApp(app.id)
		end)
		dockItems[app.id] = {button = button, holder = holder, dot = dot}
	end

	do
		local x = D.dockPadding
		for i, app in ipairs(MAC_APPS) do
			addDockItem(app, x)
			x += D.dockIcon + (if i < #MAC_APPS then D.dockGap else 0)
		end
		-- Two points wide and faint: one point is under a pixel on most screens and doesn't draw
		macNew("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.84, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, x + math.floor(D.dockSeparator / 2), 0.5, 0),
			Size = UDim2.new(0, 2, 0, D.dockIcon - 14), ZIndex = 4, Parent = dock,
		})
		addDockItem(MAC_TRASH, x + D.dockSeparator)
	end

	function refreshDock()
		for id, item in pairs(dockItems) do
			item.dot.Visible = id ~= "trash" and #windowsOf(id) > 0
		end
	end

	-- ---------- Apps ----------
	local appBuilders = {}

	function openApp(appId, args)
		args = args or {}
		if appId == "trash" then
			openApp("finder", {path = MAC_TRASH_PATH, newWindow = true})
			return
		end
		local existing = windowsOf(appId)
		if #existing > 0 and not args.newWindow then
			-- Already open: bring it forward (restoring it if it's minimized)
			local shown = {}
			for _, win in ipairs(existing) do
				if not win.minimized then
					table.insert(shown, win)
				end
			end
			if #shown == 0 then
				existing[#existing].restore()
			else
				for _, win in ipairs(shown) do
					focusWindow(win)
				end
			end
			local win = existing[#existing]
			if args.path and win.openPath then
				win.openPath(args.path)
			end
			if args.pane and win.showPane then
				win.showPane(args.pane)
			end
			return
		end
		bounce(appId)
		local builder = appBuilders[appId]
		if builder then
			builder(args)
		end
	end

	-- Finder: browses the executor's workspace folder
	appBuilders.finder = function(args)
		local sidebarWidth = 190
		openWindow({
			app = "finder", title = "Workspace", width = 820, height = 500, background = white,
			sidebarWidth = sidebarWidth, titleLeft = sidebarWidth + 92,
			build = function(win)
				local current = nil
				local history, future = {}, {}
				local sidebarButtons = {}
				local navigate

				local list = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 46), Size = UDim2.new(1, -20, 1, -56), Parent = win.sidebar})
				macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1), Parent = list})
				local function sidebarHeader(text, order)
					macLabel(list, text, 12, Enum.FontWeight.Bold, C.inkSoft, {Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, TextYAlignment = Enum.TextYAlignment.Bottom})
				end
				local function sidebarItem(text, icon, path, order)
					local button = macButton(list, {Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, BackgroundColor3 = Color3.new(0, 0, 0)})
					macCorner(button, 8)
					macImage(button, icon, 17, C.accent, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0)})
					macLabel(button, text, 14, Enum.FontWeight.Medium, C.ink, {
						Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -40, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
					})
					button.MouseButton1Click:Connect(function()
						navigate(path)
					end)
					sidebarButtons[path] = button
				end
				sidebarHeader("Favorites", 1)
				sidebarItem("Workspace", I.home, "", 2)
				local ok, rootEntries = pcall(macListFolder, "")
				if ok then
					local shown = 0
					for _, entry in ipairs(rootEntries) do
						if entry.folder and shown < 6 then
							shown += 1
							sidebarItem(entry.name, I.folder, entry.path, 2 + shown)
						end
					end
				end
				sidebarHeader("Locations", 20)
				sidebarItem("Trash", I.trash, MAC_TRASH_PATH, 21)

				-- Back / forward
				local function toolButton(icon, x)
					local button = macButton(win.body, {
						Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(30, 28),
						BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5,
					})
					macCorner(button, 8)
					local image = macImage(button, icon, 18, C.ink, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6})
					button.MouseEnter:Connect(function()
						button.BackgroundTransparency = 0.94
					end)
					button.MouseLeave:Connect(function()
						button.BackgroundTransparency = 1
					end)
					return button, image
				end
				local backButton, backIcon = toolButton(I.back, sidebarWidth + 26)
				local forwardButton, forwardIcon = toolButton(I.forward, sidebarWidth + 58)

				-- File list
				local content = win.content
				local header = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(1, -16, 0, 24), Parent = content})
				macLabel(header, "Name", 12, Enum.FontWeight.SemiBold, C.inkSoft, {Position = UDim2.fromOffset(36, 0), Size = UDim2.new(0.6, -36, 1, 0)})
				macLabel(header, "Kind", 12, Enum.FontWeight.SemiBold, C.inkSoft, {Position = UDim2.fromScale(0.62, 0), Size = UDim2.fromScale(0.38, 1)})
				macNew("Frame", {
					BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.9, BorderSizePixel = 0,
					Position = UDim2.new(0, 4, 0, 24), Size = UDim2.new(1, -20, 0, 1), Parent = content,
				})
				local scroller = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(4, 27), Size = UDim2.new(1, -12, 1, -35),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
					ScrollBarImageColor3 = Color3.new(0, 0, 0), ScrollBarImageTransparency = 0.6,
					ScrollingDirection = Enum.ScrollingDirection.Y, Parent = content,
				})
				macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller})
				local emptyLabel = macLabel(content, "", 15, Enum.FontWeight.Medium, C.inkSoft, {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 30),
					TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
				})

				local selected = nil
				local function paintRow(row, on)
					row.button.BackgroundColor3 = if on then C.accent else row.base
					row.button.BackgroundTransparency = if on or row.striped then 0 else 1
					row.name.TextColor3 = if on then white else C.ink
					row.kind.TextColor3 = if on then white else C.inkSoft
					row.icon.ImageColor3 = if on then white else row.iconColor
				end
				local function openEntry(entry)
					if entry.folder then
						navigate(entry.path)
						return
					end
					local ext = macExtension(entry.name)
					if MAC_IMAGE_EXTENSIONS[ext] then
						openApp("preview", {path = entry.path, newWindow = true})
					elseif MAC_AUDIO_EXTENSIONS[ext] then
						openApp("music", {path = entry.path})
					elseif MAC_TEXT_EXTENSIONS[ext] then
						openApp("notes", {path = entry.path, newWindow = true})
					end
				end

				function navigate(path, fromHistory)
					if path == current then
						return
					end
					if current ~= nil and not fromHistory then
						table.insert(history, current)
						table.clear(future)
					end
					current = path
					selected = nil
					for _, child in ipairs(scroller:GetChildren()) do
						if child:IsA("GuiObject") then
							child:Destroy()
						end
					end
					win.setTitle(if path == "" then "Workspace" elseif path == MAC_TRASH_PATH then "Trash" else path:match("([^/]+)$") or path)
					for buttonPath, button in pairs(sidebarButtons) do
						button.BackgroundTransparency = if buttonPath == path then 0.91 else 1
					end
					backIcon.ImageTransparency = if #history > 0 then 0 else 0.65
					forwardIcon.ImageTransparency = if #future > 0 then 0 else 0.65
					if path == MAC_TRASH_PATH then
						emptyLabel.Text = "Trash is empty"
						emptyLabel.Visible = true
						return
					end
					local listed, entries = pcall(macListFolder, path)
					if not listed then
						emptyLabel.Text = "Can't open this folder"
						emptyLabel.Visible = true
						return
					end
					emptyLabel.Text = "This folder is empty"
					emptyLabel.Visible = #entries == 0
					for i, entry in ipairs(entries) do
						if i > 400 then
							break
						end
						local kind, icon = macFileKind(entry.name, entry.folder)
						local striped = i % 2 == 0
						local button = macButton(scroller, {
							Size = UDim2.new(1, -6, 0, 28), LayoutOrder = i, BackgroundColor3 = C.zebra,
							BackgroundTransparency = if striped then 0 else 1,
						})
						macCorner(button, 6)
						local iconColor = if entry.folder then Color3.fromRGB(64, 156, 255) else C.inkSoft
						local row = {
							button = button, base = C.zebra, striped = striped, iconColor = iconColor,
							icon = macImage(button, icon, 17, iconColor, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0)}),
							name = macLabel(button, entry.name, 14, Enum.FontWeight.Regular, C.ink, {
								Position = UDim2.fromOffset(36, 0), Size = UDim2.new(0.6, -36, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
							}),
							kind = macLabel(button, kind, 14, Enum.FontWeight.Regular, C.inkSoft, {
								Position = UDim2.fromScale(0.62, 0), Size = UDim2.new(0.38, -8, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
							}),
						}
						local lastClick = 0
						button.MouseButton1Click:Connect(function()
							local now = os.clock()
							if selected == row and now - lastClick < 0.4 then
								openEntry(entry)
								return
							end
							lastClick = now
							if selected then
								paintRow(selected, false)
							end
							selected = row
							paintRow(row, true)
						end)
					end
					scroller.CanvasPosition = Vector2.zero
				end

				backButton.MouseButton1Click:Connect(function()
					if #history > 0 then
						table.insert(future, current)
						navigate(table.remove(history), true)
					end
				end)
				forwardButton.MouseButton1Click:Connect(function()
					if #future > 0 then
						table.insert(history, current)
						navigate(table.remove(future), true)
					end
				end)
				navigate(args.path or "")
			end,
		})
	end

	-- Notes: a plain text editor that saves as you type
	appBuilders.notes = function(args)
		local path = args.path or MAC_NOTES_FILE
		local name = path:match("([^/]+)$") or path
		openWindow({
			app = "notes", title = name, width = 580, height = 440, background = white,
			build = function(win)
				local text = ""
				local ok, data = pcall(function()
					return if isfile(path) then readfile(path) else ""
				end)
				if ok then
					text = data
				end
				-- Very long files open read-only (a huge TextBox gets slow)
				local readOnly = #text > 60000
				if readOnly then
					text = text:sub(1, 60000)
					win.setTitle(name .. " (read only)")
				end
				local scroller = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -30, 1, -12),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
					ScrollBarImageColor3 = Color3.new(0, 0, 0), ScrollBarImageTransparency = 0.6,
					ScrollingDirection = Enum.ScrollingDirection.Y, Parent = win.content,
				})
				local box = macNew("TextBox", {
					BackgroundTransparency = 1, MultiLine = true, ClearTextOnFocus = false, TextWrapped = true,
					Text = text, PlaceholderText = "Start typing…", PlaceholderColor3 = C.inkSoft, TextColor3 = C.ink,
					FontFace = macFont(Enum.FontWeight.Regular), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -10, 1, 0), AutomaticSize = Enum.AutomaticSize.Y,
					TextEditable = not readOnly, Parent = scroller,
				})
				local saveId = 0
				box:GetPropertyChangedSignal("Text"):Connect(function()
					if readOnly then
						return
					end
					saveId += 1
					local id = saveId
					win.setTitle(name .. " — Edited")
					task.delay(0.8, function()
						if id ~= saveId then
							return
						end
						local saved = pcall(function()
							ensureMacFolder()
							writefile(path, box.Text)
						end)
						win.setTitle(if saved then name else name .. " — Can't save")
					end)
				end)
				if text == "" and not readOnly then
					task.defer(function()
						box:CaptureFocus()
					end)
				end
			end,
		})
	end

	-- Terminal: a few shell commands for the workspace, and Luau for the rest
	appBuilders.terminal = function()
		openWindow({
			app = "terminal", title = player.Name .. " — zsh — 80×24", width = 660, height = 420, dark = true,
			background = Color3.fromRGB(30, 30, 32),
			build = function(win)
				local mono = Font.new("rbxasset://fonts/families/RobotoMono.json")
				local cwd = ""
				local scroller = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -22, 1, -12),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
					ScrollBarImageColor3 = white, ScrollBarImageTransparency = 0.7,
					ScrollingDirection = Enum.ScrollingDirection.Y, Parent = win.content,
				})
				macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller})
				local order = 0
				local lineCount = 0
				local function line(text, color)
					order += 1
					lineCount += 1
					macNew("TextLabel", {
						BackgroundTransparency = 1, Text = if text == "" then " " else text, TextColor3 = color or C.terminalText,
						FontFace = mono, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
						Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = scroller,
					})
					-- Keep the scrollback bounded
					if lineCount > 400 then
						for _, child in ipairs(scroller:GetChildren()) do
							if child:IsA("TextLabel") then
								child:Destroy()
								lineCount -= 1
								break
							end
						end
					end
				end
				local function joinArgs(...)
					local parts = table.pack(...)
					for i = 1, parts.n do
						parts[i] = tostring(parts[i])
					end
					return table.concat(parts, " ", 1, parts.n)
				end

				local inputRow = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 1e9, Parent = scroller})
				local prompt = macNew("TextLabel", {
					BackgroundTransparency = 1, FontFace = mono, TextSize = 14, TextColor3 = C.terminalAccent,
					TextXAlignment = Enum.TextXAlignment.Left, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Parent = inputRow,
				})
				local input = macNew("TextBox", {
					BackgroundTransparency = 1, ClearTextOnFocus = false, Text = "", PlaceholderText = "", FontFace = mono, TextSize = 14,
					TextColor3 = C.terminalText, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(1, 1), Parent = inputRow,
				})
				local function promptText()
					return player.Name .. "@Roblox " .. (if cwd == "" then "~" else cwd:match("([^/]+)$") or cwd) .. " %"
				end
				local function updatePrompt()
					prompt.Text = promptText()
				end
				prompt:GetPropertyChangedSignal("TextBounds"):Connect(function()
					local width = prompt.TextBounds.X + 8
					input.Position = UDim2.fromOffset(width, 0)
					input.Size = UDim2.new(1, -width, 1, 0)
				end)
				updatePrompt()

				local function resolve(arg)
					if not arg or arg == "" or arg == "~" then
						return ""
					elseif arg == "." then
						return cwd
					elseif arg == ".." then
						return cwd:match("^(.*)/[^/]+$") or ""
					elseif arg:sub(1, 2) == "~/" then
						return arg:sub(3)
					end
					return if cwd == "" then arg else cwd .. "/" .. arg
				end

				local commands = {}
				function commands.help()
					line("Commands: ls, cd, pwd, cat, echo, clear, date, whoami, open, neofetch, exit")
					line("Anything else runs as Luau, e.g.  workspace.Gravity", C.inkSoft)
				end
				function commands.clear()
					for _, child in ipairs(scroller:GetChildren()) do
						if child:IsA("TextLabel") then
							child:Destroy()
						end
					end
					lineCount = 0
				end
				function commands.pwd()
					line(if cwd == "" then "~" else "~/" .. cwd)
				end
				function commands.ls(argv)
					local listed, entries = pcall(macListFolder, resolve(argv[1]))
					if not listed then
						line("ls: " .. (argv[1] or ".") .. ": No such file or directory", C.terminalError)
						return
					end
					local names = {}
					for _, entry in ipairs(entries) do
						table.insert(names, entry.name .. (if entry.folder then "/" else ""))
					end
					line(table.concat(names, "    "))
				end
				function commands.cd(argv)
					local target = resolve(argv[1])
					if target ~= "" then
						local exists, folder = pcall(isfolder, target)
						if not (exists and folder) then
							line("cd: no such file or directory: " .. argv[1], C.terminalError)
							return
						end
					end
					cwd = target
					updatePrompt()
				end
				function commands.cat(argv)
					if not argv[1] then
						line("usage: cat <file>")
						return
					end
					local read, data = pcall(readfile, resolve(argv[1]))
					if not read then
						line("cat: " .. argv[1] .. ": No such file or directory", C.terminalError)
						return
					end
					local shown = 0
					for text in (data:sub(1, 6000) .. "\n"):gmatch("(.-)\n") do
						shown += 1
						if shown > 120 then
							line("… (" .. #data .. " bytes)", C.inkSoft)
							break
						end
						line(text)
					end
				end
				function commands.echo(_, rest)
					line(rest)
				end
				function commands.date()
					line(DateTime.now():FormatLocalTime("ddd MMM D HH:mm:ss YYYY", "en-us"))
				end
				function commands.whoami()
					line(player.Name)
				end
				function commands.open(argv)
					local id = (argv[1] or ""):lower()
					for appId, appName in pairs(MAC_APP_NAMES) do
						if id == appId or id == appName:lower() then
							openApp(appId)
							return
						end
					end
					line("open: unknown app: " .. (argv[1] or ""), C.terminalError)
				end
				function commands.neofetch()
					local viewport = workspace.CurrentCamera.ViewportSize
					line(player.Name .. "@Roblox", C.terminalAccent)
					line(string.rep("-", #player.Name + 7))
					line("OS: macOS Tahoe 26.1 (Roblox)")
					line("Host: Roblox " .. version())
					line("Shell: zsh (Luau)")
					line(string.format("Resolution: %dx%d", math.floor(viewport.X), math.floor(viewport.Y)))
					line(string.format("Memory: %d MB", math.floor(game:GetService("Stats"):GetTotalMemoryUsageMb())))
					line("Players: " .. #Players:GetPlayers())
				end
				function commands.exit()
					win.close()
				end

				local function runLuau(source)
					-- Try it as an expression first, so `workspace.Gravity` prints a value
					local fn = loadstring("return " .. source)
					if not fn then
						local compileError
						fn, compileError = loadstring(source)
						if not fn then
							line(tostring(compileError), C.terminalError)
							return
						end
					end
					local env = setmetatable({
						print = function(...)
							line(joinArgs(...))
						end,
						warn = function(...)
							line(joinArgs(...), Color3.fromRGB(255, 200, 90))
						end,
					}, {__index = getfenv(0)})
					pcall(setfenv, fn, env)
					local results = table.pack(pcall(fn))
					if not results[1] then
						line(tostring(results[2]), C.terminalError)
					elseif results.n > 1 then
						local parts = {}
						for i = 2, results.n do
							table.insert(parts, tostring(results[i]))
						end
						line(table.concat(parts, "  "))
					end
				end

				local history, historyIndex = {}, 1
				local function submit(value)
					line(promptText() .. " " .. value, C.terminalText)
					local trimmed = value:match("^%s*(.-)%s*$")
					if trimmed == "" then
						return
					end
					table.insert(history, trimmed)
					historyIndex = #history + 1
					local name, rest = trimmed:match("^(%S+)%s*(.*)$")
					local handler = commands[name]
					if handler then
						local argv = {}
						for arg in rest:gmatch("%S+") do
							table.insert(argv, arg)
						end
						local ran, err = pcall(handler, argv, rest)
						if not ran then
							line(tostring(err), C.terminalError)
						end
					else
						runLuau(trimmed)
					end
				end

				input.FocusLost:Connect(function(enterPressed)
					if not enterPressed then
						return
					end
					local value = input.Text
					input.Text = ""
					submit(value)
					task.defer(function()
						if not win.closed then
							input:CaptureFocus()
							scroller.CanvasPosition = Vector2.new(0, scroller.AbsoluteCanvasSize.Y)
						end
					end)
				end)
				-- Up/down arrows: command history
				table.insert(win.cleanup, UserInputService.InputBegan:Connect(function(key)
					if not input:IsFocused() then
						return
					end
					if key.KeyCode == Enum.KeyCode.Up and historyIndex > 1 then
						historyIndex -= 1
					elseif key.KeyCode == Enum.KeyCode.Down and historyIndex <= #history then
						historyIndex += 1
					else
						return
					end
					input.Text = history[historyIndex] or ""
					input.CursorPosition = #input.Text + 1
				end))
				scroller.InputBegan:Connect(function(event)
					if event.UserInputType == Enum.UserInputType.MouseButton1 then
						input:CaptureFocus()
					end
				end)

				line("Last login: " .. DateTime.now():FormatLocalTime("ddd MMM D HH:mm:ss", "en-us") .. " on ttys000")
				line("Type help for commands. Anything else runs as Luau.", C.inkSoft)
				task.defer(function()
					input:CaptureFocus()
				end)
			end,
		})
	end

	-- Music: plays the mp3s in coolui_music (and any audio opened from Finder)
	appBuilders.music = function(args)
		openWindow({
			app = "music", title = "Music", width = 600, height = 340,
			build = function(win)
				local sound = macNew("Sound", {Name = "coolui_mac_music", Volume = 0.8, Parent = game:GetService("SoundService")})
				table.insert(win.cleanup, function()
					sound:Destroy()
				end)
				local tracks = {}
				local function addTrack(path)
					for i, track in ipairs(tracks) do
						if track.path == path then
							return i
						end
					end
					local fileName = path:match("([^/]+)$") or path
					table.insert(tracks, {path = path, title = fileName:gsub("%.%w+$", "")})
					return #tracks
				end
				pcall(function()
					for _, entry in ipairs(macListFolder(MUSIC_FOLDER)) do
						if not entry.folder and MAC_AUDIO_EXTENSIONS[macExtension(entry.name)] then
							addTrack(entry.path)
						end
					end
				end)

				local content = win.content
				local art = macNew("Frame", {Position = UDim2.fromOffset(24, 4), Size = UDim2.fromOffset(170, 170), BackgroundColor3 = white, Parent = content})
				macCorner(art, 14)
				macNew("UIGradient", {Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(255, 96, 140), Color3.fromRGB(140, 70, 235)), Parent = art})
				macImage(art, I.music, 84, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})

				local titleLabel = macLabel(content, "Not Playing", 20, Enum.FontWeight.Bold, C.ink, {
					Position = UDim2.fromOffset(214, 8), Size = UDim2.new(1, -234, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd,
				})
				macLabel(content, "coolui", 15, Enum.FontWeight.Regular, C.inkSoft, {Position = UDim2.fromOffset(214, 36), Size = UDim2.new(1, -234, 0, 20)})

				-- Progress bar (click to seek)
				local bar = macButton(content, {
					Position = UDim2.fromOffset(214, 76), Size = UDim2.new(1, -238, 0, 6),
					BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(222, 222, 226),
				})
				macCorner(bar, UDim.new(1, 0))
				local fill = macNew("Frame", {BackgroundColor3 = Color3.fromRGB(120, 120, 126), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = bar})
				macCorner(fill, UDim.new(1, 0))
				local elapsedLabel = macLabel(content, "0:00", 12, Enum.FontWeight.Medium, C.inkSoft, {Position = UDim2.fromOffset(214, 86), Size = UDim2.fromOffset(60, 16)})
				local lengthLabel = macLabel(content, "0:00", 12, Enum.FontWeight.Medium, C.inkSoft, {
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 86), Size = UDim2.fromOffset(60, 16),
					TextXAlignment = Enum.TextXAlignment.Right,
				})

				local function controlButton(icon, size, x)
					local button = macButton(content, {
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, x, 0, 134), Size = UDim2.fromOffset(size + 14, size + 14),
						BackgroundColor3 = Color3.new(0, 0, 0),
					})
					macCorner(button, UDim.new(1, 0))
					local image = macImage(button, icon, size, C.ink, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
					button.MouseEnter:Connect(function()
						button.BackgroundTransparency = 0.94
					end)
					button.MouseLeave:Connect(function()
						button.BackgroundTransparency = 1
					end)
					return button, image
				end
				local prevButton = controlButton(I.skipBack, 22, 300)
				local playButton, playIcon = controlButton(I.play, 30, 356)
				local nextButton = controlButton(I.skipForward, 22, 412)

				local trackList = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 186), Size = UDim2.new(1, -32, 1, -194),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
					ScrollBarImageColor3 = Color3.new(0, 0, 0), ScrollBarImageTransparency = 0.6,
					ScrollingDirection = Enum.ScrollingDirection.Y, Parent = content,
				})
				macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = trackList})

				local index = 0
				local rows = {}
				local function paintRows()
					for i, row in ipairs(rows) do
						local on = i == index
						row.button.BackgroundTransparency = if on then 0 else 1
						row.label.TextColor3 = if on then white else C.ink
					end
				end
				local function play(i)
					local track = tracks[i]
					if not track then
						return
					end
					local ok, id = pcall(getcustomasset, track.path)
					if not ok then
						titleLabel.Text = "Can't play " .. track.title
						return
					end
					index = i
					sound:Stop()
					sound.SoundId = id
					sound.TimePosition = 0
					sound:Play()
					titleLabel.Text = track.title
					paintRows()
				end
				local function rebuildRows()
					for _, row in ipairs(rows) do
						row.button:Destroy()
					end
					table.clear(rows)
					for i, track in ipairs(tracks) do
						local button = macButton(trackList, {Size = UDim2.new(1, -6, 0, 28), LayoutOrder = i, BackgroundColor3 = C.accent})
						macCorner(button, 6)
						local label = macLabel(button, track.title, 14, Enum.FontWeight.Regular, C.ink, {
							Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
						})
						button.MouseButton1Click:Connect(function()
							play(i)
						end)
						rows[i] = {button = button, label = label}
					end
					paintRows()
				end
				rebuildRows()

				playButton.MouseButton1Click:Connect(function()
					if sound.IsPlaying then
						sound:Pause()
					elseif index == 0 then
						play(1)
					else
						sound:Resume()
					end
				end)
				prevButton.MouseButton1Click:Connect(function()
					if #tracks > 0 then
						play((index - 2) % #tracks + 1)
					end
				end)
				nextButton.MouseButton1Click:Connect(function()
					if #tracks > 0 then
						play(index % #tracks + 1)
					end
				end)
				sound.Ended:Connect(function()
					if #tracks > 0 then
						play(index % #tracks + 1)
					end
				end)
				bar.MouseButton1Down:Connect(function(x)
					if sound.TimeLength > 0 then
						local fraction = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
						sound.TimePosition = fraction * sound.TimeLength
					end
				end)

				local function clockText(seconds)
					seconds = math.max(0, math.floor(seconds))
					return string.format("%d:%02d", seconds // 60, seconds % 60)
				end
				task.spawn(function()
					while not win.closed do
						local length = sound.TimeLength
						fill.Size = UDim2.fromScale(if length > 0 then math.clamp(sound.TimePosition / length, 0, 1) else 0, 1)
						elapsedLabel.Text = clockText(sound.TimePosition)
						lengthLabel.Text = clockText(length)
						playIcon.Image = if sound.IsPlaying then I.pause else I.play
						task.wait(0.2)
					end
				end)

				function win.openPath(path)
					local i = addTrack(path)
					rebuildRows()
					play(i)
				end
				if args.path then
					win.openPath(args.path)
				end
			end,
		})
	end

	-- About This Mac (also the About pane in System Settings)
	local function buildAbout(parent)
		local viewport = workspace.CurrentCamera.ViewportSize
		macImage(parent, I.laptop, 96, Color3.fromRGB(96, 98, 106), {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0)})
		macLabel(parent, "MacBook Pro", 24, Enum.FontWeight.Bold, C.ink, {
			Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center,
		})
		macLabel(parent, "Roblox, " .. DateTime.now():FormatLocalTime("YYYY", "en-us"), 13, Enum.FontWeight.Regular, C.inkSoft, {
			Position = UDim2.fromOffset(0, 134), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center,
		})
		local rows = {
			{"Chip", "Roblox " .. (version():match("^%d+%.%d+") or version())},
			{"Memory", string.format("%d MB in use", math.floor(game:GetService("Stats"):GetTotalMemoryUsageMb()))},
			{"Display", string.format("Built-in (%d × %d)", math.floor(viewport.X), math.floor(viewport.Y))},
			{"Serial number", if game.JobId ~= "" then game.JobId:sub(1, 8):upper() else "STUDIO"},
			{"macOS", "Tahoe 26.1"},
		}
		for i, row in ipairs(rows) do
			local y = 170 + (i - 1) * 22
			macLabel(parent, row[1], 13, Enum.FontWeight.Medium, C.ink, {
				Position = UDim2.fromOffset(0, y), Size = UDim2.new(0.5, -6, 0, 18), TextXAlignment = Enum.TextXAlignment.Right,
			})
			macLabel(parent, row[2], 13, Enum.FontWeight.Regular, C.inkSoft, {
				Position = UDim2.new(0.5, 6, 0, y), Size = UDim2.new(0.5, -6, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
			})
		end
	end

	appBuilders.about = function()
		openWindow({
			app = "about", title = "", menuName = "About This Mac", width = 320, height = 360, fixedSize = true,
			build = function(win)
				local holder = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(16, -8), Size = UDim2.new(1, -32, 1, 0), Parent = win.content})
				buildAbout(holder)
			end,
		})
	end

	-- Preview: shows an image from the workspace
	appBuilders.preview = function(args)
		local name = args.path:match("([^/]+)$") or args.path
		openWindow({
			app = "preview", title = name, width = 560, height = 440, background = Color3.fromRGB(236, 236, 240),
			build = function(win)
				local ok, id = pcall(getcustomasset, args.path)
				if ok then
					macNew("ImageLabel", {
						BackgroundTransparency = 1, Image = id, ScaleType = Enum.ScaleType.Fit,
						Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -32, 1, -16), Parent = win.content,
					})
				else
					macLabel(win.content, "Can't open this image.", 14, Enum.FontWeight.Medium, C.inkSoft, {
						Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
					})
				end
			end,
		})
	end

	-- System Settings: Wi-Fi, battery, wallpaper and about. args.pane picks
	-- the pane it opens on.
	appBuilders.settings = function(args)
		local sidebarWidth = 210
		local firstPane = args.pane or "Wallpaper"
		openWindow({
			app = "settings", title = firstPane, width = 720, height = 470,
			sidebarWidth = sidebarWidth, titleLeft = sidebarWidth + 32,
			build = function(win)
				-- Account card
				local avatar = macNew("ImageLabel", {
					BackgroundColor3 = Color3.fromRGB(190, 196, 206), Image = assets.avatar or "",
					Position = UDim2.fromOffset(12, 50), Size = UDim2.fromOffset(38, 38), Parent = win.sidebar,
				})
				macCorner(avatar, UDim.new(1, 0))
				macLabel(win.sidebar, player.DisplayName, 14, Enum.FontWeight.SemiBold, C.ink, {
					Position = UDim2.fromOffset(58, 50), Size = UDim2.new(1, -66, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd,
				})
				macLabel(win.sidebar, "Roblox Account", 12, Enum.FontWeight.Regular, C.inkSoft, {
					Position = UDim2.fromOffset(58, 70), Size = UDim2.new(1, -66, 0, 16),
				})

				local panes = {}
				local paneButtons = {}
				local currentPane = nil
				local function showPane(name)
					if currentPane then
						currentPane:Destroy()
					end
					currentPane = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = win.content})
					win.setTitle(name)
					for paneName, button in pairs(paneButtons) do
						local on = paneName == name
						button.BackgroundTransparency = if on then 0 else 1
						button:FindFirstChildOfClass("TextLabel").TextColor3 = if on then white else C.ink
					end
					panes[name](currentPane)
				end
				local function paneButton(name, icon, top, bottom, order)
					local button = macButton(win.sidebar, {
						Position = UDim2.fromOffset(8, 100 + (order - 1) * 32), Size = UDim2.new(1, -16, 0, 30),
						BackgroundColor3 = C.accent,
					})
					macCorner(button, 8)
					macAppTile(button, {icon = icon, top = top, bottom = bottom}, 22).Position = UDim2.fromOffset(6, 4)
					macLabel(button, name, 14, Enum.FontWeight.Medium, C.ink, {Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -44, 1, 0)})
					button.MouseButton1Click:Connect(function()
						showPane(name)
					end)
					paneButtons[name] = button
				end

				panes.Wallpaper = function(pane)
					macLabel(pane, "Choose the background for your desktop and lock screen.", 14, Enum.FontWeight.Regular, C.inkSoft, {
						Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -32, 0, 20),
					})
					local rings = {}
					local function card(mode, title, x, buildPreview)
						local holder = macButton(pane, {Position = UDim2.fromOffset(x, 36), Size = UDim2.fromOffset(220, 168)})
						local preview = macNew("CanvasGroup", {BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromOffset(220, 138), Parent = holder})
						macCorner(preview, 12)
						buildPreview(preview)
						local ring = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 138), Parent = holder})
						macCorner(ring, 12)
						rings[mode] = macStroke(ring, C.accent, 1, 3)
						macLabel(holder, title, 14, Enum.FontWeight.Medium, C.ink, {
							Position = UDim2.fromOffset(0, 146), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center,
						})
						holder.MouseButton1Click:Connect(function()
							if session.mode ~= mode then
								session.setBackground(mode, true)
							end
						end)
					end
					card("wallpaper", "Tahoe", 16, function(preview)
						buildMacWallpaper(preview, assets.glow, assets.wallpaper, getScale)
					end)
					card("scene", "3D Scene", 256, function(preview)
						macNew("ImageLabel", {
							BackgroundTransparency = 1, Image = assets.scenePreview or "", ScaleType = Enum.ScaleType.Crop,
							Size = UDim2.fromScale(1, 1), Parent = preview,
						})
					end)
					local function paint()
						for mode, stroke in pairs(rings) do
							stroke.Transparency = if session.mode == mode then 0 else 1
						end
					end
					paint()
					local stop = session.onBackground(function()
						task.defer(paint)
					end)
					pane.Destroying:Connect(stop)
				end
				panes.About = function(pane)
					local holder = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 1, -8), Parent = pane})
					buildAbout(holder)
				end

				-- A rounded white group of `count` rows, like the real System
				-- Settings; returns the row frames
				local function group(pane, y, count)
					local box = macNew("Frame", {
						BackgroundColor3 = white, BorderSizePixel = 0, Position = UDim2.fromOffset(16, y),
						Size = UDim2.new(1, -32, 0, count * 40), Parent = pane,
					})
					macCorner(box, 10)
					macStroke(box, Color3.new(0, 0, 0), 0.92, 1)
					local rows = {}
					for i = 1, count do
						rows[i] = macNew("Frame", {
							BackgroundTransparency = 1, Position = UDim2.fromOffset(0, (i - 1) * 40), Size = UDim2.new(1, 0, 0, 40), Parent = box,
						})
						if i < count then
							macNew("Frame", {
								BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.92, BorderSizePixel = 0,
								AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, 0), Size = UDim2.new(1, -28, 0, 1), Parent = rows[i],
							})
						end
					end
					return rows
				end
				-- A label on the left and a grey value on the right; returns the value
				local function valueRow(row, label, value)
					macLabel(row, label, 14, Enum.FontWeight.Regular, C.ink, {Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, -14, 1, 0)})
					return macLabel(row, value, 14, Enum.FontWeight.Regular, C.inkSoft, {
						AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0.5, -14, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
					})
				end
				local function caption(pane, text, y)
					macLabel(pane, text, 13, Enum.FontWeight.SemiBold, C.ink, {Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 18)})
				end

				panes["Wi-Fi"] = function(pane)
					local top = group(pane, 0, 1)[1]
					macAppTile(top, {icon = MACOS_ICONS.wifi, top = Color3.fromRGB(90, 170, 255), bottom = Color3.fromRGB(0, 110, 245)}, 26).Position = UDim2.fromOffset(10, 7)
					macLabel(top, "Wi-Fi", 14, Enum.FontWeight.Medium, C.ink, {Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -110, 1, 0)})
					local toggle = macToggle(top, macNetwork.wifiOn, macSetWifi)
					toggle.button.AnchorPoint = Vector2.new(1, 0.5)
					toggle.button.Position = UDim2.new(1, -14, 0.5, 0)

					local current = group(pane, 56, 1)[1]
					local glyph = macWifiGlyph(macNew("Frame", {
						BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 11), Size = UDim2.fromOffset(18, 18), Parent = current,
					}), C.ink)
					local name = macLabel(current, "", 14, Enum.FontWeight.Medium, C.ink, {
						Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -170, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
					})
					local dot = macNew("Frame", {
						BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -112, 0.5, 0),
						Size = UDim2.fromOffset(8, 8), Parent = current,
					})
					macCorner(dot, UDim.new(1, 0))
					local status = macLabel(current, "", 14, Enum.FontWeight.Regular, C.inkSoft, {
						AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(94, 40),
					})

					caption(pane, "Details", 114)
					local rows = group(pane, 138, 4)
					local ping = valueRow(rows[1], "Ping", "")
					local signal = valueRow(rows[2], "Signal", "")
					local server = valueRow(rows[3], "Server", if game.JobId ~= "" then game.JobId:sub(1, 8) else "Local")
					local players = valueRow(rows[4], "Players", "")

					local function paint()
						local state = macReadNetwork()
						toggle.set(state.wifiOn)
						glyph.set(state, true)
						name.Text = if state.wifiOn then macGameName() else "Ethernet"
						dot.BackgroundColor3 = if state.connected then Color3.fromRGB(52, 199, 89) else Color3.fromRGB(190, 190, 196)
						status.Text = if state.connected then "Connected" else "Not Connected"
						ping.Text = if state.ping and state.connected then state.ping .. " ms" else "—"
						signal.Text = if not state.connected then "None"
							else ({[0] = "Poor", "Fair", "Good", "Excellent"})[state.bars]
						players.Text = #Players:GetPlayers() .. " of " .. Players.MaxPlayers
					end
					paint()
					pane.Destroying:Connect(macOnNetwork(paint))
					task.spawn(function()
						while pane.Parent do
							task.wait(1)
							if pane.Parent then
								paint()
							end
						end
					end)
				end

				panes.Battery = function(pane)
					local rows = group(pane, 0, 3)
					valueRow(rows[1], "Battery Level", "Unknown")
					valueRow(rows[2], "Power Source", "Unknown")
					valueRow(rows[3], "Battery Health", "Unknown")
					macLabel(pane, "Roblox doesn't let games read your battery, so its level and power source can't be shown.", 13, Enum.FontWeight.Regular, C.inkSoft, {
						Position = UDim2.fromOffset(20, 130), Size = UDim2.new(1, -40, 0, 36), TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
					})
				end

				paneButton("Wi-Fi", MACOS_ICONS.wifi, Color3.fromRGB(90, 170, 255), Color3.fromRGB(0, 110, 245), 1)
				paneButton("Battery", I.battery, Color3.fromRGB(120, 220, 120), Color3.fromRGB(40, 175, 70), 2)
				paneButton("Wallpaper", I.image, Color3.fromRGB(90, 200, 250), Color3.fromRGB(0, 122, 255), 3)
				paneButton("About", I.info, Color3.fromRGB(176, 178, 186), Color3.fromRGB(112, 114, 124), 4)
				win.showPane = function(name)
					if panes[name] then
						showPane(name)
					end
				end
				showPane(if panes[firstPane] then firstPane else "Wallpaper")
			end,
		})
	end

	-- ---------- Background, live glass, clock ----------
	local stopListening = session.onBackground(function(mode, animate)
		local shadeTarget = if mode == "scene" then 0 else 1
		if not root.Visible then
			shade.BackgroundTransparency = shadeTarget
			applyDockStyle()
			return
		end
		tween(shade, session.fadeTime, {BackgroundTransparency = shadeTarget}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		applyDockStyle(if animate then session.fadeTime else nil)
	end)

	RunService:BindToRenderStep("coolui_mac_glass", Enum.RenderPriority.Camera.Value + 5, function()
		if liveGlass and root.Visible then
			liveGlass.update(workspace.CurrentCamera)
		end
		if menuGlass and root.Visible then
			menuGlass.update(workspace.CurrentCamera)
		end
	end)

	task.spawn(function()
		while alive do
			clockLabel.Text = DateTime.now():FormatLocalTime("ddd MMM D  h:mm A", "en-us")
			refreshStatus()
			task.wait(1)
		end
	end)

	connect(gui:GetPropertyChangedSignal("AbsoluteSize"), relayout)
	refreshMenuBar()
	refreshDock()

	-- Shows the desktop and waits for Lock Screen, Log Out, Restart or Shut
	-- Down; returns which one
	function desktop.run()
		pendingAction = nil
		root.Visible = true
		relayout()
		local hiddenMenu = UDim2.fromOffset(0, -D.menuHeight - 4)
		local hiddenDock = UDim2.new(0.5, 0, 1, dockHeight + 12)
		menuBar.Position = hiddenMenu
		dock.Position = hiddenDock
		shade.BackgroundTransparency = 1
		tween(menuBar, 0.55, {Position = UDim2.fromOffset(0, 0)})
		task.delay(0.08, function()
			tween(dock, 0.65, {Position = UDim2.new(0.5, 0, 1, -D.dockBottom)})
		end)
		tween(shade, 0.6, {BackgroundTransparency = if session.mode == "scene" then 0 else 1})
		tween(session.wallScale, 0.9, {Scale = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, win in ipairs(windows) do
			if not win.minimized then
				task.spawn(animateWindow, win, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {scale = 0.97, transparency = 1}, {})
			end
		end

		repeat
			task.wait()
		until pendingAction or not alive

		local action = pendingAction or "shutdown"
		closeMenu()
		tooltip.Visible = false
		drag = nil
		local out = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(menuBar, out, {Position = hiddenMenu}):Play()
		TweenService:Create(dock, out, {Position = hiddenDock}):Play()
		TweenService:Create(shade, out, {BackgroundTransparency = 1}):Play()
		for _, win in ipairs(windows) do
			if not win.minimized then
				task.spawn(animateWindow, win, out, {}, {scale = 0.97, transparency = 1})
			end
		end
		task.wait(0.32)
		root.Visible = false
		return action
	end

	function desktop.closeAllWindows()
		for i = #windows, 1, -1 do
			windows[i].close(true)
		end
		cascade = 0
	end

	function desktop.destroy()
		alive = false
		desktop.closeAllWindows()
		stopListening()
		stopNetwork()
		pcall(function()
			RunService:UnbindFromRenderStep("coolui_mac_glass")
		end)
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		if liveGlass then
			liveGlass.destroy()
		end
		root:Destroy()
	end

	return desktop
end

-- Fades out the Music app's song, so quitting the apps doesn't cut it off
local function fadeMacMusic(time)
	for _, sound in game:GetService("SoundService"):GetChildren() do
		if sound.Name == "coolui_mac_music" and sound:IsA("Sound") then
			TweenService:Create(sound, TweenInfo.new(time), {Volume = 0}):Play()
		end
	end
end

-- Lock screen, then the desktop, until Shut Down. Returns a function that
-- closes macOS, so the goodbye screen can fade in over the desktop first.
local function runMacOS(assets)
	local session = createMacSession(assets)
	local desktop = nil
	local boot = true
	while true do
		showMacLockScreen(session, boot)
		boot = false
		desktop = desktop or createMacDesktop(session)
		local action = desktop.run()
		if action == "shutdown" then
			break
		elseif action == "restart" then
			fadeMacMusic(0.6)
			session.fadeCover(0, 0.6)
			desktop.closeAllWindows()
			task.wait(1.2)
			boot = true
		elseif action == "logout" then
			-- The windows are already hidden; they quit once the song has faded
			fadeMacMusic(0.4)
			task.delay(0.4, desktop.closeAllWindows)
		end
	end
	fadeMacMusic(0.5)
	return function()
		desktop.destroy()
		session.gui:Destroy()
	end
end

-- ---------- Load macOS ----------
-- "Downloading assets" screen (spinner + status text), then macOS (lock
-- screen and desktop). Returns after Shut Down.
local function runMacOSLoader()
	stopMusic(1.5)

	local function statusLabel(offsetY, textSize)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0.5, offsetY)
		l.Size = UDim2.new(0, 420, 0, textSize + 6)
		l.FontFace = macFont(Enum.FontWeight.Medium)
		l.TextSize = textSize
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextTransparency = 1
		l.ZIndex = 9
		l.Text = ""
		l.Parent = LoadingFrame
		return l
	end
	-- Sits just under the spinner
	local status = statusLabel(34, 17)
	local detail = statusLabel(58, 13)
	status.Text = "Downloading assets"

	TweenService:Create(background, macFadeInfo, {ImageTransparency = 0.1}):Play()
	TweenService:Create(Spinner, macFadeInfo, {ImageTransparency = 0}):Play()
	TweenService:Create(status, macFadeInfo, {TextTransparency = 0.08}):Play()
	TweenService:Create(detail, macFadeInfo, {TextTransparency = 0.45}):Play()
	task.wait(0.5)

	local assets = {}
	local steps = {
		{"Wallpaper effects", function()
			assets.glow = getMacGlowAsset()
		end},
		{"Liquid glass", function()
			-- Render the password field's glass now, so the lock screen opens instantly
			if assets.wallpaper or not assets.glow then return end
			local size = ScreenGui.AbsoluteSize
			local x, y, w, h = macPasswordFieldRect(size.X, size.Y)
			assets.fieldGlass = {size = size, id = bakeMacGlass("field", x, y, w, h, size.X, size.Y)}
		end},
		{"Glass clock", function()
			-- Download the clock font and render the current time's digits in glass
			if assets.wallpaper or not assets.glow then return end
			loadMacClockFont()
			local size = ScreenGui.AbsoluteSize
			local text = DateTime.now():FormatLocalTime("h:mm", "en-us")
			for _, placement in ipairs(macClockLayout(text, size.X, size.Y)) do
				bakeMacClockGlyph(placement, size.X, size.Y)
				task.wait()
			end
			assets.clockFont = true
		end},
		{"Dock glass", function()
			-- Render the Dock's glass now, so the desktop opens instantly
			local size = ScreenGui.AbsoluteSize
			local x, y, w, h, radius = macDockRect(size.X, size.Y)
			local opts = table.clone(MAC_GLASS)
			opts.cornerRadius = radius
			bakeMacGlassRim("dock", w, h, opts)
			if assets.wallpaper or not assets.glow then return end
			assets.dockGlass = {size = size, id = bakeMacGlass("dock", x, y, w, h, size.X, size.Y, opts)}
		end},
		{"3D scene glass", function()
			-- Read the scene's sky so the Dock can be live glass over it
			assets.scenePreview = sky.SkyboxFt
			loadMacSky(sky)
		end},
		{"Icons", function()
			local icons = {}
			for _, id in pairs(MACOS_ICONS) do
				table.insert(icons, id)
			end
			for _, id in pairs(MAC_DESKTOP_ICONS) do
				table.insert(icons, id)
			end
			-- Don't let one slow icon hold up the loader; they finish in the background
			local done = false
			task.spawn(function()
				pcall(ContentProvider.PreloadAsync, ContentProvider, icons)
				done = true
			end)
			local started = os.clock()
			repeat
				task.wait()
			until done or os.clock() - started > 4
		end},
		{"Fonts", function()
			local probes = {}
			for _, weight in ipairs({Enum.FontWeight.Medium, Enum.FontWeight.SemiBold, Enum.FontWeight.Bold}) do
				local probe = Instance.new("TextLabel")
				probe.FontFace = macFont(weight)
				probe.Text = "0123456789 Sun Mon Tue"
				table.insert(probes, probe)
			end
			ContentProvider:PreloadAsync(probes)
			for _, probe in ipairs(probes) do
				probe:Destroy()
			end
		end},
		{"Profile picture", function()
			assets.avatar = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
			ContentProvider:PreloadAsync({assets.avatar})
		end},
	}
	if MACOS_WALLPAPER_URL ~= "" then
		table.insert(steps, 2, {"Wallpaper", function()
			assets.wallpaper = getMacWallpaperAsset()
		end})
	end

	for i, step in ipairs(steps) do
		detail.Text = string.format("%s  ·  %d of %d", step[1], i, #steps)
		local started = os.clock()
		local ok, err = pcall(step[2])
		if not ok then
			warn("[coolui] macOS asset '" .. step[1] .. "' failed: " .. tostring(err))
		end
		-- Keep each step on screen long enough to read
		local elapsed = os.clock() - started
		if elapsed < 0.5 then
			task.wait(0.5 - elapsed)
		end
	end

	status.Text = "Starting macOS"
	detail.Text = ""
	task.wait(0.9)
	TweenService:Create(Spinner, macFadeInfo, {ImageTransparency = 1}):Play()
	TweenService:Create(status, macFadeInfo, {TextTransparency = 1}):Play()
	-- The backdrop turns fully opaque: macOS starts under a copy of it, which
	-- the lock screen then fades away (see createMacSession)
	TweenService:Create(background, macFadeInfo, {ImageTransparency = 0}):Play()
	task.wait(0.5)
	status:Destroy()
	detail:Destroy()

	return runMacOS(assets)
end

-- ==========================================
-- 5. ANIMATION & TIMING SEQUENCE
-- ==========================================
local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Second in loadingsuccess.mp3 where its big hit lands (found by measuring
-- the sound's loudness). The windows' vertical pop starts right on it.
local SUCCESS_HIT_TIME = 2.35

-- Step A: Fade in the background and spinner immediately
TweenService:Create(background, tweenInfo, {ImageTransparency = 0.1}):Play()
TweenService:Create(Spinner, tweenInfo, {ImageTransparency = 0}):Play()

-- Step B: Wait 4 seconds, then transition from Spinner to Lithora Text
task.wait(4)
TweenService:Create(Spinner, tweenInfo, {ImageTransparency = 1}):Play()
task.wait(0.5)

link.Visible = true
TweenService:Create(Description, tweenInfo, {TextTransparency = 0.04}):Play()

-- Step C: Wait 2 seconds, fade text out and play the loading sound
task.wait(2)
TweenService:Create(Description, tweenInfo, {TextTransparency = 1}):Play()
TweenService:Create(background, tweenInfo, {ImageTransparency = 1}):Play()

local successSound
if game.SoundService:FindFirstChild("loadingsuccess") then
	successSound = game.SoundService.loadingsuccess
	successSound.Volume = 1
	successSound:Play()
else
	successSound = playMusic("loadingsuccess.mp3", 1, false)
end

-- Wait on the sound's own playback position (not a fixed timer) so a slow
-- load can't throw the sync off. The X pop starts early enough that the
-- Y pop begins exactly on the hit.
local popStartAt = SUCCESS_HIT_TIME - popXOpenInfo.Time
if successSound then
	local deadline = os.clock() + popStartAt + 2
	repeat
		task.wait()
	until successSound.TimePosition >= popStartAt or not successSound.Parent or os.clock() > deadline
else
	task.wait(popStartAt)
end

-- Step D: UI Popup & Shop Music
local windowsClosing = false
Onboarding.Visible = true
task.spawn(function()
	tweenWindows(popWindows, "x", popXOpenInfo, 1)
	-- If a button was clicked during the X pop, leave the close to it
	if windowsClosing then return end
	tweenWindows(popWindows, "y", popYOpenInfo, 1)
end)

task.spawn(function()
	-- Shop music starts once the loading sound has finished
	local remaining = 4
	if successSound and successSound.TimeLength > 0 then
		remaining = math.max(0, successSound.TimeLength - successSound.TimePosition)
	end
	task.wait(remaining)
	-- Don't start the music if the UI was already closed
	if not musicEnabled then return end
	if game.SoundService:FindFirstChild("shopmusic") then
		game.SoundService.shopmusic.Volume = 1
		game.SoundService.shopmusic:Play()
	else
		playMusic("shopmusic.mp3", 1, true)
	end
end)

-- Set to true to run the old slap loader on the Load button instead of macOS.
local LOAD_BUTTON_RUNS_LOADER = false

local chosenAction = nil
local btn1 = add.MouseButton1Click:Connect(function()
	chosenAction = if LOAD_BUTTON_RUNS_LOADER then "load" else "macos"
end)
local btn2 = close.MouseButton1Click:Connect(function() chosenAction = "close" end)

-- Yield script until a button is clicked
repeat task.wait() until chosenAction ~= nil

-- Hide Popup: pop closed (Y collapses to a line, then X)
windowsClosing = true
popClose(popWindows)
Onboarding.Visible = false

local goodbyeShownAt = nil

-- Goodbye screen, styled like the Lithora intro. The world gets
-- restored behind it, then it fades away at the very end.
-- `closeBehind` (from macOS) runs once the screen is fully covered: the
-- goodbye screen fades in right over the desktop, which is then closed.
local function showGoodbye(closeBehind)
	stopMusic(2)
	Description.Text = '<font color="rgb(54, 61, 162)">Hope to see you later</font>'
	Description.TextTransparency = 1
	link.Visible = true
	if closeBehind then
		-- Above macOS, and opaque while macOS is closed underneath. The backdrop
		-- may still be set from the wallpaper (hidden behind macOS until now).
		background.ImageTransparency = 1
		ScreenGui.DisplayOrder = 1002
	end
	local coverIn = TweenService:Create(background, tweenInfo, {ImageTransparency = if closeBehind then 0 else 0.1})
	coverIn:Play()
	coverIn.Completed:Wait()
	if closeBehind then
		closeBehind()
		TweenService:Create(background, tweenInfo, {ImageTransparency = 0.1}):Play()
	end
	TweenService:Create(Description, tweenInfo, {TextTransparency = 0.04}):Play()
	goodbyeShownAt = os.clock()
end

-- Step E: Handle User Choice
if chosenAction == "load" then
	-- Show spinner for 5 seconds
	local foundslap = false
	local testpassed1 = false
	local testpassed2 = false
	TweenService:Create(background, tweenInfo, {ImageTransparency = 0.1}):Play()
	TweenService:Create(Spinner, tweenInfo, {ImageTransparency = 0}):Play()
	task.wait(3)
	TweenService:Create(Spinner, tweenInfo, {ImageTransparency = 1}):Play()
	TweenService:Create(Description, tweenInfo, {TextTransparency = 0}):Play()
	Description.Text = '<font color="rgb(54, 61, 162)">Vaildaiting</font>'
	task.wait(2.5)
	Description.Text = '<font color="rgb(54, 61, 162)">Checking for slap.</font>'
	task.wait(2)
	if game["Run Service"]:IsStudio() then
		local temptool = Instance.new("Tool")
		temptool.Parent = game.Players.LocalPlayer.Backpack
		slap = temptool
	else
		slap = findslap()
	end
	task.wait(2)
	local tpart = Instance.new("Part")
	tpart.Size = Vector3.new(5,1,5)
	tpart.Position = game.Players.LocalPlayer.Character.HumanoidRootPart.Position + Vector3.new(0,60,0)
	tpart.Anchored = true
	tpart.CanCollide = false
	tpart.Transparency = 1
	tpart.Parent = workspace
	local platform = Instance.new("Part")
	platform.Size = Vector3.new(500,1,500)
	platform.Position = game.Players.LocalPlayer.Character.HumanoidRootPart.Position + Vector3.new(0,50,0)
	platform.Anchored = true
	platform.CanCollide = true
	platform.Transparency = 1
	platform.Parent = workspace
	game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = tpart.CFrame
	task.wait(0.5)
	game.Players.LocalPlayer.Character.HumanoidRootPart.Anchored = false
	if slap then
		Description.Text = '<font color="rgb(0,255,0)">Found slap.</font>'
		foundslap = true
	else
		Description.Text = '<font color="rgb(255,0,0)">Slap not found.</font>'
		foundslap = false
	end
	task.wait(2)
	if foundslap == true then
		Description.Text = '<font color="rgb(54, 61, 162)">Running tests. (0/3) checking slap abilty</font>'
		local plrpos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
		local succes,error = pcall(function()
			hit(game.Players.LocalPlayer)
		end)
		task.wait(2)
		local newplrpos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
		if (newplrpos - plrpos).Magnitude > 5 then
			Description.Text = '<font color="rgb(0,255,0)">Test 1/3 passed. checking cooldown</font>'
			task.wait(2)
			local plrpos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
			local succes,error = pcall(function()
				hit(game.Players.LocalPlayer)
			end)
			Description.Text = '<font color="rgb(0,255,0)">Test 1/3 passed. slap 1</font>'
			task.wait(1)
			local new1plrpos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
			local succes,error = pcall(function()
				hit(game.Players.LocalPlayer)
			end)
			Description.Text = '<font color="rgb(0,255,0)">Test 1/3 passed. slap 2</font>'
			task.wait(1)
			local newerplrpos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
			print(new1plrpos)
			print(newerplrpos)
			if (plrpos - new1plrpos).Magnitude > 5 then
				if (new1plrpos - newerplrpos).Magnitude > 5 then
					testpassed1 = true
				end
			end
			task.wait(2)
			Description.Text = '<font color="rgb(0,255,0)">Test 1/3 passed. checking results...</font>'
			if testpassed1 then
				Description.Text = '<font color="rgb(0,255,0)">Test 2/3 passed. test passed. testing custom power.</font>'
			else
				Description.Text = '<font color="rgb(255,0,0)">Test 2/3 failed. your game has cooldown between each slap it will make it a worse experince.</font>'
			end
			task.wait(3)
			Description.Text = '<font color="rgb(54, 61, 162)">Test 3/3. checking custom power.</font>'
			task.wait(2)
			local plrpos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
			local succes,error = pcall(function()
				hardhit(game.Players.LocalPlayer)
			end)
			task.wait(2)
			local newplrpos = game.Players.LocalPlayer.Character.HumanoidRootPart.Position
			game.Players.LocalPlayer.Character.HumanoidRootPart.Anchored = true
			if (newplrpos - plrpos).Magnitude > 40 then
				testpassed2 = true
			else
				testpassed2 = false
			end
			if testpassed2 then
				Description.Text = '<font color="rgb(0,255,0)">Test 3/3 passed. your game supports the main stuff for it.</font>'
			else
				Description.Text = '<font color="rgb(255,0,0)">Test 3/3 failed. your game does not support custom power if the slap cooldown all so failed just join a diffrent game.</font>'
			end
			task.wait(3)
			if testpassed1 == false and testpassed2 == false then
				Description.Text = '<font color="rgb(255,0,0)">Test 2 and 3 failed it is recommend to just join a new game and rerun the script</font>'
				task.wait(3)
				Description.Text = '<font color="rgb(255,0,0)">but if you still want to load it click yes and no to exit</font>'
				-- Gui to Lua
				-- Version: 3.2

				-- Instances:
				local Opitions = Instance.new("ScreenGui")
				local No = Instance.new("ImageButton")
				local TextLabel = Instance.new("TextLabel")
				local Yes = Instance.new("ImageButton")
				local TextLabel_2 = Instance.new("TextLabel")

				--Properties:
				Opitions.IgnoreGuiInset = true
				Opitions.Parent = game.Players.LocalPlayer.PlayerGui
				Opitions.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				Opitions.Name = "Opitions"

				No.Name = "No"
				No.Parent = Opitions
				No.Active = false
				No.AnchorPoint = Vector2.new(0.5, 0.5)
				No.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
				No.BackgroundTransparency = 1.000
				No.BorderColor3 = Color3.fromRGB(0, 0, 0)
				No.BorderSizePixel = 0
				No.Position = UDim2.new(0.449999988, 0, 0.600000024, 0)
				No.Size = UDim2.new(0, 59, 0, 31)
				No.ZIndex = 8
				No.AutoButtonColor = false
				No.Image = "rbxassetid://99562943404134"
				No.ImageColor3 = Color3.fromRGB(255, 0, 0)
				No.ScaleType = Enum.ScaleType.Slice
				No.SliceCenter = Rect.new(461, 207, 563, 817)

				TextLabel.Parent = No
				TextLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				TextLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				TextLabel.BackgroundTransparency = 1.000
				TextLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
				TextLabel.BorderSizePixel = 0
				TextLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
				TextLabel.Size = UDim2.new(0.899999976, 0, 0.899999976, 0)
				TextLabel.Font = Enum.Font.Unknown
				TextLabel.Text = "No"
				TextLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
				TextLabel.TextSize = 18.000

				Yes.Name = "Yes"
				Yes.Parent = Opitions
				Yes.Active = false
				Yes.AnchorPoint = Vector2.new(0.5, 0.5)
				Yes.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
				Yes.BackgroundTransparency = 1.000
				Yes.BorderColor3 = Color3.fromRGB(0, 0, 0)
				Yes.BorderSizePixel = 0
				Yes.Position = UDim2.new(0.600000024, 0, 0.600000024, 0)
				Yes.Size = UDim2.new(0, 60, 0, 31)
				Yes.ZIndex = 8
				Yes.AutoButtonColor = false
				Yes.Image = "rbxassetid://99562943404134"
				Yes.ImageColor3 = Color3.fromRGB(0, 255, 0)
				Yes.ScaleType = Enum.ScaleType.Slice
				Yes.SliceCenter = Rect.new(461, 207, 563, 817)

				TextLabel_2.Parent = Yes
				TextLabel_2.AnchorPoint = Vector2.new(0.5, 0.5)
				TextLabel_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				TextLabel_2.BackgroundTransparency = 1.000
				TextLabel_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
				TextLabel_2.BorderSizePixel = 0
				TextLabel_2.Position = UDim2.new(0.5, 0, 0.5, 0)
				TextLabel_2.Size = UDim2.new(0.899999976, 0, 0.899999976, 0)
				TextLabel_2.Font = Enum.Font.Unknown
				TextLabel_2.Text = "Yes"
				TextLabel_2.TextColor3 = Color3.fromRGB(200, 200, 200)
				TextLabel_2.TextSize = 18.000
				Yes.MouseButton1Click:Once(function()
					Description.Text = '<font color="rgb(54, 61, 162)">Ok loading anyway.</font>'
					task.wait(2)
					TweenService:Create(background, tweenInfo, {ImageTransparency = 1}):Play()
					task.wait(0.5)
					stopMusic()
					loadstring(game:HttpGet("https://raw.githubusercontent.com/DanielNov2014/RobloxLocalScriptsHacks/refs/heads/main/SlapCommand/SlapCmdMain.lua"))()
					platform:Destroy()
					platform = nil
					Opitions:Destroy()
				end)
				No.MouseButton1Click:Once(function()
					Description.Text = '<font color="rgb(54, 61, 162)">Exiting.</font>'
					task.wait(2)
					TweenService:Create(background, tweenInfo, {ImageTransparency = 1}):Play()
					task.wait(0.5)
					stopMusic()
					platform:Destroy()
					platform = nil
					Opitions:Destroy()
				end)
				repeat task.wait() until not platform
			else
				Description.Text = '<font color="rgb(54, 61, 162)">Loading...</font>'
				task.wait(2)
				loadstring(game:HttpGet("https://raw.githubusercontent.com/DanielNov2014/RobloxLocalScriptsHacks/refs/heads/main/SlapCommand/SlapCmdMain.lua"))()
				TweenService:Create(background, tweenInfo, {ImageTransparency = 1}):Play()
				task.wait(0.5)
				stopMusic()
				platform:Destroy()
			end
		else
			Description.Text = '<font color="rgb(255,0,0)">Test 1/3 failed. this was the most inporten test failed to vaildate exiting...</font>'
			task.wait(4)
			TweenService:Create(background, tweenInfo, {ImageTransparency = 1}):Play()
			task.wait(0.5)
			stopMusic()
			platform:Destroy()
		end
	else
		Description.Text = '<font color="rgb(255,0,0)">finding slap failed. this was the most important test failed to vaildate exiting...</font>'
		task.wait(4)
		TweenService:Create(background, tweenInfo, {ImageTransparency = 1}):Play()
		task.wait(0.5)
		stopMusic()
		platform:Destroy()
	end
elseif chosenAction == "macos" then
	-- Downloading assets, then macOS; Shut Down leads to the goodbye
	showGoodbye(runMacOSLoader())
else
	showGoodbye()
end

-- Keep the goodbye message up for ~2 seconds over the same scene as the
-- Lithora intro; the real world comes back right as it fades out
if goodbyeShownAt then
	local remaining = 2 - (os.clock() - goodbyeShownAt)
	if remaining > 0 then
		task.wait(remaining)
	end
end

-- ==========================================
-- 6. RESTORE EVERYTHING
-- ==========================================
isSpinning = false
antiAfk:Disconnect()
RunService:UnbindFromRenderStep("CustomCameraSway")
for _, connection in ipairs(rankListConnections) do
	connection:Disconnect()
end

camera.CameraType = Enum.CameraType.Custom
camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")

campart:Destroy()
sky:Destroy()
bloom:Destroy()
blur:Destroy()
correction:Destroy()
sunrays:Destroy()

-- Sound cleanup (skipped if the music is already fading out)
if musicEnabled then
	stopMusic()
end

for propName, propValue in pairs(originalLighting) do
	game.Lighting[propName] = propValue
end

for _, v in tempfolder:GetChildren() do
	if v:IsA("Sky") or v:IsA("Atmosphere") then
		v.Parent = game.Lighting
	else
		v.Parent = workspace
	end
end
for _, effect in disabledEffects do
	if effect.Parent then
		effect.Enabled = true
	end
end

-- Restore original volumes
for sound, originalVolume in pairs(storedSoundVolumes) do
	-- Check if the sound still exists in the game before changing it
	if sound and sound.Parent then
		sound.Volume = originalVolume
	end
end

-- Clear the table just to keep memory clean
table.clear(storedSoundVolumes)

tempfolder:Destroy()
rootPart.Anchored = false

-- ==========================================
-- 7. FADE OUT THE GOODBYE SCREEN
-- ==========================================
local coverOutInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
TweenService:Create(Description, tweenInfo, {TextTransparency = 1}):Play()
local coverOut = TweenService:Create(background, coverOutInfo, {ImageTransparency = 1})
coverOut:Play()
coverOut.Completed:Wait()
ScreenGui:Destroy()

-- Bring the game's menus and Roblox's top bar back last, so they
-- don't pop up over the goodbye screen
for gui, originalState in pairs(storedGuiStates) do
	if gui and gui.Parent then
		gui.Enabled = originalState
	end
end
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
end)





