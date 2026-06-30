local Talented = LibStub("AceAddon-3.0"):NewAddon("Talented", "AceEvent-3.0", "AceHook-3.0", "AceConsole-3.0", "AceComm-3.0", "AceSerializer-3.0")
_G.Talented = Talented

local L = LibStub("AceLocale-3.0"):GetLocale("Talented")

local CLASS_BY_ID = {
	[1] = "WARRIOR",
	[2] = "PALADIN",
	[3] = "HUNTER",
	[4] = "ROGUE",
	[5] = "PRIEST",
	[6] = "DEATHKNIGHT",
	[7] = "SHAMAN",
	[8] = "MAGE",
	[9] = "WARLOCK",
	[11] = "DRUID"
}

local CLASS_ID_BY_NAME = {}
for classId, className in pairs(CLASS_BY_ID) do
	CLASS_ID_BY_NAME[className] = classId
end

function Talented:GetClassIdByName(className)
	return CLASS_ID_BY_NAME[className]
end

Talented.SYNASTRIA_DEFAULT_PERK_SIMPLE = {
	{id = 1042, name = "Automatic Bank"},
	{id = 855, name = "Automatic Fishing"},
	{id = 996, name = "Automatic Next Melee"},
	{id = 1602, name = "Automatic Shapeshift"},
	{id = 1157, name = "Disable Item Refund"},
	{id = 909, name = "Dungeon Event Speedup"},
	{id = 806, name = "Instant Windrider"},
	{id = 778, name = "Less Annoying Buffs"},
	{id = 816, name = "Weapon Enchant Duration"},
	{id = 758, name = "Tracking"}
}

Talented.SYNASTRIA_DEFAULT_AUTOMATIC_BUFFS = {
	"DK: Horn of Winter",
	"Druid: Mark of the Wild",
	"Druid: Thorns",
	"Mage: Arcane Intellect",
	"Paladin: Blessing of Kings",
	"Priest: Divine Spirit",
	"Priest: Fortitude",
	"Priest: Shadow Protection",
	"Shaman: Water Breathing",
	"Warlock: Detect Invisibility",
	"Warrior: Commanding Shout"
}

Talented.SYNASTRIA_DEFAULT_MISC_OPTIONS = {
	"AH Attunable",
	"Notify WG",
	"Always Show Affix",
	"Stop Crafting if Forged",
	"Notify on Forged",
	"Don't allow destroy favorited",
	"AH hide attuned"
}

Talented.SYNASTRIA_DEFAULT_TRACKING = {"Minerals", "Herbs"}

local function GetCacheKey(talentGroup)
    local characterName = UnitName("player")
    local realmName = GetRealmName()
    if not characterName or not realmName then
        return talentGroup -- Fallback if called before player data is fully loaded
    end
    return string.format("%s-%s:%d", characterName, realmName, talentGroup)
end


function Talented:IsSynastriaDataReady()
	if type(GetCustomGameData) ~= "function" then
		return true
	end
	local ok, value = pcall(GetCustomGameData, 41, 0)
	return ok and (tonumber(value) or 0) ~= 0
end

function Talented:RunDeferredSynastriaInit()
	if self:IsCustomTalentEnvironment() and not self:IsSynastriaDataReady() then
		--print("Talented:RunDeferredSynastriaInit: not ready")
		return
	end
	--print("Talented:RunDeferredSynastriaInit: ready")
	self:MigrateSpecNames()
	self:UpdatePlayerSpecs()
	--print("Talented:RunDeferredSynastriaInit: updated specs")
	if self.base and self.base.perkTab then
		self:AddPerksToFrame(self.base)
		--print("Talented:RunDeferredSynastriaInit: added perks")
	end
	--print("Talented:RunDeferredSynastriaInit: finished")
end

function Talented:QueueDeferredSynastriaInit()
	if not self:IsCustomTalentEnvironment() then
		self:RunDeferredSynastriaInit()
		return
	end
	if self:IsSynastriaDataReady() then
		self:RunDeferredSynastriaInit()
		return
	end
	_G.Talented_SafeDeferredInit = function()
		if _G.Talented and _G.Talented.RunDeferredSynastriaInit then
			_G.Talented:RunDeferredSynastriaInit()
		end
	end
end
SynastriaSafeInvoke("Talented_SafeDeferredInit")

