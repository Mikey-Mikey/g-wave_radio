GWAVE = GWAVE or {}
GWAVE.Convars = {}

GWAVE.OPCODES = {
    ADD = 1,
    REMOVE = 2,
    CLEAR = 3,
    OPEN = 4,
    PLAY = 5,
    PAUSE = 6,
    NEXT = 7
}

GWAVE.OPCODECOUNT = math.ceil( math.log( table.Count( GWAVE.OPCODES ) + 1, 2 ) )

local developerCVar = GetConVar( "developer" )

function GWAVE.Print( ... )
    if developerCVar:GetBool() then
        print( "[GWAVE]:" .. " " .. ... )
    end
end

if SERVER then
    GWAVE.Convars.RadioLimit = CreateConVar( "sbox_maxg-wave_radios", 2, { FCVAR_REPLICATED, FCVAR_ARCHIVE } )
    util.AddNetworkString( "gwave_operation" )
    util.AddNetworkString( "gwave_openmenu" )
    util.AddNetworkString( "gwave_syncqueue" )
    --[[
    net.Receive( "gwave_operation", function( _, ply )
        local opcode = net.ReadUInt( 3 )
        if opcode == GWAVE.OPCODES.ADD then
            local ent = net.ReadEntity()
            if not IsValid( ent ) then return end
            if ent:GetDataCreator() ~= ply then return end

            local url = net.ReadString()
            local title = net.ReadString()
            ent:AddToQueue( url, title )
        end

        if opcode == GWAVE.OPCODES.PLAY then
            local ent = net.ReadEntity()
            if not IsValid( ent ) then return end
            if ent:GetDataCreator() ~= ply then return end
            ent:SetState( "playing" )
            ent:SetPlaying( true )
            ent:SetStartTime( CurTime() )
        end

        if opcode == GWAVE.OPCODES.PAUSE then
            local ent = net.ReadEntity()
            if not IsValid( ent ) then return end
            if ent:GetDataCreator() ~= ply then return end
            ent:SetState( "paused" )
            ent:SetPlaying( false )
        end

        if opcode == GWAVE.OPCODES.REMOVE then
            local ent = net.ReadEntity()
            if not IsValid( ent ) then return end
            if ent:GetDataCreator() ~= ply then return end

            local index = net.ReadUInt( 4 )
            ent:RemoveFromQueue( index )
        end

        if opcode == GWAVE.OPCODES.CLEAR then
            local ent = net.ReadEntity()
            if not IsValid( ent ) then return end
            if ent:GetDataCreator() ~= ply then return end

            ent:ClearQueue()
            ent:SetState( "stopped" )
        end
    end )
    ]]
end

if CLIENT then
    GWAVE.Radios = GWAVE.Radios or {}

    GWAVE.Font = surface.CreateFont( "GWaveFont", {
        font = "Arial",
        size = math.floor( 24 * ( ScrH() / 1080 ) ),
        weight = 500,
        antialias = true,
        shadow = true,
    } )

    GWAVE.VolumeMultiplier = CreateClientConVar( "g-wave_volume_multiplier", 1, true, false, "Sets how loud radios are for you.", 0, 1 )

    -- Add settings to utilities
    hook.Add( "AddToolMenuCategories", "GWaveCategory", function()
        spawnmenu.AddToolCategory( "Utilities", "GWave", "#GWave" )
    end )

    hook.Add( "PopulateToolMenu", "GWaveMenuSettings", function()
        spawnmenu.AddToolMenuOption( "Utilities", "GWave", "GWave_Menu", "#GWave", "", "", function( panel )
            panel:NumSlider( "Global Volume", "g-wave_volume_multiplier", 0, 1 )
            panel:Help( "Sets how loud radios are for you." )
        end )
    end )

    hook.Add( "OnScreenSizeChanged", "GWave_ResizeFont", function()
        GWAVE.Font = surface.CreateFont( "GWaveFont", {
            font = "Arial",
            size = math.floor( 24 * ( ScrH() / 1080 ) ),
            weight = 500,
            antialias = true,
            shadow = true,
        } )
    end )

    hook.Add( "PreDrawTranslucentRenderables", "GWave_FixEyePos", function()
        EyePos()
        EyeAngles()
    end )
end