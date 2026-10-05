setfenv(1, SpokenEnv)

-- The DialogueUI window, the narrator style "dialogueui": the queue drawn as a smaller twin
-- of the DialogueUI addon's quest window, in that addon's own parchment or dark art, so the two read as one piece when
-- DialogueUI is the dialog on screen. Top to bottom: the speaker's face and name, the
-- captions filling the body, the waiting lines, and the playback controls along the foot.
--
-- Everything DialogueUI-shaped comes through UI/DialogueUITheme.lua: the art folder, the
-- window size the panel is a share of, the text colours. The panel itself keeps DialogueUI's
-- proportions -- its paddings and its parchment strips, which overhang the frame as its
-- do -- scaled by the Panel Size setting. Playback, actions and portraits are the services
-- the other windows use; the queue rows are built from MinimalPlayer's parts. Nothing here
-- is about quests: a zone's lore or a book page plays in it as any line does, the book for
-- a face and the page's title under the book's.
--
-- Not at the Window Scale: the panel is already sized from DialogueUI's window, and that
-- slider is hidden for this style.
--
-- Parsed by the 1.12 client too (addon.xml is shared), so Lua 5.0 syntax throughout; the
-- stub below is all that client runs.

DialogueUIPlayer = { rows = {}, offset = 0 }

if Version.IsAnyLegacy then
    function DialogueUIPlayer:IsEnabled() return false end
    function DialogueUIPlayer:SetVisible() end
    function DialogueUIPlayer:HasClip() return false end
    function DialogueUIPlayer:Describe() return "dialogueui skin: not available on this client" end
    return
end

local Skin = DialogueUIPlayer
local Theme = DialogueUITheme
local MAX_ROWS, ROW_HEIGHT = 4, 20
local PORTRAIT = 48
local CORNER_ICON = 20
local CONTROL_HEIGHT = 22
local BAR_HEIGHT = 3
local MIN_LINES = 2
local SCROLLBAR = 10
-- The quest title a little under DialogueUI's: its title shares the strip with nothing,
-- and here the speaker's name sits above it.
local TITLE_SHARE = 0.85
-- How far Shift-dragging may take the width, as shares of DialogueUI's own.
local MIN_WIDTH_SHARE, MAX_WIDTH_SHARE = 0.6, 2
-- DialogueUI's paddings at multiplier 1, and its window height as a share of the screen,
-- from which the multiplier its window was drawn at is recovered.
local PAD_H, PAD_TOP, PAD_BOTTOM = 26, 48, 36
local HEIGHT_SHARE = 0.618
-- Where in Parchment.png each strip is. The caps are 256 of 2048 rows each, the middle
-- the 640 between them; the dividers sit lower in the same image.
local CAP_ROWS, MIDDLE_ROWS = 0.125, 0.3125
local HEADER_DIVIDER = { 0, 0.65625, 0.56640625, 0.61328125, 358, 51 }
-- Where, of the strip's 358, the portrait socket at its left end gives way to the plain
-- line. The socket is drawn as is; only the line past it stretches with the panel.
local SOCKET_WIDTH = 64
local FOOTER_DIVIDER = { 0, 0.71875, 0.6875, 0.71875, 392, 34 }
-- What Panel size and Font size scale may be set to, by the settings' sliders or by the
-- wheel with Ctrl held, and the step of each.
Skin.PANEL_SIZES = { 0.3, 1.2 }
Skin.FONT_SIZES = { 0.3, 1.5 }
Skin.SIZE_STEP = 0.05

local parts = MinimalPlayer.parts
local Font, Removable, ShowRemove, Label = parts.Font, parts.Removable, parts.ShowRemove, parts.Label
local function Clamp(n, low, high) return math.max(low, math.min(high, n)) end
local function Round(n) return math.floor(n + 0.5) end
-- Through Addon:Profile: the frame still redraws while the UI is torn down, after AceDB
-- strips the profile. Its DialogueUI table likewise, from the defaults when stripped.
local function Config() return Addon:Profile("Frame") end
local function Panel() return Config().DialogueUI or Defaults.profile.Frame.DialogueUI end
local function Waiting() return math.max(0, SoundQueue:GetQueueSize() - 1) end
local function BelongsTo(frame, root)
    while frame do
        if frame == root then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

function Skin:IsEnabled()
    return Addon.db and Addon:DisplayStyle() == "dialogueui"
end

function Skin:HideTooltip()
    if BelongsTo(GameTooltip:GetOwner(), self.frame) then GameTooltip_Hide() end
end

function Skin:HasClip()
    return self:IsEnabled() and self.wanted and SoundQueue:GetCurrentSound() ~= nil
end

--- A flat text button in DialogueUI's manner: a label, and its gossip-option glow under
--- the mouse. `fn` runs while a clip plays.
local function TextButton(parent, text, fn)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(CONTROL_HEIGHT)
    button.text = Font(button, 12, 1, 1, 1)
    button.text:SetPoint("LEFT", 6, 0)
    button.text:SetPoint("RIGHT", -6, 0)
    button.text:SetJustifyH("CENTER")
    button.text:SetText(text)
    button:SetHighlightTexture([[Interface\Buttons\UI-Listbox-Highlight2]])
    button:GetHighlightTexture():SetAlpha(0.25)
    button:SetScript("OnClick", function()
        if Skin:HasClip() then fn() end
    end)
    return button
