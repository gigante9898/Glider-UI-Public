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
	  - File-backed JSON configs with auto-save and autoload
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

local LocalPlayer = Players.LocalPlayer
local IS_MOBILE   = UIS.TouchEnabled and not UIS.KeyboardEnabled

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
local FONTS = {
	Brand       = fontFace("Fondamento"),
	Heading     = fontFace("Merriweather"),
	HeadingBold = fontFace("Merriweather", Enum.FontWeight.Bold),
	Italic      = fontFace("Merriweather", Enum.FontWeight.Regular, Enum.FontStyle.Italic),
	Body        = fontFace("JosefinSans"),
	BodySemi    = fontFace("JosefinSans", Enum.FontWeight.SemiBold),
	Mono        = fontFace("RobotoMono"),
	Symbol      = Font.fromEnum(Enum.Font.GothamBold),
}

-- ---------------------------------------------------------------------------
-- SOUND FX SYSTEM
-- ---------------------------------------------------------------------------
local SOUNDS = {
	Click   = "rbxassetid://6895079853",
	Toggle  = "rbxassetid://6895079853",
	Slide   = "rbxassetid://9114223175",
	Notify  = "rbxassetid://6895079853",
	Popup   = "rbxassetid://9114223175",
}

local SoundEnabled = true
local function playSound(soundKey)
	if not SoundEnabled then return end
	local soundId = SOUNDS[soundKey] or soundKey
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
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(CONNS, c)
	return c
end

local function tween(obj, props, info)
	local t = TweenService:Create(obj, info or FAST, props)
	t:Play()
	return t
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

local function toKeyCode(name)
	local ok, key = pcall(function() return Enum.KeyCode[name] end)
	return ok and key or nil
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

local Storage = {_mem = {}, _global = {}, Folder = "Glider_Configs"}
local function safeName(name) return (tostring(name):gsub("[^%w%-_%. ]", "")) end
local function configPath(name) return Storage.Folder .. "/configs/" .. safeName(name) .. ".json" end

function Storage.init(folder)
	Storage.Folder = folder or Storage.Folder
	if not HAS_FS then return end
	pcall(function()
		if not isfolder(Storage.Folder) then makefolder(Storage.Folder) end
		if not isfolder(Storage.Folder .. "/configs") then makefolder(Storage.Folder .. "/configs") end
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
function Storage.save(name, tbl)
	local raw = HttpService:JSONEncode(tbl)
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
			local p = Storage.Folder .. "/autoload.txt"
			if name then writefile(p, name) elseif isfile(p) then delfile(p) end
		end)
	else
		Storage._autoload = name
	end
end

-- Global preferences (menu key, theme) live outside any config so they persist
-- across games and config loads.
local GLOBAL_DIR = "Glider_Global"
local function writeGlobal(file, value)
	if HAS_FS then
		pcall(function()
			if not isfolder(GLOBAL_DIR) then makefolder(GLOBAL_DIR) end
			writefile(GLOBAL_DIR .. "/" .. file, value)
		end)
	else
		Storage._global[file] = value
	end
end
local function readGlobal(file)
	if HAS_FS then
		local ok, n = pcall(function() local p = GLOBAL_DIR .. "/" .. file; return isfile(p) and readfile(p) or nil end)
		if ok and n and n ~= "" then return n end
		return nil
	end
	return Storage._global[file]
end
function Storage.saveMenuKey(name) writeGlobal("menukey.txt", name) end
function Storage.loadMenuKey() return readGlobal("menukey.txt") end
function Storage.saveTheme(name) writeGlobal("theme.txt", name) end
function Storage.loadTheme() return readGlobal("theme.txt") end
function Storage.saveHideName(on) writeGlobal("hidename.txt", on and "1" or "0") end
function Storage.loadHideName()
	local v = readGlobal("hidename.txt")
	if v == nil then return nil end
	return v == "1"
end

-- Settings flags that are global preferences, not part of any config: configs never
-- save, load or reset them, and Unload leaves them alone.
local GLOBAL_FLAGS = {MenuKey = true, HideUsername = true}

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
	IsMobile = IS_MOBILE,
	Sounds = SOUNDS,
	SoundEnabled = true,
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
		PlumeVane  = 109028262244405,
		PlumeShaft = 124588188115353,
		Grain      = 79377062140589,
	},
}
Library.__index = Library
local Tab = {}
Tab.__index = Tab

