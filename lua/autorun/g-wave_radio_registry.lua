GWAVE.RegisterRadio( "g-wave_radio", "models/g-wave_radio/radio.mdl", "Radio", 90 )
GWAVE.RegisterRadio( "g-wave_radio_consoletv", "models/props/cs_militia/television_console01.mdl", "Console TV" )
GWAVE.RegisterRadio( "g-wave_radio_bigtv", "models/props/cs_militia/tv_console.mdl", "Big TV" )
GWAVE.RegisterRadio( "g-wave_radio_small", "models/props/cs_office/radio.mdl", "Small Radio" )
GWAVE.RegisterRadio( "g-wave_radio_smalltv", "models/props/de_inferno/tv_monitor01.mdl", "Small TV" )
GWAVE.RegisterRadio( "g-wave_radio_smallconsole", "models/props_c17/consolebox03a.mdl", "Small Console" )
GWAVE.RegisterRadio( "g-wave_radio_mediumconsole", "models/props_c17/consolebox01a.mdl", "Medium Console" )

-- CS:GO Models
if util.IsValidModel( "models/props/de_inferno/hr_i/inferno_vintage_radio/inferno_vintage_radio.mdl" ) then
	GWAVE.RegisterRadio( "g-wave_radio_vintage", "models/props/de_inferno/hr_i/inferno_vintage_radio/inferno_vintage_radio.mdl", "Vintage Radio" )
end

if util.IsValidModel( "models/props/cs_italy/radio_wooden.mdl" ) then
	GWAVE.RegisterRadio( "g-wave_radio_wooden", "models/props/cs_italy/radio_wooden.mdl", "Wooden Radio" )
end
