-- ProfCDTracker.lua
-- Tracks profession cooldowns: Mooncloth, Alchemy transmutes, Cured Rugged Hide
-- Works with UNIT_SPELLCAST_SUCCEEDED when the server emits it, otherwise uses chat messages

-- Event frame and module level GUI variables
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
-- SPELL DETECTION DISABLED BY DEFAULT, use /profcd enablespells to turn on

local moonclothCheck, transmuteCheck, curedCheck, soundCheck, slider, dropdown, sliderText

-- Cooldown tracking
local MOONCLOTH_SPELLID = 18560
local ALCHEMY_TRANSMUTE_IDS = {
    -- 1 day cooldown transmutes (essences, etc.)
    [11479] = 1, -- Transmute Iron to Gold
    [11480] = 1, -- Transmute Mithril to Truesilver
    [17559] = 1, -- Transmute Air to Fire
    [17560] = 1, -- Transmute Fire to Earth
    [17561] = 1, -- Transmute Earth to Water
    [17562] = 1, -- Transmute Water to Air
    [17563] = 1, -- Transmute Undeath to Water
    [17564] = 1, -- Transmute Water to Undeath
    [17565] = 1, -- Transmute Life to Earth
    [17566] = 1, -- Transmute Earth to Life
    -- 2 day cooldown transmutes
    [17187] = 2, -- Transmute Arcanite
}
local MOONCLOTH_CD = 4 * 24 * 60 * 60 -- 4 days in seconds
local CURED_RUGGED_CD = 1 * 24 * 60 * 60 -- 1 day in seconds

local warnedMooncloth, warnedTransmute, warnedCuredRugged = false, false, false
local ticker
local isInitialized = false

-- Sounds
local SOUND_PATHS = {
    ["Ready Check"] = "Sound\\interface\\ReadyCheck.wav",
    ["Raid Warning"] = "Sound\\interface\\RaidWarning.wav",
    ["Tell Message"] = "Sound\\interface\\iTellMessage.wav",
    ["Auction Close"] = "Sound\\interface\\AuctionWindowClose.wav",
    ["Auction Open"] = "Sound\\interface\\AuctionWindowOpen.wav",
    ["Level Up"] = "Sound\\interface\\LevelUp.wav"
}

-- Helper functions
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff99ff99ProfCDTracker:|r " .. msg)
end

local function Alert(msg)
    UIErrorsFrame:AddMessage(msg, 1, 1, 0, 1, 3)
    if ProfCDTrackerDB and ProfCDTrackerDB.soundEnabled then
        local path = SOUND_PATHS[ProfCDTrackerDB.soundChoice]
        if path then
            PlaySoundFile(path)
        end
    end
end

-- Initialize defaults
local function InitializeDefaults()
    if not ProfCDTrackerDB then
        ProfCDTrackerDB = {}
    end

    local defaults = {
        moonclothEnabled = true,
        transmuteEnabled = true,
        curedruggedEnabled = true,
        soundEnabled = true,
        soundChoice = "Ready Check",
        repeatInterval = 60,
        mooncloth = 0,
        transmute = 0,
        curedrugged = 0
    }

    for key, defaultValue in pairs(defaults) do
        if ProfCDTrackerDB[key] == nil then
            ProfCDTrackerDB[key] = defaultValue
        end
    end

    -- Validate sound choice exists
    if not SOUND_PATHS[ProfCDTrackerDB.soundChoice] then
        ProfCDTrackerDB.soundChoice = "Ready Check"
    end

    -- Validate repeat interval is within bounds
    if ProfCDTrackerDB.repeatInterval < 10 or ProfCDTrackerDB.repeatInterval > 300 then
        ProfCDTrackerDB.repeatInterval = 60
    end
end

