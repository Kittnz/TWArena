-- Arena Teams Addon for WoW 1.12.1
-- Provides a GUI interface for the Arena Team system

-- Initialize addon
ArenaTeams = {}
ArenaTeams.version = "1.0"

-- Saved variables - Initialize properly
ArenaTeamsDB = {}

-- Data storage
ArenaTeams.myTeams = {}
ArenaTeams.teamRosters = {}
ArenaTeams.topTeams = {}
ArenaTeams.isWaitingForResponse = false
ArenaTeams.currentTeamId = nil

-- Constants
local ARENA_TYPES = {"2v2", "3v3", "5v5"}
local ARENA_TYPE_COLORS = {
    ["2v2"] = "|cff00ff00", -- Green
    ["3v3"] = "|cffff8000", -- Orange  
    ["5v5"] = "|cffff0000"  -- Red
}

-- Frame references
local mainFrame = nil
local createFrame = nil
local rosterFrame = nil
local topFrame = nil
local minimapButton = nil

-- Minimap button
local minimapButtonDB = {
    position = 180,
    enabled = true
}

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Auto refresh timer
local refreshTimer = 0
local REFRESH_INTERVAL = 60 -- seconds

-- Utility functions
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Arena Teams]|r " .. msg)
end

local function SendArenaCommand(command)
    ArenaTeams.isWaitingForResponse = true
    SendChatMessage(".arena " .. command, "SAY")
end

local function ParseTeamInfo(text)
    -- Parse "Arena Team: Team Name (Type: 3v3)"
    local teamName, teamType = string.match(text, "Arena Team: (.+) %(Type: (%d+v%d+)%)")
    if teamName and teamType then
        return teamName, teamType
    end
    return nil, nil
end

local function ParseTeamDetails(text)
    -- Parse "Team ID: 123 | Rating: 1500 | Rank: 1"
    local teamId, rating, rank = string.match(text, "Team ID: (%d+) %| Rating: (%d+) %| Rank: (%d+)")
    if teamId and rating and rank then
        return tonumber(teamId), tonumber(rating), tonumber(rank)
    end
    return nil, nil, nil
end

local function ParseRosterMember(text)
    -- Parse "PlayerName [Online] - Captain | Personal Rating: 1500 | Season: 10/25 | Week: 2/5"
    local name, status, role, rating, seasonWins, seasonGames, weekWins, weekGames = 
        string.match(text, "(.+) %[(.+)%] %- (.+) %| Personal Rating: (%d+) %| Season: (%d+)/(%d+) %| Week: (%d+)/(%d+)")
    if name and status and role and rating then
        return {
            name = name,
            online = (status == "Online"),
            role = role,
            personalRating = tonumber(rating),
            seasonWins = tonumber(seasonWins),
            seasonGames = tonumber(seasonGames),
            weekWins = tonumber(weekWins),
            weekGames = tonumber(weekGames)
        }
    end
    return nil
end

local function ParseTopTeam(text)
    -- Parse "1. TeamName - Rating: 1500 (Rank: 1) - 10/25 games"
    local rank, teamName, rating, teamRank, wins, games = 
        string.match(text, "(%d+)%. (.+) %- Rating: (%d+) %(Rank: (%d+)%) %- (%d+)/(%d+) games")
    if rank and teamName and rating then
        return {
            rank = tonumber(rank),
            name = teamName,
            rating = tonumber(rating),
            teamRank = tonumber(teamRank),
            wins = tonumber(wins),
            games = tonumber(games)
        }
    end
    return nil
end

