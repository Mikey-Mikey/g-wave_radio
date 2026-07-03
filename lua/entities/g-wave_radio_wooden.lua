AddCSLuaFile()

ENT.Base = "base_g-wave_radio"
ENT.Model = "models/props/cs_italy/radio_wooden.mdl"
ENT.Spawnable = true

ENT.PrintName = "Wooden Radio"
ENT.Category = "G-Wave Radio"
ENT.Author = "Mikey"

if SERVER then
	GWAVE.GenericDuplicatorFunction( "g-wave_radio_wooden" )
end
