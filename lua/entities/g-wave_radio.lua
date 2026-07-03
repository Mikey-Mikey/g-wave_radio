AddCSLuaFile()

ENT.Base = "base_g-wave_radio"
ENT.Model = "models/g-wave_radio/radio.mdl"
ENT.Spawnable = true

ENT.PrintName = "G-Wave Radio"
ENT.Category = "G-Wave Radio"
ENT.Author = "Mikey"

if SERVER then
	GWAVE.GenericDuplicatorFunction( "g-wave_radio" )
end