-- Static popup dialogs
StaticPopupDialogs["ARENA_CONFIRM_LEAVE"] = {
    text = "Are you sure you want to leave this arena team?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        SendArenaCommand("leave " .. ArenaTeams.currentTeamId)
        Print("Left arena team.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true
}

StaticPopupDialogs["ARENA_CONFIRM_DISBAND"] = {
    text = "Are you sure you want to disband this arena team? This action cannot be undone!",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        SendArenaCommand("disband " .. ArenaTeams.currentTeamId)
        Print("Disbanded arena team.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true
}

StaticPopupDialogs["ARENA_REMOVE_MEMBER"] = {
    text = "Remove %s from the arena team?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        local playerName = getglobal(this:GetParent():GetName() .. "Text"):GetText()
        local name = string.match(playerName, "Remove (.+) from")
        if name and ArenaTeams.currentTeamId then
            SendArenaCommand("remove " .. name .. " " .. ArenaTeams.currentTeamId)
            Print("Removed " .. name .. " from team.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    hasEditBox = false
}

-- Minimap button functions
local function CreateMinimapButton()
    if minimapButton then return end
    
    minimapButton = CreateFrame("Button", "ArenaTeamsMinimapButton", Minimap)
    minimapButton:SetWidth(32)
    minimapButton:SetHeight(32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    
    -- Icon
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Trophy_06")
    
    -- Border
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetWidth(32)
    border:SetHeight(32)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    -- Tooltip
    minimapButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("Arena Teams")
        GameTooltip:AddLine("Left-click: Open Arena Teams window", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Refresh team data", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handlers
    minimapButton:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            if mainFrame and mainFrame:IsShown() then
                mainFrame:Hide()
            else
                ArenaTeams.ShowMainFrame()
            end
        elseif arg1 == "RightButton" then
            ArenaTeams.RefreshTeamData()
        end
    end)
    
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    
    -- Dragging
    minimapButton:SetScript("OnDragStart", function()
        this:LockHighlight()
        this.isMoving = true
    end)
    
    minimapButton:SetScript("OnDragStop", function()
        this:UnlockHighlight()
        this.isMoving = false
    end)
    
    minimapButton:SetScript("OnUpdate", function()
        if this.isMoving then
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            px, py = px / scale, py / scale
            
            local angle = math.atan2(py - my, px - mx)
            minimapButtonDB.position = math.deg(angle)
            UpdateMinimapButtonPosition()
        end
    end)
    
    UpdateMinimapButtonPosition()
end

local function UpdateMinimapButtonPosition()
    if not minimapButton then return end
    
    local angle = math.rad(minimapButtonDB.position)
    local x = math.cos(angle) * 80
    local y = math.sin(angle) * 80
    
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Main frame creation
local function CreateMainFrame()
    if mainFrame then return end
    
    mainFrame = CreateFrame("Frame", "ArenaTeamsMainFrame", UIParent)
    mainFrame:SetWidth(400)
    mainFrame:SetHeight(500)
    mainFrame:SetPoint("CENTER", 0, 0)
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11}
    })
    mainFrame:SetBackdropColor(0, 0, 0, 1)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    mainFrame:Hide()
    
    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Arena Teams")
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    
    -- My Teams section
    local myTeamsLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    myTeamsLabel:SetPoint("TOPLEFT", 20, -50)
    myTeamsLabel:SetText("My Teams:")
    
    local refreshButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    refreshButton:SetWidth(80)
    refreshButton:SetHeight(22)
    refreshButton:SetPoint("TOPRIGHT", -20, -48)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        ArenaTeams.RefreshTeamData()
    end)
    
    -- Teams list (scrollable)
    local teamsScrollFrame = CreateFrame("ScrollFrame", nil, mainFrame)
    teamsScrollFrame:SetPoint("TOPLEFT", 20, -75)
    teamsScrollFrame:SetPoint("TOPRIGHT", -40, -75)
    teamsScrollFrame:SetHeight(150)
    
    local teamsContent = CreateFrame("Frame", nil, teamsScrollFrame)
    teamsContent:SetWidth(340)
    teamsContent:SetHeight(150)
    teamsScrollFrame:SetScrollChild(teamsContent)
    
    -- Store reference for updating
    mainFrame.teamsContent = teamsContent
    
    -- Buttons section
    local buttonY = -240
    
    -- Create Team button
    local createTeamButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    createTeamButton:SetWidth(100)
    createTeamButton:SetHeight(22)
    createTeamButton:SetPoint("TOPLEFT", 20, buttonY)
    createTeamButton:SetText("Create Team")
    createTeamButton:SetScript("OnClick", function()
        CreateTeamFrame()
    end)
    
    -- View Roster button
    local rosterButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    rosterButton:SetWidth(100)
    rosterButton:SetHeight(22)
    rosterButton:SetPoint("TOP", createTeamButton, "TOP")
    rosterButton:SetPoint("LEFT", createTeamButton, "RIGHT", 10, 0)
    rosterButton:SetText("View Roster")
    rosterButton:SetScript("OnClick", function()
        if ArenaTeams.currentTeamId then
            ShowRosterFrame(ArenaTeams.currentTeamId)
        else
            Print("Please select a team first.")
        end
    end)
    
    -- Top Teams button
    local topTeamsButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    topTeamsButton:SetWidth(100)
    topTeamsButton:SetHeight(22)
    topTeamsButton:SetPoint("TOP", rosterButton, "TOP")
    topTeamsButton:SetPoint("LEFT", rosterButton, "RIGHT", 10, 0)
    topTeamsButton:SetText("Top Teams")
    topTeamsButton:SetScript("OnClick", function()
        ShowTopTeamsFrame()
    end)
    
    -- Queue button
    local queueButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    queueButton:SetWidth(100)
    queueButton:SetHeight(22)
    queueButton:SetPoint("TOPLEFT", 20, buttonY - 30)
    queueButton:SetText("Queue Arena")
    queueButton:SetScript("OnClick", function()
        if ArenaTeams.currentTeamId then
            SendArenaCommand("queue " .. ArenaTeams.currentTeamId)
            Print("Queuing for arena with team ID: " .. ArenaTeams.currentTeamId)
        else
            Print("Please select a team first.")
        end
    end)
    
    -- Team management section
    local managementLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    managementLabel:SetPoint("TOPLEFT", 20, buttonY - 65)
    managementLabel:SetText("Team Management:")
    
    -- Invite player
    local inviteEditBox = CreateFrame("EditBox", nil, mainFrame, "InputBoxTemplate")
    inviteEditBox:SetWidth(120)
    inviteEditBox:SetHeight(20)
    inviteEditBox:SetPoint("TOPLEFT", 20, buttonY - 90)
    inviteEditBox:SetAutoFocus(false)
    
    local inviteButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    inviteButton:SetWidth(80)
    inviteButton:SetHeight(22)
    inviteButton:SetPoint("LEFT", inviteEditBox, "RIGHT", 10, 0)
    inviteButton:SetText("Invite")
    inviteButton:SetScript("OnClick", function()
        local playerName = inviteEditBox:GetText()
        if playerName ~= "" and ArenaTeams.currentTeamId then
            SendArenaCommand("invite " .. playerName .. " " .. ArenaTeams.currentTeamId)
            inviteEditBox:SetText("")
        else
            Print("Enter a player name and select a team.")
        end
    end)
    
    -- Leave team button
    local leaveButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    leaveButton:SetWidth(80)
    leaveButton:SetHeight(22)
    leaveButton:SetPoint("TOPLEFT", 20, buttonY - 120)
    leaveButton:SetText("Leave Team")
    leaveButton:SetScript("OnClick", function()
        if ArenaTeams.currentTeamId then
            StaticPopup_Show("ARENA_CONFIRM_LEAVE")
        else
            Print("Please select a team first.")
        end
    end)
    
    -- Disband team button (for captains)
    local disbandButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    disbandButton:SetWidth(80)
    disbandButton:SetHeight(22)
    disbandButton:SetPoint("LEFT", leaveButton, "RIGHT", 10, 0)
    disbandButton:SetText("Disband")
    disbandButton:SetScript("OnClick", function()
        if ArenaTeams.currentTeamId then
            StaticPopup_Show("ARENA_CONFIRM_DISBAND")
        else
            Print("Please select a team first.")
        end
    end)
    
    -- Auto-refresh checkbox
    local autoRefreshCheck = CreateFrame("CheckButton", nil, mainFrame, "UICheckButtonTemplate")
    autoRefreshCheck:SetPoint("BOTTOMLEFT", 20, 30)
    -- Safe initialization - default to true if ArenaTeamsDB is not ready
    local autoRefreshEnabled = true
    if ArenaTeamsDB and ArenaTeamsDB.autoRefresh ~= nil then
        autoRefreshEnabled = ArenaTeamsDB.autoRefresh
    end
    autoRefreshCheck:SetChecked(autoRefreshEnabled)
    
    local autoRefreshLabel = autoRefreshCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    autoRefreshLabel:SetPoint("LEFT", autoRefreshCheck, "RIGHT", 0, 0)
    autoRefreshLabel:SetText("Auto-refresh (60s)")
    
    autoRefreshCheck:SetScript("OnClick", function()
        -- Ensure ArenaTeamsDB exists before setting
        if not ArenaTeamsDB then
            ArenaTeamsDB = {}
        end
        ArenaTeamsDB.autoRefresh = this:GetChecked()
    end)
    
    mainFrame.autoRefreshCheck = autoRefreshCheck
