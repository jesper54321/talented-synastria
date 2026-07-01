local Talented = _G.Talented
local L = LibStub("AceLocale-3.0"):GetLocale("Talented")

Talented.max_talent_points = 71

local function BuildSynastriaDefaultPerksDefaults()
	local simple_ids = {}
	for _, entry in ipairs(Talented.SYNASTRIA_DEFAULT_PERK_SIMPLE) do
		simple_ids[entry.id] = true
	end
	local automatic_buffs = {}
	for _, s in ipairs(Talented.SYNASTRIA_DEFAULT_AUTOMATIC_BUFFS) do
		automatic_buffs[s] = true
	end
	local misc_options = {}
	for _, s in ipairs(Talented.SYNASTRIA_DEFAULT_MISC_OPTIONS) do
		misc_options[s] = true
	end
	local tracking = {}
	for _, s in ipairs(Talented.SYNASTRIA_DEFAULT_TRACKING) do
		tracking[s] = true
	end
	return {
		enabled = true,
		prestige_attune_mastery_excess_only = true,
		simple_ids = simple_ids,
		automatic_buffs = automatic_buffs,
		misc_options = misc_options,
		tracking = tracking
	}
end

local function BuildSynastriaDefaultPerksOptionArgs()
	local args = {
		master = {
			type = "toggle",
			name = L["Apply default Synastria perks with presets"],
			desc = L["When enabled, the toggles below run when you import a Synastria build/preset or SBM perk string (not on login). Only enables perks that are off; nothing is turned off."],
			order = 1,
			width = "full",
			get = function()
				return Talented.db.profile.synastria_default_perks.enabled
			end,
			set = function(_, v)
				Talented.db.profile.synastria_default_perks.enabled = v and true or false
			end
		},
		h_simple = {
			type = "header",
			name = L["Perks (by ID)"],
			order = 10
		}
	}
	local order = 10
	for _, entry in ipairs(Talented.SYNASTRIA_DEFAULT_PERK_SIMPLE) do
		order = order + 1
		args["simple_" .. entry.id] = {
			type = "toggle",
			name = entry.name,
			desc = L["When importing a build/preset, try to enable this perk if it is off (same click queue as build import)."],
			order = order,
			width = "full",
			arg = entry.id,
			get = function(info)
				local id = info.arg
				local t = Talented.db.profile.synastria_default_perks.simple_ids
				return t[id] and true or false
			end,
			set = function(info, v)
				local id = info.arg
				Talented.db.profile.synastria_default_perks.simple_ids[id] = v and true or false
			end
		}
	end
	order = order + 1
	args.h_buffs = {
		type = "header",
		name = L["Automatic Buffs (PerkOptions)"],
		order = order
	}
	for i, name in ipairs(Talented.SYNASTRIA_DEFAULT_AUTOMATIC_BUFFS) do
		order = order + 1
		args["buff_" .. i] = {
			type = "toggle",
			name = name,
			desc = L["Call ChangePerkOption for this sub-option when enabled."],
			order = order,
			width = "full",
			arg = name,
			get = function(info)
				local key = info.arg
				local t = Talented.db.profile.synastria_default_perks.automatic_buffs
				return t[key] and true or false
			end,
			set = function(info, v)
				local key = info.arg
				Talented.db.profile.synastria_default_perks.automatic_buffs[key] = v and true or false
			end
		}
	end
	order = order + 1
	args.h_misc = {
		type = "header",
		name = L["Misc Options (PerkOptions)"],
		order = order
	}
	for i, name in ipairs(Talented.SYNASTRIA_DEFAULT_MISC_OPTIONS) do
		order = order + 1
		args["misc_" .. i] = {
			type = "toggle",
			name = name,
			desc = L["Call ChangePerkOption for this sub-option when enabled."],
			order = order,
			width = "full",
			arg = name,
			get = function(info)
				local key = info.arg
				local t = Talented.db.profile.synastria_default_perks.misc_options
				return t[key] and true or false
			end,
			set = function(info, v)
				local key = info.arg
				Talented.db.profile.synastria_default_perks.misc_options[key] = v and true or false
			end
		}
	end
	order = order + 1
	args.h_track = {
		type = "header",
		name = L["Tracking (PerkOptions)"],
		order = order
	}
	for i, name in ipairs(Talented.SYNASTRIA_DEFAULT_TRACKING) do
		order = order + 1
		args["track_" .. i] = {
			type = "toggle",
			name = name,
			desc = L["Call ChangePerkOption for Tracking when enabled."],
			order = order,
			width = "full",
			arg = name,
			get = function(info)
				local key = info.arg
				local t = Talented.db.profile.synastria_default_perks.tracking
				return t[key] and true or false
			end,
			set = function(info, v)
				local key = info.arg
				Talented.db.profile.synastria_default_perks.tracking[key] = v and true or false
			end
		}
	end
	order = order + 1
	args.h_prestige = {
		type = "header",
		name = L["Prestige (PerkOption)"],
		order = order
	}
	order = order + 1
	args.prestige_attune_mastery_excess_only = {
		type = "toggle",
		name = L["Prestige: Attune Mastery — Excess Only"],
		desc = L["When importing a build/preset, runs ChangePerkOption(\"Prestige: Attune Mastery\", \"Excess Only\", true, false)."],
		order = order,
		width = "full",
		get = function()
			return Talented.db.profile.synastria_default_perks.prestige_attune_mastery_excess_only
		end,
		set = function(_, v)
			Talented.db.profile.synastria_default_perks.prestige_attune_mastery_excess_only = v and true or false
		end
	}
	return args
