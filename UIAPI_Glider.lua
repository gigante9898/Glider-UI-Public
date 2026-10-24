--[[
	==============================================================================
	UIAPI - Glider (vendored from Feather Ink, rebranded)
	Backend UI library. Original Feather by friend, now Glider owned.
	==============================================================================
	An ink-and-paper UI library for Roblox executors.
	  - Themes: Sakura (default), Ink, Parchment, Journal. Picked in Settings, saved globally
	  - Rail with tinted tab icons, a gliding active marker, pinned Settings/Config
	  - Controls on ruled rows: capsule toggles, ruler sliders, dropdowns, pickers
	  - Watermark, keybinds HUD, toasts, Ctrl+K search, mobile reopen button
	  - Free mouse while the menu is open: the game can't lock or click with it (Settings)
	  - File-backed JSON configs with auto-save and autoload
	  - What's New card once per update: Library.new{Version = "1.0.1", Changelog = {...}}
	  - Skin picker, gallery, hero, viewport, player list, side panels, tooltips, dependent controls
	  - Clean unload and service signal tracking (Library.Connect)
	==============================================================================
]]

local GLOBAL_KEY = "GliderUI_Instance"
if getgenv and getgenv()[GLOBAL_KEY] and type(getgenv()[GLOBAL_KEY].Unload) == "function" then
	pcall(function() getgenv()[GLOBAL_KEY]:Unload(true) end)
end

local Players         = game:GetService("Players")
local UIS             = game:GetService("UserInputService")
local TweenService    = game:GetService("TweenService")
local HttpService     = game:GetService("HttpService")
local RunService      = game:GetService("RunService")
local SoundService    = game:GetService("SoundService")
local StatsService    = game:GetService("Stats")
local ContentProvider = game:GetService("ContentProvider")
local GuiService      = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
-- Touch layout. It can be forced from the outside to preview it on a desktop:
--   getgenv().GliderForceMobile = true   (before loading the library)
--   or Library.new({ Mobile = true })
local IS_MOBILE   = UIS.TouchEnabled and not UIS.KeyboardEnabled
if getgenv and getgenv().GliderForceMobile == true then IS_MOBILE = true end

-- Safe drawing area: phones reserve the top strip for the Roblox topbar.
local function topbarInset()
	local y = 0
	pcall(function()
		local tb = GuiService.TopbarInset
		if typeof(tb) == "Rect" and tb.Y then y = tb.Y end
	end)
	if y <= 0 then
		pcall(function()
			local top = GuiService:GetGuiInset()
			if typeof(top) == "Vector2" then y = top.Y end
		end)
	end
	return math.max(y, 0)
end

local function viewportSize(gui)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(0, 0)
	-- Very early in the frame the camera still reports 1x1; the menu Gui (which
	-- is parented before the first render) already knows the real screen size.
	if (vp.X < 50 or vp.Y < 50) and gui then
		local a = gui.AbsoluteSize
		if a.X > 50 and a.Y > 50 then return a end
	end
	return vp
end

-- Instance-creation capability probe (v0.2 hardening). Restricted threads
-- (Studio command bar, sandboxed loaders) block Instance.new with
-- "lacking capability Plugin". Detect once so widgets degrade gracefully.
local CAN_CREATE_INSTANCES = (function()
	local ok, obj = pcall(function() return Instance.new("Frame") end)
	if ok and obj then pcall(function() obj:Destroy() end) return true end
	return false
end)()

-- ---------------------------------------------------------------------------
-- THEMES
-- Flat tables of named roles. The Chrome roles paint the rail and the overlays
-- (watermark, keybinds HUD, toasts); the rest paint the page and its popups.
-- ---------------------------------------------------------------------------
local rgb = Color3.fromRGB
local THEMES = {
	Sakura = {
		ChromeBg = rgb(14, 10, 16), ChromeRaised = rgb(24, 17, 26), ChromeText = rgb(252, 248, 250),
		ChromeSub = rgb(172, 146, 170), ChromeRule = rgb(48, 35, 54), ChromeAccent = rgb(255, 125, 172),
		PageBg = rgb(16, 12, 18), PageRaised = rgb(27, 20, 31), Text = rgb(252, 248, 250), SubText = rgb(172, 146, 170),
		Rule = rgb(46, 34, 52), Rule2 = rgb(72, 52, 82), Accent = rgb(255, 115, 168), Knob = rgb(20, 14, 24),
		Hover = rgb(255, 140, 185), Edge = rgb(72, 52, 82),
		Success = rgb(130, 225, 160), Warning = rgb(255, 195, 110), Danger = rgb(255, 95, 120),
		ToastSuccess = rgb(130, 225, 160), ToastWarning = rgb(255, 195, 110), ToastError = rgb(255, 95, 120),
		GrainTransparency = 0.92, Binding = false,
	},
	Ink = {
		ChromeBg = rgb(21, 18, 15), ChromeRaised = rgb(28, 24, 20), ChromeText = rgb(236, 228, 212),
		ChromeSub = rgb(138, 128, 114), ChromeRule = rgb(38, 33, 28), ChromeAccent = rgb(229, 86, 47),
		PageBg = rgb(21, 18, 15), PageRaised = rgb(28, 24, 20), Text = rgb(236, 228, 212), SubText = rgb(138, 128, 114),
		Rule = rgb(34, 29, 25), Rule2 = rgb(58, 51, 43), Accent = rgb(229, 86, 47), Knob = rgb(21, 18, 15),
		Hover = rgb(236, 228, 212), Edge = rgb(44, 38, 33),
		Success = rgb(134, 176, 126), Warning = rgb(217, 165, 70), Danger = rgb(217, 68, 82),
		ToastSuccess = rgb(134, 176, 126), ToastWarning = rgb(217, 165, 70), ToastError = rgb(217, 68, 82),
		GrainTransparency = 0.92, Binding = false,
	},
	Parchment = {
		ChromeBg = rgb(232, 223, 204), ChromeRaised = rgb(241, 234, 220), ChromeText = rgb(33, 28, 22),
		ChromeSub = rgb(98, 88, 72), ChromeRule = rgb(212, 200, 177), ChromeAccent = rgb(198, 63, 28),
		PageBg = rgb(241, 234, 220), PageRaised = rgb(247, 242, 232), Text = rgb(33, 28, 22), SubText = rgb(98, 88, 72),
		Rule = rgb(225, 215, 196), Rule2 = rgb(201, 187, 162), Accent = rgb(198, 63, 28), Knob = rgb(241, 234, 220),
		Hover = rgb(33, 28, 22), Edge = rgb(207, 195, 173),
		Success = rgb(78, 127, 72), Warning = rgb(168, 116, 26), Danger = rgb(184, 50, 63),
		ToastSuccess = rgb(78, 127, 72), ToastWarning = rgb(168, 116, 26), ToastError = rgb(184, 50, 63),
		GrainTransparency = 0.93, Binding = false,
	},
	Journal = {
		ChromeBg = rgb(27, 23, 20), ChromeRaised = rgb(28, 24, 20), ChromeText = rgb(236, 228, 212),
		ChromeSub = rgb(138, 128, 114), ChromeRule = rgb(44, 38, 33), ChromeAccent = rgb(229, 86, 47),
		PageBg = rgb(239, 231, 214), PageRaised = rgb(247, 242, 232), Text = rgb(34, 28, 22), SubText = rgb(98, 88, 72),
		Rule = rgb(224, 213, 193), Rule2 = rgb(199, 184, 158), Accent = rgb(198, 63, 28), Knob = rgb(239, 231, 214),
		Hover = rgb(34, 28, 22), Edge = rgb(44, 38, 33),
		Success = rgb(78, 127, 72), Warning = rgb(168, 116, 26), Danger = rgb(184, 50, 63),
		ToastSuccess = rgb(134, 176, 126), ToastWarning = rgb(217, 165, 70), ToastError = rgb(217, 68, 82),
		GrainTransparency = 0.92, Binding = true,
	},
}
local THEME_ORDER = {"Sakura", "Ink", "Parchment", "Journal"}
local CURRENT_THEME = THEMES.Sakura

-- ---------------------------------------------------------------------------
-- FONTS (Roblox built-in families; a missing face falls back to the closest one)
-- ---------------------------------------------------------------------------
local function fontFace(name, weight, style)
	local ok, base = pcall(function() return Font.fromEnum(Enum.Font[name]) end)
	if not ok or not base then base = Font.fromEnum(Enum.Font.GothamMedium) end
	return Font.new(base.Family, weight or Enum.FontWeight.Regular, style or Enum.FontStyle.Normal)
end
-- ---------------------------------------------------------------------------
-- FILES: Glider keeps its folders as they are, so scripts that read and write them directly keep working:
--   <Folder>/        a script's configs and its own files (Library.new{Folder = "Glider_<Game>"})
--   Glider_Global/   menu preferences shared by every script, plus cached fonts and sounds
-- ---------------------------------------------------------------------------
local HUB_GLOBAL = "Glider_Global"
local FS_DIRS = type(isfolder) == "function" and type(makefolder) == "function"
-- makes every level of a path that doesn't exist yet
local function hubDir(path)
	if not FS_DIRS then return end
	local at = ""
	for part in tostring(path):gmatch("[^/]+") do
		at = at == "" and part or (at .. "/" .. part)
		if not isfolder(at) then makefolder(at) end
	end
end
local function hubPath(name)
	name = tostring(name or "")
	if name == "" then name = "Glider_Configs" end
	return name
end
local function hubGlobal()
	pcall(hubDir, HUB_GLOBAL)
	return HUB_GLOBAL
end

-- A theme picks a font set (theme.Fonts, Default when unset). Text keeps its role (Body, Heading, ...),
-- so switching theme swaps every face in place; within one set no two roles may share a face, since a
-- label's role is read back from the face it shows. Scale shrinks a role's text sizes for wide faces.
local FONT_SETS = {
	Default = {
		Brand       = fontFace("Fondamento"),
		Heading     = fontFace("Merriweather"),
		HeadingBold = fontFace("Merriweather", Enum.FontWeight.Bold),
		Italic      = fontFace("Merriweather", Enum.FontWeight.Regular, Enum.FontStyle.Italic),
		Body        = fontFace("JosefinSans"),
		BodySemi    = fontFace("JosefinSans", Enum.FontWeight.SemiBold),
		Mono        = fontFace("RobotoMono"),
		Symbol      = Font.fromEnum(Enum.Font.GothamBold),
	},
}
local FONTS = table.clone(FONT_SETS.Default)
local FONT_SCALE = {}
local FONT_SET_NAME = "Default"

-- Custom faces ship inside this file (base64 .ttf). The first time a theme needs one it is written to
-- the global folder with a one-face family file next to it, and loaded with getcustomasset.
local CUSTOM_SLOTS = {{"Regular", 400, "normal"}}
local CUSTOM_FONTS = {}
local CUSTOM_LOADED = {}
local function b64decode(data)
	local lib = (crypt and (crypt.base64decode or crypt.base64_decode)) or base64_decode or (base64 and base64.decode)
	if lib then
		local ok, out = pcall(lib, data)
		if ok and type(out) == "string" and #out > 0 then return out end
	end
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local map = {}
	for i = 1, 64 do map[alphabet:sub(i, i)] = i - 1 end
	local out, bits, n = {}, 0, 0
	for c in data:gmatch("[^=]") do
		local v = map[c]
		if v then
			bits, n = bits * 64 + v, n + 6
			if n >= 8 then
				n -= 8
				local b = math.floor(bits / 2 ^ n)
				table.insert(out, string.char(b))
				bits -= b * 2 ^ n
			end
		end
	end
	return table.concat(out)
end
-- the family asset for a custom font, or nil when it can't be loaded here
local function customFamily(name)
	if CUSTOM_LOADED[name] ~= nil then return CUSTOM_LOADED[name] or nil end
	local spec = CUSTOM_FONTS[name]
	local family
	local canWrite = type(writefile) == "function" and type(isfolder) == "function" and type(makefolder) == "function"
	if spec and canWrite and type(getcustomasset) == "function" then
		local ok, res = pcall(function()
			local dir = hubGlobal() .. "/fonts"
			hubDir(dir)
			local bytes = b64decode(spec.Data)
			local ttf = dir .. "/" .. name .. ".ttf"
			if not (isfile and isfile(ttf)) or (readfile and #readfile(ttf) ~= #bytes) then writefile(ttf, bytes) end
			local asset = getcustomasset(ttf)
			local faces = {}
			for _, slot in ipairs(CUSTOM_SLOTS) do
				table.insert(faces, {name = slot[1], weight = slot[2], style = slot[3], assetId = asset})
			end
			local json = dir .. "/" .. name .. ".json"
			writefile(json, game:GetService("HttpService"):JSONEncode({name = name, faces = faces}))
			return getcustomasset(json)
		end)
		if ok and type(res) == "string" and res ~= "" then family = res end
	end
	CUSTOM_LOADED[name] = family or false
	return family
end
-- a set entry {Custom = name, Weight, Style} as a Font: the custom family, or its fallback family
local function customFace(e)
	local w, st = e.Weight or Enum.FontWeight.Regular, e.Style or Enum.FontStyle.Normal
	local family = customFamily(e.Custom)
	if family then return Font.new(family, w, st) end
	local spec = CUSTOM_FONTS[e.Custom]
	return fontFace(spec and spec.Fallback or "GothamMedium", w, st)
end

local function fontKey(f)
	return typeof(f) == "Font" and (tostring(f.Family) .. "|" .. tostring(f.Weight) .. "|" .. tostring(f.Style)) or nil
end
-- Makes `name` the live font set. With a root, every text object under it that shows one of the old
-- set's faces gets the matching face of the new set (and its size rescaled where a role is scaled).
local function applyFontSet(name, root)
	local set = FONT_SETS[name] and name or "Default"
	if set == FONT_SET_NAME then return end
	local byKey = {}
	for role, f in pairs(FONTS) do
		local k = fontKey(f)
		if k then byKey[k] = role end
	end
	local oldScale = FONT_SCALE
	for role, f in pairs(FONT_SETS[set]) do
		if role ~= "Scale" then FONTS[role] = type(f) == "table" and customFace(f) or f end
	end
	FONT_SCALE = FONT_SETS[set].Scale or {}
	FONT_SET_NAME = set
	if not root then return end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local role = byKey[fontKey(d.FontFace)]
			if role then
				d.FontFace = FONTS[role]
				local o, n = oldScale[role] or 1, FONT_SCALE[role] or 1
				if o ~= n and not d.TextScaled then d.TextSize = math.max(1, math.round(d.TextSize / o * n)) end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- SOUND FX SYSTEM
-- ---------------------------------------------------------------------------
local SOUNDS = {
	Click   = "rbxassetid://6895079853",
	Tab     = "rbxassetid://6895079853",
	Toggle  = "rbxassetid://6895079853",
	Slide   = "rbxassetid://9114223175",
	Notify  = "rbxassetid://6895079853",
	Popup   = "rbxassetid://9114223175",
}

-- A theme can bring its own sounds (theme.Sounds names a set): short .ogg clips embedded here,
-- written to the global folder the first time and played with getcustomasset. A sound the set
-- doesn't have uses the default above. Slider ticks only play for a set that has one.
local SOUND_SETS = {}
local EMBEDDED_SOUNDS = {}
local SOUND_LOADED = {}
local function embeddedSound(name)
	if SOUND_LOADED[name] ~= nil then return SOUND_LOADED[name] or nil end
	local id
	local canWrite = type(writefile) == "function" and type(isfolder) == "function" and type(makefolder) == "function"
	if EMBEDDED_SOUNDS[name] and canWrite and type(getcustomasset) == "function" then
		local ok, res = pcall(function()
			local dir = hubGlobal() .. "/sounds"
			hubDir(dir)
			local bytes = b64decode(EMBEDDED_SOUNDS[name])
			local path = dir .. "/" .. name .. ".ogg"
			if not (isfile and isfile(path)) or (readfile and #readfile(path) ~= #bytes) then writefile(path, bytes) end
			return getcustomasset(path)
		end)
		if ok and type(res) == "string" and res ~= "" then id = res end
	end
	SOUND_LOADED[name] = id or false
	return id
end
-- the current theme's own sound for a key, or nil
local function themeSound(key)
	local set = CURRENT_THEME.Sounds and SOUND_SETS[CURRENT_THEME.Sounds]
	return set and set[key] and embeddedSound(set[key]) or nil
end

local SoundEnabled = true
local NOTIFY_GAP = 2 -- a game spamming notifications shouldn't spam their sound
local lastNotifySound = -math.huge
local function playSound(soundKey)
	if not SoundEnabled then return end
	if soundKey == "Notify" then
		if os.clock() - lastNotifySound < NOTIFY_GAP then return end
		lastNotifySound = os.clock()
	end
	local soundId = themeSound(soundKey) or SOUNDS[soundKey] or soundKey
	task.spawn(function()
		pcall(function()
			local s = Instance.new("Sound")
			s.SoundId = soundId
			s.Volume = 0.4
			s.Parent = SoundService
			s:Play()
			s.Ended:Connect(function() s:Destroy() end)
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- MOTION (calm: no overshoot anywhere)
-- ---------------------------------------------------------------------------
local FAST  = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MED   = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ---------------------------------------------------------------------------
-- CONNECTION TRACKER & HELPERS
-- ---------------------------------------------------------------------------
local CONNS = {}
local RARITY_COLORS = {
	Common       = Color3.fromRGB(130, 255, 90),  -- Luminous Lime Green
	Uncommon     = Color3.fromRGB(130, 255, 90),
	Rare         = Color3.fromRGB(80, 220, 255),  -- Luminous Cyan
	Epic         = Color3.fromRGB(190, 130, 255), -- Luminous Purple
	Legendary    = Color3.fromRGB(255, 80, 80),   -- Luminous Red
	Mythical     = Color3.fromRGB(190, 130, 255), -- Luminous Purple (Aegis, Blizzard, etc.)
	Genuine      = Color3.fromRGB(120, 220, 130), -- Luminous Emerald
	Unique       = Color3.fromRGB(255, 170, 50),  -- Luminous Orange
	Unobtainable = Color3.fromRGB(220, 130, 255), -- Luminous Lavender/Amethyst (Never black!)
	Default      = Color3.fromRGB(190, 190, 200),
}
local function getReadableRarityColor(c, fallback)
	if not c then return fallback or RARITY_COLORS.Default end
	local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	if lum < 0.38 then
		local h, s, v = c:ToHSV()
		return Color3.fromHSV(h, math.clamp(s, 0.35, 0.75), math.clamp(v + 0.55, 0.85, 1))
	end
	return c
end
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(CONNS, c)
	return c
end

local function tween(obj, props, info)
	if not obj then return nil end
	local ok, t = pcall(function()
		return TweenService:Create(obj, info or FAST, props)
	end)
	if ok and t then
		pcall(function() t:Play() end)
		return t
	else
		for k, v in pairs(props) do
			pcall(function() obj[k] = v end)
		end
		return nil
	end
end

-- Tween when info is given, otherwise set the properties straight away.
local function apply(obj, props, info)
	if info then return tween(obj, props, info) end
	for k, v in pairs(props) do obj[k] = v end
end

-- Theme painting. paint() sets properties from theme roles and remembers them,
-- so SetTheme can repaint by role. Colours that depend on state (on/off,
-- selected, active) register a restyler instead, which SetTheme re-runs.
-- Both registries hold instances strongly. Roblox can collect the Lua handle of an
-- instance that is still on screen, which would silently drop it from a weak-keyed
-- table and leave it in the old theme's colours. Destroyed instances are swept instead.
local PAINTED, RESTYLERS = {}, {}
local registrations, sweepQueued = 0, false
local function sweepRegistries()
	sweepQueued = false
	for inst in pairs(PAINTED) do
		if inst.Parent == nil then PAINTED[inst] = nil end
	end
	for owner in pairs(RESTYLERS) do
		if owner.Parent == nil then RESTYLERS[owner] = nil end
	end
end
local function noteRegistration()
	registrations += 1
	if registrations % 400 == 0 and not sweepQueued then
		sweepQueued = true
		task.defer(sweepRegistries) -- deferred so nothing still being built (unparented) is swept
	end
end
local function paint(inst, roles)
	local rec = PAINTED[inst]
	if not rec then
		rec = {}
		PAINTED[inst] = rec
		noteRegistration()
	end
	for prop, key in pairs(roles) do
		inst[prop] = CURRENT_THEME[key]
		rec[prop] = key
	end
	return inst
end
local function restyle(owner, fn)
	if not RESTYLERS[owner] then noteRegistration() end
	RESTYLERS[owner] = fn
	fn()
	return fn
end

local function create(class, props, children)
	local obj = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then obj[k] = v end
	end
	if props.FontFace and props.TextSize and next(FONT_SCALE) then
		for role, sc in pairs(FONT_SCALE) do
			if props.FontFace == FONTS[role] then obj.TextSize = math.max(1, math.round(props.TextSize * sc)) end
		end
	end
	for _, c in ipairs(children or {}) do c.Parent = obj end
	obj.Parent = props.Parent
	return obj
end
local function make(class, props, roles, children)
	local obj = create(class, props, children)
	if roles then paint(obj, roles) end
	return obj
end

local function corner(r) return create("UICorner", {CornerRadius = UDim.new(0, r or 6)}) end
local function stroke(role, thickness, transparency)
	return make("UIStroke", {
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, role and {Color = role} or nil)
end
local function padding(v, h)
	h = h or v
	return create("UIPadding", {
		PaddingTop = UDim.new(0, v),
		PaddingBottom = UDim.new(0, v),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end
local function list(pad, dir, extra)
	local l = create("UIListLayout", {
		Padding = UDim.new(0, pad or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = dir or Enum.FillDirection.Vertical,
	})
	for k, v in pairs(extra or {}) do l[k] = v end
	return l
end
local H = Enum.FillDirection.Horizontal
local AX, AY = Enum.AutomaticSize.X, Enum.AutomaticSize.Y
local LEFT, RIGHT, CENTER = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right, Enum.TextXAlignment.Center
local TRUNC = Enum.TextTruncate.AtEnd

-- A text label painted with a theme role. Role = false leaves the colour to the caller.
local function label(props, children)
	local role = props.Role
	if role == nil then role = "Text" end
	props.Role = nil
	local base = {
		BackgroundTransparency = 1,
		FontFace = FONTS.Body,
		TextSize = 14,
		TextXAlignment = LEFT,
	}
	for k, v in pairs(props) do base[k] = v end
	return make("TextLabel", base, role and {TextColor3 = role} or nil, children)
end

-- Tracked small caps: Roblox has no letter-spacing, so letters get one space and words three.
local function track(s)
	local words = {}
	for w in string.upper(tostring(s)):gmatch("%S+") do
		local chars = {}
		for _, cp in utf8.codes(w) do table.insert(chars, utf8.char(cp)) end
		table.insert(words, table.concat(chars, " "))
	end
	return table.concat(words, "   ")
end

-- A "v" chevron drawn from two short bars, so it never depends on a font having the glyph.
-- props: Size, Position, AnchorPoint, Parent, ZIndex. Rotate the returned frame to point it.
local function drawnChevron(props)
	local holder = create("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0})
	for k, v in pairs(props) do if k ~= "Parent" then holder[k] = v end end
	for i, side in ipairs({-1, 1}) do
		make("Frame", {
			Name = i == 1 and "Left" or "Right", BorderSizePixel = 0, Size = UDim2.fromOffset(6, 2),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * 2, 0.5, 0),
			Rotation = -side * 45, ZIndex = props.ZIndex or 1, Parent = holder,
		}, {BackgroundColor3 = "SubText"}, {corner(1)})
	end
	holder.Parent = props.Parent
	return holder
end

local ROMAN = {{1000, "M"}, {900, "CM"}, {500, "D"}, {400, "CD"}, {100, "C"}, {90, "XC"},
	{50, "L"}, {40, "XL"}, {10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"}}
local function toRoman(n)
	local out = ""
	for _, pair in ipairs(ROMAN) do
		while n >= pair[1] do out ..= pair[2]; n -= pair[1] end
	end
	return out
end

local function keycap(text, parent, role)
	return make("TextButton", {
		Text = text, FontFace = FONTS.Mono, TextSize = 11, AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 22), AutomaticSize = AX,
		Parent = parent,
	}, {TextColor3 = role or "Text"}, {corner(3), stroke("Rule2"), padding(0, 7)})
end

-- A 1px line under a TextBox that turns accent while it has focus.
local function underline(box)
	local line = make("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, 0),
		BorderSizePixel = 0, Parent = box,
	}, {BackgroundColor3 = "Rule2"})
	box.Focused:Connect(function() tween(line, {BackgroundColor3 = CURRENT_THEME.Accent}) end)
	box.FocusLost:Connect(function() tween(line, {BackgroundColor3 = CURRENT_THEME.Rule2}) end)
	return line
end

-- Placeholders read in serif italic; typed text in the body face.
local function italicWhenEmpty(box, face)
	local function update() box.FontFace = box.Text == "" and FONTS.Italic or (face or FONTS.Body) end
	box:GetPropertyChangedSignal("Text"):Connect(update)
	update()
end

-- Tracked-caps button: kind = "primary" (filled accent), "danger", or nil (outlined).
local function textButton(parent, text, kind, order)
	local primary, danger = kind == "primary", kind == "danger"
	local b = make("TextButton", {
		Text = track(text), FontFace = FONTS.BodySemi, TextSize = 11, AutoButtonColor = false,
		BackgroundTransparency = primary and 0 or 1, AutomaticSize = AX, Size = UDim2.fromOffset(0, 32),
		BorderSizePixel = 0, LayoutOrder = order or 0, Parent = parent,
	}, {
		TextColor3 = primary and "Knob" or danger and "Danger" or "Text",
		BackgroundColor3 = primary and "Accent" or "Hover",
	}, {corner(3), padding(0, 14), stroke(primary and "Accent" or danger and "Danger" or "Rule2", 1, danger and 0.5 or 0)})
	b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = primary and 0.12 or 0.94}) end)
	b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = primary and 0 or 1}) end)
	return b
end

-- Capsule switch. Returns the frame and show(on, animate).
local function capsule(parent, position)
	local trackF = create("Frame", {
		Size = UDim2.fromOffset(28, 14), Position = position, AnchorPoint = Vector2.new(1, 0.5),
		BorderSizePixel = 0, BackgroundTransparency = 1, Parent = parent,
	}, {corner(7)})
	local edge = create("UIStroke", {Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = trackF})
	local knob = create("Frame", {
		Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BorderSizePixel = 0, Parent = trackF,
	}, {corner(5)})
	local state = false
	local function show(on, animate)
		state = on
		local T = CURRENT_THEME
		local info = animate and FAST or nil
		apply(trackF, {BackgroundColor3 = T.Accent, BackgroundTransparency = on and 0 or 1}, info)
		apply(edge, {Color = on and T.Accent or T.SubText}, info)
		apply(knob, {BackgroundColor3 = on and T.Knob or T.SubText}, info)
		apply(knob, {Position = UDim2.new(0, on and 16 or 2, 0.5, 0)},
			animate and TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) or nil)
	end
	restyle(trackF, function() show(state, false) end)
	return trackF, show
end

-- A bind key is an Enum.KeyCode (keyboard, gamepad and the mouse key codes) or, for the mouse buttons
-- Roblox only reports as an input type, Enum.UserInputType.MouseButton2/3. Saved by .Name either way.
local MOUSE_KEYS = {MouseButton1 = true, MouseButton2 = true, MouseButton3 = true}
local function toKeyCode(name)
	if typeof(name) ~= "string" then return nil end
	if MOUSE_KEYS[name] then return Enum.UserInputType[name] end
	local ok, key = pcall(function() return Enum.KeyCode[name] end)
	return ok and key or nil
end
-- the bind key an input event is for, or nil (mouse movement, wheel...). Roblox only reports mouse
-- buttons 1-3, so side buttons (mouse 4 / 5) can't be bound.
local function inputKey(input)
	if input.KeyCode ~= Enum.KeyCode.Unknown then return input.KeyCode end
	if MOUSE_KEYS[input.UserInputType.Name] then return input.UserInputType end
	-- a keyboard key Roblox has no code for (some layout keys, e.g. the ISO "<" key on a few layouts):
	-- still bindable, as one shared "Other key"
	if input.UserInputType == Enum.UserInputType.Keyboard then return Enum.KeyCode.Unknown end
	return nil
end
local KEY_LABELS = {
	MouseButton1 = "Mouse 1", MouseButton2 = "Mouse 2", MouseButton3 = "Mouse 3",
	MouseLeftButton = "Mouse 1", MouseRightButton = "Mouse 2", MouseMiddleButton = "Mouse 3", MouseBackButton = "Mouse 4",
}
local function keyLabel(key)
	if not key then return "—" end
	if KEY_LABELS[key.Name] then return KEY_LABELS[key.Name] end
	if key == Enum.KeyCode.Unknown then return "Other key" end
	if key.EnumType == Enum.KeyCode then
		-- symbols, digits and layout letters show as the character the keyboard prints ("<", "1", "ö")
		local ok, str = pcall(UIS.GetStringForKeyCode, UIS, key)
		if ok and typeof(str) == "string" and utf8.len(str) == 1 and not str:match("^%s$") then
			return str:upper()
		end
		if key.Name:match("^World%d+$") then
			local okc, ch = pcall(utf8.char, key.Value)
			if okc then return ch end
		end
	end
	return key.Name
end
local function toHex(c)
	return ("#%02X%02X%02X"):format(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function fromHex(s)
	if typeof(s) == "Color3" then return s end
	if type(s) ~= "string" then return nil end
	local h = s:gsub("^%s*#?", ""):gsub("%s+$", "")
	if #h == 3 then h = h:gsub(".", "%0%0") end
	if #h ~= 6 or not h:match("^%x+$") then return nil end
	local n = tonumber(h, 16)
	return Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end
local function escapeRich(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"):gsub("'", "&apos;"))
end
-- Wraps the first case-insensitive match of q in an accent <font> tag (RichText, escaped).
local function highlight(name, q, hex)
	if q == "" then return escapeRich(name) end
	local i, j = string.find(string.lower(name), q, 1, true)
	if not i then return escapeRich(name) end
	return escapeRich(name:sub(1, i - 1)) .. '<font color="' .. hex .. '">' .. escapeRich(name:sub(i, j))
		.. "</font>" .. escapeRich(name:sub(j + 1))
end

-- Smooth Draggable helper
local function makeDraggable(frame, handle)
	local dragging, startInput, startPos
	handle.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, startInput, startPos = true, input.Position, frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	connect(UIS.InputChanged, function(input)
		if dragging and isMove(input) then
			local d = input.Position - startInput
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end)
	connect(UIS.InputEnded, function(input)
		if isPress(input) then dragging = false end
	end)
end

-- Protected GUI parenting helper
local function guiParent(gui)
	if syn and syn.protect_gui then pcall(syn.protect_gui, gui)
	elseif protectgui then pcall(protectgui, gui) end
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and typeof(hui) == "Instance" then return hui end
	local okCore, core = pcall(function() return game:GetService("CoreGui") end)
	if okCore and core then
		local probe = Instance.new("Folder")
		local canParent = pcall(function() probe.Parent = core end)
		probe:Destroy()
		if canParent then return core end
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

-- ---------------------------------------------------------------------------
-- STORAGE / CONFIG PERSISTENCE
-- ---------------------------------------------------------------------------
local HAS_FS = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
	and type(listfiles) == "function" and type(isfolder) == "function" and type(makefolder) == "function" and type(delfile) == "function"

local Storage = {_mem = {}, _global = {}, Folder = hubPath(nil)}
local function safeName(name) return (tostring(name):gsub("[^%w%-_%. ]", "")) end
local function configPath(name) return Storage.Folder .. "/configs/" .. safeName(name) .. ".json" end

-- opts.Folder names the game ("FeatherHub_Rivals"); its files go to FeatherHub/Rivals, and a folder of that
function Storage.init(folder)
	Storage.Folder = hubPath(folder)
	if not HAS_FS then return end
	pcall(function()
		hubDir(Storage.Folder .. "/configs")
	end)
end
function Storage.list()
	local names = {}
	if HAS_FS then
		local ok, files = pcall(listfiles, Storage.Folder .. "/configs")
		for _, f in ipairs(ok and files or {}) do
			local n = tostring(f):match("([^/\\]+)%.json$")
			if n then table.insert(names, n) end
		end
	else
		for k in pairs(Storage._mem) do table.insert(names, k) end
	end
	table.sort(names)
	return names
end
-- JSONEncode throws on Instances, functions and raw Roblox datatypes (a dropdown filled with
-- players, a Color3 put in by hand). Drop the keys that cannot be stored instead of losing the
-- whole config to a single one.
local function jsonSafe(v, seen, depth)
	local t = type(v)
	if t == "string" or t == "number" or t == "boolean" then return v end
	if t ~= "table" then return nil end
	depth = depth or 0
	if depth > 16 then return nil end
	seen = seen or {}
	if seen[v] then return nil end -- a cycle would recurse forever and kill the save
	seen[v] = true
	local out = {}
	for k, x in pairs(v) do
		-- JSON object keys must be strings: an Enum or Instance key would break the encode
		if type(k) == "string" or type(k) == "number" then
			local ok = jsonSafe(x, seen, depth + 1)
			if ok ~= nil then out[k] = ok end
		end
	end
	seen[v] = nil
	return out
end
function Storage.save(name, tbl)
	if type(tbl) ~= "table" then return end
	-- A save never deletes what it does not know about: flags that are missing from this
	-- snapshot (widgets still being built, or a tab removed in this build) keep their old value.
	local prev = Storage.load(name)
	if prev and type(prev.flags) == "table" and type(tbl.flags) == "table" then
		for k, v in pairs(prev.flags) do
			if tbl.flags[k] == nil then tbl.flags[k] = v end
		end
	end
	local ok, raw = pcall(function() return HttpService:JSONEncode(jsonSafe(tbl)) end)
	if not ok or type(raw) ~= "string" then return end
	if HAS_FS then pcall(writefile, configPath(name), raw) else Storage._mem[safeName(name)] = raw end
end
function Storage.load(name)
	local raw
	if HAS_FS then
		local ok, data = pcall(function() return isfile(configPath(name)) and readfile(configPath(name)) or nil end)
		raw = ok and data or nil
	else
		raw = Storage._mem[safeName(name)]
	end
	if not raw then return nil end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and decoded or nil
end
function Storage.delete(name)
	if HAS_FS then pcall(function() if isfile(configPath(name)) then delfile(configPath(name)) end end)
	else Storage._mem[safeName(name)] = nil end
end
function Storage.getAutoload()
	if HAS_FS then
		local ok, n = pcall(function() local p = Storage.Folder .. "/autoload.txt"; return isfile(p) and readfile(p) or nil end)
		if ok and n and n ~= "" then return n end
		return nil
	end
	return Storage._autoload
end
function Storage.setAutoload(name)
	if HAS_FS then
		pcall(function()
			if not isfolder(Storage.Folder) then makefolder(Storage.Folder) end
			local p = Storage.Folder .. "/autoload.txt"
			if name then writefile(p, name) elseif isfile(p) then delfile(p) end
		end)
	else
		Storage._autoload = name
	end
end
function Storage.getAutosave()
	if HAS_FS then
		local ok, n = pcall(function()
			local p = Storage.Folder .. "/autosave.txt"
			if isfile(p) then return readfile(p) end
			local gp = hubGlobal() .. "/autosave.txt"
			if isfile(gp) then return readfile(gp) end
			return nil
		end)
		if ok and n and n ~= "" then return n == "1" or n == "true" end
		return nil
	end
	return Storage._autosave
end
-- autosave.txt is written on every run (it mirrors whatever the menu currently has), so it
-- cannot be trusted to mean "the user chose autosave on". Only an explicit toggle lands here.
function Storage.getAutosaveChoice()
	if HAS_FS then
		local ok, n = pcall(function()
			local p = Storage.Folder .. "/autosave_choice.txt"
			return isfile(p) and readfile(p) or nil
		end)
		if ok and n and n ~= "" then return n == "1" or n == "true" end
		return nil
	end
	return Storage._autosaveChoice
end
function Storage.setAutosave(enabled, explicit)
	if HAS_FS then
		pcall(function()
			local val = enabled and "1" or "0"
			if not isfolder(Storage.Folder) then makefolder(Storage.Folder) end
			writefile(Storage.Folder .. "/autosave.txt", val)
			writefile(hubGlobal() .. "/autosave.txt", val)
			if explicit then writefile(Storage.Folder .. "/autosave_choice.txt", val) end
		end)
	else
		Storage._autosave = enabled
		if explicit then Storage._autosaveChoice = enabled end
	end
end

-- Global preferences (menu key, theme) live outside any config so they persist
-- across games and config loads.
local function writeGlobal(file, value)
	if HAS_FS then
		pcall(function()
			writefile(hubGlobal() .. "/" .. file, value)
		end)
	else
		Storage._global[file] = value
	end
end
local function readGlobal(file)
	if HAS_FS then
		local ok, n = pcall(function() local p = hubGlobal() .. "/" .. file; return isfile(p) and readfile(p) or nil end)
		if ok and n and n ~= "" then return n end
		return nil
	end
	return Storage._global[file]
end
function Storage.saveMenuKey(name) writeGlobal("menukey.txt", name) end
function Storage.loadMenuKey() return readGlobal("menukey.txt") end
function Storage.saveTheme(name) writeGlobal("theme.txt", name) end
function Storage.loadTheme() return readGlobal("theme.txt") end
-- On/off preferences from the Settings tab, one file each holding "1" or "0".
local PREF_FILES = {
	HideUsername = "hidename.txt", SoundFX = "soundfx.txt",
	ShowWatermark = "watermark.txt", ShowKeybindHUD = "keyhud.txt", FpsCap = "fpscap.txt",
	FreeMouse = "freemouse.txt", AntiAfk = "antiafk.txt",
}
function Storage.savePref(flag, on) writeGlobal(PREF_FILES[flag], on and "1" or "0") end
-- Returns default when the preference was never saved.
function Storage.loadPref(flag, default)
	local v = readGlobal(PREF_FILES[flag])
	if v == nil then return default end
	return v == "1"
end
function Storage.saveHideName(on) Storage.savePref("HideUsername", on) end
function Storage.loadHideName() return Storage.loadPref("HideUsername") end
function Storage.saveSoundFX(on) Storage.savePref("SoundFX", on) end
function Storage.loadSoundFX() return Storage.loadPref("SoundFX") end
function Storage.saveWatermark(on) Storage.savePref("ShowWatermark", on) end
function Storage.loadWatermark() return Storage.loadPref("ShowWatermark") end
function Storage.saveKeyHUD(on) Storage.savePref("ShowKeybindHUD", on) end
function Storage.loadKeyHUD() return Storage.loadPref("ShowKeybindHUD") end
-- The FPS cap's number lives in its own file.
function Storage.saveFpsCap(n) writeGlobal("fpscapvalue.txt", tostring(n)) end
function Storage.loadFpsCap() return tonumber(readGlobal("fpscapvalue.txt") or "") end
function Storage.saveAntiAfk(on) Storage.savePref("AntiAfk", on) end
function Storage.loadAntiAfk() return Storage.loadPref("AntiAfk") end
function Storage.saveWindowSize(w, h)
	if type(w) == "number" and type(h) == "number" then
		local data = HttpService:JSONEncode({ Width = math.floor(w), Height = math.floor(h) })
		writeGlobal("window_size.json", data)
		if HAS_FS then
			pcall(function()
				if not isfolder(Storage.Folder) then makefolder(Storage.Folder) end
				writefile(Storage.Folder .. "/window_size.json", data)
			end)
		end
	end
end
function Storage.loadWindowSize()
	local raw = nil
	if HAS_FS then
		pcall(function()
			local p = Storage.Folder .. "/window_size.json"
			if isfile(p) then raw = readfile(p) end
		end)
	end
	if not raw then raw = readGlobal("window_size.json") end
	if raw and raw ~= "" then
		local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
		if type(data) == "table" and type(data.Width) == "number" and type(data.Height) == "number" then
			return data
		end
	end
	return nil
end

-- The script version this user last ran, kept in the script's own folder (Folder/version.txt).
-- A newer Version than this one shows What's New once.
function Storage.saveSeenVersion(v)
	if HAS_FS then pcall(writefile, Storage.Folder .. "/version.txt", tostring(v)) else Storage._seenVersion = tostring(v) end
end
function Storage.loadSeenVersion()
	if HAS_FS then
		local ok, v = pcall(function() local p = Storage.Folder .. "/version.txt"; return isfile(p) and readfile(p) or nil end)
		if ok and v and v ~= "" then return v end
		return nil
	end
	return Storage._seenVersion
end

-- ---------------------------------------------------------------------------
-- VERSIONS (What's New)
-- ---------------------------------------------------------------------------
-- "v1.0.10" > "1.0.9": compares the numbers part by part, a missing part counting as 0.
local function versionParts(v)
	local parts = {}
	for n in tostring(v or ""):gmatch("%d+") do table.insert(parts, tonumber(n)) end
	return parts
end
local function compareVersions(a, b)
	local pa, pb = versionParts(a), versionParts(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x < y and -1 or 1 end
	end
	return 0
end
local function versionText(v)
	return "v" .. (tostring(v):gsub("^%s*[vV]", ""))
end
-- The changelog entries newer than `after` (nil: from the first) and up to `upto`, newest first.
local function changesBetween(changelog, after, upto)
	local out = {}
	for _, entry in ipairs(changelog or {}) do
		if type(entry) == "table" and entry.Version ~= nil
			and (after == nil or compareVersions(entry.Version, after) > 0)
			and compareVersions(entry.Version, upto) <= 0 then
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a, b) return compareVersions(a.Version, b.Version) > 0 end)
	return out
end
local function newestVersion(changelog)
	local best
	for _, entry in ipairs(changelog or {}) do
		if type(entry) == "table" and entry.Version ~= nil and (best == nil or compareVersions(entry.Version, best) > 0) then
			best = entry.Version
		end
	end
	return best and tostring(best) or nil
end

-- Settings flags that are global preferences, not part of any config: configs never
-- save, load or reset them, and Unload leaves them alone.
local GLOBAL_FLAGS = {
	MenuKey = true, HideUsername = true, SoundFX = true, ShowWatermark = true, ShowKeybindHUD = true,
	FpsCap = true, FpsCapValue = true, FreeMouse = true, AntiAfk = true,
}

-- ---------------------------------------------------------------------------
-- FPS CAP (Settings > Performance), through the executor's setfpscap where it exists
-- ---------------------------------------------------------------------------
local FPS_MIN, FPS_MAX, FPS_DEFAULT = 30, 1000, 144
-- The cap in place before the menu changed it: getfpscap() where the executor has it, else Roblox's 60.
local function currentFpsCap()
	if type(getfpscap) == "function" then
		local ok, v = pcall(getfpscap)
		if ok and type(v) == "number" then return v end
	end
	return 60
end

-- ---------------------------------------------------------------------------
-- LIBRARY CORE
-- ---------------------------------------------------------------------------
local Library = {
	Flags = {},
	Elements = {},
	Binds = {},
	MenuKey = Enum.KeyCode.Insert,
	Themes = THEMES,
	Theme = CURRENT_THEME,
	Fonts = FONTS,
	Storage = Storage,
	Connect = connect,
	CanCreateInstances = CAN_CREATE_INSTANCES,
	IsMobile = IS_MOBILE,
	Sounds = SOUNDS,
	SoundEnabled = true,
	RarityColors = RARITY_COLORS,
	Components = {
		Card = true, Banner = true, Stat = true, Chips = true, List = true,
		ActionRow = true, CopyField = true, Prompt = true, Confirm = true,
		-- Marks that every Tab:Add* widget honours opts.Parent, so callers can
		-- nest widgets inside a card body (Tab:AddCard(...).Body).
		Parent = true,
	},
	Icons = {
		Combat     = 119168694531898,
		Player     = 127505433136549,
		Visuals    = 84745516177083,
		World      = 93371680357706,
		Teleport   = 85674376575351,
		Misc       = 110695217426888,
		Settings   = 87862881290117,
		Config     = 105363416845572,
		Search     = 79488727439532,
		PaperPlane = 131122221118848,
		PlumeVane  = 109028262244405,
		PlumeShaft = 124588188115353,
		Grain      = 79377062140589,
	},
}
Library.__index = Library
-- a script's own folder (made if missing): Library.HubFolder("Glider_Rivals") -> "Glider_Rivals"
function Library.HubFolder(name)
	local path = hubPath(name)
	pcall(hubDir, path)
	return path
end
local Tab = {}
Tab.__index = Tab

-- ---------------------------------------------------------------------------
-- EXECUTOR SUPPORT
-- Executors Feather doesn't support (their sUNC results are too low for the scripts' hooks to hold up)
-- get a warning: a modal at load that waits five seconds for "I understand", and a line at the top of
-- Settings and Config. Nothing is probed or locked; features are left as they are.
-- ---------------------------------------------------------------------------
local Executor = {Name = "Unknown", Version = "", Unsupported = false}
Library.Executor = Executor
local UNSUPPORTED_EXECUTORS = {"xeno", "solara"}
do
	local ok, n, ver = pcall(function() return identifyexecutor() end)
	if ok and type(n) == "string" and n ~= "" then
		Executor.Name = n
		Executor.Version = type(ver) == "string" and ver or ""
	end
	local lname = string.lower(Executor.Name)
	for _, key in ipairs(UNSUPPORTED_EXECUTORS) do
		if string.find(lname, key, 1, true) then Executor.Unsupported = true end
	end
end
function Executor.label()
	local who = Executor.Name
	if Executor.Version ~= "" then who = who .. " " .. Executor.Version end
	return who
end
Executor.Message = "Your executor is unsupported. Some features will not work."

local PAD = 14 -- inner left/right padding of a row

local function asset(id) return type(id) == "number" and ("rbxassetid://" .. id) or id end

-- Draws the window's mark into holder: the caller's Logo if set (tinted unless LogoTint = false),
-- else the Glider paper airplane. ctx "Chrome" (rail, overlays) or "Page".
local function fillMark(holder, ctx, win)
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local accentRole = ctx == "Page" and "Accent" or "ChromeAccent"
	if win and win.Logo then
		local img = create("ImageLabel", {
			Name = "Logo", Image = asset(win.Logo), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1), Parent = holder,
		})
		if win.LogoTint ~= false then paint(img, {ImageColor3 = accentRole}) end
	else
		local plane = create("ImageLabel", {
			Name = "PaperPlane",
			Image = asset(Library.Icons.PaperPlane),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = holder,
		})
		paint(plane, {ImageColor3 = accentRole})
	end
end

-- A mark of the given size; the window remembers it so SetLogo can redraw it.
local function plume(parent, size, ctx, props, win)
	local holder = create("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent})
	for k, v in pairs(props or {}) do holder[k] = v end
	fillMark(holder, ctx, win)
	if win then table.insert(win._marks, {holder, ctx}) end
	return holder
end

-- Paper grain: one tiled texture tinted with the surface's text colour.
local function grain(parent, textRole)
	if not Library.Icons.Grain then return nil end
	return make("ImageLabel", {
		Name = "Grain", Image = asset(Library.Icons.Grain), BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(128, 128),
		Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = parent,
	}, {ImageColor3 = textRole, ImageTransparency = "GrainTransparency"}, {corner(6)})
end

-- ---------------------------------------------------------------------------
-- ANTI-AFK
-- ---------------------------------------------------------------------------
-- Roblox drops the client after ~20 minutes without any input. Replaying one
-- harmless input when the LocalPlayer reports "Idled" keeps the session alive
-- without moving the character, so a menu can be left running overnight.
local AntiAfk = { On = false, Connections = {}, Count = 0 }

local function antiAfkNudge()
	local virtualUser = game:GetService("VirtualUser")
	pcall(function()
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end)
end

local function antiAfkStop()
	for _, conn in ipairs(AntiAfk.Connections) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(AntiAfk.Connections)
	AntiAfk.On = false
end

local function antiAfkStart()
	if AntiAfk.On then return true end
	local player = game:GetService("Players").LocalPlayer
	if not player then return false end
	AntiAfk.On = true
	local function hook()
		if not AntiAfk.On then return end
		table.insert(AntiAfk.Connections, player.Idled:Connect(function()
			AntiAfk.Count += 1
			antiAfkNudge()
		end))
	end
	hook()
	-- A respawn keeps the same Player object, but a session refresh may not.
	table.insert(AntiAfk.Connections, game:GetService("Players").PlayerRemoving:Connect(function(who)
		if who == player and AntiAfk.On then
			task.delay(1, function()
				if not AntiAfk.On then return end
				local again = game:GetService("Players").LocalPlayer
				if again and again ~= player then
					antiAfkStop()
					antiAfkStart()
				end
			end)
		end
	end))
	return true
end

-- Kept on the library so every menu built on it can toggle the same engine.
function Library:SetAntiAfk(on, silent)
	on = on and true or false
	self.AntiAfkEnabled = on
	if on then
		antiAfkStart()
	else
		antiAfkStop()
	end
	pcall(function() Storage.saveAntiAfk(on) end)
	if not silent then
		self:Notify({
			Title = "Anti-AFK",
			Body = on and "Session will stay awake while the game is left alone" or "Anti-AFK turned off",
			Type = on and "Success" or "Warning",
		})
	end
	return on
end

function Library:IsAntiAfkOn()
	return self.AntiAfkEnabled == true and AntiAfk.On
end

-- ---------------------------------------------------------------------------
-- WINDOW CREATION
-- ---------------------------------------------------------------------------
local RAIL_W, BRAND_H = 176, 84
-- Touch layout: the brand block loses its rule and game label and the pinned
-- tabs collapse into one icon row, so the tab list keeps a usable height on a
-- short phone window.
local BRAND_H_M = 52

function Library.new(opts)
	opts = opts or {}
	local saved = Storage.loadTheme()
	local themeName = (saved and THEMES[saved] and saved) or (opts.Theme and THEMES[opts.Theme] and opts.Theme) or "Sakura"
	CURRENT_THEME = THEMES[themeName]
	Library.Theme = CURRENT_THEME
	applyFontSet(CURRENT_THEME.Fonts or "Default")
	local changelog = type(opts.Changelog) == "table" and opts.Changelog or nil

	local self = setmetatable({
		Tabs = {},
		Visible = true,
		Listening = false,
		TintIcons = opts.TintIcons ~= false,
		Brand = opts.Brand or "Glider",
		Title = opts.Title or "GLIDER",
		Logo = opts.Logo,
		LogoTint = opts.LogoTint,
		ThemeName = themeName,
		Version = opts.Version ~= nil and tostring(opts.Version) or newestVersion(changelog),
		Changelog = changelog,
		_visibilityCallbacks = {},
		_marks = {},
		_unloadCallbacks = {},
		_themeSubscribers = {},
		_tabCount = 0,
		_tabNum = 0,
		_pinnedCount = 0,
		_hudEnabled = true,
		_sidePanels = {},
		_popups = {},
	}, Library)

	-- Header subtitle shows the game/edition name only: strip a leading
	-- "Glider | " brand prefix ("Glider | X" -> "X").
	if type(self.Title) == "string" then
		self.Title = self.Title:gsub("^[%-%s]*[Gg]lider%s*|%s*", "")
	end

	-- Promo banner (console, every menu boot -- AegisLoader-style).
	print("[Glider] Free scripts: aim, ESP, skin changer")
	print("[Glider] Support + updates: https://discord.gg/Z3vCpEPevt")

	if opts.MenuKey then Library.MenuKey = opts.MenuKey end
	do
		local savedKey = Storage.loadMenuKey()
		if savedKey then
			local kc = toKeyCode(savedKey)
			if typeof(kc) == "EnumItem" then Library.MenuKey = kc end
		end
	end

	Library._window = self
	Storage.init(opts.Folder)
	self.Folder = Storage.Folder

	-- What's New: the first run shows the current version's notes, then a Version newer than the one this
	-- user last ran queues the notes since then; both open after the intro. The same version again, or one
	-- with nothing written up, stays quiet. Without file functions nothing is remembered, so the first-run
	-- card is skipped there rather than shown on every launch.
	if self.Version then
		local seen = Storage.loadSeenVersion()
		local pending
		if seen then
			pending = compareVersions(seen, self.Version) < 0 and changesBetween(changelog, seen, self.Version)
		elseif HAS_FS then
			pending = {changesBetween(changelog, nil, self.Version)[1]}
		end
		if pending and #pending > 0 then
			self._pendingChanges = pending
		else
			Storage.saveSeenVersion(self.Version)
		end
	end

	-- Autosave is OFF unless the script asks for it or the user turned it on himself:
	-- armed by default it starts writing over a config while the menu is still being built.
	local savedAutoSave = Storage.getAutosaveChoice()
	if savedAutoSave ~= nil then
		self.AutoSave = savedAutoSave
	else
		self.AutoSave = opts.AutoSave == true
	end

	-- No autosave until the build is finished (see touch()). AutoLoad() clears it, and so does
	-- any real click, so a script that never calls AutoLoad() still saves from the first tick
	-- the user touches something.
	self._building = true
	task.delay(5, function() self._building = false end)

	local autoCfg = Storage.getAutoload()
	if autoCfg then
		self.ActiveConfig = autoCfg
	elseif self.AutoSave then
		self.ActiveConfig = "default"
	end

	-- Global settings: always persist, independent of configs/autosave.
	self.HideUsername = Storage.loadPref("HideUsername", opts.HideUsername == true)
	SoundEnabled = Storage.loadPref("SoundFX", true)
	self.SoundFXOn = SoundEnabled
	self._wmEnabled = Storage.loadPref("ShowWatermark", true)
	self.ShowWatermark = self._wmEnabled
	self._hudEnabled = Storage.loadPref("ShowKeybindHUD", true)
	self.ShowKeybindHUD = self._hudEnabled
	self._fpsEnabled = Storage.loadPref("FpsCap", false)
	self._freeMouse = Storage.loadPref("FreeMouse", opts.FreeMouse ~= false)
	self._fpsValue = math.clamp(Storage.loadFpsCap() or FPS_DEFAULT, FPS_MIN, FPS_MAX)
	self:_applyFpsCap()
	-- Anti-AFK is a global preference too, on by default.
	self.AntiAfkEnabled = true
	local antiAfkSaved = Storage.loadAntiAfk()
	if antiAfkSaved ~= nil then self.AntiAfkEnabled = antiAfkSaved end
	if self.AntiAfkEnabled then pcall(antiAfkStart) end

	-- Root ScreenGui
	self.Gui = create("ScreenGui", {
		Name = opts.Name or "UIAPI_Suite",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Above the touch thumbstick/jump buttons so the menu covers them.
		DisplayOrder = 999,
	})
	self.Gui.Parent = guiParent(self.Gui)

	-- Free-mouse shield: full-screen and invisible, under everything else in this Gui. While the
	-- menu is open it catches clicks meant for the world and, being Modal, releases first-person
	-- mouse lock (see _applyFreeMouse).
	self.MouseShield = create("TextButton", {
		Name = "MouseShield", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Selectable = false, Modal = true, Visible = false, ZIndex = 0,
		Size = UDim2.fromScale(1, 1), Parent = self.Gui,
	})

	-- Window size persistence (remembers size across executions / games)
	local savedWinSize = Storage.loadWindowSize()
	-- saved size, else opts.Width/Height (or opts.Size), else 1080 x 616; shrunk to fit small screens
	local want = typeof(opts.Size) == "Vector2" and opts.Size or Vector2.new(opts.Width or 1080, opts.Height or 616)
	local initW = (savedWinSize and savedWinSize.Width) or want.X
	local initH = (savedWinSize and savedWinSize.Height) or want.Y
	if not (IS_MOBILE or opts.Mobile == true) then
		local vp = viewportSize(self.Gui)
		if vp.X > 50 and vp.Y > 50 then
			initW = math.clamp(initW, 500, math.max(500, math.floor(vp.X * 0.92)))
			initH = math.clamp(initH, 420, math.max(420, math.floor(vp.Y * 0.88)))
		end
	end

	-- Touch layout switches on for phones/tablets, or when it is forced.
	if opts.Mobile == true then IS_MOBILE = true end
	self.MobileFit = opts.MobileFit ~= false
	self.PreviewViewport = opts.PreviewViewport

	-- Root: a full-screen host that carries the safety inset and, on touch, the
	-- shrink-to-fit scale. The window is centred inside it, so on a phone the
	-- whole menu is always visible below the Roblox topbar.
	self.Root = make("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = self.Gui,
	})
	self.Fit = create("UIScale", {Scale = 1, Parent = self.Root})

	-- Main Window Frame (never a CanvasGroup: it renders the whole menu darker)
	self.Main = make("Frame", {
		Name = "MainWindow",
		Size = UDim2.fromOffset(initW, initH),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = self.Root,
	}, {BackgroundColor3 = "PageBg"}, {corner(6), stroke("Edge")})
	self.Scale = create("UIScale", {Scale = 1, Parent = self.Main})
	grain(self.Main, "Text")
	pcall(function() self:_applyFit() end)

	-- -----------------------------------------------------------------------
	-- RAIL: brand, tab list, pinned tabs, config status
	-- -----------------------------------------------------------------------
	local rail = make("Frame", {
		Name = "Rail", Size = UDim2.new(0, RAIL_W, 1, 0), BorderSizePixel = 0, Parent = self.Main,
	}, {BackgroundColor3 = "ChromeBg"}, {corner(6)})
	make("Frame", { -- squares off the rail's right-hand corners
		Size = UDim2.new(0, 8, 1, 0), Position = UDim2.new(1, -8, 0, 0), BorderSizePixel = 0, Parent = rail,
	}, {BackgroundColor3 = "ChromeBg"})
	grain(rail, "ChromeText")
	local railLine = make("Frame", {
		Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BorderSizePixel = 0, ZIndex = 3, Parent = rail,
	}, {BackgroundColor3 = "ChromeRule"})
	self.TabRail = rail

	self._brandH = IS_MOBILE and BRAND_H_M or BRAND_H
	local brand = create("Frame", {Name = "Brand", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, self._brandH - 12), ZIndex = 15, Parent = rail})
	self.BrandMark = plume(brand, 26, "Chrome", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(29, 30), ZIndex = 20}, self)
	self.BrandLabel = label({
		Text = self.Brand, FontFace = FONTS.Brand, TextSize = 24, Role = "ChromeText", TextTruncate = TRUNC,
		Size = UDim2.new(1, -56, 0, 28), Position = UDim2.fromOffset(46, 16), Parent = brand,
	})
	local brandDash = make("Frame", {Size = UDim2.fromOffset(14, 1), Position = UDim2.fromOffset(20, 58), BorderSizePixel = 0, Parent = brand},
		{BackgroundColor3 = "ChromeAccent"})
	self.GameLabel = label({
		Text = track(self.Title), FontFace = FONTS.BodySemi, TextSize = 10, Role = "ChromeSub", TextTruncate = TRUNC,
		Size = UDim2.new(1, -52, 0, 12), Position = UDim2.fromOffset(40, 52), Parent = brand,
	})
	self.TitleLabel = self.GameLabel
	if IS_MOBILE then
		self.BrandMark.Position = UDim2.fromOffset(26, 26)
		self.BrandLabel.Position = UDim2.fromOffset(44, 12)
		self.BrandLabel.TextSize = 20
		self.BrandLabel.Size = UDim2.new(1, -54, 0, 28)
		brandDash.Visible = false
		self.GameLabel.Visible = false -- the name is already in the watermark
	end

	-- Active-tab marker: an accent wash plus a slanted bar; glides between tabs.
	self.TabMarker = make("Frame", {
		Name = "Marker", Size = UDim2.new(1, -1, 0, 34), BorderSizePixel = 0, Visible = false, ZIndex = 1, Parent = rail,
	}, {BackgroundColor3 = "ChromeAccent"}, {
		create("UIGradient", {Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.88),
			NumberSequenceKeypoint.new(0.85, 1),
			NumberSequenceKeypoint.new(1, 1),
		})}),
	})
	make("Frame", {
		Size = UDim2.fromOffset(3, 20), Position = UDim2.new(0, 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		Rotation = 12, BorderSizePixel = 0, Parent = self.TabMarker,
	}, {BackgroundColor3 = "ChromeAccent"})

	self.TabList = create("ScrollingFrame", {
		Name = "Tabs", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
		Position = UDim2.fromOffset(0, self._brandH), Size = UDim2.new(1, -1, 1, -self._brandH - 34),
		ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, Parent = rail,
	}, {list(2)})
	connect(self.TabList:GetPropertyChangedSignal("CanvasPosition"), function() self:_syncMarker(false) end)

	self.Foot = create("Frame", {
		Name = "Foot", BackgroundTransparency = 1, ZIndex = 2, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, -1, 0, 34), Parent = rail,
	}, {list(2, IS_MOBILE and H or nil, IS_MOBILE and {HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center} or {VerticalAlignment = Enum.VerticalAlignment.Bottom})})
	self.FootRule = make("Frame", {Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, LayoutOrder = 0, Visible = false, Parent = self.Foot},
		{BackgroundColor3 = "ChromeRule"})
	self.FootGap = create("Frame", {Size = UDim2.new(1, 0, 0, 4), BackgroundTransparency = 1, LayoutOrder = 1, Visible = false, Parent = self.Foot})
	self.PinnedList = self.Foot

	local status = create("Frame", {
		Name = "Status", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1000, Parent = self.Foot,
	}, {
		list(6, H, {VerticalAlignment = Enum.VerticalAlignment.Center}),
		create("UIPadding", {PaddingLeft = UDim.new(0, 20), PaddingBottom = UDim.new(0, 4)}),
	})
	self.ConfigDot = create("Frame", {Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, LayoutOrder = 1, Parent = status}, {corner(3)})
	self.ConfigLabel = label({
		Text = "no config", FontFace = FONTS.Mono, TextSize = 11, Role = false,
		AutomaticSize = AX, Size = UDim2.fromOffset(0, 14), LayoutOrder = 2, Parent = status,
	})
	self.ConfigSuffix = label({
		Text = "", FontFace = FONTS.Mono, TextSize = 11, Role = "ChromeSub",
		AutomaticSize = AX, Size = UDim2.fromOffset(0, 14), LayoutOrder = 3, Parent = status,
	})
	restyle(status, function() self:_refreshConfigStatus() end)
	if IS_MOBILE then status.Visible = false end -- no room for the config line in the icon row

	-- -----------------------------------------------------------------------
	-- PAGE: header (tab title + tools) and the scrolling content
	-- -----------------------------------------------------------------------
	local page = create("Frame", {
		Name = "Page", BackgroundTransparency = 1, Position = UDim2.fromOffset(RAIL_W, 0),
		Size = UDim2.new(1, -RAIL_W, 1, 0), Parent = self.Main,
	})
	self.PageArea = page
	local binding = create("Frame", { -- Journal's "binding" shadow along the page's left edge
		Name = "Binding", Size = UDim2.new(0, 16, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0, ZIndex = 3, Parent = page,
	}, {create("UIGradient", {Transparency = NumberSequence.new(0.55, 1)})})
	restyle(binding, function()
		binding.Visible = CURRENT_THEME.Binding == true
		railLine.Visible = CURRENT_THEME.Binding ~= true
	end)

	local header = create("Frame", {
		Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromOffset(28, 14),
		Size = UDim2.new(1, -52, 0, 40), Parent = page,
	})
	self.PageTitle = label({
		Text = "", FontFace = FONTS.HeadingBold, TextSize = 26, TextYAlignment = Enum.TextYAlignment.Bottom,
		TextTruncate = TRUNC, Size = UDim2.new(1, -150, 1, 0), Parent = header,
	})
	local tools = create("Frame", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(150, 24), Parent = header,
	}, {list(12, H, {HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center})})

	local searchBtn = make("ImageButton", {
		Image = asset(Library.Icons.Search), BackgroundTransparency = 1, AutoButtonColor = false,
		Size = UDim2.fromOffset(15, 15), LayoutOrder = 1, Parent = tools,
	}, {ImageColor3 = "SubText"})
	searchBtn.MouseEnter:Connect(function() tween(searchBtn, {ImageColor3 = CURRENT_THEME.Accent}) end)
	searchBtn.MouseLeave:Connect(function() tween(searchBtn, {ImageColor3 = CURRENT_THEME.SubText}) end)
	searchBtn.MouseButton1Click:Connect(function()
		playSound("Click")
		self:OpenSearchModal()
	end)
	self.SearchBtn = searchBtn

	if not IS_MOBILE then
		self.KeyChip = keycap(keyLabel(Library.MenuKey), tools, "SubText")
		self.KeyChip.TextSize = 10
		self.KeyChip.LayoutOrder = 2
	end

	local hideBtn = make("TextButton", {
		Text = "–", FontFace = FONTS.Body, TextSize = 18, AutoButtonColor = false, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(16, 22), LayoutOrder = 3, Parent = tools,
	}, {TextColor3 = "SubText"})
	hideBtn.MouseEnter:Connect(function() tween(hideBtn, {TextColor3 = CURRENT_THEME.Text}) end)
	hideBtn.MouseLeave:Connect(function() tween(hideBtn, {TextColor3 = CURRENT_THEME.SubText}) end)
	hideBtn.MouseButton1Click:Connect(function()
		playSound("Click")
		self:SetVisible(false)
	end)
	self.HideBtn = hideBtn

	makeDraggable(self.Main, header)
	makeDraggable(self.Main, brand)

	self.Content = create("Frame", {
		Name = "Content", BackgroundTransparency = 1, ClipsDescendants = true,
		Position = UDim2.fromOffset(28, 64), Size = UDim2.new(1, -40, 1, -64), Parent = page,
	})
	-- Tab switches fade this page-coloured veil out over the new page
	-- (a cheap fade that avoids CanvasGroup).
	self.Veil = make("Frame", {
		Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = 5, Parent = self.Content,
	}, {BackgroundColor3 = "PageBg"})

	-- -----------------------------------------------------------------------
	-- RESIZE GRIP (Bottom-Right)
	-- -----------------------------------------------------------------------
	local grip = create("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 20), Position = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(1, 1),
		ZIndex = 10, Parent = self.Main,
		-- Free resize is a desktop affordance; on touch it only steals swipes.
		Visible = not IS_MOBILE,
	})
	make("Frame", {
		Size = UDim2.fromOffset(10, 1), Position = UDim2.new(1, -5, 1, -9), AnchorPoint = Vector2.new(1, 0.5),
		Rotation = -45, BorderSizePixel = 0, Parent = grip,
	}, {BackgroundColor3 = "Rule2"})
	make("Frame", {
		Size = UDim2.fromOffset(5, 1), Position = UDim2.new(1, -5, 1, -5), AnchorPoint = Vector2.new(1, 0.5),
		Rotation = -45, BorderSizePixel = 0, Parent = grip,
	}, {BackgroundColor3 = "Rule2"})

	local resizing, rStart, rSize, rPos
	grip.InputBegan:Connect(function(i)
		if isPress(i) then
			resizing, rStart, rSize, rPos = true, i.Position, self.Main.Size, self.Main.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then
					if resizing then
						resizing = false
						Storage.saveWindowSize(self.Main.Size.X.Offset, self.Main.Size.Y.Offset)
					end
				end
			end)
		end
	end)
	connect(UIS.InputChanged, function(i)
		if resizing and isMove(i) then
			local d = i.Position - rStart
			local w = math.clamp(rSize.X.Offset + d.X, 550, 1400)
			local h = math.clamp(rSize.Y.Offset + d.Y, 420, 950)
			self.Main.Size = UDim2.fromOffset(w, h)
			self.Main.Position = UDim2.new(
				rPos.X.Scale, rPos.X.Offset + (w - rSize.X.Offset) / 2,
				rPos.Y.Scale, rPos.Y.Offset + (h - rSize.Y.Offset) / 2
			)
		end
	end)
	connect(UIS.InputEnded, function(i)
		if resizing and isPress(i) then
			resizing = false
			Storage.saveWindowSize(self.Main.Size.X.Offset, self.Main.Size.Y.Offset)
		end
	end)

	-- -----------------------------------------------------------------------
	-- NOTIFICATION CONTAINER
	-- -----------------------------------------------------------------------
	self.NotifHolder = create("Frame", {
		Size = UDim2.fromOffset(300, 500),
		Position = UDim2.new(1, -20, 1, -20),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = self.Gui,
	}, {
		list(8, nil, {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	})

	-- -----------------------------------------------------------------------
	-- WATERMARK & KEYBIND HUD OVERLAYS
	-- -----------------------------------------------------------------------
	if opts.Watermark ~= false then self:_buildWatermark(self.Title) end
	if opts.KeybindHUD ~= false then self:_buildKeybindHUD() end

	if IS_MOBILE then
		self:_buildMobileIcon()
		-- Rotation, window resize, split view: keep the menu inside the screen.
		connect(self.Gui:GetPropertyChangedSignal("AbsoluteSize"), function() self:_applyFit() end)
		-- The topbar inset is not known on the very first frame, so the first fit
		-- runs with a 0 inset; re-fit once the inset and the viewport are real.
		connect(GuiService:GetPropertyChangedSignal("TopbarInset"), function() self:_applyFit() end)
		for _, d in ipairs({ 0.2, 0.6, 1.5, 3 }) do
			task.delay(d, function()
				if self.Root and self.Root.Parent then self:_applyFit() end
			end)
		end
	end
	self:_bindInput()
	self.Main.Visible = true -- opens through the book animation rather than SetVisible's pop
	self:_playIntro()
	self:_applyFreeMouse()

	-- Pinned Tabs (Settings, Config & Discord)
	if opts.Settings ~= false then self.SettingsTab = self:_buildSettingsTab(opts.SettingsName, opts.SettingsIcon) end
	if opts.Config ~= false then self:AddConfigTab(opts.ConfigName, opts.ConfigIcon) end
	if opts.Discord ~= false then self:AddDiscordTab(opts.DiscordName, opts.DiscordIcon) end
	self:_refreshConfigStatus()

	-- Automatic executor support warning (Xeno/Solara markdown modal).
	-- Zero per-script setup: every menu built with Library.new() gets it.
	-- Opt out per script with Library.new({ SkipExecutorCheck = true }).
	if opts.SkipExecutorCheck ~= true then
		task.defer(function()
			if self.Unloaded then return end
			pcall(function() self:CheckExecutorSupport() end)
		end)
	end

	if getgenv then getgenv()[GLOBAL_KEY] = self end
	return self
end

-- Effective scale of the window (UIScale during open/close), for Absolute* maths.
-- Measured on the height, which stays fixed while the window unfolds at startup.
function Library:_uiScale()
	local h, a = self.Main.Size.Y.Offset, self.Main.AbsoluteSize.Y
	if h <= 0 or a <= 0 then return 1 end
	return a / h
end

-- Touch layout: the window fills the safe area at scale 1 so text keeps its
-- native size and nothing is shrunk into illegibility. Desktop keeps the exact
-- geometry it always had (scale 1, no inset).
function Library:_applyFit()
	if not self.Root or not self.Fit then return end
	if not IS_MOBILE then
		self.Root.Position = UDim2.fromOffset(0, 0)
		self.Root.Size = UDim2.fromScale(1, 1)
		self.Fit.Scale = 1
		return
	end
	local inset = topbarInset()
	self.Root.Position = UDim2.fromOffset(0, inset)
	self.Root.Size = UDim2.new(1, 0, 1, -inset)
	self.Fit.Scale = 1
	-- The watermark lives outside Root: drop it under the Roblox top bar.
	if self.WatermarkFrame then
		self.WatermarkFrame.Position = UDim2.new(1, -20, 0, inset + 10)
	end
	if self.MobileFit == false then return end
	-- PreviewViewport lets a desktop build render exactly what a phone renders.
	local vp = self.PreviewViewport or viewportSize(self.Gui)
	if typeof(vp) ~= "Vector2" then vp = Vector2.new(vp.X or 0, vp.Y or 0) end
	if vp.X < 50 or vp.Y < 50 then
		-- The viewport is not measured yet: try again on the next frames.
		task.delay(0.1, function()
			if self.Root and self.Root.Parent then self:_applyFit() end
		end)
		return
	end
	local margin = 8
	local w = math.max(math.floor(vp.X - margin * 2), 320)
	local h = math.max(math.floor(vp.Y - inset - margin * 2), 220)
	if math.abs(self.Main.Size.X.Offset - w) > 1 or math.abs(self.Main.Size.Y.Offset - h) > 1 then
		self.Main.Size = UDim2.fromOffset(w, h)
		self.Main.Position = UDim2.new(0.5, 0, 0.5, 0)
	end
end
-- Mobile content is bigger than the rail once a script adds a handful of tabs:
-- Roblox does not always refresh AutomaticCanvasSize from a UIListLayout inside
-- a scaled/animated frame, so the tab list must be sized by hand or the last
-- tabs become unreachable (clipped, no scrollbar).
function Library:_refreshTabCanvas()
	local list = self.TabList
	if not list or not list.Parent then return end
	local lay = list:FindFirstChildWhichIsA("UIListLayout")
	local content = lay and math.ceil(lay.AbsoluteContentSize.Y) or 0
	if content <= 0 then return end -- not laid out yet: the next AddTab/rail pass fixes it
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	-- Content only: maxing with AbsoluteSize would keep a stale canvas after the
	-- touch fit shrinks the rail, leaving a scrollbar over empty space.
	list.CanvasSize = UDim2.new(0, 0, 0, content + 4)
end

-- Sizes the tab list around the pinned tabs at the bottom of the rail.
function Library:_layoutRail()
	local n = self._pinnedCount
	if IS_MOBILE then
		-- One compact icon row at the bottom: the tab list keeps the rest.
		local bh = self._brandH or BRAND_H_M
		local fh = n > 0 and 39 or 0
		self.Foot.Size = UDim2.new(1, -1, 0, fh)
		-- The rule cannot stay inside the foot: in a horizontal list it would eat a
		-- whole slot and push the icons off the rail. Anchor it to the rail instead.
		self.FootRule.Parent = self.TabRail
		self.FootRule.Size = UDim2.new(1, -1, 0, 1)
		self.FootRule.AnchorPoint = Vector2.new(0, 0)
		self.FootRule.Position = UDim2.new(0, 0, 1, -fh)
		self.FootRule.Visible = n > 0
		self.FootGap.Visible = false
		self.TabList.Position = UDim2.fromOffset(0, bh)
		self.TabList.Size = UDim2.new(1, -1, 1, -bh - fh)
		for _, child in ipairs(self.PinnedList:GetChildren()) do
			if child:IsA("GuiButton") then child.Size = UDim2.new(1 / math.max(n, 1), -6, 0, 34) end
		end
		task.defer(function() self:_refreshTabCanvas() end)
		return
	end
	local items = 1 + (n > 0 and (2 + n) or 0)
	local h = 34 + (n > 0 and (1 + 4 + n * 34) or 0) + (items - 1) * 2
	self.Foot.Size = UDim2.new(1, -1, 0, h)
	self.TabList.Size = UDim2.new(1, -1, 1, -BRAND_H - h)
	self.FootRule.Visible = n > 0
	self.FootGap.Visible = n > 0
	task.defer(function() self:_refreshTabCanvas() end)
end

function Library:_refreshConfigStatus()
	if self._refreshAutoSaveNote then self._refreshAutoSaveNote() end
	if not self.ConfigLabel then return end
	local T = CURRENT_THEME
	local active = self.ActiveConfig
	self.ConfigLabel.Text = active or "no config"
	self.ConfigLabel.TextColor3 = active and T.ChromeText or T.ChromeSub
	self.ConfigDot.BackgroundColor3 = active and T.ChromeAccent or T.ChromeRule
	self.ConfigSuffix.Text = (active and self.AutoSave) and "· autosave" or ""
end

-- ---------------------------------------------------------------------------
-- WATERMARK HUD OVERLAY
-- ---------------------------------------------------------------------------
function Library:_buildWatermark(title)
	local wm = make("Frame", {
		Name = "Watermark",
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = AX,
		AnchorPoint = Vector2.new(1, 0), -- top-right; grows leftward as the stats change width
		Position = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 50,
		Visible = self._wmEnabled ~= false,
		Parent = self.Gui,
	}, {BackgroundColor3 = "ChromeRaised"}, {
		corner(4), stroke("Edge"), padding(0, 12),
		list(10, H, {VerticalAlignment = Enum.VerticalAlignment.Center}),
	})
	plume(wm, 16, "Chrome", {LayoutOrder = 1}, self)
	self._wmBrand = label({
		Text = self.Brand, FontFace = FONTS.Brand, TextSize = 15, Role = "ChromeText",
		AutomaticSize = AX, Size = UDim2.fromOffset(0, 20), LayoutOrder = 2, Parent = wm,
	})
	local order = 2
	local function sep()
		order += 1
		return make("Frame", {Size = UDim2.fromOffset(1, 12), BorderSizePixel = 0, LayoutOrder = order, Parent = wm},
			{BackgroundColor3 = "ChromeRule"})
	end
	local function stat(text, role)
		order += 1
		return label({
			Text = text, FontFace = FONTS.Mono, TextSize = 11, Role = role,
			AutomaticSize = AX, Size = UDim2.fromOffset(0, 20), LayoutOrder = order, Parent = wm,
		})
	end
	sep(); self._wmTitle = stat(title, "ChromeText")
	if self.Version then self._wmVersion = stat(versionText(self.Version), "ChromeSub") end
	self._wmUserSep = sep(); self._wmUser = stat(LocalPlayer.Name, "ChromeSub")
	sep(); local fpsLabel = stat("60 fps", "ChromeSub")
	sep(); local pingLabel = stat("0 ms", "ChromeSub")

	makeDraggable(wm, wm)
	self.WatermarkFrame = wm
	self:SetHideUsername(self.HideUsername)

	local fCount = 0
	local lTick = tick()
	connect(RunService.RenderStepped, function()
		fCount += 1
		local n = tick()
		if n - lTick >= 0.5 then
			local fps = math.floor(fCount / (n - lTick) + 0.5)
			local okPing, ping = pcall(function()
				return math.floor((StatsService.Network.ServerStatsItem["Data Ping"]:GetValue() or 0) + 0.5)
			end)
			fpsLabel.Text = fps .. " fps"
			pingLabel.Text = (okPing and ping or 0) .. " ms"
			fCount = 0
			lTick = n
		end
	end)
end

-- ---------------------------------------------------------------------------
-- KEYBIND HUD OVERLAY
-- ---------------------------------------------------------------------------
function Library:_buildKeybindHUD()
	local hud = make("Frame", {
		Name = "KeybindHUD",
		Size = UDim2.fromOffset(206, 0),
		AutomaticSize = AY,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0.4, 0),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 50,
		Visible = false,
		Parent = self.Gui,
	}, {BackgroundColor3 = "ChromeRaised"}, {
		corner(4), stroke("Edge"),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		}),
		list(0),
	})
	local head = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = hud})
	label({
		Text = "Keybinds", FontFace = FONTS.Italic, TextSize = 13, Role = "ChromeText",
		Size = UDim2.new(1, -30, 0, 16), Parent = head,
	})
	self.KeybindCount = label({
		Text = "0", FontFace = FONTS.Mono, TextSize = 10, Role = "ChromeAccent", TextXAlignment = RIGHT,
		Size = UDim2.fromOffset(30, 16), Position = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(1, 0), Parent = head,
	})
	make("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0, Parent = head},
		{BackgroundColor3 = "ChromeRule"})
	create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 4), LayoutOrder = 2, Parent = hud})

	self.KeybindList = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AY,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = hud,
	}, {list(0)})

	self.KeybindHUDFrame = hud
	makeDraggable(hud, hud)
	self:UpdateKeybindHUD()
end

function Library:UpdateKeybindHUD()
	if not self.KeybindList then return end
	for _, c in ipairs(self.KeybindList:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local active = {}
	for flag, bind in pairs(Library.Binds) do
		local el = Library.Elements[flag]
		if el and (bind.Mode == "Always" or el.Value == true) then
			table.insert(active, {Name = tostring(el.Name or flag), Bind = bind})
		end
	end
	table.sort(active, function(a, b) return a.Name < b.Name end)

	local ROW_W = 182 -- HUD width (206) minus its 12px side padding
	for i, item in ipairs(active) do
		local r = create("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i, Parent = self.KeybindList,
		})
		local nameLabel = label({
			Text = item.Name, TextSize = 13, Role = "ChromeText", TextTruncate = TRUNC,
			Size = UDim2.new(1, -72, 1, 0), Parent = r,
		})
		local keyLabel = label({
			Text = keyLabel(item.Bind.Key), FontFace = FONTS.Mono, TextSize = 11, Role = "ChromeAccent", TextXAlignment = RIGHT,
			Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(1, -44, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = r,
		})
		local modeLabel = label({
			Text = string.lower(item.Bind.Mode), FontFace = FONTS.Italic, TextSize = 11, Role = "ChromeSub",
			TextXAlignment = RIGHT, Size = UDim2.new(0, 40, 1, 0), Position = UDim2.fromScale(1, 0),
			AnchorPoint = Vector2.new(1, 0), Parent = r,
		})
		-- Dotted leader only in the gap between the name and the key: nothing sits behind the text.
		local leader = create("Frame", {BackgroundTransparency = 1, ClipsDescendants = true, Parent = r})
		label({
			Text = string.rep(". ", 40), FontFace = FONTS.Mono, TextSize = 10, Role = "ChromeSub",
			TextTransparency = 0.5, Size = UDim2.fromScale(1, 1), Parent = leader,
		})
		local function layout()
			local modeW = math.ceil(modeLabel.TextBounds.X)
			local keyW = math.ceil(keyLabel.TextBounds.X)
			keyLabel.Size = UDim2.new(0, keyW, 1, 0)
			keyLabel.Position = UDim2.new(1, -(modeW + 6), 0, 0)
			local avail = ROW_W - modeW - keyW - 24
			nameLabel.Size = UDim2.new(0, avail, 1, 0)
			local x = math.min(math.ceil(nameLabel.TextBounds.X), avail) + 6
			leader.Position = UDim2.fromOffset(x, 0)
			leader.Size = UDim2.fromOffset(math.max(ROW_W - x - keyW - modeW - 12, 0), 24)
		end
		for _, l in ipairs({nameLabel, keyLabel, modeLabel}) do
			l:GetPropertyChangedSignal("TextBounds"):Connect(layout)
		end
		layout()
	end
	local count = #active
	if self.KeybindCount then self.KeybindCount.Text = tostring(count) end
	if self.KeybindHUDFrame then self.KeybindHUDFrame.Visible = self._hudEnabled and count > 0 end
end

-- ---------------------------------------------------------------------------
-- THEME SYSTEM (repaints by role; see paint/restyle)
-- ---------------------------------------------------------------------------
function Library:SetTheme(themeNameOrTbl)
	local newTheme, name
	if type(themeNameOrTbl) == "string" then
		newTheme, name = THEMES[themeNameOrTbl], themeNameOrTbl
	elseif type(themeNameOrTbl) == "table" then
		newTheme = table.clone(THEMES.Sakura) -- a custom table is merged over Sakura so no role is ever nil
		for k, v in pairs(themeNameOrTbl) do newTheme[k] = v end
		name = "Custom"
	end
	if not newTheme then return end

	CURRENT_THEME = newTheme
	Library.Theme = newTheme
	self.ThemeName = name
	pcall(applyFontSet, newTheme.Fonts or "Default", self.Gui)

	for inst, rec in pairs(PAINTED) do
		if inst.Parent == nil then
			PAINTED[inst] = nil
		else
			local goal = {}
			for prop, key in pairs(rec) do goal[prop] = newTheme[key] end
			pcall(tween, inst, goal, MED)
		end
	end
	for owner, fn in pairs(RESTYLERS) do
		if owner.Parent == nil then
			RESTYLERS[owner] = nil
		else
			pcall(fn)
		end
	end
	for _, fn in ipairs(self._themeSubscribers or {}) do
		pcall(fn, CURRENT_THEME)
	end
end

-- ---------------------------------------------------------------------------
-- INTRO ANIMATION
-- Aerodynamic Glider sequence:
-- 1. Inbound flight: Glider swoops diagonally from top-right with banking
--    rotation and twin wingtip vapor trails.
-- 2. Deceleration & Shockwave: Flares smoothly to rest, emitting an expanding
--    aerodynamic vapor ring.
-- 3. Brand typing & accent expansion under the docked mark.
-- 4. Slipstream Horizon Reveal: Symmetrically expands to full window size
--    and lifts the cover to seamlessly reveal the tabs and pages.
-- ---------------------------------------------------------------------------
function Library:_playIntro()
	local main, page, rail = self.Main, self.PageArea, self.TabRail
	local finalSize = main.Size
	local fullW, fullH = finalSize.X.Offset, finalSize.Y.Offset
	local midW = math.clamp(fullW - RAIL_W, 360, 480)
	local pos = main.Position

	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = pos
	main.Size = UDim2.fromOffset(midW, fullH)

	rail.Position = UDim2.fromOffset(0, 0)
	page.Position = UDim2.fromOffset(RAIL_W, 0)
	page.Size = UDim2.new(1, -RAIL_W, 1, 0)

	local cover = make("Frame", {
		Name = "IntroCover",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		ZIndex = 40,
		Parent = main,
	}, {BackgroundColor3 = "ChromeBg"}, {corner(6)})

	local flightBox = create("Frame", {
		Name = "FlightBox",
		Size = UDim2.fromOffset(260, 180),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -48),
		BackgroundTransparency = 1,
		Parent = cover,
	})

	local mark = plume(flightBox, 64, "Chrome", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -90, 0.5, 70),
		Rotation = 18,
	}, self)
	local markScale = create("UIScale", {Scale = 0.5, Parent = mark})

	local parts = {}
	for _, c in ipairs(mark:GetChildren()) do
		if c:IsA("ImageLabel") then
			c.ImageTransparency = 1
			table.insert(parts, {c, "ImageTransparency"})
		elseif c:IsA("Frame") then
			c.BackgroundTransparency = 1
			table.insert(parts, {c, "BackgroundTransparency"})
		end
	end

	local word = label({
		Text = self.Brand, FontFace = FONTS.Brand, TextSize = 36, TextScaled = true, Role = "ChromeText",
		TextXAlignment = CENTER, TextTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 38), Size = UDim2.new(1, -40, 0, 36), Parent = cover,
	}, {create("UITextSizeConstraint", {MaxTextSize = 36})})

	local dash = make("Frame", {
		Size = UDim2.fromOffset(0, 2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 54),
		BackgroundTransparency = 1, BorderSizePixel = 0, Parent = cover,
	}, {BackgroundColor3 = "ChromeAccent"}, {corner(1)})

	local caption = label({
		Text = track(self.Title), FontFace = FONTS.BodySemi, TextSize = 10, Role = "ChromeSub", TextXAlignment = CENTER,
		TextTruncate = TRUNC, TextTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 74), Size = UDim2.new(1, -40, 0, 12), Parent = cover,
	})

	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({word, caption, self.PageTitle}) end)
	end)

	task.spawn(function()
		local function alive()
			return cover.Parent ~= nil and not self.Unloaded and main.Parent ~= nil
		end

		-- Step 1: Smooth gliding entry into center
		playSound("Slide")
		for _, p in ipairs(parts) do tween(p[1], {[p[2]] = 0}, MED) end
		tween(markScale, {Scale = 1.0}, TweenInfo.new(0.70, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		tween(mark, {
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Rotation = 0,
		}, TweenInfo.new(0.70, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))

		-- Step 2: Gentle bloom pulse & Brand text glide
		task.wait(0.35)
		if not alive() then return end

		local pulse = make("Frame", {
			Name = "BloomRing",
			Size = UDim2.fromOffset(12, 12),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = flightBox,
		}, {}, {corner(99)})
		local stroke = create("UIStroke", {
			Color = CURRENT_THEME.ChromeAccent,
			Thickness = 2,
			Transparency = 0.2,
			Parent = pulse,
		})
		tween(pulse, {Size = UDim2.fromOffset(102, 102)}, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
		tween(stroke, {Transparency = 1}, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
		task.delay(0.60, function() pcall(function() pulse:Destroy() end) end)

		tween(word, {Position = UDim2.new(0.5, 0, 0.5, 28), TextTransparency = 0}, MED)
		tween(dash, {Size = UDim2.fromOffset(40, 2), BackgroundTransparency = 0}, MED)
		tween(caption, {Position = UDim2.new(0.5, 0, 0.5, 68), TextTransparency = 0}, MED)

		-- Step 3: Readability pause
		task.wait(0.65)
		if not alive() then return end

		-- Step 4: The Takeoff & Horizon Expansion
		local flyOut = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(mark, {Position = UDim2.new(0.5, 240, 0.5, -200), Rotation = 15}, flyOut)
		tween(markScale, {Scale = 1.3}, flyOut)
		for _, p in ipairs(parts) do tween(p[1], {[p[2]] = 1}, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.In)) end

		local lift = TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tween(word, {Position = UDim2.new(0.5, 0, 0.5, 18), TextTransparency = 1}, lift)
		tween(dash, {BackgroundTransparency = 1}, lift)
		tween(caption, {Position = UDim2.new(0.5, 0, 0.5, 58), TextTransparency = 1}, lift)

		task.wait(0.12)
		if not alive() then return end

		local expandInfo = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		tween(main, {Size = finalSize}, expandInfo)
		tween(cover, {BackgroundTransparency = 1}, expandInfo)

		task.delay(0.14, function()
			if alive() then
				self:_openTabs()
				if self.BrandMark then
					self:_animateBrandMark()
				end
			end
		end)

		task.wait(0.60)
		if not self.Unloaded and main.Parent then
			main.AnchorPoint = Vector2.new(0.5, 0.5)
			main.Position = pos
			main.Size = finalSize
			rail.Position = UDim2.fromOffset(0, 0)
			page.Position = UDim2.fromOffset(RAIL_W, 0)
			page.Size = UDim2.new(1, -RAIL_W, 1, 0)
		end
		pcall(function() cover:Destroy() end)
		self:_showPendingWhatsNew() -- What's New waits for the menu to be fully open
	end)
end

-- The tabs open one after another: each fades in and slides out from the spine.
function Library:_openTabs()
	local order = table.clone(self.Tabs)
	table.sort(order, function(a, b) return a.Button.LayoutOrder < b.Button.LayoutOrder end)
	for i, t in ipairs(order) do
		local parts = {{t.NameLabel, "TextTransparency"}}
		if t.Icon then table.insert(parts, {t.Icon, "ImageTransparency"}) end
		if t.Num then table.insert(parts, {t.Num, "TextTransparency"}) end
		if t.Badge then table.insert(parts, {t.Badge, "TextTransparency"}) end
		for _, p in ipairs(parts) do p[1][p[2]] = 1 end
		t.NameLabel.Position = UDim2.fromOffset(36, 0)
		task.delay(0.12 + (i - 1) * 0.045, function()
			for _, p in ipairs(parts) do tween(p[1], {[p[2]] = 0}, MED) end
			tween(t.NameLabel, {Position = UDim2.fromOffset(46, 0)}, SLIDE)
		end)
	end
end

-- ---------------------------------------------------------------------------
-- GLOBAL QUICK-SEARCH MODAL (Ctrl+K)
-- ---------------------------------------------------------------------------
local TYPE_NAMES = {
	Toggle = "toggle", Slider = "slider", Button = "button", Dropdown = "dropdown",
	MultiDropdown = "multi-select", Textbox = "text", ColorPicker = "color", Keybind = "keybind",
	SkinPicker = "skins", Chips = "choice",
}

function Library:OpenSearchModal()
	if self._execBlocked or self.WhatsNewModal then return end
	if self.SearchModal then self:CloseSearchModal(true) end
	local overlay = create("TextButton", {
		Name = "Search", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 60, Parent = self.Main,
	}, {corner(6)})
	self.SearchModal = overlay
	tween(overlay, {BackgroundTransparency = 0.5})

	local box = make("Frame", {
		Active = true, Size = UDim2.new(1, -60, 0, 0), AutomaticSize = AY, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84), BorderSizePixel = 0, Parent = overlay,
	}, {BackgroundColor3 = "PageRaised"}, {
		corner(6), stroke("Rule2"), list(0),
		create("UISizeConstraint", {MaxSize = Vector2.new(440, math.huge)}),
	})

	local inputRow = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 1, Parent = box})
	make("ImageLabel", {
		Image = asset(Library.Icons.Search), BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(0, 18, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = inputRow,
	}, {ImageColor3 = "Accent"})
	local input = make("TextBox", {
		Text = "", PlaceholderText = "Search features…", FontFace = FONTS.Body, TextSize = 15,
		ClearTextOnFocus = false, TextXAlignment = LEFT, BackgroundTransparency = 1,
		Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(46, 0), Parent = inputRow,
	}, {TextColor3 = "Text", PlaceholderColor3 = "SubText"})
	italicWhenEmpty(input)
	local escChip = keycap("ESC", inputRow, "SubText")
	escChip.TextSize = 10
	escChip.AnchorPoint = Vector2.new(1, 0.5)
	escChip.Position = UDim2.new(1, -18, 0.5, 0)
	make("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0, Parent = inputRow},
		{BackgroundColor3 = "Rule2"})

	local results = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, LayoutOrder = 2, Parent = box,
	}, {ScrollBarImageColor3 = "Rule2"}, {list(0)})

	local function tabNameOf(el)
		local t = el.Tab
		if not t then return "" end
		return t.IsSubTab and t.ParentTab.Name or t.Name
	end
	local function jump(el)
		local t = el.Tab
		if t then self:SelectTab(t) end -- SelectTab opens the parent first when t is a sub-tab
		self:CloseSearchModal()
	end

	local first
	local function render(q)
		for _, c in ipairs(results:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		q = string.lower(q or "")
		local hex = toHex(CURRENT_THEME.Accent)
		local items = {}
		for flag, el in pairs(Library.Elements) do
			local name = el.Name or flag
			if not el.Hidden and (q == "" or string.find(string.lower(name), q, 1, true) or string.find(string.lower(flag), q, 1, true)) then
				table.insert(items, el)
			end
		end
		table.sort(items, function(a, b) return tostring(a.Name) < tostring(b.Name) end)
		first = nil
		local count = 0
		for _, el in ipairs(items) do
			count += 1
			if count > 60 then break end
			local name = tostring(el.Name or el.Flag)
			local isFirst = count == 1
			local b = make("TextButton", {
				Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 40), BorderSizePixel = 0,
				BackgroundTransparency = isFirst and 0.96 or 1, LayoutOrder = count, Parent = results,
			}, {BackgroundColor3 = "Hover"})
			if isFirst then
				first = el
				make("Frame", {Size = UDim2.new(0, 2, 1, 0), BorderSizePixel = 0, Parent = b}, {BackgroundColor3 = "Accent"})
			end
			label({
				Text = highlight(name, q, hex), RichText = true, TextTruncate = TRUNC,
				Size = UDim2.new(1, -200, 1, 0), Position = UDim2.fromOffset(18, 0), Parent = b,
			})
			label({
				Text = TYPE_NAMES[el.Type] or string.lower(tostring(el.Type or "")), FontFace = FONTS.Italic, TextSize = 12,
				Role = "SubText", TextXAlignment = RIGHT, Size = UDim2.fromOffset(96, 40),
				Position = UDim2.new(1, -96, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = b,
			})
			label({
				Text = tabNameOf(el), FontFace = FONTS.Mono, TextSize = 10, Role = "SubText", TextXAlignment = RIGHT,
				TextTruncate = TRUNC, Size = UDim2.fromOffset(70, 40), Position = UDim2.new(1, -18, 0, 0),
				AnchorPoint = Vector2.new(1, 0), Parent = b,
			})
			make("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0, Parent = b},
				{BackgroundColor3 = "Rule"})
			b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = 0.96}) end)
			b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = isFirst and 0.96 or 1}) end)
			b.MouseButton1Click:Connect(function() jump(el) end)
		end
		if count == 0 then
			label({
				Text = "No matching features.", FontFace = FONTS.Italic, TextSize = 13, Role = "SubText",
				TextXAlignment = CENTER, Size = UDim2.new(1, 0, 0, 44), Parent = results,
			})
			results.Size = UDim2.new(1, 0, 0, 44)
		else
			results.Size = UDim2.new(1, 0, 0, math.min(count, 6) * 40)
		end
	end

	input:GetPropertyChangedSignal("Text"):Connect(function() render(input.Text) end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed and first and self.SearchModal == overlay then jump(first) end
	end)
	overlay.MouseButton1Click:Connect(function() self:CloseSearchModal() end)
	self._searchEsc = connect(UIS.InputBegan, function(i)
		if i.KeyCode == Enum.KeyCode.Escape and self.SearchModal == overlay then self:CloseSearchModal() end
	end)
	render("")
	input:CaptureFocus()
end

function Library:CloseSearchModal(instant)
	local overlay = self.SearchModal
	if not overlay then return end
	self.SearchModal = nil
	if self._searchEsc then
		pcall(function() self._searchEsc:Disconnect() end)
		self._searchEsc = nil
	end
	if instant then overlay:Destroy() return end
	for _, c in ipairs(overlay:GetChildren()) do
		if c:IsA("GuiObject") then c.Visible = false end
	end
	tween(overlay, {BackgroundTransparency = 1}, FAST).Completed:Connect(function()
		overlay:Destroy()
	end)
end

-- ---------------------------------------------------------------------------
-- WHAT'S NEW: the changelog card after a script's Version goes up
-- ---------------------------------------------------------------------------
-- Changelog entry: {Version = "1.0.1", New = {...}, Improved = {...}, Fixed = {...}, Removed = {...}, Notes = {...}}.
-- Each list holds plain strings (one string works too); Notes print without a heading.
local CHANGE_KINDS = {
	{Key = "New", Title = "New", Role = "Accent"},
	{Key = "Improved", Title = "Improved", Role = "Warning"},
	{Key = "Fixed", Title = "Fixed", Role = "Success"},
	{Key = "Removed", Title = "Removed", Role = "Danger"},
	{Key = "Notes", Role = "SubText"},
}

function Library:_showPendingWhatsNew()
	local pending = self._pendingChanges
	if not pending or self._execBlocked or self.Unloaded then return end
	self._pendingChanges = nil
	self:ShowWhatsNew(pending)
end

-- entries: changelog entries to show, newest first. Leave it out for the current version's notes.
function Library:ShowWhatsNew(entries)
	if self.Unloaded or not self.Version then return end
	entries = entries or {changesBetween(self.Changelog, nil, self.Version)[1]}
	if #entries == 0 then return end
	self:CloseSearchModal(true)
	self:CloseWhatsNew(true)
	local overlay = create("TextButton", {
		Name = "WhatsNew", Text = "", AutoButtonColor = false, Active = true, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 70, Parent = self.Main,
	}, {corner(6)})
	self.WhatsNewModal = overlay
	tween(overlay, {BackgroundTransparency = 0.5})
	playSound("Popup")

	local box = make("Frame", {
		Active = true, Size = UDim2.new(1, -60, 0, 0), AutomaticSize = AY, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BorderSizePixel = 0, ZIndex = 71, Parent = overlay,
	}, {BackgroundColor3 = "PageRaised"}, {
		corner(6), stroke("Rule2"), padding(22, 24), list(10),
		create("UISizeConstraint", {MaxSize = Vector2.new(440, math.huge)}),
	})
	local head = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, ZIndex = 72, Parent = box})
	label({
		Text = "What's new", FontFace = FONTS.HeadingBold, TextSize = 18,
		Size = UDim2.new(1, -90, 1, 0), ZIndex = 72, Parent = head,
	})
	label({
		Text = versionText(self.Version), FontFace = FONTS.Mono, TextSize = 12, Role = "Accent", TextXAlignment = RIGHT,
		Size = UDim2.new(0, 90, 1, 0), Position = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(1, 0), ZIndex = 72, Parent = head,
	})
	label({
		Text = track(self.Title), FontFace = FONTS.BodySemi, TextSize = 11, Role = "SubText", TextTruncate = TRUNC,
		Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 2, ZIndex = 72, Parent = box,
	})
	make("Frame", {Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, LayoutOrder = 3, ZIndex = 72, Parent = box}, {BackgroundColor3 = "Rule2"})

	-- The notes scroll once they outgrow the card (kept short enough for the smallest window).
	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, LayoutOrder = 4, ZIndex = 72, Parent = box,
	}, {ScrollBarImageColor3 = "Rule2"})
	local body = list(6)
	body.Parent = scroll
	local order = 0
	local function add(obj)
		order += 1
		obj.LayoutOrder = order
		obj.ZIndex = 72
		obj.Parent = scroll
		return obj
	end
	local function gap(h) add(create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h)})) end
	for i, entry in ipairs(entries) do
		if #entries > 1 then -- several versions since the last run: each gets its own number
			if i > 1 then gap(8) end
			add(label({Text = versionText(entry.Version), FontFace = FONTS.Mono, TextSize = 12, Size = UDim2.new(1, 0, 0, 18)}))
		end
		local firstKind = true
		for _, kind in ipairs(CHANGE_KINDS) do
			local items = entry[kind.Key]
			if type(items) == "string" then items = {items} end
			if type(items) == "table" and #items > 0 then
				if not firstKind then gap(2) end
				firstKind = false
				if kind.Title then
					add(label({Text = track(kind.Title), FontFace = FONTS.BodySemi, TextSize = 10, Role = kind.Role, Size = UDim2.new(1, 0, 0, 14)}))
				end
				for _, item in ipairs(items) do
					local line = add(create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = AY}))
					make("Frame", {Size = UDim2.fromOffset(6, 1), Position = UDim2.fromOffset(2, 9), BorderSizePixel = 0, ZIndex = 72, Parent = line},
						{BackgroundColor3 = kind.Role})
					label({
						Text = tostring(item), TextSize = 14, TextWrapped = true, LineHeight = 1.2,
						TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -18, 0, 0), AutomaticSize = AY,
						Position = UDim2.fromOffset(18, 0), ZIndex = 72, Parent = line,
					})
				end
			end
		end
	end
	local maxH = math.clamp(self.Main.Size.Y.Offset - 230, 120, 300)
	local function fit()
		local h = body.AbsoluteContentSize.Y / self:_uiScale()
		scroll.Size = UDim2.new(1, 0, 0, math.min(h, maxH))
		scroll.ScrollingEnabled = h > maxH
	end
	body:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()

	local row = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 5, ZIndex = 72, Parent = box},
		{list(0, H, {HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Bottom})})
	local btn = textButton(row, "Got it", "primary")
	btn.ZIndex = 73
	btn.MouseButton1Click:Connect(function()
		playSound("Click")
		self:CloseWhatsNew()
	end)
	overlay.MouseButton1Click:Connect(function() self:CloseWhatsNew() end)
	self._whatsNewEsc = connect(UIS.InputBegan, function(i)
		if i.KeyCode == Enum.KeyCode.Escape and self.WhatsNewModal == overlay then self:CloseWhatsNew() end
	end)
end

-- Closing the card marks this version as seen, so it shows once per update.
function Library:CloseWhatsNew(instant)
	local overlay = self.WhatsNewModal
	if not overlay then return end
	self.WhatsNewModal = nil
	if not self.Unloaded then Storage.saveSeenVersion(self.Version) end
	if self._whatsNewEsc then
		pcall(function() self._whatsNewEsc:Disconnect() end)
		self._whatsNewEsc = nil
	end
	if instant then overlay:Destroy() return end
	for _, c in ipairs(overlay:GetChildren()) do
		if c:IsA("GuiObject") then c.Visible = false end
	end
	tween(overlay, {BackgroundTransparency = 1}, FAST).Completed:Connect(function()
		overlay:Destroy()
	end)
end

-- ---------------------------------------------------------------------------
-- SETTINGS TAB & CONTROLS
-- ---------------------------------------------------------------------------
-- "Executor" at the top of Settings and Config, only on an unsupported executor
function Library:_executorSection(tab)
	if not Executor.Unsupported then return end
	tab:AddSection("Executor")
	tab:AddLabel(Executor.label() .. ": " .. Executor.Message, {Role = "Warning"})
end

-- Deletes the remembered choice for the current game (its GliderLoader/remember.json
-- entry), so the loader shows its menu again instead of auto-launching.
-- Saved keys are intentionally left alone. Returns 1 when an entry was removed.
local function ForgetLoaderSession()
	local removed = 0
	if not HAS_FS then return removed end
	local gameKey = tostring(game.GameId)
	pcall(function()
		local rememberPath = "GliderLoader/remember.json"
		if not isfile(rememberPath) then return end
		local raw = readfile(rememberPath)
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok or type(data) ~= "table" then
			pcall(function() delfile(rememberPath) end)
			return
		end
		if data[gameKey] == nil then return end
		data[gameKey] = nil
		removed = 1
		local empty = true
		for _ in pairs(data) do empty = false break end
		if empty then
			pcall(function() delfile(rememberPath) end)
		else
			pcall(writefile, rememberPath, HttpService:JSONEncode(data))
		end
	end)
	return removed
end

function Library:_buildSettingsTab(name, icon)
	local tab = self:AddTab(name or "Settings", icon or Library.Icons.Settings, true)

	self:_executorSection(tab)
	tab:AddSection("Theme")
	local tiles = tab:_block(104)
	local tileRow = create("Frame", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(PAD, 12), Size = UDim2.new(1, -PAD * 2, 0, 84), Parent = tiles,
	}, {list(14, H)})
	local views = {}
	local function bar(parent, x, y, frac, color)
		create("Frame", {
			Position = UDim2.fromOffset(x, y), Size = UDim2.new(frac, -x * 2, 0, 2), BackgroundColor3 = color,
			BorderSizePixel = 0, Parent = parent,
		}, {corner(1)})
	end
	for i, tname in ipairs(THEME_ORDER) do
		local th = THEMES[tname]
		local btn = create("TextButton", {
			Name = "Theme_" .. tname, Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
			Size = UDim2.fromOffset(112, 84), LayoutOrder = i, Parent = tileRow,
		})
		local preview = create("Frame", {
			Size = UDim2.fromOffset(112, 62), BackgroundColor3 = th.PageBg, BorderSizePixel = 0,
			ClipsDescendants = true, Parent = btn,
		}, {corner(4)})
		local ring = create("UIStroke", {Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = preview})
		local railPart = create("Frame", {
			Size = UDim2.new(0.3, 0, 1, 0), BackgroundColor3 = th.ChromeBg, BorderSizePixel = 0, Parent = preview,
		})
		bar(railPart, 5, 9, 0.7, th.ChromeAccent)
		bar(railPart, 5, 16, 0.6, th.ChromeSub)
		bar(railPart, 5, 23, 0.5, th.ChromeSub)
		local pagePart = create("Frame", {
			Size = UDim2.new(0.7, 0, 1, 0), Position = UDim2.fromScale(0.3, 0), BackgroundTransparency = 1, Parent = preview,
		})
		bar(pagePart, 7, 10, 0.6, th.Text)
		bar(pagePart, 7, 20, 1, th.Rule2)
		bar(pagePart, 7, 30, 1, th.Rule2)
		bar(pagePart, 7, 40, 0.35, th.Accent)
		if th.Binding then
			create("Frame", {
				Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = pagePart,
			}, {create("UIGradient", {Transparency = NumberSequence.new(0.6, 1)})})
		end
		local nameLabel = label({
			Text = tname, Role = false, TextSize = 13, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 68), Parent = btn,
		})
		views[tname] = {Ring = ring, Name = nameLabel}
		btn.MouseButton1Click:Connect(function()
			playSound("Click")
			self:SetTheme(tname)
			Storage.saveTheme(tname)
		end)
	end
	restyle(tileRow, function()
		local T = CURRENT_THEME
		for tname, v in pairs(views) do
			local on = self.ThemeName == tname
			v.Ring.Color = on and T.Accent or T.Rule2
			v.Ring.Thickness = on and 2 or 1
			v.Name.FontFace = on and FONTS.Italic or FONTS.Body
			v.Name.TextColor3 = on and T.Text or T.SubText
		end
	end)

	-- These switches are global preferences (see GLOBAL_FLAGS): saved outside any config.
	local function remember(flag, v)
		if not self.Unloaded then Storage.savePref(flag, v) end
	end

	tab:AddSection("Performance")
	local fpsToggle
	fpsToggle = tab:AddToggle({
		Name = "FPS Cap",
		Flag = "FpsCap",
		Default = self._fpsEnabled,
		Note = "Only supported executors.",
		Callback = function(v)
			if v and type(setfpscap) ~= "function" then
				fpsToggle:Set(false, true)
				self:Notify({Title = "FPS Cap", Body = "This executor doesn't support setfpscap.", Type = "Warning"})
				return
			end
			self._fpsEnabled = v
			remember("FpsCap", v)
			self:_applyFpsCap()
		end,
	})
	tab:AddSlider({
		Name = "Max FPS",
		Flag = "FpsCapValue",
		Min = FPS_MIN,
		Max = FPS_MAX,
		Default = self._fpsValue,
		CallbackOnRelease = true, -- setfpscap once the slider is let go, not on every step of the drag
		Callback = function(v)
			self._fpsValue = v
			if not self.Unloaded then Storage.saveFpsCap(v) end
			self:_applyFpsCap()
		end,
	})

	tab:AddSection("Menu")
	tab:AddKeybind({
		Name = "Open / Close Menu",
		Flag = "MenuKey",
		Default = Library.MenuKey,
		Callback = function(key)
			if not key then return end
			self:SetMenuKey(key)
			self:Notify({Title = "Keybind", Body = "Menu key set to " .. keyLabel(key), Type = "Success"})
		end,
	})
	tab:AddToggle({
		Name = "Free Mouse While Open",
		Flag = "FreeMouse",
		Default = self._freeMouse,
		Note = "The game can't lock or use the mouse while the menu is open.",
		Callback = function(v)
			self._freeMouse = v
			remember("FreeMouse", v)
			self:_applyFreeMouse()
		end,
	})
	tab:AddToggle({
		Name = "Sound Effects",
		Flag = "SoundFX",
		Default = SoundEnabled,
		Callback = function(v)
			SoundEnabled = v
			remember("SoundFX", v)
		end,
	})
	tab:AddToggle({
		Name = "Watermark",
		Flag = "ShowWatermark",
		Default = self._wmEnabled,
		Callback = function(v)
			self._wmEnabled = v
			if self.WatermarkFrame then self.WatermarkFrame.Visible = v end
			remember("ShowWatermark", v)
		end,
	})
	tab:AddToggle({
		Name = "Hide Username",
		Flag = "HideUsername",
		Default = self.HideUsername,
		Callback = function(v)
			self:SetHideUsername(v)
			remember("HideUsername", v)
		end,
	})
	tab:AddToggle({
		Name = "Keybinds HUD",
		Flag = "ShowKeybindHUD",
		Default = self._hudEnabled,
		Callback = function(v)
			self._hudEnabled = v
			self:UpdateKeybindHUD()
			remember("ShowKeybindHUD", v)
		end,
	})
	tab:AddToggle({
		Name = "Anti-AFK",
		Flag = "AntiAfk",
		Default = self.AntiAfkEnabled ~= false,
		Note = "Stops Roblox from kicking you after 20 idle minutes.",
		Callback = function(v) self:SetAntiAfk(v, false) end,
	})
	tab:AddSection("Session")
	tab:AddButton({
		Name = "Forget this script",
		Desc = "Clears the saved key and the remembered build, so the loader asks again next time.",
		Danger = true,
		Callback = function()
			local ok, removed = pcall(ForgetLoaderSession)
			if ok and (removed or 0) > 0 then
				self:Notify({Title = "Session", Body = "Script forgotten. The loader menu will show again.", Type = "Success"})
			elseif ok then
				self:Notify({Title = "Session", Body = "No remembered choice found for this game.", Type = "Info"})
			else
				self:Notify({Title = "Session", Body = "Could not access saved files.", Type = "Error"})
			end
		end,
	})
	if self.Version and #changesBetween(self.Changelog, nil, self.Version) > 0 then
		tab:AddButton({
			Name = "What's New in " .. versionText(self.Version),
			Callback = function() self:ShowWhatsNew() end,
		})
	end
	local unload = tab:AddButton({
		Name = "Unload " .. self.Brand,
		Danger = true,
		Callback = function() self:Unload() end,
	})
	self._unloadLabel = unload.Frame:FindFirstChild("Label")
	return tab
end

-- Sets the executor's FPS cap from the Performance settings. Turning the cap off puts back
-- the one from before the menu first changed it. Returns false when setfpscap is missing.
function Library:_applyFpsCap()
	if type(setfpscap) ~= "function" then return false end
	if self._fpsEnabled then
		if self._fpsRestore == nil then self._fpsRestore = currentFpsCap() end
		pcall(setfpscap, self._fpsValue)
	elseif self._fpsRestore ~= nil then
		pcall(setfpscap, self._fpsRestore)
		self._fpsRestore = nil
	end
	return true
end

-- ---------------------------------------------------------------------------
-- OPEN / CLOSE & VISIBILITY
-- ---------------------------------------------------------------------------
function Library:SetMenuKey(key)
	Library.MenuKey = key
	if self.KeyChip then self.KeyChip.Text = keyLabel(key) end
	Storage.saveMenuKey(key.Name)
end

-- ---------------------------------------------------------------------------
-- IDENTITY: brand wordmark, title, logo, and the username in the watermark
-- ---------------------------------------------------------------------------
function Library:SetBrand(text)
	self.Brand = tostring(text)
	if self.BrandLabel then self.BrandLabel.Text = self.Brand end
	if self._wmBrand then self._wmBrand.Text = self.Brand end
	if self._unloadLabel then self._unloadLabel.Text = "Unload " .. self.Brand end
end

function Library:SetTitle(text)
	self.Title = tostring(text)
	if self.GameLabel then self.GameLabel.Text = track(self.Title) end
	if self._wmTitle then self._wmTitle.Text = self.Title end
end

-- id: an image asset id (number or "rbxassetid://…"), or nil to go back to the Plume.
-- tint: false keeps the image's own colours; true (default) tints it with the accent.
function Library:SetLogo(id, tint)
	self.Logo = id
	if tint ~= nil then self.LogoTint = tint end
	for i = #self._marks, 1, -1 do
		local mark = self._marks[i]
		if mark[1].Parent == nil then
			table.remove(self._marks, i)
		else
			fillMark(mark[1], mark[2], self)
		end
	end
end

function Library:SetHideUsername(on)
	self.HideUsername = on == true
	if self._wmUser then self._wmUser.Visible = not self.HideUsername end
	if self._wmUserSep then self._wmUserSep.Visible = not self.HideUsername end
end

-- Free mouse (Settings > Menu, on by default, PC only). While the menu is open a full-screen Modal
-- shield sits under the window: Modal frees a first-person mouse lock natively and the shield takes the
-- clicks meant for the world. The only other thing touched is the cursor's visibility, switched back on
-- if the game hides it. Nothing else of the game's mouse or input handling is changed: anti-cheats react
-- to that (Rivals froze the client in duels when the menu disabled its mouse handlers).
local FREE_MOUSE_STEP = "UIAPI_FreeMouse"
function Library:_applyFreeMouse()
	local want = self._freeMouse == true and self.Visible == true and not self.Unloaded and not IS_MOBILE
	if self.MouseShield and self.MouseShield.Parent then self.MouseShield.Visible = want end
	if want == (self._mouseFreed == true) then return end
	self._mouseFreed = want
	if want then
		self._iconPrev = UIS.MouseIconEnabled
		pcall(function()
			RunService:BindToRenderStep(FREE_MOUSE_STEP, Enum.RenderPriority.Last.Value + 1, function()
				if not UIS.MouseIconEnabled then UIS.MouseIconEnabled = true end
			end)
		end)
	else
		pcall(function() RunService:UnbindFromRenderStep(FREE_MOUSE_STEP) end)
		if self._iconPrev ~= nil then pcall(function() UIS.MouseIconEnabled = self._iconPrev end) end
		self._iconPrev = nil
	end

local brandAnimToken = 0
function Library:_animateBrandMark()
	local mark = self.BrandMark
	if not mark or not mark.Parent then return end
	local scale = mark:FindFirstChild("BrandMarkScale")
	if not scale then
		scale = create("UIScale", {Name = "BrandMarkScale", Scale = 1, Parent = mark})
	end
	local plane = mark:FindFirstChild("PaperPlane") or mark:FindFirstChildOfClass("ImageLabel")

	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.ZIndex = 25
	if plane then plane.ZIndex = 26 end

	brandAnimToken += 1
	local myToken = brandAnimToken

	-- Aerodynamic Diagonal Entrance Flight Path:
	-- P0: Enters diagonally from the lower-left edge (clipped outside Main) (X = -45, Y = 280)
	-- P1: Flight control apex (X = -5, Y = 115)
	-- P2: Soft landing dock (X = 29, Y = 30)
	local p0 = Vector2.new(-45, 280)
	local p1 = Vector2.new(-5, 115)
	local p2 = Vector2.new(29, 30)

	local duration = 0.52
	local elapsed = 0

	task.spawn(function()
		while elapsed < duration do
			local dt = RunService.RenderStepped:Wait()
			if brandAnimToken ~= myToken or not mark or not mark.Parent then return end
			elapsed = math.min(duration, elapsed + dt)

			local linearT = elapsed / duration
			local t = 1 - (1 - linearT) ^ 4 -- EaseOutQuart aerodynamic glide

			local u = 1 - t
			local x = u * u * p0.X + 2 * u * t * p1.X + t * t * p2.X
			local y = u * u * p0.Y + 2 * u * t * p1.Y + t * t * p2.Y

			local dx = 2 * u * (p1.X - p0.X) + 2 * t * (p2.X - p1.X)
			local dy = 2 * u * (p1.Y - p0.Y) + 2 * t * (p2.Y - p1.Y)
			local flightAngle = math.deg(math.atan2(dy, dx))
			local idealRot = flightAngle + 41
			local rot = idealRot * (1 - (t ^ 1.8))

			mark.Position = UDim2.fromOffset(x, y)
			mark.Rotation = rot
			scale.Scale = 0.55 + 0.45 * (t ^ 0.7)

			if plane then
				plane.ImageTransparency = math.clamp(1 - linearT * 3.5, 0, 1)
			end
		end

		if brandAnimToken == myToken and mark and mark.Parent then
			mark.Position = UDim2.fromOffset(p2.X, p2.Y)
			mark.Rotation = 0
			scale.Scale = 1.0
			if plane then plane.ImageTransparency = 0 end
		end
	end)
end
end

function Library:SetVisible(v)
	if v == self.Visible and self.Main.Visible == v then return end
	local changed = v ~= self.Visible
	self.Visible = v
	self:_applyFreeMouse()
	if changed then
		for _, fn in ipairs(self._visibilityCallbacks) do task.spawn(pcall, fn, v) end
	end
	if v then
		self.Main.Visible = true
		self.Scale.Scale = 0.96
		-- Re-fit on open: the screen may have rotated while hidden.
		if IS_MOBILE then pcall(function() self:_applyFit() end) end
		tween(self.Scale, {Scale = 1}, SLIDE)
		if self.MobileIcon then self.MobileIcon.Visible = false end
		if self.BrandMark then self:_animateBrandMark() end
		if self._sidePanels then
			for _, sp in ipairs(self._sidePanels) do
				sp.WindowVisible = true
				if sp.IsOpen and sp.Frame then sp.Frame.Visible = true end
			end
		end
	else
		if self.Popup then self.Popup:Destroy(); self.Popup = nil end
		if self._popups then
			for i = #self._popups, 1, -1 do
				local p = self._popups[i]
				if p and p.Close then pcall(function() p:Close() end) end
			end
			table.clear(self._popups)
		end
		self:CloseSearchModal(true)
		if self._sidePanels then
			for _, sp in ipairs(self._sidePanels) do
				sp.WindowVisible = false
				if sp.Frame then sp.Frame.Visible = false end
			end
		end
		tween(self.Scale, {Scale = 0.96}, FAST).Completed:Connect(function()
			if not self.Visible then self.Main.Visible = false; self.Scale.Scale = 1 end
		end)
		if IS_MOBILE and self.MobileIcon then
			self.MobileIcon.Visible = true
			self.MobileScale.Scale = 0
			tween(self.MobileScale, {Scale = 1}, SLIDE)
		else
			self:Notify({Title = "Menu Hidden", Body = "Press " .. keyLabel(Library.MenuKey) .. " to open the menu", Type = "Info", Duration = 2.5})
		end
	end
end

-- ---------------------------------------------------------------------------
-- UNLOAD & CLEANUP
-- ---------------------------------------------------------------------------
-- fn(open) runs whenever the menu opens or closes, and once right away with the current state.
-- For game-specific input gating (a game's own "menu is open" switch) in the calling script.
function Library:OnVisibilityChanged(fn)
	table.insert(self._visibilityCallbacks, fn)
	task.spawn(pcall, fn, self.Visible ~= false)
end

function Library:OnUnload(fn)
	table.insert(self._unloadCallbacks, fn)
end

function Library:Unload(instant)
	if self.Unloaded then return end
	self.Unloaded = true
	self:_applyFreeMouse() -- hand the mouse back before anything else goes
	-- The anti-AFK connection belongs to the menu, so it goes with it.
	pcall(antiAfkStop)
	self._applying = true
	for _, el in pairs(Library.Elements) do
		if el.Type == "Toggle" and el.Value and not GLOBAL_FLAGS[el.Flag] and not el.NoSave then pcall(el.Set, el, false) end
	end
	self._applying = false
	for _, fn in ipairs(self._unloadCallbacks) do pcall(fn) end
	if self._sidePanels then
		for _, sp in ipairs(self._sidePanels) do pcall(function() sp:Destroy() end) end
		table.clear(self._sidePanels)
	end
	-- the game gets its own FPS cap back; the saved setting re-applies on the next load
	if self._fpsRestore ~= nil then pcall(setfpscap, self._fpsRestore) end
	for _, c in ipairs(CONNS) do pcall(function() c:Disconnect() end) end
	table.clear(CONNS)
	table.clear(Library.Elements) -- a window built after this starts with every name free again

	if getgenv then getgenv()[GLOBAL_KEY] = nil end
	if not instant and self.Main and self.Scale then
		self.Main.Active = false
		tween(self.Scale, {Scale = 0.9}, FAST).Completed:Connect(function()
			self.Gui:Destroy()
			sweepRegistries()
		end)
	else
		self.Gui:Destroy()
		sweepRegistries()
	end
end

-- ---------------------------------------------------------------------------
-- MOBILE REOPEN WIDGET
-- ---------------------------------------------------------------------------
function Library:_buildMobileIcon()
	local icon = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(50, 50),
		Position = UDim2.new(0, 24, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BorderSizePixel = 0,
		Visible = false,
		Parent = self.Gui,
	}, {BackgroundColor3 = "ChromeBg"}, {corner(25), stroke("ChromeRule")})
	self.MobileScale = create("UIScale", {Scale = 1, Parent = icon})
	plume(icon, 26, "Chrome", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)}, self)

	local moved = false
	icon.InputBegan:Connect(function(i) if isPress(i) then moved = false end end)
	icon.InputChanged:Connect(function(i) if isMove(i) then moved = true end end)
	icon.InputEnded:Connect(function(i)
		if isPress(i) and not moved then
			playSound("Click")
			self:SetVisible(true)
		end
	end)
	makeDraggable(icon, icon)
	self.MobileIcon = icon
end

-- ---------------------------------------------------------------------------
-- KEYBIND INPUT DISPATCHER
-- ---------------------------------------------------------------------------
function Library:_bindInput()
	connect(UIS.InputBegan, function(input, gameProcessed)
		local key = inputKey(input)
		if not key or self.Listening then return end
		-- gameProcessed is also set when a game binds the same input itself (ContextActionService sinks
		-- it; shooters bind mouse 1-3 to fire / aim / ping), so it can't decide alone. Keys: only a focused
		-- text box (typing in chat or a field) stops a bind. Mouse buttons: only a click on the menu does.
		local typing = UIS:GetFocusedTextBox() ~= nil
		if key == Library.MenuKey then -- the menu key works whatever handled it (a mouse menu key must close it too)
			if not typing then self:SetVisible(not self.Visible) end
			return
		end
		if gameProcessed then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				if typing then return end
			elseif self.Visible then
				return -- with the menu open, a click belongs to the menu (and its full-screen shield)
			end
		end
		-- Ctrl+K for search
		local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		if ctrl and key == Enum.KeyCode.K then
			if self.Visible then self:OpenSearchModal() end
			return
		end
		for flag, bind in pairs(Library.Binds) do
			local el = Library.Elements[flag]
			if el and bind.Key == key then
				if el.Type == "Toggle" then
					if bind.Mode == "Toggle" then el:Set(not el.Value)
					elseif bind.Mode == "Hold" then el:Set(true) end
				elseif el.Type == "Button" and el.Press then el:Press()
				elseif el.Type == "Dropdown" and el.Cycle then el:Cycle()
				end
				self:UpdateKeybindHUD()
			end
		end
	end)

	connect(UIS.InputEnded, function(input)
		local key = inputKey(input)
		if not key then return end
		for flag, bind in pairs(Library.Binds) do
			local el = Library.Elements[flag]
			if el and bind.Key == key and bind.Mode == "Hold" then
				el:Set(false)
				self:UpdateKeybindHUD()
			end
		end
	end)
end

function Library:ListenForKey(cb)
	self.Listening = true
	local conn
	conn = UIS.InputBegan:Connect(function(input)
		local key = inputKey(input)
		if not key then return end
		conn:Disconnect()
		task.defer(function() self.Listening = false end)
		cb(key ~= Enum.KeyCode.Escape and key or nil)
	end)
end

-- ---------------------------------------------------------------------------
-- NOTIFICATION SYSTEM (Success, Warning, Error, Info)
-- Supports both Window:Notify("Title", "Body", 3.5) and Window:Notify({Title=..., Body=..., Type=...})
-- ---------------------------------------------------------------------------
local TOAST_ROLES = {Success = "ToastSuccess", Warning = "ToastWarning", Error = "ToastError", Info = "ChromeAccent"}

function Library:Notify(opts, body, duration)
	if self._applying or (Library._window and Library._window._applying) then return end
	if type(opts) == "string" then
		opts = {Title = opts, Body = body or "", Duration = duration or 3.5, Type = "Info"}
	end
	local title = opts.Title or "Notification"
	local notifBody = opts.Body or ""
	local dur = opts.Duration or 3.5
	local nType = TOAST_ROLES[opts.Type] and opts.Type or "Info"
	local role = TOAST_ROLES[nType]
	playSound("Notify")

	local slot = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AY,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = self.NotifHolder,
	})
	local card = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AY,
		Position = UDim2.fromOffset(320, 0),
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Parent = slot,
	}, {BackgroundColor3 = "ChromeRaised"}, {corner(3), stroke("Edge")})
	make("Frame", {Size = UDim2.new(0, 2, 1, 0), BorderSizePixel = 0, ZIndex = 2, Parent = card}, {BackgroundColor3 = role})

	local inner = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AY,
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		create("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14),
		}),
		list(4),
	})
	label({
		Text = track(nType), FontFace = FONTS.BodySemi, TextSize = 9, Role = role,
		Size = UDim2.new(1, 0, 0, 11), LayoutOrder = 1, Parent = inner,
	})
	label({
		Text = title, FontFace = FONTS.Heading, TextSize = 14, Role = "ChromeText", TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, LayoutOrder = 2, Parent = inner,
	})
	if notifBody ~= "" then
		label({
			Text = notifBody, TextSize = 13, Role = "ChromeSub", TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, LayoutOrder = 3, Parent = inner,
		})
	end

	local timer = make("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	}, {BackgroundColor3 = role})

	tween(card, {Position = UDim2.new()}, SLIDE)
	tween(timer, {Size = UDim2.new(0, 0, 0, 1)}, TweenInfo.new(dur, Enum.EasingStyle.Linear))

	task.delay(dur, function()
		if not slot.Parent then return end
		tween(card, {Position = UDim2.fromOffset(320, 0)}, FAST).Completed:Wait()
		slot:Destroy()
	end)
end

-- ---------------------------------------------------------------------------
-- TABS & SUBTABS
-- ---------------------------------------------------------------------------
local PINNED_GLYPHS = {Settings = "§", Config = "¶", Discord = "@"}

function Library:AddTab(name, icon, pinned)
	local tab = setmetatable({Name = name, Window = self, Pinned = pinned or false, _secCount = 0}, Tab)
	self._tabCount += 1
	if pinned then
		self._pinnedCount += 1
	else
		self._tabNum += 1
	end

	tab.Button = create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = (pinned and 10 or 0) + self._tabCount,
		Parent = pinned and self.PinnedList or self.TabList,
	})
	if icon then
		tab.Icon = create("ImageLabel", {
			Image = asset(icon),
			ImageColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(0, 21, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = tab.Button,
		})
	else
		tab.Num = label({
			Text = pinned and (PINNED_GLYPHS[name] or "·") or string.format("%02d", self._tabNum),
			FontFace = FONTS.Mono, TextSize = 10, Role = false,
			Size = UDim2.fromOffset(18, 34), Position = UDim2.fromOffset(20, 0), Parent = tab.Button,
		})
	end
	tab.NameLabel = label({
		Text = name, Role = false, TextSize = 14, AutomaticSize = AX,
		Size = UDim2.fromOffset(0, 34), Position = UDim2.fromOffset(46, 0), Parent = tab.Button,
	})
	tab.Badge = label({
		Text = "", FontFace = FONTS.Italic, TextSize = 10, Role = "ChromeAccent", AutomaticSize = AX,
		Size = UDim2.fromOffset(0, 12), Position = UDim2.fromOffset(50, 6), Visible = false, Parent = tab.Button,
	})
	local function placeBadge()
		tab.Badge.Position = UDim2.fromOffset(46 + tab.NameLabel.TextBounds.X + 3, 6)
	end
	tab.NameLabel:GetPropertyChangedSignal("TextBounds"):Connect(placeBadge)
	tab.NameLabel:GetPropertyChangedSignal("FontFace"):Connect(placeBadge)
	placeBadge()

	if IS_MOBILE and pinned then
		-- Touch layout: the pinned tabs are an icon row, so nothing but the glyph shows.
		tab.NameLabel.Visible = false
		tab.Badge.Visible = false
		if tab.Icon then
			tab.Icon.Position = UDim2.fromScale(0.5, 0.5)
			tab.Icon.AnchorPoint = Vector2.new(0.5, 0.5)
			tab.Icon.Size = UDim2.fromOffset(16, 16)
		end
		if tab.Num then
			tab.Num.Position = UDim2.new(0.5, -9, 0, 0)
			tab.Num.Size = UDim2.fromOffset(18, 34)
			tab.Num.TextXAlignment = CENTER
		end
	end

	function tab._paint(animate)
		local T = CURRENT_THEME
		local on = self.CurrentTab == tab
		local info = animate and FAST or nil
		tab.NameLabel.FontFace = on and FONTS.Italic or FONTS.Body
		apply(tab.NameLabel, {TextColor3 = (on or tab._hover) and T.ChromeText or T.ChromeSub}, info)
		local slot = on and T.ChromeAccent or (tab._hover and T.ChromeText or T.ChromeSub)
		if tab.Icon and self.TintIcons then apply(tab.Icon, {ImageColor3 = slot}, info) end
		if tab.Num then apply(tab.Num, {TextColor3 = slot}, info) end
	end
	restyle(tab.Button, function() tab._paint(false) end)

	tab.Page = make("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AY,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = self.Content,
	}, {ScrollBarImageColor3 = "Rule2"}, {
		list(0),
		-- 1px left/top inset so the sheets' outer borders aren't clipped by the page
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 1), PaddingTop = UDim.new(0, 1),
			PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 18),
		}),
	})

	tab.Button.MouseButton1Click:Connect(function()
		playSound("Tab")
		self:SelectTab(tab)
	end)
	tab.Button.MouseEnter:Connect(function() tab._hover = true; tab._paint(true) end)
	tab.Button.MouseLeave:Connect(function() tab._hover = false; tab._paint(true) end)
	tab.Button:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if self.CurrentTab == tab then self:_syncMarker(false) end
	end)

	table.insert(self.Tabs, tab)
	if pinned then self:_layoutRail() end
	task.defer(function() self:_refreshTabCanvas() end)
	if not self.CurrentTab or (self.CurrentTab.Pinned and not pinned) then self:SelectTab(tab) end
	return tab
end

function Tab:SetBadge(text)
	if not self.Badge then return end
	self.Badge.Text = tostring(text or "")
	self.Badge.Visible = text ~= nil and text ~= ""
end

-- ---------------------------------------------------------------------------
-- SIDE PANEL: a page attached to the window's right edge, as tall as the window.
--   local panel = Window:AddPanel({
--     Title = "Chams", Width = 340,
--     Tab = VisualsTab,      -- only shown while this tab (or sub-tab) is open (omit: every tab)
--     ShowFlag = "ChamsOn",  -- only shown while this flag is on (omit: always)
--     Manual = true,         -- hidden until panel:SetOpen(true); gets a close button (OnClose = fn)
--   })
--   panel:SetTitle(text) renames it.
--   panel:AddToggle({...})  -- every Tab:Add* element works on it
-- It follows the window when dragged and scales with it.
-- ---------------------------------------------------------------------------
function Library:AddPanel(opts)
	opts = opts or {}
	local GAP, W = 10, opts.Width or 340
	local panel = setmetatable({Name = opts.Title or "Panel", Window = self, _secCount = 0, IsPanel = true, HostTab = opts.Tab}, Tab)
	local frame = make("Frame", {
		Name = "SidePanel", Visible = false, BorderSizePixel = 0, ClipsDescendants = true,
		Size = UDim2.fromOffset(W, self.Main.Size.Y.Offset), Parent = self.Gui,
	}, {BackgroundColor3 = "PageBg"}, {corner(6), stroke("Edge")})
	local scale = create("UIScale", {Scale = 1, Parent = frame})
	grain(frame, "Text")
	panel.Frame = frame
	local head = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), Parent = frame})
	local titleLabel = label({
		Text = panel.Name, FontFace = FONTS.Heading, TextSize = 17, AutomaticSize = AX,
		Size = UDim2.fromOffset(0, 52), Position = UDim2.fromOffset(18, 0), Parent = head,
	})
	function panel:SetTitle(text) titleLabel.Text = tostring(text or "") end
	-- Manual panels open with panel:SetOpen(true) and get a close button
	panel.Open = not opts.Manual
	function panel:SetOpen(v) self.Open = v == true end
	if opts.Manual then
		local close = create("TextButton", {
			Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -12, 0, 26), AnchorPoint = Vector2.new(1, 0.5), Parent = head,
		}, {corner(6)})
		local bars = {}
		for _, rot in ipairs({45, -45}) do
			table.insert(bars, make("Frame", {
				Size = UDim2.fromOffset(13, 2), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = rot, BorderSizePixel = 0, Parent = close,
			}, {BackgroundColor3 = "SubText"}))
		end
		paint(close, {BackgroundColor3 = "Hover"})
		close.MouseEnter:Connect(function() tween(close, {BackgroundTransparency = 0.9}) end)
		close.MouseLeave:Connect(function() tween(close, {BackgroundTransparency = 1}) end)
		close.MouseButton1Click:Connect(function()
			playSound("Click")
			panel:SetOpen(false)
			if opts.OnClose then pcall(opts.OnClose) end
		end)
	end
	make("Frame", {
		Size = UDim2.new(1, -36, 0, 1), Position = UDim2.new(0, 18, 1, -1), BorderSizePixel = 0, Parent = head,
	}, {BackgroundColor3 = "Rule2"})
	panel.Page = make("ScrollingFrame", {
		Name = panel.Name, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 1, -62), Position = UDim2.fromOffset(12, 58),
		ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = frame,
	}, {ScrollBarImageColor3 = "Rule2"}, {
		list(0),
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 1), PaddingTop = UDim.new(0, 1),
			PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 14),
		}),
	})

	-- slides out from behind the window's edge when it opens, tucks back when it closes
	local shown = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not frame.Parent then conn:Disconnect() return end
		local host = panel.HostTab
		-- a sub-tab host counts only while its parent tab is open on that sub-tab
		local onHost = not host or (host.IsSubTab and self.CurrentTab == host.ParentTab and host.ParentTab.CurrentSubTab == host)
			or self.CurrentTab == host
		local want = self.Visible and self.Main.Visible and onHost and panel.Open
			and (not opts.ShowFlag or (Library.Flags[opts.ShowFlag] ~= nil and Library.Flags[opts.ShowFlag] ~= false))
		shown = math.clamp(shown + (want and dt or -dt) * 7, 0, 1)
		frame.Visible = shown > 0.001
		if not frame.Visible then return end
		local k = self:_uiScale() -- the window's size on screen vs its design size, open/close tween included
		scale.Scale = k
		frame.Size = UDim2.fromOffset(W, self.Main.Size.Y.Offset)
		local origin = self.Gui.AbsolutePosition
		local pos = self.Main.AbsolutePosition - origin
		local ease = 1 - (1 - shown) ^ 3
		frame.Position = UDim2.fromOffset(pos.X + self.Main.AbsoluteSize.X + (GAP - 24 * (1 - ease)) * k, pos.Y)
	end)
	return panel
end

function Library:SelectTab(tab)
	if type(tab) == "string" then
		for _, t in ipairs(self.Tabs) do
			if t.Name == tab then
				tab = t
				break
			end
		end
	end
	if type(tab) ~= "table" then return end
	if tab.IsPanel then -- a side panel isn't a page: open the tab it belongs to instead
		if tab.HostTab then self:SelectTab(tab.HostTab) end
		return
	end
	if tab.IsSubTab then -- a sub-tab lives inside its parent: open the parent, then the sub-tab
		self:SelectTab(tab.ParentTab)
		tab.ParentTab:SelectSubTab(tab)
		return
	end
	local prev = self.CurrentTab
	self.CurrentTab = tab
	for _, t in ipairs(self.Tabs) do
		t.Page.Visible = t == tab
		t._paint(true)
	end
	if self._sidePanels then
		for _, sp in ipairs(self._sidePanels) do
			if sp.BoundTab and tab.Name ~= sp.BoundTab and sp.IsOpen then
				sp:Close()
			elseif sp.BoundTab and tab.Name == sp.BoundTab and not sp.IsOpen and (sp.AutoOpen ~= false) then
				sp:Open()
			end
		end
	end
	self.PageTitle.Text = tab.Name
	self:_syncMarker(prev ~= nil and prev ~= tab)
	task.defer(function()
		if self.CurrentTab == tab and not self.Unloaded then self:_syncMarker(false) end
	end)
	if prev and prev ~= tab then
		self.Veil.BackgroundTransparency = 0
		tween(self.Veil, {BackgroundTransparency = 1}, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		tab.Page.Position = UDim2.fromOffset(0, 8)
		tween(tab.Page, {Position = UDim2.new()}, SLIDE)
	end
end

-- Moves the rail marker to the current tab (glides when animate is true).
function Library:_syncMarker(animate)
	local tab, m, rail = self.CurrentTab, self.TabMarker, self.TabRail
	if not (tab and m and rail) then return end
	local btn = tab.Button
	if btn.AbsoluteSize.Y < 1 or rail.AbsoluteSize.X < 1 then
		m.Visible = false
		return -- not laid out yet; the AbsolutePosition listener syncs again once it is
	end
	local s = self:_uiScale()
	local y = math.floor((btn.AbsolutePosition.Y - rail.AbsolutePosition.Y) / s + 0.5)
	local railH = rail.AbsoluteSize.Y / s
	local visible = tab.Pinned or (y >= (self._brandH or BRAND_H) - 4 and y <= railH - self.Foot.Size.Y.Offset - 30)
	local goal = UDim2.fromOffset(0, y)
	if IS_MOBILE and tab.Pinned then
		m.Size = UDim2.fromOffset(math.floor(btn.AbsoluteSize.X / s + 0.5), 34)
		goal = UDim2.fromOffset(math.floor((btn.AbsolutePosition.X - rail.AbsolutePosition.X) / s + 0.5), y)
	else
		m.Size = UDim2.new(1, -1, 0, 34)
	end
	if animate and visible and m.Visible then
		tween(m, {Position = goal}, SLIDE)
	else
		m.Position = goal
	end
	m.Visible = visible
end

-- ---------------------------------------------------------------------------
-- SUB-TABS
-- ---------------------------------------------------------------------------
-- Tab:AddSubTab(name, icon, opts): opts.IconSize = Vector2 for a wide icon (e.g. a weapon picture,
-- fitted inside). sub:SetMarked(true) puts a small accent dot on its button.
function Tab:AddSubTab(name, icon, opts)
	opts = opts or {}
	if self.IsSubTab then error("Sub-tabs cannot be nested", 2) end
	if not self.SubBar then
		self.SubTabs, self._subCount = {}, 0
		self.SubBar = create("Frame", {
			Name = "SubTabs",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = -1000,
			Parent = self.Page,
		})
		make("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0, Parent = self.SubBar},
			{BackgroundColor3 = "Rule2"})
		-- scrolls sideways (wheel or drag) when the sub-tabs don't fit
		self.SubItems = create("ScrollingFrame", {
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = self.SubBar,
			ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = AX,
		}, {list(22, H, {VerticalAlignment = Enum.VerticalAlignment.Bottom}), create("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4)})})
	end
	self._subCount += 1
	local sub = setmetatable({Name = name, Window = self.Window, ParentTab = self, IsSubTab = true, _secCount = 0}, Tab)
	local iconSize = opts.IconSize or Vector2.new(14, 14)
	local iconPad = icon and (iconSize.X + 6) or 0

	sub.Button = create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AutomaticSize = AX,
		Size = UDim2.fromOffset(0, 36),
		LayoutOrder = self._subCount,
		Parent = self.SubItems,
	}, {create("UIPadding", {PaddingLeft = UDim.new(0, iconPad)})})
	sub.Label = label({
		Text = name, Role = false, TextSize = 14, AutomaticSize = AX, Size = UDim2.fromOffset(0, 36), Parent = sub.Button,
	})
	if icon then
		sub.Icon = create("ImageLabel", {
			Image = asset(icon),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(iconSize.X, iconSize.Y),
			Position = UDim2.new(0, -iconPad, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = sub.Button,
		})
	end
	sub.Under = make("Frame", {
		Size = UDim2.new(0, 0, 0, 2), Position = UDim2.new(0, -iconPad, 1, -2), BorderSizePixel = 0, Parent = sub.Button,
	}, {BackgroundColor3 = "Accent"})
	sub._iconPad = iconPad
	local dot = make("Frame", {
		Size = UDim2.fromOffset(5, 5), Position = UDim2.new(1, 4, 0, 9), AnchorPoint = Vector2.new(0, 0.5),
		BorderSizePixel = 0, Visible = false, Parent = sub.Button,
	}, {BackgroundColor3 = "Accent"}, {corner(3)})
	function sub:SetMarked(on) dot.Visible = on == true end

	sub.Page = create("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AY,
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = -999,
		Parent = self.Page,
	}, {list(0)})

	function sub._paint(animate)
		local T = CURRENT_THEME
		local on = self.CurrentSubTab == sub
		local info = animate and FAST or nil
		sub.Label.FontFace = on and FONTS.Italic or FONTS.Body
		apply(sub.Label, {TextColor3 = (on or sub._hover) and T.Text or T.SubText}, info)
		if sub.Icon then
			apply(sub.Icon, {ImageColor3 = on and T.Accent or (sub._hover and T.Text or T.SubText)}, info)
		end
	end
	restyle(sub.Button, function() sub._paint(false) end)

	sub.Button.MouseButton1Click:Connect(function()
		playSound("Click")
		self:SelectSubTab(sub)
	end)
	sub.Button.MouseEnter:Connect(function() sub._hover = true; sub._paint(true) end)
	sub.Button.MouseLeave:Connect(function() sub._hover = false; sub._paint(true) end)

	table.insert(self.SubTabs, sub)
	if not self.CurrentSubTab then self:SelectSubTab(sub) end
	return sub
end

function Tab:SelectSubTab(sub)
	self.CurrentSubTab = sub
	for _, s in ipairs(self.SubTabs or {}) do
		local on = s == sub
		s.Page.Visible = on
		s._paint(true)
		tween(s.Under, {Size = on and UDim2.new(1, s._iconPad, 0, 2) or UDim2.new(0, 0, 0, 2)}, on and SLIDE or FAST)
	end
end

-- ---------------------------------------------------------------------------
-- ELEMENT REGISTRATION & BASE ROW
-- Every row sits on a section's sheet: a raised panel with a soft border. Rows on a
-- sheet are split by inset rules, and each section header (numeral, title, rule) sits
-- above its sheet with clear space before it, so sections read as separate groups.
-- ---------------------------------------------------------------------------
local ROW_H = 44

local function newSheet(tab)
	local body = make("Frame", {
		Name = "Sheet", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BorderSizePixel = 0, Parent = tab.Page,
	}, {BackgroundColor3 = "PageRaised"}, {corner(5), stroke("Rule2", 1, 0.45), list(0)})
	return {Rows = {}, Open = true, Body = body}
end

-- The sheet new rows go on; rows added before any AddSection get an untitled one.
local function sheetOf(tab)
	if not tab._section then tab._section = newSheet(tab) end
	return tab._section
end

-- A component container can be a tab (rows go into the current sheet) or a bare
-- Frame such as a card body (rows go straight into it). Widgets created inside a
-- card still register their flag and config against the tab that owns the card.
local function contentHost(host)
	if typeof(host) == "Instance" then
		return host, nil
	end
	local sec = sheetOf(host)
	return sec.Body, sec
end

local function nextOrder(host, parent)
	if typeof(host) == "Instance" then
		return #parent:GetChildren() + 1
	end
	return #sheetOf(host).Rows + 1
end

local function trackRow(host, frame)
	if typeof(host) ~= "Instance" then
		table.insert(sheetOf(host).Rows, frame)
	end
end

-- A row without hover (content blocks). Every row but a sheet's first gets an inset top rule.
local function block(tab, height)
	local parent, sec = contentHost(tab)
	local f = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(tab, parent),
		Parent = parent,
	})
	make("Frame", {
		Name = "Rule", Size = UDim2.new(1, -PAD * 2, 0, 1), Position = UDim2.fromOffset(PAD, 0),
		BackgroundTransparency = 0.35, BorderSizePixel = 0,
		Visible = sec ~= nil and #sec.Rows > 0, Parent = f,
	}, {BackgroundColor3 = "Rule2"})
	trackRow(tab, f)
	return f
end

-- A row with a hover tint (controls).
local function row(tab, height)
	local f = block(tab, height or ROW_H)
	paint(f, {BackgroundColor3 = "Hover"})
	f.MouseEnter:Connect(function() tween(f, {BackgroundTransparency = 0.96}) end)
	f.MouseLeave:Connect(function() tween(f, {BackgroundTransparency = 1}) end)
	return f
end

function Tab:_block(height) return block(self, height) end

local autosaveToken = 0
local function touch()
	local w = Library._window
	if not (w and w.AutoSave) or w._applying or w._building then return end
	if not w.ActiveConfig then
		w.ActiveConfig = Storage.getAutoload() or "default"
		if not Storage.getAutoload() then
			Storage.setAutoload(w.ActiveConfig)
		end
		w:_refreshConfigStatus()
	end
	autosaveToken += 1
	local token = autosaveToken
	task.delay(0.8, function()
		if token ~= autosaveToken then return end
		if w.AutoSave and w.ActiveConfig and not w._applying then Storage.save(w.ActiveConfig, w:Serialize()) end
	end)
end

-- A flag defaults to the element's name. When that is already taken (the same name on
-- two tabs), the element is filed under its tab path instead, e.g. "Visuals/ESP/Enabled",
-- so neither overwrites the other in Flags, configs, binds or search.
local function uniqueFlag(opts, tab)
	local flag = opts.Flag or opts.Name
	if Library.Elements[flag] == nil then return flag end
	local base = flag
	if not opts.Flag and tab then
		base = (tab.IsSubTab and (tab.ParentTab.Name .. "/") or "") .. tab.Name .. "/" .. flag
	end
	local candidate, n = base, 1
	while Library.Elements[candidate] ~= nil do
		n += 1
		candidate = base .. " " .. n
	end
	if opts.Flag then
		warn(("[UIAPI] Flag %q is already in use; %q is saved as %q instead"):format(flag, tostring(opts.Name), candidate))
	end
	return candidate
end

-- ---------------------------------------------------------------------------
-- DEPENDENT CONTROLS
-- opts.DependsOn hangs a control under another one: it unfolds (row height grows, like an
-- opening dropdown) while the other is on, and folds away while it is off.
--   DependsOn = "Flag"                                   shown while that flag is on
--   DependsOn = {Flag = "Flag", Values = {"A", "B"}}     shown while it is one of these (or, for a
--                                                        multi-select, while any of them is picked)
-- Chains work: a control under a hidden control is hidden too.
-- ---------------------------------------------------------------------------
local DEP_WATCH = {} -- flag -> controls that depend on it
local function depMet(el)
	local d = el._dep
	local parent = Library.Elements[d.Flag]
	if parent and parent._depHidden then return false end
	local v = Library.Flags[d.Flag]
	if d.Values then
		if type(v) == "table" then
			for _, x in ipairs(d.Values) do if table.find(v, x) then return true end end
			return false
		end
		return table.find(d.Values, v) ~= nil
	end
	if type(v) == "table" then return #v > 0 end
	return v ~= nil and v ~= false and v ~= "" and v ~= "None"
end
local applyDep
local function notifyDeps(flag)
	local list = DEP_WATCH[flag]
	if not list then return end
	local w = Library._window
	local instant = w and w._applying
	for _, el in ipairs(list) do applyDep(el, instant) end
end
function applyDep(el, instant)
	local f = el.Frame
	if not (f and f.Parent) then return end
	local show = depMet(el)
	if el._depReady and el._depHidden == not show then return end
	local first = not el._depReady
	el._depReady = true
	el._depHidden = not show
	if el._depClip == nil then el._depClip = f.ClipsDescendants end
	el._depTween = (el._depTween or 0) + 1
	local token = el._depTween
	if show then
		local h = el._depH or f.Size.Y.Offset
		f.Visible = true
		if instant or first then
			f.Size = UDim2.new(1, 0, 0, h)
			f.ClipsDescendants = el._depClip
		else
			f.ClipsDescendants = true
			f.Size = UDim2.new(1, 0, 0, 0)
			tween(f, {Size = UDim2.new(1, 0, 0, h)}, MED).Completed:Connect(function()
				if el._depTween == token then f.ClipsDescendants = el._depClip end
			end)
		end
	else
		if f.Size.Y.Offset > 0 then el._depH = f.Size.Y.Offset end
		f.ClipsDescendants = true
		if instant or first then
			f.Size = UDim2.new(1, 0, 0, 0)
			f.Visible = false
		else
			tween(f, {Size = UDim2.new(1, 0, 0, 0)}, MED).Completed:Connect(function()
				if el._depTween == token and el._depHidden then f.Visible = false end
			end)
		end
	end
	notifyDeps(el.Flag) -- anything hanging under this control follows it
end

-- el:SetLocked(true) greys an element out and blocks its input (e.g. settings that currently follow
-- another profile); its value still shows and can still be :Set() by the script
local function setLocked(el, locked)
	local f = el.Frame
	el.Locked = locked == true
	if not f then return end
	if el.Locked and not el._lock then
		el._lock = make("TextButton", {
			Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1), ZIndex = 60, Parent = f,
		}, {BackgroundColor3 = "PageBg"})
	end
	if el._lock then el._lock.Visible = el.Locked end
end


-- opts.NoSave = true: the control shows state the script keeps itself (e.g. the selected player's switches),
-- so configs never save, load or reset it, unloading never flips it, and the settings search skips it
local UNNAMED = 0
local function register(el, opts, tab)
	el.NoSave = opts.NoSave == true
	if opts.Flag == nil and opts.Name == nil then
		UNNAMED += 1
		opts.Flag = (el.Type or "Element") .. "#" .. UNNAMED
		el.NoSave = true
	end
	if el.NoSave then el.Hidden = true end
	el.Flag = uniqueFlag(opts, tab)
	el.SetLocked = setLocked
	el.Name = opts.Name or el.Flag
	el.Default = el.Value
	el.Tab = tab
	el.Callback = opts.Callback or function() end
	Library.Elements[el.Flag] = el
	Library.Flags[el.Flag] = el.Value
	if opts.DependsOn then
		local d = opts.DependsOn
		el._dep = type(d) == "string" and {Flag = d} or {Flag = d.Flag, Values = d.Values or (d.Value ~= nil and {d.Value} or nil)}
		DEP_WATCH[el._dep.Flag] = DEP_WATCH[el._dep.Flag] or {}
		table.insert(DEP_WATCH[el._dep.Flag], el)
		task.defer(function() applyDep(el, true) end) -- once the Add* call has built el.Frame
	end
end

-- ---------------------------------------------------------------------------
-- SECTIONS & LABELS
-- ---------------------------------------------------------------------------
function Tab:AddSection(text, opts)
	opts = opts or {}
	local first = self._section == nil -- the first group on a page needs no gap above it
	self._secCount = (self._secCount or 0) + 1
	local head = create("TextButton", {
		Name = "Section", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, first and 38 or 60), Parent = self.Page,
	})
	local num = label({
		Text = toRoman(self._secCount) .. ".", FontFace = FONTS.Italic, TextSize = 15, Role = "Accent",
		TextYAlignment = Enum.TextYAlignment.Bottom, AutomaticSize = AX,
		Size = UDim2.fromOffset(0, 20), Position = UDim2.new(0, 2, 1, -30), Parent = head,
	})
	local title = label({
		Text = text, FontFace = FONTS.Heading, TextSize = 16, TextYAlignment = Enum.TextYAlignment.Bottom,
		AutomaticSize = AX, Size = UDim2.fromOffset(0, 20), Position = UDim2.new(0, 24, 1, -30), Parent = head,
	})
	local rule = make("Frame", {
		Size = UDim2.new(1, -120, 0, 1), Position = UDim2.new(0, 100, 1, -18), BorderSizePixel = 0, Parent = head,
	}, {BackgroundColor3 = "Rule2"})
	local chevron
	if opts.Collapsible then
		chevron = label({
			Text = "▾", FontFace = FONTS.Symbol, TextSize = 11, Role = "SubText", TextXAlignment = CENTER,
			Size = UDim2.fromOffset(16, 20), Position = UDim2.new(1, -4, 1, -28), AnchorPoint = Vector2.new(1, 0), Parent = head,
		})
	end
	local function layout()
		local nx = 2 + num.TextBounds.X + 7
		title.Position = UDim2.new(0, nx, 1, -30)
		local rx = nx + title.TextBounds.X + 12
		rule.Position = UDim2.new(0, rx, 1, -18)
		rule.Size = UDim2.new(1, -rx - (chevron and 28 or 2), 0, 1)
	end
	num:GetPropertyChangedSignal("TextBounds"):Connect(layout)
	title:GetPropertyChangedSignal("TextBounds"):Connect(layout)
	layout()

	local sec = newSheet(self)
	sec.Name = text
	if chevron then
		head.MouseButton1Click:Connect(function()
			playSound("Click")
			sec.Open = not sec.Open
			sec.Body.Visible = sec.Open
			tween(chevron, {Rotation = sec.Open and 0 or -90}, FAST)
		end)
	end
	self._section = sec
	return self
end

-- Tab:AddLabel(text, opts): opts.Role = a theme colour for the text (e.g. "Danger", "Warning",
-- "Success", "SubText"); opts.Copy adds a copy button.
function Tab:AddLabel(text, opts)
	opts = opts or {}
	local f = row((opts and opts.Parent) or self, ROW_H)
	local l = label({
		Text = text,
		Role = opts.Role,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = AY,
		Size = UDim2.new(1, -PAD - (opts.Copy and 80 or PAD), 0, 0),
		Position = UDim2.fromOffset(PAD, 15),
		Parent = f,
	})
	local el = {Type = "Label", Frame = f}
	-- The row grows with wrapped text (long descriptions span several lines).
	local function fit()
		local textH = l.AbsoluteSize.Y / self.Window:_uiScale()
		local h = math.max(ROW_H, math.ceil(textH) + 30)
		-- folded away under DependsOn: remember the height for when it unfolds
		if el._depHidden then el._depH = h return end
		f.Size = UDim2.new(1, 0, 0, h)
	end
	l:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	if opts.Copy then
		local copyBtn = make("TextButton", {
			Text = track("Copy"), FontFace = FONTS.BodySemi, TextSize = 10, AutoButtonColor = false,
			BackgroundTransparency = 1, AutomaticSize = AX, Size = UDim2.fromOffset(0, ROW_H),
			Position = UDim2.new(1, -PAD, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = f,
		}, {TextColor3 = "Accent"})
		copyBtn.MouseButton1Click:Connect(function()
			if setclipboard then pcall(setclipboard, l.Text) end
			copyBtn.Text = track("Copied")
			task.delay(1.5, function() copyBtn.Text = track("Copy") end)
		end)
	end

	el.Set = function(_, t) l.Text = t end
	if opts.DependsOn then
		local d = opts.DependsOn
		el._dep = type(d) == "string" and {Flag = d} or {Flag = d.Flag, Values = d.Values or (d.Value ~= nil and {d.Value} or nil)}
		DEP_WATCH[el._dep.Flag] = DEP_WATCH[el._dep.Flag] or {}
		table.insert(DEP_WATCH[el._dep.Flag], el)
		task.defer(function() applyDep(el, true) end)
	end
	return el
end

-- Markdown docs: headings, bold/italic/code, bullets, quotes, dividers.
-- One call renders a whole guide/changelog page; Set() rebuilds it.
function Tab:AddMarkdown(md, opts)
	opts = opts or {}
	local host = (opts and opts.Parent) or self
	local rows = {}
	local function mdInline(s)
		s = escapeRich(s)
		s = s:gsub("%*%*(.-)%*%*", "<b>%1</b>")
		s = s:gsub("%*(.-)%*", "<i>%1</i>")
		s = s:gsub("`(.-)`", '<font color="' .. toHex(CURRENT_THEME.Accent) .. '">%1</font>')
		return s
	end
	local function noRule(f)
		local r = f:FindFirstChild("Rule")
		if r then r.Visible = false end
	end
	local function mdRow(rich, font, size, role, indent)
		local f = row(host, ROW_H)
		noRule(f)
		local l = label({
			Text = rich,
			RichText = true,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = font or FONTS.Body,
			TextSize = size or 13,
			AutomaticSize = AY,
			Size = UDim2.new(1, -(indent or PAD), 0, 0),
			Position = UDim2.fromOffset(indent or PAD, 12),
			Parent = f,
			Role = role or "Text",
		})
		local function fit()
			-- Modal popups render markdown with a window (or the Tab class) as
			-- self, which has no .Window link: resolve the UI scale safely.
			local s = 1
			local hostWin = (self and self.Window) or (self and self.Main and self)
			if hostWin and type(hostWin._uiScale) == "function" then
				local ok, v = pcall(function() return hostWin:_uiScale() end)
				if ok and type(v) == "number" and v > 0 then s = v end
			end
			local textH = l.AbsoluteSize.Y / s
			f.Size = UDim2.new(1, 0, 0, math.max(ROW_H, math.ceil(textH) + 24))
		end
		l:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		rows[#rows + 1] = f
		return f
	end
	local function mdDivider()
		local f = row(host, 14)
		noRule(f)
		make("Frame", {
			Size = UDim2.new(1, -PAD * 2, 0, 1), Position = UDim2.fromOffset(PAD, 6),
			BorderSizePixel = 0, Parent = f,
		}, { BackgroundColor3 = "Rule2" })
		rows[#rows + 1] = f
	end
	local function render(text)
		for _, f in ipairs(rows) do f:Destroy() end
		rows = {}
		for line in tostring(text):gsub("\r", ""):gmatch("([^\n]*)\n?") do
			line = line:match("^%s*(.-)%s*$") or "" -- heredocs come indented; parse the content
			local h1 = line:match("^#%s+(.+)")
			local h2 = line:match("^##%s+(.+)")
			local h3 = line:match("^###%s+(.+)")
			local bullet = line:match("^[%-%*]%s+(.+)")
			local quote = line:match("^>%s+(.+)")
			if line:match("^%s*%-%-%-%s*$") then
				mdDivider()
			elseif h1 then
				mdRow(mdInline(h1), FONTS.HeadingBold, 18, "Text", PAD)
			elseif h2 then
				mdRow(mdInline(h2), FONTS.HeadingBold, 15, "Text", PAD)
			elseif h3 then
				mdRow(mdInline(h3), FONTS.BodySemi, 13, "Accent", PAD)
			elseif bullet then
				mdRow("•  " .. mdInline(bullet), FONTS.Body, 13, "Text", PAD + 14)
			elseif quote then
				mdRow(mdInline(quote), FONTS.Italic, 13, "SubText", PAD + 14)
			elseif line:match("%S") then
				mdRow(mdInline(line), FONTS.Body, 13, "Text", PAD)
			end
		end
	end
	render(md)
	return { Set = function(_, t) render(t) end }
end

-- A stronger full-width rule inside the current sheet.
function Tab:AddDivider(opts)
	local div = block((opts and opts.Parent) or self, 13)
	div:FindFirstChild("Rule").Visible = false
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.fromScale(0, 0.5),
		BorderSizePixel = 0,
		Parent = div,
	}, {BackgroundColor3 = "Rule2"})
	return div
end

-- ---------------------------------------------------------------------------
-- KEYBIND AFFORDANCE HELPER
-- Faint dots (brighter on row hover) open the bind popup; once bound, a key chip
-- replaces them. Right-clicking the row also opens the popup.
-- ---------------------------------------------------------------------------
local function attachBind(window, f, hit, el, name, pos, showMode, onState)
	if IS_MOBILE then
		el.RefreshBind = function() if onState then onState(false) end end
		if onState then onState(false) end
		return
	end
	local chip = keycap("", f, "SubText")
	chip.TextSize = 10
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = pos
	chip.Visible = false
	chip.ZIndex = 3

	local dots = create("TextButton", {
		Text = "", AutoButtonColor = false,
		Size = UDim2.fromOffset(14, 24), Position = pos, AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1, ZIndex = 3, Parent = f,
	}, {
		list(3, nil, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	local dotList = {}
	for i = 1, 3 do
		dotList[i] = make("Frame", {
			Size = UDim2.fromOffset(3, 3), BackgroundTransparency = 0.6, BorderSizePixel = 0, LayoutOrder = i, Parent = dots,
		}, {BackgroundColor3 = "SubText"}, {corner(2)})
	end
	local function fade(t, c)
		for _, d in ipairs(dotList) do tween(d, {BackgroundTransparency = t, BackgroundColor3 = c}) end
	end
	f.MouseEnter:Connect(function() fade(0, CURRENT_THEME.SubText) end)
	f.MouseLeave:Connect(function() fade(0.6, CURRENT_THEME.SubText) end)
	dots.MouseEnter:Connect(function() fade(0, CURRENT_THEME.Accent) end)
	dots.MouseLeave:Connect(function() fade(0, CURRENT_THEME.SubText) end)

	local function open() window:_openBindPopup(el, name) end
	dots.MouseButton1Click:Connect(open)
	chip.MouseButton1Click:Connect(open)
	if hit then hit.MouseButton2Click:Connect(open) end

	function el:RefreshBind()
		local b = Library.Binds[self.Flag]
		chip.Visible = b ~= nil
		dots.Visible = b == nil
		if b then
			chip.Text = keyLabel(b.Key) .. (showMode ~= false and ("  ·  " .. string.upper(b.Mode)) or "")
		end
		if onState then onState(b ~= nil) end
		window:UpdateKeybindHUD()
	end
end

-- ---------------------------------------------------------------------------
-- TOGGLE ELEMENT (capsule)
-- ---------------------------------------------------------------------------
function Tab:AddToggle(opts)
	local window = self.Window
	local el = {Type = "Toggle", Value = opts.Default or false}
	register(el, opts, self)
	local note = opts.Note
	local f = row((opts and opts.Parent) or self, note and 56 or ROW_H)
	el.Frame = f
	local hit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = f})

	-- opts.Color tints the name: a Color3, or a theme role name ("Warning", "Accent", ...) to follow the theme
	local nameRole = nil -- nil = the normal "Text" role
	if typeof(opts.Color) == "Color3" then nameRole = false elseif type(opts.Color) == "string" then nameRole = opts.Color end
	local nameLabel = label({
		Text = opts.Name,
		TextTruncate = TRUNC,
		Role = nameRole,
		Size = note and UDim2.new(1, -190, 0, 18) or UDim2.new(1, -190, 1, 0),
		Position = UDim2.fromOffset(PAD, note and 10 or 0),
		Parent = f,
	})
	if typeof(opts.Color) == "Color3" then nameLabel.TextColor3 = opts.Color end
	-- Note: an italic caption under the name, laid out like the Config tab's Auto-save row.
	if note then
		label({
			Text = note, FontFace = FONTS.Italic, TextSize = 12, Role = "SubText", TextTruncate = TRUNC,
			Size = UDim2.new(1, -190, 0, 16), Position = UDim2.fromOffset(PAD, 31), Parent = f,
		})
	end
	local _, show = capsule(f, UDim2.new(1, -PAD - 1, 0.5, 0))

	attachBind(window, f, hit, el, opts.Name, UDim2.new(1, -PAD - 42, 0.5, 0), true)

	-- Dynamic caption: lets a toggle rewrite its own text on state change
	-- (e.g. "Public party, appears on browse" / "Private, code only"), with a quick fade.
	function el:SetName(text)
		opts.Name = text
		text = tostring(text)
		local token = (el._nameToken or 0) + 1
		el._nameToken = token
		task.spawn(function()
			if nameLabel.Text == text then return end
			local tw = tween(nameLabel, {TextTransparency = 1}, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
			if tw then pcall(function() tw.Completed:Wait() end) else task.wait(0.1) end
			if el._nameToken ~= token then return end
			nameLabel.Text = text
			tween(nameLabel, {TextTransparency = 0}, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		end)
	end

	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		notifyDeps(self.Flag)
		touch()
		show(v, true)
		window:UpdateKeybindHUD()
		if not silent then
			-- no click per toggle while a config loads or the menu unloads (dozens at once)
			if not window._applying then playSound("Toggle") end
			self.Callback(v)
		end
	end

	hit.MouseButton1Click:Connect(function()
		local b = Library.Binds[el.Flag]
		if b and b.Mode == "Always" then
			window:Notify({Title = "Locked", Body = opts.Name .. " is set to Always. Right-click to change.", Type = "Warning"})
			return
		end
		el:Set(not el.Value)
	end)

	el:Set(el.Value, true)
	el:RefreshBind()
	return el
end

-- ---------------------------------------------------------------------------
-- SLIDER ELEMENT (ruler: quarter ticks and a nib; the value is typeable)
-- ---------------------------------------------------------------------------
function Tab:AddSlider(opts)
	local min, max, step = opts.Min or 0, opts.Max or 100, opts.Step or 1
	local el = {Type = "Slider", Value = opts.Default or min}
	register(el, opts, self)
	local f = row((opts and opts.Parent) or self, ROW_H)
	el.Frame = f
	local VALUE_W = 80

	label({
		Text = opts.Name,
		TextTruncate = TRUNC,
		Size = UDim2.new(0.35, -PAD, 1, 0),
		Position = UDim2.fromOffset(PAD, 0),
		Parent = f,
	})

	local valueBox = make("TextBox", {
		Text = "", FontFace = FONTS.Mono, TextSize = 12, TextXAlignment = RIGHT,
		BackgroundTransparency = 1, ClearTextOnFocus = false,
		Size = UDim2.fromOffset(VALUE_W, 22), Position = UDim2.new(1, -PAD, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		Parent = f,
	}, {TextColor3 = "Text"})
	local focusLine = make("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		Parent = valueBox,
	}, {BackgroundColor3 = "Accent"})
	valueBox.Focused:Connect(function() tween(focusLine, {BackgroundTransparency = 0}) end)

	local area = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.35, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0.65, -PAD - VALUE_W - 22, 0, 24),
		Parent = f,
	})
	local trackF = make("Frame", {
		Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5),
		BorderSizePixel = 0, Parent = area,
	}, {BackgroundColor3 = "Rule2"})
	for _, at in ipairs({0.25, 0.5, 0.75}) do
		make("Frame", {
			Size = UDim2.fromOffset(1, 8), Position = UDim2.fromScale(at, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0, Parent = trackF,
		}, {BackgroundColor3 = "Rule2"})
	end
	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, ZIndex = 2, Parent = trackF,
	}, {BackgroundColor3 = "Accent"})
	local nib = make("Frame", {
		Size = UDim2.fromOffset(3, 14), Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0, ZIndex = 3, Parent = trackF,
	}, {BackgroundColor3 = "Accent"}, {corner(1)})

	local hit = create("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 12, 1, 0),
		Position = UDim2.fromOffset(-6, 0),
		ZIndex = 4,
		Parent = area,
	})

	function el:Set(v, silent)
		v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
		self.Value = v
		Library.Flags[self.Flag] = v
		notifyDeps(self.Flag)
		touch()
		local a = (max == min) and 0 or (v - min) / (max - min)
		tween(fill, {Size = UDim2.fromScale(a, 1)}, TweenInfo.new(0.05))
		tween(nib, {Position = UDim2.fromScale(a, 0.5)}, TweenInfo.new(0.05))
		if not valueBox:IsFocused() then
			valueBox.Text = (math.floor(v * 100 + 0.5) / 100) .. (opts.Suffix or "")
		end
		if not silent then self.Callback(v) end
	end

	valueBox.FocusLost:Connect(function()
		tween(focusLine, {BackgroundTransparency = 1})
		local num = tonumber((valueBox.Text:gsub("[^%d%.%-]", "")))
		if num then el:Set(num) else el:Set(el.Value) end
	end)

	-- CallbackOnRelease: dragging only moves the slider, and Callback runs once when it is let go.
	-- A typed value, a config load or el:Set from code still call it straight away.
	local onRelease = opts.CallbackOnRelease == true
	local dragging, dragFrom = false, nil
	local lastTick = 0
	local function update(x)
		local a = math.clamp((x - trackF.AbsolutePosition.X) / math.max(trackF.AbsoluteSize.X, 1), 0, 1)
		local before = el.Value
		el:Set(min + a * (max - min), onRelease)
		-- a tick per step while dragging, for themes that have one (at most ~20 a second)
		if el.Value ~= before and os.clock() - lastTick > 0.05 and themeSound("Slide") then
			lastTick = os.clock()
			playSound("Slide")
		end
	end

	hit.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging, dragFrom = true, el.Value
			tween(nib, {Size = UDim2.fromOffset(3, 18)}, FAST)
			update(i.Position.X)
		end
	end)
	connect(UIS.InputEnded, function(i)
		if dragging and isPress(i) then
			dragging = false
			tween(nib, {Size = UDim2.fromOffset(3, 14)}, FAST)
			if onRelease and el.Value ~= dragFrom then el.Callback(el.Value) end
		end
	end)
	connect(UIS.InputChanged, function(i)
		if dragging and isMove(i) then update(i.Position.X) end
	end)

	el:Set(el.Value, true)
	return el
end

-- ---------------------------------------------------------------------------
-- BUTTON ELEMENT (accent label + arrow; an ink underline draws on press)
-- ---------------------------------------------------------------------------
function Tab:AddButton(opts)
	local window = self.Window
	local el = {Type = "Button"}
	register(el, opts, self)
	local role = opts.Danger and "Danger" or "Accent"
	local f = row((opts and opts.Parent) or self, ROW_H)
	el.Frame = f

	local btn = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = f,
	})
	local text = label({
		Name = "Label",
		Text = opts.Name,
		FontFace = FONTS.BodySemi,
		Role = role,
		TextTruncate = TRUNC,
		Size = UDim2.new(1, -160, 1, 0),
		Position = UDim2.fromOffset(PAD, 0),
		Parent = f,
	})
	-- Optional one-line description under the label (opts.Desc). The row grows
	-- so the text never overlaps the button title.
	if opts.Desc and opts.Desc ~= "" then
		f.Size = UDim2.new(1, 0, 0, ROW_H + 18)
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.Size = UDim2.new(1, -160, 0, 18)
		text.Position = UDim2.fromOffset(PAD, 7)
		local desc = label({
			Name = "Desc", Text = opts.Desc, FontFace = FONTS.Body, TextSize = 12, Role = "SubText",
			TextTruncate = TRUNC, Size = UDim2.new(1, -160, 0, 14), Position = UDim2.fromOffset(PAD, 26), Parent = f,
		})
		desc.ZIndex = 2
	end
	local ink = make("Frame", {
		Size = UDim2.fromOffset(0, 1), Position = UDim2.new(0, PAD, 0.5, 10), BackgroundTransparency = 1,
		BorderSizePixel = 0, Parent = f,
	}, {BackgroundColor3 = role})
	local arrow = label({
		Text = "→",
		TextSize = 16,
		Role = role,
		TextXAlignment = RIGHT,
		Size = UDim2.fromOffset(20, ROW_H),
		Position = UDim2.new(1, -PAD, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = f,
	})
	f.MouseEnter:Connect(function() tween(arrow, {Position = UDim2.new(1, -PAD + 3, 0, 0)}) end)
	f.MouseLeave:Connect(function() tween(arrow, {Position = UDim2.new(1, -PAD, 0, 0)}) end)

	local function fire()
		playSound("Click")
		ink.Size = UDim2.fromOffset(0, 1)
		ink.BackgroundTransparency = 0
		tween(ink, {Size = UDim2.fromOffset(math.min(text.TextBounds.X, text.AbsoluteSize.X / window:_uiScale()), 1)},
			TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)).Completed:Connect(function()
			tween(ink, {BackgroundTransparency = 1}, MED)
		end)
		if opts.Callback then opts.Callback() end
	end

	function el:Press() fire() end
	btn.MouseButton1Click:Connect(fire)

	attachBind(window, f, btn, el, opts.Name, UDim2.new(1, -PAD - 28, 0.5, 0), true)
	el:RefreshBind()
	-- Glider scripts used the returned row as an Instance (row:FindFirstChild("Label")): anything el doesn't
	-- have is read from the row, and its methods run on the row.
	return setmetatable(el, {__index = function(_, k)
		local ok, v = pcall(function() return f[k] end)
		if not ok then return nil end
		if type(v) == "function" then return function(_, ...) return v(f, ...) end end
		return v
	end})
end

-- ---------------------------------------------------------------------------
-- DROPDOWN (single select, optional search)
-- ---------------------------------------------------------------------------
local function chevronLabel(parent)
	return label({
		Text = "▾", FontFace = FONTS.Symbol, TextSize = 11, Role = "SubText", TextXAlignment = CENTER,
		Size = UDim2.fromOffset(14, ROW_H), Position = UDim2.new(1, -PAD, 0, 0), AnchorPoint = Vector2.new(1, 0),
		Parent = parent,
	})
end

-- A search field for dropdown bodies: accent magnifier, italic placeholder, underline.
local function searchField(parent, order)
	local sf = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order, Parent = parent})
	make("ImageLabel", {
		Image = asset(Library.Icons.Search), BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12),
		Position = UDim2.new(0, PAD + 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = sf,
	}, {ImageColor3 = "Accent"})
	local box = make("TextBox", {
		Text = "", PlaceholderText = "Search options…", FontFace = FONTS.Body, TextSize = 13, ClearTextOnFocus = false,
		TextXAlignment = LEFT, BackgroundTransparency = 1,
		Size = UDim2.new(1, -PAD * 2 - 22, 0, 26), Position = UDim2.new(0, PAD + 22, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		Parent = sf,
	}, {TextColor3 = "Text", PlaceholderColor3 = "SubText"})
	italicWhenEmpty(box)
	make("Frame", {
		Size = UDim2.new(1, -PAD * 2, 0, 1), Position = UDim2.new(0, PAD, 1, -2), BorderSizePixel = 0, Parent = sf,
	}, {BackgroundColor3 = "Rule2"})
	return box
end

function Tab:AddDropdown(opts)
	opts.Options = opts.Options or {}
	local ROW = 28
	local maxVisible = opts.MaxVisible or 8
	local maxRender  = opts.MaxRender or 60
	local el = {Type = "Dropdown", Value = opts.Default or opts.Options[1] or ""}
	register(el, opts, self)
	local f = row((opts and opts.Parent) or self, ROW_H)
	el.Frame = f
	f.ClipsDescendants = true

	local hit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ROW_H), Parent = f})
	label({
		Text = opts.Name, TextTruncate = TRUNC,
		Size = UDim2.new(0.45, -PAD, 0, ROW_H), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})
	local valueLabel = label({
		Text = "", FontFace = FONTS.Italic, TextSize = 13, TextXAlignment = RIGHT, TextTruncate = TRUNC,
		Size = UDim2.new(0.55, -(PAD + 50), 0, ROW_H), Position = UDim2.new(1, -(PAD + 42), 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = f,
	})
	local arrow = chevronLabel(f)

	local body = create("Frame", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(0, ROW_H), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY,
		Parent = f,
	}, {list(0)})
	local search = opts.Search and searchField(body, 1) or nil
	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 2, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AY, LayoutOrder = 2, Parent = body,
	}, {ScrollBarImageColor3 = "Rule2"}, {list(0)})

	local open = false
	local optionViews, rendered = {}, 0

	local function listHeight()
		return math.min(rendered, maxVisible) * ROW
	end
	local function resize()
		local h = ROW_H
		if open then h = ROW_H + (search and 38 or 4) + listHeight() + 10 end
		tween(f, {Size = UDim2.new(1, 0, 0, h)}, MED)
	end
	local function paintOption(option, v)
		local T = CURRENT_THEME
		local on = option == el.Value
		v.Text.FontFace = on and FONTS.Italic or FONTS.Body
		v.Text.TextColor3 = on and T.Accent or T.Text
		v.Mark.Visible = on
	end
	restyle(f, function()
		for option, v in pairs(optionViews) do paintOption(option, v) end
	end)

	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		notifyDeps(self.Flag)
		touch()
		valueLabel.Text = tostring(v)
		for option, view in pairs(optionViews) do paintOption(option, view) end
		if not silent then self.Callback(v) end
	end
	local function setOpen(o)
		open = o
		resize()
		tween(arrow, {Rotation = o and 180 or 0})
	end
	local function build()
		for _, v in pairs(optionViews) do v.Button:Destroy() end
		optionViews = {}
		local q = search and string.lower(search.Text) or ""
		rendered = 0
		for i, option in ipairs(opts.Options) do
			local text = tostring(option)
			if q == "" or string.find(string.lower(text), q, 1, true) then
				rendered += 1
				if rendered <= maxRender then
					local b = make("TextButton", {
						Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
						Size = UDim2.new(1, -4, 0, ROW), LayoutOrder = i, Parent = scroll,
					}, {BackgroundColor3 = "Hover"})
					local mark = make("Frame", {
						Size = UDim2.fromOffset(2, 14), Position = UDim2.new(0, PAD, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
						Rotation = 12, BorderSizePixel = 0, Visible = false, Parent = b,
					}, {BackgroundColor3 = "Accent"})
					local t = label({
						Text = text, Role = false, TextSize = 14, TextTruncate = TRUNC,
						Size = UDim2.new(1, -PAD * 2 - 10, 1, 0), Position = UDim2.fromOffset(PAD + 10, 0), Parent = b,
					})
					local view = {Button = b, Text = t, Mark = mark}
					optionViews[option] = view
					paintOption(option, view)
					b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = 0.96}) end)
					b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = 1}) end)
					b.MouseButton1Click:Connect(function()
						playSound("Click")
						el:Set(option)
						setOpen(false)
					end)
				end
			end
		end
		scroll.Size = UDim2.new(1, 0, 0, listHeight())
		if open then resize() end
	end

	function el:SetOptions(options, silent)
		opts.Options = options or {}
		build()
		if not table.find(opts.Options, self.Value) then self:Set(opts.Options[1] or "", silent) end
	end

	build()
	if search then search:GetPropertyChangedSignal("Text"):Connect(build) end
	hit.MouseButton1Click:Connect(function() playSound("Click"); setOpen(not open) end)

	function el:Cycle()
		local listOpts = opts.Options
		if #listOpts == 0 then return end
		local idx = 0
		for i, o in ipairs(listOpts) do if o == self.Value then idx = i break end end
		self:Set(listOpts[(idx % #listOpts) + 1])
	end

	attachBind(self.Window, f, hit, el, opts.Name, UDim2.new(1, -PAD - 20, 0, ROW_H / 2), false, function(bound)
		-- a bound key chip takes the space next to the chevron; shift and narrow the value to make room
		valueLabel.Position = UDim2.new(1, -(PAD + (bound and 120 or 42)), 0, 0)
		valueLabel.Size = UDim2.new(0.55, -(PAD + (bound and 128 or 50)), 0, ROW_H)
	end)
	el:Set(el.Value, true)
	el:RefreshBind()
	return el
end

-- ---------------------------------------------------------------------------
-- MULTI-SELECT DROPDOWN ELEMENT
-- ---------------------------------------------------------------------------
function Tab:AddMultiDropdown(opts)
	opts.Options = opts.Options or {}
	local ROW = 28
	local maxVisible = opts.MaxVisible or 8
	local el = {Type = "MultiDropdown", Value = opts.Default or {}}
	register(el, opts, self)
	local f = row((opts and opts.Parent) or self, ROW_H)
	el.Frame = f
	f.ClipsDescendants = true

	local hit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ROW_H), Parent = f})
	label({
		Text = opts.Name, TextTruncate = TRUNC,
		Size = UDim2.new(0.45, -PAD, 0, ROW_H), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})
	local summary = label({
		Text = "", FontFace = FONTS.Italic, TextSize = 13, Role = false, TextXAlignment = RIGHT, TextTruncate = TRUNC,
		Size = UDim2.new(0.55, -(PAD + 60), 0, ROW_H), Position = UDim2.new(1, -(PAD + 50), 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = f,
	})
	local countChip = make("TextLabel", {
		Text = "0", FontFace = FONTS.Mono, TextSize = 10, TextXAlignment = CENTER, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(22, 18), Position = UDim2.new(1, -PAD - 20, 0, ROW_H / 2), AnchorPoint = Vector2.new(1, 0.5),
		Parent = f,
	}, {TextColor3 = "Accent"}, {corner(3), stroke("Accent")})
	local arrow = chevronLabel(f)

	local body = create("Frame", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(0, ROW_H), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY,
		Parent = f,
	}, {list(0)})
	local search = opts.Search and searchField(body, 1) or nil
	local actions = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 2, Parent = body,
	}, {list(18, H, {VerticalAlignment = Enum.VerticalAlignment.Center}), create("UIPadding", {PaddingLeft = UDim.new(0, PAD)})})
	local function link(text, role, order)
		local b = make("TextButton", {
			Text = track(text), FontFace = FONTS.BodySemi, TextSize = 10, AutoButtonColor = false,
			BackgroundTransparency = 1, AutomaticSize = AX, Size = UDim2.fromOffset(0, 22), LayoutOrder = order, Parent = actions,
		}, {TextColor3 = role})
		return b
	end
	local selectAllBtn = link("Select all", "Accent", 1)
	local clearBtn = link("Clear", "SubText", 2)

	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 2, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AY, LayoutOrder = 3, Parent = body,
	}, {ScrollBarImageColor3 = "Rule2"}, {list(0)})

	local open = false
	local boxes, rendered = {}, 0

	-- Whether an option matches the search text (every option does when there is no search).
	local function matches(option)
		local q = search and string.lower(search.Text) or ""
		return q == "" or string.find(string.lower(tostring(option)), q, 1, true) ~= nil
	end
	local function listHeight()
		return math.min(rendered, maxVisible) * ROW
	end
	local function resize()
		local h = ROW_H
		if open then h = ROW_H + (search and 34 or 0) + 26 + listHeight() + 10 end
		tween(f, {Size = UDim2.new(1, 0, 0, h)}, MED)
	end
	local function paintBox(v, on)
		local T = CURRENT_THEME
		v.Box.BackgroundColor3 = T.Accent
		v.Box.BackgroundTransparency = on and 0 or 1
		v.Stroke.Color = on and T.Accent or T.SubText
		v.Check.Visible = on
		v.Check.TextColor3 = T.Knob
	end
	local function paintSummary()
		local T = CURRENT_THEME
		local names = {}
		for _, o in ipairs(el.Value) do table.insert(names, tostring(o)) end
		summary.Text = #names > 0 and table.concat(names, ", ") or "none"
		summary.TextColor3 = #names > 0 and T.Text or T.SubText
		countChip.Text = tostring(#names)
	end
	restyle(f, function()
		paintSummary()
		for option, v in pairs(boxes) do paintBox(v, table.find(el.Value, option) ~= nil) end
	end)

	function el:Set(tbl, silent)
		-- a single value (e.g. a config saved while this was a plain dropdown) becomes a one-item list
		if type(tbl) ~= "table" then tbl = tbl ~= nil and {tbl} or {} end
		self.Value = tbl
		Library.Flags[self.Flag] = self.Value
		notifyDeps(self.Flag)
		touch()
		paintSummary()
		for option, v in pairs(boxes) do paintBox(v, table.find(self.Value, option) ~= nil) end
		if not silent then self.Callback(self.Value) end
	end

	local function build()
		for _, v in pairs(boxes) do v.Button:Destroy() end
		boxes = {}
		rendered = 0
		for i, option in ipairs(opts.Options) do
			if matches(option) then
				rendered += 1
				local b = make("TextButton", {
					Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
					Size = UDim2.new(1, -4, 0, ROW), LayoutOrder = i, Parent = scroll,
				}, {BackgroundColor3 = "Hover"})
				local box = create("Frame", {
					Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, PAD, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0, Parent = b,
				}, {corner(2)})
				local boxStroke = create("UIStroke", {Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = box})
				local check = create("TextLabel", {
					Text = "✓", FontFace = FONTS.Symbol, TextSize = 11, BackgroundTransparency = 1,
					TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Visible = false, Parent = box,
				})
				label({
					Text = tostring(option), TextTruncate = TRUNC,
					Size = UDim2.new(1, -PAD * 2 - 24, 1, 0), Position = UDim2.fromOffset(PAD + 24, 0), Parent = b,
				})
				local v = {Button = b, Box = box, Stroke = boxStroke, Check = check}
				boxes[option] = v
				paintBox(v, table.find(el.Value, option) ~= nil)
				b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = 0.96}) end)
				b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = 1}) end)
				b.MouseButton1Click:Connect(function()
					playSound("Click")
					local idx = table.find(el.Value, option)
					local newTbl = table.clone(el.Value)
					if idx then table.remove(newTbl, idx) else table.insert(newTbl, option) end
					el:Set(newTbl)
				end)
			end
		end
		scroll.Size = UDim2.new(1, 0, 0, listHeight())
		if open then resize() end
	end

	-- With a search typed, Select all and Clear only touch the options it shows.
	selectAllBtn.MouseButton1Click:Connect(function()
		playSound("Click")
		local newTbl = {}
		for _, option in ipairs(opts.Options) do
			if matches(option) or table.find(el.Value, option) then table.insert(newTbl, option) end
		end
		el:Set(newTbl)
	end)
	clearBtn.MouseButton1Click:Connect(function()
		playSound("Click")
		local newTbl = {}
		for _, option in ipairs(el.Value) do
			if not matches(option) then table.insert(newTbl, option) end
		end
		el:Set(newTbl)
	end)

	-- Picks that are no longer offered are dropped, as Dropdown:SetOptions does.
	function el:SetOptions(options, silent)
		opts.Options = options or {}
		build()
		local kept = {}
		for _, option in ipairs(self.Value) do
			if table.find(opts.Options, option) then table.insert(kept, option) end
		end
		if #kept ~= #self.Value then self:Set(kept, silent) end
	end

	build()
	if search then search:GetPropertyChangedSignal("Text"):Connect(build) end
	hit.MouseButton1Click:Connect(function()
		playSound("Click")
		open = not open
		resize()
		tween(arrow, {Rotation = open and 180 or 0})
	end)

	el:Set(el.Value, true)
	return el
end

-- ---------------------------------------------------------------------------
-- TEXTBOX ELEMENT (underline input)
-- ---------------------------------------------------------------------------
function Tab:AddTextbox(opts)
	local el = {Type = "Textbox", Value = opts.Default or ""}
	register(el, opts, self)
	local f = row((opts and opts.Parent) or self, ROW_H)
	el.Frame = f
	label({
		Text = opts.Name, TextTruncate = TRUNC,
		Size = UDim2.new(0.45, -PAD, 1, 0), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})
	local box = make("TextBox", {
		Text = el.Value, PlaceholderText = opts.Placeholder or "Type here…",
		FontFace = FONTS.Body, TextSize = 14, ClearTextOnFocus = false, TextXAlignment = LEFT,
		BackgroundTransparency = 1, TextTruncate = TRUNC,
		Size = UDim2.new(0.5, -PAD, 0, 24), Position = UDim2.new(1, -PAD, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		Parent = f,
	}, {TextColor3 = "Text", PlaceholderColor3 = "SubText"})
	underline(box)
	italicWhenEmpty(box)

	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		notifyDeps(self.Flag)
		touch()
		box.Text = v
		if not silent then self.Callback(v) end
	end
	box.FocusLost:Connect(function() el:Set(box.Text) end)
	return el
end

-- ---------------------------------------------------------------------------
-- COLOR PICKER ELEMENT
-- ---------------------------------------------------------------------------
function Tab:AddColorPicker(opts)
	local el = {Type = "ColorPicker", Value = fromHex(opts.Default) or Color3.new(1, 1, 1)}
	register(el, opts, self)
	local SQ, BAR, BOX = 104, 8, 24
	local bodyH = SQ + 10 + BAR + 12 + BOX
	local f = row((opts and opts.Parent) or self, ROW_H)
	el.Frame = f
	f.ClipsDescendants = true

	local hit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ROW_H), Parent = f})
	label({
		Text = opts.Name, TextTruncate = TRUNC,
		Size = UDim2.new(1, -120, 0, ROW_H), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})

	local swatch = create("Frame", {
		Size = UDim2.fromOffset(14, 14), Position = UDim2.new(1, -PAD - 1, 0, ROW_H / 2), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = el.Value, BorderSizePixel = 0, Parent = f,
	}, {corner(7), stroke("Rule2")})

	local body = create("Frame", {
		Size = UDim2.new(1, -PAD * 2, 0, bodyH), Position = UDim2.fromOffset(PAD, ROW_H + 4),
		BackgroundTransparency = 1, Visible = false, Parent = f,
	})

	local sv = create("Frame", {
		Size = UDim2.new(1, 0, 0, SQ), BackgroundColor3 = Color3.new(1, 0, 0),
		BorderSizePixel = 0, Parent = body,
	}, {corner(3)})
	create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = sv,
	}, {corner(3), create("UIGradient", {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})})})
	create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 3, Parent = sv,
	}, {corner(3), create("UIGradient", {Rotation = 90, Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})})})
	local svCursor = create("Frame", {
		Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1, ZIndex = 4, Parent = sv,
	}, {corner(5), create("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 2})})

	local hueStops = {}
	for i = 0, 6 do table.insert(hueStops, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i % 6) / 6, 1, 1))) end
	local hue = create("Frame", {
		Size = UDim2.new(1, 0, 0, BAR), Position = UDim2.fromOffset(0, SQ + 10),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = body,
	}, {corner(2), create("UIGradient", {Color = ColorSequence.new(hueStops)})})
	local hueCursor = create("Frame", {
		Size = UDim2.fromOffset(3, 14), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 2, Parent = hue,
	}, {corner(1), create("UIStroke", {Color = Color3.fromRGB(20, 20, 24), Thickness = 1})})

	local hexBox = make("TextBox", {
		Text = toHex(el.Value), PlaceholderText = "#RRGGBB", FontFace = FONTS.Mono, TextSize = 12,
		ClearTextOnFocus = false, TextXAlignment = LEFT, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(90, BOX), Position = UDim2.fromOffset(0, SQ + 10 + BAR + 12), Parent = body,
	}, {TextColor3 = "Text", PlaceholderColor3 = "SubText"})
	underline(hexBox)

	local rgbLabel = label({
		Text = "", FontFace = FONTS.Mono, TextSize = 12, Role = "SubText",
		Size = UDim2.new(1, -110, 0, BOX), Position = UDim2.fromOffset(110, SQ + 10 + BAR + 12), Parent = body,
	})

	local h, s, v = el.Value:ToHSV()
	local open = false
	local function draw()
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.new(h, 0, 0.5, 0)
		swatch.BackgroundColor3 = el.Value
		if not hexBox:IsFocused() then hexBox.Text = toHex(el.Value) end
		rgbLabel.Text = ("%d, %d, %d"):format(math.floor(el.Value.R * 255 + 0.5), math.floor(el.Value.G * 255 + 0.5), math.floor(el.Value.B * 255 + 0.5))
	end

	function el:Set(c, silent)
		c = fromHex(c) or self.Value
		self.Value = c
		Library.Flags[self.Flag] = c
		touch()
		local nh, ns, nv = c:ToHSV()
		if ns > 0 and nv > 0 then h = nh end
		s, v = ns, nv
		draw()
		if not silent then self.Callback(c) end
	end

	local function fromState() el:Set(Color3.fromHSV(h, s, v)) end
	local function setOpen(o)
		open = o
		body.Visible = true
		tween(f, {Size = UDim2.new(1, 0, 0, o and (ROW_H + 4 + bodyH + 14) or ROW_H)}, MED)
		if not o then task.delay(0.2, function() if not open then body.Visible = false end end) end
	end

	local dragging = nil
	local function readSV(pos)
		local a, sz = sv.AbsolutePosition, sv.AbsoluteSize
		s = math.clamp((pos.X - a.X) / math.max(sz.X, 1), 0, 1)
		v = 1 - math.clamp((pos.Y - a.Y) / math.max(sz.Y, 1), 0, 1)
		fromState()
	end
	local function readHue(pos)
		local a, sz = hue.AbsolutePosition, hue.AbsoluteSize
		h = math.clamp((pos.X - a.X) / math.max(sz.X, 1), 0, 0.999)
		fromState()
	end

	sv.InputBegan:Connect(function(i) if isPress(i) then dragging = "sv"; readSV(i.Position) end end)
	hue.InputBegan:Connect(function(i) if isPress(i) then dragging = "hue"; readHue(i.Position) end end)
	connect(UIS.InputChanged, function(i)
		if not dragging or not isMove(i) then return end
		if dragging == "sv" then readSV(i.Position) else readHue(i.Position) end
	end)
	connect(UIS.InputEnded, function(i) if isPress(i) then dragging = nil end end)

	hexBox.FocusLost:Connect(function()
		local c = fromHex(hexBox.Text)
		if c then el:Set(c) else hexBox.Text = toHex(el.Value) end
	end)
	hit.MouseButton1Click:Connect(function() playSound("Click"); setOpen(not open) end)
	draw()
	return el
end

-- ---------------------------------------------------------------------------
-- KEYBIND ELEMENT
-- ---------------------------------------------------------------------------
function Tab:AddKeybind(opts)
	local window = self.Window
	local el = {Type = "Keybind", Value = opts.Default and opts.Default.Name or "None"}
	register(el, opts, self)
	if IS_MOBILE then
		function el:Set(v) self.Value = v end
		return el
	end

	local f = row((opts and opts.Parent) or self, ROW_H)
	el.Frame = f
	label({
		Text = opts.Name, TextTruncate = TRUNC,
		Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})
	local btn = keycap(el.Value == "None" and "None" or keyLabel(toKeyCode(el.Value)), f, "Text")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -PAD - 1, 0.5, 0)
	local edge = btn:FindFirstChildOfClass("UIStroke")

	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		notifyDeps(self.Flag)
		touch()
		local k = toKeyCode(v)
		btn.Text = k and keyLabel(k) or tostring(v)
		tween(edge, {Color = CURRENT_THEME.Rule2})
		if not silent then self.Callback(toKeyCode(v)) end
	end
	btn.MouseButton1Click:Connect(function()
		playSound("Click")
		btn.Text = "…"
		tween(edge, {Color = CURRENT_THEME.Accent})
		window:ListenForKey(function(key) el:Set(key and key.Name or el.Value) end)
	end)
	return el
end

-- ---------------------------------------------------------------------------
-- SKIN PICKER ELEMENT (catalogue grid)
-- Category chips, a weapon strip, then a grid of skin cards with a rarity filter.
-- One pick per weapon per team; clicking the picked card again clears it.
-- Value = {[teamId] = {[weapon] = skin}}, saved with configs like any flag.
--   Tab:AddSkinPicker({
--     Name = "Skins", Flag = "Skins",
--     Teams = {{Id = "CT", Name = "Counter-Terrorists", Color = c}, {Id = "T", Name = "Terrorists", Color = c}},
--     Rarities = {{Name = "Red", Color = c}, ...},        -- order used by the filter
--     Categories = {{Name = "Rifles", Weapons = {{Name = "AK-47", Icon = id, Skins = {{Name = "Lore", Rarity = "Red", Image = id}}}}}},
--     (a skin's Name is the value stored; an optional Display is what its card shows)
--     Callback = function(value, change) end,            -- change = {Team, Weapon, Skin} (Skin nil = cleared)
--     Customize = {Text = "Customize", Callback = function(weapon, skin, team) end},  -- button on the equipped card
--   })
-- Without Teams there is a single loadout under the id "All".
-- ---------------------------------------------------------------------------
function Tab:AddSkinPicker(opts)
	local window = self.Window
	local teams = (opts.Teams and #opts.Teams > 0) and opts.Teams or {{Id = "All", Name = "All"}}
	local multi = #teams > 1
	local rarities = opts.Rarities or {}
	local rarityColor = {}
	for _, r in ipairs(rarities) do rarityColor[r.Name] = r.Color end
	local GRID_H, MIN_CARD, GAP = opts.Height or 430, opts.CardWidth or 150, 8
	local HEAD_H, CATS_H, STRIP_H = 46, 50, 66

	local function blank()
		local v = {}
		for _, t in ipairs(teams) do v[t.Id] = {} end
		return v
	end
	local el = {Type = "SkinPicker", Value = blank()}
	register(el, opts, self)
	el.Default = blank()

	local cats = opts.Categories or {}
	local st = {cat = 1, weapon = nil, team = teams[1].Id, rarity = nil}
	local BOTH = "__both__"
	-- edit both teams at once by default; opts.DefaultTeam picks a team id (or "Both") instead
	if multi and opts.BothOption ~= false and (opts.DefaultTeam == nil or opts.DefaultTeam == "Both") then
		st.team = BOTH
	elseif opts.DefaultTeam then
		for _, t in ipairs(teams) do if t.Id == opts.DefaultTeam then st.team = t.Id end end
	end
	local buildCards -- defined with the grid below; the rarity filter calls it

	local f = block(self, HEAD_H + CATS_H + STRIP_H + GRID_H + 12)
	el.Frame = f
	f.ClipsDescendants = false
	f:FindFirstChild("Rule").Visible = false

	-- header: weapon title on the left, team switch on the right
	local titleCap = create("UISizeConstraint", {MaxSize = Vector2.new(400, HEAD_H)})
	local title = label({
		Text = "", FontFace = FONTS.Heading, TextSize = 15, AutomaticSize = AX, TextTruncate = TRUNC,
		Size = UDim2.fromOffset(0, HEAD_H), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	}, {titleCap})
	local count = label({
		Text = "", FontFace = FONTS.Italic, TextSize = 12, Role = "SubText", AutomaticSize = AX,
		Size = UDim2.fromOffset(0, HEAD_H), Position = UDim2.fromOffset(PAD, 1), Parent = f,
	})
	local seg -- the team switch, set below when there is more than one team
	-- keep "title  N skins" left of the team switch however narrow the window gets
	local function layoutHead()
		local scale = window:_uiScale()
		local width = f.AbsoluteSize.X / scale
		local segW = seg and (seg.AbsoluteSize.X / scale + 12) or 0
		local countW = count.TextBounds.X / scale
		local room = width - PAD * 2 - segW - countW - 10
		titleCap.MaxSize = Vector2.new(math.max(40, room), HEAD_H)
		count.Visible = room > 60
		count.Position = UDim2.fromOffset(PAD + title.AbsoluteSize.X / scale + 10, 1)
	end
	title:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHead)
	count:GetPropertyChangedSignal("TextBounds"):Connect(layoutHead)
	f:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHead)

	local teamBtns = {}
	local paintTeams
	if multi then
		seg = create("Frame", {
			BackgroundTransparency = 1, AutomaticSize = AX, Size = UDim2.fromOffset(0, 28),
			Position = UDim2.new(1, -PAD, 0, HEAD_H / 2), AnchorPoint = Vector2.new(1, 0.5), Parent = f,
		}, {corner(14), stroke("Rule2", 1, 0.2), padding(3), list(2, H)})
		local entries = table.clone(teams)
		if opts.BothOption ~= false then table.insert(entries, {Id = BOTH, Name = "Both"}) end
		for i, t in ipairs(entries) do
			local b = create("TextButton", {
				Text = t.Short or t.Name, FontFace = FONTS.BodySemi, TextSize = 12, AutoButtonColor = false,
				BackgroundTransparency = 1, AutomaticSize = AX, Size = UDim2.fromOffset(0, 22), LayoutOrder = i, Parent = seg,
			}, {corner(11), padding(0, 11)})
			teamBtns[t.Id] = {Button = b, Team = t}
			b.MouseButton1Click:Connect(function()
				if st.team == t.Id then return end
				playSound("Click")
				st.team = t.Id
				paintTeams()
				el:_refresh()
			end)
		end
		function paintTeams()
			local T = CURRENT_THEME
			for id, v in pairs(teamBtns) do
				local on = id == st.team
				local c = v.Team.Color or T.Accent
				tween(v.Button, {BackgroundTransparency = on and 0.82 or 1, BackgroundColor3 = c, TextColor3 = on and c or T.SubText})
			end
		end
		restyle(seg, paintTeams)
		seg:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHead)
	end

	-- category chips + rarity filter
	local catRow = create("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -PAD * 2 - 162, 0, 38),
		Position = UDim2.fromOffset(PAD, HEAD_H), ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = AX, ClipsDescendants = true, Parent = f,
	}, {list(6, H, {VerticalAlignment = Enum.VerticalAlignment.Center}), create("UIPadding", {PaddingLeft = UDim.new(0, 1), PaddingRight = UDim.new(0, 1)})})
	local chipViews = {}

	local filterBtn = make("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(152, 34),
		Position = UDim2.new(1, -PAD, 0, HEAD_H + 2), AnchorPoint = Vector2.new(1, 0), ZIndex = 4, Parent = f,
	}, nil, {corner(5), stroke("Rule2", 1, 0.2)})
	local filterDot = create("Frame", {
		Size = UDim2.fromOffset(7, 7), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BorderSizePixel = 0, ZIndex = 4, Parent = filterBtn,
	}, {corner(4)})
	local filterText = label({
		Text = "", TextSize = 14, TextTruncate = TRUNC, ZIndex = 4,
		Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(24, 0), Parent = filterBtn,
	})
	drawnChevron({
		Size = UDim2.new(0, 16, 1, 0), Position = UDim2.new(1, -8, 0, 0), AnchorPoint = Vector2.new(1, 0), ZIndex = 4, Parent = filterBtn,
	})
	local filterList = make("Frame", {
		Visible = false, AutomaticSize = AY, Size = UDim2.fromOffset(170, 0), ZIndex = 30,
		Position = UDim2.new(1, -PAD, 0, HEAD_H + 40), AnchorPoint = Vector2.new(1, 0), Parent = f,
	}, {BackgroundColor3 = "PageRaised"}, {corner(6), stroke("Rule2", 1, 0), padding(4), list(0)})

	local function paintFilter()
		local T = CURRENT_THEME
		filterText.Text = st.rarity or "All rarities"
		filterDot.Visible = st.rarity ~= nil
		filterDot.BackgroundColor3 = st.rarity and rarityColor[st.rarity] or T.SubText
	end
	local function filterOption(name, order)
		local b = make("TextButton", {
			Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = order, ZIndex = 31, Parent = filterList,
		}, {BackgroundColor3 = "Hover"}, {corner(4)})
		if name then
			create("Frame", {
				Size = UDim2.fromOffset(7, 7), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = rarityColor[name], BorderSizePixel = 0, ZIndex = 31, Parent = b,
			}, {corner(4)})
		end
		local t = label({
			Text = name or "All rarities", TextSize = 13, ZIndex = 31,
			Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(22, 0), Parent = b,
		})
		restyle(b, function()
			local on = st.rarity == name
			t.FontFace = on and FONTS.Italic or FONTS.Body
			t.TextColor3 = on and CURRENT_THEME.Accent or CURRENT_THEME.Text
		end)
		b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = 0.94}) end)
		b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = 1}) end)
		b.MouseButton1Click:Connect(function()
			playSound("Click")
			st.rarity = name
			filterList.Visible = false
			for _, c in ipairs(filterList:GetChildren()) do
				if RESTYLERS[c] then RESTYLERS[c]() end
			end
			paintFilter()
			buildCards()
		end)
	end
	filterOption(nil, 0)
	for i, r in ipairs(rarities) do filterOption(r.Name, i) end
	filterBtn.MouseButton1Click:Connect(function()
		playSound("Click")
		filterList.Visible = not filterList.Visible
	end)
	restyle(filterBtn, paintFilter)

	-- weapon strip: no scrollbar; < and > at its ends page through it when the weapons overflow
	local ARROW_W = 26
	local strip = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = AX,
		Size = UDim2.new(1, -PAD * 2 - ARROW_W * 2, 0, STRIP_H - 4), Position = UDim2.fromOffset(PAD + ARROW_W, HEAD_H + CATS_H), Parent = f,
	}, {ScrollBarImageColor3 = "Rule2"}, {list(4, H)})
	local stripArrows = {}
	local function paintArrows()
		local over = strip.AbsoluteCanvasSize.X - strip.AbsoluteWindowSize.X
		local x = strip.CanvasPosition.X
		for _, a in ipairs(stripArrows) do
			local can = over > 1 and ((a.Dir < 0 and x > 1) or (a.Dir > 0 and x < over - 1))
			a.Can = can
			a.Button.Visible = over > 1
			for _, bar in ipairs(a.Chevron:GetChildren()) do
				bar.BackgroundColor3 = (can and a.Hover) and CURRENT_THEME.Text or CURRENT_THEME.SubText
				bar.BackgroundTransparency = can and 0 or 0.75
			end
		end
	end
	for _, dir in ipairs({-1, 1}) do
		local btn = create("TextButton", {
			Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
			Size = UDim2.fromOffset(ARROW_W, STRIP_H - 10),
			Position = dir < 0 and UDim2.fromOffset(PAD, HEAD_H + CATS_H) or UDim2.new(1, -PAD - ARROW_W, 0, HEAD_H + CATS_H),
			Parent = f,
		})
		local chev = drawnChevron({
			Size = UDim2.fromOffset(16, 20), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = dir < 0 and 90 or -90, Parent = btn,
		})
		local a = {Dir = dir, Button = btn, Chevron = chev}
		table.insert(stripArrows, a)
		btn.MouseEnter:Connect(function() a.Hover = true paintArrows() end)
		btn.MouseLeave:Connect(function() a.Hover = false paintArrows() end)
		btn.MouseButton1Click:Connect(function()
			if not a.Can then return end
			playSound("Click")
			local over = strip.AbsoluteCanvasSize.X - strip.AbsoluteWindowSize.X
			local step = strip.AbsoluteWindowSize.X * 0.8
			local x = math.clamp(strip.CanvasPosition.X + dir * step, 0, math.max(0, over))
			tween(strip, {CanvasPosition = Vector2.new(x, 0)}, FAST)
		end)
	end
	strip:GetPropertyChangedSignal("CanvasPosition"):Connect(paintArrows)
	strip:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(paintArrows)
	strip:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(paintArrows)
	restyle(strip, paintArrows)
	make("Frame", {
		Size = UDim2.new(1, -PAD * 2, 0, 1), Position = UDim2.fromOffset(PAD, HEAD_H + CATS_H + STRIP_H - 2),
		BorderSizePixel = 0, Parent = f,
	}, {BackgroundColor3 = "Rule2"})
	local weaponViews = {}

	-- card grid
	local grid = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AY, Size = UDim2.new(1, -PAD * 2 + 6, 0, GRID_H),
		Position = UDim2.fromOffset(PAD, HEAD_H + CATS_H + STRIP_H + 8), Parent = f,
	}, {ScrollBarImageColor3 = "Rule2"}, {create("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6), PaddingTop = UDim.new(0, 2)})})
	local gridLayout = create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(GAP, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid,
	})
	local empty = label({
		Text = "No skins match this filter.", FontFace = FONTS.Italic, TextSize = 13, Role = "SubText",
		TextXAlignment = CENTER, Visible = false, Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(0, HEAD_H + CATS_H + STRIP_H + 30), Parent = f,
	})
	local cardViews = {}

	local function cellSize()
		local w = grid.AbsoluteSize.X / window:_uiScale() - 14
		if w <= 0 then w = 520 end
		local cols = math.max(1, math.floor((w + GAP) / (MIN_CARD + GAP)))
		local cw = math.floor((w - GAP * (cols - 1)) / cols)
		return cw, math.floor(cw * 0.5) + 62
	end
	local function layoutGrid()
		local cw, ch = cellSize()
		gridLayout.CellSize = UDim2.fromOffset(cw, ch)
		for _, v in ipairs(cardViews) do v.Art.Size = UDim2.new(1, 0, 0, ch - 62) end
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid)

	local function currentCategory() return cats[st.cat] end
	local function findWeapon(name)
		for _, c in ipairs(cats) do
			for _, w in ipairs(c.Weapons or {}) do
				if w.Name == name then return w end
			end
		end
	end
	-- the skin shown as picked: the current team's, or under "Both" the one every team shares
	local function pickedSkin(weapon)
		if st.team ~= BOTH then return el.Value[st.team] and el.Value[st.team][weapon] end
		local s
		for i, t in ipairs(teams) do
			local v = el.Value[t.Id] and el.Value[t.Id][weapon]
			if i == 1 then s = v elseif v ~= s then return nil end
		end
		return s
	end

	local function paintCard(v)
		local T = CURRENT_THEME
		local on = pickedSkin(v.Weapon) == v.Skin.Name
		v.Card.BackgroundColor3 = on and T.PageBg:Lerp(T.Accent, 0.1) or T.PageBg
		v.Stroke.Color = on and T.Accent or (v.Hover and T.SubText or T.Rule2)
		v.Stroke.Thickness = on and 2 or 1
		v.Stroke.Transparency = on and 0 or (v.Hover and 0.2 or 0.35)
		v.Tag.Visible = on
		v.TagText.TextColor3 = T.Knob
		v.Tag.BackgroundColor3 = T.Accent
		if v.Custom then v.Custom.Visible = on end
		-- small team badges wherever this skin is in use
		for _, b in ipairs(v.Badges:GetChildren()) do
			if b:IsA("TextLabel") then b:Destroy() end
		end
		if multi then
			for i, t in ipairs(teams) do
				if el.Value[t.Id] and el.Value[t.Id][v.Weapon] == v.Skin.Name then
					local c = t.Color or T.Accent
					create("TextLabel", {
						Text = t.Short or t.Id, FontFace = FONTS.Mono, TextSize = 10, TextColor3 = c,
						BackgroundColor3 = c:Lerp(Color3.new(), 0.72), BackgroundTransparency = 0.05,
						AutomaticSize = AX, Size = UDim2.fromOffset(0, 16), LayoutOrder = i, ZIndex = 3, Parent = v.Badges,
					}, {corner(3), padding(0, 5)})
				end
			end
		end
	end

	-- 3D card art: opts.Preview(weapon, skin) returns a Model (or nil to keep the image). The model
	-- is framed side-on along its longest axis and turns while the card is hovered.
	local function preview(art, img, w, skin)
		local vp = create("ViewportFrame", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2,
			Ambient = Color3.fromRGB(170, 170, 170), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-0.4, -1, -0.6),
			Parent = art,
		})
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.Parent = vp
		vp.CurrentCamera = cam
		local state = {spinning = false, angle = 0}
		local center, up, side, dist
		local function place()
			if not center then return end
			local dir = CFrame.fromAxisAngle(up, state.angle):VectorToWorldSpace(side)
			cam.CFrame = CFrame.lookAt(center + dir * dist, center, up)
		end
		task.spawn(function()
			local ok, model = pcall(opts.Preview, w.Name, skin.Name)
			if not ok or typeof(model) ~= "Instance" or not vp.Parent then
				if ok and typeof(model) == "Instance" then model:Destroy() end
				if img.Parent then img.Visible = true end
				return
			end
			model.Parent = vp
			local bcf, size
			if model:IsA("Model") then bcf, size = model:GetBoundingBox()
			elseif model:IsA("BasePart") then bcf, size = model.CFrame, model.Size end
			if not bcf then img.Visible = true return end
			-- longest axis runs across the card, the thinnest one faces the camera
			local axes = {{bcf.RightVector, size.X}, {bcf.UpVector, size.Y}, {bcf.LookVector, size.Z}}
			table.sort(axes, function(a, b) return a[2] > b[2] end)
			local long, mid, thin = axes[1], axes[2], axes[3]
			center, up, side = bcf.Position, mid[1], thin[1]
			local aspect = math.max(art.AbsoluteSize.X, 1) / math.max(art.AbsoluteSize.Y, 1)
			local vHalf = math.rad(cam.FieldOfView) / 2
			local hHalf = math.atan(math.tan(vHalf) * aspect)
			dist = math.max((long[2] / 2) / math.tan(hHalf), (mid[2] / 2) / math.tan(vHalf)) * 1.12 + thin[2] / 2
			place()
		end)
		local conn
		function state.spin(on)
			if on and not conn then
				conn = RunService.RenderStepped:Connect(function(dt)
					if not vp.Parent then conn:Disconnect() conn = nil return end
					state.angle += dt * 1.6
					place()
				end)
			elseif not on and conn then
				conn:Disconnect()
				conn = nil
				state.angle = 0
				place()
			end
		end
		return state
	end

	function buildCards()
		for _, v in ipairs(cardViews) do v.Card:Destroy() end
		cardViews = {}
		local w = st.weapon and findWeapon(st.weapon)
		local skins = w and w.Skins or {}
		local cw, ch = cellSize()
		gridLayout.CellSize = UDim2.fromOffset(cw, ch)
		local shown = 0
		for i, skin in ipairs(skins) do
			if not st.rarity or skin.Rarity == st.rarity then
				shown += 1
				local rc = rarityColor[skin.Rarity] or CURRENT_THEME.SubText
				local card = create("TextButton", {
					Text = "", AutoButtonColor = false, BorderSizePixel = 0, ClipsDescendants = true,
					LayoutOrder = i, Parent = grid,
				}, {corner(6)})
				local s = create("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card})
				local art = create("Frame", {
					BackgroundColor3 = rc, BackgroundTransparency = 0.88, BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, ch - 62), Parent = card,
				}, {create("UIGradient", {
					Rotation = 90,
					Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0)}),
				})})
				local img = create("ImageLabel", {
					Image = asset(skin.Image or w.Icon or ""), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
					Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5),
					ZIndex = 2, Visible = not opts.Preview, Parent = art,
				})
				local view = opts.Preview and preview(art, img, w, skin) or nil
				label({
					Text = w.Name, FontFace = FONTS.Mono, TextSize = 11, Role = "SubText", TextTruncate = TRUNC,
					Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 9, 1, -58), Parent = card,
				})
				label({
					Text = skin.Display or skin.Name, FontFace = FONTS.BodySemi, TextSize = 14, TextTruncate = TRUNC,
					Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 9, 1, -43), Parent = card,
				})
				create("TextLabel", {
					Text = skin.Label or skin.Rarity or "", FontFace = FONTS.Body, TextSize = 12, TextColor3 = rc,
					BackgroundTransparency = 1, TextXAlignment = LEFT, TextTruncate = TRUNC,
					Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 9, 1, -23), Parent = card,
				})
				create("Frame", {
					BackgroundColor3 = rc, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3),
					Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1), ZIndex = 2, Parent = card,
				})
				local tag = create("Frame", {
					BorderSizePixel = 0, AutomaticSize = AX, Size = UDim2.fromOffset(0, 18),
					Position = UDim2.new(1, -6, 0, 6), AnchorPoint = Vector2.new(1, 0), ZIndex = 3, Parent = card,
				}, {corner(4), padding(0, 7)})
				local tagText = create("TextLabel", {
					Text = "Equipped", FontFace = FONTS.BodySemi, TextSize = 11, BackgroundTransparency = 1,
					AutomaticSize = AX, Size = UDim2.fromScale(0, 1), ZIndex = 3, Parent = tag,
				})
				local badges = create("Frame", {
					BackgroundTransparency = 1, Size = UDim2.new(0.6, 0, 0, 16), Position = UDim2.fromOffset(6, 7),
					ZIndex = 3, Parent = card,
				}, {list(3, H)})
				-- opts.Customize: a button on the equipped card (its own click, the card's pick stays)
				local custom
				if opts.Customize then
					custom = create("TextButton", {
						Text = opts.Customize.Text or "Customize", FontFace = FONTS.BodySemi, TextSize = 12, AutoButtonColor = false,
						AutomaticSize = AX, Size = UDim2.fromOffset(0, 24), BorderSizePixel = 0, Visible = false,
						Position = UDim2.new(1, -7, 1, -7), AnchorPoint = Vector2.new(1, 1), ZIndex = 4, Parent = art,
					}, {corner(12), padding(0, 11)})
					local cs = create("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Parent = custom})
					local hot = false
					local function paintCustom()
						local T = CURRENT_THEME
						tween(custom, {BackgroundColor3 = hot and T.Accent or T.PageBg, BackgroundTransparency = hot and 0 or 0.08,
							TextColor3 = hot and T.Knob or T.Accent}, FAST)
						cs.Color = T.Accent
					end
					restyle(custom, paintCustom)
					custom.MouseEnter:Connect(function() hot = true paintCustom() end)
					custom.MouseLeave:Connect(function() hot = false paintCustom() end)
					custom.MouseButton1Click:Connect(function()
						playSound("Click")
						filterList.Visible = false
						if opts.Customize.Callback then
							pcall(opts.Customize.Callback, w.Name, skin.Name, st.team == BOTH and "Both" or st.team)
						end
					end)
				end
				local v = {Card = card, Stroke = s, Art = art, Image = img, Tag = tag, TagText = tagText, Badges = badges, Weapon = w.Name, Skin = skin, Custom = custom}
				table.insert(cardViews, v)
				restyle(card, function() paintCard(v) end)
				card.MouseEnter:Connect(function()
					v.Hover = true
					paintCard(v)
					tween(img, {Size = UDim2.fromScale(0.88, 0.88)}, MED)
					if view then view.spin(true) end
				end)
				card.MouseLeave:Connect(function()
					v.Hover = false
					paintCard(v)
					tween(img, {Size = UDim2.fromScale(0.8, 0.8)}, MED)
					if view then view.spin(false) end
				end)
				card.MouseButton1Click:Connect(function()
					playSound("Click")
					filterList.Visible = false
					local clear = pickedSkin(w.Name) == skin.Name
					local targets = {}
					if st.team == BOTH then
						for _, t in ipairs(teams) do table.insert(targets, t.Id) end
					else
						targets[1] = st.team
					end
					for _, id in ipairs(targets) do
						el.Value[id] = el.Value[id] or {}
						el.Value[id][w.Name] = (not clear) and skin.Name or nil
					end
					el:Set(el.Value, false, {Team = st.team == BOTH and "Both" or st.team, Weapon = w.Name, Skin = (not clear) and skin.Name or nil})
				end)
			end
		end
		grid.CanvasPosition = Vector2.zero
		empty.Visible = shown == 0 and #skins > 0
		local n = #skins
		title.Text = st.weapon or "Pick a weapon"
		count.Text = st.weapon and (n == 1 and "1 skin" or (n .. " skins")) or ""
	end

	local function paintWeapon(v)
		local T = CURRENT_THEME
		local on = v.Name == st.weapon
		v.Button.BackgroundColor3 = T.PageBg
		v.Button.BackgroundTransparency = on and 0 or 1
		v.Text.TextColor3 = on and T.Text or T.SubText
		v.Icon.ImageColor3 = on and T.Text or T.SubText
		v.Under.Visible = on
		v.Under.BackgroundColor3 = T.Accent
		local has = false
		for _, t in ipairs(teams) do
			if st.team == BOTH or st.team == t.Id then
				if el.Value[t.Id] and el.Value[t.Id][v.Name] then has = true end
			end
		end
		v.Dot.Visible = has
		v.Dot.BackgroundColor3 = T.Accent
	end

	local function buildWeapons()
		for _, v in pairs(weaponViews) do v.Button:Destroy() end
		weaponViews = {}
		local c = currentCategory()
		for i, w in ipairs(c and c.Weapons or {}) do
			local b = create("TextButton", {
				Text = "", AutoButtonColor = false, BorderSizePixel = 0, Size = UDim2.fromOffset(98, STRIP_H - 10),
				LayoutOrder = i, Parent = strip,
			}, {corner(5)})
			local icon = create("ImageLabel", {
				Image = asset(w.Icon or ""), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(74, 26), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0), Parent = b,
			})
			local t = create("TextLabel", {
				Text = w.Name, FontFace = FONTS.Body, TextSize = 12, BackgroundTransparency = 1, TextTruncate = TRUNC,
				Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0.5, 0, 0, 35), AnchorPoint = Vector2.new(0.5, 0), Parent = b,
			})
			local under = create("Frame", {
				BorderSizePixel = 0, Size = UDim2.new(1, -36, 0, 2), Position = UDim2.new(0.5, 0, 1, 0),
				AnchorPoint = Vector2.new(0.5, 1), Parent = b,
			}, {corner(1)})
			local dot = create("Frame", {
				BorderSizePixel = 0, Size = UDim2.fromOffset(6, 6), Position = UDim2.new(1, -7, 0, 7),
				AnchorPoint = Vector2.new(1, 0), Parent = b,
			}, {corner(3)})
			local v = {Name = w.Name, Button = b, Icon = icon, Text = t, Under = under, Dot = dot}
			weaponViews[w.Name] = v
			restyle(b, function() paintWeapon(v) end)
			b.MouseButton1Click:Connect(function()
				if st.weapon == w.Name then return end
				playSound("Click")
				st.weapon = w.Name
				for _, o in pairs(weaponViews) do paintWeapon(o) end
				buildCards()
			end)
		end
		strip.CanvasPosition = Vector2.zero
	end

	local function paintChip(v)
		local T = CURRENT_THEME
		local on = v.Index == st.cat
		v.Button.BackgroundColor3 = T.Accent
		v.Button.BackgroundTransparency = on and 0.86 or 1
		v.Button.TextColor3 = on and T.Text or T.SubText
		v.Stroke.Color = on and T.Accent or T.Rule2
		v.Stroke.Transparency = on and 0 or 0.2
	end
	local function selectCategory(i)
		st.cat = i
		local c = cats[i]
		st.weapon = c and c.Weapons and c.Weapons[1] and c.Weapons[1].Name or nil
		for _, v in ipairs(chipViews) do paintChip(v) end
		buildWeapons()
		buildCards()
	end
	local function buildChips()
		for _, v in ipairs(chipViews) do v.Button:Destroy() end
		chipViews = {}
		for i, c in ipairs(cats) do
			local b = create("TextButton", {
				Text = c.Name, FontFace = FONTS.Body, TextSize = 15, AutoButtonColor = false, BorderSizePixel = 0,
				AutomaticSize = AX, Size = UDim2.fromOffset(0, 34), LayoutOrder = i, Parent = catRow,
			}, {corner(6), padding(0, 18)})
			local s = create("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b})
			local v = {Index = i, Button = b, Stroke = s}
			table.insert(chipViews, v)
			restyle(b, function() paintChip(v) end)
			b.MouseButton1Click:Connect(function()
				if st.cat == i then return end
				playSound("Click")
				selectCategory(i)
			end)
		end
	end

	-- repaint selection state after a team switch
	function el:_refresh()
		for _, v in pairs(weaponViews) do paintWeapon(v) end
		for _, v in ipairs(cardViews) do paintCard(v) end
	end

	function el:Set(v, silent, change)
		local clean = blank()
		if type(v) == "table" then
			for _, t in ipairs(teams) do
				if type(v[t.Id]) == "table" then
					for weapon, skin in pairs(v[t.Id]) do
						if type(weapon) == "string" and type(skin) == "string" then clean[t.Id][weapon] = skin end
					end
				end
			end
		end
		self.Value = clean
		Library.Flags[self.Flag] = clean
		touch()
		for _, wv in pairs(weaponViews) do paintWeapon(wv) end
		for _, cv in ipairs(cardViews) do paintCard(cv) end
		if not silent then self.Callback(clean, change) end
	end

	function el:Get(team, weapon)
		local t = self.Value[team or teams[1].Id]
		return t and t[weapon]
	end

	function el:Select(team, weapon, skin)
		self.Value[team] = self.Value[team] or {}
		self.Value[team][weapon] = skin
		self:Set(self.Value, false, {Team = team, Weapon = weapon, Skin = skin})
	end

	-- jump to one weapon's skins (its category, its strip button, its grid); the page also scrolls the
	-- picker into view unless keepPage is true (e.g. when following the held weapon automatically)
	function el:ShowWeapon(name, keepPage)
		for i, c in ipairs(cats) do
			for _, w in ipairs(c.Weapons or {}) do
				if w.Name == name then
					if not (st.cat == i and st.weapon == name) then -- already showing it: nothing to rebuild
						if st.cat ~= i then
							st.cat = i
							for _, v in ipairs(chipViews) do paintChip(v) end
							buildWeapons()
						end
						st.weapon = name
						for _, v in pairs(weaponViews) do paintWeapon(v) end
						buildCards()
					end
					local scale = window:_uiScale()
					local wv = weaponViews[name]
					if wv then
						local x = (wv.Button.AbsolutePosition.X - strip.AbsolutePosition.X) / scale + strip.CanvasPosition.X
						strip.CanvasPosition = Vector2.new(math.max(0, x - 40), 0)
					end
					local page = not keepPage and self.Tab and self.Tab.Page
					if page and page:IsA("ScrollingFrame") then
						local y = (f.AbsolutePosition.Y - page.AbsolutePosition.Y) / scale + page.CanvasPosition.Y
						tween(page, {CanvasPosition = Vector2.new(0, math.max(0, y - 12))}, MED)
					end
					return true
				end
			end
		end
		return false
	end

	-- swap in a new catalogue (e.g. once the game's skin list has loaded); picks are kept
	function el:SetCategories(newCats)
		cats = newCats or {}
		local keep = st.weapon
		buildChips()
		local ci = 1
		if keep then
			for i, c in ipairs(cats) do
				for _, w in ipairs(c.Weapons or {}) do
					if w.Name == keep then ci = i end
				end
			end
		end
		st.cat = ci
		for _, v in ipairs(chipViews) do paintChip(v) end
		buildWeapons()
		local c = cats[ci]
		st.weapon = (keep and findWeapon(keep) and keep) or (c and c.Weapons and c.Weapons[1] and c.Weapons[1].Name) or nil
		for _, v in pairs(weaponViews) do paintWeapon(v) end
		buildCards()
	end

	buildChips()
	selectCategory(1)
	if multi then paintTeams() end
	paintFilter()
	task.defer(layoutGrid)
	return el
end

-- ---------------------------------------------------------------------------
-- HERO ELEMENT (one item shown big with its name; e.g. the head of a customize panel)
--   local hero = Tab:AddHero({Height = 170})
--   hero:Set({Title = "Revolver", Name = "Peppermint Sheriff", Label = "Legendary", Color = c, Image = id,
--             Model = function() return model end,   -- optional: a 3D model shown (slowly turning) instead of the image
--             Upright = true})  -- keep the model standing (characters): up stays up, it turns around its own vertical axis
-- ---------------------------------------------------------------------------
-- camera placement for a model: longest axis across the frame, thinnest one facing the camera
local function frameModel(model, aspect, fov)
	local bcf, size
	if model:IsA("Model") then bcf, size = model:GetBoundingBox()
	elseif model:IsA("BasePart") then bcf, size = model.CFrame, model.Size end
	if not bcf then return nil end
	local axes = {{bcf.RightVector, size.X}, {bcf.UpVector, size.Y}, {bcf.LookVector, size.Z}}
	table.sort(axes, function(a, b) return a[2] > b[2] end)
	local long, mid, thin = axes[1], axes[2], axes[3]
	local vHalf = math.rad(fov) / 2
	local hHalf = math.atan(math.tan(vHalf) * aspect)
	local dist = math.max((long[2] / 2) / math.tan(hHalf), (mid[2] / 2) / math.tan(vHalf)) * 1.15 + thin[2] / 2
	return {center = bcf.Position, up = mid[1], side = thin[1], dist = dist}
end
-- camera placement for a standing model (a character): its up axis stays up, the camera starts in front of it
local function frameUpright(model, aspect, fov)
	local bcf, size
	if model:IsA("Model") then bcf, size = model:GetBoundingBox()
	elseif model:IsA("BasePart") then bcf, size = model.CFrame, model.Size end
	if not bcf then return nil end
	local vHalf = math.rad(fov) / 2
	local hHalf = math.atan(math.tan(vHalf) * aspect)
	local width = math.max(size.X, size.Z)
	local dist = math.max((size.Y / 2) / math.tan(vHalf), (width / 2) / math.tan(hHalf)) * 1.12 + width / 2
	return {center = bcf.Position, up = bcf.UpVector, side = bcf.LookVector, dist = dist}
end
function Tab:AddHero(opts)
	opts = opts or {}
	local ART_H = opts.Height or 170
	local el = {Type = "Hero"}
	local f = block(self, ART_H + 80)
	el.Frame = f
	f:FindFirstChild("Rule").Visible = false
	local art = make("Frame", {
		Size = UDim2.new(1, -PAD * 2, 0, ART_H), Position = UDim2.fromOffset(PAD, 8), BorderSizePixel = 0,
		ClipsDescendants = true, Parent = f,
	}, {BackgroundColor3 = "PageRaised"}, {corner(8), stroke("Rule2", 1, 0.35)})
	local glow = create("Frame", {
		BackgroundTransparency = 0.78, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = art,
	}, {create("UIGradient", {
		Rotation = 90, Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15)}),
	})})
	local img = create("ImageLabel", {
		BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(0.82, 0.82),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 2, Parent = art,
	})
	local vp = create("ViewportFrame", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Visible = false,
		Ambient = Color3.fromRGB(170, 170, 170), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = art,
	})
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local bar = create("Frame", {
		BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1),
		ZIndex = 3, Parent = art,
	})
	local title = label({
		Text = "", FontFace = FONTS.Mono, TextSize = 11, Role = "SubText", TextTruncate = TRUNC,
		Size = UDim2.new(1, -PAD * 2, 0, 14), Position = UDim2.fromOffset(PAD, ART_H + 18), Parent = f,
	})
	local name = label({
		Text = "", FontFace = FONTS.Heading, TextSize = 19, TextTruncate = TRUNC,
		Size = UDim2.new(1, -PAD * 2, 0, 24), Position = UDim2.fromOffset(PAD, ART_H + 33), Parent = f,
	})
	local sub = create("TextLabel", {
		Text = "", FontFace = FONTS.Body, TextSize = 12, BackgroundTransparency = 1, TextXAlignment = LEFT, TextTruncate = TRUNC,
		Size = UDim2.new(1, -PAD * 2, 0, 14), Position = UDim2.fromOffset(PAD, ART_H + 59), Parent = f,
	})
	local shot, model, token, angle = nil, nil, 0, 0
	local function place()
		if not shot then return end
		local dir = CFrame.fromAxisAngle(shot.up, angle):VectorToWorldSpace(shot.side)
		cam.CFrame = CFrame.lookAt(shot.center + dir * shot.dist, shot.center, shot.up)
	end
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not f.Parent then conn:Disconnect() return end
		if shot and vp.Visible and art.AbsoluteSize.X > 0 then
			angle += dt * (opts.Spin or 0.5)
			place()
		end
	end)
	local function paintColor()
		local c = el.Info and el.Info.Color or CURRENT_THEME.Accent
		glow.BackgroundColor3 = c
		bar.BackgroundColor3 = c
		sub.TextColor3 = c
	end
	restyle(f, paintColor)
	function el:Set(info)
		info = info or {}
		self.Info = info
		title.Text = info.Title or ""
		name.Text = info.Name or ""
		sub.Text = info.Label or ""
		img.Image = asset(info.Image or "")
		paintColor()
		token += 1
		local mine = token
		if model then model:Destroy() model = nil end
		shot = nil
		vp.Visible, img.Visible = false, true
		if type(info.Model) ~= "function" then return end
		task.spawn(function()
			local ok, m = pcall(info.Model)
			if not (ok and typeof(m) == "Instance") then return end
			if mine ~= token or not vp.Parent then m:Destroy() return end
			model = m
			m.Parent = vp
			local aspect = math.max(art.AbsoluteSize.X, 1) / math.max(art.AbsoluteSize.Y, 1)
			shot = (info.Upright and frameUpright or frameModel)(m, aspect, cam.FieldOfView)
			if not shot then return end
			angle = 0
			place()
			vp.Visible, img.Visible = true, false
		end)
	end
	return el
end

-- ---------------------------------------------------------------------------
-- GALLERY ELEMENT (a searchable grid of picture tiles: one pick, or none)
--   local g = Tab:AddGallery({
--     Name = "Wrap", Height = 230, TileSize = 74, NoneText = "None", Search = true,
--     Items = {{Name = "Red Rubber", Image = id, Color = rarityColor, View = function() return guiObject end}},
--     Callback = function(name) end,   -- nil = None
--   })
--   g:SetItems(items, value)   g:Set(name, silent)   g:SetTitle(text)   g.Value
-- View (optional) builds a tile's picture (e.g. a ViewportFrame) the first time the tile scrolls into view.
-- Not saved with configs: the script keeps the picks.
-- ---------------------------------------------------------------------------
function Tab:AddGallery(opts)
	opts = opts or {}
	local window = self.Window
	local TILE, GRID_H, GAP_G, LABEL_H = opts.TileSize or 74, opts.Height or 230, 6, 18
	local HEAD_H, SEARCH_H = 34, opts.Search == false and 0 or 34
	local el = {Type = "Gallery", Value = opts.Value, Callback = opts.Callback or function() end}
	local f = block(self, HEAD_H + SEARCH_H + GRID_H + 14)
	el.Frame = f
	local title = label({
		Text = opts.Name or "", FontFace = FONTS.BodySemi, TextSize = 14, AutomaticSize = AX,
		Size = UDim2.fromOffset(0, HEAD_H), Position = UDim2.fromOffset(PAD, 4), Parent = f,
	})
	local current = label({
		Text = "", FontFace = FONTS.Italic, TextSize = 13, Role = "Accent", TextXAlignment = RIGHT, TextTruncate = TRUNC,
		Size = UDim2.new(0.62, -PAD, 0, HEAD_H), Position = UDim2.new(1, -PAD, 0, 4), AnchorPoint = Vector2.new(1, 0), Parent = f,
	})
	local box
	if SEARCH_H > 0 then
		local holder = create("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, SEARCH_H), Position = UDim2.fromOffset(0, HEAD_H + 2), Parent = f,
		})
		box = searchField(holder, 0)
		box.PlaceholderText = "Search " .. string.lower(opts.Name or "") .. "..."
	end
	local grid = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AY, Size = UDim2.new(1, -PAD * 2 + 10, 0, GRID_H),
		Position = UDim2.fromOffset(PAD - 4, HEAD_H + SEARCH_H + 8), Parent = f,
	}, {ScrollBarImageColor3 = "Rule2"}, {create("UIPadding", {
		PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4),
	})})
	local layout = create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(GAP_G, GAP_G), CellSize = UDim2.fromOffset(TILE, TILE + LABEL_H),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid,
	})
	local empty = label({
		Text = "Nothing matches.", FontFace = FONTS.Italic, TextSize = 13, Role = "SubText", TextXAlignment = CENTER,
		Visible = false, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, HEAD_H + SEARCH_H + 30), Parent = f,
	})
	local items = opts.Items or {}
	local tiles = {}

	local function fit()
		local w = grid.AbsoluteSize.X / window:_uiScale() - 14
		if w <= 0 then return end
		local cols = math.max(1, math.floor((w + GAP_G) / (TILE + GAP_G)))
		local cw = math.floor((w - GAP_G * (cols - 1)) / cols)
		layout.CellSize = UDim2.fromOffset(cw, cw + LABEL_H)
	end
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local function paintTile(t)
		local T = CURRENT_THEME
		local on = el.Value == t.Name
		t.Button.BackgroundColor3 = on and T.PageBg:Lerp(T.Accent, 0.12) or T.PageRaised
		t.Stroke.Color = on and T.Accent or (t.Hover and T.SubText or T.Rule2)
		t.Stroke.Thickness = on and 2 or 1
		t.Stroke.Transparency = on and 0 or (t.Hover and 0.2 or 0.45)
		t.Label.TextColor3 = on and T.Text or T.SubText
	end
	local function paintAll() for _, t in ipairs(tiles) do paintTile(t) end end

	-- pictures from View are made only for tiles near the visible part of the grid, a few per frame
	local loading = false
	local function loadVisible()
		if loading then return end
		loading = true
		task.spawn(function()
			while grid.Parent do
				local top = grid.AbsolutePosition.Y - TILE
				local bottom = grid.AbsolutePosition.Y + grid.AbsoluteSize.Y + TILE
				local made = 0
				for _, t in ipairs(tiles) do
					if not t.Made and t.Item.View and t.Button.Visible then
						local y = t.Button.AbsolutePosition.Y
						if y >= top and y <= bottom then
							t.Made = true
							local ok, inst = pcall(t.Item.View)
							if ok and typeof(inst) == "Instance" then
								if inst:IsA("GuiObject") then
									inst.Size, inst.Position, inst.AnchorPoint = UDim2.fromScale(1, 1), UDim2.new(), Vector2.zero
									inst.BackgroundTransparency, inst.ZIndex = 1, 2
								end
								inst.Parent = t.Art
								if t.Image then t.Image.Visible = false end
							end
							made += 1
							if made >= 3 then break end
						end
					end
				end
				if made == 0 then break end
				RunService.Heartbeat:Wait()
			end
			loading = false
		end)
	end
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(loadVisible)
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(loadVisible)
	f:GetPropertyChangedSignal("AbsolutePosition"):Connect(loadVisible)

	local function filter()
		local q = box and string.lower(box.Text) or ""
		local shown = 0
		for _, t in ipairs(tiles) do
			local text = t.Item.None and "" or string.lower(t.Item.Display or t.Item.Name or "")
			local vis = q == "" or (not t.Item.None and string.find(text, q, 1, true) ~= nil)
			t.Button.Visible = vis
			if vis then shown += 1 end
		end
		empty.Visible = shown == 0
		grid.CanvasPosition = Vector2.zero
		task.defer(loadVisible)
	end
	if box then box:GetPropertyChangedSignal("Text"):Connect(filter) end

	local function build()
		for _, t in ipairs(tiles) do t.Button:Destroy() end
		tiles = {}
		local entries = {{None = true}}
		for _, it in ipairs(items) do table.insert(entries, it) end
		for i, it in ipairs(entries) do
			local b = create("TextButton", {
				Text = "", AutoButtonColor = false, BorderSizePixel = 0, ClipsDescendants = true, LayoutOrder = i, Parent = grid,
			}, {corner(6)})
			local s = create("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b})
			local art = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -LABEL_H), Parent = b})
			if it.Color then
				create("Frame", {
					BackgroundColor3 = it.Color, BackgroundTransparency = 0.84, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = art,
				}, {create("UIGradient", {
					Rotation = 90, Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 0)}),
				})})
				create("Frame", {
					BackgroundColor3 = it.Color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2),
					Position = UDim2.new(0, 0, 1, -LABEL_H), AnchorPoint = Vector2.new(0, 1), ZIndex = 3, Parent = b,
				})
			end
			local image
			if it.None then
				local ring = make("Frame", {
					BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24), Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5), Parent = art,
				}, nil, {corner(12), stroke("SubText", 2, 0.25)})
				make("Frame", {
					Size = UDim2.fromOffset(24, 2), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
					Rotation = -45, BorderSizePixel = 0, BackgroundTransparency = 0.25, Parent = ring,
				}, {BackgroundColor3 = "SubText"})
			else
				image = create("ImageLabel", {
					Image = asset(it.Image or ""), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
					Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
					ZIndex = 2, Visible = (it.Image or "") ~= "", Parent = art,
				})
			end
			local lab = create("TextLabel", {
				Text = it.None and (opts.NoneText or "None") or (it.Display or it.Name or ""), FontFace = FONTS.Body, TextSize = 11,
				BackgroundTransparency = 1, TextTruncate = TRUNC,
				Size = UDim2.new(1, -8, 0, LABEL_H - 2), Position = UDim2.new(0, 4, 1, -LABEL_H + 1), Parent = b,
			})
			local t = {Button = b, Stroke = s, Art = art, Image = image, Label = lab, Item = it, Name = it.Name}
			table.insert(tiles, t)
			restyle(b, function() paintTile(t) end)
			b.MouseEnter:Connect(function() t.Hover = true paintTile(t) end)
			b.MouseLeave:Connect(function() t.Hover = false paintTile(t) end)
			b.MouseButton1Click:Connect(function()
				if el.Value == t.Name then return end
				playSound("Click")
				el:Set(t.Name)
			end)
		end
		fit()
		filter()
	end

	function el:Set(v, silent)
		self.Value = v
		current.Text = v or (opts.NoneText or "None")
		paintAll()
		if not silent then pcall(self.Callback, v) end
	end
	function el:SetItems(newItems, value)
		items = newItems or {}
		self.Value = value
		current.Text = value or (opts.NoneText or "None")
		if box then box.Text = "" end
		build()
	end
	function el:SetTitle(text) title.Text = tostring(text or "") end

	current.Text = el.Value or (opts.NoneText or "None")
	build()
	return el
end

-- ---------------------------------------------------------------------------
-- VIEWPORT ELEMENT (a live 3D preview, with optional tabs along the top)
--   Tab:AddViewport({
--     Flag = "PreviewTab", Tabs = {"Enemy", "Arms"}, Height = 230,
--     Model = function(tab) return model end,   -- on build, on tab change and on :Refresh()
--     Update = function(model, tab, dt) end,     -- every frame while the menu is open
--     Spin = 0.6,                                -- radians a second, 0 to hold still
--     TabsPerRow = 4,                            -- tabs per row; more start a new row below (default 4)
--   })
-- The selected tab is the element's value, so other controls can use
-- DependsOn = {Flag = "PreviewTab", Values = {"Enemy"}} to show only under that tab.
-- ---------------------------------------------------------------------------
function Tab:AddViewport(opts)
	local tabs = opts.Tabs or {}
	local el = {Type = "Viewport", Value = opts.Default or tabs[1] or ""}
	register(el, opts, self)
	local PER_ROW = math.max(1, opts.TabsPerRow or 4)
	local ROWS = math.ceil(#tabs / PER_ROW)
	local TABS_H = #tabs > 0 and (ROWS * 36 + 6) or 8
	local VIEW_H = opts.Height or 230
	local f = block(self, TABS_H + VIEW_H + 12)
	el.Frame = f
	f.ClipsDescendants = false

	local tabArea = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -PAD * 2, 0, ROWS * 36 - 6), Position = UDim2.fromOffset(PAD, 8), Parent = f,
	}, {list(6)})
	local tabRows = {}
	for r = 1, ROWS do
		tabRows[r] = create("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = r, Parent = tabArea,
		}, {list(6, H, {VerticalAlignment = Enum.VerticalAlignment.Center})})
	end
	local box = make("Frame", {
		Size = UDim2.new(1, -PAD * 2, 0, VIEW_H), Position = UDim2.fromOffset(PAD, TABS_H),
		BorderSizePixel = 0, ClipsDescendants = true, Parent = f,
	}, {BackgroundColor3 = "PageRaised"}, {corner(6), stroke("Rule2", 1, 0.2)})
	local vp = create("ViewportFrame", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 170, 170), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = box,
	})
	local empty = label({
		Text = opts.EmptyText or "Nothing to preview yet.", FontFace = FONTS.Italic, TextSize = 13, Role = "SubText",
		TextXAlignment = CENTER, Size = UDim2.fromScale(1, 1), Visible = false, Parent = box,
	})
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam

	local model, center, dist = nil, Vector3.zero, 10
	local angle = 0
	local function place()
		local dir = Vector3.new(math.sin(angle), 0.18, math.cos(angle)).Unit
		cam.CFrame = CFrame.lookAt(center + dir * dist, center)
	end

	local building = 0
	function el:Refresh()
		building += 1
		local token = building
		task.spawn(function()
			local ok, m = pcall(opts.Model or function() end, el.Value)
			if token ~= building or not vp.Parent then
				if ok and typeof(m) == "Instance" then m:Destroy() end
				return
			end
			if model then model:Destroy() model = nil end
			if not ok or typeof(m) ~= "Instance" then
				empty.Visible = true
				return
			end
			empty.Visible = false
			model = m
			m.Parent = vp
			local cf, size
			if m:IsA("Model") then cf, size = m:GetBoundingBox()
			elseif m:IsA("BasePart") then cf, size = m.CFrame, m.Size end
			if not cf then return end
			-- back off until the whole bounding sphere fits the shorter side of the box
			local aspect = math.max(box.AbsoluteSize.X, 1) / math.max(box.AbsoluteSize.Y, 1)
			local half = math.rad(cam.FieldOfView) / 2
			if aspect < 1 then half = math.atan(math.tan(half) * aspect) end
			center = cf.Position
			dist = (size.Magnitude / 2) / math.sin(half) * 1.04
			place()
		end)
	end

	local chips = {}
	local function paintTab(c)
		local T = CURRENT_THEME
		local on = el.Value == c.Name
		c.Button.BackgroundColor3 = T.Accent
		c.Button.BackgroundTransparency = on and 0.86 or 1
		c.Button.TextColor3 = on and T.Text or T.SubText
		c.Stroke.Color = on and T.Accent or T.Rule2
		c.Stroke.Transparency = on and 0 or 0.2
	end
	function el:Set(v, silent)
		if #tabs > 0 and not table.find(tabs, v) then return end
		self.Value = v
		Library.Flags[self.Flag] = v
		for _, c in ipairs(chips) do paintTab(c) end
		notifyDeps(self.Flag)
		self:Refresh()
		if not silent then self.Callback(v) end
	end
	for i, name in ipairs(tabs) do
		local b = create("TextButton", {
			Text = name, FontFace = FONTS.Body, TextSize = 14, AutoButtonColor = false, BorderSizePixel = 0,
			AutomaticSize = AX, Size = UDim2.fromOffset(0, 30), LayoutOrder = i, Parent = tabRows[math.ceil(i / PER_ROW)],
		}, {corner(6), padding(0, 16)})
		local s = create("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b})
		local c = {Name = name, Button = b, Stroke = s}
		table.insert(chips, c)
		restyle(b, function() paintTab(c) end)
		b.MouseButton1Click:Connect(function()
			if el.Value == name then return end
			playSound("Click")
			el:Set(name)
		end)
	end

	local spin = opts.Spin or 0.6
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not vp.Parent then conn:Disconnect() return end
		local w = Library._window
		if w and not w.Visible then return end
		if not model then return end
		if spin ~= 0 then
			angle += dt * spin
			place()
		end
		if opts.Update then pcall(opts.Update, model, el.Value, dt) end
	end)

	el:Refresh()
	return el
end

-- ---------------------------------------------------------------------------
-- CHIPS ELEMENT (a wrapping row of choices, like the skin picker's categories)
--   Tab:AddChoiceChips({Flag = "Group", Options = {"A", "B"}, Default = "A", Callback = fn(v),
--                 Marked = fn(option) -> bool})   -- a small dot on chips the script marks
--   el:Refresh() repaints the marks after whatever Marked reads has changed.
-- ---------------------------------------------------------------------------
function Tab:AddChoiceChips(opts)
	opts.Options = opts.Options or {}
	local el = {Type = "Chips", Value = opts.Default or opts.Options[1]}
	register(el, opts, self)
	local f = block(self, 44)
	el.Frame = f
	f.AutomaticSize = AY
	local holder = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -PAD * 2, 0, 0), AutomaticSize = AY,
		Position = UDim2.fromOffset(PAD, 9), Parent = f,
	}, {list(6, H, {Wraps = true, VerticalAlignment = Enum.VerticalAlignment.Center}),
		create("UIPadding", {PaddingBottom = UDim.new(0, 9)})})
	local views = {}
	local function paintChip(v)
		local T = CURRENT_THEME
		local on = v.Option == el.Value
		v.Button.BackgroundColor3 = T.Accent
		v.Button.BackgroundTransparency = on and 0.86 or 1
		v.Button.TextColor3 = on and T.Text or T.SubText
		v.Stroke.Color = on and T.Accent or T.Rule2
		v.Stroke.Transparency = on and 0 or 0.2
		local marked = opts.Marked and opts.Marked(v.Option) and true or false
		v.Dot.Visible = marked
		v.Dot.BackgroundColor3 = T.Accent
	end
	for i, option in ipairs(opts.Options) do
		local b = create("TextButton", {
			Text = tostring(option), FontFace = FONTS.Body, TextSize = 13, AutoButtonColor = false, BorderSizePixel = 0,
			AutomaticSize = AX, Size = UDim2.fromOffset(0, 26), LayoutOrder = i, Parent = holder,
		}, {corner(5), padding(0, 13)})
		local st = create("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b})
		local dot = create("Frame", {
			Size = UDim2.fromOffset(5, 5), Position = UDim2.new(1, 9, 0, 4), AnchorPoint = Vector2.new(1, 0),
			BorderSizePixel = 0, Visible = false, Parent = b,
		}, {corner(3)})
		local v = {Option = option, Button = b, Stroke = st, Dot = dot}
		table.insert(views, v)
		restyle(b, function() paintChip(v) end)
		b.MouseButton1Click:Connect(function()
			if el.Value == option then return end
			playSound("Click")
			el:Set(option)
		end)
	end
	function el:Refresh()
		for _, v in ipairs(views) do paintChip(v) end
	end
	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		notifyDeps(self.Flag)
		touch()
		self:Refresh()
		if not silent then self.Callback(v) end
	end
	el:Set(el.Value, true)
	return el
end

-- ---------------------------------------------------------------------------
-- PLAYER LIST ELEMENT (a searchable, grouped list with one selection, like a scoreboard)
--   local pl = Tab:AddPlayerList({
--     Height = 260, ResetText = "Reset all" (false = no button), OnReset = fn(),
--     Callback = fn(id),                      -- the selection changed (nil = nothing selected)
--   })
--   pl:SetGroups({{Title = "Enemies", Items = {{Id = "u1", Name = "Name", Color = c, Marked = true}}}})
--   pl:Select(id, silent)   pl.Value (the selected id)
-- Color is the little dot in front of the name, Marked puts an accent dot at the right end of the row.
-- Rows are rebuilt only when the ids, names or groups change, so calling SetGroups often is cheap.
-- Not saved with configs: the script keeps the data.
-- ---------------------------------------------------------------------------
function Tab:AddPlayerList(opts)
	opts = opts or {}
	local HEAD_H, ITEM_H, GROUP_H = 38, 26, 28
	local LIST_H = opts.Height or 260
	local RESET_H = opts.ResetText == false and 0 or 44
	local el = {Type = "PlayerList", Value = nil, Hidden = true, Callback = opts.Callback or function() end}
	local f = block(self, HEAD_H + LIST_H + RESET_H + 12)
	el.Frame = f
	local box = searchField(f, 0)
	box.PlaceholderText = "Search players..."
	box.Parent.Position = UDim2.fromOffset(0, 2)
	local holder = make("Frame", {
		Size = UDim2.new(1, -PAD * 2, 0, LIST_H), Position = UDim2.fromOffset(PAD, HEAD_H), BorderSizePixel = 0,
		ClipsDescendants = true, Parent = f,
	}, {BackgroundColor3 = "PageBg"}, {corner(5), stroke("Rule2", 1, 0.45)})
	local scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AY, Size = UDim2.fromScale(1, 1), Parent = holder,
	}, {ScrollBarImageColor3 = "Rule2"}, {list(0), create("UIPadding", {
		PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), PaddingRight = UDim.new(0, 4),
	})})
	local empty = label({
		Text = "Nobody here.", FontFace = FONTS.Italic, TextSize = 13, Role = "SubText", TextXAlignment = CENTER,
		Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 14), Visible = false, Parent = holder,
	})
	if opts.ResetText ~= false then
		local reset = make("TextButton", {
			Text = opts.ResetText or "Reset all", FontFace = FONTS.BodySemi, TextSize = 13, AutoButtonColor = false,
			BorderSizePixel = 0, Size = UDim2.new(1, -PAD * 2, 0, 30), Position = UDim2.new(0, PAD, 1, -(RESET_H - 6) + 2),
			Parent = f,
		}, {BackgroundColor3 = "PageRaised", TextColor3 = "SubText"}, {corner(5), stroke("Rule2", 1, 0.3)})
		reset.MouseEnter:Connect(function() paint(reset, {TextColor3 = "Text"}) end)
		reset.MouseLeave:Connect(function() paint(reset, {TextColor3 = "SubText"}) end)
		reset.MouseButton1Click:Connect(function()
			playSound("Click")
			if opts.OnReset then pcall(opts.OnReset) end
		end)
	end

	local groups, collapsed, rows, sig = {}, {}, {}, ""
	local function paintRow(r)
		local T = CURRENT_THEME
		local on = el.Value == r.Id
		r.Button.BackgroundColor3 = T.Accent
		r.Button.BackgroundTransparency = on and 0.86 or (r.Hover and 0.94 or 1)
		r.Label.TextColor3 = on and T.Text or T.SubText
		r.Label.FontFace = on and FONTS.BodySemi or FONTS.Body
		r.Dot.BackgroundColor3 = r.Item.Color or T.SubText
		r.Mark.BackgroundColor3 = T.Accent
		r.Mark.Visible = r.Item.Marked == true
	end
	local function paintAll() for _, r in ipairs(rows) do paintRow(r) end end
	restyle(f, paintAll)

	local function applyFilter()
		local q = string.lower(box.Text or "")
		local anyShown = false
		for _, g in ipairs(rows.groups or {}) do
			local shown = 0
			for _, r in ipairs(g.Rows) do
				local vis = q == "" or string.find(string.lower(r.Item.Name or ""), q, 1, true) ~= nil
				r.Vis = vis
				if vis then shown += 1 end
			end
			g.Header.Visible = shown > 0
			local open = q ~= "" or not collapsed[g.Title]
			for _, r in ipairs(g.Rows) do r.Button.Visible = r.Vis and open end
			g.Chevron.Rotation = open and 0 or -90
			if shown > 0 then anyShown = true end
		end
		empty.Visible = not anyShown
	end
	box:GetPropertyChangedSignal("Text"):Connect(applyFilter)

	local function build()
		for _, c in ipairs(scroll:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		rows = {groups = {}}
		local order = 0
		for _, g in ipairs(groups) do
			order += 1
			local head = create("TextButton", {
				Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, GROUP_H),
				LayoutOrder = order, Parent = scroll,
			})
			local chev = drawnChevron({Size = UDim2.fromOffset(14, GROUP_H), Position = UDim2.fromOffset(8, 0), Parent = head})
			label({
				Text = g.Title, FontFace = FONTS.BodySemi, TextSize = 13, TextTruncate = TRUNC,
				Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(28, 0), Parent = head,
			})
			local gr = {Title = g.Title, Header = head, Chevron = chev, Rows = {}}
			table.insert(rows.groups, gr)
			head.MouseButton1Click:Connect(function()
				playSound("Click")
				collapsed[g.Title] = not collapsed[g.Title]
				applyFilter()
			end)
			for _, item in ipairs(g.Items or {}) do
				order += 1
				local b = create("TextButton", {
					Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, ITEM_H), LayoutOrder = order, Parent = scroll,
				}, {corner(3)})
				local dot = create("Frame", {
					Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0, 26, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0, Parent = b,
				}, {corner(3)})
				local lab = label({
					Text = item.Name or "", FontFace = FONTS.Body, TextSize = 13, TextTruncate = TRUNC,
					Size = UDim2.new(1, -62, 1, 0), Position = UDim2.fromOffset(40, 0), Parent = b,
				})
				local mark = create("Frame", {
					Size = UDim2.fromOffset(5, 5), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
					BorderSizePixel = 0, Visible = false, Parent = b,
				}, {corner(3)})
				local r = {Id = item.Id, Item = item, Button = b, Label = lab, Dot = dot, Mark = mark, Vis = true}
				table.insert(gr.Rows, r)
				table.insert(rows, r)
				b.MouseEnter:Connect(function() r.Hover = true paintRow(r) end)
				b.MouseLeave:Connect(function() r.Hover = false paintRow(r) end)
				b.MouseButton1Click:Connect(function()
					playSound("Click")
					el:Select(r.Id)
				end)
			end
		end
		paintAll()
		applyFilter()
	end

	function el:Select(id, silent)
		if self.Value == id then return end
		self.Value = id
		paintAll()
		if not silent then self.Callback(id) end
	end
	function el:SetGroups(new)
		groups = new or {}
		local parts = {}
		for _, g in ipairs(groups) do
			table.insert(parts, "#" .. tostring(g.Title))
			for _, it in ipairs(g.Items or {}) do table.insert(parts, tostring(it.Id) .. "=" .. tostring(it.Name)) end
		end
		local now = table.concat(parts, "|")
		if now ~= sig then
			sig = now
			build()
		else
			-- same rows: just take the new colours and marks
			local byId = {}
			for _, g in ipairs(groups) do for _, it in ipairs(g.Items or {}) do byId[it.Id] = it end end
			for _, r in ipairs(rows) do r.Item = byId[r.Id] or r.Item end
			paintAll()
		end
		-- the selected one left: nothing is selected any more
		if self.Value ~= nil then
			local found = false
			for _, g in ipairs(groups) do for _, it in ipairs(g.Items or {}) do if it.Id == self.Value then found = true end end end
			if not found then self:Select(nil) end
		end
	end
	return el
end

-- ---------------------------------------------------------------------------
-- STATE ELEMENT (no control: a value the script keeps, saved and loaded with configs)
--   local st = Tab:AddState({Flag = "MyData", Default = {}, Callback = fn(value)})
--   Mutate st.Value and call st:Save() (auto-save) or st:Set(newValue).
-- ---------------------------------------------------------------------------
local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = deepCopy(x) end
	return t
end
function Tab:AddState(opts)
	local el = {Type = "State", Value = deepCopy(opts.Default), Hidden = true}
	register(el, opts, self)
	el.Default = deepCopy(opts.Default)
	function el:Set(v, silent)
		self.Value = deepCopy(v) -- never share the Default table (or a caller's) with live state
		Library.Flags[self.Flag] = self.Value
		touch()
		if not silent then self.Callback(self.Value) end
	end
	function el:Save()
		Library.Flags[self.Flag] = self.Value
		touch()
	end
	return el
end

-- ---------------------------------------------------------------------------
-- PROGRESS BAR ELEMENT
-- ---------------------------------------------------------------------------
function Tab:AddProgressBar(opts)
	local el = {Type = "ProgressBar", Value = opts.Default or 0}
	local f = row((opts and opts.Parent) or self, 58)
	el.Frame = f
	label({
		Text = opts.Name or "Progress", TextTruncate = TRUNC,
		Size = UDim2.new(1, -80, 0, 18), Position = UDim2.fromOffset(PAD, 14), Parent = f,
	})
	local pctLabel = label({
		Text = "0%", FontFace = FONTS.Mono, TextSize = 12, TextXAlignment = RIGHT,
		Size = UDim2.fromOffset(60, 18), Position = UDim2.new(1, -PAD, 0, 14), AnchorPoint = Vector2.new(1, 0), Parent = f,
	})
	local trackF = make("Frame", {
		Size = UDim2.new(1, -PAD * 2, 0, 2), Position = UDim2.new(0, PAD, 0, 40),
		BorderSizePixel = 0, Parent = f,
	}, {BackgroundColor3 = "Rule2"})
	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = trackF,
	}, {BackgroundColor3 = "Accent"})

	function el:Set(pct)
		pct = math.clamp(pct or 0, 0, 1)
		self.Value = pct
		tween(fill, {Size = UDim2.fromScale(pct, 1)}, TweenInfo.new(0.2))
		pctLabel.Text = math.floor(pct * 100) .. "%"
	end
	el:Set(el.Value)
	return el
end

-- ---------------------------------------------------------------------------
-- 3D MODEL GRID (experimental v0.1, branch feature/viewport-grid)
-- Generic ViewportFrame tile grid with string-Id selection + Flag persistence.
-- Items: { { Id = "AK_Red", Name = "Red", Model = Instance | AssetId = number | Build = fn } }
-- Weapon grouping + FollowEquipped toggle live in the game script via SetItems.
-- ---------------------------------------------------------------------------
local function setupModelViewport(viewport, item)
	if not CAN_CREATE_INSTANCES then return nil end
	if typeof(viewport) ~= "Instance" or type(item) ~= "table" then return nil end
	for _, c in ipairs(viewport:GetChildren()) do
		if c:IsA("WorldModel") or c:IsA("Camera") then c:Destroy() end
	end
	viewport.BackgroundTransparency = 1
	local ok, model = pcall(function()
		if item.Build and type(item.Build) == "function" then
			return item.Build()
		elseif item.Model and typeof(item.Model) == "Instance" then
			return item.Model:Clone()
		elseif item.AssetId then
			local objs = game:GetObjects("rbxassetid://" .. tostring(item.AssetId))
			return objs and objs[1]
		end
		return nil
	end)
	if not ok or typeof(model) ~= "Instance" then return nil end
	local world = create("WorldModel", { Parent = viewport })
	if not world then return nil end
	pcall(function()
		model.Parent = world
		if model:IsA("BasePart") then
			local wrapper = create("Model", {})
			if wrapper then
				model.Parent = wrapper
				model = wrapper
				model.Parent = world
			end
		end
	end)
	if typeof(model) ~= "Instance" or not model.Parent then return nil end
	local center, size = Vector3.new(0, 0, 0), Vector3.new(2, 2, 2)
	pcall(function()
		local cf, sz = model:GetBoundingBox()
		center, size = cf.Position, sz
	end)
	-- GetBoundingBox never throws, even on empty models (identity CFrame,
	-- zero size). A model with no visible parts is "No preview", not a
	-- camera aimed at world origin while parts sit thousands of studs away.
	local visibleParts = 0
	pcall(function()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then visibleParts += 1 end
		end
	end)
	if visibleParts == 0 then return nil end
	local maxDim = math.max(size.X, size.Y, size.Z, 0.5)
	-- Recenter the clone to the origin: templates carry baked world-space
	-- CFrames (often thousands of studs out), so the camera and the model
	-- can never disagree about where center is.
	pcall(function() model:PivotTo(CFrame.new()) end)
	center = Vector3.new(0, 0, 0)
	local dist = maxDim * 1.9
	local cam = create("Camera", {
		FieldOfView = 35,
		CFrame = CFrame.new(center + Vector3.new(dist * 0.7, dist * 0.45, dist * 0.9), center),
		Parent = viewport,
	})
	viewport.CurrentCamera = cam
	return { Model = model, Camera = cam, Center = center, Dist = dist, Angle = math.atan2(dist * 0.9, dist * 0.7) }
end

-- Eight is the identity Roblox wants for instance writes from an executor.
local function threadEight()
	local fn = setthreadidentity or (syn and syn.set_thread_identity)
	if fn then pcall(fn, 8) end
end

-- Clear the tiles of a picker before a rebuild: the records, their buttons and
-- any leftover button still sitting in the scroll frame.
local function wipeTiles(tiles, scroll)
	for _, t in pairs(tiles) do
		if t.Button then pcall(function() t.Button:Destroy() end) end
	end
	table.clear(tiles)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiButton") then pcall(function() child:Destroy() end) end
	end
end

-- Picker header: the widget name on the left, the current value on the right.
-- AddModelGrid, AddImageGrid and AddIconRow all want exactly this row.
local function pickerHead(tab, name, fallback)
	local f = row(tab, ROW_H)
	label({
		Text = name or fallback, TextTruncate = TRUNC,
		Size = UDim2.new(0.55, -PAD, 0, ROW_H), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})
	return label({
		Text = "", FontFace = FONTS.Italic, TextSize = 13, TextXAlignment = RIGHT, TextTruncate = TRUNC,
		Size = UDim2.new(0.45, -(PAD + 8), 0, ROW_H), Position = UDim2.new(1, -(PAD + 8), 0, 0),
		AnchorPoint = Vector2.new(1, 0), Parent = f,
	})
end

-- The three tile pickers (models, images, icons) only differ in what they draw,
-- so the selection bookkeeping lives here once instead of three times.
local function tileSet(el, value, silent, items, valueLabel, paintTiles, touch)
	el.Value = tostring(value or "")
	Library.Flags[el.Flag] = el.Value
	if touch then touch() end
	local found = ""
	for _, it in ipairs(items) do
		if tostring(it.Id) == el.Value then found = it.Name or tostring(it.Id) break end
	end
	if valueLabel then valueLabel.Text = found end
	paintTiles()
	if not silent and el.Callback then el.Callback(el.Value) end
end

function Tab:AddModelGrid(opts)
	opts = opts or {}
	local columns = opts.Columns or 3
	local tileSize = opts.TileSize or 96
	local gridH = opts.GridHeight or 264
	local rotate = opts.Rotate ~= false
	local el = { Type = "ModelGrid", Value = opts.Default or "" }
	register(el, opts, self)
	local items = opts.Items or {}

	-- Header row: grid name + selected value.
	local valueLabel = pickerHead((opts and opts.Parent) or self, opts.Name, "Models")

	-- Body block: scrolling grid of tiles.
	local body = block((opts and opts.Parent) or self, gridH + PAD * 2)
	local scroll = make("ScrollingFrame", {
		Name = "ModelGrid", Size = UDim2.new(1, -PAD * 2, 1, -PAD),
		Position = UDim2.fromOffset(PAD, PAD * 0.5), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AY, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = body,
	}, { ScrollBarImageColor3 = "Rule2" }, {
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(tileSize, tileSize + 22),
			CellPadding = UDim2.fromOffset(8, 8),
			FillDirectionMaxCells = columns,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		padding(2, 2),
	})
	local emptyLabel = label({
		Text = "No models yet. Call SetItems() with your skins.",
		FontFace = FONTS.Italic, TextSize = 13, Role = "SubText",
		Size = UDim2.new(1, -PAD * 2, 0, 24), Position = UDim2.fromOffset(PAD, 4),
		Visible = #items == 0, Parent = body,
	})

	local tiles, previews = {}, {}
	local spinOn = true
	local gridGen = 0 -- guards stale deferred thumbnail builds across SetItems calls

	local function paintTiles()
		local T = CURRENT_THEME
		for id, t in pairs(tiles) do
			local on = (id == el.Value)
			if t.Ring then t.Ring.Color = on and T.Accent or T.Rule2 end
			if t.Ring then t.Ring.Transparency = on and 0 or 0.55 end
			if t.NameLabel then
				t.NameLabel.TextColor3 = on and T.Accent or T.Text
				t.NameLabel.FontFace = on and FONTS.Italic or FONTS.Body
			end
		end
	end
	restyle(body, paintTiles)

	function el:Set(id, silent) return tileSet(self, id, silent, items, valueLabel, paintTiles, touch) end

	function el:Get() return self.Value end

	function el:SetItems(newItems, silent)
		threadEight()
		items = newItems or {}
		wipeTiles(tiles, scroll)
		table.clear(previews)
		local cap = math.min(#items, opts.MaxTiles or 60)
		gridGen += 1
		local myGen = gridGen
		for i = 1, cap do
			local okTile, errTile = pcall(function()
			local item = items[i]
			if type(item) ~= "table" then error("bad item at index " .. tostring(i)) end
			local id = tostring(item.Id or ("item" .. i))
			local b = make("TextButton", {
				Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
				BorderSizePixel = 0, LayoutOrder = i, Parent = scroll,
			}, { BackgroundColor3 = "Hover" }, { corner(6) })
			if not b then error("tile button blocked") end
			local vp = create("ViewportFrame", {
				Name = "Preview", BackgroundTransparency = 1, BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, tileSize), Position = UDim2.fromOffset(4, 4),
				Ambient = Color3.fromRGB(160, 160, 160),
				LightColor = Color3.fromRGB(255, 255, 255),
				LightDirection = Vector3.new(0.5, -1, 0.75),
				Parent = b,
			}, { corner(6) })
			if not vp then error("viewport blocked") end
			local ring = create("UIStroke", {
				Thickness = 1.5, Transparency = 0.55,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b,
			})
			local nm = label({
				Text = tostring(item.Name or id), TextSize = 12, TextTruncate = TRUNC,
				TextXAlignment = CENTER, Size = UDim2.new(1, -8, 0, 16),
				Position = UDim2.new(0, 4, 0, tileSize + 6), Parent = b,
			})
			local tile = { Button = b, Viewport = vp, Ring = ring, NameLabel = nm }
			tiles[id] = tile
			-- Build the 3D thumbnail lazily so a big grid does not hitch.
			local idx = i
			task.defer(function()
				if myGen ~= gridGen then return end -- stale build from a previous SetItems
				if not vp or not vp.Parent then return end
				local info
				pcall(function() info = setupModelViewport(vp, item) end)
				if myGen ~= gridGen then return end
				if info then
					previews[idx] = info
				elseif CAN_CREATE_INSTANCES then
					pcall(function()
						label({
							Text = "No preview", FontFace = FONTS.Italic, TextSize = 11,
							Role = "SubText", TextXAlignment = CENTER,
							Size = UDim2.fromScale(1, 1), Parent = vp,
						})
					end)
				end
				-- Without Instance capability the tile keeps its name label (text mode).
			end)
			b.MouseEnter:Connect(function() tween(b, { BackgroundTransparency = 0.96 }) end)
			b.MouseLeave:Connect(function() tween(b, { BackgroundTransparency = 1 }) end)
			b.MouseButton1Click:Connect(function()
				playSound("Click")
				el:Set(id)
			end)
			end)
			if not okTile then
				warn("[Glider][ModelGrid] skipped tile #" .. tostring(i) .. ": " .. tostring(errTile))
			end
		end
		emptyLabel.Visible = cap == 0
		if el.Value == "" or not tiles[el.Value] then
			local first = items[1]
			self:Set(first and tostring(first.Id) or "", true)
		else
			self:Set(self.Value, true)
		end
	end

	-- One shared orbit loop per grid; paused when the menu is hidden.
	if rotate then
		connect(RunService.RenderStepped, function(dt)
			if not spinOn then return end
			if not (body.Parent and scroll.Parent) then return end
			local win = Library._window
			if win and win.Main and not win.Main.Visible then return end
			for _, info in pairs(previews) do
				if info.Camera and info.Camera.Parent then
					info.Angle += dt * 0.5
					local c, d = info.Center, info.Dist
					pcall(function()
						info.Camera.CFrame = CFrame.new(
							c + Vector3.new(math.cos(info.Angle) * d, d * 0.45, math.sin(info.Angle) * d), c)
					end)
				end
			end
		end)
		connect(body:GetPropertyChangedSignal("Parent"), function()
			if body.Parent == nil then spinOn = false end
		end)
	end

	el:SetItems(items, true)
	el:Set(el.Value, true)
	return el
end

-- ---------------------------------------------------------------------------
-- 2D IMAGE GRID (v0.8, branch feature/viewport-grid)
-- Image tile grid for catalogs with thumbnail art (e.g. Rivals skins).
-- Items: { { Id = "AKEY-47", Name = "AKEY-47", Image = "rbxassetid://..." } }
-- Same Flag persistence + Callback contract as AddModelGrid, no 3D involved.
-- ---------------------------------------------------------------------------
function Tab:AddImageGrid(opts)
	opts = opts or {}
	local columns = opts.Columns or 5
	local tileSize = opts.TileSize or 128
	local gridH = opts.GridHeight or 320
	local el = {
		Type = "ImageGrid",
		Value = opts.Default or "",
		OnHover = opts.OnHover,
		OnClick = opts.OnClick,
	}
	register(el, opts, self)
	local items = opts.Items or {}

	local f, valueLabel
	if not opts.HideHeader then
		valueLabel = pickerHead((opts and opts.Parent) or self, opts.Name, "Images")
	end

	local gridLayout = create("UIGridLayout", {
		CellSize = UDim2.fromOffset(tileSize, tileSize + 36),
		CellPadding = UDim2.fromOffset(10, 10),
		FillDirectionMaxCells = columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})

	local body
	if opts.Flat then
		body = create("Frame", {
			Name = "ImageGridFrame", Size = UDim2.new(1, 0, 0, gridH),
			BackgroundTransparency = 1, BorderSizePixel = 0, Parent = self.Page,
		})
	else
		body = block((opts and opts.Parent) or self, gridH + PAD * 2)
	end

	local scroll = make("ScrollingFrame", {
		Name = "ImageGrid", Size = UDim2.new(1, opts.Flat and 0 or -PAD * 2, 1, opts.Flat and 0 or -PAD),
		Position = opts.Flat and UDim2.new() or UDim2.fromOffset(PAD, PAD * 0.5), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AY, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = body,
	}, { ScrollBarImageColor3 = "Rule2" }, {
		gridLayout,
		padding(2, 2),
	})
	local emptyLabel = label({
		Text = "No images yet. Call SetItems() with your catalog.",
		FontFace = FONTS.Italic, TextSize = 13, Role = "SubText",
		Size = UDim2.new(1, -PAD * 2, 0, 24), Position = UDim2.fromOffset(PAD, 4),
		Visible = #items == 0, Parent = body,
	})

	local tiles = {}
	local cell = tileSize
	local gap, maxCols = 10, 7

	local function fitTiles()
		local w = scroll.AbsoluteSize.X - 8
		if w <= 0 then return end
		local cols = opts.Columns or math.clamp(math.floor((w + gap) / (tileSize + gap)), 2, maxCols)
		gridLayout.FillDirectionMaxCells = cols
		cell = math.max(math.floor((w - (cols - 1) * gap) / cols), 90)
		local extraH = (opts.CardStyle == "Rivals" or opts.ShowRarity) and 42 or 28
		gridLayout.CellSize = UDim2.fromOffset(cell, cell + extraH)
		for _, t in pairs(tiles) do
			if t.Image then
				t.Image.Size = UDim2.new(1, -6, 0, cell - 2)
				t.Image.Position = UDim2.fromOffset(3, 3)
			end
			if t.NameLabel then t.NameLabel.Position = UDim2.new(0, 6, 0, cell + 3) end
			if t.RarityLabel then t.RarityLabel.Position = UDim2.new(0, 6, 0, cell + 19) end
		end
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTiles)
	task.defer(fitTiles)

	local NEUTRAL_SEL = Color3.fromRGB(90, 85, 95)
	local function paintTiles()
		local T = CURRENT_THEME
		for id, t in pairs(tiles) do
			local on = (id == el.Value)
			local rarCol = t.RarityColor
			local isNone = (id == "None" or id == "__none")
			if t.Ring then
				if on then
					t.Ring.Color = NEUTRAL_SEL
					t.Ring.Transparency = 0.1
					t.Ring.Thickness = 1.5
				elseif rarCol and not isNone then
					t.Ring.Color = rarCol
					t.Ring.Transparency = 0.45
					t.Ring.Thickness = 1
				else
					t.Ring.Color = T.Rule2
					t.Ring.Transparency = 0.6
					t.Ring.Thickness = 1
				end
			end
			if t.Button then
				t.Button.BackgroundColor3 = on and T.ChromeRaised or T.PageRaised
				t.Button.BackgroundTransparency = on and 0.25 or 0.55
			end
			if t.SelectedBar then
				t.SelectedBar.Visible = on
				t.SelectedBar.BackgroundColor3 = NEUTRAL_SEL
			end
			if t.EquippedBadge then
				t.EquippedBadge.Visible = on
			end
			if t.NameLabel then
				t.NameLabel.TextColor3 = on and T.Text or T.Text
				t.NameLabel.FontFace = on and FONTS.BodySemi or FONTS.Body
			end
		end
	end
	restyle(body, paintTiles)

	function el:Set(id, silent) return tileSet(self, id, silent, items, valueLabel, paintTiles, nil) end

	function el:Get() return self.Value end

	function el:SetHoverCallback(fn) self.OnHover = fn end
	function el:SetClickCallback(fn) self.OnClick = fn end

	function el:SetItems(newItems, silent)
		threadEight()
		items = newItems or {}
		wipeTiles(tiles, scroll)
		local cap = math.min(#items, opts.MaxTiles or 80)
		for i = 1, cap do
			local okTile, errTile = pcall(function()
				local item = items[i]
				if type(item) ~= "table" then error("bad item at index " .. tostring(i)) end
				local id = tostring(item.Id or ("item" .. i))
				local rarityText = item.Rarity or "Default"
				local rarityCol = getReadableRarityColor(item.RarityColor or RARITY_COLORS[rarityText] or RARITY_COLORS.Default)
				local rarCol = rarityCol
				local isNone = (id == "None" or id == "__none")
				local isEquipped = (id == el.Value) or (item.Equipped == true)

				local b = make("TextButton", {
					Text = "", AutoButtonColor = false, BackgroundTransparency = 0.55,
					BorderSizePixel = 0, LayoutOrder = i, Parent = scroll,
				}, { BackgroundColor3 = "PageRaised" }, { corner(6) })
				if not b then error("tile button blocked") end

				local img = create("ImageLabel", {
					Name = "Thumb", BackgroundTransparency = 1, BorderSizePixel = 0,
					Size = UDim2.new(1, -6, 0, cell - 2), Position = UDim2.fromOffset(3, 3),
					Image = tostring(item.Image or ""), ScaleType = Enum.ScaleType.Fit,
					Parent = b,
				}, { corner(4) })

				if img.Image == "" then
					label({
						Text = "— None —", FontFace = FONTS.Italic, TextSize = 11,
						Role = "SubText", TextXAlignment = CENTER, TextYAlignment = Enum.TextYAlignment.Center,
						Size = UDim2.fromScale(1, 1), Parent = img,
					})
				end
				local ring = stroke("Rule2", 1, isEquipped and 0.1 or ((rarCol and not isNone) and 0.45 or 0.6))
				if isEquipped then
					ring.Color = NEUTRAL_SEL
					ring.Thickness = 1.5
				elseif rarCol and not isNone then
					ring.Color = rarCol
					ring.Thickness = 1
				end
				ring.Parent = b

				-- Top-right Equipped badge
				local eqBadge = make("Frame", {
					Name = "EquippedBadge", Size = UDim2.fromOffset(48, 14),
					Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0),
					BorderSizePixel = 0, Visible = isEquipped, ZIndex = 3, Parent = b,
				}, { BackgroundColor3 = "Accent" }, { corner(3) })
				label({
					Text = "Equipped", FontFace = FONTS.Mono, TextSize = 8.5,
					Role = "ChromeText", TextXAlignment = CENTER, TextYAlignment = Enum.TextYAlignment.Center,
					Size = UDim2.fromScale(1, 1), Parent = eqBadge,
				})

				-- Bottom 2.5px rarity underline
				local rarityBar = create("Frame", {
					Name = "RarityBar", Size = UDim2.new(1, 0, 0, 2),
					Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, ZIndex = 2,
					BackgroundColor3 = rarityCol, Parent = b,
				})

				-- Labels
				local nm = label({
					Text = tostring(item.Name or id), FontFace = FONTS.BodySemi, TextSize = 12,
					TextTruncate = TRUNC, TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -12, 0, 15), Position = UDim2.new(0, 6, 0, cell + 3), Parent = b,
				})
				local rLbl = create("TextLabel", {
					Name = "RarityLabel", Text = rarityText, FontFace = FONTS.Body, TextSize = 10.5,
					TextColor3 = rarityCol, BackgroundTransparency = 1, TextTruncate = TRUNC,
					TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -12, 0, 13),
					Position = UDim2.new(0, 6, 0, cell + 19), Parent = b,
				})

				tiles[id] = {
					Button = b, Image = img, Ring = ring, NameLabel = nm,
					RarityLabel = rLbl, RarityBar = rarityBar,
					EquippedBadge = eqBadge, RarityColor = rarityCol,
				}

				b.MouseEnter:Connect(function()
					local on = (id == el.Value)
					tween(b, { BackgroundTransparency = on and 0.2 or 0.38 })
					if ring and not on then
						tween(ring, { Transparency = 0.2, Color = (rarCol and not isNone) and rarCol or NEUTRAL_SEL })
					end
					if el.OnHover then pcall(el.OnHover, id, item, true) end
				end)
				b.MouseLeave:Connect(function()
					local on = (id == el.Value)
					tween(b, { BackgroundTransparency = on and 0.25 or 0.55 })
					if ring and not on then
						tween(ring, { Transparency = (rarCol and not isNone) and 0.45 or 0.65, Color = (rarCol and not isNone) and rarCol or CURRENT_THEME.Rule2 })
					end
					if el.OnHover then pcall(el.OnHover, id, item, false) end
				end)
				b.MouseButton1Click:Connect(function()
					playSound("Click")
					el:Set(id)
					if el.OnClick then pcall(el.OnClick, id, item) end
				end)
			end)
			if not okTile then
				warn("[Glider][ImageGrid] skipped tile #" .. tostring(i) .. ": " .. tostring(errTile))
			end
		end
		emptyLabel.Visible = cap == 0
		if el.Value == "" or not tiles[el.Value] then
			local first = items[1]
			self:Set(first and tostring(first.Id) or "", true)
		else
			self:Set(self.Value, true)
		end
	end

	el:SetItems(items, true)
	el:Set(el.Value, true)
	return el
end

-- Horizontal Pills Selector (Category tabs / sub-filters)
function Tab:AddPills(opts)
	opts = opts or {}
	local items = opts.Items or {}
	local el = {
		Type = "Pills",
		Value = opts.Default or (items[1] or ""),
		Buttons = {},
	}
	register(el, opts, self)

	local rowFrame = create("Frame", {
		Name = "PillsRow",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = (opts and opts.Parent) or self.Page,
	}, {
		list(8, Enum.FillDirection.Horizontal, {
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		padding(opts.Flat and 2 or PAD, 0),
	})

	for _, name in ipairs(items) do
		local isSel = (name == el.Value)
		local b = make("TextButton", {
			Name = "Pill_" .. name, Text = name, FontFace = FONTS.BodySemi, TextSize = 12,
			AutoButtonColor = false, AutomaticSize = AX, Size = UDim2.new(0, 0, 1, -4),
			Parent = rowFrame,
		}, {
			BackgroundColor3 = isSel and "PageRaised" or "ChromeBg",
			TextColor3 = isSel and "Text" or "SubText",
		}, {
			corner(4),
			stroke("Rule2", 1, isSel and 0.15 or 0.6),
			padding(12, 0),
		})
		local str = b:FindFirstChildOfClass("UIStroke")
		if str and isSel then str.Color = Color3.fromRGB(90, 85, 95) end
		el.Buttons[name] = b

		b.MouseButton1Click:Connect(function()
			playSound("Click")
			el:Set(name)
		end)
	end

	function el:Set(name, silent)
		self.Value = name
		Library.Flags[self.Flag] = self.Value
		touch()
		local T = CURRENT_THEME
		local NEUTRAL_SEL = Color3.fromRGB(90, 85, 95)
		for pName, b in pairs(self.Buttons) do
			local active = (pName == name)
			b.BackgroundColor3 = active and T.PageRaised or T.ChromeBg
			b.TextColor3 = active and T.Text or T.SubText
			local str = b:FindFirstChildOfClass("UIStroke")
			if str then
				str.Color = active and NEUTRAL_SEL or T.Rule2
				str.Transparency = active and 0.15 or 0.6
			end
		end
		if not silent and self.Callback then self.Callback(name) end
	end

	function el:Get() return self.Value end

	return el
end

-- Horizontal icon picker: same contract as the grids (Flag/Set/Get/SetItems)
-- but a single X-scrolling row. Used for weapon pickers (photos, not dropdowns).
function Tab:AddIconRow(opts)
	opts = opts or {}
	local tileSize = opts.TileSize or 96
	local el = { Type = "IconRow", Value = opts.Default or "" }
	register(el, opts, self)
	local items = opts.Items or {}

	local valueLabel = pickerHead((opts and opts.Parent) or self, opts.Name, "Pick")

	local body = block((opts and opts.Parent) or self, tileSize + 14 + PAD * 2)
	local scroll = make("ScrollingFrame", {
		Name = "IconRow", Size = UDim2.new(1, -PAD * 2, 1, -PAD),
		Position = UDim2.fromOffset(PAD, PAD * 0.5), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 2, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AX, ScrollingDirection = Enum.ScrollingDirection.X, Parent = body,
	}, { ScrollBarImageColor3 = "Rule2" }, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
		padding(2, 2),
	})

	-- Mouse wheel over a horizontal row scrolls it sideways (Roblox only
	-- scrolls the wheel along the frame's own direction by default). Tiles
	-- cover the frame, so every tile forwards the wheel too (see SetItems).
	local function wheelScroll(dir)
		local maxX = math.max(scroll.CanvasSize.X.Offset - scroll.AbsoluteWindowSize.X, 0)
		scroll.CanvasPosition = Vector2.new(math.clamp(scroll.CanvasPosition.X + dir * (tileSize + 8), 0, maxX), 0)
	end
	local function wheelHook(obj)
		obj.InputChanged:Connect(function(io)
			local okT, t = pcall(function() return io.UserInputType end)
			local n = (okT and typeof(t) == "EnumItem") and t.Name or "?"
			if n == "MouseWheelForward" then wheelScroll(1)
			elseif n == "MouseWheelBackward" then wheelScroll(-1) end
		end)
	end
	wheelHook(scroll)

	local tiles = {}

	local function paintTiles()
		local T = CURRENT_THEME
		local NEUTRAL_SEL = Color3.fromRGB(90, 85, 95)
		for id, t in pairs(tiles) do
			local on = (id == el.Value)
			if t.Ring then t.Ring.Color = on and NEUTRAL_SEL or T.Rule2 end
			if t.Ring then t.Ring.Transparency = on and 0.15 or 0.65 end
			if t.NameLabel then
				t.NameLabel.TextColor3 = on and T.Text or T.SubText
				t.NameLabel.FontFace = on and FONTS.BodySemi or FONTS.Body
			end
		end
	end
	restyle(body, paintTiles)

	function el:Set(id, silent) return tileSet(self, id, silent, items, valueLabel, paintTiles, touch) end

	function el:Get() return self.Value end

	function el:SetItems(newItems, silent)
		threadEight()
		items = newItems or {}
		wipeTiles(tiles, scroll)
		for i, item in ipairs(items) do
			local okTile, errTile = pcall(function()
				if type(item) ~= "table" then error("bad item at index " .. tostring(i)) end
				local id = tostring(item.Id or ("item" .. i))
				local b = make("TextButton", {
					Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
					BorderSizePixel = 0, LayoutOrder = i,
					Size = UDim2.fromOffset(tileSize, tileSize + 14),
					Parent = scroll,
				}, { BackgroundColor3 = "Hover" }, { corner(6) })
				if not b then error("tile button blocked") end
				local img = create("ImageLabel", {
					Name = "Thumb", BackgroundTransparency = 1, BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, tileSize), Position = UDim2.fromOffset(0, 0),
					Image = tostring(item.Image or ""), ScaleType = Enum.ScaleType.Fit,
					Parent = b,
				}, { corner(6) })
				if not img then error("thumbnail blocked") end
				if img.Image == "" then
					label({
						Text = "No image", FontFace = FONTS.Italic, TextSize = 11,
						Role = "SubText", TextXAlignment = CENTER,
						Size = UDim2.fromScale(1, 1), Parent = img,
					})
				end
				local ring = create("UIStroke", {
					Thickness = 1.5, Transparency = 0.55,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b,
				})
				local nm = label({
					Text = tostring(item.Name or id), TextSize = 11, TextTruncate = TRUNC,
					TextXAlignment = CENTER, Size = UDim2.new(1, 0, 0, 14),
					Position = UDim2.new(0, 0, 0, tileSize), Parent = b,
				})
				tiles[id] = { Button = b, Image = img, Ring = ring, NameLabel = nm }
				wheelHook(b)
				b.MouseEnter:Connect(function()
					local on = (id == el.Value)
					tween(b, { BackgroundTransparency = on and 0.94 or 0.96 })
					if ring and not on then
						tween(ring, { Transparency = 0.35, Color = Color3.fromRGB(90, 85, 95) })
					end
				end)
				b.MouseLeave:Connect(function()
					local on = (id == el.Value)
					tween(b, { BackgroundTransparency = 1 })
					if ring and not on then
						tween(ring, { Transparency = 0.65, Color = CURRENT_THEME.Rule2 })
					end
				end)
				b.MouseButton1Click:Connect(function()
					playSound("Click")
					el:Set(id)
				end)
			end)
			if not okTile then
				warn("[Glider][IconRow] skipped tile #" .. tostring(i) .. ": " .. tostring(errTile))
			end
		end
		if el.Value == "" or not tiles[el.Value] then
			local first = items[1]
			self:Set(first and tostring(first.Id) or "", true)
		else
			self:Set(self.Value, true)
		end
	end

	el:SetItems(items, true)
	el:Set(el.Value, true)
	return el
end

-- ---------------------------------------------------------------------------
-- PARTY / QUEUE COMPONENTS
-- Cards, banners, stats, chips, row lists, action rows and copy fields. They are
-- all built from the shared builders above, so they inherit theming, connection
-- tracking and the current section/sheet layout.
-- ---------------------------------------------------------------------------

-- A dynamic-height row on the current sheet. Unlike block(), its height follows
-- its content, and its children are centered with PAD gutters on both sides.
local function autoBlock(tab, gap)
	local parent, sec = contentHost(tab)
	local outer = create("Frame", {
		Name = "AutoBlock",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AY,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(tab, parent),
		Parent = parent,
	}, { list(gap or 8, nil, { HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	make("Frame", {
		Name = "Rule", Size = UDim2.new(1, -PAD * 2, 0, 1), BackgroundTransparency = 0.35,
		BorderSizePixel = 0, LayoutOrder = 0,
		Visible = sec ~= nil and #sec.Rows > 0, Parent = outer,
	}, { BackgroundColor3 = "Rule2" })
	trackRow(tab, outer)
	return outer
end

-- A small status pill. setChip() recolours both its outline and its text by role.
local function statusChip(parent, order)
	local f = make("Frame", {
		Name = "Chip", Size = UDim2.fromOffset(0, 20), AutomaticSize = AX, BorderSizePixel = 0,
		LayoutOrder = order or 0, Parent = parent,
	}, { BackgroundColor3 = "Hover" }, { corner(3), padding(0, 8), stroke("Rule2", 1, 0.45) })
	local l = label({
		Text = "", FontFace = FONTS.BodySemi, TextSize = 10, AutomaticSize = AX,
		Size = UDim2.fromOffset(0, 20), Role = "Text", Parent = f,
	})
	return { Frame = f, Text = l, Stroke = f:FindFirstChildOfClass("UIStroke") }
end

local function setChip(chip, text, role)
	local t = tostring(text or "")
	if chip.Text.Text ~= t then chip.Text.Text = t end
	local r = role or "Text"
	paint(chip.Text, { TextColor3 = r })
	if chip.Stroke then paint(chip.Stroke, { Color = r }) end
end

local function copyToClipboard(text)
	if setclipboard then pcall(setclipboard, text) end
end

-- A titled, rounded container. The caller parents arbitrary content into card.Body.
function Tab:AddCard(opts)
	opts = opts or {}
	local accentRole = opts.Accent or "Accent"
	local pad = opts.Padding or PAD
	local collapsible = opts.Collapsible and true or false
	local collapsed = opts.Collapsed and true or false
	local headH = 40

	local lane = autoBlock((opts and opts.Parent) or self, 0)
	local laneRule = lane:FindFirstChild("Rule")
	if laneRule then laneRule.Visible = false end -- the card carries its own border

	local cardFrame = make("Frame", {
		Name = "Card", Size = UDim2.new(1, -PAD * 2, 0, 0), AutomaticSize = AY,
		BorderSizePixel = 0, ClipsDescendants = true, LayoutOrder = 1, Parent = lane,
	}, { BackgroundColor3 = "PageRaised" }, { corner(6), stroke("Rule2", 1, 0.4) })

	-- No left rail by default: the card already has a border and a header, and the
	-- rail read as a stray vertical line. opts.Bar = true brings it back.
	local accent
	if opts.Bar == true then
		accent = create("Frame", {
			Name = "Accent", Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0, ZIndex = 2, Parent = cardFrame,
		}, { BackgroundColor3 = accentRole })
	end

	local header = create("TextButton", {
		Name = "Header", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Active = collapsible, Size = UDim2.new(1, 0, 0, headH), Position = UDim2.fromOffset(3, 0), Parent = cardFrame,
	})
	local titleX = pad + (collapsible and 16 or 0)
	local title = label({
		Text = opts.Name or "", FontFace = FONTS.HeadingBold, TextSize = 15, Role = "Text",
		TextTruncate = TRUNC, Size = UDim2.new(0.6, -titleX, 0, 16), Position = UDim2.fromOffset(titleX, 7), Parent = header,
	})
	local subLbl = label({
		Text = opts.Sub or "", FontFace = FONTS.Italic, TextSize = 12, Role = "SubText",
		TextTruncate = TRUNC, Size = UDim2.new(0.6, -titleX, 0, 13), Position = UDim2.fromOffset(titleX, 24),
		Visible = opts.Sub ~= nil, Parent = header,
	})
	local rightHost = create("Frame", {
		Name = "Right", BackgroundTransparency = 1, Size = UDim2.new(0.4, -pad, 0, headH),
		Position = UDim2.new(1, -pad, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = header,
	}, { list(8, H, { HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center }) })
	local badge = statusChip(rightHost, -1)
	badge.Frame.Visible = false
	for i, action in ipairs(opts.Actions or {}) do
		local b = textButton(rightHost, action.Text or "", action.Kind, i)
		connect(b.MouseButton1Click, function()
			playSound("Click")
			if action.Callback then action.Callback() end
		end)
	end

	local chevron
	if collapsible then
		chevron = label({
			Text = "▾", FontFace = FONTS.Symbol, TextSize = 12, Role = "SubText", TextXAlignment = CENTER,
			Size = UDim2.fromOffset(16, 18), Position = UDim2.fromOffset(0, 11), Parent = header,
		})
	end

	local body = create("Frame", {
		Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(3, headH), Parent = cardFrame,
	}, { list(6), padding(pad, pad) })

	local function setCollapsed(v)
		collapsed = v and true or false
		body.Visible = not collapsed
		if chevron then tween(chevron, { Rotation = collapsed and -90 or 0 }, FAST) end
	end
	if collapsible then
		connect(header.MouseButton1Click, function()
			playSound("Click")
			setCollapsed(not collapsed)
		end)
	end
	setCollapsed(collapsed)

	local card = { Frame = cardFrame, Body = body }
	function card:SetTitle(t) title.Text = tostring(t or "") end
	function card:SetSub(t)
		subLbl.Text = tostring(t or "")
		subLbl.Visible = t ~= nil and t ~= ""
	end
	function card:SetBadge(text, role)
		if text == nil or text == "" then badge.Frame.Visible = false return end
		badge.Frame.Visible = true
		setChip(badge, text, role or "Accent")
	end
	function card:SetAccent(role)
		accentRole = role or "Accent"
		if accent then paint(accent, { BackgroundColor3 = accentRole }) end
	end
	function card:Toggle() setCollapsed(not collapsed) end
	function card:Destroy() lane:Destroy() end
	return card
end
-- A compact tinted info banner for short explanations.
function Tab:AddBanner(opts)
	opts = opts or {}
	local KIND_ROLE = { Info = "Accent", Success = "Success", Warning = "Warning", Danger = "Danger" }
	local kind = opts.Kind or "Info"
	local dismissable = opts.Dismissable and true or false

	local outer = autoBlock((opts and opts.Parent) or self, 0)
	local box = create("Frame", {
		Name = "Banner", Size = UDim2.new(1, -PAD * 2, 0, 0), AutomaticSize = AY,
		BorderSizePixel = 0, ClipsDescendants = true, LayoutOrder = 1, Parent = outer,
	}, { corner(4) })
	paint(box, { BackgroundColor3 = KIND_ROLE[kind] or "Accent" })
	box.BackgroundTransparency = 0.9
	-- Tinted background is the kind indicator; the rail was redundant.
	local accent
	if opts.Bar == true then
		accent = create("Frame", {
			Name = "Accent", Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0, ZIndex = 2, Parent = box,
		}, { BackgroundColor3 = KIND_ROLE[kind] or "Accent" })
	end
	local content = create("Frame", {
		Name = "Content", Size = UDim2.new(1, -(PAD + (dismissable and 26 or PAD)), 0, 0),
		AutomaticSize = AY, Position = UDim2.fromOffset(PAD, PAD * 0.6), BackgroundTransparency = 1, Parent = box,
	}, { list(3), create("UIPadding", { PaddingBottom = UDim.new(0, PAD * 0.6) }) })
	local title = label({
		Text = opts.Text or "", FontFace = FONTS.BodySemi, TextSize = 13, Role = "Text",
		TextWrapped = true, AutomaticSize = AY, Size = UDim2.new(1, 0, 0, 0), Parent = content,
	})
	local subLbl = label({
		Text = opts.Sub or "", FontFace = FONTS.Body, TextSize = 12, Role = "SubText",
		TextWrapped = true, AutomaticSize = AY, Size = UDim2.new(1, 0, 0, 0),
		Visible = opts.Sub ~= nil and opts.Sub ~= "", Parent = content,
	})
	local closeBtn
	if dismissable then
		closeBtn = make("TextButton", {
			Text = "×", FontFace = FONTS.Body, TextSize = 18, AutoButtonColor = false, BackgroundTransparency = 1,
			Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -6, 0, 4), AnchorPoint = Vector2.new(1, 0), Parent = box,
		}, { TextColor3 = "SubText" })
		connect(closeBtn.MouseButton1Click, function()
			playSound("Click")
			outer:Destroy()
		end)
	end

	local banner = {}
	function banner:Set(text, sub)
		title.Text = tostring(text or "")
		if sub ~= nil then
			subLbl.Text = tostring(sub)
			subLbl.Visible = sub ~= ""
		end
	end
	function banner:SetKind(k)
		local r = KIND_ROLE[k] or "Accent"
		paint(box, { BackgroundColor3 = r })
		if accent then paint(accent, { BackgroundColor3 = r }) end
	end
	function banner:Destroy() outer:Destroy() end
	return banner
end

-- A key/value display row, optionally copyable.
function Tab:AddStat(opts)
	opts = opts or {}
	local f = row((opts and opts.Parent) or self, ROW_H)
	label({
		Text = opts.Name, TextTruncate = TRUNC, Size = UDim2.new(0.5, -PAD, 1, 0),
		Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})
	local copyW = opts.Copy and 56 or 0
	local value = label({
		Text = tostring(opts.Value or ""),
		FontFace = (opts.Mono ~= false) and FONTS.Mono or FONTS.Body,
		Role = opts.Role or "Text", TextXAlignment = RIGHT, TextTruncate = TRUNC,
		Size = UDim2.new(0.5, -(PAD + copyW), 1, 0),
		Position = UDim2.new(1, -(PAD + copyW), 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = f,
	})
	if opts.Copy then
		local copyBtn = make("TextButton", {
			Text = track("Copy"), FontFace = FONTS.BodySemi, TextSize = 10, AutoButtonColor = false,
			BackgroundTransparency = 1, AutomaticSize = AX, Size = UDim2.fromOffset(0, 22),
			Position = UDim2.new(1, -PAD, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = f,
		}, { TextColor3 = "Accent" })
		connect(copyBtn.MouseButton1Click, function()
			playSound("Click")
			copyToClipboard(value.Text)
			copyBtn.Text = track("Copied")
			task.delay(1.4, function() if copyBtn.Parent then copyBtn.Text = track("Copy") end end)
		end)
	end
	local stat = {}
	function stat:Set(v) value.Text = tostring(v or "") end
	return stat
end

-- A read-only row of status chips. Frames are pooled across SetItems() calls.
local MAX_CHIPS = 12

function Tab:AddChips(opts)
	opts = opts or {}
	local f = block((opts and opts.Parent) or self, ROW_H)
	local emptyLbl = label({
		Text = "", FontFace = FONTS.Italic, TextSize = 12, Role = "SubText",
		Size = UDim2.new(1, -PAD * 2, 1, 0), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})
	local host = create("Frame", {
		Name = "Chips", BackgroundTransparency = 1, Size = UDim2.new(1, -PAD * 2, 1, 0),
		Position = UDim2.fromOffset(PAD, 0), Parent = f,
	}, { list(8, H, { VerticalAlignment = Enum.VerticalAlignment.Center }) })
	local pool = {}
	local items = opts.Items or {}
	local emptyText = opts.Empty or "No status."
	local el = { Items = items }

	function el:SetItems(newItems)
		items = newItems or {}
		for i, item in ipairs(items) do
			if i > MAX_CHIPS then break end
			local c = pool[i]
			if not c then c = statusChip(host, i); pool[i] = c end
			c.Frame.Visible = true
			setChip(c, item.Text, item.Role)
		end
		for i = math.min(#items, MAX_CHIPS) + 1, #pool do pool[i].Frame.Visible = false end
		local empty = #items == 0
		emptyLbl.Visible = empty
		emptyLbl.Text = empty and emptyText or ""
	end
	function el:SetEmpty(text)
		emptyText = tostring(text or "")
		self:SetItems(items)
	end
	function el:Clear() self:SetItems({}) end

	el:SetItems(items)
	return el
end

-- A dynamic, scrollable row list with pooled frames and per-row action buttons.
function Tab:AddList(opts)
	opts = opts or {}
	local rowH = opts.RowHeight or 52
	local areaH = opts.Height or 190
	local maxRows = opts.MaxRows or 40
	local searchable = opts.Search and true or false

	local data = {}
	local query = ""
	local el = {}

	local outer = autoBlock((opts and opts.Parent) or self, 0)
	local box = create("Frame", {
		Name = "List", Size = UDim2.new(1, -PAD * 2, 0, 0), AutomaticSize = AY,
		BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 1, Parent = outer,
	}, { list(6) })

	if opts.Name or opts.Sub then
		local head = create("Frame", {
			Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, opts.Sub and 38 or 20), Parent = box,
		})
		if opts.Name then
			label({
				Text = opts.Name, FontFace = FONTS.HeadingBold, TextSize = 14, TextTruncate = TRUNC,
				Size = UDim2.new(1, 0, 0, 18), Parent = head,
			})
		end
		if opts.Sub then
			label({
				Text = opts.Sub, FontFace = FONTS.Italic, TextSize = 12, Role = "SubText", TextTruncate = TRUNC,
				Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 20), Parent = head,
			})
		end
	end

	local searchBox
	if searchable then
		local sf = create("Frame", { Name = "Search", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = box })
		make("ImageLabel", {
			Image = asset(Library.Icons.Search), BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12),
			Position = UDim2.new(0, 3, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = sf,
		}, { ImageColor3 = "Accent" })
		searchBox = make("TextBox", {
			Text = "", PlaceholderText = "Filter…", FontFace = FONTS.Body, TextSize = 13, ClearTextOnFocus = false,
			TextXAlignment = LEFT, BackgroundTransparency = 1,
			Size = UDim2.new(1, -22, 0, 26), Position = UDim2.fromOffset(22, 2), Parent = sf,
		}, { TextColor3 = "Text", PlaceholderColor3 = "SubText" })
		italicWhenEmpty(searchBox)
		make("Frame", {
			Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0, Parent = sf,
		}, { BackgroundColor3 = "Rule2" })
	end

	local host = create("Frame", {
		Name = "ScrollHost", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, areaH), Parent = box,
	})
	local scroll = make("ScrollingFrame", {
		Name = "Rows", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = host,
	}, { ScrollBarImageColor3 = "Rule2" }, {
		list(6),
		create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), PaddingRight = UDim.new(0, 6) }),
	})
	local emptyText = opts.Empty or "Nothing here yet."
	local emptyLbl = label({
		Text = emptyText, FontFace = FONTS.Italic, TextSize = 13, Role = "SubText",
		TextXAlignment = CENTER, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true,
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = host,
	})

	local pool = {}

	local function actionSignature(actions)
		local parts = {}
		for i, a in ipairs(actions or {}) do
			parts[i] = tostring(a.Text or "") .. "|" .. tostring(a.Kind or "")
		end
		return table.concat(parts, ";")
	end

	local function ensureRow(index)
		local r = pool[index]
		if r then return r end
		local f = create("Frame", {
			Name = "Row" .. index, Size = UDim2.new(1, -8, 0, rowH), BackgroundTransparency = 1,
			BorderSizePixel = 0, LayoutOrder = index, Parent = scroll,
		}, { corner(4) })
		paint(f, { BackgroundColor3 = "Hover" })
		local accent = create("Frame", {
			Name = "Accent", Size = UDim2.new(0, 3, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
			ZIndex = 2, Parent = f,
		}, { BackgroundColor3 = "Accent" })
		local title = label({
			Text = "", FontFace = FONTS.BodySemi, TextSize = 13, TextTruncate = TRUNC,
			Size = UDim2.new(0.55, -PAD, 0, 17), Position = UDim2.fromOffset(PAD, 6), Parent = f,
		})
		local sub = label({
			Text = "", FontFace = FONTS.Body, TextSize = 11, Role = "SubText", TextTruncate = TRUNC,
			Size = UDim2.new(0.55, -PAD, 0, 14), Position = UDim2.fromOffset(PAD, 24), Visible = false, Parent = f,
		})
		local chips = create("Frame", {
			Name = "Chips", BackgroundTransparency = 1, Size = UDim2.new(0.55, -PAD, 0, 20),
			Position = UDim2.fromOffset(PAD, 40), Visible = false, Parent = f,
		}, { list(6, H, { VerticalAlignment = Enum.VerticalAlignment.Center }) })
		local actions = create("Frame", {
			Name = "Actions", BackgroundTransparency = 1, Size = UDim2.new(0.45, -PAD, 1, 0),
			Position = UDim2.new(1, -PAD, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = f,
		}, { list(6, H, { HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center }) })
		r = { Frame = f, Accent = accent, Title = title, Sub = sub, Chips = chips, Actions = actions,
			Buttons = {}, ChipPool = {}, Callbacks = {}, Id = nil, Selected = false, Hovered = false, Sig = false }
		pool[index] = r
		connect(f.MouseEnter, function()
			r.Hovered = true
			f.BackgroundTransparency = r.Selected and 0.85 or 0.94
		end)
		connect(f.MouseLeave, function()
			r.Hovered = false
			f.BackgroundTransparency = r.Selected and 0.92 or 1
		end)
		return r
	end

	local function ensureButtons(r, actions)
		local sig = actionSignature(actions)
		if r.Sig ~= sig then
			for _, b in ipairs(r.Buttons) do pcall(function() b:Destroy() end) end
			table.clear(r.Buttons)
			for i, a in ipairs(actions or {}) do
				if i > 3 then break end
				local b = textButton(r.Actions, a.Text or "", a.Kind, i)
				r.Callbacks[i] = a.Callback
				connect(b.MouseButton1Click, function()
					playSound("Click")
					local cb = r.Callbacks[i]
					if cb and r.Id ~= nil then cb(r.Id) end
				end)
				table.insert(r.Buttons, b)
			end
			r.Sig = sig
		else
			for i, a in ipairs(actions or {}) do r.Callbacks[i] = a.Callback end
		end
	end

	local function applyRow(r, item)
		r.Id = item.Id
		local selected = item.Selected and true or false
		r.Selected = selected
		r.Accent.BackgroundTransparency = selected and 0 or 1
		r.Frame.BackgroundTransparency = r.Hovered and (selected and 0.85 or 0.94) or (selected and 0.92 or 1)

		local t = tostring(item.Title or "")
		if r.Title.Text ~= t then r.Title.Text = t end
		local s = item.Sub and tostring(item.Sub) or ""
		if r.Sub.Text ~= s then r.Sub.Text = s end
		r.Sub.Visible = s ~= ""

		local dim = item.Dim and true or false
		if r.Title.TextTransparency ~= (dim and 0.5 or 0) then r.Title.TextTransparency = dim and 0.5 or 0 end
		if r.Sub.TextTransparency ~= (dim and 0.6 or 0) then r.Sub.TextTransparency = dim and 0.6 or 0 end

		local chips = {}
		if item.Badge and item.Badge.Text then
			table.insert(chips, { Text = item.Badge.Text, Role = item.Badge.Role or "Accent" })
		end
		for _, c in ipairs(item.Chips or {}) do table.insert(chips, c) end
		if #chips > 0 then
			r.Chips.Visible = true
			r.Frame.Size = UDim2.new(1, -8, 0, rowH + 18)
			for i, c in ipairs(chips) do
				local chip = r.ChipPool[i]
				if not chip then chip = statusChip(r.Chips, i); r.ChipPool[i] = chip end
				chip.Frame.Visible = true
				setChip(chip, c.Text, c.Role)
			end
			for i = #chips + 1, #r.ChipPool do r.ChipPool[i].Frame.Visible = false end
		else
			r.Chips.Visible = false
			r.Frame.Size = UDim2.new(1, -8, 0, rowH)
		end

		ensureButtons(r, item.Actions)
	end

	local function visibleItems()
		local out = {}
		for _, item in ipairs(data) do
			if #out >= maxRows then break end
			if query == "" then
				table.insert(out, item)
			else
				local hay = (tostring(item.Title or "") .. " " .. tostring(item.Sub or "")):lower()
				if string.find(hay, query, 1, true) then table.insert(out, item) end
			end
		end
		return out
	end

	local function render()
		local items = visibleItems()
		for i, item in ipairs(items) do
			local r = ensureRow(i)
			r.Frame.Visible = true
			applyRow(r, item)
		end
		for i = #items + 1, #pool do pool[i].Frame.Visible = false end
		local empty = #items == 0
		emptyLbl.Visible = empty
		emptyLbl.Text = empty and emptyText or ""
	end

	function el:SetRows(newRows)
		data = newRows or {}
		render()
	end
	function el:SetRow(id, rowData)
		local found = false
		for i, item in ipairs(data) do
			if item.Id == id then data[i] = rowData; found = true; break end
		end
		if not found then table.insert(data, rowData) end
		render()
	end
	function el:RemoveRow(id)
		for i = #data, 1, -1 do
			if data[i].Id == id then table.remove(data, i) end
		end
		render()
	end
	function el:GetSelection()
		for _, item in ipairs(data) do
			if item.Selected then return item.Id end
		end
		return nil
	end
	function el:SetEmpty(text)
		emptyText = tostring(text or "")
		render()
	end
	function el:Clear()
		data = {}
		render()
	end

	if searchBox then
		connect(searchBox:GetPropertyChangedSignal("Text"), function()
			query = string.lower(searchBox.Text or "")
			render()
		end)
	end

	render()
	return el
end

-- A single row with up to N buttons side by side.
function Tab:AddActionRow(opts)
	opts = opts or {}
	local f = row((opts and opts.Parent) or self, ROW_H)
	local labelW = opts.Name and 0.4 or 0
	if opts.Name then
		label({
			Text = opts.Name, TextTruncate = TRUNC, Size = UDim2.new(0.4, -PAD, 1, 0),
			Position = UDim2.fromOffset(PAD, 0), Parent = f,
		})
	end
	local host = create("Frame", {
		Name = "Actions", BackgroundTransparency = 1, Size = UDim2.new(1 - labelW, -PAD * 2, 1, 0),
		Position = UDim2.new(1, -PAD, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = f,
	}, { list(8, H, { HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center }) })
	-- The enabled flag has to live in a Lua table: an Instance cannot carry
	-- custom fields, so `b._enabled` raised "_enabled is not a valid member of
	-- TextButton" the moment SetEnabled ran.
	local buttons, enabled = {}, {}
	for i, a in ipairs(opts.Actions or {}) do
		local b = textButton(host, a.Text or "", a.Kind, i)
		buttons[i] = b
		enabled[i] = true
		connect(b.MouseButton1Click, function()
			if enabled[i] == false then return end
			playSound("Click")
			if a.Callback then a.Callback() end
		end)
	end
	local el = { Buttons = buttons }
	function el:SetEnabled(index, on)
		local b = self.Buttons[index]
		if not b then return end
		enabled[index] = on and true or false
		b.Active = on and true or false
		b.TextTransparency = on and 0 or 0.6
	end
	return el
end

-- A read-only value in a bordered box with a copy button.
function Tab:AddCopyField(opts)
	opts = opts or {}
	local mono = opts.Mono ~= false
	local value = tostring(opts.Value or "")

	local outer = autoBlock((opts and opts.Parent) or self, 0)
	local box = create("Frame", {
		Name = "CopyField", Size = UDim2.new(1, -PAD * 2, 0, 0), AutomaticSize = AY,
		BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 1, Parent = outer,
	}, { list(5) })
	if opts.Name then
		label({
			Text = opts.Name, FontFace = FONTS.BodySemi, TextSize = 12, Role = "SubText",
			TextTruncate = TRUNC, Size = UDim2.new(1, 0, 0, 14), Parent = box,
		})
	end
	local field = create("Frame", {
		Name = "Field", Size = UDim2.new(1, 0, 0, 34), BorderSizePixel = 0, Parent = box,
	}, { corner(4), stroke("Rule2", 1, 0.4) })
	paint(field, { BackgroundColor3 = "PageBg" })
	local valLbl = label({
		Text = value, FontFace = mono and FONTS.Mono or FONTS.Body, TextSize = 13, Role = "Text",
		TextTruncate = TRUNC, Size = UDim2.new(1, -100, 0, 34), Position = UDim2.fromOffset(12, 0), Parent = field,
	})
	local copyBtn = textButton(field, opts.Button or "Copy", "primary")
	copyBtn.AnchorPoint = Vector2.new(1, 0.5)
	copyBtn.Position = UDim2.new(1, -6, 0.5, 0)
	copyBtn.Size = UDim2.fromOffset(0, 24)
	connect(copyBtn.MouseButton1Click, function()
		playSound("Click")
		copyToClipboard(valLbl.Text)
		copyBtn.Text = track("Copied")
		task.delay(1.4, function() if copyBtn.Parent then copyBtn.Text = track(opts.Button or "Copy") end end)
	end)

	local el = { Value = value }
	function el:Set(v)
		self.Value = tostring(v or "")
		valLbl.Text = self.Value
	end
	function el:Get() return self.Value end
	return el
end

-- ---------------------------------------------------------------------------
-- KEYBIND MODAL POPUP
-- ---------------------------------------------------------------------------
function Library:_openBindPopup(el, name)
	if self.Popup then self.Popup:Destroy() end
	local overlay = create("TextButton", {
		Name = "BindPopup", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		ZIndex = 20, Parent = self.Main,
	}, {corner(6)})
	self.Popup = overlay
	tween(overlay, {BackgroundTransparency = 0.5})

	local box = make("Frame", {
		Active = true, Size = UDim2.fromOffset(300, 0), AutomaticSize = AY,
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0, Parent = overlay,
	}, {BackgroundColor3 = "PageRaised"}, {
		corner(6), stroke("Rule2"),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18),
			PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20),
		}),
		list(0),
	})
	local scale = create("UIScale", {Scale = 0.96, Parent = box})
	tween(scale, {Scale = 1}, FAST)

	local isToggle = el.Type == "Toggle"
	local defaultMode = isToggle and "Toggle" or (el.Type == "Dropdown" and "Cycle" or "Press")
	local bind = Library.Binds[el.Flag] and table.clone(Library.Binds[el.Flag]) or {Key = nil, Mode = defaultMode}

	local head = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, Parent = box,
	}, {list(8, H, {VerticalAlignment = Enum.VerticalAlignment.Center})})
	label({
		Text = "Keybind", FontFace = FONTS.HeadingBold, TextSize = 16,
		AutomaticSize = AX, Size = UDim2.fromOffset(0, 22), LayoutOrder = 1, Parent = head,
	})
	label({
		Text = name, FontFace = FONTS.Italic, TextSize = 13, Role = "Accent", TextTruncate = TRUNC,
		Size = UDim2.fromOffset(170, 22), LayoutOrder = 2, Parent = head,
	})
	make("Frame", {Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, LayoutOrder = 2, Parent = box}, {BackgroundColor3 = "Rule2"})

	local keyRow = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 3, Parent = box,
	}, {list(12, H, {VerticalAlignment = Enum.VerticalAlignment.Center})})
	local keyBtn = keycap(keyLabel(bind.Key), keyRow, "Text")
	keyBtn.TextSize = 13
	keyBtn.Size = UDim2.fromOffset(0, 30)
	keyBtn.LayoutOrder = 1
	local hint = label({
		Text = "click, then press a key", FontFace = FONTS.Italic, TextSize = 12, Role = "SubText",
		AutomaticSize = AX, Size = UDim2.fromOffset(0, 30), LayoutOrder = 2, Parent = keyRow,
	})

	local function commit()
		if bind.Key then
			Library.Binds[el.Flag] = {Key = bind.Key, Mode = bind.Mode}
			if bind.Mode == "Always" then el:Set(true) end
		else
			Library.Binds[el.Flag] = nil
		end
		touch()
		el:RefreshBind()
	end

	if isToggle then
		local modes = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 4, Parent = box})
		make("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0, Parent = modes},
			{BackgroundColor3 = "Rule2"})
		local items = create("Frame", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = modes,
		}, {list(22, H, {VerticalAlignment = Enum.VerticalAlignment.Bottom})})
		local views = {}
		local function refreshModes(animate)
			local T = CURRENT_THEME
			for mode, v in pairs(views) do
				local on = mode == bind.Mode
				v.Text.FontFace = on and FONTS.Italic or FONTS.Body
				v.Text.TextColor3 = on and T.Text or T.SubText
				apply(v.Under, {Size = UDim2.new(on and 1 or 0, 0, 0, 2)}, animate and SLIDE or nil)
			end
		end
		for i, mode in ipairs({"Always", "Toggle", "Hold"}) do
			local b = create("TextButton", {
				Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AutomaticSize = AX,
				Size = UDim2.fromOffset(0, 30), LayoutOrder = i, Parent = items,
			})
			local t = label({Text = mode, Role = false, TextSize = 14, AutomaticSize = AX, Size = UDim2.fromOffset(0, 28), Parent = b})
			local u = make("Frame", {
				Size = UDim2.new(0, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0, Parent = b,
			}, {BackgroundColor3 = "Accent"})
			views[mode] = {Text = t, Under = u}
			b.MouseButton1Click:Connect(function()
				playSound("Click")
				bind.Mode = mode
				refreshModes(true)
				commit()
			end)
		end
		restyle(items, function() refreshModes(false) end)
		label({
			Text = "Always stays on · Toggle flips each press · Hold is on while the key is down",
			TextSize = 12, Role = "SubText", TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, LayoutOrder = 5, Parent = box,
		}, {create("UIPadding", {PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 16)})})
	else
		create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 5, Parent = box})
	end

	local footer = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 6, Parent = box})
	local unbind = make("TextButton", {
		Text = track("Unbind"), FontFace = FONTS.BodySemi, TextSize = 11, AutoButtonColor = false,
		BackgroundTransparency = 1, AutomaticSize = AX, Size = UDim2.fromOffset(0, 32), Parent = footer,
	}, {TextColor3 = "Danger"})
	local done = textButton(footer, "Done", "primary")
	done.AnchorPoint = Vector2.new(1, 0)
	done.Position = UDim2.fromScale(1, 0)

	local function close()
		if self.Popup == overlay then self.Popup = nil end
		tween(scale, {Scale = 0.96})
		tween(overlay, {BackgroundTransparency = 1}).Completed:Wait()
		overlay:Destroy()
	end

	keyBtn.MouseButton1Click:Connect(function()
		keyBtn.Text = "…"
		hint.Text = "press a key or mouse button (Esc cancels)"
		self:ListenForKey(function(key)
			if key then bind.Key = key end
			keyBtn.Text = keyLabel(bind.Key)
			hint.Text = "click, then press a key"
			commit()
		end)
	end)
	unbind.MouseButton1Click:Connect(function() bind.Key = nil; commit(); close() end)
	done.MouseButton1Click:Connect(close)
	overlay.MouseButton1Click:Connect(close)
end

-- ---------------------------------------------------------------------------
-- MODAL DIALOGS
-- Prompt/Confirm share the bind popup's backdrop + centred box. Every open modal
-- is tracked in self._popups so SetVisible(false) (and Unload) closes them too.
-- ---------------------------------------------------------------------------
local DIALOG_ROLE = {Info = "Accent", Success = "Success", Warning = "Warning", Danger = "Danger"}

function Library:Prompt(opts)
	opts = opts or {}
	local kind = opts.Kind or "Info"
	local role = DIALOG_ROLE[kind] or "Accent"
	local dismissable = opts.Dismissable ~= false
	local buttons = opts.Buttons or {{Text = "OK", Kind = "primary"}}

	local overlay = create("TextButton", {
		Name = "Prompt", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		ZIndex = 20, Parent = self.Main,
	}, {corner(6)})
	tween(overlay, {BackgroundTransparency = 0.5})

	local box = make("Frame", {
		Active = true, Size = UDim2.fromOffset(opts.Width or 300, 0), AutomaticSize = AY,
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0, ZIndex = 21, Parent = overlay,
	}, {BackgroundColor3 = "PageRaised"}, {
		corner(6), stroke("Rule2"),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18),
			PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20),
		}),
		list(10),
	})
	local scale = create("UIScale", {Scale = 0.96, Parent = box})
	tween(scale, {Scale = 1}, FAST)
	playSound("Popup")

	local head = create("Frame", {
		Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Parent = box,
	})
	local accent = make("Frame", {
		Name = "Accent", Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0, Parent = head,
	}, {BackgroundColor3 = role})
	local title = label({
		Text = tostring(opts.Title or ""), FontFace = FONTS.HeadingBold, TextSize = 16, TextTruncate = TRUNC,
		Size = UDim2.new(1, -(dismissable and 24 or 0) - 11, 1, 0), Position = UDim2.fromOffset(11, 0), Parent = head,
	})
	make("Frame", {Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, LayoutOrder = 2, Parent = box}, {BackgroundColor3 = "Rule2"})

	local body = create("Frame", {
		Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY,
		LayoutOrder = 3, Parent = box,
	}, {list(8)})
	local bodyLbl = label({
		Text = tostring(opts.Body or ""), TextSize = 13, Role = "SubText", TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, AutomaticSize = AY, Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 0, Visible = opts.Body ~= nil and opts.Body ~= "", Parent = body,
	})

	local prompt = {Body = body, Closed = false}

	local footer = create("Frame", {
		Name = "Footer", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 5, Parent = box,
	}, {list(8, H, {HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center})})

	local function close()
		if prompt.Closed then return end
		prompt.Closed = true
		if self._popups then
			for i = #self._popups, 1, -1 do
				if self._popups[i] == prompt then table.remove(self._popups, i) end
			end
		end
		if prompt.Cleanup then pcall(prompt.Cleanup) end
		tween(scale, {Scale = 0.96})
		local out = tween(overlay, {BackgroundTransparency = 1})
		if out then out.Completed:Wait() end
		overlay:Destroy()
	end

	prompt.Close = close
	prompt.SetTitle = function(_, t) title.Text = tostring(t or "") end
	prompt.SetBody = function(_, t)
		bodyLbl.Text = tostring(t or "")
		bodyLbl.Visible = t ~= nil and t ~= ""
	end

	if opts.Content then
		prompt.Cleanup = opts.Content(body)
	end

	for i, btn in ipairs(buttons) do
		local b = textButton(footer, btn.Text or "", btn.Kind, i)
		-- Optional click delay: Cooldown = seconds. The button shows a
		-- countdown ("Continue (5)") and ignores clicks until it hits 0.
		local cooldown = math.floor(tonumber(btn.Cooldown) or 0)
		local baseText = btn.Text or ""
		if cooldown > 0 then
			local left = cooldown
			b.Active = false
			b.TextTransparency = 0.5
			b.Text = track(baseText) .. "  (" .. left .. ")"
			task.spawn(function()
				while left > 0 do
					task.wait(1)
					if prompt.Closed then return end
					left -= 1
					if left > 0 then
						b.Text = track(baseText) .. "  (" .. left .. ")"
					else
						b.Text = track(baseText)
						b.TextTransparency = 0
						b.Active = true
					end
				end
			end)
		end
		connect(b.MouseButton1Click, function()
			if cooldown > 0 and b.Active == false then return end
			playSound("Click")
			if btn.Callback then pcall(btn.Callback) end
			close()
		end)
	end

	if dismissable then
		local closeBtn = make("TextButton", {
			Name = "Close", Text = "×", FontFace = FONTS.Body, TextSize = 18, AutoButtonColor = false,
			BackgroundTransparency = 1, Size = UDim2.fromOffset(22, 22),
			Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = head,
		}, {TextColor3 = "SubText"})
		connect(closeBtn.MouseButton1Click, function() playSound("Click"); close() end)
		connect(overlay.MouseButton1Click, function() playSound("Click"); close() end)
	end

	self._popups = self._popups or {}
	table.insert(self._popups, prompt)

	if type(opts.Timeout) == "number" and opts.Timeout > 0 then
		task.delay(opts.Timeout, function()
			if prompt.Closed then return end
			if opts.OnTimeout then pcall(opts.OnTimeout) end
			close()
		end)
	end

	return prompt
end

function Library:Confirm(opts)
	opts = opts or {}
	local kind = opts.Kind or "Danger"
	return self:Prompt({
		Title = opts.Title,
		Body = opts.Body,
		Kind = kind,
		Width = opts.Width,
		Dismissable = opts.Dismissable,
		Buttons = {
			{Text = opts.CancelText or "Cancel", Callback = function()
				if opts.OnCancel then opts.OnCancel() end
			end},
			{Text = opts.ConfirmText or "Confirm", Kind = kind == "Danger" and "danger" or "primary", Callback = function()
				if opts.OnConfirm then opts.OnConfirm() end
			end},
		},
	})
end

-- ---------------------------------------------------------------------------
-- EXECUTOR SUPPORT WARNING (Xeno / Solara)
-- Detects the running executor and shows a markdown-based modal popup when it
-- is known to have limited support. Usage (one line after Library.new):
--   win:CheckExecutorSupport()
-- ---------------------------------------------------------------------------
function Library:GetExecutorName()
	-- Per Potassium docs: identifyexecutor() returns (name, version).
	-- Alias: getexecutorname. Both names are documented; anything else is not.
	-- NOTE: plain env[key] access, NOT rawget. Executor globals like
	-- identifyexecutor resolve through the environment metatable, so rawget
	-- misses them (verified live: rawget -> nil, direct call -> works).
	local function tryGlobal(key)
		local ok, fn = pcall(function()
			local env = getfenv and getfenv() or _G
			local f = env and env[key] or nil
			if type(f) ~= "function" and type(_G) == "table" then
				f = _G[key]
			end
			return f
		end)
		if not ok or type(fn) ~= "function" then return nil end
		local okCall, name, _version = pcall(fn)
		if okCall and type(name) == "string" and name ~= "" then return name end
		return nil
	end
	local name = tryGlobal("identifyexecutor")
		or tryGlobal("getexecutorname")
	if type(name) ~= "string" or name == "" then
		name = "Unknown"
	end
	return name
end

function Library:IsLowSupportExecutor(name)
	if type(name) ~= "string" or name == "" then
		name = self:GetExecutorName()
	end
	local lower = string.lower(tostring(name))
	local unsupported = lower:find("xeno", 1, true) ~= nil or lower:find("solara", 1, true) ~= nil
	if not unsupported then
		-- Test hook (dev only, per session): run this in the executor
		-- console BEFORE executing any script to force the warning:
		--   getgenv().GliderTestExecutorWarn = true
		-- Production sessions never set it, so behavior is unchanged.
		if type(getgenv) == "function" then
			local ok, env = pcall(getgenv)
			if ok and type(env) == "table" and env.GliderTestExecutorWarn == true then
				unsupported = true
			end
		end
	end
	return unsupported, name
end

function Library:ShowExecutorWarning(opts)
	opts = opts or {}
	local win = self
	local execName = opts.ExecutorName or self:GetExecutorName()
	local md = opts.Markdown or ([[
# Executor Warning
Detected executor: `]] .. tostring(execName) .. [[`
---
**MY SCRIPTS ARE MOST LIKELY NOT SUPPORTED FOR XENO OR SOLARA.**
- Expect missing features, broken visuals, or crashes on these executors.
- For the best experience use a fully supported executor.
---
> IF YOU STILL WANNA TRY THEN CONTINUE.
> To see supported executors join our Discord: https://discord.gg/Z3vCpEPevt
]])
	return self:Prompt({
		Title = opts.Title or "Unsupported Executor",
		Kind = opts.Kind or "Warning",
		Width = opts.Width or 360,
		Dismissable = opts.Dismissable ~= nil and opts.Dismissable or false,
		Content = function(body)
			Tab.AddMarkdown(win, md, { Parent = body })
		end,
		Buttons = opts.Buttons or {
			{ Text = opts.ContinueText or "Continue", Kind = "primary",
				Cooldown = opts.ContinueCooldown or 5, Callback = function()
				if opts.OnContinue then pcall(opts.OnContinue) end
			end },
		},
		Timeout = opts.Timeout,
		OnTimeout = opts.OnTimeout,
	})
end

-- Shows the warning popup only when the current executor is Xeno or Solara.
-- Returns the prompt handle on unsupported executors, nil otherwise.
function Library:CheckExecutorSupport(opts)
	opts = opts or {}
	local unsupported = self:IsLowSupportExecutor(opts.ExecutorName)
	if unsupported then
		return self:ShowExecutorWarning(opts)
	end
	if opts.OnSupported then pcall(opts.OnSupported) end
	return nil
end

-- ---------------------------------------------------------------------------
-- CONFIG MANAGER & TAB
-- ---------------------------------------------------------------------------
function Library:Serialize()
	local binds = {}
	for flag, b in pairs(Library.Binds) do if not GLOBAL_FLAGS[flag] then binds[flag] = {Key = b.Key.Name, Mode = b.Mode} end end
	local flags = {}
	for flag, v in pairs(Library.Flags) do
		local owner = Library.Elements[flag]
		if not GLOBAL_FLAGS[flag] and not (owner and owner.NoSave) then
			flags[flag] = (typeof(v) == "Color3") and toHex(v) or v
		end
	end
	return {flags = flags, binds = binds}
end

function Library:Apply(data)
	self._applying = true
	local count = 0
	for flag, v in pairs(data.flags or {}) do
		if not GLOBAL_FLAGS[flag] then
			local el = Library.Elements[flag]
			if el and el.Type ~= "Keybind" and not el.NoSave then
				-- One widget refusing its stored value must not abort the whole load and swallow
				-- the success notification: isolate it, count it and keep going.
				local ok, err = pcall(el.Set, el, el.Type == "ColorPicker" and (fromHex(v) or el.Value) or v)
				if ok then
					count += 1
				else
					print("[Glider] Apply skipped " .. tostring(flag) .. ":", err)
				end
			end
		end
	end
	Library.Binds = {}
	for flag, b in pairs(data.binds or {}) do
		if not GLOBAL_FLAGS[flag] and toKeyCode(b.Key) then Library.Binds[flag] = {Key = toKeyCode(b.Key), Mode = b.Mode} end
	end
	for _, el in pairs(Library.Elements) do
		if el.RefreshBind then el:RefreshBind() end
		if el.Type == "Keybind" and not GLOBAL_FLAGS[el.Flag] and data.flags and data.flags[el.Flag] then
			el:Set(data.flags[el.Flag])
		end
	end
	self._applying = false
	self._lastApplyCount = count
	return count
end

function Library:AutoLoad()
	self._building = false
	local n = Storage.getAutoload()
	if not n then return end
	local data = Storage.load(n)
	if not data then return end
	local count = self:Apply(data)
	self.ActiveConfig = n
	if self.RefreshConfigList then self.RefreshConfigList() end
	self:_refreshConfigStatus()
	self:Notify({Title = "Config", Body = 'Auto-loaded "' .. n .. '" (' .. count .. ' features)', Type = "Success"})
end

function Library:SetAutoSave(v, animate)
	self.AutoSave = v and true or false
	self._building = false
	Storage.setAutosave(self.AutoSave, true)
	if self.AutoSave and not self.ActiveConfig then
		self.ActiveConfig = Storage.getAutoload() or "default"
		if not Storage.getAutoload() then
			Storage.setAutoload(self.ActiveConfig)
		end
		Storage.save(self.ActiveConfig, self:Serialize())
	end
	if self._updateAutoSaveUI then
		self._updateAutoSaveUI(self.AutoSave, animate ~= false)
	end
	self:_refreshConfigStatus()
end

function Library:AddConfigTab(name, icon)
	local tab = self:AddTab(name or "Config", icon or Library.Icons.Config, true)
	self.ConfigTab = tab

	self:_executorSection(tab)
	tab:AddSection("Current")
	local nameRow = row(tab, 44)
	label({
		Text = "Config Name", TextTruncate = TRUNC,
		Size = UDim2.new(0.4, -PAD, 1, 0), Position = UDim2.fromOffset(PAD, 0), Parent = nameRow,
	})
	local nameBox = make("TextBox", {
		Text = "", PlaceholderText = "Enter a name…", FontFace = FONTS.Body, TextSize = 14,
		ClearTextOnFocus = false, TextXAlignment = LEFT, BackgroundTransparency = 1, TextTruncate = TRUNC,
		Size = UDim2.new(0.55, -PAD, 0, 24), Position = UDim2.new(1, -PAD, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		Parent = nameRow,
	}, {TextColor3 = "Text", PlaceholderColor3 = "SubText"})
	underline(nameBox)
	italicWhenEmpty(nameBox)

	local actionsBlock = block(tab, 60)
	local group = create("Frame", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(PAD, 14),
		Size = UDim2.new(1, -PAD * 2 - 96, 0, 32), AutomaticSize = AY, Parent = actionsBlock,
	})
	local groupLayout = list(8, H, {VerticalAlignment = Enum.VerticalAlignment.Center})
	pcall(function() groupLayout.Wraps = true end)
	groupLayout.Parent = group
	groupLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local h = groupLayout.AbsoluteContentSize.Y / self:_uiScale()
		actionsBlock.Size = UDim2.new(1, 0, 0, math.max(60, math.ceil(h) + 28))
	end)

	-- Auto-save switch with a caption saying what it will do.
	local asRow = row(tab, 56)
	local asHit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = asRow})
	label({Text = "Auto-save", Size = UDim2.new(1, -80, 0, 18), Position = UDim2.fromOffset(PAD, 10), Parent = asRow})
	local asNote = label({
		Text = "", FontFace = FONTS.Italic, TextSize = 12, Role = "SubText", TextTruncate = TRUNC,
		Size = UDim2.new(1, -80, 0, 16), Position = UDim2.fromOffset(PAD, 31), Parent = asRow,
	})
	local _, showAutoSave = capsule(asRow, UDim2.new(1, -PAD - 1, 0.5, 0))
	local function refreshNote()
		asNote.Text = self.AutoSave
			and ('Changes write to "' .. (self.ActiveConfig or "the active config") .. '" automatically.')
			or "Nothing writes until you press Save."
	end
	local function setAutoSave(v, animate)
		self.AutoSave = v and true or false
		Storage.setAutosave(self.AutoSave, false)
		showAutoSave(self.AutoSave, animate)
		refreshNote()
		self:_refreshConfigStatus()
	end
	self._updateAutoSaveUI = function(v, animate) setAutoSave(v, animate) end
	asHit.MouseButton1Click:Connect(function() playSound("Click"); self:SetAutoSave(not self.AutoSave, true) end)
	setAutoSave(self.AutoSave, false)

	tab:AddSection("Saved")
	local listHolder = block(tab, 0) -- sits on the "Saved" sheet; holds one row per config
	listHolder.AutomaticSize = AY
	listHolder:FindFirstChild("Rule").Visible = false
	list(0).Parent = listHolder
	local autoRow = row(tab, ROW_H)
	local autoLabel = label({
		Text = "", Role = "SubText", TextTruncate = TRUNC,
		Size = UDim2.new(1, -160, 1, 0), Position = UDim2.fromOffset(PAD, 0), Parent = autoRow,
	})
	local clearLink = make("TextButton", {
		Text = track("Clear autoload"), FontFace = FONTS.BodySemi, TextSize = 10, AutoButtonColor = false,
		BackgroundTransparency = 1, AutomaticSize = AX, Size = UDim2.fromOffset(0, ROW_H),
		Position = UDim2.new(1, -PAD, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = autoRow,
	}, {TextColor3 = "SubText"})
	clearLink.MouseEnter:Connect(function() tween(clearLink, {TextColor3 = CURRENT_THEME.Accent}) end)
	clearLink.MouseLeave:Connect(function() tween(clearLink, {TextColor3 = CURRENT_THEME.SubText}) end)

	local function refreshList()
		for _, c in ipairs(listHolder:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local names = Storage.list()
		local auto = Storage.getAutoload()
		autoLabel.Text = "Autoload: " .. (auto or "none")
		clearLink.Visible = auto ~= nil
		if #names == 0 then
			local empty = create("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ROW_H), Parent = listHolder})
			label({
				Text = "No saved configs yet.", FontFace = FONTS.Italic, TextSize = 13, Role = "SubText",
				Size = UDim2.new(1, -PAD * 2, 1, 0), Position = UDim2.fromOffset(PAD, 0), Parent = empty,
			})
		end
		for i, n in ipairs(names) do
			local active = n == self.ActiveConfig
			local b = make("TextButton", {
				Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, ROW_H), LayoutOrder = i, Parent = listHolder,
			}, {BackgroundColor3 = "Hover"})
			make("Frame", {
				Size = UDim2.new(1, -PAD * 2, 0, 1), Position = UDim2.fromOffset(PAD, 0), BackgroundTransparency = 0.35,
				BorderSizePixel = 0, Visible = i > 1, Parent = b,
			}, {BackgroundColor3 = "Rule2"})
			label({
				Text = n, FontFace = active and FONTS.Italic or FONTS.Body, Role = active and "Accent" or "Text",
				TextTruncate = TRUNC, Size = UDim2.new(1, -170, 1, 0), Position = UDim2.fromOffset(PAD, 0), Parent = b,
			})
			local tags = {}
			if active then table.insert(tags, "active") end
			if n == auto then table.insert(tags, "autoload") end
			if #tags > 0 then
				label({
					Text = table.concat(tags, " · "), FontFace = FONTS.Italic, TextSize = 12,
					Role = active and "Accent" or "SubText", TextXAlignment = RIGHT,
					Size = UDim2.fromOffset(150, ROW_H), Position = UDim2.new(1, -PAD, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = b,
				})
			end
			b.MouseEnter:Connect(function() tween(b, {BackgroundTransparency = 0.96}) end)
			b.MouseLeave:Connect(function() tween(b, {BackgroundTransparency = 1}) end)
			b.MouseButton1Click:Connect(function() playSound("Click"); nameBox.Text = n end)
		end
		self:_refreshConfigStatus()
		refreshNote()
	end
	self.RefreshConfigList = refreshList

	local function getName()
		local n = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if n == "" then self:Notify({Title = "Config", Body = "Enter a config name first.", Type = "Warning"}) return nil end
		return n
	end

	local actions = {
		New = function()
			local n = getName(); if not n then return end
			if Storage.load(n) then self:Notify({Title = "Config", Body = n .. " already exists.", Type = "Warning"}) return end
			self._applying = true
			for _, el in pairs(Library.Elements) do
				if el.Set and el.Default ~= nil and not GLOBAL_FLAGS[el.Flag] and not el.NoSave then el:Set(el.Default) end
			end
			Library.Binds = {}
			for _, el in pairs(Library.Elements) do if el.RefreshBind then el:RefreshBind() end end
			self._applying = false
			Storage.save(n, self:Serialize())
			self.ActiveConfig = n
			refreshList()
			self:Notify({Title = "Config Created", Body = n .. " created and saved.", Type = "Success"})
		end,
		Load = function()
			local n = getName(); if not n then return end
			local data = Storage.load(n)
			if not data then self:Notify({Title = "Config", Body = "No config named " .. n, Type = "Error"}) return end
			local count = self:Apply(data)
			self.ActiveConfig = n
			refreshList()
			self:Notify({Title = "Config Loaded", Body = count .. ' features restored from "' .. n .. '"', Type = "Success"})
		end,
		Save = function()
			local n = getName(); if not n then return end
			Storage.save(n, self:Serialize())
			self.ActiveConfig = n
			refreshList()
			self:Notify({Title = "Config Saved", Body = n .. " updated successfully.", Type = "Success"})
		end,
		Delete = function()
			local n = getName(); if not n then return end
			Storage.delete(n)
			if self.ActiveConfig == n then self.ActiveConfig = nil end
			if Storage.getAutoload() == n then Storage.setAutoload(nil) end
			refreshList()
			self:Notify({Title = "Config Deleted", Body = n .. " removed.", Type = "Info"})
		end,
		["Set Autoload"] = function()
			local n = getName(); if not n then return end
			if not Storage.load(n) then self:Notify({Title = "Config", Body = "Save " .. n .. " first.", Type = "Warning"}) return end
			Storage.setAutoload(n)
			refreshList()
			self:Notify({Title = "Autoload Set", Body = n .. " will load on inject.", Type = "Success"})
		end,
		["Clear Autoload"] = function()
			Storage.setAutoload(nil)
			refreshList()
			self:Notify({Title = "Autoload", Body = "Cleared autoload config.", Type = "Info"})
		end,
	}
	-- A config action that errors must say so: a silent failure looks exactly like a dead button.
	for _, key in ipairs({"New", "Load", "Save", "Delete", "Set Autoload", "Clear Autoload"}) do
		local inner = actions[key]
		actions[key] = function(...)
			local ok, err = pcall(inner, ...)
			if not ok then
				self._applying = false -- never leave the library frozen
				print("[Glider] config " .. key .. " failed:", err)
				self:Notify({Title = "Config Error", Body = tostring(key) .. " failed: " .. tostring(err), Type = "Error", Duration = 8})
			end
		end
	end
	self._configActions = actions

	for i, spec in ipairs({{"New"}, {"Save", "primary"}, {"Load"}, {"Set Autoload"}}) do
		local b = textButton(group, spec[1], spec[2], i)
		b.MouseButton1Click:Connect(function() playSound("Click"); actions[spec[1]]() end)
	end
	local del = textButton(actionsBlock, "Delete", "danger")
	del.AnchorPoint = Vector2.new(1, 0)
	del.Position = UDim2.new(1, -PAD, 0, 14)
	del.MouseButton1Click:Connect(function() playSound("Click"); actions.Delete() end)
	clearLink.MouseButton1Click:Connect(function() playSound("Click"); actions["Clear Autoload"]() end)

	refreshList()
	return tab
end

function Library:AddDiscordTab(name, icon)
	local tab = self:AddTab(name or "Discord", icon or Library.Icons.Misc, true)
	self.DiscordTab = tab

	tab:AddSection("Community & Support")
	tab:AddMarkdown([[
# Community & Support
Please let us know if there is any issue with our scripts!
- Join the **Discord Server** for updates and support.
- Custom scripts from **+5EUR** -- DM `jirxy_2` for any issue or request.
---
> Need help? Open a ticket or DM us on Discord.
]])
	tab:AddButton({
		Name = "Copy Discord Invite",
		Callback = function()
			local clipFn = setclipboard or toclipboard or (syn and syn.write_clipboard)
			if clipFn then pcall(clipFn, "https://discord.gg/Z3vCpEPevt") end
			self:Notify({Title = "Discord Server", Body = "Invite copied to clipboard!", Type = "Success"})
		end,
	})
	tab:AddButton({
		Name = "Copy Discord Tag (jirxy_2)",
		Callback = function()
			local clipFn = setclipboard or toclipboard or (syn and syn.write_clipboard)
			if clipFn then pcall(clipFn, "jirxy_2") end
			self:Notify({Title = "Discord Tag", Body = "Copied to clipboard!", Type = "Success"})
		end,
	})
	return tab
end

-- ---------------------------------------------------------------------------
-- TOOLTIPS & RISKY NAMES
-- Any element takes Tooltip = "..." (shown after its row is hovered for a moment) and
-- Risky = true (its name is drawn in the Warning colour, for options that are easier to notice).
-- ---------------------------------------------------------------------------
local TextService = game:GetService("TextService")
local TOOLTIP_DELAY, TOOLTIP_MAX_W = 0.45, 260

function Library:_tooltipView()
	if self._tip and self._tip.Frame.Parent then return self._tip end
	local frame = make("Frame", {
		Name = "Tooltip", AutomaticSize = AY, Size = UDim2.fromOffset(TOOLTIP_MAX_W, 0), Visible = false,
		BorderSizePixel = 0, ZIndex = 300, Parent = self.Gui,
	}, {BackgroundColor3 = "ChromeRaised"}, {corner(5), stroke("Rule2", 1, 0.2), padding(7, 10)})
	local text = label({
		Text = "", TextSize = 12, TextWrapped = true, Role = "ChromeText", AutomaticSize = AY,
		Size = UDim2.new(1, 0, 0, 0), ZIndex = 301, Parent = frame,
	})
	self._tip = {Frame = frame, Text = text}
	return self._tip
end

function Library:_placeTooltip()
	local tip = self._tip
	if not (tip and tip.Frame.Visible) then return end
	local m = UIS:GetMouseLocation()
	local screen = self.Gui.AbsoluteSize
	local size = tip.Frame.AbsoluteSize
	local x = math.min(m.X + 14, screen.X - size.X - 8)
	local y = m.Y + 18
	if y + size.Y > screen.Y - 8 then y = m.Y - size.Y - 10 end
	tip.Frame.Position = UDim2.fromOffset(math.max(8, x), math.max(8, y))
end

function Library:_attachTooltip(frame, text)
	local hovering, token = false, 0
	frame.MouseEnter:Connect(function()
		hovering = true
		token += 1
		local mine = token
		task.delay(TOOLTIP_DELAY, function()
			if not hovering or mine ~= token or not self.Visible then return end
			local tip = self:_tooltipView()
			local width = TextService:GetTextSize(text, 12, Enum.Font.Gotham, Vector2.new(TOOLTIP_MAX_W - 20, 2000)).X
			tip.Frame.Size = UDim2.fromOffset(math.min(TOOLTIP_MAX_W, width + 22), 0)
			tip.Text.Text = text
			tip.Frame.Visible = true
			self:_placeTooltip()
		end)
	end)
	frame.MouseMoved:Connect(function() self:_placeTooltip() end)
	frame.MouseLeave:Connect(function()
		hovering = false
		token += 1
		if self._tip then self._tip.Frame.Visible = false end
	end)
end

for _, method in ipairs({"AddToggle", "AddSlider", "AddButton", "AddDropdown", "AddMultiDropdown", "AddTextbox", "AddColorPicker", "AddKeybind"}) do
	local original = Tab[method]
	Tab[method] = function(self, opts, ...)
		local el = original(self, opts, ...)
		if type(opts) == "table" and type(el) == "table" and el.Frame then
			if type(opts.Tooltip) == "string" and opts.Tooltip ~= "" then
				self.Window:_attachTooltip(el.Frame, opts.Tooltip)
			end
			if opts.Risky and opts.Name then
				for _, d in ipairs(el.Frame:GetDescendants()) do
					if d:IsA("TextLabel") and d.Text == opts.Name then
						paint(d, {TextColor3 = "Warning"})
						break
					end
				end
			end
		end
		return el
	end
end

-- ---------------------------------------------------------------------------
-- SIDE PANEL & 3D VIEWPORT API
-- Floating inspector attached to MainWindow with 3D studio viewport support.
-- ---------------------------------------------------------------------------
function Library:CreateSidePanel(title, opts)
	if type(title) == "table" then opts = title; title = opts.Title end
	opts = opts or {}
	title = title or opts.Title or "Preview"
	-- Called as Library:CreateSidePanel, self is the Library module, but
	-- Main/Gui live on the window instance: resolve it explicitly so the
	-- panel anchors to a real window either way.
	local host = (self and self.Main) and self or Library._window
	if not host or not host.Main or not host.Gui then
		error("CreateSidePanel needs a window: call it after Library.new()")
	end
	local baseWidth = opts.Width or 300
	local gap = opts.Gap or 12

	local panel = {
		Title = title,
		IsOpen = opts.Default == true or false,
		WindowVisible = host.Visible ~= false,
		_connections = {},
	}

	-- Root frame parented to ScreenGui (never clipped by MainWindow)
	local frame = make("Frame", {
		Name = "SidePanel",
		Size = UDim2.fromOffset(baseWidth, host.Main.Size.Y.Offset),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		Parent = host.Gui,
	}, { BackgroundColor3 = "PageBg" }, { corner(6), stroke("Edge") })
	panel.Frame = frame

	local panelScale = create("UIScale", { Scale = 1, Parent = frame })
	panel.Scale = panelScale
	grain(frame, "Text")

	-- Header
	local head = make("Frame", {
		Name = "Header", Size = UDim2.new(1, 0, 0, 42), BorderSizePixel = 0,
		Parent = frame,
	}, { BackgroundColor3 = "ChromeBg" }, { corner(6) })
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 1, -6),
		BorderSizePixel = 0, Parent = head,
	}, { BackgroundColor3 = "ChromeBg" })
	grain(head, "ChromeText")
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, 0),
		BorderSizePixel = 0, ZIndex = 3, Parent = head,
	}, { BackgroundColor3 = "ChromeRule" })

	local titleLbl = label({
		Text = string.upper(title), FontFace = FONTS.Brand, TextSize = 14, Role = "ChromeText",
		TextTruncate = TRUNC, Size = UDim2.new(1, -70, 0, 24),
		Position = UDim2.fromOffset(14, 9), Parent = head,
	})
	local subLbl = label({
		Text = opts.Subtitle or "3D LIVE", FontFace = FONTS.Mono, TextSize = 9,
		Role = "ChromeSub", TextTruncate = TRUNC, AutomaticSize = AX,
		Size = UDim2.fromOffset(0, 14), Position = UDim2.new(1, -38, 0, 14),
		AnchorPoint = Vector2.new(1, 0), Parent = head,
	})
	local closeBtn = make("TextButton", {
		Text = "×", FontFace = FONTS.Title, TextSize = 18,
		Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5), AutoButtonColor = false,
		BackgroundTransparency = 1, Parent = head,
	}, { TextColor3 = "ChromeSub", BackgroundColor3 = "Hover" }, { corner(4) })
	closeBtn.MouseEnter:Connect(function() tween(closeBtn, { BackgroundTransparency = 0.85 }) end)
	closeBtn.MouseLeave:Connect(function() tween(closeBtn, { BackgroundTransparency = 1 }) end)
	closeBtn.MouseButton1Click:Connect(function()
		playSound("Click")
		panel:Close()
		if opts.OnClose then pcall(opts.OnClose) end
	end)

	-- Header drag moves the whole window + side panel together!
	makeDraggable(host.Main, head)

	-- Content scrolling container
	local content = create("ScrollingFrame", {
		Name = "Content", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 43), Size = UDim2.new(1, 0, 1, -43),
		ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY,
		Parent = frame,
	}, { list(8), padding(10, 12) })
	panel.Content = content

	-- Real-time position tracking relative to host.Main, with auto-fit: on a
	-- narrow viewport the panel shrinks instead of hanging off-screen, and
	-- when not even a slim panel fits it docks to the right screen edge as an
	-- overlay without shifting Main.
	local function panelShift()
		return math.floor(((panel._width or baseWidth) + gap) / 2)
	end
	local function updatePos()
		if not frame or not host.Main then return end
		local mainPos = host.Main.Position
		local mainSize = host.Main.Size
		local anchorX = host.Main.AnchorPoint.X
		local w, overlay = baseWidth, false
		pcall(function()
			local viewW = host.Gui.AbsoluteSize.X
			local mainW = host.Main.AbsoluteSize.X
			local side = math.floor((viewW - mainW) / 2 - gap - 8)
			if side >= 200 then
				w = math.min(baseWidth, side)
			else
				overlay = true
				w = math.min(baseWidth, math.max(220, viewW - 32))
			end
		end)
		panel._width = w
		panel._overlay = overlay
		if overlay then
			frame.AnchorPoint = Vector2.new(1, 0.5)
			frame.Position = UDim2.new(1, -8, 0.5, 0)
		else
			frame.AnchorPoint = Vector2.new(0, 0.5)
			local xOffset = (mainSize.X.Offset * (1 - anchorX)) + gap
			frame.Position = UDim2.new(
				mainPos.X.Scale, mainPos.X.Offset + xOffset,
				mainPos.Y.Scale, mainPos.Y.Offset
			)
		end
		frame.Size = UDim2.fromOffset(w, mainSize.Y.Offset)
		-- Space ran out while open: hand Main its position back.
		if overlay and panel._isShifted then
			local lib = panel.Library or Library._window
			if lib and lib.Main and panel._origMainPos then
				panel._isShifted = false
				local orig = panel._origMainPos
				panel._origMainPos = nil
				pcall(function() lib.Main.Position = orig end)
			end
		end
	end
	table.insert(panel._connections, host.Main:GetPropertyChangedSignal("Position"):Connect(updatePos))
	table.insert(panel._connections, host.Main:GetPropertyChangedSignal("Size"):Connect(updatePos))
	if host.Gui then
		table.insert(panel._connections, host.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePos))
	end
	updatePos()

	-- Methods
	function panel:SetWidth(w)
		baseWidth = math.max(200, tonumber(w) or baseWidth)
		updatePos()
	end
	panel.BoundTab = opts and opts.Tab
	panel.Library = self

	function panel:SetTitle(t)
		titleLbl.Text = string.upper(tostring(t or ""))
	end
	function panel:SetSubtitle(t, role)
		subLbl.Text = tostring(t or "")
		if role then paint(subLbl, { TextColor3 = role }) end
	end

	function panel:Open()
		local lib = self.Library or Library._window
		if panel.BoundTab and lib and lib.CurrentTab and lib.CurrentTab.Name ~= panel.BoundTab then
			return
		end
		panel.IsOpen = true
		if lib and lib.Main and not panel._isShifted and not panel._overlay then
			panel._isShifted = true
			panel._origMainPos = lib.Main.Position
			local orig = panel._origMainPos
			local target = UDim2.new(orig.X.Scale, orig.X.Offset - panelShift(), orig.Y.Scale, orig.Y.Offset)
			tween(lib.Main, { Position = target }, SLIDE)
		end
		updatePos()
		if not lib or lib.Visible ~= false then
			frame.Visible = true
			panelScale.Scale = 0.96
			tween(panelScale, { Scale = 1 }, SLIDE)
		end
	end

	function panel:Close()
		local lib = self.Library or Library._window
		panel.IsOpen = false
		if panel._isShifted and lib and lib.Main and panel._origMainPos then
			panel._isShifted = false
			local orig = panel._origMainPos
			panel._origMainPos = nil
			tween(lib.Main, { Position = orig }, SLIDE)
		end
		tween(panelScale, { Scale = 0.96 }, FAST).Completed:Connect(function()
			if not panel.IsOpen then frame.Visible = false end
		end)
	end

	function panel:Toggle(v)
		if v == nil then v = not self.IsOpen end
		if v then self:Open() else self:Close() end
	end

	function panel:Clear()
		for _, c in ipairs(content:GetChildren()) do
			if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
				pcall(function() c:Destroy() end)
			end
		end
	end

	-- 3D Viewport Builder
	function panel:AddViewport(vpOpts)
		vpOpts = vpOpts or {}
		local vpH = vpOpts.Height or 240
		local card = make("Frame", {
			Name = "ViewportCard", Size = UDim2.new(1, 0, 0, vpH),
			BackgroundTransparency = 0.45, BorderSizePixel = 0, LayoutOrder = 1,
			Parent = content,
		}, { BackgroundColor3 = "PageRaised" }, { corner(8), stroke("Rule2", 1, 0.4) })

		local vpFrame = Instance.new("ViewportFrame")
		vpFrame.Name = "ModelViewport"
		vpFrame.Size = UDim2.fromScale(1, 1)
		vpFrame.BackgroundTransparency = 1
		vpFrame.Ambient = Color3.fromRGB(220, 215, 225)
		vpFrame.LightColor = Color3.fromRGB(255, 255, 255)
		vpFrame.LightDirection = Vector3.new(-1, -1.2, -1.5).Unit
		vpFrame.Parent = card

		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = vpFrame

		local camera = Instance.new("Camera")
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = vpOpts.FieldOfView or 48
		camera.Parent = vpFrame
		vpFrame.CurrentCamera = camera

		local vp = {
			Card = card,
			Viewport = vpFrame,
			WorldModel = worldModel,
			Camera = camera,
			CurrentModel = nil,
			IsRotating = false,
			RotateSpeed = vpOpts.RotateSpeed or 0.85,
			Yaw = math.rad(35),
			Pitch = math.rad(-14),
			Distance = 4,
			_conn = nil,
		}

		function vp:UpdateCamera()
			local camRot = CFrame.Angles(0, self.Yaw, 0) * CFrame.Angles(self.Pitch, 0, 0)
			local camPos = camRot:PointToWorldSpace(Vector3.new(0, 0, self.Distance))
			camera.CFrame = CFrame.lookAt(camPos, Vector3.zero)
		end

		function vp:SetModel(inst, isAnimated)
			self:Clear()
			if not inst then return nil end
			local ok, clone = pcall(function() return inst:Clone() end)
			if not ok or not clone then return nil end

			if not clone:IsA("Model") then
				local m = Instance.new("Model")
				m.Name = clone.Name
				clone.Parent = m
				clone = m
			end

			-- Sterilize physics and strip invisible/utility parts (e.g. Primary, Gauge, helper joints)
			-- so they do not artificially distort the visual bounding box
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then
					if d.Transparency >= 0.99 or d.Name == "Primary" or d.Name == "Gauge" or d.Name == "Flash" or d.Name == "Sight" then
						pcall(function() d:Destroy() end)
					else
						d.Anchored = true
						d.CanCollide = false
						d.CanTouch = false
						d.CanQuery = false
						d.CastShadow = false
					end
				elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
					d.Enabled = false
				end
			end
			if clone:IsA("BasePart") then
				clone.Anchored = true
				clone.CanCollide = false
			end

			-- Center model bounding box at Vector3.zero
			local cf, size = clone:GetBoundingBox()
			local center = cf.Position
			clone:PivotTo(CFrame.new(-center) * clone:GetPivot())

			-- Auto-frame
			local maxDim = math.max(size.X, size.Y, size.Z, 0.2)
			local fovRad = math.rad(camera.FieldOfView)
			local zoom = vpOpts.ZoomMultiplier or 1.04
			self.Distance = math.max((maxDim * 0.5) / math.tan(fovRad * 0.5) * zoom, 0.4)

			clone.Parent = worldModel
			self.CurrentModel = clone
			self._animTextures = {}
			if isAnimated == true then
				for _, d in ipairs(clone:GetDescendants()) do
					if d:IsA("Texture") then
						table.insert(self._animTextures, d)
					end
				end
			end
			self:UpdateCamera()
			return clone
		end

		function vp:Clear()
			self._animTextures = nil
			if self.CurrentModel then
				pcall(function() self.CurrentModel:Destroy() end)
				self.CurrentModel = nil
			end
		end

		function vp:SetRotating(bool, speed)
			self.IsRotating = bool
			if speed then self.RotateSpeed = speed end
		end

		function vp:ResetRotation()
			self.Yaw = math.rad(25)
			self:UpdateCamera()
		end

		vp._conn = RunService.RenderStepped:Connect(function(dt)
			if card.Visible and card.Parent and vp.CurrentModel and vp.CurrentModel.Parent then
				local lib = Library._window
				if lib and lib.Visible == false then return end
				if vp.IsRotating then
					vp.Yaw = (vp.Yaw + dt * vp.RotateSpeed) % (math.pi * 2)
					vp:UpdateCamera()
				end
				if vp._animTextures and #vp._animTextures > 0 then
					local now = os.clock()
					for _, tex in ipairs(vp._animTextures) do
						if tex.Parent then
							local su = tex.StudsPerTileU > 0 and tex.StudsPerTileU or 1
							local sv = tex.StudsPerTileV > 0 and tex.StudsPerTileV or 1
							tex.OffsetStudsU = (now * 0.7) % su
							tex.OffsetStudsV = (now * 0.35) % sv
						end
					end
				end
			end
		end)

		function vp:Destroy()
			if self._conn then self._conn:Disconnect(); self._conn = nil end
			self:Clear()
			card:Destroy()
		end

		vp:UpdateCamera()
		return vp
	end

	-- Flat Header Info (Minimalist: zero card nesting!)
	function panel:AddHeaderInfo(opts)
		opts = opts or {}
		local container = create("Frame", {
			Name = "HeaderInfo", Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = opts.LayoutOrder or 2,
			Parent = content,
		})

		local tagLbl = label({
			Text = tostring(opts.Tag or opts.Weapon or ""), FontFace = FONTS.Body, TextSize = 10,
			Role = "ChromeSub", TextTruncate = TRUNC, Size = UDim2.new(1, 0, 0, 13),
			Position = UDim2.fromOffset(2, 2), Parent = container,
		})
		local titleLbl = label({
			Text = tostring(opts.Title or opts.Skin or ""), FontFace = FONTS.Heading, TextSize = 16,
			Role = "Text", TextTruncate = TRUNC, Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(2, 16), Parent = container,
		})
		local rarityLbl = label({
			Text = tostring(opts.Subtitle or opts.Rarity or ""), FontFace = FONTS.BodySemi, TextSize = 12,
			Role = "SubText", TextTruncate = TRUNC, Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(2, 37), Parent = container,
		})

		local info = { Container = container, TagLabel = tagLbl, TitleLabel = titleLbl, RarityLabel = rarityLbl }
		function info:Set(data)
			data = data or {}
			if data.Tag or data.Weapon then tagLbl.Text = tostring(data.Tag or data.Weapon) end
			if data.Title or data.Skin then titleLbl.Text = tostring(data.Title or data.Skin) end
			local sub = data.Subtitle or data.Rarity or data.Wrap
			if sub then rarityLbl.Text = tostring(sub) end
			if data.Color then
				rarityLbl.TextColor3 = getReadableRarityColor(data.Color)
			elseif data.Rarity and RARITY_COLORS[data.Rarity] then
				rarityLbl.TextColor3 = getReadableRarityColor(RARITY_COLORS[data.Rarity])
			elseif data.Role then
				paint(rarityLbl, { TextColor3 = data.Role })
			end
		end
		if opts.Color then rarityLbl.TextColor3 = getReadableRarityColor(opts.Color) end
		return info
	end

	-- AddInfoCard alias for backward compatibility (maps to flat AddHeaderInfo)
	function panel:AddInfoCard(opts)
		return self:AddHeaderInfo(opts)
	end

	-- Sub-Tabs / Pills Row (e.g. [ Wrap ] [ Charm ] [ Kill effect ])
	function panel:AddPills(pillList, defaultPick, callback)
		pillList = pillList or {}
		local count = #pillList
		local gap = 6
		local container = create("Frame", {
			Name = "PillsRow", Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 3,
			Parent = content,
		}, { list(gap, Enum.FillDirection.Horizontal, { VerticalAlignment = Enum.VerticalAlignment.Center }) })

		local NEUTRAL_SEL = Color3.fromRGB(90, 85, 95)
		local pills = { Value = defaultPick or (pillList[1] or ""), Buttons = {} }
		local pillWidth = count > 0 and UDim2.new(1 / count, -math.floor((count - 1) * gap / count), 1, -4) or UDim2.new(1, 0, 1, -4)

		for _, name in ipairs(pillList) do
			local isSel = (name == pills.Value)
			local b = make("TextButton", {
				Name = "Pill_" .. name, Text = name, FontFace = FONTS.BodySemi, TextSize = 11,
				AutoButtonColor = false, Size = pillWidth, TextXAlignment = Enum.TextXAlignment.Center,
				Parent = container,
			}, {
				BackgroundColor3 = isSel and "PageRaised" or "ChromeBg",
				TextColor3 = isSel and "Text" or "SubText",
			}, {
				corner(4),
				stroke("Rule2", 1, isSel and 0.15 or 0.65),
			})
			local str = b:FindFirstChildOfClass("UIStroke")
			if str and isSel then str.Color = NEUTRAL_SEL end
			pills.Buttons[name] = b

			b.MouseButton1Click:Connect(function()
				playSound("Click")
				pills:Set(name)
			end)
		end

		function pills:Set(name, silent)
			self.Value = name
			local T = CURRENT_THEME
			for pName, b in pairs(self.Buttons) do
				local active = (pName == name)
				b.BackgroundColor3 = active and T.PageRaised or T.ChromeBg
				b.TextColor3 = active and T.Text or T.SubText
				local str = b:FindFirstChildOfClass("UIStroke")
				if str then
					str.Color = active and NEUTRAL_SEL or T.Rule2
					str.Transparency = active and 0.15 or 0.65
				end
			end
			if not silent and callback then callback(name) end
		end
		return pills
	end

	-- Flat Section Sub-Header (e.g. Left: "Wrap", Right: "None")
	function panel:AddSectionHeader(text, actionText, actionCallback)
		local row = create("Frame", {
			Name = "SectionHeader", Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 4,
			Parent = content,
		})
		local tLbl = label({
			Text = tostring(text or "Wrap"), FontFace = FONTS.BodySemi, TextSize = 13,
			Role = "Text", Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(2, 0),
			Parent = row,
		})
		local actionBtn
		if actionText then
			actionBtn = make("TextButton", {
				Text = tostring(actionText), FontFace = FONTS.BodySemi, TextSize = 11,
				AutoButtonColor = false, BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 0),
				Size = UDim2.fromOffset(40, 20), Parent = row,
			}, { TextColor3 = "SubText" })
			actionBtn.MouseEnter:Connect(function() tween(actionBtn, { TextColor3 = CURRENT_THEME.Text }) end)
			actionBtn.MouseLeave:Connect(function() tween(actionBtn, { TextColor3 = CURRENT_THEME.SubText }) end)
			actionBtn.MouseButton1Click:Connect(function()
				playSound("Click")
				if actionCallback then actionCallback() end
			end)
		end
		return {
			Row = row, TitleLabel = tLbl, ActionButton = actionBtn,
			SetAction = function(txt, cb)
				threadEight()
				pcall(function()
					if actionBtn and txt then actionBtn.Text = tostring(txt) end
				end)
				if cb then actionCallback = cb end
			end,
		}
	end

	-- Minimalist Search Input
	function panel:AddSearch(placeholder, callback, order)
		local box = make("Frame", {
			Name = "SearchBox", Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 0.5, BorderSizePixel = 0, LayoutOrder = order or 5,
			Parent = content,
		}, { BackgroundColor3 = "PageRaised" }, { corner(4), stroke("Rule2", 1, 0.4) })

		make("ImageLabel", {
			Image = asset(Library.Icons.Search), BackgroundTransparency = 1,
			Size = UDim2.fromOffset(13, 13), Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5), Parent = box,
		}, { ImageColor3 = "SubText" })

		local tb = create("TextBox", {
			Text = "", PlaceholderText = placeholder or "Search wrap...",
			FontFace = FONTS.Body, TextSize = 11, ClearTextOnFocus = false,
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Size = UDim2.new(1, -32, 1, 0), Position = UDim2.fromOffset(26, 0),
			Parent = box,
		})
		paint(tb, { TextColor3 = "Text", PlaceholderColor3 = "SubText" })

		tb:GetPropertyChangedSignal("Text"):Connect(function()
			if callback then callback(tb.Text) end
		end)

		return {
			Box = box,
			TextBox = tb,
			Get = function() return tb.Text end,
			Set = function(t) tb.Text = t or "" end,
		}
	end

	-- 3-Column Flat Wrap Grid (Textures / Materials)
	function panel:AddWrapGrid(opts)
		opts = opts or {}
		local cols = opts.Columns or 3
		local gap = opts.Gap or 6
		local gridHeight = opts.Height or 240
		local NEUTRAL_SEL = Color3.fromRGB(90, 85, 95)

		local scroll = create("ScrollingFrame", {
			Name = "WrapGrid", Size = UDim2.new(1, 0, 0, gridHeight),
			BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 6,
			ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY,
			Parent = content,
		})
		local gridLayout = create("UIGridLayout", {
			CellSize = UDim2.fromOffset(92, 110),
			CellPadding = UDim2.fromOffset(gap, gap),
			FillDirectionMaxCells = cols,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = scroll,
		})

		local function fit()
			local w = scroll.AbsoluteSize.X
			if w and w > 20 then
				local cellW = math.floor((w - (cols - 1) * gap - 2) / cols)
				if cellW > 30 then
					gridLayout.CellSize = UDim2.fromOffset(cellW, cellW + 28)
				end
			end
		end
		scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		task.defer(fit)
		task.delay(0.1, fit)

		local tiles = {}
		local currentPick = opts.Default or ""

		local gridObj = {
			Scroll = scroll,
			Value = currentPick,
			OnHover = opts.OnHover,
			OnClick = opts.OnClick,
			Callback = opts.Callback,
		}

		local gridGen = 0
		function gridObj:SetItems(items)
			threadEight()
			items = items or {}
			gridGen = gridGen + 1
			local myGen = gridGen

			for _, t in pairs(tiles) do
				if t.Item and type(t.Item.Destroy) == "function" then
					pcall(t.Item.Destroy, t.Item)
				end
				if t.Button then pcall(function() t.Button:Destroy() end) end
			end
			table.clear(tiles)
			for _, child in ipairs(scroll:GetChildren()) do
				if child:IsA("GuiButton") then
					pcall(function() child:Destroy() end)
				end
			end

			for i, item in ipairs(items) do
				local id = tostring(item.Id or item.Name or ("wrap" .. i))
				local name = tostring(item.Name or id)
				local isSel = (id == currentPick)

				local rarCol = getReadableRarityColor(item.RarityColor or (item.Rarity and RARITY_COLORS[item.Rarity]))
				local isNone = (id == "None" or id == "__none")

				local b = make("TextButton", {
					Name = "Tile_" .. id, Text = "", AutoButtonColor = false,
					BackgroundTransparency = isSel and 0.25 or 0.5, BorderSizePixel = 0,
					LayoutOrder = i, Parent = scroll,
				}, { BackgroundColor3 = "PageRaised" }, { corner(6) })

				local ring = stroke("Rule2", 1, isSel and 0.15 or ((rarCol and not isNone) and 0.45 or 0.65))
				if isSel then
					ring.Color = NEUTRAL_SEL
				elseif rarCol and not isNone then
					ring.Color = rarCol
				end
				ring.Parent = b

				local prevContainer = make("Frame", {
					Name = "PreviewContainer",
					Size = UDim2.new(1, -6, 1, -29),
					Position = UDim2.fromOffset(3, 3),
					BorderSizePixel = 0,
					ClipsDescendants = true,
					Parent = b,
				}, {
					BackgroundColor3 = "PageBg",
				}, { corner(4) })

				if rarCol and not isNone then
					create("Frame", {
						Name = "RarityBar", Size = UDim2.new(1, 0, 0, 2),
						Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0,
						BackgroundColor3 = rarCol, BackgroundTransparency = 0.2,
						Parent = b,
					})
				end

				local hasImg = (item.Image and item.Image ~= "")
				local previewInstance = create("ImageLabel", {
					Name = "PreviewImage",
					BackgroundColor3 = CURRENT_THEME.PageBg,
					BackgroundTransparency = hasImg and 1 or 0.8,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1, 1),
					Image = hasImg and item.Image or (isNone and "" or "rbxassetid://112715941288555"),
					ImageTransparency = (not hasImg) and 0.45 or 0,
					ScaleType = Enum.ScaleType.Crop,
					Parent = prevContainer,
				})

				if typeof(item.Frame) == "Instance" then
					local f = item.Frame
					f.AnchorPoint = Vector2.new(0.5, 0.5)
					f.Position = UDim2.fromScale(0.5, 0.5)
					f.Size = UDim2.fromScale(1, 1)
					f.BackgroundTransparency = 1
					f.Parent = prevContainer
					previewInstance.Visible = false
				end

				local nm = label({
					Text = name, FontFace = FONTS.BodySemi, TextSize = 9.5,
					Role = isSel and "Text" or "SubText", TextTruncate = TRUNC,
					TextXAlignment = CENTER, Size = UDim2.new(1, -4, 0, 13),
					Position = UDim2.new(0, 2, 1, -24), Parent = b,
				})

				local rarityText = (item.Rarity and item.Rarity ~= "None" and item.Rarity ~= "Default") and tostring(item.Rarity) or ""
				local rLbl = nil
				if rarityText ~= "" then
					rLbl = create("TextLabel", {
						Name = "RarityLabel", Text = rarityText, FontFace = FONTS.Body, TextSize = 8.5,
						TextColor3 = rarCol or CURRENT_THEME.SubText, BackgroundTransparency = 1, TextTruncate = TRUNC,
						TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -4, 0, 11),
						Position = UDim2.new(0, 2, 1, -12), Parent = b,
					})
				end

				if item.Animated == true then
					create("TextLabel", {
						Name = "AnimBadge", Text = "✦", FontFace = FONTS.Header, TextSize = 10,
						TextColor3 = Color3.fromRGB(200, 220, 255), BackgroundTransparency = 1,
						Size = UDim2.fromOffset(13, 13), Position = UDim2.new(1, -14, 0, 2),
						ZIndex = 4, Parent = b,
					})
				end

				tiles[id] = { Button = b, PreviewContainer = prevContainer, Ring = ring, Label = nm, Item = item }

				b.MouseEnter:Connect(function()
					local active = (id == currentPick)
					tween(b, { BackgroundTransparency = active and 0.2 or 0.35 })
					if ring and not active then
						tween(ring, { Transparency = 0.15, Color = (rarCol and not isNone) and rarCol or NEUTRAL_SEL })
					end
					if gridObj.OnHover then gridObj.OnHover(id, item, true) end
				end)
				b.MouseLeave:Connect(function()
					local active = (id == currentPick)
					tween(b, { BackgroundTransparency = active and 0.25 or 0.5 })
					if ring and not active then
						tween(ring, { Transparency = (rarCol and not isNone) and 0.45 or 0.65, Color = (rarCol and not isNone) and rarCol or CURRENT_THEME.Rule2 })
					end
					if gridObj.OnHover then gridObj.OnHover(id, item, false) end
				end)
				b.MouseButton1Click:Connect(function()
					playSound("Click")
					gridObj:Set(id)
				end)
			end

			if #items > 0 then
				task.spawn(function()
					for i, item in ipairs(items) do
						if gridGen ~= myGen then return end
						if type(item.CreatePreview) == "function" then
							local id = tostring(item.Id or item.Name or ("wrap" .. i))
							local t = tiles[id]
							if t and t.PreviewContainer and t.PreviewContainer.Parent then
								local ok, res = pcall(item.CreatePreview, t.PreviewContainer)
								if ok and typeof(res) == "Instance" then
									res.AnchorPoint = Vector2.new(0.5, 0.5)
									res.Position = UDim2.fromScale(0.5, 0.5)
									res.Size = UDim2.fromScale(1, 1)
									if res.Parent ~= t.PreviewContainer then res.Parent = t.PreviewContainer end
									local img = t.PreviewContainer:FindFirstChild("PreviewImage")
									if img then img.Visible = false end
								end
							end
						end
						if i % 6 == 0 then
							task.wait()
						end
					end
				end)
			end
		end

		function gridObj:Set(id, silent)
			currentPick = tostring(id or "")
			self.Value = currentPick
			local T = CURRENT_THEME
			for tId, t in pairs(tiles) do
				local active = (tId == currentPick)
				local tRar = t.Item and (t.Item.RarityColor or (t.Item.Rarity and RARITY_COLORS[t.Item.Rarity]))
				local tIsNone = (tId == "None" or tId == "__none")
				if t.Ring then
					t.Ring.Color = active and NEUTRAL_SEL or ((tRar and not tIsNone) and tRar or T.Rule2)
					t.Ring.Transparency = active and 0.15 or ((tRar and not tIsNone) and 0.45 or 0.65)
				end
				if t.Button then
					t.Button.BackgroundTransparency = active and 0.25 or 0.5
				end
				if t.Label then
					t.Label.TextColor3 = active and T.Text or T.SubText
					t.Label.FontFace = active and FONTS.BodySemi or FONTS.Body
				end
			end
			if not silent and self.Callback then self.Callback(currentPick) end
			if not silent and self.OnClick then self.OnClick(currentPick) end
		end

		function gridObj:Get() return currentPick end

		if opts.Items then gridObj:SetItems(opts.Items) end
		return gridObj
	end

	-- Simple Side Button
	function panel:AddButton(btnOpts)
		btnOpts = btnOpts or {}
		local b = make("TextButton", {
			Name = "SideButton", Size = UDim2.new(1, 0, 0, 32),
			AutoButtonColor = false, BackgroundTransparency = 0.5,
			LayoutOrder = btnOpts.Order or 0,
			Text = btnOpts.Name or "Button", FontFace = FONTS.BodySemi, TextSize = 12,
			Parent = content,
		}, { BackgroundColor3 = "PageRaised", TextColor3 = "Text" }, { corner(6), stroke("Rule2", 1, 0.4) })
		b.MouseEnter:Connect(function() tween(b, { BackgroundTransparency = 0.25 }) end)
		b.MouseLeave:Connect(function() tween(b, { BackgroundTransparency = 0.5 }) end)
		b.MouseButton1Click:Connect(function()
			playSound("Click")
			if btnOpts.Callback then btnOpts.Callback() end
		end)
		return b
	end

	-- Simple Side Toggle
	function panel:AddToggle(toggleOpts)
		toggleOpts = toggleOpts or {}
		local el = { Type = "Toggle", Value = toggleOpts.Default or false, Callback = toggleOpts.Callback }
		local h = toggleOpts.Height or 28
		local f = make("Frame", {
			Name = "SideToggle", Size = UDim2.new(1, 0, 0, h),
			BackgroundTransparency = 0.5, BorderSizePixel = 0,
			Parent = content,
		}, { BackgroundColor3 = "PageRaised" }, { corner(6), stroke("Rule2", 1, 0.4) })
		el.Frame = f

		local hit = create("TextButton", {
			Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = f,
		})

		label({
			Text = toggleOpts.Name or "Toggle",
			FontFace = FONTS.BodySemi,
			TextSize = 11,
			TextTruncate = TRUNC,
			Size = UDim2.new(1, -50, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			Parent = f,
		})
		local titleLabel = f:FindFirstChildOfClass("TextLabel")

		local _, show = capsule(f, UDim2.new(1, -8, 0.5, 0))

		-- Same animated caption as Tab:AddToggle:SetName.
		function el:SetName(text)
			toggleOpts.Name = text
			text = tostring(text)
			local token = (el._nameToken or 0) + 1
			el._nameToken = token
			task.spawn(function()
				local same = false
				pcall(function() same = (titleLabel and titleLabel.Text == text) end)
				if same then return end
				local tw = titleLabel and tween(titleLabel, { TextTransparency = 1 }, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
				if tw then pcall(function() tw.Completed:Wait() end) else task.wait(0.1) end
				if el._nameToken ~= token then return end
				pcall(function() titleLabel.Text = text end)
				if titleLabel then tween(titleLabel, { TextTransparency = 0 }, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)) end
			end)
		end

		function el:Set(v, silent)
			self.Value = v
			show(v, true)
			if not silent then
				playSound("Toggle")
				if self.Callback then self.Callback(v) end
			end
		end

		hit.MouseButton1Click:Connect(function()
			el:Set(not el.Value)
		end)

		show(el.Value, false)
		return el
	end

	-- Member/row list: color dot + title + sub + up to 3 small action buttons.
	-- The menu diffs rows by id (see party side panel): Set refreshes in
	-- place, Destroy removes. Returns nil when content is gone.
	function panel:AddListRow(rowOpts)
		rowOpts = rowOpts or {}
		local host_ = rowOpts.Parent or content
		local actions = {}
		if type(rowOpts.Actions) == "table" then actions = rowOpts.Actions end
		while #actions > 3 do table.remove(actions) end
		local h = math.max(rowOpts.Height or 46, 12 + math.max(#actions, 1) * 22)
		local row = make("Frame", {
			Name = "SideRow", Size = UDim2.new(1, 0, 0, h),
			BackgroundTransparency = 0.5, BorderSizePixel = 0,
			Parent = host_,
		}, { BackgroundColor3 = "PageRaised" }, { corner(6), stroke("Rule2", 1, 0.4) })
		if not row or not row.Parent then return nil end
		local dot = make("Frame", {
			Name = "Dot", Size = UDim2.fromOffset(8, 8),
			Position = UDim2.new(0, 10, 0, 10), BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(140, 140, 150),
			Parent = row,
		}, nil, { corner(4) })
		local titleLbl = label({
			Text = tostring(rowOpts.Title or ""), FontFace = FONTS.BodySemi, TextSize = 12,
			Role = "Text", TextTruncate = TRUNC,
			Size = UDim2.new(1, -96, 0, 17), Position = UDim2.fromOffset(26, 5),
			Parent = row,
		})
		local subLbl = label({
			Text = tostring(rowOpts.Sub or ""), FontFace = FONTS.Body, TextSize = 10,
			Role = "SubText", TextTruncate = TRUNC,
			Size = UDim2.new(1, -96, 0, 14), Position = UDim2.fromOffset(26, 23),
			Parent = row,
		})
		local btnCol = create("Frame", {
			Name = "Actions", BackgroundTransparency = 1, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.new(0, 64, 1, -12),
			Parent = row,
		}, { list(4) })
		local api = { Row = row }
		local function paintDot(color)
			local c = color
			if type(c) == "string" then c = fromHex(c) end
			if typeof(c) == "Color3" then
				pcall(function() dot.BackgroundColor3 = c end)
			end
		end
		local function buildButtons(list)
			for _, c in ipairs(btnCol:GetChildren()) do
				if c:IsA("TextButton") then pcall(function() c:Destroy() end) end
			end
			for _, a in ipairs(list) do
				local b = make("TextButton", {
					Text = tostring(a.Text or "..."), FontFace = FONTS.BodySemi, TextSize = 10,
				AutoButtonColor = false, BackgroundTransparency = 0.5,
				Size = UDim2.fromOffset(64, 20),
				Parent = btnCol,
				}, { BackgroundColor3 = (a.Kind == "danger" and "Danger" or (a.Kind == "primary" and "Accent" or "ChromeBg")), TextColor3 = (a.Kind == "danger" or a.Kind == "primary") and "Text" or "SubText" }, { corner(4) })
				b.MouseEnter:Connect(function() tween(b, { BackgroundTransparency = 0.25 }) end)
				b.MouseLeave:Connect(function() tween(b, { BackgroundTransparency = 0.5 }) end)
				local cb = a.Callback
				b.MouseButton1Click:Connect(function()
					playSound("Click")
					if cb then cb() end
				end)
			end
		end
		function api:Set(data)
			data = data or {}
			if not row.Parent then return end
			if data.Title then pcall(function() titleLbl.Text = tostring(data.Title) end) end
			if data.Sub then pcall(function() subLbl.Text = tostring(data.Sub) end) end
			if data.Color then paintDot(data.Color) end
			if data.Actions then buildButtons(data.Actions) end
		end
		function api:Destroy()
			pcall(function() row:Destroy() end)
		end
		paintDot(rowOpts.Color)
		buildButtons(actions)
		return api
	end
	function panel:AddRowGroup(order)
		local g = make("Frame", {
			Name = "SideRows", Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1, BorderSizePixel = 0, AutomaticSize = AY,
		LayoutOrder = order or 0, Parent = content,
		}, nil, { list(6) })
		return g
	end
	function panel:AddSection(text, order)
		local sec = make("Frame", {
			Name = "SideSection", Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = order or 0,
			BackgroundTransparency = 1, Parent = content,
		})
		label({
			Text = string.upper(tostring(text or "")), FontFace = FONTS.Mono, TextSize = 10,
			Role = "ChromeSub", TextTruncate = TRUNC,
			Size = UDim2.new(1, 0, 1, 0), Position = UDim2.fromOffset(4, 0),
			Parent = sec,
		})
		return sec
	end

	function panel:Destroy()
		for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
		table.clear(self._connections)
		if frame then frame:Destroy() end
	end

	-- Register with window for theme changes and visibility syncing
	self._sidePanels = self._sidePanels or {}
	table.insert(self._sidePanels, panel)

	if opts.Default then panel:Open() end
	return panel
end

-- Two widgets share each of these names. The arguments say which one is meant:
--   AddChips{Items = ...}             read-only status chips (Glider)
--   AddChips{Options = ...}           a row of choices, one picked (Tab:AddChoiceChips)
--   AddSidePanel("Title", opts)       floating inspector with a 3D viewport (Library:CreateSidePanel)
--   AddSidePanel{ShowFlag/Manual=..}  a page docked to the window's right edge (Library:AddPanel)
do
	local statusChips = Tab.AddChips
	function Tab:AddChips(opts)
		opts = opts or {}
		if opts.Items == nil and opts.Options ~= nil then return self:AddChoiceChips(opts) end
		return statusChips(self, opts)
	end
end
function Library:AddSidePanel(a, b)
	if type(a) == "table" and (a.ShowFlag ~= nil or a.Manual ~= nil) then return self:AddPanel(a) end
	return self:CreateSidePanel(a, b)
end

function Library:SaveWindowSize()
	if self.Main then
		Storage.saveWindowSize(self.Main.Size.X.Offset, self.Main.Size.Y.Offset)
	end
end

function Library:ResetWindowSize()
	Storage.saveWindowSize(880, 560)
	if self.Main then
		self.Main.Size = UDim2.fromOffset(880, 560)
	end
end

return Library