end

-- Create team frame
function CreateTeamFrame()
    if createFrame then
        createFrame:Show()
        return
    end
    
    createFrame = CreateFrame("Frame", "ArenaTeamsCreateFrame", UIParent)
    createFrame:SetWidth(300)
    createFrame:SetHeight(200)
    createFrame:SetPoint("CENTER", 0, 0)
    createFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11}
    })
    createFrame:SetBackdropColor(0, 0, 0, 1)
    createFrame:EnableMouse(true)
    createFrame:SetMovable(true)
    createFrame:RegisterForDrag("LeftButton")
    createFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    createFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    
    -- Title
    local title = createFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Create Arena Team")
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, createFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    
    -- Team type dropdown
    local typeLabel = createFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    typeLabel:SetPoint("TOPLEFT", 20, -50)
    typeLabel:SetText("Team Type:")
    
    local typeDropDown = CreateFrame("Frame", "ArenaTeamTypeDropDown", createFrame, "UIDropDownMenuTemplate")
    typeDropDown:SetPoint("TOPLEFT", 20, -70)
    UIDropDownMenu_SetWidth(100, typeDropDown)
    UIDropDownMenu_SetText("2v2", typeDropDown)
    
    local function TypeDropDown_OnClick()
        UIDropDownMenu_SetSelectedValue(typeDropDown, this.value)
        UIDropDownMenu_SetText(this.value, typeDropDown)
    end
    
    local function TypeDropDown_Initialize()
        for i, arenaType in ipairs(ARENA_TYPES) do
            local info = {}
            info.text = arenaType
            info.value = arenaType
            info.func = TypeDropDown_OnClick
            UIDropDownMenu_AddButton(info)
        end
    end
    
    UIDropDownMenu_Initialize(typeDropDown, TypeDropDown_Initialize)
    
    -- Team name
    local nameLabel = createFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", 20, -110)
    nameLabel:SetText("Team Name:")
    
    local nameEditBox = CreateFrame("EditBox", nil, createFrame, "InputBoxTemplate")
    nameEditBox:SetWidth(200)
    nameEditBox:SetHeight(20)
    nameEditBox:SetPoint("TOPLEFT", 20, -130)
    nameEditBox:SetAutoFocus(false)
    nameEditBox:SetMaxLetters(24)
    
    -- Create button
    local createButton = CreateFrame("Button", nil, createFrame, "UIPanelButtonTemplate")
    createButton:SetWidth(80)
    createButton:SetHeight(22)
    createButton:SetPoint("BOTTOM", -50, 20)
    createButton:SetText("Create")
    createButton:SetScript("OnClick", function()
        local teamType = UIDropDownMenu_GetSelectedValue(typeDropDown) or "2v2"
        local teamName = nameEditBox:GetText()
        if teamName ~= "" then
            SendArenaCommand("create " .. teamType .. ' "' .. teamName .. '"')
            createFrame:Hide()
            nameEditBox:SetText("")
        else
            Print("Please enter a team name.")
        end
    end)
    
    -- Cancel button
    local cancelButton = CreateFrame("Button", nil, createFrame, "UIPanelButtonTemplate")
    cancelButton:SetWidth(80)
    cancelButton:SetHeight(22)
    cancelButton:SetPoint("BOTTOM", 50, 20)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function()
        createFrame:Hide()
        nameEditBox:SetText("")
    end)