local PAD = 14 -- inner left/right padding of a row

local function asset(id) return type(id) == "number" and ("rbxassetid://" .. id) or id end

-- Draws the window's mark into holder: the caller's Logo if set (tinted unless LogoTint = false),
-- else the Glider skate (deck + wheels, vectorial), else a diamond. ctx "Chrome" (rail, overlays) or "Page".
local function fillMark(holder, ctx, win)
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local accentRole = ctx == "Page" and "Accent" or "ChromeAccent"
	local textRole = ctx == "Page" and "Text" or "ChromeText"
	if win and win.Logo then
		local img = create("ImageLabel", {
			Name = "Logo", Image = asset(win.Logo), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1), Parent = holder,
		})
		if win.LogoTint ~= false then paint(img, {ImageColor3 = accentRole}) end
	else
		local wing = make("Frame", {
			Name = "GliderWing",
			Size = UDim2.new(0.12, 0, 0.90, 0),
			Position = UDim2.new(0.60, 0, 0.43, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = -35,
			BorderSizePixel = 0,
			Parent = holder,
		}, {BackgroundColor3 = accentRole}, {corner(3)})
		local tail = make("Frame", {
			Name = "GliderTail",
			Size = UDim2.new(0.09, 0, 0.40, 0),
			Position = UDim2.new(0.25, 0, 0.67, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = -35,
			BorderSizePixel = 0,
			Parent = holder,
		}, {BackgroundColor3 = accentRole}, {corner(2)})
		local body = make("Frame", {
			Name = "GliderFuselage",
			Size = UDim2.new(0.86, 0, 0.12, 0),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = -35,
			BorderSizePixel = 0,
			Parent = holder,
		}, {BackgroundColor3 = textRole}, {corner(99)})
		restyle(holder, function()
			if body.Parent and wing.Parent and tail.Parent then
				body.BackgroundColor3 = CURRENT_THEME[textRole]
				wing.BackgroundColor3 = CURRENT_THEME[accentRole]
				tail.BackgroundColor3 = CURRENT_THEME[accentRole]
			end
		end)
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
-- WINDOW CREATION
-- ---------------------------------------------------------------------------
local RAIL_W, BRAND_H = 176, 84

function Library.new(opts)
	opts = opts or {}
	local saved = Storage.loadTheme()
	local themeName = (saved and THEMES[saved] and saved) or (opts.Theme and THEMES[opts.Theme] and opts.Theme) or "Sakura"
	CURRENT_THEME = THEMES[themeName]
	Library.Theme = CURRENT_THEME

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
		_marks = {},
		_unloadCallbacks = {},
		_themeSubscribers = {},
		_tabCount = 0,
		_tabNum = 0,
		_pinnedCount = 0,
		_hudEnabled = true,
	}, Library)

	if opts.MenuKey then Library.MenuKey = opts.MenuKey end
	do
		local savedKey = Storage.loadMenuKey()
		if savedKey then
			local ok, kc = pcall(function() return Enum.KeyCode[savedKey] end)
			if ok and typeof(kc) == "EnumItem" then Library.MenuKey = kc end
		end
	end

	self.AutoSave = opts.AutoSave == true
	local hideSaved = Storage.loadHideName()
	if hideSaved ~= nil then self.HideUsername = hideSaved else self.HideUsername = opts.HideUsername == true end
	Library._window = self
	Storage.init(opts.Folder)

	-- Root ScreenGui
	self.Gui = create("ScreenGui", {
		Name = opts.Name or "UIAPI_Suite",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	self.Gui.Parent = guiParent(self.Gui)

	-- Main Window Frame (never a CanvasGroup: it renders the whole menu darker)
	self.Main = make("Frame", {
		Name = "MainWindow",
		Size = UDim2.fromOffset(780, 550),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = self.Gui,
	}, {BackgroundColor3 = "PageBg"}, {corner(6), stroke("Edge")})
	self.Scale = create("UIScale", {Scale = 1, Parent = self.Main})
	grain(self.Main, "Text")

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

	local brand = create("Frame", {Name = "Brand", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, BRAND_H - 12), ZIndex = 2, Parent = rail})
	plume(brand, 26, "Chrome", {Position = UDim2.fromOffset(16, 17)}, self)
	self.BrandLabel = label({
		Text = self.Brand, FontFace = FONTS.Brand, TextSize = 24, Role = "ChromeText", TextTruncate = TRUNC,
		Size = UDim2.new(1, -56, 0, 28), Position = UDim2.fromOffset(46, 16), Parent = brand,
	})
	make("Frame", {Size = UDim2.fromOffset(14, 1), Position = UDim2.fromOffset(20, 58), BorderSizePixel = 0, Parent = brand},
		{BackgroundColor3 = "ChromeAccent"})
	self.GameLabel = label({
		Text = track(self.Title), FontFace = FONTS.BodySemi, TextSize = 10, Role = "ChromeSub", TextTruncate = TRUNC,
		Size = UDim2.new(1, -52, 0, 12), Position = UDim2.fromOffset(40, 52), Parent = brand,
	})
	self.TitleLabel = self.GameLabel

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
		Position = UDim2.fromOffset(0, BRAND_H), Size = UDim2.new(1, -1, 1, -BRAND_H - 34),
		ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, Parent = rail,
	}, {list(2)})
	connect(self.TabList:GetPropertyChangedSignal("CanvasPosition"), function() self:_syncMarker(false) end)

	self.Foot = create("Frame", {
		Name = "Foot", BackgroundTransparency = 1, ZIndex = 2, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, -1, 0, 34), Parent = rail,
	}, {list(2, nil, {VerticalAlignment = Enum.VerticalAlignment.Bottom})})
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
		self.KeyChip = keycap(Library.MenuKey.Name, tools, "SubText")
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
				if i.UserInputState == Enum.UserInputState.End then resizing = false end
			end)
		end
	end)
	connect(UIS.InputChanged, function(i)
		if resizing and isMove(i) then
			local d = i.Position - rStart
			local w = math.clamp(rSize.X.Offset + d.X, 500, 1250)
			local h = math.clamp(rSize.Y.Offset + d.Y, 420, 920)
			self.Main.Size = UDim2.fromOffset(w, h)
			self.Main.Position = UDim2.new(
				rPos.X.Scale, rPos.X.Offset + (w - rSize.X.Offset) / 2,
				rPos.Y.Scale, rPos.Y.Offset + (h - rSize.Y.Offset) / 2
			)
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

	if IS_MOBILE then self:_buildMobileIcon() end
	self:_bindInput()
	self.Main.Visible = true -- opens through the book animation rather than SetVisible's pop
	self:_playIntro()

	-- Pinned Tabs (Settings & Config)
	if opts.Settings ~= false then self:_buildSettingsTab(opts.SettingsName, opts.SettingsIcon) end
	if opts.Config ~= false then self:AddConfigTab(opts.ConfigName, opts.ConfigIcon) end
	self:_refreshConfigStatus()

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

-- Sizes the tab list around the pinned tabs at the bottom of the rail.
function Library:_layoutRail()
	local n = self._pinnedCount
	local items = 1 + (n > 0 and (2 + n) or 0)
	local h = 34 + (n > 0 and (1 + 4 + n * 34) or 0) + (items - 1) * 2
	self.Foot.Size = UDim2.new(1, -1, 0, h)
	self.TabList.Size = UDim2.new(1, -1, 1, -BRAND_H - h)
	self.FootRule.Visible = n > 0
	self.FootGap.Visible = n > 0
end

function Library:_refreshConfigStatus()
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
			Text = item.Bind.Key.Name, FontFace = FONTS.Mono, TextSize = 11, Role = "ChromeAccent", TextXAlignment = RIGHT,
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
-- STARTUP: the window starts folded, as a tall panel in the middle of the screen
-- showing the mark while the brand writes itself in. Then it unfolds like paper:
-- the left flap swings open toward the left to reveal the tabs, and the right side
-- widens. The middle panel never moves, so the open window ends up centred.
-- ---------------------------------------------------------------------------
function Library:_playIntro()
	local main, page, rail = self.Main, self.PageArea, self.TabRail
	local finalSize = main.Size
	local fullW, fullH = finalSize.X.Offset, finalSize.Y.Offset
	local mid = math.max(fullW - 2 * RAIL_W, 200) -- the folded panel; the right side grows by the rest
	local grow = fullW - RAIL_W - mid
	local pos = main.Position

	-- Lays the window out for flap progress a (0 folded, 1 flat) and right-side progress b.
	-- The hinge sits at the folded panel's left edge, which stays fixed on screen.
	local cover, flap, crease
	local function layoutAt(a, b)
		local h = RAIL_W * a
		main.Position = UDim2.new(pos.X.Scale, pos.X.Offset - mid / 2 - h, pos.Y.Scale, pos.Y.Offset)
		main.Size = UDim2.fromOffset(h + mid + grow * b, fullH)
		rail.Position = UDim2.fromOffset(h - RAIL_W, 0)
		page.Position = UDim2.fromOffset(h, 0)
		if cover then cover.Position = UDim2.fromOffset(h, 0) end
		if flap then flap.Size = UDim2.new(0, h, 1, 0) end
		if crease then crease.Position = UDim2.fromOffset(h, 0) end
	end

	main.AnchorPoint = Vector2.new(0, 0.5)
	page.Size = UDim2.new(0, fullW - RAIL_W, 1, 0) -- final width up front: content is revealed, never squashed

	cover = make("Frame", {
		Name = "Intro", Size = UDim2.new(0, mid, 1, 0), BorderSizePixel = 0, ZIndex = 40, Parent = main,
	}, {BackgroundColor3 = "ChromeBg"}, {corner(6)})
	layoutAt(0, 0)

	local mark = plume(cover, 60, "Chrome", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -46)}, self)
	local markScale = create("UIScale", {Scale = 0.9, Parent = mark})
	local parts = {} -- {instance, transparency property} for everything on the cover
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
		Text = self.Brand, FontFace = FONTS.Brand, TextSize = 40, TextScaled = true, Role = "ChromeText",
		TextXAlignment = CENTER, MaxVisibleGraphemes = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 16), Size = UDim2.new(1, -40, 0, 46), Parent = cover,
	}, {create("UITextSizeConstraint", {MaxTextSize = 40})})
	local dash = make("Frame", {
		Size = UDim2.fromOffset(18, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 50),
		BackgroundTransparency = 1, BorderSizePixel = 0, Parent = cover,
	}, {BackgroundColor3 = "ChromeAccent"})
	local caption = label({
		Text = track(self.Title), FontFace = FONTS.BodySemi, TextSize = 10, Role = "ChromeSub", TextXAlignment = CENTER,
		TextTruncate = TRUNC, TextTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 64), Size = UDim2.new(1, -40, 0, 12), Parent = cover,
	})

	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({word, caption, self.PageTitle}) end)
	end)

	for _, p in ipairs(parts) do tween(p[1], {[p[2]] = 0}, MED) end
	tween(markScale, {Scale = 1}, SLIDE)

	task.spawn(function()
		local function alive() return cover.Parent ~= nil and not self.Unloaded end

		-- the brand writes itself in under the mark
		task.wait(0.3)
		local n = utf8.len(self.Brand) or #self.Brand
		for i = 1, n do
			if not alive() then return end
			word.MaxVisibleGraphemes = i
			task.wait(0.055)
		end
		word.MaxVisibleGraphemes = -1
		tween(dash, {BackgroundTransparency = 0}, MED)
		tween(caption, {TextTransparency = 0}, MED)
		task.wait(0.55)
		if not alive() then return end

		-- The left flap: a sheet in the rail's colour, shaded while it swings flat.
		flap = make("Frame", {
			Name = "Flap", Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0, ZIndex = 35, Parent = main,
		}, {BackgroundColor3 = "ChromeBg"}, {corner(6)})
		local flapEdge = make("Frame", { -- squares the flap's hinge side
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 6, 1, 0),
			BorderSizePixel = 0, Parent = flap,
		}, {BackgroundColor3 = "ChromeBg"})
		local shade = create("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
			BorderSizePixel = 0, ZIndex = 2, Parent = flap,
		}, {create("UIGradient", {Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 0.6),
		})})})
		crease = create("Frame", {
			Name = "Crease", Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 36, Parent = main,
		})

		local lift = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tween(cover, {BackgroundTransparency = 1}, lift)
		for _, p in ipairs(parts) do tween(p[1], {[p[2]] = 1}, lift) end
		tween(word, {TextTransparency = 1}, lift)
		tween(caption, {TextTransparency = 1}, lift)
		tween(dash, {BackgroundTransparency = 1}, lift)

		local function ease(x, style, dir)
			return TweenService:GetValue(math.clamp(x, 0, 1), style, dir)
		end
		local FOLD, WIDEN, WIDEN_AT = 0.6, 0.65, 0.15
		local t, tabsOpened, flapLifted = 0, false, false
		while t < WIDEN_AT + WIDEN do
			t += RunService.RenderStepped:Wait() or (1 / 60)
			if self.Unloaded or not main.Parent then return end
			local a = ease(t / FOLD, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			local b = ease((t - WIDEN_AT) / WIDEN, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
			layoutAt(a, b)
			shade.BackgroundTransparency = 0.35 + 0.65 * a
			if not tabsOpened and t >= FOLD - 0.15 then
				tabsOpened = true
				self:_openTabs()
			end
			if not flapLifted and t >= FOLD then
				flapLifted = true -- flat now: lift the sheet off the real rail underneath
				tween(flap, {BackgroundTransparency = 1}, lift)
				tween(flapEdge, {BackgroundTransparency = 1}, lift)
				tween(crease, {BackgroundTransparency = 1}, lift)
			end
		end

		-- hand back to the normal layout
		main.AnchorPoint = Vector2.new(0.5, 0.5)
		main.Position = pos
		main.Size = finalSize
		rail.Position = UDim2.fromOffset(0, 0)
		page.Position = UDim2.fromOffset(RAIL_W, 0)
		page.Size = UDim2.new(1, -RAIL_W, 1, 0)
		cover:Destroy()
		task.wait(0.36)
		flap:Destroy()
		crease:Destroy()
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
}

function Library:OpenSearchModal()
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
			if q == "" or string.find(string.lower(name), q, 1, true) or string.find(string.lower(flag), q, 1, true) then
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
-- SETTINGS TAB & CONTROLS
-- ---------------------------------------------------------------------------
function Library:_buildSettingsTab(name, icon)
	local tab = self:AddTab(name or "Settings", icon or Library.Icons.Settings, true)

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

	tab:AddSection("Menu")
	tab:AddKeybind({
		Name = "Open / Close Menu",
		Flag = "MenuKey",
		Default = Library.MenuKey,
		Callback = function(key)
			if not key then return end
			self:SetMenuKey(key)
			self:Notify({Title = "Keybind", Body = "Menu key set to " .. key.Name, Type = "Success"})
		end,
	})
	tab:AddToggle({
		Name = "Sound Effects",
		Flag = "SoundFX",
		Default = true,
		Callback = function(v) SoundEnabled = v end,
	})
	tab:AddToggle({
		Name = "Watermark",
		Flag = "ShowWatermark",
		Default = true,
		Callback = function(v)
			if self.WatermarkFrame then self.WatermarkFrame.Visible = v end
		end,
	})
	tab:AddToggle({
		Name = "Hide Username",
		Flag = "HideUsername",
		Default = self.HideUsername,
		Callback = function(v)
			self:SetHideUsername(v)
			if not self.Unloaded then Storage.saveHideName(v) end
		end,
	})
	tab:AddToggle({
		Name = "Keybinds HUD",
		Flag = "ShowKeybindHUD",
		Default = true,
		Callback = function(v)
			self._hudEnabled = v
			self:UpdateKeybindHUD()
		end,
	})
	local unloadRow = tab:AddButton({
		Name = "Unload " .. self.Brand,
		Danger = true,
		Callback = function() self:Unload() end,
	})
	self._unloadLabel = unloadRow:FindFirstChild("Label")
	return tab
end

-- ---------------------------------------------------------------------------
-- OPEN / CLOSE & VISIBILITY
-- ---------------------------------------------------------------------------
function Library:SetMenuKey(key)
	Library.MenuKey = key
	if self.KeyChip then self.KeyChip.Text = key.Name end
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

function Library:SetVisible(v)
	if v == self.Visible and self.Main.Visible == v then return end
	self.Visible = v
	if v then
		self.Main.Visible = true
		self.Scale.Scale = 0.96
		tween(self.Scale, {Scale = 1}, SLIDE)
		if self.MobileIcon then self.MobileIcon.Visible = false end
	else
		if self.Popup then self.Popup:Destroy(); self.Popup = nil end
		self:CloseSearchModal(true)
		tween(self.Scale, {Scale = 0.96}, FAST).Completed:Connect(function()
			if not self.Visible then self.Main.Visible = false; self.Scale.Scale = 1 end
		end)
		if IS_MOBILE and self.MobileIcon then
			self.MobileIcon.Visible = true
			self.MobileScale.Scale = 0
			tween(self.MobileScale, {Scale = 1}, SLIDE)
		else
			self:Notify({Title = "Menu Hidden", Body = "Press " .. Library.MenuKey.Name .. " to open the menu", Type = "Info", Duration = 2.5})
		end
	end
end

-- ---------------------------------------------------------------------------
-- UNLOAD & CLEANUP
-- ---------------------------------------------------------------------------
function Library:OnUnload(fn)
	table.insert(self._unloadCallbacks, fn)
end

function Library:Unload(instant)
	if self.Unloaded then return end
	self.Unloaded = true
	self._applying = true
	for _, el in pairs(Library.Elements) do
		if el.Type == "Toggle" and el.Value and not GLOBAL_FLAGS[el.Flag] then pcall(el.Set, el, false) end
	end
	self._applying = false
	for _, fn in ipairs(self._unloadCallbacks) do pcall(fn) end
	for _, c in ipairs(CONNS) do pcall(function() c:Disconnect() end) end
	table.clear(CONNS)

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
		if input.UserInputType ~= Enum.UserInputType.Keyboard or gameProcessed or self.Listening then return end
		if input.KeyCode == Library.MenuKey then
			self:SetVisible(not self.Visible)
			return
		end
		-- Ctrl+K for search
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) and input.KeyCode == Enum.KeyCode.K then
			if self.Visible then self:OpenSearchModal() end
			return
		end
		for flag, bind in pairs(Library.Binds) do
			local el = Library.Elements[flag]
			if el and bind.Key == input.KeyCode then
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
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		for flag, bind in pairs(Library.Binds) do
			local el = Library.Elements[flag]
			if el and bind.Key == input.KeyCode and bind.Mode == "Hold" then
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
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		conn:Disconnect()
		task.defer(function() self.Listening = false end)
		cb(input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode or nil)
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
local PINNED_GLYPHS = {Settings = "§", Config = "¶"}

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
		playSound("Click")
		self:SelectTab(tab)
	end)
	tab.Button.MouseEnter:Connect(function() tab._hover = true; tab._paint(true) end)
	tab.Button.MouseLeave:Connect(function() tab._hover = false; tab._paint(true) end)
	tab.Button:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if self.CurrentTab == tab then self:_syncMarker(false) end
	end)

	table.insert(self.Tabs, tab)
	if pinned then self:_layoutRail() end
	if not self.CurrentTab or (self.CurrentTab.Pinned and not pinned) then self:SelectTab(tab) end
	return tab
