-- Event frame and module-level GUI variables
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

local moonclothCheck, transmuteCheck, soundCheck, slider, dropdown, sliderText

-- Cooldown tracking
local MOONCLOTH_SPELLID = 18560
local ALCHEMY_TRANSMUTE_IDS = {
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
    [17187] = 2, -- Transmute Arcanite (2-day CD)
}
local MOONCLOTH_CD = 4*24*60*60
local warnedMooncloth, warnedTransmute = false, false
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
        if path then PlaySoundFile(path) end
    end
end

-- Defaults
local function InitializeDefaults()
    if not ProfCDTrackerDB then
        ProfCDTrackerDB = {}
    end
    local defaults = {
        moonclothEnabled = true,
        transmuteEnabled = true, 
        soundEnabled = true,
        soundChoice = "Ready Check",
        repeatInterval = 60,
        mooncloth = 0,
        transmute = 0
    }
    for key, defaultValue in pairs(defaults) do
        if ProfCDTrackerDB[key] == nil then
            ProfCDTrackerDB[key] = defaultValue
        end
    end
    if not SOUND_PATHS[ProfCDTrackerDB.soundChoice] then
        ProfCDTrackerDB.soundChoice = "Ready Check"
    end
    if ProfCDTrackerDB.repeatInterval < 10 or ProfCDTrackerDB.repeatInterval > 300 then
        ProfCDTrackerDB.repeatInterval = 60
    end
end

-- Cooldown checking
local function CheckCooldowns(showReadyText)
    if not ProfCDTrackerDB then return end
    local now = time()

    if ProfCDTrackerDB.moonclothEnabled then
        if ProfCDTrackerDB.mooncloth > now then
            warnedMooncloth = false
        elseif showReadyText or not warnedMooncloth then
            Alert("Mooncloth is READY")
            warnedMooncloth = true
        end
    end

    if ProfCDTrackerDB.transmuteEnabled then
        if ProfCDTrackerDB.transmute > now then
            warnedTransmute = false
        elseif showReadyText or not warnedTransmute then
            Alert("Transmute is READY")
            warnedTransmute = true
        end
    end
end

-- Repeating ticker
local function StartRepeatingCheck()
    if not ProfCDTrackerDB or not isInitialized then return end
    if ticker then ticker:Cancel() ticker = nil end
    if ProfCDTrackerDB.repeatInterval > 0 then
        ticker = C_Timer.NewTicker(ProfCDTrackerDB.repeatInterval, function() 
            CheckCooldowns(false) 
        end)
    end
end

-- Update GUI
local function UpdateGUIFromSettings()
    if not ProfCDTrackerDB then return end
    local function toBool(v) return v == true or v == 1 or v == "true" end
    if moonclothCheck then moonclothCheck:SetChecked(toBool(ProfCDTrackerDB.moonclothEnabled)) end
    if transmuteCheck then transmuteCheck:SetChecked(toBool(ProfCDTrackerDB.transmuteEnabled)) end
    if soundCheck then soundCheck:SetChecked(toBool(ProfCDTrackerDB.soundEnabled)) end
    if dropdown then UIDropDownMenu_SetSelectedName(dropdown, ProfCDTrackerDB.soundChoice) end
    if slider and sliderText then
        slider:SetValue(ProfCDTrackerDB.repeatInterval)
        sliderText:SetText("Check interval: " .. ProfCDTrackerDB.repeatInterval .. "s")
    end
end

