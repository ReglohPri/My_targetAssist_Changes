--[[
Name: targetAssist
Author: Sonora (The Dragonflight, US Kirin Tor)
Website & SVN: http://wow.curseforge.com/addons/targetassist/
License: GNU General Public License v3
]]
local ADDON, NS = ...
local autoAdds = NS.Auto
local util = NS.Utils
local addon = _G[ADDON]
local tsort = table.sort
local LibKeyBound = LibStub("LibKeyBound-1.0")
local headerMenuName = ("%sHeaderFrame"):format(ADDON)
local assistNameTemplate = ("%s_Assist%%d"):format(ADDON)
local targetNameTemplate = ("%s_Target%%d"):format(ADDON)
local targettargetNameTemplate = ("%s_TargetTarget%%d"):format(ADDON)

--Methods that draw stuff
function addon:yesnoBox(msg, callback)
    StaticPopupDialogs["TARGETASSIST_YESNOBOX"] = {
        text = msg,
        button1 = "Yes",
        button2 = "No",
        OnAccept = function(self, data, data2)
            callback()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
    }

    StaticPopup_Show ("TARGETASSIST_YESNOBOX")
end

local groupSelection,unitNames = {},{}
function addon:showHeaderMenu()

    self:updateRoster()

    wipe(groupSelection)
    wipe(unitNames)
    local unitNames = util.keys(self.roster)
    tsort(unitNames)
    for _, unitName in ipairs(unitNames) do
        local name = util.decoratedName(unitName)
        tinsert(groupSelection, {
            text = name,
            checked = function() return util.hasValue(self.config.targets, unitName) end,
            func = function(this, arg1, arg2, checked)
                if checked then
                    tremove(self.config.targets, util.tableIndex(self.config.targets, unitName))
                    autoAdds[unitName] = nil
                    this.checked = false
                else
                    tinsert(self.config.targets, unitName)
                    autoAdds[unitName] = nil
                    this.checked = true
                end
                self:updateConfig()
            end,
        })
    end

    local broadcastSelection = {}
    for _, broadcast in ipairs(self.previousBroadcasts) do
        local sender, dist, targetList = unpack(broadcast)
        tinsert(broadcastSelection, {
                text = sender..' ('..table.concat(targetList, ", ")..')',
                notCheckable = true,
                func = function()
                    self.config.targets = targetList
                    self:updateConfig()
                end,
            }
        )
    end

    self.headerMenu = {
        {text = 'Main assists',
            isTitle = true,
            notCheckable = true,
        },
        {text = 'Select custom assists',
            hasArrow = true,
            notCheckable = true,
            menuList = groupSelection,
        },
        {text = 'Add all',
            notCheckable = true,
            func = function() self:addAll() end,
        },
        {text = 'Clear all',
            notCheckable = true,
            func = function() self:clearAll() end,
        },
        {text = 'Add party',
            notCheckable = true,
            func = function() self:addParty() end,
        },
        {text = 'Add all tanks',
            notCheckable = true,
            func = function()
                self:addTanks()
                self:updateConfig()
            end,
        },
        {text = 'Add all main assists',
            notCheckable = true,
            func = function()
                self:addMainAssists()
                self:updateConfig()
            end,
        },
        {text = 'Add current target',
            notCheckable = true,
            func = function()
                self:addTarget()
                self:updateConfig()
            end,
        },
        {text = 'Invert assist order',
            notCheckable = true,
            func = function()
                self:invertTargetOrder()
            end,
        },

        {text = 'Broadcasts',
            isTitle = true,
            notCheckable = true,
        },
        {text = 'Received broadcasts',
            hasArrow = true,
            notCheckable = true,
            menuList = broadcastSelection,
        },
        {text = 'Broadcast targets',
            hasArrow = true,
            notCheckable = true,
            menuList = {
                {text = 'To raid',
                    notCheckable = true,
                    func = function()
                        if IsInRaid() then
                            self:SendCommMessage(self.Prefix, self:Serialize(self.config.targets), 'RAID')
                        end
                    end,
                },
                {text = 'To party',
                    notCheckable = true,
                    func = function()
                        if IsInGroup(LE_PARTY_CATEGORY_HOME) then
                            self:SendCommMessage(self.Prefix, self:Serialize(self.config.targets), 'PARTY')
                        end
                    end,
                },
                {text = 'To guild',
                    notCheckable = true,
                    func = function()
                        if IsInGuild() then
                            self:SendCommMessage(self.Prefix, self:Serialize(self.config.targets), 'GUILD')
                        end
                    end,
                },
            },
        },

        {text = 'Configuration',
            isTitle = true,
            notCheckable = true,
        },
        {text = 'Open options panel',
            notCheckable = true,
            func = function() InterfaceOptionsFrame_OpenToCategory(self.optionsBaseFrame) end,
        },
        {text = 'Target keybindings',
            notCheckable = true,
            func = function() LibKeyBound:Activate() end,
        },
    }

    -- Make the menu appear at the cursor:
    EasyMenu(self.headerMenu, self.contextMenu, "cursor", 0 , 0, "MENU")

end

function addon:showAssistFrameMenu(targetName)

    local idx = util.tableIndex(self.config.targets, targetName)
    local assistMenu = {
        {text = 'Move up',
            notCheckable = true,
            disabled = idx==1,
            func = function()
                tinsert(self.config.targets,idx-1,(tremove(self.config.targets,idx)))
                self:updateConfig()
            end,
        },
        {text = 'Move down',
            notCheckable = true,
            disabled = idx == #self.config.targets,
            func = function()
                tinsert(self.config.targets,idx+1,(tremove(self.config.targets,idx)))
                self:updateConfig()
            end,
        },
    }

    EasyMenu(assistMenu, self.contextMenu, "cursor", 0 , 0, "MENU")
end

function addon:showAssistTargetMenu(_,unitID)

    local currentIcon = GetRaidTargetIndex(unitID)

    local menu = {}
    for iconIdx, raidIcon in ipairs(self.config.raidIcons) do
        local iconName, iconTexture = unpack(raidIcon)
        tinsert(menu, {
                text = iconName,
                checked = iconIdx == currentIcon,
                func = function(this, arg1, arg2, checked)
                    if checked == true then
                        this.checked = true
                    else
                        this.checked = false
                    end
                    SetRaidTargetIcon(unitID, iconIdx)
                end,
                icon = iconTexture,
            }
        )

    end

    EasyMenu(menu, self.contextMenu, "cursor", 0 , 0, "MENU")