end

function Tab:SetBadge(text)
	if not self.Badge then return end
	self.Badge.Text = tostring(text or "")
	self.Badge.Visible = text ~= nil and text ~= ""
end

function Library:SelectTab(tab)
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
	local visible = tab.Pinned or (y >= BRAND_H - 4 and y <= railH - self.Foot.Size.Y.Offset - 30)
	local goal = UDim2.fromOffset(0, y)
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
function Tab:AddSubTab(name, icon)
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
		self.SubItems = create("Frame", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = self.SubBar,
		}, {list(22, H, {VerticalAlignment = Enum.VerticalAlignment.Bottom}), create("UIPadding", {PaddingLeft = UDim.new(0, 4)})})
	end
	self._subCount += 1
	local sub = setmetatable({Name = name, Window = self.Window, ParentTab = self, IsSubTab = true, _secCount = 0}, Tab)
	local iconPad = icon and 20 or 0

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
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(0, -iconPad, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = sub.Button,
		})
	end
	sub.Under = make("Frame", {
		Size = UDim2.new(0, 0, 0, 2), Position = UDim2.new(0, -iconPad, 1, -2), BorderSizePixel = 0, Parent = sub.Button,
	}, {BackgroundColor3 = "Accent"})
	sub._iconPad = iconPad

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

