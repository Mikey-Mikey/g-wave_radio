AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "G-Wave Radio"
ENT.Author = "Mikey"
ENT.Category = "G-Wave Radio"

ENT.Spawnable = true

ENT.Queue = {}
ENT.QueueCooldown = 0.1
ENT._AudioChannel = nil
ENT.Radius = 1500
ENT.PlaybackRate = 1
ENT._CurrentBassVolume = 0
ENT.Time = 0
ENT.ChangingSong = false
ENT.BarHeights = {}
ENT.AverageVol = 0
ENT.MaxQueueSize = 32

if CLIENT then
    language.Add( "g-wave_radio", "G-Wave Radio" )
    language.Add( "sboxlimit_g-wave_radios", "You have hit the GWave Radio limit!" )
end

function ENT:Initialize()
    self:SetModel( "models/g-wave_radio/radio.mdl" )
    if SERVER then
        self:PhysicsInit( SOLID_VPHYSICS )
        self:SetUseType( SIMPLE_USE )
        self:SetSkin( math.random( 0, self:SkinCount() - 1 ) )
        self:SetState( "stopped" )
        self:SetRadioVolume( 1 )
        if WireLib then
            local inputs = {}

            local outputs = {}
            self:SetupWiremodPorts( inputs, outputs )

            local inNames, inTypes, inDescr = {}, {}, {}

            for i, v in ipairs( inputs ) do
                inNames[i] = v[1]
                inTypes[i] = v[2]
                inDescr[i] = v[3]
            end

            WireLib.CreateSpecialInputs(
                self,
                inNames,
                inTypes,
                inDescr
            )

            local outNames, outTypes, outDescr = {}, {}, {}

            for i, v in ipairs( outputs ) do
                outNames[i] = v[1]
                outTypes[i] = v[2]
                outDescr[i] = v[3]
            end

            WireLib.CreateSpecialOutputs(
                self,
                outNames,
                outTypes,
                outDescr
            )
        end
    end
end

function ENT:SetupWiremodPorts( inputs, outputs )
    table.insert( inputs, { "Playing", "NORMAL", "Play/Pause the radio" } )
    table.insert( inputs, { "Volume", "NORMAL", "Set the volume of the radio" } )
    table.insert( inputs, { "URL", "STRING", "Set the URL of the radio" } )
    table.insert( inputs, { "Queue", "ARRAY", "Set the queue of the radio" } )

    table.insert( outputs, { "Playing", "NORMAL", "Is the radio playing?" } )
    table.insert( outputs, { "Volume", "NORMAL", "The volume of the radio" } )
    table.insert( outputs, { "URL", "STRING", "The URL of the radio" } )
    table.insert( outputs, { "Queue", "ARRAY", "The queue of the radio" } )
end

