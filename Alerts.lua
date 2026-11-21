-- On-screen poison reminders: one tile per hand, shown when that hand's poison
-- is missing or in its final seconds. Left-click applies the hand's favorite
-- through a secure item action; right-click snoozes until the next loading
-- screen, Shift-right-click until that weapon is poisoned again or you log out. Positioned through Blizzard's Edit Mode when LibEditMode is present.
local _, ns = ...

local LEM = LibStub and LibStub("LibEditMode", true)
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local BASE, CAPTION = 40, 18
local COUNTDOWN = ns.COUNTDOWN
local URGENT = 5 -- Seconds left when the countdown turns red.
local TENTHS = 3 -- Seconds left when the countdown shows tenths.
local PREVIEW_CYCLE = COUNTDOWN + 5
local PREVIEW_LENGTH = PREVIEW_CYCLE * 2
local GLOW = ns.MEDIA .. "PoisonTileGlow.tga"
local MASK = ns.MEDIA .. "PoisonTileMask.tga"
local GLOW_KEY = "PoisonSlot"
local COLORS = {
	expiring = { 1, 0.70, 0.28 },
	missing = { 0.96, 0.36, 0.26 },
	poison = { 0.45, 0.88, 0.27 },
	badge = { 0.93, 0.79, 0.52 },
	count = { 1, 0.86, 0.42 },
	urgent = { 1, 0.27, 0.2 },
}
local PIXEL_COLOR = { 0.96, 0.36, 0.26, 1 }
local BRONZE = ns.BRONZE
ns.DEFAULT_POSITION = { point = "CENTER", x = 0, y = -140 }

local hud = CreateFrame("Frame", "PoisonSlotAlerts", UIParent)
hud:SetSize(BASE * 2 + 14, BASE + CAPTION)
hud:SetClampedToScreen(true)
hud:SetMovable(true)
hud:SetFrameStrata("MEDIUM")
hud.editModeName = "PoisonSlot Reminders"

-- snoozed[i] is "zone" (until the next loading screen) or "session" (until
-- that weapon is poisoned again or the UI reloads).
local tiles, clickers, snoozed = {}, {}, {}
local started, unlocked, editing, previewStart, dragging
local pendingLayout, combatDriver, appliedScale
local castingTile, expiryTimer
local layoutKey = "default"

local function animated()
	return ns.db.animations
end

local function demoMode()
	return unlocked or editing or previewStart ~= nil
end

---------------------------------------------------------------------------
-- Glow styles
---------------------------------------------------------------------------

local function hasProcArt()
	return C_Texture and C_Texture.GetAtlasInfo
		and C_Texture.GetAtlasInfo("UI-HUD-ActionBar-Proc-Loop-Flipbook") ~= nil or false
end

-- The style actually drawn for a Missing tile, after falling back for missing
-- libraries, missing art or animations being off.
local function glowStyle()
	local style = ns.db.alertGlow
	if style == "proc" and not (LCG and hasProcArt()) then style = "pixel" end
	if style == "pixel" and not LCG then style = "soft" end
	if not animated() and style ~= "none" then style = "static" end
	return style
end

local function stopGlow(tile)
	if tile.glowStyle == "proc" then
		LCG.ProcGlow_Stop(tile.top, GLOW_KEY)
	elseif tile.glowStyle == "pixel" then
		LCG.PixelGlow_Stop(tile.top, GLOW_KEY)
	end
	tile.breathe:Stop()
	tile.glow:SetAlpha(0.85)
	tile.glowStyle = nil
end

local function startGlow(tile)
	local style = glowStyle()
	if tile.glowStyle == style then return end
	stopGlow(tile)
	tile.glowStyle = style
	if style == "proc" then
		-- No start burst: on a reminder-sized icon it flashes about 3.5x too
		-- big before shrinking to the border. The tile has its own entrance.
		LCG.ProcGlow_Start(tile.top, { key = GLOW_KEY, frameLevel = 4, startAnim = false })
	elseif style == "pixel" then
		LCG.PixelGlow_Start(tile.top, PIXEL_COLOR, 8, 0.2, nil, 2, 1, 1, false, GLOW_KEY, 4)
	elseif style == "soft" then
		tile.breathe:Play()
	end
end

---------------------------------------------------------------------------
-- Position, size and layout
---------------------------------------------------------------------------

