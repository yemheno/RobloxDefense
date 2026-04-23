-- UIUtils.lua
-- Shared helpers for AppGui Controllers.
-- Location: AppGui/Controllers/UIUtils  (ModuleScript)
--
-- Other controllers:
--   local UIUtils = require(script.Parent:WaitForChild("UIUtils"))

local UIUtils = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _nm, _rc, _root

-- ── WaitForChild chain ────────────────────────────────────────────────────────
-- UIUtils.w(parent, "A", "B", "C")  →  parent:WFC("A"):WFC("B"):WFC("C")
function UIUtils.w(p, ...)
	for _, n in ipairs({...}) do
		p = p:WaitForChild(n, 10)
	end
	return p
end

-- ── Lazy module accessors ─────────────────────────────────────────────────────
local function playerModules()
	return Players.LocalPlayer
		:WaitForChild("PlayerScripts", 10)
		:WaitForChild("Modules", 10)
end

-- NetworkManager: require + ensure Init() has been called.
-- Multiple Init() calls are safe (idempotent for the client module).
function UIUtils.nm()
	if not _nm then
		local M = playerModules()
		_nm = require(M:WaitForChild("NetworkManager"))
		_nm.Init()
	end
	return _nm
end

-- ResourceCache: require only; Init() is called by LobbyClient/SocialPlazaClient.
-- GetLatest() and Subscribe() are safe to call before Init() – they return
-- a zero-filled default and register the callback for later delivery.
function UIUtils.rc()
	if not _rc then
		local M = playerModules()
		_rc = require(M:WaitForChild("ResourceCache"))
	end
	return _rc
end

-- ── AppGui instance references ────────────────────────────────────────────────
-- script  →  UIUtils (ModuleScript)
-- script.Parent         →  Controllers (Frame)
-- script.Parent.Parent  →  AppGui (ScreenGui)
function UIUtils.appGui()
	return script.Parent.Parent
end

function UIUtils.root()
	if not _root then
		_root = UIUtils.appGui():WaitForChild("AppRoot", 10)
	end
	return _root
end

-- ── Bar updater (mkStatusBar rows) ───────────────────────────────────────────
-- Row structure built by mkStatusBar in generate_ui.lua:
--   ROW (Frame)
--     Inner (Frame)
--       Label  (TextLabel)   – bar name / level label
--       Track  (Frame)       – background track
--         Fill (Frame)       – colored fill: Size.X.Scale = percentage
--       Value  (TextLabel)   – "cur / max" text
function UIUtils.updateBar(row, cur, max)
	cur = math.max(cur or 0, 0)
	max = math.max(max or 1, 1)
	local pct   = math.clamp(cur / max, 0, 1)
	local inner = row:FindFirstChild("Inner")
	if not inner then return end
	local track = inner:FindFirstChild("Track")
	if track then
		local fill = track:FindFirstChild("Fill")
		if fill then fill.Size = UDim2.new(pct, 0, 1, 0) end
	end
	local val = inner:FindFirstChild("Value")
	if val then val.Text = math.floor(cur) .. " / " .. math.floor(max) end
end

function UIUtils.setBarLabel(row, text)
	local inner = row:FindFirstChild("Inner")
	if inner then
		local lbl = inner:FindFirstChild("Label")
		if lbl then lbl.Text = text end
	end
end

-- ── Currency pill text ────────────────────────────────────────────────────────
-- Pill structure: PILL (Frame) > Label (TextLabel) with text "♦  0"
--
-- §2.8a: use strata-aware formatting (1k / 1M / 1B / 1T). Raw tostring()
-- overflows the pill once players hit the millions of merits that late-game
-- horde runs can produce. Keep four tiers; if we ever need quadrillions we
-- can extend to Qa/Qi or switch to scientific.
local function formatCurrency(n)
	n = tonumber(n) or 0
	if n >= 1e12 then
		return string.format("%.2fT", n / 1e12)
	elseif n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fk", n / 1e3)
	else
		-- Comma separators for the 1,000–9,999 band so humans can still read it.
		local s = tostring(math.floor(n))
		if #s <= 3 then return s end
		local result = ""
		local len = #s
		for i = 1, len do
			if i > 1 and (len - i + 1) % 3 == 0 then
				result = result .. ","
			end
			result = result .. s:sub(i, i)
		end
		return result
	end
end

function UIUtils.setCurrencyPill(pill, icon, value)
	local lbl = pill:FindFirstChild("Label")
	if lbl then lbl.Text = icon .. "  " .. formatCurrency(value) end
end

UIUtils.formatCurrency = formatCurrency

-- ── Simple open / close ───────────────────────────────────────────────────────
function UIUtils.open(bd)  bd.Visible = true  end
function UIUtils.close(bd) bd.Visible = false end

-- ── Wire close button on panel to hide backdrop ───────────────────────────────
function UIUtils.wireCloseBtn(panel, backdrop)
	local btn = panel:FindFirstChild("CloseBtn")
	if btn then
		btn.Activated:Connect(function() backdrop.Visible = false end)
	end
end

-- ── Tab bar highlighting ──────────────────────────────────────────────────────
function UIUtils.wireTabBar(bar, onColor, offColor)
	local function setActive(activeName)
		for _, b in ipairs(bar:GetChildren()) do
			if b:IsA("TextButton") then
				local on = b.Name == activeName
				b.BackgroundColor3 = on and onColor or offColor
				b.TextColor3       = on
					and Color3.fromRGB(220, 220, 230)
					or  Color3.fromRGB(130, 130, 150)
			end
		end
	end
	for _, b in ipairs(bar:GetChildren()) do
		if b:IsA("TextButton") then
			b.Activated:Connect(function() setActive(b.Name) end)
		end
	end
end

return UIUtils