-- Check cooldowns - only if enabled
local function CheckCooldowns(showReadyText)
    if not ProfCDTrackerDB then return end

    local now = time()

    -- Mooncloth
    if ProfCDTrackerDB.moonclothEnabled then
        if ProfCDTrackerDB.mooncloth > now then
            warnedMooncloth = false
        elseif showReadyText or not warnedMooncloth then
            Alert("Mooncloth is READY")
            warnedMooncloth = true
        end
    end

    -- Transmute
    if ProfCDTrackerDB.transmuteEnabled then
        if ProfCDTrackerDB.transmute > now then
            warnedTransmute = false
        elseif showReadyText or not warnedTransmute then
            Alert("Transmute is READY")
            warnedTransmute = true
        end
    end

    -- Cured Rugged Hide
    if ProfCDTrackerDB.curedruggedEnabled then
        if ProfCDTrackerDB.curedrugged > now then
            warnedCuredRugged = false
        elseif showReadyText or not warnedCuredRugged then
            Alert("Cured Rugged Hide is READY")
            warnedCuredRugged = true
        end
    end
end

-- Repeating ticker
local function StartRepeatingCheck()
    if not ProfCDTrackerDB or not isInitialized then return end

    if ticker then
        ticker:Cancel()
        ticker = nil
    end

    if ProfCDTrackerDB.repeatInterval > 0 then
        ticker = C_Timer.NewTicker(ProfCDTrackerDB.repeatInterval, function()
            CheckCooldowns(false)
        end)
    end
end

-- Function to update GUI with current settings
local function UpdateGUIFromSettings()
    if not ProfCDTrackerDB then return end

    if moonclothCheck then
        moonclothCheck:SetChecked(ProfCDTrackerDB.moonclothEnabled)
    end
    if transmuteCheck then
        transmuteCheck:SetChecked(ProfCDTrackerDB.transmuteEnabled)
    end
    if curedCheck then
        curedCheck:SetChecked(ProfCDTrackerDB.curedruggedEnabled)
    end
    if soundCheck then
        soundCheck:SetChecked(ProfCDTrackerDB.soundEnabled)
    end
    if dropdown then
        UIDropDownMenu_SetSelectedName(dropdown, ProfCDTrackerDB.soundChoice)
    end
    if slider and sliderText then
        slider:SetValue(ProfCDTrackerDB.repeatInterval)
        sliderText:SetText("Check interval: " .. ProfCDTrackerDB.repeatInterval .. "s")
    end
end