end

-- Show roster frame
function ShowRosterFrame(teamId)
    SendArenaCommand("roster " .. teamId)
    
    if not rosterFrame then
        rosterFrame = CreateFrame("Frame", "ArenaTeamsRosterFrame", UIParent)
        rosterFrame:SetWidth(500)
        rosterFrame:SetHeight(400)
        rosterFrame:SetPoint("CENTER", 100, 0)
        rosterFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11}
        })
        rosterFrame:SetBackdropColor(0, 0, 0, 1)
        rosterFrame:EnableMouse(true)
        rosterFrame:SetMovable(true)
        rosterFrame:RegisterForDrag("LeftButton")
        rosterFrame:SetScript("OnDragStart", function() this:StartMoving() end)
        rosterFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        
        -- Title
        local title = rosterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        title:SetPoint("TOP", 0, -20)
        title:SetText("Team Roster")
        rosterFrame.title = title
        
        -- Close button
        local closeButton = CreateFrame("Button", nil, rosterFrame, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", -5, -5)
        
        -- Roster content (scrollable)
        local rosterScrollFrame = CreateFrame("ScrollFrame", nil, rosterFrame)
        rosterScrollFrame:SetPoint("TOPLEFT", 20, -50)
        rosterScrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)
        
        local rosterContent = CreateFrame("Frame", nil, rosterScrollFrame)
        rosterContent:SetWidth(440)
        rosterScrollFrame:SetScrollChild(rosterContent)
        
        rosterFrame.rosterContent = rosterContent
    end
    
    rosterFrame:Show()
