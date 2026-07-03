AddCSLuaFile()

ENT.Base = "base_g-wave_radio"
ENT.Model = "models/props/cs_militia/tv_console.mdl"
ENT.Spawnable = true

ENT.PrintName = "Big TV"
ENT.Category = "G-Wave Radio"
ENT.Author = "Mikey"

if SERVER then
	GWAVE.GenericDuplicatorFunction( "g-wave_radio_bigtv" )
end