-- GUI creation function
local function CreateGUI()
    -- GUI panel
    local panel = CreateFrame("Frame", "ProfCDTrackerOptions", InterfaceOptionsFramePanelContainer)
    panel.name = "ProfCDTracker"

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ProfCDTracker Settings")

    -- Mooncloth checkbox
    moonclothCheck = CreateFrame("CheckButton", "ProfCDMoonclothCheck", panel, "UICheckButtonTemplate")
    moonclothCheck:SetPoint("TOPLEFT", 16, -50)
    _G[moonclothCheck:GetName() .. "Text"]:SetText("Enable Mooncloth alerts")
    moonclothCheck:SetScript("OnClick", function(self)
        local newValue = self:GetChecked() and true or false
        ProfCDTrackerDB.moonclothEnabled = newValue
    end)

    -- Transmute checkbox
    transmuteCheck = CreateFrame("CheckButton", "ProfCDTransmuteCheck", panel, "UICheckButtonTemplate")
    transmuteCheck:SetPoint("TOPLEFT", moonclothCheck, "BOTTOMLEFT", 0, -8)
    _G[transmuteCheck:GetName() .. "Text"]:SetText("Enable Transmute alerts")
    transmuteCheck:SetScript("OnClick", function(self)
        local newValue = self:GetChecked() and true or false
        ProfCDTrackerDB.transmuteEnabled = newValue
    end)

    -- Cured Rugged Hide checkbox
    curedCheck = CreateFrame("CheckButton", "ProfCDCuredRuggedCheck", panel, "UICheckButtonTemplate")
    curedCheck:SetPoint("TOPLEFT", transmuteCheck, "BOTTOMLEFT", 0, -8)
    _G[curedCheck:GetName() .. "Text"]:SetText("Enable Cured Rugged Hide alerts")
    curedCheck:SetScript("OnClick", function(self)
        local newValue = self:GetChecked() and true or false
        ProfCDTrackerDB.curedruggedEnabled = newValue
    end)

    -- Sound checkbox
    soundCheck = CreateFrame("CheckButton", "ProfCDSoundCheck", panel, "UICheckButtonTemplate")
    soundCheck:SetPoint("TOPLEFT", curedCheck, "BOTTOMLEFT", 0, -8)
    _G[soundCheck:GetName() .. "Text"]:SetText("Enable sounds")
    soundCheck:SetScript("OnClick", function(self)
        local newValue = self:GetChecked() and true or false
        ProfCDTrackerDB.soundEnabled = newValue
    end)

    -- Sound dropdown
    local dropdownLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropdownLabel:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -16)
    dropdownLabel:SetText("Choose alert sound:")

    dropdown = CreateFrame("Frame", "ProfCDTrackerSoundDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", dropdownLabel, "BOTTOMLEFT", -16, -4)

    UIDropDownMenu_Initialize(dropdown, function(frame, level, menuList)
        local soundNames = {}
        for name, _ in pairs(SOUND_PATHS) do
            table.insert(soundNames, name)
        end
        table.sort(soundNames)

        for _, name in ipairs(soundNames) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.func = function()
                ProfCDTrackerDB.soundChoice = name
                UIDropDownMenu_SetSelectedName(dropdown, name)
            end
            info.checked = (name == ProfCDTrackerDB.soundChoice)
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetWidth(dropdown, 160)

    -- Test sound button
    local testButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testButton:SetSize(100, 22)
    testButton:SetPoint("LEFT", dropdown, "RIGHT", 10, 0)
    testButton:SetText("Test Sound")
    testButton:SetScript("OnClick", function()
        local path = SOUND_PATHS[ProfCDTrackerDB.soundChoice]
        if path then
            PlaySoundFile(path)
        else
            Print("Invalid sound selection: " .. tostring(ProfCDTrackerDB.soundChoice))
        end
    end)

    -- Slider
    slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 20, -30)
    slider:SetMinMaxValues(10, 300)
    slider:SetValueStep(1)
    slider:SetWidth(300)

    sliderText = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sliderText:SetPoint("TOP", slider, "BOTTOM", 0, -2)

    local sliderLow = slider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sliderLow:SetPoint("LEFT", slider, "LEFT", 0, 0)
    sliderLow:SetText("10s")

    local sliderHigh = slider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sliderHigh:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    sliderHigh:SetText("300s")

    slider:SetScript("OnValueChanged", function(self, value)
        local newValue = math.floor(value)
        ProfCDTrackerDB.repeatInterval = newValue
        sliderText:SetText("Check interval: " .. newValue .. "s")
        StartRepeatingCheck()
    end)

    -- Manual check button
    local checkButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    checkButton:SetSize(120, 22)
    checkButton:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -30)
    checkButton:SetText("Check Now")
    checkButton:SetScript("OnClick", function()
        CheckCooldowns(true)
    end)

    -- Status display
    local statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", checkButton, "BOTTOMLEFT", 0, -20)
    statusText:SetText("Use '/profcd' for manual checks and test commands")

    -- Panel okay cancel handlers
    panel.okay = function() end
    panel.cancel = function()
        UpdateGUIFromSettings()
    end

    InterfaceOptions_AddCategory(panel)
end

