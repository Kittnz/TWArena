-- TWArena.lua - Main addon file for WoW 1.12
-- Interfaces with TW_ARENA server-side messaging system

-- Addon variables
TWArena = {};
TWArena.VERSION = "1.0.2";
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
    INFO = "S2C_INFO",
    STATS = "S2C_STATS", 
    ROSTER = "S2C_ROSTER",
    TOP = "S2C_TOP",
    CREATE_SUCCESS = "S2C_CREATE_SUCCESS",
    INVITE_SUCCESS = "S2C_INVITE_SUCCESS",
    INVITED = "S2C_INVITED",
    INVITE_ACCEPTED = "S2C_INVITE_ACCEPTED",
    INVITE_DECLINED = "S2C_INVITE_DECLINED",
    KICK_SUCCESS = "S2C_KICK_SUCCESS",
    KICKED = "S2C_KICKED",
    DISBAND_SUCCESS = "S2C_DISBAND_SUCCESS",
    QUEUE_SUCCESS = "S2C_QUEUE_SUCCESS",
    LEAVE_QUEUE_SUCCESS = "S2C_LEAVE_QUEUE_SUCCESS",
    LEAVE_TEAM_SUCCESS = "S2C_LEAVE_TEAM_SUCCESS",
    MEMBER_LEFT = "S2C_MEMBER_LEFT",
    ERROR = "S2C_ERROR"
};

-- Field delimiters (matching server protocol)
TWArena.FIELD_DELIMITER = ";";
TWArena.ARRAY_DELIMITER = ":";
TWArena.SUBFIELD_DELIMITER = "|";

-- Data storage
TWArena.TeamData = {};
TWArena.QueueStatus = {};
TWArena.PendingInvites = {}; -- Store pending invitations

-- UI Frame references
TWArena.Frames = {};

-- Utility Functions
function TWArena:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[TWArena]|r " .. msg);
end

