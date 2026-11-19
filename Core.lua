-- PoisonSlot: Rogue poison controls on the main-hand and off-hand weapon slots.
-- See docs/HANDOFF.md for the full spec. This file is a loadable stub until the
-- Phase 0 secure-action spike is done in game.

local ADDON_NAME, ns = ...

ns.MAIN_HAND_SLOT = 16
ns.OFF_HAND_SLOT = 17

local DEFAULTS = {
	version = 1,
	favorites = { mh = nil, oh = nil }, -- poison family per hand, never a bag slot
	reminders = "expiring", -- "off" | "missing" | "expiring"
	expiryThresholdMinutes = 5,
}

local function applyDefaults(db, defaults)
	for key, value in pairs(defaults) do
		if db[key] == nil then
			db[key] = type(value) == "table" and CopyTable(value) or value
		end
	end
	return db
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON_NAME then
		self:UnregisterEvent("ADDON_LOADED")
		PoisonSlotDB = applyDefaults(PoisonSlotDB or {}, DEFAULTS)
		ns.db = PoisonSlotDB

		local _, class = UnitClass("player")
		ns.isRogue = class == "ROGUE"
	end
end)

SLASH_POISONSLOT1 = "/pslot"
SlashCmdList.POISONSLOT = function()
	local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
	print(("|cff8fd14fPoisonSlot|r %s (%s)"):format(version, ns.isRogue and "rogue" or "not a rogue, inactive"))
end
