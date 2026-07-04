AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.WantsTranslucency = true
ENT.IsGWAVERadio = true

ENT.Queue = {}
ENT.QueueCooldown = 0.1
ENT._AudioChannel = nil
ENT.Radius = 1500
ENT.PlaybackRate = 1
ENT._CurrentBassVolume = 0
ENT.Time = 0
ENT.BarHeights = {}
ENT.AverageVol = 0
ENT.MaxQueueSize = 32

if CLIENT then
    language.Add( "g-wave_radio", "G-Wave Radio" )
    language.Add( "sboxlimit_g-wave_radios", "You have hit the GWave Radio limit!" )
end

function ENT:Initialize()
    self:SetModel( self.Model )
    if SERVER then
        self:PhysicsInit( SOLID_VPHYSICS )
        self:SetUseType( SIMPLE_USE )
        self:SetSkin( math.random( 0, self:SkinCount() - 1 ) )
        self:SetState( "stopped" )
        self:SetRadioVolume( 1 )
        self:SetRadius( 1500 )
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
    self:NetworkVar( "Float", "Radius" )

    if CLIENT then
        self:NetworkVarNotify( "URL", function( _, _, old, new )
            if not IsValid( self ) then return end
            timer.Simple( 0, function()
                if not IsValid( self ) then return end
                local url = string.gsub( new, "%|.*$", "" )
                if url == "" then
                    self:StopAudio()
                    return
                end
                -- Stop the old channel so it doesn't keep playing the previous song
                self:StopAudio()
                if self:GetPlaying() then
                    self:LoadUrl( url )
                end
            end )
        end )

        self:NetworkVarNotify( "Playing", function()
            if not IsValid( self ) then return end
            timer.Simple( 0, function()
                if not IsValid( self ) then return end

                if not self:GetPlaying() then
                    if IsValid( self._AudioChannel ) then
                        self._AudioChannel:Pause()
                    end
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

        if self:GetPlaying() and self:GetState() == "playing" then
            local dur = self:GetDuration()
            if dur > 0 then
                local startTime = self:GetPlayStartTime()
                if startTime > 0 then
                    local elapsed = ( CurTime() - startTime ) + self:GetPlayStartOffset()
                    -- Add a 0.5s grace period to account for loading/buffer desync
                    if elapsed >= dur + 0.5 then
                        self:PlayNextSong()
                    end
                end
            end
        end
    end

    function ENT:OnDuplicated( tbl )
        self:SetState( "stopped" )
        self:SetPlaying( false )

        timer.Simple( 0, function()
            self:SetState( tbl.DT.State )
            self:SetPlaying( tbl.DT.Playing )
            self:SetPlayStartTime( CurTime() )
            self:SetPlayStartOffset( 0 )
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

        local ent = ents.Create( self.ClassName )
        ent:Spawn()
        ent:Activate()

        ent:SetAngles( Angle( 0, ply:EyeAngles()[2] - ( self.AngleOffset or 180 ), 0 ) )
        local min, max = ent:WorldSpaceAABB()
        local offset = tr.HitNormal
        offset = offset * ( max - min ) * 0.5

        ent:SetPos( tr.HitPos + offset )
        ent:PhysWake()

        ent:SetDataCreator( ply )

        ply:AddCount( "g-wave_radios", ent )

        return ent
    end

    GWAVE.GenericDuplicatorFunction( "g-wave_radio" )

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
            elseif radio:GetURL() ~= "" then
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
            else
                radio:SetPlaying( false )
                radio:SetState( "stopped" )
                radio:SetURL( "" )
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
        elseif opcode == GWAVE.OPCODES.RADIUS then
            local radius = net.ReadFloat()
            radio:SetRadius( math.Clamp( radius, 100, 10000 ) )
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
            GWAVE.ActiveChannels[self:EntIndex()] = nil
        end
    end

    function ENT:GetCurrentPlayingURL()
        if IsValid( self._AudioChannel ) then
            return self._AudioChannel_URL
        end
        return nil
    end

    function ENT:GetElapsedTime()
        local startTime = self:GetPlayStartTime()
        local offset = self:GetPlayStartOffset()
        local elapsed
        if startTime > 0 then
            elapsed = ( CurTime() - startTime ) + offset
        else
            elapsed = offset
        end
        elapsed = math.max( 0, elapsed )
        return elapsed
    end

    ENT._IsLoading = false

    do
        local function playStation( radio, url, filepath )
            if not IsValid( radio ) then return end
            if IsValid( radio._AudioChannel ) then
                radio._AudioChannel:Stop()
                radio._AudioChannel = nil
            end
            sound.PlayFile( "data/" .. filepath, "noplay 3d noblock", function( station )
                if not IsValid( radio ) then return end
                radio._IsLoading = false
                if not IsValid( station ) then
                    radio:StopAudio()

                    return
                end

                if not IsValid( radio ) then
                    station:Stop()

                    return
                end

                radio._AudioChannel = station
                radio._AudioChannel_URL = url

                -- Register for global cleanup tracking
                GWAVE.ActiveChannels[radio:EntIndex()] = { ent = radio, station = station }

                station:SetPos( radio:GetPos() )
                station:Set3DFadeDistance( 1000, 1000 )

                -- Start muted to hide the seek blip
                station:SetVolume( 0 )

                if radio:GetElapsedTime() > 0 then
                    timer.Create( "gwave_bufferload_" .. radio:EntIndex(), 0, 0, function()
                        if not IsValid( radio ) or not IsValid( station ) then
                            timer.Remove( "gwave_bufferload_" .. radio:EntIndex() )

                            return
                        end

                        local elapsed = radio:GetElapsedTime()
                        if station:GetBufferedTime() >= elapsed then
                            station:SetTime( elapsed )
                            station:Play()

                            -- Delayed unmute to ensure BASS has finished the seek
                            timer.Simple( 0.1, function()
                                if IsValid( station ) then station:SetVolume( 1 ) end
                            end )

                            timer.Remove( "gwave_bufferload_" .. radio:EntIndex() )
                        end
                    end )
                else
                    station:Play()
                    station:SetVolume( 1 )
                end
            end )
        end

        function ENT:LoadUrl( url )
            if self:GetCurrentPlayingURL() == url then return end
            if self._IsLoading then return end

            local extension = string.GetExtensionFromFilename( url )
            if not extension then return end

            local filepath = "g-wave_cache/" .. util.CRC( url ) .. "." .. extension:Left( 3 )
            self._IsLoading = true

            if file.Exists( filepath, "DATA" ) then
                playStation( self, url, filepath )

                return
            end

            http.Fetch( url, function( body )
                file.Write( filepath, body )

                if IsValid( self ) then
                    playStation( self, url, filepath )
                end
            end )
        end
    end

    net.Receive( "gwave_operation", function()
        local opcode = net.ReadUInt( GWAVE.OPCODECOUNT )
        local radio = net.ReadEntity()
        if not IsValid( radio ) then return end
        if not radio.IsGWAVERadio then return end

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
        local audioValid = IsValid( self._AudioChannel )
        local isPlaying = self:GetPlaying()

        if audioValid then
            local audioState = self._AudioChannel:GetState()
            if isPlaying and audioState == GMOD_CHANNEL_PAUSED then
                self._AudioChannel:Play()
            elseif not isPlaying and audioState == GMOD_CHANNEL_PLAYING then
                self._AudioChannel:Pause()
            end
        end

        if audioValid and isPlaying then
            self._AudioChannel:SetPos( self:GetPos() )
            local eyeOffset = self:GetPos() - EyePos()
            local eyeDist2 = eyeOffset:LengthSqr()
            local radius = self:GetRadius() or 1500

            if eyeDist2 > radius^2 then
                self._AudioChannel:SetVolume( 0 )
            else
                local radioVol = self:GetRadioVolume() or 1
                local realVolume = 1 / ( 1 + eyeDist2 )
                realVolume = realVolume * radius^1.38
                realVolume = math.min( realVolume * radioVol, radioVol )

                local dot = eyeOffset:GetNormalized():Dot( EyeAngles():Forward() )
                realVolume = realVolume * math.max( 0.5, math.min( dot, 0 ) + 1 )
                realVolume = realVolume * GWAVE.VolumeMultiplier:GetFloat()

                self._AudioChannel:SetVolume( realVolume * 4 )
            end

            self._AudioChannel:SetPlaybackRate( self.PlaybackRate )
        elseif self:GetManipulateBoneScale( 0 ) ~= Vector( 1, 1, 1 ) then
            self:ManipulateBoneScale( 0, Vector( 1, 1, 1 ) )
        end

        -- Ensure channel keeps playing if it stopped unexpectedly (buffer underrun)
        if audioValid and self:GetPlaying() and self._AudioChannel:GetState() == GMOD_CHANNEL_STOPPED and self._AudioChannel:GetTime() < self._AudioChannel:GetLength() * 0.90 then
            self._AudioChannel:Play()
        end

        self:SetNextClientThink( CurTime() )
        return true
    end

    local defaultScale = Vector( 1, 1, 1 )

    function ENT:DrawTranslucent( flags )
        self:DrawModel( flags )

        local pos = self:GetPos()
        local eyePos = EyePos()
        if pos:DistToSqr( eyePos ) > 512 ^ 2 then return end

        local ch = self._AudioChannel
        local playing = self:GetPlaying()

        -- Scale the radio by its loudness
        if IsValid( ch ) and playing then
            local fft = {}
            self._AudioChannel:FFT( fft, FFT_1024 )

            local maxVal = 0
            local samples = #fft

            for i = 1, samples do
                if not fft[i] then continue end
                maxVal = math.max( maxVal, fft[i] )
            end

            local lerpFactor = 1 - math.pow( 1 - 0.1, FrameTime() * 66.666 )
            self._CurrentBassVolume = self._CurrentBassVolume + ( maxVal - self._CurrentBassVolume ) * lerpFactor

            local squish = self._CurrentBassVolume * 0.5
            squish = math.min( squish, 0.5 )

            self:ManipulateBoneScale( 0, Vector( 1 + squish, 1 - squish, 1 + squish ) )
        elseif self:GetManipulateBoneScale( 0 ) ~= defaultScale then
            self:ManipulateBoneScale( 0, defaultScale )
        end

        -- Radio overlay
        local url = self:GetURL() or ""
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

        local state = self:GetState() or "stopped"

        if state == "stopped" or text == "" then
            text = self.PrintName or "G-Wave Radio"
        elseif not playing then
            text = "[Paused] " .. text
        end

        local prog = 0
        local dur = self:GetDuration()
        if IsValid( ch ) then
            if dur and dur > 0 then
                prog = math.Clamp( ch:GetTime() / dur, 0, 1 )
            end
        end

        local zOffset = self:OBBMaxs().z + 12
        local drawPos = pos + Vector( 0, 0, zOffset )

        local ang = ( eyePos - drawPos ):Angle()
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
                local barHeights = self.BarHeights

                --local highestDb = math.max( 0, 20 * math.log10( fft[highestIndex] ) + 12 ) / 16
                --print( highestDb )
                --barHeights[1] = barHeights[1] or 0
                --barHeights[1] = barHeights[1] + ( highestDb * 5 - barHeights[1] ) * 0.1
                --barHeights[1] = math.sin( CurTime() * 30 ) * 0.5 + 0.5
                for i = 1, #fft do
                    barHeights[i] = barHeights[i] or 0
                end

                local dt = FrameTime()
                local iterCount = math.max( 1, math.Round( dt * 120 ) )
                local stepTime = dt / iterCount
                local relativeStep = stepTime * 120

                local decay = math.pow( 0.99, relativeStep )
                local ripple = 1 - math.pow( 0.5, relativeStep )

                for iter = 1, iterCount do
                    local unRippledHeights = table.Copy( barHeights )
                    for i = 1, #fft do
                        local db = fft[i]^2 * 10--math.max( 0, 20 * math.log10( fft[i] ) + 16 ) / 4
                        db = db ^ 0.5
                        barHeights[i] = barHeights[i] * decay
                        barHeights[i] = math.max( barHeights[i], db )--math.max( barHeights[i], barHeights[i] + ( db * 5 - barHeights[i] ) * 0.1 )

                        if i > 1 then
                            -- ripple
                            barHeights[i] = Lerp( ripple, barHeights[i], unRippledHeights[i - 1] )
                        end

                        if i < #fft then
                            -- ripple
                            barHeights[i + 1] = Lerp( ripple, barHeights[i + 1], unRippledHeights[i] )
                        end
                    end
                end

                for i = 1, #fft do
                    local nx = ( i - 1 + 0.5 ) * barWidth
                    surface.SetDrawColor( 157, 80, 187, 100 + barHeights[i] * 155 )
                    surface.DrawRect( nx, y * 3 + h - math.floor( barHeights[i] * h ), barWidth, math.floor( barHeights[i] * h ) )
                    surface.DrawRect( -nx, y * 3 + h - math.floor( barHeights[i] * h ), barWidth, math.floor( barHeights[i] * h ) )
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
end