end

function addon:createHeaderFrame()

    if not self.headerFrame then
        self.headerFrame = CreateFrame('Frame', headerMenuName, UIParent, "BackdropTemplate")
        self.headerFrame.texture = self.headerFrame:CreateTexture()
        self.headerFrame.text = self.headerFrame:CreateFontString(nil, 'OVERLAY')

        self.headerFrame:EnableMouse(true)
        self.headerFrame:SetMovable(true)
        self.headerFrame:RegisterForDrag('LeftButton')
        self.headerFrame:SetScript("OnDragStart", function()
            if self.config.headerUnlocked then self.headerFrame:StartMoving() end
        end)

        self.headerFrame:SetScript("OnDragStop",
            function()
                self.headerFrame:StopMovingOrSizing()
                self.config.headerAnchor = {self.headerFrame:GetPoint()}
                self.config.headerAnchor[2] = 'UIParent'
            end
        )

        self.headerFrame:SetScript("OnMouseUp",
            function(_, button)
                if button == 'RightButton' then
                    self:showHeaderMenu()
                end
            end
        )

        self.headerFrame.fadeOut = self.headerFrame:CreateAnimationGroup()
        local fadeOut = self.headerFrame.fadeOut:CreateAnimation('Alpha')
        fadeOut:SetDuration(0.5)
        fadeOut:SetStartDelay(0.5)
        -- fadeOut:SetChange(-1 * self.config.headerColor[4])
		fadeOut:SetToAlpha(-1 * self.config.headerColor[4])
        self.headerFrame.fadeOut:SetScript('OnFinished', function() self.headerFrame:SetAlpha(0) end)

        self.headerFrame.fadeIn = self.headerFrame:CreateAnimationGroup()
        local fadeIn = self.headerFrame.fadeIn:CreateAnimation('Alpha')
        fadeIn:SetDuration(0.3)
        -- fadeIn:SetChange(self.config.headerColor[4])
		fadeIn:SetToAlpha(self.config.headerColor[4])
        self.headerFrame.fadeIn:SetScript('OnFinished', function() self.headerFrame:SetAlpha(self.config.headerColor[4]) end)

    else
        self.headerFrame:ClearAllPoints()
    end

    if self.config.showTargetTarget then
        self.headerFrame:SetWidth(self.config.targetWidth * 3 + (self.config.targetHeight/2)+2)
    else
        self.headerFrame:SetWidth(self.config.targetWidth * 2)
    end

    self.headerFrame:SetHeight(self.config.headerHeight)
    self.headerFrame:SetPoint(unpack(self.config.headerAnchor))
    self.headerFrame.backdropInfo = self.config.headerBackdrop
	self.headerFrame:ApplyBackdrop()
    self.headerFrame:SetBackdropColor(0.15, 0.15, 0.15)

    self.headerFrame.texture:SetAllPoints(self.headerFrame)
    self.headerFrame.texture:SetTexture(self.config.headerTexture)
    self.headerFrame.texture:SetVertexColor(unpack(self.config.headerColor))

    self.headerFrame.text:SetFont(self.config.fontName, self.config.fontHeight)
    self.headerFrame.text:SetTextColor(unpack(self.config.fontColor))
    self.headerFrame.text:SetAllPoints(self.headerFrame)
    self.headerFrame.text:SetText(ADDON)
    if self.config.hideAddonName then self.headerFrame.text:Hide() end

    if self.config.autoHideHeader then
        self.headerFrame:SetScript('OnEnter', function()
            if self.headerFrame.fadeOut:IsPlaying() then self.headerFrame.fadeOut:Stop() end
            if self.headerFrame:GetAlpha() < self.config.headerColor[4] then
                self.headerFrame.fadeIn:Play()
            end
        end)
        self.headerFrame:SetScript('OnLeave', function()
            if self.headerFrame.fadeIn:IsPlaying() then self.headerFrame.fadeIn:Stop() end
            if #(util.keys(self.targetButtons)) > 0 then
                self.headerFrame.fadeOut:Play()
            else
                self.headerFrame:SetAlpha(self.config.headerColor[4])
            end
        end)
    else
        self.headerFrame:SetScript('OnEnter', nil)
        self.headerFrame:SetScript('OnLeave', nil)
    end

    self.headerFrame:Show()
    self.headerFrame:SetAlpha(self.config.headerColor[4])

end

function addon:setupButtonFunctionality(buttonFrame, unitID, targetName, menuCall)

    --Hide all buttons on creation
    buttonFrame:Hide()

    --Set us up as a secure button
    buttonFrame:SetAttribute('unitName',targetName)
    buttonFrame:SetAttribute('unitID', unitID)
    buttonFrame.unitID = unitID
    SecureUnitButton_OnLoad(buttonFrame, unitID)

    --Right click menu stuff
    buttonFrame:SetScript("OnMouseUp",
        function(_, button)
            if button == 'RightButton' then
                if not IsModifierKeyDown() then self[menuCall](self, targetName, unitID) end
            end
        end
    )

    --LibKeyBound stuff
    buttonFrame:SetScript("OnEnter",
        function() LibKeyBound:Set(buttonFrame) end
    )

    local command = "CLICK "..buttonFrame:GetName()..":LeftButton"

    function buttonFrame:GetHotkey()
        return GetBindingKey(command)
    end

    function buttonFrame:GetBindings()
        local keys = ""
        for i = 1, select('#', GetBindingKey(command)) do
            local hotKey = select(i, GetBindingKey(command))
            if keys ~= "" then keys = keys .. ', ' end
            keys = keys.. GetBindingText(hotKey,'KEY_')
        end

        return keys
    end

    function buttonFrame:SetKey(key)
        SetBinding(key, command)
    end

    function buttonFrame:ClearBindings()
        while GetBindingKey(command) do
            SetBinding(GetBindingKey(command), nil)
        end
    end

    --Setup Clique support
    ClickCastFrames[buttonFrame] = true

    --Track us for the future
    self.targetButtons[targetName] = buttonFrame

end

