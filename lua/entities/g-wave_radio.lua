AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "#g-wave_radio"
ENT.Author = "Mikey"
ENT.Category = "#g-wave_radio"

ENT.Spawnable = true

if CLIENT then
    language.Add( "g-wave_radio", "G-Wave Radio" )
end

function ENT:Initialize()
    self:SetModel( "models/g-wave_radio/radio.mdl" )
    if SERVER then
        self:PhysicsInit( SOLID_VPHYSICS )
        self:SetUseType( SIMPLE_USE )
        self:SetSkin( math.random( 0, self:SkinCount() - 1 ) )
    end
end

function ENT:Use( activator )
    if not IsValid( activator ) or not activator:IsPlayer() then return end
    self:OpenRadioMenu( activator )
end

function ENT:OpenRadioMenu( ply )
    net.Start( "GWave_OpenRadioMenu" )
    net.WriteEntity( self )
    net.Send( ply )
end

function ENT:OnRemove()
    if CLIENT then
        self._radioObj:Remove()
    end
end

function ENT:Draw()
    self:MarkShadowAsDirty() -- Makes the shadow scale with the model
    self:DrawModel()
end

function ENT:SpawnFunction( ply, tr )
    if not tr.Hit then return end
    
    local ent = ents.Create( "g-wave_radio" )
    ent:Spawn()
    ent:Activate()

    ent:SetAngles( Angle( 0, ply:EyeAngles()[2] - 90, 0 ) )
    local min, max = ent:WorldSpaceAABB()
    local offset = tr.HitNormal
    offset = offset * ( max - min ) * 0.5

    ent:SetPos( tr.HitPos + offset )

    ent:PhysWake()

    return ent
end