end

function Skin:Initialize(original)
    if self.frame then return end
    local frame = CreateFrame("Frame", "SpokenDialogueUIPlayerFrame", UIParent)
    self.frame = frame
    frame.spokenBaseScale = 1
    frame:SetSize(300, 400)
    if not Addon:RestoreLayout("DialogueUI", frame) then
        -- Left of centre, the mirror of where DialogueUI puts its window, so the two sit
        -- side by side rather than one over the other.
        frame:SetPoint("CENTER", UIParent, "CENTER", -Round(UIParent:GetWidth() / 4), 0)
    end
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:SetUserPlaced(false)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() self:StartDrag() end)
    frame:SetScript("OnDragStop", function() self:StopDrag() end)
    -- No menu of its own: right-click opens the settings, as the Large Window's does.
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Options:Open() end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed) self:Tick(elapsed) end)
    -- While the handle is dragged the captions follow the edge, not the drop.
    frame:SetScript("OnSizeChanged", function()
        if self.sizing and not self.layingOut then self:Layout() end
    end)
    frame:SetScript("OnHide", function() self:HideTooltip() end)
    -- Ctrl and the wheel size the panel, Ctrl, Shift and the wheel its text. The captions
    -- and the queue take the wheel first and hand it here when Ctrl is held.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) self:Wheel(delta) end)
    frame.spokenWheel = function(delta) return self:Wheel(delta) end
    frame:Hide()

    -- The three parchment strips, as DialogueUI lays them: a cap centred on each end of
    -- the frame and the middle stretched between, all wider than the frame itself.
    self.parchments = {}
    for index = 1, 3 do
        local strip = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        self.parchments[index] = strip
    end
    self.parchments[1]:SetPoint("CENTER", frame, "TOP", 0, 0)
    self.parchments[3]:SetPoint("CENTER", frame, "BOTTOM", 0, 0)
    self.parchments[2]:SetPoint("TOPLEFT", self.parchments[1], "BOTTOMLEFT", 0, 0)
    self.parchments[2]:SetPoint("BOTTOMRIGHT", self.parchments[3], "TOPRIGHT", 0, 0)
    self.parchments[1]:SetTexCoord(0, 1, 0, CAP_ROWS)
    self.parchments[2]:SetTexCoord(0, 1, CAP_ROWS, CAP_ROWS + MIDDLE_ROWS)
    self.parchments[3]:SetTexCoord(0, 1, CAP_ROWS + MIDDLE_ROWS, 2 * CAP_ROWS + MIDDLE_ROWS)

    local content = CreateFrame("Frame", nil, frame)
    self.content, frame.container = content, content
    content.buttons = {}

    -- Header: DialogueUI's header strip, whose left end is a socket the face sits in, as
    -- DialogueUI sets its own; the speaker and the line's title to the right of it.
    -- DialogueUI's header strip in two pieces: the socket the face sits in, never stretched,
    -- and the line running on from it to the panel's width.
    local socketU = HEADER_DIVIDER[1] + (HEADER_DIVIDER[2] - HEADER_DIVIDER[1]) * SOCKET_WIDTH / HEADER_DIVIDER[5]
    self.headerSocket = content:CreateTexture(nil, "ARTWORK")
    self.headerSocket:SetTexCoord(HEADER_DIVIDER[1], socketU, HEADER_DIVIDER[3], HEADER_DIVIDER[4])
    self.headerDivider = content:CreateTexture(nil, "ARTWORK")
    self.headerDivider:SetTexCoord(socketU, HEADER_DIVIDER[2], HEADER_DIVIDER[3], HEADER_DIVIDER[4])
    local host = CreateFrame("Frame", nil, content)
    self.portrait, frame.portrait = host, host
    host:SetSize(PORTRAIT, PORTRAIT)
    self.viewport = CreateFrame("Frame", nil, host)
    self.viewport:SetAllPoints()
    self.viewport:SetClipsChildren(true)
    -- Pause and play on the face itself, as the Minimal Classic skin has it: the glyph
    -- shows under the mouse or while paused, and a wash dims a paused face.
    local pause = CreateFrame("Button", nil, host)
    self.pause = pause
    pause:SetAllPoints()
    pause:SetFrameLevel(host:GetFrameLevel() + 3)
    pause.wash = pause:CreateTexture(nil, "BACKGROUND")
    pause.wash:SetAllPoints()
    -- The round mask as a disc, so the wash stops at the face's edge.
    pause.wash:SetTexture([[Interface\AddOns\Spoken\Textures\MinimalPortraitMask]])
    pause.wash:SetVertexColor(0, 0, 0, .45)
    pause:SetNormalTexture([[Interface\AddOns\Spoken\Textures\PortraitFrameAtlas]])
    local glyph = pause:GetNormalTexture()
    glyph:ClearAllPoints()
    glyph:SetPoint("CENTER")
    glyph:SetSize(18, 18)
    pause:SetScript("OnClick", function()
        if self:HasClip() and SoundQueue:CanBePaused() then SoundQueue:TogglePauseQueue() end
    end)
    pause:SetScript("OnEnter", function()
        self:UpdateControls()
        if not self:HasClip() then return end
        GameTooltip:SetOwner(pause, "ANCHOR_RIGHT")
        GameTooltip:SetText(SoundQueue:IsPaused() and L.PLAY or L.PAUSE)
        GameTooltip:AddLine(L.PAUSE_TOOLTIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pause:SetScript("OnLeave", function() self:UpdateControls(); self:HideTooltip() end)
    self.name = Font(content, 18, 1, 1, 1)
    content.name = self.name -- Actions' header anchor contract.
    self.title = CreateFrame("Button", nil, content)
    self.name:SetHeight(20)
    Removable(self.title, 12, 1, 1, 1)
    self.title:SetScript("OnClick", function()
        if self:HasClip() then SoundQueue:RemoveSoundFromQueue(self.clip) end
    end)
    self.title:SetScript("OnEnter", function()
        if not self:HasClip() then return end
        ShowRemove(self.title, true)
        GameTooltip:SetOwner(self.title, "ANCHOR_RIGHT")
        GameTooltip:SetText(Label(self.clip))
        GameTooltip:AddLine(L.QUEUE_REMOVE_TOOLTIP, 1, .82, 0, true)
        GameTooltip:Show()
    end)
    self.title:SetScript("OnLeave", function()
        ShowRemove(self.title, false)
        self:HideTooltip()
    end)

    -- The corner: a cross that closes the line (the next one plays), and the fold that
    -- takes the panel down to two caption lines or back up.
    self.close = CreateFrame("Button", nil, content)
    self.close:SetSize(CORNER_ICON, CORNER_ICON)
    self.close:SetPoint("TOPRIGHT", content, "TOPRIGHT", 4, 4)
    self.close:SetNormalTexture([[Interface\Buttons\UI-Panel-MinimizeButton-Up]])
    self.close:SetPushedTexture([[Interface\Buttons\UI-Panel-MinimizeButton-Down]])
    self.close:SetHighlightTexture([[Interface\Buttons\UI-Panel-MinimizeButton-Highlight]], "ADD")
    self.close:SetScript("OnClick", function()
        if self:HasClip() then SoundQueue:Skip() end
    end)
    self.close:SetScript("OnEnter", function()
        GameTooltip:SetOwner(self.close, "ANCHOR_LEFT")
        GameTooltip:SetText(L.DUI_CLOSE)
        GameTooltip:AddLine(L.DUI_CLOSE_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.close:SetScript("OnLeave", function() self:HideTooltip() end)
    self.fold = CreateFrame("Button", nil, content)
    self.fold:SetSize(CORNER_ICON - 4, CORNER_ICON - 4)
    self.fold:SetPoint("RIGHT", self.close, "LEFT", 0, 0)
    self.fold:SetHighlightTexture([[Interface\Buttons\UI-PlusButton-Hilight]], "ADD")
    self.fold:SetScript("OnClick", function() self:SetExpanded(not self.expanded) end)
    self.fold:SetScript("OnEnter", function()
        GameTooltip:SetOwner(self.fold, "ANCHOR_LEFT")
        GameTooltip:SetText(self.expanded and L.TRANSCRIPT_COLLAPSE or L.TRANSCRIPT_EXPAND)
        GameTooltip:Show()
    end)
    self.fold:SetScript("OnLeave", function() self:HideTooltip() end)
    self.expanded = Panel().Expanded ~= false

    -- The waiting lines, under the captions.
    self.drawer = CreateFrame("Frame", nil, content)
    self.drawer:EnableMouseWheel(true)
    self.drawer:SetScript("OnMouseWheel", function(_, delta)
        if self:Wheel(delta) then return end
        self.offset = Clamp(self.offset - delta, 0, math.max(0, Waiting() - MAX_ROWS))
        self:LayoutQueue()
    end)
    self.queueNote = Font(self.drawer, 10, 1, 1, 1)
    self.drawer:Hide()

    -- Footer: the progress line, the divider, then the controls.
    self.bar = CreateFrame("StatusBar", nil, content)
    self.bar:SetHeight(BAR_HEIGHT)
    self.bar:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
    self.bar:SetMinMaxValues(0, 1)
    self.bar:SetValue(0)
    -- A faint track, so the line reads as a bar even when little of it is filled.
    self.track = self.bar:CreateTexture(nil, "BACKGROUND")
    self.track:SetAllPoints()
    self.footerDivider = content:CreateTexture(nil, "ARTWORK")
    self.footerDivider:SetTexCoord(FOOTER_DIVIDER[1], FOOTER_DIVIDER[2], FOOTER_DIVIDER[3], FOOTER_DIVIDER[4])
    self.controls = CreateFrame("Frame", nil, content)
    self.controls:SetHeight(CONTROL_HEIGHT)
    self.play = TextButton(self.controls, L.PAUSE, function()
        if SoundQueue:CanBePaused() then SoundQueue:TogglePauseQueue() end
    end)
    self.stop = TextButton(self.controls, L.MIN_STOP_ALL, function() SoundQueue:RemoveAllSoundsFromQueue() end)
    self.buttons = { self.play, self.stop }
    Actions:Build(frame)

    -- A slim scrollbar beside the captions, for a line longer than the page. The captions
    -- page themselves on the wheel; this shows where the reader is and lets them drag.
    self.scrollbar = CreateFrame("Slider", nil, content)
    self.scrollbar:SetOrientation("VERTICAL")
    self.scrollbar:SetWidth(SCROLLBAR)
    -- Drawn flat in the theme's colours: a faint track the whole page tall, and a thumb as
    -- long as the page's share of the line, so its length says how much there is to read.
    self.scrollbar.track = self.scrollbar:CreateTexture(nil, "BACKGROUND")
    self.scrollbar.track:SetPoint("TOPLEFT", 2, 0)
    self.scrollbar.track:SetPoint("BOTTOMRIGHT", -2, 0)
    self.scrollbar:SetThumbTexture([[Interface\Buttons\WHITE8x8]])
    local thumb = self.scrollbar:GetThumbTexture()
    if thumb then thumb:SetSize(SCROLLBAR - 2, 24) end
    self.scrollbar:SetMinMaxValues(1, 1)
    self.scrollbar:SetValueStep(0)
    self.scrollbar:SetScript("OnValueChanged", function(_, value, byUser)
        if byUser then Transcript:ScrollTo(value) end
    end)
    self.scrollbar:Hide()

    -- The handle under the foot: drag it to make the open panel taller or shorter. Held with
    -- Shift as the drag starts, it moves the width as well; without, the width stays put, so
    -- a drag meant for the height cannot knock the column out of DialogueUI's shape.
    self.resizer = CreateFrame("Button", nil, frame)
    self.resizer:SetSize(14, 14)
    self.resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    self.resizer:SetNormalTexture([[Interface\AddOns\Spoken\Textures\SizeGrabber-Up]])
    self.resizer:SetAlpha(.5)
    self.resizer:SetScript("OnEnter", function()
        self.resizer:SetAlpha(1)
        GameTooltip:SetOwner(self.resizer, "ANCHOR_LEFT")
        GameTooltip:SetText(L.DUI_RESIZE_TIP)
        GameTooltip:Show()
    end)
    self.resizer:SetScript("OnLeave", function() self.resizer:SetAlpha(.5); self:HideTooltip() end)
    self.resizer:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or Addon:IsFrameLocked() or not self.expanded then return end
        self.sizing = true
        self.sizingWidth = IsShiftKeyDown and IsShiftKeyDown() and true or false
        self:Layout() -- the resize bounds for this drag: free width only with Shift
        frame:StartSizing(self.sizingWidth and "BOTTOMRIGHT" or "BOTTOM")
    end)
    self.resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if self.sizing then
            Addon:Layout().DialogueUIHeight = Round(frame:GetHeight())
            if self.sizingWidth then Addon:Layout().DialogueUIWidth = Round(frame:GetWidth()) end
        end
        self.sizing, self.sizingWidth = false, false
        self:Layout(); self:Update()
    end)
end

function Skin:StartDrag()
    if not Addon:IsFrameLocked() then self.frame:StartMoving() end
end

function Skin:StopDrag()
    self.frame:StopMovingOrSizing()
    if not Addon:IsFrameLocked() then Addon:SaveLayout("DialogueUI", self.frame) end
end

--- Size and dress the panel from DialogueUI's window and theme. Called on every refresh,
--- so a theme or size change in DialogueUI lands on the next one.
function Skin:Layout()
    local frame, cfg = self.frame, Panel()
    self.layingOut = true
    -- Laid out exactly as DialogueUI lays out its window: its size, its paddings, its text
    -- size and spacing. Panel size then scales the whole frame, text and all, so at 100%
    -- the two are the same size on screen and at 80% this is the same page, smaller.
    local scale = cfg.Scale or 0.65
    frame.spokenBaseScale = scale * Theme:FrameScale() / UIParent:GetEffectiveScale()
    local duiWidth, duiHeight = Theme:FrameSize()
    -- The multiplier DialogueUI drew its window at, so the paddings keep its proportions.
    local multiplier = duiHeight / (HEIGHT_SHARE * math.max(1, UIParent:GetHeight()))
    local padH, padTop, padBottom = PAD_H * multiplier, PAD_TOP * multiplier, PAD_BOTTOM * multiplier
    -- DialogueUI's width, or the one dragged with Shift held.
    local width = self.sizingWidth and Round(frame:GetWidth()) or Addon:Layout().DialogueUIWidth or Round(duiWidth)
    -- Narrow enough to sit beside the dialog, never so narrow the header strip cannot hold
    -- the face and a title.
    local minWidth, maxWidth = Round(duiWidth * MIN_WIDTH_SHARE), Round(duiWidth * MAX_WIDTH_SHARE)
    width = Clamp(width, minWidth, maxWidth)
    local inner = math.max(1, width - 2 * padH)
    -- DialogueUI's own column, which the header and footer are sized from: a wider or
    -- narrower panel stretches its strips sideways and keeps the face, the title and the
    -- strips' thickness as DialogueUI draws them.
    local baseInner = math.max(1, Round(duiWidth) - 2 * padH)
    -- DialogueUI's spacing: 0.35 of the text size under each line, four of those between
    -- paragraphs (here an empty line, which comes to about the same).
    local fonts = Theme:Fonts()
    local fontSize = fonts.paragraphSize
    -- The captions' size. Linked, it is DialogueUI's, scaled with the rest of the panel.
    -- Unlinked, Font size scale is its share of DialogueUI's on screen, so it is set here
    -- against the panel's scale, which the whole frame is drawn at.
    local captionSize = fontSize
    if cfg.LinkFontScale == false then
        captionSize = math.max(6, Round(fontSize * (cfg.FontScale or scale) / scale))
    end
    local lineGap = Round(0.35 * captionSize)
    local lineHeight = captionSize + lineGap
    self.fonts, self.captionSize, self.lineGap = fonts, captionSize, lineGap

    -- The header strip across the panel's width, at DialogueUI's thickness, and DialogueUI's
    -- placements on it: the face centred in the socket at its left end, the title past it.
    local ratio = baseInner / HEADER_DIVIDER[5]
    local stripHeight = Round(HEADER_DIVIDER[6] * ratio)
    local face = Round(34 * ratio)
    local headerHeight = stripHeight + Round(4 * 0.35 * fontSize)
    local footerStrip = Round(FOOTER_DIVIDER[6] * baseInner / FOOTER_DIVIDER[5])
    local footerHeight = CONTROL_HEIGHT + footerStrip + BAR_HEIGHT + 6
    local waiting = Waiting()
    local shownRows = math.min(MAX_ROWS, waiting)
    local queueHeight = shownRows * ROW_HEIGHT + (waiting > MAX_ROWS and 14 or 0)
    -- The captions take what the panel leaves, within the captions' page sizes. A panel too
    -- small for the smallest page grows to fit it: the controls are never cut off.
    -- The share of DialogueUI's window, or the height the handle was dragged to.
    local height = self.sizing and Round(frame:GetHeight()) or Addon:Layout().DialogueUIHeight or Round(duiHeight)
    local body = height - padTop - headerHeight - queueHeight - padBottom - footerHeight
    local lines = math.max(MIN_LINES, math.floor(body / lineHeight))
    -- Folded, the panel is only as tall as the smallest page needs.
    if not self.expanded then lines, height = MIN_LINES, 0 end
    local captionHeight = lines * lineHeight
    height = math.max(height, padTop + headerHeight + captionHeight + queueHeight + padBottom + footerHeight)
    frame:SetSize(width, height)
    local minHeight = padTop + headerHeight + MIN_LINES * lineHeight + queueHeight + padBottom + footerHeight
    if frame.SetResizeBounds then
        if self.sizingWidth then
            frame:SetResizeBounds(minWidth, minHeight, maxWidth, 4000)
        else
            frame:SetResizeBounds(width, minHeight, width, 4000)
        end
    end
    self.resizer:SetShown(self.expanded and not Addon:IsFrameLocked())
    self.lines = lines

    local capWidth, capHeight = Theme:ParchmentSize()
    for index = 1, 3 do self.parchments[index]:SetTexture(Theme:TexturePath() .. "Parchment.png") end
    -- The paper follows the panel's width, keeping DialogueUI's overhang either side.
    local paperWidth = capWidth * width / math.max(1, Round(duiWidth))
    self.parchments[1]:SetSize(paperWidth, capHeight)
    self.parchments[3]:SetSize(paperWidth, capHeight)

    local content = self.content
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", padH, -padTop)
    content:SetPoint("BOTTOMRIGHT", -padH, padBottom)
    local socket = Round(SOCKET_WIDTH * ratio)
    self.headerSocket:ClearAllPoints()
    self.headerSocket:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.headerSocket:SetSize(socket, stripHeight)
    self.headerSocket:SetTexture(Theme:TexturePath() .. "Parchment.png")
    self.headerDivider:ClearAllPoints()
    self.headerDivider:SetPoint("TOPLEFT", self.headerSocket, "TOPRIGHT", 0, 0)
    self.headerDivider:SetSize(math.max(1, inner - socket), stripHeight)
    self.headerDivider:SetTexture(Theme:TexturePath() .. "Parchment.png")
    self.portrait:SetSize(face, face)
    self.portrait:ClearAllPoints()
    self.portrait:SetPoint("CENTER", self.headerSocket, "TOPLEFT", Round(23 * ratio), -Round(23 * ratio))
    -- DialogueUI's header: the quest title on the strip, past the socket, and the small
    -- line above it -- here the speaker's name.
    self.title:ClearAllPoints()
    self.title:SetPoint("LEFT", self.headerSocket, "LEFT", Round(53 * ratio), Round(2 * ratio))
    self.title:SetPoint("RIGHT", content, "RIGHT", -(2 * CORNER_ICON), 0)
    self.title:SetHeight(Round(fonts.titleSize * TITLE_SHARE) + 4)
    self.name:ClearAllPoints()
    self.name:SetPoint("BOTTOMLEFT", self.title, "TOPLEFT", 0, 2)
    self.name:SetPoint("RIGHT", content, "RIGHT", -(2 * CORNER_ICON), 0)
    self.name:SetHeight(fonts.subtitleSize + 2)
    local glyph = [[Interface\Buttons\UI-]] .. (self.expanded and "Minus" or "Plus")
    self.fold:SetNormalTexture(glyph .. "Button-Up")
    self.fold:SetPushedTexture(glyph .. "Button-Down")

    -- The text takes DialogueUI's full column; the scrollbar sits in the margin beside it.
    Transcript:Dock(frame, content, "TOPLEFT", 0, -headerHeight, inner, captionHeight)
    self.scrollbar:ClearAllPoints()
    self.scrollbar:SetPoint("TOPLEFT", content, "TOPRIGHT", 4, -headerHeight)
    self.scrollbar:SetHeight(captionHeight)

    self.drawer:ClearAllPoints()
    self.drawer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(headerHeight + captionHeight))
    self.drawer:SetSize(inner, math.max(1, queueHeight))

    self.controls:ClearAllPoints()
    self.controls:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    self.controls:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    self.footerDivider:ClearAllPoints()
    self.footerDivider:SetPoint("BOTTOM", self.controls, "TOP", 0, 0)
    self.footerDivider:SetSize(inner, footerStrip)
    self.footerDivider:SetTexture(Theme:TexturePath() .. "Parchment.png")
    self.bar:ClearAllPoints()
    self.bar:SetPoint("BOTTOMLEFT", self.footerDivider, "TOPLEFT", 0, 2)
    self.bar:SetPoint("BOTTOMRIGHT", self.footerDivider, "TOPRIGHT", 0, 2)

    self:Dress()
    self.layingOut = false
end

--- The theme's colours on everything that has one.
function Skin:Dress()
    local colors = Theme:Colors()
    local fonts = self.fonts or Theme:Fonts()
    local body = fonts.paragraphSize
    local function Paint(text, face, size, color)
        text:SetFont(face, size, "")
        text:SetShadowColor(0, 0, 0, 0)
        text:SetTextColor(color[1], color[2], color[3])
    end
    Paint(self.name, fonts.subtitle, fonts.subtitleSize, colors.title)
    Paint(self.title.text, fonts.title, Round(fonts.titleSize * TITLE_SHARE), colors.title)
    self.title.color = colors.title
    Paint(self.queueNote, fonts.paragraph, math.max(8, body - 2), colors.disabled)
    for _, row in ipairs(self.rows) do
        Paint(row.text, fonts.paragraph, math.max(8, body - 1), colors.gossip)
        row.color = colors.gossip
    end
    for _, button in ipairs(self.buttons) do Paint(button.text, fonts.paragraph, body, colors.paragraph) end
    self.colors = colors
    local tint = colors.portraitTint
    if self.viewport.texture then self.viewport.texture:SetVertexColor(tint[1], tint[2], tint[3]) end
    local track = colors.disabled
    self.track:SetColorTexture(track[1], track[2], track[3], .25)
    self.scrollbar.track:SetColorTexture(track[1], track[2], track[3], .2)
    local thumb = self.scrollbar:GetThumbTexture()
    if thumb then thumb:SetVertexColor(track[1], track[2], track[3], .75) end
    local captionSize = self.captionSize or body
    Transcript:SetStyle({ font = fonts.paragraph, size = captionSize, lineGap = self.lineGap or Round(0.35 * captionSize),
        paragraphs = true, color = colors.paragraph, shadow = false,
        highlight = colors.highlight, lines = self.lines })
end

function Skin:ConfigurePortrait()
    if Config().HidePortrait then self.portrait:Hide(); return end
    self.portrait:Show()
    if not StaticPortrait:Configure(self.viewport, self.clip) then Portrait:Configure(self.viewport, self.clip) end
    local viewport = self.viewport
    if viewport.active == "texture" and viewport.texture then StaticPortrait:Mask(viewport, viewport.texture) end
    local tint = self.colors and self.colors.portraitTint
    if tint and viewport.texture then viewport.texture:SetVertexColor(tint[1], tint[2], tint[3]) end
end

function Skin:ConfigureActions()
    Actions:Configure(self.frame, self.clip)
    local corner, x = nil, 0
    local right = self.controls:GetWidth()
    for _, button in ipairs(self.frame.actions.buttons) do
        local action = button.action
        if action.anchor == "header" then
            button:Hide()
        elseif action.anchor == "topright" and button.showsIcon and not corner then
            -- The Report icon: faint at the right end of the controls row, since a bug is
            -- the rare case and the corner belongs to Close; as big as Close, as smaller it
            -- was hard to see on the parchment. It brightens under the mouse; hooked once,
            -- as its own scripts carry the tooltip.
            corner = button
            button:SetParent(self.controls)
            button:SetFrameLevel(self.controls:GetFrameLevel() + 1)
            button:SetSize(CORNER_ICON, CORNER_ICON)
            button:ClearAllPoints()
            button:SetPoint("RIGHT", self.controls, "RIGHT", 0, 0)
            button:SetAlpha(.4)
            if not button.spokenDimmed then
                button.spokenDimmed = true
                button:HookScript("OnEnter", function(b) b:SetAlpha(1) end)
                button:HookScript("OnLeave", function(b) b:SetAlpha(.4) end)
            end
            x = CORNER_ICON + 6
        else
            -- The rest line up from the right of the controls row, after Stop.
            button:SetParent(self.controls)
            button:SetFrameLevel(self.controls:GetFrameLevel() + 1)
            button:ClearAllPoints()
            button:SetPoint("RIGHT", self.controls, "RIGHT", -x, 0)
            x = x + button:GetWidth() + 6
        end
    end
    self.actionsWidth = x
end

--- The wheel with Ctrl held: Panel size a step up or down, or with Shift too, Font size
--- scale, which unlinks the text from the panel. The panel keeps its top left corner where
--- it was, rather than sliding as its scale changes. True when the wheel was taken.
function Skin:Wheel(delta)
    if delta == 0 or not (IsControlKeyDown and IsControlKeyDown()) then return false end
    local cfg = Panel()
    local step = delta > 0 and self.SIZE_STEP or -self.SIZE_STEP
    local function Snap(value, range)
        return Clamp(math.floor(value / self.SIZE_STEP + 0.5) * self.SIZE_STEP, range[1], range[2])
    end
    local label, value
    if IsShiftKeyDown and IsShiftKeyDown() then
        if cfg.LinkFontScale ~= false then cfg.FontScale, cfg.LinkFontScale = cfg.Scale or 0.65, false end
        cfg.FontScale = Snap(cfg.FontScale + step, self.FONT_SIZES)
        label, value = L.OPT_DUI_FONT_SCALE, cfg.FontScale
    else
        cfg.Scale = Snap((cfg.Scale or 0.65) + step, self.PANEL_SIZES)
        label, value = L.OPT_DUI_SCALE, cfg.Scale
    end
    local frame = self.frame
    local left, top, before = frame:GetLeft(), frame:GetTop(), frame:GetEffectiveScale()
    PlayerFrame:RefreshConfig()
    if left and top and not Addon:IsFrameLocked() then
        local after = frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * before / after, top * before / after)
        Addon:SaveLayout("DialogueUI", frame)
    end
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
    GameTooltip:SetText(format("%s: %d%%", label, Round(value * 100)))
    GameTooltip:Show()
    return true