local function enabledHands()
	local list = {}
	for i, hand in ipairs(ns.hands) do
		if ns.db[hand.alertKey] then list[#list + 1] = i end
	end
	return list
end

local function currentPosition()
	local positions = ns.db.positions
	return positions[layoutKey] or positions.default or ns.DEFAULT_POSITION
end

local function place()
	local pos = currentPosition()
	hud:ClearAllPoints()
	hud:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

-- Text, badge, glow and animation toggles only touch unprotected regions, so
-- they apply at once, even in combat.
local function applyStyle()
	for _, tile in ipairs(tiles) do
		tile.caption:SetShown(ns.db.alertCaption)
		tile.badge:SetShown(ns.db.alertBadge)
		tile.badgeText:SetShown(ns.db.alertBadge)
		if tile.visible and tile.state == "missing" then
			stopGlow(tile)
			startGlow(tile)
		end
		if not animated() then
			tile.urgent:Stop()
			tile.icon:SetAlpha(1)
		end
	end
end

-- The reminder frame is sized for every enabled hand. The tiles themselves
-- are centered on it by how many are showing (see reflow).
local function arrange()
	local gap = ns.db.alertSpacing
	local caption = ns.db.alertCaption and CAPTION or 0
	local count = math.max(1, #enabledHands())
	if ns.db.alertLayout == "vertical" then
		hud:SetSize(BASE, count * (BASE + caption) + (count - 1) * gap)
	else
		hud:SetSize(count * BASE + (count - 1) * gap, BASE + caption)
	end
end

local function layoutStep()
	local caption = ns.db.alertCaption and CAPTION or 0
	if ns.db.alertLayout == "vertical" then
		return 0, -(BASE + caption + ns.db.alertSpacing), caption / 2
	end
	return BASE + ns.db.alertSpacing, 0, caption / 2
end

-- Offset from the reminder frame's center for the k-th of n showing tiles.
local function centeredOffset(k, n)
	local dx, dy, lift = layoutStep()
	local along = k - 1 - (n - 1) / 2
	return dx * along, dy * along + lift
end

local function moveTile(tile, x, y, slide)
	if tile.x == x and tile.y == y then return end
	tile.slide:Stop()
	local fromX, fromY = tile.x, tile.y
	tile.x, tile.y = x, y
	tile:ClearAllPoints()
	if slide and fromX and animated() then
		tile:SetPoint("CENTER", hud, "CENTER", fromX, fromY)
		tile.slideBy:SetOffset(x - fromX, y - fromY)
		tile.slide:Play()
	else
		tile:SetPoint("CENTER", hud, "CENTER", x, y)
	end
end

local function moveClicker(button, x, y)
	if button.x == x and button.y == y then return end
	button.x, button.y = x, y
	button:ClearAllPoints()
	button:SetPoint("CENTER", hud, "CENTER", x, y)
end

-- Centers the showing tiles: one sits in the middle, two spread out evenly.
-- The secure click layers can't move in combat, so during combat showing
-- tiles stay put and a new one lines up beside them (or over its frozen
-- click layer); everything recenters once combat ends.
local function reflow(states)
	local showing = {}
	for i in ipairs(tiles) do
		if states[i] then showing[#showing + 1] = i end
	end
	if not InCombatLockdown() then
		for k, i in ipairs(showing) do
			local x, y = centeredOffset(k, #showing)
			moveTile(tiles[i], x, y, tiles[i].visible)
			moveClicker(clickers[i], x, y)
		end
		return
	end
	local dx, dy = layoutStep()
	for _, i in ipairs(showing) do
		local tile = tiles[i]
		if not tile.visible then
			local x, y
			if clickers[i]:IsShown() and clickers[i].x then
				x, y = clickers[i].x, clickers[i].y
			else
				for _, j in ipairs(showing) do
					if j ~= i and tiles[j].visible and tiles[j].x then
						x, y = tiles[j].x + dx * (i - j), tiles[j].y + dy * (i - j)
						break
					end
				end
			end
			if not x then
				x, y = centeredOffset(1, 1)
			end
			moveTile(tile, x, y, false)
		end
	end
end

-- A secure visibility driver hides the reminders, click layers included, the
-- moment combat starts.
local function applyCombatVisibility()
	local want = ns.db.alertHideInCombat
	if want and not combatDriver then
		RegisterStateDriver(hud, "visibility", "[combat] hide; show")
		combatDriver = true
	elseif not want and combatDriver then
		UnregisterStateDriver(hud, "visibility")
		hud:Show()
		combatDriver = false
	end
end

local function applyLayout()
	applyStyle()
	if InCombatLockdown() then
		pendingLayout = true
		return
	end
	pendingLayout = false
	-- Keep the on-screen anchor steady when the icon size changes: saved
	-- offsets are in the reminders' own scaled units.
	local scale = ns.db.iconSize / BASE
	if appliedScale and appliedScale ~= scale then
		for _, pos in pairs(ns.db.positions) do
			pos.x, pos.y = pos.x * appliedScale / scale, pos.y * appliedScale / scale
		end
	end
	appliedScale = scale
	hud:SetScale(scale)
	arrange()
	place()
	applyCombatVisibility()
	hud:SetFrameStrata(demoMode() and "FULLSCREEN_DIALOG" or "MEDIUM")
end

local function savePosition(point, x, y, key)
	ns.db.positions[key or layoutKey] = { point = point, x = x, y = y }
end

local function finishDrag()
	if not dragging then return end
	hud:StopMovingOrSizing()
	dragging = false
	local scale = hud:GetScale()
	local x, y = hud:GetCenter()
	local cx, cy = UIParent:GetCenter()
	savePosition("CENTER", math.floor((x * scale - cx) / scale + 0.5), math.floor((y * scale - cy) / scale + 0.5))
	place()
end

---------------------------------------------------------------------------
-- Tiles
---------------------------------------------------------------------------

local function maskedColor(parent, layer, sublevel, inset, r, g, b, a)
	local texture = parent:CreateTexture(nil, layer, nil, sublevel)
	texture:SetPoint("TOPLEFT", -inset, inset)
	texture:SetPoint("BOTTOMRIGHT", inset, -inset)
	texture:SetColorTexture(r, g, b, a)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return texture
end

local function glowTexture(parent, sublevel, blend)
	local texture = parent:CreateTexture(nil, "OVERLAY", nil, sublevel)
	texture:SetTexture(GLOW)
	texture:SetPoint("TOPLEFT", -4, 4)
	texture:SetPoint("BOTTOMRIGHT", 4, -4)
	if blend then texture:SetBlendMode(blend) end
	return texture
end

local function addAlpha(group, target, from, to, duration, order, smoothing)
	local animation = group:CreateAnimation("Alpha")
	if target then animation:SetTarget(target) end
	animation:SetFromAlpha(from)
	animation:SetToAlpha(to)
	animation:SetDuration(duration)
	animation:SetOrder(order or 1)
	animation:SetSmoothing(smoothing or "OUT")
	return animation
end

local function addScale(group, from, to, duration, order, smoothing)
	local animation = group:CreateAnimation("Scale")
	animation:SetScaleFrom(from, from)
	animation:SetScaleTo(to, to)
	animation:SetDuration(duration)
	animation:SetOrder(order or 1)
	animation:SetSmoothing(smoothing or "OUT")
	animation:SetOrigin("CENTER", 0, 0)
	return animation
end

local function tileIcon(hand, tile)
	if tile.entry and tile.entry.icon then
		return tile.entry.icon
	end
	local wanted = tile.wanted
	return wanted and C_Item.GetItemIconByID and C_Item.GetItemIconByID(wanted) or ns.VIAL_ICON
end

local function paintGlow(tile)
	if tile.hovered then
		tile.glow:SetVertexColor(unpack(COLORS.poison))
		tile.hover:Show()
	else
		tile.glow:SetVertexColor(unpack(COLORS[tile.state or "missing"]))
		tile.hover:Hide()
	end
end

local function paintCaption(tile)
	if castingTile == tile then
		tile.caption:SetText("Applying…")
		tile.caption:SetTextColor(unpack(COLORS.poison))
	elseif tile.state == "expiring" then
		tile.caption:SetText("Expiring")
		tile.caption:SetTextColor(unpack(COLORS.expiring))
	else
		tile.caption:SetText("Missing")
		tile.caption:SetTextColor(unpack(COLORS.missing))
	end
end

local function formatCount(left)
	if left <= 0 then return "" end
	if left < TENTHS then return ("%.1f"):format(left) end
	return tostring(math.ceil(left))
end

local function resetCount(tile)
	tile.isUrgent = nil
	tile.count:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
	tile.count:SetTextColor(unpack(COLORS.count))
	tile.urgent:Stop()
	tile.icon:SetAlpha(1)
end

local function tickCountdown(tile, elapsed)
	tile.sinceTick = (tile.sinceTick or 0) + elapsed
	if tile.sinceTick < 0.05 then return end
	tile.sinceTick = 0
	local left = (tile.expiry or 0) - GetTime()
	tile.count:SetText(formatCount(left))
	local urgent = left <= URGENT
	if urgent ~= tile.isUrgent then
		if urgent then
			tile.isUrgent = true
			tile.count:SetFont(STANDARD_TEXT_FONT, 22, "THICKOUTLINE")
			tile.count:SetTextColor(unpack(COLORS.urgent))
			if animated() then tile.urgent:Play() end
		else
			resetCount(tile)
			tile.isUrgent = false
		end
	end
end

local function createTile(hand)
	local tile = CreateFrame("Frame", nil, hud)
	tile:SetSize(BASE, BASE)
	tile:Hide()

	-- Bronze rim, dark plate, then the poison artwork, all as rounded squares.
	maskedColor(tile, "BACKGROUND", 0, 3, 0, 0, 0, 0.55)
	maskedColor(tile, "BACKGROUND", 1, 2, BRONZE[1], BRONZE[2], BRONZE[3], 1)
	maskedColor(tile, "BACKGROUND", 2, 1, 0.04, 0.035, 0.03, 1)
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetAllPoints()
	tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local iconMask = tile:CreateMaskTexture()
	iconMask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	iconMask:SetAllPoints(tile.icon)
	tile.icon:AddMaskTexture(iconMask)

	tile.cooldown = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
	tile.cooldown:SetAllPoints(tile.icon)
	tile.cooldown:SetSwipeTexture(MASK)
	tile.cooldown:SetSwipeColor(0, 0, 0, 0.72)
	tile.cooldown:SetDrawEdge(false)
	tile.cooldown:SetDrawBling(false)
	tile.cooldown:SetHideCountdownNumbers(true)
	-- The tile draws its own countdown; tell OmniCC-style addons (OmniCC,
	-- ClassicCooldownCount, tullaCC) not to add a second one.
	tile.cooldown.noCooldownCount = true
	tile.cooldown:EnableMouse(false)

	-- Fills green while the poison is being applied.
	tile.castSwipe = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
	tile.castSwipe:SetAllPoints(tile.icon)
	tile.castSwipe:SetSwipeTexture(MASK)
	tile.castSwipe:SetSwipeColor(COLORS.poison[1], COLORS.poison[2], COLORS.poison[3], 0.45)
	tile.castSwipe:SetReverse(true)
	tile.castSwipe:SetDrawEdge(false)
	tile.castSwipe:SetDrawBling(false)
	tile.castSwipe:SetHideCountdownNumbers(true)
	tile.castSwipe:EnableMouse(false)

	local top = CreateFrame("Frame", nil, tile)
	top:SetAllPoints()
	top:SetFrameLevel(tile.castSwipe:GetFrameLevel() + 2)
	tile.top = top
	tile.glow = glowTexture(top, 0)
	tile.glow:SetAlpha(0.85)
	tile.hover = glowTexture(top, 1, "ADD")
	tile.hover:SetVertexColor(0.55, 1, 0.32)
	tile.hover:SetAlpha(0.5)
	tile.hover:Hide()
	tile.flash = glowTexture(top, 2, "ADD")
	tile.flash:SetAlpha(0)

	-- Text sits above any library glow drawn on the top frame.
	local text = CreateFrame("Frame", nil, tile)
	text:SetAllPoints()
	text:SetFrameLevel(top:GetFrameLevel() + 8)
	tile.count = text:CreateFontString(nil, "OVERLAY")
	tile.count:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
	tile.count:SetTextColor(unpack(COLORS.count))
	tile.count:SetPoint("CENTER", 0, 1)
	tile.count:SetShadowOffset(1, -1)

	local badge = maskedColor(text, "OVERLAY", 3, 0, 0.05, 0.04, 0.03, 0.92)
	badge:ClearAllPoints()
	badge:SetSize(22, 11)
	badge:SetPoint("CENTER", text, "BOTTOM", 0, 1)
	local badgeText = text:CreateFontString(nil, "OVERLAY")
	badgeText:SetFont(STANDARD_TEXT_FONT, 8, "")
	badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
	badgeText:SetTextColor(unpack(COLORS.badge))
	badgeText:SetText(hand.short)
	badgeText:SetDrawLayer("OVERLAY", 4)
	tile.badge, tile.badgeText = badge, badgeText

	tile.caption = text:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tile.caption:SetPoint("TOP", tile, "BOTTOM", 0, -7)
	tile.caption:SetShadowOffset(1, -1)

	-- Entrance: grow in from a smaller size while fading in.
	tile.intro = tile:CreateAnimationGroup()
	addAlpha(tile.intro, nil, 0, 1, 0.18)
	addScale(tile.intro, 0.7, 1, 0.24, 1, "OUT")

	-- Expiry: a single coral flare as the countdown turns into Missing.
	tile.flare = tile:CreateAnimationGroup()
	addScale(tile.flare, 1.15, 1, 0.35, 1, "OUT")
	addAlpha(tile.flare, tile.flash, 0.9, 0, 0.6, 1, "OUT")

	-- Final seconds: the artwork pulses like Blizzard's expiring buffs.
	tile.urgent = tile.icon:CreateAnimationGroup()
	tile.urgent:SetLooping("BOUNCE")
	addAlpha(tile.urgent, nil, 1, 0.45, 0.5, 1, "IN_OUT")

	-- Soft glow style: a slow breathe on the inner glow.
	tile.breathe = tile.glow:CreateAnimationGroup()
	tile.breathe:SetLooping("BOUNCE")
	addAlpha(tile.breathe, nil, 0.55, 0.95, 1.3, 1, "IN_OUT")

	-- Applied: a green flash, then the tile lifts away.
	tile.success = tile:CreateAnimationGroup()
	tile.success:SetToFinalAlpha(true)
	addAlpha(tile.success, tile.flash, 0, 1, 0.12, 1, "OUT")
	addScale(tile.success, 1, 1.22, 0.45, 1, "OUT")
	addAlpha(tile.success, nil, 1, 0, 0.3, 2, "IN")
	tile.success:SetScript("OnFinished", function()
		tile:Hide()
		tile:SetAlpha(1)
		tile.flash:SetAlpha(0)
	end)

	-- Quiet exit for every other reason (snoozed, rested, weapon removed).
	tile.outro = tile:CreateAnimationGroup()
	tile.outro:SetToFinalAlpha(true)
	addAlpha(tile.outro, nil, 1, 0, 0.2, 1, "IN")
	addScale(tile.outro, 1, 0.8, 0.2, 1, "IN")
	tile.outro:SetScript("OnFinished", function()
		tile:Hide()
		tile:SetAlpha(1)
	end)

	-- Recentering: a short slide to the new spot.
	tile.slide = tile:CreateAnimationGroup()
	tile.slideBy = tile.slide:CreateAnimation("Translation")
	tile.slideBy:SetDuration(0.22)
	tile.slideBy:SetSmoothing("OUT")
	local function settle()
		tile:ClearAllPoints()
		tile:SetPoint("CENTER", hud, "CENTER", tile.x or 0, tile.y or 0)
	end
	tile.slide:SetScript("OnFinished", settle)
	tile.slide:SetScript("OnStop", settle)

	tile.hand = hand
	return tile
end

local function showTile(tile)
	if tile.visible then return end
	tile.visible = true
	tile.outro:Stop()
	tile.success:Stop()
	tile.flash:SetAlpha(0)
	tile:SetAlpha(1)
	tile:Show()
	if animated() then
		tile.intro:Play()
	end
end

local function hideTile(tile, applied)
	if not tile.visible then return end
	tile.visible = false
	tile.state, tile.expiry, tile.hovered = nil, nil, nil
	tile:SetScript("OnUpdate", nil)
	stopGlow(tile)
	resetCount(tile)
	tile.intro:Stop()
	tile.flare:Stop()
	tile.castSwipe:SetCooldown(0, 0)
	if not animated() then
		tile:Hide()
	elseif applied then
		tile.success:Play()
	else
		tile.outro:Play()
	end
end

local function paintTile(tile, state, remaining)
	local previous = tile.state
	tile.state = state
	tile.icon:SetTexture(tileIcon(tile.hand, tile))
	if state == "expiring" then
		local expiry = GetTime() + remaining
		if not tile.expiry or math.abs(expiry - tile.expiry) > 0.25 then
			tile.cooldown:SetCooldown(expiry - COUNTDOWN, COUNTDOWN)
			tile.expiry = expiry
		end
		stopGlow(tile)
		tile:SetScript("OnUpdate", tickCountdown)
		tickCountdown(tile, 1)
	else
		if previous == "expiring" and animated() then
			tile.flare:Play()
		end
		tile.expiry = nil
		tile.cooldown:SetCooldown(0, 0)
		tile.count:SetText("")
		resetCount(tile)
		tile:SetScript("OnUpdate", nil)
		startGlow(tile)
	end
	paintGlow(tile)
	paintCaption(tile)
end

---------------------------------------------------------------------------
-- Clickable layer (secure)
---------------------------------------------------------------------------

-- The secure buttons can only be shown, hidden or retargeted out of combat.
-- During combat they keep whatever they were set to when combat started.
local function syncClickers()
	if not started then return end
	if InCombatLockdown() then return end
	local byID
	for i, hand in ipairs(ns.hands) do
		local tile, button = tiles[i], clickers[i]
		local active = tile.visible and tile.state and not demoMode()
		-- A reminder reapplies the last poison this hand got. Until one has been
		-- seen, it uses the hand's favorite.
		local entry, wanted = nil, ns.db.lastPoison[hand.key] or ns.db.favorites[hand.key]
		if active then
			if not byID then
				local _
				_, byID = ns.ScanBags()
			end
			if ns.db.lastPoison[hand.key] then
				entry = ns.ResolveLastPoison(hand, byID)
			else
				entry = ns.ResolveFavorite(hand, byID)
			end
		end
		tile.entry, tile.wanted = entry, wanted
		-- Left-click applies (suffix 1). Right-click has no secure action and
		-- only snoozes, in PostClick.
		if entry and ns.db.alertClick then
			button:SetAttribute("item1", "item:" .. entry.id)
			button:SetAttribute("type1", "item")
		else
			button:SetAttribute("type1", nil)
			button:SetAttribute("item1", nil)
		end
		if active then
			button:Show()
		else
			button:Hide()
			if tile.hovered then
				tile.hovered = nil
				paintGlow(tile)
			end
		end
		if tile.visible then
			tile.icon:SetTexture(tileIcon(hand, tile))
		end
	end
end

local function clickerTooltip(button, tile)
	if not ns.db.tooltips then return end
	local hand, entry, wanted = tile.hand, tile.entry, tile.wanted
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	if tile.state == "expiring" then
		GameTooltip:SetText(hand.label .. " poison is expiring", unpack(COLORS.expiring))
	else
		GameTooltip:SetText(hand.label .. " has no poison", unpack(COLORS.missing))
	end
	if entry and ns.db.alertClick then
		GameTooltip:AddDoubleLine("Left-click", "Apply " .. (entry.name or "poison"), 1, 0.82, 0, 0.6, 1, 0.45)
		GameTooltip:AddDoubleLine(" ", ("%d in bags"):format(entry.count), 1, 1, 1, 0.7, 0.7, 0.7)
	elseif ns.db.alertClick and wanted then
		local name = C_Item.GetItemNameByID(wanted)
		GameTooltip:AddLine(("No %s in your bags."):format(name or "matching poison"), 0.7, 0.7, 0.7, true)
	elseif ns.db.alertClick then
		GameTooltip:AddLine("Poison this weapon once and clicking here will reapply it.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:AddDoubleLine("Right-click", "Snooze until next loading screen", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine("Shift-right-click", "Silence until poisoned again", 1, 0.82, 0, 1, 1, 1)
	if InCombatLockdown() then
		GameTooltip:AddLine("Changes to this button wait until combat ends.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end

local refresh

local function createClicker(hand, tile, index)
	local button = CreateFrame("Button", "PoisonSlotAlertButton" .. hand.short, hud, "SecureActionButtonTemplate")
	button:SetSize(BASE, BASE)
	button:SetFrameLevel(tile:GetFrameLevel() + 20)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetAttribute("useOnKeyDown", false)
	button:SetAttribute("target-slot1", hand.slot)
	button:Hide()
	button:SetScript("OnEnter", function(self)
		if not tile.visible then return end
		tile.hovered = true
		paintGlow(tile)
		clickerTooltip(self, tile)
	end)
	button:SetScript("OnLeave", function()
		tile.hovered = nil
		if tile.visible then paintGlow(tile) end
		GameTooltip:Hide()
	end)
	button:SetScript("PostClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			snoozed[index] = IsShiftKeyDown() and "session" or "zone"
			GameTooltip:Hide()
			refresh()
		else
			tile.clickedAt = GetTime()
		end
	end)
	return button
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function quiet()
	return UnitIsDeadOrGhost("player") or UnitOnTaxi("player")
		or (ns.db.hideWhenResting and IsResting())
end

-- Returns the tile state for a hand, or nil plus whether the hand is coated.
local function handStatus(index, hand, now)
	if not ns.db[hand.alertKey] then
		return
	end
	if demoMode() then
		if index == 1 and ns.db.alertCountdown then
			local left = COUNTDOWN - ((now - (previewStart or now)) % PREVIEW_CYCLE)
			if left > 0 then return "expiring", left end
		end
		return "missing"
	end
	local state, remaining = ns.WeaponPoisonState(hand)
	local coated = state == "active" or state == "expiring"
	if coated then
		snoozed[index] = nil
	end
	if not ns.db.remindersEnabled or quiet() or snoozed[index] then
		return nil, false
	end
	if state == "missing" then
		return "missing"
	elseif state == "expiring" and ns.db.alertCountdown then
		return "expiring", remaining
	end
	return nil, coated
end

-- Plays once when a poison that was on the weapon runs out, not on login or
-- when a reminder reappears after leaving town.
local function noteRunOut(tile, index, hand)
	local state = ns.WeaponPoisonState(hand)
	if tile.coated and state == "missing" and ns.db.remindersEnabled and ns.db[hand.alertKey]
		and not demoMode() and not quiet() and not snoozed[index] and ns.PlayAlertSound then
		ns.PlayAlertSound(ns.db.alertSound)
	end
	if state then tile.coated = state == "active" or state == "expiring" end
end

refresh = function()
	if not started then return end
	local now = GetTime()
	if previewStart and not unlocked and not editing and now - previewStart >= PREVIEW_LENGTH then
		ns.EndPreview()
		return
	end
	local changed, soonest = false, nil
	local states, extras = {}, {}
	for i, hand in ipairs(ns.hands) do
		noteRunOut(tiles[i], i, hand)
		states[i], extras[i] = handStatus(i, hand, now)
	end
	reflow(states)
	for i in ipairs(ns.hands) do
		local tile = tiles[i]
		local state, extra = states[i], extras[i]
		if state then
			if not tile.visible or tile.state ~= state then changed = true end
			showTile(tile)
			paintTile(tile, state, extra)
			if state == "expiring" then
				soonest = math.min(soonest or extra, extra)
			end
		elseif tile.visible then
			changed = true
			hideTile(tile, extra == true)
		end
	end
	-- Switch to Missing right as the countdown ends instead of on the next tick.
	if expiryTimer then
		expiryTimer:Cancel()
		expiryTimer = nil
	end
	if soonest then
		expiryTimer = C_Timer.NewTimer(soonest + 0.05, refresh)
	end
	if changed then
		syncClickers()
	end
end

function ns.RefreshAlerts()
	if not started then return end
	refresh()
	syncClickers()
end

---------------------------------------------------------------------------
-- Move mode, Edit Mode and preview
---------------------------------------------------------------------------

-- Fallback mover for clients without Edit Mode support.
local mover = CreateFrame("Frame", nil, hud, "BackdropTemplate")
mover:SetPoint("TOPLEFT", -12, 28)
mover:SetPoint("BOTTOMRIGHT", 12, -6)
mover:SetBackdrop({
	bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
	edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
mover:SetBackdropColor(0.12, 0.09, 0.05, 0.55)
mover:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 1)
mover:SetFrameLevel(hud:GetFrameLevel() + 40)
mover:EnableMouse(true)
mover:EnableMouseWheel(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
local moverTitle = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
moverTitle:SetPoint("TOP", 0, -8)
moverTitle:SetText("PoisonSlot")
local moverHint = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
moverHint:SetPoint("TOP", mover, "BOTTOM", 0, -4)
moverHint:SetText("Drag to move. Mouse wheel nudges, Shift+wheel sideways.\nCtrl+right-click resets. Right-click locks.")
local moverDone = CreateFrame("Button", nil, mover, "UIPanelButtonTemplate")
moverDone:SetSize(80, 22)
moverDone:SetPoint("TOP", moverHint, "BOTTOM", 0, -4)
moverDone:SetText("Lock")
moverDone:SetScript("OnClick", function() ns.LockAlerts() end)
mover:SetScript("OnDragStart", function()
	if InCombatLockdown() then return end
	hud:StartMoving()
	dragging = true
end)
mover:SetScript("OnDragStop", finishDrag)
mover:SetScript("OnMouseUp", function(_, button)
	if button ~= "RightButton" then return end
	if IsControlKeyDown() then
		ns.ResetAlertPosition()
	else
		ns.LockAlerts()
	end
end)
mover:SetScript("OnMouseWheel", function(_, delta)
	if InCombatLockdown() then return end
	local pos = CopyTable(currentPosition())
	if IsShiftKeyDown() then
		pos.x = pos.x + delta
	else
		pos.y = pos.y + delta
	end
	savePosition(pos.point, pos.x, pos.y)
	place()
end)

local function enterDemo()
	applyLayout()
	syncClickers()
	refresh()
end

function ns.PreviewAlerts()
	if not started or InCombatLockdown() then return end
	if previewStart and not unlocked and not editing then
		ns.EndPreview()
		return
	end
	previewStart = GetTime()
	enterDemo()
end

function ns.EndPreview()
	if unlocked or editing then return end
	previewStart = nil
	applyLayout()
	refresh()
	syncClickers()
end

function ns.IsPreviewing()
	return previewStart ~= nil
end

local function editModeAvailable()
	return LEM and EditModeManagerFrame and ShowUIPanel and true or false
end
ns.EditModeAvailable = editModeAvailable

-- Opens Blizzard's Edit Mode when available, otherwise the built-in mover.
function ns.UnlockAlerts(useFallback)
	if not started or InCombatLockdown() then return end
	if SettingsPanel and SettingsPanel:IsShown() then
		HideUIPanel(SettingsPanel)
	end
	if editModeAvailable() and not useFallback then
		ShowUIPanel(EditModeManagerFrame)
		return
	end
	unlocked = true
	previewStart = previewStart or GetTime()
	mover:Show()
	enterDemo()
end

function ns.LockAlerts()
	if editing and editModeAvailable() then
		HideUIPanel(EditModeManagerFrame)
		return
	end
	if not unlocked then return end
	finishDrag()
	unlocked = false
	mover:Hide()
	previewStart = nil
	applyLayout()
	refresh()
	syncClickers()
end

function ns.ResetAlertPosition()
	ns.db.positions[layoutKey] = CopyTable(ns.DEFAULT_POSITION)
	applyLayout()
end

function ns.ApplyAlertLayout()
	if started then applyLayout() end
end

local function setupEditMode()
	if not LEM then return end
	LEM:AddFrame(hud, function(_, layoutName, point, x, y)
		savePosition(point, x, y, layoutName or "default")
	end, ns.DEFAULT_POSITION, "PoisonSlot Reminders")
	LEM:RegisterCallback("enter", function()
		if InCombatLockdown() then return end
		editing = true
		previewStart = GetTime()
		enterDemo()
	end)
	LEM:RegisterCallback("exit", function()
		editing = false
		previewStart = nil
		if not InCombatLockdown() then
			applyLayout()
			refresh()
			syncClickers()
		end
	end)
	LEM:RegisterCallback("layout", function(layoutName)
		layoutKey = layoutName or "default"
		-- A layout without its own position starts from the last one used.
		if not ns.db.positions[layoutKey] and ns.db.positions.default then
			ns.db.positions[layoutKey] = CopyTable(ns.db.positions.default)
		end
		if started then applyLayout() end
	end)
	if ns.EditModeSettings then
		LEM:AddFrameSettings(hud, ns.EditModeSettings(LEM))
	end
	if LEM.AddFrameSettingsButton then
		LEM:AddFrameSettingsButton(hud, {
			text = "More options",
			click = function()
				HideUIPanel(EditModeManagerFrame)
				ns.OpenOptions()
			end,
		})
	end
end

function ns.RefreshEditModeDialog()
	if LEM and LEM.RefreshFrameSettings and LEM:IsInEditMode() then
		LEM:RefreshFrameSettings(hud)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function onCast(event)
	if event == "UNIT_SPELLCAST_START" then
		local now = GetTime()
		for _, tile in ipairs(tiles) do
			if tile.visible and tile.clickedAt and now - tile.clickedAt < 0.6 then
				local _, _, _, startMS, endMS = UnitCastingInfo("player")
				if startMS and endMS then
					castingTile = tile
					tile.castSwipe:SetCooldown(startMS / 1000, (endMS - startMS) / 1000)
					paintCaption(tile)
				end
			end
		end
	elseif castingTile then
		local tile = castingTile
		castingTile = nil
		tile.castSwipe:SetCooldown(0, 0)
		if tile.visible then paintCaption(tile) end
	end
end

hud:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- Fires just before combat lockdown, while protected changes still work.
		if unlocked then ns.LockAlerts() elseif previewStart and not editing then ns.EndPreview() end
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingLayout then applyLayout() end
		refresh()
		syncClickers()
		return
	elseif event == "BAG_UPDATE_DELAYED" or event == "ITEM_DATA_LOAD_RESULT" then
		syncClickers()
		return
	elseif event:find("^UNIT_SPELLCAST_") then
		onCast(event)
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		for i, kind in pairs(snoozed) do
			if kind == "zone" then snoozed[i] = nil end
		end
	end
	refresh()
end)

ns.OnLogin(function()
	for i, hand in ipairs(ns.hands) do
		tiles[i] = createTile(hand)
		clickers[i] = createClicker(hand, tiles[i], i)
	end
	started = true
	-- If Edit Mode support fails on this client, fall back to the built-in mover.
	if LEM and not pcall(setupEditMode) then
		LEM = nil
	end
	applyLayout()
	for _, event in ipairs({
		"PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_UPDATE_RESTING",
		"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
		"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT",
	}) do
		hud:RegisterEvent(event)
	end
	hud:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	for _, event in ipairs({ "START", "STOP", "FAILED", "INTERRUPTED" }) do
		hud:RegisterUnitEvent("UNIT_SPELLCAST_" .. event, "player")
	end
	C_Timer.NewTicker(1, refresh)
	refresh()
end)