-- Slash command system
SLASH_PROFCD1 = "/profcd"
SlashCmdList["PROFCD"] = function(msg)
    if not msg then msg = "" end
    msg = string.lower(string.trim(msg))

    if msg == "enablespells" then
        Print("Enabling spell detection...")
        f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        Print("Spell detection enabled, craft mooncloth or transmutes to test")

    elseif msg == "disablespells" then
        Print("Disabling spell detection...")
        f:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        Print("Spell detection disabled")

    elseif msg == "testmoon" then
        Print("=== Testing Mooncloth Cooldown ===")
        ProfCDTrackerDB.mooncloth = time() + 30 -- 30 second test
        warnedMooncloth = false
        Print("Mooncloth cooldown set to 30 seconds for testing")

    elseif msg == "testtrans" then
        Print("=== Testing Transmute Cooldown ===")
        ProfCDTrackerDB.transmute = time() + 30 -- 30 second test
        warnedTransmute = false
        Print("Transmute cooldown set to 30 seconds for testing")

    elseif msg == "testcured" then
        Print("=== Testing Cured Rugged Hide Cooldown ===")
        ProfCDTrackerDB.curedrugged = time() + 30
        warnedCuredRugged = false
        Print("Cured Rugged Hide cooldown set to 30 seconds for testing")

    elseif msg == "clearcds" then
        Print("=== Clearing All Cooldowns ===")
        ProfCDTrackerDB.mooncloth = 0
        ProfCDTrackerDB.transmute = 0
        ProfCDTrackerDB.curedrugged = 0
        warnedMooncloth = false
        warnedTransmute = false
        warnedCuredRugged = false
        Print("All cooldowns cleared, should show as READY")

    elseif msg == "findspells" then
        Print("Now showing spell IDs when you cast.")
        f.debugMode = true

    elseif msg == "stopfind" then
        Print("Stopped showing spell IDs.")
        f.debugMode = false

    elseif msg == "debug" then
        if not ProfCDTrackerDB then
            Print("ProfCDTrackerDB is nil!")
            return
        end
        Print("=== Debug Info ===")
        Print("moonclothEnabled: " .. tostring(ProfCDTrackerDB.moonclothEnabled))
        Print("transmuteEnabled: " .. tostring(ProfCDTrackerDB.transmuteEnabled))
        Print("curedruggedEnabled: " .. tostring(ProfCDTrackerDB.curedruggedEnabled))
        Print("soundEnabled: " .. tostring(ProfCDTrackerDB.soundEnabled))
        Print("soundChoice: " .. tostring(ProfCDTrackerDB.soundChoice))
        Print("repeatInterval: " .. tostring(ProfCDTrackerDB.repeatInterval))

    elseif msg == "status" or msg == "s" then
        if not ProfCDTrackerDB then
            Print("Settings not loaded yet")
            return
        end

        local now = time()
        local moonclothReady = ProfCDTrackerDB.mooncloth <= now
        local transmuteReady = ProfCDTrackerDB.transmute <= now
        local curedReady = ProfCDTrackerDB.curedrugged <= now

        Print("=== Cooldown Status ===")
        if moonclothReady then
            Print("Mooncloth: |cff00ff00READY|r")
        else
            local remaining = ProfCDTrackerDB.mooncloth - now
            local hours = math.floor(remaining / 3600)
            Print(string.format("Mooncloth: |cffff0000%d hours remaining|r", hours))
        end

        if transmuteReady then
            Print("Transmute: |cff00ff00READY|r")
        else
            local remaining = ProfCDTrackerDB.transmute - now
            local hours = math.floor(remaining / 3600)
            Print(string.format("Transmute: |cffff0000%d hours remaining|r", hours))
        end

        if curedReady then
            Print("Cured Rugged Hide: |cff00ff00READY|r")
        else
            local remaining = ProfCDTrackerDB.curedrugged - now
            local hours = math.floor(remaining / 3600)
            Print(string.format("Cured Rugged Hide: |cffff0000%d hours remaining|r", hours))
        end

    elseif msg == "help" then
        Print("=== ProfCDTracker Commands ===")
        Print("/profcd - Manual cooldown check")
        Print("/profcd status - Show detailed cooldown status")
        Print("/profcd debug - Show current settings")
        Print("/profcd testmoon - Set 30s mooncloth cooldown for testing")
        Print("/profcd testtrans - Set 30s transmute cooldown for testing")
        Print("/profcd testcured - Set 30s cured rugged cooldown for testing")
        Print("/profcd clearcds - Clear all cooldowns")
        Print("/profcd enablespells - Enable automatic spell detection")
        Print("/profcd disablespells - Disable automatic spell detection")
        Print("/profcd findspells - Show spell IDs when casting for debugging")
        Print("/profcd stopfind - Stop showing spell IDs")

    else
        -- Default: manual cooldown check
        CheckCooldowns(true)
    end
