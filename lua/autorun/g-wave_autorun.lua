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
    LOOP = 10,
    RADIUS = 11,
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
        "drive.usercontent.google.com",
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

    function GWAVE.GenericDuplicatorFunction( class )
        duplicator.RegisterEntityClass( class, function( ply, data )
            if ply:CheckLimit( "g-wave_radios" ) then
                return duplicator.GenericDuplicatorFunction( ply, data )
            end
        end, "Data" )
    end
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

    list.Set( "ContentCategoryIcons", "G-Wave Radio", "materials/icon16/sound.png" )
    file.CreateDir( "g-wave_cache" )

    -- Clear cache
    local function clearCache()
        local files = file.Find( "g-wave_cache/*", "DATA" )

        if #files == 0 then
            print( "[GWAVE]: No files found" )

            return
        end

        for _, path in ipairs( files ) do
            file.Delete( "g-wave_cache/" .. path )
        end

        print( "[GWAVE]: Cleared " .. #files .. " file(s)" )
    end

    clearCache()

    concommand.Add( "g-wave_clear_cache", clearCache )
end

function GWAVE.RegisterRadio( class, model, print_name, angle_offset )
    local ent = {}
    ent.Base = "base_g-wave_radio"
    ent.Spawnable = true

    ent.Model = model
    ent.AngleOffset = angle_offset
    ent.PrintName = print_name
    ent.Category = "G-Wave Radio"
    ent.Author = "Mikey"

    if SERVER then
        GWAVE.GenericDuplicatorFunction( class )
    end

    scripted_ents.Register( ent, class )
end