end

--- Fold the panel to two caption lines, or open it to its share of DialogueUI's window.
--- For the session: the Opening setting is what it opens as.
function Skin:SetExpanded(expanded)
    expanded = expanded and true or false
    if self.expanded == expanded then return end
    self.expanded = expanded
    if self.frame then self:Layout(); self:Update() end
end

function Skin:LayoutControls()
    local x = 0
    for _, button in ipairs(self.buttons) do
        button:ClearAllPoints()
        button:SetPoint("LEFT", self.controls, "LEFT", x, 0)
        button:SetWidth(button.text:GetStringWidth() + 12)
        x = x + button:GetWidth() + 4
    end
end

function Skin:UpdateControls()
    if not self.clip then return end
    local paused, playing = SoundQueue:IsPaused(), SoundQueue:IsPlaying()
    self.play.text:SetText(paused and L.PLAY or L.PAUSE)
    -- The glyph on the face: pause's left half of the atlas row, play's right.
    local left = paused and 0 or 93
    self.pause:GetNormalTexture():SetTexCoord(left / 512, (left + 93) / 512, 419 / 512, 1)
    self.pause:GetNormalTexture():SetAlpha((paused or MouseIsOver(self.pause)) and .9 or 0)
    self.pause.wash:SetShown(paused and not playing)
    local colors = self.colors
    if colors then
        local bar = paused and colors.disabled or colors.gossip
        self.bar:SetStatusBarColor(bar[1], bar[2], bar[3])
    end
    local held = not paused and not playing and SoundQueue:GetHeldReason(self.clip)
    self.title.text:SetText(held and format("%s (%s)", Label(self.clip), held) or Label(self.clip))
    for _, button in ipairs(self.buttons) do
        local color = SoundQueue:CanBePaused() and colors and colors.paragraph or colors and colors.disabled
        if color then button.text:SetTextColor(color[1], color[2], color[3]) end
        if SoundQueue:CanBePaused() then button:Enable() else button:Disable() end
    end
    self:LayoutControls()
