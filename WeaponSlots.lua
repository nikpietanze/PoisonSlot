-- Poison vials on the Character panel's weapon slots and their poison tray.
local _, ns = ...

local CORNER_SIZE = 18
local TILE_SIZE, TILE_GAP, FLYOUT_PADDING = 42, 4, 7
local CIRCLE_MASK = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local GOLD = { 1, 0.78, 0.12, 1 }
local LIGHT_GOLD = { 1, 0.89, 0.38, 1 }
local COMBAT_RING = { 0.45, 0.38, 0.24, 1 }
local hands = ns.hands

local root, menu, openHand
local inCombat = false

-- In combat the vials stay visible but dimmed: the game doesn't let addons
-- change what a click applies until combat ends.
local function paintVial(button, highlighted)
	if inCombat then
		button.ring:SetColorTexture(unpack(COMBAT_RING))
	else
		button.ring:SetColorTexture(unpack(highlighted and LIGHT_GOLD or GOLD))
	end
	local shade = inCombat and 0.7 or 1
	button.icon:SetDesaturated(inCombat)
	button.icon:SetVertexColor(shade, shade, shade)
end
local rows = {}

local function closeMenu()
	menu:Hide()
	openHand = nil
end

local function showUnavailable(owner, title, detail)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:SetText(title, 1, 0.75, 0.3)
	if detail then
		GameTooltip:AddLine(detail, 1, 1, 1, true)
	end
	GameTooltip:Show()
end

local function clearAction(button, suffix)
	button:SetAttribute("type" .. suffix, nil)
	button:SetAttribute("item" .. suffix, nil)
	button:SetAttribute("target-slot" .. suffix, nil)
end

local function prepareClick(button, hand, entry, suffix)
	clearAction(button, suffix)
	if not entry or not ns.HasEligibleWeapon(hand) or SpellIsTargeting() or GetCursorInfo() then
		return false
	end
	if not ns.IsUsable(entry) then
		showUnavailable(button, "Poison unavailable", "Check your bags and the item's requirements.")
		return false
	end
	button:SetAttribute("item" .. suffix, ("%d %d"):format(entry.bag, entry.slot))
	button:SetAttribute("target-slot" .. suffix, hand.slot)
	button:SetAttribute("type" .. suffix, "item")
	return true
end

-- The secure action is prepared in PreClick, right before Blizzard's handler
-- runs, so it always uses the poison's current bag position.
local function installAction(button, clickName, suffix, getSelection, afterClick)
	button:SetAttribute("useOnKeyDown", false)
	button:SetScript("PreClick", function(self, mouseButton)
		if mouseButton ~= clickName or InCombatLockdown() then
			return
		end
		local hand, entry = getSelection(self)
		if not hand or not entry then
			return
		end
		self.poisonAttempt = prepareClick(self, hand, entry, suffix)
	end)
	button:SetScript("PostClick", function(self, mouseButton)
		if mouseButton == clickName and not InCombatLockdown() then
			clearAction(self, suffix)
			if afterClick and self.poisonAttempt and not SpellIsTargeting() then
				afterClick()
			end
			self.poisonAttempt = nil
		end
	end)
end

local refreshMenu

local function favoritesChanged()
	if ns.RefreshAlerts then ns.RefreshAlerts() end
end

