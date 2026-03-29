GWAVE = GWAVE or {}
GWAVE.Convars = {}

GWAVE.OPCODES = {
    ADD = 1,
    REMOVE = 2,
    CLEAR = 3,
    OPEN = 4,
    PLAY = 5,
    PAUSE = 6,
    SKIP = 7,
    TIME = 8,
    VOLUME = 9,
}

GWAVE.OPCODECOUNT = math.ceil( math.log( table.Count( GWAVE.OPCODES ) + 1, 2 ) )

--- Default whitelist
if not CFCHTTP then
    GWAVE.Whitelist = {
        -- Discord
        "discordapp.com",
        "discordapp.net",
        
        -- Github
        "github.com",
        "githubusercontent.com",

        -- Dropbox
        "dropbox.com",
        "dropboxusercontent.com",

        -- Google Drive
        "docs.google.com",
        "drive.google.com",
        ".googleusercontent.com",

        -- Other
        "tts.cyzon.us",
    }
end

local developerCVar = GetConVar( "developer" )

function GWAVE.Print( ... )
    if developerCVar:GetBool() then
        print( "[GWAVE]:" .. " " .. ... )
    end
end

if SERVER then
    --resource.AddFile( "models/g-wave_radio/radio.mdl" )
    resource.AddWorkshop( "3690398910" )

    GWAVE.Convars.RadioLimit = CreateConVar( "sbox_maxg-wave_radios", 2, { FCVAR_REPLICATED, FCVAR_ARCHIVE } )
    util.AddNetworkString( "gwave_operation" )
    util.AddNetworkString( "gwave_openmenu" )
    util.AddNetworkString( "gwave_syncqueue" )
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