-- A row without hover (content blocks). Every row but a sheet's first gets an inset top rule.
local function block(tab, height)
	local sec = sheetOf(tab)
	local f = create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = #sec.Rows + 1,
		Parent = sec.Body,
	})
	make("Frame", {
		Name = "Rule", Size = UDim2.new(1, -PAD * 2, 0, 1), Position = UDim2.fromOffset(PAD, 0),
		BackgroundTransparency = 0.35, BorderSizePixel = 0, Visible = #sec.Rows > 0, Parent = f,
	}, {BackgroundColor3 = "Rule2"})
	table.insert(sec.Rows, f)
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
	if not (w and w.AutoSave and w.ActiveConfig) or w._applying then return end
	autosaveToken += 1
	local token = autosaveToken
	task.delay(0.8, function()
		if token ~= autosaveToken then return end
		if w.AutoSave and w.ActiveConfig and not w._applying then Storage.save(w.ActiveConfig, w:Serialize()) end
	end)
end

local function register(el, opts, tab)
	el.Flag = opts.Flag or opts.Name
	el.Name = opts.Name or el.Flag
	el.Default = el.Value
	el.Tab = tab
	el.Callback = opts.Callback or function() end
	Library.Elements[el.Flag] = el
	Library.Flags[el.Flag] = el.Value
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

