AddCSLuaFile()

ENT.Base = "base_g-wave_radio"
ENT.Model = "models/props_debris/tv_monitor01.mdl"
ENT.Spawnable = true

ENT.PrintName = "Small TV"
ENT.Category = "G-Wave Radio"
ENT.Author = "Mikey"

if SERVER then
	GWAVE.GenericDuplicatorFunction( "g-wave_radio_smalltv" )
end