-- Create GUI
local function CreateGUI()
    local panel = CreateFrame("Frame", "ProfCDTrackerOptions", InterfaceOptionsFramePanelContainer)
    panel.name = "ProfCDTracker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ProfCDTracker Settings")

    moonclothCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    moonclothCheck:SetPoint("TOPLEFT", 16, -50)
    moonclothCheck.text = moonclothCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moonclothCheck.text:SetPoint("LEFT", moonclothCheck, "RIGHT", 4, 0)
    moonclothCheck.text:SetText("Enable Mooncloth alerts")
    moonclothCheck:SetScript("OnClick", function(self)
        ProfCDTrackerDB.moonclothEnabled = self:GetChecked() and true or false
    end)
    moonclothCheck:SetChecked(ProfCDTrackerDB.moonclothEnabled)

    transmuteCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    transmuteCheck:SetPoint("TOPLEFT", moonclothCheck, "BOTTOMLEFT", 0, -8)
    transmuteCheck.text = transmuteCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    transmuteCheck.text:SetPoint("LEFT", transmuteCheck, "RIGHT", 4, 0)
    transmuteCheck.text:SetText("Enable Transmute alerts")
    transmuteCheck:SetScript("OnClick", function(self)
        ProfCDTrackerDB.transmuteEnabled = self:GetChecked() and true or false
    end)
    transmuteCheck:SetChecked(ProfCDTrackerDB.transmuteEnabled)

    soundCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    soundCheck:SetPoint("TOPLEFT", transmuteCheck, "BOTTOMLEFT", 0, -8)
    soundCheck.text = soundCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soundCheck.text:SetPoint("LEFT", soundCheck, "RIGHT", 4, 0)
    soundCheck.text:SetText("Enable sounds")
    soundCheck:SetScript("OnClick", function(self)
        ProfCDTrackerDB.soundEnabled = self:GetChecked() and true or false
        Print("Sound checkbox clicked - setting to: " .. tostring(ProfCDTrackerDB.soundEnabled))
    end)
    soundCheck:SetChecked(ProfCDTrackerDB.soundEnabled)

    local dropdownLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropdownLabel:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -16)
    dropdownLabel:SetText("Choose alert sound:")

    dropdown = CreateFrame("Frame", "ProfCDTrackerSoundDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", dropdownLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_Initialize(dropdown, function(frame, level, menuList)
        local soundNames = {}
        for name, _ in pairs(SOUND_PATHS) do table.insert(soundNames, name) end
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

    local testButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testButton:SetSize(100, 22)
    testButton:SetPoint("LEFT", dropdown, "RIGHT", 10, 0)
    testButton:SetText("Test Sound")
    testButton:SetScript("OnClick", function()
        local path = SOUND_PATHS[ProfCDTrackerDB.soundChoice]
        if path then PlaySoundFile(path) else Print("Invalid sound: " .. tostring(ProfCDTrackerDB.soundChoice)) end
    end)

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

    local checkButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    checkButton:SetSize(120, 22)
    checkButton:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -30)
    checkButton:SetText("Check Now")
    checkButton:SetScript("OnClick", function() CheckCooldowns(true) end)

    local statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", checkButton, "BOTTOMLEFT", 0, -20)
    statusText:SetText("Use '/profcd' to check cooldowns anytime")

    panel.okay = function() end
    panel.cancel = function() UpdateGUIFromSettings() end
    InterfaceOptions_AddCategory(panel)
end

-- Slash commands
SLASH_PROFCD1 = "/profcd"
SlashCmdList["PROFCD"] = function(msg)
    msg = msg and string.lower(msg) or ""
    if msg == "debug" then
        Print("Debug info:")
        Print("MoonclothEnabled: " .. tostring(ProfCDTrackerDB.moonclothEnabled))
        Print("TransmuteEnabled: " .. tostring(ProfCDTrackerDB.transmuteEnabled))
        Print("SoundEnabled: " .. tostring(ProfCDTrackerDB.soundEnabled))
        Print("SoundChoice: " .. tostring(ProfCDTrackerDB.soundChoice))
        Print("RepeatInterval: " .. tostring(ProfCDTrackerDB.repeatInterval))
        Print("Mooncloth CD: " .. tostring(ProfCDTrackerDB.mooncloth) .. " (" .. (ProfCDTrackerDB.mooncloth - time()) .. "s left)")
        Print("Transmute CD: " .. tostring(ProfCDTrackerDB.transmute) .. " (" .. (ProfCDTrackerDB.transmute - time()) .. "s left)")
    elseif msg == "status" or msg == "" then
        local now = time()
        if ProfCDTrackerDB.mooncloth > now then
            Print("Mooncloth ready in " .. SecondsToTime(ProfCDTrackerDB.mooncloth - now))
        else
            Print("Mooncloth is READY")
        end
        if ProfCDTrackerDB.transmute > now then
            Print("Transmute ready in " .. SecondsToTime(ProfCDTrackerDB.transmute - now))
        else
            Print("Transmute is READY")
        end
    else
        Print("Commands:")
        Print("/profcd - show status")
        Print("/profcd debug - show debug info")
    end
end

-- Event handler
f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5, arg6, spellID)
    if event == "ADDON_LOADED" and arg1 == "ProfCDTracker" then
        InitializeDefaults()
        CreateGUI()
        UpdateGUIFromSettings()
        isInitialized = true
        Print("Loaded successfully, use '/profcd debug' for settings")
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(5, function()
            if isInitialized then
                CheckCooldowns(true)
                StartRepeatingCheck()
            end
        end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" and isInitialized then
        if spellID == MOONCLOTH_SPELLID then
            ProfCDTrackerDB.mooncloth = time() + MOONCLOTH_CD
            warnedMooncloth = false
            Print("Mooncloth crafted, 4-day cooldown started")
        elseif ALCHEMY_TRANSMUTE_IDS[spellID] then
            local cooldownDays = ALCHEMY_TRANSMUTE_IDS[spellID]
            ProfCDTrackerDB.transmute = time() + cooldownDays*24*60*60
            warnedTransmute = false
            Print("Transmute performed, " .. cooldownDays .. "-day cooldown started")
        end
    end
end)
