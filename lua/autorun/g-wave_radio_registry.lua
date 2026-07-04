GWAVE.RegisterRadio( "g-wave_radio", "models/g-wave_radio/radio.mdl", "Radio" )
GWAVE.RegisterRadio( "g-wave_radio_bigtv", "models/props/cs_militia/tv_console.mdl", "Big TV" )
GWAVE.RegisterRadio( "g-wave_radio_small", "models/props/cs_office/radio.mdl", "Small Radio" )
GWAVE.RegisterRadio( "g-wave_radio_smalltv", "models/props/de_inferno/tv_monitor01.mdl", "Small TV" )

if IsMounted( "csgo" ) then
	GWAVE.RegisterRadio( "g-wave_radio_vintage", "models/props/de_inferno/hr_i/inferno_vintage_radio/inferno_vintage_radio.mdl", "Vintage Radio" )
	GWAVE.RegisterRadio( "g-wave_radio_wooden", "models/props/cs_italy/radio_wooden.mdl", "Wooden Radio" )
end
