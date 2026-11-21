-- Options under Esc > Options > AddOns > PoisonSlot, built from Blizzard's
-- native settings controls so it is searchable and has a Defaults button. The
-- layout options are also offered in the reminders' Edit Mode dialog.
local _, ns = ...

local category, layout
local settings = {}
local fromEditMode

local GLOWS = {
	{ value = "proc", text = "Proc glow", tooltip = "The action bar's \"use this now\" glow." },
	{ value = "pixel", text = "Pixel border", tooltip = "Thin lines that run around the reminder." },
	{ value = "soft", text = "Soft pulse", tooltip = "A slow, gentle pulse on the reminder's own glow." },
	{ value = "none", text = "None", tooltip = "No extra glow." },
}
local LAYOUTS = {
	{ value = "horizontal", text = "Horizontal" },
	{ value = "vertical", text = "Vertical" },
}

local function rogueOnly(action)
	return function()
		if not ns.isRogue then
			ns.Print("Reminders are only available on Rogues.")
			return
		end
		action()
	end
end

local function refreshAlerts()
	if ns.RefreshAlerts then ns.RefreshAlerts() end
end

local function applyAlertLayout()
	if ns.ApplyAlertLayout then ns.ApplyAlertLayout() end
	refreshAlerts()
	-- Rebuilding the dialog mid-drag would interrupt its slider.
	if not fromEditMode and ns.RefreshEditModeDialog then ns.RefreshEditModeDialog() end
end

local function refreshWeaponButtons()
	if ns.RefreshWeaponButtons then ns.RefreshWeaponButtons() end
end

local function register(key, varType, name, default, onChange)
	local setting = Settings.RegisterAddOnSetting(category, "PoisonSlot_" .. key, key, ns.db, varType, name, default)
	if onChange then
		Settings.SetOnValueChangedCallback("PoisonSlot_" .. key, onChange)
	end
	settings[key] = setting
	return setting
end

-- Changes an option through its registered setting, so the options panel and
-- the Edit Mode dialog always agree and change callbacks run once.
function ns.SetOption(key, value)
	fromEditMode = true
	local setting = settings[key]
	if setting and setting.SetValue then
		setting:SetValue(value)
	else
		ns.db[key] = value
		applyAlertLayout()
	end
	fromEditMode = false
end

-- Grays a control out while its parent checkbox is off.
local function dependsOn(initializer, parent, parentKey)
	if parent and initializer and initializer.SetParentInitializer then
		initializer:SetParentInitializer(parent, function() return ns.db[parentKey] end)
	end
	return initializer
end

local function checkbox(key, name, tooltip, onChange, parent, parentKey, default)
	if default == nil then default = true end
	local setting = register(key, Settings.VarType.Boolean, name, default, onChange)
	return dependsOn(Settings.CreateCheckbox(category, setting, tooltip), parent, parentKey)
end

local function dropdown(key, name, default, choices, tooltip, onChange, parent, parentKey)
	local setting = register(key, Settings.VarType.String, name, default, onChange)
	local initializer = Settings.CreateDropdown(category, setting, function()
		local container = Settings.CreateControlTextContainer()
		for _, choice in ipairs(type(choices) == "function" and choices() or choices) do
			container:Add(choice.value, choice.text, choice.tooltip)
		end
		return container:GetData()
	end, tooltip)
	return dependsOn(initializer, parent, parentKey)
end

local function slider(key, name, default, min, max, step, format, tooltip, onChange)
	local setting = register(key, Settings.VarType.Number, name, default, onChange)
	local options = Settings.CreateSliderOptions(min, max, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return format:format(value)
	end)
	return Settings.CreateSlider(category, setting, options, tooltip)
end