end

function Skin:UpdateProgress()
    local clip = self.clip
    if not clip then return end
    local duration = tonumber(clip.length) or 0
    if clip.nextSoundTimer and duration > 0 then
        -- The queue's timer includes the source's trailing gap and any initial silence,
        -- so TimeLeft is right through hidden UI and replays alike.
        local remaining = Addon:TimeLeft(clip.nextSoundTimer)
        self.seconds = Clamp(duration + (clip.source.interClipGap or 0) - remaining, 0, duration)
    elseif not SoundQueue:IsPaused() then self.seconds = 0 end
    self.bar:SetValue(duration > 0 and (self.seconds or 0) / duration or 0)
end

function Skin:CreateQueueRow(index)
    local button = CreateFrame("Button", nil, self.drawer)
    self.rows[index] = button
    button:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    button:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    button:SetHeight(ROW_HEIGHT)
    local color = self.colors and self.colors.gossip or { 1, 1, 1 }
    Removable(button, 11, color[1], color[2], color[3])
    local fonts = self.fonts or Theme:Fonts()
    button.text:SetFont(fonts.paragraph, math.max(8, fonts.paragraphSize - 1), "")
    button.text:SetShadowColor(0, 0, 0, 0)
    button:SetScript("OnEnter", function()
        ShowRemove(button, true)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(Label(button.clip))
        GameTooltip:AddLine(L.QUEUE_REMOVE_TOOLTIP, 1, .82, 0, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() ShowRemove(button, false); self:HideTooltip() end)
    button:SetScript("OnClick", function()
        if self:HasClip() then SoundQueue:RemoveSoundFromQueue(button.clip) end
    end)
    return button
end

function Skin:LayoutQueue()
    local waiting = Waiting()
    self.offset = Clamp(self.offset, 0, math.max(0, waiting - MAX_ROWS))
    local shown = math.min(MAX_ROWS, waiting - self.offset)
    for index = 1, MAX_ROWS do
        local button = self.rows[index]
        if index <= shown then
            button = button or self:CreateQueueRow(index)
            button.clip = SoundQueue.sounds[index + self.offset + 1]
            local held = SoundQueue:GetHeldReason(button.clip)
            button.text:SetText(held and format("%s (%s)", Label(button.clip), held) or Label(button.clip))
            ShowRemove(button, false)
            button:Show()
        elseif button then button:Hide(); button.clip = nil end
    end
    self.queueNote:ClearAllPoints()
    self.queueNote:SetPoint("BOTTOMLEFT")
    self.queueNote:SetText(format(L.MIN_SCROLL_QUEUE, self.offset + 1, self.offset + shown, waiting))
    self.queueNote:SetShown(waiting > MAX_ROWS)
    self.drawer:SetShown(shown > 0)
end

function Skin:SetVisible(visible, immediate)
    if not self.frame then return end
    if not visible then self:HideTooltip() end
    if immediate then
        self.wanted = false
        self.frame:Hide()
        self.frame:SetAlpha(0)
        self.fadeTime = nil
        return
    end
    if self.wanted == visible then return end
    self.wanted = visible
    self.fadeFrom = self.frame:IsShown() and self.frame:GetAlpha() or 0
    self.fadeTime = 0
    if visible then self.frame:SetAlpha(self.fadeFrom); self.frame:Show() end
end

function Skin:Tick(elapsed)
    if self.fadeTime then
        self.fadeTime = self.fadeTime + elapsed
        local t = Clamp(self.fadeTime / (self.wanted and .18 or .24), 0, 1)
        local eased = 1 - (1 - t) * (1 - t)
        self.frame:SetAlpha(self.fadeFrom + ((self.wanted and 1 or 0) - self.fadeFrom) * eased)
        if t == 1 then
            self.fadeTime = nil
            if not self.wanted then self.frame:Hide(); return end
        end
    end
    if not self.wanted then return end
    if StaticPortrait:Resolved() then self:ConfigurePortrait() end
    self:UpdateProgress()
    self:UpdateScrollbar()
    self.poll = (self.poll or 0) + elapsed
    if self.poll >= .2 then
        self.poll = 0
        self:UpdateControls()
    end
end

function Skin:RefreshConfig(original)
    self:Initialize(original.frame)
    local frame = self.frame
    frame:SetFrameStrata(Config().FrameStrata)
    self:Layout()
    frame:SetScale(frame.spokenBaseScale)
    if Addon:IsFrameLocked() then frame:StopMovingOrSizing() end
    Addon:ApplyHost(frame)
    self:Update()
end

function Skin:Update()
    if not self.frame then return end
    if not self:IsEnabled() or Config().HideFrame then self:SetVisible(false, true); return end
    -- The line playing, or the sample a style tile previews (PlayerFrame:ShowSample).
    local clip = PlayerFrame:Current()
    if not clip then self:SetVisible(false); return end
    if clip ~= self.clip then
        self:HideTooltip()
        self.clip, self.seconds, self.offset = clip, 0, 0
    end
    -- The queue's length decides how much of the body the captions get.
    local waiting = Waiting()
    if waiting ~= self.laidOutFor then
        self.laidOutFor = waiting
        self:Layout()
    end
    self:SetVisible(true)
    self.name:SetText(clip.present and clip.present.header or "")
    self:ConfigurePortrait()
    self:ConfigureActions()
    self:LayoutQueue()
    self:UpdateProgress()
    self:UpdateControls()
end

--- Shown only when the line runs past the page; its range is the page count.
function Skin:UpdateScrollbar()
    -- By line, so the thumb rides the captions' glide rather than jumping a page at a time.
    local top, maxTop = Transcript:GetScroll()
    if maxTop <= 1 then self.scrollbar:Hide(); return end
    self.scrollbar:SetMinMaxValues(1, maxTop)
    local lines = (self.lines or 1)
    local thumb = self.scrollbar:GetThumbTexture()
    if thumb then
        thumb:SetHeight(math.max(24, (self.scrollbar:GetHeight() or 0) * lines / (lines + maxTop - 1)))
    end
    if math.abs((self.scrollbar:GetValue() or 1) - top) > 0.001 then self.scrollbar:SetValue(top) end
    self.scrollbar:Show()
end

function Skin:Reset()
    if not self.frame then return end
    self.frame:StopMovingOrSizing()
    Addon:Layout().DialogueUI = nil
    Addon:Layout().DialogueUIHeight = nil
    Addon:Layout().DialogueUIWidth = nil
    -- Folded or open as the Opening setting says, again.
    self.expanded = Panel().Expanded ~= false
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", -Round(UIParent:GetWidth() / 4), 0)
    self:RefreshConfig(PlayerFrame)
end

function Skin:Describe()
    if not self.frame then return "dialogueui skin: no frame built" end
    return format("dialogueui skin: enabled=%s visible=%s theme=%d size=%.0fx%.0f lines=%d portrait=%s",
        tostring(self:IsEnabled()), tostring(self.frame:IsVisible()), Theme:Available() and Theme:ThemeID() or 0,
        self.frame:GetWidth() or 0, self.frame:GetHeight() or 0, self.lines or 0, tostring(self.viewport.active))
end
