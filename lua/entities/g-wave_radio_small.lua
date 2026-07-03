AddCSLuaFile()

ENT.Base = "base_g-wave_radio"
ENT.Model = "models/props/cs_office/radio.mdl"
ENT.Spawnable = true

ENT.PrintName = "Small Radio"
ENT.Category = "G-Wave Radio"
ENT.Author = "Mikey"

if SERVER then
	GWAVE.GenericDuplicatorFunction( "g-wave_radio_small" )
end
