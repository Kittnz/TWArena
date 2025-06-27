-- TWArena.lua - Main addon file for WoW 1.12
-- Interfaces with TW_ARENA server-side messaging system

-- Addon variables
TWArena = {};
TWArena.VERSION = "1.0.0";
TWArena.ADDON_PREFIX = "TW_ARENA";
TWArena.ADDON_CHANNEL = "GUILD";

-- Arena types
TWArena.ARENA_TYPES = {
    ["2v2"] = 2,
    ["3v3"] = 3,
    ["5v5"] = 5
};

-- Message types from server
TWArena.MSG_TYPES = {
    INFO = "INFO",
    STATS = "STATS", 
    ROSTER = "ROSTER",
    TOP = "TOP",
    CREATE_SUCCESS = "CREATE_SUCCESS",
    INVITE_SUCCESS = "INVITE_SUCCESS",
    INVITED = "INVITED",
    KICK_SUCCESS = "KICK_SUCCESS",
    KICKED = "KICKED",
    DISBAND_SUCCESS = "DISBAND_SUCCESS",
    QUEUE_SUCCESS = "QUEUE_SUCCESS",
    LEAVE_QUEUE_SUCCESS = "LEAVE_QUEUE_SUCCESS",
    ERROR = "ERROR"
};

-- Field delimiters (matching server protocol)
TWArena.FIELD_DELIMITER = ";";
TWArena.ARRAY_DELIMITER = ":";
TWArena.SUBFIELD_DELIMITER = "|";

-- Data storage
TWArena.TeamData = {};
TWArena.QueueStatus = {};

-- UI Frame references
TWArena.Frames = {};

-- Utility Functions
function TWArena:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[TWArena]|r " .. msg);
end

