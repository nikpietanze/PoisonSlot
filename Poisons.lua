-- Poison data, bag scanning, favorite resolution and weapon coating state.
local _, ns = ...

ns.IsSecret = issecretvalue or function() return false end
local isSecret = ns.IsSecret

ns.VIAL_ICON = 134799

ns.hands = {
	{ key = "mh", label = "Main Hand", short = "MH", slot = ns.MAIN_HAND_SLOT, enchantSlot = 0, frame = "CharacterMainHandSlot", alertKey = "alertMainHand" },
	{ key = "oh", label = "Off Hand", short = "OH", slot = ns.OFF_HAND_SLOT, enchantSlot = 1, frame = "CharacterSecondaryHandSlot", alertKey = "alertOffHand" },
}

-- PvE display priority by family. IDs are ordered from lowest to highest rank.
local poisonFamilies = {
	{ name = "instant", items = { 6947, 6949, 6950, 8926, 8927, 8928 } },
	{ name = "occult", items = { 226374, 234444 } },
	{ name = "deadly", items = { 2892, 2893, 8984, 8985, 20844 } },
	{ name = "sebacious", items = { 217345 } },
	{ name = "crippling", items = { 3775, 3776 } },
	{ name = "wound", items = { 10918, 10920, 10921, 10922 } },
	{ name = "mind-numbing", items = { 5237, 6951, 9186 } },
	{ name = "numbing", items = { 217346 } },
	{ name = "atrophic", items = { 217347 } },
}
-- The off hand favors stacking poisons for sustained raid fights.
local raidOffHandPriority = { occult = 1, deadly = 2, instant = 3 }
local poisonsByID = {}
for priority, family in ipairs(poisonFamilies) do
	for rank, id in ipairs(family.items) do
		poisonsByID[id] = {
			family = family.name,
			rank = rank,
			priority = priority,
			raidOffHand = raidOffHandPriority[family.name] or priority,
		}
	end
end

function ns.IsPoison(itemID)
	return poisonsByID[itemID] ~= nil
end

local POISON_WEAPON_SUBCLASSES = 173555

function ns.HasEligibleWeapon(hand)
	local id = GetInventoryItemID("player", hand.slot)
	if isSecret(id) or not id then
		return false
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
	return not isSecret(classID) and not isSecret(subclassID)
		and classID == Enum.ItemClass.Weapon and subclassID ~= nil
		and bit.band(POISON_WEAPON_SUBCLASSES, bit.lshift(1, subclassID)) ~= 0
end

local requestedItems = {}

-- Returns a list of poison entries in the bags and a lookup by item ID. Each
-- entry carries an unlocked bag position to use and the total stack count.
function ns.ScanBags()
	local entries, byID = {}, {}
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and poisonsByID[info.itemID] then
				local entry = byID[info.itemID]
				if not entry then
					entry = {
						id = info.itemID,
						name = C_Item.GetItemNameByID(info.itemID),
						icon = info.iconFileID,
						count = 0,
					}
					byID[entry.id] = entry
					entries[#entries + 1] = entry
					if not entry.name and not requestedItems[entry.id] then
						requestedItems[entry.id] = true
						C_Item.RequestLoadItemDataByID(entry.id)
					end
				end
				entry.count = entry.count + (info.stackCount or 1)
				if not info.isLocked and not entry.bag then
					entry.bag, entry.slot = bag, slot
				end
			end
		end
	end
	return entries, byID
end

function ns.IsUsable(entry)
	return entry and entry.bag and entry.name and C_Item.IsUsableItem(entry.id) and true or false
end

function ns.SortPoisons(entries, hand)
	local _, instanceType = IsInInstance()
	local order = instanceType == "raid" and hand.slot == ns.OFF_HAND_SLOT and "raidOffHand" or "priority"
	for _, entry in ipairs(entries) do
		entry.usable = ns.IsUsable(entry)
	end
	table.sort(entries, function(a, b)
		if a.usable ~= b.usable then
			return a.usable
		end
		local first, second = poisonsByID[a.id], poisonsByID[b.id]
		if first[order] ~= second[order] then
			return first[order] < second[order]
		end
		return first.rank > second.rank
	end)
end

-- Returns the bag entry to use for a hand's favorite, plus the saved favorite
-- ID. The exact starred rank wins. If it is gone, the best usable rank of the
-- same family is used instead. A different family is never substituted.
function ns.ResolveFavorite(hand, byID)
	local favorite = ns.db.favorites[hand.key]
	if not favorite then
		return nil
	end
	if not byID then
		local _
		_, byID = ns.ScanBags()
	end
	local exact = byID[favorite]
	if ns.IsUsable(exact) then
		return exact, favorite
	end
	local info = poisonsByID[favorite]
	local best
	if info then
		for id, entry in pairs(byID) do
			local candidate = poisonsByID[id]
			if candidate.family == info.family and ns.IsUsable(entry)
				and (not best or candidate.rank > poisonsByID[best.id].rank) then
				best = entry
			end
		end
	end
	return best, favorite
end

-- Returns "active" | "expiring" | "missing" and the seconds left, or nil when
-- the hand has no poisonable weapon or the client hides the data.
function ns.WeaponPoisonState(hand)
	if not ns.HasEligibleWeapon(hand) then return end
	local enchants = C_Item.GetWeaponEnchantInfo(hand.enchantSlot)
	if isSecret(enchants) or type(enchants) ~= "table" then return end
	for _, enchant in ipairs(enchants) do
		if isSecret(enchant.enchantType) or isSecret(enchant.hasEnchant) then return end
		if enchant.hasEnchant and enchant.enchantType == Enum.ItemEnchantType.Imbue then
			local ms = enchant.timeLeft
			if isSecret(ms) then return "active" end
			if ms == 0 then return "missing" end
			if ms and ms > 0 and ms <= ns.COUNTDOWN * 1000 then
				return "expiring", ms / 1000
			end
			return "active", ms and ms / 1000
		end
	end
	return "missing"
end