local function createRow()
	local row = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate")
	row:SetSize(TILE_SIZE, TILE_SIZE)
	row:RegisterForClicks("LeftButtonUp")
	installAction(row, "LeftButton", "1", function()
		local _, byID = ns.ScanBags()
		return openHand, byID[row.entry.id]
	end, closeMenu)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", 1, -1)
	row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local mask = row:CreateMaskTexture()
	mask:SetTexture(ns.MEDIA .. "PoisonTileMask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(row.icon)
	row.icon:AddMaskTexture(mask)
	local glow = row:CreateTexture(nil, "OVERLAY")
	glow:SetTexture(ns.MEDIA .. "PoisonTileGlow.tga")
	glow:SetPoint("TOPLEFT", -4, 4)
	glow:SetPoint("BOTTOMRIGHT", 4, -4)
	glow:SetVertexColor(0.45, 0.88, 0.27)
	glow:SetAlpha(0.78)
	local hoverGlow = row:CreateTexture(nil, "OVERLAY", nil, 1)
	hoverGlow:SetTexture(ns.MEDIA .. "PoisonTileGlow.tga")
	hoverGlow:SetAllPoints(glow)
	hoverGlow:SetVertexColor(0.55, 1, 0.32)
	hoverGlow:SetBlendMode("ADD")
	hoverGlow:SetAlpha(0.46)
	hoverGlow:Hide()
	row:SetScript("OnHide", function() hoverGlow:Hide() end)
	row:SetScript("OnEnter", function()
		hoverGlow:Show()
		if not ns.db.tooltips then return end
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(row.entry.name or "Loading item…")
		if ns.IsUsable(row.entry) then
			GameTooltip:AddLine(("Click to apply to your %s."):format(openHand.label:lower()), 0.6, 1, 0.45)
			GameTooltip:AddLine(("%d in bags"):format(row.entry.count), 0.7, 0.7, 0.7)
		else
			GameTooltip:AddLine("Currently unavailable", 1, 0.75, 0.3)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		hoverGlow:Hide()
		GameTooltip:Hide()
	end)

	row.star = CreateFrame("Button", nil, row)
	row.star:SetPoint("TOPRIGHT")
	row.star:SetSize(18, 18)
	row.star:SetFrameLevel(row:GetFrameLevel() + 1)
	row.star.icon = row.star:CreateTexture(nil, "ARTWORK")
	row.star.icon:SetPoint("TOPLEFT", 1, -1)
	row.star.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	row.star.highlight = row.star:CreateTexture(nil, "HIGHLIGHT")
	row.star.highlight:SetAllPoints(row.star.icon)
	row.star.highlight:SetBlendMode("ADD")
	local function starTooltip()
		if not ns.db.tooltips or not openHand or not row.entry then return end
		GameTooltip:SetOwner(row.star, "ANCHOR_RIGHT")
		if row.starState == "favorite" then
			GameTooltip:SetText("Remove favorite")
		else
			GameTooltip:SetText("Favorite for " .. openHand.label)
			if row.starState == "standin" then
				local name = C_Item.GetItemNameByID(ns.db.favorites[openHand.key]) or "your favorite"
				GameTooltip:AddLine(("Used in place of %s, which isn't available right now."):format(name),
					1, 0.82, 0, true)
			end
			GameTooltip:AddLine("Applied by right-clicking the vial or clicking a reminder.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end
	row.star:SetScript("OnEnter", function()
		hoverGlow:Show()
		starTooltip()
	end)
	row.star:SetScript("OnLeave", function()
		hoverGlow:Hide()
		GameTooltip:Hide()
	end)
	row.star:SetScript("OnClick", function()
		if not openHand or InCombatLockdown() then
			return
		end
		if ns.db.favorites[openHand.key] == row.entry.id then
			ns.db.favorites[openHand.key] = nil
		else
			ns.db.favorites[openHand.key] = row.entry.id
		end
		refreshMenu()
		favoritesChanged()
		-- Keep the tooltip in step with the new state while still hovering.
		if row.star:IsMouseOver() then starTooltip() end
	end)
	return row
end

refreshMenu = function()
	local entries, byID = ns.ScanBags()
	if #entries == 0 then
		local button = openHand.button
		closeMenu()
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText("No poisons in your bags")
		GameTooltip:Show()
		return
	end
	ns.SortPoisons(entries, openHand)
	local resolved, favoriteID = ns.ResolveFavorite(openHand, byID)
	for index, entry in ipairs(entries) do
		local row = rows[entry.id] or createRow()
		rows[entry.id] = row
		row.entry = entry
		row:ClearAllPoints()
		local top = CORNER_SIZE + FLYOUT_PADDING + (index - 1) * (TILE_SIZE + TILE_GAP)
		row:SetPoint("TOPLEFT", FLYOUT_PADDING, -top)
		row.revealAt = top + TILE_SIZE
		row.icon:SetTexture(entry.icon or ns.VIAL_ICON)
		row.icon:SetDesaturated(not entry.usable)
		-- The filled star marks the saved favorite. If that exact poison can't
		-- be used right now, the rank applied in its place gets a faded star.
		local state = "off"
		if favoriteID == entry.id then
			state = "favorite"
		elseif resolved and resolved.id == entry.id then
			state = "standin"
		end
		row.starState = state
		local atlas = state == "off" and "auctionhouse-icon-favorite-off" or "auctionhouse-icon-favorite"
		row.star.icon:SetAtlas(atlas)
		row.star.icon:SetAlpha(state == "standin" and 0.5 or 1)
		row.star.highlight:SetAtlas(atlas)
		row.star.highlight:SetAlpha(state == "off" and 0.4 or 0.2)
		row:SetShown(menu:IsShown() and not menu.openTime)
	end
	for id, row in pairs(rows) do
		if not byID[id] then
			row.revealAt = nil
			row:Hide()
		end
	end
	local height = CORNER_SIZE + #entries * (TILE_SIZE + TILE_GAP) - TILE_GAP + 2 * FLYOUT_PADDING
	menu:SetHeight(height)
	local menuScale = menu:GetParent():GetEffectiveScale()
	local screenHeight = UIParent:GetHeight() * UIParent:GetEffectiveScale() / menuScale
	local button = openHand.button
	local spaceBelow = (button:GetBottom() or 0) * button:GetEffectiveScale() / menuScale - 8
	local available = math.min(screenHeight - 8, math.max(spaceBelow, height * 0.8))
	local scale = math.min(1, available / height)
	if menu:GetScale() ~= scale then
		menu:SetScale(scale)
	end
	if menu:IsShown() and not menu.openTime then
		menu.shell:SetSize(menu:GetWidth(), height)
	end
	menu:Show()
end

local function roundTexture(button, layer, inset)
	local texture = button:CreateTexture(nil, layer)
	texture:SetPoint("TOPLEFT", inset, -inset)
	texture:SetPoint("BOTTOMRIGHT", -inset, inset)
	local mask = button:CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return texture
end

local function cornerTooltip(button, hand)
	if not ns.db.tooltips then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(hand.label .. " poisons")
	if InCombatLockdown() then
		GameTooltip:AddLine("Poisons can't be changed in combat.", 1, 0.5, 0.4)
		GameTooltip:Show()
		return
	end
	GameTooltip:AddLine("Left-click to choose a poison.", 1, 1, 1)
	local favorite = ns.db.favorites[hand.key]
	if favorite and ns.db.vialRightClick then
		local resolved = ns.ResolveFavorite(hand)
		if resolved then
			GameTooltip:AddLine("Right-click to apply " .. (resolved.name or "your favorite") .. ".", 0.6, 1, 0.45)
		else
			local name = C_Item.GetItemNameByID(favorite) or "Your favorite"
			GameTooltip:AddLine(name .. " is not in your bags.", 1, 0.5, 0.4)
		end
	end
	GameTooltip:Show()
end

local function createCorner(hand, slotFrame)
	local button = CreateFrame("Button", nil, root, "SecureActionButtonTemplate")
	button:SetSize(CORNER_SIZE, CORNER_SIZE)
	button:SetPoint("CENTER", slotFrame, "TOPRIGHT")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local outline = roundTexture(button, "BACKGROUND", 0)
	outline:SetColorTexture(0.18, 0.10, 0.02, 1)
	button.ring = roundTexture(button, "BORDER", 1)
	button.ring:SetColorTexture(unpack(GOLD))
	-- ForeverTint recognizes button.icon and leaves its artwork alone.
	button.icon = roundTexture(button, "ARTWORK", 2.5)
	button.icon:SetTexture(ns.VIAL_ICON)
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- Keep the vial above the expanding tray as its clickable clasp.
	button:SetFrameStrata("DIALOG")
	button:SetFrameLevel(menu:GetFrameLevel() + 5)
	installAction(button, "RightButton", "2", function()
		if not ns.db.vialRightClick then return end
		return hand, ns.ResolveFavorite(hand)
	end)
	button:HookScript("PostClick", function(_, mouseButton)
		if mouseButton ~= "LeftButton" or InCombatLockdown() then
			return
		end
		if menu:IsShown() then
			local wasOpen = openHand == hand
			closeMenu()
			if wasOpen then
				return
			end
		end
		GameTooltip:Hide()
		openHand = hand
		menu:ClearAllPoints()
		menu:SetPoint("TOP", button, "TOP", 0, 2)
		refreshMenu()
	end)
	button:SetScript("OnEnter", function()
		paintVial(button, true)
		if openHand == hand and menu:IsShown() then
			return
		end
		cornerTooltip(button, hand)
	end)
	button:SetScript("OnLeave", function()
		if openHand ~= hand or not menu:IsShown() then
			paintVial(button, false)
		end
		GameTooltip:Hide()
	end)
	hand.button = button
	paintVial(button, false)
end

local function initialize()
	local panel = PaperDollFrame
	if not panel or not _G[hands[1].frame] or not _G[hands[2].frame] then
		return
	end
	-- ForeverTint skips indicator frames and their children during CharacterFrame scans.
	root = CreateFrame("Frame", "PoisonSlotWeaponIndicators", panel, "SecureHandlerStateTemplate")
	root:SetFrameStrata("HIGH")
	-- Protected from the start so the combat snippet can always close it; its
	-- secure rows only exist once it has been opened.
	menu = CreateFrame("Frame", nil, root, "SecureFrameTemplate")
	menu:SetSize(TILE_SIZE + 2 * FLYOUT_PADDING, TILE_SIZE + 2 * FLYOUT_PADDING)
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:Hide()
	local shell = CreateFrame("Frame", nil, menu, "BackdropTemplate")
	menu.shell = shell
	shell:SetFrameLevel(menu:GetFrameLevel())
	shell:EnableMouse(false)
	shell:SetPoint("TOP", menu)
	shell:SetSize(CORNER_SIZE, CORNER_SIZE)
	shell:SetBackdrop({
		bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	shell:SetBackdropColor(0.065, 0.06, 0.055, 0.96)
	shell:SetBackdropBorderColor(ns.BRONZE[1], ns.BRONZE[2], ns.BRONZE[3], 1)
	-- Grow only the decorative shell. Each secure row becomes clickable at
	-- its final position once the expanding edge has passed it.
	local function unfold(self, elapsed)
		if InCombatLockdown() then return end
		self.openTime = self.openTime + elapsed
		local progress = math.min(1, self.openTime / 0.28)
		local widthProgress = 1 - (1 - math.min(1, progress * 2)) ^ 3
		local heightProgress = progress * progress * (3 - 2 * progress)
		local height = CORNER_SIZE + (self:GetHeight() - CORNER_SIZE) * heightProgress
		shell:SetSize(CORNER_SIZE + (self:GetWidth() - CORNER_SIZE) * widthProgress, height)
		for _, row in pairs(rows) do
			if row.revealAt and row.revealAt <= height and not row:IsShown() then
				row:Show()
			end
		end
		if progress == 1 then
			self:SetScript("OnUpdate", nil)
			self.openTime = nil
		end
	end
	menu:SetScript("OnShow", function(self)
		if not openHand or InCombatLockdown() then return end
		paintVial(openHand.button, true)
		-- With animations off the first step lands on the fully open tray.
		self.openTime = ns.db.animations and 0 or 1
		self:SetScript("OnUpdate", unfold)
		unfold(self, 0)
	end)
	menu:SetScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
		self.openTime = nil
		if openHand then
			paintVial(openHand.button, openHand.button:IsMouseOver())
		end
		openHand = nil
	end)

	for _, hand in ipairs(hands) do
		createCorner(hand, _G[hand.frame])
	end
	root:SetFrameRef("menu", menu)
	-- Combat closes the poison tray; the vials themselves stay on the slots.
	root:SetAttribute("_onstate-combat", [[
		if newstate == "locked" then
			self:GetFrameRef("menu"):Hide()
		end
	]])
	RegisterStateDriver(root, "combat", "[combat] locked; ready")
	panel:HookScript("OnHide", function()
		if not InCombatLockdown() then
			closeMenu()
		end
	end)
end

local function updateButtons()
	if not root or InCombatLockdown() then return end
	for _, hand in ipairs(hands) do
		hand.button:SetShown(ns.db.weaponButtons and ns.HasEligibleWeapon(hand))
	end
	if menu:IsShown() then
		if openHand and openHand.button:IsShown() then
			refreshMenu()
		else
			closeMenu()
		end
	end
end

function ns.RefreshWeaponButtons()
	updateButtons()
end

local listener = CreateFrame("Frame")
local itemRefreshQueued

ns.OnLogin(function()
	listener:RegisterEvent("ADDON_LOADED")
	listener:RegisterEvent("PLAYER_REGEN_ENABLED")
	listener:RegisterEvent("PLAYER_REGEN_DISABLED")
	listener:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	listener:RegisterEvent("BAG_UPDATE_DELAYED")
	listener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	listener:RegisterEvent("GLOBAL_MOUSE_DOWN")
	inCombat = InCombatLockdown()
	if not root then initialize() end
	updateButtons()
end)

local function setCombat(state)
	inCombat = state
	for _, hand in ipairs(hands) do
		if hand.button then
			paintVial(hand.button, hand.button:IsMouseOver() or (openHand == hand and menu:IsShown()))
		end
	end
end

listener:SetScript("OnEvent", function(_, event, arg)
	if event == "PLAYER_REGEN_DISABLED" then
		setCombat(true)
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		setCombat(false)
	end
	if event == "ADDON_LOADED" and arg ~= "Blizzard_UIPanels_Game" then
		return
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		if ns.IsPoison(arg) and not itemRefreshQueued then
			itemRefreshQueued = true
			C_Timer.After(0, function()
				itemRefreshQueued = nil
				if not InCombatLockdown() and menu and menu:IsVisible() then
					refreshMenu()
				end
			end)
		end
		return
	end
	if InCombatLockdown() then
		return
	end
	if not root then
		initialize()
		if not root then return end
	end
	if event == "GLOBAL_MOUSE_DOWN" then
		if menu:IsVisible() and not menu:IsMouseOver() and openHand and not openHand.button:IsMouseOver() then
			closeMenu()
		end
		return
	end
	updateButtons()
end)