function TWArena:PrintError(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[TWArena Error]|r " .. msg);
end

function TWArena:PrintSuccess(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[TWArena]|r " .. msg);
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

-- Invitation System Functions
function TWArena:AcceptInvite(teamId, arenaType)
    if not teamId or not arenaType then
        TWArena:PrintError("Invalid invitation data");
        return;
    end
    
    TWArena:SendAddonMessage("C2S_ACCEPT_INVITE", teamId, arenaType);
    TWArena:Print("Accepting invitation...");
end

function TWArena:DeclineInvite(teamId, arenaType)
    if not teamId or not arenaType then
        TWArena:PrintError("Invalid invitation data");
        return;
    end
    
    TWArena:SendAddonMessage("C2S_DECLINE_INVITE", teamId, arenaType);
    TWArena:Print("Declining invitation...");
end

function TWArena:StorePendingInvite(teamName, arenaType, inviterName, teamId)
    local invite = {
        teamName = teamName,
        arenaType = arenaType,
        inviterName = inviterName,
        teamId = teamId,
        timestamp = GetTime()
    };
    
    TWArena.PendingInvites[arenaType] = invite;
    TWArena:Print("Stored pending invite for " .. arenaType .. " team: " .. teamName);
end

function TWArena:GetPendingInvite(arenaType)
    local invite = TWArena.PendingInvites[arenaType];
    if invite then
        -- Check if invite has expired (5 minutes)
        if GetTime() - invite.timestamp > 300 then
            TWArena.PendingInvites[arenaType] = nil;
            return nil;
        end
        return invite;
    end
    return nil;
end

function TWArena:ClearPendingInvite(arenaType)
    TWArena.PendingInvites[arenaType] = nil;
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
    elseif msgType == TWArena.MSG_TYPES.INVITE_ACCEPTED then
        TWArena:HandleInviteAcceptedMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.INVITE_DECLINED then
        TWArena:HandleInviteDeclinedMessage(fields);
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
    elseif msgType == TWArena.MSG_TYPES.LEAVE_TEAM_SUCCESS then
        TWArena:HandleLeaveTeamSuccessMessage(fields);
    elseif msgType == TWArena.MSG_TYPES.MEMBER_LEFT then
        TWArena:HandleMemberLeftMessage(fields);
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
    
    -- Parse team data: type:name:role:rating:rank:seasonWins:seasonGames:weekWins:weekGames|...
    local teams = TWArena:SplitString(teamData, TWArena.SUBFIELD_DELIMITER);
    
    TWArena:Print("DEBUG: Split into " .. table.getn(teams) .. " teams");
    
    for i = 1, table.getn(teams) do
        local teamInfo = TWArena:SplitString(teams[i], TWArena.ARRAY_DELIMITER);
        TWArena:Print("DEBUG: Team " .. i .. " has " .. table.getn(teamInfo) .. " parts: " .. teams[i]);
        
        if table.getn(teamInfo) >= 9 then
            local arenaTypeNum = teamInfo[1];
            local teamName = teamInfo[2];
            local role = teamInfo[3];
            local rating = tonumber(teamInfo[4]) or 0;
            local rank = tonumber(teamInfo[5]) or 0;
            local seasonWins = tonumber(teamInfo[6]) or 0;
            local seasonGames = tonumber(teamInfo[7]) or 0;
            local weekWins = tonumber(teamInfo[8]) or 0;
            local weekGames = tonumber(teamInfo[9]) or 0;
            
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
                    rank = rank,
                    seasonWins = seasonWins,
                    seasonGames = seasonGames,
                    weekWins = weekWins,
                    weekGames = weekGames
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
    
    -- Parse roster data: name:role:personalRating:seasonGames:seasonWins|...
    local members = TWArena:SplitString(rosterData, TWArena.SUBFIELD_DELIMITER);
    
    for i = 1, table.getn(members) do
        local memberInfo = TWArena:SplitString(members[i], TWArena.ARRAY_DELIMITER);
        if table.getn(memberInfo) >= 5 then
            local name = memberInfo[1];
            local role = memberInfo[2];
            local personalRating = tonumber(memberInfo[3]) or 0;
            local seasonGames = tonumber(memberInfo[4]) or 0;
            local seasonWins = tonumber(memberInfo[5]) or 0;
            TWArena:Print(string.format("%s (%s) - Rating: %d, Record: %d/%d", 
                name, role, personalRating, seasonWins, seasonGames));
        end
    end
end

function TWArena:HandleTopMessage(fields)
    if table.getn(fields) < 3 then
        return;
    end
    
    local arenaType = fields[2];
    local topData = fields[3];
    
    if arenaType == "ALL" then
        TWArena:Print("=== Top Arena Teams (All Types) ===");
    else
        TWArena:Print("=== Top " .. arenaType .. " Teams ===");
    end
    
    if topData == "" then
        TWArena:Print("No top teams data available.");
        return;
    end
    
    -- Parse top teams data: rank:name:type:rating:rank:wins:games|...
    local teams = TWArena:SplitString(topData, TWArena.SUBFIELD_DELIMITER);
    
    for i = 1, table.getn(teams) do
        local teamInfo = TWArena:SplitString(teams[i], TWArena.ARRAY_DELIMITER);
        if table.getn(teamInfo) >= 7 then
            local rank = teamInfo[1];
            local name = teamInfo[2];
            local teamType = teamInfo[3];
            local rating = tonumber(teamInfo[4]) or 0;
            local teamRank = tonumber(teamInfo[5]) or 0;
            local wins = tonumber(teamInfo[6]) or 0;
            local games = tonumber(teamInfo[7]) or 0;
            TWArena:Print(string.format("%s. %s (%s) - Rating: %d (Rank: %d), Record: %d/%d", 
                rank, name, teamType, rating, teamRank, wins, games));
        end
    end
end

function TWArena:HandleCreateSuccessMessage(fields)
    if table.getn(fields) >= 3 then
        local arenaType = fields[2];
        local teamName = fields[3];
        TWArena:PrintSuccess("Successfully created " .. arenaType .. " team: " .. teamName);
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleInviteSuccessMessage(fields)
    if table.getn(fields) >= 4 then
        local playerName = fields[2];
        local arenaType = fields[3];
        local teamName = fields[4];
        TWArena:PrintSuccess("Successfully invited " .. playerName .. " to " .. arenaType .. " team: " .. teamName);
    end
end

function TWArena:HandleInvitedMessage(fields)
    if table.getn(fields) >= 5 then
        local teamName = fields[2];
        local arenaType = fields[3];
        local inviterName = fields[4];
        local teamId = fields[5];
        
        -- Store the invitation
        TWArena:StorePendingInvite(teamName, arenaType, inviterName, teamId);
        
        -- Show invitation dialog
        TWArena:ShowInvitationDialog(teamName, arenaType, inviterName, teamId);
        
        TWArena:Print("You have been invited to " .. arenaType .. " team '" .. teamName .. "' by " .. inviterName);
    end
end

function TWArena:HandleInviteAcceptedMessage(fields)
    if table.getn(fields) >= 4 then
        local arg1 = fields[2]; -- teamName (for invitee) or playerName (for inviter)
        local arg2 = fields[3]; -- arenaType (for invitee) or teamName (for inviter)
        local arg3 = fields[4]; -- inviterName (for invitee) or arenaType (for inviter)
        
        -- Determine if we're the invitee or inviter based on context
        -- If arg2 is a number, we're the invitee
        local arenaTypeNum = tonumber(arg2);
        if arenaTypeNum then
            -- We accepted an invitation
            local teamName = arg1;
            local arenaType = arg2 .. "v" .. arg2;
            local inviterName = arg3;
            TWArena:PrintSuccess("You have successfully joined " .. arenaType .. " team '" .. teamName .. "'!");
            TWArena:ClearPendingInvite(arenaType);
        else
            -- Someone accepted our invitation
            local playerName = arg1;
            local teamName = arg2;
            local arenaTypeNum = tonumber(arg3);
            local arenaType = arg3 .. "v" .. arg3;
            TWArena:PrintSuccess(playerName .. " has joined your " .. arenaType .. " team '" .. teamName .. "'!");
        end
        
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleInviteDeclinedMessage(fields)
    if table.getn(fields) >= 4 then
        local arg1 = fields[2]; -- teamName (for invitee) or playerName (for inviter)
        local arg2 = fields[3]; -- arenaType (for invitee) or teamName (for inviter)
        local arg3 = fields[4]; -- inviterName (for invitee) or arenaType (for inviter)
        
        -- Determine if we're the invitee or inviter based on context
        local arenaTypeNum = tonumber(arg2);
        if arenaTypeNum then
            -- We declined an invitation
            local teamName = arg1;
            local arenaType = arg2 .. "v" .. arg2;
            local inviterName = arg3;
            TWArena:Print("You have declined the invitation to " .. arenaType .. " team '" .. teamName .. "'");
            TWArena:ClearPendingInvite(arenaType);
        else
            -- Someone declined our invitation
            local playerName = arg1;
            local teamName = arg2;
            local arenaTypeNum = tonumber(arg3);
            local arenaType = arg3 .. "v" .. arg3;
            TWArena:Print(playerName .. " has declined your invitation to " .. arenaType .. " team '" .. teamName .. "'");
        end
    end
end

function TWArena:HandleKickSuccessMessage(fields)
    if table.getn(fields) >= 4 then
        local playerName = fields[2];
        local arenaType = fields[3];
        local teamName = fields[4];
        TWArena:PrintSuccess("Successfully kicked " .. playerName .. " from " .. arenaType .. " team: " .. teamName);
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
        TWArena:PrintSuccess("Successfully disbanded " .. arenaType .. " team: " .. teamName);
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleQueueSuccessMessage(fields)
    if table.getn(fields) >= 3 then
        local arenaType = fields[2];
        local avgTime = tonumber(fields[3]) or 0;
        TWArena:PrintSuccess("Successfully joined " .. arenaType .. " arena queue. Average wait time: " .. avgTime .. "ms");
        TWArena.QueueStatus[arenaType] = true;
    end
end

function TWArena:HandleLeaveQueueSuccessMessage(fields)
    TWArena:PrintSuccess("Successfully left arena queue.");
    TWArena.QueueStatus = {};
end

function TWArena:HandleLeaveTeamSuccessMessage(fields)
    if table.getn(fields) >= 3 then
        local arenaType = fields[2];
        local teamName = fields[3];
        TWArena:PrintSuccess("You have successfully left " .. arenaType .. " team: " .. teamName);
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleMemberLeftMessage(fields)
    if table.getn(fields) >= 4 then
        local playerName = fields[2];
        local arenaType = fields[3];
        local teamName = fields[4];
        TWArena:Print(playerName .. " has left your " .. arenaType .. " team '" .. teamName .. "'");
        TWArena:RequestTeamInfo();
    end
end

function TWArena:HandleErrorMessage(fields)
    if table.getn(fields) >= 2 then
        TWArena:PrintError(fields[2]);
    end
end

-- API Functions
function TWArena:RequestTeamInfo()
    TWArena:Print("DEBUG: Requesting team info...");
    TWArena:SendAddonMessage("S2C_INFO");
end

function TWArena:RequestTeamStats(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("S2C_STATS", arenaType);
end

function TWArena:RequestTeamRoster(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("S2C_ROSTER", arenaType);
end

function TWArena:RequestTopTeams(arenaType)
    if arenaType and not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("S2C_TOP", arenaType or "");
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
    TWArena:SendAddonMessage("S2C_CREATE", arenaType, teamName);
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
    TWArena:SendAddonMessage("S2C_INVITE", playerName, arenaType);
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
    TWArena:SendAddonMessage("S2C_KICK", playerName, arenaType);
end

function TWArena:DisbandTeam(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("S2C_DISBAND", arenaType);
end

function TWArena:LeaveTeam(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("S2C_LEAVE_TEAM", arenaType);
end

function TWArena:JoinQueue(arenaType)
    if not TWArena.ARENA_TYPES[arenaType] then
        TWArena:PrintError("Invalid arena type: " .. arenaType);
        return;
    end
    TWArena:SendAddonMessage("S2C_QUEUE", arenaType);
end

function TWArena:LeaveQueue()
    TWArena:SendAddonMessage("S2C_LEAVE_QUEUE");
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

function TWArena:ShowInvitationDialog(teamName, arenaType, inviterName, teamId)
    -- Close existing invitation dialog if any
    if TWArena.Frames.InviteDialog then
        TWArena.Frames.InviteDialog:Hide();
        TWArena.Frames.InviteDialog = nil;
    end
    
    local frame = CreateFrame("Frame", "TWArenaInviteDialog", UIParent);
    frame:SetFrameStrata("FULLSCREEN_DIALOG");
    frame:SetWidth(350);
    frame:SetHeight(150);
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100);
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    });
    frame:SetMovable(true);
    frame:EnableMouse(true);
    
    -- Title
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
    title:SetPoint("TOP", frame, "TOP", 0, -15);
    title:SetText("Arena Team Invitation");
    title:SetTextColor(1, 1, 0); -- Yellow
    
    -- Invitation text
    local inviteText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal");
    inviteText:SetPoint("TOP", title, "BOTTOM", 0, -10);
    inviteText:SetWidth(300);
    inviteText:SetText(inviterName .. " has invited you to join\\n" .. arenaType .. " team: " .. teamName);
    inviteText:SetJustifyH("CENTER");
    
    -- Accept button
    local acceptBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate");
    acceptBtn:SetWidth(80);
    acceptBtn:SetHeight(25);
    acceptBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 30, 15);
    acceptBtn:SetText("Accept");
    acceptBtn:SetScript("OnClick", function() 
        TWArena:AcceptInvite(teamId, TWArena.ARENA_TYPES[arenaType]);
        frame:Hide();
        TWArena.Frames.InviteDialog = nil;
    end);
    
    -- Decline button
    local declineBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate");
    declineBtn:SetWidth(80);
    declineBtn:SetHeight(25);
    declineBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 15);
    declineBtn:SetText("Decline");
    declineBtn:SetScript("OnClick", function() 
        TWArena:DeclineInvite(teamId, TWArena.ARENA_TYPES[arenaType]);
        frame:Hide();
        TWArena.Frames.InviteDialog = nil;
    end);
    
    -- Auto-close after 5 minutes
    local startTime = GetTime();
    frame:SetScript("OnUpdate", function()
        if GetTime() - startTime > 300 then -- 5 minutes
            TWArena:Print("Arena invitation has expired.");
            frame:Hide();
            TWArena.Frames.InviteDialog = nil;
            TWArena:ClearPendingInvite(arenaType);
        end
    end);
    
    frame:Show();
    TWArena.Frames.InviteDialog = frame;
    
    -- Play sound notification
    PlaySound("TellMessage");
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
        yOffset = yOffset - 15;
        
        local teamStats = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
        teamStats:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset);
        teamStats:SetText("Season: " .. teamInfo.seasonWins .. "/" .. teamInfo.seasonGames .. " | Week: " .. teamInfo.weekWins .. "/" .. teamInfo.weekGames);
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
        if arg1 == TWArena.ADDON_PREFIX then
            -- Debug: Print all addon messages to see what we're receiving
            TWArena:Print("DEBUG: Received addon message - Prefix: '" .. tostring(arg1) .. "' Message: '" .. tostring(arg2) .. "' Channel: '" .. tostring(arg4) .. "'");
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
    elseif command == "leave" then
        local arenaType = args[2];
        if arenaType then
            TWArena:LeaveTeam(arenaType);
        else
            TWArena:PrintError("Usage: /arena leave <2v2|3v3|5v5>");
        end
    elseif command == "queue" then
        local arenaType = args[2];
        if arenaType then
            TWArena:JoinQueue(arenaType);
        else
            TWArena:PrintError("Usage: /arena queue <2v2|3v3|5v5>");
        end
    elseif command == "leavequeue" or command == "leaveq" then
        TWArena:LeaveQueue();
    elseif command == "accept" then
        local arenaType = args[2];
        if arenaType then
            local invite = TWArena:GetPendingInvite(arenaType);
            if invite then
                TWArena:AcceptInvite(invite.teamId, TWArena.ARENA_TYPES[arenaType]);
            else
                TWArena:PrintError("No pending " .. arenaType .. " invitation found.");
            end
        else
            TWArena:PrintError("Usage: /arena accept <2v2|3v3|5v5>");
        end
    elseif command == "decline" then
        local arenaType = args[2];
        if arenaType then
            local invite = TWArena:GetPendingInvite(arenaType);
            if invite then
                TWArena:DeclineInvite(invite.teamId, TWArena.ARENA_TYPES[arenaType]);
            else
                TWArena:PrintError("No pending " .. arenaType .. " invitation found.");
            end
        else
            TWArena:PrintError("Usage: /arena decline <2v2|3v3|5v5>");
        end
    elseif command == "help" then
        TWArena:Print("=== TWArena Commands ===");
        TWArena:Print("/arena show - Show/hide arena window");
        TWArena:Print("/arena info - Refresh team information");
        TWArena:Print("/arena stats <type> - Show team statistics");
        TWArena:Print("/arena roster <type> - Show team roster");
        TWArena:Print("/arena top [type] - Show top teams");
        TWArena:Print("/arena create <type> <name> - Create a team");
        TWArena:Print("/arena invite <player> <type> - Invite player");
        TWArena:Print("/arena accept <type> - Accept invitation");
        TWArena:Print("/arena decline <type> - Decline invitation");
        TWArena:Print("/arena kick <player> <type> - Kick player");
        TWArena:Print("/arena disband <type> - Disband team");
        TWArena:Print("/arena leave <type> - Leave team");
        TWArena:Print("/arena queue <type> - Join arena queue");
        TWArena:Print("/arena leavequeue - Leave arena queue");
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
    
    TWArena:Print("=== Pending Invitations ===");
    local inviteCount = 0;
    for arenaType, invite in pairs(TWArena.PendingInvites) do
        inviteCount = inviteCount + 1;
        TWArena:Print(arenaType .. ": " .. invite.teamName .. " (from " .. invite.inviterName .. ", ID: " .. invite.teamId .. ")");
    end
    if inviteCount == 0 then
        TWArena:Print("No pending invitations!");
    end
end

SLASH_ARENAUPDATE1 = "/arenaupdate";
SlashCmdList["ARENAUPDATE"] = function()
    TWArena:UpdateMainFrame();
end

SLASH_ARENAINVITE1 = "/arenainvite";
SlashCmdList["ARENAINVITE"] = function(msg)
    -- Debug command to simulate receiving an invitation
    local args = TWArena:SplitString(msg, " ");
    if table.getn(args) >= 4 then
        local teamName = args[1];
        local arenaType = args[2];
        local inviterName = args[3];
        local teamId = args[4];
        TWArena:ShowInvitationDialog(teamName, arenaType, inviterName, teamId);
    else
        TWArena:Print("Usage: /arenainvite <teamName> <arenaType> <inviterName> <teamId>");
    end
end