end

-- Event handler
-- Register extra events for chat detection
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:RegisterEvent("CHAT_MSG_LOOT")

f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5, arg6, spellID)
    if event == "ADDON_LOADED" and arg1 == "ProfCDTracker" then
        InitializeDefaults()
        CreateGUI()
        UpdateGUIFromSettings()
        isInitialized = true
        Print("Loaded successfully, type '/profcd help' for commands")
        Print("Spell detection is OFF by default, use '/profcd enablespells' when needed")

    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(5, function()
            if isInitialized then
                CheckCooldowns(true)
                StartRepeatingCheck()
            end
        end)

    -- SPELL detection (if server supports it)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" and isInitialized then
        if not spellID then return end

        if f.debugMode then
            local spellName = GetSpellInfo(spellID)
            Print("Spell: " .. tostring(spellName) .. " (ID: " .. tostring(spellID) .. ")")
        end

        if spellID == MOONCLOTH_SPELLID then
            ProfCDTrackerDB.mooncloth = time() + MOONCLOTH_CD
            warnedMooncloth = false
            Print("Mooncloth crafted, cooldown started (via spell detection)")

        elseif ALCHEMY_TRANSMUTE_IDS[spellID] then
            local cooldownDays = ALCHEMY_TRANSMUTE_IDS[spellID]
            local cooldownSeconds = cooldownDays * 24 * 60 * 60
            ProfCDTrackerDB.transmute = time() + cooldownSeconds
            warnedTransmute = false
            Print(string.format("Transmute performed, %d day cooldown started (via spell detection)", cooldownDays))

        elseif spellID == 19047 then -- possible retail spell ID for curing rugged hide, may differ on your server
            ProfCDTrackerDB.curedrugged = time() + CURED_RUGGED_CD
            warnedCuredRugged = false
            Print("Cured Rugged Hide crafted, cooldown started (via spell detection)")
        end

    -- CHAT detection (loot or system messages)
    elseif (event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_SYSTEM") and arg1 then
        -- Make pattern matching case insensitive by coercing to lower case
        local msgLower = string.lower(arg1)

        -- Mooncloth
        if string.find(msgLower, "mooncloth") then
            ProfCDTrackerDB.mooncloth = time() + MOONCLOTH_CD
            warnedMooncloth = false
            Print("Mooncloth crafted, cooldown started (via chat detection)")

        -- Transmutes: detect the word "transmute" or common result names used by your server
        elseif string.find(msgLower, "transmute") then
            -- default 1 day unless a known transmutes table is added for chat results
            local cooldownSeconds = 24 * 60 * 60
            ProfCDTrackerDB.transmute = time() + cooldownSeconds
            warnedTransmute = false
            Print("Alchemy transmute performed, cooldown started (via chat detection)")

        -- Cured Rugged Hide
        elseif string.find(msgLower, "cured rugged hide") then
            ProfCDTrackerDB.curedrugged = time() + CURED_RUGGED_CD
            warnedCuredRugged = false
            Print("Cured Rugged Hide crafted, cooldown started (via chat detection)")
        end
    end
end)
