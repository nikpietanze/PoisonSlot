-- PoisonSlot: Rogue poison controls on the main-hand and off-hand weapon slots.

local ADDON_NAME, ns = ...

ns.MAIN_HAND_SLOT = 16
ns.OFF_HAND_SLOT = 17
ns.COUNTDOWN = 10 -- Seconds of countdown shown before a poison runs out.
ns.MEDIA = [[Interface\AddOns\]] .. ADDON_NAME .. [[\Media\]]
ns.BRONZE = { 0.50, 0.39, 0.22 }

local DB_VERSION = 4
local DEFAULTS = {
	favorites = {}, -- Exact poison item ID keyed by "mh" or "oh".
	lastPoison = {}, -- Last poison item ID applied to each hand, for the reminders.
	-- Reminders
	remindersEnabled = true,
	alertMainHand = true,
	alertOffHand = true,
	alertCountdown = true, -- Count down the final seconds before showing Missing.
	alertClick = true, -- Clicking a reminder reapplies that hand's last poison.
	alertHideInCombat = false,
	hideWhenResting = true,
	-- Reminder appearance
	iconSize = 40, -- Pixels; the reminders scale from a 40px design.
	alertSpacing = 14,
	alertLayout = "horizontal", -- "horizontal" | "vertical"
	alertGlow = "proc", -- Missing glow: "proc" | "pixel" | "soft" | "none"
	alertSound = "none", -- "none", "kit:<SOUNDKIT key>" or "lsm:<LibSharedMedia name>"
	alertCaption = true,
	alertBadge = true,
	positions = {}, -- Reminder anchor per Edit Mode layout, plus "default".
	-- Character panel
	weaponButtons = true,
	vialRightClick = true,
	-- General
	animations = true,
	tooltips = true,
}