function TWArena:PrintError(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[TWArena Error]|r " .. msg);
end

function TWArena:SendAddonMessage(command, arg1, arg2, arg3, arg4, arg5)
    -- Don't include the prefix in the message - WoW handles that automatically
    local message = command;
    
    if arg1 then
        message = message .. TWArena.FIELD_DELIMITER .. tostring(arg1);
    end
    if arg2 then
        message = message .. TWArena.FIELD_DELIMITER .. tostring(arg2);
    end
    if arg3 then
        message = message .. TWArena.FIELD_DELIMITER .. tostring(arg3);
    end
    if arg4 then
        message = message .. TWArena.FIELD_DELIMITER .. tostring(arg4);
    end
    if arg5 then
        message = message .. TWArena.FIELD_DELIMITER .. tostring(arg5);
    end
    
    -- Clean the message to remove any unwanted characters
    message = string.gsub(message, "^%s+", ""); -- Remove leading whitespace
    message = string.gsub(message, "%s+$", ""); -- Remove trailing whitespace
    
    SendAddonMessage(TWArena.ADDON_PREFIX, message, TWArena.ADDON_CHANNEL);
    TWArena:Print("Sent: [" .. message .. "]");
end

function TWArena:SplitString(str, delimiter)
    local result = {};
    local start = 1;
    local splitStart, splitEnd = string.find(str, delimiter, start);
    
    while splitStart do
        table.insert(result, string.sub(str, start, splitStart - 1));
        start = splitEnd + 1;
        splitStart, splitEnd = string.find(str, delimiter, start);
    end
    
    table.insert(result, string.sub(str, start));
    return result;
end

-- Message Handlers
function TWArena:HandleServerMessage(msg)
    TWArena:Print("Received: " .. msg);
    
    local fields = TWArena:SplitString(msg, TWArena.FIELD_DELIMITER);
    if table.getn(fields) == 0 then
        return;
    end
    
    local msgType = fields[1];
    
    if msgType == TWArena.MSG_TYPES.INFO then
        TWArena:HandleInfoMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.STATS then
        TWArena:HandleStatsMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.ROSTER then
        TWArena:HandleRosterMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.TOP then
        TWArena:HandleTopMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.CREATE_SUCCESS then
        TWArena:HandleCreateSuccessMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.INVITE_SUCCESS then
        TWArena:HandleInviteSuccessMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.INVITED then
        TWArena:HandleInvitedMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.KICK_SUCCESS then
        TWArena:HandleKickSuccessMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.KICKED then
        TWArena:HandleKickedMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.DISBAND_SUCCESS then
        TWArena:HandleDisbandSuccessMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.QUEUE_SUCCESS then
        TWArena:HandleQueueSuccessMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.LEAVE_QUEUE_SUCCESS then
        TWArena:HandleLeaveQueueSuccessMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.ERROR then
        TWArena:HandleErrorMessage(fields);
    else
        TWArena:PrintError("Unknown message type: " .. msgType);
    end
end

function TWArena:HandleInfoMessage(fields)
    TWArena:Print("DEBUG: HandleInfoMessage called with " .. table.getn(fields) .. " fields");
    
    if table.getn(fields) < 2 then
        TWArena:Print("DEBUG: Not enough fields in INFO message");
        return;
    end
    
    TWArena.TeamData = {};
    local teamData = fields[2];
    
    TWArena:Print("DEBUG: Team data string: '" .. teamData .. "'");
    
    if teamData == "No teams found" then
        TWArena:Print("You are not a member of any arena teams.");
        TWArena:UpdateMainFrame();
        return;
    end
    
    -- Parse team data: type:name:role:rating:rank|type:name:role:rating:rank|...
    local teams = TWArena:SplitString(teamData, TWArena.SUBFIELD_DELIMITER);
    
    TWArena:Print("DEBUG: Split into " .. table.getn(teams) .. " teams");
    
    for i = 1, table.getn(teams) do
        local teamInfo = TWArena:SplitString(teams[i], TWArena.ARRAY_DELIMITER);
        TWArena:Print("DEBUG: Team " .. i .. " has " .. table.getn(teamInfo) .. " parts: " .. teams[i]);
        
        if table.getn(teamInfo) >= 5 then
            local arenaTypeNum = teamInfo[1];
            local teamName = teamInfo[2];
            local role = teamInfo[3];
            local rating = tonumber(teamInfo[4]) or 0;
            local rank = tonumber(teamInfo[5]) or 0;
            
            -- Convert numeric arena type to readable format
            local arenaType;
            if arenaTypeNum == "2" then
                arenaType = "2v2";
            elseif arenaTypeNum == "3" then
                arenaType = "3v3";
            elseif arenaTypeNum == "5" then
                arenaType = "5v5";
            else
                arenaType = arenaTypeNum .. "v" .. arenaTypeNum;
            end
            
            TWArena:Print("DEBUG: Processing team - Type: " .. arenaType .. ", Name: " .. teamName .. ", Role: " .. role);
            
            if teamName ~= "None" then
                TWArena.TeamData[arenaType] = {
                    name = teamName,
                    role = role,
                    rating = rating,
                    rank = rank
                };
                TWArena:Print("Added team: " .. arenaType .. " - " .. teamName .. " (Rating: " .. rating .. ")");
            else
                TWArena:Print("DEBUG: Skipping 'None' team for " .. arenaType);
            end
        else
            TWArena:Print("DEBUG: Team info incomplete for team " .. i);
        end
    end
    
    TWArena:UpdateMainFrame();
end

function TWArena:HandleStatsMessage(fields)
    if table.getn(fields) < 9 then
        return;
    end
    
    local arenaType = fields[2];
    local teamName = fields[3];
    local rating = tonumber(fields[4]) or 0;
    local rank = tonumber(fields[5]) or 0;
    local seasonWins = tonumber(fields[6]) or 0;
    local seasonGames = tonumber(fields[7]) or 0;
    local weekWins = tonumber(fields[8]) or 0;
    local weekGames = tonumber(fields[9]) or 0;
    
    TWArena:Print("=== " .. arenaType .. " Team Statistics ===");
    TWArena:Print("Team: " .. teamName);
    TWArena:Print("Rating: " .. rating .. " (Rank: " .. rank .. ")");
    TWArena:Print("Season: " .. seasonWins .. "/" .. seasonGames .. " wins");
    TWArena:Print("This Week: " .. weekWins .. "/" .. weekGames .. " wins");
end

function TWArena:HandleRosterMessage(fields)
    if table.getn(fields) < 3 then
        return;
    end
    
    local arenaType = fields[2];
    local teamName = fields[3];
    local rosterData = fields[4] or "";
    
    TWArena:Print("=== " .. arenaType .. " Team Roster ===");
    TWArena:Print("Team: " .. teamName);
    
    if rosterData == "" then
        TWArena:Print("No roster data available.");
        return;
    end
    
    -- Parse roster data: name:class:role|name:class:role|...
    local members = TWArena:SplitString(rosterData, TWArena.SUBFIELD_DELIMITER);
    
    for i = 1, table.getn(members) do
        local memberInfo = TWArena:SplitString(members[i], TWArena.ARRAY_DELIMITER);
        if table.getn(memberInfo) >= 3 then
            local name = memberInfo[1];
            local class = memberInfo[2];
            local role = memberInfo[3];
            TWArena:Print(string.format("%s (%s) - %s", name, class, role));
        end
    end
end

function TWArena:HandleTopMessage(fields)
    if table.getn(fields) < 3 then
        return;
    end
    
    local arenaType = fields[2];
    local topData = fields[3];
    
    if arenaType == "" then
        TWArena:Print("=== Top Arena Teams (All Types) ===");
    else
        TWArena:Print("=== Top " .. arenaType .. " Teams ===");
    end
    
    if topData == "" then
        TWArena:Print("No top teams data available.");
        return;
    end
    
    -- Parse top teams data: rank:name:type:rating:wins:games|...
    local teams = TWArena:SplitString(topData, TWArena.SUBFIELD_DELIMITER);
    
    for i = 1, table.getn(teams) do
        local teamInfo = TWArena:SplitString(teams[i], TWArena.ARRAY_DELIMITER);
        if table.getn(teamInfo) >= 6 then
            local rank = teamInfo[1];
            local name = teamInfo[2];
            local teamType = teamInfo[3];
            local rating = tonumber(teamInfo[4]) or 0;
            local wins = tonumber(teamInfo[5]) or 0;
            local games = tonumber(teamInfo[6]) or 0;
            TWArena:Print(string.format("%s. %s (%s) - Rating: %d, Record: %d/%d", 
                rank, name, teamType, rating, wins, games));
        end
    end
end

function TWArena:HandleCreateSuccessMessage(fields)
    if table.getn(fields) >= 3 then
        local arenaType = fields[2];
        local teamName = fields[3];
        TWArena:Print("Successfully created " .. arenaType .. " team: " .. teamName);
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleInviteSuccessMessage(fields)
    if table.getn(fields) >= 4 then
        local playerName = fields[2];
        local arenaType = fields[3];
        local teamName = fields[4];
        TWArena:Print("Successfully invited " .. playerName .. " to " .. arenaType .. " team: " .. teamName);
    end
end

function TWArena:HandleInvitedMessage(fields)
    if table.getn(fields) >= 4 then
        local teamName = fields[2];
        local arenaType = fields[3];
        local inviterName = fields[4];
        TWArena:Print("You have been invited to " .. arenaType .. " team '" .. teamName .. "' by " .. inviterName);
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleKickSuccessMessage(fields)
    if table.getn(fields) >= 4 then
        local playerName = fields[2];
        local arenaType = fields[3];
        local teamName = fields[4];
        TWArena:Print("Successfully kicked " .. playerName .. " from " .. arenaType .. " team: " .. teamName);
    end
end

function TWArena:HandleKickedMessage(fields)
    if table.getn(fields) >= 4 then
        local teamName = fields[2];
        local arenaType = fields[3];
        local kicker = fields[4];
        TWArena:Print("You have been kicked from " .. arenaType .. " team '" .. teamName .. "' by " .. kicker);
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleDisbandSuccessMessage(fields)
    if table.getn(fields) >= 3 then
        local arenaType = fields[2];
        local teamName = fields[3];
        TWArena:Print("Successfully disbanded " .. arenaType .. " team: " .. teamName);
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleQueueSuccessMessage(fields)
    if table.getn(fields) >= 3 then
        local arenaType = fields[2];
        local avgTime = tonumber(fields[3]) or 0;
        TWArena:Print("Successfully joined " .. arenaType .. " arena queue. Average wait time: " .. avgTime .. "ms");
        TWArena.QueueStatus[arenaType] = true;
    end
end

function TWArena:HandleLeaveQueueSuccessMessage(fields)
    TWArena:Print("Successfully left arena queue.");
    TWArena.QueueStatus = {};
end

function TWArena:HandleErrorMessage(fields)
    if table.getn(fields) >= 2 then
        TWArena:PrintError(fields[2]);
    end
end

-- API Functions
function TWArena:RequestTeamInfo()
    TWArena:Print("DEBUG: Requesting team info...");
    TWArena:SendAddonMessage("INFO");
end

function TWArena:RequestTeamStats(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("STATS", arenaType);
end

function TWArena:RequestTeamRoster(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("ROSTER", arenaType);
end

function TWArena:RequestTopTeams(arenaType)
    if arenaType and not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("TOP", arenaType or "");
end

function TWArena:CreateTeam(arenaType, teamName)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    if not teamName or string.len(teamName) < 2 or string.len(teamName) > 24 then
        TWArena:PrintError("Team name must be between 2 and 24 characters");
        return;
    end
    TWArena:SendAddonMessage("CREATE", arenaType, teamName);
end

function TWArena:InvitePlayer(playerName, arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    if not playerName or string.len(playerName) == 0 then
        TWArena:PrintError("Player name cannot be empty");
        return;
    end
    TWArena:SendAddonMessage("INVITE", playerName, arenaType);
end

function TWArena:KickPlayer(playerName, arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    if not playerName or string.len(playerName) == 0 then
        TWArena:PrintError("Player name cannot be empty");
        return;
    end
    TWArena:SendAddonMessage("KICK", playerName, arenaType);
end

function TWArena:DisbandTeam(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("DISBAND", arenaType);
end

function TWArena:JoinQueue(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("QUEUE", arenaType);
end

function TWArena:LeaveQueue()
    TWArena:SendAddonMessage("LEAVE_QUEUE");
end

-- UI Functions
function TWArena:CreateMainFrame()
    if TWArena.Frames.Main then
        return;
    end
    
    local frame = CreateFrame("Frame", "TWArenaMainFrame", UIParent);
    frame:SetFrameStrata("DIALOG");
    frame:SetWidth(400);
    frame:SetHeight(300);
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    });
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", function() this:StartMoving(); end);
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); end);
    frame:Hide();
    
    -- Title
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
    title:SetPoint("TOP", frame, "TOP", 0, -15);
    title:SetText("TWArena v" .. TWArena.VERSION);
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5);
    
    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate");
    refreshBtn:SetWidth(80);
    refreshBtn:SetHeight(20);
    refreshBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -45);
    refreshBtn:SetText("Refresh");
    refreshBtn:SetScript("OnClick", function() TWArena:RequestTeamInfo(); end);
    
    -- Team info scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "TWArenaScrollFrame", frame, "UIPanelScrollFrameTemplate");
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -75);
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 15);
    
    local content = CreateFrame("Frame", nil, scrollFrame);
    content:SetWidth(350);
    content:SetHeight(200);
    scrollFrame:SetScrollChild(content);
    
    frame.content = content;
    TWArena.Frames.Main = frame;
    
    TWArena:Print("DEBUG: Main frame created");