function Talented:GetCurrentClassFromTalentTabs()
	if not self.tabdata then
		return nil
	end

	local tabCount = GetNumTalentTabs()
	if not tabCount or tabCount < 1 then
		return nil
	end

	local candidates = {}
	if type(CustomGetClassMask) == "function" then
		local classMask = CustomGetClassMask() or 0
		for classId = 1, 11 do
			local className = CLASS_BY_ID[classId]
			if className and bit.band(classMask, bit.lshift(1, classId - 1)) > 0 then
				candidates[#candidates + 1] = className
			end
		end
	end
	if #candidates == 0 then
		for classId = 1, 11 do
			local className = CLASS_BY_ID[classId]
			if className then
				candidates[#candidates + 1] = className
			end
		end
	end

	local bestClass, bestScore
	for _, className in ipairs(candidates) do
		local classTabs = self.tabdata[className]
		if classTabs and #classTabs >= tabCount then
			local score = 0
			for tab = 1, tabCount do
				local liveName, _, _, liveBackground = GetTalentTabInfo(tab)
				local expected = classTabs[tab]
				if expected then
					if liveBackground and expected.background and liveBackground == expected.background then
						score = score + 3
					end
					if liveName and expected.name and liveName == expected.name then
						score = score + 1
					end
				end
			end
			if score > 0 and (not bestScore or score > bestScore) then
				bestClass, bestScore = className, score
			end
		end
	end

	return bestClass
end

function Talented:GetCurrentPlayerClass()
	if self.manualPlayerClass and self.spelldata and self.spelldata[self.manualPlayerClass] then
		return self.manualPlayerClass
	end

	local classFromTabs = self:GetCurrentClassFromTalentTabs()
	if classFromTabs then
		return classFromTabs
	end

	if type(CustomGetClassId) == "function" then
		local classId = CustomGetClassId()
		if classId and CLASS_BY_ID[classId] then
			return CLASS_BY_ID[classId]
		end
	end

	return select(2, UnitClass("player"))
end

function Talented:GetBasePlayerClass()
	return select(2, UnitClass("player"))
end

function Talented:ClassTrace(s, ...)
	return
end

function Talented:TraceTalentSnapshot(tag)
	return
end

function Talented:SetManualPlayerClass(className)
	if not className or not self.spelldata or not self.spelldata[className] then
		self:ClassTrace("SetManualPlayerClass rejected class=%s", tostring(className))
		return false
	end
	self:ClassTrace("SetManualPlayerClass class=%s index=%s", className, tostring(self.manualClassIndex))
	self.manualPlayerClass = className
	local nativeOk = true
	if self:IsCustomTalentEnvironment() then
		nativeOk = self:EnsureNativeClassSelection()
		local liveClass = self:GetCurrentClassFromTalentTabs()
		if nativeOk or liveClass == className then
			self:CaptureClassSpecsFromServer(className)
		else
			self:ClassTrace("SetManualPlayerClass capture skipped class=%s nativeOk=%s live=%s", className, tostring(nativeOk), tostring(liveClass))
			if self:CaptureClassSpecsFromSpellbook(className) then
				self:ClassTrace("SetManualPlayerClass used spellbook fallback class=%s", className)
			end
		end
	end
	self:UpdatePlayerSpecs()
	if self.template and self.template.talentGroup then
		self:SetTemplate(self:GetActiveSpec())
	else
		self:UpdateView()
	end
	if self.tabs then
		self.tabs:Update()
	end
	self:UpdateClassSwitchButtons()
	self:PLAYER_TALENT_UPDATE()
	return nativeOk
end

function Talented:GetManualClassIndex()
	local classes = self:GetPlayerClasses()
	if self.manualClassIndex and classes[self.manualClassIndex] == self.manualPlayerClass then
		return self.manualClassIndex
	end
	for i, className in ipairs(classes) do
		if className == self.manualPlayerClass then
			return i
		end
	end
end

function Talented:GetNativeClassButtonIndexForTalentedSlot(talentedSlot)
	if type(talentedSlot) ~= "number" or talentedSlot < 1 then
		return talentedSlot
	end
	local classes = self:GetPlayerClasses()
	if #classes ~= 2 then
		return talentedSlot
	end
	local base = self:GetBasePlayerClass()
	if classes[1] == base then
		return talentedSlot
	end
	if classes[2] == base then
		return 3 - talentedSlot
	end
	return talentedSlot
end

function Talented:SyncManualClassFromLiveTabs()
	if not self:IsCustomTalentEnvironment() then
		return
	end
	local liveClass = self:GetCurrentClassFromTalentTabs()
	if not liveClass then
		return
	end
	for i, name in ipairs(self:GetPlayerClasses()) do
		if name == liveClass then
			self.manualClassIndex = i
			self.manualPlayerClass = liveClass
			return
		end
	end
end

function Talented:OpenNativeTalentFrame()
	local opened = false
	if not IsAddOnLoaded("Blizzard_TalentUI") then
		pcall(LoadAddOn, "Blizzard_TalentUI")
	end
	if self.hooks and type(self.hooks.ToggleTalentFrame) == "function" and (not _G.PlayerTalentFrame or not _G.PlayerTalentFrame:IsShown()) then
		pcall(self.hooks.ToggleTalentFrame)
		opened = true
	end
	if _G.PlayerTalentFrame and not _G.PlayerTalentFrame:IsShown() then
		ShowUIPanel(_G.PlayerTalentFrame)
		opened = true
	end
	return opened
end

function Talented:BootstrapNativeClassButtons()
	if self.nativeBootstrapDone or not self:IsCustomTalentEnvironment() then
		return
	end
	self.nativeBootstrapDone = true

	if not IsAddOnLoaded("Blizzard_TalentUI") then
		pcall(LoadAddOn, "Blizzard_TalentUI")
	end

	self:PrimeNativeClassButtons(false)

	if not self.nativeBootstrapFrame then
		local f = CreateFrame("Frame")
		f:Hide()
		f:SetScript("OnUpdate", function(frame, elapsed)
			frame.elapsed = (frame.elapsed or 0) + elapsed
			if frame.elapsed < 0.4 then
				return
			end
			frame:Hide()
			frame.elapsed = 0

			Talented:DiscoverNativeClassButtons()
			Talented:HookClassSwitchButtons()
			Talented:UpdateClassSwitchButtons()
			Talented:ClassTrace("BootstrapNativeClassButtons finished; native1=%s native2=%s", tostring(Talented.nativeClassButtons and Talented.nativeClassButtons[1] and true or false), tostring(Talented.nativeClassButtons and Talented.nativeClassButtons[2] and true or false))
		end)
		self.nativeBootstrapFrame = f
	end

	self.nativeBootstrapFrame.elapsed = 0
	self.nativeBootstrapFrame:Show()
end

function Talented:OnNativeTalentFrameShow()
	self:DiscoverNativeClassButtons()
	self:HookClassSwitchButtons()
	self:UpdateClassSwitchButtons()
end

function Talented:PrimeNativeClassButtons(forceOpen)
	if self.nativeButtonsPrimed then
		return true
	end

	if not IsAddOnLoaded("Blizzard_TalentUI") then
		pcall(LoadAddOn, "Blizzard_TalentUI")
	end

	local talentFrame = _G.PlayerTalentFrame
	if not talentFrame then
		return false
	end

	if not self.nativeTalentFrameShowHooked then
		self:HookScript(talentFrame, "OnShow", "OnNativeTalentFrameShow")
		self.nativeTalentFrameShowHooked = true
	end

	self:DiscoverNativeClassButtons()
	if self.nativeClassButtons and self.nativeClassButtons[1] and self.nativeClassButtons[2] then
		self.nativeButtonsPrimed = true
		return true
	end

	if forceOpen then
		local wasShown = talentFrame:IsShown()
		if not wasShown then
			ShowUIPanel(talentFrame)
		end
		self:DiscoverNativeClassButtons()
		if self.nativeClassButtons and self.nativeClassButtons[1] and self.nativeClassButtons[2] then
			self.nativeButtonsPrimed = true
		end
		if not wasShown and talentFrame:IsShown() then
			HideUIPanel(talentFrame)
		end
	end
	return false
end

function Talented:DiscoverNativeClassButtons()
	self.nativeClassButtons = self.nativeClassButtons or {}

	local knownNames = {
		"PlayerClassTalentBtn1", "PlayerClassTalentBtn2",
		"ClassTalentBtn1", "ClassTalentBtn2",
		"ClassBtn1", "ClassBtn2"
	}
	for _, name in ipairs(knownNames) do
		local obj = _G[name]
		if obj then
			local index = tonumber(name:match("(%d+)$"))
			if index then
				self.nativeClassButtons[index] = obj
			end
		end
	end

	if (not self.nativeClassButtons[1] or not self.nativeClassButtons[2]) and _G.PlayerTalentFrame and _G.PlayerTalentFrame.GetChildren then
		for _, child in ipairs({_G.PlayerTalentFrame:GetChildren()}) do
			local t = type(child)
			if t == "table" or t == "userdata" then
				local name = (type(child.GetName) == "function") and child:GetName() or nil
				if type(name) == "string" then
					local index = tonumber(name:match("PlayerClassTalentBtn(%d+)"))
						or tonumber(name:match("ClassTalentBtn(%d+)"))
						or tonumber(name:match("ClassBtn(%d+)"))
					if index then
						self.nativeClassButtons[index] = child
					end
				end
			end
		end
	end
end

function Talented:GetNativeClassButton(index, allowTempShow)
	if not _G["PlayerClassTalentBtn" .. tostring(index)] and not IsAddOnLoaded("Blizzard_TalentUI") then
		pcall(LoadAddOn, "Blizzard_TalentUI")
	end

	local button = _G["PlayerClassTalentBtn" .. tostring(index)]
	if not button then
		self:PrimeNativeClassButtons(false)
		self:DiscoverNativeClassButtons()
		button = self.nativeClassButtons and self.nativeClassButtons[index]
	end
	local tempOpenedTalentFrame
	if not button and allowTempShow then
		tempOpenedTalentFrame = self:OpenNativeTalentFrame()
		self:PrimeNativeClassButtons(false)
		button = _G["PlayerClassTalentBtn" .. tostring(index)]
		if not button then
			self:DiscoverNativeClassButtons()
			button = self.nativeClassButtons and self.nativeClassButtons[index]
		end
	end

	return button, tempOpenedTalentFrame
end

function Talented:EnsureNativeClassSelection()
	local index = self:GetManualClassIndex()
	if not index then
		self:ClassTrace("EnsureNativeClassSelection no manual index for class=%s", tostring(self.manualPlayerClass))
		return false
	end
	local wasTalentFrameShown = _G.PlayerTalentFrame and _G.PlayerTalentFrame:IsShown()
	local buttonIndex = self:GetNativeClassButtonIndexForTalentedSlot(index)
	if self.classSwitchDebug and buttonIndex ~= index then
		print(
			("Talented[ClassSwitch]: native button remap talentedSlot=%s -> PlayerClassTalentBtn%s (base=%s classes=%s,%s)"):format(
				tostring(index),
				tostring(buttonIndex),
				tostring(self:GetBasePlayerClass()),
				tostring(self:GetPlayerClasses()[1]),
				tostring(self:GetPlayerClasses()[2])
			)
		)
	end
	local button = select(1, self:GetNativeClassButton(buttonIndex, true))
	local ok = false
	if button and button.Click then
		self.suppressClassSwitchHook = true
		pcall(button.Click, button)
		self.suppressClassSwitchHook = nil
		self:ClassTrace(
			"EnsureNativeClassSelection clicked native button talentedSlot=%d buttonIndex=%d name=%s",
			index,
			buttonIndex,
			tostring(button.GetName and button:GetName() or "unknown")
		)
		ok = true
	elseif button then
		local onClick = button:GetScript("OnClick")
		if onClick then
			self.suppressClassSwitchHook = true
			pcall(onClick, button, "LeftButton")
			self.suppressClassSwitchHook = nil
			self:ClassTrace(
				"EnsureNativeClassSelection fired OnClick talentedSlot=%d buttonIndex=%d name=%s",
				index,
				buttonIndex,
				tostring(button.GetName and button:GetName() or "unknown")
			)
			ok = true
		end
	end
	local tf = _G.PlayerTalentFrame
	if tf and tf:IsShown() and not wasTalentFrameShown then
		HideUIPanel(tf)
	end
	if not ok then
		self:ClassTrace("EnsureNativeClassSelection failed talentedSlot=%d buttonIndex=%d", index, buttonIndex)
	end
	return ok
end

function Talented:TryServerClassSwitch(index, className, allowNativeSelection)
	local classId = self:GetClassIdByName(className)
	local candidates = {
		"CustomSetActiveClass",
		"CustomSetClass",
		"CustomSwitchClass",
		"CMCSetActiveClass",
		"CMCSetClass",
		"CMCSelectClass",
		"SetCustomClass",
		"SetPlayerClassIndex"
	}

	local function tryGlobals()
		for _, fnName in ipairs(candidates) do
			local fn = _G[fnName]
			if type(fn) == "function" then
				if pcall(fn, index) then
					self:ClassTrace("TryServerClassSwitch used %s(%d)", fnName, index)
					if self.classSwitchDebug then
						print(("Talented[ClassSwitch]: global hook OK %s(%d)"):format(fnName, index))
					end
					return true
				end
				if classId and pcall(fn, classId) then
					self:ClassTrace("TryServerClassSwitch used %s(%d classId)", fnName, classId)
					if self.classSwitchDebug then
						print(("Talented[ClassSwitch]: global hook OK %s(classId %d)"):format(fnName, classId))
					end
					return true
				end
				if className and pcall(fn, className) then
					self:ClassTrace("TryServerClassSwitch used %s(%s className)", fnName, className)
					if self.classSwitchDebug then
						print(("Talented[ClassSwitch]: global hook OK %s(%s)"):format(fnName, className))
					end
					return true
				end
			end
		end
		return false
	end

	if self:IsCustomTalentEnvironment() then
		local globalOk = tryGlobals()
		local nativeOk = false
		if allowNativeSelection ~= false then
			nativeOk = self:EnsureNativeClassSelection()
		end
		return globalOk or nativeOk
	end

	if allowNativeSelection ~= false and self:EnsureNativeClassSelection() then
		return true
	end

	return tryGlobals()
end

function Talented:RunNativeClassSync(options)
	options = options or {}
	local quiet = options.quiet and true or false
	local allowNativeSelection = options.allowNativeSelection
	if allowNativeSelection == nil then
		allowNativeSelection = true
	end

	if not self:IsCustomTalentEnvironment() then
		if not quiet then
			self:Print("Class sync is only needed in custom multiclass mode.")
		end
		return
	end

	local classes = self:GetPlayerClasses()
	if #classes < 2 then
		if not quiet then
			self:Print("Class sync skipped: less than 2 classes detected.")
		end
		return
	end

	if not IsAddOnLoaded("Blizzard_TalentUI") then
		pcall(LoadAddOn, "Blizzard_TalentUI")
	end

	local talentFrame = _G.PlayerTalentFrame
	if allowNativeSelection and not talentFrame then
		if not quiet then
			self:Print("Class sync failed: Blizzard talent frame not available.")
		end
		return
	end

	local restore = {
		manualClassIndex = self.manualClassIndex,
		manualPlayerClass = self.manualPlayerClass,
		wasShown = talentFrame and talentFrame:IsShown() or false
	}

	if allowNativeSelection and talentFrame and not restore.wasShown then
		ShowUIPanel(talentFrame)
	end

	if not self.nativeClassSyncFrame then
		local f = CreateFrame("Frame")
		f:Hide()
		f:SetScript("OnUpdate", function(frame, elapsed)
			frame.elapsed = (frame.elapsed or 0) + elapsed
			if frame.elapsed < 0.25 then
				return
			end
			frame.elapsed = 0

			local idx = frame.step
			if idx > #frame.classes then
				frame:Hide()
				local state = frame.restoreState
				if state then
					if state.manualClassIndex and state.manualPlayerClass then
						Talented:TryServerClassSwitch(state.manualClassIndex, state.manualPlayerClass, frame.allowNativeSelection)
					end
					Talented.manualClassIndex = state.manualClassIndex
					Talented.manualPlayerClass = state.manualPlayerClass
					if frame.allowNativeSelection and not state.wasShown and _G.PlayerTalentFrame and _G.PlayerTalentFrame:IsShown() then
						HideUIPanel(_G.PlayerTalentFrame)
					end
				end
				Talented:UpdatePlayerSpecs()
				Talented:UpdateView()
				Talented:UpdateClassSwitchButtons()
				if not frame.quiet then
					Talented:Print("Class sync complete.")
				end
				if type(frame.onComplete) == "function" then
					pcall(frame.onComplete)
				end
				return
			end

			local className = frame.classes[idx]
			Talented.manualClassIndex = idx
			Talented.manualPlayerClass = className

			frame.phase = frame.phase or "switch"
			if frame.phase == "switch" then
				frame.switched = Talented:TryServerClassSwitch(idx, className, frame.allowNativeSelection)
				frame.waitTries = 0
				frame.phase = "wait"
				Talented:ClassTrace("ClassSync switch step=%d class=%s switched=%s", idx, className, tostring(frame.switched))
				return
			end

			if frame.phase == "wait" then
				local liveClass = Talented:GetCurrentClassFromTalentTabs()
				if liveClass == className then
					Talented:CaptureClassSpecsFromServer(className)
					Talented:ClassTrace("ClassSync captured from server step=%d class=%s", idx, className)
					frame.phase = "switch"
					frame.step = idx + 1
					return
				end

				frame.waitTries = (frame.waitTries or 0) + 1
				if frame.waitTries % 3 == 0 then
					Talented:TryServerClassSwitch(idx, className, frame.allowNativeSelection)
				end
				if frame.waitTries >= 12 then
					Talented:CaptureClassSpecsFromSpellbook(className)
					Talented:ClassTrace("ClassSync fallback spellbook step=%d class=%s live=%s", idx, className, tostring(liveClass))
					frame.phase = "switch"
					frame.step = idx + 1
				end
			end
		end)
		self.nativeClassSyncFrame = f
	end

	self.nativeClassSyncFrame.classes = classes
	self.nativeClassSyncFrame.step = 1
	self.nativeClassSyncFrame.elapsed = 0
	self.nativeClassSyncFrame.phase = "switch"
	self.nativeClassSyncFrame.waitTries = 0
	self.nativeClassSyncFrame.restoreState = restore
	self.nativeClassSyncFrame.quiet = quiet
	self.nativeClassSyncFrame.allowNativeSelection = allowNativeSelection
	self.nativeClassSyncFrame.onComplete = options.onComplete
	self.nativeClassSyncFrame:Show()
	if not quiet then
		self:Print("Class sync started...")
	end
end

function Talented:ScheduleInitialClassSync()
	if not self:IsCustomTalentEnvironment() or self.initialClassSyncScheduled or self.initialClassSyncDone then
		return
	end
	local classes = self:GetPlayerClasses()
	if #classes < 2 then
		self.initialClassSyncDone = true
		return
	end
	self.initialClassSyncScheduled = true
	if not self.initialClassSyncFrame then
		local f = CreateFrame("Frame")
		f:Hide()
		f:SetScript("OnUpdate", function(frame, elapsed)
			frame.elapsed = (frame.elapsed or 0) + elapsed
			if frame.elapsed < 1.0 then
				return
			end
			frame:Hide()
			frame.elapsed = 0
			Talented:RunNativeClassSync({
				quiet = true,
				allowNativeSelection = false,
				onComplete = function()
					Talented.initialClassSyncDone = true
				end
			})
		end)
		self.initialClassSyncFrame = f
	end
	self.initialClassSyncFrame.elapsed = 0
	self.initialClassSyncFrame:Show()
end

function Talented:CaptureClassSpecsFromServer(className)
	if not className or not self.spelldata or not self.spelldata[className] then
		self:ClassTrace("CaptureClassSpecsFromServer rejected class=%s", tostring(className))
		return
	end
	if GetNumTalentTabs() == 0 then
		self:ClassTrace("CaptureClassSpecsFromServer skipped class=%s reason=no_tabs", className)
		return
	end
	local liveClass = self:GetCurrentClassFromTalentTabs()
	if liveClass and liveClass ~= className then
		self:ClassTrace("CaptureClassSpecsFromServer skipped class=%s reason=live_class_%s", className, liveClass)
		return
	end

	local info = self:UncompressSpellData(className)
	self.multiClassCache = self.multiClassCache or {}
	local classCache = self.multiClassCache[className] or {}
	for talentGroup = 1, GetNumTalentGroups() do
		local specCache = classCache[talentGroup] or {}
		local tabTotals = {}
		for tab, tree in ipairs(info) do
			local cacheTab = specCache[tab] or {}
			local tabTotal = 0
			for index = 1, #tree do
				local rank = select(5, GetTalentInfo(tab, index, nil, nil, talentGroup)) or 0
				cacheTab[index] = rank
				tabTotal = tabTotal + rank
			end
			specCache[tab] = cacheTab
			tabTotals[#tabTotals + 1] = tostring(tabTotal)
		end
		classCache[talentGroup] = specCache
		self:ClassTrace("Captured class=%s spec=%d tabs=%s", className, talentGroup, table.concat(tabTotals, "/"))
	end
	self.multiClassCache[className] = classCache
end

function Talented:GetKnownPlayerSpellIds()
	local known = {}
	local tabs = (GetNumSpellTabs and GetNumSpellTabs()) or 0
	for tab = 1, tabs do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		for i = 1, (numSpells or 0) do
			local spellBookIndex = (offset or 0) + i
			local spellId
			if type(GetSpellBookItemInfo) == "function" then
				local spellType, resolvedSpellId = GetSpellBookItemInfo(spellBookIndex, BOOKTYPE_SPELL or "spell")
				if spellType == "SPELL" and resolvedSpellId then
					spellId = resolvedSpellId
				end
			end
			if not spellId and type(GetSpellLink) == "function" then
				local link = GetSpellLink(spellBookIndex, BOOKTYPE_SPELL or "spell")
				if type(link) == "string" then
					spellId = tonumber(link:match("spell:(%d+)"))
				end
			end
			if spellId then
				known[spellId] = true
			end
		end
	end
	return known
end

function Talented:CaptureClassSpecsFromSpellbook(className)
	if not className or not self.spelldata or not self.spelldata[className] then
		return false
	end
	local info = self:UncompressSpellData(className)
	if not info then
		return false
	end

	local known = self:GetKnownPlayerSpellIds()
	self.multiClassCache = self.multiClassCache or {}
	local classCache = self.multiClassCache[className] or {}
	local capturedAny = false

	for talentGroup = 1, GetNumTalentGroups() do
		local specCache = classCache[talentGroup] or {}
		local tabTotals = {}
		for tab, tree in ipairs(info) do
			local cacheTab = specCache[tab] or {}
			local tabTotal = 0
			for index, talent in ipairs(tree) do
				local rankValue = 0
				if talent and talent.ranks then
					for rankIdx = #talent.ranks, 1, -1 do
						local spellId = talent.ranks[rankIdx]
						if spellId and known[spellId] then
							rankValue = rankIdx
							break
						end
					end
				end
				cacheTab[index] = rankValue
				tabTotal = tabTotal + rankValue
			end
			specCache[tab] = cacheTab
			tabTotals[#tabTotals + 1] = tostring(tabTotal)
			if tabTotal > 0 then
				capturedAny = true
			end
		end
		classCache[talentGroup] = specCache
		self:ClassTrace("SpellbookCapture class=%s spec=%d tabs=%s", className, talentGroup, table.concat(tabTotals, "/"))
	end
	self.multiClassCache[className] = classCache
	return capturedAny
end

function Talented:GetPlayerClasses()
	if type(CustomGetClassMask) == "function" then
		local classes = {}
		local classMask = CustomGetClassMask() or 0
		for classId = 1, 11 do
			local className = CLASS_BY_ID[classId]
			if className and bit.band(classMask, bit.lshift(1, classId - 1)) > 0 then
				classes[#classes + 1] = className
			end
		end
		if #classes > 0 then
			local base = self:GetBasePlayerClass()
			if base then
				for i, name in ipairs(classes) do
					if name == base and i > 1 then
						table.remove(classes, i)
						table.insert(classes, 1, base)
						break
					end
				end
			end
			return classes
		end
	end

	return {self:GetCurrentPlayerClass()}
end

function Talented:IsPlayerClass(className)
	if not className then
		return false
	end

	if type(CustomIsClassMask) == "function" then
		local classId = CLASS_ID_BY_NAME[className]
		if classId then
			local ok, result = pcall(CustomIsClassMask, bit.lshift(1, classId - 1))
			if ok and result then
				return true
			end
		end
	end

	for _, playerClass in ipairs(self:GetPlayerClasses()) do
		if playerClass == className then
			return true
		end
	end

	return false
end

function Talented:GetCommunityBuildsForClass(className)
	self.communityBuildCatalog = self.communityBuildCatalog or {}
	self.communityBuildCatalog.WITCH = self.communityBuildCatalog.WITCH or {}
	self.communityBuildCatalog.BARBARIAN = self.communityBuildCatalog.BARBARIAN or {}
	self.communityBuildCatalog.MAGE = self.communityBuildCatalog.MAGE or {}
	self.communityBuildCatalog.ROGUE = self.communityBuildCatalog.ROGUE or {}
	self.communityBuildCatalog.PRIEST = self.communityBuildCatalog.PRIEST or {}
	self.communityBuildCatalog.DEATHKNIGHT = self.communityBuildCatalog.DEATHKNIGHT or {}
	self.communityBuildCatalog.PALADIN = self.communityBuildCatalog.PALADIN or {}
	self.communityBuildCatalog.WARLOCK = self.communityBuildCatalog.WARLOCK or {}
	self.communityBuildCatalog.WARRIOR = self.communityBuildCatalog.WARRIOR or {}
	self.communityBuildCatalog.HUNTER = self.communityBuildCatalog.HUNTER or {}

	local function ensureBuild(list, build)
		for i = 1, #list do
			if type(list[i]) == "table" and list[i].url == build.url then
				return
			end
		end
		list[#list + 1] = build
	end

	ensureBuild(self.communityBuildCatalog.WITCH, {
		name = "Lulleh's Witch - Soullink Regen Build (Open World)",
		description = "",
		category = "Prestige",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
		url = "SUB2,\"Lulleh's Witch - Soullink Regen Build (Open World)\",\"\",\"Prestige\",\"Lulleh\",\"Interface\\Icons\\Spell_Shadow_SoulLeech_3\",\"DRUID,0Fm30Dpa0AZtood3A13wa30bZA,WARLOCK,pZAoDmbrAF3aZ53mfC0nr,SAGE,SG20lsk1lsk10lsk1qyk10vtk1,PERKS,P24371X1B2J524Lo2IYH1JI11116Ad1S1P3T1s1FVc2Q3GFn8k11116h1112375132Y1\"",
		baseClass = "WITCH",
		classes = "WARLOCK,DRUID"
	})
	ensureBuild(self.communityBuildCatalog.BARBARIAN, {
		name = "Bladestorm to Win!",
		description = "Bladestorm then Execute!",
		category = "Prestige",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Ability_Whirlwind",
		url = "SUB2,\"Bladestorm to Win!\",\"Bladestorm then Execute!\",\"Prestige\",\"Qt\",\"Interface\\Icons\\Ability_Whirlwind\",\"WARRIOR,M5Am1Dpu0AAc1onFamZAmt0t,DRUID,0Z5Aod3C1Dwcpm1rbAr01,SAGE,SG2fhk1mq1fhk10fhk1iwj100,PERKS,P2A132H933B2AK7x2b1qG1JI11116Ad1K9PW11s1FVc2TGFv5b3111CI11115v141121\"",
		baseClass = "BARBARIAN",
		classes = "WARRIOR,DRUID"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Operational's Low-Level Farming",
		description = "",
		category = "Protection",
		subcategory = "Operational",
		icon = "Interface\\Icons\\Ability_Warrior_Charge",
		url = "SUB2,\"Operational's Low-Level Farming\",\"\",\"Protection\",\"Operational\",\"Interface\\Icons\\Ability_Warrior_Charge\",\"WARRIOR,M50o1AZmZFmtC23BFApBdoa,PERKS,P25141312S3BS47E8s6iI5221a18_F8\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Jukeyboy's UngaBunga Arms",
		description = "",
		category = "Arms",
		subcategory = "Jukeyboy",
		icon = "Interface\\Icons\\Ability_Warrior_Bladestorm",
		url = "SUB2,\"Jukeyboy's UngaBunga Arms\",\"\",\"Arms\",\"Jukeyboy\",\"Interface\\Icons\\Ability_Warrior_Bladestorm\",\"WARRIOR,M3ADaDpu00CcBonFamZDmBA,PERKS,P2371312AF6BO87w2c1i3iIi12gF1114U\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR"
	})
	ensureBuild(self.communityBuildCatalog.HUNTER, {
		name = "Volley Farm",
		description = "",
		category = "Volley",
		subcategory = "Veelina",
		icon = "Interface\\Icons\\Ability_Hunter_FocusedAim",
		url = "SUB2,\"Volley Farm\",\"\",\"Volley\",\"Veelina\",\"Interface\\Icons\\Ability_Hunter_FocusedAim\",\"HUNTER,3Z0wr3cm1oma2Zw00F0D3Awa,PERKS,P25913UB2AKL2y6_I1OAx4t41212D\"",
		baseClass = "HUNTER",
		classes = "HUNTER"
	})
	ensureBuild(self.communityBuildCatalog.HUNTER, {
		name = "Combat Sub BM",
		description = "",
		category = "Prestige",
		subcategory = "Scoots",
		icon = "Interface\\Icons\\Ability_BullRush",
		url = "SUB2,\"Combat Sub BM\",\"\",\"Prestige\",\"Scoots\",\"Interface\\Icons\\Ability_BullRush\",\"HUNTER,35AmAtvaFno3auZt30F3A,ROGUE,Dmw00tZ2vmB0Dyf2nA0cu0A,PERKS,P2374113EFD46K43S31x15W1N5lL1i21_94i1r3\"",
		baseClass = "HUNTER",
		classes = "HUNTER,ROGUE"
	})
	ensureBuild(self.communityBuildCatalog.HUNTER, {
		name = "Beast Master Bleed",
		description = "",
		category = "Beast Mastery",
		subcategory = "Tehnix",
		icon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
		url = "SUB2,\"Beast Master Bleed\",\"\",\"Beast Mastery\",\"Tehnix\",\"Interface\\Icons\\Ability_Hunter_BeastTaming\",\"HUNTER,35AcAvvbCnmwau0w50aZ3,PERKS,P2732211HF832U43S3X2W1hM1Y1x4n611\"",
		baseClass = "HUNTER",
		classes = "HUNTER"
	})
	ensureBuild(self.communityBuildCatalog.MAGE, {
		name = "Big Fuckin Blizzard",
		description = "",
		category = "Prestige",
		subcategory = "Fae",
		icon = "Interface\\Icons\\Spell_Frost_IceStorm",
		url = "SUB2,\"Big Fuckin Blizzard\",\"\",\"Prestige\",\"Fae\",\"Interface\\Icons\\Spell_Frost_IceStorm\",\"DRUID,0f2AnFp02Bmrb0A5AoZAt30A,MAGE,aD3A3mA21vmnot1AZmp0DdAm,SAGE,SG2yzf1yzf1yzf1guByzf100guB,PERKS,P2136411W1B2I24DEv4111m6w81JI11116Ad1R2FAB2J1s1FVc2TGFt7e21116v141111b1\"",
		baseClass = "MAGE",
		classes = "MAGE,DRUID"
	})
	ensureBuild(self.communityBuildCatalog.MAGE, {
		name = "Mirror Image (Farming)",
		description = "",
		category = "Mirror Image",
		subcategory = "Magealou",
		icon = "Interface\\Icons\\Spell_Arcane_Blink",
		url = "SUB2,\"Mirror Image (Farming)\",\"\",\"Mirror Image\",\"Magealou\",\"Interface\\Icons\\Spell_Arcane_Blink\",\"MAGE,a0wA3mApBwmnmt3BZ5p03a,PERKS,P213331121BM83R5St6k4d911-36HYL1\"",
		baseClass = "MAGE",
		classes = "MAGE"
	})
	ensureBuild(self.communityBuildCatalog.MAGE, {
		name = "Mirror Image (Tanky Mirrors)",
		description = "",
		category = "Mirror Image",
		subcategory = "Magealou",
		icon = "Interface\\Icons\\Spell_Arcane_Blink",
		url = "SUB2,\"Mirror Image (Tanky Mirrors)\",\"\",\"Mirror Image\",\"Magealou\",\"Interface\\Icons\\Spell_Arcane_Blink\",\"MAGE,a0wA3mApBwmnmt3BZ5p03a,PERKS,P213331121BM83R5St6k4c9111q3A6H\"",
		baseClass = "MAGE",
		classes = "MAGE"
	})
	ensureBuild(self.communityBuildCatalog.ROGUE, {
		name = "Turret Sin",
		description = "",
		category = "Turret",
		subcategory = "Fappable",
		icon = "Interface\\Icons\\Spell_Fire_BlueFlameBreath",
		url = "SUB2,\"Turret Sin\",\"\",\"Turret\",\"Fappable\",\"Interface\\Icons\\Spell_Fire_BlueFlameBreath\",\"ROGUE,D0wA0wva5A3pm5a2vmB0D,PERKS,P24151311Q6B2AK7Eo3hM1Y1r11111XB\"",
		baseClass = "ROGUE",
		classes = "ROGUE"
	})
	ensureBuild(self.communityBuildCatalog.ROGUE, {
		name = "Shadowclone Rogue",
		description = "",
		category = "Subtlety",
		subcategory = "Qt",
		icon = "Interface\\Icons\\Ability_Rogue_ShadowDance",
		url = "SUB2,\"Shadowclone Rogue\",\"\",\"Subtlety\",\"Qt\",\"Interface\\Icons\\Ability_Rogue_ShadowDance\",\"ROGUE,Dmw0atmZZDA3AmoBBrb51cu,PERKS,P241542372KB2AK43_3P112m2_I1yDp3\"",
		baseClass = "ROGUE",
		classes = "ROGUE"
	})
	ensureBuild(self.communityBuildCatalog.ROGUE, {
		name = "Combat CP Evis",
		description = "",
		category = "Combat",
		subcategory = "Scoots",
		icon = "Interface\\Icons\\Ability_rogue_eviscerate",
		url = "SUB2,\"Combat CP Evis\",\"\",\"Combat\",\"Scoots\",\"Interface\\Icons\\Ability_rogue_eviscerate\",\"ROGUE,DmZ2vmB03tf2nAtcuDADAm,PERKS,P232541BMB2AB97W4J13qL1h22lB\"",
		baseClass = "ROGUE",
		classes = "ROGUE"
	})
	ensureBuild(self.communityBuildCatalog.PRIEST, {
		name = "Ultimate Holy Wander",
		description = "",
		category = "Holy",
		subcategory = "Qt",
		icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit",
		url = "SUB2,\"Ultimate Holy Wander\",\"\",\"Holy\",\"Qt\",\"Interface\\Icons\\Spell_Holy_GuardianSpirit\",\"PRIEST,A5mA0mZAtu3AAfF0otn5ao,PERKS,P2451151A3IBK22FX5aKEx1j14u111uA2\"",
		baseClass = "PRIEST",
		classes = "PRIEST"
	})
	ensureBuild(self.communityBuildCatalog.PRIEST, {
		name = "Standard SW:D Spriest",
		description = "",
		category = "Shadow",
		subcategory = "Veelina",
		icon = "Interface\\Icons\\Spell_Holy_ConsumeMagic",
		url = "SUB2,\"Standard SW:D Spriest\",\"\",\"Shadow\",\"Veelina\",\"Interface\\Icons\\Spell_Holy_ConsumeMagic\",\"PRIEST,AF3A0mZ3ZotAFbDbADfD15a,PERKS,P21351131BMBEC24Ts6pHK5i1-31211\"",
		baseClass = "PRIEST",
		classes = "PRIEST"
	})
	ensureBuild(self.communityBuildCatalog.PRIEST, {
		name = "Mythic Spirits",
		description = "",
		category = "Spirits",
		subcategory = "Veelina",
		icon = "Interface\\Icons\\Ability_Vehicle_LiquidPyrite _blue",
		url = "SUB2,\"Mythic Spirits\",\"\",\"Spirits\",\"Veelina\",\"Interface\\Icons\\Ability_Vehicle_LiquidPyrite _blue\",\"PRIEST,AZD5u0AA5ZowAAcDbA3fDb1,PERKS,P2451131B1LBK4224Tg3bLEV1111E\"",
		baseClass = "PRIEST",
		classes = "PRIEST"
	})
	ensureBuild(self.communityBuildCatalog.PRIEST, {
		name = "Solo",
		description = "",
		category = "Disc",
		subcategory = "Veelina",
		icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
		url = "SUB2,\"Solo\",\"\",\"Disc\",\"Veelina\",\"Interface\\Icons\\Spell_Holy_PowerWordShield\",\"PRIEST,AynA1m0FcpaAAZDtup005Zm,PERKS,P2135141119MBD3Ao123s2X1aK2Cn1r2\"",
		baseClass = "PRIEST",
		classes = "PRIEST"
	})
	ensureBuild(self.communityBuildCatalog.PRIEST, {
		name = "Group",
		description = "",
		category = "Disc",
		subcategory = "Veelina",
		icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
		url = "SUB2,\"Group\",\"\",\"Disc\",\"Veelina\",\"Interface\\Icons\\Spell_Holy_PowerWordShield\",\"PRIEST,Ay3AAm0F2paAD2u2tumAA,PERKS,P21351411AMBD3AAd14u2X1aK2C5i1s21\"",
		baseClass = "PRIEST",
		classes = "PRIEST"
	})
	ensureBuild(self.communityBuildCatalog.BARBARIAN, {
		name = "Blademaster Regen Combat Fury",
		description = "",
		category = "Prestige",
		subcategory = "Bloodlight",
		icon = "Interface\\Icons\\Ability_Rogue_MurderSpree",
		url = "SUB2,\"Blademaster Regen Combat Fury\",\"\",\"Prestige\",\"Bloodlight\",\"Interface\\Icons\\Ability_Rogue_MurderSpree\",\"WARRIOR,Mr021DmZmtAaR511waf1ra,ROGUE,DmZ2vmB03tf2nAtcuDADAm,PERKS,P237131R6B2AB187Lb2v113j1e1_I1h22h4a7q232\"",
		baseClass = "BARBARIAN",
		classes = "WARRIOR,ROGUE"
	})
	ensureBuild(self.communityBuildCatalog.DEATHKNIGHT, {
		name = "Anthaney's Skeletons",
		description = "",
		category = "Skeleton",
		subcategory = "Anthaney",
		icon = "Interface\\Icons\\Spell_DeathKnight_ArmyOfTheDead",
		url = "SUB2,\"Anthaney's Skeletons\",\"\",\"Skeleton\",\"Anthaney\",\"Interface\\Icons\\Spell_DeathKnight_ArmyOfTheDead\",\"DEATHKNIGHT,P0yo0mp3aDbZovtt02p1aaA1,PERKS,P27412111V833LMEiM111b2Fi1AY6u5-4\"",
		baseClass = "DEATHKNIGHT",
		classes = "DEATHKNIGHT"
	})
	ensureBuild(self.communityBuildCatalog.WARLOCK, {
		name = "IMPerator",
		description = "",
		category = "Demo",
		subcategory = "Mcflurry",
		icon = "Interface\\Icons\\Spell_Shadow_SummonImp",
		url = "SUB2,\"IMPerator\",\"\",\"Demo\",\"Mcflurry\",\"Interface\\Icons\\Spell_Shadow_SummonImp\",\"WARLOCK,pZ3oAmbr0Fpdtm5a5D25,PERKS,P27311221AL833N28Z3X41111fIY7u6x2\"",
		baseClass = "WARLOCK",
		classes = "WARLOCK"
	})
	ensureBuild(self.communityBuildCatalog.DEATHKNIGHT, {
		name = "Blood Rune Tough Shell",
		description = "",
		category = "Blood",
		subcategory = "Deathgranny",
		icon = "Interface\\Icons\\Spell_Shadow_LifeDrain",
		url = "SUB2,\"Blood Rune Tough Shell\",\"\",\"Blood\",\"Deathgranny\",\"Interface\\Icons\\Spell_Shadow_LifeDrain\",\"DEATHKNIGHT,PArm50mp3Ac0aZo0mZAoop0A0v,PERKS,P2461312AF674S4S3Y2c1i3iIi1i6u5c512\"",
		baseClass = "DEATHKNIGHT",
		classes = "DEATHKNIGHT"
	})
	ensureBuild(self.communityBuildCatalog.PALADIN, {
		name = "Shadow Paladin",
		description = "",
		category = "Oathbreaker",
		subcategory = "Hannah",
		icon = "Interface\\Icons\\Spell_Holy_BlessingOfStrength",
		url = "SUB2,\"Shadow Paladin\",\"\",\"Oathbreaker\",\"Hannah\",\"Interface\\Icons\\Spell_Holy_BlessingOfStrength\",\"PALADIN,dZy2NmAm0mZtD2tAp1o1pA3,PERKS,P2271131X1BE2A2443L1s6vHd2r71311\"",
		baseClass = "PALADIN",
		classes = "PALADIN"
	})
	ensureBuild(self.communityBuildCatalog.PALADIN, {
		name = "Ret Paladin",
		description = "",
		category = "Retribution",
		subcategory = "Hannah",
		icon = "Interface\\Icons\\Spell_Holy_AuraOfLight",
		url = "SUB2,\"Ret Paladin\",\"\",\"Retribution\",\"Hannah\",\"Interface\\Icons\\Spell_Holy_AuraOfLight\",\"PALADIN,d5Z52tmZtD0uApmoB3Ddn,PERKS,P21361311191LBQ67Mg3uLq1D1111kD\"",
		baseClass = "PALADIN",
		classes = "PALADIN"
	})
	ensureBuild(self.communityBuildCatalog.DEATHKNIGHT, {
		name = "Anthaney's Burgerblast Farming",
		description = "",
		category = "Blood Rune",
		subcategory = "Anthaney",
		icon = "Interface\\Icons\\Spell_Shadow_ChillTouch",
		url = "SUB2,\"Anthaney's Burgerblast Farming\",\"\",\"Blood\",\"Anthaney\",\"Interface\\Icons\\Spell_Shadow_ChillTouch\",\"DEATHKNIGHT,PAym50ap3Ac0aZo0aZAtmmMD0v,PERKS,P247211296A6d144HAZN1y1i1AY6-A127\"",
		baseClass = "DEATHKNIGHT",
		classes = "DEATHKNIGHT"
	})
	ensureBuild(self.communityBuildCatalog.DEATHKNIGHT, {
		name = "Paha's Lich",
		description = "",
		category = "Lich",
		subcategory = "Paha",
		icon = "Interface\\Icons\\Spell_Deathknight_FrostPresence",
		url = "SUB2,\"Paha's Lich\",\"\",\"Lich\",\"Paha\",\"Interface\\Icons\\Spell_Deathknight_FrostPresence\",\"DEATHKNIGHT,PD5ZoOtu0Cp100A1ZDoom0A0t,PERKS,P24114131B1LBS4L8s6pHPs1Y6WB8111\"",
		baseClass = "DEATHKNIGHT",
		classes = "DEATHKNIGHT"
	})
	ensureBuild(self.communityBuildCatalog.WARLOCK, {
		name = "Qt's Pet-less Hellfire 800+FR",
		description = "",
		category = "Hellfire",
		subcategory = "Qt",
		icon = "Interface\\Icons\\Spell_Fire_Incinerate",
		url = "SUB2,\"Qt's Pet-less Hellfire 800+FR\",\"\",\"Hellfire\",\"Qt\",\"Interface\\Icons\\Spell_Fire_Incinerate\",\"WARLOCK,pZ0o3mbmAZ5DAfCmbr3r0au,PERKS,P243711W1BD87kP425s1p311t1p9Y31213\"",
		baseClass = "WARLOCK",
		classes = "WARLOCK"
	})
	ensureBuild(self.communityBuildCatalog.DEATHKNIGHT, {
		name = "Teddy187's Dancing Rune Weapon",
		description = "",
		category = "Blood",
		subcategory = "Teddy187",
		icon = "Interface\\Icons\\Spell_Deathknight_DeathStrike",
		url = "SUB2,\"Teddy187's Dancing Rune Weapon\",\"\",\"Blood\",\"Teddy187\",\"Interface\\Icons\\Spell_Deathknight_DeathStrike\",\"DEATHKNIGHT,PArmf3npdAcAaduo0Dt02,PERKS,P23213231B1F6BM244S3b61wIi1i6zA1\"",
		baseClass = "DEATHKNIGHT",
		classes = "DEATHKNIGHT"
	})
	ensureBuild(self.communityBuildCatalog.DEATHKNIGHT, {
		name = "Paha's Melee Frost",
		description = "",
		category = "Frost",
		subcategory = "Paha",
		icon = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
		url = "SUB2,\"Paha's Melee Frost\",\"\",\"Frost\",\"Paha\",\"Interface\\Icons\\Spell_Deathknight_ClassIcon\",\"DEATHKNIGHT,PArZoottm23bD03n1ra0u0m,PERKS,P2A131CLB3N247E8g3i3iIi1i6-A9711\"",
		baseClass = "DEATHKNIGHT",
		classes = "DEATHKNIGHT"
	})
	ensureBuild(self.communityBuildCatalog.WARLOCK, {
		name = "Reaper Soulmirror no Voidsac Toc myth Viable",
		description = "",
		category = "Reaper",
		subcategory = "Mcflurry",
		icon = "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
		url = "SUB2,\"Reaper Soulmirror no Voidsac Toc myth Viable\",\"\",\"Reaper\",\"Mcflurry\",\"Interface\\Icons\\Spell_Shadow_SoulLeech_3\",\"WARLOCK,pAtAAnAra5r0p0u0o2maaZt3,PERKS,P2191311BLBEC244Z4xIa2FAu6f92215\"",
		baseClass = "WARLOCK",
		classes = "WARLOCK"
	})
	ensureBuild(self.communityBuildCatalog.PALADIN, {
		name = "Lulleh's PvP Sentinel [God Mode]",
		description = "",
		category = "Prestige",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Spell_Nature_LightningShield",
		url = "SUB2,\"Lulleh's PvP Sentinel [God Mode]\",\"\",\"Prestige\",\"Lulleh\",\"Interface\\Icons\\Spell_Nature_LightningShield\",\"PALADIN,dZZ00010000100a1,SHAMAN,m53qaZ0tv30yBpo0d2n5a,PERKS,P213613111VBGA247W4YNAD1111tCNv51111\"",
		baseClass = "PALADIN",
		classes = "PALADIN,SHAMAN"
	})
	ensureBuild(self.communityBuildCatalog.DEATHKNIGHT, {
		name = "Test's Corpse Explosion Cannonball - Bolt-Action",
		description = "",
		category = "Prestige",
		subcategory = "Test",
		icon = "Interface\\Icons\\Spell_Shadow_CorpseExplode",
		url = "SUB2,\"Test's Corpse Explosion Cannonball - Bolt-Action\",\"\",\"Prestige\",\"Test\",\"Interface\\Icons\\Spell_Shadow_CorpseExplode\",\"DEATHKNIGHT,PZmttt02o1Z0tmmuDAt0mtAm3,DRUID,0ZRoo33C1AwcmmBr1Ar,PERKS,P24151311CKB2A8JEb3lJs2J1b2_4qA111m1113\"",
		baseClass = "DEATHKNIGHT",
		classes = "DEATHKNIGHT,DRUID"
	})
	ensureBuild(self.communityBuildCatalog.DEATHKNIGHT, {
		name = "Test's Corpse Explosion Cannonball - Semi-Auto",
		description = "",
		category = "Prestige",
		subcategory = "Test",
		icon = "Interface\\Icons\\Spell_Shadow_AntiMagicShell",
		url = "SUB2,\"Test's Corpse Explosion Cannonball - Semi-Auto\",\"\",\"Prestige\",\"Test\",\"Interface\\Icons\\Spell_Shadow_AntiMagicShell\",\"DEATHKNIGHT,PZmttt02o1Z0tmmuDAt0mtAm3,DRUID,0ZRoo33C1AwcmmBr1Ar,PERKS,P24151311CKB2A8JEb3kJ1s2J1b2_4qA11n1113\"",
		baseClass = "DEATHKNIGHT",
		classes = "DEATHKNIGHT,DRUID"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Lulleh's Butcher - Fury (Zero Compromise)",
		description = "",
		category = "Prestige",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Ability_Warrior_Cleave",
		url = "SUB2,\"Lulleh's Butcher - Fury (Zero Compromise)\",\"\",\"Prestige\",\"Lulleh\",\"Interface\\Icons\\Ability_Warrior_Cleave\",\"WARRIOR,MZ000000100a0b,DEATHKNIGHT,PAym50ap3Ac0aZo0aZAtmmMD0v,PERKS,P231A12AF6BW1S3Y21f32c1iIi12-5Cx5p33KP127\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR,DEATHKNIGHT"
	})
	ensureBuild(self.communityBuildCatalog.MAGE, {
		name = "Lulleh's Conjurer - Arcane (Magic Barbarian)",
		description = "",
		category = "Prestige",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Spell_Arcane_ArcaneTorrent",
		url = "SUB2,\"Lulleh's Conjurer - Arcane (Magic Barbarian)\",\"\",\"Prestige\",\"Lulleh\",\"Interface\\Icons\\Spell_Arcane_ArcaneTorrent\",\"MAGE,aD2BAmAD1wmncu3BZAp3ma3,DRUID,000000000100001,PERKS,P246411282KB2IZ1v4Z2k4dDNJ1b2e4-C131E213\"",
		baseClass = "MAGE",
		classes = "MAGE,DRUID"
	})
	ensureBuild(self.communityBuildCatalog.PALADIN, {
		name = "Lulleh's Martyr (Double Shadow)",
		description = "",
		category = "Prestige",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
		url = "SUB2,\"Lulleh's Martyr (Double Shadow)\",\"\",\"Prestige\",\"Lulleh\",\"Interface\\Icons\\Spell_Holy_SealOfSacrifice\",\"PALADIN,dZyo1ramZtD0tCp1o1pA3,PRIEST,A53AmZ3ZotAFaDbADfD1ra,PERKS,P211711311T3BE66247pP5q1s31211x31211\"",
		baseClass = "PALADIN",
		classes = "PALADIN,PRIEST"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Lulleh's Prot (Farm Build)",
		description = "",
		category = "Protection",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Ability_Warrior_ShieldWall",
		url = "SUB2,\"Lulleh's Prot (Farm Build)\",\"\",\"Protection\",\"Lulleh\",\"Interface\\Icons\\Ability_Warrior_ShieldWall\",\"WARRIOR,M52m0DZmZ50uCv3AFAp1doa,PERKS,P2271131R33BQ67x2k3111iJk18zBY48\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Miri's Honeybadger",
		description = "",
		category = "Arms",
		subcategory = "Miri",
		icon = "Interface\\Icons\\Ability_Warrior_Pummel",
		url = "SUB2,\"Miri's Honeybadger\",\"\",\"Arms\",\"Miri\",\"Interface\\Icons\\Ability_Warrior_Pummel\",\"WARRIOR,M50D1Dpu0A2c0cZmtt0t51aw,PERKS,P2A141BF6BS4S1b2b1i3iIi12kF1115P\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Lulleh's Fury (Aug WW w/ Free Will)",
		description = "",
		category = "Fury",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Ability_Warrior_Whirlwind",
		url = "SUB2,\"Lulleh's Fury (Aug WW w/ Free Will)\",\"\",\"Fury\",\"Lulleh\",\"Interface\\Icons\\Ability_Warrior_Whirlwind\",\"WARRIOR,M50D0DmZo0t0y51awc5ara,PERKS,P2371311191F6BW1X3c1a22oJi12-5d6n32N\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Lulleh's Fury (Aug WW w/ Adaptation)",
		description = "",
		category = "Fury",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Ability_Warrior_Bloodthirst",
		url = "SUB2,\"Lulleh's Fury (Aug WW w/ Adaptation)\",\"\",\"Fury\",\"Lulleh\",\"Interface\\Icons\\Ability_Warrior_Bloodthirst\",\"WARRIOR,M50D0DmZo0t0y51awc5ara,PERKS,P2371311191F6BS4X3c1a22-K2-5d6n32N\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Lulleh's Fury (Tough as Nails w/ Free Will)",
		description = "",
		category = "Fury",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Ability_Warrior_ShieldMastery",
		url = "SUB2,\"Lulleh's Fury (Tough as Nails w/ Free Will)\",\"\",\"Fury\",\"Lulleh\",\"Interface\\Icons\\Ability_Warrior_ShieldMastery\",\"WARRIOR,M50D0DmZo0t0y51awc5ara,PERKS,P2371311191F6BW1X3c1a22oJi12-5d6n35K\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR"
	})
	ensureBuild(self.communityBuildCatalog.WARRIOR, {
		name = "Lulleh's Fury (Tough as Nails w/ Adaptation)",
		description = "",
		category = "Fury",
		subcategory = "Lulleh",
		icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
		url = "SUB2,\"Lulleh's Fury (Tough as Nails w/ Adaptation)\",\"\",\"Fury\",\"Lulleh\",\"Interface\\Icons\\Ability_Warrior_DefensiveStance\",\"WARRIOR,M50D0DmZo0t0y51awc5ara,PERKS,P2371311191F6BS4X3c1a22-K2-5d6n35K\"",
		baseClass = "WARRIOR",
		classes = "WARRIOR"
	})
	ensureBuild(self.communityBuildCatalog.WITCH, {
		name = "Mortus' PvP Witch - Affliction Boomkin",
		description = "",
		category = "Prestige",
		subcategory = "Mortus",
		icon = "Interface\\Icons\\Spell_Nature_StarFall",
		url = "SUB2,\"Mortus' PvP Witch - Affliction Boomkin\",\"\",\"Prestige\",\"Mortus\",\"Interface\\Icons\\Spell_Nature_StarFall\",\"WARLOCK,p3t21nCnb5r0pbu0oAmaZt3,DRUID,0y2AnFpa3Bmo10n5AoZAta,PERKS,P2m1DpQT1\"",
		baseClass = "WITCH",
		classes = "WARLOCK,DRUID"
	})

	self.communityBuildCatalog[className] = self.communityBuildCatalog[className] or {}
	return self.communityBuildCatalog[className]
end

do
	local function NormalizeCommunityBuild(raw, keyHint)
		if type(raw) == "table" then
			local name = raw.name or raw.title or raw.label or raw[1] or keyHint
			local url = raw.url or raw.payload or raw.code or raw[2]
			if type(name) == "string" and type(url) == "string" and name ~= "" and url ~= "" then
				local build = {}
				for k, v in pairs(raw) do
					build[k] = v
				end
				build.name = name
				build.url = url
				return build
			end
			return nil
		end
		if type(raw) == "string" and raw ~= "" and type(keyHint) == "string" and keyHint ~= "" then
			return {
				name = keyHint,
				url = raw
			}
		end
		return nil
	end

	local function BuildMatchesCurrentClassMask(self, build, sourceClassName, requiredClassName)
		if type(build) ~= "table" then
			return false
		end

		local sourceClass = type(sourceClassName) == "string" and sourceClassName:upper() or nil
		local requiredClass = type(requiredClassName) == "string" and requiredClassName:upper() or nil
		local currentClasses = {}

		for _, name in ipairs(self:GetPlayerClasses()) do
			if type(name) == "string" and name ~= "" then
				currentClasses[name:upper()] = true
			end
		end
		local liveClass = self:GetCurrentClassFromTalentTabs()
		if type(liveClass) == "string" and liveClass ~= "" then
			currentClasses[liveClass:upper()] = true
		end
		local playerClass = self:GetCurrentPlayerClass()
		if type(playerClass) == "string" and playerClass ~= "" then
			currentClasses[playerClass:upper()] = true
		end

		local classMask = (type(CustomGetClassMask) == "function") and (CustomGetClassMask() or 0) or nil
		if classMask then
			for classId = 1, 11 do
				local className = CLASS_BY_ID[classId]
				if className and bit.band(classMask, bit.lshift(1, classId - 1)) > 0 then
					currentClasses[className] = true
				end
			end
		end

		local required = {}
		local requiredSet = {}
		local function addRequired(name)
			if type(name) ~= "string" then
				return
			end
			local token = name:upper():gsub("^%s*(.-)%s*$", "%1")
			if token ~= "" and not requiredSet[token] then
				requiredSet[token] = true
				required[#required + 1] = token
			end
		end
		if type(build.classes) == "string" and build.classes ~= "" then
			for token in build.classes:gmatch("[^,%s;|]+") do
				addRequired(token)
			end
		end
		addRequired(build.class1)
		addRequired(build.class2)
		addRequired(build.class)
		local hasExplicitRequirements = (#required > 0)

		if hasExplicitRequirements then
			for _, className in ipairs(required) do
				if not currentClasses[className] then
					return false
				end
			end
			return true
		end

		if type(build.classMask) == "number" and classMask then
			if bit.band(classMask, build.classMask) == build.classMask then
				return true
			end
		end

		if requiredClass == "WITCH" and type(build.baseClass) == "string" and build.baseClass:upper() == "WITCH" then
			return true
		end
		if sourceClass and currentClasses[sourceClass] then
			return true
		end
		return false
	end

	function Talented:GetCommunityBuildsForCurrentMask(className)
		self.communityBuildCatalog = self.communityBuildCatalog or {}
		local output = {}
		local seen = {}

		local function addBuild(build, sourceClassName)
			if type(build) ~= "table" then
				return
			end
			if not BuildMatchesCurrentClassMask(self, build, sourceClassName, className) then
				return
			end
			local key = tostring(build.name or "") .. "||" .. tostring(build.url or "")
			if seen[key] then
				return
			end
			seen[key] = true
			output[#output + 1] = build
		end

		local function collectBuildsFromContainer(container, sourceClassName)
			if type(container) ~= "table" then
				return
			end
			local hasArray = (#container > 0)
			if hasArray then
				for _, raw in ipairs(container) do
					addBuild(NormalizeCommunityBuild(raw), sourceClassName)
				end
			end
			for key, raw in pairs(container) do
				if type(key) ~= "number" then
					addBuild(NormalizeCommunityBuild(raw, key), sourceClassName)
				end
			end
		end

		collectBuildsFromContainer(self:GetCommunityBuildsForClass(className), className)

		for key, builds in pairs(self.communityBuildCatalog) do
			if key ~= className then
				collectBuildsFromContainer(builds, key)
			end
		end

		return output
	end
end

function Talented:IsCustomTalentEnvironment()
	if type(CMCGetMultiClassEnabled) == "function" and (CMCGetMultiClassEnabled() or 1) == 2 then
		return true
	end
	if type(CustomGetClassMask) == "function" or type(CustomGetClassId) == "function" then
		return true
	end
	return false
end

function Talented:HookClassSwitchButtons()
	if self.classSwitchButtonsHooked then
		return true
	end

	local button1 = _G.PlayerClassTalentBtn1
	local button2 = _G.PlayerClassTalentBtn2
	if not button1 or not button2 then
		return false
	end

	self:HookScript(button1, "OnClick", "OnClassSwitchButtonClicked")
	self:HookScript(button2, "OnClick", "OnClassSwitchButtonClicked")
	self.classSwitchButtonsHooked = true
	return true
end

function Talented:SwitchPlayerClassButton(index)
	local classes = self:GetPlayerClasses()
	local className = classes[index]
	self.manualClassIndex = index
	self:ClassTrace("SwitchPlayerClassButton index=%d class=%s", index, tostring(className))
	local switchedNative = false
	if className then
		local activeSpec = GetActiveTalentGroup() or 1
		local classCache = self.multiClassCache and self.multiClassCache[className]
		local specCache = classCache and classCache[activeSpec]
		if not specCache then
			local liveClass = self:GetCurrentClassFromTalentTabs()
			local allowSpellbookPrime = not self:IsCustomTalentEnvironment()
				or liveClass == className
				or (not liveClass and (GetNumTalentTabs() or 0) == 0)
			if allowSpellbookPrime then
				self:CaptureClassSpecsFromSpellbook(className)
			end
		end
		switchedNative = self:SetManualPlayerClass(className)
	end
	if not switchedNative then
		self:ClassTrace("SwitchPlayerClassButton no native button index=%d", index)
		self:OnClassSwitchButtonClicked()
	else
		self:ScheduleClassSwitchRefresh({syncManualFromLive = false})
	end
end

function Talented:UpdateClassSwitchButtons()
	local base = self.base
	if not base or not base.bclass1 or not base.bclass2 then
		return
	end

	local enabled = self:IsCustomTalentEnvironment()
	local classes = self:GetPlayerClasses()
	if not enabled or #classes < 2 then
		base.bclass1:Hide()
		base.bclass2:Hide()
		return
	end

	local localized = _G.LOCALIZED_CLASS_NAMES_MALE or {}
	local activeClass = self:GetCurrentPlayerClass()
	local class1 = classes[1]
	local class2 = classes[2]

	if base.bclass1.SetClassToken then
		base.bclass1:SetClassToken(class1)
	else
		base.bclass1:SetText(localized[class1] or class1 or "Class 1")
		base.bclass1:SetSize(math.max(90, base.bclass1:GetTextWidth() + 20), 22)
	end
	if base.bclass2.SetClassToken then
		base.bclass2:SetClassToken(class2)
	else
		base.bclass2:SetText(localized[class2] or class2 or "Class 2")
		base.bclass2:SetSize(math.max(90, base.bclass2:GetTextWidth() + 20), 22)
	end
	base.bclass1:Show()
	base.bclass2:Show()

	if activeClass == class1 then
		if base.bclass1.SetChecked then
			base.bclass1:SetChecked(true)
			base.bclass2:SetChecked(false)
		else
			base.bclass1:SetButtonState("PUSHED", 1)
			base.bclass2:SetButtonState("NORMAL")
		end
	elseif activeClass == class2 then
		if base.bclass1.SetChecked then
			base.bclass1:SetChecked(false)
			base.bclass2:SetChecked(true)
		else
			base.bclass2:SetButtonState("PUSHED", 1)
			base.bclass1:SetButtonState("NORMAL")
		end
	else
		if base.bclass1.SetChecked then
			base.bclass1:SetChecked(false)
			base.bclass2:SetChecked(false)
		else
			base.bclass1:SetButtonState("NORMAL")
			base.bclass2:SetButtonState("NORMAL")
		end
	end
end

Talented.classSwitchDebug = false

function Talented:ScheduleClassSwitchRefresh(options)
	options = options or {}
	if not self.classSwitchRefreshFrame then
		local f = CreateFrame("Frame")
		f:Hide()
		f:SetScript("OnUpdate", function(frame, elapsed)
			frame.elapsed = (frame.elapsed or 0) + elapsed
			frame.ticks = (frame.ticks or 0) + 1

			if frame.syncManualFromLive then
				Talented:SyncManualClassFromLiveTabs()
			end

			Talented:UpdatePlayerSpecs()
			local refreshClass = Talented:GetCurrentClassFromTalentTabs()
			if refreshClass then
				Talented:CaptureClassSpecsFromServer(refreshClass)
			end
			if Talented.template and Talented.template.talentGroup then
				Talented:SetTemplate(Talented:GetActiveSpec())
			else
				Talented:UpdateView()
			end
			if Talented.tabs then
				Talented.tabs:Update()
			end
			Talented:UpdateClassSwitchButtons()

			local live = Talented:GetCurrentClassFromTalentTabs()
			local manual = Talented.manualPlayerClass
			local tabsReady = (GetNumTalentTabs() or 0) > 0
			local aligned = tabsReady and live and manual and live == manual
			if aligned then
				frame.stableFrames = (frame.stableFrames or 0) + 1
			else
				frame.stableFrames = 0
			end

			local maxElapsed = 2.5
			local maxTicks = frame.syncManualFromLive and 90 or 48
			if frame.stableFrames >= 3 or frame.elapsed >= maxElapsed or frame.ticks >= maxTicks then
				frame:Hide()
				frame.elapsed = 0
				frame.ticks = 0
				frame.stableFrames = 0
			end
		end)
		self.classSwitchRefreshFrame = f
	end
	self.classSwitchRefreshFrame.syncManualFromLive = options.syncManualFromLive and true or false
	self.classSwitchRefreshFrame.elapsed = 0
	self.classSwitchRefreshFrame.ticks = 0
	self.classSwitchRefreshFrame.stableFrames = 0
	self.classSwitchRefreshFrame:Show()
end

function Talented:OnClassSwitchButtonClicked()
		if self.suppressClassSwitchHook then
			self:ClassTrace("OnClassSwitchButtonClicked suppressed")
			return
		end
		self:ClassTrace("OnClassSwitchButtonClicked class=%s live=%s", tostring(self:GetCurrentPlayerClass()), tostring(self:GetCurrentClassFromTalentTabs()))

		self:SyncManualClassFromLiveTabs()
		self:UpdatePlayerSpecs()
		if self.template and self.template.talentGroup then
			self:SetTemplate(self:GetActiveSpec())
		else
			self:UpdateView()
		end
		if self.tabs then
			self.tabs:Update()
		end
		self:UpdateClassSwitchButtons()

		self:ScheduleClassSwitchRefresh({syncManualFromLive = true})
end

-------------------------------------------------------------------------------
-- core.lua
--

do
	Talented.prev_Print = Talented.Print
	function Talented:Print(s, ...)
		if type(s) == "string" and s:find("%", nil, true) then
			self:prev_Print(s:format(...))
		else
			self:prev_Print(s, ...)
		end
	end

	function Talented:Debug(...)
		if not self.db or self.db.profile.debug then
			self:Print(...)
		end
	end

	function Talented:MakeTarget(targetName)
		local name = self.db.char.targets[targetName]
		local src = name and self.db.global.templates[name]
		if not src then
			if name then
				self.db.char.targets[targetName] = nil
			end
			return
		end

		local target = self.target
		if not target then
			target = {}
			self.target = target
		end
		self:CopyPackedTemplate(src, target)

		if
			not self:ValidateTemplate(target) or
				(RAID_CLASS_COLORS[target.class] and not self:IsPlayerClass(target.class)) or
				(not RAID_CLASS_COLORS[target.class] and (not self.GetPetClass or target.class ~= self:GetPetClass()))
		 then
			self.db.char.targets[targetName] = nil
			return nil
		end
		target.name = name
		return target
	end

	function Talented:GetMode()
		return self.mode
	end

	function Talented:SetMode(mode)
		if self.mode ~= mode then
			self.mode = mode
			if mode == "apply" then
				self:ApplyCurrentTemplate()
			elseif self.base and self.base.view then
				self.base.view:SetViewMode(mode)
			end
		end
		local cb = self.base and self.base.checkbox
		if cb then
			cb:SetChecked(mode == "edit")
		end
	end

	function Talented:OnInitialize()
		self.db = LibStub("AceDB-3.0"):New("TalentedDB_Guid", self.defaults)
		self:UpgradeOptions()
		self:LoadTemplates()

		local AceDBOptions = LibStub("AceDBOptions-3.0", true)
		if AceDBOptions then
			self.options.args.profiles = AceDBOptions:GetOptionsTable(self.db)
			self.options.args.profiles.order = 200
		end

		LibStub("AceConfig-3.0"):RegisterOptionsTable("Talented", self.options)
		self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Talented", "Talented")
		self:RegisterChatCommand("talented", "OnChatCommand")

		self:RegisterComm("Talented")
		if self.InitializePet then
			self:InitializePet()
		end

		-- Register events
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("PLAYER_TALENT_UPDATE")
		self:RegisterEvent("GLYPH_ADDED")
		self:RegisterEvent("GLYPH_REMOVED")
		self:RegisterEvent("GLYPH_UPDATED")
		self:RegisterEvent("UNIT_PET")

		-- Hook the talent frame to add perks tab
		if IsAddOnLoaded("Blizzard_TalentUI") then
			self:HookScript(PlayerTalentFrame, "OnShow", function()
				if not self.base or not self.base.perkTab then
					self:AddPerksToFrame(self.base)
				end
				self:HookClassSwitchButtons()
			end)
		else
			self:RegisterEvent("ADDON_LOADED")
		end

		self.OnInitialize = nil
	end

	function Talented:ADDON_LOADED(event, addon)
		if addon == "Blizzard_TalentUI" then
			self:UnregisterEvent("ADDON_LOADED")
			self.ADDON_LOADED = nil
			self:HookScript(PlayerTalentFrame, "OnShow", function()
				if not self.base or not self.base.perkTab then
					self:AddPerksToFrame(self.base)
				end
				self:HookClassSwitchButtons()
			end)
		end
	end

	function Talented:OnChatCommand(input)
		if not input or input:trim() == "" then
			self:OpenOptionsFrame()
		else
			local cmd, arg = input:match("^(%S+)%s*(.-)$")
			cmd = cmd and cmd:lower()
			if cmd == "classsync" then
				self:RunNativeClassSync()
				return
			end
			LibStub("AceConfigCmd-3.0").HandleCommand(self, "talented", "Talented", input)
		end
	end

	function Talented:DeleteCurrentTemplate()
		local template = self.template
		if template.talentGroup then return end
		local templates = self.db.global.templates
		templates[template.name] = nil
		self:SetTemplate()
	end

	function Talented:UpdateTemplateName(template, newname)
		if self.db.global.templates[newname] or template.talentGroup or type(newname) ~= "string" or newname == "" then return end

		local oldname = template.name
		template.name = newname
		local t = self.db.global.templates
		t[newname] = template
		t[oldname] = nil
	end

	do
		local function new(templates, name, class)
			local count = 0
			local template = {name = name, class = class}
			while templates[template.name] do
				count = count + 1
				template.name = format(L["%s (%d)"], name, count)
			end
			templates[template.name] = template
			return template
		end

		local function copy(dst, src)
			dst.class = src.class
			if src.code then
				dst.code = src.code
				return
			else
				for tab, tree in ipairs(Talented:UncompressSpellData(src.class)) do
					local s, d = src[tab], {}
					dst[tab] = d
					for index = 1, #tree do
						d[index] = s[index]
					end
				end
			end
		end

		function Talented:ImportFromOther(name, src)
			if not self:UncompressSpellData(src.class) then
				return
			end

			local dst = new(self.db.global.templates, name, src.class)
			copy(dst, src)
			self:OpenTemplate(dst)
			return dst
		end

		function Talented:CopyTemplate(src)
			local dst = new(self.db.global.templates, format(L["Copy of %s"], src.name), src.class)
			copy(dst, src)
			return dst
		end

		function Talented:CreateEmptyTemplate(class)
			class = class or self:GetCurrentPlayerClass()
			local template = new(self.db.global.templates, L["Empty"], class)

			local info = self:UncompressSpellData(class)

			for tab, tree in ipairs(info) do
				local t = {}
				template[tab] = t
				for index = 1, #tree do
					t[index] = 0
				end
			end

			return template
		end

		Talented.importers = {}
		Talented.exporters = {}
		function Talented:ImportTemplate(url)
			local dst, result = new(self.db.global.templates, L["Imported"])
			for pattern, method in pairs(self.importers) do
				if url:find(pattern) then
					result = method(self, url, dst)
					if result then
						break
					end
				end
			end
			if result then
				if not self:ValidateTemplate(dst) then
					self:Print(L["The given template is not a valid one!"])
					self.db.global.templates[dst.name] = nil
				else
					return dst
				end
			else
				self:Print(L['"%s" does not appear to be a valid URL!'], url)
				self.db.global.templates[dst.name] = nil
			end
		end
	end

	function Talented:OpenTemplate(template)
		self:UnpackTemplate(template)
		if not self:ValidateTemplate(template, true) then
			local name = template.name
			self.db.global.templates[name] = nil
			self:Print(L["The template '%s' is no longer valid and has been removed."], name)
			return
		end
		local base = self:CreateBaseFrame()
		if not self.alternates then
			self:UpdatePlayerSpecs()
		end
		self:SetTemplate(template)
		if not base:IsVisible() then
			ShowUIPanel(base)
		end
	end

	function Talented:SetTemplate(template)
		if not template then
			template = assert(self:GetActiveSpec())
		end
		local view = self:CreateBaseFrame().view
		local old = view.template
		if template ~= old then
			if template.talentGroup then
				if not template.pet then
					view:SetTemplate(template, self:MakeTarget(template.talentGroup))
				else
					view:SetTemplate(template, self:MakeTarget(UnitName "PET"))
				end
			else
				view:SetTemplate(template)
			end
			self.template = template
		end
		if not template.talentGroup then
			self.db.profile.last_template = template.name
		end
		self:SetMode(self:GetDefaultMode())
		-- self:UpdateView()
	end

	function Talented:GetDefaultMode()
		return self.db.profile.always_edit and "edit" or "view"
	end

	function Talented:OnEnable()
		self:RawHook("ToggleTalentFrame", true)
		self:RawHook("ToggleGlyphFrame", true)
		self:SecureHook("UpdateMicroButtons")
		self:CheckHookInspectUI()

		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		UIParent:UnregisterEvent("USE_GLYPH")
		UIParent:UnregisterEvent("CONFIRM_TALENT_WIPE")
		self:RegisterEvent("USE_GLYPH")
		self:RegisterEvent("CONFIRM_TALENT_WIPE")
		self:RegisterEvent("CHARACTER_POINTS_CHANGED")
		self:RegisterEvent("PLAYER_TALENT_UPDATE")
		self:RegisterEvent("CHAT_MSG_ADDON")
		TalentMicroButton:SetScript("OnClick", ToggleTalentFrame)
	end

	function Talented:OnDisable()
		self:UnhookInspectUI()
		UIParent:RegisterEvent("USE_GLYPH")
		UIParent:RegisterEvent("CONFIRM_TALENT_WIPE")
	end

	function Talented:MigrateSpecNames()
		-- Keep server-defined names in local profile for session persistence.
		if not self.db or not self.db.profile then
			return
		end

		local profile = self.db.profile
		profile.specNames = profile.specNames or {}
		if not GetCustomGameDataString then
			return
		end

	    for talentGroup = 1, 6 do
	        local cacheKey = GetCacheKey(talentGroup)
	        local serverName = GetCustomGameDataString(21, talentGroup)
	        
	        -- Always respect the server data if it exists to keep characters synchronized
	        if serverName and serverName ~= "" then
	            profile.specNames[cacheKey] = serverName
	        end
	    end
	end

	function Talented:PLAYER_ENTERING_WORLD()
		-- Update player specs and perk menu
		if self:IsCustomTalentEnvironment() then
			self:BootstrapNativeClassButtons()
			self:PrimeNativeClassButtons(false)
			self:ScheduleInitialClassSync()
		end
		self:QueueDeferredSynastriaInit()
	end

	function Talented:PLAYER_TALENT_UPDATE()
		self:ClassTrace("Event PLAYER_TALENT_UPDATE class=%s base=%s live=%s activeSpec=%s", tostring(self:GetCurrentPlayerClass()), tostring(self:GetBasePlayerClass()), tostring(self:GetCurrentClassFromTalentTabs()), tostring(GetActiveTalentGroup()))
		self:TraceTalentSnapshot("TalentEvent PLAYER_TALENT_UPDATE")
		self:UpdatePlayerSpecs()
	end

	function Talented:CONFIRM_TALENT_WIPE(_, cost)
		local dialog = StaticPopup_Show("CONFIRM_TALENT_WIPE")
		if dialog then
			MoneyFrame_Update(dialog:GetName() .. "MoneyFrame", cost)
			self:SetTemplate()
			local frame = self.base
			if not frame or not frame:IsVisible() then
				self:Update()
				ShowUIPanel(self.base)
			end
			dialog:SetFrameLevel(frame:GetFrameLevel() + 5)
		end
	end

	function Talented:CHARACTER_POINTS_CHANGED()
		self:ClassTrace("Event CHARACTER_POINTS_CHANGED class=%s base=%s live=%s activeSpec=%s", tostring(self:GetCurrentPlayerClass()), tostring(self:GetBasePlayerClass()), tostring(self:GetCurrentClassFromTalentTabs()), tostring(GetActiveTalentGroup()))
		self:TraceTalentSnapshot("TalentEvent CHARACTER_POINTS_CHANGED")
		self:UpdatePlayerSpecs()
		self:UpdateView()
		if self.mode == "apply" then
			self:CheckTalentPointsApplied()
		end
	end

	function Talented:CHAT_MSG_ADDON(_, prefix, message, distribution, sender)
		return
	end

	function Talented:UpdateMicroButtons()
		local button = TalentMicroButton
		if self.db.profile.donthide and UnitLevel "player" < button.minLevel then
			button:Enable()
		end
		if self.base and self.base:IsShown() then
			button:SetButtonState("PUSHED", 1)
		else
			button:SetButtonState("NORMAL")
		end
	end

	function Talented:ToggleTalentFrame()
		local frame = self.base
		if not frame or not frame:IsVisible() then
			self:Update()
			ShowUIPanel(self.base)
		else
			HideUIPanel(frame)
		end
	end

	function Talented:Update()
		self:CreateBaseFrame()
		self:UpdatePlayerSpecs()
		if not self.template then
			self:SetTemplate()
		end
		self:UpdateView()
	end

	function Talented:LoadTemplates()
		local db = self.db.global.templates
		local invalid = {}
		for name, code in pairs(db) do
			if type(code) == "string" then
				local class = self:GetTemplateStringClass(code)
				if class then
					db[name] = {
						name = name,
						code = code,
						class = class
					}
				else
					db[name] = nil
					invalid[#invalid + 1] = name
				end
			elseif not self:ValidateTemplate(code) then
				db[name] = nil
				invalid[#invalid + 1] = name
			end
		end
		if next(invalid) then
			table.sort(invalid)
			self:Print(L["The following templates are no longer valid and have been removed:"])
			self:Print(table.concat(invalid, ", "))
		end

		self.OnDatabaseShutdown = function(self, event, db)
			local _db = db.global.templates
			for name, template in pairs(_db) do
				template.talentGroup = nil
				Talented:PackTemplate(template)
				if template.code then
					_db[name] = template.code
				end
			end
			self.db = nil
		end
		self.db.RegisterCallback(self, "OnDatabaseShutdown")
		self.LoadTemplates = nil
	end
end

-------------------------------------------------------------------------------
-- spell.lua
--

do
	local function handle_ranks(...)
		local result = {}
		local first = (...)
		local pos, row, column, req = 1
		local c = string.byte(first, pos)
		if c == 42 then
			row, column = nil, -1
			pos = pos + 1
			c = string.byte(first, pos)
		elseif c > 32 and c <= 40 then
			column = c - 32
			if column > 4 then
				row = true
				column = column - 4
			end
			pos = pos + 1
			c = string.byte(first, pos)
		end
		if c >= 65 and c <= 90 then
			req = c - 64
			pos = pos + 1
		elseif c >= 97 and c <= 122 then
			req = 96 - c
			pos = pos + 1
		end
		result[1] = tonumber(first:sub(pos))
		for i = 2, select("#", ...) do
			result[i] = tonumber((select(i, ...)))
		end
		local entry = {
			ranks = result,
			row = row,
			column = column,
			req = req
		}
		if not result[1] then
			entry.req = nil
			entry.ranks = nil
			entry.inactive = true
		end
		return entry
	end

	local function next_talent_pos(row, column)
		column = column + 1
		if column >= 5 then
			return row + 1, 1
		else
			return row, column
		end
	end

	local function handle_talents(...)
		local result = {}
		for talent = 1, select("#", ...) do
			result[talent] = handle_ranks(strsplit(";", (select(talent, ...))))
		end
		local row, column = 1, 1
		for index, talent in ipairs(result) do
			local drow, dcolumn = talent.row, talent.column
			if dcolumn == -1 then
				talent.row, talent.column = result[index - 1].row, result[index - 1].column
				talent.inactive = true
			elseif dcolumn then
				if drow then
					row = row + 1
					column = dcolumn
				else
					column = column + dcolumn
				end
				talent.row, talent.column = row, column
			else
				talent.row, talent.column = row, column
			end
			if dcolumn ~= -1 or drow then
				row, column = next_talent_pos(row, column)
			end
			if talent.req then
				talent.req = talent.req + index
				assert(talent.req > 0 and talent.req <= #result)
			end
		end
		return result
	end

	local function handle_tabs(...)
		local result = {}
		for tab = 1, select("#", ...) do
			result[tab] = handle_talents(strsplit(",", (select(tab, ...))))
		end
		return result
	end

	function Talented:UncompressSpellData(class)
		local data = self.spelldata[class]
		if type(data) == "table" then
			return data
		end
		self:Debug("UNCOMPRESS CLASSDATA", class)
		data = handle_tabs(strsplit("|", data))
		self.spelldata[class] = data
		local liveClass = self:GetCurrentClassFromTalentTabs() or self:GetCurrentPlayerClass()
		if class == liveClass and self.CheckSpellData and ((not self:IsCustomTalentEnvironment()) or self:IsSynastriaDataReady()) then
			self:CheckSpellData(class)
		end
		return data
	end

	local spellTooltip
	local function CreateSpellTooltip()
		local tt = CreateFrame "GameTooltip"
		local lefts, rights = {}, {}
		for i = 1, 5 do
			local left, right = tt:CreateFontString(), tt:CreateFontString()
			left:SetFontObject(GameFontNormal)
			right:SetFontObject(GameFontNormal)
			tt:AddFontStrings(left, right)
			lefts[i], rights[i] = left, right
		end
		tt.lefts, tt.rights = lefts, rights
		function tt:SetSpell(spell)
			self:SetOwner(_G.TalentedFrame)
			self:ClearLines()
			self:SetHyperlink("spell:" .. spell)
			return self:NumLines()
		end
		local index
		if _G.CowTip then
			index = function(self, key)
				if not key then
					return ""
				end
				local lines = tt:SetSpell(key)
				if not lines then
					return ""
				end
				local value
				if lines == 2 and not tt.rights[2]:GetText() then
					value = tt.lefts[2]:GetText()
				else
					value = {}
					for i = 2, tt:NumLines() do
						value[i - 1] = {
							left = tt.lefts[i]:GetText(),
							right = tt.rights[i]:GetText()
						}
					end
				end
				tt:Hide() -- CowTip forces the Tooltip to Show, for some reason
				self[key] = value
				return value
			end
		else
			index = function(self, key)
				if not key then
					return ""
				end
				local lines = tt:SetSpell(key)
				if not lines then
					return ""
				end
				local value
				if lines == 2 and not tt.rights[2]:GetText() then
					value = tt.lefts[2]:GetText()
				else
					value = {}
					for i = 2, tt:NumLines() do
						value[i - 1] = {
							left = tt.lefts[i]:GetText(),
							right = tt.rights[i]:GetText()
						}
					end
				end
				self[key] = value
				return value
			end
		end
		Talented.spellDescCache = setmetatable({}, {__index = index})
		CreateSpellTooltip = nil
		return tt
	end

	function Talented:GetTalentName(class, tab, index)
		local spell = self:UncompressSpellData(class)[tab][index].ranks[1]
		return (GetSpellInfo(spell))
	end

	function Talented:GetTalentIcon(class, tab, index)
		local spell = self:UncompressSpellData(class)[tab][index].ranks[1]
		return (select(3, GetSpellInfo(spell)))
	end

	function Talented:GetTalentDesc(class, tab, index, rank)
		if not spellTooltip then
			spellTooltip = CreateSpellTooltip()
		end
		local spell = self:UncompressSpellData(class)[tab][index].ranks[rank]
		return self.spellDescCache[spell]
	end

	function Talented:GetTalentPos(class, tab, index)
		local talent = self:UncompressSpellData(class)[tab][index]
		return talent.row, talent.column
	end

	function Talented:GetTalentPrereqs(class, tab, index)
		local talent = self:UncompressSpellData(class)[tab][index]
		return talent.req
	end

	function Talented:GetTalentRanks(class, tab, index)
		local talent = self:UncompressSpellData(class)[tab][index]
		return #talent.ranks
	end

	function Talented:GetTalentLink(template, tab, index, rank)
		local data = self:UncompressSpellData(template.class)
		rank = rank or (template[tab] and template[tab][index])
		if not rank or rank == 0 then
			rank = 1
		end
		return ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(
			data[tab][index].ranks[rank],
			self:GetTalentName(template.class, tab, index)
		)
	end
end

-------------------------------------------------------------------------------
-- check.lua
--

do
	local function DisableTalented(s, ...)
		if _G.Talented and _G.Talented.IsCustomTalentEnvironment and _G.Talented:IsCustomTalentEnvironment() then
			if s:find("%", nil, true) then
				s = s:format(...)
			end
			if not _G.Talented.customValidationWarned then
				_G.Talented:Print("Skipping strict talent validation in custom multi-class mode: %s", s)
				_G.Talented.customValidationWarned = true
			end
			return
		end
		if _G.TalentedFrame then
			_G.TalentedFrame:Hide()
		end
		if s:find("%", nil, true) then
			s = s:format(...)
		end
		StaticPopupDialogs.TALENTED_DISABLE = {
			button1 = OKAY,
			text = L["Talented has detected an incompatible change in the talent information that requires an update to Talented. Talented will now Disable itself and reload the user interface so that you can use the default interface."] .. "|n" .. s,
			OnAccept = function()
				DisableAddOn("Talented")
				ReloadUI()
			end,
			timeout = 0,
			exclusive = 1,
			whileDead = 1,
			interruptCinematic = 1
		}
		StaticPopup_Show("TALENTED_DISABLE")
	end

	function Talented:CheckSpellData(class)
		if GetNumTalentTabs() < 1 then return end -- postpone checking without failing
		local spelldata, tabdata = self.spelldata[class], self.tabdata[class]
		local invalid
		if #spelldata > GetNumTalentTabs() then
			self:Debug("[SpellData] too many tabs: %d > %d", #spelldata, GetNumTalentTabs())
			invalid = true
			for i = #spelldata, GetNumTalentTabs() + 1, -1 do
				spelldata[i] = nil
			end
		end
		for tab = 1, GetNumTalentTabs() do
			local talents = spelldata[tab]
			if not talents then
				self:Debug("[SpellData] missing talents for tab %d", tab)
				invalid = true
				talents = {}
				spelldata[tab] = talents
			end
			local tabname, _, _, background = GetTalentTabInfo(tab)
			tabdata[tab].name = tabname -- no need to mark invalid for these
			tabdata[tab].background = background
			if #talents > GetNumTalents(tab) then
				self:Debug("[SpellData] too many talents for tab %d", tab)
				invalid = true
				for i = #talents, GetNumTalents(tab) + 1, -1 do
					talents[i] = nil
				end
			end
			for index = 1, GetNumTalents(tab) do
				local talent = talents[index]
				if not talent then
					return DisableTalented("%s:%d:%d MISSING TALENT", class, tab, index)
				end
				local name, icon, row, column, _, ranks = GetTalentInfo(tab, index)
				if not name then
					if not talent.inactive then
						self:Debug("[SpellData] inactive talent %s:%d:%d", class, tab, index)
						talent.inactive = true
						invalid = true
					end
				else
					if talent.inactive then
						return DisableTalented("%s:%d:%d NOT INACTIVE", class, tab, index)
					end
					local found
					for _, spell in ipairs(talent.ranks) do
						if GetSpellInfo(spell) == name then
							found = true
							break
						end
					end
					if not found then
						local s, n = pcall(GetSpellInfo, talent.ranks[1])
						return DisableTalented("%s:%d:%d MISMATCHED %s ~= %s", class, tab, index, n or "unknown talent-" .. talent.ranks[1], name)
					end
					if row ~= talent.row then
						self:Debug("[SpellData] invalid row tab=%d index=%d live=%s cached=%s", tab, index, tostring(row), tostring(talent.row))
						invalid = true
						talent.row = row
					end
					if column ~= talent.column then
						self:Debug("[SpellData] invalid column tab=%d index=%d live=%s cached=%s", tab, index, tostring(column), tostring(talent.column))
						invalid = true
						talent.column = column
					end
					if ranks > #talent.ranks then
						return DisableTalented("%s:%d:%d MISSING RANKS %d ~= %d", class, tab, index, #talent.ranks, ranks)
					end
					if ranks < #talent.ranks then
						invalid = true
						self:Debug("[SpellData] too many ranks tab=%d index=%d live=%d cached=%d", tab, index, ranks, #talent.ranks)
						for i = #talent.ranks, ranks + 1, -1 do
							talent.ranks[i] = nil
						end
					end
					local req_row, req_column, _, _, req2 = GetTalentPrereqs(tab, index)
					if req2 then
						self:Debug("[SpellData] too many reqs tab=%d index=%d req2=%s", tab, index, tostring(req2))
						invalid = true
					end
					if not req_row then
						if talent.req then
							self:Debug("[SpellData] stale req tab=%d index=%d", tab, index)
							invalid = true
							talent.req = nil
						end
					else
						local req = talents[talent.req]
						if not req or req.row ~= req_row or req.column ~= req_column then
							self:Debug("[SpellData] invalid req tab=%d index=%d cachedRow=%s liveRow=%s cachedCol=%s liveCol=%s", tab, index, tostring(req and req.row), tostring(req_row), tostring(req and req.column), tostring(req_column))
							invalid = true
							-- it requires another pass to get the right talent.
							talent.req = 0
						end
					end
				end
			end
			for index = 1, GetNumTalents(tab) do
				local talent = talents[index]
				if talent.req == 0 then
					local row, column = GetTalentPrereqs(tab, index)
					for j = 1, GetNumTalents(tab) do
						if talents[j].row == row and talents[j].column == column then
							talent.req = j
							break
						end
					end
					assert(talent.req ~= 0)
				end
			end
		end
		if invalid then
			self:Print(L["WARNING: Talented has detected that its talent data is outdated. Talented will work fine for your class for this session but may have issue with other classes. You should update Talented if you can."])
		end
		self.CheckSpellData = nil
	end
end

-------------------------------------------------------------------------------
-- encode.lua
--

do
	local assert, ipairs, modf, fmod = assert, ipairs, math.modf, math.fmod

	local stop = "Z"
	local talented_map = "012345abcdefABCDEFmnopqrMNOPQRtuvwxy*"
	local classmap = {
		"DRUID",
		"HUNTER",
		"MAGE",
		"PALADIN",
		"PRIEST",
		"ROGUE",
		"SHAMAN",
		"WARLOCK",
		"WARRIOR",
		"DEATHKNIGHT",
		"Ferocity",
		"Cunning",
		"Tenacity"
	}

	function Talented:GetTemplateStringClass(code, nmap)
		nmap = nmap or talented_map
		if code:len() <= 0 then return end
		local index = modf((nmap:find(code:sub(1, 1), nil, true) - 1) / 3) + 1
		if not index or index > #classmap then return end
		return classmap[index]
	end

	local function get_point_string(class, tabs, primary)
		if type(tabs) == "number" then
			return " - |cffffd200" .. tabs .. "|r"
		end
		local start = " - |cffffd200"
		if primary then
			start = start .. Talented.tabdata[class][primary].name .. " "
			tabs[primary] = "|cffffffff" .. tostring(tabs[primary]) .. "|cffffd200"
		end
		return start .. table.concat(tabs, "/", 1, 3) .. "|r"
	end

	local temp_tabcount = {}
	local function GetTemplateStringInfo(code)
		if code:len() <= 0 then return end

		local index = modf((talented_map:find(code:sub(1, 1), nil, true) - 1) / 3) + 1
		if not index or index > #classmap then return end
		local class = classmap[index]
		local talents = Talented:UncompressSpellData(class)
		local tabs, count, t = 1, 0, 0
		for i = 2, code:len() do
			local char = code:sub(i, i)
			if char == stop then
				if t >= #talents[tabs] then
					temp_tabcount[tabs] = count
					tabs = tabs + 1
					count, t = 0, 0
				end
				temp_tabcount[tabs] = count
				tabs = tabs + 1
				count, t = 0, 0
			else
				index = talented_map:find(char, nil, true) - 1
				if not index then
					return
				end
				local b = fmod(index, 6)
				local a = (index - b) / 6
				if t >= #talents[tabs] then
					temp_tabcount[tabs] = count
					tabs = tabs + 1
					count, t = 0, 0
				end
				t = t + 2
				count = count + a + b
			end
		end
		if count > 0 then
			temp_tabcount[tabs] = count
		else
			tabs = tabs - 1
		end
		for i = tabs + 1, #talents do
			temp_tabcount[i] = 0
		end
		tabs = #talents
		if tabs == 1 then
			return get_point_string(class, temp_tabcount[1])
		else -- tab == 3
			local primary, min, max, total = 0, 0, 0, 0
			for i = 1, tabs do
				local points = temp_tabcount[i]
				if points < min then
					min = points
				end
				if points > max then
					primary, max = i, points
				end
				total = total + points
			end
			local middle = total - min - max
			if 3 * (middle - min) >= 2 * (max - min) then
				primary = nil
			end
			return get_point_string(class, temp_tabcount, primary)
		end
	end

	function Talented:GetTemplateInfo(template)
		self:Debug("GET TEMPLATE INFO", template.name)
		if template.code then
			return GetTemplateStringInfo(template.code)
		else
			local tabs = #template
			if tabs == 1 then
				return get_point_string(template.class, self:GetPointCount(template))
			else
				local primary, min, max, total = 0, 0, 0, 0
				for i = 1, tabs do
					local points = 0
					for _, value in ipairs(template[i]) do
						points = points + value
					end
					temp_tabcount[i] = points
					if points < min then
						min = points
					end
					if points > max then
						primary, max = i, points
					end
					total = total + points
				end
				local middle = total - min - max
				if 3 * (middle - min) >= 2 * (max - min) then
					primary = nil
				end
				return get_point_string(template.class, temp_tabcount, primary)
			end
		end
	end

	function Talented:StringToTemplate(code, template, nmap)
		nmap = nmap or talented_map
		if code:len() <= 0 then return end

		local index = modf((nmap:find(code:sub(1, 1), nil, true) - 1) / 3) + 1
		assert(index and index <= #classmap, "Unknown class code")

		local class = classmap[index]
		template = template or {}
		template.class = class

		local talents = self:UncompressSpellData(class)
		assert(talents)

		local tab = 1
		local t = wipe(template[tab] or {})
		template[tab] = t

		for i = 2, code:len() do
			local char = code:sub(i, i)
			if char == stop then
				if #t >= #talents[tab] then
					tab = tab + 1
					t = wipe(template[tab] or {})
					template[tab] = t
				end
				tab = tab + 1
				t = wipe(template[tab] or {})
				template[tab] = t
			else
				index = nmap:find(char, nil, true) - 1
				if not index then
					return
				end
				local b = fmod(index, 6)
				local a = (index - b) / 6

				if #t >= #talents[tab] then
					tab = tab + 1
					t = wipe(template[tab] or {})
					template[tab] = t
				end
				t[#t + 1] = a

				if #t < #talents[tab] then
					t[#t + 1] = b
				else
					assert(b == 0)
				end
			end
		end

		assert(#template <= #talents, "Too many branches")
		do
			for tb, tree in ipairs(talents) do
				local _t = template[tb] or {}
				template[tb] = _t
				for i = 1, #tree do
					_t[i] = _t[i] or 0
				end
			end
		end

		return template, class
	end

	local function rtrim(s, c)
		local l = #s
		while l >= 1 and s:sub(l, l) == c do
			l = l - 1
		end
		return s:sub(1, l)
	end

	local function get_next_valid_index(tmpl, index, talents)
		if not talents[index] then
			return 0, index
		else
			return tmpl[index], index + 1
		end
	end

	function Talented:TemplateToString(template, nmap)
		nmap = nmap or talented_map

		local class = template.class

		local code, ccode = ""
		do
			for index, c in ipairs(classmap) do
				if c == class then
					local i = (index - 1) * 3 + 1
					ccode = nmap:sub(i, i)
					break
				end
			end
		end
		assert(ccode, "invalid class")
		local s = nmap:sub(1, 1)
		local info = self:UncompressSpellData(class)
		for tab, talents in ipairs(info) do
			local tmpl = template[tab]
			local index = 1
			while index <= #tmpl do
				local r1, r2
				r1, index = get_next_valid_index(tmpl, index, talents)
				r2, index = get_next_valid_index(tmpl, index, talents)
				local v = r1 * 6 + r2 + 1
				local c = nmap:sub(v, v)
				assert(c)
				code = code .. c
			end
			local ncode = rtrim(code, s)
			if ncode ~= code then
				code = ncode .. stop
			end
		end
		local output = ccode .. rtrim(code, stop)

		return output
	end

	function Talented:PackTemplate(template)
		if not template or template.talentGroup or template.code then return end
		self:Debug("PACK TEMPLATE", template.name)
		template.code = self:TemplateToString(template)
		for tab in ipairs(template) do
			template[tab] = nil
		end
	end

	function Talented:UnpackTemplate(template)
		if not template.code then return end
		self:Debug("UNPACK TEMPLATE", template.name)
		self:StringToTemplate(template.code, template)
		template.code = nil
		if not RAID_CLASS_COLORS[template.class] then
			self:FixPetTemplate(template)
		end
	end

	function Talented:CopyPackedTemplate(src, dst)
		local packed = src.code
		if packed then
			self:UnpackTemplate(src)
		end
		dst.class = src.class
		for tab, talents in ipairs(src) do
			local d = dst[tab]
			if not d then
				d = {}
				dst[tab] = d
			end
			for index, value in ipairs(talents) do
				d[index] = value
			end
		end
		if packed then
			self:PackTemplate(src)
		end
	end
end

-------------------------------------------------------------------------------
-- viewmode.lua
--

do
	local select, ipairs = select, ipairs
	local GetTalentInfo = GetTalentInfo

	function Talented:UpdatePlayerSpecs()
		if GetNumTalentTabs() == 0 then return end
		self:HookClassSwitchButtons()
		if self:IsCustomTalentEnvironment() and not self.manualPlayerClass then
			self.manualPlayerClass = self:GetCurrentClassFromTalentTabs() or self:GetBasePlayerClass()
			local classes = self:GetPlayerClasses()
			for i, className in ipairs(classes) do
				if className == self.manualPlayerClass then
					self.manualClassIndex = i
					break
				end
			end
			self:ClassTrace("Initialized manual class to base=%s index=%s", tostring(self.manualPlayerClass), tostring(self.manualClassIndex))
		end
		local class = self:GetCurrentPlayerClass()
		local baseClass = self:GetBasePlayerClass()
		local liveClass = self:GetCurrentClassFromTalentTabs()
		local customEnv = self:IsCustomTalentEnvironment()
		local shouldReadLive = (class == liveClass) or ((not liveClass) and class == baseClass)
		self:ClassTrace("UpdatePlayerSpecs class=%s base=%s live=%s manual=%s source=%s", tostring(class), tostring(baseClass), tostring(liveClass), tostring(self.manualPlayerClass), shouldReadLive and "live" or "cache")
		if liveClass and class == liveClass then
			self:CaptureClassSpecsFromServer(class)
		end
		local info = self:UncompressSpellData(class)
		if not self.multiClassCache then
			self.multiClassCache = {}
		end
		local classCache = self.multiClassCache[class]
		if not classCache then
			classCache = {}
			self.multiClassCache[class] = classCache
		end
		if not self.alternates then
			self.alternates = {}
		end
		for talentGroup = 1, GetNumTalentGroups() do
			local template = self.alternates[talentGroup]
			local classChanged = template and template.class ~= class
			local defaultGroupName = self:GetTalentGroupName(talentGroup)
			if not template then
				template = {
					talentGroup = talentGroup,
					name = defaultGroupName,
					autoName = defaultGroupName,
					class = class
				}
			else
				template.points = nil
				if not template.name or template.name == "" or template.name == template.autoName then
					template.name = defaultGroupName
				end
				template.autoName = defaultGroupName
				if classChanged then
					for i = #template, 1, -1 do
						template[i] = nil
					end
				end
			end
			template.class = class
			if customEnv then
				template.virtualSpec = (class ~= baseClass) and true or nil
			else
				template.virtualSpec = (class ~= liveClass) and true or nil
			end
			local specCache = classCache[talentGroup]
			if not specCache then
				specCache = {}
				classCache[talentGroup] = specCache
			end
			local tabTotals = {}
			for tab, tree in ipairs(info) do
				local ttab = template[tab]
				if not ttab then
					ttab = {}
					template[tab] = ttab
				end
				local cacheTab = specCache[tab]
				if not cacheTab then
					cacheTab = {}
					specCache[tab] = cacheTab
				end
				local tabTotal = 0
				for index = 1, #tree do
					if shouldReadLive then
						local rank = select(5, GetTalentInfo(tab, index, nil, nil, talentGroup)) or 0
						ttab[index] = rank
						cacheTab[index] = rank
					else
						if cacheTab[index] ~= nil then
							ttab[index] = cacheTab[index]
						elseif ttab[index] == nil then
							ttab[index] = 0
						end
					end
					tabTotal = tabTotal + (ttab[index] or 0)
				end
				tabTotals[#tabTotals + 1] = tostring(tabTotal)
			end
			self:ClassTrace("SpecState class=%s spec=%d virtual=%s tabs=%s", class, talentGroup, tostring(template.virtualSpec and true or false), table.concat(tabTotals, "/"))
			self.alternates[talentGroup] = template
			if self.template == template then
				self:UpdateTooltip()
			end
			for _, view in self:IterateTalentViews(template) do
				view:Update()
			end
		end
		self:UpdateClassSwitchButtons()
	end

	function Talented:GetActiveSpec()
		if not self.alternates then
			self:UpdatePlayerSpecs()
		end
		return self.alternates[GetActiveTalentGroup()]
	end

	function Talented:UpdateView()
		if not self.base then return end
		self.base.view:Update()
	end
end

function Talented:GetTalentGroupName(talentGroup)
	if self.db and self.db.profile then
		self.db.profile.specNames = self.db.profile.specNames or {}
        local cacheKey = GetCacheKey(cacheKey)
		local savedName = self.db.profile.specNames[talentGroup]
		if savedName and savedName ~= "" then
			return savedName
		end
		if GetCustomGameDataString then
			local serverName = GetCustomGameDataString(21, talentGroup)
			if serverName and serverName ~= "" then
				self.db.profile.specNames[cacheKey] = serverName
				return serverName
			end
		end
	end

	if talentGroup == 1 then
		return TALENT_SPEC_PRIMARY
	elseif talentGroup == 2 then
		return TALENT_SPEC_SECONDARY
	else
		return string.format("Spec %d", talentGroup)
	end
end

function Talented:SetTalentGroupName(talentGroup, name)
	if type(talentGroup) ~= "number" or talentGroup < 1 then
		return false
	end
	local value = tostring(name or ""):gsub("^%s*(.-)%s*$", "%1")
	if value == "" then
		return self:ClearTalentGroupName(talentGroup)
	end
	if self.db and self.db.profile then
		self.db.profile.specNames = self.db.profile.specNames or {}
		local cacheKey = GetCacheKey(talentGroup)
		self.db.profile.specNames[cacheKey] = value
	end
	if type(SetCustomGameDataString) == "function" then
		pcall(SetCustomGameDataString, 21, talentGroup, value)
	end
	if self.alternates and self.alternates[talentGroup] then
		local template = self.alternates[talentGroup]
		template.name = value
		template.autoName = value
	end
	self:UpdateView()
	return true
end

function Talented:ClearTalentGroupName(talentGroup)
	if type(talentGroup) ~= "number" or talentGroup < 1 then
		return false
	end
	if self.db and self.db.profile and self.db.profile.specNames then
		local cacheKey = GetCacheKey(talentGroup)
		self.db.profile.specNames[cacheKey] = nil
	end
	if type(SetCustomGameDataString) == "function" then
		pcall(SetCustomGameDataString, 21, talentGroup, "")
	end
	local fallback = nil
	if type(GetCustomGameDataString) == "function" then
		local serverName = GetCustomGameDataString(21, talentGroup)
		if serverName and serverName ~= "" then
			fallback = serverName
		end
	end
	if not fallback then
		if talentGroup == 1 then
			fallback = TALENT_SPEC_PRIMARY
		elseif talentGroup == 2 then
			fallback = TALENT_SPEC_SECONDARY
		else
			fallback = string.format("Spec %d", talentGroup)
		end
	end
	if self.alternates and self.alternates[talentGroup] then
		local template = self.alternates[talentGroup]
		template.name = fallback
		template.autoName = fallback
	end
	self:UpdateView()
	return true
end
-------------------------------------------------------------------------------
-- view.lua
--

do
	local LAYOUT_BASE_X = 4
	local LAYOUT_BASE_Y = 24

	local LAYOUT_OFFSET_X, LAYOUT_OFFSET_Y, LAYOUT_DELTA_X, LAYOUT_DELTA_Y
	local LAYOUT_SIZE_X

	local function RecalcLayout(offset)
		if LAYOUT_OFFSET_X ~= offset then
			LAYOUT_OFFSET_X = offset
			LAYOUT_OFFSET_Y = LAYOUT_OFFSET_X

			LAYOUT_DELTA_X = LAYOUT_OFFSET_X / 2
			LAYOUT_DELTA_Y = LAYOUT_OFFSET_Y / 2

			LAYOUT_SIZE_X --[[LAYOUT_MAX_COLUMNS]] = 4 * LAYOUT_OFFSET_X + LAYOUT_DELTA_X

			return true
		end
	end

	local function offset(row, column)
		return (column - 1) * LAYOUT_OFFSET_X + LAYOUT_DELTA_X, -((row - 1) * LAYOUT_OFFSET_Y + LAYOUT_DELTA_Y)
	end

	local TalentView = {}
	function TalentView:init(frame, name)
		self.frame = frame
		self.name = name
		self.elements = {}
	end

	function TalentView:SetUIElement(element, ...)
		self.elements[strjoin("-", ...)] = element
	end

	function TalentView:GetUIElement(...)
		return self.elements[strjoin("-", ...)]
	end

	function TalentView:SetViewMode(mode, force)
		if mode ~= self.mode or force then
			self.mode = mode
			self:Update()
		end
	end

	local function GetMaxPoints(...)
		local total = 0
		for i = 1, GetNumTalentTabs(...) do
			total = total + select(3, GetTalentTabInfo(i, ...))
		end
		return total + GetUnspentTalentPoints(...)
	end

	function TalentView:SetClass(class, force)
		if self.class == class and not force then return end
		local pet = not RAID_CLASS_COLORS[class]
		self.pet = pet

		Talented.Pool:changeSet(self.name)
		wipe(self.elements)
		local talents = Talented:UncompressSpellData(class)
		if not LAYOUT_OFFSET_X then
			RecalcLayout(Talented.db.profile.offset)
		end
		local top_offset, bottom_offset = LAYOUT_BASE_X, LAYOUT_BASE_X
		if self.frame.SetTabSize then
			local n = #talents
			self.frame:SetTabSize(n)
			top_offset = top_offset + (4 - n) * LAYOUT_BASE_Y
			if Talented.db.profile.add_bottom_offset then
				bottom_offset = bottom_offset + LAYOUT_BASE_Y
			end
		end
		local first_tree = talents[1]
		local size_y = first_tree[#first_tree].row * LAYOUT_OFFSET_Y + LAYOUT_DELTA_Y
		for tab, tree in ipairs(talents) do
			local frame = Talented:MakeTalentFrame(self.frame, LAYOUT_SIZE_X, size_y)
			frame.tab = tab
			frame.view = self
			frame.pet = self.pet

			local background = Talented.tabdata[class][tab].background
			frame.topleft:SetTexture("Interface\\TalentFrame\\" .. background .. "-TopLeft")
			frame.topright:SetTexture("Interface\\TalentFrame\\" .. background .. "-TopRight")
			frame.bottomleft:SetTexture("Interface\\TalentFrame\\" .. background .. "-BottomLeft")
			frame.bottomright:SetTexture("Interface\\TalentFrame\\" .. background .. "-BottomRight")

			self:SetUIElement(frame, tab)

			for index, talent in ipairs(tree) do
				if not talent.inactive then
					local button = Talented:MakeButton(frame)
					button.id = index

					self:SetUIElement(button, tab, index)

					button:SetPoint("TOPLEFT", offset(talent.row, talent.column))
					button.texture:SetTexture(Talented:GetTalentIcon(class, tab, index))
					button:Show()
				end
			end

			for index, talent in ipairs(tree) do
				local req = talent.req
				if req then
					local elements = {}
					Talented.DrawLine(elements, frame, offset, talent.row, talent.column, tree[req].row, tree[req].column)
					self:SetUIElement(elements, tab, index, req)
				end
			end

			frame:SetPoint("TOPLEFT", (tab - 1) * LAYOUT_SIZE_X + LAYOUT_BASE_X, -top_offset)
		end
		self.frame:SetSize(#talents * LAYOUT_SIZE_X + LAYOUT_BASE_X * 2, size_y + top_offset + bottom_offset)
		self.frame:SetScale(Talented.db.profile.scale)

		self.class = class
		self:Update()
	end

	function TalentView:SetTemplate(template, target)
		if template then
			Talented:UnpackTemplate(template)
		end
		if target then
			Talented:UnpackTemplate(target)
		end

		local curr = self.target
		self.target = target
		if curr and curr ~= template and curr ~= target then
			Talented:PackTemplate(curr)
		end
		curr = self.template
		self.template = template
		if curr and curr ~= template and curr ~= target then
			Talented:PackTemplate(curr)
		end

		self.spec = template.virtualSpec and nil or template.talentGroup
		self:SetClass(template.class)

		return self:Update()
	end

	function TalentView:ClearTarget()
		if self.target then
			self.target = nil
			self:Update()
		end
	end

	function TalentView:GetReqLevel(total)
		if not self.pet then
			return total == 0 and 1 or total + 9
		else
			if total == 0 then
				return 10
			end
			if total > 16 then
				return 60 + (total - 15) * 4 -- this spec requires Beast Mastery
			else
				return 16 + total * 4
			end
		end
	end

	local GRAY_FONT_COLOR = GRAY_FONT_COLOR
	local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR
	local GREEN_FONT_COLOR = GREEN_FONT_COLOR
	local RED_FONT_COLOR = RED_FONT_COLOR
	local LIGHTBLUE_FONT_COLOR = {r = 0.3, g = 0.9, b = 1}
	function TalentView:Update()
		local template, target = self.template, self.target
		if self.class ~= template.class then
			self:SetClass(template.class, true)
			return
		end
		local isLiveSpec = template.talentGroup and not template.virtualSpec
		local canEditTemplate = (self.mode == "edit")
		local total = 0
		local info = Talented:UncompressSpellData(template.class)
		local at_cap = Talented:IsTemplateAtCap(template)
		for tab, tree in ipairs(info) do
			local count = 0
			for index, talent in ipairs(tree) do
				if not talent.inactive then
					local rank = template[tab][index]
					count = count + rank
					local button = self:GetUIElement(tab, index)
					local color = GRAY_FONT_COLOR
					local state = Talented:GetTalentState(template, tab, index)
					if state == "empty" and (at_cap or not canEditTemplate) then
						state = "unavailable"
					end
					if state == "unavailable" then
						button.texture:SetDesaturated(1)
						button.slot:SetVertexColor(0.65, 0.65, 0.65)
						button.rank:Hide()
						button.rank.texture:Hide()
					else
						button.rank:Show()
						button.rank.texture:Show()
						button.rank:SetText(rank)
						button.texture:SetDesaturated(0)
						if state == "full" then
							color = NORMAL_FONT_COLOR
						else
							color = GREEN_FONT_COLOR
						end
						button.slot:SetVertexColor(color.r, color.g, color.b)
						button.rank:SetVertexColor(color.r, color.g, color.b)
					end
					local req = talent.req
					if req then
						local ecolor = color
						if ecolor == GREEN_FONT_COLOR then
							if canEditTemplate then
								local s = Talented:GetTalentState(template, tab, req)
								if s ~= "full" then
									ecolor = RED_FONT_COLOR
								end
							else
								ecolor = NORMAL_FONT_COLOR
							end
						end
						local reqElements = self:GetUIElement(tab, index, req)
						if reqElements then
							for _, element in ipairs(reqElements) do
								element:SetVertexColor(ecolor.r, ecolor.g, ecolor.b)
							end
						end
					end
					local targetvalue = target and target[tab][index]
					if targetvalue and (targetvalue > 0 or rank > 0) then
						local btarget = Talented:GetButtonTarget(button)
						btarget:Show()
						btarget.texture:Show()
						btarget:SetText(targetvalue)
						local tcolor
						if rank < targetvalue then
							tcolor = LIGHTBLUE_FONT_COLOR
						elseif rank == targetvalue then
							tcolor = GRAY_FONT_COLOR
						else
							tcolor = RED_FONT_COLOR
						end
						btarget:SetVertexColor(tcolor.r, tcolor.g, tcolor.b)
					elseif button.target then
						button.target:Hide()
						button.target.texture:Hide()
					end
				end
			end
			local frame = self:GetUIElement(tab)
			frame.name:SetFormattedText(L["%s (%d)"], Talented.tabdata[template.class][tab].name, count)
			total = total + count
			local clear = frame.clear
			if (not canEditTemplate) or count <= 0 or self.spec then
				clear:Hide()
			else
				clear:Show()
			end
		end
		local maxpoints
		if template.virtualSpec then
			maxpoints = Talented.max_talent_points or 71
		else
			maxpoints = GetMaxPoints(nil, self.pet, self.spec)
		end
		local points = self.frame.points
		if points then
			if template.virtualSpec then
				points:SetFormattedText(L["%d/%d"], total, maxpoints)
			elseif Talented.db.profile.show_level_req then
				points:SetFormattedText(L["Level %d"], self:GetReqLevel(total))
			else
				points:SetFormattedText(L["%d/%d"], total, maxpoints)
			end
			local color
			if total < maxpoints then
				color = GREEN_FONT_COLOR
			elseif total > maxpoints then
				color = RED_FONT_COLOR
			else
				color = NORMAL_FONT_COLOR
			end
			points:SetTextColor(color.r, color.g, color.b)
		end
		local pointsleft = self.frame.pointsleft
		if pointsleft then
			if maxpoints ~= total and (isLiveSpec or template.virtualSpec) then
				pointsleft:Show()
				pointsleft.text:SetFormattedText(L["You have %d talent |4point:points; left"], maxpoints - total)
			else
				pointsleft:Hide()
			end
		end
		local edit = self.frame.editname
		if edit then
			if template.talentGroup then
				edit:Hide()
			else
				edit:Show()
				edit:SetText(template.name)
			end
		end
		local cb, activate = self.frame.checkbox, self.frame.bactivate
if cb then
	if (isLiveSpec and template.talentGroup == GetActiveTalentGroup()) or template.pet then
		if activate then
			activate:Hide()
		end
		cb:Show()
		cb.label:SetText(L["Edit talents"])
		cb.tooltip = L["Toggle editing of talents."]
	elseif isLiveSpec then
		cb:Hide()
		if activate then
			activate.talentGroup = template.talentGroup
			activate:Show()
		end
	else
		if activate then
			activate:Hide()
		end
		cb:Show()
		if template.talentGroup then
			cb.label:SetText(L["Edit talents"])
			cb.tooltip = L["Toggle editing of talents."]
		else
			cb.label:SetText(L["Edit template"])
			cb.tooltip = L["Toggle edition of the template."]
		end
	end
	cb:SetChecked(canEditTemplate)
end
		local targetname = self.frame.targetname
	if targetname then
		if template.pet then
			targetname:Show()
			targetname:SetText(TALENT_SPEC_PET_PRIMARY)
		elseif template.talentGroup then
			targetname:Show()
			if isLiveSpec and template.talentGroup == GetActiveTalentGroup() and target then
				targetname:SetText(L["Target: %s"]:format(target.name))
			else
				targetname:SetText(Talented:GetTalentGroupName(template.talentGroup)) -- Updated this line
			end
		else
			targetname:Hide()
		end
	end
end

	function TalentView:SetTooltipInfo(owner, tab, index)
		Talented:SetTooltipInfo(owner, self.class, tab, index)
	end

	function TalentView:OnTalentClick(button, tab, index)
		if IsModifiedClick "CHATLINK" then
			local link = Talented:GetTalentLink(self.template, tab, index)
			if link then
				ChatEdit_InsertLink(link)
			end
		else
			self:UpdateTalent(tab, index, button == "LeftButton" and 1 or -1)
		end
	end

	function TalentView:UpdateTalent(tab, index, offset)
		local template = self.template
		local canEditTemplate = (self.mode == "edit")
		if not canEditTemplate then return end
		if template.virtualSpec and Talented:IsCustomTalentEnvironment() then
			if offset > 0 then
				Talented:EnsureNativeClassSelection()
				LearnTalent(tab, index, false)
				Talented:PLAYER_TALENT_UPDATE()
				Talented:CHARACTER_POINTS_CHANGED()
			end
		end
		if self.spec and not template.virtualSpec then
			-- Applying talent
			if offset > 0 then
				Talented:LearnTalent(self.template, tab, index)
			end
			return
		end

		if offset > 0 and Talented:IsTemplateAtCap(template) then return end
		local s = Talented:GetTalentState(template, tab, index)

		local ranks = Talented:GetTalentRanks(template.class, tab, index)
		local original = template[tab][index]
		local value = original + offset
		if value < 0 or s == "unavailable" then
			value = 0
		elseif value > ranks then
			value = ranks
		end
		Talented:Debug("Updating %d-%d : %d -> %d (%d)", tab, index, original, value, offset)
		if value == original or not Talented:ValidateTalentBranch(template, tab, index, value) then return end
		template[tab][index] = value
		template.points = nil
		if template.virtualSpec and template.talentGroup and Talented.multiClassCache then
			local classCache = Talented.multiClassCache[template.class]
			local specCache = classCache and classCache[template.talentGroup]
			local cacheTab = specCache and specCache[tab]
			if cacheTab then
				cacheTab[index] = value
			end
		end
		for _, view in Talented:IterateTalentViews(template) do
			view:Update()
		end
		Talented:UpdateTooltip()
		return true
	end

	function TalentView:ClearTalentTab(t)
		local template = self.template
		if template and (not template.talentGroup or template.virtualSpec) then
			local tab = template[t]
			for index, value in ipairs(tab) do
				tab[index] = 0
			end
		end
		for _, view in Talented:IterateTalentViews(template) do
			view:Update()
		end
	end

	Talented.views = {}
	Talented.TalentView = {
		__index = TalentView,
		new = function(self, ...)
			local view = setmetatable({}, self)
			view:init(...)
			table.insert(Talented.views, view)
			return view
		end
	}

	local function next_TalentView(views, index)
		index = (index or 0) + 1
		local view = views[index]
		if not view then
			return nil
		else
			return index, view
		end
	end

	function Talented:IterateTalentViews(template)
		local next
		if template then
			next = function(views, index)
				while true do
					index = (index or 0) + 1
					local view = views[index]
					if not view then
						return nil
					elseif view.template == template then
						return index, view
					end
				end
			end
		else
			next = next_TalentView
		end
		return next, self.views
	end

	function Talented:ViewsReLayout(force)
		if RecalcLayout(self.db.profile.offset) or force then
			for _, view in self:IterateTalentViews() do
				view:SetClass(view.class, true)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- editmode.lua
--

do
	local ipairs = ipairs

	function Talented:IsTemplateAtCap(template)
		local max = RAID_CLASS_COLORS[template.class] and 71 or 20
		return self.db.profile.level_cap and self:GetPointCount(template) >= max
	end

	function Talented:GetPointCount(template)
		local total = 0
		local info = self:UncompressSpellData(template.class)
		for tab in ipairs(info) do
			total = total + self:GetTalentTabCount(template, tab)
		end
		return total
	end

	function Talented:GetTalentTabCount(template, tab)
		local total = 0
		for _, value in ipairs(template[tab]) do
			total = total + value
		end
		return total
	end

	function Talented:ClearTalentTab(t)
		local template = self.template
		if template and not template.talentGroup and self.mode == "edit" then
			local tab = template[t]
			for index, value in ipairs(tab) do
				tab[index] = 0
			end
		end
		self:UpdateView()
	end

	function Talented:GetSkillPointsPerTier(class)
		-- Player Tiers are 5 points appart, Pet Tiers are only 3 points appart.
		return RAID_CLASS_COLORS[class] and 5 or 3
	end

	function Talented:GetTalentState(template, tab, index)
		local s
		local info = self:UncompressSpellData(template.class)[tab][index]
		local tier = (info.row - 1) * self:GetSkillPointsPerTier(template.class)
		local count = self:GetTalentTabCount(template, tab)

		if count < tier then
			s = false
		else
			s = true
			if info.req and self:GetTalentState(template, tab, info.req) ~= "full" then
				s = false
			end
		end

		if not s or info.inactive then
			s = "unavailable"
		else
			local value = template[tab][index]
			if value == #info.ranks then
				s = "full"
			elseif value == 0 then
				s = "empty"
			else
				s = "available"
			end
		end
		return s
	end

	function Talented:ValidateTalentBranch(template, tab, index, newvalue)
		local count = 0
		local pointsPerTier = self:GetSkillPointsPerTier(template.class)
		local tree = self:UncompressSpellData(template.class)[tab]
		local ttab = template[tab]
		for i, talent in ipairs(tree) do
			local value = i == index and newvalue or ttab[i]
			if value > 0 then
				local tier = (talent.row - 1) * pointsPerTier
				if count < tier then
					self:Debug("Update refused because of tier")
					return false
				end
				local r = talent.req
				if r then
					local rvalue = r == index and newvalue or ttab[r]
					if rvalue < #tree[r].ranks then
						self:Debug("Update refused because of prereq")
						return false
					end
				end
				count = count + value
			end
		end
		return true
	end

	function Talented:ValidateTemplate(template, fix)
		local class = template.class
		if not class then return end
		local pointsPerTier = self:GetSkillPointsPerTier(template.class)
		local info = self:UncompressSpellData(class)
		local fixed
		for tab, tree in ipairs(info) do
			local t = template[tab]
			if not t then
				return
			end
			local count = 0
			for i, talent in ipairs(tree) do
				local value = t[i]
				if not value then
					return
				end
				if value > 0 then
					if count < (talent.row - 1) * pointsPerTier or value > (talent.inactive and 0 or #talent.ranks) then
						if fix then
							t[i], value, fixed = 0, 0, true
						else
							return
						end
					end
					local r = talent.req
					if r then
						if t[r] < #tree[r].ranks then
							if fix then
								t[i], value, fixed = 0, 0, true
							else
								return
							end
						end
					end
					count = count + value
				end
			end
		end
		if fixed then
			self:Print(L["The template '%s' had inconsistencies and has been fixed. Please check it before applying."], template.name)
			template.points = nil
		end
		return true
	end
end

-------------------------------------------------------------------------------
-- learn.lua
--

do
	local StaticPopupDialogs = StaticPopupDialogs

	local function ShowDialog(text, tab, index, pet)
		StaticPopupDialogs.TALENTED_CONFIRM_LEARN = {
			button1 = YES,
			button2 = NO,
			OnAccept = function(self)
				LearnTalent(self.talent_tab, self.talent_index, self.is_pet)
			end,
			timeout = 0,
			exclusive = 1,
			whileDead = 1,
			interruptCinematic = 1
		}
		ShowDialog = function(text, tab, index, pet)
			StaticPopupDialogs.TALENTED_CONFIRM_LEARN.text = text
			local dlg = StaticPopup_Show "TALENTED_CONFIRM_LEARN"
			dlg.talent_tab = tab
			dlg.talent_index = index
			dlg.is_pet = pet
			return dlg
		end
		return ShowDialog(text, tab, index, pet)
	end

	function Talented:LearnTalent(template, tab, index)
		local is_pet = not RAID_CLASS_COLORS[template.class]
		local p = self.db.profile

		if not p.confirmlearn then
			LearnTalent(tab, index, is_pet)
			return
		end

		if not p.always_call_learn_talents then
			local state = self:GetTalentState(template, tab, index)
			if
				state == "full" or -- talent maxed out
					state == "unavailable" or -- prereqs not fullfilled
					GetUnspentTalentPoints(nil, is_pet, GetActiveTalentGroup(nil, is_pet)) == 0
			 then -- no more points
				return
			end
		end

		ShowDialog(L['Are you sure that you want to learn "%s (%d/%d)" ?']:format(self:GetTalentName(template.class, tab, index), template[tab][index] + 1, self:GetTalentRanks(template.class, tab, index)), tab, index, is_pet)
	end
end

-------------------------------------------------------------------------------
-- other.lua
--

do
	local function ShowDialog(sender, name, code)
		StaticPopupDialogs.TALENTED_CONFIRM_SHARE_TEMPLATE = {
			button1 = YES,
			button2 = NO,
			text = L['Do you want to add the template "%s" that %s sent you ?'],
			OnAccept = function(self)
				local res, value, class = pcall(Talented.StringToTemplate, Talented, self.code)
				if res then
					Talented:ImportFromOther(self.name, {
						code = self.code,
						class = class
					})
				else
					Talented:Print("Invalid template", value)
				end
			end,
			timeout = 0,
			exclusive = 1,
			whileDead = 1,
			interruptCinematic = 1
		}
		ShowDialog = function(sender, name, code)
			local dlg = StaticPopup_Show("TALENTED_CONFIRM_SHARE_TEMPLATE", name, sender)
			dlg.name = name
			dlg.code = code
		end
		return ShowDialog(sender, name, code)
	end

	function Talented:OnCommReceived(prefix, message, distribution, sender)
		local status, name, code = self:Deserialize(message)
		if not status then return end

		ShowDialog(sender, name, code)
	end

	function Talented:ExportTemplateToUser(name)
		if not name or name:trim() == "" then return end
		local message = self:Serialize(self.template.name, self:TemplateToString(self.template))
		self:SendCommMessage("Talented", message, "WHISPER", name)
	end
end

-------------------------------------------------------------------------------
-- chat.lua
--

do
	local ipairs, format = ipairs, string.format

	function Talented:WriteToChat(text, ...)
		if text:find("%", 1, true) then
			text = text:format(...)
		end
		local edit = ChatEdit_GetLastActiveWindow and ChatEdit_GetLastActiveWindow() or DEFAULT_CHAT_FRAME.editBox
		local type = edit:GetAttribute("chatType")
		local lang = edit.language
		if type == "WHISPER" then
			local target = edit:GetAttribute("tellTarget")
			SendChatMessage(text, type, lang, target)
		elseif type == "CHANNEL" then
			local channel = edit:GetAttribute("channelTarget")
			SendChatMessage(text, type, lang, channel)
		else
			SendChatMessage(text, type, lang)
		end
	end

	local function GetDialog()
		StaticPopupDialogs.TALENTED_SHOW_DIALOG = {
			text = L["URL:"],
			button1 = OKAY,
			hasEditBox = 1,
			hasWideEditBox = 1,
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
			OnShow = function(self)
				self.button1:SetPoint("TOP", self.editBox, "BOTTOM", 0, -8)
			end
		}
		GetDialog = function()
			return StaticPopup_Show "TALENTED_SHOW_DIALOG"
		end
		return GetDialog()
	end

	function Talented:ShowInDialog(text, ...)
		if text:find("%", 1, true) then
			text = text:format(...)
		end
		local edit = GetDialog().wideEditBox
		edit:SetText(text)
		edit:HighlightText()
	end
end

-------------------------------------------------------------------------------
-- tips.lua
--

do
	local type = type
	local ipairs = ipairs
	local GameTooltip = GameTooltip
	local IsAltKeyDown = IsAltKeyDown
	local GREEN_FONT_COLOR = GREEN_FONT_COLOR
	local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR
	local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR
	local RED_FONT_COLOR = RED_FONT_COLOR

	local function addline(line, color, split)
		GameTooltip:AddLine(line, color.r, color.g, color.b, split)
	end

	local function addtipline(tip)
		local color = HIGHLIGHT_FONT_COLOR
		tip = tip or ""
		if type(tip) == "string" then
			addline(tip, NORMAL_FONT_COLOR, true)
		else
			for _, i in ipairs(tip) do
				if (_ == #tip) then
					color = NORMAL_FONT_COLOR
				end
				if i.right then
					GameTooltip:AddDoubleLine(i.left, i.right, color.r, color.g, color.b, color.r, color.g, color.b)
				else
					addline(i.left, color, true)
				end
			end
		end
	end

	local lastTooltipInfo = {}
	function Talented:SetTooltipInfo(frame, class, tab, index)
		lastTooltipInfo[1] = frame
		lastTooltipInfo[2] = class
		lastTooltipInfo[3] = tab
		lastTooltipInfo[4] = index
		if not GameTooltip:IsOwned(frame) then
			GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
		end

		local tree = self.spelldata[class][tab]
		local info = tree[index]
		GameTooltip:ClearLines()
		local tier = (info.row - 1) * self:GetSkillPointsPerTier(class)
		local template = frame:GetParent().view.template

		self:UnpackTemplate(template)
		local rank = template[tab][index]
		local ranks, req = #info.ranks, info.req
		addline(self:GetTalentName(class, tab, index), HIGHLIGHT_FONT_COLOR)
		addline(TOOLTIP_TALENT_RANK:format(rank, ranks), HIGHLIGHT_FONT_COLOR)
		if req then
			local oranks = #tree[req].ranks
			if template[tab][req] < oranks then
				addline(TOOLTIP_TALENT_PREREQ:format(oranks, self:GetTalentName(class, tab, req)), RED_FONT_COLOR)
			end
		end
		if tier >= 1 and self:GetTalentTabCount(template, tab) < tier then
			addline(TOOLTIP_TALENT_TIER_POINTS:format(tier, self.tabdata[class][tab].name), RED_FONT_COLOR)
		end
		if IsAltKeyDown() then
			for i = 1, ranks do
				local tip = self:GetTalentDesc(class, tab, index, i)
				if type(tip) == "table" then
					tip = tip[#tip].left
				end
				addline(tip, i == rank and HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR, true)
			end
		else
			if rank > 0 then
				addtipline(self:GetTalentDesc(class, tab, index, rank))
			end
			if rank < ranks then
				if rank > 0 then
					addline("|n" .. TOOLTIP_TALENT_NEXT_RANK, HIGHLIGHT_FONT_COLOR)
				end
				addtipline(self:GetTalentDesc(class, tab, index, rank + 1))
			end
		end
		local s = self:GetTalentState(template, tab, index)
		if self.mode == "edit" then
			if template.talentGroup then
				if s == "available" or s == "empty" then
					addline(TOOLTIP_TALENT_LEARN, GREEN_FONT_COLOR)
				end
			elseif s == "full" then
				addline(TALENT_TOOLTIP_REMOVEPREVIEWPOINT, GREEN_FONT_COLOR)
			elseif s == "available" then
				GameTooltip:AddDoubleLine(
					TALENT_TOOLTIP_ADDPREVIEWPOINT,
					TALENT_TOOLTIP_REMOVEPREVIEWPOINT,
					GREEN_FONT_COLOR.r,
					GREEN_FONT_COLOR.g,
					GREEN_FONT_COLOR.b,
					GREEN_FONT_COLOR.r,
					GREEN_FONT_COLOR.g,
					GREEN_FONT_COLOR.b
				)
			elseif s == "empty" then
				addline(TALENT_TOOLTIP_ADDPREVIEWPOINT, GREEN_FONT_COLOR)
			end
		end
		GameTooltip:Show()
	end

	function Talented:HideTooltipInfo()
		GameTooltip:Hide()
		wipe(lastTooltipInfo)
	end

	function Talented:UpdateTooltip()
		if next(lastTooltipInfo) then
			self:SetTooltipInfo(unpack(lastTooltipInfo))
		end
	end

	function Talented:MODIFIER_STATE_CHANGED(_, mod)
		if mod:sub(-3) == "ALT" then
			self:UpdateTooltip()
		end
	end
end

-------------------------------------------------------------------------------
-- apply.lua
--

do
	function Talented:ApplyCurrentTemplate()
		local template = self.template
		local pet = not RAID_CLASS_COLORS[template.class]
		if pet then
			if not self.GetPetClass or self:GetPetClass() ~= template.class then
				self:Print(L["Sorry, I can't apply this template because it doesn't match your pet's class!"])
				self.mode = "view"
				self:UpdateView()
				return
			end
		elseif not self:IsPlayerClass(template.class) then
			self:Print(L["Sorry, I can't apply this template because it doesn't match your class!"])
			self.mode = "view"
			self:UpdateView()
			return
		end
		local count = 0
		local current = pet and self.pet_current or self:GetActiveSpec()
		local group = GetActiveTalentGroup(nil, pet)
		-- check if enough talent points are available
		local available = GetUnspentTalentPoints(nil, pet, group)
		for tab, tree in ipairs(self:UncompressSpellData(template.class)) do
			for index = 1, #tree do
				local delta = template[tab][index] - current[tab][index]
				if delta > 0 then
					count = count + delta
				end
			end
		end
		if count == 0 then
			self:Print(L["Nothing to do"])
			self.mode = "view"
			self:UpdateView()
		elseif count > available then
			self:Print(L["Sorry, I can't apply this template because you don't have enough talent points available (need %d)!"], count)
			self.mode = "view"
			self:UpdateView()
		else
			self:EnableUI(false)
			self:ApplyTalentPoints()
		end
	end

	function Talented:ApplyTalentPoints()
		local p = GetCVar "previewTalents"
		SetCVar("previewTalents", "1")

		local template = self.template
		local pet = not RAID_CLASS_COLORS[template.class]
		local group = GetActiveTalentGroup(nil, pet)
		ResetGroupPreviewTalentPoints(pet, group)
		local cp = GetUnspentTalentPoints(nil, pet, group)

		while true do
			local missing, set
			for tab, tree in ipairs(self:UncompressSpellData(template.class)) do
				local ttab = template[tab]
				for index = 1, #tree do
					local rank = select(9, GetTalentInfo(tab, index, nil, pet, group))
					local delta = ttab[index] - rank
					if delta > 0 then
						AddPreviewTalentPoints(tab, index, delta, pet, group)
						local nrank = select(9, GetTalentInfo(tab, index, nil, pet, group))
						if nrank < ttab[index] then
							missing = true
						elseif nrank > rank then
							set = true
						end
						cp = cp - nrank + rank
					end
				end
			end
			if not missing then
				break
			end
			assert(set) -- make sure we did something
		end
		if cp < 0 then
			Talented:Print(L["Error while applying talents! Not enough talent points!"])
			ResetGroupPreviewTalentPoints(pet, group)
			Talented:EnableUI(true)
		else
			LearnPreviewTalents(pet)
		end
		SetCVar("previewTalents", p)
	end

	function Talented:CheckTalentPointsApplied()
		local template = self.template
		local pet = not RAID_CLASS_COLORS[template.class]
		local group = GetActiveTalentGroup(nil, pet)
		local failed
		for tab, tree in ipairs(self:UncompressSpellData(template.class)) do
			local ttab = template[tab]
			for index = 1, #tree do
				local delta = ttab[index] - select(5, GetTalentInfo(tab, index, nil, pet, group))
				if delta > 0 then
					failed = true
					break
				end
			end
		end
		if failed then
			Talented:Print(L["Error while applying talents! some of the request talents were not set!"])
		else
			local cp = GetUnspentTalentPoints(nil, pet, group)
			Talented:Print(L["Template applied successfully, %d talent points remaining."], cp)

			if self.db.profile.restore_bars then
				local set = template.name:match("[^-]*"):trim():lower()
				if set and ABS then
					ABS:RestoreProfile(set)
				elseif set and _G.KPack and _G.KPack.ActionBarSaver then
					_G.KPack.ActionBarSaver:RestoreProfile(set)
				end
			end
		end
		Talented:OpenTemplate(pet and self.pet_current or self:GetActiveSpec())
		Talented:EnableUI(true)

		return not failed
	end
end

-------------------------------------------------------------------------------
-- inspectui.lua
--

do
	local prev_script
	local new_script = function()
		local template = Talented:UpdateInspectTemplate()
		if template then
			Talented:OpenTemplate(template)
		end
	end

	function Talented:HookInspectUI()
		if not prev_script then
			prev_script = InspectFrameTab3:GetScript("OnClick")
			InspectFrameTab3:SetScript("OnClick", new_script)
		end
	end

	function Talented:UnhookInspectUI()
		if prev_script then
			InspectFrameTab3:SetScript("OnClick", prev_script)
			prev_script = nil
		end
	end

	function Talented:CheckHookInspectUI()
		self:RegisterEvent("INSPECT_TALENT_READY")
		if self.db.profile.hook_inspect_ui then
			if IsAddOnLoaded("Blizzard_InspectUI") then
				self:HookInspectUI()
			else
				self:RegisterEvent("ADDON_LOADED")
			end
		else
			if IsAddOnLoaded("Blizzard_InspectUI") then
				self:UnhookInspectUI()
			else
				self:UnregisterEvent("ADDON_LOADED")
			end
		end
	end

	function Talented:ADDON_LOADED(_, addon)
		if addon == "Blizzard_InspectUI" then
			self:UnregisterEvent("ADDON_LOADED")
			self.ADDON_LOADED = nil
			self:HookInspectUI()
		end
	end

	function Talented:GetInspectUnit()
		return InspectFrame and InspectFrame.unit
	end

	function Talented:UpdateInspectTemplate()
		local unit = self:GetInspectUnit()
		if not unit then return end
		local name = UnitName(unit)
		if not name then return end
		local inspections = self.inspections or {}
		self.inspections = inspections
		local class = select(2, UnitClass(unit))
		local info = self:UncompressSpellData(class)
		local retval
		for talentGroup = 1, GetNumTalentGroups(true) do
			local template_name = name .. " - " .. tostring(talentGroup)
			local template = inspections[template_name]
			if not template then
				template = {
					name = L["Inspection of %s"]:format(name) .. (talentGroup == GetActiveTalentGroup(true) and "" or L[" (alt)"]),
					class = class
				}
				for tab, tree in ipairs(info) do
					template[tab] = {}
				end
				inspections[template_name] = template
			else
				self:UnpackTemplate(template)
			end
			for tab, tree in ipairs(info) do
				for index = 1, #tree do
					local rank = select(5, GetTalentInfo(tab, index, true, nil, talentGroup))
					template[tab][index] = rank
				end
			end
			if not self:ValidateTemplate(template) then
				inspections[template_name] = nil
			else
				local found
				for _, view in self:IterateTalentViews(template) do
					view:Update()
					found = true
				end
				if not found then
					self:PackTemplate(template)
				end
				if talentGroup == GetActiveTalentGroup(true) then
					retval = template
				end
			end
		end
		return retval
	end

	Talented.INSPECT_TALENT_READY = Talented.UpdateInspectTemplate
end

-------------------------------------------------------------------------------
-- pet.lua
--

do
	function Talented:FixPetTemplate(template)
		local data = self:UncompressSpellData(template.class)[1]
		for index = 1, #data - 1 do
			local info = data[index]
			local ninfo = data[index + 1]
			if info.row == ninfo.row and info.column == ninfo.column then
				local talent = not info.inactive
				local value = template[1][index] + template[1][index + 1]
				if talent then
					template[1][index] = value
					template[1][index + 1] = 0
				else
					template[1][index] = 0
					template[1][index + 1] = value
				end
			end
		end
	end

	function Talented:GetPetClass()
		local _, _, _, texture = GetTalentTabInfo(1, nil, true)
		return texture and texture:sub(10)
	end

	local function PetTalentsAvailable()
		local talentGroup = GetActiveTalentGroup(nil, true)
		if not talentGroup then return end
		local has_talent = GetTalentInfo(1, 1, nil, true, talentGroup) or GetTalentInfo(1, 2, nil, true, talentGroup)
		return has_talent
	end

	function Talented:PET_TALENT_UPDATE()
		local class = self:GetPetClass()
		if not class or not PetTalentsAvailable() then return end
		self:FixAlternatesTalents(class)
		local template = self.pet_current
		if not template then
			template = {pet = true, name = TALENT_SPEC_PET_PRIMARY}
			self.pet_current = template
		end
		local talentGroup = GetActiveTalentGroup(nil, true)
		template.talentGroup = talentGroup
		template.class = class
		local info = self:UncompressSpellData(class)
		for tab, tree in ipairs(info) do
			local ttab = template[tab]
			if not ttab then
				ttab = {}
				template[tab] = ttab
			end
			for index in ipairs(tree) do
				ttab[index] = select(5, GetTalentInfo(tab, index, nil, true, talentGroup))
			end
		end
		for _, view in self:IterateTalentViews(template) do
			view:SetClass(class)
			view:Update()
		end
		if self.mode == "apply" then
			self:CheckTalentPointsApplied()
		end
	end

	function Talented:UNIT_PET(_, unit)
		if unit == "player" then
			self:PET_TALENT_UPDATE()
		end
	end

	function Talented:InitializePet()
		self:RegisterEvent("UNIT_PET")
		self:RegisterEvent("PET_TALENT_UPDATE")
		self:PET_TALENT_UPDATE()
	end

	function Talented:FixAlternatesTalents(class)
		local talentGroup = GetActiveTalentGroup(nil, true)
		local data = self:UncompressSpellData(class)[1]
		for index = 1, #data - 1 do
			local info = data[index]
			local ninfo = data[index + 1]
			if info.row == ninfo.row and info.column == ninfo.column then
				local talent = GetTalentInfo(1, index, nil, true, talentGroup)
				local ntalent = GetTalentInfo(1, index + 1, nil, true, talentGroup)
				if talent then
					assert(not ntalent)
					info.inactive = nil
					ninfo.inactive = true
				else
					assert(ntalent)
					info.inactive = true
					ninfo.inactive = nil
				end
				for _, template in pairs(self.db.global.templates) do
					if template.class == class and not template.code then
						local value = template[1][index] + template[1][index + 1]
						if talent then
							template[1][index] = value
							template[1][index + 1] = 0
						else
							template[1][index] = 0
							template[1][index + 1] = value
						end
					end
				end
			end
		end
		for _, view in self:IterateTalentViews() do
			if view.class == class then
				view:SetClass(view.class, true)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- whpet.lua
--

do
	local WH_MAP = "0zMcmVokRsaqbdrfwihuGINALpTjnyxtgevE"
	local WH_PET_INFO_CLASS = "FFCTTTFTT FF       TT  CFCC  CCTCCC FCF CTTFFF"

	local TALENTED_MAP = "012345abcdefABCDEFmnopqrMNOPQRtuvwxy*"
	local TALENTED_CLASS_CODE = {
		F = "Ferocity",
		C = "Cunning",
		T = "Tenacity",
		Ferocity = "t",
		Cunning = "w",
		Tenacity = "*",
		["t"] = "Ferocity",
		["w"] = "Cunning",
		["*"] = "Tenacity"
	}

	function Talented:GetPetClassByFamily(index)
		return TALENTED_CLASS_CODE[WH_PET_INFO_CLASS:sub(index, index)]
	end

	local function GetPetFamilyForClass(class)
		return WH_PET_INFO_CLASS:find(class:sub(1, 1), nil, true)
	end

	local function map(code, src, dst)
		local temp = {}
		for i = 1, string.len(code) do
			local index = assert(src:find(code:sub(i, i), nil, true))
			temp[i] = dst:sub(index, index)
		end
		return table.concat(temp)
	end

	local function ImportCode(code)
		local a = (WH_MAP:find(code:sub(1, 1), nil, true) - 1) * 10
		local b = bit.rshift(WH_MAP:find(code:sub(2, 2), nil, true) - 1, 1)
		local family = a + b
		local class = Talented:GetPetClassByFamily(family)

		return TALENTED_CLASS_CODE[class] .. map(code:sub(3), WH_MAP, TALENTED_MAP)
	end

	local function ExportCode(code)
		local class = TALENTED_CLASS_CODE[code:sub(1, 1)]
		local family = GetPetFamilyForClass(class)

		local a = math.floor(family / 10)
		local b = (family - (a * 10)) * 2 + 1
		return WH_MAP:sub(a + 1, a + 1) .. WH_MAP:sub(b, b) .. map(code:sub(2), TALENTED_MAP, WH_MAP)
	end

	local function FixImportTemplate(self, template)
		local data = self:UncompressSpellData(template.class)[1]
		template = template[1]
		for index, info in ipairs(data) do
			if info.inactive then
				if index > 1 and info.row == data[index - 1].row and info.column == data[index - 1].column then
					template[index - 1] = template[index] + template[index - 1]
				elseif index < #data and info.row == data[index + 1].row and info.column == data[index + 1].column then
					template[index + 1] = template[index] + template[index + 1]
				end
			end
		end
	end

	local function FixExportTemplate(self, template)
		local data = self:UncompressSpellData(template.class)[1]
		template = template[1]
		for index, info in ipairs(data) do
			if info.inactive then
				if index > 1 and info.row == data[index - 1].row and info.column == data[index - 1].column then
					template[index - 1] = template[index] + template[index - 1]
				end
			end
		end
	end

	Talented.importers["/%??petcalc#"] = function(self, url, dst)
		local s, _, code = url:find(".*/%??petcalc#(.*)$")
		if not s or not code then return end
		code = ImportCode(code)
		if not code then return end
		local val, class = self:StringToTemplate(code, dst)
		dst.class = class
		FixImportTemplate(self, dst)
		return dst
	end

	function Talented:ExportWhpetTemplate(template, url)
		if RAID_CLASS_COLORS[template.class] then return end
		FixExportTemplate(self, template)
		local code = ExportCode(self:TemplateToString(template))
		FixImportTemplate(self, template)
		if code then
			url = url or "https://wotlk.evowow.com/?petcalc#%s"
			return url:format(code)
		end
	end
end

function Talented:GLYPH_ADDED()
    self:UpdateView()
end

function Talented:GLYPH_REMOVED()
    self:UpdateView()
end

function Talented:GLYPH_UPDATED()
    self:UpdateView()
end

do
	local addonName = "SynastriaBuildManager"
	local standaloneBuildManagerLoaded = type(IsAddOnLoaded) == "function" and IsAddOnLoaded(addonName) or false
	local SBM = rawget(_G, addonName) or {}
	if not standaloneBuildManagerLoaded then
		_G[addonName] = SBM
	end
	local BUILD_VERSION = "SBM1"
	local SAGE_PERK_IDS = {1561, 1562, 1563, 1564, 1565, 1566, 1567, 1568}

	local function SafeGetHunterBmMask()
		if type(_G.GetHunterBM) ~= "function" then
			return nil
		end
		local ok, v = pcall(_G.GetHunterBM)
		if not ok or v == nil then
			return nil
		end
		v = tonumber(v) or 0
		if v < 0 then
			v = 0
		end
		return v
	end

	local function CollectSynastriaSageSpells()
		if type(_G.GetDruidSpec) ~= "function" then
			return nil
		end
		local spells = {}
		for i = 1, #SAGE_PERK_IDS do
			local perkId = SAGE_PERK_IDS[i]
			local ok, sid = pcall(_G.GetDruidSpec, perkId)
			if not ok then
				return nil
			end
			sid = tonumber(sid) or 0
			if sid < 0 then
				sid = 0
			end
			spells[i] = sid
		end
		return spells
	end

	local ActionTypes = {
		CALL = "call",
		DELAY = "delay",
		CLICK_PERK = "click_perk",
		CLICK_TOGGLE = "click_toggle",
		COMPLETE = "complete"
	}

	local buildActionQueue = {}
	local buildQueueHead = 1
	local buildQueueTail = 0
	local buildQueueFrame = CreateFrame("Frame")
	local buildQueueTimer = 0
	local buildQueueProcessing = false
	local MAX_QUEUE_ACTIONS_PER_TICK = 8

	local function QueueBuildAction(actionType, data)
		buildQueueTail = buildQueueTail + 1
		buildActionQueue[buildQueueTail] = {
			type = actionType,
			data = data or {}
		}
	end

	local function QueueSynastriaSageImport(spellSlots)
		if type(spellSlots) ~= "table" then
			return
		end
		for i = 1, #SAGE_PERK_IDS do
			local spellId = tonumber(spellSlots[i]) or 0
			if spellId > 0 then
				local perkId = SAGE_PERK_IDS[i]
				QueueBuildAction(ActionTypes.CALL, {fn = function()
					if type(_G.ChangeDruidSpec) == "function" then
						pcall(_G.ChangeDruidSpec, perkId, spellId)
					end
				end})
				QueueBuildAction(ActionTypes.DELAY, {duration = 0.02})
			end
		end
	end

	local function QueueSynastriaBmImport(mask)
		mask = tonumber(mask) or 0
		if mask <= 0 then
			return
		end
		QueueBuildAction(ActionTypes.CALL, {fn = function()
			if type(_G.ChangeHunterBM) == "function" then
				pcall(_G.ChangeHunterBM, mask)
			end
		end})
		QueueBuildAction(ActionTypes.DELAY, {duration = 0.05})
		QueueBuildAction(ActionTypes.CALL, {fn = function()
			if type(_G.UpdateHunterBM) == "function" then
				pcall(_G.UpdateHunterBM)
			end
		end})
	end

	local function ClearBuildQueue()
		buildActionQueue = {}
		buildQueueHead = 1
		buildQueueTail = 0
		buildQueueFrame:SetScript("OnUpdate", nil)
		buildQueueTimer = 0
		buildQueueProcessing = false
	end

	local function ProcessBuildQueue(_, elapsed)
		local actionsProcessed = 0
		while buildQueueHead <= buildQueueTail and actionsProcessed < MAX_QUEUE_ACTIONS_PER_TICK do
			local action = buildActionQueue[buildQueueHead]
			if action.type == ActionTypes.DELAY then
				buildQueueTimer = buildQueueTimer + elapsed
				if buildQueueTimer >= (action.data.duration or 0) then
					buildActionQueue[buildQueueHead] = nil
					buildQueueHead = buildQueueHead + 1
					buildQueueTimer = 0
				else
					return
				end
			else
				buildActionQueue[buildQueueHead] = nil
				buildQueueHead = buildQueueHead + 1
				if action.type == ActionTypes.CLICK_PERK then
					local frameName = "PerkMgrFrame-PerkLine-" .. tostring(action.data.position or "")
					local perkFrame = _G[frameName]
					if perkFrame and perkFrame.Click then
						perkFrame:Click()
					end
				elseif action.type == ActionTypes.CLICK_TOGGLE then
					local toggleButton = _G["PerkMgrFrame-Toggle"]
					if toggleButton and toggleButton.Click then
						toggleButton:Click()
					end
				elseif action.type == ActionTypes.CALL then
					local fn = action.data.fn
					if type(fn) == "function" then
						pcall(fn, action.data.payload)
					end
				elseif action.type == ActionTypes.COMPLETE then
					local message = action.data.message
					if message and message ~= "" then
						Talented:Print(message)
					end
				end
				actionsProcessed = actionsProcessed + 1
			end
		end
		if buildQueueHead > buildQueueTail then
			buildActionQueue = {}
			buildQueueHead = 1
			buildQueueTail = 0
			buildQueueFrame:SetScript("OnUpdate", nil)
			buildQueueProcessing = false
		end
	end

	local function StartBuildQueue()
		if buildQueueProcessing then
			return
		end
		buildQueueProcessing = true
		buildQueueTimer = 0
		buildQueueFrame:SetScript("OnUpdate", ProcessBuildQueue)
	end

	local function QueueAction(actionType, data)
		QueueBuildAction(actionType, data)
	end

	local function ProcessQueue(self, elapsed)
		ProcessBuildQueue(self, elapsed)
	end

	local function StartQueue()
		StartBuildQueue()
	end

	local function ClearQueue()
		ClearBuildQueue()
	end

	local function GetPerkActiveState(perkId)
		if type(GetPerkActive) == "function" then
			local ok, value = pcall(GetPerkActive, perkId)
			if ok then
				return value and true or false
			end
		end
		return false
	end

	local function NormalizePerkUiState()
		local filter = _G["PerkMgrFrame-FilterButton"]
		if filter and filter.Click then
			filter:Click()
		end
		if _G.DropDownList1Button1 and _G.DropDownList1Button1.Click then
			_G.DropDownList1Button1:Click()
		end
		local cats = {"Off", "Def", "Sup", "Uti", "Cla", "Clb", "Mis"}
		for _, cat in ipairs(cats) do
			local catFrame = _G["PerkMgrFrame-Cat" .. cat]
			if catFrame and catFrame.isCollapsed and catFrame.Click then
				catFrame:Click()
			end
		end
	end

	function Talented:GetAllSynastriaPerks()
		local perks = {}
		local perkList = _G["PerkMgrFrame-Content1"]
		if not perkList then
			return perks
		end
		NormalizePerkUiState()
		local children = {perkList:GetChildren()}
		local startIndex
		for i = 1, #children do
			local child = children[i]
			if child and child.GetName and child:GetName() == "PerkMgrFrame-PerkLine-1" then
				startIndex = i
				break
			end
		end
		if not startIndex then
			return perks
		end
		for i = startIndex, #children do
			local perkFrame = children[i]
			if perkFrame and perkFrame.perk and perkFrame.perk.id then
				local perkId = perkFrame.perk.id
				perks[#perks + 1] = {
					id = perkId,
					active = GetPerkActiveState(perkId),
					position = i - startIndex + 1
				}
			else
				break
			end
		end
		return perks
	end

	function Talented:ExportPerksString()
		local activePerks = {}
		for _, perk in ipairs(self:GetAllSynastriaPerks()) do
			if perk.active then
				activePerks[#activePerks + 1] = tostring(perk.id)
			end
		end
		table.sort(activePerks, function(a, b)
			return tonumber(a) < tonumber(b)
		end)
		return table.concat(activePerks, ",")
	end

	function Talented:QueuePerkImport(perkString)
		if not perkString or perkString == "" then
			return 0
		end
		local targetPerkIds = {}
		for perkId in string.gmatch(perkString, "([^,]+)") do
			local id = tonumber(perkId)
			if id then
				targetPerkIds[id] = true
			end
		end
		if next(targetPerkIds) == nil then
			return 0
		end

		local perks = self:GetAllSynastriaPerks()
		local deactivateList, activateList = {}, {}
		for _, perk in ipairs(perks) do
			local shouldBeActive = targetPerkIds[perk.id] and true or false
			if perk.active and not shouldBeActive then
				deactivateList[#deactivateList + 1] = perk
			elseif (not perk.active) and shouldBeActive then
				activateList[#activateList + 1] = perk
			end
		end

		local changeCount = 0
		for _, perk in ipairs(deactivateList) do
			QueueBuildAction(ActionTypes.CLICK_PERK, {position = perk.position})
			QueueBuildAction(ActionTypes.DELAY, {duration = 0.01})
			QueueBuildAction(ActionTypes.CLICK_TOGGLE, {})
			QueueBuildAction(ActionTypes.DELAY, {duration = 0.01})
			changeCount = changeCount + 1
		end
		for _, perk in ipairs(activateList) do
			QueueBuildAction(ActionTypes.CLICK_PERK, {position = perk.position})
			QueueBuildAction(ActionTypes.DELAY, {duration = 0.01})
			QueueBuildAction(ActionTypes.CLICK_TOGGLE, {})
			QueueBuildAction(ActionTypes.DELAY, {duration = 0.01})
			changeCount = changeCount + 1
		end
		return changeCount
	end

	local function QueueEnablePerkByIdIfInactive(perkId, perksById)
		local perk = perksById[perkId]
		if not perk or perk.active then
			return false
		end
		QueueBuildAction(ActionTypes.CLICK_PERK, {position = perk.position})
		QueueBuildAction(ActionTypes.DELAY, {duration = 0.01})
		QueueBuildAction(ActionTypes.CLICK_TOGGLE, {})
		QueueBuildAction(ActionTypes.DELAY, {duration = 0.01})
		return true
	end

	function Talented:EnqueueSynastriaDefaultPerks()
		if not self:IsCustomTalentEnvironment() or not self:IsSynastriaDataReady() then
			return false
		end
		local cfg = self.db.profile.synastria_default_perks
		if not cfg or not cfg.enabled then
			return false
		end
		local changePerkOption = _G.ChangePerkOption
		if cfg.prestige_attune_mastery_excess_only then
			ChangePerkOption("Prestige: Attune Mastery", "Excess Only", true, false)
		end
		if type(changePerkOption) == "function" then
			for name, on in pairs(cfg.automatic_buffs or {}) do
				if on then
					pcall(changePerkOption, "Automatic Buffs", name, true, false)
				end
			end
			for name, on in pairs(cfg.misc_options or {}) do
				if on then
					pcall(changePerkOption, "Misc Options", name, true, false)
				end
			end
			for name, on in pairs(cfg.tracking or {}) do
				if on then
					pcall(changePerkOption, "Tracking", name, true, false)
				end
			end
		end
		local perks = self:GetAllSynastriaPerks()
		local perksById = {}
		for _, perk in ipairs(perks) do
			perksById[perk.id] = perk
		end
		local queued = false
		for id, on in pairs(cfg.simple_ids or {}) do
			id = tonumber(id)
			if id and on and QueueEnablePerkByIdIfInactive(id, perksById) then
				queued = true
			end
		end
		return queued
	end

	local function BuildTemplateFromCache(self, className, specCache)
		local info = self:UncompressSpellData(className)
		if not info then
			return nil
		end
		local template = {class = className}
		for tab, tree in ipairs(info) do
			local ttab = {}
			local cacheTab = specCache and specCache[tab]
			for index = 1, #tree do
				ttab[index] = (cacheTab and cacheTab[index]) or 0
			end
			template[tab] = ttab
		end
		return template
	end

	local function GetClassIndex(self, className)
		local classes = self:GetPlayerClasses()
		if self.classIndexOverrides and self.classIndexOverrides[className] then
			local idx = self.classIndexOverrides[className]
			if classes[idx] == className then
				return idx
			end
			self.classIndexOverrides[className] = nil
			if not next(self.classIndexOverrides) then
				self.classIndexOverrides = nil
			end
		end
		for index, name in ipairs(classes) do
			if name == className then
				return index
			end
		end
	end

	local function IsLiveTalentFrameClass(self, className)
		if not className then
			return false
		end
		local liveClass = self:GetCurrentClassFromTalentTabs()
		if liveClass == className then
			return true
		end
		if not self.tabdata or not self.tabdata[className] then
			return false
		end
		local expected = self.tabdata[className][1]
		if not expected then
			return false
		end
		local liveName, _, _, liveBackground = GetTalentTabInfo(1)
		if expected.background and liveBackground and expected.background == liveBackground then
			return true
		end
		if expected.name and liveName and expected.name == liveName then
			return true
		end
		return false
	end

	local function EnsureClassForImport(self, className, forcedIndex)
		local classIndex = GetClassIndex(self, className)
		local indexToUse = forcedIndex or classIndex
		if not indexToUse then
			return false
		end
		local classes = self:GetPlayerClasses()
		local classCount = #classes
		for _ = 1, 2 do
			self.manualClassIndex = indexToUse
			self.manualPlayerClass = className
			self:TryServerClassSwitch(indexToUse, className)
			self:SetManualPlayerClass(className)
			if IsLiveTalentFrameClass(self, className) then
				self.classIndexOverrides = self.classIndexOverrides or {}
				self.classIndexOverrides[className] = indexToUse
				return true
			end
		end
		if classCount >= 2 then
			local alternateIndex = (indexToUse == 1) and 2 or 1
			for _ = 1, 2 do
				self.manualClassIndex = alternateIndex
				self.manualPlayerClass = className
				self:TryServerClassSwitch(alternateIndex, className)
				self:SetManualPlayerClass(className)
				if IsLiveTalentFrameClass(self, className) then
					self.classIndexOverrides = self.classIndexOverrides or {}
					self.classIndexOverrides[className] = alternateIndex
					return true
				end
			end
		end
		return false
	end

	local function BuildEmptyTemplate(self, className)
		local info = self:UncompressSpellData(className)
		if not info then
			return nil
		end
		local template = {class = className}
		for tab, tree in ipairs(info) do
			local ttab = {}
			for index = 1, #tree do
				ttab[index] = 0
			end
			template[tab] = ttab
		end
		return template
	end

	local function TemplateHasPoints(template)
		if type(template) ~= "table" then
			return false
		end
		for tab = 1, #template do
			local ttab = template[tab]
			if type(ttab) == "table" then
				for i = 1, #ttab do
					if (ttab[i] or 0) > 0 then
						return true
					end
				end
			end
		end
		return false
	end

	local BASE36_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	local PERK_PACK_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

	local function ToBase36(value)
		value = tonumber(value) or 0
		if value <= 0 then
			return "0"
		end
		local out = {}
		while value > 0 do
			local rem = math.fmod(value, 36)
			out[#out + 1] = BASE36_ALPHABET:sub(rem + 1, rem + 1)
			value = math.floor(value / 36)
		end
		local i, j = 1, #out
		while i < j do
			out[i], out[j] = out[j], out[i]
			i = i + 1
			j = j - 1
		end
		return table.concat(out)
	end

	local function ParseBase36(text)
		if not text or text == "" then
			return nil
		end
		local value = 0
		for i = 1, #text do
			local ch = text:sub(i, i):upper()
			local idx = BASE36_ALPHABET:find(ch, 1, true)
			if not idx then
				return nil
			end
			value = value * 36 + (idx - 1)
		end
		return value
	end

	local function EncodeVarint32(value)
		local out = {}
		value = tonumber(value) or 0
		repeat
			local chunk = bit.band(value, 31)
			value = bit.rshift(value, 5)
			if value > 0 then
				chunk = chunk + 32
			end
			out[#out + 1] = PERK_PACK_ALPHABET:sub(chunk + 1, chunk + 1)
		until value == 0
		return table.concat(out)
	end

	local function DecodeVarint32Stream(payload)
		local out = {}
		local idx = 1
		local len = #payload
		while idx <= len do
			local shift = 1
			local value = 0
			local hasMore = true
			while hasMore do
				if idx > len then
					return nil
				end
				local ch = payload:sub(idx, idx)
				local pos = PERK_PACK_ALPHABET:find(ch, 1, true)
				if not pos then
					return nil
				end
				local v = pos - 1
				local data = bit.band(v, 31)
				value = value + data * shift
				shift = bit.lshift(shift, 5)
				hasMore = v >= 32
				idx = idx + 1
			end
			out[#out + 1] = value
		end
		return out
	end

	function Talented:EncodePerkPayload(perkCsv)
		if not perkCsv or perkCsv == "" then
			return ""
		end
		local ids, seen = {}, {}
		for raw in perkCsv:gmatch("([^,;]+)") do
			local id = tonumber(raw)
			if id and id > 0 and not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
		if #ids == 0 then
			return ""
		end
		table.sort(ids)
		local chunksP2 = {}
		local chunksP1 = {}
		local prev = 0
		for i, id in ipairs(ids) do
			local delta = (i == 1) and id or (id - prev)
			chunksP2[#chunksP2 + 1] = EncodeVarint32(delta)
			chunksP1[#chunksP1 + 1] = ToBase36(delta)
			prev = id
		end
		local p2 = "P2" .. table.concat(chunksP2, "")
		local p1 = "P1." .. table.concat(chunksP1, ".")
		if #p2 < #p1 then
			return p2
		end
		return p1
	end

	function Talented:DecodePerkPayload(payload)
		if not payload or payload == "" then
			return ""
		end
		if payload:sub(1, 2) == "P2" then
			local body = payload:sub(3)
			if body == "" then
				return ""
			end
			local deltas = DecodeVarint32Stream(body)
			if not deltas then
				return payload:gsub(";", ",")
			end
			local ids = {}
			local current = 0
			for _, delta in ipairs(deltas) do
				current = current + delta
				ids[#ids + 1] = tostring(current)
			end
			return table.concat(ids, ",")
		end
		if payload:sub(1, 3) ~= "P1." then
			return payload:gsub(";", ",")
		end
		local body = payload:sub(4)
		if body == "" then
			return ""
		end
		local ids = {}
		local current = 0
		for token in body:gmatch("([^%.]+)") do
			local delta = ParseBase36(token)
			if not delta then
				return payload:gsub(";", ",")
			end
			current = current + delta
			ids[#ids + 1] = tostring(current)
		end
		return table.concat(ids, ",")
	end

	function Talented:EncodeBmPayload(mask)
		mask = tonumber(mask) or 0
		if mask <= 0 then
			return ""
		end
		return "BM2" .. EncodeVarint32(mask)
	end

	function Talented:DecodeBmPayload(payload)
		if not payload or payload == "" then
			return nil
		end
		if payload:sub(1, 3) ~= "BM2" then
			return nil
		end
		local body = payload:sub(4)
		if body == "" then
			return nil
		end
		local vals = DecodeVarint32Stream(body)
		if not vals or #vals < 1 then
			return nil
		end
		return vals[1]
	end

	function Talented:EncodeSagePayload(spells)
		if type(spells) ~= "table" then
			return ""
		end
		local chunks = {}
		for i = 1, #SAGE_PERK_IDS do
			chunks[#chunks + 1] = EncodeVarint32(tonumber(spells[i]) or 0)
		end
		return "SG2" .. table.concat(chunks, "")
	end

	function Talented:DecodeSagePayload(payload)
		if not payload or payload == "" then
			return nil
		end
		if payload:sub(1, 3) ~= "SG2" then
			return nil
		end
		local body = payload:sub(4)
		local vals = DecodeVarint32Stream(body)
		if not vals or #vals ~= #SAGE_PERK_IDS then
			return nil
		end
		return vals
	end

	function Talented:ExportDualClassTalents()
		self:UpdatePlayerSpecs()
		local lines = {}
		local classes = self:GetPlayerClasses()
		local groupCount = GetNumTalentGroups() or 1
		local currentClass = self:GetCurrentPlayerClass()

		for _, className in ipairs(classes) do
			local classCache = self.multiClassCache and self.multiClassCache[className]
			for spec = 1, groupCount do
				local template
				if className == currentClass and self.alternates and self.alternates[spec] and self.alternates[spec].class == className then
					template = {}
					self:CopyPackedTemplate(self.alternates[spec], template)
					template.class = className
				elseif classCache and classCache[spec] then
					template = BuildTemplateFromCache(self, className, classCache[spec])
				end
				if template then
					local code = self:TemplateToString(template)
					lines[#lines + 1] = ("T:%s:%d:%s"):format(className, spec, code)
				end
			end
		end
		return table.concat(lines, "\n")
	end

	function Talented:ApplyTemplateToActiveGroup(template)
		if not template or not template.class or not RAID_CLASS_COLORS[template.class] then
			return false
		end
		if not IsLiveTalentFrameClass(self, template.class) then
			EnsureClassForImport(self, template.class)
		end
		if not IsLiveTalentFrameClass(self, template.class) then
			self:Print("Skipping %s template: class switch not ready.", template.class)
			return false
		end
		local group = GetActiveTalentGroup()
		if not group then
			return false
		end

		local pointsNeeded = 0
		local tabInfo = self:UncompressSpellData(template.class)
		for tab, tree in ipairs(tabInfo) do
			local ttab = template[tab]
			for index = 1, #tree do
				pointsNeeded = pointsNeeded + ((ttab and ttab[index]) or 0)
			end
		end

		local oldPreview = GetCVar("previewTalents")
		SetCVar("previewTalents", "1")
		ResetGroupPreviewTalentPoints(false, group)

		-- Clear current build to ensure import is an exact match for this class/spec.
		for tab, tree in ipairs(tabInfo) do
			for index = 1, #tree do
				local committedRank = select(5, GetTalentInfo(tab, index, nil, false, group)) or 0
				if committedRank > 0 then
					AddPreviewTalentPoints(tab, index, -committedRank, false, group)
				end
			end
		end

		local availableAfterClear = GetUnspentTalentPoints(nil, false, group) or 0
		if pointsNeeded > availableAfterClear and not self:IsCustomTalentEnvironment() then
			self:Print("Not enough points to apply %s spec %d (need %d).", template.class, group, pointsNeeded)
			SetCVar("previewTalents", oldPreview)
			ResetGroupPreviewTalentPoints(false, group)
			return false
		end

		local cp = availableAfterClear
		local loopGuard = 0
		while true do
			local missing, set = false, false
			for tab, tree in ipairs(tabInfo) do
				local ttab = template[tab]
				for index = 1, #tree do
					local rank = select(9, GetTalentInfo(tab, index, nil, false, group)) or 0
					local targetRank = (ttab and ttab[index]) or 0
					local delta = targetRank - rank
					if delta > 0 then
						AddPreviewTalentPoints(tab, index, delta, false, group)
						local newRank = select(9, GetTalentInfo(tab, index, nil, false, group)) or rank
						if newRank < targetRank then
							missing = true
						elseif newRank > rank then
							set = true
						end
						cp = cp - (newRank - rank)
					end
				end
			end
			if not missing then
				break
			end
			loopGuard = loopGuard + 1
			if (not set) or loopGuard > 60 then
				SetCVar("previewTalents", oldPreview)
				ResetGroupPreviewTalentPoints(false, group)
				return false
			end
		end
		if cp < 0 then
			SetCVar("previewTalents", oldPreview)
			ResetGroupPreviewTalentPoints(false, group)
			return false
		end
		LearnPreviewTalents(false)
		SetCVar("previewTalents", oldPreview)
		return true
	end

	function Talented:ImportDualClassTalents(importText)
		if not importText or importText == "" then
			return false
		end
		local records = {}
		local fallbackClassSpec = {}
		for rawLine in importText:gmatch("[^\r\n]+") do
			local line = rawLine:gsub("^%s*(.-)%s*$", "%1")
			if line ~= "" then
				local className, specText, code = line:match("^T:([^:]+):(%d+):(.+)$")
				if className and code then
					records[#records + 1] = {
						class = className:upper(),
						spec = tonumber(specText) or 1,
						code = code
					}
				else
					local oldClass, oldCode = line:match("^([^:]+):(.+)$")
					if oldClass and oldCode then
						oldClass = oldClass:upper()
						records[#records + 1] = {
							class = oldClass,
							spec = nil,
							code = oldCode
						}
					end
				end
			end
		end
		if #records == 0 then
			return false
		end

		local ordered = {}
		local available = {}
		for _, className in ipairs(self:GetPlayerClasses()) do
			available[className] = true
		end
		for _, className in ipairs(self:GetPlayerClasses()) do
			for _, record in ipairs(records) do
				if record.class == className then
					ordered[#ordered + 1] = record
				end
			end
		end
		if #ordered == 0 then
			return false
		end

		for _, record in ipairs(ordered) do
			local classIndex = GetClassIndex(self, record.class)
			if classIndex and available[record.class] then
				local fallbackIndex
				local classCount = #self:GetPlayerClasses()
				if classCount >= 2 then
					if classIndex == 1 then
						fallbackIndex = 2
					elseif classIndex == 2 then
						fallbackIndex = 1
					end
				end

				QueueBuildAction(ActionTypes.CALL, {
					fn = function(payload)
						EnsureClassForImport(Talented, payload.className, payload.preferredIndex)
					end,
					payload = {
						className = record.class,
						classIndex = classIndex,
						preferredIndex = classIndex
					}
				})
				QueueBuildAction(ActionTypes.DELAY, {duration = 0.80})
				if fallbackIndex then
					QueueBuildAction(ActionTypes.CALL, {
						fn = function(payload)
							if not IsLiveTalentFrameClass(Talented, payload.className) then
								EnsureClassForImport(Talented, payload.className, payload.fallbackIndex)
							end
						end,
						payload = {
							className = record.class,
							fallbackIndex = fallbackIndex
						}
					})
					QueueBuildAction(ActionTypes.DELAY, {duration = 0.80})
				end

				if record.spec then
					QueueBuildAction(ActionTypes.CALL, {
						fn = function(payload)
							if type(SetActiveTalentGroup) == "function" and payload.spec ~= GetActiveTalentGroup() then
								pcall(SetActiveTalentGroup, payload.spec)
							end
						end,
						payload = {spec = record.spec}
					})
					QueueBuildAction(ActionTypes.DELAY, {duration = 0.65})
				end

				local applyDone = {}
				for attempt = 1, 3 do
					QueueBuildAction(ActionTypes.CALL, {
						fn = function(payload)
							if payload.done[payload.className] then
								return
							end
							local template = {}
							local ok = pcall(Talented.StringToTemplate, Talented, payload.code, template)
							if not ok or template.class ~= payload.className then
								if payload.attempt == 1 then
									Talented:Print("Failed to decode talent string for %s.", payload.className)
								end
								return
							end
							local applied = Talented:ApplyTemplateToActiveGroup(template)
							if not applied then
								if payload.fallbackIndex and bit.band(payload.attempt, 1) == 0 then
									EnsureClassForImport(Talented, payload.className, payload.fallbackIndex)
								elseif payload.preferredIndex then
									EnsureClassForImport(Talented, payload.className, payload.preferredIndex)
								else
									EnsureClassForImport(Talented, payload.className)
								end
								applied = Talented:ApplyTemplateToActiveGroup(template)
							end
							if applied then
								Talented:Print("Applied talents for %s.", payload.className)
								payload.done[payload.className] = true
							elseif payload.attempt == 3 then
								Talented:Print("Failed to apply talents for %s.", payload.className)
							end
						end,
						payload = {
							className = record.class,
							code = record.code,
							preferredIndex = classIndex,
							fallbackIndex = fallbackIndex,
							attempt = attempt,
							done = applyDone
						}
					})
					QueueBuildAction(ActionTypes.DELAY, {duration = 0.80})
				end
			end
		end
		return true
	end

	function Talented:ExportSynastriaBuildString()
		self:UpdatePlayerSpecs()
		local perkSnapshot = self:GetAllSynastriaPerks()
		if not perkSnapshot or #perkSnapshot == 0 then
			self:Print("No perk data detected yet. Please open View Perks before exporting a sharable string.")
			return nil
		end
		local classes = self:GetPlayerClasses()
		local activeSpec = GetActiveTalentGroup() or 1
		local tokens = {}
		local exportedClass = {}
		for _, className in ipairs(classes) do
			local template
			if self.alternates and self.alternates[activeSpec] and self.alternates[activeSpec].class == className then
				template = {}
				self:CopyPackedTemplate(self.alternates[activeSpec], template)
				template.class = className
			else
				local classCache = self.multiClassCache and self.multiClassCache[className]
				if classCache and classCache[activeSpec] then
					template = BuildTemplateFromCache(self, className, classCache[activeSpec])
				elseif classCache then
					for spec, specCache in pairs(classCache) do
						if type(spec) == "number" and specCache then
							template = BuildTemplateFromCache(self, className, specCache)
							break
						end
					end
				end
			end
			if (not template) or (not TemplateHasPoints(template)) then
				EnsureClassForImport(self, className)
				self:CaptureClassSpecsFromServer(className)
				if not self:CaptureClassSpecsFromSpellbook(className) then
					-- no-op; keep best known cache snapshot below
				end
				local classCache = self.multiClassCache and self.multiClassCache[className]
				if classCache and classCache[activeSpec] then
					template = BuildTemplateFromCache(self, className, classCache[activeSpec])
				end
			end
			if template then
				local code = self:TemplateToString(template)
				if code and code ~= "" then
					if not TemplateHasPoints(template) then
						self:Print("Warning: %s export appears to have 0 talent points. Open/switch to %s talents before exporting if this is unexpected.", className, className)
					end
					tokens[#tokens + 1] = className
					tokens[#tokens + 1] = code
					exportedClass[className] = true
				end
			end
		end

		-- In dual-class mode, always include both class tokens even if cache is missing.
		if #classes >= 2 then
			for _, className in ipairs(classes) do
				if not exportedClass[className] then
					local classCache = self.multiClassCache and self.multiClassCache[className]
					local template
					if classCache and classCache[activeSpec] then
						template = BuildTemplateFromCache(self, className, classCache[activeSpec])
					end
					if not template then
						self:CaptureClassSpecsFromSpellbook(className)
						classCache = self.multiClassCache and self.multiClassCache[className]
						if classCache and classCache[activeSpec] then
							template = BuildTemplateFromCache(self, className, classCache[activeSpec])
						end
					end
					if not template then
						template = BuildEmptyTemplate(self, className)
					end
					if template then
						local code = self:TemplateToString(template)
						if code and code ~= "" then
							if not TemplateHasPoints(template) then
								self:Print("Warning: %s fallback export is empty (0 points).", className)
							end
							tokens[#tokens + 1] = className
							tokens[#tokens + 1] = code
						end
					end
				end
			end
		end

		local bmMask = SafeGetHunterBmMask()
		if bmMask and bmMask ~= 0 then
			local bmEnc = self:EncodeBmPayload(bmMask)
			if bmEnc ~= "" then
				tokens[#tokens + 1] = "BM"
				tokens[#tokens + 1] = bmEnc
			end
		end

		local sageSpells = CollectSynastriaSageSpells()
		local sageHasData = false
		if sageSpells then
			for si = 1, #sageSpells do
				if (sageSpells[si] or 0) > 0 then
					sageHasData = true
					break
				end
			end
		end
		if sageHasData then
			local sageEnc = self:EncodeSagePayload(sageSpells)
			if sageEnc ~= "" then
				tokens[#tokens + 1] = "SAGE"
				tokens[#tokens + 1] = sageEnc
			end
		end

		local perkCsv = self:ExportPerksString() or ""
		local perkData = self:EncodePerkPayload(perkCsv)
		tokens[#tokens + 1] = "PERKS"
		tokens[#tokens + 1] = perkData
		return table.concat(tokens, ",")
	end

	function Talented:BuildCommunitySubmissionString(name, description, payload, metadata)
		if not payload or payload == "" then
			return nil
		end
		local safeName = tostring(name or "Shared Preset"):gsub('[\r\n"]+', " "):gsub("^%s*(.-)%s*$", "%1")
		local safeDesc = tostring(description or ""):gsub('[\r\n"]+', " "):gsub("^%s*(.-)%s*$", "%1")
		local safeCategory = metadata and tostring(metadata.category or ""):gsub('[\r\n"]+', " "):gsub("^%s*(.-)%s*$", "%1") or ""
		local safeSubCategory = metadata and tostring(metadata.subcategory or ""):gsub('[\r\n"]+', " "):gsub("^%s*(.-)%s*$", "%1") or ""
		local safeIcon = metadata and tostring(metadata.icon or ""):gsub('[\r\n"]+', " "):gsub("^%s*(.-)%s*$", "%1") or ""
		if safeName == "" then
			safeName = "Shared Preset"
		end
		if safeCategory ~= "" or safeSubCategory ~= "" or safeIcon ~= "" then
			return ('SUB2,"%s","%s","%s","%s","%s","%s"'):format(safeName, safeDesc, safeCategory, safeSubCategory, safeIcon, payload)
		end
		return ('SUB1,"%s","%s","%s"'):format(safeName, safeDesc, payload)
	end

	function Talented:GetCommunitySuggestionName()
		if self.template and self.template.talentGroup then
			local specName = self:GetTalentGroupName(self.template.talentGroup)
			if type(specName) == "string" and specName ~= "" then
				return specName
			end
		end
		local displayClass = select(1, UnitClass("player"))
		if type(displayClass) == "string" and displayClass ~= "" then
			return displayClass
		end
		if self.template and self.template.name and self.template.name ~= "" then
			return self.template.name
		end
		return "Shared Preset"
	end

	function Talented:ParseCommunitySubmissionString(text)
		if type(text) ~= "string" then
			return nil
		end
		local compact = text:gsub("^%s*(.-)%s*$", "%1")
		local name2, description2, category2, subCategory2, icon2, payload2 = compact:match('^SUB2,"([^"]*)","([^"]*)","([^"]*)","([^"]*)","([^"]*)","(.-)"$')
		if payload2 and payload2 ~= "" then
			return {
				name = name2,
				description = description2,
				category = category2,
				subcategory = subCategory2,
				icon = icon2,
				payload = payload2
			}
		end
		local name, description, payload = compact:match('^SUB1,"([^"]*)","([^"]*)","(.-)"$')
		if payload and payload ~= "" then
			return {
				name = name,
				description = description,
				payload = payload
			}
		end
		return nil
	end

	function Talented:ExportCommunitySubmission(name, description)
		local payload = self:ExportSynastriaBuildString()
		if not payload or payload == "" then
			return nil
		end
		local defaultName = self:GetCommunitySuggestionName()
		return self:BuildCommunitySubmissionString(name or defaultName, description or "", payload)
	end

	function Talented:ImportSynastriaBuildString(importText)
		if not importText or importText == "" then
			self:Print("Please provide a valid import string.")
			return false
		end
		ClearBuildQueue()
		do
			local submission = self:ParseCommunitySubmissionString(importText)
			if submission and submission.payload then
				importText = submission.payload
				if submission.name and submission.name ~= "" then
					if submission.description and submission.description ~= "" then
						self:Print('Loading preset "%s" - %s', submission.name, submission.description)
					else
						self:Print('Loading preset "%s"', submission.name)
					end
				end
			end
		end
		do
			local compactInput = tostring(importText):gsub("^%s*(.-)%s*$", "%1")
			local wrappedPayload = compactInput:match('^"%s*.-%s*"%s*,%s*"(.-)"%s*$')
			if wrappedPayload and wrappedPayload ~= "" then
				importText = wrappedPayload
			end
		end

		local lines = {}
		for rawLine in importText:gmatch("[^\r\n]+") do
			local line = rawLine:gsub("^%s*(.-)%s*$", "%1")
			if line ~= "" then
				lines[#lines + 1] = line
			end
		end
		if #lines == 0 then
			self:Print("No valid build data found.")
			return false
		end

		do
			local compact = table.concat(lines, ",")
			local tokens = {}
			for token in compact:gmatch("([^,]+)") do
				local trimmed = token:gsub("^%s*(.-)%s*$", "%1")
				if trimmed ~= "" then
					tokens[#tokens + 1] = trimmed
				end
			end
			local perkLine
			local talentLines = {}
			local foundPerksMarker = false
			local bmMaskDecoded = nil
			local sageSlotsDecoded = nil
			local i = 1
			while i <= #tokens do
				local token = tokens[i]
				local up = token:upper()
				if up == "PERKS" then
					foundPerksMarker = true
					perkLine = self:DecodePerkPayload(tokens[i + 1] or "")
					break
				end
				if up == "BM" then
					local enc = tokens[i + 1]
					if enc then
						bmMaskDecoded = self:DecodeBmPayload(enc)
					end
					i = i + 2
				elseif up == "SAGE" then
					local enc = tokens[i + 1]
					if enc then
						sageSlotsDecoded = self:DecodeSagePayload(enc)
					end
					i = i + 2
				else
					local className = up
					local code = tokens[i + 1]
					if not code then
						break
					end
					if self.spelldata and self.spelldata[className] then
						talentLines[#talentLines + 1] = className .. ":" .. code
					end
					i = i + 2
				end
			end
			local hasPerkWork = perkLine and perkLine ~= ""
			local hasTalentWork = #talentLines > 0
			local hasBmWork = bmMaskDecoded and bmMaskDecoded > 0
			local hasSageWork = false
			if sageSlotsDecoded then
				for sj = 1, #sageSlotsDecoded do
					if (sageSlotsDecoded[sj] or 0) > 0 then
						hasSageWork = true
						break
					end
				end
			end
			if foundPerksMarker and (hasTalentWork or hasPerkWork or hasBmWork or hasSageWork) then
				local perkChanges = 0
				ClearBuildQueue()
				self:EnqueueSynastriaDefaultPerks()
				if perkLine and perkLine ~= "" then
					perkChanges = self:QueuePerkImport(perkLine)
				end
				local importedTalents = false
				if #talentLines > 0 then
					importedTalents = self:ImportDualClassTalents(table.concat(talentLines, "\n"))
				end
				if hasSageWork and sageSlotsDecoded then
					QueueSynastriaSageImport(sageSlotsDecoded)
				end
				if hasBmWork and bmMaskDecoded then
					QueueSynastriaBmImport(bmMaskDecoded)
				end
				QueueBuildAction(ActionTypes.COMPLETE, {
					message = ("Synastria build import queued (perk changes: %d, talents: %s)."):format(perkChanges, importedTalents and "yes" or "no")
				})
				StartBuildQueue()
				return true
			end
		end

		local perkLine
		local talentLines = {}
		local offset = 1
		if lines[1] == BUILD_VERSION then
			offset = 2
			local perks = lines[offset]
			if perks and perks:match("^PERKS:") then
				perkLine = perks:gsub("^PERKS:", "")
				offset = offset + 1
			end
			for i = offset, #lines do
				talentLines[#talentLines + 1] = lines[i]
			end
		else
			local first = lines[1]
			if first and first:match("^[0-9,]+$") then
				perkLine = first
				offset = 2
			end
			for i = offset, #lines do
				talentLines[#talentLines + 1] = lines[i]
			end
		end

		local perkChanges = 0
		self:EnqueueSynastriaDefaultPerks()
		if perkLine and perkLine ~= "" then
			perkChanges = self:QueuePerkImport(perkLine)
		end

		local importedTalents = false
		if #talentLines > 0 then
			importedTalents = self:ImportDualClassTalents(table.concat(talentLines, "\n"))
		end

		QueueBuildAction(ActionTypes.COMPLETE, {
			message = ("Synastria build import queued (perk changes: %d, talents: %s)."):format(perkChanges, importedTalents and "yes" or "no")
		})
		StartBuildQueue()
		return true
	end

	function SBM.ImportPerks(importString)
		if not importString or importString == "" then
			Talented:Print("Please provide a valid import string.")
			return
		end
		ClearQueue()
		Talented:EnqueueSynastriaDefaultPerks()
		local changeCount = Talented:QueuePerkImport(importString)
		if changeCount == 0 then
			Talented:Print("Perks are already configured correctly.")
			return
		end
		QueueAction(ActionTypes.COMPLETE, {message = "Perk import completed! Made " .. tostring(changeCount) .. " changes."})
		StartQueue()
	end

	local buildManagerFrame

	function Talented:CreateSynastriaBuildManagerFrame()
		if buildManagerFrame then
			return buildManagerFrame
		end

		local frame = CreateFrame("Frame", "SBM_BuildManagerFrame", UIParent)
		frame:SetSize(500, 640)
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 32,
			insets = {left = 11, right = 12, top = 12, bottom = 11}
		})
		frame:SetBackdropColor(0, 0, 0, 1)
		frame:SetFrameStrata("FULLSCREEN_DIALOG")
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
		frame:Hide()

		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", 0, -15)
		title:SetText("Talented Community Build Export")

		local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		nameLabel:SetPoint("TOPLEFT", 24, -42)
		nameLabel:SetText("Build Name")

		local nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
		nameBox:SetSize(450, 22)
		nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
		nameBox:SetAutoFocus(false)
		nameBox:SetMaxLetters(120)

		local function TrimText(value)
			return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
		end

		local function GetOnlinePlayerName()
			return TrimText(UnitName("player"))
		end

		local function GetDefaultSubmissionCategory()
			local hasMultipleClasses = false
			local playerClasses = self.GetPlayerClasses and self:GetPlayerClasses()
			if type(playerClasses) == "table" and #playerClasses > 1 then
				hasMultipleClasses = true
			end
			if hasMultipleClasses then
				return "Prestige"
			end
			local groupCount = GetNumTalentGroups() or 1
			for talentGroup = 1, groupCount do
				local specName = TrimText(self:GetTalentGroupName(talentGroup))
				if specName ~= "" then
					return specName
				end
			end
			return "Prestige"
		end

		local categoryLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		categoryLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -16)
		categoryLabel:SetText("Category")

		local categoryHelp = CreateFrame("Frame", nil, frame)
		categoryHelp:SetSize(16, 16)
		categoryHelp:SetPoint("LEFT", categoryLabel, "RIGHT", 4, 0)
		categoryHelp:EnableMouse(true)
		local categoryHelpText = categoryHelp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		categoryHelpText:SetPoint("CENTER")
		categoryHelpText:SetText("?")
		categoryHelp:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Category Guide")
			GameTooltip:AddLine("Categories are the build name for example Balance.", 1, 1, 1, true)
			GameTooltip:AddLine("The dif balance variants like Thorns would be under the name of the build but both belong to the Boomie Family, Sage is different because its a new perk set.", 1, 1, 1, true)
			GameTooltip:AddLine("Oathbreaker is a seperate spec from Paladin's for example.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		categoryHelp:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		local categoryBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
		categoryBox:SetSize(220, 22)
		categoryBox:SetPoint("TOPLEFT", categoryLabel, "BOTTOMLEFT", 0, -4)
		categoryBox:SetAutoFocus(false)
		categoryBox:SetMaxLetters(80)
		categoryBox:SetTextInsets(8, 8, 0, 0)
		categoryBox:SetText(GetDefaultSubmissionCategory())
		local categoryBorder = CreateFrame("Frame", nil, frame)
		categoryBorder:SetSize(224, 26)
		categoryBorder:SetPoint("CENTER", categoryBox, "CENTER")
		categoryBorder:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = {left = 2, right = 2, top = 2, bottom = 2}
		})
		categoryBorder:SetBackdropColor(0, 0, 0, 0.85)
		categoryBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		categoryBorder:SetFrameLevel(categoryBox:GetFrameLevel() - 1)

		local subCategoryLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		subCategoryLabel:SetPoint("TOPLEFT", categoryLabel, "TOPLEFT", 250, 0)
		subCategoryLabel:SetText("Author")

		local subCategoryBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
		subCategoryBox:SetSize(194, 22)
		subCategoryBox:SetPoint("TOPLEFT", subCategoryLabel, "BOTTOMLEFT", 0, -4)
		subCategoryBox:SetAutoFocus(false)
		subCategoryBox:SetMaxLetters(80)
		subCategoryBox:SetTextInsets(8, 8, 0, 0)
		local defaultAuthor = GetOnlinePlayerName()
		subCategoryBox:SetText(defaultAuthor ~= "" and defaultAuthor or "Author")
		local subCategoryBorder = CreateFrame("Frame", nil, frame)
		subCategoryBorder:SetSize(198, 26)
		subCategoryBorder:SetPoint("CENTER", subCategoryBox, "CENTER")
		subCategoryBorder:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = {left = 2, right = 2, top = 2, bottom = 2}
		})
		subCategoryBorder:SetBackdropColor(0, 0, 0, 0.85)
		subCategoryBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		subCategoryBorder:SetFrameLevel(subCategoryBox:GetFrameLevel() - 1)

		local iconLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		iconLabel:SetPoint("TOPLEFT", categoryBox, "BOTTOMLEFT", 0, -32)
		iconLabel:SetText("Guide Icon")

		local iconPreview = CreateFrame("Button", nil, frame)
		iconPreview:SetSize(26, 26)
		iconPreview:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -2)
		iconPreview:SetFrameLevel(frame:GetFrameLevel() + 15)
		local iconPreviewTex = iconPreview:CreateTexture(nil, "ARTWORK")
		iconPreviewTex:SetAllPoints(iconPreview)
		iconPreviewTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

		local function UpdateGuideIconPreview(texturePath)
			if type(texturePath) ~= "string" or texturePath == "" then
				iconPreviewTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			else
				iconPreviewTex:SetTexture(texturePath)
			end
		end

		local function CollectMacroIcons()
			local icons = {}
			local seen = {}
			local function addIcon(path)
				if type(path) == "string" and path ~= "" and not seen[path] then
					seen[path] = true
					icons[#icons + 1] = path
				end
			end
			addIcon("Interface\\Icons\\INV_Misc_QuestionMark")
			if type(GetNumMacroIcons) == "function" and type(GetMacroIconInfo) == "function" then
				local count = GetNumMacroIcons() or 0
				for i = 1, count do
					addIcon(GetMacroIconInfo(i))
				end
			elseif type(GetMacroIcons) == "function" then
				local temp = {}
				GetMacroIcons(temp)
				for i = 1, #temp do
					addIcon(temp[i])
				end
			end
			return icons
		end

		frame.selectedGuideIcon = ""
		local picker = CreateFrame("Frame", nil, UIParent)
		picker:SetSize(300, 252)
		picker:SetPoint("CENTER", frame, "CENTER", 0, -4)
		picker:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 24,
			insets = {left = 8, right = 8, top = 8, bottom = 8}
		})
		picker:SetBackdropColor(0, 0, 0, 1)
		picker:SetFrameStrata("FULLSCREEN_DIALOG")
		picker:SetFrameLevel(frame:GetFrameLevel() + 40)
		picker:EnableMouse(true)
		picker:SetToplevel(true)
		picker:Hide()
		picker.allIcons = {}
		picker.icons = {}
		picker.page = 1
		picker.perPage = 24

		local pickerTitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		pickerTitle:SetPoint("TOP", 0, -12)
		pickerTitle:SetText("Select Guide Icon")

		local searchEdit = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
		searchEdit:SetSize(268, 20)
		searchEdit:SetPoint("TOPLEFT", 14, -32)
		searchEdit:SetAutoFocus(false)
		searchEdit:SetMaxLetters(160)
		searchEdit:SetTextInsets(4, 4, 0, 0)

		local function SetPickerNavEnabled(button, enabled)
			if enabled then
				if button.Enable then
					button:Enable()
				elseif button.SetEnabled then
					button:SetEnabled(true)
				end
			else
				if button.Disable then
					button:Disable()
				elseif button.SetEnabled then
					button:SetEnabled(false)
				end
			end
		end

		local RefreshIconPicker
		local function RebuildCommunityIconFilter()
			local query = searchEdit:GetText() or ""
			query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
			local filtered = {}
			if query == "" then
				for i = 1, #picker.allIcons do
					filtered[#filtered + 1] = picker.allIcons[i]
				end
			else
				for i = 1, #picker.allIcons do
					local p = picker.allIcons[i]
					if type(p) == "string" and p:lower():find(query, 1, true) then
						filtered[#filtered + 1] = p
					end
				end
			end
			picker.icons = filtered
			picker.page = 1
			RefreshIconPicker()
		end

		RefreshIconPicker = function()
			local startIndex = (picker.page - 1) * picker.perPage + 1
			local totalPages = math.max(1, math.ceil(#picker.icons / picker.perPage))
			if picker.page > totalPages then
				picker.page = totalPages
				startIndex = (picker.page - 1) * picker.perPage + 1
			end
			for i = 1, picker.perPage do
				local btn = picker.buttons[i]
				local idx = startIndex + i - 1
				local texturePath = picker.icons[idx]
				if texturePath then
					btn.texturePath = texturePath
					btn.icon:SetTexture(texturePath)
					btn:Show()
				else
					btn.texturePath = nil
					btn:Hide()
				end
			end
			picker.pageText:SetText(("Page %d/%d"):format(picker.page, totalPages))
			SetPickerNavEnabled(picker.prevBtn, picker.page > 1)
			SetPickerNavEnabled(picker.nextBtn, picker.page < totalPages)
		end

		searchEdit:SetScript("OnTextChanged", function()
			RebuildCommunityIconFilter()
		end)
		searchEdit:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
		end)

		picker.buttons = {}
		for i = 1, picker.perPage do
			local btn = CreateFrame("Button", nil, picker)
			btn:SetSize(36, 36)
			local col = bit.band(i - 1, 7)
			local row = math.floor((i - 1) / 8)
			btn:SetPoint("TOPLEFT", 18 + col * 34, -58 - row * 38)
			local icon = btn:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints(btn)
			btn.icon = icon
			btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			btn:SetScript("OnClick", function(self)
				if not self.texturePath then
					return
				end
				frame.selectedGuideIcon = self.texturePath
				UpdateGuideIconPreview(self.texturePath)
				picker:Hide()
			end)
			picker.buttons[i] = btn
		end

		picker.prevBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
		picker.prevBtn:SetSize(60, 20)
		picker.prevBtn:SetPoint("BOTTOMLEFT", 14, 12)
		picker.prevBtn:SetText("Prev")
		picker.prevBtn:SetScript("OnClick", function()
			picker.page = picker.page - 1
			RefreshIconPicker()
		end)
		picker.nextBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
		picker.nextBtn:SetSize(60, 20)
		picker.nextBtn:SetPoint("BOTTOMRIGHT", -14, 12)
		picker.nextBtn:SetText("Next")
		picker.nextBtn:SetScript("OnClick", function()
			picker.page = picker.page + 1
			RefreshIconPicker()
		end)
		picker.pageText = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		picker.pageText:SetPoint("BOTTOM", 0, 17)

		local pickIconBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		pickIconBtn:SetSize(64, 22)
		pickIconBtn:SetPoint("LEFT", iconPreview, "RIGHT", 6, 0)
		pickIconBtn:SetFrameLevel(frame:GetFrameLevel() + 15)
		pickIconBtn:SetText("Pick...")
		pickIconBtn:SetScript("OnClick", function()
			picker.allIcons = CollectMacroIcons()
			searchEdit:SetText("")
			picker:SetFrameLevel(frame:GetFrameLevel() + 40)
			RebuildCommunityIconFilter()
			picker:Show()
		end)

		picker.allIcons = CollectMacroIcons()
		searchEdit:SetText("")
		RebuildCommunityIconFilter()

		local payloadLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		payloadLabel:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -32)
		payloadLabel:SetText("Payload (talents + perks)")

		local payloadScroll = CreateFrame("ScrollFrame", nil, frame)
		payloadScroll:SetSize(450, 90)
		payloadScroll:SetPoint("TOPLEFT", payloadLabel, "BOTTOMLEFT", 0, -4)
		local payloadEditBox = CreateFrame("EditBox", nil, payloadScroll)
		payloadEditBox:SetSize(450, 90)
		payloadEditBox:SetPoint("TOPLEFT")
		payloadEditBox:SetMultiLine(true)
		payloadEditBox:SetFontObject(ChatFontNormal)
		payloadEditBox:SetAutoFocus(false)
		payloadEditBox:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			frame:Hide()
		end)
		payloadScroll:SetScrollChild(payloadEditBox)

		local payloadBorder = CreateFrame("Frame", nil, frame)
		payloadBorder:SetSize(454, 94)
		payloadBorder:SetPoint("CENTER", payloadScroll, "CENTER")
		payloadBorder:SetBackdrop({
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = {left = 2, right = 2, top = 2, bottom = 2}
		})
		payloadBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

		local communityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		communityLabel:SetPoint("TOPLEFT", payloadScroll, "BOTTOMLEFT", 0, -10)
		communityLabel:SetText("Community Export (SUB2/SUB1)")

		local communityScroll = CreateFrame("ScrollFrame", nil, frame)
		communityScroll:SetSize(450, 70)
		communityScroll:SetPoint("TOPLEFT", communityLabel, "BOTTOMLEFT", 0, -4)
		local communityEditBox = CreateFrame("EditBox", nil, communityScroll)
		communityEditBox:SetSize(450, 70)
		communityEditBox:SetPoint("TOPLEFT")
		communityEditBox:SetMultiLine(true)
		communityEditBox:SetFontObject(ChatFontNormal)
		communityEditBox:SetAutoFocus(false)
		communityEditBox:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			frame:Hide()
		end)
		communityScroll:SetScrollChild(communityEditBox)

		local communityBorder = CreateFrame("Frame", nil, frame)
		communityBorder:SetSize(454, 74)
		communityBorder:SetPoint("CENTER", communityScroll, "CENTER")
		communityBorder:SetBackdrop({
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = {left = 2, right = 2, top = 2, bottom = 2}
		})
		communityBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

		local submitGuideLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		submitGuideLabel:SetPoint("TOPLEFT", communityScroll, "BOTTOMLEFT", 0, -8)
		submitGuideLabel:SetWidth(450)
		submitGuideLabel:SetJustifyH("LEFT")
		submitGuideLabel:SetJustifyV("TOP")
		submitGuideLabel:SetText(
			"Submit to Discord:\n" ..
			"I am handing out 5k gold bounty for all submissions.\n" ..
			"1. Click Export Both.\n" ..
			"2. Copy the Community Export text.\n" ..
			"3. Open Discord and message @qtasc.\n" ..
			"4. Paste the full Community Export string.\n" ..
			"5. Ask for inclusion in the next update."
		)

		local function BuildCurrentCommunityExport()
			local name = nameBox:GetText()
			local payload = Talented:ExportSynastriaBuildString()
			if TrimText(name) == "" then
				name = Talented:GetCommunitySuggestionName()
				nameBox:SetText(name)
			end
			payloadEditBox:SetText(payload or "")
			local category = TrimText(categoryBox:GetText())
			if category == "" then
				category = GetDefaultSubmissionCategory()
				categoryBox:SetText(category)
			end
			local subCategory = TrimText(subCategoryBox:GetText())
			if subCategory == "" then
				subCategory = GetOnlinePlayerName()
				if subCategory == "" then
					subCategory = "Author"
				end
				subCategoryBox:SetText(subCategory)
			end
			local out = Talented:BuildCommunitySubmissionString(name, "", payload, {
				category = category,
				subcategory = subCategory,
				icon = frame.selectedGuideIcon or ""
			}) or ""
			communityEditBox:SetText(out)
			return out
		end

		local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		exportBtn:SetSize(130, 22)
		exportBtn:SetPoint("BOTTOMLEFT", 24, 18)
		exportBtn:SetText("Export Both")
		exportBtn:SetScript("OnClick", function()
			local out = BuildCurrentCommunityExport()
			communityEditBox:SetFocus()
			communityEditBox:HighlightText()
		end)

		local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		importBtn:SetSize(90, 22)
		importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
		importBtn:SetText("Import")
		importBtn:SetScript("OnClick", function()
			local input = payloadEditBox:GetText()
			if not input or input == "" then
				input = communityEditBox:GetText()
			end
			Talented:ImportSynastriaBuildString(input or "")
		end)

		local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		closeBtn:SetSize(90, 22)
		closeBtn:SetPoint("BOTTOMRIGHT", -16, 18)
		closeBtn:SetText("Close")
		closeBtn:SetScript("OnClick", function()
			frame:Hide()
		end)
		frame.nameBox = nameBox
		frame.categoryBox = categoryBox
		frame.subCategoryBox = subCategoryBox
		frame.payloadEditBox = payloadEditBox
		frame.communityEditBox = communityEditBox
		frame.editBox = payloadEditBox
		buildManagerFrame = frame
		return frame
	end

	local function CreateBuildManagerFrame()
		return Talented:CreateSynastriaBuildManagerFrame()
	end

	function Talented:ToggleSynastriaBuildManager()
		local frame = self:CreateSynastriaBuildManagerFrame()
	local function hasText(value)
		return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1") ~= ""
	end
		if frame:IsShown() then
			frame:Hide()
		else
			if _G.TalentedFrame and _G.TalentedFrame.GetFrameLevel then
				frame:SetFrameLevel(_G.TalentedFrame:GetFrameLevel() + 30)
			end
			frame:Show()
		if frame.nameBox and not hasText(frame.nameBox:GetText()) then
				frame.nameBox:SetText(self:GetCommunitySuggestionName())
			end
		if frame.categoryBox and not hasText(frame.categoryBox:GetText()) then
				frame.categoryBox:SetText(GetDefaultSubmissionCategory())
			end
		if frame.subCategoryBox and not hasText(frame.subCategoryBox:GetText()) then
				local authorName = GetOnlinePlayerName()
				frame.subCategoryBox:SetText(authorName ~= "" and authorName or "Author")
			end
			frame.payloadEditBox:SetFocus()
			frame.payloadEditBox:SetCursorPosition(0)
		end
	end

	function Talented:AddPerksToFrame(baseFrame)
		if not baseFrame then
			return
		end
		baseFrame.perkTab = true
		if baseFrame.sbmBuildButton then
			return
		end
		local button = CreateFrame("Button", nil, baseFrame, "UIPanelButtonTemplate")
		button:SetSize(110, 22)
		button:SetPoint("TOPRIGHT", baseFrame, "TOPRIGHT", -200, -5)
		button:SetText("Build Manager")
		button:SetScript("OnClick", function()
			Talented:ToggleSynastriaBuildManager()
		end)
		baseFrame.sbmBuildButton = button
		if self.uielements then
			self.uielements[#self.uielements + 1] = button
		end
	end

	function Talented:AddSynastriaBuildManagerButton()
		return
	end

	local function AddBuildManagerButton()
		Talented:AddSynastriaBuildManagerButton()
	end

	function Talented:InitializeSynastriaBuildManagerHook()
		return
	end

	if not standaloneBuildManagerLoaded then
		_G.GetAllPerks = function()
			return Talented:GetAllSynastriaPerks()
		end

		_G.SBM = SBM

		_G.ExportDualClassTalents = function()
			return Talented:ExportDualClassTalents()
		end

		_G.ImportDualClassTalents = function(importText)
			ClearBuildQueue()
			local ok = Talented:ImportDualClassTalents(importText)
			if ok then
				QueueBuildAction(ActionTypes.COMPLETE, {message = "Talent import queued."})
				StartBuildQueue()
			end
			return ok
		end
	end
end