end

Talented.defaults = {
	profile = {
		confirmlearn = false,
		level_cap = true,
		show_level_req = true,
		offset = 48,
		scale = 1,
		add_bottom_offset = true,
		framepos = {},
		glyph_on_talent_swap = "active",
		restore_bars = false,
		debug_classswitch = false,
		synastria_default_perks = BuildSynastriaDefaultPerksDefaults()
	},
	global = {
		templates = {},
		communityBuilds = {}
	},
	char = {
		specNames = {},
		specIconTabs = {},
		specIconPaths = {},
		targets = {}
	}
}

function Talented:SetOption(info, value)
	local name = info[#info]
	self.db.profile[name] = value
	local arg = info.arg
	if arg then
		self[arg](self)
	end
end

function Talented:GetOption(info)
	local name = info[#info]
	return self.db.profile[name]
end

function Talented:MustNotConfirmLearn()
	return not self.db.profile.confirmlearn
end

Talented.options = {
	desc = L["Talented - Talent Editor"],
	type = "group",
	childGroups = "tab",
	handler = Talented,
	get = "GetOption",
	set = "SetOption",
	args = {
		options = {
			name = L["Options"],
			desc = L["General Options for Talented."],
			type = "group",
			order = 1,
			args = {
				header1 = {
					type = "header",
					name = L["General options"],
					order = 1
				},
				always_edit = {
					type = "toggle",
					name = L["Always edit"],
					desc = L["Always allow templates and the current build to be modified, instead of having to Unlock them first."],
					arg = "UpdateView",
					order = 2
				},
				confirmlearn = {
					type = "toggle",
					name = L["Confirm Learning"],
					desc = L["Ask for user confirmation before learning any talent."],
					order = 3
				},
				always_call_learn_talents = {
					type = "toggle",
					name = L["Always try to learn talent"],
					desc = L["Always call the underlying API when a user input is made, even when no talent should be learned from it."],
					disabled = "MustNotConfirmLearn",
					order = 4
				},
				level_cap = {
					type = "toggle",
					name = L["Talent cap"],
					desc = L["Restrict templates to a maximum of %d points."]:format(Talented.max_talent_points),
					arg = "UpdateView",
					order = 5
				},
				show_level_req = {
					type = "toggle",
					name = L["Level restriction"],
					desc = L["Show the required level for the template, instead of the number of points."],
					arg = "UpdateView",
					order = 6
				},
				hook_inspect_ui = {
					type = "toggle",
					name = L["Hook Inspect UI"],
					desc = L["Hook the Talent Inspection UI."],
					arg = "CheckHookInspectUI",
					order = 7
				},
				show_url_in_chat = {
					type = "toggle",
					name = L["Output URL in Chat"],
					desc = L["Directly outputs the URL in Chat instead of using a Dialog."],
					order = 8
				},
				restore_bars = {
					type = "toggle",
					name = L["Restore bars with ABS"],
					desc = L["If enabled, action bars will be restored automatically after successful respec. Applied template name until first dash is used as parameter (lower case, trailing space removed).\nRequires ABS addon to work."],
					order = 9
				},
				header2 = {
					type = "header",
					name = L["Glyph frame options"],
					order = 10
				},
				glyph_on_talent_swap = {
					name = L["Glyph frame policy on spec swap"],
					desc = L["Select the way the glyph frame handle spec swaps."],
					type = "select",
					order = 11,
					width = "double",
					values = {
						keep = L["Keep the shown spec"],
						swap = L["Swap the shown spec"],
						active = L["Always show the active spec after a change"]
					}
				},
				header3 = {
					type = "header",
					name = L["Display options"],
					order = 12
				},
				offset = {
					type = "range",
					name = L["Icon offset"],
					desc = L["Distance between icons."],
					arg = "ReLayout",
					order = 13,
					min = 42,
					max = 64,
					step = 1
				},
				scale = {
					type = "range",
					name = L["Frame scale"],
					desc = L["Overall scale of the Talented frame."],
					arg = "ReLayout",
					order = 14,
					min = 0.5,
					max = 1.0,
					step = 0.01
				},
				add_bottom_offset = {
					type = "toggle",
					name = L["Add bottom offset"],
					desc = L["Add some space below the talents to show the bottom information."],
					arg = "ReLayout",
					order = 15
				}
			}
		},
		synastria_defaults = {
			name = L["Synastria defaults"],
			desc = L["Default Synastria perks and PerkOptions applied when importing builds/presets."],
			type = "group",
			order = 100,
			args = BuildSynastriaDefaultPerksOptionArgs()
		},
		apply = {
			name = "Apply",
			desc = "Apply the specified template",
			type = "input",
			dialogHidden = true,
			order = 99,
			set = function(_, name)
				local template = Talented.db.global.templates[name]
				if not template then
					Talented:Print(L['Can not apply, unknown template "%s"'], name)
					return
				end
				Talented:SetTemplate(template)
				Talented:SetMode "apply"
			end
		}
	}
}

function Talented:ReLayout()
	self:ViewsReLayout(true)
end

local function mergeSavedTable(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			dst[k] = v
		elseif type(v) == "table" and type(dst[k]) == "table" then
			mergeSavedTable(dst[k], v)
		end
	end
end

function Talented:LegacyCharKey()
	local name = UnitName("player")
	local realm = GetRealmName()
	if not name or not realm then
		return
	end
	return name .. " - " .. realm
end

function Talented:BindGuidStorage()
	local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
	if type(guid) ~= "string" or guid == "" then
		return false
	end

	local db = self.db
	local sv = db and db.sv
	if not sv then
		return false
	end

	local legacy = self:LegacyCharKey()

	sv.char = sv.char or {}
	sv.profiles = sv.profiles or {}
	sv.profileKeys = sv.profileKeys or {}

	if legacy and legacy ~= guid then
		if sv.char[legacy] then
			sv.char[guid] = sv.char[guid] or {}
			mergeSavedTable(sv.char[guid], sv.char[legacy])
			sv.char[legacy] = nil
		end
		if sv.profiles[legacy] then
			sv.profiles[guid] = sv.profiles[guid] or {}
			mergeSavedTable(sv.profiles[guid], sv.profiles[legacy])
			sv.profiles[legacy] = nil
		end
		sv.profileKeys[legacy] = nil
	end

	sv.char[guid] = sv.char[guid] or {}
	sv.profiles[guid] = sv.profiles[guid] or {}
	sv.profileKeys[guid] = guid

	if db.keys.char ~= guid then
		db.keys.char = guid
		rawset(db, "char", nil)
	end
	if db.keys.profile ~= guid then
		db.keys.profile = guid
		rawset(db, "profile", nil)
	end

	return true
end

function Talented:EnsureDB()
	if self.db then
		self:BindGuidStorage()
		return true
	end

	local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
	if type(guid) ~= "string" or guid == "" then
		return false
	end

	self.db = LibStub("AceDB-3.0-Talented"):New("TalentedDB_Guid", self.defaults)
	if self.UpgradeOptions then
		self:UpgradeOptions()
	end
	if self.LoadTemplates then
		self:LoadTemplates()
	end

	if not self.dbOptionsRegistered then
		local AceDBOptions = LibStub("AceDBOptions-3.0", true)
		if AceDBOptions then
			self.options.args.profiles = AceDBOptions:GetOptionsTable(self.db)
			self.options.args.profiles.order = 200
		end
		self.dbOptionsRegistered = true
	end

	return true
end

function Talented:UpgradeOptions()
	self:BindGuidStorage()
	local p = self.db.profile
	if p.point or p.offsetx or p.offsety then
		local opts = {
			anchor = p.point or "CENTER",
			anchorTo = p.point or "CENTER",
			x = p.offsetx or 0,
			y = p.offsety or 0
		}
		p.framepos.TalentedFrame = opts
		p.point, p.offsetx, p.offsety = nil, nil, nil
	end
	local c = self.db.char
	if c.target then
		c.targets[1] = c.target
		c.target = nil
	end
	c.specNames = c.specNames or {}
	if p.specNames then
		for key, name in pairs(p.specNames) do
			local tg = type(key) == "number" and key
			if not tg and type(key) == "string" then
				tg = tonumber(key:match(":(%d+)$"))
			end
			if tg and type(name) == "string" and name ~= "" and not c.specNames[tg] then
				c.specNames[tg] = name
			end
		end
		p.specNames = nil
	end
	c.specIconTabs = c.specIconTabs or {}
	c.specIconPaths = c.specIconPaths or {}
	if p.specIconTabs then
		for key, tabIndex in pairs(p.specIconTabs) do
			local baseKey = type(key) == "string" and key:match("(spec%d+|petspec1)$")
			if baseKey and type(tabIndex) == "number" and not c.specIconTabs[baseKey] then
				c.specIconTabs[baseKey] = tabIndex
			end
		end
		p.specIconTabs = nil
	end
	if p.specIconPaths then
		for key, iconPath in pairs(p.specIconPaths) do
			local baseKey = type(key) == "string" and key:match("(spec%d+|petspec1)$")
			if baseKey and type(iconPath) == "string" and iconPath ~= "" and not c.specIconPaths[baseKey] then
				c.specIconPaths[baseKey] = iconPath
			end
		end
		p.specIconPaths = nil
	end
	local g = self.db.global
	if not g.communityBuilds then
		g.communityBuilds = {}
	end
	self.UpgradeOptions = nil
end

function Talented:SaveFramePosition(frame)
	local db = self.db.profile.framepos
	local name = frame:GetName()

	local data, _ = db[name]
	if not data then
		data = {}
		db[name] = data
	end
	data.anchor, _, data.anchorTo, data.x, data.y = frame:GetPoint(1)
end

function Talented:LoadFramePosition(frame)
	if not self.db then
		self:EnsureDB()
	end
	local data = self.db.profile.framepos[frame:GetName()]
	if data and data.anchor then
		frame:ClearAllPoints()
		frame:SetPoint(data.anchor, UIParent, data.anchorTo, data.x, data.y)
	else
		frame:SetPoint "CENTER"
		self:SaveFramePosition(frame)
	end
end

local function BaseFrame_OnMouseDown(self)
	if self.OnMouseDown then
		self:OnMouseDown()
	end
	self:StartMoving()
end

local function BaseFrame_OnMouseUp(self)
	self:StopMovingOrSizing()
	Talented:SaveFramePosition(self)
	if self.OnMouseUp then
		self:OnMouseUp()
	end
end

function Talented:SetFrameLock(frame, locked)
	local db = self.db.profile.framepos
	local name = frame:GetName()
	local data = db[name]
	if not data then
		data = {}
		db[name] = data
	end
	if locked == nil then
		locked = data.locked
	elseif locked == false then
		locked = nil
	end
	data.locked = locked
	if locked then
		frame:SetMovable(false)
		frame:SetScript("OnMouseDown", nil)
		frame:SetScript("OnMouseUp", nil)
	else
		frame:SetMovable(true)
		frame:SetScript("OnMouseDown", BaseFrame_OnMouseDown)
		frame:SetScript("OnMouseUp", BaseFrame_OnMouseUp)
	end
	frame:SetClampedToScreen(true)
end

function Talented:GetFrameLock(frame)
	local data = self.db.profile.framepos[frame:GetName()]
	return data and data.locked
end