local loadCallbacks, loginCallbacks = {}, {}
function ns.OnLoad(fn) loadCallbacks[#loadCallbacks + 1] = fn end
function ns.OnLogin(fn) loginCallbacks[#loginCallbacks + 1] = fn end

function ns.Print(message)
	print("|cff8fd14fPoisonSlot|r " .. message)
end

function ns.Version()
	local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
	-- Split the token so the packager only substitutes it in the TOC.
	if not version or version == "@project" .. "-version@" then
		return "dev"
	end
	return version
end

local function migrate(db)
	-- Version 2 stored reminders as one "expiring" | "missing" | "off" choice.
	if db.reminders ~= nil then
		if db.reminders == "off" then
			db.remindersEnabled = false
		elseif db.reminders == "missing" then
			db.alertCountdown = false
		end
		db.reminders = nil
	end
	-- Version 3 stored a boolean sound, a percentage scale and one screen offset.
	if type(db.alertSound) == "boolean" then
		db.alertSound = db.alertSound and "kit:ALARM_CLOCK_WARNING_3" or "none"
	end
	if db.alertScale then
		local size = math.floor(40 * db.alertScale / 2 + 0.5) * 2
		db.iconSize = math.max(24, math.min(80, size))
		db.alertScale = nil
	end
	if db.reminderX or db.reminderY then
		local scale = (db.iconSize or 40) / 40
		db.positions = db.positions or {}
		db.positions.default = { point = "CENTER", x = (db.reminderX or 0) / scale, y = (db.reminderY or -140) / scale }
		db.reminderX, db.reminderY = nil, nil
	end
	for key, value in pairs(DEFAULTS) do
		if db[key] == nil then
			db[key] = type(value) == "table" and CopyTable(value) or value
		end
	end
	-- Reminders always start locked; unlocking is a temporary edit mode.
	db.remindersLocked = nil
	db.expiryThresholdMinutes = nil
	db.version = DB_VERSION
	return db
end

-- Built-in alert sounds. SharedMedia sounds are offered too when installed.
ns.SOUNDS = {
	{ key = "kit:ALARM_CLOCK_WARNING_3", label = "Alarm clock" },
	{ key = "kit:RAID_WARNING", label = "Raid warning" },
	{ key = "kit:READY_CHECK", label = "Ready check" },
	{ key = "kit:MAP_PING", label = "Map ping" },
	{ key = "kit:TELL_MESSAGE", label = "Whisper" },
}

function ns.SharedMedia()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function ns.PlayAlertSound(choice)
	if not choice or choice == "none" then return end
	local kind, name = choice:match("^(%a+):(.+)$")
	if kind == "kit" then
		local id = SOUNDKIT and SOUNDKIT[name]
		if id then PlaySound(id, "Master") end
	elseif kind == "lsm" then
		local media = ns.SharedMedia()
		local file = media and media:Fetch("sound", name, true)
		if file then PlaySoundFile(file, "Master") end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON_NAME then return end
		self:UnregisterEvent("ADDON_LOADED")
		PoisonSlotDB = migrate(PoisonSlotDB or {})
		ns.db = PoisonSlotDB
		local _, class = UnitClass("player")
		ns.isRogue = class == "ROGUE"
		for _, fn in ipairs(loadCallbacks) do fn() end
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		if not ns.isRogue then return end
		for _, fn in ipairs(loginCallbacks) do fn() end
	end
end)

local function printStatus()
	local version, build, _, interface = GetBuildInfo()
	ns.Print(("%s on client %s (%s), interface %s"):format(ns.Version(), version, build, interface))
	if not ns.isRogue then
		ns.Print("Inactive: this character is not a Rogue.")
		return
	end
	for _, hand in ipairs(ns.hands) do
		local weapon = GetInventoryItemID("player", hand.slot)
		local state, remaining = ns.WeaponPoisonState(hand)
		local favorite = ns.db.favorites[hand.key]
		local resolved = ns.ResolveFavorite(hand)
		local lastEntry, last = ns.ResolveLastPoison(hand)
		print(("  %s: weapon=%s eligible=%s poison=%s%s favorite=%s resolved=%s last=%s reapplies=%s"):format(
			hand.short, tostring(weapon), tostring(ns.HasEligibleWeapon(hand)), tostring(state),
			remaining and (" (" .. math.floor(remaining) .. "s)") or "", tostring(favorite),
			resolved and tostring(resolved.id) or "none", tostring(last),
			lastEntry and tostring(lastEntry.id) or "none"))
		if weapon and not InCombatLockdown() then
			for _, info in ipairs(C_Item.GetWeaponEnchantInfo(hand.enchantSlot) or {}) do
				if info.hasEnchant and not ns.IsSecret(info.enchantID) then
					print(("    enchant=%s type=%s remaining=%ss charges=%s"):format(info.enchantID,
						tostring(info.enchantType), math.floor((info.timeLeft or 0) / 1000), tostring(info.charges)))
				end
			end
		end
	end
end

-- Addon compartment (the addons button by the minimap).
function PoisonSlot_OnCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		if ns.isRogue then ns.PreviewAlerts() end
	else
		ns.OpenOptions()
	end
end

function PoisonSlot_OnCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText("PoisonSlot")
	GameTooltip:AddDoubleLine("Left-click", "Options", 1, 0.82, 0, 1, 1, 1)
	if ns.isRogue then
		GameTooltip:AddDoubleLine("Right-click", "Preview reminders", 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:Show()
end

function PoisonSlot_OnCompartmentLeave()
	GameTooltip:Hide()
end

local commands = {
	status = printStatus,
	preview = function() ns.PreviewAlerts() end,
	move = function() ns.UnlockAlerts() end,
	unlock = function() ns.UnlockAlerts(true) end,
	lock = function() ns.LockAlerts() end,
	reset = function() ns.ResetAlertPosition() end,
}

SLASH_POISONSLOT1 = "/pslot"
SLASH_POISONSLOT2 = "/poisonslot"
SlashCmdList.POISONSLOT = function(input)
	local command = strtrim((input or ""):lower())
	if command == "" or command == "options" or command == "config" then
		ns.OpenOptions()
	elseif commands[command] then
		if command ~= "status" and not ns.isRogue then
			ns.Print("Inactive: this character is not a Rogue.")
			return
		end
		commands[command]()
	else
		ns.Print("Commands: /pslot [options | preview | move | unlock | lock | reset | status]")
	end
end