end

function TWArena:UpdateMainFrame()
    TWArena:Print("DEBUG: UpdateMainFrame called");
    
    if not TWArena.Frames.Main then
        TWArena:Print("DEBUG: No main frame exists, creating...");
        TWArena:CreateMainFrame();
        return;
    end
    
    local content = TWArena.Frames.Main.content;
    
    -- Clear existing children
    local children = { content:GetChildren() };
    for i = 1, table.getn(children) do
        children[i]:Hide();
        children[i]:SetParent(nil);
    end
    
    local yOffset = 0;
    
    -- Check if we have any team data
    local hasTeams = false;
    local teamCount = 0;
    for arenaType, teamInfo in pairs(TWArena.TeamData) do
        hasTeams = true;
        teamCount = teamCount + 1;
        TWArena:Print("DEBUG: Found team " .. arenaType .. ": " .. teamInfo.name);
    end
    
    TWArena:Print("DEBUG: Total teams found: " .. teamCount);
    
    if not hasTeams then
        local noTeams = content:CreateFontString(nil, "ARTWORK", "GameFontNormal");
        noTeams:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset);
        noTeams:SetText("No arena teams found. Use /arena info to refresh.");
        TWArena:Print("DEBUG: Displaying 'no teams' message");
        return;
    end
    
    for arenaType, teamInfo in pairs(TWArena.TeamData) do
        local teamHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
        teamHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset);
        teamHeader:SetText(arenaType .. " Team: " .. teamInfo.name);
        yOffset = yOffset - 20;
        
        local teamDetails = content:CreateFontString(nil, "ARTWORK", "GameFontNormal");
        teamDetails:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset);
        teamDetails:SetText("Role: " .. teamInfo.role .. " | Rating: " .. teamInfo.rating .. " | Rank: " .. teamInfo.rank);
        yOffset = yOffset - 25;
        
        TWArena:Print("DEBUG: Added UI elements for " .. arenaType);
    end
    
    TWArena:Print("DEBUG: Frame update completed");