function Tab:AddLabel(text, opts)
	opts = opts or {}
	local f = row(self, ROW_H)
	local l = label({
		Text = text,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = AY,
		Size = UDim2.new(1, -PAD - (opts.Copy and 80 or PAD), 0, 0),
		Position = UDim2.fromOffset(PAD, 15),
		Parent = f,
	})
	-- The row grows with wrapped text (long descriptions span several lines).
	local function fit()
		local textH = l.AbsoluteSize.Y / self.Window:_uiScale()
		f.Size = UDim2.new(1, 0, 0, math.max(ROW_H, math.ceil(textH) + 30))
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

	return {
		Set = function(_, t) l.Text = t end,
	}
end

-- A stronger full-width rule inside the current sheet.
function Tab:AddDivider()
	local div = block(self, 13)
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
			chip.Text = b.Key.Name .. (showMode ~= false and ("  ·  " .. string.upper(b.Mode)) or "")
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
	local f = row(self, ROW_H)
	local hit = create("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = f})

	label({
		Text = opts.Name,
		TextTruncate = TRUNC,
		Size = UDim2.new(1, -190, 1, 0),
		Position = UDim2.fromOffset(PAD, 0),
		Parent = f,
	})
	local _, show = capsule(f, UDim2.new(1, -PAD - 1, 0.5, 0))

	attachBind(window, f, hit, el, opts.Name, UDim2.new(1, -PAD - 42, 0.5, 0), true)

	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		touch()
		show(v, true)
		window:UpdateKeybindHUD()
		if not silent then
			playSound("Toggle")
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
	local f = row(self, ROW_H)
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

	local dragging = false
	local function update(x)
		local a = math.clamp((x - trackF.AbsolutePosition.X) / math.max(trackF.AbsoluteSize.X, 1), 0, 1)
		el:Set(min + a * (max - min))
	end

	hit.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging = true
			tween(nib, {Size = UDim2.fromOffset(3, 18)}, FAST)
			update(i.Position.X)
		end
	end)
	connect(UIS.InputEnded, function(i)
		if dragging and isPress(i) then
			dragging = false
			tween(nib, {Size = UDim2.fromOffset(3, 14)}, FAST)
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
	local f = row(self, ROW_H)

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
	return f
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
	local f = row(self, ROW_H)
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
	local f = row(self, ROW_H)
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
	local actions = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = body,
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
		AutomaticCanvasSize = AY, LayoutOrder = 2, Parent = body,
	}, {ScrollBarImageColor3 = "Rule2"}, {list(0)})

	local open = false
	local boxes = {}

	local function listHeight()
		return math.min(#opts.Options, maxVisible) * ROW
	end
	local function resize()
		local h = ROW_H
		if open then h = ROW_H + 26 + listHeight() + 10 end
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
		self.Value = tbl or {}
		Library.Flags[self.Flag] = self.Value
		touch()
		paintSummary()
		for option, v in pairs(boxes) do paintBox(v, table.find(self.Value, option) ~= nil) end
		if not silent then self.Callback(self.Value) end
	end

	local function build()
		for _, v in pairs(boxes) do v.Button:Destroy() end
		boxes = {}
		for i, option in ipairs(opts.Options) do
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
		scroll.Size = UDim2.new(1, 0, 0, listHeight())
		if open then resize() end
	end

	selectAllBtn.MouseButton1Click:Connect(function()
		playSound("Click")
		el:Set(table.clone(opts.Options))
	end)
	clearBtn.MouseButton1Click:Connect(function()
		playSound("Click")
		el:Set({})
	end)

	build()
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
	local f = row(self, ROW_H)
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
	local f = row(self, ROW_H)
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

	local f = row(self, ROW_H)
	label({
		Text = opts.Name, TextTruncate = TRUNC,
		Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(PAD, 0), Parent = f,
	})
	local btn = keycap(el.Value, f, "Text")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -PAD - 1, 0.5, 0)
	local edge = btn:FindFirstChildOfClass("UIStroke")

	function el:Set(v, silent)
		self.Value = v
		Library.Flags[self.Flag] = v
		touch()
		btn.Text = v
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
-- PROGRESS BAR ELEMENT
-- ---------------------------------------------------------------------------
function Tab:AddProgressBar(opts)
	local el = {Type = "ProgressBar", Value = opts.Default or 0}
	local f = row(self, 58)
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
	local keyBtn = keycap(bind.Key and bind.Key.Name or "—", keyRow, "Text")
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
		hint.Text = "press a key (Esc cancels)"
		self:ListenForKey(function(key)
			if key then bind.Key = key end
			keyBtn.Text = bind.Key and bind.Key.Name or "—"
			hint.Text = "click, then press a key"
			commit()
		end)
	end)
	unbind.MouseButton1Click:Connect(function() bind.Key = nil; commit(); close() end)
	done.MouseButton1Click:Connect(close)
	overlay.MouseButton1Click:Connect(close)
