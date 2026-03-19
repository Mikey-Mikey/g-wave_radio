AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "#g-wave_radio"
ENT.Author = "Mikey"
ENT.Category = "#g-wave_radio"

ENT.Spawnable = true

ENT.Queue = {}
ENT._AudioChannel = nil
ENT.Radius = 1000
ENT.Volume = 1
ENT.PlaybackRate = 1
ENT._CurrentBassVolume = 0
ENT.Time = 0
ENT.ChangingSong = false

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
    end
end

function ENT:SetupDataTables()
    self:NetworkVar( "Entity", "DataCreator" )
    self:NetworkVar( "String", "URL" )
    self:NetworkVar( "Float", "StartTime" )
    self:NetworkVar( "Float", "Duration" )
    self:NetworkVar( "Bool", "Playing" )
    self:NetworkVar( "String", "State" )

    if CLIENT then
        self:NetworkVarNotify( "URL", function( _, old, new )
            timer.Simple( 0, function() -- 0 Timer to make sure URL, StartTime and Duration are updated before this runs
                if not IsValid( self ) then return end
                local url = self:GetURL()
                -- trim delimiter
                local delimiter = "%[|%]"
                url = string.gsub( url, "%|.*$", "" )
                if not url or url == "" then return end
                if not self:GetPlaying() then return end

                sound.PlayURL( url, "noplay 3d noblock", function( station )
                    if not IsValid( station ) then return end
                    self._AudioChannel = station
                    station:SetPos( self:GetPos() )
                    station:Set3DFadeDistance( 1000, 1000 )
                    station:SetVolume( 1 )
                    if new then
                        station:Play()
                    end
                    self.ChangingSong = false
                end )
            end )
        end )

        self:NetworkVarNotify( "Playing", function( _, old, new )
            if not IsValid( self ) then return end
            if not self._AudioChannel then
                sound.PlayURL( self:GetURL(), "noplay 3d noblock", function( station )
                    if not IsValid( station ) then return end
                    self._AudioChannel = station
                    station:SetPos( self:GetPos() )
                    station:Set3DFadeDistance( 1000, 1000 )
                    station:SetVolume( 1 )
                    if new then
                        station:Play()
                    end
                end )
                return
            end

            if new then
                local elapsed = self:GetStartTime()
                local duration = self:GetDuration()
                if elapsed < duration and self._AudioChannel:GetState() == GMOD_CHANNEL_PAUSED then
                    self._AudioChannel:Play()
                    self._AudioChannel:SetTime( self:GetStartTime() )
                else
                    sound.PlayURL( self:GetURL(), "noplay 3d noblock", function( station )
                        if not IsValid( station ) then return end
                        self._AudioChannel = station
                        station:SetPos( self:GetPos() )
                        station:Set3DFadeDistance( 1000, 1000 )
                        station:SetVolume( 1 )
                        station:Play()
                    end )
                    --self._AudioChannel:Stop()
                end
            else
                self._AudioChannel:Pause()
            end
        end )
    end
end

