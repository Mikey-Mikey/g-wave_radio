AddCSLuaFile()

ENT.Base = "base_g-wave_radio"
ENT.Model = "models/props/de_inferno/hr_i/inferno_vintage_radio/inferno_vintage_radio.mdl"
ENT.Spawnable = true

ENT.PrintName = "Vintage Radio"
ENT.Category = "G-Wave Radio"
ENT.Author = "Mikey"

if SERVER then
	GWAVE.GenericDuplicatorFunction( "g-wave_radio_vintage" )
end