end

-- ---------------------------------------------------------------------------
-- CONFIG MANAGER & TAB
-- ---------------------------------------------------------------------------
function Library:Serialize()
	local binds = {}
	for flag, b in pairs(Library.Binds) do binds[flag] = {Key = b.Key.Name, Mode = b.Mode} end
	local flags = {}
	for flag, v in pairs(Library.Flags) do
		if not GLOBAL_FLAGS[flag] then
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
			if el and el.Type ~= "Keybind" then
				el:Set(el.Type == "ColorPicker" and (fromHex(v) or el.Value) or v)
				count += 1
			end
		end
	end
	Library.Binds = {}
	for flag, b in pairs(data.binds or {}) do
		if toKeyCode(b.Key) then Library.Binds[flag] = {Key = toKeyCode(b.Key), Mode = b.Mode} end
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

function Library:AddConfigTab(name, icon)
	local tab = self:AddTab(name or "Config", icon or Library.Icons.Config, true)
	self.ConfigTab = tab

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
		showAutoSave(self.AutoSave, animate)
		refreshNote()
		self:_refreshConfigStatus()
	end
	asHit.MouseButton1Click:Connect(function() playSound("Click"); setAutoSave(not self.AutoSave, true) end)
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
				if el.Set and el.Default ~= nil and not GLOBAL_FLAGS[el.Flag] then el:Set(el.Default) end
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

return Library