local targetTable = {}
function addon:createTargetButtons()

    local headerFrame = self.headerFrame

    wipe(targetTable)
    for _, targetName in ipairs(self.config.targets) do
        if self.roster[targetName] then tinsert(targetTable, targetName) end
    end
    if self.config.invertTargetOrder then
        targetTable = util.inverted(targetTable)
    end

    --Support for Clique
    ClickCastFrames = ClickCastFrames or {}

    --Clean out target button structures (TODO:  how expensive are GC cycles for WoW lua?  I tend to hit them hard...)
    if self.targetButtons then
        for targetName, buttonFrame in pairs(self.targetButtons) do
            buttonFrame:Hide()
            ClickCastFrames[buttonFrame] = nil
        end
        wipe(self.targetButtons)
    else
    	self.targetButtons = {}
    end

    --For each assist target
    local anchorFrame, width = headerFrame, self.config.targetWidth
    self.buttonWidth = width-self.config.spacingOffset
    for i, targetName in ipairs(targetTable) do

        local unitID = self.roster[targetName]
        if unitID then

            if self.config.invertTargetOrder then
                i = #targetTable - (i-1)
            end

            --Make the assist target unit button
            local assistFrame
            local assistFrameName = assistNameTemplate:format(i)
            if _G[assistFrameName] then
                assistFrame = _G[assistFrameName]
                assistFrame:ClearAllPoints()
                assistFrame.texture:ClearAllPoints()
                assistFrame.fontString:ClearAllPoints()
                assistFrame.mostTargetedIcon:ClearAllPoints()
                assistFrame.targetCountString:ClearAllPoints()
            else
                --assistFrame = CreateFrame("Button", assistFrameName, UIParent, "SecureUnitButtonTemplate")
                assistFrame = CreateFrame("Button", assistFrameName, UIParent, "BackdropTemplate")
                assistFrame.texture = assistFrame:CreateTexture()
                assistFrame.fontString = assistFrame:CreateFontString(nil, 'OVERLAY')
                assistFrame.mostTargetedIcon = assistFrame:CreateTexture(nil, 'OVERLAY')
                assistFrame.targetCountString = assistFrame:CreateFontString(nil, 'OVERLAY')
            end

            local buttonAnchorPoint, headerAnchorPoint, verticalOffset = unpack(self.config.targetButtonAnchor)
            assistFrame:SetPoint(buttonAnchorPoint, anchorFrame, headerAnchorPoint, 0, verticalOffset)
            assistFrame:SetWidth(self.buttonWidth)
            assistFrame:SetHeight(self.config.targetHeight)

            assistFrame.backdropInfo = self.config.targetBackdrop
			assistFrame:ApplyBackdrop()
            assistFrame:SetBackdropColor(unpack(self.config.targetBackdropColor))

            assistFrame.texture:SetPoint('TOP', assistFrame, 'TOP')
            assistFrame.texture:SetPoint('BOTTOM', assistFrame, 'BOTTOM')
            assistFrame.texture:SetPoint('LEFT', assistFrame, 'LEFT')
            assistFrame.texture:SetWidth(self.buttonWidth)
            assistFrame.texture:SetTexture(self.config.targetTexture)
            assistFrame.texture:SetVertexColor(unpack(self.config.friendlyTargetColor))

            assistFrame.fontString:SetFont(self.config.fontName, self.config.fontHeight)
            assistFrame.fontString:SetTextColor(unpack(self.config.fontColor))
            assistFrame.fontString:SetAllPoints(assistFrame)

            assistFrame.mostTargetedIcon:SetPoint('BOTTOMRIGHT', assistFrame, 'BOTTOMLEFT', -2, 0)
            assistFrame.mostTargetedIcon:SetHeight(self.config.targetHeight/2)
            assistFrame.mostTargetedIcon:SetWidth(self.config.targetHeight/2)
            assistFrame.mostTargetedIcon:Hide()

            assistFrame.targetCountString:SetFont(self.config.fontName, self.config.fontHeight)
            assistFrame.targetCountString:SetTextColor(unpack(self.config.fontColor))
            assistFrame.targetCountString:SetPoint('TOPRIGHT', assistFrame, 'TOPLEFT', -2, 0)
            assistFrame.targetCountString:SetHeight(self.config.targetHeight/2)
            assistFrame.targetCountString:SetWidth(self.config.targetHeight/2)

            self:setupButtonFunctionality(assistFrame, unitID, targetName, 'showAssistFrameMenu')

            --Make the assist target target unit button
            local targetFrame
            local targetFrameName = targetNameTemplate:format(i)
            if _G[targetFrameName] then
                targetFrame = _G[targetFrameName]
                targetFrame:ClearAllPoints()
                targetFrame.texture:ClearAllPoints()
                targetFrame.fontString:ClearAllPoints()
                targetFrame.mostTargetedIcon:ClearAllPoints()
                targetFrame.targetCountString:ClearAllPoints()
                targetFrame.raidIcon:ClearAllPoints()

            else
                --targetFrame = CreateFrame("Button", targetFrameName, UIParent, "SecureUnitButtonTemplate")
                targetFrame = CreateFrame("Button", targetFrameName, UIParent, "BackdropTemplate")
                targetFrame.texture = targetFrame:CreateTexture()
                targetFrame.fontString = targetFrame:CreateFontString(nil, 'OVERLAY')
                targetFrame.mostTargetedIcon = targetFrame:CreateTexture(nil, 'OVERLAY')
                targetFrame.targetCountString = targetFrame:CreateFontString(nil, 'OVERLAY')
                targetFrame.raidIcon = targetFrame:CreateTexture(nil, "OVERLAY", nil)
            end

            targetFrame:SetPoint('TOP', assistFrame, 'TOP', 0, 0)
            targetFrame:SetPoint('LEFT', assistFrame, 'RIGHT', 2, 0)
            targetFrame:SetWidth(self.buttonWidth)
            targetFrame:SetHeight(self.config.targetHeight)

            targetFrame.backdropInfo = self.config.targetBackdrop
			targetFrame:ApplyBackdrop()
            targetFrame:SetBackdropColor(unpack(self.config.targetBackdropColor))

            targetFrame.texture:SetPoint('TOP', targetFrame, 'TOP')
            targetFrame.texture:SetPoint('BOTTOM', targetFrame, 'BOTTOM')
            targetFrame.texture:SetPoint('LEFT', targetFrame, 'LEFT')
            targetFrame.texture:SetWidth(self.buttonWidth)
            targetFrame.texture:SetTexture(self.config.targetTexture)
            targetFrame.texture:SetVertexColor(unpack(self.config.friendlyTargetColor))

            targetFrame.fontString:SetFont(self.config.fontName, self.config.fontHeight)
            targetFrame.fontString:SetTextColor(unpack(self.config.fontColor))
            targetFrame.fontString:SetAllPoints(targetFrame)

            targetFrame.mostTargetedIcon:SetPoint('BOTTOMLEFT', targetFrame, 'BOTTOMRIGHT', 2, 0)
            targetFrame.mostTargetedIcon:SetHeight(self.config.targetHeight/2)
            targetFrame.mostTargetedIcon:SetWidth(self.config.targetHeight/2)
            targetFrame.mostTargetedIcon:Hide()

            targetFrame.targetCountString:SetFont(self.config.fontName, self.config.fontHeight)
            targetFrame.targetCountString:SetTextColor(unpack(self.config.fontColor))
            targetFrame.targetCountString:SetPoint('TOPLEFT', targetFrame, 'TOPRIGHT', 2, 0)
            targetFrame.targetCountString:SetHeight(self.config.targetHeight/2)
            targetFrame.targetCountString:SetWidth(self.config.targetHeight/2)

            targetFrame.raidIcon:SetPoint('BOTTOMRIGHT', targetFrame, 'BOTTOMRIGHT', 0, 0)
            targetFrame.raidIcon:SetHeight(self.config.targetHeight*.75)
            targetFrame.raidIcon:SetWidth(self.config.targetHeight*.75)

            self:setupButtonFunctionality(targetFrame, unitID..'target', targetName..'target', 'showAssistTargetMenu')

            --Optionally make a target of target button
            if self.config.showTargetTarget then

                local targetTargetFrame
                local targetTargetFrameName = targettargetNameTemplate:format(i)
                if _G[targetTargetFrameName] then
                    targetTargetFrame = _G[targetTargetFrameName]
                    targetTargetFrame:ClearAllPoints()
                    targetTargetFrame.texture:ClearAllPoints()
                    targetTargetFrame.fontString:ClearAllPoints()
                else
                    --targetTargetFrame = CreateFrame("Button", targetTargetFrameName, UIParent, "SecureUnitButtonTemplate")
                    targetTargetFrame = CreateFrame("Button", targetTargetFrameName, UIParent, "BackdropTemplate")
                    targetTargetFrame.texture = targetTargetFrame:CreateTexture()
                    targetTargetFrame.fontString = targetTargetFrame:CreateFontString(nil, 'OVERLAY')
                end

                targetTargetFrame:SetPoint('TOP', assistFrame, 'TOP')
                --TODO remove:  targetTargetFrame:SetPoint('LEFT', headerFrame, 'RIGHT', (self.config.targetHeight/2)+5, 0)
                targetTargetFrame:SetPoint('RIGHT', headerFrame, 'RIGHT', 0, 0)
                targetTargetFrame:SetWidth(self.buttonWidth)
                targetTargetFrame:SetHeight(self.config.targetHeight)

                local targetTargetBackdrop = {
                    bgFile = self.config.targetBackdrop.bgFile,
                    insets = {top = -1, left = -1 * (self.config.targetHeight/2 + 2), bottom = -1, right = -1}
                }

                targetTargetFrame.backdropInfo = targetTargetBackdrop
				targetTargetFrame:ApplyBackdrop()
                targetTargetFrame:SetBackdropColor(unpack(self.config.targetBackdropColor))

                targetTargetFrame.texture:SetPoint('TOP', targetTargetFrame, 'TOP')
                targetTargetFrame.texture:SetPoint('BOTTOM', targetTargetFrame, 'BOTTOM')
                targetTargetFrame.texture:SetPoint('LEFT', targetTargetFrame, 'LEFT')
                targetTargetFrame.texture:SetWidth(self.buttonWidth)
                targetTargetFrame.texture:SetTexture(self.config.targetTexture)
                targetTargetFrame.texture:SetVertexColor(unpack(self.config.friendlyTargetColor))

                targetTargetFrame.fontString:SetFont(self.config.fontName, self.config.fontHeight)
                targetTargetFrame.fontString:SetTextColor(unpack(self.config.fontColor))
                targetTargetFrame.fontString:SetAllPoints(targetTargetFrame)

                self:setupButtonFunctionality(targetTargetFrame, unitID..'targettarget', targetName..'targettarget', 'showAssistTargetMenu')

            end

            --Next time around, anchor to this row
            anchorFrame = assistFrame

        end

    end
    self:updateEnabled()

    --Decide whether or not to show the header frame (logic in the OnLeave function)
    if self.config.autoHideHeader then
        self.headerFrame:GetScript('OnLeave')()
    end