end

-- Show top teams frame
function ShowTopTeamsFrame()
    SendArenaCommand("top")
    
    if not topFrame then
        topFrame = CreateFrame("Frame", "ArenaTeamsTopFrame", UIParent)
        topFrame:SetWidth(600)
        topFrame:SetHeight(500)
        topFrame:SetPoint("CENTER", -100, 0)
        topFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11}
        })
        topFrame:SetBackdropColor(0, 0, 0, 1)
        topFrame:EnableMouse(true)
        topFrame:SetMovable(true)
        topFrame:RegisterForDrag("LeftButton")
        topFrame:SetScript("OnDragStart", function() this:StartMoving() end)
        topFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        
        -- Title
        local title = topFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        title:SetPoint("TOP", 0, -20)
        title:SetText("Top Arena Teams")
        
        -- Close button
        local closeButton = CreateFrame("Button", nil, topFrame, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", -5, -5)
        
        -- Filter buttons
        local filterY = -50
        for i, arenaType in ipairs(ARENA_TYPES) do
            local filterButton = CreateFrame("Button", nil, topFrame, "UIPanelButtonTemplate")
            filterButton:SetWidth(60)
            filterButton:SetHeight(22)
            filterButton:SetPoint("TOPLEFT", 20 + (i-1) * 70, filterY)
            filterButton:SetText(arenaType)
            filterButton:SetScript("OnClick", function()
                SendArenaCommand("top " .. arenaType)
            end)
        end
        
        -- Top teams content (scrollable)
        local topScrollFrame = CreateFrame("ScrollFrame", nil, topFrame)
        topScrollFrame:SetPoint("TOPLEFT", 20, filterY - 30)
        topScrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)
        
        local topContent = CreateFrame("Frame", nil, topScrollFrame)
        topContent:SetWidth(540)
        topScrollFrame:SetScrollChild(topContent)
        
        topFrame.topContent = topContent
    end
    
    topFrame:Show()
end

