GWAVE = GWAVE or {}
GWAVE.Convars = {}

local developerCVar = GetConVar( "developer" )

function GWAVE.Print( ... )
    if developerCVar:GetBool() then
        print( ... )
    end
end

if SERVER then
    GWAVE.Convars.RadioLimit = CreateConVar( "sbox_maxgwave_radios", 2, { FCVAR_REPLICATED, FCVAR_ARCHIVE } )
    util.AddNetworkString( "GWave_OpenRadioMenu" )
end

if CLIENT then
    GWAVE.Radios = {}

    GWAVE.Font = surface.CreateFont( "GWaveFont", {
        font = "Arial",
        size = math.floor( 24 * ( ScrH() / 1080 ) ),
        weight = 500,
        antialias = true,
        shadow = true,
    } )

    hook.Add( "OnScreenSizeChanged", "GWave_ResizeFont", function()
        GWAVE.Font = surface.CreateFont( "GWaveFont", {
            font = "Arial",
            size = math.floor( 24 * ( ScrH() / 1080 ) ),
            weight = 500,
            antialias = true,
            shadow = true,
        } )
    end )

    local function CreateRadio( parent )
        local radioObj = GWave.new()
        radioObj:SetParent( parent )
        parent._radioObj = radioObj
    end

    local function GetRadioFromParent( parent )
        for i = #GWAVE.Radios, 1, -1 do
            local radio = GWAVE.Radios[i]
            if radio._parent == parent then
                return radio
            end
        end
    end

    hook.Add( "PreDrawTranslucentRenderables", "GWave_FixEyePos", function()
        EyePos()
        EyeAngles()
    end )

    hook.Add( "NetworkEntityCreated", "GWave_NetEnt", function( ent )
        if IsValid( ent ) and ent:GetClass() == "g-wave_radio" then
            CreateRadio( ent )
        end
    end )

    net.Receive( "GWave_OpenRadioMenu", function()
        local radio = net.ReadEntity()
        if IsValid( radio ) then
            local radioObj = GetRadioFromParent( radio )

            if radioObj then
                radioObj:OpenRadioMenu()
            end
        end
    end )
end