end

function addon:createBasePanel()

    return {
        type = "group",
        name = ("%s Configuration"):format(ADDON),
        args={
            introduction = {
                type = 'description',
                name = ("Changes to many of the configuration settings for %s can only be updated when you are out of combat.  If you make changes while in combat, they will be queued and applied later.\n\nIf you'd like to change the texture or font settings please make sure you have |cffFF7D0ASharedMedia|r installed."):format(ADDON),
                order = 1
            },

            headerUnlocked = {
                type = 'toggle',
                name = 'Unlock header',
                desc = 'Allows the header bar to be moved by dragging it with the mouse.  Uncheck to lock it in place.',
                width = 'full',
                get = function() return self.config.headerUnlocked end,
                set = function(info, value) self.config.headerUnlocked = value end,
                order = 10,
            },
            disabled = {
                type = 'toggle',
                name = 'Disable addon',
                desc = "If checked the addon will be hidden and updates disabled.",
                width = 'full',
                get = function() return self.config.userDisabled end,
                set = function(info, value)
                    self.config.userDisabled = value
                    self:updateEnabled()
                end,
                order = 15,
            },

            h2 = {
                type = 'header',
                name = 'Keybinds',
                order = 20,
            },
            introduction = {
                type = 'description',
                name = ("%s general keybindings can be set through the standard keybindings configuration.  You can also add keybinds to target any assist or assist target using the button below or with the /kb chat command."):format(ADDON),
                order = 21
            },
            showKeybindUI = {
                type = 'execute',
                name = 'General Keybinds',
                desc = ('Shows the built-in keybinding configuration window.  Scroll down to the %s section to find keybindings for this addon.'):format(ADDON),
                func = function()
                    GameMenuButtonKeybindings:Click()
                    GameMenuFrame:Hide()
                    InterfaceOptionsFrame:Hide()
                end,
                order = 22,
            },
            showLibKeybind = {
                type = 'execute',
                name = 'Targeting keybinds',
                desc = ('Shows the built-in keybinding configuration window.  Scroll down to the %s section to find keybindings for this addon.'):format(ADDON),
                func = function() LibKeyBound:Toggle() end,
                order = 23,
            },

            h3 = {
                type = 'header',
                name = 'Performance & Debugging',
                order = 30,
            },
            t1 = {
                type = 'description',
                name = 'It is recommended that you reload your user interface after making adjustments to the configuration.  This will help to free up memory and make the game more responsive.',
                order = 31,
            },
            reloadUI = {
                type = 'execute',
                name = 'Reload',
                desc = 'Reloads the WoW user interface.',
                func = function() ReloadUI() end,
                order = 32,
            },
            updateInterval = {
                type = 'input',
                name = 'Update interval',
                desc = 'Time (in seconds) between updates of button state. Change this to a larger value if you are having performance problems (recommended values are 0.1-0.5).',
                width = 'half',
                pattern = '%d',
                get = function() return tostring(self.config.updateInterval) end,
                set = function(info, value)
                    self.config.updateInterval = tonumber(value)
                    self:updateConfig(true)
                end,
                order = 33,
            },
            broadcastHistory = {
                type = 'input',
                name = 'Broadcast history',
                desc = 'Number of past broadcasts to save in the broadcast history.',
                pattern = '%d',
                get = function() return tostring(self.config.broadcastHistory) end,
                set = function(info, value)
                    self.config.broadcastHistory = tonumber(value)
                    while #self.previousBroadcasts > self.config.broadcastHistory do
                        tremove(self.broadcastHistory, 1)
                    end
                    self:updateConfig(true)
                end,
                order = 34,
            },

            --TODO:  remove once we track down the stack overflow bug
            disableClique = {
                type = 'toggle',
                name = 'Disable Clique support',
                desc = "If checked, Clique support will be disabled.  This option is here for debugging purposes:  if you are experiencing the stack overflow bug, please try checking this option.  Please leave a comment reporting the results on curse.com.",
                width = 'full',
                disabled = IsAddOnLoaded('Clique') == nil,
                get = function() return self.config.disableClique end,
                set = function(info, value)
                    self.config.disableClique = value
                    self:updateConfig(true)
                end,
                order = 35,
            },

        }
    }

