-- Offline integration checks: real Spoken queue, sources, callbacks, transcript,
-- layout and quest adapter, with a small WoW widget/timer host.
local clock, timers, nextTimer = 0, {}, 0
format, getn, strlower = string.format, table.getn, string.lower
strtrim = function(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
GetTime = function() return clock end
UnitName = function() return 'Test' end
GetRealmName = function() return 'Realm' end
SlashCmdList = {}
GameFontNormal = { GetFont = function() return 'font.ttf', 14 end }

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local addons = here .. "/../../addons/"
dofile(here .. '/fixture.lua')
local function Copy(v)
    if type(v)~='table' then return v end
    local t={}; for k,value in pairs(v) do t[k]=Copy(value) end; return t
end
local Timer = {}
function Timer:ScheduleTimer(fn, delay)
    nextTimer=nextTimer+1; timers[nextTimer]={fn=fn,at=clock+delay}; return nextTimer
end
function Timer:ScheduleRepeatingTimer(fn, delay)
    local id=self:ScheduleTimer(fn,delay); timers[id].interval=delay; return id
end
function Timer:CancelTimer(id) timers[id]=nil end
function Timer:TimeLeft(id) return timers[id] and timers[id].at-clock or 0 end
LibStub=function(name)
    if name=='AceTimer-3.0' then
        return { Embed=function(_,obj) for k,v in pairs(Timer) do obj[k]=v end; return obj end }
    end
    assert(name=='AceDB-3.0')
    return { New=function(_,_,defaults) local db=Copy(defaults); db.global={migratedFrom='test'}; return db end }
end

dofile(addons .. 'SpokenPlayer/Environment.lua')
local E=SpokenEnv
E.Version={IsLegacyVanilla=false,IsLegacyBurningCrusade=false,IsLegacyWrath=false,
    IsCamelot=true,IsAnyLegacy=false,IsRetailOrAboveLegacyVersion=function() return true end}
dofile(addons .. 'SpokenPlayer/Core.lua')
dofile(addons .. 'SpokenPlayer/Callbacks.lua')
dofile(addons .. 'SpokenPlayer/SoundQueue.lua')
dofile(addons .. 'SpokenPlayer/Sources.lua')
dofile(addons .. 'SpokenPlayer/Strings.lua')
dofile(addons .. 'SpokenPlayer/UI/Layout.lua')
dofile(addons .. 'SpokenPlayer/UI/Transcript.lua')
E.SoundUtils={WhyInaudible=function() end,IsMutedByPlayer=function() return false end,
    MuteChannel=function() end,TestSound=function() return true end,
    PlaySound=function(_,clip) if clip.path=='missing' then return false end; clip.handle=1; return true end,
    StopSound=function(_,clip) clip.handle=nil end}
E.StaticPortrait={Configure=function() return false end,Resolved=function() return false end}
E.Portrait={Configure=function(_,frame) frame.active='mock-model' end}
dofile(addons .. 'SpokenPlayer/UI/Actions.lua')
dofile(addons .. 'SpokenPlayer/UI/PlayerFrame.lua')
dofile(addons .. 'SpokenPlayer/UI/MinimalPlayer.lua')
E.Minimap={Setup=function() end}; E.Options={Setup=function() end}
E.Addon:Enable()
local T,Q,M=E.Transcript,E.SoundQueue,E.MinimalPlayer
local source=E.Sources:Register('quests',{interClipGap=.55})
local cfg=E.Addon.db.profile.Transcript

local assertions=0
local function Check(v,message) assertions=assertions+1; assert(v,message) end
local function Advance(seconds)
    local target=clock+seconds
    while true do
        local earliest,id
        for k,t in pairs(timers) do if t.at<=target and (not earliest or t.at<earliest) then earliest,id=t.at,k end end
        if not id then break end
        clock=earliest
        local t=timers[id]
        if t.interval then t.at=clock+t.interval else timers[id]=nil end
        t.fn()
    end
    clock=target
    T:Update()
    M:Tick(seconds)
end
local function Clip(key,text,length)
    return {key=key,path=key,length=length or 60,text=text,
        present={header='NPC '..key,label='Quest '..key}}
end
local function Plain(text) return text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','') end
local function Captions()
    local lines={}
    for _,label in ipairs(T.labels) do if label:IsShown() then lines[#lines+1]=label:GetText() end end
    return table.concat(lines,'\n'),#lines
end
local function HighlightCount()
    local text=Captions()
    local _,count=text:gsub('|cffffd100','')
    return count
end
local function CheckLayout()
    local _,count=Captions()
    Check(count<=(E.Addon:Layout().CaptionsExpanded and 8 or cfg.Lines),'only the requested number of lines is visible')
    for _,label in ipairs(T.labels) do
        if label:IsShown() then
            Check(not label.wordWrap and not label:GetText():find('\n'),'each caption label is exactly one non-wrapping line')
            Check(label:GetStringWidth()<=label:GetWidth(),'rendered text fits the available width')
        end
    end
end
local long=string.rep('A long line about the quest and the world. ',55)
local initialTop=M.frame:GetTop()
local a,b=Clip('a',long),Clip('b','Second quest text',20)
source:Enqueue(a); source:Enqueue(b)
Check(T.frame:IsShown(),'transcript appears for a narrated quest')
Check(T.frame:GetParent()==M.frame and T.frame:IsVisible(),'captions belong to the visible portrait player')
Check(math.abs(M.frame:GetTop()-initialTop)<.001,'adding captions preserves the portrait position')
Check(T.frame:GetTop()<M.bar:GetBottom(),'captions sit below the existing progress bar')
Check(T.frame:GetBottom()>M.panel:GetBottom(),'caption text fits inside the existing stone panel')
Check(T.frame:GetLeft()==M.content:GetLeft(),'captions align with the player name and title')
Check(not T.frame.backdrop and not T.speaker and not T.status,'captions have no independent window chrome')
Check(T.labels[1].textColor[1]==M.title.text.textColor[1] and T.labels[1].shadowOffset[1]==1,'captions use the player text palette and shadow')
Check(T.text==long:sub(1,-2),'first text is retained while another NPC is queued')
Check(M.name:GetText()=='NPC a','speaker belongs to the current clip')
Check(cfg.Lines==2 and T.frame:GetHeight()<160,'default panel is compact with two caption lines')
Check(T.activeWord==1 and HighlightCount()==2,'first two words are highlighted at the start')
CheckLayout()
Advance(30)
Check(T:GetProgress()==.5,'progress follows real queue timing')
Check(T.page>1 and T.activeWord>1 and HighlightCount()>=1,'captions follow the highlighted word through the recording')
CheckLayout()
T.frame:Fire('OnMouseWheel',1)
local manualPage=T.page
Advance(5)
Check(T.manualScroll and T.page==manualPage,'manual scrolling holds the chosen caption page')
T:Follow()
Check(not T.manualScroll and T.page>manualPage and HighlightCount()>=1,'Follow brings the active word back into view')
Q:PauseQueue()
local elapsed,pausedCaptions=T:GetElapsed(),Captions()
Advance(8)
Check(T:GetElapsed()==elapsed and Q:IsPaused(),'pause freezes time')
Check(Captions()==pausedCaptions,'pause freezes the word highlight and caption page')
Q:ResumeQueue()
Check(T:GetElapsed()==0 and T.page==1 and T.activeWord==1,'resume restarts captions with the actual restarted audio')
T:SetEnabled(false); Advance(10)
Check(not T.frame:IsShown() and Q:IsPlaying(a),'hiding captions leaves audio playing')
T:SetEnabled(true)
Check(T.frame:IsShown() and T:GetElapsed()==10 and HighlightCount()>=1,'reopening catches up to current narration')
Q:Skip()
Check(T.clip==b and Plain(Captions())=='Second quest text','skip switches to the next queued clip')
Check(T:GetElapsed()==0 and T.activeWord==1,'new clip begins at its first word')
Check(Captions()=='|cffffd100Second|r |cffffd100quest|r text','current and next word are highlighted together')
Advance(19)
Check(Captions()=='Second |cffffd100quest|r |cffffd100text|r','the last visible word keeps its previous neighbor highlighted')
Advance(1.25)
Check(T.frame:IsShown() and HighlightCount()==0,'highlight ends during the inter-clip gap')
Advance(1)
Check(Q:IsEmpty() and not T.frame:IsShown(),'normal completion hides captions')
Check(Captions()=='' and T.activeWord==nil,'queue exhaustion clears stale dialogue and highlighting')

-- Chinese has no spaces: each character is a word, punctuation stays with
-- the character before it and adds a pause, and no spaces are inserted.
local chinese=Clip('zh','你好，「勇士」。去吧Go!',10)
source:Enqueue(chinese)
Check(Captions()=='|cffffd100你|r|cffffd100好，|r「勇士」。去吧Go!','Chinese highlights one character at a time, without spaces')
local texts={}
for i,w in ipairs(T.words) do texts[i]=w.text end
Check(table.concat(texts,'|')=='你|好，|「勇|士」。|去|吧|Go!','Chinese splits into characters with attached punctuation')
Check(T.words[2].finish-T.words[2].start>T.words[1].finish-T.words[1].start
    and T.words[4].finish-T.words[4].start>T.words[2].finish-T.words[2].start,'。 pauses longer than ， and ， longer than none')
Advance(5)
Check(HighlightCount()==2 and Plain(Captions())=='你好，「勇士」。去吧Go!','highlight moves through Chinese text')
Q:RemoveAllSoundsFromQueue()

source:Enqueue(Clip('c',long,30)); Advance(12)
source:Enqueue(Clip('no-text',nil,5)); Q:Skip()
Check(not T.frame:IsShown() and Captions()=='','a clip without text never shows previous captions')
Q:RemoveAllSoundsFromQueue()
Check(not T.frame:IsShown(),'Stop clears captions')
source:Enqueue(Clip('d',long,60)); Advance(30)
local oldPages,word=T:PageCount(),T.activeWord
M.frame:SetWidth(700)
Check(T:PageCount()<oldPages,'widening the panel fits more words on each page')
Check(T.activeWord==word and HighlightCount()>=1,'resize keeps the current word visible')
cfg.FontSize=24; T:RefreshConfig()
Check(T.labels[1].fontSize==24 and T.labels[2].fontSize==24,'font-size setting applies to both lines')
Check(T.activeWord==word and HighlightCount()>=1,'font changes preserve the active word')
CheckLayout()
local twoLineHeight=T.frame:GetHeight()
SlashCmdList.SPOKEN('transcript 1')
Check(cfg.Lines==1 and select(2,Captions())==1,'one-line command shows just one caption line')
Check(T.frame:GetHeight()<twoLineHeight,'one-line mode shrinks the panel')
Check(T.activeWord==word and HighlightCount()>=1,'one-line mode still shows the active word')
CheckLayout()
SlashCmdList.SPOKEN('transcript 2')
Check(cfg.Lines==2 and T.frame:GetHeight()==twoLineHeight,'two-line command restores compact pair of lines')
Check(M.frame.bounds[2]==M.frame.bounds[4],'vertical resize is locked to the number of lines')
local compactTop, compactWord, compactElapsed = M.frame:GetTop(), T.activeWord, T:GetElapsed()
T.expand:Fire('OnClick')
Check(E.Addon:Layout().CaptionsExpanded and select(2,Captions())==8,'the plus button opens eight caption lines')
Check(T.frame:GetHeight()==twoLineHeight*4,'expanded captions grow inside the player')
Check(math.abs(M.frame:GetTop()-compactTop)<.001,'expanding leaves the portrait in place')
Check(T.activeWord==compactWord and T:GetElapsed()==compactElapsed,'expanding does not restart playback or its highlight')
Check(T.expand:GetLeft()>T.labels[1]:GetRight(),'the caption button has space beside the text')
CheckLayout()
T:TurnPage(1)
local firstVisible=(T.page-1)*8+1
T.expand:Fire('OnClick')
Check(not E.Addon:Layout().CaptionsExpanded and cfg.Lines==2 and T.frame:GetHeight()==twoLineHeight,'minus restores the compact preference')
Check(T.manualScroll and T.page==math.floor((firstVisible-1)/2)+1,'collapsing keeps the manually selected passage visible')
T:Follow()
cfg.HighlightWord=false; T:RefreshConfig()
Check(HighlightCount()==0 and T.activeWord==word,'highlight can be disabled while captions keep following')
cfg.HighlightWord=true; cfg.AutoScroll=false; T:RefreshConfig()
local heldPage=T.page
Advance(3)
Check(T.page==heldPage,'disabling Follow keeps the chosen caption page')
T:Follow()
Check(T.page>heldPage and HighlightCount()>=1,'Follow re-enables automatic page changes')
Q:RemoveAllSoundsFromQueue()

local held=true
source:AddGate(function() if held then return 'combat' end end)
source:Enqueue(Clip('held','Waiting for combat',8))
Advance(3)
Check(T:GetElapsed()==0 and not Q:IsPlaying(),'gated clips do not accrue speech time')
Check(HighlightCount()==0 and T.activeWord==nil,'waiting clips do not claim a word is being spoken')
held=false; Advance(1)
Check(Q:IsPlaying() and T:GetElapsed()==0 and T.activeWord==1,'gated clip begins highlighting only when audio starts')
Q:RemoveAllSoundsFromQueue()
local failed=Clip('failed','Not playable',10); failed.path='missing'
source:Enqueue(failed)
Check(not T.frame:IsShown(),'rejected audio leaves no stale captions')
local delayed=Clip('delayed',long,10); delayed.delay=2
source:Enqueue(delayed); Advance(1)
Check(T:GetProgress()==0 and HighlightCount()==0,'initial silence is excluded from highlighting')
Q:PauseQueue(); Advance(2)
Check(HighlightCount()==0,'pausing during initial silence does not highlight a word')
Q:ResumeQueue(); Advance(2)
Check(T.activeWord==1 and HighlightCount()>=1,'first word appears when initial silence ends')
Advance(5)
Check(T:GetProgress()==.5 and HighlightCount()>=1,'duration starts after the delay')
SlashCmdList.SPOKEN('transcript off')
Check(not cfg.Enabled,'slash command disables captions')
SlashCmdList.SPOKEN('transcript on')
Check(cfg.Enabled,'slash command enables captions')
SlashCmdList.SPOKEN('stop')
Check(not T.frame:IsShown(),'slash stop clears display')
Check(T:CleanText('|cffff0000Hello|r |Hitem:1|h[sword]|h|n|Ticon:16|tWorld')=='Hello [sword]\nWorld','markup is normalized without losing visible text')
Check(T:CleanText('Привет 世界')=='Привет 世界','UTF-8 text remains intact')

-- Exercise the actual player layouts: docking, queue expansion, scale, visibility,
-- original-skin fallback and controls. All coordinates are in player UI units.
source:Enqueue(Clip('docking',long,120))
local frameCfg=E.Addon.db.profile.Frame
T:Reset()
local playerTop=M.frame:GetTop()
local extra={}
for i=1,6 do extra[i]=Clip('extra'..i,'Later dialogue',10); source:Enqueue(extra[i]) end
M:ToggleQueue()
Check(M.drawer:IsShown() and M.queueNote:IsShown(),'expanded queue still displays rows and its paging note')
Check(M.drawer:GetTop()<T.frame:GetBottom(),'downward queue drawer cannot overlap captions')
T.expand:Fire('OnClick')
Check(M.drawer:GetTop()<T.frame:GetBottom() or M.drawer:GetBottom()>T.frame:GetTop(),
    'the open queue stays clear of expanded captions, including when it flips upward')
Check(T.frame:GetBottom()>M.panel:GetBottom(),'the panel encloses expanded captions and queue')
T.expand:Fire('OnClick')
Check(M.panel:GetBottom()<M.drawer:GetBottom(),'the shared background encloses the expanded queue')
Check(math.abs(M.frame:GetTop()-playerTop)<.001,'opening the queue leaves the unit icon in place')
local anchor={M.frame:GetPoint(1)}
M.frame:ClearAllPoints(); M.frame:SetPoint('BOTTOM',UIParent,'BOTTOM',0,20)
M:LayoutQueue()
Check(M.drawer:GetBottom()>M.header:GetTop(),'near the bottom of the screen the queue opens above the speaker name')
Check(T.frame:GetTop()<M.bar:GetBottom(),'queue opening upwards leaves captions beneath the progress bar')
M.frame:ClearAllPoints(); M.frame:SetPoint(unpack(anchor))
for _,clip in ipairs(extra) do source:Remove(clip) end
M:ToggleQueue()
frameCfg.HidePortrait=true; E.PlayerFrame:RefreshConfig()
Check(not M.portrait:IsShown() and math.abs(T.frame:GetLeft()-M.content:GetLeft())<.001,'hide-portrait mode keeps captions aligned')
frameCfg.HidePortrait=false; frameCfg.FrameScale=1.1; E.PlayerFrame:RefreshConfig()
Check(T.frame:GetEffectiveScale()==M.frame:GetEffectiveScale(),'captions inherit the player scale')
Check(M.portrait:IsShown() and T.frame:GetLeft()>M.portrait:GetLeft(),'restored portrait remains beside the caption text')
frameCfg.HideFrame=true; E.PlayerFrame:RefreshConfig()
Check(not T.frame:IsVisible() and Q:IsPlaying(),'hiding the player hides its captions while audio continues')
frameCfg.HideFrame=false; E.PlayerFrame:RefreshConfig()
Check(T.frame:IsVisible(),'showing the player restores its attached captions')
local movedTop=M.frame:GetTop()
T:SetEnabled(false)
Check(M.frame:GetHeight()==98 and M.frame:IsShown(),'disabling captions restores the original compact player height')
Check(math.abs(M.frame:GetTop()-movedTop)<.001,'removing captions keeps the portrait in place')
T:SetEnabled(true)
Check(math.abs(M.frame:GetTop()-movedTop)<.001,'restoring captions keeps the portrait in place')
T:TurnPage(-1); T.frame:Fire('OnClick','LeftButton')
Check(not T.manualScroll,'clicking the caption text resumes following')
T.frame:Fire('OnClick','RightButton')
Check(M.menu:IsShown(),'right-clicking captions opens the existing player menu')
M.menu:Hide()
frameCfg.LockFrame=true; E.PlayerFrame:RefreshConfig(); M:StartDrag()
Check(not M.frame.moving and not M.resizer:IsShown(),'the player lock controls the attached caption layout')
frameCfg.LockFrame=false; E.PlayerFrame:RefreshConfig(); M.header:Fire('OnDragStart')
Check(M.frame.moving,'the existing header still moves the whole player')
M.header:Fire('OnDragStop')
frameCfg.MinimalPlayer=false; E.PlayerFrame:RefreshConfig()
local original=E.PlayerFrame.frame
Check(T.frame:GetParent()==original and original:IsShown() and not M.frame:IsShown(),'switching skins attaches captions to the original player')
Check(T.frame:GetTop()<original.portrait:GetBottom(),'original-skin captions stay below portrait and action controls')
Check(T.frame:GetBottom()>original.background:GetBottom(),'original background extends behind the captions')
local originalTop=original:GetTop()
T.expand:Fire('OnClick')
Check(select(2,Captions())==8 and T.frame:GetBottom()>original.background:GetBottom(),'the floating-head layout encloses expanded captions')
Check(math.abs(original:GetTop()-originalTop)<.001,'expanding preserves the floating head position')
T.expand:Fire('OnClick')
local previousWidth=T.frame:GetWidth()
original:SetWidth(620)
Check(T.frame:GetWidth()>previousWidth,'resizing the original player reflows the attached text')
CheckLayout()
frameCfg.MinimalPlayer=true; frameCfg.FrameScale=.7; E.PlayerFrame:RefreshConfig()
Check(T.frame:GetParent()==M.frame and not original:IsShown(),'switching back restores attachment to the portrait player')
for _,point in ipairs({'TOPLEFT','CENTER','BOTTOM'}) do
    M.frame:ClearAllPoints(); M.frame:SetPoint(point,UIParent,point,0,200)
    local top=M.frame:GetTop()
    cfg.Lines=1; T:RefreshConfig()
    Check(math.abs(M.frame:GetTop()-top)<.001,'one-line mode preserves '..point..' portrait position')
    cfg.Lines=2; T:RefreshConfig()
    Check(math.abs(M.frame:GetTop()-top)<.001,'two-line mode preserves '..point..' portrait position')
    T:ToggleExpanded()
    Check(math.abs(M.frame:GetTop()-top)<.001,'expanded mode preserves '..point..' portrait position')
    T:ToggleExpanded()
end
Q:RemoveAllSoundsFromQueue()

-- Compare every displayed page to the original text; resizing must neither lose
-- nor duplicate characters, including long names and text without spaces.
local multilingual='Welcome, Windbeard!\nПривет путник. '..string.rep('世界',60)..' '..string.rep('W',90)..' The end.'
source:Enqueue(Clip('unicode',multilingual,120))
for _,size in ipairs({12,26}) do
    for _,width in ipairs({300,900}) do
        for _,count in ipairs({1,2,8}) do
            cfg.FontSize,cfg.Lines,E.Addon:Layout().CaptionsExpanded=size,count==1 and 1 or 2,count==8
            M.frame:SetWidth(width); T:RefreshConfig()
            T.manualScroll,T.page=true,1
            local displayed={}
            for page=1,T:PageCount() do
                T.page=page; T:Update()
                CheckLayout()
                displayed[#displayed+1]=Plain(Captions())
            end
            local joined=table.concat(displayed):gsub('%s','')
            Check(joined==multilingual:gsub('%s',''),'every source character survives wrapping and paging')
        end
    end
end
-- Sample playback through split UTF-8 words and page boundaries in one-line mode.
E.Addon:Layout().CaptionsExpanded=false; cfg.Lines=1; T:RefreshConfig()
T:Follow()
for sample=1,100 do
    Advance(1)
    Check(HighlightCount()>=1,'the current word remains highlighted throughout speech')
    CheckLayout()
end
Q:RemoveAllSoundsFromQueue()
local unknown=Clip('unknown','Words without a usable duration',0)
source:Enqueue(unknown)
Check(T.frame:IsShown() and HighlightCount()==0,'unusable timing shows text without a fabricated highlight')
Q:RemoveAllSoundsFromQueue()
local override=Clip('override','Fallback text',10); override.present.transcript='Display this instead'
source:Enqueue(override)
Check(T.text=='Display this instead','explicit source transcript takes precedence')
Q:RemoveAllSoundsFromQueue()
Check(#E.Callbacks.errors==0,table.concat(E.Callbacks.errors,'\n'))

-- Exercise the actual quest adapter and log-text helper, including reward text.
dofile(addons .. 'SpokenQuests/Environment.lua')
-- Player.lua names its report action at load time, so it needs the string table.
dofile(addons .. 'SpokenQuests/Strings.lua')
VoiceOver.Version=E.Version
dofile(addons .. 'SpokenQuests/Enums.lua')
dofile(addons .. 'SpokenQuests/Contribute.lua')
dofile(addons .. 'SpokenQuests/Player.lua')
local V=VoiceOver
C_QuestLog={GetLogIndexForQuestID=function(id) return id==33 and 7 or nil end}
GetQuestLogQuestText=function(index) assert(index==7); return 'Log description', 'Objectives' end
local logClip={event=V.Enums.SoundEvent.QuestAccept,questID=33,name='NPC',fileName='33-accept',filePath='voice.ogg'}
V.Player:Prepare(logClip)
Check(logClip.text=='Log description','quest-log replay captures the correct entry description')
local reward={event=V.Enums.SoundEvent.QuestComplete,questID=33,fileName='33-complete',filePath='voice.ogg'}
V.Player:Prepare(reward)
Check(reward.text==nil,'acceptance text is never substituted for a reward speech')
local snap={event=V.Enums.SoundEvent.QuestAccept,questID=33,text='Text from NPC',fileName='accept'}
V.Player:Prepare(snap)
Check(snap.text=='Text from NPC','captured NPC text is preserved')
GetQuestLogQuestText=function() error('client API unavailable') end
local unavailable={event=V.Enums.SoundEvent.QuestAccept,questID=33,fileName='accept'}
Check(pcall(V.Player.Prepare,V.Player,unavailable),'missing log APIs do not break playback')
print(string.format('PASS: %d checks using the real queue, both player layouts, captions, commands and quest adapter.',assertions))