if SERVER then
    function ENT:Use( activator )
        if not IsValid( activator ) or not activator:IsPlayer() then return end
        self:OpenRadioMenu( activator )
    end

    function ENT:OpenRadioMenu( ply )
        net.Start( "gwave_openmenu" )
        net.WriteEntity( self )
        net.WriteTable( self:GetQueue() )
        net.Send( ply )
    end

    function ENT:AddToQueue( url, duration )
        table.insert( self.Queue, { url = url, duration = duration } )
        net.Start( "gwave_syncqueue" )
        net.WriteEntity( self )
        net.WriteTable( self:GetQueue() )
        net.Broadcast()
    end

    function ENT:RemoveFromQueue( id )
        local element = table.remove( self.Queue, id )
        net.Start( "gwave_syncqueue" )
        net.WriteEntity( self )
        net.WriteTable( self:GetQueue() )
        net.Broadcast()
        return element
    end

    function ENT:GetQueue()
        return self.Queue
    end

    function ENT:PlayFirstSong()
        if #self.Queue == 0 then
            self:SetPlaying( false )
            return
        end

        local current = self:RemoveFromQueue( 1 )
        self:SetURL( current.url )
        self:SetDuration( current.duration )
        self:SetStartTime( 0 )
        self:SetState( "playing" )
        self:SetPlaying( true )
    end

    function ENT:PlayNextSong()
        local current = self:RemoveFromQueue( 1 )
        self:SetURL( current.url .. "|" .. os.time() )
        self:SetDuration( current.duration )
        self:SetPlaying( true )
        self:SetState( "playing" )
        self:SetStartTime( 0 )
        print( "Playing ", current.url )
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
    
    net.Receive( "gwave_operation", function( _, ply )
        local opcode = net.ReadUInt( GWAVE.OPCODECOUNT )
        local radio = net.ReadEntity()
        if not IsValid( radio ) then return end
        if radio:GetDataCreator() ~= ply then return end

        if opcode == GWAVE.OPCODES.OPEN then
            radio:OpenRadioMenu( ply )
        elseif opcode == GWAVE.OPCODES.ADD then
            radio:AddToQueue( net.ReadString(), net.ReadFloat() )
            if #radio:GetQueue() == 1 and not radio:GetPlaying() then
                radio:PlayFirstSong()
            end
        elseif opcode == GWAVE.OPCODES.REMOVE then
            radio:RemoveFromQueue( net.ReadUInt( 8 ) )
        elseif opcode == GWAVE.OPCODES.CLEAR then
            radio.Queue = {}
            radio:SetPlaying( false )
            radio:SetState( "stopped" )
        elseif opcode == GWAVE.OPCODES.PLAY then
            local time = net.ReadFloat()
            radio:SetPlaying( true )
            radio:SetState( "playing" )
            radio:SetStartTime( time )
        elseif opcode == GWAVE.OPCODES.PAUSE then
            radio:SetPlaying( false )
            radio:SetState( "paused" )
        elseif opcode == GWAVE.OPCODES.NEXT then
            if #radio:GetQueue() > 0 then
                radio:PlayNextSong()
            end
        end
    end )
end

if CLIENT then
    function ENT:OnRemove( fullUpdate )
        --if not fullUpdate then return end

        if self._AudioChannel then
            self._AudioChannel:Stop()
            self._AudioChannel = nil
        end
    end

    function ENT:Think()
        if IsValid( self._AudioChannel ) and self:GetPlaying() then
            self._AudioChannel:SetPos( self:GetPos() )
            local eyeOffset = self:GetPos() - EyePos()
            local eyeDist2 = eyeOffset:LengthSqr()
            
            if eyeDist2 > self.Radius^2 then
                self._AudioChannel:SetVolume( 0 )
            else
                local realVolume = 1 / ( 1 + eyeDist2 )
                realVolume = realVolume * self.Radius^1.38
                realVolume = math.min( realVolume * self.Volume, self.Volume )

                local dot = eyeOffset:GetNormalized():Dot( EyeAngles():Forward() )
                realVolume = realVolume * math.max( 0.5, ( math.min( dot, 0 ) + 1 ) )
                realVolume = realVolume * GWAVE.VolumeMultiplier:GetFloat()

                self._AudioChannel:SetVolume( realVolume )
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


            self._CurrentBassVolume = self._CurrentBassVolume + ( maxVal - self._CurrentBassVolume ) * 0.1

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
            if self._queue and #self._queue > 0 and not self.ChangingSong then
                self.ChangingSong = true
                net.Start( "gwave_operation" )
                net.WriteUInt( GWAVE.OPCODES.NEXT, GWAVE.OPCODECOUNT )
                net.WriteEntity( self )
                net.SendToServer()
            end
        end
    end

    function ENT:Draw()
        self:MarkShadowAsDirty() -- Makes the shadow scale with the model
        self:DrawModel()
    end
end
