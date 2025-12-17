require('common');
require('helpers');
local imgui = require('imgui');
local progressbar = require('progressbar');

local bgAlpha = 0.4;
local bgRadius = 3;

local alliedlist = {};
alliedlist._hidden = false;

function alliedlist.SetHidden(v)
    alliedlist._hidden = v;
end

local townZoneIds = T{
    [230] = true, -- Southern San d'Oria
    [231] = true, -- Northern San d'Oria
    [232] = true, -- Port San d'Oria
    [233] = true, -- Chateau d'Oraguille
    [234] = true, -- Bastok Mines
    [235] = true, -- Bastok Markets
    [236] = true, -- Port Bastok
    [237] = true, -- Metalworks
    [238] = true, -- Windurst Waters
    [239] = true, -- Windurst Walls
    [240] = true, -- Port Windurst
    [241] = true, -- Windurst Woods
    [242] = true, -- Heavens Tower
    [243] = true, -- Ru'Lude Gardens
    [244] = true, -- Upper Jeuno
    [245] = true, -- Lower Jeuno
    [246] = true, -- Port Jeuno
    [248] = true, -- Selbina
    [249] = true, -- Mhaura
};

local alliedWhitelist = nil;


if (gConfig ~= nil) then
    gConfig.alliedWhitelist = gConfig.alliedWhitelist or T{};
    if (next(gConfig.alliedWhitelist) == nil and gConfig.alliedWhitelistSeeded ~= true) then
        for k,v in pairs(defaultAlliedWhitelist) do
            gConfig.alliedWhitelist[k] = v;
        end
        gConfig.alliedWhitelistSeeded = true;
    end
end


local function GetIsValidEntity(idx)
    local renderflags = AshitaCore:GetMemoryManager():GetEntity():GetRenderFlags0(idx);
    if bit.band(renderflags, 0x200) ~= 0x200 or bit.band(renderflags, 0x4000) ~= 0 then
        return false;
    end
    return true;
end

local function IsAlliedForceCandidate(ent)
    if (ent == nil) then
        return false;
    end
    if (ent.SpawnFlags == nil) then
        return false;
    end

    -- NPC
    if (bit.band(ent.SpawnFlags, 0x0002) ~= 0x0002) then
        return false;
    end

    -- Combat-capable (filters out most static NPCs)
    if (ent.HPPercent == nil or ent.HPPercent <= 0) then
        return false;
    end

    if (ent.Name == nil or tostring(ent.Name) == '') then
        return false;
    end

    -- Whitelist (if empty, allow all; if not empty, require match)
    local n = tostring(ent.Name);
    local wl = (gConfig ~= nil) and gConfig.alliedWhitelist or nil;
    if (wl ~= nil and next(wl) ~= nil) then
        if (wl[n] ~= true) then
            return false;
        end
    end

    return true;
end

local function TargetByIndex(idx)
    local mmT = AshitaCore:GetMemoryManager():GetTarget();
    if (mmT == nil) then
        return;
    end
    pcall(function() mmT:SetTarget(idx, false); end);
end

