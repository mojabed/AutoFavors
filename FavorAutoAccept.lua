-- FavorAutoAccept.lua
-- Auto accepts and completes favor quests from Freerunner Post Boards.
-- Slash commands: /faa on | off | toggle

FavorAutoAccept = { enabled = true, inProgress = false }

local ACCEPT_MATCH   = "Favors for"
local COMPLETE_MATCH = "Lockbox"
local SAFETY_TIMEOUT_MS = 10000

local function SlashHandler(args)
    args = string.lower(args or "")
    if args == "on" then
        FavorAutoAccept.enabled = true
        d("[FavorAutoAccept] ENABLED")
    elseif args == "off" then
        FavorAutoAccept.enabled = false
        d("[FavorAutoAccept] DISABLED")
    elseif args == "toggle" then
        FavorAutoAccept.enabled = not FavorAutoAccept.enabled
        d("[FavorAutoAccept] " .. (FavorAutoAccept.enabled and "ENABLED" or "DISABLED"))
    else
        d("[FavorAutoAccept] Usage: /faa on | off | toggle")
    end
end
SLASH_COMMANDS["/faa"] = SlashHandler

local function IsTimedOut()
    return (GetGameTimeMilliseconds() - (FavorAutoAccept.startTime or 0)) > SAFETY_TIMEOUT_MS
end

local function TryAdvanceScreen2()
    if not FavorAutoAccept.enabled or not FavorAutoAccept.inProgress then return end
    if IsTimedOut() then FavorAutoAccept.inProgress = false; return end
    if not INTERACTION or not INTERACTION.optionCount or INTERACTION.optionCount < 1 then
        FavorAutoAccept.inProgress = false; return
    end

    local bodyOk, bodyText = pcall(ZO_InteractWindowTargetAreaBodyText.GetText,
                                    ZO_InteractWindowTargetAreaBodyText)
    if bodyOk and bodyText and bodyText == FavorAutoAccept.savedBodyText then
        FavorAutoAccept.s2Retry = (FavorAutoAccept.s2Retry or 0) + 1
        if FavorAutoAccept.s2Retry > 40 then
            FavorAutoAccept.inProgress = false; return
        end
        zo_callLater(TryAdvanceScreen2, 150)
        return
    end

    pcall(INTERACTION.SelectChatterOptionByIndex, INTERACTION, 1)
    d("[FavorAutoAccept] Quest " .. (FavorAutoAccept.isCompleting and "completed" or "accepted") .. "!")
    FavorAutoAccept.inProgress = false
end

local function TryAdvanceScreen1()
    if not FavorAutoAccept.enabled or not FavorAutoAccept.inProgress then return end
    if IsTimedOut() then FavorAutoAccept.inProgress = false; return end
    if not INTERACTION then FavorAutoAccept.inProgress = false; return end

    local phase = FavorAutoAccept.s1Phase or 0

    if phase == 0 then
        if not INTERACTION.optionCount or INTERACTION.optionCount < 1 then
            FavorAutoAccept.retryCount = (FavorAutoAccept.retryCount or 0) + 1
            if FavorAutoAccept.retryCount > 30 then
                FavorAutoAccept.inProgress = false; return
            end
            zo_callLater(TryAdvanceScreen1, 100); return
        end

        local _, bodyText = pcall(ZO_InteractWindowTargetAreaBodyText.GetText,
                                  ZO_InteractWindowTargetAreaBodyText)
        if not bodyText or bodyText == "" then
            FavorAutoAccept.s1TextRetries = (FavorAutoAccept.s1TextRetries or 0) + 1
            if FavorAutoAccept.s1TextRetries > 10 then
                FavorAutoAccept.inProgress = false; return
            end
            zo_callLater(TryAdvanceScreen1, 100); return
        end

        FavorAutoAccept.savedBodyText    = bodyText
        FavorAutoAccept.s2Retry          = 0
        FavorAutoAccept.s1AdvanceRetries = 0
        FavorAutoAccept.s1TextRetries    = 0
        FavorAutoAccept.retryCount       = 0
        FavorAutoAccept.s1Phase          = 1

        pcall(INTERACTION.SelectChatterOptionByIndex, INTERACTION, 1)
        zo_callLater(TryAdvanceScreen1, 200)
        return
    end

    -- Phase 1: verify body text changed to confirm the advance worked
    local bodyOk, bodyText = pcall(ZO_InteractWindowTargetAreaBodyText.GetText,
                                    ZO_InteractWindowTargetAreaBodyText)
    if bodyOk and bodyText and bodyText == FavorAutoAccept.savedBodyText then
        FavorAutoAccept.s1AdvanceRetries = (FavorAutoAccept.s1AdvanceRetries or 0) + 1
        if FavorAutoAccept.s1AdvanceRetries > 5 then
            FavorAutoAccept.inProgress = false
            FavorAutoAccept.s1Phase = 0
            return
        end
        pcall(INTERACTION.SelectChatterOptionByIndex, INTERACTION, 1)
        zo_callLater(TryAdvanceScreen1, 250)
        return
    end

    FavorAutoAccept.s1Phase = 0
    TryAdvanceScreen2()
end

local function OnClientInteractResult(_, _, interactName)
    if not FavorAutoAccept.enabled or FavorAutoAccept.inProgress then return end
    if not interactName or type(interactName) ~= "string" then return end

    local isAccept   = string.find(interactName, ACCEPT_MATCH, 1, true)
    local isComplete = string.find(interactName, COMPLETE_MATCH, 1, true)
    if not isAccept and not isComplete then return end

    FavorAutoAccept.isCompleting = isComplete
    FavorAutoAccept.inProgress   = true
    FavorAutoAccept.retryCount   = 0
    FavorAutoAccept.startTime    = GetGameTimeMilliseconds()

    zo_callLater(TryAdvanceScreen1, 100)
end

local function OnAddOnLoaded(_, addonName)
    if addonName ~= "FavorAutoAccept" then return end
    EVENT_MANAGER:RegisterForEvent("FavorAutoAccept_Interact", EVENT_CLIENT_INTERACT_RESULT, OnClientInteractResult)
    d("[FavorAutoAccept] Loaded. /faa for help.")
end
EVENT_MANAGER:RegisterForEvent("FavorAutoAccept_Loaded", EVENT_ADD_ON_LOADED, OnAddOnLoaded)