end

function addon:createFeaturesPanel()

    return {
        type = "group",
        name = ("%s Features"):format(ADDON),
        args={

            h1 = {
                type = 'header',
                name = 'What to show',
                order = 10,
            },
            hideOutOfGroup = {
                type = 'toggle',
                name = 'Hide addon when not in a group',
                desc = 'Hides the header bar and any targeting buttons when you are not in a party/raid.  Uncheck to leave the header bar shown at all times.',
                width = 'full',
                get = function() return self.config.hideOutOfGroup end,
                set = function(info, value)
                    self.config.hideOutOfGroup = value
                    self:updateRoster()
                end,
                order = 11,
            },
            showTargetTarget = {
                type = 'toggle',
                name = 'Show target of target',
                desc = "Adds an extra column of unit buttons showing each assist target's target",
                width = 'full',
                get = function() return self.config.showTargetTarget end,
                set = function(info, value)
                    self.config.showTargetTarget = value
                    self:updateConfig()
                end,
                order = 12,
            },
            includePlayer = {
                type = 'toggle',
                name = 'Include me in the roster',
                desc = "Allows you to add yourself as a main assist.  If unchecked you will not show up in the selection list and will not be shown as an assist button.",
                width = 'full',
                get = function() return self.config.includePlayer end,
                set = function(info, value)
                    self.config.includePlayer = value
                    self:updateRoster()
                    self:updateConfig()
                end,
                order = 13,
            },
            showPets = {
                type = 'toggle',
                name = 'Include pets in the roster',
                desc = "Includes your pet and all group pets in the roster.",
                width = 'full',
                get = function() return self.config.showPets end,
                set = function(info, value)
                    self.config.showPets = value
                    self:updateRoster()
                    self:updateConfig()
                end,
                order = 14,
            },


            h2 = {
                type = 'header',
                name = ('%s Sources'):format(ADDON),
                order = 20,
            },
            includeRaidAssists = {
                type = 'toggle',
                name = 'Raid Assists',
                desc = 'Include any party/raid members assigned the role of main assist through the Blizzard UI. Applies to auto addition as well as through the header context menu.\n\nRaid leaders can set the main assist role with the "/ma PlayerName" chat command.',
                get = function() return self.config.includeRaidAssists end,
                set = function(info, value) self.config.includeRaidAssists = value end,
                order = 21,
            },
            includeRaidTanks = {
                type = 'toggle',
                name = 'Raid Tanks',
                desc = 'Include any party/raid members assigned the roles of main tank.  Applies to auto addition as well as through the header context menu.\n\nRaid leaders can set the main tank role with the "/mt PlayerName" chat command.',
                get = function() return self.config.includeRaidTanks end,
                set = function(info, value) self.config.includeRaidTanks = value end,
                order = 22,
            },
            includeRoleTanks = {
            	type = 'toggle',
            	name = 'Tank Role',
            	desc = 'Include any party/raid members assigned the role of tank. Applies to auto addition as well as through the header context menu.\n\nRaid leaders and assistants can set role manually or perform a role check, also set by the LFD/R tools.',
            	get = function() return self.config.includeRoleTanks end,
            	set = function(info, value) self.config.includeRoleTanks = value end,
            	order = 23,
            },
            includeSpecTanks = {
            	type = 'toggle',
            	name = 'Tank Specialization',
            	desc = 'Include and party/raid members in tank specialization. Applies to auto addition as well as through the header context menu.',
            	get = function() return self.config.includeSpecTanks end,
            	set = function(info, value) self.config.includeSpecTanks = value end,
            	order = 24,
            },
            includeORA3 = {
                type = 'toggle',
                name = 'Tanks from oRA3',
                desc = 'Include party/raid members assigned as tanks through oRA3 when adding tanks manually or automatically (requires oRA3).',
                width = 'double',
                get = function() return self.config.includeORA3 end,
                set = function(info, value) self.config.includeORA3 = value end,
                disabled = function() return not oRA3 end,
                order = 25,
            },
            autoAddTargets = {
            	type = 'toggle',
            	name = 'Auto Add',
            	desc = ('Auto add %s units from the selected sources.'):format(ADDON),
            	get = function() return self.config.autoAddTargets end,
            	set = function(info, value)
                    self.config.autoAddTargets = value
                    if not self.config.autoAddTargets then
                        self.config.purgeAutoAdds = false
                    end
                end,
            	order = 26,
            },
            purgeAutoAdds = {
                type = 'toggle',
                name = 'Reset automatically added tanks and mainassists',
                desc = 'Clears the automatically added tanks and mainassists whenever the roster updates.',
                width = 'double',
                get = function() return self.config.purgeAutoAdds end,
                set = function(info, value) self.config.purgeAutoAdds = value end,
                disabled = function() return not self.config.autoAddTargets end,
                order = 27,
            },
            autoAcceptBroadcasts = {
                type = 'toggle',
                name = 'Automatically accept broadcasted targets',
                desc = 'Automatically accept incomming assist target lists broadcasted by other players in your party/group.  If this is left unchecked you will be asked whether or not you want to accept broadcasts when they are received.',
                width = 'double',
                get = function() return self.config.autoAcceptBroadcasts end,
                set = function(info, value) self.config.autoAcceptBroadcasts = value end,
                order = 28,
            },

            h3 = {
                type = 'header',
                name = 'Button markers',
                order = 30,
            },
            fadeOutOfRange = {
                type = 'toggle',
                name = 'Fade out of range units',
                desc = 'Fades unit buttons for targets that are out of range.  Friendly units are faded based on the range of typical heals.  Hostile targets are faded based on class-specific spell/ability checks.',
                get = function() return self.config.fadeOutOfRange end,
                set = function(info, value)
                	self.config.fadeOutOfRange = value
                	if self.config.fadeOutOfRange then
                		if not self.enemyOutOfRangeChecker then
                			self.enemyOutOfRangeChecker = self.LibRange:GetHarmMinChecker(self.config.enemyRange)
                		end
                		if not self.friendOutOfRangeChecker then
                			self.friendOutOfRangeChecker = self.LibRange:GetFriendMinChecker(self.config.friendRange)
                		end
                	end
                end,
                disabled = not (self.LibRange),
                order = 31,
            },
            enemyRange = {
            	type = 'input',
            	name = 'Enemy',
            	desc = 'Further than x (numeric) yards will be considered out of range',
            	width = 'half',
            	get = function() return tostring(self.config.enemyRange) end,
            	set = function(info, value)
            		local val,range = tonumber(value)
            		self.enemyOutOfRangeChecker,range = self.LibRange:GetHarmMinChecker(val)
            		self.config.enemyRange = range and range or val
            	end,
            	validate = function(info, value)
            		local val = tonumber(value)
            		if not val or not (self.LibRange:GetHarmMinChecker(val)) then
            			print(('%s: Invalid range specified!'):format(ADDON))
            			return false
            		else
            			return true
            		end
            	end,
            	disabled = function() return not self.config.fadeOutOfRange end,
            	order = 32,
            },
            friendRange = {
            	type = 'input',
            	name = 'Friend',
            	desc = 'Further than y (numeric) yards will be considered out of range',
            	width = 'half',
            	get = function() return tostring(self.config.friendRange) end,
            	set = function(info, value)
            		local val,range = tonumber(value)
            		self.friendOutOfRangeChecker,range = self.LibRange:GetFriendMinChecker(val)
            		self.config.friendRange = range and range or val
            	end,
            	validate = function(info, value)
            		local val = tonumber(value)
            		if not val or not (self.LibRange:GetFriendMinChecker(val)) then
            			print(('%s: Invalid range specified!'):format(ADDON))
            			return false
            		else
            			return true
            		end
            	end,
            	disabled = function() return not self.config.fadeOutOfRange end,
            	order = 33,
            },
            outOfRangeAlphaOffset = {
            	type = 'range',
            	name = 'Fade out alpha offset',
            	desc = 'The amount of alpha to reduce when the target is out of range. Bigger values affect visibility more.',
            	min = 0.1, max = 0.9, step = 0.1,
            	get = function() return self.config.outOfRangeAlphaOffset end,
            	set = function(info, value) self.config.outOfRangeAlphaOffset = value end,
            	disabled = function() return not self.config.fadeOutOfRange end,
            	order = 34,
            },
            trackNumberTargetingHostiles = {
                type = 'toggle',
                name = 'Track group members targeting hostiles',
                desc = 'Adds a counter next to all hostile units being targeted by MTs/MAs showing the number of party/raid members targeting that unit.',
                width = 'full',
                get = function() return self.config.trackNumberTargetingHostiles end,
                set = function(info, value)
                    self.config.trackNumberTargetingHostiles = value
                    self:updateConfig()
                end,
                order = 35,
            },
            markMostTargetedHostile = {
                type = 'toggle',
                name = 'Mark most popular hostile target',
                desc = 'Marks the most common hostile target with a Skull icon.',
                width = 'full',
                get = function() return self.config.markMostTargetedHostile end,
                set = function(info, value)
                    self.config.markMostTargetedHostile = value
                    self:updateConfig()
                end,
                order = 36,
            },
            trackNumberTargetingFriendlies = {
                type = 'toggle',
                name = 'Track group members targeting friendlies',
                desc = 'Adds a counter next to all MAs/MTs showing the number of party/raid members targeting that player.',
                width = 'full',
                get = function() return self.config.trackNumberTargetingFriendlies end,
                set = function(info, value)
                    self.config.trackNumberTargetingFriendlies = value
                    self:updateConfig()
                end,
                order = 37,
            },
            markMostTargetedFriendly = {
                type = 'toggle',
                name = 'Mark most popular friendly target',
                desc = 'Marks the most common target with a green triangle icon.',
                width = 'full',
                get = function() return self.config.markMostTargetedFriendly end,
                set = function(info, value)
                    self.config.markMostTargetedFriendly = value
                    self:updateConfig()
                end,
                order = 38,
            },
        }
    }