local function header(text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function button(name, text, onClick, tooltip)
	layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
end

local function soundChoices()
	local list = { { value = "none", text = "None" } }
	for _, sound in ipairs(ns.SOUNDS) do
		list[#list + 1] = { value = sound.key, text = sound.label }
	end
	local media = ns.SharedMedia()
	if media then
		for _, name in ipairs(media:List("sound")) do
			if name ~= "None" then
				list[#list + 1] = { value = "lsm:" .. name, text = name }
			end
		end
	end
	return list
end

ns.OnLoad(function()
	category, layout = Settings.RegisterVerticalLayoutCategory("PoisonSlot")
	layout = layout or SettingsPanel:GetLayout(category)

	header("General")

	checkbox("animations", "Animations",
		"Animate reminders and the poison menu. When off, everything appears and disappears instantly.",
		applyAlertLayout)
	checkbox("tooltips", "Tooltips", "Show PoisonSlot's tooltips on reminders, vials and the poison menu.")

	header("Reminders")

	local enabled = checkbox("remindersEnabled", "Show reminders",
		"Show an on-screen reminder when a weapon's poison is missing or about to run out.", refreshAlerts)
	local function child(key, name, tooltip, onChange, default)
		return checkbox(key, name, tooltip, onChange or refreshAlerts, enabled, "remindersEnabled", default)
	end

	child("alertMainHand", "Main hand", "Remind you about the main-hand weapon.", applyAlertLayout)
	child("alertOffHand", "Off hand", "Remind you about the off-hand weapon.", applyAlertLayout)
	child("alertCountdown", "Countdown before it runs out",
		("Count down the final %d seconds of a poison. When off, the reminder only appears once the poison is gone.")
			:format(ns.COUNTDOWN))
	child("alertClick", "Click to reapply",
		"Left-click a reminder to reapply the last poison you put on that weapon, without opening the "
			.. "Character panel. Until you've poisoned it once, it uses the hand's starred favorite.")
	child("hideWhenResting", "Quiet in towns and inns", "Hide reminders while you are in a rested area.")
	child("alertHideInCombat", "Hide in combat",
		"Hide reminders while you are in combat. They come back as soon as combat ends.", applyAlertLayout, false)
	dropdown("alertSound", "Sound when a poison runs out", "none", soundChoices,
		"Play a sound once when a poison wears off a weapon. Choosing a sound plays it.", function()
			ns.PlayAlertSound(ns.db.alertSound)
		end, enabled, "remindersEnabled")

	header("Reminder appearance")

	slider("iconSize", "Icon size", 40, 24, 80, 2, "%dpx", "Size of each reminder icon.", applyAlertLayout)
	slider("alertSpacing", "Spacing", 14, 0, 40, 1, "%dpx", "Space between the two reminders.", applyAlertLayout)
	dropdown("alertLayout", "Layout", "horizontal", LAYOUTS, "Place the reminders side by side or stacked.",
		applyAlertLayout)
	dropdown("alertGlow", "Missing glow", "proc", GLOWS,
		"How a reminder calls for attention once a poison is gone.", applyAlertLayout)
	checkbox("alertCaption", "Status text", "Show Expiring, Missing or Applying under each reminder.",
		applyAlertLayout)
	checkbox("alertBadge", "Hand badges", "Show the MH and OH label on each reminder.", applyAlertLayout)

	button("Preview reminders", "Preview", rogueOnly(function() ns.PreviewAlerts() end),
		"Show the reminders with your current settings, including the countdown. Click again to stop.")
	button("Move reminders", "Move", rogueOnly(function() ns.UnlockAlerts() end),
		"Open Edit Mode and drag the reminders where you want them. Select them there for more layout options.")
	button("Reset position", "Reset", rogueOnly(function() ns.ResetAlertPosition() end),
		"Move the reminders back below the center of the screen.")

	header("Character panel")

	local buttons = checkbox("weaponButtons", "Poison buttons on weapon slots",
		"Show the poison vial on each weapon slot. Left-click it to pick a poison.", refreshWeaponButtons)
	checkbox("vialRightClick", "Right-click vial to apply favorite",
		"Right-click a weapon slot's vial to apply that hand's favorite poison.", nil, buttons, "weaponButtons")
	button("Clear favorites", "Clear", function()
		wipe(ns.db.favorites)
		refreshAlerts()
		refreshWeaponButtons()
		ns.Print("Cleared this character's favorite poisons.")
	end, "Forget the starred poison for both hands on this character.")

	Settings.RegisterAddOnCategory(category)
end)

-- Settings shown when the reminders are selected in Edit Mode.
function ns.EditModeSettings(lib)
	local types = lib.SettingType
	local function value(key)
		return function() return ns.db[key] end
	end
	local function setter(key)
		return function(_, v) ns.SetOption(key, v) end
	end
	local function pixels(v) return ("%dpx"):format(v) end
	return {
		{ kind = types.Slider, name = "Icon size", default = 40, get = value("iconSize"), set = setter("iconSize"),
			minValue = 24, maxValue = 80, valueStep = 2, formatter = pixels },
		{ kind = types.Slider, name = "Spacing", default = 14, get = value("alertSpacing"), set = setter("alertSpacing"),
			minValue = 0, maxValue = 40, valueStep = 1, formatter = pixels },
		{ kind = types.Dropdown, name = "Layout", default = "horizontal", get = value("alertLayout"),
			set = setter("alertLayout"), values = LAYOUTS },
		{ kind = types.Dropdown, name = "Missing glow", default = "proc", get = value("alertGlow"),
			set = setter("alertGlow"), values = GLOWS },
		{ kind = types.Checkbox, name = "Status text", default = true, get = value("alertCaption"),
			set = setter("alertCaption") },
		{ kind = types.Checkbox, name = "Hand badges", default = true, get = value("alertBadge"),
			set = setter("alertBadge") },
	}
end

function ns.OpenOptions()
	if category then
		Settings.OpenToCategory(category:GetID())
	end
end
