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
-- missing file with a tiny "404: Not Found" page, which is skipped). For a
-- few minutes after a file is added to the repo, GitHub's cache can keep
-- answering "404" for it, so GitHub links get a second try with a query
-- string on the end, which the cache doesn't have yet.
local function downloadAsset(urls, minBytes)
	local lastProblem
	local tries = table.clone(urls)
	for _, url in ipairs(urls) do
		if url:find("raw.githubusercontent.com", 1, true) and not url:find("?", 1, true) then
			table.insert(tries, url .. "?v=" .. os.time())
		end
	end
	for _, url in ipairs(tries) do
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

-- `force`: download it again even if it's saved (Redownload). The saved file
-- is only replaced once the new one has arrived.
local function getMusicAsset(fileName, force)
	local path = MUSIC_FOLDER .. "/" .. fileName
	if force or not isfile(path) then
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

-- ---------- Sleep ----------
-- Sleep (Apple menu) gives the game back while macOS is hidden: the world,
-- camera, lighting, sounds, the game's menus and Roblox's own UI go back to
-- how the game had them. Waking sets the scene up again the way the script
-- did at the start (anything the game changed meanwhile is picked up).
local sceneLighting = {}

local function isCooluiSound(sound)
	return sound.Name:sub(1, 7) == "coolui_" or sound.Name == "shopmusic" or sound.Name == "loadingsuccess"
end

local function sleepScene()
	RunService:UnbindFromRenderStep("CustomCameraSway")
	character = player.Character or character
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = character and character:FindFirstChildOfClass("Humanoid")
	for _, item in {sky, bloom, blur, correction, sunrays, campart} do
		item.Parent = nil
	end
	for name, value in pairs(originalLighting) do
		sceneLighting[name] = game.Lighting[name]
		game.Lighting[name] = value
	end
	for _, v in tempfolder:GetChildren() do
		pcall(function()
			v.Parent = if v:IsA("Sky") or v:IsA("Atmosphere") then game.Lighting else workspace
		end)
	end
	for _, effect in disabledEffects do
		if effect.Parent then
			effect.Enabled = true
		end
	end
	for sound, volume in pairs(storedSoundVolumes) do
		if sound.Parent then
			sound.Volume = volume
		end
	end
	table.clear(storedSoundVolumes)
	for gui, enabled in pairs(storedGuiStates) do
		if gui.Parent then
			gui.Enabled = enabled
		end
	end
	table.clear(storedGuiStates)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)
	rootPart = character and character:FindFirstChild("HumanoidRootPart") or rootPart
	if rootPart then
		rootPart.Anchored = false
	end
end

-- `keepGuis`: our own ScreenGuis, which stay on
local function wakeScene(keepGuis)
	for _, v in workspace:GetChildren() do
		if not v:IsA("Camera") and not v:IsA("Terrain") and not Players:GetPlayerFromCharacter(v) then
			pcall(function()
				v.Parent = tempfolder
			end)
		end
	end
	for _, v in game.Lighting:GetChildren() do
		if v:IsA("Sky") or v:IsA("Atmosphere") then
			v.Parent = tempfolder
		end
	end
	table.clear(disabledEffects)
	for _, container in {game.Lighting, workspace.CurrentCamera, workspace.Terrain} do
		for _, effect in container:GetChildren() do
			if (effect:IsA("PostEffect") or effect:IsA("Clouds")) and effect.Enabled then
				effect.Enabled = false
				table.insert(disabledEffects, effect)
			end
		end
	end
	for name, value in pairs(sceneLighting) do
		game.Lighting[name] = value
	end
	for _, item in {sky, bloom, blur, correction, sunrays} do
		item.Parent = game.Lighting
	end
	campart.Parent = workspace
	for _, container in {workspace, game:GetService("SoundService")} do
		for _, sound in container:GetDescendants() do
			if sound:IsA("Sound") and not isCooluiSound(sound) then
				storedSoundVolumes[sound] = sound.Volume
				sound.Volume = 0
			end
		end
	end
	for _, gui in player.PlayerGui:GetChildren() do
		if gui:IsA("ScreenGui") and not keepGuis[gui] then
			storedGuiStates[gui] = gui.Enabled
			gui.Enabled = false
		end
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	character = player.Character or character
	rootPart = character and character:FindFirstChild("HumanoidRootPart") or rootPart
	if rootPart then
		rootPart.Anchored = true
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = campart.CFrame
	RunService:BindToRenderStep("CustomCameraSway", Enum.RenderPriority.Camera.Value + 1, updateCameraSway)
end

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

-- The rest of the settings, as JSON:
--   appearance     "light" or "dark" (System Settings > Appearance)
--   startupScreen  show the startup screen on Load macOS (System Settings > General)
--   booted         macOS has started before (the first start always shows it)
--   reopen         windows to reopen after Shut Down, when that was ticked
local MAC_SETTINGS_FILE = "coolui_assets/settings.json"
local macSettings = {}
pcall(function()
	if isfile(MAC_SETTINGS_FILE) then
		local decoded = game:GetService("HttpService"):JSONDecode(readfile(MAC_SETTINGS_FILE))
		if type(decoded) == "table" then
			macSettings = decoded
		end
	end
end)
local function saveMacSettings()
	pcall(function()
		if not isfolder("coolui_assets") then
			makefolder("coolui_assets")
		end
		writefile(MAC_SETTINGS_FILE, game:GetService("HttpService"):JSONEncode(macSettings))
	end)
end

-- Ask (Spotlight) talks to Claude with the user's own API key. It's kept in
-- a file of its own in the executor's workspace (not in settings.json), only
-- ever sent to Anthropic, and never shown in full.
local macClaudeKey = {file = "coolui_assets/claude_api_key.txt"}
function macClaudeKey.read()
	local ok, key = pcall(function()
		return if isfile(macClaudeKey.file) then readfile(macClaudeKey.file) else nil
	end)
	key = if ok and type(key) == "string" then key:match("^%s*(.-)%s*$") else nil
	return if key and key ~= "" then key else nil
end
function macClaudeKey.save(key)
	return pcall(function()
		if not isfolder("coolui_assets") then
			makefolder("coolui_assets")
		end
		writefile(macClaudeKey.file, key)
	end)
end
function macClaudeKey.remove()
	pcall(function()
		if isfile(macClaudeKey.file) then
			delfile(macClaudeKey.file)
		end
	end)
end
-- Only the start and the last four characters, for showing in Settings
function macClaudeKey.masked(key)
	return key:sub(1, 7) .. "…" .. key:sub(-4)
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

-- Every image this session has made (or found already made), with how to
-- make it again: System Settings > General > Redownload remakes them all
local macMadeImages = {list = {}, seen = {}}
function macMadeImages.remember(path, make)
	if not macMadeImages.seen[path] then
		macMadeImages.seen[path] = true
		table.insert(macMadeImages.list, {path = path, make = make})
	end
end

local function getMacGlowAsset()
	local path = MACOS_FOLDER .. "/softglow.png"
	macMadeImages.remember(path, getMacGlowAsset)
	if not isfile(path) then
		ensureMacFolder()
		writefile(path, makeGlowPng(128))
	end
	return getcustomasset(path)
end

