-- Event frame and module-level GUI variables
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

local moonclothCheck, transmuteCheck, soundCheck, slider, dropdown, sliderText

-- Cooldown tracking
local MOONCLOTH_SPELLID = 18560
local ALCHEMY_TRANSMUTE_IDS = {
    [11479]=true,[11480]=true,[17559]=true,[17560]=true,
    [17561]=true,[17562]=true,[17563]=true,[17564]=true,
    [17565]=true,[17566]=true,[17187]=true
}
local MOONCLOTH_CD = 4*24*60*60  -- 4 days in seconds
local TRANSMUTE_CD = 24*60*60    -- 1 day in seconds
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

-- Initialize defaults - this will be called after ADDON_LOADED
local function InitializeDefaults()
    if not ProfCDTrackerDB then
        ProfCDTrackerDB = {}
    end
    
    -- Set defaults for missing values using more robust checking
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
    
    -- Validate sound choice exists
    if not SOUND_PATHS[ProfCDTrackerDB.soundChoice] then
        ProfCDTrackerDB.soundChoice = "Ready Check"
    end
    
    -- Validate repeat interval is within bounds
    if ProfCDTrackerDB.repeatInterval < 10 or ProfCDTrackerDB.repeatInterval > 300 then
        ProfCDTrackerDB.repeatInterval = 60
    end
end

-- Helpers
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

-- Check cooldowns
local function CheckCooldowns(showReadyText)
    if not ProfCDTrackerDB then return end
    
    local now = time()
    
    -- Check mooncloth
    if ProfCDTrackerDB.mooncloth > now then
        warnedMooncloth = false
    elseif ProfCDTrackerDB.moonclothEnabled and (showReadyText or not warnedMooncloth) then
        Alert("Mooncloth is READY")
        warnedMooncloth = true
    end

    -- Check transmute
    if ProfCDTrackerDB.transmute > now then
        warnedTransmute = false
    elseif ProfCDTrackerDB.transmuteEnabled and (showReadyText or not warnedTransmute) then
        Alert("Transmute is READY")
        warnedTransmute = true
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

-- GUI creation function (called after SavedVariables are loaded)
local function CreateGUI()
    -- GUI panel
    local panel = CreateFrame("Frame", "ProfCDTrackerOptions", InterfaceOptionsFramePanelContainer)
    panel.name = "ProfCDTracker"

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ProfCDTracker Settings")

    -- Mooncloth checkbox
    moonclothCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    moonclothCheck:SetPoint("TOPLEFT", 16, -50)
    moonclothCheck.text = moonclothCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moonclothCheck.text:SetPoint("LEFT", moonclothCheck, "RIGHT", 4, 0)
    moonclothCheck.text:SetText("Enable Mooncloth alerts")
    moonclothCheck:SetScript("OnClick", function(self)
        ProfCDTrackerDB.moonclothEnabled = self:GetChecked()
    end)

    -- Transmute checkbox
    transmuteCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    transmuteCheck:SetPoint("TOPLEFT", moonclothCheck, "BOTTOMLEFT", 0, -8)
    transmuteCheck.text = transmuteCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    transmuteCheck.text:SetPoint("LEFT", transmuteCheck, "RIGHT", 4, 0)
    transmuteCheck.text:SetText("Enable Transmute alerts")
    transmuteCheck:SetScript("OnClick", function(self)
        ProfCDTrackerDB.transmuteEnabled = self:GetChecked()
    end)

    -- Sound checkbox
    soundCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    soundCheck:SetPoint("TOPLEFT", transmuteCheck, "BOTTOMLEFT", 0, -8)
    soundCheck.text = soundCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    soundCheck.text:SetPoint("LEFT", soundCheck, "RIGHT", 4, 0)
    soundCheck.text:SetText("Enable sounds")
    soundCheck:SetScript("OnClick", function(self)
        ProfCDTrackerDB.soundEnabled = self:GetChecked()
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
    statusText:SetText("Use '/profcd' command to check cooldowns anytime")

    -- Panel okay/cancel handlers
    panel.okay = function() end
    panel.cancel = function()
        UpdateGUIFromSettings()
    end

    InterfaceOptions_AddCategory(panel)
    
    -- Update GUI elements with current saved values
    UpdateGUIFromSettings()
end

-- Enhanced slash command with status info
SLASH_PROFCD1 = "/profcd"
SlashCmdList["PROFCD"] = function(msg)
    msg = string.lower(string.trim(msg or ""))
    
    if msg == "status" or msg == "s" then
        if not ProfCDTrackerDB then
            Print("Settings not loaded yet")
            return
        end
        
        local now = time()
        local moonclothReady = ProfCDTrackerDB.mooncloth <= now
        local transmuteReady = ProfCDTrackerDB.transmute <= now
        
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
    else
        CheckCooldowns(true)
    end
end

-- Event handler
f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5, arg6, spellID)
    if event == "ADDON_LOADED" and arg1 == "ProfCDTracker" then
        -- Initialize SavedVariables with defaults
        InitializeDefaults()
        -- Create GUI after SavedVariables are loaded
        CreateGUI()
        isInitialized = true
        Print("Loaded successfully - Use '/profcd status' for cooldown info")
        
    elseif event == "PLAYER_LOGIN" then
        -- Delay initial check to ensure everything is loaded
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
            local hours = MOONCLOTH_CD / 3600
            Print(string.format("Mooncloth crafted - %d hour cooldown started", hours))
            
        elseif ALCHEMY_TRANSMUTE_IDS[spellID] then
            ProfCDTrackerDB.transmute = time() + TRANSMUTE_CD
            warnedTransmute = false
            local hours = TRANSMUTE_CD / 3600
            Print(string.format("Transmute performed - %d hour cooldown started", hours))
        end
    end
end)