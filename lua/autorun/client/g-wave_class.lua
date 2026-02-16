--- G-WAVE Handle class
GWave = GWave or {}

hook.Add( "Think", "GWave_Radio_Think", function()
    for i = #GWAVE.Radios, 1, -1 do
        local radio = GWAVE.Radios[i]
        if radio:IsMarkedForRemoval() or not IsValid( radio._parent ) then
            radio:Clear()
            table.remove( GWAVE.Radios, i )
            continue
        end
        radio:_think()
    end
end )

--- G-WAVE Handle meta-table
GWave.__index = GWave
function GWave.new()
    local self = setmetatable({}, GWave)

    self._parent = nil -- The entity it's parented to

    self._volume = 1
    self._pitch = 1
    self._radius = 1000

    self._queue = {} -- Queue for multiple urls
    self._queueChanged = false
    self._current = nil -- The url of the currently playing audio
    self._state = "stopped"
    self._soundObject = nil
    self._markedForRemoval = false
    self._currentBassVolume = 0

    GWAVE.Radios[#GWAVE.Radios + 1] = self

    GWAVE.Print( string.format( "Radio Object [%i]", #GWAVE.Radios ) )

    return self
end

--- Adds a url to the queue
function GWave:Add( url )
    -- check if the url actually leads to a valid audio file
    sound.PlayURL( url, "noplay 3d noblock", function( obj, errorID, errorName )
        if IsValid( obj ) then
            self._queue[#self._queue + 1] = url
            self:Play()
            self._queueChanged = true
            GWAVE.Print( "Added URL: " .. url )
            obj:Stop()
            obj = nil
        else
            local err = ""
            if errorName == "BASS_ERROR_ILLPARAM" then
                GWAVE.Print( "Invalid URL: " .. url )
            end
            
        end
    end )
end

--- Sets the parent entity
function GWave:SetParent( ent )
    self._parent = ent
end

--- Plays/Resumes the radio
function GWave:Play()
    if self._state ~= "playing" then
        if IsValid( self._soundObject ) then
            self._soundObject:Play()
            if self._state ~= "paused" then
                self._soundObject:SetTime( 0 )
            end
        end
        self._state = "playing"
    end
end

--- Rewinds the radio
function GWave:Rewind()
    if IsValid( self._soundObject ) then
        self._soundObject:SetTime( 0 )
    end
end

--- Moves to the next audio in the queue
function GWave:Next()
    if IsValid( self._soundObject ) then
        self._soundObject:Stop()
        self._soundObject = nil
    end

    self._current = nil

    if self._queue[1] and self._state ~= "playing" then
        self._current = table.remove( self._queue, 1 )
        
        GWAVE.Print( self._current )
        local radio = self
        sound.PlayURL( self._current, "noplay 3d noblock", function( obj, errorID, errorName )
            if IsValid( obj ) then
                self._queueChanged = true
                GWAVE.Print( "Now Playing: " .. radio._current )
                radio._soundObject = obj
                radio:Play()
                radio._soundObject:Set3DFadeDistance( 200, 200 )
            else
                GWAVE.Print( "Failed to play: " .. nextUrl )
                radio._current = nil
            end
        end )
    end
end

--- Pauses the radio
function GWave:Pause()
    if self._state ~= "paused" then
        self._state = "paused"
        if IsValid( self._soundObject ) then
            self._soundObject:Pause()
        end
    end
end

--- Stops the radio
function GWave:Stop()
    if self._state ~= "stopped" then
        self._state = "stopped"
        if IsValid( self._soundObject ) then
            self._soundObject:Stop()
            self._soundObject = nil
        end
        self._state = "stopped"
        self._current = nil
    end
end

--- Stops and clears the radio
function GWave:Clear()
    if self._state ~= "stopped" then
        self._state = "stopped"
        if IsValid( self._soundObject ) then
            self._soundObject:Stop()
            self._soundObject = nil
        end
        self._queue = {}
        self._queueChanged = true
    end
end

function GWave:Remove()
    self._markedForRemoval = true
    --self._htmlPanel:Remove()
end

function GWave:IsMarkedForRemoval()
    return self._markedForRemoval
end

--- Updates the radio
function GWave:_think()
    if self._state == "playing" and ( not self._soundObject or self._soundObject:GetState() == GMOD_CHANNEL_STOPPED ) then
        self._state = "next"
        if self._queue[1] then
            self:Next()
        else
            self:Stop()
        end
    end

    if IsValid( self._soundObject ) and self._state == "playing" then
        self._soundObject:SetPos( self._parent:GetPos() )
        local eyeOffset = self._parent:GetPos() - EyePos()
        local eyeDist2 = eyeOffset:LengthSqr()
        if eyeDist2 > self._radius^2 then
            self._soundObject:SetVolume( 0 )
        else
            local realVolume = 1 / ( 1 + eyeDist2 )
            realVolume = realVolume * self._radius^1.38
            realVolume = math.min( realVolume * self._volume, self._volume )

            local dot = eyeOffset:GetNormalized():Dot( EyeAngles():Forward() )
            realVolume = realVolume * math.max( 0.5, ( math.min( dot, 0 ) + 1 ) )

            self._soundObject:SetVolume( realVolume )
        end

        self._soundObject:SetPlaybackRate( self._pitch )

        -- Scale the radio by its loudness
        local scale = Vector( 1, 1, 1 )
        local fft = {}
        self._soundObject:FFT( fft, FFT_1024 )
        local samples = 2

        local maxVal = 0
        for i = 1, samples do
            if not fft[i] then continue end
            maxVal = math.max( maxVal, fft[i] ^ 2 )
        end


        self._currentBassVolume = self._currentBassVolume + ( maxVal - self._currentBassVolume ) * 0.1

        local squish = self._currentBassVolume * 8

        squish = math.min( squish, 0.5 )

        scale[1] = scale[1] + squish
        scale[2] = scale[2] - squish
        scale[3] = scale[3] + squish

        self._parent:ManipulateBoneScale( 0, scale )
    end
end

local playMat = Material( "vgui/Play.png" )
local pauseMat = Material( "vgui/Pause.png" )
local skipMat = Material( "vgui/Skip.png" )
local rewindMat = Material( "vgui/Rewind.png" )

--- Opens the radio's menu
function GWave:OpenRadioMenu()
    local radio = self

    local queueChanged = false

    local scrW, scrH = ScrW(), ScrH()
    local dframe = vgui.Create( "DFrame" )
    dframe:SetSize( scrW * 0.6, scrH * 0.6 )
    dframe:Center()
    dframe:SetTitle( "" )
    dframe:MakePopup()
    dframe:InvalidateParent( true )

    function dframe:Paint( w, h )
        draw.RoundedBox( 4, 0, 0, w, h, Color( 42, 38, 53 ) )
    end

    --- URL Bar
    local urlBarPanel = vgui.Create( "DPanel", dframe )
    urlBarPanel:Dock( TOP )
    urlBarPanel:SetTall( 24 )
    urlBarPanel:DockMargin( 0, 0, 28, 4 )

    local urlBar = vgui.Create( "DTextEntry", urlBarPanel )
    urlBar:Dock( FILL )
    urlBar:SetMultiline( false )
    urlBar:SetPlaceholderText( "Enter a URL" )
    urlBar:SetTextColor( color_white )
    urlBar:SetPaintBackground( false )

    function urlBarPanel:Paint( w, h )
        draw.RoundedBox( 4, 0, 0, w, h, Color( 21, 18, 27) )
    end

        --- Add Button
    local addButton = vgui.Create( "DButton", dframe )
    --addButton:DockMargin( 0, 4, dframe:GetWide() - 24, 0 )
    addButton:SetText( "" )
    addButton:SetIcon( "icon16/sound_add.png" )
    addButton:SetTall( 24 )
    addButton:SetWide( 24 )
    addButton:SetPos( dframe:GetWide() - 29, 29 )

    function addButton:Paint( w, h )
        draw.RoundedBox( 4, 0, 0, w, h, Color( 21, 18, 27) )
    end

    addButton.DoClick = function()
        self:Add( urlBar:GetValue() )
    end

    --- Queue list
    local queueH = dframe:GetTall() * 0.8
    local queueList = vgui.Create( "DScrollPanel", dframe )
    queueList:Dock( TOP )
    queueList:SetTall( queueH )
    queueList:InvalidateParent( true )
    queueList:SetDrawBackground( false )

    local sbar = queueList:GetVBar()
    function sbar:Paint(w, h)
        draw.RoundedBox( 4, 0, 0, w, h, Color(17, 19, 26) )
    end
    function sbar.btnUp:Paint(w, h)
        draw.RoundedBox( 4, 0, 0, w, h, Color(62, 73, 104) )
    end
    function sbar.btnDown:Paint(w, h)
        draw.RoundedBox( 4, 0, 0, w, h, Color(62, 73, 104) )
    end
    function sbar.btnGrip:Paint(w, h)
        draw.RoundedBox( w / 2, 0, 0, w, h, Color(92, 97, 112) )
    end

    function queueList:Paint( w, h )
        draw.RoundedBox( 4, 0, 0, w, h, Color( 21, 18, 27 ) )
    end

    local function getTitle( path )
        -- Returns the Path, Filename, and Extension as 3 values
        local _, title = string.match( path, "^(.-)([^\\/]-)(%.[^\\/%.]-)%.?$" )

        --if string.find( path, "discord" ) then
        title = string.Replace( title, "_", " " )
        --end

        return title
    end

    local function UpdateList()
        -- Add the queue to the scroll panel
        queueList:Clear()
        for i = 1, #radio._queue do
            local panel = vgui.Create( "DPanel", queueList )
            panel:SetTall( 24 )
            panel:Dock( TOP )
            panel:DockMargin( 0, 0, 0, 4 )
            
            function panel:Paint( w, h )
                draw.RoundedBox( 4, 0, 0, w, h, Color( 83, 77, 94) )
            end
            
            local label = vgui.Create( "DLabel", panel )
            label:Dock( FILL )
            label:DockMargin( 4, 0, 0, 0 )
            local title = getTitle( radio._queue[i] )

            label:SetText( title or radio._queue[i] )
            label:SetTextColor( color_white )

            local removeButton = vgui.Create( "DButton", panel )
            removeButton:Dock( RIGHT )
            removeButton:DockMargin( 0, 0, 4, 0 )
            removeButton:SetText( "" )
            removeButton:SetIcon( "icon16/cross.png" )
            removeButton:SetWide( 16 )
            
            function removeButton:Paint( w, h )
                draw.RoundedBox( 4, 0, 0, w, h, Color( 83, 77, 94) )
            end

            removeButton.DoClick = function()
                table.remove( radio._queue, i )
                radio._queueChanged = true
            end
            
            queueList:AddItem( panel )
        end
        queueList:InvalidateLayout()
        
    end
    UpdateList()

    function queueList:PaintOver( w, h )
        if radio._queueChanged then
            UpdateList()
            radio._queueChanged = false
        end
    end

    local controlPanelH = dframe:GetWide() * 0.04
    local controlPanelW = dframe:GetWide() * 0.15
    local controlPanelX = dframe:GetWide() * 0.5 - controlPanelW * 0.5
    local controlPanelY = queueList:GetY() + queueList:GetTall()
    local buttonSize = controlPanelH * 0.6
    local buttonSpacing = controlPanelW * 0.4
    local controlPanel = vgui.Create( "DPanel", dframe )
    controlPanel:SetSize( controlPanelW, controlPanelH )
    controlPanel:SetPos( controlPanelX, controlPanelY + ( dframe:GetTall() - controlPanelY ) * 0.5 - controlPanelH * 0.5 )
    controlPanel:InvalidateParent( true )
    
    function controlPanel:Paint( w, h )
        draw.RoundedBox( h * 0.5, 0, 0, w, h, Color( 18, 7, 37) )
    end

    --- Rewind button
    local rewindButton = vgui.Create( "DButton", controlPanel )
    rewindButton:SetText( "" )
    rewindButton:SetPos( controlPanelW * 0.5 - buttonSpacing, controlPanelH * 0.5 - buttonSize * 0.5 )
    rewindButton:SetSize( buttonSize, buttonSize )
    
    function rewindButton:Paint( w, h )
        surface.SetMaterial( rewindMat )
        surface.SetDrawColor( 126, 119, 189)
        surface.DrawTexturedRect( 0, 0, w, h )
    end

    rewindButton.DoClick = function()
        radio:Rewind()
    end

    --- Pause/Play Button
    local pausePlayButton = vgui.Create( "DButton", controlPanel )
    pausePlayButton:SetText( "" )
    pausePlayButton:SetPos( controlPanelW * 0.5 - buttonSize * 0.5, controlPanelH * 0.5 - buttonSize * 0.5 )
    pausePlayButton:SetSize( buttonSize, buttonSize )

    function pausePlayButton:Paint( w, h )
        local mat = radio._state == "playing" and pauseMat or playMat
        surface.SetMaterial( mat )
        surface.SetDrawColor( 126, 119, 189)
        surface.DrawTexturedRect( 0, 0, w, h )
    end

    pausePlayButton.DoClick = function()
        if self._state == "playing" then
            self:Pause()
        else
            self:Play()
        end
    end

    --- Skip Button
    local skipButton = vgui.Create( "DButton", controlPanel )
    skipButton:SetText( "" )
    skipButton:SetPos( controlPanelW * 0.5 - buttonSize + buttonSpacing, controlPanelH * 0.5 - buttonSize * 0.5 )
    skipButton:SetSize( buttonSize, buttonSize )

    function skipButton:Paint( w, h )
        surface.SetMaterial( skipMat )
        surface.SetDrawColor( 126, 119, 189)
        surface.DrawTexturedRect( 0, 0, w, h )
    end

    skipButton.DoClick = function()
        radio:Next()
    end

    --- Currently Playing Audio
    local currentAudio = vgui.Create( "DPanel", dframe )
    currentAudio:SetSize( 400, controlPanelH )
    currentAudio:SetPos( controlPanelX + controlPanelW, controlPanelY )

    function currentAudio:Paint( w, h )
        local txt = radio._current and getTitle( radio._current ) or "Nothing is playing..."
        surface.SetFont( "GWaveFont" )
        local textWidth, textHeight = surface.GetTextSize( txt )
        self:SetPos( controlPanelX + controlPanelW * 1.1, ( controlPanelY + dframe:GetTall() ) * 0.5 - textHeight * 0.5 )

        draw.SimpleText( txt, "GWaveFont", 0, 0, color_white )
    end
    
end