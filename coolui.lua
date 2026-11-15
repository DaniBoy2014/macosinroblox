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
			row.popScale.Scale = 0.92
			task.delay((i - 1) * 0.04, function()
				TweenService:Create(row.popScale, rowPopTweenInfo, {Scale = 1}):Play()
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
	wifi = "rbxassetid://10747382504", -- Lucide "wifi"
	battery = "rbxassetid://10709774206", -- Lucide "battery-full"
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

local function buildMacWallpaper(parent, glowId, imageId)
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
		local h = wall.AbsoluteSize.Y
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
local MAC_GLASS_DISPLACEMENT = 0.05 * math.sqrt(2) * 1000 -- px per unit of bend
local MAC_GLASS_VERSION = 4 -- bump when the look changes so cached images refresh

local macSamplers = {}
local function macSamplerFor(width, height)
	local key = width .. "x" .. height
	macSamplers[key] = macSamplers[key] or macWallpaperSampler(width, height)
	return macSamplers[key]
end

-- The shared glass shader. `shapeAt(px, py)` gives, for pixel (px, py) of the
-- w x h image, how deep inside the shape it is (negative outside) and the
-- outward surface normal. `p` holds pixel lengths (see the wrappers below).
-- Returns the PNG file contents.
local function renderMacGlass(x0, y0, w, h, shapeAt, sample, p)
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
				local scale = edgeFactor(depth) * MAC_GLASS_DISPLACEMENT
				local reach = p.reach(px, py, nx, ny)
				if maxScale > reach then
					scale = scale * math.max(0, reach) / maxScale
				end
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
				local white = wf + wg - wf * wg
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

-- Glass for a rounded rect (a pill by default) at x0, y0, size w x h
local function renderMacGlassPng(x0, y0, w, h, sample, opts)
	opts = opts or MAC_GLASS
	local minAxis = math.min(w, h)
	local halfMin = minAxis / 2
	local radius = math.min(opts.cornerRadius or halfMin, halfMin)
	local halfW, halfH = w / 2, h / 2
	local innerX, innerY = halfW - radius, halfH - radius
	local room = 0.9 * halfMin
	local function rimK(size)
		return if size > 0 then (500 / size) ^ 2 / 1500 else nil
	end
	return renderMacGlass(x0, y0, w, h, function(px, py)
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
	end, sample, {
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
	})
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
-- Shows the lock screen and yields until it's unlocked.
local function showMacLockScreen(assets)
	local gui = Instance.new("ScreenGui")
	gui.Name = "macOS"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1001
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local alive = true
	local connections = {}

	local backgroundMode = loadMacBackgroundChoice()
	local wall = buildMacWallpaper(gui, assets.glow, assets.wallpaper)
	local wallScale = Instance.new("UIScale")
	wallScale.Parent = wall

	local ui = Instance.new("Frame")
	ui.Name = "LockScreen"
	ui.BackgroundTransparency = 1
	ui.Size = UDim2.fromScale(1, 1)
	ui.ZIndex = 2
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
	-- frosted text clock is used instead
	local function applyClockStyle()
		local useGlass = glassClockOn and backgroundMode == "wallpaper"
		glassClock.Visible = useGlass
		clock.Visible = not useGlass
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
	local function statusIcon(image, order)
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.ImageColor3 = Color3.new(1, 1, 1)
		icon.Size = UDim2.fromScale(1, 1)
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		icon.LayoutOrder = order
		icon.Parent = statusBar
	end
	statusIcon(MACOS_ICONS.wifi, 2)
	statusIcon(MACOS_ICONS.battery, 3)
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
	local function applyFieldStyle()
		local fill, rim, pane = fieldStyle()
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

	local switching = false
	local backgroundFade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local function setBackground(mode, animate)
		backgroundMode = mode
		updateSwitch()
		local showWall = mode == "wallpaper"
		-- The Lithora backdrop in the main UI would dim the 3D scene, so clear it
		local backdropTransparency = if showWall then 0.1 else 1
		local shadeTransparency = if showWall then 1 else 0
		if not animate then
			wall.Visible = showWall
			background.ImageTransparency = backdropTransparency
			sceneShade.BackgroundTransparency = shadeTransparency
			applyClockStyle()
			applyFieldStyle()
			return
		end
		TweenService:Create(sceneShade, backgroundFade, {BackgroundTransparency = shadeTransparency}):Play()
		switching = true
		-- Crossfade: the wallpaper rides in a CanvasGroup just for the fade
		local fader = Instance.new("CanvasGroup")
		fader.BackgroundTransparency = 1
		fader.Size = UDim2.fromScale(1, 1)
		fader.GroupTransparency = if showWall then 1 else 0
		fader.Parent = gui
		wall.Visible = true
		wall.Parent = fader
		TweenService:Create(background, backgroundFade, {ImageTransparency = backdropTransparency}):Play()
		local fade = TweenService:Create(fader, backgroundFade, {GroupTransparency = if showWall then 0 else 1})
		fade:Play()
		task.delay(backgroundFade.Time / 2, function()
			if alive then
				applyClockStyle()
				applyFieldStyle()
			end
		end)
		fade.Completed:Wait()
		wall.Parent = gui
		wall.Visible = showWall
		fader:Destroy()
		switching = false
	end
	setBackground(backgroundMode, false)
	table.insert(connections, switch.MouseButton1Click:Connect(function()
		if switching or unlocked then return end
		local mode = if backgroundMode == "wallpaper" then "scene" else "wallpaper"
		saveMacBackgroundChoice(mode)
		setBackground(mode, true)
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

	-- Boot in: fade up from black while the date and clock settle into place
	local overlay = Instance.new("Frame")
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 10
	overlay.Parent = gui
	local settle = TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local clockHome, dateHome = clock.Position, dateLabel.Position
	clock.Position = clockHome - UDim2.fromScale(0, 0.02)
	dateLabel.Position = dateHome - UDim2.fromScale(0, 0.02)
	glassClock.Position = UDim2.fromScale(0, -0.02)
	TweenService:Create(overlay, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	TweenService:Create(clock, settle, {Position = clockHome}):Play()
	TweenService:Create(dateLabel, settle, {Position = dateHome}):Play()
	TweenService:Create(glassClock, settle, {Position = UDim2.fromScale(0, 0)}):Play()

	repeat
		task.wait()
	until unlocked or not gui.Parent

	-- Unlock: the lock screen lifts away, the wallpaper eases forward, then fade out
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
	TweenService:Create(wallScale, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {Scale = 1.06}):Play()
	task.wait(0.35)
	local fadeOut = TweenService:Create(overlay, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 0})
	fadeOut:Play()
	fadeOut.Completed:Wait()

	alive = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	gui:Destroy()
end

-- ---------- Load macOS ----------
-- "Downloading assets" screen (spinner + status text), then the lock screen.
-- Returns once the lock screen is unlocked.
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
		{"Status icons", function()
			ContentProvider:PreloadAsync({MACOS_ICONS.wifi, MACOS_ICONS.battery, MACOS_ICONS.submit, MACOS_ICONS.wallpaper, MACOS_ICONS.scene})
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
	task.wait(0.5)
	status:Destroy()
	detail:Destroy()

	showMacLockScreen(assets)
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
local function showGoodbye()
	stopMusic(2)
	Description.Text = '<font color="rgb(54, 61, 162)">Hope to see you later</font>'
	Description.TextTransparency = 1
	link.Visible = true
	local coverIn = TweenService:Create(background, tweenInfo, {ImageTransparency = 0.1})
	coverIn:Play()
	coverIn.Completed:Wait()
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
	-- Downloading assets, then the lock screen; unlocking leads to the goodbye
	runMacOSLoader()
	showGoodbye()
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
	if v:IsA("Sky") then
		v.Parent = game.Lighting
	else
		v.Parent = workspace
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