end

function TWArena:ToggleMainFrame()
    TWArena:CreateMainFrame();
    
    if TWArena.Frames.Main:IsShown() then
        TWArena.Frames.Main:Hide();
    else
        TWArena.Frames.Main:Show();
        TWArena:RequestTeamInfo();
    end
end

-- Event Handlers
function TWArena:OnEvent()
    if event == "ADDON_LOADED" and arg1 == "TWArena" then
        TWArena:Print("TWArena v" .. TWArena.VERSION .. " loaded. Type /arena help for commands.");
    elseif event == "CHAT_MSG_ADDON" then
        -- Debug: Print all addon messages to see what we're receiving
        TWArena:Print("DEBUG: Received addon message - Prefix: '" .. tostring(arg1) .. "' Message: '" .. tostring(arg2) .. "' Channel: '" .. tostring(arg4) .. "'");
        
        if arg1 == TWArena.ADDON_PREFIX then
            TWArena:HandleServerMessage(arg2);
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Request team info when entering world
        TWArena:RequestTeamInfo();
    end
end

-- Frame setup
local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("ADDON_LOADED");
eventFrame:RegisterEvent("CHAT_MSG_ADDON");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:SetScript("OnEvent", TWArena.OnEvent);

-- Slash Commands
SLASH_ARENA1 = "/arena";
SlashCmdList["ARENA"] = function(msg)
    local args = TWArena:SplitString(string.lower(msg), " ");
    local command = args[1] or "";
    
    if command == "" or command == "show" then
        TWArena:ToggleMainFrame();
    elseif command == "info" then
        TWArena:RequestTeamInfo();
    elseif command == "stats" then
        local arenaType = args[2];
        if arenaType then
            TWArena:RequestTeamStats(arenaType);
        else
            TWArena:PrintError("Usage: /arena stats <2v2|3v3|5v5>");
        end
    elseif command == "roster" then
        local arenaType = args[2];
        if arenaType then
            TWArena:RequestTeamRoster(arenaType);
        else
            TWArena:PrintError("Usage: /arena roster <2v2|3v3|5v5>");
        end
    elseif command == "top" then
        local arenaType = args[2];
        TWArena:RequestTopTeams(arenaType);
    elseif command == "create" then
        local arenaType = args[2];
        local teamName = "";
        for i = 3, table.getn(args) do
            if teamName ~= "" then
                teamName = teamName .. " ";
            end
            teamName = teamName .. args[i];
        end
        if arenaType and teamName ~= "" then
            TWArena:CreateTeam(arenaType, teamName);
        else
            TWArena:PrintError("Usage: /arena create <2v2|3v3|5v5> <team name>");
        end
    elseif command == "invite" then
        local playerName = args[2];
        local arenaType = args[3];
        if playerName and arenaType then
            TWArena:InvitePlayer(playerName, arenaType);
        else
            TWArena:PrintError("Usage: /arena invite <player> <2v2|3v3|5v5>");
        end
    elseif command == "kick" then
        local playerName = args[2];
        local arenaType = args[3];
        if playerName and arenaType then
            TWArena:KickPlayer(playerName, arenaType);
        else
            TWArena:PrintError("Usage: /arena kick <player> <2v2|3v3|5v5>");
        end
    elseif command == "disband" then
        local arenaType = args[2];
        if arenaType then
            TWArena:DisbandTeam(arenaType);
        else
            TWArena:PrintError("Usage: /arena disband <2v2|3v3|5v5>");
        end
    elseif command == "queue" then
        local arenaType = args[2];
        if arenaType then
            TWArena:JoinQueue(arenaType);
        else
            TWArena:PrintError("Usage: /arena queue <2v2|3v3|5v5>");
        end
    elseif command == "leave" then
        TWArena:LeaveQueue();
    elseif command == "help" then
        TWArena:Print("=== TWArena Commands ===");
        TWArena:Print("/arena show - Show/hide arena window");
        TWArena:Print("/arena info - Refresh team information");
        TWArena:Print("/arena stats <type> - Show team statistics");
        TWArena:Print("/arena roster <type> - Show team roster");
        TWArena:Print("/arena top [type] - Show top teams");
        TWArena:Print("/arena create <type> <name> - Create a team");
        TWArena:Print("/arena invite <player> <type> - Invite player");
        TWArena:Print("/arena kick <player> <type> - Kick player");
        TWArena:Print("/arena disband <type> - Disband team");
        TWArena:Print("/arena queue <type> - Join arena queue");
        TWArena:Print("/arena leave - Leave arena queue");
        TWArena:Print("Arena types: 2v2, 3v3, 5v5");
    else
        TWArena:PrintError("Unknown command. Type /arena help for help.");
    end
end

-- Debug Commands
SLASH_ARENADATA1 = "/arenadata";
SlashCmdList["ARENADATA"] = function()
    TWArena:Print("=== Arena Team Data ===");
    local count = 0;
    for arenaType, teamInfo in pairs(TWArena.TeamData) do
        count = count + 1;
        TWArena:Print(arenaType .. ": " .. teamInfo.name .. " (" .. teamInfo.role .. ", " .. teamInfo.rating .. ")");
    end
    if count == 0 then
        TWArena:Print("No team data stored!");
    end
end

SLASH_ARENAUPDATE1 = "/arenaupdate";
SlashCmdList["ARENAUPDATE"] = function()
    TWArena:UpdateMainFrame();
end