-- A smooth white disc with a slightly darker rim (tinted to each traffic
-- light's color). As an image it can stretch into a true oval, which a
-- rounded frame can't (its ends would be half circles on a straight middle).
local macDiscId = nil
local MAC_DISC_FILL = 27 / 32 -- how much of the image the disc spans
local function getMacDiscAsset()
	if macDiscId then
		return macDiscId
	end
	-- Small (close to the buttons' size on screen), so shrinking it doesn't
	-- leave a ragged edge, and with a clear margin: Roblox cuts the edges of a
	-- rotated image off sharply, which would notch a disc that touched them
	local path = MACOS_FOLDER .. "/disc_v3.png"
	macMadeImages.remember(path, function()
		macDiscId = nil
		getMacDiscAsset()
	end)
	if not isfile(path) then
		local size = 32
		local radius = MAC_DISC_FILL * size / 2 - 0.5
		local rows = table.create(size)
		for y = 0, size - 1 do
			local row = table.create(size + 1)
			row[1] = "\0"
			for x = 0, size - 1 do
				local d = math.sqrt((x + 0.5 - size / 2) ^ 2 + (y + 0.5 - size / 2) ^ 2)
				local coverage = math.clamp(radius - d + 0.5, 0, 1)
				-- The outermost pixels shade toward 82% for the rim
				local rim = math.clamp((d - (radius - 2)) / 1, 0, 1)
				local value = 1 - 0.18 * rim
				row[x + 2] = string.char(math.floor(value * 255 + 0.5), math.floor(coverage * 255 + 0.5))
			end
			rows[y + 1] = table.concat(row)
		end
		ensureMacFolder()
		writefile(path, macMakePng(size, size, 4, table.concat(rows))) -- 4 = gray + alpha
	end
	macDiscId = getcustomasset(path)
	return macDiscId
end

local function getMacWallpaperAsset(force)
	if MACOS_WALLPAPER_URL == "" then
		return nil
	end
	local ext = if MACOS_WALLPAPER_URL:lower():match("%.jpe?g") then "jpg" else "png"
	local path = MACOS_FOLDER .. "/wallpaper." .. ext
	local urlPath = MACOS_FOLDER .. "/wallpaper_url.txt"
	-- Re-download only when the link changes (or Redownload asks)
	if force or not (isfile(path) and isfile(urlPath) and readfile(urlPath) == MACOS_WALLPAPER_URL) then
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

-- System sounds, from the asset repo (assets/sounds/): the startup chime
-- plays on the startup screen, the log-in sound when you unlock the desktop.
-- Saved next to the other assets, so Music doesn't list them as songs.
local macSounds = {startup = "startup_chime.wav", login = "volume_mount.wav"}
function macSounds.get(fileName, force)
	local path = MACOS_FOLDER .. "/sound_" .. fileName
	if force or not isfile(path) then
		local data = downloadAsset({ASSET_BASE_URL .. "sounds/" .. fileName}, 4096)
		if data:sub(1, 4) ~= "RIFF" then
			error(fileName .. " download looks broken (" .. #data .. " bytes)")
		end
		ensureMacFolder()
		writefile(path, data)
	end
	return getcustomasset(path)
end
-- Plays one without waiting (downloading it first if it isn't saved yet)
function macSounds.play(fileName, volume)
	task.spawn(function()
		local ok, id = pcall(macSounds.get, fileName)
		if not ok then
			warn("[coolui] couldn't play " .. fileName .. ": " .. tostring(id))
			return
		end
		local sound = Instance.new("Sound")
		sound.Name = "coolui_mac_sound"
		sound.SoundId = id
		sound.Volume = volume or 0.5
		sound.Parent = game:GetService("SoundService")
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		game:GetService("Debris"):AddItem(sound, 15)
	end)
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
-- Spotlight's search bar: a capsule of glass with a strong lensing rim. Only
-- lightly tinted: a gradient over it darkens the top (see openSpotlight).
local MAC_SPOTLIGHT_GLASS = {
	thickness = 0.34, refraction = 2.1, aberration = 0.22,
	frost = 0.12,
	tint = Color3.fromRGB(14, 12, 12), tintAlpha = 0.3,
	fresnelSize = 0.1, fresnelHardness = 0.4, fresnelIntensity = 0.3,
	glareSize = 0.2, glareHardness = 0.4, glareIntensity = 0.55,
	glareConvergence = 0.9, glareOpposite = 0.5, glareAngle = -50,
}
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
	macMadeImages.remember(path, function()
		bakeMacGlassRim(name, w, h, opts)
	end)
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
	macMadeImages.remember(path, function()
		bakeMacGlass(name, x0, y0, w, h, width, height, opts)
	end)
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

local function loadMacClockFont(force)
	if macClockFont and not force then
		return macClockFont
	end
	local path = MACOS_FOLDER .. "/clockfont_inter700.ttf"
	if force or not isfile(path) then
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
	macMadeImages.remember(path, function()
		bakeMacClockGlyph(placement, width, height)
	end)
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

-- Light and Dark appearance (System Settings > Appearance). Switching walks
-- the desktop and swaps each color for its counterpart by value, so every
-- color here has to differ from every other color the desktop uses. That's
-- why `surface` is 254 rather than pure white and `line` is (0, 0, 1) rather
-- than pure black: white and black also mean things that don't change (text
-- on blue, shadows).
local MAC_PALETTES = {
	light = {
		ink = Color3.fromRGB(29, 29, 31), -- text
		inkSoft = Color3.fromRGB(118, 118, 124), -- secondary text
		window = Color3.fromRGB(247, 247, 249),
		sidebar = Color3.fromRGB(233, 234, 238),
		menu = Color3.fromRGB(240, 240, 243),
		zebra = Color3.fromRGB(244, 245, 247), -- every other list row
		surface = Color3.fromRGB(254, 254, 254), -- Finder's list, Notes, settings groups
		line = Color3.fromRGB(0, 0, 1), -- hairlines, outlines and hover tints (used see-through)
		unlit = Color3.fromRGB(206, 206, 210), -- traffic lights of inactive windows
		toggleOff = Color3.fromRGB(214, 214, 220),
		track = Color3.fromRGB(222, 222, 226), -- progress bars
		trackFill = Color3.fromRGB(120, 120, 126),
		preview = Color3.fromRGB(236, 236, 240), -- behind images in Preview
		glyph = Color3.fromRGB(96, 98, 106), -- large grey icons
	},
	dark = {
		ink = Color3.fromRGB(235, 235, 240),
		inkSoft = Color3.fromRGB(152, 152, 160),
		window = Color3.fromRGB(38, 38, 42),
		sidebar = Color3.fromRGB(50, 50, 55),
		menu = Color3.fromRGB(46, 46, 51),
		zebra = Color3.fromRGB(45, 45, 49),
		surface = Color3.fromRGB(31, 31, 35),
		line = Color3.fromRGB(255, 255, 254),
		unlit = Color3.fromRGB(80, 80, 86),
		toggleOff = Color3.fromRGB(73, 73, 79),
		track = Color3.fromRGB(66, 66, 72),
		trackFill = Color3.fromRGB(174, 174, 180),
		preview = Color3.fromRGB(33, 33, 37),
		glyph = Color3.fromRGB(172, 174, 182),
	},
}

local MAC_COLORS = {
	accent = Color3.fromRGB(0, 122, 255),
	terminalText = Color3.fromRGB(232, 232, 232),
	terminalError = Color3.fromRGB(255, 120, 110),
	terminalAccent = Color3.fromRGB(120, 220, 140),
}
local function macUsePalette(name)
	for key, value in pairs(MAC_PALETTES[name] or MAC_PALETTES.light) do
		MAC_COLORS[key] = value
	end
end
macUsePalette(if macSettings.appearance == "dark" then "dark" else "light")

-- The desktop is laid out in points for a screen this many points tall,
-- then scaled to the real screen
local MAC_DESK = {
	height = 1080,
	menuHeight = 30,
	dockIcon = 56, dockPadding = 8, dockGap = 6, dockSeparator = 17, dockBottom = 8, dockRadius = 22,
	titleBar = 52, windowRadius = 16, shadowBlur = 44,
}

-- Two icons the Lucide set doesn't have, for the Dock: a stopwatch (Timer)
-- and a speech bubble (Chat). Drawn once as white on clear, 16 samples a
-- pixel so the edges are smooth.
do
	local function drawIcon(name, inside)
		local path = MACOS_FOLDER .. "/icon_" .. name .. "_v1.png"
		local function make()
			if isfile(path) then
				return
			end
			local size = 64
			local rows = table.create(size)
			for y = 0, size - 1 do
				local row = table.create(size + 1)
				row[1] = "\0"
				for x = 0, size - 1 do
					local hits = 0
					for sy = 0, 3 do
						for sx = 0, 3 do
							if inside(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4) then
								hits += 1
							end
						end
					end
					row[x + 2] = "\255" .. string.char(math.floor(hits / 16 * 255 + 0.5))
				end
				rows[y + 1] = table.concat(row)
			end
			ensureMacFolder()
			writefile(path, macMakePng(size, size, 4, table.concat(rows)))
		end
		macMadeImages.remember(path, make)
		local ok, id = pcall(function()
			make()
			return getcustomasset(path)
		end)
		return if ok then id else MAC_DESKTOP_ICONS.apple
	end
	local function segmentDistance(px, py, ax, ay, bx, by)
		local dx, dy = bx - ax, by - ay
		local t = math.clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1)
		return math.sqrt((px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2)
	end
	MAC_DESKTOP_ICONS.timer = drawIcon("timer", function(x, y)
		local d = math.sqrt((x - 32) ^ 2 + (y - 37) ^ 2)
		return (d >= 17 and d <= 22.5) -- the face's rim
			or segmentDistance(x, y, 32, 37, 38.5, 26) <= 2.4 -- the hand
			or d <= 3.4 -- its pivot
			or (math.abs(x - 32) <= 5.5 and y >= 6 and y <= 10.5) -- the button on top
			or (math.abs(x - 32) <= 2 and y >= 9 and y <= 15.5) -- and its stem
			or segmentDistance(x, y, 46.5, 20, 50.5, 16) <= 2.3 -- the side button
	end)
	MAC_DESKTOP_ICONS.chat = drawIcon("chat", function(x, y)
		local ex, ey = (x - 32) / 25, (y - 29) / 19
		if ex * ex + ey * ey <= 1 then
			return true
		end
		-- The tail, down to the bottom left
		local function side(ax, ay, bx, by)
			return (bx - ax) * (y - ay) - (by - ay) * (x - ax)
		end
		local a, b, c = side(15, 38, 10, 54), side(10, 54, 29, 44), side(29, 44, 15, 38)
		return (a >= 0 and b >= 0 and c >= 0) or (a <= 0 and b <= 0 and c <= 0)
	end)
end

-- Dock apps, left to right (the Trash goes after a separator)
local MAC_APPS = {
	{id = "finder", name = "Finder", icon = MAC_DESKTOP_ICONS.finder, top = Color3.fromRGB(110, 198, 255), bottom = Color3.fromRGB(18, 110, 238)},
	{id = "notes", name = "Notes", icon = MAC_DESKTOP_ICONS.notes, top = Color3.fromRGB(255, 228, 120), bottom = Color3.fromRGB(247, 184, 34)},
	{id = "chat", name = "Chat", icon = MAC_DESKTOP_ICONS.chat, top = Color3.fromRGB(104, 232, 116), bottom = Color3.fromRGB(28, 188, 62)},
	{id = "music", name = "Music", icon = MAC_DESKTOP_ICONS.music, top = Color3.fromRGB(255, 110, 132), bottom = Color3.fromRGB(236, 34, 76)},
	{id = "youtube", name = "YouTube", icon = MAC_DESKTOP_ICONS.play, top = Color3.fromRGB(255, 78, 78), bottom = Color3.fromRGB(214, 0, 24)},
	{id = "timer", name = "Timer", icon = MAC_DESKTOP_ICONS.timer, top = Color3.fromRGB(255, 184, 72), bottom = Color3.fromRGB(255, 122, 0)},
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
	local track = macButton(parent, {
		Size = UDim2.fromOffset(34, 20), BackgroundTransparency = 0,
		BackgroundColor3 = if on then MAC_COLORS.accent else MAC_COLORS.toggleOff,
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
		TweenService:Create(track, info, {BackgroundColor3 = if value then MAC_COLORS.accent else MAC_COLORS.toggleOff}):Play()
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

-- ---------- Startup screen ----------
-- The Apple logo over a progress bar on black, like a Mac starting up. It
-- shows the first time macOS ever starts, on every Restart, and on Load
-- macOS when it's switched on (System Settings > General).
-- `fadeIn`: start see-through and fade to black (over the loader); otherwise
-- it starts black (over the black restart cover).
local function createMacBootScreen(parent, zIndex, fadeIn)
	local frame = Instance.new("Frame")
	frame.Name = "Startup"
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = if fadeIn then 1 else 0
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = zIndex
	frame.Parent = parent
	local logo = Instance.new("ImageLabel")
	logo.BackgroundTransparency = 1
	logo.Image = MAC_DESKTOP_ICONS.apple
	logo.ImageTransparency = 1
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.44)
	logo.Size = UDim2.fromScale(0.085, 0.085)
	logo.SizeConstraint = Enum.SizeConstraint.RelativeYY
	logo.ZIndex = zIndex + 1
	logo.Parent = frame
	local track = Instance.new("Frame")
	track.BackgroundColor3 = Color3.new(1, 1, 1)
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.56)
	track.Size = UDim2.fromScale(0.16, 0.0045)
	track.SizeConstraint = Enum.SizeConstraint.RelativeYY
	track.ZIndex = zIndex + 1
	track.Parent = frame
	local fill = track:Clone()
	fill.AnchorPoint = Vector2.zero
	fill.Position = UDim2.fromScale(0, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.SizeConstraint = Enum.SizeConstraint.RelativeXY
	fill.ZIndex = zIndex + 2
	fill.Parent = track
	for _, bar in {track, fill} do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = bar
	end
	-- What it's doing, under the bar (only Redownload uses these)
	local function statusLine(offsetY, textSize)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0.56, offsetY)
		label.Size = UDim2.new(0.8, 0, 0, textSize + 6)
		label.FontFace = macFont(Enum.FontWeight.Medium)
		label.TextSize = textSize
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextTransparency = 1
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = ""
		label.ZIndex = zIndex + 1
		label.Parent = frame
		return label
	end
	local statusLabel = statusLine(22, 15)
	local fileLabel = statusLine(44, 13)

	local boot = {}
	local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- Fades in (to black first, if asked) and shows the logo and bar, with
	-- the startup chime; yields
	function boot.show()
		if fadeIn then
			local black = TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {BackgroundTransparency = 0})
			black:Play()
			black.Completed:Wait()
			task.wait(0.3)
		end
		macSounds.play(macSounds.startup)
		TweenService:Create(logo, fadeInfo, {ImageTransparency = 0}):Play()
		task.wait(0.4)
		TweenService:Create(track, fadeInfo, {BackgroundTransparency = 0.72}):Play()
		TweenService:Create(fill, fadeInfo, {BackgroundTransparency = 0}):Play()
		task.wait(0.5)
	end
	-- `title` ("Downloading music 1/2") and `detail` (the file's name)
	function boot.setStatus(title, detail)
		statusLabel.Text = title or ""
		fileLabel.Text = detail or ""
		if statusLabel.TextTransparency == 1 then
			TweenService:Create(statusLabel, fadeInfo, {TextTransparency = 0.08}):Play()
			TweenService:Create(fileLabel, fadeInfo, {TextTransparency = 0.5}):Play()
		end
	end
	function boot.setProgress(fraction, time)
		TweenService:Create(fill, TweenInfo.new(time or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
		}):Play()
	end
	-- Fills the bar in uneven steps over `duration` seconds, like a real boot; yields
	function boot.run(duration)
		local steps = {0.12, 0.3, 0.36, 0.58, 0.7, 0.86, 0.94, 1}
		for _, fraction in ipairs(steps) do
			local pause = duration / #steps * (0.6 + math.random() * 0.8)
			boot.setProgress(fraction, pause * 0.7)
			task.wait(pause)
		end
	end
	-- The logo and bar fade away, leaving black; yields
	function boot.hide()
		task.wait(0.35)
		local out = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(logo, out, {ImageTransparency = 1}):Play()
		TweenService:Create(track, out, {BackgroundTransparency = 1}):Play()
		TweenService:Create(fill, out, {BackgroundTransparency = 1}):Play()
		TweenService:Create(statusLabel, out, {TextTransparency = 1}):Play()
		TweenService:Create(fileLabel, out, {TextTransparency = 1}):Play()
		task.wait(0.55)
	end
	-- (boot.ownGui: a ScreenGui made just for it, removed too)
	function boot.destroy()
		frame:Destroy()
		if boot.ownGui then
			boot.ownGui:Destroy()
		end
	end
	return boot
end

-- ---------- Session ----------
-- One ScreenGui shared by the lock screen and the desktop, plus the
-- background (wallpaper or 3D scene) that both sit on
local function createMacSession(assets, fromStartupScreen)
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
	-- sight; the first lock screen fades it away, straight out of the loader.
	-- After the startup screen it's built behind black instead.
	if fromStartupScreen then
		session.cover.BackgroundTransparency = 0
	else
		session.veil = background:Clone()
		session.veil.ImageTransparency = 0
		session.veil.ZIndex = 51
		session.veil.Parent = gui
	end

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
			-- Also as a tween, which stops any fade still running on the backdrop
			background.ImageTransparency = backdropTransparency
			TweenService:Create(background, TweenInfo.new(0), {ImageTransparency = backdropTransparency}):Play()
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

-- Redownload (System Settings > General): downloads the music, sounds,
-- clock font and wallpaper again, and deletes and remakes every Liquid Glass
-- image. A downloaded file is only replaced once its new copy has arrived,
-- so a failed download leaves the old one working. Notes, settings, the
-- background choice, the Claude key and your own songs stay. `report(fraction,
-- title, file)` says what it's on; yields.
local function rebuildMacAssets(report)
	local made = {"^glass_", "^glassrim_", "^softglow", "^disc_v", "^edgeglow", "^ripple", "^icon_", "^ytplay"}
	local downloadedMusic = {"loadingsuccess.mp3", "shopmusic.mp3"}
	local doomed = {}
	pcall(function()
		for _, entry in ipairs(macListFolder(MACOS_FOLDER)) do
			for _, pattern in ipairs(made) do
				if not entry.folder and entry.name:match(pattern) then
					table.insert(doomed, entry)
					break
				end
			end
		end
	end)

	-- What to get back, in order: downloads first (the glass clock needs the font)
	local jobs = {}
	for i, name in ipairs(downloadedMusic) do
		table.insert(jobs, {string.format("Downloading music %d/%d", i, #downloadedMusic), name, function()
			getMusicAsset(name, true)
		end})
	end
	for i, name in ipairs({macSounds.startup, macSounds.login}) do
		table.insert(jobs, {string.format("Downloading sound %d/2", i), name, function()
			macSounds.get(name, true)
		end})
	end
	table.insert(jobs, {"Downloading font 1/1", "Inter-Bold.ttf", function()
		loadMacClockFont(true)
	end})
	if MACOS_WALLPAPER_URL ~= "" then
		table.insert(jobs, {"Downloading wallpaper 1/1", MACOS_WALLPAPER_URL:match("([^/?]+)[^/]*$") or "wallpaper", function()
			getMacWallpaperAsset(true)
		end})
	end
	-- Every image this session has used: the glow and the traffic lights'
	-- disc first, then each piece of glass
	local images = {}
	for _, path in ipairs({MACOS_FOLDER .. "/softglow.png", MACOS_FOLDER .. "/disc_v3.png"}) do
		for _, item in ipairs(macMadeImages.list) do
			if item.path == path then
				table.insert(images, item)
			end
		end
	end
	for _, item in ipairs(macMadeImages.list) do
		if not table.find(images, item) then
			table.insert(images, item)
		end
	end
	for i, item in ipairs(images) do
		table.insert(jobs, {string.format("Creating image %d/%d", i, #images), item.path:match("([^/]+)$"), item.make})
	end

	-- Deleting the images counts for the first tenth of the bar
	for i, entry in ipairs(doomed) do
		report(0.1 * i / #doomed, string.format("Deleting old images %d/%d", i, #doomed), entry.name)
		pcall(delfile, entry.path)
		if i % 8 == 0 then
			task.wait()
		end
	end
	local failed = 0
	for i, job in ipairs(jobs) do
		report(0.1 + 0.9 * (i - 1) / #jobs, job[1], job[2])
		task.wait()
		local ok, err = pcall(job[3])
		if not ok then
			failed += 1
			warn("[coolui] Redownload: " .. job[2] .. " failed: " .. tostring(err))
		end
	end
	report(1, if failed > 0 then string.format("Done, but %d couldn't be downloaded", failed) else "All assets downloaded", "")
	return failed
end

local function createMacDesktop(session)
	local gui, assets = session.gui, session.assets
	local D, C, I = MAC_DESK, MAC_COLORS, MAC_DESKTOP_ICONS
	local desktop = {}
	local alive = true
	local connections = {}
	local pendingAction = nil
	-- Light or Dark (System Settings > Appearance); MAC_COLORS holds its palette
	local appearance = if macSettings.appearance == "dark" then "dark" else "light"
	macUsePalette(appearance)
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
	local resize = nil -- {win, sx, sy, start, position, size, min} while an edge is dragged
	local nextWindowGeometry = nil -- {x, y, w, h}: where the next window opens (reopening)
	local lastOpenedWindow = nil

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
	-- sidebarWidth?, titleLeft?, fixedSize?, onClose?, menuName?,
	-- minWidth?, minHeight?}
	local function openWindow(spec)
		local win = {app = spec.app, minimized = false, zoomed = false, closed = false, active = false, cleanup = {}}
		local ax, ay, aw, ah = workArea()
		local width, height = math.min(spec.width, aw), math.min(spec.height, ah)
		local x = math.floor(ax + (aw - width) / 2 + cascade * 24)
		local y = math.floor(ay + math.max(0, (ah - height) / 2 - 30) + cascade * 24)
		cascade = (cascade + 1) % 5
		-- Reopening after Restart / Shut Down: where the window was
		local geometry = nextWindowGeometry
		nextWindowGeometry = nil
		if geometry then
			width = if spec.fixedSize then width else math.clamp(geometry.w, spec.minWidth or 200, aw)
			height = if spec.fixedSize then height else math.clamp(geometry.h, spec.minHeight or 150, ah)
			x = math.clamp(geometry.x, ax, ax + aw - width)
			y = math.clamp(geometry.y, ay, ay + ah - height)
		end
		lastOpenedWindow = win

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
		macStroke(body, if spec.dark then Color3.new(0, 0, 0) else C.line, if spec.dark then 0.4 else 0.86, 1)
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

		-- Traffic lights: close, minimize, zoom (symbols show on hover). Each is
		-- a disc image, so pulling on it can stretch it into a true oval.
		local lightsFrame = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 19), Size = UDim2.fromOffset(54, 14), ZIndex = 6, Parent = body})
		local lightDefs = {
			{Color3.fromRGB(255, 95, 87), "close", Color3.fromRGB(100, 8, 6), true},
			{Color3.fromRGB(254, 188, 46), "minimize", Color3.fromRGB(122, 66, 0), true},
			{Color3.fromRGB(40, 200, 64), "zoom", Color3.fromRGB(0, 88, 12), not spec.fixedSize},
		}
		local discImage = getMacDiscAsset()
		local lights = {}
		local hoveringLights = false
		for i, def in ipairs(lightDefs) do
			local home = UDim2.fromOffset((i - 1) * 20 + 7, 7)
			local light = macButton(lightsFrame, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = home, Size = UDim2.fromOffset(14, 14), ZIndex = 6,
			})
			-- Soft glow in the button's color while it's held
			local glow = macNew("ImageLabel", {
				BackgroundTransparency = 1, Image = assets.glow or "", ImageColor3 = def[1], ImageTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(2.6, 2.6),
				ZIndex = 5, Parent = light,
			})
			-- (the image is a bit bigger than the button: the disc has a clear margin)
			local disc = macNew("ImageLabel", {
				BackgroundTransparency = 1, Image = discImage, ImageColor3 = def[1], AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1 / MAC_DISC_FILL, 1 / MAC_DISC_FILL),
				ZIndex = 6, Parent = light,
			})
			-- The symbol, drawn as bars so it's crisp and bold (it stays upright
			-- and doesn't stretch with the button)
			local glyph = macNew("Frame", {
				BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(14, 14), Visible = false, ZIndex = 7, Parent = light,
			})
			local function bar(rotation, length, thickness)
				local piece = macNew("Frame", {
					BackgroundColor3 = def[3], BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(length, thickness or 1.8), Rotation = rotation,
					ZIndex = 8, Parent = glyph,
				})
				macCorner(piece, UDim.new(1, 0))
			end
			if def[2] == "close" then
				-- (diagonal bars draw thinner, so these are a bit thicker)
				bar(45, 8, 2.2)
				bar(-45, 8, 2.2)
			elseif def[2] == "minimize" then
				bar(0, 8)
			else
				bar(0, 8)
				bar(90, 8)
			end
			local entry = {button = light, disc = disc, glyph = glyph, color = def[1], enabled = def[4], stretched = false, held = false}
			lights[i] = entry

			-- Stretchy, like Liquid Glass: pressed, the button swells a little
			-- and glows; dragged, it pulls into an oval toward the pointer (a
			-- few points at most, giving less the further you pull); let go, it
			-- springs back. A real drag doesn't count as a click.
			local quick = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			light.MouseButton1Down:Connect(function()
				local start = UserInputService:GetMouseLocation()
				entry.stretched = false
				entry.held = true
				win.paintLights()
				-- Over its neighbours while it's held
				light.ZIndex = 8
				TweenService:Create(light, quick, {Size = UDim2.fromOffset(16, 16)}):Play()
				TweenService:Create(glow, quick, {ImageTransparency = 0.45}):Play()
				local moved, ended
				moved = UserInputService.InputChanged:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseMovement then
						return
					end
					local delta = (UserInputService:GetMouseLocation() - start) / s
					local distance = delta.Magnitude
					if distance > 5 then
						entry.stretched = true
					end
					if distance < 0.5 then
						return
					end
					local direction = delta.Unit
					local stretch = 8 * (1 - math.exp(-distance / 26))
					light.Rotation = math.deg(math.atan2(direction.Y, direction.X))
					glyph.Rotation = -light.Rotation
					light.Size = UDim2.fromOffset(16 + stretch, 16 - stretch * 0.3)
					light.Position = home + UDim2.fromOffset(direction.X * stretch * 0.4, direction.Y * stretch * 0.4)
				end)
				ended = UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
						return
					end
					moved:Disconnect()
					ended:Disconnect()
					entry.held = false
					win.paintLights()
					TweenService:Create(glow, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 1}):Play()
					local spring = TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
						Size = UDim2.fromOffset(14, 14), Position = home,
					})
					spring:Play()
					spring.Completed:Once(function(state)
						if state == Enum.PlaybackState.Completed then
							light.Rotation = 0
							glyph.Rotation = 0
							light.ZIndex = 6
						end
					end)
					-- (`stretched` stays set for the click that may follow; the next press clears it)
				end)
			end)
		end
		-- Unlit buttons are grey: light on light windows, dark on dark ones.
		-- The symbols show while the pointer is over the buttons or one is held.
		function win.paintLights()
			local unlit = if spec.dark then Color3.fromRGB(74, 74, 80) else C.unlit
			local anyHeld = false
			for _, light in ipairs(lights) do
				anyHeld = anyHeld or light.held
			end
			for _, light in ipairs(lights) do
				local lit = light.enabled and (win.active or hoveringLights or anyHeld)
				light.disc.ImageColor3 = if lit then light.color else unlit
				light.glyph.Visible = light.enabled and (hoveringLights or anyHeld)
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
			if not lights[1].stretched then
				win.close()
			end
		end)
		lights[2].button.MouseButton1Click:Connect(function()
			if not lights[2].stretched then
				win.minimize()
			end
		end)
		lights[3].button.MouseButton1Click:Connect(function()
			if lights[3].enabled and not lights[3].stretched then
				win.zoom()
			end
		end)

		-- Content sits under the title bar; a sidebar (Tahoe: a rounded panel
		-- floating inside the window) takes the left side from the top
		-- Both clip, so a window stretched small cuts its contents off at its
		-- edges instead of spilling them out
		win.content = macNew("Frame", {
			Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, D.titleBar),
			Size = UDim2.new(1, 0, 1, -D.titleBar), ZIndex = 2, ClipsDescendants = true, Parent = body,
		})
		if spec.sidebarWidth then
			win.sidebar = macNew("Frame", {
				Name = "Sidebar", BackgroundColor3 = C.sidebar, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 8),
				Size = UDim2.new(0, spec.sidebarWidth, 1, -16), ZIndex = 2, ClipsDescendants = true, Parent = body,
			})
			macCorner(win.sidebar, D.windowRadius - 6)
			win.content.Position = UDim2.fromOffset(spec.sidebarWidth + 16, D.titleBar)
			win.content.Size = UDim2.new(1, -(spec.sidebarWidth + 16), 1, -D.titleBar)
		end

		local function forget()
			if drag and drag.win == win then
				drag = nil
			end
			if resize and resize.win == win then
				resize = nil
				UserInputService.MouseIcon = ""
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
			if resize and resize.win == win then
				resize = nil
				UserInputService.MouseIcon = ""
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

		-- Stretching: drag an edge or a corner. The zones straddle the window's
		-- outline (half of each is outside, over the shadow); the top one is
		-- thin so the title bar still drags the window.
		if not spec.fixedSize then
			local minSize = Vector2.new(spec.minWidth or math.min(spec.width, 360), spec.minHeight or math.min(spec.height, 240))
			local edge, corner = 8, 16
			local zones = {
				-- {x direction, y direction, position, size, cursor}
				{-1, 0, UDim2.new(0, -edge / 2, 0, corner / 2), UDim2.new(0, edge, 1, -corner), "SizeEW"},
				{1, 0, UDim2.new(1, -edge / 2, 0, corner / 2), UDim2.new(0, edge, 1, -corner), "SizeEW"},
				{0, -1, UDim2.new(0, corner / 2, 0, -edge / 2), UDim2.new(1, -corner, 0, edge / 2 + 2), "SizeNS"},
				{0, 1, UDim2.new(0, corner / 2, 1, -edge / 2), UDim2.new(1, -corner, 0, edge), "SizeNS"},
				{-1, -1, UDim2.fromOffset(-edge / 2, -edge / 2), UDim2.fromOffset(corner, corner), "SizeNWSE"},
				{1, -1, UDim2.new(1, edge / 2 - corner, 0, -edge / 2), UDim2.fromOffset(corner, corner), "SizeNESW"},
				{-1, 1, UDim2.new(0, -edge / 2, 1, edge / 2 - corner), UDim2.fromOffset(corner, corner), "SizeNESW"},
				{1, 1, UDim2.new(1, edge / 2 - corner, 1, edge / 2 - corner), UDim2.fromOffset(corner, corner), "SizeNWSE"},
			}
			for _, zone in ipairs(zones) do
				local button = macButton(frame, {Name = "Resize", Position = zone[3], Size = zone[4], ZIndex = 10})
				local cursor = "rbxasset://SystemCursors/" .. zone[5]
				button.MouseEnter:Connect(function()
					if not resize and not drag then
						UserInputService.MouseIcon = cursor
					end
				end)
				button.MouseLeave:Connect(function()
					if not resize then
						UserInputService.MouseIcon = ""
					end
				end)
				button.MouseButton1Down:Connect(function()
					if win.minimized or win.closed or frame.Parent ~= windowLayer then
						return
					end
					focusWindow(win)
					win.zoomed = false
					resize = {
						win = win, sx = zone[1], sy = zone[2], min = minSize,
						start = UserInputService:GetMouseLocation(),
						position = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset),
						size = Vector2.new(frame.Size.X.Offset, frame.Size.Y.Offset),
					}
					UserInputService.MouseIcon = cursor
				end)
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

	-- Dragging windows by the title bar, and stretching them by an edge
	connect(UserInputService.InputChanged, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if resize then
			local r = resize
			local win = r.win
			if win.closed or win.minimized or win.frame.Parent ~= windowLayer then
				return
			end
			local delta = (UserInputService:GetMouseLocation() - r.start) / s
			local x, y, w, h = r.position.X, r.position.Y, r.size.X, r.size.Y
			if r.sx > 0 then
				w = math.clamp(r.size.X + delta.X, r.min.X, math.max(r.min.X, screenW - x))
			elseif r.sx < 0 then
				-- The right edge stays put; the left one stops at the screen's edge
				w = math.clamp(r.size.X - delta.X, r.min.X, math.max(r.min.X, r.position.X + r.size.X))
				x = r.position.X + r.size.X - w
			end
			if r.sy > 0 then
				h = math.clamp(r.size.Y + delta.Y, r.min.Y, math.max(r.min.Y, D.height - y))
			elseif r.sy < 0 then
				-- The top stops at the menu bar
				h = math.clamp(r.size.Y - delta.Y, r.min.Y, math.max(r.min.Y, r.position.Y + r.size.Y - D.menuHeight))
				y = r.position.Y + r.size.Y - h
			end
			win.frame.Position = UDim2.fromOffset(x, y)
			win.frame.Size = UDim2.fromOffset(w, h)
			return
		end
		if not drag then
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
			if resize then
				resize = nil
				UserInputService.MouseIcon = ""
			end
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
		macStroke(panel, C.line, 0.86, 1)
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
	local MENU_STYLE = {ink = C.ink, soft = C.inkSoft, softFade = 0, line = C.line, lineFade = 0.88}
	local CLEAR_STYLE = {ink = white, soft = white, softFade = 0.3, line = white, lineFade = 0.7}
	-- Dark text on light glass, whatever the appearance (a shade off the
	-- palette's ink, so switching appearance leaves it alone)
	local DARK_TEXT_STYLE = {ink = Color3.fromRGB(28, 28, 30), soft = Color3.fromRGB(110, 110, 116), softFade = 0, line = Color3.new(0, 0, 0), lineFade = 0.88}

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

	-- ---------- Alerts ----------
	-- A macOS alert in the middle of the screen, over everything. spec:
	-- {title, message, confirm (button text), checkbox = {text, value}?,
	-- countdown? (seconds)}. With a countdown, `message` is a function of the
	-- seconds left, and the alert confirms itself when it runs out. Return
	-- confirms and Escape cancels. Yields; returns confirmed, checked.
	local alertOpen = false
	local function showAlert(spec)
		if alertOpen then
			return false, false
		end
		alertOpen = true
		closeMenu()
		local checked = spec.checkbox ~= nil and spec.checkbox.value == true
		local result = nil
		local blocker = macButton(overlay, {Size = UDim2.fromScale(1, 1), ZIndex = 20})
		local holder = macNew("Frame", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(280, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 21, Parent = overlay,
		})
		local popScale = macNew("UIScale", {Scale = 0.88, Parent = holder})
		macNew("ImageLabel", {
			Name = "Shadow", BackgroundTransparency = 1, Image = assets.glow or "", ImageColor3 = Color3.new(0, 0, 0),
			ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(63, 63, 65, 65), SliceScale = 36 / 63,
			Position = UDim2.fromOffset(-24, -16), Size = UDim2.new(1, 48, 1, 48), ImageTransparency = 0.55, ZIndex = 1, Parent = holder,
		})
		local panel = macNew("Frame", {
			BackgroundColor3 = C.window, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 2, Active = true, Parent = holder,
		})
		macCorner(panel, 20)
		macStroke(panel, C.line, 0.86, 1)
		macNew("UIPadding", {
			PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18),
			PaddingRight = UDim.new(0, 18), Parent = panel,
		})
		macNew("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8), Parent = panel,
		})
		macImage(panel, I.apple, 44, C.ink, {LayoutOrder = 1})
		macLabel(panel, spec.title, 14, Enum.FontWeight.Bold, C.ink, {
			Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2,
		})
		local secondsLeft = spec.countdown
		local function messageText()
			return if type(spec.message) == "function" then spec.message(secondsLeft) else spec.message
		end
		local message = macLabel(panel, messageText(), 12, Enum.FontWeight.Regular, C.ink, {
			Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3,
		})
		if spec.checkbox then
			local row = macButton(panel, {Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4})
			local box = macNew("Frame", {
				BorderSizePixel = 0, Position = UDim2.fromOffset(0, 1), Size = UDim2.fromOffset(15, 15),
				BackgroundColor3 = if checked then C.accent else C.surface, Parent = row,
			})
			macCorner(box, 4)
			local boxRim = macStroke(box, C.line, if checked then 1 else 0.7, 1)
			local tick = macImage(box, I.check, 12, Color3.new(1, 1, 1), {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ImageTransparency = if checked then 0 else 1,
			})
			macLabel(row, spec.checkbox.text, 12, Enum.FontWeight.Regular, C.ink, {
				Position = UDim2.fromOffset(23, 0), Size = UDim2.new(1, -23, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
			})
			row.MouseButton1Click:Connect(function()
				checked = not checked
				box.BackgroundColor3 = if checked then C.accent else C.surface
				boxRim.Transparency = if checked then 1 else 0.7
				tick.ImageTransparency = if checked then 0 else 1
			end)
		end
		-- Cancel and the confirm button, side by side (Tahoe's capsules)
		local buttons = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 5, Parent = panel})
		local function alertButton(text, primary, side)
			local button = macButton(buttons, {
				AnchorPoint = Vector2.new(side, 0), Position = UDim2.fromScale(side, 0), Size = UDim2.new(0.5, -4, 1, 0),
				BackgroundTransparency = if primary then 0 else 0.9, BackgroundColor3 = if primary then C.accent else C.line,
			})
			macCorner(button, UDim.new(1, 0))
			macLabel(button, text, 13, Enum.FontWeight.Medium, if primary then Color3.new(1, 1, 1) else C.ink, {
				Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
			})
			return button
		end
		alertButton("Cancel", false, 0).MouseButton1Click:Connect(function()
			result = result or "cancel"
		end)
		alertButton(spec.confirm, true, 1).MouseButton1Click:Connect(function()
			result = result or "confirm"
		end)
		local keys = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
				result = result or "confirm"
			elseif input.KeyCode == Enum.KeyCode.Escape then
				result = result or "cancel"
			end
		end)
		tween(popScale, 0.22, {Scale = 1}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		local lastSecond = os.clock()
		while result == nil and alive and root.Visible do
			task.wait()
			if secondsLeft and os.clock() - lastSecond >= 1 then
				lastSecond += 1
				secondsLeft -= 1
				if secondsLeft <= 0 then
					result = "confirm"
				else
					message.Text = messageText()
				end
			end
		end
		keys:Disconnect()
		local close = tween(popScale, 0.12, {Scale = 0.92}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		close.Completed:Wait()
		holder:Destroy()
		blocker:Destroy()
		alertOpen = false
		return result == "confirm", checked
	end

	-- The open windows, back to front, to reopen after Restart or Shut Down
	local function snapshotWindows()
		local list = {}
		for _, win in ipairs(windows) do
			if not win.closed then
				local frame = win.frame
				local size = Vector2.new(frame.Size.X.Offset, frame.Size.Y.Offset)
				local position = if win.home then win.home - size / 2 else Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
				local args = {}
				for key, value in pairs(win.openArgs or {}) do
					if key ~= "newWindow" and (type(value) == "string" or type(value) == "number" or type(value) == "boolean") then
						args[key] = value
					end
				end
				-- Where the window has got to (Finder's folder, Settings' pane)
				for key, value in pairs(win.reopenArgs or {}) do
					args[key] = value
				end
				table.insert(list, {
					app = win.app, args = args, minimized = win.minimized,
					x = math.round(position.X), y = math.round(position.Y), w = math.round(size.X), h = math.round(size.Y),
				})
			end
		end
		return list
	end

	local function reopenWindows(list)
		for _, item in ipairs(list) do
			if type(item) == "table" and type(item.app) == "string" then
				local args = if type(item.args) == "table" then table.clone(item.args) else {}
				args.newWindow = true
				nextWindowGeometry = {x = tonumber(item.x) or 0, y = tonumber(item.y) or 0, w = tonumber(item.w) or 400, h = tonumber(item.h) or 300}
				lastOpenedWindow = nil
				pcall(openApp, item.app, args)
				nextWindowGeometry = nil
				local win = lastOpenedWindow
				if win and item.minimized then
					task.delay(0.35, win.minimize)
				end
			end
		end
	end

	local function plural(n, word)
		return n .. " " .. word .. (if n == 1 then "" else "s")
	end

	-- Sleep, Restart and Shut Down, each after its alert (the Apple menu and
	-- Spotlight both use these)
	local function confirmSleep()
		local confirmed, keepRunning = showAlert({
			title = "Put macOS to sleep?",
			message = "macOS hides so you can play the game. To wake it, click Wake macOS at the top of the screen.",
			checkbox = {text = "Keep apps running while asleep (music keeps playing)", value = session.keepRunning == true},
			confirm = "Sleep",
		})
		if confirmed then
			session.keepRunning = keepRunning
			finish("sleep")
		end
	end

	local function confirmRestart()
		local confirmed, reopen = showAlert({
			title = "Are you sure you want to restart your computer now?",
			message = function(left)
				return "If you do nothing, the computer will restart automatically in " .. plural(left, "second") .. "."
			end,
			countdown = 60,
			checkbox = {text = "Reopen windows when logging back in", value = true},
			confirm = "Restart",
		})
		if confirmed then
			desktop.reopenList = if reopen then snapshotWindows() else nil
			finish("restart")
		end
	end

	local function confirmShutDown()
		local confirmed, reopen = showAlert({
			title = "Are you sure you want to shut down your computer now?",
			message = function(left)
				return "If you do nothing, the computer will shut down automatically in " .. plural(left, "second") .. "."
			end,
			countdown = 60,
			checkbox = {text = "Reopen windows when logging back in", value = true},
			confirm = "Shut Down",
		})
		if confirmed then
			-- Saved, so they reopen the next time macOS is loaded
			macSettings.reopen = if reopen then snapshotWindows() else nil
			saveMacSettings()
			finish("shutdown")
		end
	end

	-- System Settings > General > Redownload (see rebuildMacAssets)
	local function confirmRedownload()
		local confirmed, reopen = showAlert({
			title = "Redownload macOS's assets?",
			message = "macOS will restart, delete its music, sounds, font and glass images, and get them all again. Notes, settings and your Claude key stay.",
			checkbox = {text = "Reopen windows when logging back in", value = true},
			confirm = "Redownload",
		})
		if confirmed then
			desktop.reopenList = if reopen then snapshotWindows() else nil
			finish("redownload")
		end
	end

	-- Ask (Spotlight's Claude): filled in by the Ask section further down.
	-- transcript: what the panel shows ({kind, text}); messages: the
	-- conversation as JSON, as Anthropic's API takes it.
	local ask = {transcript = {}, messages = {}, busy = false, status = ""}

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
			{"Sleep…", confirmSleep},
			{"Restart…", confirmRestart},
			{"Shut Down…", confirmShutDown},
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
		-- Over the 3D scene: frosted glass with a faint outline against the
		-- bright sky, light (dark text) or, in Dark appearance, dark (white
		-- text). On the wallpaper: clear glass, with dark text if it's bright.
		local darkGlass = live and appearance == "dark"
		local bright = live and not darkGlass
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
				if darkGlass then
					opts.tint = Color3.fromRGB(30, 30, 34)
				end
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
				panel.BackgroundColor3 = if bright then Color3.fromRGB(240, 240, 243) else Color3.fromRGB(44, 44, 50)
				panel.BackgroundTransparency = if bright then 0.04 else 0.15
				return
			end
			for _, layer in ipairs(layers) do
				tween(layer[1], 0.12, {[layer[2]] = layer[3]}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
		end)
		return if bright then DARK_TEXT_STYLE else CLEAR_STYLE
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
	-- The magnifier opens Spotlight (further down)
	local toggleSpotlight
	local spotlightGlass = nil -- its live glass over the 3D scene
	local searchButton = macButton(menuRight, {Size = UDim2.fromOffset(31, 24), BackgroundColor3 = white, LayoutOrder = 3})
	macCorner(searchButton, 6)
	macImage(searchButton, I.search, 15, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
	searchButton.MouseButton1Down:Connect(function()
		closeMenu()
		toggleSpotlight()
	end)
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
	macStroke(tooltip, C.line, 0.88, 1)
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
			-- (YouTube: a search or a link to play; Timer: seconds to count down;
			-- Music: a category to show)
			if (args.query or args.kind or args.seconds or args.category) and win.handle then
				win.handle(args)
			end
			return
		end
		bounce(appId)
		local builder = appBuilders[appId]
		if builder then
			lastOpenedWindow = nil
			builder(args)
			-- Remembered so the window can be reopened after Restart / Shut Down
			if lastOpenedWindow then
				lastOpenedWindow.openArgs = table.clone(args)
			end
		end
	end

	-- Finder: browses the executor's workspace folder
	appBuilders.finder = function(args)
		local sidebarWidth = 190
		openWindow({
			app = "finder", title = "Workspace", width = 820, height = 500, background = C.surface, minWidth = 560, minHeight = 300,
			sidebarWidth = sidebarWidth, titleLeft = sidebarWidth + 92,
			build = function(win)
				local current = nil
				local history, future = {}, {}
				local sidebarButtons = {}
				local navigate

				-- Scrolls when the window is stretched too short to show it all
				local list = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 46), Size = UDim2.new(1, -14, 1, -56),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
					ScrollBarImageColor3 = C.line, ScrollBarImageTransparency = 0.6, ScrollingDirection = Enum.ScrollingDirection.Y,
					Parent = win.sidebar,
				})
				macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1), Parent = list})
				local function sidebarHeader(text, order)
					macLabel(list, text, 12, Enum.FontWeight.Bold, C.inkSoft, {Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, TextYAlignment = Enum.TextYAlignment.Bottom})
				end
				local function sidebarItem(text, icon, path, order)
					local button = macButton(list, {Size = UDim2.new(1, -6, 0, 30), LayoutOrder = order, BackgroundColor3 = C.line})
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
						BackgroundColor3 = C.line, ZIndex = 5,
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
					BackgroundColor3 = C.line, BackgroundTransparency = 0.9, BorderSizePixel = 0,
					Position = UDim2.new(0, 4, 0, 24), Size = UDim2.new(1, -20, 0, 1), Parent = content,
				})
				local scroller = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(4, 27), Size = UDim2.new(1, -12, 1, -35),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
					ScrollBarImageColor3 = C.line, ScrollBarImageTransparency = 0.6,
					ScrollingDirection = Enum.ScrollingDirection.Y, Parent = content,
				})
				macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller})
				local emptyLabel = macLabel(content, "", 15, Enum.FontWeight.Medium, C.inkSoft, {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 30),
					TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
				})

				local selected = nil
				local function paintRow(row, on)
					row.button.BackgroundColor3 = if on then C.accent else C.zebra
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
					win.reopenArgs = {path = path}
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
							button = button, striped = striped, iconColor = iconColor,
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
			app = "notes", title = name, width = 580, height = 440, background = C.surface, minWidth = 320, minHeight = 220,
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
					ScrollBarImageColor3 = C.line, ScrollBarImageTransparency = 0.6,
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
			app = "terminal", title = player.Name .. " — zsh — 80×24", width = 660, height = 420, dark = true, minWidth = 420, minHeight = 240,
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

	-- ---------- Music ----------
	-- A library made of folders: coolui_music is the library, every folder in
	-- it is a category (lofi, fun, dance…), and a category can hold more
	-- categories, as deep as you like. Songs are the mp3, ogg and wav files in
	-- them. A category's info.json says how it looks (every key is optional,
	-- and a folder without one is still a category):
	--   {
	--     "title": "Lofi",                 shown instead of the folder's name
	--     "description": "Slow beats to study to.",
	--     "image": "cover.png",            a picture in the folder, a workspace path,
	--                                      an rbxassetid:// id or an https:// link
	--                                      (cover.png or cover.jpg is found by itself)
	--     "color": "#8E5CF7",              the cover's color when there's no picture
	--     "artist": "Various Artists",     the songs' artist, unless a song says
	--     "genre": "Hip-Hop", "year": 2026,
	--     "shuffle": true,                 Play shuffles
	--     "volume": 0.8,                   0 to 1 (2 at most)
	--     "songs": {"rain.mp3": {"title": "Rain", "artist": "Someone", "image": "rain.png", "volume": 0.6}}
	--   }
	-- "songs" can also be a list, [{"file": "rain.mp3", …}, …], which sets the
	-- order. A picture named like a song (rain.png) is that song's cover. The
	-- library is read again every few seconds, so changes show up by themselves.
	do
		local HttpService = game:GetService("HttpService")
		local COVER_FOLDER = MACOS_FOLDER .. "/music_covers"
		local PINK = Color3.fromRGB(250, 45, 85)
		local PALETTE = {
			Color3.fromRGB(250, 45, 85), Color3.fromRGB(142, 92, 247), Color3.fromRGB(10, 140, 250), Color3.fromRGB(255, 140, 20),
			Color3.fromRGB(30, 190, 120), Color3.fromRGB(235, 70, 170), Color3.fromRGB(40, 180, 200),
		}
		local images = {} -- a picture's path or link -> its asset id (false: it can't be had)
		local downloads = {} -- link -> what's waiting for it

		local function hashText(text)
			local hash = 5381
			for i = 1, #text do
				hash = (hash * 33 + string.byte(text, i)) % 4294967296
			end
			return hash
		end

		local function fileExists(path)
			local ok, exists = pcall(isfile, path)
			return ok and exists == true
		end

		local function localImage(path)
			if images[path] ~= nil then
				return images[path] or nil
			end
			local id = false
			if MAC_IMAGE_EXTENSIONS[macExtension(path)] and fileExists(path) then
				local ok, asset = pcall(getcustomasset, path)
				id = ok and asset or false
			end
			images[path] = id
			return id or nil
		end

		-- Puts an info.json "image" on `label`, now or once it has downloaded
		local function showImage(label, value, folder)
			if type(value) == "number" then
				value = tostring(math.floor(value))
			end
			if type(value) ~= "string" then
				return
			end
			value = value:match("^%s*(.-)%s*$")
			local function show(id)
				if id and label.Parent then
					label.Image = id
					label.Visible = true
				end
			end
			if value == "" then
				return
			elseif value:match("^%d+$") then
				show("rbxassetid://" .. value)
			elseif value:match("^rbx%w*://") then
				show(value)
			elseif value:match("^https?://") then
				-- Downloaded once and kept in coolui_assets/music_covers
				if images[value] ~= nil then
					show(images[value] or nil)
					return
				end
				if downloads[value] then
					table.insert(downloads[value], show)
					return
				end
				local waiting = {show}
				downloads[value] = waiting
				task.spawn(function()
					local id = false
					pcall(function()
						local base = COVER_FOLDER .. "/" .. string.format("%08x", hashText(value))
						local path = if fileExists(base .. ".png") then base .. ".png" elseif fileExists(base .. ".jpg") then base .. ".jpg" else nil
						if not path then
							local data = game:HttpGet(value)
							local kind = if data:sub(1, 4) == "\137PNG" then ".png" elseif data:sub(1, 3) == "\255\216\255" then ".jpg" else nil
							if not kind then
								error("not a PNG or JPEG picture")
							end
							ensureMacFolder()
							if not isfolder(COVER_FOLDER) then
								makefolder(COVER_FOLDER)
							end
							path = base .. kind
							writefile(path, data)
						end
						id = getcustomasset(path)
					end)
					images[value] = id
					downloads[value] = nil
					for _, callback in ipairs(waiting) do
						callback(id or nil)
					end
				end)
			else
				local relative = value:gsub("\\", "/"):gsub("^%./", "")
				show(localImage(folder .. "/" .. relative) or localImage(relative))
			end
		end

		local function colorOf(value)
			if type(value) == "string" then
				local hex = value:match("^%s*#?(%x%x%x%x%x%x)%s*$")
				if hex then
					return Color3.fromHex(hex)
				end
			elseif type(value) == "table" and tonumber(value[1]) and tonumber(value[2]) and tonumber(value[3]) then
				return Color3.fromRGB(math.clamp(tonumber(value[1]), 0, 255), math.clamp(tonumber(value[2]), 0, 255), math.clamp(tonumber(value[3]), 0, 255))
			end
			return nil
		end

		local function textOf(value)
			if type(value) == "number" then
				return tostring(value)
			elseif type(value) == "string" and value:match("%S") then
				return value:match("^%s*(.-)%s*$")
			end
			return nil
		end

		-- Reads the whole library. Returns its root (the coolui_music folder) and
		-- a fingerprint of everything read, to notice changes by.
		local function readLibrary()
			local seen = {}
			local function read(path, parent, depth)
				local name = path:match("([^/]+)$") or path
				local node = {path = path, name = name, parent = parent, depth = depth, children = {}, songs = {}, info = {}}
				table.insert(seen, path)
				local infoPath = path .. "/info.json"
				if fileExists(infoPath) then
					node.hasInfo = true
					local okRead, raw = pcall(readfile, infoPath)
					raw = if okRead and type(raw) == "string" then raw else ""
					table.insert(seen, raw)
					local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
					if ok and type(decoded) == "table" then
						node.info = decoded
					elseif raw:match("%S") then
						node.problem = "It isn't valid JSON, so it's being skipped. Look for a missing comma, quote or bracket."
					end
				end
				local info = node.info
				node.title = textOf(info.title) or (if parent then name else "Music")
				node.description = textOf(info.description)
				node.artist = textOf(info.artist) or (parent and parent.artist)
				node.genre = textOf(info.genre)
				node.year = textOf(info.year)
				node.color = colorOf(info.color) or (if parent then PALETTE[hashText(name:lower()) % #PALETTE + 1] else PINK)
				node.shuffle = info.shuffle == true
				local volume = tonumber(info.volume)
				node.volume = if volume then math.clamp(volume, 0, 2) else (parent and parent.volume)

				-- Song details by file name (with or without its extension)
				local details, order = {}, {}
				if type(info.songs) == "table" then
					if #info.songs > 0 then
						for i, entry in ipairs(info.songs) do
							local file = if type(entry) == "table" then entry.file elseif type(entry) == "string" then entry else nil
							if type(file) == "string" then
								order[file:lower()] = i
								if type(entry) == "table" then
									details[file:lower()] = entry
								end
							end
						end
					else
						for file, entry in pairs(info.songs) do
							if type(file) == "string" and type(entry) == "table" then
								details[file:lower()] = entry
							end
						end
					end
				end

				local okList, entries = pcall(macListFolder, path)
				entries = if okList then entries else {}
				local pictures = {}
				for _, entry in ipairs(entries) do
					table.insert(seen, entry.path)
					if not entry.folder and MAC_IMAGE_EXTENSIONS[macExtension(entry.name)] then
						pictures[entry.name:lower()] = entry.name
					end
				end
				-- (a picture file that isn't there falls back to cover.png or cover.jpg)
				local image = info.image
				if type(image) == "string" and not image:match("^%s*https?://") and not image:match("^%s*rbx%w*://") and not image:match("^%s*%d+%s*$") then
					local relative = image:match("^%s*(.-)%s*$"):gsub("\\", "/"):gsub("^%./", "")
					if relative == "" or not (fileExists(path .. "/" .. relative) or fileExists(relative)) then
						image = nil
					end
				end
				node.image = if image ~= nil then image
					else pictures["cover.png"] or pictures["cover.jpg"] or pictures["cover.jpeg"] or pictures["folder.png"] or pictures["folder.jpg"]
				for _, entry in ipairs(entries) do
					if entry.folder then
						if depth < 12 then
							table.insert(node.children, read(entry.path, node, depth + 1))
						end
					elseif MAC_AUDIO_EXTENSIONS[macExtension(entry.name)] then
						local key = entry.name:lower()
						local bare = key:gsub("%.%w+$", "")
						local detail = details[key] or details[bare] or {}
						local songVolume = tonumber(detail.volume)
						table.insert(node.songs, {
							path = entry.path, file = entry.name, category = node,
							title = textOf(detail.title) or (entry.name:gsub("%.%w+$", "")),
							artist = textOf(detail.artist) or node.artist,
							image = detail.image or pictures[bare .. ".png"] or pictures[bare .. ".jpg"] or pictures[bare .. ".jpeg"],
							volume = if songVolume then math.clamp(songVolume, 0, 2) else nil,
							order = order[key] or order[bare] or math.huge,
						})
					end
				end
				table.sort(node.songs, function(a, b)
					if a.order ~= b.order then
						return a.order < b.order
					end
					return a.file:lower() < b.file:lower()
				end)
				table.sort(node.children, function(a, b)
					return a.title:lower() < b.title:lower()
				end)
				return node
			end
			pcall(function()
				if not isfolder(MUSIC_FOLDER) then
					makefolder(MUSIC_FOLDER)
				end
			end)
			local root = read(MUSIC_FOLDER, nil, 0)
			return root, table.concat(seen, "\n")
		end

		-- Every song in a category and the categories inside it
		local function songsUnder(node, into)
			into = into or {}
			for _, song in ipairs(node.songs) do
				table.insert(into, song)
			end
			for _, child in ipairs(node.children) do
				songsUnder(child, into)
			end
			return into
		end

		local function eachCategory(node, callback)
			for _, child in ipairs(node.children) do
				callback(child)
				eachCategory(child, callback)
			end
		end

		-- A new category's info.json
		local function infoTemplate(title, description, color, genre)
			local function quoted(text)
				return HttpService:JSONEncode(text)
			end
			return table.concat({
				"{",
				'  "title": ' .. quoted(title) .. ",",
				'  "description": ' .. quoted(description) .. ",",
				'  "image": "cover.png",',
				'  "color": "' .. color .. '",',
				'  "artist": "",',
				'  "genre": ' .. quoted(genre) .. ",",
				'  "shuffle": false,',
				'  "songs": {',
				'    "example.mp3": {"title": "Example Song", "artist": "Someone"}',
				"  }",
				"}",
				"",
			}, "\n")
		end

		-- The first time Music opens: lofi, fun and dance, to show how it works
		local function makeExamples()
			if macSettings.musicExamples then
				return
			end
			macSettings.musicExamples = true
			saveMacSettings()
			pcall(function()
				if not isfolder(MUSIC_FOLDER) then
					makefolder(MUSIC_FOLDER)
				end
				for _, example in ipairs({
					{"lofi", "Lofi", "Slow, warm beats to study, read or relax to.", "#8E5CF7", "Lofi Hip-Hop"},
					{"fun", "Fun", "Bright, bouncy songs that make everything a bit more fun.", "#FF9F0A", "Pop"},
					{"dance", "Dance", "Fast songs with a big beat, for dancing.", "#FF2D78", "Electronic"},
				}) do
					local folder = MUSIC_FOLDER .. "/" .. example[1]
					if not isfolder(folder) then
						makefolder(folder)
						writefile(folder .. "/info.json", infoTemplate(example[2], example[3], example[4], example[5]))
					end
				end
			end)
		end

		local function clockText(seconds)
			seconds = math.max(0, math.floor(seconds))
			return string.format("%d:%02d", seconds // 60, seconds % 60)
		end

		appBuilders.music = function(args)
			local sidebarWidth = 214
			openWindow({
				app = "music", title = "", menuName = "Music", width = 920, height = 600, minWidth = 720, minHeight = 420,
				sidebarWidth = sidebarWidth, background = C.window,
				build = function(win)
					win.frame.Name = "Music"
					local body, sidebar, content = win.body, win.sidebar, win.content
					local sound = macNew("Sound", {Name = "coolui_mac_music", Volume = 0.8, Parent = game:GetService("SoundService")})
					table.insert(win.cleanup, function()
						sound:Destroy()
					end)

					makeExamples()
					local library, fingerprint = readLibrary()
					local page = {kind = "home"}
					local expanded = {[library.path:lower()] = true}
					local queue, queueIndex, current = {}, 0, nil
					local listed = {} -- the songs on the page showing (Play with nothing queued plays these)
					local listedShuffle = false
					local songRows = {}
					local showPage, paintTree

					local function findNode(path)
						path = path:gsub("\\", "/"):gsub("/+$", ""):lower()
						local function search(node)
							if node.path:lower() == path then
								return node
							end
							for _, child in ipairs(node.children) do
								local found = search(child)
								if found then
									return found
								end
							end
							return nil
						end
						return search(library)
					end

					local function hover(button, isOn)
						button.MouseEnter:Connect(function()
							if not (isOn and isOn()) then
								button.BackgroundTransparency = 0.93
							end
						end)
						button.MouseLeave:Connect(function()
							if not (isOn and isOn()) then
								button.BackgroundTransparency = 1
							end
						end)
					end

					-- A cover: the picture if there is one, over a gradient in the
					-- category's color with its first letter
					local function makeCover(parent, node, size, radius, props, song)
						local cover = macNew("Frame", {Size = UDim2.fromOffset(size, size), BackgroundColor3 = white, BorderSizePixel = 0, Parent = parent})
						for key, value in pairs(props or {}) do
							cover[key] = value
						end
						macCorner(cover, radius)
						local color = if node then node.color else PINK
						macNew("UIGradient", {Rotation = 45, Color = ColorSequence.new(color:Lerp(white, 0.3), color), Parent = cover})
						if node and node.parent then
							macLabel(cover, (node.title:match("[%w]") or "?"):upper(), math.max(9, math.round(size * 0.46)), Enum.FontWeight.Bold, white, {
								Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.08,
							})
						else
							macImage(cover, I.music, math.round(size * 0.5), white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
						end
						-- The category's picture, and over it the song's own (if it loads)
						local function art(zIndex)
							local label = macNew("ImageLabel", {
								BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, Visible = false, ZIndex = zIndex, Parent = cover,
							})
							macCorner(label, radius)
							return label
						end
						if node and node.image ~= nil then
							showImage(art(2), node.image, node.path)
						end
						if song and song.image ~= nil and song.category then
							showImage(art(3), song.image, song.category.path)
						end
						return cover
					end

					-- ---- The player, in the title bar ----
					local x0 = sidebarWidth + 22
					local function barButton(icon, size, x)
						local button = macButton(body, {
							AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 26), Size = UDim2.fromOffset(32, 32),
							BackgroundColor3 = C.line, ZIndex = 3,
						})
						macCorner(button, 8)
						local image = macImage(button, icon, size, C.ink, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
						hover(button)
						return button, image
					end
					local prevButton = barButton(I.skipBack, 17, x0 + 16)
					local playButton, playIcon = barButton(I.play, 21, x0 + 52)
					local nextButton = barButton(I.skipForward, 17, x0 + 88)
					local lcdX = x0 + 118
					local lcd = macNew("Frame", {
						Position = UDim2.fromOffset(lcdX, 5), Size = UDim2.new(1, -(lcdX + 18), 0, 42), BackgroundColor3 = C.line,
						BackgroundTransparency = 0.955, BorderSizePixel = 0, ZIndex = 3, Parent = body,
					})
					macCorner(lcd, 9)
					macStroke(lcd, C.line, 0.9, 1)
					macNew("UISizeConstraint", {MaxSize = Vector2.new(560, 42), Parent = lcd})
					local lcdArt = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(32, 32), Parent = lcd})
					local lcdTitle = macLabel(lcd, "Music", 13, Enum.FontWeight.SemiBold, C.ink, {
						Position = UDim2.fromOffset(46, 4), Size = UDim2.new(1, -142, 0, 17), TextTruncate = Enum.TextTruncate.AtEnd,
					})
					local lcdSub = macLabel(lcd, "Not Playing", 11, Enum.FontWeight.Regular, C.inkSoft, {
						Position = UDim2.fromOffset(46, 20), Size = UDim2.new(1, -142, 0, 13), TextTruncate = Enum.TextTruncate.AtEnd,
					})
					local lcdTime = macLabel(lcd, "", 11, Enum.FontWeight.Medium, C.inkSoft, {
						AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(90, 14),
						TextXAlignment = Enum.TextXAlignment.Right,
					})
					-- (click it to jump)
					local seek = macButton(lcd, {Position = UDim2.new(0, 46, 1, -10), Size = UDim2.new(1, -56, 0, 9)})
					local seekTrack = macNew("Frame", {
						AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 3),
						BackgroundColor3 = C.track, BorderSizePixel = 0, Parent = seek,
					})
					macCorner(seekTrack, UDim.new(1, 0))
					local seekFill = macNew("Frame", {BackgroundColor3 = C.trackFill, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = seekTrack})
					macCorner(seekFill, UDim.new(1, 0))

					local function paintPlayer()
						lcdArt:ClearAllChildren()
						if current then
							makeCover(lcdArt, if current.category and current.category.parent then current.category else nil, 32, 6, {}, current)
							lcdTitle.Text = current.title
							local parts = {}
							if current.artist then
								table.insert(parts, current.artist)
							end
							if current.category and current.category.parent then
								table.insert(parts, current.category.title)
							end
							lcdSub.Text = if #parts > 0 then table.concat(parts, " — ") else "coolui"
						else
							makeCover(lcdArt, nil, 32, 6, {})
							lcdTitle.Text = "Music"
							lcdSub.Text = "Not Playing"
						end
					end
					paintPlayer()

					local playingSpeakers = {}
					local function paintSongRows()
						table.clear(playingSpeakers)
						for _, row in ipairs(songRows) do
							local on = current ~= nil and row.song.path == current.path
							row.title.TextColor3 = if on then C.accent else C.ink
							row.number.Visible = not on
							row.speaker.Visible = on
							if on then
								table.insert(playingSpeakers, row.speaker)
							end
						end
					end

					local function play(i)
						local song = queue[i]
						if not song then
							return false
						end
						local ok, id = pcall(getcustomasset, song.path)
						if not ok then
							lcdTitle.Text = "Can't play " .. song.title
							lcdSub.Text = "The file couldn't be loaded"
							return false
						end
						queueIndex, current = i, song
						sound:Stop()
						sound.SoundId = id
						sound.Volume = song.volume or (song.category and song.category.volume) or 0.8
						sound.TimePosition = 0
						sound:Play()
						paintPlayer()
						paintSongRows()
						return true
					end

					-- Plays `songs` from `start`; shuffled, `start` still goes first
					local function playSongs(songs, start, shuffle)
						if #songs == 0 then
							return
						end
						if shuffle then
							local first = songs[start or 0]
							queue = table.clone(songs)
							for i = #queue, 2, -1 do
								local j = math.random(i)
								queue[i], queue[j] = queue[j], queue[i]
							end
							if first then
								table.remove(queue, table.find(queue, first))
								table.insert(queue, 1, first)
							end
							play(1)
						else
							queue = table.clone(songs)
							play(start or 1)
						end
					end

					local function step(direction)
						if #queue == 0 then
							playSongs(listed, 1, listedShuffle)
							return
						end
						if direction < 0 and sound.TimePosition > 3 then
							sound.TimePosition = 0
							return
						end
						play((queueIndex - 1 + direction) % #queue + 1)
					end

					playButton.MouseButton1Click:Connect(function()
						if sound.IsPlaying then
							sound:Pause()
						elseif current then
							sound:Resume()
						else
							playSongs(listed, 1, listedShuffle)
						end
					end)
					prevButton.MouseButton1Click:Connect(function()
						step(-1)
					end)
					nextButton.MouseButton1Click:Connect(function()
						step(1)
					end)
					sound.Ended:Connect(function()
						step(1)
					end)
					seek.MouseButton1Down:Connect(function(x)
						if sound.TimeLength > 0 then
							local fraction = math.clamp((x - seek.AbsolutePosition.X) / seek.AbsoluteSize.X, 0, 1)
							sound.TimePosition = fraction * sound.TimeLength
						end
					end)
					task.spawn(function()
						while not win.closed do
							local length = sound.TimeLength
							seekFill.Size = UDim2.fromScale(if length > 0 then math.clamp(sound.TimePosition / length, 0, 1) else 0, 1)
							lcdTime.Text = if current and length > 0 then clockText(sound.TimePosition) .. " / " .. clockText(length) else ""
							playIcon.Image = if sound.IsPlaying then I.pause else I.play
							for _, speaker in ipairs(playingSpeakers) do
								speaker.ImageTransparency = if sound.IsPlaying then 0 else 0.5
							end
							task.wait(0.2)
						end
					end)

					-- ---- The sidebar: Songs, and the tree of categories ----
					local tree = macNew("ScrollingFrame", {
						BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 46), Size = UDim2.new(1, -12, 1, -46 - 82),
						CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
						ScrollBarImageColor3 = C.line, ScrollBarImageTransparency = 0.6, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = sidebar,
					})
					macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1), Parent = tree})
					local treeItems = {}

					local function pageKey()
						return if page.kind == "category" then page.path:lower() else page.kind
					end

					function paintTree()
						for _, item in ipairs(treeItems) do
							item:Destroy()
						end
						table.clear(treeItems)
						local order = 0
						local function heading(text)
							order += 1
							local label = macLabel(tree, text, 11, Enum.FontWeight.SemiBold, C.inkSoft, {
								Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order, TextYAlignment = Enum.TextYAlignment.Bottom,
							})
							macNew("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6), Parent = label})
							table.insert(treeItems, label)
						end
						local function row(depth, title, node, kind)
							order += 1
							local key = if node then node.path:lower() else kind
							local on = key == pageKey()
							local hasChildren = node ~= nil and #node.children > 0
							local button = macButton(tree, {
								Size = UDim2.new(1, -2, 0, 28), LayoutOrder = order, BackgroundTransparency = if on then 0 else 1,
								BackgroundColor3 = if on then C.accent else C.line,
							})
							macCorner(button, 7)
							if not on then
								hover(button)
							end
							local ink = if on then white else C.ink
							local x = 6 + depth * 14
							if hasChildren then
								local toggle = macButton(button, {Position = UDim2.fromOffset(x, 4), Size = UDim2.fromOffset(16, 20)})
								macImage(toggle, I.forward, 12, if on then white else C.inkSoft, {
									AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = if expanded[key] then 90 else 0,
								})
								toggle.MouseButton1Click:Connect(function()
									expanded[key] = not expanded[key]
									paintTree()
								end)
							end
							x += 18
							if node then
								makeCover(button, node, 20, 5, {Position = UDim2.fromOffset(x, 4)})
							else
								macImage(button, I.music, 16, if on then white else C.accent, {Position = UDim2.fromOffset(x + 2, 6)})
							end
							macLabel(button, title, 13, Enum.FontWeight.Medium, ink, {
								Position = UDim2.fromOffset(x + 28, 0), Size = UDim2.new(1, -(x + 34), 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
							})
							button.MouseButton1Click:Connect(function()
								showPage(if node and node.parent then {kind = "category", path = node.path} elseif node then {kind = "home"} else {kind = kind})
							end)
							table.insert(treeItems, button)
						end
						heading("Library")
						row(0, "Songs", nil, "songs")
						heading("Categories")
						-- The library itself is the tree's top ("Music"), so the home page
						-- is its row (the key for that row is "home")
						order += 1
						do
							local key = library.path:lower()
							local on = page.kind == "home"
							local button = macButton(tree, {
								Size = UDim2.new(1, -2, 0, 28), LayoutOrder = order, BackgroundTransparency = if on then 0 else 1,
								BackgroundColor3 = if on then C.accent else C.line,
							})
							macCorner(button, 7)
							if not on then
								hover(button)
							end
							if #library.children > 0 then
								local toggle = macButton(button, {Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(16, 20)})
								macImage(toggle, I.forward, 12, if on then white else C.inkSoft, {
									AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = if expanded[key] then 90 else 0,
								})
								toggle.MouseButton1Click:Connect(function()
									expanded[key] = not expanded[key]
									paintTree()
								end)
							end
							makeCover(button, library, 20, 5, {Position = UDim2.fromOffset(24, 4)})
							macLabel(button, library.title, 13, Enum.FontWeight.Medium, if on then white else C.ink, {
								Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -58, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
							})
							button.MouseButton1Click:Connect(function()
								showPage({kind = "home"})
							end)
							table.insert(treeItems, button)
						end
						local function walk(node, depth)
							for _, child in ipairs(node.children) do
								row(depth, child.title, child)
								if #child.children > 0 and expanded[child.path:lower()] then
									walk(child, depth + 1)
								end
							end
						end
						if expanded[library.path:lower()] then
							walk(library, 1)
						end
						if #library.children == 0 then
							order += 1
							local note = macLabel(tree, "No categories yet. Every folder in coolui_music is one.", 12, Enum.FontWeight.Regular, C.inkSoft, {
								Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = order,
							})
							macNew("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), Parent = note})
							table.insert(treeItems, note)
						end
					end

					-- Reads the library again; true if anything changed
					local function reload()
						local ok, newLibrary, newPrint = pcall(readLibrary)
						if not ok or newPrint == fingerprint then
							return false
						end
						library, fingerprint = newLibrary, newPrint
						table.clear(images) -- a picture may have been swapped for another of the same name
						local byPath = {}
						for _, song in ipairs(songsUnder(library)) do
							byPath[song.path] = song
						end
						local kept = {}
						for _, song in ipairs(queue) do
							if byPath[song.path] then
								table.insert(kept, byPath[song.path])
							end
						end
						queue = kept
						if current and byPath[current.path] then
							current = byPath[current.path]
						end
						queueIndex = if current then table.find(queue, current) or 0 else 0
						paintPlayer()
						return true
					end

					-- Puts a new category in the one showing (or the library) and opens
					-- its info.json in Notes, to name it
					local function newCategory()
						local parentNode = if page.kind == "category" then findNode(page.path) or library else library
						local base = parentNode.path .. "/New Category"
						local path, n = base, 1
						while isfolder(path) do
							n += 1
							path = base .. " " .. n
						end
						local made = pcall(function()
							makefolder(path)
							writefile(path .. "/info.json", infoTemplate("New Category", "What's in this category.", "#5E5CE6", ""))
						end)
						if not made then
							return
						end
						expanded[parentNode.path:lower()] = true
						reload()
						showPage({kind = "category", path = path})
						openApp("notes", {path = path .. "/info.json", newWindow = true})
					end

					local function sidebarAction(icon, text, bottom, onClick)
						local button = macButton(sidebar, {
							AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -bottom), Size = UDim2.new(1, -16, 0, 30),
							BackgroundColor3 = C.line,
						})
						macCorner(button, 8)
						macImage(button, icon, 16, C.inkSoft, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0)})
						macLabel(button, text, 13, Enum.FontWeight.Medium, C.ink, {Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -40, 1, 0)})
						hover(button)
						button.MouseButton1Click:Connect(onClick)
					end
					sidebarAction(I.plus, "New Category", 42, newCategory)
					sidebarAction(I.folder, "Show in Finder", 8, function()
						local node = if page.kind == "category" then findNode(page.path) else nil
						openApp("finder", {path = if node then node.path else MUSIC_FOLDER, newWindow = true})
					end)

					-- ---- The page ----
					local scroller = macNew("ScrollingFrame", {
						BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
						CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
						ScrollBarImageColor3 = C.line, ScrollBarImageTransparency = 0.6, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = content,
					})
					macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = scroller})
					macNew("UIPadding", {
						PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 22), Parent = scroller,
					})

					local function countText(node)
						local songs, categories = #songsUnder(node), 0
						eachCategory(node, function()
							categories += 1
						end)
						local parts = {}
						if categories > 0 then
							table.insert(parts, categories .. (if categories == 1 then " category" else " categories"))
						end
						table.insert(parts, songs .. (if songs == 1 then " song" else " songs"))
						return table.concat(parts, " · ")
					end

					local function editInfo(node)
						local infoPath = node.path .. "/info.json"
						if not fileExists(infoPath) then
							pcall(writefile, infoPath, infoTemplate(node.title, node.description or "What's in this category.",
								"#" .. node.color:ToHex():upper(), node.genre or ""))
						end
						openApp("notes", {path = infoPath, newWindow = true})
					end

					local function sectionTitle(order, text)
						macLabel(scroller, text, 18, Enum.FontWeight.Bold, C.ink, {
							Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order, TextYAlignment = Enum.TextYAlignment.Bottom,
						})
					end

					local function pill(parent, text, icon, x, width, filled, color, onClick)
						local button = macButton(parent, {
							Position = UDim2.fromOffset(x, 158), Size = UDim2.fromOffset(width, 30), BackgroundTransparency = if filled then 0 else 0.92,
							BackgroundColor3 = if filled then color else C.line,
						})
						macCorner(button, 8)
						local ink = if filled then white else color
						local label = macLabel(button, text, 13, Enum.FontWeight.SemiBold, ink, {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center})
						if icon then
							macImage(button, icon, 14, ink, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0)})
							label.Position = UDim2.fromOffset(10, 0)
						end
						button.MouseEnter:Connect(function()
							button.BackgroundTransparency = if filled then 0.12 else 0.86
						end)
						button.MouseLeave:Connect(function()
							button.BackgroundTransparency = if filled then 0 else 0.92
						end)
						button.MouseButton1Click:Connect(onClick)
						return button
					end

					local function iconButton(parent, icon, x, onClick)
						local button = macButton(parent, {
							Position = UDim2.fromOffset(x, 158), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 0.92, BackgroundColor3 = C.line,
						})
						macCorner(button, UDim.new(1, 0))
						macImage(button, icon, 15, C.ink, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
						button.MouseEnter:Connect(function()
							button.BackgroundTransparency = 0.86
						end)
						button.MouseLeave:Connect(function()
							button.BackgroundTransparency = 0.92
						end)
						button.MouseButton1Click:Connect(onClick)
					end

					-- The top of a page: cover, title, what's in it, Play and Shuffle
					local function header(order, spec)
						local frame = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 204), LayoutOrder = order, Parent = scroller})
						makeCover(frame, spec.node, 176, 12, {Position = UDim2.fromOffset(0, 14)})
						local x = 198
						local color = if spec.node then spec.node.color else PINK
						macLabel(frame, spec.kicker, 12, Enum.FontWeight.SemiBold, C.inkSoft, {
							Position = UDim2.fromOffset(x, 22), Size = UDim2.new(1, -x, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd,
						})
						macLabel(frame, spec.title, 28, Enum.FontWeight.Bold, C.ink, {
							Position = UDim2.fromOffset(x, 40), Size = UDim2.new(1, -x, 0, 34), TextTruncate = Enum.TextTruncate.AtEnd,
						})
						macLabel(frame, spec.subtitle or "", 15, Enum.FontWeight.Medium, color, {
							Position = UDim2.fromOffset(x, 76), Size = UDim2.new(1, -x, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd,
						})
						macLabel(frame, spec.meta or "", 12, Enum.FontWeight.Regular, C.inkSoft, {
							Position = UDim2.fromOffset(x, 98), Size = UDim2.new(1, -x, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd,
						})
						macLabel(frame, spec.description or "", 13, Enum.FontWeight.Regular, C.ink, {
							Position = UDim2.fromOffset(x, 118), Size = UDim2.new(1, -x, 0, 34), TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd,
						})
						local songs = spec.songs
						pill(frame, "Play", I.play, x, 92, true, color, function()
							playSongs(songs, 1, spec.shuffle)
						end)
						pill(frame, "Shuffle", nil, x + 102, 92, false, color, function()
							playSongs(songs, nil, true)
						end)
						local nextX = x + 204
						if spec.node then
							iconButton(frame, I.info, nextX, function()
								editInfo(spec.node)
							end)
							nextX += 40
						end
						iconButton(frame, I.folder, nextX, function()
							openApp("finder", {path = if spec.node then spec.node.path else MUSIC_FOLDER, newWindow = true})
						end)
					end

					-- A list of songs; `withCategory` adds a column saying where each is
					local function songList(order, songs, withCategory, shuffle)
						local holder = macNew("Frame", {
							BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = scroller,
						})
						macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder})
						local titleWidth, artistWidth = if withCategory then 0.44 else 0.6, if withCategory then 0.28 else 0.4
						local headings = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 0, Parent = holder})
						local function heading(text, position, size)
							return macLabel(headings, text, 11, Enum.FontWeight.SemiBold, C.inkSoft, {Position = position, Size = size, TextTruncate = Enum.TextTruncate.AtEnd})
						end
						heading("#", UDim2.fromOffset(6, 0), UDim2.fromOffset(30, 26)).TextXAlignment = Enum.TextXAlignment.Center
						heading("Title", UDim2.fromOffset(84, 0), UDim2.new(titleWidth, -90, 1, 0))
						heading("Artist", UDim2.new(titleWidth, 0, 0, 0), UDim2.new(artistWidth, -10, 1, 0))
						if withCategory then
							heading("Category", UDim2.new(titleWidth + artistWidth, 0, 0, 0), UDim2.new(1 - titleWidth - artistWidth, -10, 1, 0))
						end
						macNew("Frame", {
							BackgroundColor3 = C.line, BackgroundTransparency = 0.9, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
							Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), Parent = headings,
						})
						for i, song in ipairs(songs) do
							local striped = i % 2 == 0
							local button = macButton(holder, {
								Size = UDim2.new(1, 0, 0, 40), LayoutOrder = i, BackgroundTransparency = if striped then 0 else 1, BackgroundColor3 = C.zebra,
							})
							macCorner(button, 6)
							button.MouseEnter:Connect(function()
								button.BackgroundColor3 = C.line
								button.BackgroundTransparency = 0.93
							end)
							button.MouseLeave:Connect(function()
								button.BackgroundColor3 = C.zebra
								button.BackgroundTransparency = if striped then 0 else 1
							end)
							local number = macLabel(button, tostring(i), 12, Enum.FontWeight.Regular, C.inkSoft, {
								Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(30, 40), TextXAlignment = Enum.TextXAlignment.Center,
							})
							local speaker = macImage(button, I.music, 14, C.accent, {
								AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(21, 20), Visible = false,
							})
							makeCover(button, if song.category and song.category.parent then song.category else nil, 28, 5, {Position = UDim2.fromOffset(44, 6)}, song)
							local title = macLabel(button, song.title, 13, Enum.FontWeight.Medium, C.ink, {
								Position = UDim2.fromOffset(84, 0), Size = UDim2.new(titleWidth, -90, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
							})
							macLabel(button, song.artist or "", 13, Enum.FontWeight.Regular, C.inkSoft, {
								Position = UDim2.new(titleWidth, 0, 0, 0), Size = UDim2.new(artistWidth, -10, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
							})
							if withCategory then
								macLabel(button, if song.category and song.category.parent then song.category.title else "", 13, Enum.FontWeight.Regular, C.inkSoft, {
									Position = UDim2.new(titleWidth + artistWidth, 0, 0, 0), Size = UDim2.new(1 - titleWidth - artistWidth, -10, 1, 0),
									TextTruncate = Enum.TextTruncate.AtEnd,
								})
							end
							button.MouseButton1Click:Connect(function()
								playSongs(songs, i, shuffle)
							end)
							table.insert(songRows, {song = song, title = title, number = number, speaker = speaker})
						end
					end

					-- Categories as cards with their covers; hover one to play it
					local function cardGrid(order, nodes)
						local holder = macNew("Frame", {
							BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = scroller,
						})
						macNew("UIGridLayout", {
							CellSize = UDim2.fromOffset(140, 186), CellPadding = UDim2.fromOffset(18, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder,
						})
						for i, node in ipairs(nodes) do
							local card = macButton(holder, {LayoutOrder = i})
							local cover = makeCover(card, node, 140, 10, {})
							macStroke(cover, C.line, 0.92, 1)
							macLabel(card, node.title, 13, Enum.FontWeight.SemiBold, C.ink, {
								Position = UDim2.fromOffset(2, 146), Size = UDim2.new(1, -4, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
							})
							macLabel(card, countText(node), 12, Enum.FontWeight.Regular, C.inkSoft, {
								Position = UDim2.fromOffset(2, 164), Size = UDim2.new(1, -4, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd,
							})
							local quick = macButton(cover, {
								AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.fromOffset(32, 32),
								BackgroundTransparency = 0.35, BackgroundColor3 = Color3.new(0, 0, 0), Visible = false, ZIndex = 4,
							})
							macCorner(quick, UDim.new(1, 0))
							macImage(quick, I.play, 16, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 1, 0.5, 0)})
							card.MouseEnter:Connect(function()
								quick.Visible = true
							end)
							card.MouseLeave:Connect(function()
								quick.Visible = false
							end)
							quick.MouseButton1Click:Connect(function()
								playSongs(songsUnder(node), 1, node.shuffle)
							end)
							card.MouseButton1Click:Connect(function()
								showPage({kind = "category", path = node.path})
							end)
						end
					end

					local function note(order, text, color, onClick)
						local button = macButton(scroller, {
							Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order,
							BackgroundTransparency = if color then 0.85 else 1, BackgroundColor3 = color or C.line, Active = onClick ~= nil,
						})
						macCorner(button, 8)
						macNew("UIPadding", {
							PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9), Parent = button,
						})
						macLabel(button, text, 13, Enum.FontWeight.Regular, C.inkSoft, {
							Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true,
						})
						if onClick then
							button.MouseButton1Click:Connect(onClick)
						end
					end

					function showPage(target, keepScroll)
						local node = nil
						if target.kind == "category" then
							node = findNode(target.path)
							if not node or not node.parent then
								node = nil
								target = {kind = "home"}
							else
								target = {kind = "category", path = node.path}
							end
						end
						page = target
						win.reopenArgs = {category = if node then node.path elseif target.kind == "songs" then "::songs" else ""}
						-- Opening a category shows it, and what's in it, in the tree
						if node and not keepScroll then
							expanded[node.path:lower()] = true
						end
						local up = node and node.parent
						while up do
							expanded[up.path:lower()] = true
							up = up.parent
						end

						local scroll = scroller.CanvasPosition
						for _, child in ipairs(scroller:GetChildren()) do
							if child:IsA("GuiObject") then
								child:Destroy()
							end
						end
						table.clear(songRows)

						if target.kind == "songs" then
							local songs = songsUnder(library)
							listed, listedShuffle = songs, false
							header(1, {
								kicker = "Library", title = "Songs", subtitle = countText(library),
								meta = "Every song in coolui_music and its categories",
								songs = songs, shuffle = false,
							})
							if #songs > 0 then
								songList(3, songs, true, false)
							else
								note(3, "No songs yet. Put mp3, ogg or wav files in <b>coolui_music</b>, or in one of its categories.")
							end
						elseif node then
							local songs = songsUnder(node)
							listed, listedShuffle = songs, node.shuffle
							local crumbs = {}
							local up2 = node.parent
							while up2 do
								table.insert(crumbs, 1, up2.title)
								up2 = up2.parent
							end
							local meta = {}
							if node.artist and node.genre then
								table.insert(meta, node.genre)
							end
							if node.year then
								table.insert(meta, node.year)
							end
							table.insert(meta, countText(node))
							header(1, {
								node = node, kicker = table.concat(crumbs, " › "), title = node.title,
								subtitle = node.artist or node.genre or (if node.depth > 1 then "Subcategory" else "Category"),
								meta = table.concat(meta, " · "), description = node.description,
								songs = songs, shuffle = node.shuffle,
							})
							if node.problem then
								note(2, "<b>Problem with info.json.</b> " .. node.problem .. " Click here to open it.", Color3.fromRGB(255, 159, 10), function()
									editInfo(node)
								end)
							end
							if #node.children > 0 then
								sectionTitle(3, "Categories")
								cardGrid(4, node.children)
							end
							if #songs > 0 then
								if #node.children > 0 then
									sectionTitle(5, "Songs")
								end
								songList(6, songs, #node.children > 0, node.shuffle)
							else
								note(6, "No songs here yet. Put mp3, ogg or wav files in <b>" .. node.path .. "</b> (Show in Finder opens it).")
							end
						else
							listed, listedShuffle = songsUnder(library), false
							header(1, {
								node = library, kicker = "Library", title = library.title, subtitle = countText(library),
								description = library.description or "Every folder in coolui_music is a category, and categories can hold more. Give one an info.json for its title, picture and description.",
								songs = listed, shuffle = false,
							})
							if library.problem then
								note(2, "<b>Problem with info.json.</b> " .. library.problem .. " Click here to open it.", Color3.fromRGB(255, 159, 10), function()
									editInfo(library)
								end)
							end
							if #library.children > 0 then
								sectionTitle(3, "Categories")
								cardGrid(4, library.children)
							else
								note(4, "No categories yet. Click <b>New Category</b>, or make folders in coolui_music.")
							end
							if #library.songs > 0 then
								sectionTitle(5, "Not in a Category")
								songList(6, library.songs, false, false)
							end
						end
						paintSongRows()
						paintTree()
						if keepScroll then
							task.defer(function()
								scroller.CanvasPosition = scroll
							end)
						else
							scroller.CanvasPosition = Vector2.zero
						end
					end

					-- Folder changes (from Finder, Notes or anywhere) show up by themselves
					task.spawn(function()
						while not win.closed do
							task.wait(2.5)
							if not win.closed and reload() then
								showPage(page, true)
							end
						end
					end)

					local function showCategoryArg(value)
						if value == "::songs" then
							showPage({kind = "songs"})
						elseif type(value) == "string" and value ~= "" then
							showPage({kind = "category", path = value})
						else
							showPage({kind = "home"})
						end
					end

					-- An audio file from Finder: played in its category, or by itself
					-- if it's somewhere else; a category's folder: shown
					function win.openPath(path)
						path = path:gsub("\\", "/")
						reload()
						local okFolder, isFolder = pcall(isfolder, path)
						if okFolder and isFolder then
							showCategoryArg(path)
							return
						end
						for _, song in ipairs(songsUnder(library)) do
							if song.path:lower() == path:lower() then
								local songs = song.category.songs
								if song.category.parent then
									showPage({kind = "category", path = song.category.path})
								end
								playSongs(songs, table.find(songs, song), false)
								return
							end
						end
						local fileName = path:match("([^/]+)$") or path
						queue = {{path = path, file = fileName, title = (fileName:gsub("%.%w+$", ""))}}
						play(1)
					end
					function win.handle(handleArgs)
						if handleArgs.category then
							showCategoryArg(handleArgs.category)
						end
					end

					-- For Ask: "play" (a song or a category whose name contains `wanted`,
					-- or carry on), "pause", "next", "previous" or "status". Returns
					-- what's playing, every song and every category, or nil and what
					-- went wrong.
					function win.control(command, wanted)
						reload()
						local everything = songsUnder(library)
						if command == "play" then
							if type(wanted) == "string" and wanted:match("%S") then
								local lower = wanted:lower():match("^%s*(.-)%s*$")
								local found = nil
								for _, song in ipairs(everything) do
									if song.title:lower() == lower or song.file:lower() == lower then
										found = song
										break
									end
								end
								local category = nil
								eachCategory(library, function(node)
									if not category and (node.title:lower() == lower or node.name:lower() == lower) then
										category = node
									end
								end)
								if not found and not category then
									for _, song in ipairs(everything) do
										if song.title:lower():find(lower, 1, true) then
											found = song
											break
										end
									end
								end
								if not found and not category then
									eachCategory(library, function(node)
										if not category and (node.title:lower():find(lower, 1, true) or node.name:lower():find(lower, 1, true)) then
											category = node
										end
									end)
								end
								if found then
									local songs = found.category.songs
									playSongs(songs, table.find(songs, found), false)
								elseif category then
									local songs = songsUnder(category)
									if #songs == 0 then
										return nil, "The " .. category.title .. " category has no songs yet (put audio files in " .. category.path .. ")"
									end
									showPage({kind = "category", path = category.path})
									playSongs(songs, 1, category.shuffle)
								else
									return nil, "There's no song or category called \"" .. wanted .. "\""
								end
							elseif not current then
								playSongs(if #listed > 0 then listed else everything, 1, listedShuffle)
							elseif not sound.IsPlaying then
								sound:Resume()
							end
						elseif command == "pause" then
							sound:Pause()
						elseif command == "next" then
							step(1)
						elseif command == "previous" then
							step(-1)
						end
						local names, categories = {}, {}
						for i, song in ipairs(everything) do
							if i > 150 then
								table.insert(names, "and " .. (#everything - 150) .. " more")
								break
							end
							table.insert(names, if song.category.parent then song.title .. " (" .. song.category.title .. ")" else song.title)
						end
						eachCategory(library, function(node)
							local count = #songsUnder(node)
							table.insert(categories, node.title .. " (" .. count .. (if count == 1 then " song)" else " songs)"))
						end)
						return {
							playing = sound.IsPlaying, track = if current then current.title else nil,
							songs = names, categories = categories,
						}
					end

					showCategoryArg(args.category)
					if args.path then
						win.openPath(args.path)
					end
				end,
			})
		end
	end

	-- ---------- YouTube ----------
	-- Roblox can't play video (it won't load a video file a script saves), and
	-- YouTube won't hand a game its streams, so watching needs the YouTube
	-- helper (youtube_helper.py in the repo) running on this PC. It searches
	-- and decodes with yt-dlp and ffmpeg; this app paints its pictures into an
	-- EditableImage and plays its sound in short mp3 pieces, keeping the
	-- pictures in time with the sound.
	appBuilders.youtube = function(args)
		openWindow({
			app = "youtube", title = "YouTube", width = 980, height = 620, minWidth = 640, minHeight = 460, dark = true,
			background = Color3.fromRGB(15, 15, 15),
			build = function(win)
				local HELPER = "http://127.0.0.1:8765/"
				local HELPER_FILE = "https://raw.githubusercontent.com/" .. ASSET_REPO .. "/" .. ASSET_BRANCH .. "/youtube_helper.py"
				local FOLDER = "coolui_youtube"
				local FPS = 24
				local RED = Color3.fromRGB(255, 0, 51)
				local GREY = Color3.fromRGB(170, 170, 170)
				local CHIP = Color3.fromRGB(39, 39, 39)
				local HttpService = game:GetService("HttpService")
				local AssetService = game:GetService("AssetService")
				local SoundService = game:GetService("SoundService")
				local content = win.content
				local windowOpen = true

				-- ---- Talking to the helper ----
				local function helper(path)
					local send = (syn and syn.request) or http_request or request or (http and http.request)
					if not send then
						return nil
					end
					local ok, response = pcall(send, {Url = HELPER .. path, Method = "GET"})
					if ok and type(response) == "table" and tonumber(response.StatusCode) and tonumber(response.StatusCode) > 0 then
						return response
					end
					return nil
				end
				local function header(response, name)
					for key, value in pairs(response.Headers or {}) do
						if tostring(key):lower() == name then
							return value
						end
					end
					return nil
				end
				local function decode(response)
					local ok, data = pcall(HttpService.JSONDecode, HttpService, response.Body or "")
					return if ok and type(data) == "table" then data else nil
				end
				pcall(function()
					if not isfolder(FOLDER) then
						makefolder(FOLDER)
					end
					if not isfolder(FOLDER .. "/thumbnails") then
						makefolder(FOLDER .. "/thumbnails")
					end
					-- Sound left over from an earlier run
					for _, entry in ipairs(macListFolder(FOLDER)) do
						if not entry.folder and entry.name:match("%.mp3$") then
							delfile(entry.path)
						end
					end
				end)

				-- A white triangle pointing right (YouTube's play symbol), drawn once
				local function triangleImage()
					local path = MACOS_FOLDER .. "/ytplay_v1.png"
					macMadeImages.remember(path, triangleImage)
					if not isfile(path) then
						local size = 32
						local rows = table.create(size)
						-- the corners: (7, 4), (7, 28) and (27, 16), smoothed by sampling 4x4 per pixel
						local function inside(x, y)
							return x >= 7 and (y - 4) >= (x - 7) * 0.6 and (28 - y) >= (x - 7) * 0.6
						end
						for y = 0, size - 1 do
							local row = table.create(size + 1)
							row[1] = "\0"
							for x = 0, size - 1 do
								local hits = 0
								for sy = 0, 3 do
									for sx = 0, 3 do
										if inside(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4) then
											hits += 1
										end
									end
								end
								row[x + 2] = "\255" .. string.char(math.floor(hits / 16 * 255 + 0.5))
							end
							rows[y + 1] = table.concat(row)
						end
						ensureMacFolder()
						writefile(path, macMakePng(size, size, 4, table.concat(rows)))
					end
					return getcustomasset(path)
				end
				local triangle = ""
				pcall(function()
					triangle = triangleImage()
				end)

				local function clockText(seconds)
					seconds = math.max(0, math.floor(seconds or 0))
					if seconds >= 3600 then
						return string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
					end
					return string.format("%d:%02d", seconds // 60, seconds % 60)
				end
				local function shortNumber(n)
					for _, unit in ipairs({{1e9, "B"}, {1e6, "M"}, {1e3, "K"}}) do
						if n >= unit[1] then
							local value = n / unit[1]
							return (if value < 10 then (string.format("%.1f", value):gsub("%.0$", "")) else tostring(math.floor(value))) .. unit[2]
						end
					end
					return tostring(math.floor(n))
				end

				-- ---- Top: the logo, the search field and the tabs ----
				local logo = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 11), Size = UDim2.fromOffset(124, 30), ZIndex = 3, Parent = content})
				local mark = macNew("Frame", {BackgroundColor3 = RED, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(31, 22), ZIndex = 3, Parent = logo})
				macCorner(mark, 7)
				macNew("ImageLabel", {
					BackgroundTransparency = 1, Image = triangle, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.55, 0.5),
					Size = UDim2.fromOffset(14, 14), ZIndex = 4, Parent = mark,
				})
				macLabel(logo, "YouTube", 19, Enum.FontWeight.Bold, white, {Position = UDim2.fromOffset(36, 0), Size = UDim2.fromOffset(90, 30), ZIndex = 3})

				local searchBar = macNew("Frame", {
					BackgroundColor3 = Color3.fromRGB(18, 18, 18), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 30, 0, 8), Size = UDim2.new(1, -330, 0, 36), ZIndex = 3, Parent = content,
				})
				macNew("UISizeConstraint", {MaxSize = Vector2.new(560, 36), Parent = searchBar})
				macCorner(searchBar, UDim.new(1, 0))
				macStroke(searchBar, Color3.fromRGB(56, 56, 56), 0, 1)
				local field = macNew("TextBox", {
					BackgroundTransparency = 1, ClearTextOnFocus = false, Text = "", PlaceholderText = "Search or paste a YouTube link",
					PlaceholderColor3 = Color3.fromRGB(136, 136, 136), TextColor3 = white, FontFace = macFont(Enum.FontWeight.Regular),
					TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -84, 1, 0),
					ClipsDescendants = true, ZIndex = 4, Parent = searchBar,
				})
				local searchButton = macButton(searchBar, {
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 60, 1, 0),
					BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(34, 34, 34), ZIndex = 4,
				})
				macCorner(searchButton, UDim.new(1, 0))
				macImage(searchButton, I.search, 18, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.45, 0.5), ZIndex = 5})

				local TABS = {
					{key = "home", label = "Home", width = 64, kind = "video", query = "trending"},
					{key = "shorts", label = "Shorts", width = 72, kind = "shorts", query = "trending"},
					{key = "live", label = "Live", width = 56, kind = "live", query = "live"},
				}
				local tabButtons = {}
				local currentTab = TABS[1]
				local x = 18
				for _, tab in ipairs(TABS) do
					local button = macButton(content, {
						Position = UDim2.fromOffset(x, 54), Size = UDim2.fromOffset(tab.width, 30), BackgroundTransparency = 0,
						BackgroundColor3 = CHIP, ZIndex = 3,
					})
					macCorner(button, 8)
					local label = macLabel(button, tab.label, 13, Enum.FontWeight.SemiBold, white, {
						Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
					})
					tabButtons[tab.key] = {button = button, label = label}
					x += tab.width + 10
				end
				local function paintTabs()
					for key, tab in pairs(tabButtons) do
						local on = key == currentTab.key
						tab.button.BackgroundColor3 = if on then Color3.fromRGB(241, 241, 241) else CHIP
						tab.label.TextColor3 = if on then Color3.fromRGB(15, 15, 15) else white
					end
				end
				paintTabs()

				-- ---- The grid of videos ----
				local grid = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 1, -96),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6,
					ScrollBarImageColor3 = Color3.fromRGB(120, 120, 120), ScrollBarImageTransparency = 0.3,
					ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 2, Parent = content,
				})
				macNew("UIPadding", {
					PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 18), Parent = grid,
				})
				local gridLayout = macNew("UIGridLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder, CellPadding = UDim2.fromOffset(14, 18), CellSize = UDim2.fromOffset(290, 236), Parent = grid,
				})
				-- A message in the middle of the grid (searching, nothing found, start the helper)
				local notice = macNew("Frame", {
					BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 48),
					Size = UDim2.new(1, -120, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 3, Parent = content,
				})
				macNew("UISizeConstraint", {MaxSize = Vector2.new(520, math.huge), Parent = notice})
				macNew("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), Parent = notice,
				})
				local noticeTitle = macLabel(notice, "", 17, Enum.FontWeight.SemiBold, white, {
					Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, ZIndex = 3,
				})
				local noticeText = macLabel(notice, "", 13, Enum.FontWeight.Regular, GREY, {
					Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true,
					TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, ZIndex = 3,
				})
				local noticeButtons = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 34), LayoutOrder = 3, ZIndex = 3, Parent = notice})
				macNew("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = noticeButtons,
				})
				local function noticeButton(text, order, primary)
					local button = macButton(noticeButtons, {
						Size = UDim2.fromOffset(136, 34), BackgroundTransparency = 0, BackgroundColor3 = if primary then Color3.fromRGB(241, 241, 241) else CHIP,
						LayoutOrder = order, ZIndex = 4,
					})
					macCorner(button, UDim.new(1, 0))
					macLabel(button, text, 13, Enum.FontWeight.SemiBold, if primary then Color3.fromRGB(15, 15, 15) else white, {
						Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5,
					})
					return button
				end
				local retryButton = noticeButton("Try Again", 1, true)
				local copyButton = noticeButton("Copy Helper Link", 2, false)
				local function showNotice(title, text, withButtons)
					notice.Visible = title ~= nil
					noticeTitle.Text = title or ""
					noticeText.Text = text or ""
					noticeText.Visible = text ~= nil and text ~= ""
					noticeButtons.Visible = withButtons == true
				end
				local function showHelperMissing()
					showNotice("YouTube needs its helper",
						"Roblox can't play video by itself, so a small program on your PC does it. Install Python, yt-dlp "
							.. "(<b>pip install -U yt-dlp</b>) and ffmpeg, download <b>youtube_helper.py</b> from the macOS in Roblox repo, "
							.. "and run <b>python youtube_helper.py</b>. Leave it open while you watch.", true)
				end

				-- Thumbnails: saved in the workspace, so they load straight away next time
				local function loadThumbnail(item, label)
					local path = FOLDER .. "/thumbnails/" .. item.id .. ".jpg"
					task.spawn(function()
						local ok = pcall(function()
							if not isfile(path) then
								local data = game:HttpGet("https://i.ytimg.com/vi/" .. item.id .. (if item.short then "/hqdefault.jpg" else "/mqdefault.jpg"))
								if #data < 600 then
									error("no thumbnail")
								end
								writefile(path, data)
							end
						end)
						if ok and label.Parent then
							label.Image = getcustomasset(path)
						end
					end)
				end

				local results = {}
				local resultsKind = "video"
				local cards = {}
				local function layoutGrid()
					local width = grid.AbsoluteSize.X / getScale() - 36 - 8
					if width <= 0 then
						return
					end
					if resultsKind == "shorts" then
						local columns = math.max(2, math.floor((width + 12) / 190))
						local cell = (width - (columns - 1) * 12) / columns
						gridLayout.CellPadding = UDim2.fromOffset(12, 18)
						gridLayout.CellSize = UDim2.fromOffset(cell, cell * 16 / 9 + 48)
					else
						local columns = math.max(1, math.floor((width + 14) / 280))
						local cell = (width - (columns - 1) * 14) / columns
						gridLayout.CellPadding = UDim2.fromOffset(14, 18)
						gridLayout.CellSize = UDim2.fromOffset(cell, cell * 9 / 16 + 74)
					end
				end
				table.insert(win.cleanup, grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid))

				local playItem -- (below)
				local function renderResults()
					for _, card in ipairs(cards) do
						card:Destroy()
					end
					table.clear(cards)
					layoutGrid()
					grid.CanvasPosition = Vector2.zero
					for i, item in ipairs(results) do
						local vertical = resultsKind == "shorts"
						local card = macButton(grid, {LayoutOrder = i, ZIndex = 3})
						local thumb = macNew("ImageLabel", {
							BackgroundColor3 = CHIP, BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop,
							Size = UDim2.new(1, 0, 1, if vertical then -48 else -74), ZIndex = 3, Parent = card,
						})
						macCorner(thumb, if vertical then 12 else 10)
						loadThumbnail({id = item.id, short = vertical}, thumb)
						-- Duration, or LIVE, in the corner
						local badgeText = if item.live then "LIVE" elseif item.duration and not vertical then clockText(item.duration) else nil
						if badgeText then
							local badge = macLabel(thumb, badgeText, 11, Enum.FontWeight.SemiBold, white, {
								AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -6), Size = UDim2.fromOffset(0, 18),
								AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = if item.live then 0 else 0.25,
								BackgroundColor3 = if item.live then Color3.fromRGB(204, 0, 0) else Color3.new(0, 0, 0), ZIndex = 4,
							})
							macCorner(badge, 4)
							macNew("UIPadding", {PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = badge})
						end
						macLabel(card, item.title or "", if vertical then 13 else 14, Enum.FontWeight.Medium, white, {
							Position = UDim2.new(0, 0, 1, if vertical then -42 else -66), Size = UDim2.new(1, 0, 0, if vertical then 34 else 38),
							TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
						})
						local meta = {}
						if not vertical and item.channel and item.channel ~= "" then
							table.insert(meta, item.channel)
						end
						if item.views then
							table.insert(meta, shortNumber(item.views) .. (if item.live then " watching" else " views"))
						end
						macLabel(card, table.concat(meta, " · "), 12, Enum.FontWeight.Regular, GREY, {
							Position = UDim2.new(0, 0, 1, if vertical then -8 else -24), Size = UDim2.new(1, 0, 0, if vertical then 0 else 16),
							TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3, Visible = not vertical or #meta > 0,
						})
						card.MouseButton1Click:Connect(function()
							playItem(item, i)
						end)
						table.insert(cards, card)
					end
				end

				local searchNumber = 0
				local function search(query, kind)
					searchNumber += 1
					local number = searchNumber
					results = {}
					resultsKind = kind
					renderResults()
					showNotice("Searching…")
					local response = helper(("search?type=%s&limit=30&q=%s"):format(kind, HttpService:UrlEncode(query)))
					if number ~= searchNumber or not windowOpen then
						return nil
					end
					if not response then
						showHelperMissing()
						return nil
					end
					local data = decode(response)
					if response.StatusCode ~= 200 or not data then
						showNotice("Search didn't work", if data and data.error then tostring(data.error) else "The helper couldn't search YouTube.")
						return nil
					end
					results = data.results or {}
					showNotice(if #results == 0 then "No results" else nil)
					renderResults()
					return results
				end

				-- ---- The player ----
				local playerView = macNew("Frame", {
					BackgroundColor3 = Color3.fromRGB(15, 15, 15), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false,
					ZIndex = 6, Active = true, Parent = content,
				})
				local stage = macNew("Frame", {
					BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Position = UDim2.fromOffset(20, 6), Size = UDim2.new(1, -40, 1, -112),
					ClipsDescendants = true, ZIndex = 6, Parent = playerView,
				})
				macCorner(stage, 14)
				local screen = macNew("ImageLabel", {
					BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = stage,
				})
				local stageStatus = macLabel(stage, "", 16, Enum.FontWeight.Medium, white, {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -60, 0, 60),
					TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, TextTransparency = 0.15, ZIndex = 8,
				})
				local function roundButton(parent, props)
					props.Size = props.Size or UDim2.fromOffset(36, 36)
					props.BackgroundTransparency = props.BackgroundTransparency or 0.35
					props.BackgroundColor3 = props.BackgroundColor3 or Color3.new(0, 0, 0)
					props.ZIndex = props.ZIndex or 8
					local button = macButton(parent, props)
					macCorner(button, UDim.new(1, 0))
					return button
				end
				local backButton = roundButton(stage, {Position = UDim2.fromOffset(12, 12)})
				macImage(backButton, I.back, 20, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 9})
				-- Shorts: up and down to the previous and next one
				local upButton = roundButton(stage, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, -26), Visible = false})
				macImage(upButton, I.back, 20, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = 90, ZIndex = 9})
				local downButton = roundButton(stage, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 26), Visible = false})
				macImage(downButton, I.back, 20, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = -90, ZIndex = 9})

				-- Controls under the picture: play/pause, time, the progress bar, mute
				local controls = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.new(0, 20, 1, -100), Size = UDim2.new(1, -40, 0, 36), ZIndex = 6, Parent = playerView})
				local playButton = roundButton(controls, {BackgroundTransparency = 0, BackgroundColor3 = CHIP, ZIndex = 7})
				local playIcon = macNew("ImageLabel", {
					BackgroundTransparency = 1, Image = triangle, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.54, 0.5),
					Size = UDim2.fromOffset(16, 16), ZIndex = 8, Parent = playButton,
				})
				local pauseIcon = macNew("Frame", {
					BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 14),
					ZIndex = 8, Parent = playButton,
				})
				for _, xBar in ipairs({0, 8}) do
					local bar = macNew("Frame", {BackgroundColor3 = white, BorderSizePixel = 0, Position = UDim2.fromOffset(xBar, 0), Size = UDim2.fromOffset(4, 14), ZIndex = 8, Parent = pauseIcon})
					macCorner(bar, 1)
				end
				local timeLabel = macLabel(controls, "", 13, Enum.FontWeight.Medium, white, {
					Position = UDim2.fromOffset(48, 0), Size = UDim2.fromOffset(120, 36), ZIndex = 7,
				})
				local liveDot = macNew("Frame", {
					BackgroundColor3 = Color3.fromRGB(255, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 50, 0.5, 0),
					Size = UDim2.fromOffset(8, 8), Visible = false, ZIndex = 7, Parent = controls,
				})
				macCorner(liveDot, UDim.new(1, 0))
				local progress = macButton(controls, {
					Position = UDim2.new(0, 176, 0.5, -8), Size = UDim2.new(1, -176 - 100, 0, 16), ZIndex = 7,
				})
				local track = macNew("Frame", {
					BackgroundColor3 = white, BackgroundTransparency = 0.75, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 4), ZIndex = 7, Parent = progress,
				})
				macCorner(track, UDim.new(1, 0))
				local fill = macNew("Frame", {BackgroundColor3 = RED, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 8, Parent = track})
				macCorner(fill, UDim.new(1, 0))
				local knob = macNew("Frame", {
					BackgroundColor3 = RED, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.fromOffset(12, 12), ZIndex = 9, Parent = track,
				})
				macCorner(knob, UDim.new(1, 0))
				local muteButton = macButton(controls, {
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(86, 36),
					BackgroundTransparency = 0, BackgroundColor3 = CHIP, ZIndex = 7,
				})
				macCorner(muteButton, UDim.new(1, 0))
				local muteLabel = macLabel(muteButton, "Mute", 13, Enum.FontWeight.SemiBold, white, {
					Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8,
				})
				local videoTitle = macLabel(playerView, "", 17, Enum.FontWeight.Bold, white, {
					Position = UDim2.new(0, 22, 1, -56), Size = UDim2.new(1, -44, 0, 24), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6,
				})
				local videoChannel = macLabel(playerView, "", 13, Enum.FontWeight.Regular, GREY, {
					Position = UDim2.new(0, 22, 1, -30), Size = UDim2.new(1, -44, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6,
				})

				-- State of what's playing. Pictures come from the helper in batches
				-- into `queue` ({number, pixels}); the sound's position is the clock
				-- that decides which picture shows.
				local player = {gen = 0, queue = {}, sounds = {}, files = {}, volume = 0.8, muted = false}
				local image, imageSize = nil, nil
				local function setStatus(text)
					stageStatus.Text = text or ""
					stageStatus.Visible = text ~= nil
				end

				local function stopPlayback()
					player.gen += 1
					local info = player.info
					player.info = nil
					if info then
						task.spawn(helper, "stop?session=" .. info.session)
					end
					for _, sound in ipairs(player.sounds) do
						sound:Destroy()
					end
					table.clear(player.sounds)
					for _, path in ipairs(player.files) do
						pcall(delfile, path)
					end
					table.clear(player.files)
					table.clear(player.queue)
					player.current, player.firstIndex, player.audioClock = nil, nil, nil
					player.silentBase, player.silentStarted = nil, nil
					player.picturesDone, player.finished, player.buffering, player.failed = false, false, false, false
					player.lastShown = nil
				end

				-- The playing position in seconds from where this session started
				function player.time()
					if player.audioClock then
						return player.audioClock()
					elseif player.silentBase then
						return player.silentBase + (if player.silentStarted then os.clock() - player.silentStarted else 0)
					end
					return nil
				end

				-- One piece of sound as a Sound, false when there's no more, nil if stopped
				local function loadSegment(gen, info, number)
					while gen == player.gen do
						local response = helper(("audio?session=%s&seg=%d"):format(info.session, number))
						if gen ~= player.gen then
							return nil
						end
						local status = response and tonumber(response.StatusCode) or 0
						if status == 200 then
							local path = ("%s/%s_%d.mp3"):format(FOLDER, info.session, number)
							if not pcall(writefile, path, response.Body) then
								return false
							end
							table.insert(player.files, path)
							local sound = macNew("Sound", {
								Name = "coolui_youtube_sound", SoundId = getcustomasset(path), Volume = if player.muted then 0 else player.volume,
								Parent = SoundService,
							})
							table.insert(player.sounds, sound)
							return sound
						elseif status ~= 202 then
							return false
						end
						task.wait(0.3)
					end
					return nil
				end

				local function runSound(gen, info)
					while not player.firstIndex and gen == player.gen do
						task.wait()
					end
					if gen ~= player.gen then
						return
					end
					local segment = info.segment or 10
					local offset = player.firstIndex / info.fps
					local number = math.floor(offset / segment)
					offset -= number * segment
					local current = if info.silent then false else loadSegment(gen, info, number)
					if current == nil then
						return
					elseif current == false then
						-- No sound: keep time by the clock instead
						player.silentBase = player.firstIndex / info.fps
						player.silentStarted = if player.paused then nil else os.clock()
						return
					end
					while not current.IsLoaded and gen == player.gen do
						task.wait()
					end
					if gen ~= player.gen then
						return
					end
					current.TimePosition = offset
					player.current, player.base = current, number * segment
					local finishing = false
					player.audioClock = function()
						local sound = player.current
						return player.base + (if finishing then sound.TimeLength else sound.TimePosition)
					end
					if not player.paused then
						current:Play()
					end
					local upcoming = nil
					local function fetch(n)
						task.spawn(function()
							local sound = loadSegment(gen, info, n)
							if gen == player.gen then
								upcoming = sound
							end
						end)
					end
					fetch(number + 1)
					-- Each piece hands over to the next just before it ends
					while gen == player.gen do
						local sound = player.current
						if not finishing and sound.TimeLength > 0 and sound.TimePosition >= sound.TimeLength - 0.035 then
							finishing = true
						end
						if finishing and upcoming == false then
							-- The sound has run out: the pictures carry on by the clock
							player.silentBase, player.silentStarted = player.base + sound.TimeLength, if player.paused then nil else os.clock()
							player.audioClock = nil
							return
						elseif finishing and upcoming then
							local nextSound = upcoming
							upcoming = nil
							while not nextSound.IsLoaded and gen == player.gen do
								task.wait()
							end
							if gen ~= player.gen then
								return
							end
							player.base += sound.TimeLength
							player.current = nextSound
							finishing = false
							if not player.paused and not player.buffering then
								nextSound:Play()
							end
							local i = table.find(player.sounds, sound)
							if i then
								table.remove(player.sounds, i)
							end
							sound:Destroy()
							number += 1
							fetch(number + 1)
						end
						task.wait()
					end
				end

				local function runPictures(gen, info, size)
					local nextFrame = 0
					local misses = 0
					while gen == player.gen do
						if #player.queue >= info.fps * 2 then
							task.wait(0.03)
							continue
						end
						local response = helper(("frames?session=%s&from=%d&max=12&wait=2"):format(info.session, nextFrame))
						if gen ~= player.gen then
							break
						end
						if not response or tonumber(response.StatusCode) ~= 200 then
							misses += 1
							if misses >= 6 then
								setStatus("The YouTube helper stopped answering.")
								break
							end
							task.wait(0.5)
							continue
						end
						misses = 0
						local first = tonumber(header(response, "x-first")) or nextFrame
						local count = tonumber(header(response, "x-count")) or 0
						if count > 0 and #response.Body >= count * size then
							local all = buffer.fromstring(response.Body)
							for i = 0, count - 1 do
								local frame = buffer.create(size)
								buffer.copy(frame, 0, all, i * size, size)
								table.insert(player.queue, {first + i, frame})
							end
							nextFrame = first + count
							if not player.firstIndex then
								player.firstIndex = first
							end
						end
						if tostring(header(response, "x-ended")) == "1" then
							player.picturesDone = true
							break
						end
					end
				end

				local playingItem, playingIndex = nil, nil
				local function paintPlayButton()
					local playing = player.info ~= nil and not player.paused and not player.finished
					playIcon.Visible = not playing
					pauseIcon.Visible = playing
				end

				-- Plays `item` from `startAt` seconds
				local function startPlayback(item, startAt)
					stopPlayback()
					local gen = player.gen
					player.paused = false
					local vertical = item.short == true
					playerView.Visible = true
					upButton.Visible = vertical and playingIndex ~= nil and playingIndex > 1
					downButton.Visible = vertical and playingIndex ~= nil and playingIndex < #results
					videoTitle.Text = item.title or ""
					videoChannel.Text = item.channel or ""
					setStatus("Loading…")
					paintPlayButton()
					timeLabel.Text = ""
					liveDot.Visible = false
					progress.Visible = false
					fill.Size = UDim2.fromScale(0, 1)
					knob.Position = UDim2.fromScale(0, 0.5)
					local w, h = if vertical then 270 else 480, if vertical then 480 else 270
					local response = helper(("play?id=%s&w=%d&h=%d&fps=%d&start=%d"):format(item.id, w, h, FPS, math.floor(startAt or 0)))
					if gen ~= player.gen or not windowOpen then
						local data = response and decode(response)
						if data and data.session then
							task.spawn(helper, "stop?session=" .. data.session)
						end
						return
					end
					if not response then
						setStatus("Start the YouTube helper on your PC to watch.")
						return
					end
					local info = decode(response)
					if tonumber(response.StatusCode) ~= 200 or not info or not info.session then
						setStatus("This video can't be played." .. (if info and info.error then "\n" .. tostring(info.error) else ""))
						return
					end
					player.info = info
					paintPlayButton()
					videoTitle.Text = if info.title ~= "" then info.title else videoTitle.Text
					videoChannel.Text = (if info.channel ~= "" then info.channel else videoChannel.Text) .. (if info.live then "  ·  Live now" else "")
					timeLabel.Position = UDim2.fromOffset(if info.live then 64 else 48, 0)
					liveDot.Visible = info.live == true
					progress.Visible = not info.live
					-- A fresh picture to paint into
					local size = Vector2.new(info.width, info.height)
					if image then
						image:Destroy()
					end
					image = AssetService:CreateEditableImage({Size = size})
					imageSize = size
					screen.ImageContent = Content.fromObject(image)
					task.spawn(runPictures, gen, info, info.width * info.height * 4)
					task.spawn(runSound, gen, info)
					-- Nothing to show after a long wait: say so rather than load forever
					task.delay(45, function()
						if gen == player.gen and not player.lastShown then
							setStatus("This video is taking too long to load.")
						end
					end)
				end

				function playItem(item, index)
					playingItem, playingIndex = item, index
					if item.short == nil then
						item.short = resultsKind == "shorts"
					end
					task.spawn(startPlayback, item, 0)
				end

				local function setPaused(paused)
					local info = player.info
					if not info then
						return
					end
					if info.live then
						-- Pausing live stops it; playing again picks it up live
						if paused then
							stopPlayback()
							player.paused = true
							setStatus(nil)
						end
						paintPlayButton()
						return
					end
					player.paused = paused
					if player.current then
						if paused then
							player.current:Pause()
						elseif not player.buffering then
							player.current:Resume()
						end
					end
					if player.silentBase then
						if paused and player.silentStarted then
							player.silentBase += os.clock() - player.silentStarted
							player.silentStarted = nil
						elseif not paused then
							player.silentStarted = os.clock()
						end
					end
					paintPlayButton()
				end

				playButton.MouseButton1Click:Connect(function()
					if not playingItem then
						return
					end
					if player.finished or (not player.info and player.paused) then
						task.spawn(startPlayback, playingItem, 0)
					elseif player.info then
						setPaused(not player.paused)
					end
				end)
				progress.MouseButton1Down:Connect(function(mouseX)
					local info = player.info
					if not info or info.live or not info.duration or info.duration <= 0 then
						return
					end
					local fraction = math.clamp((mouseX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
					task.spawn(startPlayback, playingItem, fraction * info.duration)
				end)
				muteButton.MouseButton1Click:Connect(function()
					player.muted = not player.muted
					muteLabel.Text = if player.muted then "Unmute" else "Mute"
					for _, sound in ipairs(player.sounds) do
						sound.Volume = if player.muted then 0 else player.volume
					end
				end)
				backButton.MouseButton1Click:Connect(function()
					stopPlayback()
					playingItem, playingIndex = nil, nil
					playerView.Visible = false
				end)
				local function step(delta)
					local index = (playingIndex or 0) + delta
					local item = results[index]
					if item then
						playItem(item, index)
					end
				end
				upButton.MouseButton1Click:Connect(function()
					step(-1)
				end)
				downButton.MouseButton1Click:Connect(function()
					step(1)
				end)

				-- Every frame: the picture for the sound's position, and the controls
				table.insert(win.cleanup, RunService.RenderStepped:Connect(function()
					local info = player.info
					if not info or not image then
						return
					end
					-- The helper finished without a single picture
					if player.picturesDone and not player.firstIndex and not player.failed then
						player.failed = true
						setStatus("This video can't be played here.")
					end
					local now = player.time()
					if now then
						local target = math.floor(now * info.fps)
						local show = nil
						while player.queue[1] and player.queue[1][1] <= target do
							show = table.remove(player.queue, 1)
						end
						if show then
							image:WritePixelsBuffer(Vector2.zero, imageSize, show[2])
							player.lastShown = show[1]
							if stageStatus.Visible and not player.buffering then
								setStatus(nil)
							end
						end
						-- A video waits for its pictures if they fall behind
						if not info.live and not player.paused and player.current then
							local starved = #player.queue == 0 and not player.picturesDone
								and (player.lastShown == nil or target - player.lastShown > info.fps * 0.4)
							if starved and not player.buffering then
								player.buffering = true
								player.current:Pause()
								setStatus("Buffering…")
							elseif player.buffering and (#player.queue >= info.fps or player.picturesDone) then
								player.buffering = false
								player.current:Resume()
								setStatus(nil)
							end
						end
						-- The end: Shorts start again, videos wait for Play
						if player.picturesDone and #player.queue == 0 and not player.finished then
							player.finished = true
							if playingItem and playingItem.short then
								task.spawn(startPlayback, playingItem, 0)
							else
								for _, sound in ipairs(player.sounds) do
									sound:Stop()
								end
								paintPlayButton()
							end
						end
						local position = (info.start or 0) + now
						if info.live then
							timeLabel.Text = "LIVE"
						elseif info.duration then
							timeLabel.Text = clockText(position) .. " / " .. clockText(info.duration)
							local fraction = math.clamp(position / info.duration, 0, 1)
							fill.Size = UDim2.fromScale(fraction, 1)
							knob.Position = UDim2.fromScale(fraction, 0.5)
						else
							timeLabel.Text = clockText(position)
						end
					end
				end))

				table.insert(win.cleanup, function()
					windowOpen = false
					stopPlayback()
					if image then
						image:Destroy()
						image = nil
					end
				end)

				-- ---- Searching, tabs, links ----
				local function videoFromLink(text)
					local id = text:match("youtu%.be/([%w_%-]+)") or text:match("[?&]v=([%w_%-]+)") or text:match("/shorts/([%w_%-]+)")
						or text:match("/live/([%w_%-]+)") or text:match("/embed/([%w_%-]+)")
					if id and #id >= 11 then
						return {id = id:sub(1, 11), short = text:find("/shorts/", 1, true) ~= nil, title = "", channel = ""}
					end
					return nil
				end
				-- Searches (or opens a link); `autoplay` plays the top result
				local function handle(request)
					request = request or {}
					local text = tostring(request.query or ""):match("^%s*(.-)%s*$")
					if request.kind then
						for _, tab in ipairs(TABS) do
							if tab.kind == request.kind then
								currentTab = tab
							end
						end
						paintTabs()
					end
					local link = videoFromLink(text)
					if link then
						results = {link}
						resultsKind = if link.short then "shorts" else "video"
						renderResults()
						showNotice(nil)
						playItem(link, 1)
						return
					end
					if text ~= "" then
						field.Text = text
					end
					task.spawn(function()
						local found = search(if text ~= "" then text else currentTab.query, currentTab.kind)
						if found and found[1] and request.autoplay then
							playItem(found[1], 1)
						end
					end)
				end
				function win.handle(request)
					if playerView.Visible then
						stopPlayback()
						playerView.Visible = false
					end
					handle(request)
				end

				field.FocusLost:Connect(function(enterPressed)
					if enterPressed and field.Text:match("%S") then
						handle({query = field.Text})
					end
				end)
				searchButton.MouseButton1Click:Connect(function()
					if field.Text:match("%S") then
						handle({query = field.Text})
					end
				end)
				for _, tab in ipairs(TABS) do
					tabButtons[tab.key].button.MouseButton1Click:Connect(function()
						currentTab = tab
						paintTabs()
						handle({query = field.Text})
					end)
				end
				retryButton.MouseButton1Click:Connect(function()
					handle({query = field.Text})
				end)
				copyButton.MouseButton1Click:Connect(function()
					pcall(setclipboard, HELPER_FILE)
					noticeTitle.Text = "Link copied"
				end)

				-- Open: check the helper is there, then the request or Home
				task.spawn(function()
					local response = helper("ping")
					if not windowOpen then
						return
					end
					if not response or tonumber(response.StatusCode) ~= 200 then
						showHelperMissing()
						return
					end
					handle(args)
				end)
			end,
		})
	end

	-- ---------- Notifications ----------
	-- A banner in the top right, like macOS's: an app's icon, a title and a
	-- line of text. It slides in, stays 5 seconds, and clicking it runs
	-- `spec.onClick`. Banners stack downward.
	local banners = {}
	local function notify(spec)
		if not alive then
			return
		end
		local app = nil
		for _, candidate in ipairs(MAC_APPS) do
			if candidate.id == spec.app then
				app = candidate
			end
		end
		local holder = macButton(overlay, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 380, 0, 0), Size = UDim2.fromOffset(344, 66),
			BackgroundTransparency = 0.04, BackgroundColor3 = C.menu, ZIndex = 24,
		})
		macCorner(holder, 18)
		macStroke(holder, C.line, 0.88, 1)
		if app then
			macAppTile(holder, app, 38).Position = UDim2.fromOffset(12, 14)
		end
		macLabel(holder, spec.title or "", 13, Enum.FontWeight.SemiBold, C.ink, {
			Position = UDim2.fromOffset(60, 13), Size = UDim2.new(1, -72, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 25,
		})
		macLabel(holder, spec.text or "", 13, Enum.FontWeight.Regular, C.ink, {
			Position = UDim2.fromOffset(60, 33), Size = UDim2.new(1, -72, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
			TextTransparency = 0.15, ZIndex = 25,
		})
		local entry = {holder = holder}
		table.insert(banners, entry)
		local function place(animate)
			for i, banner in ipairs(banners) do
				local target = UDim2.new(1, -12, 0, D.menuHeight + 10 + (i - 1) * 74)
				if animate or banner ~= entry then
					tween(banner.holder, 0.35, {Position = target})
				end
			end
		end
		holder.Position = UDim2.new(1, 380, 0, D.menuHeight + 10 + (#banners - 1) * 74)
		place(true)
		local function dismiss()
			local i = table.find(banners, entry)
			if not i then
				return
			end
			table.remove(banners, i)
			local out = tween(holder, 0.3, {Position = UDim2.new(1, 380, 0, holder.Position.Y.Offset)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			out.Completed:Once(function()
				holder:Destroy()
			end)
			place(false)
		end
		holder.MouseButton1Click:Connect(function()
			dismiss()
			if spec.onClick then
				task.spawn(spec.onClick)
			end
		end)
		task.delay(spec.duration or 5, dismiss)
	end

	-- ---------- Timer ----------
	-- A countdown timer, with a ring that empties as it runs, and a
	-- stopwatch, like the Clock app's. When the timer's done it chimes and a
	-- banner says so (even with the window minimized).
	appBuilders.timer = function(args)
		openWindow({
			app = "timer", title = "Timer", width = 400, height = 520, minWidth = 360, minHeight = 480, dark = true, fixedSize = true,
			background = Color3.fromRGB(28, 28, 30),
			build = function(win)
				local content = win.content
				local ORANGE = Color3.fromRGB(255, 159, 10)
				local GREEN = Color3.fromRGB(48, 209, 88)
				local RED = Color3.fromRGB(255, 69, 58)
				local GREY = Color3.fromRGB(152, 152, 158)
				local TRACK = Color3.fromRGB(58, 58, 62)
				local mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Light)

				-- Timer | Stopwatch
				local switcher = macNew("Frame", {
					BackgroundColor3 = Color3.fromRGB(46, 46, 50), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(220, 30), Parent = content,
				})
				macCorner(switcher, 9)
				local pages, switchButtons = {}, {}
				local function showPage(name)
					for key, page in pairs(pages) do
						page.Visible = key == name
						switchButtons[key].BackgroundTransparency = if key == name then 0 else 1
					end
					win.setTitle(if name == "timer" then "Timer" else "Stopwatch")
				end
				for i, name in ipairs({"timer", "stopwatch"}) do
					local button = macButton(switcher, {
						Position = UDim2.new((i - 1) / 2, 2, 0, 2), Size = UDim2.new(0.5, -4, 1, -4),
						BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(100, 100, 106),
					})
					macCorner(button, 7)
					macLabel(button, if name == "timer" then "Timer" else "Stopwatch", 13, Enum.FontWeight.Medium, white, {
						Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
					})
					switchButtons[name] = button
					pages[name] = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), Parent = content})
					button.MouseButton1Click:Connect(function()
						showPage(name)
					end)
				end

				-- A round button with its word in the middle (tinted, like the Clock app's)
				local function roundButton(parent, text, color, x)
					local button = macButton(parent, {
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 1, -64), Size = UDim2.fromOffset(78, 78),
						BackgroundTransparency = 0.72, BackgroundColor3 = color,
					})
					macCorner(button, UDim.new(1, 0))
					local label = macLabel(button, text, 15, Enum.FontWeight.Medium, color, {
						Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
					})
					local api = {button = button}
					function api.set(newText, newColor)
						label.Text = newText
						label.TextColor3 = newColor
						button.BackgroundColor3 = newColor
					end
					return api
				end
				local function clockText(seconds, tenths)
					seconds = math.max(0, seconds)
					local whole = math.floor(seconds)
					local h, m, s = whole // 3600, whole // 60 % 60, whole % 60
					local text = if h > 0 then string.format("%d:%02d:%02d", h, m, s) else string.format("%02d:%02d", m, s)
					if tenths then
						text ..= string.format(".%02d", math.floor((seconds - whole) * 100))
					end
					return text
				end

				-- ---- Timer ----
				local timerPage = pages.timer
				-- Setting it: hours, minutes and seconds you can type into, and presets
				local setter = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 220), Parent = timerPage})
				local fields = {}
				for i, part in ipairs({{"h", "hours", 0}, {"m", "min", 5}, {"s", "sec", 0}}) do
					local x = (i - 2) * 104
					local field = macNew("TextBox", {
						BackgroundColor3 = Color3.fromRGB(44, 44, 48), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, x, 0, 20), Size = UDim2.fromOffset(88, 70), ClearTextOnFocus = true,
						Text = string.format("%02d", part[3]), TextColor3 = white, FontFace = mono, TextSize = 40,
						TextXAlignment = Enum.TextXAlignment.Center, Parent = setter,
					})
					macCorner(field, 12)
					macLabel(setter, part[2], 12, Enum.FontWeight.Medium, GREY, {
						AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, 96), Size = UDim2.fromOffset(88, 16),
						TextXAlignment = Enum.TextXAlignment.Center,
					})
					field.FocusLost:Connect(function()
						local n = math.clamp(tonumber(field.Text:match("%d+") or "0") or 0, 0, if part[1] == "h" then 23 else 59)
						field.Text = string.format("%02d", n)
					end)
					fields[part[1]] = field
				end
				local presets = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 34), Parent = setter})
				macNew("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = presets,
				})
				for i, minutes in ipairs({1, 3, 5, 10, 15, 30}) do
					local chip = macButton(presets, {
						Size = UDim2.fromOffset(46, 30), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(44, 44, 48), LayoutOrder = i,
					})
					macCorner(chip, UDim.new(1, 0))
					macLabel(chip, minutes .. "m", 13, Enum.FontWeight.Medium, white, {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center})
					chip.MouseButton1Click:Connect(function()
						fields.h.Text, fields.m.Text, fields.s.Text = "00", string.format("%02d", minutes), "00"
					end)
				end

				-- Running: a ring of short bars that empties clockwise, and the time left
				local runner = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 280), Visible = false, Parent = timerPage})
				local RING_RADIUS, RING_BARS = 116, 96
				local ring = macNew("Frame", {
					BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 132),
					Size = UDim2.fromOffset(2 * RING_RADIUS, 2 * RING_RADIUS), Parent = runner,
				})
				local bars = {}
				local barLength = 2 * math.pi * RING_RADIUS / RING_BARS * 1.25
				for i = 1, RING_BARS do
					local angle = (i - 0.5) / RING_BARS * math.pi * 2
					local bar = macNew("Frame", {
						BackgroundColor3 = ORANGE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, math.sin(angle) * RING_RADIUS, 0.5, -math.cos(angle) * RING_RADIUS),
						Size = UDim2.fromOffset(barLength, 7), Rotation = math.deg(angle), Parent = ring,
					})
					bars[i] = bar
				end
				local remainingLabel = macLabel(ring, "", 46, Enum.FontWeight.Light, white, {
					FontFace = mono, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(220, 56),
					TextXAlignment = Enum.TextXAlignment.Center,
				})
				local endsLabel = macLabel(ring, "", 13, Enum.FontWeight.Medium, GREY, {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.64), Size = UDim2.fromOffset(200, 18),
					TextXAlignment = Enum.TextXAlignment.Center,
				})

				local cancel = roundButton(timerPage, "Cancel", GREY, -110)
				local startPause = roundButton(timerPage, "Start", GREEN, 110)
				-- total: the length set; endsAt (os.clock) while running; left while paused
				local timer = {state = "idle", total = 0, left = 0, endsAt = 0}
				local function paintTimer()
					local idle = timer.state == "idle"
					setter.Visible = idle
					runner.Visible = not idle
					cancel.button.BackgroundTransparency = if idle then 0.88 else 0.72
					if timer.state == "running" then
						startPause.set("Pause", ORANGE)
					elseif timer.state == "paused" then
						startPause.set("Resume", GREEN)
					else
						startPause.set("Start", GREEN)
					end
				end
				local function timeLeft()
					return if timer.state == "running" then timer.endsAt - os.clock() elseif timer.state == "paused" then timer.left else timer.total
				end
				local function startTimer(seconds)
					if seconds <= 0 then
						return
					end
					timer.total, timer.state, timer.endsAt = seconds, "running", os.clock() + seconds
					endsLabel.Text = "Ends at " .. DateTime.fromUnixTimestamp(os.time() + math.floor(seconds)):FormatLocalTime("h:mm A", "en-us")
					paintTimer()
				end
				local function finished()
					timer.state = "idle"
					paintTimer()
					task.spawn(function()
						for _ = 1, 3 do
							macSounds.play(macSounds.login, 0.8)
							task.wait(1.1)
						end
					end)
					notify({app = "timer", title = "Timer", text = "Your " .. clockText(timer.total) .. " timer is done.", onClick = function()
						if not win.closed then
							if win.minimized then
								win.restore()
							else
								focusWindow(win)
							end
						end
					end})
				end
				startPause.button.MouseButton1Click:Connect(function()
					if timer.state == "idle" then
						local seconds = (tonumber(fields.h.Text) or 0) * 3600 + (tonumber(fields.m.Text) or 0) * 60 + (tonumber(fields.s.Text) or 0)
						startTimer(seconds)
					elseif timer.state == "running" then
						timer.left, timer.state = timer.endsAt - os.clock(), "paused"
						endsLabel.Text = "Paused"
						paintTimer()
					else
						startTimer(timer.left)
						timer.total = math.max(timer.total, timer.left)
					end
				end)
				cancel.button.MouseButton1Click:Connect(function()
					if timer.state ~= "idle" then
						timer.state = "idle"
						paintTimer()
					end
				end)

				-- ---- Stopwatch ----
				local watchPage = pages.stopwatch
				local watchLabel = macLabel(watchPage, "00:00.00", 54, Enum.FontWeight.Light, white, {
					FontFace = mono, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(340, 70),
					TextXAlignment = Enum.TextXAlignment.Center,
				})
				local laps = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(28, 128), Size = UDim2.new(1, -56, 1, -244),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
					ScrollBarImageColor3 = GREY, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = watchPage,
				})
				macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = laps})
				local lapButton = roundButton(watchPage, "Lap", GREY, -110)
				local runButton = roundButton(watchPage, "Start", GREEN, 110)
				local watch = {running = false, base = 0, started = 0, laps = {}, lastLap = 0}
				local function elapsed()
					return watch.base + (if watch.running then os.clock() - watch.started else 0)
				end
				local function paintWatch()
					runButton.set(if watch.running then "Stop" else "Start", if watch.running then RED else GREEN)
					lapButton.set(if watch.running or elapsed() == 0 then "Lap" else "Reset", GREY)
				end
				runButton.button.MouseButton1Click:Connect(function()
					if watch.running then
						watch.base, watch.running = elapsed(), false
					else
						watch.started, watch.running = os.clock(), true
					end
					paintWatch()
				end)
				lapButton.button.MouseButton1Click:Connect(function()
					if watch.running then
						local now = elapsed()
						local number = #watch.laps + 1
						table.insert(watch.laps, now - watch.lastLap)
						local row = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 34), LayoutOrder = -number, Parent = laps})
						macLabel(row, "Lap " .. number, 14, Enum.FontWeight.Regular, white, {Size = UDim2.fromScale(0.5, 1)})
						macLabel(row, clockText(now - watch.lastLap, true), 14, Enum.FontWeight.Regular, white, {
							FontFace = mono, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.5, 1),
							TextXAlignment = Enum.TextXAlignment.Right,
						})
						macNew("Frame", {
							BackgroundColor3 = white, BackgroundTransparency = 0.88, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
							Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), Parent = row,
						})
						watch.lastLap = now
					else
						watch.base, watch.lastLap = 0, 0
						table.clear(watch.laps)
						for _, child in ipairs(laps:GetChildren()) do
							if child:IsA("Frame") then
								child:Destroy()
							end
						end
					end
					paintWatch()
				end)

				-- Every frame: the ring, the time left, the stopwatch
				table.insert(win.cleanup, RunService.Heartbeat:Connect(function()
					if timer.state ~= "idle" then
						local left = timeLeft()
						if timer.state == "running" and left <= 0 then
							finished()
							return
						end
						remainingLabel.Text = clockText(math.ceil(left))
						local fraction = math.clamp(left / timer.total, 0, 1)
						for i, bar in ipairs(bars) do
							bar.BackgroundColor3 = if (i - 0.5) / RING_BARS <= fraction then ORANGE else TRACK
						end
					end
					if watch.running then
						watchLabel.Text = clockText(elapsed(), true)
					end
				end))

				function win.handle(request)
					if request and tonumber(request.seconds) then
						showPage("timer")
						startTimer(tonumber(request.seconds))
					end
				end
				paintTimer()
				paintWatch()
				showPage("timer")
				win.handle(args)
			end,
		})
	end

	-- ---------- Chat ----------
	-- The game's chat in a window: the server, Roblox's Global chat
	-- (everyone playing this game, in any server), team chat and private
	-- whispers. It all goes through Roblox's own chat (TextChatService, or the
	-- old chat system in games that still use it), so Roblox's filter and
	-- rules apply as usual, and Roblox's chat window is left as the game set
	-- it. "/w name message" (a username or a display name) whispers. Messages
	-- are collected from the moment the desktop starts, so opening Chat shows
	-- what's been said.
	local chatStore = nil
	local openChat -- (the Chat window's "show this channel")
	local function getChatStore()
		if chatStore then
			return chatStore
		end
		local TextChatService = game:GetService("TextChatService")
		local legacy = TextChatService.ChatVersion == Enum.ChatVersion.LegacyChatService
		local store = {channels = {}, order = {}, listeners = {}, legacy = legacy, muted = {}}
		-- Whether the game has switched off typing in its chat (it can still be read)
		function store.typingOff()
			local config = if legacy then nil else TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
			return config ~= nil and not config.Enabled
		end
		chatStore = store
		local function changed(channel, message)
			for _, fn in ipairs(table.clone(store.listeners)) do
				task.spawn(fn, channel, message)
			end
		end
		local function stripTags(text)
			return (tostring(text or ""):gsub("<[^>]->", ""))
		end
		-- One channel's entry: {key, name, kind ("server"/"team"/"whisper"/
		-- "other"), textChannel?, partner?, messages, unread, lastActivity}
		local function channelFor(key, make)
			local channel = store.channels[key]
			if not channel and make then
				channel = make()
				channel.key, channel.messages, channel.unread, channel.lastActivity = key, {}, 0, 0
				store.channels[key] = channel
				table.insert(store.order, channel)
				changed(channel, nil)
			end
			return channel
		end
		local function partnerOf(textChannel)
			for _, source in ipairs(textChannel:GetChildren()) do
				if source:IsA("TextSource") and source.UserId ~= player.UserId then
					return Players:GetPlayerByUserId(source.UserId), source.UserId
				end
			end
			return nil, nil
		end
		local function describe(textChannel)
			local name = textChannel.Name
			if name == "RBXGeneral" then
				return {name = "Server", kind = "server", textChannel = textChannel}
			elseif name:match("^RBXTeam") then
				return {name = "Team", kind = "team", textChannel = textChannel}
			elseif name:match("^RBXWhisper") then
				local partner, userId = partnerOf(textChannel)
				return {name = if partner then partner.DisplayName else "Whisper", kind = "whisper", textChannel = textChannel, partner = partner, partnerId = userId}
			end
			return {name = (name:gsub("^RBX", "")), kind = "other", textChannel = textChannel}
		end
		store.server = nil
		-- A message into a channel (`entry`: {id, text, from (Player or nil),
		-- fromName, mine, system, time, pending})
		function store.add(channel, entry)
			if entry.id then
				for _, existing in ipairs(channel.messages) do
					if existing.id == entry.id then
						existing.text, existing.pending = entry.text, entry.pending
						changed(channel, existing)
						return existing
					end
				end
			end
			table.insert(channel.messages, entry)
			if #channel.messages > 200 then
				table.remove(channel.messages, 1)
			end
			channel.lastActivity = os.clock()
			if not entry.mine and not entry.system and store.viewing ~= channel then
				channel.unread += 1
			end
			changed(channel, entry)
			return entry
		end
		-- System notes go to whichever channel is open (or the server)
		function store.note(text)
			local channel = store.viewing or store.server
			if channel then
				store.add(channel, {text = text, system = true, time = DateTime.now()})
			end
		end

		if legacy then
			-- The old chat: events in ReplicatedStorage
			local events = game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents")
			store.server = channelFor("All", function()
				return {name = "Server", kind = "server"}
			end)
			if events then
				local filtered = events:FindFirstChild("OnMessageDoneFiltering")
				if filtered then
					connect(filtered.OnClientEvent, function(data)
						if type(data) ~= "table" then
							return
						end
						local channelName = tostring(data.OriginalChannel or "All")
						local channel = store.server
						if channelName ~= "All" then
							channel = channelFor(channelName, function()
								local whisper = channelName:match("^To ") ~= nil
								return {name = if whisper then channelName:gsub("^To ", "") else channelName, kind = if whisper then "whisper" else "other"}
							end)
						end
						local from = Players:FindFirstChild(tostring(data.FromSpeaker or ""))
						store.add(channel, {
							text = tostring(data.Message or ""), from = from, fromName = if from then from.DisplayName else tostring(data.FromSpeaker or ""),
							mine = from == player, time = DateTime.now(),
						})
					end)
				end
				local system = events:FindFirstChild("OnNewSystemMessage")
				if system then
					connect(system.OnClientEvent, function(data)
						if type(data) == "table" and data.Message then
							store.note(tostring(data.Message))
						end
					end)
				end
			end
			function store.send(channel, text)
				local request = events and events:FindFirstChild("SayMessageRequest")
				if not request then
					return false, "This game's chat can't be reached."
				end
				request:FireServer(text, if channel.kind == "other" then channel.key else "All")
				return true
			end
		else
			local folder = TextChatService:WaitForChild("TextChannels", 10)
			local function register(textChannel)
				if not textChannel:IsA("TextChannel") or textChannel.Name == "RBXSystem" then
					return
				end
				local channel = channelFor(textChannel, function()
					return describe(textChannel)
				end)
				if textChannel.Name == "RBXGeneral" then
					store.server = channel
				end
				-- A whisper's other person may arrive a moment later
				if channel.kind == "whisper" then
					connect(textChannel.ChildAdded, function()
						local fresh = describe(textChannel)
						channel.name, channel.partner, channel.partnerId = fresh.name, fresh.partner, fresh.partnerId
						changed(channel, nil)
					end)
				end
			end
			store.register = register
			if folder then
				for _, textChannel in ipairs(folder:GetChildren()) do
					register(textChannel)
				end
				connect(folder.ChildAdded, register)
				connect(folder.ChildRemoved, function(textChannel)
					local channel = store.channels[textChannel]
					if channel then
						store.channels[textChannel] = nil
						local i = table.find(store.order, channel)
						if i then
							table.remove(store.order, i)
						end
						changed(channel, nil)
					end
				end)
			end
			connect(TextChatService.MessageReceived, function(message)
				local textChannel = message.TextChannel
				if not textChannel then
					return
				end
				local source = message.TextSource
				if textChannel.Name == "RBXSystem" or not source then
					local text = stripTags(message.Text)
					if text ~= "" then
						store.note(text)
					end
					return
				end
				register(textChannel)
				local channel = store.channels[textChannel]
				if not channel or store.muted[source.UserId] then
					return
				end
				local from = Players:GetPlayerByUserId(source.UserId)
				local entry = store.add(channel, {
					id = message.MessageId, text = message.Text, from = from,
					fromName = if from then from.DisplayName else stripTags(message.PrefixText):gsub(":%s*$", ""),
					mine = source.UserId == player.UserId, time = message.Timestamp or DateTime.now(),
				})
				-- A whisper while Chat isn't in front gets a banner
				if channel.kind == "whisper" and not entry.mine and store.viewing ~= channel then
					notify({app = "chat", title = (if from then from.DisplayName else "Whisper") .. " (whisper)", text = stripTags(message.Text), onClick = function()
						openApp("chat")
						if openChat then
							openChat(channel)
						end
					end})
				end
			end)
			-- Roblox's Global chat, when Roblox has it on for this game and
			-- account. It isn't a TextChannel: it has its own messages and
			-- sending, which is what Roblox's own Global tab uses.
			local function addGlobal()
				if not store.global then
					store.global = channelFor("RBXGlobal", function()
						return {name = "Global", kind = "global"}
					end)
				end
			end
			local hasGlobal = false
			pcall(function()
				hasGlobal = TextChatService:HasAllocatedUniverseChatContext("global")
			end)
			if hasGlobal then
				addGlobal()
			end
			pcall(function()
				connect(TextChatService.UniverseChatChannelAllocated, function(context)
					if context == "global" then
						addGlobal()
					end
				end)
				connect(TextChatService.UniverseChatMessageReceived, function(message)
					addGlobal()
					local userId = message.TextSource and message.TextSource.UserId
					if userId and store.muted[userId] then
						return
					end
					-- (usually someone in another server, so the name comes from the message)
					local from = userId and Players:GetPlayerByUserId(userId)
					store.add(store.global, {
						id = message.MessageId, text = message.Text, from = from,
						fromName = if from then from.DisplayName else (stripTags(message.PrefixText):gsub(":%s*$", "")),
						mine = userId == player.UserId, time = message.Timestamp or DateTime.now(),
					})
				end)
			end)

			function store.send(channel, text)
				local ok, result
				if channel.kind == "global" then
					ok, result = pcall(TextChatService.SendUniverseChatMessageAsync, TextChatService, text, "")
				else
					local textChannel = channel.textChannel
					if not textChannel then
						return false, "That channel has gone."
					end
					ok, result = pcall(textChannel.SendAsync, textChannel, text)
				end
				if not ok then
					return false, tostring(result)
				end
				-- Shown straight away; Roblox's copy replaces it when it arrives. If
				-- it never does (some games turn chat off), it's marked undelivered.
				if typeof(result) == "Instance" and result:IsA("TextChatMessage") and result.MessageId ~= "" then
					local entry = store.add(channel, {id = result.MessageId, text = result.Text, from = player, fromName = player.DisplayName, mine = true, pending = true, time = DateTime.now()})
					task.delay(8, function()
						if entry.pending then
							entry.pending, entry.failed = false, true
							changed(channel, entry)
							if not store.warnedUndelivered then
								store.warnedUndelivered = true
								store.note("Your message wasn't delivered. " .. (if store.typingOff() then "This game has turned off typing in chat." else "The game may be blocking chat right now."))
							end
						end
					end)
				end
				return true
			end
		end

		-- Someone in this server by username or display name ("@" optional):
		-- an exact match first, then the start of a name. nil and a reason if not.
		function store.findPlayer(text)
			local wanted = tostring(text or ""):gsub("^@", ""):lower()
			if wanted == "" then
				return nil, "Who to? Try /w name message."
			end
			for _, candidate in ipairs(Players:GetPlayers()) do
				if candidate.Name:lower() == wanted then
					return candidate
				end
			end
			for _, candidate in ipairs(Players:GetPlayers()) do
				if candidate.DisplayName:lower() == wanted then
					return candidate
				end
			end
			local found = nil
			for _, candidate in ipairs(Players:GetPlayers()) do
				if candidate.Name:lower():sub(1, #wanted) == wanted or candidate.DisplayName:lower():sub(1, #wanted) == wanted then
					if found and found ~= candidate then
						return nil, "More than one person matches “" .. text .. "”. Type more of the name."
					end
					found = candidate
				end
			end
			return found, if found then nil else "No one called “" .. text .. "” is in this server."
		end
		function store.whisperWith(target)
			for _, channel in ipairs(store.order) do
				if channel.kind == "whisper" and (channel.partner == target or channel.partnerId == target.UserId or channel.key == "To " .. target.Name) then
					return channel
				end
			end
			return nil
		end
		-- Opens (or finds) a whisper with `target`; yields. Returns the channel or nil and why.
		function store.startWhisper(target)
			if target == player then
				return nil, "You can't whisper to yourself."
			end
			local existing = store.whisperWith(target)
			if existing then
				return existing
			end
			if legacy then
				-- The old chat whispers by sending "/w name" through the server
				return channelFor("To " .. target.Name, function()
					return {name = target.DisplayName, kind = "whisper", partner = target, partnerId = target.UserId}
				end)
			end
			-- Roblox's own chat opens a whisper by asking the server through this
			-- RemoteFunction, which hands back the private channel. (Sending
			-- "/w name" as a message would just post it for everyone to see.)
			local remote = nil
			pcall(function()
				remote = game:GetService("RobloxReplicatedStorage").ExperienceChat.WhisperChat
			end)
			if not remote or not remote:IsA("RemoteFunction") then
				return nil, "This game's chat doesn't have whispers."
			end
			local ok, textChannel = pcall(remote.InvokeServer, remote, tostring(target.UserId))
			if not ok or typeof(textChannel) ~= "Instance" or not textChannel:IsA("TextChannel") then
				return nil, "Roblox wouldn't open a whisper with " .. target.DisplayName .. ". Their chat settings may not allow it."
			end
			if store.register then
				store.register(textChannel)
			end
			return store.channels[textChannel] or store.whisperWith(target)
		end
		return store
	end
	-- Start listening as soon as the desktop is up
	task.spawn(function()
		pcall(getChatStore)
	end)

	appBuilders.chat = function(args)
		local store = getChatStore()
		openWindow({
			app = "chat", title = "Server", width = 760, height = 520, minWidth = 560, minHeight = 380,
			sidebarWidth = 220, titleLeft = 220 + 32, background = C.window,
			build = function(win)
				local content, sidebar = win.content, win.sidebar
				local viewing = nil
				local rows = {}

				-- ---- The list of channels ----
				local list = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 48), Size = UDim2.new(1, -12, 1, -54),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
					ScrollBarImageColor3 = C.line, ScrollBarImageTransparency = 0.6, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = sidebar,
				})
				macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = list})
				-- New whisper: a list of the people here
				local newButton = macButton(sidebar, {
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 12), Size = UDim2.fromOffset(28, 28),
					BackgroundTransparency = 1, BackgroundColor3 = C.line,
				})
				macCorner(newButton, 8)
				macImage(newButton, I.plus, 18, C.ink, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
				newButton.MouseEnter:Connect(function()
					newButton.BackgroundTransparency = 0.92
				end)
				newButton.MouseLeave:Connect(function()
					newButton.BackgroundTransparency = 1
				end)

				local function preview(channel)
					local last = channel.messages[#channel.messages]
					if not last then
						return if channel.kind == "server" then "Everyone in this server" elseif channel.kind == "global" then "Everyone playing this game" elseif channel.kind == "team" then "Your team" else "No messages yet"
					end
					local text = tostring(last.text):gsub("<[^>]->", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
					return (if last.mine then "You: " elseif last.system or (channel.kind ~= "server" and channel.kind ~= "global") then "" else (last.fromName or "") .. ": ") .. text
				end
				local selectChannel
				local function paintList()
					for _, row in pairs(rows) do
						row:Destroy()
					end
					table.clear(rows)
					local sorted = table.clone(store.order)
					local rank = {server = 0, global = 1, team = 2, other = 3, whisper = 4}
					table.sort(sorted, function(a, b)
						if rank[a.kind] ~= rank[b.kind] then
							return rank[a.kind] < rank[b.kind]
						end
						return a.lastActivity > b.lastActivity
					end)
					for i, channel in ipairs(sorted) do
						local on = channel == viewing
						local row = macButton(list, {
							Size = UDim2.new(1, -4, 0, 54), BackgroundTransparency = if on then 0 else 1, BackgroundColor3 = C.accent, LayoutOrder = i,
						})
						macCorner(row, 10)
						local ink = if on then white else C.ink
						if channel.kind == "whisper" and channel.partnerId then
							local avatar = macNew("ImageLabel", {
								BackgroundColor3 = Color3.fromRGB(190, 196, 206), Image = "rbxthumb://type=AvatarHeadShot&id=" .. channel.partnerId .. "&w=48&h=48",
								Position = UDim2.fromOffset(8, 9), Size = UDim2.fromOffset(36, 36), Parent = row,
							})
							macCorner(avatar, UDim.new(1, 0))
						else
							local badge = macNew("Frame", {
								BackgroundColor3 = if channel.kind == "team" then Color3.fromRGB(255, 159, 10) elseif channel.kind == "global" then Color3.fromRGB(10, 132, 255) else Color3.fromRGB(28, 188, 62),
								BorderSizePixel = 0, Position = UDim2.fromOffset(8, 9), Size = UDim2.fromOffset(36, 36), Parent = row,
							})
							macCorner(badge, UDim.new(1, 0))
							macLabel(badge, if channel.kind == "team" then "T" elseif channel.kind == "global" then "G" else "#", 17, Enum.FontWeight.Bold, white, {
								Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
							})
						end
						macLabel(row, channel.name, 14, Enum.FontWeight.SemiBold, ink, {
							Position = UDim2.fromOffset(52, 8), Size = UDim2.new(1, -78, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
						})
						macLabel(row, preview(channel), 12, Enum.FontWeight.Regular, ink, {
							Position = UDim2.fromOffset(52, 27), Size = UDim2.new(1, -60, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd,
							TextTransparency = if on then 0.15 else 0.45,
						})
						if channel.unread > 0 and not on then
							local dot = macNew("Frame", {
								BackgroundColor3 = C.accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 12),
								Size = UDim2.fromOffset(9, 9), Parent = row,
							})
							macCorner(dot, UDim.new(1, 0))
						end
						row.MouseButton1Click:Connect(function()
							selectChannel(channel)
						end)
						rows[channel] = row
					end
				end

				-- ---- The messages ----
				local scroller = macNew("ScrollingFrame", {
					BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -62),
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
					ScrollBarImageColor3 = C.line, ScrollBarImageTransparency = 0.6, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = content,
				})
				local messageList = macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = scroller})
				macNew("UIPadding", {
					PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), Parent = scroller,
				})
				local emptyLabel = macLabel(content, "", 13, Enum.FontWeight.Regular, C.inkSoft, {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -30), Size = UDim2.new(1, -60, 0, 40),
					TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
				})
				local order = 0
				local shown = {} -- message entry -> its label (so a pending one can be updated)
				local function addMessage(channel, entry)
					order += 1
					local previous = channel.messages[table.find(channel.messages, entry) and table.find(channel.messages, entry) - 1 or 0]
					if entry.system then
						local label = macLabel(scroller, entry.text, 12, Enum.FontWeight.Medium, C.inkSoft, {
							Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true,
							TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = order,
						})
						shown[entry] = label
						return
					end
					-- A name (and picture) above the first of a run of someone's messages
					local first = not previous or previous.system or previous.mine ~= entry.mine or previous.fromName ~= entry.fromName
					local row = macNew("Frame", {
						BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = scroller,
					})
					macNew("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = if entry.mine then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
						Padding = UDim.new(0, 2), Parent = row,
					})
					if first and not entry.mine and channel.kind ~= "whisper" then
						macLabel(row, entry.fromName or "", 11, Enum.FontWeight.Medium, C.inkSoft, {
							Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1,
						}).Position = UDim2.fromOffset(12, 0)
					end
					local bubble = macNew("Frame", {
						BackgroundColor3 = if entry.failed then Color3.fromRGB(255, 69, 58) elseif entry.mine then C.accent else C.surface,
						BackgroundTransparency = if entry.pending then 0.35 else 0,
						BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2, Parent = row,
					})
					macCorner(bubble, 16)
					if not entry.mine then
						macStroke(bubble, C.line, 0.9, 1)
					end
					macNew("UIPadding", {
						PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7), Parent = bubble,
					})
					local label = macLabel(bubble, entry.text, 14, Enum.FontWeight.Regular, if entry.mine then white else C.ink, {
						Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, TextWrapped = true, RichText = true,
					})
					macNew("UISizeConstraint", {MaxSize = Vector2.new(360, math.huge), Parent = label})
					-- Under a message Roblox never took: "Not delivered"
					local note = macLabel(row, "Not delivered", 11, Enum.FontWeight.Medium, Color3.fromRGB(255, 69, 58), {
						Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3,
						TextXAlignment = Enum.TextXAlignment.Right, Visible = entry.failed == true,
					})
					shown[entry] = {label = label, bubble = bubble, note = note}
				end
				local function nearBottom()
					return scroller.CanvasPosition.Y >= scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y - 60
				end
				local function toBottom()
					task.defer(function()
						scroller.CanvasPosition = Vector2.new(0, math.max(0, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y))
					end)
				end

				-- ---- Typing ----
				local inputBar = macNew("Frame", {
					BackgroundColor3 = C.surface, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
					Size = UDim2.new(1, -28, 0, 36), Parent = content,
				})
				macCorner(inputBar, UDim.new(1, 0))
				macStroke(inputBar, C.line, 0.85, 1)
				local input = macNew("TextBox", {
					BackgroundTransparency = 1, ClearTextOnFocus = false, Text = "", PlaceholderText = "Message", PlaceholderColor3 = C.inkSoft,
					TextColor3 = C.ink, FontFace = macFont(Enum.FontWeight.Regular), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -60, 1, 0), ClipsDescendants = true, Parent = inputBar,
				})
				local sendButton = macButton(inputBar, {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(28, 28),
					BackgroundTransparency = 0, BackgroundColor3 = C.accent,
				})
				macCorner(sendButton, UDim.new(1, 0))
				macImage(sendButton, I.back, 16, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = 90})

				function selectChannel(channel)
					viewing = channel
					store.viewing = channel
					channel.unread = 0
					win.setTitle(channel.name)
					win.reopenArgs = nil
					input.PlaceholderText = if store.typingOff() then "This game has turned off typing in chat"
						elseif channel.kind == "whisper" then "Whisper to " .. channel.name
						elseif channel.kind == "global" then "Message everyone playing this game"
						elseif channel.kind == "team" then "Message your team"
						else "Message everyone here  ·  /w name to whisper"
					for _, child in ipairs(scroller:GetChildren()) do
						if child:IsA("GuiObject") then
							child:Destroy()
						end
					end
					table.clear(shown)
					order = 0
					for _, entry in ipairs(channel.messages) do
						addMessage(channel, entry)
					end
					emptyLabel.Text = if #channel.messages == 0 then (if channel.kind == "whisper" then "Only you and " .. channel.name .. " see these messages." elseif channel.kind == "global" then "Global is Roblox's chat with everyone playing this game, in every server. Messages show up here as they're sent." else "Messages in this server show up here as they're sent.") else ""
					paintList()
					toBottom()
				end
				openChat = selectChannel

				local function send()
					local text = input.Text:match("^%s*(.-)%s*$")
					if text == "" or not viewing then
						return
					end
					input.Text = ""
					task.spawn(function()
						local command, rest = text:match("^/(%S+)%s*(.*)$")
						command = command and command:lower()
						if command == "w" or command == "whisper" then
							local name, message = rest:match("^(%S+)%s*(.*)$")
							local target, problem = store.findPlayer(name or "")
							if not target then
								store.note(problem)
								return
							end
							store.note("Starting a whisper with " .. target.DisplayName .. "…")
							local channel, why = store.startWhisper(target)
							if not channel then
								store.note(why)
								return
							end
							if openChat == selectChannel and not win.closed then
								selectChannel(channel)
							end
							if message ~= "" then
								local ok, err = store.send(channel, if store.legacy then "/w " .. target.Name .. " " .. message else message)
								if not ok then
									store.note("Couldn't send: " .. tostring(err))
								end
							end
							return
						end
						-- Roblox's other built-in commands, done here (sent as messages they'd
						-- just be posted). The old chat system handles them itself.
						if command and not store.legacy then
							if command == "e" or command == "emote" then
								local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
								local ok, played = pcall(function()
									return humanoid and humanoid:PlayEmote(rest)
								end)
								if not (ok and played) then
									store.note("You can't use the emote “" .. rest .. "”.")
								end
								return
							elseif command == "t" or command == "team" then
								for _, channel in ipairs(store.order) do
									if channel.kind == "team" then
										selectChannel(channel)
										return
									end
								end
								store.note("This game has no team chat.")
								return
							elseif command == "mute" or command == "m" or command == "unmute" or command == "um" then
								local target, problem = store.findPlayer(rest)
								if not target then
									store.note(problem)
									return
								end
								local mute = command == "mute" or command == "m"
								store.muted[target.UserId] = mute or nil
								store.note((if mute then "Muted " else "Unmuted ") .. target.DisplayName .. ". " .. (if mute then "Their messages won't show here." else ""))
								return
							elseif command == "clear" or command == "cls" then
								table.clear(viewing.messages)
								selectChannel(viewing)
								return
							elseif command == "help" or command == "?" then
								store.note("/w name message: whisper (a username or display name)  ·  /t: team chat  ·  /e name: emote  ·  /mute name, /unmute name  ·  /clear")
								return
							end
						end
						-- Anything else (a game's own commands too, like admin ones) goes to this channel as is
						local ok, err = store.send(viewing, if store.legacy and viewing.kind == "whisper" and viewing.partner then "/w " .. viewing.partner.Name .. " " .. text else text)
						if not ok then
							store.note("Couldn't send: " .. tostring(err))
						end
					end)
				end
				input.FocusLost:Connect(function(enterPressed)
					if enterPressed then
						send()
						task.defer(function()
							if not win.closed then
								input:CaptureFocus()
							end
						end)
					end
				end)
				sendButton.MouseButton1Click:Connect(send)

				-- The people here, to whisper to
				local picker = nil
				newButton.MouseButton1Click:Connect(function()
					if picker then
						picker:Destroy()
						picker = nil
						return
					end
					picker = macNew("Frame", {
						BackgroundColor3 = C.menu, BorderSizePixel = 0, Position = UDim2.fromOffset(sidebar.Size.X.Offset - 40, 44),
						Size = UDim2.fromOffset(240, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 20, Parent = win.body,
					})
					macCorner(picker, 12)
					macStroke(picker, C.line, 0.85, 1)
					macNew("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = picker})
					macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = picker})
					macLabel(picker, "Whisper to…", 12, Enum.FontWeight.SemiBold, C.inkSoft, {Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 0, ZIndex = 21})
					local others = {}
					for _, other in ipairs(Players:GetPlayers()) do
						if other ~= player then
							table.insert(others, other)
						end
					end
					table.sort(others, function(a, b)
						return a.DisplayName:lower() < b.DisplayName:lower()
					end)
					if #others == 0 then
						macLabel(picker, "No one else is here.", 13, Enum.FontWeight.Regular, C.ink, {Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, ZIndex = 21})
					end
					for i, other in ipairs(others) do
						local row = macButton(picker, {Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.accent, LayoutOrder = i, ZIndex = 21})
						macCorner(row, 8)
						local avatar = macNew("ImageLabel", {
							BackgroundColor3 = Color3.fromRGB(190, 196, 206), Image = "rbxthumb://type=AvatarHeadShot&id=" .. other.UserId .. "&w=48&h=48",
							Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(28, 28), ZIndex = 22, Parent = row,
						})
						macCorner(avatar, UDim.new(1, 0))
						local name = macLabel(row, other.DisplayName, 13, Enum.FontWeight.Medium, C.ink, {
							Position = UDim2.fromOffset(42, 3), Size = UDim2.new(1, -48, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 22,
						})
						local handle = macLabel(row, "@" .. other.Name, 11, Enum.FontWeight.Regular, C.inkSoft, {
							Position = UDim2.fromOffset(42, 20), Size = UDim2.new(1, -48, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 22,
						})
						row.MouseEnter:Connect(function()
							row.BackgroundTransparency = 0
							name.TextColor3, handle.TextColor3 = white, white
						end)
						row.MouseLeave:Connect(function()
							row.BackgroundTransparency = 1
							name.TextColor3, handle.TextColor3 = C.ink, C.inkSoft
						end)
						row.MouseButton1Click:Connect(function()
							if picker then
								picker:Destroy()
								picker = nil
							end
							input.Text = "/w " .. other.Name .. " "
							input:CaptureFocus()
							input.CursorPosition = #input.Text + 1
						end)
					end
				end)

				-- Keep up with new messages and channels
				local function onChange(channel, entry)
					if win.closed then
						return
					end
					if channel == viewing and entry then
						local existing = shown[entry]
						if existing and type(existing) == "table" and existing.label then
							existing.label.Text = entry.text
							existing.bubble.BackgroundTransparency = if entry.pending then 0.35 else 0
							if entry.failed then
								existing.bubble.BackgroundColor3 = Color3.fromRGB(255, 69, 58)
								existing.note.Visible = true
							end
						elseif not existing then
							local stick = nearBottom()
							emptyLabel.Text = ""
							addMessage(channel, entry)
							if stick or entry.mine then
								toBottom()
							end
						end
					end
					if not viewing and store.server then
						selectChannel(store.server)
					else
						paintList()
					end
				end
				table.insert(store.listeners, onChange)
				table.insert(win.cleanup, function()
					local i = table.find(store.listeners, onChange)
					if i then
						table.remove(store.listeners, i)
					end
					if store.viewing == viewing then
						store.viewing = nil
					end
					if openChat == selectChannel then
						openChat = nil
					end
				end)

				local first = store.server or store.order[1]
				if first then
					selectChannel(first)
				else
					emptyLabel.Text = "This game has no chat."
				end
			end,
		})
	end

	-- About This Mac (also the About pane in System Settings)
	local function buildAbout(parent)
		local viewport = workspace.CurrentCamera.ViewportSize
		macImage(parent, I.laptop, 96, C.glyph, {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0)})
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
			app = "preview", title = name, width = 560, height = 440, background = C.preview, minWidth = 300, minHeight = 240,
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
			app = "settings", title = firstPane, width = 720, height = 470, minWidth = 720, minHeight = 420,
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
					win.reopenArgs = {pane = name}
					for paneName, button in pairs(paneButtons) do
						local on = paneName == name
						button.BackgroundTransparency = if on then 0 else 1
						button:FindFirstChildOfClass("TextLabel").TextColor3 = if on then white else C.ink
					end
					panes[name](currentPane)
				end
				-- `decorate(tile)` draws an icon that isn't an image
				local function paneButton(name, icon, top, bottom, order, decorate)
					local button = macButton(win.sidebar, {
						Position = UDim2.fromOffset(8, 100 + (order - 1) * 32), Size = UDim2.new(1, -16, 0, 30),
						BackgroundColor3 = C.accent,
					})
					macCorner(button, 8)
					local tile = macAppTile(button, {icon = icon or "", top = top, bottom = bottom}, 22)
					tile.Position = UDim2.fromOffset(6, 4)
					if decorate then
						decorate(tile)
					end
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
						BackgroundColor3 = C.surface, BorderSizePixel = 0, Position = UDim2.fromOffset(16, y),
						Size = UDim2.new(1, -32, 0, count * 40), Parent = pane,
					})
					macCorner(box, 10)
					macStroke(box, C.line, 0.92, 1)
					local rows = {}
					for i = 1, count do
						rows[i] = macNew("Frame", {
							BackgroundTransparency = 1, Position = UDim2.fromOffset(0, (i - 1) * 40), Size = UDim2.new(1, 0, 0, 40), Parent = box,
						})
						if i < count then
							macNew("Frame", {
								BackgroundColor3 = C.line, BackgroundTransparency = 0.92, BorderSizePixel = 0,
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

				panes.General = function(pane)
					local row = group(pane, 0, 1)[1]
					macLabel(row, "Show startup screen", 14, Enum.FontWeight.Regular, C.ink, {Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -80, 1, 0)})
					local toggle = macToggle(row, macSettings.startupScreen == true, function(on)
						macSettings.startupScreen = on
						saveMacSettings()
					end)
					toggle.button.AnchorPoint = Vector2.new(1, 0.5)
					toggle.button.Position = UDim2.new(1, -14, 0.5, 0)
					macLabel(pane, "When you load macOS, show the Apple logo and a progress bar instead of going straight to the lock screen. It always shows on Restart and the first time macOS starts.", 13, Enum.FontWeight.Regular, C.inkSoft, {
						Position = UDim2.fromOffset(20, 50), Size = UDim2.new(1, -40, 0, 54), TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
					})

					-- Redownload: restarts into the startup screen, which deletes the
					-- assets and gets them again (see rebuildMacAssets)
					local assetsRow = group(pane, 116, 1)[1]
					macLabel(assetsRow, "Assets", 14, Enum.FontWeight.Regular, C.ink, {Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -170, 1, 0)})
					local redownload = macButton(assetsRow, {
						AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(122, 26),
						BackgroundTransparency = 0.9, BackgroundColor3 = C.line,
					})
					macCorner(redownload, UDim.new(1, 0))
					macLabel(redownload, "Redownload…", 13, Enum.FontWeight.Medium, C.ink, {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center})
					redownload.MouseButton1Click:Connect(function()
						task.spawn(confirmRedownload)
					end)
					macLabel(pane, "Deletes the music, sounds, clock font and Liquid Glass images macOS has saved, then restarts and downloads or makes each one again. Try it if something looks broken.", 13, Enum.FontWeight.Regular, C.inkSoft, {
						Position = UDim2.fromOffset(20, 166), Size = UDim2.new(1, -40, 0, 54), TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
					})
				end

				-- Ask: the Claude API key Spotlight's Ask uses
				panes.Ask = function(pane)
					local red, green = Color3.fromRGB(230, 70, 60), Color3.fromRGB(40, 170, 80)
					local top = group(pane, 0, 1)[1]
					ask.orb(top, 26).Position = UDim2.fromOffset(10, 7)
					macLabel(top, "Claude API key", 14, Enum.FontWeight.Medium, C.ink, {Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -250, 1, 0)})
					local current = macLabel(top, "", 14, Enum.FontWeight.Regular, C.inkSoft, {
						AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -100, 0, 0), Size = UDim2.fromOffset(150, 40),
						TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
					})
					local remove = macButton(top, {
						AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(84, 26),
						BackgroundTransparency = 0.9, BackgroundColor3 = C.line,
					})
					macCorner(remove, UDim.new(1, 0))
					macLabel(remove, "Remove", 13, Enum.FontWeight.Medium, C.ink, {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center})

					-- The field shows dots, never the key itself
					local fieldRow = group(pane, 52, 1)[1]
					local hint = "Paste your key (sk-ant-…)"
					local field = macNew("TextBox", {
						BackgroundTransparency = 1, ClearTextOnFocus = false, Text = "", PlaceholderText = "", TextTransparency = 1,
						TextColor3 = C.ink, FontFace = macFont(Enum.FontWeight.Regular), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
						Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -110, 1, 0), ClipsDescendants = true, Parent = fieldRow,
					})
					local dots = macLabel(fieldRow, hint, 14, Enum.FontWeight.Regular, C.inkSoft, {
						Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -110, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
					})
					field:GetPropertyChangedSignal("Text"):Connect(function()
						local count = utf8.len(field.Text) or #field.Text
						dots.Text = if count == 0 then hint else string.rep("•", math.min(count, 60))
						dots.TextColor3 = if count == 0 then C.inkSoft else C.ink
					end)
					local save = macButton(fieldRow, {
						AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(84, 26),
						BackgroundTransparency = 0, BackgroundColor3 = C.accent,
					})
					macCorner(save, UDim.new(1, 0))
					macLabel(save, "Save", 13, Enum.FontWeight.Medium, white, {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center})
					local message = macLabel(pane, "", 13, Enum.FontWeight.Medium, C.inkSoft, {
						Position = UDim2.fromOffset(20, 98), Size = UDim2.new(1, -40, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd,
					})
					local function say(text, color)
						message.Text = text
						message.TextColor3 = color or C.inkSoft
					end
					local function refresh()
						local key = macClaudeKey.read()
						current.Text = if key then macClaudeKey.masked(key) else "Not set"
						current.Position = UDim2.new(1, if key then -100 else -14, 0, 0)
						remove.Visible = key ~= nil
					end
					refresh()
					local checking = false
					local function trySave()
						local key = (field.Text:gsub("%s", ""))
						if key == "" or checking then
							return
						end
						if not key:match("^sk%-ant%-") then
							say("That doesn't look like a Claude API key: they start with sk-ant-.", red)
							return
						end
						-- Anthropic's free model list says whether the key works
						checking = true
						say("Checking the key with Anthropic…")
						task.spawn(function()
							local ok, problem = ask.checkKey(key)
							checking = false
							if ok then
								macClaudeKey.save(key)
								field.Text = ""
								refresh()
								say("Saved. Press Ctrl+Space and type a question to Ask.", green)
							else
								say(problem or "Anthropic didn't accept that key.", red)
							end
						end)
					end
					save.MouseButton1Click:Connect(trySave)
					field.FocusLost:Connect(function(enterPressed)
						if enterPressed then
							trySave()
						end
					end)
					remove.MouseButton1Click:Connect(function()
						macClaudeKey.remove()
						refresh()
						say("Removed. Ask is off until you add a key.")
					end)

					local switches = group(pane, 126, 2)
					for i, spec in ipairs({{"Let Claude use this Mac", "askTools"}, {"Let Claude search the web", "askWeb"}}) do
						macLabel(switches[i], spec[1], 14, Enum.FontWeight.Regular, C.ink, {Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -80, 1, 0)})
						local toggle = macToggle(switches[i], macSettings[spec[2]] ~= false, function(on)
							macSettings[spec[2]] = on
							saveMacSettings()
						end)
						toggle.button.AnchorPoint = Vector2.new(1, 0.5)
						toggle.button.Position = UDim2.new(1, -14, 0.5, 0)
					end
					macLabel(pane, "Ask (in Spotlight) sends what you type to Claude Opus 5.5 with your own API key, so it's billed to your Anthropic account (web searches cost about a cent each). Claude can open apps, arrange windows, read and write files in the workspace, play music and change settings; Sleep, Restart and Shut Down still ask you first. The key is saved as plain text in your executor's workspace (coolui_assets/claude_api_key.txt) and is only ever sent to api.anthropic.com. Get one at console.anthropic.com.", 13, Enum.FontWeight.Regular, C.inkSoft, {
						Position = UDim2.fromOffset(20, 216), Size = UDim2.new(1, -40, 0, 120), TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
					})
				end

				panes.Appearance = function(pane)
					macLabel(pane, "Choose how windows and menus look.", 14, Enum.FontWeight.Regular, C.inkSoft, {
						Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -32, 0, 20),
					})
					-- Mini windows on the desktop. Their colors are a shade off the
					-- palettes', so switching appearance doesn't repaint them.
					local looks = {
						light = {window = Color3.fromRGB(246, 246, 248), sidebar = Color3.fromRGB(231, 232, 236), line = Color3.fromRGB(205, 205, 210)},
						dark = {window = Color3.fromRGB(39, 39, 43), sidebar = Color3.fromRGB(52, 52, 57), line = Color3.fromRGB(78, 78, 84)},
					}
					local rings = {}
					local function card(name, title, x)
						local look = looks[name]
						local holder = macButton(pane, {Position = UDim2.fromOffset(x, 36), Size = UDim2.fromOffset(150, 124)})
						local preview = macNew("Frame", {BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromOffset(150, 96), Parent = holder})
						macCorner(preview, 10)
						macNew("UIGradient", {Rotation = 60, Color = ColorSequence.new(Color3.fromRGB(70, 150, 255), Color3.fromRGB(20, 70, 200)), Parent = preview})
						local mini = macNew("Frame", {BackgroundColor3 = look.window, BorderSizePixel = 0, Position = UDim2.fromOffset(22, 18), Size = UDim2.fromOffset(106, 64), Parent = preview})
						macCorner(mini, 7)
						local side = macNew("Frame", {BackgroundColor3 = look.sidebar, BorderSizePixel = 0, Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(30, 58), Parent = mini})
						macCorner(side, 5)
						for i, color in ipairs({Color3.fromRGB(255, 95, 87), Color3.fromRGB(254, 188, 46), Color3.fromRGB(40, 200, 64)}) do
							local dot = macNew("Frame", {BackgroundColor3 = color, BorderSizePixel = 0, Position = UDim2.fromOffset(4 + (i - 1) * 7, 6), Size = UDim2.fromOffset(5, 5), Parent = side})
							macCorner(dot, UDim.new(1, 0))
						end
						for i = 0, 2 do
							macNew("Frame", {
								BackgroundColor3 = look.line, BorderSizePixel = 0, Position = UDim2.fromOffset(40, 14 + i * 12),
								Size = UDim2.fromOffset(if i == 1 then 44 else 58, 5), Parent = mini,
							})
						end
						local ring = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 96), Parent = holder})
						macCorner(ring, 10)
						rings[name] = macStroke(ring, C.accent, 1, 3)
						macLabel(holder, title, 14, Enum.FontWeight.Medium, C.ink, {
							Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center,
						})
						holder.MouseButton1Click:Connect(function()
							desktop.setAppearance(name)
							for other, stroke in pairs(rings) do
								stroke.Transparency = if other == name then 0 else 1
							end
						end)
					end
					card("light", "Light", 16)
					card("dark", "Dark", 182)
					for name, stroke in pairs(rings) do
						stroke.Transparency = if name == appearance then 0 else 1
					end
				end

				paneButton("Wi-Fi", MACOS_ICONS.wifi, Color3.fromRGB(90, 170, 255), Color3.fromRGB(0, 110, 245), 1)
				paneButton("Battery", I.battery, Color3.fromRGB(120, 220, 120), Color3.fromRGB(40, 175, 70), 2)
				paneButton("General", I.settings, Color3.fromRGB(176, 178, 186), Color3.fromRGB(112, 114, 124), 3)
				-- Appearance's icon: a circle, half white and half black
				paneButton("Appearance", nil, Color3.fromRGB(70, 70, 76), Color3.fromRGB(28, 28, 32), 4, function(tile)
					local circle = macNew("Frame", {
						BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), Parent = tile,
					})
					macCorner(circle, UDim.new(1, 0))
					macStroke(circle, Color3.new(1, 1, 1), 0, 1)
					macNew("UIGradient", {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
							ColorSequenceKeypoint.new(0.501, Color3.new(0, 0, 0)), ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
						}),
						Parent = circle,
					})
				end)
				paneButton("Wallpaper", I.image, Color3.fromRGB(90, 200, 250), Color3.fromRGB(0, 122, 255), 5)
				-- Ask's icon: Claude's orb on black
				paneButton("Ask", nil, Color3.fromRGB(44, 44, 52), Color3.fromRGB(14, 14, 18), 6, function(tile)
					local orb = ask.orb(tile, 14)
					orb.AnchorPoint = Vector2.new(0.5, 0.5)
					orb.Position = UDim2.fromScale(0.5, 0.5)
				end)
				paneButton("About", I.info, Color3.fromRGB(176, 178, 186), Color3.fromRGB(112, 114, 124), 7)
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
		if spotlightGlass and root.Visible then
			spotlightGlass.update(workspace.CurrentCamera)
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

	-- ---------- Spotlight ----------
	-- macOS 27's "Search or Ask" bar: a capsule of dark Liquid Glass with a
	-- glowing cursor (the menu bar's magnifier, or Ctrl+Space). It finds apps,
	-- System Settings panes, actions (Lock Screen, Sleep, Restart, Dark Mode…),
	-- files in the workspace, and works out sums. With a Claude API key
	-- (System Settings > Ask) it also Asks: see the Ask section below.
	-- Sized like macOS 27's bar (measured from Apple's own screenshot): about
	-- six times as long as it's tall, a seventh of the way down the screen
	local SPOT_WIDTH, SPOT_HEIGHT, SPOT_TOP = 460, 74, 150
	local SPOT_TEXT_SIZE, SPOT_TEXT_LEFT = 20, 30
	local TextService = game:GetService("TextService")
	local SPOT_ROW, SPOT_MAX_ROWS = 40, 8
	local spotlight = nil -- the open one
	local fileIndex, indexing, indexedAt = nil, false, 0

	-- Files and folders in the workspace, a few levels deep. Built in the
	-- background when Spotlight opens (and again after a while, as files change).
	local function indexFiles()
		if indexing then
			return
		end
		indexing = true
		local found = {}
		local queue = {{"", 0}}
		local folders = 0
		while #queue > 0 and #found < 3000 and alive do
			local folder = table.remove(queue, 1)
			local ok, entries = pcall(macListFolder, folder[1])
			if ok then
				for _, entry in ipairs(entries) do
					table.insert(found, entry)
					if entry.folder and folder[2] < 3 then
						table.insert(queue, {entry.path, folder[2] + 1})
					end
				end
			end
			folders += 1
			if folders % 6 == 0 then
				task.wait()
			end
		end
		fileIndex, indexing, indexedAt = found, false, os.clock()
	end

	-- Opens a found file in the app that shows it (or its folder in Finder)
	local function openFile(entry)
		if entry.folder then
			openApp("finder", {path = entry.path, newWindow = true})
			return
		end
		local ext = macExtension(entry.name)
		if MAC_IMAGE_EXTENSIONS[ext] then
			openApp("preview", {path = entry.path, newWindow = true})
		elseif MAC_AUDIO_EXTENSIONS[ext] then
			openApp("music", {path = entry.path})
		elseif MAC_TEXT_EXTENSIONS[ext] then
			openApp("notes", {path = entry.path, newWindow = true})
		else
			openApp("finder", {path = entry.path:match("^(.*)/[^/]+$") or "", newWindow = true})
		end
	end

	-- Everything Spotlight knows besides files: {title, kind, keywords?,
	-- tile (an app, for its icon) or icon, action}
	local spotlightItems = {}
	do
		local settingsTile, finderTile
		for _, app in ipairs(MAC_APPS) do
			if app.id == "settings" then
				settingsTile = app
			elseif app.id == "finder" then
				finderTile = app
			end
		end
		local appWords = {
			finder = "files folders workspace", notes = "text write", music = "songs mp3 audio",
			terminal = "console shell command luau", settings = "preferences system", youtube = "video videos shorts live stream watch", timer = "clock stopwatch countdown alarm",
			chat = "messages roblox whisper talk",
		}
		for _, app in ipairs(MAC_APPS) do
			table.insert(spotlightItems, {title = app.name, kind = "Application", keywords = appWords[app.id], tile = app, action = function()
				openApp(app.id)
			end})
		end
		table.insert(spotlightItems, {title = "Trash", kind = "Application", tile = MAC_TRASH, action = function()
			openApp("trash")
		end})
		table.insert(spotlightItems, {title = "About This Mac", kind = "Application", tile = finderTile, action = function()
			openApp("about")
		end})
		local paneWords = {
			["Wi-Fi"] = "wifi internet network ping", Battery = "power", General = "startup screen redownload assets",
			Appearance = "dark mode light mode theme", Wallpaper = "background desktop 3d scene", Ask = "claude ai api key siri",
			About = "version",
		}
		for _, pane in ipairs({"Wi-Fi", "Battery", "General", "Appearance", "Wallpaper", "Ask", "About"}) do
			table.insert(spotlightItems, {title = pane, kind = "System Settings", keywords = paneWords[pane], tile = settingsTile, action = function()
				openApp("settings", {pane = pane})
			end})
		end
		local actions = {
			{"Lock Screen", function()
				finish("lock")
			end},
			{"Log Out", function()
				finish("logout")
			end},
			{"Sleep", confirmSleep},
			{"Restart", confirmRestart},
			{"Shut Down", confirmShutDown},
			{"Dark Mode", function()
				desktop.setAppearance("dark")
			end, "appearance theme"},
			{"Light Mode", function()
				desktop.setAppearance("light")
			end, "appearance theme"},
			{"Redownload Assets", confirmRedownload, "download reset images"},
		}
		for _, action in ipairs(actions) do
			table.insert(spotlightItems, {title = action[1], kind = "Action", keywords = action[3], icon = I.apple, action = action[2]})
		end
	end

	-- How well `text` matches (0 = not at all): whole, start, start of a word, anywhere
	local function matchScore(text, query)
		text = text:lower()
		if text == query then
			return 4
		elseif text:sub(1, #query) == query then
			return 3
		elseif text:find("[%s%-_%.]" .. query:gsub("%p", "%%%0")) then
			return 2
		elseif text:find(query, 1, true) then
			return 1
		end
		return 0
	end

	-- A sum like "12 * (3 + 4)": only digits, operators and brackets, so it's
	-- safe to hand to Luau
	local function calculate(query)
		if not query:match("^[%d%s%.%+%-%*/%%%^%(%)]+$") or not query:match("%d") or not query:match("%d%s*[%+%-%*/%%%^]") then
			return nil
		end
		local chunk = loadstring("return " .. query)
		if not chunk then
			return nil
		end
		local ok, value = pcall(chunk)
		if ok and type(value) == "number" and value == value and math.abs(value) ~= math.huge then
			return value
		end
		return nil
	end

	-- `canAsk`: there's a Claude key, so the query can be asked too
	local function search(query, canAsk)
		local original = query:match("^%s*(.-)%s*$")
		query = original:lower()
		if query == "" then
			return {}
		end
		local results = {}
		local value = calculate(query)
		if value then
			local text = if value == math.floor(value) and math.abs(value) < 1e15 then string.format("%d", value) else string.format("%.10g", value)
			table.insert(results, {title = "= " .. text, kind = "Calculator — Enter copies", icon = I.plus, score = 10, action = function()
				pcall(setclipboard, text)
			end})
		end
		for _, item in ipairs(spotlightItems) do
			local score = matchScore(item.title, query)
			if score == 0 and item.keywords and matchScore(item.keywords, query) > 0 then
				score = 0.5
			end
			if score > 0 then
				item.score = score + 1.5 -- apps, settings and actions before files
				table.insert(results, item)
			end
		end
		if fileIndex then
			local files = 0
			for _, entry in ipairs(fileIndex) do
				local score = matchScore(entry.name, query)
				if score > 0 then
					local kind, icon = macFileKind(entry.name, entry.folder)
					local where = entry.path:match("^(.*)/[^/]+$")
					table.insert(results, {
						title = entry.name, kind = if where then kind .. " — " .. where else kind, icon = icon,
						iconColor = if entry.folder then Color3.fromRGB(100, 170, 255) else Color3.fromRGB(205, 205, 212),
						score = score, isFile = true, action = function()
							openFile(entry)
						end,
					})
					files += 1
					if files >= 40 then
						break
					end
				end
			end
		end
		table.sort(results, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return #a.title < #b.title
		end)
		local top, files = {}, 0
		for _, item in ipairs(results) do
			local isFile = item.isFile == true
			if not isFile or files < 5 then
				table.insert(top, item)
				files += if isFile then 1 else 0
			end
			if #top >= SPOT_MAX_ROWS then
				break
			end
		end

		-- Ask Claude: first when nothing matches well or it reads like a
		-- sentence, otherwise last. Without a key, a way to set one up.
		local _, words = original:gsub("%S+", "")
		local askRow = nil
		if canAsk then
			askRow = {title = original, kind = if #ask.transcript > 0 then "Ask a follow-up" else "Ask Claude", orb = true, ask = true}
		elseif words >= 3 or #top == 0 then
			askRow = {title = "Ask Claude", kind = "Set up in System Settings", orb = true, action = function()
				openApp("settings", {pane = "Ask"})
			end}
		end
		if askRow then
			local first = canAsk and (words >= 3 or not top[1] or top[1].score < 3)
			if first then
				table.insert(top, 1, askRow)
			else
				table.insert(top, askRow)
			end
			if #top > SPOT_MAX_ROWS then
				table.remove(top, if first then #top else SPOT_MAX_ROWS)
			end
		end
		return top
	end

	local function closeSpotlight()
		if not spotlight then
			return
		end
		local open = spotlight
		spotlight = nil
		ask.onChange = nil
		searchButton.BackgroundTransparency = 1
		for _, connection in ipairs(open.connections) do
			connection:Disconnect()
		end
		if spotlightGlass then
			spotlightGlass.destroy()
			spotlightGlass = nil
		end
		open.catcher:Destroy()
		local out = tween(open.scale, 0.12, {Scale = 0.97}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, item in ipairs(open.holder:GetDescendants()) do
			if item:IsA("GuiObject") and item.BackgroundTransparency < 1 then
				tween(item, 0.12, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
			if item:IsA("ImageLabel") then
				tween(item, 0.12, {ImageTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			elseif item:IsA("TextLabel") or item:IsA("TextBox") then
				tween(item, 0.12, {TextTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			elseif item:IsA("UIStroke") then
				tween(item, 0.12, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
		out.Completed:Once(function()
			open.holder:Destroy()
		end)
	end

	-- `quiet`: just show it (Ask's answer coming in), without taking the keyboard
	local function openSpotlight(quiet)
		if spotlight then
			if not quiet then
				spotlight.box:CaptureFocus()
			end
			return
		end
		closeMenu()
		if not fileIndex or os.clock() - indexedAt > 30 then
			task.spawn(indexFiles)
		end
		-- A conversation left alone for ten minutes starts over
		if not ask.busy and ask.lastActivity and os.clock() - ask.lastActivity > 600 and ask.clear then
			ask.clear()
		end
		searchButton.BackgroundTransparency = 0.72
		local open = {connections = {}, results = {}, selected = 1, hasKey = macClaudeKey.read() ~= nil, glassParts = {}, merged = false}
		spotlight = open

		-- Clicking anywhere else closes it
		open.catcher = macButton(overlay, {Size = UDim2.fromScale(1, 1), ZIndex = 25})
		open.catcher.MouseButton1Down:Connect(closeSpotlight)
		local holder = macNew("Frame", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, SPOT_TOP),
			Size = UDim2.fromOffset(SPOT_WIDTH, SPOT_HEIGHT), ZIndex = 26, Parent = overlay,
		})
		open.holder = holder
		open.scale = macNew("UIScale", {Scale = 0.96, Parent = holder})
		tween(open.scale, 0.2, {Scale = 1})

		-- The bar. Like macOS 27's: glass that's nearly black along the top and
		-- clears toward the bottom, where the background shows through, with
		-- light catching its lower edge. (A dark fill where there's no glass.)
		local bar = macNew("Frame", {
			BackgroundColor3 = Color3.fromRGB(20, 20, 24), BackgroundTransparency = 1, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(1, 1),
			ZIndex = 2, Active = true, Parent = holder,
		})
		macCorner(bar, UDim.new(1, 0))
		local edge = macStroke(bar, white, 0, 1)
		macNew("UIGradient", {
			Rotation = 90, Parent = edge,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.6, 0.8), NumberSequenceKeypoint.new(1, 0.35),
			}),
		})
		local shading = macNew("Frame", {
			BackgroundColor3 = Color3.fromRGB(6, 6, 8), BackgroundTransparency = 0, BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = bar,
		})
		macCorner(shading, UDim.new(1, 0))
		macNew("UIGradient", {
			Rotation = 90, Parent = shading,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.04), NumberSequenceKeypoint.new(0.45, 0.2), NumberSequenceKeypoint.new(1, 0.62),
			}),
		})
		local baked = session.mode == "wallpaper" and not assets.wallpaper and assets.glow ~= nil
		local live = session.mode == "scene" and macSky ~= nil
		if baked or live then
			task.spawn(function()
				local ok, err = pcall(function()
					-- Where the bar settles, in pixels from the top of the screen
					local x = math.round((screenW - SPOT_WIDTH) / 2 * s)
					local y = math.round(SPOT_TOP * s)
					local w, h = math.round(SPOT_WIDTH * s), math.round(SPOT_HEIGHT * s)
					local opts = table.clone(MAC_SPOTLIGHT_GLASS)
					local pane = macNew("ImageLabel", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageTransparency = 1, ZIndex = 1, Parent = bar})
					macCorner(pane, UDim.new(1, 0))
					table.insert(open.glassParts, pane)
					pane.Visible = not open.merged
					local layers = {{pane, "ImageTransparency", 0}}
					if baked then
						local screen = gui.AbsoluteSize
						pane.Image = bakeMacGlass("spotlight5", x, y, w, h, screen.X, screen.Y, opts)
					else
						local tint = macNew("Frame", {BackgroundColor3 = opts.tint, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = bar})
						macCorner(tint, UDim.new(1, 0))
						local rimLight = macNew("ImageLabel", {
							BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageTransparency = 1, ZIndex = 1,
							Image = bakeMacGlassRim("spotlight5", w, h, opts), Parent = bar,
						})
						table.insert(layers, {tint, "BackgroundTransparency", 1 - opts.tintAlpha})
						table.insert(layers, {rimLight, "ImageTransparency", 0})
						for _, part in ipairs({tint, rimLight}) do
							table.insert(open.glassParts, part)
							part.Visible = not open.merged
						end
						task.wait() -- sized by now
						local glass = createMacLiveGlass(pane, opts)
						glass.enabled = true
						glass.update(workspace.CurrentCamera)
						if spotlight == open then
							spotlightGlass = glass
						else
							glass.destroy()
						end
					end
					local images = {}
					for _, layer in ipairs(layers) do
						table.insert(images, layer[1])
					end
					ContentProvider:PreloadAsync(images)
					if spotlight == open then
						for _, layer in ipairs(layers) do
							tween(layer[1], 0.15, {[layer[2]] = layer[3]}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
						end
					end
				end)
				if not ok then
					warn("[coolui] Spotlight glass failed: " .. tostring(err))
					open.barFill = 0.12
					bar.BackgroundTransparency = if open.merged then 1 else 0.12
				end
			end)
		else
			open.barFill = 0.12
			bar.BackgroundTransparency = 0.12
		end
		-- With an answer showing, the bar becomes the answer card's bottom row:
		-- its own glass and shading go, and a hairline divides it off
		local divider = macNew("Frame", {
			BackgroundColor3 = white, BackgroundTransparency = 0.88, BorderSizePixel = 0, Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -44, 0, 1), Visible = false, ZIndex = 3, Parent = bar,
		})
		local function setMerged(on)
			open.merged = on
			shading.Visible = not on
			edge.Enabled = not on
			divider.Visible = on
			bar.BackgroundTransparency = if on then 1 else open.barFill or 1
			for _, part in ipairs(open.glassParts) do
				part.Visible = not on
			end
			if not on then
				bar.Position = UDim2.fromScale(0.5, 0)
				bar.Size = UDim2.fromScale(1, 1)
			end
		end

		-- Text field, with macOS 27's cursor drawn over Roblox's own: a bright
		-- white line with a soft halo, wherever the cursor is in the text
		local box = macNew("TextBox", {
			BackgroundTransparency = 1, ClearTextOnFocus = false, Text = "", PlaceholderText = "Search",
			PlaceholderColor3 = Color3.fromRGB(200, 198, 196), TextColor3 = white, FontFace = macFont(Enum.FontWeight.Regular),
			TextSize = SPOT_TEXT_SIZE, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(SPOT_TEXT_LEFT, 0),
			Size = UDim2.new(1, -2 * SPOT_TEXT_LEFT, 1, 0), ClipsDescendants = true, ZIndex = 5, Parent = bar,
		})
		open.box = box
		local caret = macNew("Frame", {
			BackgroundColor3 = white, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, SPOT_TEXT_LEFT, 0.5, 0), Size = UDim2.fromOffset(2, SPOT_TEXT_SIZE + 6),
			Visible = false, ZIndex = 7, Parent = bar,
		})
		macCorner(caret, UDim.new(1, 0))
		-- Two halos: a tight bright one, and a faint wider one
		local halo = macNew("ImageLabel", {
			BackgroundTransparency = 1, Image = assets.glow or "", ImageColor3 = Color3.fromRGB(255, 252, 245),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, SPOT_TEXT_SIZE + 20),
			ImageTransparency = 0.25, ZIndex = 6, Parent = caret,
		})
		local outerHalo = macNew("ImageLabel", {
			BackgroundTransparency = 1, Image = assets.glow or "", ImageColor3 = Color3.fromRGB(255, 250, 240),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, SPOT_TEXT_SIZE + 34),
			ImageTransparency = 0.78, ZIndex = 6, Parent = caret,
		})

		-- Results, in a dark panel under the bar
		local panel = macNew("Frame", {
			BackgroundColor3 = Color3.fromRGB(24, 24, 28), BackgroundTransparency = 0, BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, SPOT_HEIGHT + 10), Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false, ZIndex = 2, Active = true, Parent = holder,
		})
		macCorner(panel, 22)
		macStroke(panel, white, 0.88, 1)
		macNew("UIPadding", {
			PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = panel,
		})
		macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel})

		-- Ask. While Claude works, the bar gives way to a small "Working" pill
		-- with a ring of dots, whose words turn into what you asked about once
		-- that's known. Then the answer and the bar become one card: the answer
		-- on top (with close and expand buttons), the bar as its bottom row for
		-- a follow-up, and a ripple of light spreads through it as it arrives.
		local pill = macNew("Frame", {
			BackgroundColor3 = Color3.fromRGB(14, 14, 16), BackgroundTransparency = 0.06, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, (SPOT_HEIGHT - 46) / 2), Size = UDim2.fromOffset(0, 46),
			AutomaticSize = Enum.AutomaticSize.X, Visible = false, ZIndex = 2, Active = true, Parent = holder,
		})
		macCorner(pill, UDim.new(1, 0))
		macStroke(pill, white, 0.9, 1)
		local pillScale = macNew("UIScale", {Parent = pill})
		macNew("UIPadding", {PaddingLeft = UDim.new(0, 13), PaddingRight = UDim.new(0, 10), Parent = pill})
		macNew("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 11), Parent = pill,
		})
		-- The ring: eight dots round a circle; a bright head goes round and the
		-- dots behind it shrink and fade, leaving a gap just ahead of it
		local ring = macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 26), LayoutOrder = 1, ZIndex = 3, Parent = pill})
		local dots = {}
		for i = 1, 8 do
			local angle = (i - 1) / 8 * math.pi * 2
			local dot = macNew("Frame", {
				BackgroundColor3 = white, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.sin(angle) * 9.5, 0.5, -math.cos(angle) * 9.5), Size = UDim2.fromOffset(4, 4),
				ZIndex = 3, Parent = ring,
			})
			macCorner(dot, UDim.new(1, 0))
			dots[i] = {frame = dot, angle = angle}
		end
		local pillText = macLabel(pill, "Working", 16, Enum.FontWeight.Medium, white, {
			Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 3,
		})
		-- Stop: a small square in a circle at the end of the pill
		local stopButton = macButton(pill, {
			Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0.85, BackgroundColor3 = white, LayoutOrder = 3, ZIndex = 3,
		})
		macCorner(stopButton, UDim.new(1, 0))
		local stopSquare = macNew("Frame", {
			BackgroundColor3 = white, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(9, 9), ZIndex = 4, Parent = stopButton,
		})
		macCorner(stopSquare, 2)
		local shownTopic = "Working"
		local function setPillText(text)
			if text == shownTopic then
				return
			end
			shownTopic = text
			local out = tween(pillText, 0.12, {TextTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			out.Completed:Once(function()
				pillText.Text = shownTopic
				tween(pillText, 0.18, {TextTransparency = 0}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end)
		end

		local CARD_HEADER, CARD_MAX = 56, 440
		local card = macNew("Frame", {
			BackgroundColor3 = white, BackgroundTransparency = 0.03, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(SPOT_WIDTH, CARD_HEADER + SPOT_HEIGHT),
			Visible = false, ZIndex = 1, Active = true, Parent = holder,
		})
		macCorner(card, 28)
		macStroke(card, white, 0.87, 1)
		-- (white tinted by the gradient: a little lighter along the top)
		macNew("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(42, 42, 48), Color3.fromRGB(19, 19, 23)), Parent = card})
		local function roundButton(anchor, x)
			local button = macButton(card, {
				AnchorPoint = Vector2.new(anchor, 0), Position = UDim2.new(anchor, x, 0, 12), Size = UDim2.fromOffset(32, 32),
				BackgroundTransparency = 0.86, BackgroundColor3 = white, ZIndex = 3,
			})
			macCorner(button, UDim.new(1, 0))
			return button
		end
		local closeButton = roundButton(0, 12)
		macImage(closeButton, I.close, 16, white, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 4})
		-- Expand: two little arrows out to opposite corners, drawn as bars
		local expandButton = roundButton(1, -12)
		local glyph = macNew("Frame", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14), ZIndex = 4, Parent = expandButton,
		})
		for _, bar in ipairs({{7, 7, 16, -45}, {11, 0.8, 6, 0}, {13.2, 3, 6, 90}, {3, 13.2, 6, 0}, {0.8, 11, 6, 90}}) do
			local piece = macNew("Frame", {
				BackgroundColor3 = white, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(bar[1], bar[2]),
				Size = UDim2.fromOffset(bar[3], 1.7), Rotation = bar[4], ZIndex = 4, Parent = glyph,
			})
			macCorner(piece, UDim.new(1, 0))
		end
		local cardTitle = macLabel(card, "", 13, Enum.FontWeight.Medium, white, {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(1, -120, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.5, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
		})
		local scroller = macNew("ScrollingFrame", {
			BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, CARD_HEADER), Size = UDim2.new(1, 0, 0, 0),
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
			ScrollBarImageColor3 = white, ScrollBarImageTransparency = 0.65, ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 3, Parent = card,
		})
		local lines = macNew("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = scroller})
		macNew("UIPadding", {PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), PaddingBottom = UDim.new(0, 22), Parent = scroller})
		-- The ripple: a rainbow ring spreading from the top of the card, kept
		-- inside its rounded corners by a CanvasGroup
		local rippleLayer = macNew("CanvasGroup", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = card})
		macCorner(rippleLayer, 28)
		local ripple = macNew("ImageLabel", {
			BackgroundTransparency = 1, Image = ask.rippleImage(), ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(0, 0), ZIndex = 8, Parent = rippleLayer,
		})
		local rippleGradient = macNew("UIGradient", {Color = ask.colors, Parent = ripple})
		for _, part in ipairs({rippleLayer, ripple}) do
			pcall(function()
				part.Interactable = false
			end)
		end

		-- Claude writes Markdown: paragraphs, # headings, - and 1. lists,
		-- **bold**, `code` and [links](…), which show underlined
		local function inline(text)
			text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
			text = text:gsub("%[([^%]\n]+)%]%(([^%)\n]+)%)", "<u>%1</u>")
			text = text:gsub("%*%*(.-)%*%*", "<b>%1</b>"):gsub("`([^`\n]+)`", '<font face="RobotoMono">%1</font>')
			return text
		end
		local function parseBlocks(text)
			local out, paragraph, code = {}, {}, nil
			local function flush()
				if #paragraph > 0 then
					table.insert(out, {kind = "p", text = table.concat(paragraph, "\n")})
					table.clear(paragraph)
				end
			end
			for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
				if line:match("^%s*```") then
					flush()
					if code then
						table.insert(out, {kind = "code", text = table.concat(code, "\n")})
						code = nil
					else
						code = {}
					end
				elseif code then
					table.insert(code, line)
				else
					local heading = line:match("^%s*#+%s+(.+)$")
					local bullet = line:match("^%s*[%-%*•]%s+(.+)$")
					local number, numbered = line:match("^%s*(%d+)[%.%)]%s+(.+)$")
					if heading then
						flush()
						table.insert(out, {kind = "h", text = heading})
					elseif bullet or numbered then
						flush()
						table.insert(out, {kind = "li", text = bullet or numbered, marker = if numbered then number .. "." else nil})
					elseif line:match("^%s*$") then
						flush()
					else
						table.insert(paragraph, line)
					end
				end
			end
			flush()
			if code and #code > 0 then
				table.insert(out, {kind = "code", text = table.concat(code, "\n")})
			end
			return out
		end

		local order = 0
		local function add(instance)
			order += 1
			instance.LayoutOrder = order
			return instance
		end
		local function textBlock(text, size, weight, props)
			props = props or {}
			props.Size = props.Size or UDim2.fromScale(1, 0)
			props.AutomaticSize = Enum.AutomaticSize.Y
			props.TextWrapped = true
			props.RichText = true
			props.LineHeight = props.LineHeight or 1.15
			props.ZIndex = 4
			local color = props.color or white
			props.color = nil
			return macLabel(scroller, text, size, weight, color, props)
		end
		-- Small grey tags in a row that wraps: what Claude did, or its sources
		local function chips(items)
			local row = add(macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = scroller}))
			local layout = macNew("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = row,
			})
			pcall(function()
				layout.Wraps = true
			end)
			for i, text in ipairs(items) do
				local chip = macNew("Frame", {
					BackgroundColor3 = white, BackgroundTransparency = 0.9, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 24),
					AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, ZIndex = 4, Parent = row,
				})
				macCorner(chip, 8)
				macNew("UIPadding", {PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = chip})
				macLabel(chip, text, 11, Enum.FontWeight.Medium, white, {
					Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, TextTransparency = 0.38, ZIndex = 5,
				})
			end
		end
		local function renderAnswer(entry)
			local sourcesShown = false
			local function sources()
				if sourcesShown or not entry.sources or #entry.sources == 0 then
					return
				end
				sourcesShown = true
				local shown = {}
				for i = 1, math.min(3, #entry.sources) do
					shown[i] = entry.sources[i]
				end
				if #entry.sources > 3 then
					table.insert(shown, "+" .. (#entry.sources - 3))
				end
				chips(shown)
			end
			for _, block in ipairs(parseBlocks(entry.text)) do
				if block.kind == "h" then
					-- (a little more room above a heading)
					add(macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 4), Parent = scroller}))
					add(textBlock(inline(block.text), 21, Enum.FontWeight.Bold, {LineHeight = 1.05}))
				elseif block.kind == "li" then
					local row = add(macNew("Frame", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = scroller}))
					if block.marker then
						macLabel(row, block.marker, 15, Enum.FontWeight.Medium, white, {Size = UDim2.fromOffset(22, 20), TextTransparency = 0.45, ZIndex = 4})
					else
						local dot = macNew("Frame", {
							BackgroundColor3 = white, BackgroundTransparency = 0.5, BorderSizePixel = 0, Position = UDim2.fromOffset(4, 8),
							Size = UDim2.fromOffset(5, 5), ZIndex = 4, Parent = row,
						})
						macCorner(dot, UDim.new(1, 0))
					end
					local label = textBlock(inline(block.text), 15, Enum.FontWeight.Regular, {Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 0, 0)})
					label.Parent = row
				elseif block.kind == "code" then
					local text = block.text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
					add(textBlock('<font face="RobotoMono">' .. text .. "</font>", 13, Enum.FontWeight.Regular, {TextTransparency = 0.15}))
				else
					add(textBlock(inline(block.text), 16, Enum.FontWeight.Regular))
					sources()
				end
			end
			sources()
		end

		local mode = nil -- "search", "busy" or "answer"
		local function fitCard()
			local width = card.Size.X.Offset
			-- (screen pixels per point, pop-in scale included)
			local ratio = scroller.AbsoluteSize.X / width
			if ratio <= 0 then
				return
			end
			local most = if ask.expanded then math.max(CARD_MAX, D.height - SPOT_TOP - SPOT_HEIGHT - CARD_HEADER - 110) else CARD_MAX
			local height = math.min(math.ceil(lines.AbsoluteContentSize.Y / ratio) + 22, most) -- (+ the bottom padding)
			scroller.Size = UDim2.new(1, 0, 0, height)
			card.Size = UDim2.fromOffset(width, CARD_HEADER + height + SPOT_HEIGHT)
			-- The bar sits in the card's bottom row
			if mode == "answer" then
				bar.Position = UDim2.new(0.5, 0, 0, CARD_HEADER + height)
				bar.Size = UDim2.fromOffset(width, SPOT_HEIGHT)
			end
		end
		table.insert(open.connections, lines:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitCard))
		-- The latest exchange: what Claude did (as tags), then its answer
		local function paintCard()
			for _, child in ipairs(scroller:GetChildren()) do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			order = 0
			local start = 0
			for i, entry in ipairs(ask.transcript) do
				if entry.kind == "question" then
					start = i
				end
			end
			cardTitle.Text = if ask.transcript[start] then ask.transcript[start].text else ""
			local actions = {}
			for i = start + 1, #ask.transcript do
				if ask.transcript[i].kind == "step" then
					table.insert(actions, ask.transcript[i].text)
				end
			end
			if #actions > 0 then
				chips(actions)
			end
			for i = start + 1, #ask.transcript do
				local entry = ask.transcript[i]
				if entry.kind == "answer" then
					renderAnswer(entry)
				elseif entry.kind == "error" then
					add(textBlock(inline(entry.text), 15, Enum.FontWeight.Medium, {color = Color3.fromRGB(255, 130, 120)}))
				end
			end
			card.Size = UDim2.fromOffset(if ask.expanded then 680 else SPOT_WIDTH, card.Size.Y.Offset)
			scroller.CanvasPosition = Vector2.zero
			task.defer(fitCard)
		end

		local function refocus()
			task.defer(function()
				if spotlight == open and mode ~= "busy" then
					box:CaptureFocus()
				end
			end)
		end

		-- The ripple: the ring spreads from the top middle of the card, and
		-- each part of the answer fades in as the ring reaches it
		local RIPPLE_TIME = 1.2
		local function playRipple()
			task.wait() -- (laid out by now)
			if spotlight ~= open or mode ~= "answer" then
				return
			end
			local w, h = card.Size.X.Offset, card.Size.Y.Offset
			local ratio = card.AbsoluteSize.X / w
			local radius = math.sqrt((w / 2) ^ 2 + h ^ 2) * 1.08 -- reaches the far corners
			ripple.Size = UDim2.fromOffset(0, 0)
			ripple.ImageTransparency = 0.2
			rippleGradient.Rotation = math.random(0, 359)
			tween(ripple, RIPPLE_TIME, {Size = UDim2.fromOffset(2 * radius, 2 * radius)}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(RIPPLE_TIME * 0.4, function()
				tween(ripple, RIPPLE_TIME * 0.6, {ImageTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
			local origin = card.AbsolutePosition + Vector2.new(card.AbsoluteSize.X / 2, 0)
			for _, child in ipairs(scroller:GetChildren()) do
				if child:IsA("GuiObject") then
					local parts = child:GetDescendants()
					table.insert(parts, child)
					local saved = {}
					for _, part in ipairs(parts) do
						if part:IsA("TextLabel") then
							table.insert(saved, {part, "TextTransparency", part.TextTransparency})
							part.TextTransparency = 1
						elseif part:IsA("ImageLabel") then
							table.insert(saved, {part, "ImageTransparency", part.ImageTransparency})
							part.ImageTransparency = 1
						end
						if part:IsA("GuiObject") and part.BackgroundTransparency < 1 then
							table.insert(saved, {part, "BackgroundTransparency", part.BackgroundTransparency})
							part.BackgroundTransparency = 1
						end
					end
					-- When the ring (Quad Out) gets to this part's middle
					local distance = ((child.AbsolutePosition + child.AbsoluteSize / 2 - origin) / ratio).Magnitude
					local delay = RIPPLE_TIME * (1 - math.sqrt(1 - math.min(distance / radius, 1)))
					task.delay(delay, function()
						for _, item in ipairs(saved) do
							tween(item[1], 0.4, {[item[2]] = item[3]}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
						end
					end)
				end
			end
		end

		-- Which shows: the bar (and results while there's text) with no
		-- conversation; the pill while Claude works; then the card with the bar
		-- as its bottom row
		local function refreshPanels()
			local typing = box.Text:match("%S") ~= nil
			local newMode = if ask.busy then "busy"
				elseif #ask.transcript > 0 and not typing then "answer"
				else "search" -- (typing searches, even in a conversation)
			if newMode ~= mode then
				local old = mode
				mode = newMode
				bar.Visible = mode ~= "busy"
				pill.Visible = mode == "busy"
				card.Visible = mode == "answer"
				setMerged(mode == "answer")
				if mode == "busy" then
					box:ReleaseFocus()
					pillScale.Scale = 0.6
					tween(pillScale, 0.35, {Scale = 1}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				elseif mode == "answer" then
					card.Size = UDim2.fromOffset(if ask.expanded then 680 else SPOT_WIDTH, card.Size.Y.Offset)
					card.BackgroundTransparency = 1
					tween(card, 0.3, {BackgroundTransparency = 0.03}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					fitCard()
					if old == "busy" and not quiet then
						refocus()
					end
				end
			end
			panel.Visible = mode == "search" and typing and #open.results > 0
			setPillText(if ask.topic then ask.topic else "Working")
			box.PlaceholderText = if not open.hasKey then "Search" elseif #ask.transcript > 0 then "Ask a follow-up" else "Search or Ask"
		end
		-- (a fresh Spotlight shows an answer it's already seen without the
		-- ripple; one opened for an answer that just came in ripples)
		local shownVersion = if quiet then -1 else ask.version or 0
		ask.onChange = function()
			if spotlight ~= open then
				return
			end
			local fresh = (ask.version or 0) ~= shownVersion
			if fresh then
				paintCard()
			end
			refreshPanels()
			if fresh and mode == "answer" then
				shownVersion = ask.version or 0
				task.spawn(playRipple)
			end
		end
		stopButton.MouseButton1Down:Connect(function()
			ask.stop()
			refocus()
		end)
		closeButton.MouseButton1Down:Connect(function()
			ask.clear()
			refocus()
		end)
		expandButton.MouseButton1Down:Connect(function()
			ask.expanded = not ask.expanded
			local width = if ask.expanded then 680 else SPOT_WIDTH
			tween(card, 0.25, {Size = UDim2.fromOffset(width, card.Size.Y.Offset)})
			tween(bar, 0.25, {Size = UDim2.fromOffset(width, SPOT_HEIGHT)})
			task.delay(0.27, fitCard)
			refocus()
		end)

		local measured, measuredWidth = nil, 0
		local opened = os.clock()
		table.insert(open.connections, RunService.RenderStepped:Connect(function()
			if pill.Visible then
				-- The ring of dots: about one turn a second
				local head = (os.clock() * 1.15 % 1) * math.pi * 2
				for _, dot in ipairs(dots) do
					local behind = (head - dot.angle) % (math.pi * 2)
					local t = (1 - behind / (math.pi * 2)) ^ 1.6
					dot.frame.BackgroundTransparency = 0.72 - 0.72 * t
					local size = 3 + 2.6 * t
					dot.frame.Size = UDim2.fromOffset(size, size)
				end
			end
			if not box:IsFocused() then
				caret.Visible = false
				return
			end
			-- Width of the text up to the cursor (cached until it changes)
			local cursor = box.CursorPosition
			local before = if cursor > 0 then box.Text:sub(1, cursor - 1) else box.Text
			if before ~= measured then
				measured = before
				measuredWidth = TextService:GetTextSize(before, SPOT_TEXT_SIZE, Enum.Font.Roboto, Vector2.new(10000, 200)).X
			end
			local room = (if bar.Size.X.Offset > 0 then bar.Size.X.Offset else SPOT_WIDTH) - 2 * SPOT_TEXT_LEFT
			caret.Position = UDim2.new(0, SPOT_TEXT_LEFT + math.min(measuredWidth, room) + 0.5, 0.5, 0)
			caret.Visible = true
			-- The halo breathes gently
			local breath = math.sin((os.clock() - opened) * 3)
			halo.ImageTransparency = 0.25 + 0.1 * breath
			outerHalo.ImageTransparency = 0.78 + 0.08 * breath
		end))

		local rows = {}
		local function paintRows()
			for i, row in ipairs(rows) do
				row.BackgroundTransparency = if i == open.selected then 0 else 1
			end
		end
		local function activate(item)
			if item.ask then
				-- Asking keeps Spotlight open: the Working pill takes the bar's place
				box.Text = ""
				ask.submit(item.title)
				return
			end
			closeSpotlight()
			task.spawn(item.action)
		end
		local function showResults()
			for _, row in ipairs(rows) do
				row:Destroy()
			end
			table.clear(rows)
			open.selected = 1
			-- (In a conversation the Ask row reads "Ask a follow-up", and clearing
			-- the field brings the conversation back)
			open.results = search(box.Text, open.hasKey)
			for i, item in ipairs(open.results) do
				local row = macButton(panel, {
					Size = UDim2.new(1, 0, 0, SPOT_ROW), BackgroundColor3 = C.accent, BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 3,
				})
				macCorner(row, 14)
				if item.orb then
					ask.orb(row, 24).Position = UDim2.fromOffset(10, 8)
				elseif item.tile then
					macAppTile(row, item.tile, 26).Position = UDim2.fromOffset(9, 7)
				elseif item.icon then
					macImage(row, item.icon, 20, item.iconColor or white, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0)})
				end
				macLabel(row, item.title, 15, Enum.FontWeight.Medium, white, {
					Position = UDim2.fromOffset(46, 0), Size = UDim2.new(0.62, -46, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
				})
				macLabel(row, item.kind, 12, Enum.FontWeight.Regular, white, {
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0.38, -14, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 0.4, TextTruncate = Enum.TextTruncate.AtEnd,
				})
				row.MouseEnter:Connect(function()
					open.selected = i
					paintRows()
				end)
				row.MouseButton1Down:Connect(function()
					activate(item)
				end)
				rows[i] = row
			end
			paintRows()
			refreshPanels()
		end
		table.insert(open.connections, box:GetPropertyChangedSignal("Text"):Connect(showResults))
		-- Enter opens the highlighted result; Escape, or clicking away, closes
		-- (but not while Claude is working, or when the click was on the conversation)
		table.insert(open.connections, box.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				local item = open.results[open.selected]
				if item then
					activate(item)
				else
					task.defer(function()
						if spotlight == open then
							box:CaptureFocus()
						end
					end)
				end
				return
			end
			task.delay(0.15, function()
				if spotlight ~= open or box:IsFocused() or ask.busy then
					return
				end
				local mouse = UserInputService:GetMouseLocation()
				if (card.Visible and pointIn(card, mouse)) or (pill.Visible and pointIn(pill, mouse)) then
					return
				end
				closeSpotlight()
			end)
		end))
		-- Up and Down move through the results
		table.insert(open.connections, UserInputService.InputBegan:Connect(function(input)
			if #open.results == 0 or not panel.Visible then
				return
			end
			if input.KeyCode == Enum.KeyCode.Down then
				open.selected = open.selected % #open.results + 1
				paintRows()
			elseif input.KeyCode == Enum.KeyCode.Up then
				open.selected = (open.selected - 2) % #open.results + 1
				paintRows()
			end
		end))
		paintCard()
		refreshPanels()
		if quiet then
			ask.onChange() -- (ripples the answer that just came in)
		end
		-- (a frame later, so the Space of Ctrl+Space doesn't land in the field)
		task.defer(function()
			if spotlight == open then
				box.Text = ""
				if not quiet then
					box:CaptureFocus()
				end
			end
		end)
	end

	function toggleSpotlight()
		if spotlight then
			closeSpotlight()
		elseif root.Visible then
			openSpotlight()
		end
	end
	connect(UserInputService.InputBegan, function(input)
		if input.KeyCode == Enum.KeyCode.Space and root.Visible
			and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
			toggleSpotlight()
		end
	end)

	-- ---------- Ask (Claude) ----------
	-- Spotlight's Ask sends the question to Claude (Anthropic's Messages API,
	-- with the user's own key from System Settings > Ask) along with tools for
	-- this desktop, so Claude can look at and use it: apps, windows, files,
	-- music and settings. While it works, a rainbow glow runs around the edges
	-- of the screen, like Siri's. (Its own function, to keep its many locals
	-- out of the desktop's.)
	do
		local function setUpAsk()
			local HttpService = game:GetService("HttpService")
			local API = "https://api.anthropic.com/v1/"
			local MAX_STEPS = 25

			-- Apple Intelligence's colors, for the orb and the edge glow
			ask.colors = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(188, 130, 243)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(245, 185, 234)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(141, 159, 255)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 103, 120)),
				ColorSequenceKeypoint.new(0.8, Color3.fromRGB(255, 186, 113)), ColorSequenceKeypoint.new(1, Color3.fromRGB(198, 134, 255)),
			})
			-- Claude's orb: a ball of those colors with a soft highlight.
			-- Returns it and its gradient (Spotlight spins it while Claude works).
			function ask.orb(parent, size)
				local orb = macNew("Frame", {BackgroundColor3 = white, BorderSizePixel = 0, Size = UDim2.fromOffset(size, size), Parent = parent})
				macCorner(orb, UDim.new(1, 0))
				local gradient = macNew("UIGradient", {Color = ask.colors, Rotation = 35, Parent = orb})
				local shine = macNew("Frame", {
					BackgroundColor3 = white, BackgroundTransparency = 0.5, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.38, 0.32), Size = UDim2.fromScale(0.44, 0.3), Parent = orb,
				})
				macCorner(shine, UDim.new(1, 0))
				return orb, gradient
			end

			-- ---- The rainbow edge glow ----
			-- A soft band of light just inside the screen's edges (brightest in
			-- the corners), as a white image tinted by a turning rainbow gradient
			local function edgeGlowPng()
				local size, half, radius, reach = 128, 64, 40, 60
				local rows = table.create(size)
				for y = 0, size - 1 do
					local row = table.create(size + 1)
					row[1] = "\0"
					for x = 0, size - 1 do
						-- How far inside a rounded square this pixel is
						local qx = math.abs(x + 0.5 - half) - (half - radius)
						local qy = math.abs(y + 0.5 - half) - (half - radius)
						local outside = math.sqrt(math.max(qx, 0) ^ 2 + math.max(qy, 0) ^ 2) + math.min(math.max(qx, qy), 0) - radius
						local t = math.clamp(1 + outside / reach, 0, 1)
						row[x + 2] = "\255" .. string.char(math.floor(t ^ 2.4 * 255 + 0.5))
					end
					rows[y + 1] = table.concat(row)
				end
				return macMakePng(size, size, 4, table.concat(rows)) -- 4 = gray + alpha
			end
			local function getEdgeGlow()
				local path = MACOS_FOLDER .. "/edgeglow_v1.png"
				macMadeImages.remember(path, getEdgeGlow)
				if not isfile(path) then
					ensureMacFolder()
					writefile(path, edgeGlowPng())
				end
				return getcustomasset(path)
			end
			-- The ripple that spreads through an answer as it arrives: a soft
			-- white ring (tinted by a gradient) with a faint glow inside it
			local function ripplePng()
				local size = 128
				local rows = table.create(size)
				for y = 0, size - 1 do
					local row = table.create(size + 1)
					row[1] = "\0"
					for x = 0, size - 1 do
						local r = math.sqrt((x + 0.5 - size / 2) ^ 2 + (y + 0.5 - size / 2) ^ 2) / (size / 2)
						local ring = math.exp(-((r - 0.86) / 0.07) ^ 2)
						local inside = if r < 0.86 then 0.2 * (r / 0.86) ^ 3 else 0
						local alpha = if r < 1 then math.max(ring, inside) else 0
						row[x + 2] = "\255" .. string.char(math.floor(math.clamp(alpha, 0, 1) * 255 + 0.5))
					end
					rows[y + 1] = table.concat(row)
				end
				return macMakePng(size, size, 4, table.concat(rows)) -- 4 = gray + alpha
			end
			function ask.rippleImage()
				local path = MACOS_FOLDER .. "/ripple_v1.png"
				macMadeImages.remember(path, ask.rippleImage)
				if not isfile(path) then
					ensureMacFolder()
					writefile(path, ripplePng())
				end
				return getcustomasset(path)
			end

			local glow = nil
			local function buildGlow()
				local holder = macNew("Frame", {Name = "AskGlow", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 45, Parent = gui})
				local image = getEdgeGlow()
				-- The same colors, deeper, so they hold up over a bright wallpaper
				local vivid = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(168, 92, 255)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 120, 205)),
					ColorSequenceKeypoint.new(0.4, Color3.fromRGB(96, 128, 255)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 72, 98)),
					ColorSequenceKeypoint.new(0.8, Color3.fromRGB(255, 166, 64)), ColorSequenceKeypoint.new(1, Color3.fromRGB(178, 98, 255)),
				})
				-- {reach (fraction of the screen's height), opacity, spin (degrees a second)}
				local layers = {}
				for _, spec in ipairs({{0.095, 0.6, 30}, {0.036, 1, -44}}) do
					local label = macNew("ImageLabel", {
						BackgroundTransparency = 1, Image = image, ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice,
						SliceCenter = Rect.new(63, 63, 65, 65), Size = UDim2.fromScale(1, 1), ZIndex = 45, Parent = holder,
					})
					local gradient = macNew("UIGradient", {Color = vivid, Parent = label})
					table.insert(layers, {label = label, gradient = gradient, reach = spec[1], opacity = spec[2], spin = spec[3]})
				end
				-- And a crisp line right along the edge
				local line = macNew("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ZIndex = 46, Parent = holder})
				local stroke = macStroke(line, white, 1, 2)
				local strokeGradient = macNew("UIGradient", {Color = vivid, Parent = stroke})
				local parts = holder:GetDescendants()
				table.insert(parts, holder)
				for _, item in ipairs(parts) do
					pcall(function()
						item.Interactable = false -- never in the way of a click
					end)
				end
				glow = {holder = holder, layers = layers, stroke = stroke, strokeGradient = strokeGradient, level = 0, target = 0}
			end
			local glowConnection = nil
			-- Fades the glow in or out
			local function setGlow(on)
				if not glow then
					local ok, err = pcall(buildGlow)
					if not ok then
						warn("[coolui] Ask glow failed: " .. tostring(err))
						return
					end
				end
				glow.target = if on then 1 else 0
				glow.holder.Visible = true
				if glowConnection then
					return
				end
				local started = os.clock()
				glowConnection = connect(RunService.RenderStepped, function(dt)
					glow.level += math.clamp(glow.target - glow.level, -dt * 2.2, dt * 2.2)
					local t = os.clock() - started
					local height = gui.AbsoluteSize.Y
					local pulse = 0.5 + 0.5 * math.sin(t * 2.3)
					for _, layer in ipairs(glow.layers) do
						-- (the image's glow is 60 pixels deep)
						layer.label.SliceScale = layer.reach * height * (0.92 + 0.08 * pulse) / 60
						layer.gradient.Rotation = (t * layer.spin) % 360
						layer.label.ImageTransparency = 1 - glow.level * layer.opacity * (0.85 + 0.15 * pulse)
					end
					glow.strokeGradient.Rotation = (t * 60) % 360
					glow.stroke.Transparency = 1 - glow.level * 0.85
					if glow.level <= 0 and glow.target == 0 then
						glow.holder.Visible = false
						glowConnection:Disconnect()
						glowConnection = nil
					end
				end)
			end

			-- ---- Talking to Anthropic ----
			-- Text as a JSON string (bytes that aren't UTF-8 become "?")
			local escapes = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
			local function jsonString(text)
				text = tostring(text)
				if utf8.len(text) == nil then
					text = text:gsub("[\128-\255]", "?")
				end
				return '"' .. text:gsub('[%c"\\]', function(c)
					return escapes[c] or string.format("\\u%04x", string.byte(c))
				end) .. '"'
			end
			-- Claude's replies go back into the conversation exactly as they came
			-- (thinking blocks must stay untouched), so their JSON is cut out of
			-- the response as text rather than decoded and encoded again
			local function skipString(json, i)
				i += 1
				while true do
					local at = json:find('["\\]', i)
					if not at then
						return #json + 1
					elseif json:sub(at, at) == "\\" then
						i = at + 2
					else
						return at + 1
					end
				end
			end
			local function skipValue(json, i)
				local c = json:sub(i, i)
				if c == '"' then
					return skipString(json, i)
				elseif c == "{" or c == "[" then
					local depth = 0
					while i <= #json do
						local at = json:find('[{}%[%]"]', i)
						if not at then
							return #json + 1
						end
						local ch = json:sub(at, at)
						if ch == '"' then
							i = skipString(json, at)
						else
							depth += if ch == "{" or ch == "[" then 1 else -1
							i = at + 1
							if depth == 0 then
								return i
							end
						end
					end
					return i
				end
				return json:find("[,}%]%s]", i) or #json + 1 -- a number, true, false or null
			end
			-- The raw JSON of one field of the top-level object
			local function rawField(json, key)
				local i = json:find("{", 1, true)
				if not i then
					return nil
				end
				i += 1
				while true do
					i = json:find("%S", i)
					if not i then
						return nil
					end
					local c = json:sub(i, i)
					if c == "," then
						i += 1
					elseif c ~= '"' then
						return nil
					else
						local nameEnd = skipString(json, i)
						local name = json:sub(i + 1, nameEnd - 2)
						local colon = json:find(":", nameEnd, true)
						if not colon then
							return nil
						end
						local start = json:find("%S", colon + 1)
						if not start then
							return nil
						end
						local finish = skipValue(json, start)
						if name == key then
							return json:sub(start, finish - 1)
						end
						i = finish
					end
				end
			end

			-- One request to the API; returns the decoded reply and its raw text,
			-- or nil and what went wrong (never the key)
			local function call(key, path, body)
				local send = (syn and syn.request) or http_request or request or (http and http.request)
				if not send then
					return nil, "This executor can't make web requests, so Ask can't reach Claude."
				end
				local ok, response = pcall(send, {
					Url = API .. path, Method = if body then "POST" else "GET", Body = body,
					Headers = {
						["Content-Type"] = "application/json",
						["x-api-key"] = key,
						["anthropic-version"] = "2026-10-21",
						-- lets Anthropic rerun a declined request on a fallback model
						["anthropic-beta"] = "server-side-fallback-2026-07-01",
					},
				})
				if not ok or type(response) ~= "table" then
					return nil, "Couldn't reach Claude. Check your connection and try again."
				end
				local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, response.Body or "")
				if not decodedOk then
					decoded = nil
				end
				local status = tonumber(response.StatusCode) or 0
				if status ~= 200 then
					local detail = if type(decoded) == "table" and type(decoded.error) == "table" then tostring(decoded.error.message or "") else ""
					if status == 401 then
						return nil, "Anthropic didn't accept the API key. Check it in System Settings > Ask.", status
					elseif status == 429 then
						return nil, "Too many requests just now. Try again in a moment."
					elseif status >= 500 then
						return nil, "Claude is busy right now. Try again in a moment."
					end
					return nil, string.format("Claude couldn't answer (%d)%s", status, if detail ~= "" then ": " .. detail else ".")
				end
				if type(decoded) ~= "table" then
					return nil, "Claude's reply couldn't be read."
				end
				return decoded, response.Body
			end

			-- Whether a key works, from Anthropic's model list (free to ask)
			function ask.checkKey(key)
				local reply, problem, status = call(key, "models?limit=1", nil)
				if status == 401 then
					problem = "Anthropic didn't accept that key. Check you copied all of it."
				end
				return reply ~= nil, problem
			end

			-- ---- What Claude can do ----
			local appNames = {trash = "the Trash", about = "About This Mac"}
			for _, app in ipairs(MAC_APPS) do
				appNames[app.id] = app.name
			end
			local TOOLS = [==[[
{"name":"get_desktop_state","description":"What's on the screen now: the open windows (front first, with the ids window_action takes), the focused one, Light or Dark appearance, the background, Wi-Fi and ping, what Music is playing, the time and the screen size.","input_schema":{"type":"object","properties":{}}},
{"name":"open_app","description":"Opens an app, or brings it to the front if it's already open. trash opens the Trash in Finder; about opens About This Mac.","input_schema":{"type":"object","properties":{"app":{"type":"string","enum":["finder","notes","chat","terminal","music","youtube","timer","settings","trash","about"]},"settings_pane":{"type":"string","enum":["Wi-Fi","Battery","General","Appearance","Wallpaper","Ask","About"],"description":"For settings: which pane to show."}},"required":["app"]}},
{"name":"window_action","description":"Focuses, closes, minimizes, restores (un-minimizes) or zooms a window. Window ids come from get_desktop_state.","input_schema":{"type":"object","properties":{"window_id":{"type":"integer"},"action":{"type":"string","enum":["focus","close","minimize","restore","zoom"]}},"required":["window_id","action"]}},
{"name":"list_folder","description":"Lists a folder in the workspace (what Finder shows). Paths are relative to the workspace with forward slashes; an empty path is the workspace itself.","input_schema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},
{"name":"search_files","description":"Finds files and folders in the workspace (a few levels deep) whose names contain the text.","input_schema":{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}},
{"name":"read_file","description":"Reads a text file in the workspace (up to 30,000 characters).","input_schema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},
{"name":"write_file","description":"Writes a text file in the workspace, making it (and its folders) if needed. overwrite replaces what's in the file, so only overwrite an existing file when the user asked for that; append adds to the end.","input_schema":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"},"mode":{"type":"string","enum":["overwrite","append"]}},"required":["path","content","mode"]}},
{"name":"open_file","description":"Opens a file or folder in the app that shows it: text in Notes, images in Preview, audio in Music, folders in Finder.","input_schema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},
{"name":"music","description":"Controls the Music app, opening it if needed: play (a song or a whole category whose name contains song, or carry on), pause, next, previous, or status. Returns what's playing, the categories and every song.","input_schema":{"type":"object","properties":{"command":{"type":"string","enum":["play","pause","next","previous","status"]},"song":{"type":"string","description":"For play: part of a song's name, or a category's (like lofi) to play all of it."}},"required":["command"]}},
{"name":"change_setting","description":"Changes a setting. appearance: light or dark. background: wallpaper (the Tahoe wallpaper) or scene (the live 3D game world behind the desktop). wifi: on or off (off shows Ethernet). startup_screen: on or off (the Apple logo screen when macOS loads).","input_schema":{"type":"object","properties":{"setting":{"type":"string","enum":["appearance","background","wifi","startup_screen"]},"value":{"type":"string","enum":["light","dark","wallpaper","scene","on","off"]}},"required":["setting","value"]}},
{"name":"system_action","description":"Locks the screen, or shows the user the confirmation for Sleep, Restart or Shut Down (they can cancel). If it goes ahead, that's the end of your turn.","input_schema":{"type":"object","properties":{"action":{"type":"string","enum":["lock_screen","sleep","restart","shut_down"]}},"required":["action"]}},
{"name":"copy_to_clipboard","description":"Puts text on the user's clipboard.","input_schema":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}},
{"name":"start_timer","description":"Starts a countdown in the Timer app. When it's done the user hears a chime and sees a banner.","input_schema":{"type":"object","properties":{"seconds":{"type":"integer","description":"How long, in seconds (1 to 86399)."}},"required":["seconds"]}},
{"name":"youtube","description":"Opens the YouTube app on a search or a YouTube link. With play true it plays the top result (or the link). kind picks videos, Shorts or live streams. Watching needs the YouTube helper running on the user's PC; if it isn't, the app shows how to start it.","input_schema":{"type":"object","properties":{"query":{"type":"string","description":"What to search for, or a YouTube link."},"kind":{"type":"string","enum":["video","shorts","live"]},"play":{"type":"boolean"}},"required":["query"]}}
]]==]
			-- What the panel says while each tool runs
			local working = {
				get_desktop_state = "Looking at the desktop…", open_app = "Opening an app…", window_action = "Arranging windows…",
				list_folder = "Looking through files…", search_files = "Searching files…", read_file = "Reading a file…",
				write_file = "Writing a file…", open_file = "Opening a file…", music = "Using Music…",
				change_setting = "Changing a setting…", system_action = "Waiting for you…", copy_to_clipboard = "Copying…",
				youtube = "Opening YouTube…", start_timer = "Setting a timer…",
			}

			local function systemPrompt(useTools, useWeb)
				local now = DateTime.now():FormatLocalTime("dddd, MMMM D, YYYY h:mm A", "en-us")
				return table.concat({
					"You are Claude, built into \"macOS in Roblox\": a recreation of macOS Tahoe that runs as a script inside the Roblox game \""
						.. macGameName() .. "\". The user opened you from Spotlight's Ask. It's " .. now .. ". The user is "
						.. player.DisplayName .. " (@" .. player.Name .. ").",
					"",
					if useTools then "You can see and use this macOS with your tools: open apps (Finder, Notes, Chat, Terminal, Music, YouTube, Timer, System Settings), play YouTube videos, Shorts and live streams, set timers, arrange windows, list, search, read, write and open files in the executor's workspace folder (what Finder shows), play music, change settings and copy text. When the user asks you to do something on the computer, do it with the tools, then say briefly what you did. For questions you can answer yourself, just answer."
						else "The user has turned off your access to the desktop, so you can only answer.",
					"",
					if useWeb then "You can search the web for anything current or that you're unsure of; the card shows the sites you cite." else "You can't search the web.",
					"",
					"Your reply shows in a card under the Spotlight bar. Start with a direct answer in a short paragraph. When a list helps, follow it with a short \"# \" heading and a few \"- \" bullets that each start with a **bold** term. **Bold**, `code` and links work (links show underlined but can't be clicked); tables and images don't. Keep it brief: the card is small.",
					"",
					"Good to know: Notes saves to coolui_assets/Notes.txt. Songs are the audio files in coolui_music, sorted into categories: each folder in it is one (they can nest), with an info.json for its title, image and description. Sleep, Restart and Shut Down always ask the user first. You can't see the 3D game itself, only this desktop.",
				}, "\n")
			end

			-- Windows get small ids for Claude, the first time it sees them
			local nextWindowId = 0
			local function windowId(win)
				if not win.askId then
					nextWindowId += 1
					win.askId = nextWindowId
				end
				return win.askId
			end
			local function musicWindow()
				for i = #windows, 1, -1 do
					local win = windows[i]
					if win.app == "music" and not win.closed and win.control then
						return win
					end
				end
				return nil
			end
			local function fileName(path)
				return path:match("([^/]+)$") or path
			end
			-- A workspace path, tidied; nothing outside the workspace, and never the key
			local function cleanPath(path)
				path = tostring(path or ""):gsub("\\", "/"):gsub("^%./", ""):gsub("^/+", ""):gsub("/+$", "")
				for part in path:gmatch("[^/]+") do
					if part == ".." then
						error("Paths can't leave the workspace.", 0)
					end
				end
				if path:lower() == macClaudeKey.file:lower() then
					error("That file holds the user's API key, so it's off limits.", 0)
				end
				return path
			end

			local function desktopState()
				local out = {}
				local network = macReadNetwork()
				local screen = gui.AbsoluteSize
				table.insert(out, "Time: " .. DateTime.now():FormatLocalTime("dddd, MMMM D, YYYY h:mm A", "en-us"))
				table.insert(out, "Appearance: " .. appearance .. "; background: " .. (if session.mode == "scene" then "the 3D scene" else "the wallpaper"))
				table.insert(out, "Wi-Fi: " .. (if network.wifiOn then "on, network \"" .. macGameName() .. "\"" else "off (Ethernet)")
					.. "; ping: " .. (if network.ping then network.ping .. " ms" else "unknown"))
				table.insert(out, string.format("Screen: %d x %d pixels", screen.X, screen.Y))
				local music = musicWindow()
				local status = if music then music.control("status") else nil
				table.insert(out, "Music: " .. (if status and status.track then (if status.playing then "playing \"" else "paused on \"") .. status.track .. "\"" else "not playing"))
				local listed = 0
				for i = #windows, 1, -1 do
					local win = windows[i]
					if not win.closed then
						if listed == 0 then
							table.insert(out, "Windows, front first:")
						end
						listed += 1
						table.insert(out, string.format("- id %d: %s, \"%s\"%s%s", windowId(win), appNames[win.app] or MAC_APP_NAMES[win.app] or win.app,
							win.title or "", if win.minimized then " (minimized)" else "", if win == frontWindow and not win.minimized then " (focused)" else ""))
					end
				end
				if listed == 0 then
					table.insert(out, "Windows: none open")
				end
				return table.concat(out, "\n")
			end

			-- Runs one tool; returns the result for Claude and a line for the panel
			local function runTool(name, input)
				input = if type(input) == "table" then input else {}
				if name == "get_desktop_state" then
					return desktopState(), "Looked at the desktop"
				elseif name == "open_app" then
					local app = tostring(input.app)
					if not appNames[app] then
						error("There's no app called " .. app, 0)
					end
					local pane = if app == "settings" and type(input.settings_pane) == "string" then input.settings_pane else nil
					openApp(app, if pane then {pane = pane} else nil)
					local label = if pane then "System Settings > " .. pane else appNames[app]
					return "Opened " .. label, "Opened " .. label
				elseif name == "window_action" then
					local id = tonumber(input.window_id)
					local win = nil
					for _, candidate in ipairs(windows) do
						if not candidate.closed and candidate.askId == id then
							win = candidate
						end
					end
					if not win then
						error("No open window has id " .. tostring(input.window_id) .. ". get_desktop_state lists them.", 0)
					end
					local action = input.action
					local verbs = {focus = "Brought forward", close = "Closed", minimize = "Minimized", restore = "Restored", zoom = "Zoomed"}
					if not verbs[action] then
						error("Unknown window action: " .. tostring(action), 0)
					end
					if action == "focus" or action == "restore" then
						if win.minimized then
							win.restore()
						else
							focusWindow(win)
						end
					elseif action == "close" then
						win.close()
					elseif action == "minimize" then
						if not win.minimized then
							win.minimize()
						end
					else
						win.zoom()
					end
					local title = if win.title ~= "" then win.title else appNames[win.app] or win.app
					return verbs[action] .. " \"" .. title .. "\"", verbs[action] .. " " .. title
				elseif name == "list_folder" then
					local path = cleanPath(input.path)
					if path ~= "" and not isfolder(path) then
						error("There's no folder at \"" .. path .. "\"", 0)
					end
					local entries = macListFolder(path)
					local out = {}
					for i, entry in ipairs(entries) do
						if i > 300 then
							table.insert(out, "… and " .. (#entries - 300) .. " more")
							break
						end
						table.insert(out, (if entry.folder then "[folder] " else "") .. entry.path)
					end
					return if #out == 0 then "(empty)" else table.concat(out, "\n"), "Looked in " .. (if path == "" then "the workspace" else fileName(path))
				elseif name == "search_files" then
					local query = tostring(input.query or ""):lower()
					if query == "" then
						error("Give some text to search for", 0)
					end
					if not fileIndex or os.clock() - indexedAt > 30 then
						indexFiles()
					end
					while indexing do
						task.wait()
					end
					local out = {}
					for _, entry in ipairs(fileIndex or {}) do
						if entry.name:lower():find(query, 1, true) then
							table.insert(out, (if entry.folder then "[folder] " else "") .. entry.path)
							if #out >= 40 then
								break
							end
						end
					end
					return if #out == 0 then "Nothing found" else table.concat(out, "\n"), "Searched for “" .. tostring(input.query) .. "”"
				elseif name == "read_file" then
					local path = cleanPath(input.path)
					if not isfile(path) then
						error("There's no file at \"" .. path .. "\"", 0)
					end
					local text = readfile(path)
					local length = utf8.len(text)
					if length == nil then
						error(string.format("\"%s\" isn't a text file (%d bytes)", path, #text), 0)
					end
					if length > 30000 then
						text = text:sub(1, utf8.offset(text, 30001) - 1) .. string.format("\n[…cut off here: the file has %d characters]", length)
					end
					return text, "Read " .. fileName(path)
				elseif name == "write_file" then
					local path = cleanPath(input.path)
					if path == "" or isfolder(path) then
						error("Give the path of a file", 0)
					end
					if path:lower() == MAC_SETTINGS_FILE:lower() then
						error("That's macOS's own settings file; use change_setting instead.", 0)
					end
					local folder = nil
					for part in path:gmatch("([^/]+)/") do
						folder = if folder then folder .. "/" .. part else part
						if not isfolder(folder) then
							makefolder(folder)
						end
					end
					local content = tostring(input.content or "")
					local appending = input.mode == "append" and isfile(path)
					writefile(path, if appending then readfile(path) .. content else content)
					return string.format("Saved %s (%d characters %s)", path, utf8.len(content) or #content, if appending then "added" else "in all"),
						(if appending then "Added to " else "Wrote ") .. fileName(path)
				elseif name == "open_file" then
					local path = cleanPath(input.path)
					local isFolder = path == "" or isfolder(path)
					if not isFolder and not isfile(path) then
						error("There's nothing at \"" .. path .. "\"", 0)
					end
					openFile({path = path, name = fileName(path), folder = isFolder})
					return "Opened " .. (if path == "" then "the workspace" else path), "Opened " .. (if path == "" then "the workspace" else fileName(path))
				elseif name == "music" then
					local command = tostring(input.command)
					local win = musicWindow()
					if not win then
						if command == "pause" or command == "status" then
							return "Music isn't open, so nothing is playing.", "Checked Music"
						end
						openApp("music")
						win = musicWindow()
					end
					if not win then
						error("Music didn't open", 0)
					end
					local status, problem = win.control(command, input.song)
					if not status then
						error(problem, 0)
					end
					local songs = if #status.songs > 0 then table.concat(status.songs, ", ") else "none (put mp3 files in coolui_music or its category folders)"
					local now = if status.track then (if status.playing then "Playing \"" else "Paused on \"") .. status.track .. "\"" else "Not playing"
					if status.categories and #status.categories > 0 then
						songs = songs .. "\nCategories: " .. table.concat(status.categories, ", ")
					end
					local line = if command == "pause" then "Paused Music"
						elseif command == "status" then "Checked Music"
						elseif status.track then "Playing “" .. status.track .. "”"
						else "Opened Music"
					return now .. "\nSongs: " .. songs, line
				elseif name == "change_setting" then
					local setting, value = input.setting, input.value
					if setting == "appearance" and (value == "light" or value == "dark") then
						desktop.setAppearance(value)
						return "Appearance is now " .. value, "Switched to " .. (if value == "dark" then "Dark" else "Light") .. " Mode"
					elseif setting == "background" and (value == "wallpaper" or value == "scene") then
						if session.mode ~= value then
							session.setBackground(value, true)
						end
						local label = if value == "scene" then "the 3D scene" else "the wallpaper"
						return "The background is now " .. label, "Switched the background to " .. label
					elseif setting == "wifi" and (value == "on" or value == "off") then
						macSetWifi(value == "on")
						return "Wi-Fi is now " .. value, "Turned Wi-Fi " .. value
					elseif setting == "startup_screen" and (value == "on" or value == "off") then
						macSettings.startupScreen = value == "on"
						saveMacSettings()
						return "The startup screen is now " .. value, "Turned the startup screen " .. value
					end
					error("Can't set " .. tostring(setting) .. " to " .. tostring(value), 0)
				elseif name == "system_action" then
					local action = input.action
					if action == "lock_screen" then
						ask.endTurn = true
						closeSpotlight()
						finish("lock")
						return "The screen is locked.", "Locked the screen"
					end
					local confirmations = {sleep = confirmSleep, restart = confirmRestart, shut_down = confirmShutDown}
					local labels = {sleep = "Sleep", restart = "Restart", shut_down = "Shut Down"}
					if not confirmations[action] then
						error("Unknown action: " .. tostring(action), 0)
					end
					-- The alert sits under Spotlight, so Spotlight gets out of the way
					closeSpotlight()
					confirmations[action]()
					if pendingAction then
						ask.endTurn = true
						return "The user confirmed " .. labels[action] .. ".", labels[action] .. ": confirmed"
					end
					return "The user cancelled " .. labels[action] .. ".", labels[action] .. ": cancelled"
				elseif name == "copy_to_clipboard" then
					setclipboard(tostring(input.text or ""))
					return "Copied.", "Copied to the clipboard"
				elseif name == "start_timer" then
					local seconds = math.floor(tonumber(input.seconds) or 0)
					if seconds < 1 or seconds > 86399 then
						error("Give between 1 and 86399 seconds", 0)
					end
					openApp("timer", {seconds = seconds})
					local h, m, sec = seconds // 3600, seconds // 60 % 60, seconds % 60
					local label = (if h > 0 then h .. "h " else "") .. (if m > 0 then m .. "m " else "") .. (if sec > 0 then sec .. "s" else "")
					return "Started a " .. label:match("^%s*(.-)%s*$") .. " timer.", "Set a " .. label:match("^%s*(.-)%s*$") .. " timer"
				elseif name == "youtube" then
					local query = tostring(input.query or "")
					if not query:match("%S") then
						error("Give something to search for, or a link", 0)
					end
					local kind = if input.kind == "shorts" or input.kind == "live" then input.kind else "video"
					openApp("youtube", {query = query, kind = kind, autoplay = input.play == true})
					return "Opened YouTube on “" .. query .. "”" .. (if input.play == true then " and started the top result (if the helper is running)." else "."),
						(if input.play == true then "Playing “" else "Searched YouTube for “") .. query .. "”"
				end
				error("There's no tool called " .. tostring(name), 0)
			end

			-- ---- The conversation ----
			local function changed()
				if ask.onChange then
					task.spawn(ask.onChange)
				end
			end
			local function note(kind, text)
				table.insert(ask.transcript, {kind = kind, text = text})
				ask.version = (ask.version or 0) + 1
				changed()
			end
			-- Forget everything after message `count` (a turn that didn't finish
			-- can't stay in the conversation)
			local function rewind(count)
				for i = #ask.messages, count + 1, -1 do
					table.remove(ask.messages, i)
				end
			end

			-- Claude, then its tools, then Claude again, until it answers
			-- The desktop's tools, plus Anthropic's web search (it runs on their side)
			local WEB_SEARCH = '{"type":"web_search_20260209","name":"web_search"}'
			local function toolsJson()
				if ask.useTools and ask.useWeb then
					return TOOLS:gsub("%]%s*$", "," .. WEB_SEARCH .. "]")
				elseif ask.useTools then
					return TOOLS
				elseif ask.useWeb then
					return "[" .. WEB_SEARCH .. "]"
				end
				return nil
			end

			local function converse(key, checkpoint)
				local tools = toolsJson()
				for _ = 1, MAX_STEPS do
					local body = '{"model":"claude-opus-5-5","max_tokens":16000,"output_config":{"effort":"medium"},"fallbacks":"default",'
						.. '"cache_control":{"type":"ephemeral"},"system":' .. jsonString(ask.system)
						.. (if tools then ',"tools":' .. tools else "")
						.. ',"messages":[' .. table.concat(ask.messages, ",") .. "]}"
					local reply, raw = call(key, "messages", body)
					if ask.stopped or not alive then
						rewind(checkpoint)
						note("step", "Stopped")
						return
					end
					if not reply then
						rewind(checkpoint)
						note("error", raw)
						return
					end
					local content = rawField(raw, "content")
					if not content then
						rewind(checkpoint)
						note("error", "Claude's reply couldn't be read.")
						return
					end
					-- Text comes in runs split by tool blocks (citations cut a sentence
					-- into several text blocks, so a run is joined as it is). The last
					-- run is the answer; the sites it cites are its sources.
					local runs, current, uses = {}, {}, {}
					local sources, seen = {}, {}
					for _, block in ipairs(reply.content or {}) do
						if block.type == "text" and type(block.text) == "string" then
							table.insert(current, block.text)
							for _, cite in ipairs(if type(block.citations) == "table" then block.citations else {}) do
								local site = type(cite) == "table" and type(cite.url) == "string" and cite.url:match("^%a+://([^/:?#]+)")
								site = site and site:gsub("^www%.", "")
								if site and not seen[site] then
									seen[site] = true
									table.insert(sources, site)
								end
							end
						else
							if #current > 0 then
								table.insert(runs, table.concat(current))
								current = {}
							end
							if block.type == "tool_use" then
								table.insert(uses, block)
							elseif block.type == "server_tool_use" and block.name == "web_search" and type(block.input) == "table" then
								note("step", "Searched “" .. tostring(block.input.query or "the web") .. "”")
							end
						end
					end
					if #current > 0 then
						table.insert(runs, table.concat(current))
					end
					local said = (runs[#runs] or ""):match("^%s*(.-)%s*$")
					local stop = reply.stop_reason
					if stop == "tool_use" and #uses > 0 then
						table.insert(ask.messages, '{"role":"assistant","content":' .. content .. "}")
						if said ~= "" then
							note("note", said)
						end
						local results = {}
						for _, use in ipairs(uses) do
							local ok, result, line
							if ask.stopped then
								ok, result = false, "The user stopped this."
							else
								ask.status = working[use.name] or "Working…"
								changed()
								ok, result, line = pcall(runTool, use.name, use.input)
								if ok then
									note("step", line or use.name)
								end
							end
							table.insert(results, '{"type":"tool_result","tool_use_id":' .. jsonString(use.id) .. ',"content":'
								.. jsonString(if ok then result else tostring(result)) .. (if ok then "" else ',"is_error":true') .. "}")
						end
						if ask.stopped or not alive then
							rewind(checkpoint)
							note("step", "Stopped")
							return
						end
						if ask.endTurn then
							-- Locked, asleep, restarting or shutting down: next time is a new chat
							ask.messages = {}
							return
						end
						table.insert(ask.messages, '{"role":"user","content":[' .. table.concat(results, ",") .. "]}")
						ask.status = "Thinking…"
						changed()
					elseif stop == "pause_turn" then
						-- (the API paused a long turn; sending it back carries on)
						table.insert(ask.messages, '{"role":"assistant","content":' .. content .. "}")
					elseif stop == "refusal" then
						rewind(checkpoint)
						note("error", if said ~= "" then said else "Claude can't help with that one.")
						return
					elseif stop == "max_tokens" then
						rewind(checkpoint)
						note("answer", (if said ~= "" then said .. "\n\n" else "") .. "(The answer ran too long and was cut off.)")
						return
					else
						if content:match("^%[%s*%]$") then
							rewind(checkpoint)
						else
							table.insert(ask.messages, '{"role":"assistant","content":' .. content .. "}")
						end
						table.insert(ask.transcript, {kind = "answer", text = if said ~= "" then said else "Done.", sources = sources})
					ask.version = (ask.version or 0) + 1
						changed()
						return
					end
				end
				-- Too many steps: the conversation ends on tool results, so start over next time
				ask.messages = {}
				note("error", "Stopped after " .. MAX_STEPS .. " steps.")
			end

			-- A few words on what the question is about, for the Working pill.
			-- Claude Haiku 5.5 with thinking off answers in about a second.
			local TOPIC_PROMPT = "You label requests for a small status pill. Reply with only a title of 1 to 4 words for what the user's message is about, in sentence case, with no quotes and no full stop. Examples: Professional audio editors / Opening Notes / Weather in Paris / Writing a poem"
			local function fetchTopic(key, question, id)
				local body = '{"model":"claude-haiku-5-5","max_tokens":60,"thinking":{"type":"disabled"},"output_config":{"effort":"low"},'
					.. '"system":' .. jsonString(TOPIC_PROMPT) .. ',"messages":[{"role":"user","content":' .. jsonString(question) .. "}]}"
				local reply = call(key, "messages", body)
				if not reply or ask.requestId ~= id or not ask.busy then
					return
				end
				local text = ""
				for _, block in ipairs(reply.content or {}) do
					if block.type == "text" and type(block.text) == "string" then
						text ..= block.text
					end
				end
				text = text:gsub("%s+", " "):match("^%s*[\"'“]?(.-)[\"'”%.]?%s*$") or ""
				if text ~= "" and utf8.len(text) and utf8.len(text) <= 40 then
					ask.topic = text
					changed()
				end
			end

			function ask.submit(question)
				question = tostring(question):match("^%s*(.-)%s*$")
				if ask.busy or question == "" then
					return
				end
				local key = macClaudeKey.read()
				if not key then
					note("error", "Add your Claude API key in System Settings > Ask first.")
					return
				end
				if #ask.messages == 0 then
					ask.useTools = macSettings.askTools ~= false
					ask.useWeb = macSettings.askWeb ~= false
					ask.system = systemPrompt(ask.useTools, ask.useWeb)
				end
				ask.busy, ask.stopped, ask.endTurn = true, false, false
				ask.requestId = (ask.requestId or 0) + 1
				ask.topic = nil
				task.spawn(fetchTopic, key, question, ask.requestId)
				ask.status = "Thinking…"
				ask.lastActivity = os.clock()
				local checkpoint = #ask.messages
				table.insert(ask.messages, '{"role":"user","content":' .. jsonString(question) .. "}")
				note("question", question)
				setGlow(true)
				task.spawn(function()
					local ok, err = pcall(converse, key, checkpoint)
					if not ok then
						warn("[coolui] Ask failed: " .. tostring(err))
						rewind(checkpoint)
						note("error", "Something went wrong: " .. tostring(err))
					end
					ask.busy = false
					ask.status = ""
					ask.lastActivity = os.clock()
					setGlow(false)
					changed()
					-- If Spotlight was closed meanwhile, it comes back with the answer
					if alive and root.Visible and not spotlight and not ask.endTurn then
						openSpotlight(true)
					end
				end)
			end

			function ask.stop()
				if ask.busy then
					ask.stopped = true
					ask.status = "Stopping…"
					ask.topic = "Stopping…"
					changed()
				end
			end

			function ask.clear()
				if ask.busy then
					return
				end
				table.clear(ask.transcript)
				ask.version = (ask.version or 0) + 1
				ask.messages = {}
				changed()
			end
		end
		setUpAsk()
	end

	-- Light or Dark. Every color on the desktop that's in the old palette is
	-- swapped for the new palette's (see MAC_PALETTES), so open windows change
	-- along with everything built from now on.
	local function colorKey(color)
		return math.round(color.R * 255) .. "," .. math.round(color.G * 255) .. "," .. math.round(color.B * 255)
	end
	function desktop.setAppearance(name)
		if name == appearance or not MAC_PALETTES[name] then
			return
		end
		local swap = {}
		for key, value in pairs(MAC_PALETTES[name]) do
			swap[colorKey(MAC_PALETTES[appearance][key])] = value
		end
		appearance = name
		macUsePalette(name)
		macSettings.appearance = name
		saveMacSettings()
		local function remap(instance, property)
			local new = swap[colorKey(instance[property])]
			if new then
				instance[property] = new
			end
		end
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("GuiObject") then
				remap(item, "BackgroundColor3")
				if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
					remap(item, "TextColor3")
					if item:IsA("TextBox") then
						remap(item, "PlaceholderColor3")
					end
				elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
					remap(item, "ImageColor3")
				elseif item:IsA("ScrollingFrame") then
					remap(item, "ScrollBarImageColor3")
				end
			elseif item:IsA("UIStroke") then
				remap(item, "Color")
			end
		end
		MENU_STYLE.ink, MENU_STYLE.soft, MENU_STYLE.line = C.ink, C.inkSoft, C.line
		for _, win in ipairs(windows) do
			win.paintLights()
		end
	end

	-- Shows the desktop and waits for Lock Screen, Log Out, Sleep, Restart or
	-- Shut Down; returns which one
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
		-- After Restart or Shut Down with "Reopen windows" ticked
		if desktop.reopenList then
			local list = desktop.reopenList
			desktop.reopenList = nil
			task.delay(0.5, reopenWindows, list)
		end

		repeat
			task.wait()
		until pendingAction or not alive

		local action = pendingAction or "shutdown"
		closeMenu()
		closeSpotlight()
		tooltip.Visible = false
		drag = nil
		resize = nil
		UserInputService.MouseIcon = ""
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

-- Sleep: hides macOS and gives the game back (see sleepScene) until "Wake
-- macOS" in the top-left corner is clicked. Returns with the screen black, for
-- the lock screen to fade in from. Unless session.keepRunning (the Sleep
-- alert's checkbox), the Music app pauses until then.
local function macSleep(session)
	local sleepGui = Instance.new("ScreenGui")
	sleepGui.Name = "coolui_sleep"
	sleepGui.IgnoreGuiInset = true
	sleepGui.ResetOnSpawn = false
	sleepGui.DisplayOrder = 1005
	sleepGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sleepGui.Parent = player:WaitForChild("PlayerGui")
	local black = Instance.new("Frame")
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Size = UDim2.fromScale(1, 1)
	black.ZIndex = 5
	black.Parent = sleepGui
	local function fadeBlack(transparency, time)
		local fade = TweenService:Create(black, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {BackgroundTransparency = transparency})
		fade:Play()
		fade.Completed:Wait()
	end

	-- The screen goes dark, macOS goes away, and the game fades in
	fadeBlack(0, 0.5)
	local paused = {}
	if not session.keepRunning then
		for _, sound in game:GetService("SoundService"):GetChildren() do
			if sound.Name == "coolui_mac_music" and sound:IsA("Sound") and sound.IsPlaying then
				sound:Pause()
				table.insert(paused, sound)
			end
		end
	end
	session.gui.Enabled = false
	ScreenGui.Enabled = false
	sleepScene()
	task.wait(0.25)
	fadeBlack(1, 0.6)

	-- "Wake macOS", in the middle of the top bar (games put their own buttons
	-- next to Roblox's on the left)
	local wake = Instance.new("TextButton")
	wake.Name = "Wake"
	wake.AutoButtonColor = false
	wake.Text = ""
	wake.BackgroundColor3 = Color3.fromRGB(18, 18, 21)
	wake.BackgroundTransparency = 1
	wake.AutomaticSize = Enum.AutomaticSize.X
	wake.Size = UDim2.fromOffset(0, 44)
	wake.ZIndex = 2
	wake.Parent = sleepGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = wake
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = wake
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = wake
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = MAC_DESKTOP_ICONS.apple
	icon.ImageTransparency = 1
	icon.Size = UDim2.fromOffset(20, 20)
	icon.LayoutOrder = 1
	icon.ZIndex = 3
	icon.Parent = wake
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = macFont(Enum.FontWeight.SemiBold)
	label.Text = "Wake macOS"
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 44)
	label.LayoutOrder = 2
	label.ZIndex = 3
	label.Parent = wake
	local GuiService = game:GetService("GuiService")
	wake.AnchorPoint = Vector2.new(0.5, 0)
	local function place()
		local inset = GuiService.TopbarInset
		wake.Position = UDim2.new(0.5, 0, 0, if inset.Height > 44 then (inset.Height - 44) / 2 else 8)
	end
	place()
	local insetChanged = GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
	local show = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(wake, show, {BackgroundTransparency = 0.3}):Play()
	TweenService:Create(icon, show, {ImageTransparency = 0}):Play()
	TweenService:Create(label, show, {TextTransparency = 0}):Play()
	wake.MouseEnter:Connect(function()
		wake.BackgroundTransparency = 0.12
	end)
	wake.MouseLeave:Connect(function()
		wake.BackgroundTransparency = 0.3
	end)
	local woken = false
	wake.MouseButton1Click:Connect(function()
		woken = true
	end)
	repeat
		task.wait()
	until woken
	insetChanged:Disconnect()
	wake:Destroy()

	-- Dark again, the scene comes back, and macOS waits behind black
	fadeBlack(0, 0.4)
	wakeScene({[ScreenGui] = true, [session.gui] = true, [sleepGui] = true})
	session.cover.BackgroundTransparency = 0
	session.gui.Enabled = true
	ScreenGui.Enabled = true
	for _, sound in ipairs(paused) do
		if sound.Parent then
			sound:Resume()
		end
	end
	task.wait(0.3)
	sleepGui:Destroy()
end

-- Lock screen, then the desktop, until Shut Down. Returns a function that
-- closes macOS, so the goodbye screen can fade in over the desktop first.
-- `startup`: the startup screen (createMacBootScreen) is up, so macOS is built
-- behind black and the lock screen comes up out of it.
local function runMacOS(assets, startup)
	local session = createMacSession(assets, startup ~= nil)
	if startup then
		startup.hide()
		startup.destroy()
	end
	local desktop = nil
	local boot = true
	while true do
		showMacLockScreen(session, boot)
		boot = false
		macSounds.play(macSounds.login) -- logged in
		if not desktop then
			desktop = createMacDesktop(session)
			-- Windows saved at the last Shut Down
			if type(macSettings.reopen) == "table" then
				desktop.reopenList = macSettings.reopen
				macSettings.reopen = nil
				saveMacSettings()
			end
		end
		local action = desktop.run()
		if action == "shutdown" then
			break
		elseif action == "restart" then
			fadeMacMusic(0.6)
			session.fadeCover(0, 0.6)
			desktop.closeAllWindows()
			task.wait(0.8)
			-- Startup screen over the black cover, then the lock screen
			local restartScreen = createMacBootScreen(session.gui, 60, false)
			restartScreen.show()
			restartScreen.run(3.5)
			restartScreen.hide()
			restartScreen.destroy()
			boot = true
		elseif action == "redownload" then
			-- Like Restart, but the startup screen deletes the assets and gets
			-- them all again, saying what it's on
			fadeMacMusic(0.6)
			session.fadeCover(0, 0.6)
			desktop.closeAllWindows()
			task.wait(0.8)
			local screen = createMacBootScreen(session.gui, 60, false)
			screen.show()
			local ok, err = pcall(rebuildMacAssets, function(fraction, title, file)
				screen.setProgress(fraction, 0.2)
				screen.setStatus(title, file)
			end)
			if not ok then
				warn("[coolui] Redownload failed: " .. tostring(err))
				screen.setStatus("Something went wrong", tostring(err))
				screen.setProgress(1, 0.3)
				task.wait(2.5)
			end
			task.wait(0.9)
			screen.hide()
			screen.destroy()
			boot = true
		elseif action == "sleep" then
			macSleep(session)
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
		{"Sounds", function()
			-- First, so the startup chime is ready when the startup screen comes up
			macSounds.get(macSounds.startup)
			macSounds.get(macSounds.login)
		end},
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

	-- The startup screen: the first time macOS ever starts, and whenever it's
	-- switched on in System Settings > General. It takes over from the loading
	-- screen after 2 seconds, and its bar follows the remaining steps.
	local startup = nil
	local startupShown = false
	local progress = 0
	local showStartup = nil
	if not macSettings.booted or macSettings.startupScreen == true then
		function showStartup()
			if startup then
				return
			end
			local holder = Instance.new("ScreenGui")
			holder.Name = "coolui_startup"
			holder.IgnoreGuiInset = true
			holder.ResetOnSpawn = false
			holder.DisplayOrder = 1003
			holder.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			holder.Parent = player:WaitForChild("PlayerGui")
			startup = createMacBootScreen(holder, 1, true)
			startup.ownGui = holder
			startup.show()
			startup.setProgress(progress, 0.6)
			startupShown = true
		end
		task.delay(2, showStartup)
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
		progress = i / #steps
		if startupShown then
			startup.setProgress(progress)
		end
	end

	if showStartup then
		-- (if loading somehow beat the 2 seconds, it shows now)
		showStartup()
		repeat
			task.wait()
		until startupShown
		startup.setProgress(1, 0.5)
		task.wait(0.8)
		macSettings.booted = true
		saveMacSettings()
		-- The loading screen is under the black now; clear it out of the way
		Spinner.ImageTransparency = 1
		status:Destroy()
		detail:Destroy()
		return runMacOS(assets, startup)
	end

	status.Text = "Starting macOS"
	detail.Text = ""
	task.wait(0.9)
	TweenService:Create(Spinner, macFadeInfo, {ImageTransparency = 1}):Play()
	TweenService:Create(status, macFadeInfo, {TextTransparency = 1}):Play()
	-- The backdrop turns fully opaque: macOS starts under a copy of it, which
	-- the lock screen then fades away (see createMacSession). Wait for the fade
	-- to really finish: if it were still running when macOS clears the
	-- backdrop for the 3D scene, its last frame would make it opaque again.
	local opaque = TweenService:Create(background, macFadeInfo, {ImageTransparency = 0})
	opaque:Play()
	opaque.Completed:Wait()
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