function ENT:TriggerInput( inputName, value )
    if inputName == "Playing" then
        self:SetPlaying( value ~= 0 )
    elseif inputName == "Volume" then
        self:SetRadioVolume( value )
    elseif inputName == "URL" then
        if self.QueueCooldown > 0 then return end
        self.QueueCooldown = 0.1
        self:SetURL( value )
    elseif inputName == "Queue" then
        if self.QueueCooldown > 0 then return end
        self.QueueCooldown = 0.1
        self.Queue = {}
        for i = 1, math.min( #value, self.MaxQueueSize ) do
            self.Queue[i] = value[i]
        end
        net.Start( "gwave_syncqueue" )
        net.WriteEntity( self )
        self:WriteQueue()
        net.Broadcast()
    end
end

function ENT:SetupDataTables()
    self:NetworkVar( "Entity", "DataCreator" )
    self:NetworkVar( "String", "URL" )
    self:NetworkVar( "Float", "Duration" )
    self:NetworkVar( "Bool", "Playing" )
    self:NetworkVar( "String", "State" )
    self:NetworkVar( "Float", "RadioVolume" )
    self:NetworkVar( "Bool", "Looping" )
    -- PlayStartTime: server CurTime() when playback started/resumed (0 when paused/stopped)
    -- PlayStartOffset: seek position in seconds at that moment
    -- Current position = (CurTime() - PlayStartTime) + PlayStartOffset
    self:NetworkVar( "Float", "PlayStartTime" )
    self:NetworkVar( "Float", "PlayStartOffset" )

    if CLIENT then
        self:NetworkVarNotify( "Playing", function()
            if not IsValid( self ) then return end
            timer.Simple( 0, function()
                if not IsValid( self ) then return end

                if not self:GetPlaying() then
                    self:StopAudio()
                    return
                end

                local url = self:GetURL()
                url = string.gsub( url, "%|.*$", "" )
                if url and url ~= "" then
                    self:LoadUrl( url )
                end
            end )
        end )
    end
end

if SERVER then
    function ENT:Think()
        self.QueueCooldown = self.QueueCooldown - engine.TickInterval()
    end

    function ENT:OnDuplicated( tbl )
        self:SetState( "stopped" )
        self:SetPlaying( false )

        timer.Simple( 0, function()
            self:SetState( tbl.DT.State )
            self:SetPlaying( tbl.DT.Playing )
        end )

        if tbl.Skin then
            self:SetSkin( tbl.Skin )
        end

        net.Start( "gwave_syncqueue" )
        net.WriteEntity( self )
        self:WriteQueue()
        net.Broadcast()
    end

    function ENT:PostEntityPaste( ply )
        self:SetDataCreator( ply )
        ply:AddCount( "g-wave_radios", self )
    end

    function ENT:Use( activator )
        if not IsValid( activator ) or activator ~= self:GetDataCreator() then return end
        self:OpenRadioMenu( activator )
    end

    function ENT:OpenRadioMenu( ply )
        net.Start( "gwave_openmenu" )
        net.WriteEntity( self )
        self:WriteQueue()
        net.Send( ply )
    end

    function ENT:AddToQueue( url, duration )
        table.insert( self.Queue, { url = url, duration = duration } )
        net.Start( "gwave_syncqueue" )
        net.WriteEntity( self )
        self:WriteQueue()
        net.Broadcast()
    end

    function ENT:RemoveFromQueue( id )
        local element = table.remove( self.Queue, id )
        net.Start( "gwave_syncqueue" )
        net.WriteEntity( self )
        self:WriteQueue()
        net.Broadcast()
        return element
    end

    function ENT:GetQueue()
        return self.Queue
    end

    function ENT:WriteQueue()
        local q = self:GetQueue()
        net.WriteUInt( #q, 16 )
        for i = 1, #q do
            net.WriteString( q[i].url or "" )
            net.WriteFloat( q[i].duration or 0 )
        end
    end

    function ENT:PlayFirstSong()
        self:SetState( "stopped" )
        self:SetPlaying( false )
        if #self.Queue == 0 then
            return
        end

        local current = self:RemoveFromQueue( 1 )
        self:SetURL( current.url .. "|" .. os.time() )
        self:SetDuration( current.duration )
        self:SetPlayStartOffset( 0 )
        self:SetPlayStartTime( CurTime() )
        self:SetState( "playing" )
        self:SetPlaying( true )
    end

    function ENT:PlayNextSong()
        if self:GetLooping() and self:GetURL() ~= "" then
            local oldUrl = string.gsub( self:GetURL(), "%|.*$", "" )
            table.insert( self.Queue, { url = oldUrl, duration = self:GetDuration() } )
        end

        if #self.Queue == 0 then
            self:SetPlaying( false )
            self:SetState( "stopped" )
            self:SetURL( "" )
            return
        end

        local current = table.remove( self.Queue, 1 )
        net.Start( "gwave_syncqueue" )
        net.WriteEntity( self )
        self:WriteQueue()
        net.Broadcast()

        self:SetURL( current.url .. "|" .. os.time() )
        self:SetDuration( current.duration )
        self:SetPlayStartOffset( 0 )
        self:SetPlayStartTime( CurTime() )
        self:SetPlaying( true )
        self:SetState( "playing" )
    end

    function ENT:SpawnFunction( ply, tr )
        if not tr.Hit then return end

        if not ply:CheckLimit( "g-wave_radios" ) then
            return
        end

        local ent = ents.Create( "g-wave_radio" )
        ent:Spawn()
        ent:Activate()

        ent:SetAngles( Angle( 0, ply:EyeAngles()[2] - 90, 0 ) )
        local min, max = ent:WorldSpaceAABB()
        local offset = tr.HitNormal
        offset = offset * ( max - min ) * 0.5

        ent:SetPos( tr.HitPos + offset )
        ent:PhysWake()

        ent:SetDataCreator( ply )

        ply:AddCount( "g-wave_radios", ent )

        return ent
    end

    local function checkWhitelist( url )
        if not GWAVE.Whitelist then return true end
        for _, domain in ipairs( GWAVE.Whitelist ) do
            if string.find( url, domain, 1, true ) then
                return true
            end
        end
        return false
    end

    net.Receive( "gwave_operation", function( _, ply )
        local opcode = net.ReadUInt( GWAVE.OPCODECOUNT )
        local radio = net.ReadEntity()
        if not IsValid( radio ) then return end
        if radio:GetDataCreator() ~= ply then return end

        radio._lastOpTime = radio._lastOpTime or 0
        if CurTime() - radio._lastOpTime < 0.1 then return end
        radio._lastOpTime = CurTime()

        if opcode == GWAVE.OPCODES.OPEN then
            radio:OpenRadioMenu( ply )
        elseif opcode == GWAVE.OPCODES.ADD then
            local url, duration = net.ReadString(), net.ReadFloat()
            if not url or url == "" then return end
            if not checkWhitelist( url ) then
                GWAVE.Print( "Blocked URL: " .. url )
                return
            end

            radio:AddToQueue( url, duration )
            if #radio:GetQueue() == 1 and radio:GetURL() == "" then
                radio:PlayFirstSong()
            end
        elseif opcode == GWAVE.OPCODES.REMOVE then
            radio:RemoveFromQueue( net.ReadUInt( 8 ) )
        elseif opcode == GWAVE.OPCODES.CLEAR then
            radio.Queue = {}
            radio:SetPlaying( false )
            radio:SetState( "stopped" )
        elseif opcode == GWAVE.OPCODES.PLAY then
            if #radio:GetQueue() > 0 and radio:GetURL() == "" then
                radio:PlayFirstSong()
            else
                -- Resume: advance offset to the paused position, restart the clock
                radio:SetPlayStartTime( CurTime() )
                radio:SetPlaying( true )
                radio:SetState( "playing" )
            end

        elseif opcode == GWAVE.OPCODES.PAUSE then
            -- Freeze offset at the current computed position so resumers seek correctly
            local elapsed = ( CurTime() - radio:GetPlayStartTime() ) + radio:GetPlayStartOffset()
            radio:SetPlayStartOffset( math.max( 0, elapsed ) )
            radio:SetPlayStartTime( 0 )
            radio:SetPlaying( false )
            radio:SetState( "paused" )
        elseif opcode == GWAVE.OPCODES.SKIP then
            if #radio:GetQueue() > 0 or radio:GetLooping() then
                radio:PlayNextSong()
                radio:SetPlaying( true )
                radio:SetState( "playing" )
            end
        elseif opcode == GWAVE.OPCODES.TIME then
            local time = net.ReadFloat()
            -- Persist seek position so late-joining clients start at the right place
            radio:SetPlayStartOffset( time )
            radio:SetPlayStartTime( radio:GetPlaying() and CurTime() or 0 )
            net.Start( "gwave_operation" )
            net.WriteUInt( GWAVE.OPCODES.TIME, GWAVE.OPCODECOUNT )
            net.WriteEntity( radio )
            net.WriteFloat( time )
            net.Broadcast()
        elseif opcode == GWAVE.OPCODES.VOLUME then
            local volume = net.ReadFloat()
            radio:SetRadioVolume( math.Clamp( volume, 0, 1 ) )
        elseif opcode == GWAVE.OPCODES.LOOP then
            radio:SetLooping( not radio:GetLooping() )
        end
    end )
end

if CLIENT then
    function ENT:GetAudioChannel()
        return IsValid( self._AudioChannel ) and self._AudioChannel or nil
    end

    function ENT:StopAudio()
        self._AudioChannel_URL = nil
        if IsValid( self._AudioChannel ) then
            self._AudioChannel:Stop()
            self._AudioChannel = nil
        end
    end

    function ENT:GetCurrentPlayingURL()
        if IsValid( self._AudioChannel ) then
            return self._AudioChannel_URL
        end
        return nil
    end

    ENT._IsLoading = false
    function ENT:LoadUrl( url )
        if self:GetCurrentPlayingURL() == url then return end
        if self._IsLoading then return end

        self._IsLoading = true
        sound.PlayURL( url, "noplay 3d noblock", function( station )
            self._IsLoading = false
            if not IsValid( station ) then
                self:StopAudio()
                return
            end

            if not IsValid( self ) then
                station:Stop()
                return
            end

            self._AudioChannel = station
            self._AudioChannel_URL = url

            station:SetPos( self:GetPos() )
            station:Set3DFadeDistance( 1000, 1000 )
            station:SetVolume( 1 )

            -- Seek to the correct position based on server-tracked play time
            local startTime = self:GetPlayStartTime()
            local offset = self:GetPlayStartOffset()
            local elapsed
            if startTime > 0 then
                elapsed = ( CurTime() - startTime ) + offset
            else
                elapsed = offset
            end
            elapsed = math.max( 0, elapsed )
            if elapsed > 0 then
                timer.Create( "gwave_bufferload_" .. self:EntIndex(), 0.1, 0, function()
                    if not IsValid( self ) or not IsValid( station ) then
                        timer.Remove( "gwave_bufferload_" .. self:EntIndex() )
                        return
                    end

                    if station:GetBufferedTime() >= elapsed then
                        station:SetTime( elapsed )
                        station:Play()
                        timer.Remove( "gwave_bufferload_" .. self:EntIndex() )
                    end
                end )
            else
                station:Play()
            end
        end )
    end

    net.Receive( "gwave_operation", function()
        local opcode = net.ReadUInt( GWAVE.OPCODECOUNT )
        local radio = net.ReadEntity()
        if not IsValid( radio ) then return end

        if opcode == GWAVE.OPCODES.TIME then
            local time = net.ReadFloat()
            if IsValid( radio._AudioChannel ) then
                radio._AudioChannel:SetTime( time )
                if radio:GetPlaying() and radio._AudioChannel:GetState() == GMOD_CHANNEL_STOPPED then
                    radio._AudioChannel:Play()
                end
            else
                local url = radio:GetURL()
                url = string.gsub( url, "%|.*$", "" )
                if url and url ~= "" then
                    radio:LoadUrl( url )
                end
            end
        end
    end )

    function ENT:OnRemove()
        self:StopAudio()
    end

    function ENT:Think()
        if IsValid( self._AudioChannel ) and self._AudioChannel:GetState() ~= GMOD_CHANNEL_PLAYING and self:GetPlaying() then
            self._AudioChannel:Play()
        end

        if IsValid( self._AudioChannel ) and self:GetPlaying() then
            self._AudioChannel:SetPos( self:GetPos() )
            local eyeOffset = self:GetPos() - EyePos()
            local eyeDist2 = eyeOffset:LengthSqr()

            if eyeDist2 > self.Radius^2 then
                self._AudioChannel:SetVolume( 0 )
            else
                local radioVol = self:GetRadioVolume() or 1
                local realVolume = 1 / ( 1 + eyeDist2 )
                realVolume = realVolume * self.Radius^1.38
                realVolume = math.min( realVolume * radioVol, radioVol )

                local dot = eyeOffset:GetNormalized():Dot( EyeAngles():Forward() )
                realVolume = realVolume * math.max( 0.5, ( math.min( dot, 0 ) + 1 ) )
                realVolume = realVolume * GWAVE.VolumeMultiplier:GetFloat()

                self._AudioChannel:SetVolume( realVolume * 2 )
            end

            self._AudioChannel:SetPlaybackRate( self.PlaybackRate )

            -- Scale the radio by its loudness
            local scale = Vector( 1, 1, 1 )
            local fft = {}
            self._AudioChannel:FFT( fft, FFT_1024 )
            local samples = #fft

            local maxVal = 0
            for i = 1, samples do
                if not fft[i] then continue end
                maxVal = math.max( maxVal, fft[i] )
            end

            local lerpFactor = 1 - math.pow( 1 - 0.1, FrameTime() * 66.666 )
            self._CurrentBassVolume = self._CurrentBassVolume + ( maxVal - self._CurrentBassVolume ) * lerpFactor

            local squish = self._CurrentBassVolume * 0.5

            squish = math.min( squish, 0.5 )

            scale[1] = scale[1] + squish
            scale[2] = scale[2] - squish
            scale[3] = scale[3] + squish

            self:ManipulateBoneScale( 0, scale )
        elseif self:GetManipulateBoneScale( 0 ) ~= Vector( 1, 1, 1 ) then
            self:ManipulateBoneScale( 0, Vector( 1, 1, 1 ) )
        end

        -- Advance queue and update server queue
        if self:GetDataCreator() == LocalPlayer() and IsValid( self._AudioChannel ) and self._AudioChannel:GetState() == GMOD_CHANNEL_STOPPED then
            if not self.ChangingSong and self:GetURL() ~= "" then
                self.ChangingSong = true
                if (self._queue and #self._queue > 0) or self:GetLooping() then
                    net.Start( "gwave_operation" )
                    net.WriteUInt( GWAVE.OPCODES.SKIP, GWAVE.OPCODECOUNT )
                    net.WriteEntity( self )
                    net.SendToServer()
                else
                    self.ChangingSong = false
                end
            end
        end
    end

    function ENT:Draw()
        self:MarkShadowAsDirty()
        self:DrawModel()
    end

    local function drawRadioOverlay( radio )
        local ply = LocalPlayer()
        if not IsValid( ply ) then return end

        local pos = radio:GetPos()

        local url = radio:GetURL() or ""
        url = string.gsub( url, "%|.*$", "" )

        local text = url
        if text ~= "" then
            local pathExt = string.match( text, "([^/]+)$" )
            if pathExt then
                local name = string.match( pathExt, "^(.+)%.[^.]+$" )
                text = name or pathExt
            end
            text = string.Replace( text, "_", " " )
            text = string.Trim( text )
            text = string.gsub( text, "%%20", " " )
        end

        local state = radio:GetState() or "stopped"
        local playing = radio:GetPlaying()

        if state == "stopped" or text == "" then
            text = "G-Wave Radio"
        elseif not playing then
            text = "[Paused] " .. text
        end

        local ch = radio._AudioChannel
        local prog = 0
        local dur = radio:GetDuration()
        if IsValid( ch ) then
            if dur and dur > 0 then
                prog = math.Clamp( ch:GetTime() / dur, 0, 1 )
            end
        end

        local zOffset = radio:OBBMaxs().z + 12
        local drawPos = pos + Vector( 0, 0, zOffset )

        local ang = ( ply:EyePos() - drawPos ):Angle()
        ang.p = 0
        ang.r = 0
        ang:RotateAroundAxis( ang:Up(), 90 )
        ang:RotateAroundAxis( ang:Forward(), 90 )

        cam.Start3D2D( drawPos, ang, 0.1 )
            surface.SetFont( "Trebuchet24" )
            local tw, th = surface.GetTextSize( text )

            local paddingX = 48
            local paddingY = 24
            local barH = 6
            local barGap = 12

            local w = math.max( tw, 250 ) + paddingX
            local h = th + barGap + barH + paddingY

            local x = -w / 2
            local y = -h / 2

            draw.RoundedBox( 12, x, y, w, h, Color( 14, 14, 14, 240 ) )

            if ch and playing then
                -- rectangle visualizer
                local fft = {}
                ch:FFT( fft, FFT_256 )
                local barWidth = math.floor( w / #fft / 2 )

                --local highestDb = math.max( 0, 20 * math.log10( fft[highestIndex] ) + 12 ) / 16
                --print( highestDb )
                --self.BarHeights[1] = self.BarHeights[1] or 0
                --self.BarHeights[1] = self.BarHeights[1] + ( highestDb * 5 - self.BarHeights[1] ) * 0.1
                --self.BarHeights[1] = math.sin( CurTime() * 30 ) * 0.5 + 0.5
                for i = 1, #fft do
                    radio.BarHeights[i] = radio.BarHeights[i] or 0
                end

                local dt = FrameTime()
                local iterCount = math.max( 1, math.Round( dt * 120 ) )
                local stepTime = dt / iterCount
                local relativeStep = stepTime * 120

                local decay = math.pow( 0.99, relativeStep )
                local ripple = 1 - math.pow( 0.5, relativeStep )

                for iter = 1, iterCount do
                    local unRippledHeights = table.Copy( radio.BarHeights )
                    for i = 1, #fft do
                        local db = fft[i]^2 * 10--math.max( 0, 20 * math.log10( fft[i] ) + 16 ) / 4
                        db = db ^ 0.5
                        radio.BarHeights[i] = radio.BarHeights[i] * decay
                        radio.BarHeights[i] = math.max( radio.BarHeights[i], db )--math.max( self.BarHeights[i], self.BarHeights[i] + ( db * 5 - self.BarHeights[i] ) * 0.1 )

                        if i > 1 then
                            -- ripple
                            radio.BarHeights[i] = Lerp( ripple, radio.BarHeights[i], unRippledHeights[i - 1] )
                        end

                        if i < #fft then
                            -- ripple
                            radio.BarHeights[i + 1] = Lerp( ripple, radio.BarHeights[i + 1], unRippledHeights[i] )
                        end
                    end
                end

                for i = 1, #fft do
                    local nx = ( i - 1 + 0.5 ) * barWidth
                    surface.SetDrawColor( 157, 80, 187, 100 + radio.BarHeights[i] * 155 )
                    surface.DrawRect( nx, y * 3 + h - math.floor( radio.BarHeights[i] * h ), barWidth, math.floor( radio.BarHeights[i] * h ) )
                    surface.DrawRect( -nx, y * 3 + h - math.floor( radio.BarHeights[i] * h ), barWidth, math.floor( radio.BarHeights[i] * h ) )
                end
            end

            surface.SetTextColor( 255, 255, 255, 255 )
            surface.SetTextPos( x + (w - tw) / 2, y + paddingY / 2 )
            surface.DrawText( text )

            local barX = x + paddingX / 2
            local barY = y + paddingY / 2 + th + barGap
            local barW = w - paddingX
            surface.SetDrawColor( 79, 26, 104)
            surface.DrawRect( barX - 1, barY - 1, barW + 2, barH + 2 )

            surface.SetDrawColor( 43, 4, 48)
            surface.DrawRect( barX, barY, barW, barH )

            if prog > 0 then
                surface.SetDrawColor( 157, 80, 187, 255 )
                surface.DrawRect( barX, barY, barW * prog, barH )
            end
        cam.End3D2D()
    end
    --hook.Remove( "PostDrawOpaqueRenderables", "G-Wave_DrawRadioOverlays" )
    hook.Add( "PostDrawTranslucentRenderables", "G-Wave_DrawRadioOverlays", function( depth, sky, sky3d )
        if depth or sky or sky3d then return end
        local radios = ents.FindInBox( LocalPlayer():EyePos() - Vector( 500, 500, 500 ), LocalPlayer():EyePos() + Vector( 500, 500, 500 ) )
        for _, ent in ipairs( radios ) do
            if ent:GetClass() == "g-wave_radio" then
                drawRadioOverlay( ent )
            end
        end
    end )
end