end

function addon:createAppearancePanel()

    return {
        type = "group",
        name = ("%s Appearance"):format(ADDON),
        args={

            h1 = {
                type = 'header',
                name = 'Button positioning',
                order = 10,
            },
            growVertically = {
                type = 'toggle',
                name = 'Advance buttons upwards',
                desc = 'If checked the targeting buttons advance upwards from the header bar.  If unchecked they advance downwards.',
                width = 'full',
                get = function()
                    return self.config.targetButtonAnchor[1] == 'BOTTOMLEFT'
                end,
                set = function(info, value)
                    if value == true then
                        self.config.targetButtonAnchor[1] = 'BOTTOMLEFT'
                        self.config.targetButtonAnchor[2] = 'TOPLEFT'
                        self.config.invertTargetOrder = true
                    else
                        self.config.targetButtonAnchor[1] = 'TOPLEFT'
                        self.config.targetButtonAnchor[2] = 'BOTTOMLEFT'
                        self.config.invertTargetOrder = false
                    end
                    self.config.targetButtonAnchor[3] = self.config.targetButtonAnchor[3]*-1
                    self:updateConfig()
                end,
                order = 14,
            },
            spacingOffset = {
                type = 'input',
                name = 'Horizontal spacing',
                desc = 'Horizontal spacing between assist buttons',
                pattern = '%d',
                width = 'half',
                get = function() return tostring(self.config.spacingOffset) end,
                set = function(info, value)
                    self.config.spacingOffset = tonumber(value)
                    self:updateConfig()
                end,
                order = 15,
            },
            verticalOffset = {
                type = 'input',
                name = 'Vertical spacing',
                desc = 'Vertical spacing between rows of assist buttons and the header bar.',
                pattern = '%d',
                width = 'half',
                get = function() return tostring(self.config.targetButtonAnchor[3]*(self.config.targetButtonAnchor[1] == 'BOTTOMLEFT' and 1 or -1)) end,
                set = function(info, value)
                    self.config.targetButtonAnchor[3] = tonumber(value)*(self.config.targetButtonAnchor[1] == 'BOTTOMLEFT' and 1 or -1)
                    self:updateConfig()
                end,
                order = 16,
            },


            h2 = {
                type = 'header',
                name = 'Header bar',
                order = 20,
            },
            autoHideHeader = {
                type = 'toggle',
                name = 'Hide header bar',
                desc = 'Hides the header bar until you hover your mouse over it.',
                width = 'full',
                get = function() return self.config.autoHideHeader end,
                set = function(info, value)
                    self.config.autoHideHeader = value
                    self:updateConfig()
                end,
                order = 21,
            },
            hideAddonName = {
                type = 'toggle',
                name = 'Hide addon name',
                desc = ('Removes the text %q from the header bar.'):format(ADDON),
                width = 'full',
                get = function() return self.config.hideAddonName end,
                set = function(info, value)
                    self.config.hideAddonName = value
                    if value then
                        self.headerFrame.text:Hide()
                    else
                        self.headerFrame.text:Show()
                    end
                end,
                order = 22,
            },
            headerHeight = {
                type = 'input',
                name = 'Header height',
                desc = 'Height of the header bar (a positive value)',
                width = 'half',
                pattern = '%d',
                get = function() return tostring(self.config.headerHeight) end,
                set = function(info, value)
                    self.config.headerHeight = tonumber(value)
                    self:updateConfig()
                end,
                order = 24,
            },
            headerTexture = {
                type = 'select',
                name = 'Header texture',
                desc = 'Texture used to paint the header bar.  If this control is greyed out please installed SharedMedia.',
                dialogControl = 'LSM30_Statusbar',
                values = AceGUIWidgetLSMlists.statusbar,
                get = function() return util.keyFromValue(AceGUIWidgetLSMlists.statusbar, self.config.headerTexture) end,
                set = function(info, key)
                    self.config.headerTexture = AceGUIWidgetLSMlists.statusbar[key]
                    self:updateConfig()
                end,
                order = 25,
            },
            headerColor = {
                type = 'color',
                name = 'Header color',
                desc = 'Changes the color of the header bar.',
                hasAlpha = true,
                get = function() return unpack(self.config.headerColor) end,
                set = function(info, r,g,b,a)
                    self.config.headerColor = {r,g,b,a}
                    self:updateConfig()
                end,
                order = 26,
            },

            h3 = {
                type = 'header',
                name = 'Assist/Target Buttons',
                order = 30,
            },
            targetHeight = {
                type = 'input',
                name = 'Button height',
                desc = 'Height of the assist buttons (a positive value)',
                width = 'half',
                pattern = '%d',
                get = function() return tostring(self.config.targetHeight) end,
                set = function(info, value)
                    self.config.targetHeight = tonumber(value)
                    self:updateConfig()
                end,
                order = 32,
            },
            targetWidth = {
                type = 'input',
                name = 'Header width',
                desc = 'Width of the assist buttons (a positive value)',
                width = 'half',
                pattern = '%d',
                get = function() return tostring(self.config.targetWidth) end,
                set = function(info, value)
                    self.config.targetWidth = tonumber(value)
                    self:updateConfig()
                end,
                order = 32.5,
            },

            targetTexture = {
                type = 'select',
                name = 'Button texture',
                desc = 'Texture used to paint the assist buttons.  If this control is greyed out please installed SharedMedia.',
                dialogControl = 'LSM30_Statusbar',
                values = AceGUIWidgetLSMlists.statusbar,
                get = function() return util.keyFromValue(AceGUIWidgetLSMlists.statusbar, self.config.targetTexture) end,
                set = function(info, key)
                    self.config.targetTexture = AceGUIWidgetLSMlists.statusbar[key]
                    self:updateConfig()
                end,
                order = 34,
            },

            colorFriendlyTargetsByClass = {
                type = 'toggle',
                name = 'Color friendly targets by class',
                desc = "Colors the assist buttons tracking friendly targets based on the character's class.",
                get = function() return self.config.colorFriendlyTargetsByClass end,
                set = function(info, value)
                    self.config.colorFriendlyTargetsByClass = value
                    self:updateConfig()
                end,
                width = 'full',
                order = 35,
            },

            friendlyTargetColor = {
                type = 'color',
                name = 'Friendly target color',
                desc = 'Changes the color of the assist buttons tracking friendly targets.',
                hasAlpha = true,
                get = function() return unpack(self.config.friendlyTargetColor) end,
                set = function(info, r,g,b,a)
                    self.config.friendlyTargetColor = {r,g,b,a}
                    self:updateConfig()
                end,
                width = 'full',
                order = 35.5,
            },

            colorHostileTargetsByClass = {
                type = 'toggle',
                name = 'Color hostile targets by class',
                desc = "Colors the assist buttons tracking hostile targets based on the character's class.  Only affects targets who are player characters.\n\nIf this option is enabled than the font for hostile targets is colored using the 'Hostile target color' setting below.",
                get = function() return self.config.colorHostileTargetsByClass end,
                set = function(info, value)
                    self.config.colorHostileTargetsByClass = value
                    self:updateConfig()
                end,
                width = 'full',
                order = 35.8
            },

            hostileTargetColor = {
                type = 'color',
                name = 'Hostile target color',
                desc = "Changes the color of the assist buttons tracking hostile targets.\n\nAlternatively, if 'Color hostile targets by class' is checked, this color is used for the font on hostile targets.",
                hasAlpha = true,
                get = function() return unpack(self.config.hostileTargetColor) end,
                set = function(info, r,g,b,a)
                    self.config.hostileTargetColor = {r,g,b,a}
                    self:updateConfig()
                end,
                order = 35.9,
            },

            missingColor = {
                type = 'color',
                name = 'Button color (dead or missing)',
                desc = 'Color for buttons when the associated unit is dead or missing.',
                hasAlpha = true,
                width = 'full',
                get = function() return unpack(self.config.missingColor) end,
                set = function(info, r,g,b,a)
                    self.config.missingColor = {r,g,b,a}
                    self:updateConfig()
                end,
                order = 36,
            },

            myTargetColor = {
                type = 'color',
                name = 'Button color (my target)',
                desc = 'Color for buttons associated with the unit you currently have targeted.',
                hasAlpha = true,
                width = 'full',
                get = function() return unpack(self.config.myTargetColor) end,
                set = function(info, r,g,b,a)
                    self.config.myTargetColor = {r,g,b,a}
                    self:updateConfig()
                end,
                order = 37,
            },

            showHealth = {
                type = 'toggle',
                name = 'Show health bar',
                desc = 'If checked the colored texture on assist buttons will reflect the percentage health of the associated unit.',
                width = 'full',
                get = function() return self.config.showHealth end,
                set = function(info, value)
                    self.config.showHealth = value
                    if value == false then
                    	if self.targetButtons then
	                        for _, buttonFrame in pairs(self.targetButtons) do
	                            buttonFrame.texture:SetWidth( self.buttonWidth )
	                        end
                    	end
                    end
                end,
                order = 38.1,
            },

            showFriendlyHealthPercent = {
                type = 'toggle',
                name = 'Show friendly unit health percentage',
                desc = 'If checked shows the percentage health for friendly units.',
                width = 'full',
                get = function() return self.config.showFriendlyHealthPercent end,
                set = function(info, value)
                    self.config.showFriendlyHealthPercent = value
                end,
                order = 38.3,
            },

            showHostileHealthPercent = {
                type = 'toggle',
                name = 'Show hostile unit health percentage',
                desc = 'If checked shows the percentage health for hostile units.',
                width = 'full',
                get = function() return self.config.showHostileHealthPercent end,
                set = function(info, value)
                    self.config.showHostileHealthPercent = value
                end,
                order = 38.5,
            },

            h4 = {
                type = 'header',
                name = 'Font',
                order = 40,
            },

            fontName = {
                type = 'select',
                name = 'Font',
                desc = 'Font used to draw text in the addon.  If this box is greyed out please install SharedMedia.',
                dialogControl = 'LSM30_Font',
                values = AceGUIWidgetLSMlists.font,
                get = function() return util.keyFromValue(AceGUIWidgetLSMlists.font, self.config.fontName) end,
                set = function(info, key)
                    self.config.fontName = AceGUIWidgetLSMlists.font[key]
                    self:updateConfig()
                end,
                order = 41,
            },

            fontHeight = {
                type = 'input',
                name = 'Font height',
                desc = 'Height of text drawn by the addon (a positive value)',
                width = 'half',
                pattern = '%d',
                get = function() return tostring(self.config.fontHeight) end,
                set = function(info, value)
                    self.config.fontHeight = tonumber(value)
                    self:updateConfig()
                end,
                order = 42,
            },

            fontColor = {
                type = 'color',
                name = 'Font color',
                desc = 'Color for text drawn by the addon.',
                hasAlpha = true,
                get = function() return unpack(self.config.fontColor) end,
                set = function(info, r,g,b,a)
                    self.config.fontColor = {r,g,b,a}
                    self:updateConfig()
                end,
                order = 43
            },

        }
    }