-- Update my teams display
local function UpdateMyTeamsDisplay()
    if not mainFrame or not mainFrame.teamsContent then return end
    
    -- Clear existing team buttons
    local children = {mainFrame.teamsContent:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
    end
    
    local yOffset = 0
    for _, team in ipairs(ArenaTeams.myTeams) do
        local teamButton = CreateFrame("Button", nil, mainFrame.teamsContent)
        teamButton:SetWidth(320)
        teamButton:SetHeight(30)
        teamButton:SetPoint("TOPLEFT", 10, yOffset)
        
        -- Background
        local bg = teamButton:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        bg:SetAlpha(0.3)
        
        -- Team info text
        local teamText = teamButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        teamText:SetPoint("LEFT", 5, 0)
        local colorCode = ARENA_TYPE_COLORS[team.type] or "|cffffffff"
        teamText:SetText(colorCode .. team.name .. "|r (" .. team.type .. ") - Rating: " .. team.rating)
        
        -- Selection highlight
        local highlight = teamButton:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetAlpha(0.7)
        
        -- Tooltip
        teamButton:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(team.name .. " (" .. team.type .. ")")
            GameTooltip:AddLine("Rating: " .. team.rating, 1, 1, 0)
            GameTooltip:AddLine("Rank: " .. team.rank, 1, 1, 0)
            GameTooltip:AddLine("Team ID: " .. team.id, 0.5, 0.5, 0.5)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to select this team", 0, 1, 0)
            GameTooltip:Show()
        end)
        
        teamButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        teamButton:SetScript("OnClick", function()
            ArenaTeams.currentTeamId = team.id
            Print("Selected team: " .. team.name)
            -- Update visual selection
            for _, child in ipairs({mainFrame.teamsContent:GetChildren()}) do
                if child.selectedBorder then
                    child.selectedBorder:Hide()
                end
            end
            if not this.selectedBorder then
                this.selectedBorder = this:CreateTexture(nil, "OVERLAY")
                this.selectedBorder:SetAllPoints()
                this.selectedBorder:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                this.selectedBorder:SetVertexColor(1, 1, 0, 0.8)
            end
            this.selectedBorder:Show()
        end)
        
        yOffset = yOffset - 35
    end
    
    mainFrame.teamsContent:SetHeight(math.max(150, math.abs(yOffset)))
end

