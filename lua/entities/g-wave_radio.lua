AddCSLuaFile()

ENT.Base = "base_g-wave_radio"
ENT.Model = "models/g-wave_radio/radio.mdl"
ENT.AngleOffset = 90
ENT.Spawnable = true

ENT.PrintName = "Radio"
ENT.Category = "G-Wave Radio"
ENT.Author = "Mikey"

if SERVER then
	GWAVE.GenericDuplicatorFunction( "g-wave_radio" )
end