end

function addon:createConsoleOptions()

    return {
        type = "group",
        name = ("%s Configuration"):format(ADDON),
        args={
            introduction = {
                type = 'description',
                name = ("Changes to many of the configuration settings for %s can only be updated when you are out of combat.  If you make changes while in combat, they will be queued and applied later."):format(ADDON),
                order = 1
            },
            add = {
                type = 'group',
                name = 'Add MAs/MTs',
                order = 20,
                args = {
                    target = {
                        type = 'execute',
                        name = 'add current target',
                        order = 1,
                        func = function() self:addTarget() end,
                    },
                    all = {
                        type = 'execute',
                        name = 'add all group members',
                        order = 2,
                        func = function() self:addAll() end,
                    },
                    party = {
                        type = 'execute',
                        name = 'add all party members',
                        order = 3,
                        func = function() self:addParty() end,
                    },
                    tanks = {
                        type = 'execute',
                        name = 'add all tanks',
                        order = 4,
                        func = function() self:addTanks() end,
                    },
                    mainassists = {
                        type = 'execute',
                        name = 'add all main assists',
                        order = 4,
                        func = function() self:addMainAssists() end,
                    },
                    player = {
                        type = 'input',
                        name = 'Add player by name (must be in raid or party).  Usage: "/ta add player NAME" where NAME is the name of the player to add.',
                        order = 4,
                        get = function() return '' end,
                        set = function(info, value)
                            if self.roster[value] then
                                if not util.hasValue(self.config.targets, value) then
                                    tinsert(self.config.targets, 1, value)
                                    autoAdds[value] = nil
                                end
                            else
                                print("Could not find player '"..tostring(value).."' in your raid or party.")
                            end
                        end,
                    },
                },
            },

            clear = {
                type = 'execute',
                name = 'Clear all MAs/MTs.',
                func = function() self:clearAll() end,
                order = 50,
            },
            invert = {
                type = 'execute',
                name = 'Invert  assist order',
                func = function() self:invertTargetOrder() end,
                order = 50.1,
            },
            hide = {
                type = 'execute',
                name = 'Hides the addon and disables updates.  Use /ta show to re-enable.',
                func = function()
                    self.config.userDisabled = true
                    self:updateEnabled()
                end,
                order = 50.2,
            },
            show = {
                type = 'execute',
                name = 'Show the addon and re-enables updates after being hidden.  Also shows the addon if it is being hidden because you are not in a group.',
                func = function()
                    self.config.userDisabled = false
                    if not IsInGroup() and self.config.hideOutOfGroup then
                        self.config.hideOutOfGroup = false
                        self.hide = false
                    end
                    self:updateEnabled()
                end,
                order = 50.3,
            },
            config = {
                type = 'execute',
                name = 'Open configuration panel.',
                func = function() InterfaceOptionsFrame_OpenToCategory(self.optionsBaseFrame) end,
                order = 51,
            },
        }
    }

end