-- Update roster display
local function UpdateRosterDisplay(teamName)
    if not rosterFrame or not rosterFrame.rosterContent then return end
    
    -- Update title
    rosterFrame.title:SetText("Team Roster: " .. teamName)
    
    -- Clear existing roster
    local children = {rosterFrame.rosterContent:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
    end
    
    local yOffset = 0
    for _, member in ipairs(ArenaTeams.teamRosters) do
        local memberFrame = CreateFrame("Frame", nil, rosterFrame.rosterContent)
        memberFrame:SetWidth(420)
        memberFrame:SetHeight(60)
        memberFrame:SetPoint("TOPLEFT", 10, yOffset)
        
        -- Background
        local bg = memberFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        bg:SetVertexColor(0.1, 0.1, 0.2, 0.8)
        
        -- Member name and status
        local nameText = memberFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("TOPLEFT", 5, -5)
        local statusColor = member.online and "|cff00ff00" or "|cff808080"
        local roleColor = (member.role == "Captain") and "|cffffd700" or "|cffffffff"
        nameText:SetText(statusColor .. member.name .. "|r " .. roleColor .. "(" .. member.role .. ")|r")
        
        -- Member stats
        local statsText = memberFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statsText:SetPoint("TOPLEFT", 5, -25)
        statsText:SetText("Rating: " .. member.personalRating .. " | Season: " .. member.seasonWins .. "/" .. member.seasonGames .. " | Week: " .. member.weekWins .. "/" .. member.weekGames)
        
        -- Remove button (for captains)
        if member.role ~= "Captain" then
            local removeButton = CreateFrame("Button", nil, memberFrame, "UIPanelButtonTemplate")
            removeButton:SetWidth(60)
            removeButton:SetHeight(18)
            removeButton:SetPoint("TOPRIGHT", -5, -5)
            removeButton:SetText("Remove")
            removeButton:SetScript("OnClick", function()
                StaticPopup_Show("ARENA_REMOVE_MEMBER", member.name)
            end)
        end
        
        yOffset = yOffset - 65
    end
    
    rosterFrame.rosterContent:SetHeight(math.max(320, math.abs(yOffset)))
end

-- Update top teams display
local function UpdateTopTeamsDisplay()
    if not topFrame or not topFrame.topContent then return end
    
    -- Clear existing teams
    local children = {topFrame.topContent:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
    end
    
    local yOffset = 0
    for _, team in ipairs(ArenaTeams.topTeams) do
        local teamFrame = CreateFrame("Frame", nil, topFrame.topContent)
        teamFrame:SetWidth(520)
        teamFrame:SetHeight(30)
        teamFrame:SetPoint("TOPLEFT", 10, yOffset)
        
        -- Background (alternating colors)
        local bg = teamFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        if math.mod(team.rank, 2) == 0 then
            bg:SetVertexColor(0.1, 0.1, 0.1, 0.5)
        else
            bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        end
        
        -- Rank color based on position
        local rankColor = "|cffffffff"
        if team.rank <= 3 then
            rankColor = "|cffffd700" -- Gold for top 3
        elseif team.rank <= 10 then
            rankColor = "|cffc0c0c0" -- Silver for top 10
        end
        
        local teamText = teamFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        teamText:SetPoint("LEFT", 5, 0)
        teamText:SetText(rankColor .. team.rank .. ". " .. team.name .. "|r - Rating: " .. team.rating .. " (" .. team.wins .. "/" .. team.games .. ")")
        
        -- Win percentage (fixed line)
        local winPct = 0
        if team.games > 0 then
            winPct = math.floor((team.wins / team.games) * 100)
        end
        local pctText = teamFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pctText:SetPoint("RIGHT", -5, 0)
        pctText:SetText(winPct .. "%%")
        
        yOffset = yOffset - 35
    end
    
    topFrame.topContent:SetHeight(math.max(420, math.abs(yOffset)))
end

-- Chat message parsing
local function OnChatMessage(message)
    if not ArenaTeams.isWaitingForResponse then return end
    
    -- Parse team info responses
    local teamName, teamType = ParseTeamInfo(message)
    if teamName and teamType then
        local currentTeam = {name = teamName, type = teamType}
        ArenaTeams.currentTeam = currentTeam
        return
    end
    
    -- Parse team details
    if ArenaTeams.currentTeam then
        local teamId, rating, rank = ParseTeamDetails(message)
        if teamId and rating and rank then
            ArenaTeams.currentTeam.id = teamId
            ArenaTeams.currentTeam.rating = rating
            ArenaTeams.currentTeam.rank = rank
            table.insert(ArenaTeams.myTeams, ArenaTeams.currentTeam)
            ArenaTeams.currentTeam = nil
            UpdateMyTeamsDisplay()
            return
        end
    end
    
    -- Parse roster header
    if string.find(message, "=== Arena Team Roster:") then
        ArenaTeams.teamRosters = {}
        local teamName = string.match(message, "=== Arena Team Roster: (.+) ===")
        ArenaTeams.currentRosterTeam = teamName
        return
    end
    
    -- Parse roster members
    if ArenaTeams.currentRosterTeam then
        local member = ParseRosterMember(message)
        if member then
            table.insert(ArenaTeams.teamRosters, member)
        else
            -- End of roster, update display
            UpdateRosterDisplay(ArenaTeams.currentRosterTeam)
            ArenaTeams.currentRosterTeam = nil
        end
        return
    end
    
    -- Parse top teams header
    if string.find(message, "=== Arena Top Teams") then
        ArenaTeams.topTeams = {}
        return
    end
    
    -- Parse top teams
    local topTeam = ParseTopTeam(message)
    if topTeam then
        table.insert(ArenaTeams.topTeams, topTeam)
        UpdateTopTeamsDisplay()
        return
    end
    
    -- Check for end of responses
    if string.find(message, "You are not a member") or 
       string.find(message, "Arena team") and (string.find(message, "created") or string.find(message, "disbanded")) then
        ArenaTeams.isWaitingForResponse = false
        if string.find(message, "created") then
            -- Refresh team list after creation
            ArenaTeams.RefreshTeamData()
        end
    end
end

-- Public functions
function ArenaTeams.ShowMainFrame()
    CreateMainFrame()
    if not mainFrame:IsShown() then
        mainFrame:Show()
        if table.getn(ArenaTeams.myTeams) == 0 then
            ArenaTeams.RefreshTeamData()
        end
    end
end

function ArenaTeams.RefreshTeamData()
    ArenaTeams.myTeams = {}
    SendArenaCommand("info")
end

function ArenaTeams.ToggleMainFrame()
    CreateMainFrame()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        ArenaTeams.ShowMainFrame()
    end
end

-- Slash commands
SLASH_ARENA1 = "/arena"
SLASH_ARENA2 = "/arenateams"
SlashCmdList["ARENA"] = function(msg)
    local command = string.lower(msg or "")
    
    if command == "" or command == "show" then
        ArenaTeams.ShowMainFrame()
    elseif command == "refresh" then
        ArenaTeams.RefreshTeamData()
    elseif command == "top" then
        ShowTopTeamsFrame()
    elseif command == "minimap" then
        if minimapButtonDB.enabled then
            minimapButtonDB.enabled = false
            if minimapButton then minimapButton:Hide() end
            Print("Minimap button hidden.")
        else
            minimapButtonDB.enabled = true
            CreateMinimapButton()
            minimapButton:Show()
            Print("Minimap button shown.")
        end
    elseif command == "help" then
        Print("Arena Teams Commands:")
        Print("/arena - Show main window")
        Print("/arena refresh - Refresh team data")
        Print("/arena top - Show top teams")
        Print("/arena minimap - Toggle minimap button")
        Print("/arena help - Show this help")
    else
        Print("Unknown command. Type '/arena help' for available commands.")
    end
end

-- Event handling
local function OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local addonName = arg1
        if addonName == "ArenaTeams" then
            -- Initialize ArenaTeamsDB if it doesn't exist
            if not ArenaTeamsDB then
                ArenaTeamsDB = {}
            end
            
            -- Set default values
            if ArenaTeamsDB.autoRefresh == nil then
                ArenaTeamsDB.autoRefresh = true
            end
            
            if not ArenaTeamsDB.minimapButton then
                ArenaTeamsDB.minimapButton = {
                    position = 180,
                    enabled = true
                }
            end
            
            minimapButtonDB = ArenaTeamsDB.minimapButton
            
            Print("Arena Teams v" .. ArenaTeams.version .. " loaded. Type /arena to open.")
            
            -- Create minimap button if enabled
            if minimapButtonDB.enabled then
                CreateMinimapButton()
            end
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = arg1
        OnChatMessage(message)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Auto-refresh on login if teams are empty
        if table.getn(ArenaTeams.myTeams) == 0 then
            ArenaTeams.RefreshTeamData()
        end
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

-- OnUpdate for auto-refresh
local function OnUpdate()
    local elapsed = arg1
    refreshTimer = refreshTimer + elapsed
    
    if refreshTimer >= REFRESH_INTERVAL then
        refreshTimer = 0
        
        -- Auto-refresh if enabled and main frame is shown
        -- Safe check for ArenaTeamsDB and default to true if not set
        local autoRefreshEnabled = true
        if ArenaTeamsDB and ArenaTeamsDB.autoRefresh ~= nil then
            autoRefreshEnabled = ArenaTeamsDB.autoRefresh
        end
        
        if autoRefreshEnabled and mainFrame and mainFrame:IsShown() then
            ArenaTeams.RefreshTeamData()
        end
    end
end

eventFrame:SetScript("OnUpdate", OnUpdate)

-- Save data on logout
local function OnLogout()
    if ArenaTeamsDB then
        ArenaTeamsDB.minimapButton = minimapButtonDB
    end
end

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", OnLogout)