alliedlist.DrawWindow = function(settings)
    if (alliedlist._hidden == true) then
        return;
    end

    local party = AshitaCore:GetMemoryManager():GetParty();
    if (party ~= nil) then
        local zid = party:GetMemberZone(0);
        if (zid ~= nil and townZoneIds[zid] == true) then
            return;
        end
    end

    imgui.SetNextWindowSize({ settings.barWidth, -1, }, ImGuiCond_Always);

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav,
        ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoBringToFrontOnFocus
    );
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    if (imgui.Begin('AlliedForces', true, windowFlags)) then
        imgui.SetWindowFontScale(settings.textScale);

        if (gConfig.showAlliedListTitle) then
            imgui.Text('Allied Forces');
            imgui.Separator();
        end

        local targetIndex;
        local subTargetIndex;
        local subTargetActive = false;
        local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
        if (playerTarget ~= nil) then
            subTargetActive = GetSubTargetActive();
            targetIndex, subTargetIndex = GetTargets();
            if (subTargetActive) then
                local tempTarget = targetIndex;
                targetIndex = subTargetIndex;
                subTargetIndex = tempTarget;
            end
        end

        local numShown = 0;
        local maxShown = 8;

        if (showConfig[1] and gConfig.alliedListPreview) then
            for i = 1, maxShown do
                imgui.Dummy({0, settings.entrySpacing});

                local nameText = 'Allied Force ' .. tostring(i);
                local rectLength = imgui.GetColumnWidth() + imgui.GetStyle().FramePadding.x;
                local winX, winY = imgui.GetCursorScreenPos();

                local isOor = false;

                local cornerOffset = settings.bgTopPadding;
                local _, yDist = imgui.CalcTextSize(nameText);
                if (yDist > settings.barHeight) then
                    yDist = yDist + yDist;
                else
                    yDist = yDist + settings.barHeight;
                end

                draw_rect(
                    {winX + cornerOffset , winY + cornerOffset},
                    {winX + rectLength, winY + yDist + settings.bgPadding},
                    {0,0,0,bgAlpha},
                    bgRadius,
                    true
                );

                do
                    local restoreX, restoreY = imgui.GetCursorScreenPos();
                    imgui.SetCursorScreenPos({ winX, winY });

                    imgui.InvisibleButton('AlliedPreviewClick##' .. tostring(i), { rectLength, (yDist + settings.bgPadding) });

                    if (imgui.IsItemHovered()) then
                        draw_rect(
                            {winX + cornerOffset , winY + cornerOffset},
                            {winX + rectLength, winY + yDist + settings.bgPadding},
                            {1, 1, 1, 0.10},
                            bgRadius,
                            true
                        );
                    end

                    imgui.SetCursorScreenPos({ restoreX, restoreY });
                end

                imgui.Text(nameText);

                local hpGrad = { '#e16c6c', '#fb9494' };
                progressbar.ProgressBar(
                    {{1, hpGrad}},
                    {-1, settings.barHeight},
                    {decorate = gConfig.showAlliedListBookends}
                );

                imgui.Separator();
            end
        else
            for idx = 0, 2303 do
                if (GetIsValidEntity(idx)) then
                    local ent = GetEntity(idx);
                    if (IsAlliedForceCandidate(ent)) then
                        imgui.Dummy({0, settings.entrySpacing});

                        local nameText = ent.Name;
                        local rectLength = imgui.GetColumnWidth() + imgui.GetStyle().FramePadding.x;
                        local winX, winY = imgui.GetCursorScreenPos();

                        local dist = (ent.Distance ~= nil) and math.sqrt(ent.Distance) or 0;
                        local maxDist = tonumber(gConfig.alliedListRangeDistance) or 21.8;
                        local isOor = (dist > maxDist);

                        local cornerOffset = settings.bgTopPadding;
                        local _, yDist = imgui.CalcTextSize(nameText);
                        if (yDist > settings.barHeight) then
                            yDist = yDist + yDist;
                        else
                            yDist = yDist + settings.barHeight;
                        end

                        draw_rect(
                            {winX + cornerOffset , winY + cornerOffset},
                            {winX + rectLength, winY + yDist + settings.bgPadding},
                            {0,0,0,bgAlpha},
                            bgRadius,
                            true
                        );

                        do
                            local restoreX, restoreY = imgui.GetCursorScreenPos();
                            imgui.SetCursorScreenPos({ winX, winY });

                            imgui.InvisibleButton('AlliedClick##' .. tostring(idx), { rectLength, (yDist + settings.bgPadding) });

                            if (imgui.IsItemHovered()) then
                                draw_rect(
                                    {winX + cornerOffset , winY + cornerOffset},
                                    {winX + rectLength, winY + yDist + settings.bgPadding},
                                    {1, 1, 1, 0.10},
                                    bgRadius,
                                    true
                                );
                            end

                            if (imgui.IsItemClicked(0)) then
                                TargetByIndex(idx);
                            end

                            imgui.SetCursorScreenPos({ restoreX, restoreY });
                        end

                        local borderThickness = 3;
                        if (subTargetIndex ~= nil and idx == subTargetIndex) then
                            for i = 0, borderThickness - 1 do
                                draw_rect(
                                    {winX + cornerOffset - i, winY + cornerOffset - i},
                                    {winX + rectLength - 1 + i, winY + yDist + settings.bgPadding + i},
                                    {.5, .5, 1, 1},
                                    bgRadius,
                                    false
                                );
                            end
                        elseif (targetIndex ~= nil and idx == targetIndex) then
                            for i = 0, borderThickness - 1 do
                                draw_rect(
                                    {winX + cornerOffset - i, winY + cornerOffset - i},
                                    {winX + rectLength - 1 + i, winY + yDist + settings.bgPadding + i},
                                    {1, 0.8, 0, 1},
                                    bgRadius,
                                    false
                                );
                            end
                        end

                        if (isOor) then
                            imgui.PushStyleColor(ImGuiCol_Text, {0.35, 0.35, 0.35, 1});
                        end
                        imgui.Text(nameText);
                        if (isOor) then
                            imgui.PopStyleColor(1);
                        end

                        local hpGrad = { '#e16c6c', '#fb9494' };
                        if (isOor) then
                            hpGrad = { '#151515', '#1f1f1f' };
                        end
                        progressbar.ProgressBar(
                            {{ent.HPPercent / 100, hpGrad}},
                            {-1, settings.barHeight},
                            {decorate = gConfig.showAlliedListBookends}
                        );

                        imgui.Separator();

                        numShown = numShown + 1;
                        if (numShown >= maxShown) then
                            break;
                        end
                    end
                end
            end
        end


    end

    imgui.End();
end


alliedlist.SetHidden = function(hidden)
    alliedlist._hidden = (hidden == true);
end

return alliedlist;

