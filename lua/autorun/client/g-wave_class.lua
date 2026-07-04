--- G-WAVE Handle class
GWave = GWave or {}

local function getFileDuration( filepath, callback )
  sound.PlayFile( "data/" .. filepath, "noplay 3d noblock", function( obj, errorID, errorName )
      if IsValid( obj ) then
          local duration = obj:GetLength()
          obj:Stop()
          obj = nil
          callback( duration )
      else
          callback( nil )
      end
  end )
end

local function getUrlDuration( url, callback )
  local filepath = "g-wave_cache/" .. util.SHA256( url ) .. ".dat"

  if file.Exists( filepath, "DATA" ) then
      getFileDuration( filepath, callback )
      return
  end

  http.Fetch( url, function( body )
      file.CreateDir( "g-wave_cache" )
      file.Write( filepath, body )

      getFileDuration( filepath, function( duration )
          if not duration then
              -- Return invalid cache file
              file.Delete( filepath )
              callback( nil )
              return
          end

          callback( duration )
      end )
  end )
end

local function getTitle( path )
    -- Returns the Path, Filename, and Extension as 3 values
    local _, title = string.match( path, "^(.-)([^\\/]-)(%.[^\\/%.]-)%.?$" )

    if not title then
        return path
    end

    title = string.Replace( title, "_", " " )

    return title
end

local params = [[
$smooth 1
$mips 1
]]
local function playButtonSound()
    surface.PlaySound( "buttons/lightswitch2.wav" )
end

local function playErrorSound()
    surface.PlaySound( "buttons/button10.wav" )
end

-- Global channel tracker to prevent leaks when entities are removed while dormant
GWAVE.ActiveChannels = GWAVE.ActiveChannels or {}

timer.Create( "GWave_AudioCleanup", 1, 0, function()
    for entIndex, data in pairs( GWAVE.ActiveChannels ) do
        local ent = data.ent
        local station = data.station

        if not IsValid( ent ) then
            if IsValid( station ) then
                station:Stop()
            end
            GWAVE.ActiveChannels[entIndex] = nil
        end
    end
end )

--- Opens the radio's menu (DHTML implementation — wiki.facepunch.com/gmod/DHTML)
local radioMenu = nil
function GWave.OpenRadioMenu( radio, queue )
    if IsValid( radioMenu ) then
        radioMenu:Remove()
    end

    local owner  = radio:GetDataCreator()
    local isOwner = ( owner == LocalPlayer() )
    local scrW, scrH = ScrW(), ScrH()

    -- ── Possessive title ────────────────────────────────────
    local ownerName = owner:GetName() or "Unknown"
    local frameTitle
    if string.sub( ownerName, -1 ) == "s" then
        frameTitle = ownerName .. "' Radio"
    else
        frameTitle = ownerName .. "'s Radio"
    end

    -- ── Outer DFrame (invisible chrome, used for dragging) ──
    -- Per wiki: DFrame is the standard popup container.
    -- https://wiki.facepunch.com/gmod/DFrame
    local appW = math.Clamp( scrW * 0.55, 580, 920 )
    local appH = math.Clamp( scrH * 0.62, 480, 760 )
    local pad = 24 -- CSS body padding so shadow renders safely inside frame
    local W = appW + (pad * 2)
    local H = appH + (pad * 2)

    local dframe = vgui.Create( "DFrame" )
    dframe:SetSize( W, H )
    dframe:Center()
    dframe:SetTitle( "" )
    dframe:MakePopup()
    dframe:ShowCloseButton( false )
    dframe:SetDraggable( true )
    dframe:InvalidateParent( true )
    dframe:SetScreenLock( true )
    radioMenu = dframe

    -- Transparent frame background — DHTML fills the whole area
    function dframe:Paint( w, h ) end

    -- ── DHTML panel (wiki.facepunch.com/gmod/DHTML) ─────────
    -- Set to full size rather than docking to avoid DFrame's invisible title gap
    local dhtml = vgui.Create( "DHTML", dframe )
    dhtml:SetPos( 0, 0 )
    dhtml:SetSize( W, H )
    dhtml:SetScrollbars( false )

    -- DHTML triggers native dragging perfectly pixel-accurate to CEF scaling
    dhtml:AddFunction( "gwave", "startDrag", function()
        dframe.Dragging = { gui.MouseX() - dframe.x, gui.MouseY() - dframe.y }
        dframe:MouseCapture( true )
    end )

    dframe.OnMouseReleased = function( self, code )
        self.Dragging = nil
        self:MouseCapture( false )
    end

    local function jsStr( s )
        s = tostring( s or "" )
        s = s:gsub( "\\", "\\\\" )
        s = s:gsub( "'",  "\\'" )
        s = s:gsub( "\n", "\\n" )
        s = s:gsub( "\r", "" )
        s = s:gsub( "<", "\\x3c" )
        s = s:gsub( ">", "\\x3e" )
        return s
    end

    -- ── Helper: format seconds as M:SS ──────────────────────
    local function fmtDur( secs )
        if not secs or secs <= 0 then return "--:--" end
        local m   = math.floor( secs / 60 )
        local sec = math.floor( secs % 60 )
        return string.format( "%d:%02d", m, sec )
    end

    -- ════════════════════════════════════════════════════════
    --  JS → Lua bridges  (wiki.facepunch.com/gmod/DHTML:AddFunction)
    -- ════════════════════════════════════════════════════════

    -- Close
    dhtml:AddFunction( "gwave", "close", function()
        dframe:Close()
        playButtonSound()
    end )

    -- Add URL
    dhtml:AddFunction( "gwave", "add", function( url )
        if not isOwner then return end
        getUrlDuration( url, function( duration )
            if not IsValid( dhtml ) then return end
            if duration then
                net.Start( "gwave_operation" )
                net.WriteUInt( GWAVE.OPCODES.ADD, GWAVE.OPCODECOUNT )
                net.WriteEntity( radio )
                net.WriteString( url )
                net.WriteFloat( duration )
                net.SendToServer()
                -- Optimistic UI feedback
                dhtml:Call( "window.gwaveUI.showNotice('Adding track…','info')" )
                playButtonSound()
            else
                dhtml:Call( "window.gwaveUI.showNotice('Invalid URL — stream unreachable.','error')" )
                playErrorSound()
            end
        end )
    end )

    -- Seek
    dhtml:AddFunction( "gwave", "seek", function( progress )
        local dur = radio:GetDuration()
        if not dur or dur <= 0 then return end

        local time = dur * math.Clamp( tonumber( progress ) or 0, 0, 1 )
        net.Start( "gwave_operation" )
        net.WriteUInt( GWAVE.OPCODES.TIME, GWAVE.OPCODECOUNT )
        net.WriteEntity( radio )
        net.WriteFloat( time )
        net.SendToServer()
    end )

    -- Rewind to 0
    dhtml:AddFunction( "gwave", "rewind", function()
        net.Start( "gwave_operation" )
        net.WriteUInt( GWAVE.OPCODES.TIME, GWAVE.OPCODECOUNT )
        net.WriteEntity( radio )
        net.WriteFloat( 0 )
        net.SendToServer()
        playButtonSound()
    end )

    -- Play / Pause toggle
    dhtml:AddFunction( "gwave", "playPause", function()
        net.Start( "gwave_operation" )
        if radio:GetState() == "playing" then
            net.WriteUInt( GWAVE.OPCODES.PAUSE, GWAVE.OPCODECOUNT )
        else
            net.WriteUInt( GWAVE.OPCODES.PLAY, GWAVE.OPCODECOUNT )
        end
        net.WriteEntity( radio )
        net.SendToServer()
        playButtonSound()
    end )

    -- Skip current track
    dhtml:AddFunction( "gwave", "skip", function()
        net.Start( "gwave_operation" )
        net.WriteUInt( GWAVE.OPCODES.SKIP, GWAVE.OPCODECOUNT )
        net.WriteEntity( radio )
        net.SendToServer()
        playButtonSound()
    end )

    -- Toggle loop
    dhtml:AddFunction( "gwave", "toggleLoop", function()
        if not isOwner then return end
        net.Start( "gwave_operation" )
        net.WriteUInt( GWAVE.OPCODES.LOOP, GWAVE.OPCODECOUNT )
        net.WriteEntity( radio )
        net.SendToServer()
        playButtonSound()
    end )

    -- Change Volume
    dhtml:AddFunction( "gwave", "volume", function( vol )
        if not isOwner then return end
        net.Start( "gwave_operation" )
        net.WriteUInt( GWAVE.OPCODES.VOLUME, GWAVE.OPCODECOUNT )
        net.WriteEntity( radio )
        net.WriteFloat( tonumber( vol ) or 1 )
        net.SendToServer()
    end )

    dhtml:AddFunction( "gwave", "setRadius", function( val )
        if not isOwner then return end
        net.Start( "gwave_operation" )
        net.WriteUInt( GWAVE.OPCODES.RADIUS, GWAVE.OPCODECOUNT )
        net.WriteEntity( radio )
        net.WriteFloat( tonumber( val ) or 1500 )
        net.SendToServer()
    end )

    -- Remove queue item by 1-based index
    dhtml:AddFunction( "gwave", "remove", function( idx )
        if not isOwner then return end
        idx = tonumber( idx )
        if not idx then return end
        net.Start( "gwave_operation" )
        net.WriteUInt( GWAVE.OPCODES.REMOVE, GWAVE.OPCODECOUNT )
        net.WriteEntity( radio )
        net.WriteUInt( idx, 8 )
        net.SendToServer()
        playButtonSound()
    end )

    -- ════════════════════════════════════════════════════════
    --  Lua → JS helpers
    --  dhtml:Call runs JS immediately  (wiki.facepunch.com/gmod/DHTML:Call)
    -- ════════════════════════════════════════════════════════

    -- Push the full queue table as a JS array literal and call updateQueue()
    local function pushQueue( q )
        if not IsValid( dhtml ) then return end
        local parts = {}
        for i, song in ipairs( q ) do
            local title = jsStr( getTitle( song.url ) or song.url )
            local dur   = jsStr( fmtDur( song.duration ) )
            parts[#parts+1] = string.format(
                "{idx:%d,title:'%s',dur:'%s'}",
                i, title, dur
            )
        end
        local jsArr = "[" .. table.concat( parts, "," ) .. "]"
        dhtml:Call( "window.gwaveUI.updateQueue(" .. jsArr .. ")" )
    end

    -- Push now-playing info
    local function pushNowPlaying()
        if not IsValid( dhtml ) then return end
        local url = radio:GetURL() or ""
        url = string.gsub( url, "%|.*$", "" )
        local title    = ( url ~= "" ) and jsStr( getTitle( url ) ) or "Nothing playing"
        local subtitle = ( url ~= "" ) and "Now Streaming" or "Queue is empty"
        dhtml:Call( string.format(
            "window.gwaveUI.setNowPlaying('%s','%s')",
            title, subtitle
        ) )
    end

    -- Push playback state ("playing" | "paused" | "stopped")
    local function pushState( state )
        if not IsValid( dhtml ) then return end
        dhtml:Call( string.format( "window.gwaveUI.setState('%s')", jsStr( state ) ) )
    end

    -- Push progress 0–1
    local function pushProgress( prog )
        if not IsValid( dhtml ) then return end
        dhtml:Call( string.format( "window.gwaveUI.setProgress(%f)", prog ) )
    end

    -- Push volume 0–1
    local function pushVolume( vol )
        if not IsValid( dhtml ) then return end
        dhtml:Call( string.format( "window.gwaveUI.setVolume(%f)", vol ) )
    end

    -- Push looping
    local function pushLooping( isLooping )
        if not IsValid( dhtml ) then return end
        dhtml:Call( string.format( "window.gwaveUI.setLooping(%s)", isLooping and "true" or "false" ) )
    end

    -- ════════════════════════════════════════════════════════
    --  Think hook — ticks state/progress into HTML each frame
    -- ════════════════════════════════════════════════════════
    local lastState   = ""
    local lastURL     = ""
    local prevQueueSz = -1

    hook.Add( "Think", "GWave_DHMLTick_" .. tostring( dframe ), function()
        if not IsValid( dframe ) then
            hook.Remove( "Think", "GWave_DHMLTick_" .. tostring( dframe ) )
            return
        end
        if not IsValid( radio ) then return end
        -- State change
        local state = radio:GetState() or "stopped"
        if state ~= lastState then
            pushState( state )
            lastState = state
        end

        -- Now-playing change
        local url = radio:GetURL() or ""
        if url ~= lastURL then
            pushNowPlaying()
            lastURL = url
        end

        -- Queue change (server-pushed)
        if radio._queueChanged then
            pushQueue( radio._queue or {} )
            radio._queueChanged = false
            prevQueueSz = #( radio._queue or {} )
        end

        -- Progress bar
        local ch   = radio._AudioChannel
        local prog = 0
        if IsValid( ch ) then
            local dur = radio:GetDuration()
            if dur and dur > 0 then
                prog = math.Clamp( ch:GetTime() / dur, 0, 1 )
            end
        end
        pushProgress( prog )

        -- Volume sync
        local vol = radio:GetRadioVolume() or 1
        if vol ~= radio._lastPushedVol then
            pushVolume( vol )
            radio._lastPushedVol = vol
        end

        -- Looping sync
        local isLooping = radio:GetLooping() or false
        if isLooping ~= radio._lastPushedLooping then
            pushLooping( isLooping )
            radio._lastPushedLooping = isLooping
        end

        -- Sync time display
        local elapsed = radio:GetElapsedTime()
        if elapsed ~= radio._lastPushedTime then
            dhtml:Call( string.format( "window.gwaveUI.updateTime('%s')", fmtDur( elapsed ) ) )
            radio._lastPushedTime = elapsed
        end

        -- Radius sync
        local radius = radio:GetRadius() or 1500
        if radius ~= radio._lastPushedRadius then
            dhtml:Call( string.format( "window.gwaveUI.setRadius(%f)", radius ) )
            radio._lastPushedRadius = radius
        end
    end )

    -- Clean up Think hook when frame is closed
    dframe.OnClose = function( self )
        hook.Remove( "Think", "GWave_DHMLTick_" .. tostring( self ) )
    end

    -- ════════════════════════════════════════════════════════
    --  HTML + CSS + JS  (Sonic Curator design)
    -- ════════════════════════════════════════════════════════
    local isOwnerStr = isOwner and "true" or "false"

    -- Build initial queue JSON for inline bootstrap
    local initQueueParts = {}
    for i, song in ipairs( queue ) do
        local title = jsStr( getTitle( song.url ) or song.url )
        local dur   = jsStr( fmtDur( song.duration ) )
        initQueueParts[#initQueueParts+1] = string.format(
            "{idx:%d,title:'%s',dur:'%s'}", i, title, dur
        )
    end
    local initQueueJS = "[" .. table.concat( initQueueParts, "," ) .. "]"

    local initURL = radio:GetURL() or ""
    initURL = string.gsub( initURL, "%|.*$", "" )
    local initTitle    = ( initURL ~= "" ) and getTitle( initURL ) or "Nothing playing"
    local initSubtitle = ( initURL ~= "" ) and "Now Streaming" or "Queue is empty"
    local initState    = jsStr( radio:GetState() or "stopped" )
    local initOwner    = frameTitle
    local initVolume   = radio:GetRadioVolume() or 1
    local initLooping  = radio:GetLooping() and "true" or "false"

    dhtml:SetHTML( [[<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>G-Wave Radio</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Inter:wght@400;500&display=swap" rel="stylesheet">
<style>
.icon {
  display: inline-block;
  width: 1.2em;
  height: 1.2em;
  background-color: currentColor;
  -webkit-mask-size: contain;
  mask-size: contain;
  -webkit-mask-repeat: no-repeat;
  mask-repeat: no-repeat;
  -webkit-mask-position: center;
  mask-position: center;
  vertical-align: -0.125em;
}
.icon-radio { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/radio.png'); }
.icon-xmark { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/xmark.png'); }
.icon-plus { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/plus.png'); }
.icon-backward-step { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/backward-step.png'); }
.icon-play { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/play.png'); }
.icon-pause { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/pause.png'); }
.icon-forward-step { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/forward-step.png'); }
.icon-repeat { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/repeat.png'); }
.icon-volume-high { -webkit-mask-image: url('asset://garrysmod/materials/vgui/icons/volume-high.png'); }
.icon-gear { -webkit-mask-image: url('asset://garrysmod/materials/icon16/cog.png'); }
.icon-arrow-left { -webkit-mask-image: url('asset://garrysmod/materials/icon16/arrow_left.png'); }
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0;}
:root{
  --background: #0e0e0e;
  --foreground: #ffffff;
  --card: #131313;
  --card-foreground: #ffffff;
  --primary: #9D50BB;
  --primary-foreground: #ffffff;
  --primary-hover: #c87ce6;
  --secondary: #131313;
  --secondary-foreground: #ffffff;
  --muted: #131313;
  --muted-foreground: #adaaaa;
  --accent: #262626;
  --accent-foreground: #ffffff;
  --destructive: #dc5050;
  --destructive-foreground: #ffffff;
  --border: #262626;
  --input: #262626;
  --ring: #9D50BB;
  --radius: 0.5rem;
}
* {
  user-select:none;
}
*:focus {
  outline:none;
}
html,body{
  width:100%;height:100%;
  padding:24px;
  box-sizing:border-box;
  background:transparent;
  color:var(--foreground);
  font-family:'Inter',sans-serif;
  overflow:hidden;
  user-select:none;
}
#app{
  display:flex;
  flex-direction:column;
  height:100%;
  background:var(--background);
  border:1px solid var(--border);
  border-radius:var(--radius);
  overflow:hidden;
  box-shadow:0 12px 12px rgba(0,0,0,0.85);
}
/* ── Header ── */
#header{
  display:flex;
  align-items:center;
  gap:12px;
  padding:0 16px;
  height:56px;
  flex-shrink:0;
  border-bottom:1px solid var(--border);
  background:var(--background);
  cursor:move;
}
#header-text { pointer-events:none; }
#header-icon{
  display:flex;align-items:center;justify-content:center;
  width:24px;height:24px;
  border-radius:4px;
  background: transparent;
  color:var(--primary-foreground);
  font-size:12px;
}

.icon-radio {
  width: 4em;
  height: 4em;
}

.icon-volume-high {
  width: 2em;
  height: 2em;
}

#header-text{display:flex;flex-direction:column;flex:1;justify-content:center;}
#header-title{font-size:14px;font-weight:600;color:var(--foreground);}
#header-super{font-size:12px;color:var(--muted-foreground);}
#close-btn{
  height:32px;width:32px;
  border-radius:calc(var(--radius) - 2px);
  border:none;
  background:transparent;
  color:var(--muted-foreground);
  font-size:14px;
  cursor:pointer;
  display:flex;align-items:center;justify-content:center;
  transition:background-color 0.2s,color 0.2s;
}
#close-btn:hover{background:var(--accent);color:var(--accent-foreground);}

/* ── URL row ── */
#url-row{
  display:flex;
  gap:8px;
  padding:16px 16px 0;
  flex-shrink:0;
}
#url-input{
  flex:1;
  height:36px;
  background:var(--background);
  border:1px solid var(--input);
  border-radius:calc(var(--radius) - 2px);
  padding:0 12px;
  color:var(--foreground);
  font-family:'Inter',sans-serif;
  font-size:14px;
  outline:none;
  transition:border-color 0.2s,box-shadow 0.2s;
}
#url-input::placeholder{color:var(--muted-foreground);}
#url-input:focus-visible{
  outline:none;
  border-color:var(--ring);
  box-shadow:0 0 0 1px var(--ring);
}
#add-btn{
  display:inline-flex;align-items:center;justify-content:center;
  height:36px;width:44px;
  border-radius:calc(var(--radius) - 2px);
  border:none;
  background:var(--primary);
  color:var(--primary-foreground);
  font-size:14px;font-weight:500;
  cursor:pointer;
  transition:background-color 0.2s;
  box-shadow:0 1px 2px rgba(0,0,0,0.05);
}
#add-btn:hover{background:rgba(157, 80, 187, 0.9);} /* Primary/90 */

/* ── Notice bar ── */
#notice{
  margin:12px 16px 0;
  padding:12px 16px;
  border-radius:calc(var(--radius) - 2px);
  border:1px solid var(--border);
  font-size:14px;font-family:'Inter',sans-serif;
  display:none;
  background:var(--card);
}
#notice.info{border-color:var(--border);color:var(--foreground);}
#notice.error{border-color:var(--destructive);color:var(--destructive);}

/* ── Queue section ── */
#queue-section{
  flex:1;
  display:flex;
  flex-direction:column;
  min-height:0;
  padding:16px;
}
#queue-label{
  font-size:14px;font-weight:600;
  color:var(--foreground);
  margin-bottom:12px;
  padding-bottom:12px;
  border-bottom:1px solid var(--border);
}
#queue-list{
  flex:1;
  overflow-y:auto;
  overflow-x:hidden;
  scrollbar-width:thin;
  scrollbar-color:var(--border) transparent;
  display:flex;
  flex-direction:column;
  gap:4px;
}
#queue-list::-webkit-scrollbar{width:6px;}
#queue-list::-webkit-scrollbar-thumb{background:var(--border);border-radius:3px;}
/* empty state */
#queue-empty{
  padding:32px 0;
  text-align:center;
  color:var(--muted-foreground);
  font-size:14px;
}
/* queue row */
.q-row{
  display:flex;
  align-items:center;
  gap:12px;
  padding:8px 12px;
  border-radius:calc(var(--radius) - 2px);
  border:1px solid transparent;
  background:transparent;
  transition:background-color 0.2s,border-color 0.2s;
}
.q-row:hover{background:var(--accent);}
.q-row.first-track{
  background:var(--card);
  border:1px solid var(--border);
}
.q-num{
  min-width:24px;
  text-align:center;
  font-size:12px;
  font-weight:500;
  color:var(--muted-foreground);
}
.q-row.first-track .q-num{color:var(--foreground);}
.q-info{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px;}
.q-title{
  font-size:14px;font-weight:500;
  color:var(--foreground);
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;
}
.q-dur{
  font-size:12px;color:var(--muted-foreground);
}
.q-del{
  height:28px;width:28px;
  border-radius:calc(var(--radius) - 2px);
  border:none;
  background:transparent;
  color:var(--muted-foreground);
  font-size:14px;
  cursor:pointer;
  display:flex;align-items:center;justify-content:center;
  transition:background-color 0.2s,color 0.2s;
  opacity:0;
}
.q-row:hover .q-del{opacity:1;}
.q-del:hover{background:var(--destructive);color:var(--destructive-foreground);}

/* ── Views ── */
.view-pane { display:flex; flex-direction:column; flex:1; min-height:0; }
.hidden { display:none !important; }
#settings-view { padding: 16px; }
.setting-row { display:flex; flex-direction:column; gap:8px; margin-bottom:24px; }
.setting-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:4px; }
.setting-label { font-size:14px; font-weight:600; color:var(--foreground); }
.setting-val { font-size:12px; color:var(--primary); font-family:monospace; }
.setting-help { font-size:12px; color:var(--muted-foreground); line-height:1.4; }

#player-timer {
  font-family: 'Inter', monospace;
  font-size: 13px;
  font-weight: 600;
  color: var(--muted-foreground);
  margin-left: 10px;
  min-width: 40px;
}

/* ── Player bar ── */
#player{
  flex-shrink:0;
  display:flex;
  flex-direction:column;
  background:var(--background);
  border-top:1px solid var(--border);
  height:80px;
}
/* progress bar */
#progress{
  position:relative;
  height:6px;
  background:var(--muted);
  width:100%;
  cursor:pointer;
  transition:height 0.1s;
}
#progress-fill{
  position:relative;
  height:100%;
  width:0%;
  background:var(--primary);
  /*transition:width 0.2s linear;*/
  pointer-events:none;
}
#progress-fill::after{
  content:"";
  position:absolute;
  top:50%;
  right:0;
  width:16px;
  height:16px;
  background:var(--primary);
  border-radius:50%;
  transform:translate(50%, -50%) scale(0);
  transition:transform 0.1s ease;
  box-shadow: 0 0 4px rgba(0,0,0,0.5);
}

#progress:hover #progress-fill::after{
  transform:translate(50%, -50%) scale(1);
  background: var(--primary-hover);
}

#progress:hover #progress-fill{
  background: var(--primary-hover);
}

#player-inner{
  flex:1;
  display:flex;
  align-items:center;
  padding:0 24px;
  justify-content:space-between;
}
/* now-playing */
#now-playing{
  flex:1;
  display:flex;
  flex-direction:column;
  gap:2px;
  min-width:0;
}
#np-title{
  font-size:14px;font-weight:600;
  color:var(--foreground);
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;
}
#np-sub{
  font-size:12px;
  color:var(--muted-foreground);
}
/* transport controls */
#transport{
  display:flex;
  align-items:center;
  justify-content:center;
  gap:16px;
  flex:1;
}
.t-btn{
  border:none;
  background:transparent;
  cursor:pointer;
  display:flex;align-items:center;justify-content:center;
  transition:transform 0.1s,background-color 0.2s,color 0.2s;
}
.t-btn.sm{
  width:36px;height:36px;
  border-radius:50%;
  background:rgba(255,255,255,0.08);
  color:var(--foreground);
  font-size:14px;
}
.t-btn.sm:hover{
  background:rgba(255,255,255,0.15);
  transform:scale(1.05);
}
.t-btn.sm:active{
  transform:scale(0.95);
}
#play-btn{
  width:40px;height:40px;
  border-radius:50%;
  background:var(--foreground);
  color:var(--background);
  font-size:16px;
  transition:transform 0.1s,background-color 0.2s;
  display:flex;align-items:center;justify-content:center;
}
#play-btn:hover{
  background:var(--muted-foreground);
  color:var(--background);
  transform:scale(1.05);
}
#play-btn:active{transform:scale(0.95);}

/* Volume Slider */
#vol-container {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 8px;
}
input[type=range] {
  -webkit-appearance: none;
  width: 80px;
  background: var(--muted);
  height: 4px;
  border-radius: 2px;
  outline: none;
}
input[type=range]::-webkit-slider-thumb {
  -webkit-appearance: none;
  height: 12px;
  width: 12px;
  border-radius: 50%;
  background: var(--primary);
  cursor: pointer;
  margin-top: -4px;
}
input[type=range]::-webkit-slider-runnable-track {
  width: 100%;
  height: 4px;
  cursor: pointer;
  background: transparent;
  border-radius: 2px;
}
input[type=range]:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
input[type=range]:disabled::-webkit-slider-thumb {
  background: var(--muted-foreground);
  cursor: not-allowed;
}
</style>
</head>
<body>
<div id="app">

  <!-- Header -->
  <div id="header" onmousedown="if(event.button===0){gwave.startDrag();}">
    <div id="header-icon"><i class="icon icon-radio"></i></div>
    <div id="header-text">
      <span id="header-title">]] .. initOwner .. [[</span>
    </div>
    <button id="settings-btn" class="t-btn sm" style="background:transparent; margin-right:4px;" onmousedown="event.stopPropagation();" onclick="window.gwaveUI.toggleSettings()" title="Settings"><i class="icon icon-gear"></i></button>
    <button id="close-btn" onmousedown="event.stopPropagation();" onclick="gwave.close()" title="Close"><i class="icon icon-xmark"></i></button>
  </div>

  <!-- Main View Container -->
  <div id="main-view" class="view-pane">
    <!-- URL row -->
    <div id="url-row">
      <input id="url-input" type="text" placeholder="Paste a stream URL..."
             onkeydown="if(event.key==='Enter'){gwave.add(this.value);this.value='';}">
      <button id="add-btn" onclick="gwave.add(document.getElementById('url-input').value);document.getElementById('url-input').value='';" title="Add to queue"><i class="icon icon-plus"></i></button>
    </div>

    <!-- Notice bar -->
    <div id="notice"></div>

    <!-- Queue -->
    <div id="queue-section">
      <div id="queue-label">Queue</div>
      <div id="queue-list">
        <div id="queue-empty">No tracks in queue</div>
      </div>
    </div>
  </div>

  <!-- Settings View Container -->
  <div id="settings-view" class="view-pane hidden">
    <div id="queue-label" style="display:flex; align-items:center; gap:8px;">
        Settings
    </div>
    <div id="settings-list" style="flex:1; overflow-y:auto;">
        <!-- Range Setting -->
        <div class="setting-row">
            <div class="setting-header">
                <span class="setting-label">Playback Range</span>
                <span id="radius-val" class="setting-val">1500u</span>
            </div>
            <input type="range" id="radius-slider" min="100" max="5000" step="50" style="width:100%;">
            <span class="setting-help">How far away players can be before the audio cuts out.</span>
        </div>

        <!-- Future settings can be added here -->
    </div>
  </div>

  <!-- Player bar -->
  <div id="player">
    <div id="progress" onclick="if(window.gwave && gwave.seek){ gwave.seek((event.clientX - this.getBoundingClientRect().left) / this.getBoundingClientRect().width); }"><div id="progress-fill"></div></div>
    <div id="player-inner">
      <div id="now-playing">
        <div id="np-sub">]] .. initSubtitle .. [[</div>
        <div id="np-title">]] .. initTitle .. [[</div>
      </div>
      <div id="transport">
        <button class="t-btn sm" onclick="gwave.rewind()" title="Rewind"><i class="icon icon-backward-step"></i></button>
        <button id="play-btn" class="t-btn lg" onclick="gwave.playPause()" title="Play / Pause"><i class="icon icon-play"></i></button>
        <button class="t-btn sm" onclick="gwave.skip()" title="Skip"><i class="icon icon-forward-step"></i></button>
        <button id="loop-btn" class="t-btn sm" onclick="gwave.toggleLoop()" title="Loop Track"><i class="icon icon-repeat"></i></button>
        <span id="player-timer">00:00</span>
      </div>
      <div style="flex:0 0 36%; padding-right:16px;" id="vol-container">
        <i class="icon icon-volume-high" style="color:var(--muted-foreground); font-size:12px; cursor:pointer;" onclick="if(IS_OWNER) window.gwaveUI.toggleMute();"></i>
        <input type="range" id="vol-slider" min="0" max="1" step="0.01">
      </div>
    </div>
  </div>

</div>
<script>
// ── Owner flag injected from Lua ───────────────────────────
var IS_OWNER = ]] .. isOwnerStr .. [[;

// ── UI helpers called from Lua via DHTML:Call ──────────────
// Kept separate from window.gwave (the Lua bridge created by AddFunction)
// so we do NOT overwrite the Lua-registered functions.
window.gwaveUI = {

  updateQueue: function(tracks) {
    var list = document.getElementById('queue-list');
    var empty = document.getElementById('queue-empty');
    // Clear old rows but keep the empty placeholder
    var rows = list.querySelectorAll('.q-row');
    rows.forEach(function(r){ r.remove(); });

    if (!tracks || tracks.length === 0) {
      empty.style.display = '';
      return;
    }
    empty.style.display = 'none';

    tracks.forEach(function(t) {
      var row = document.createElement('div');
      row.className = 'q-row' + (t.idx === 1 ? ' first-track' : '');

      var numSpan = document.createElement('span');
      numSpan.className = 'q-num ' + (t.idx === 1 ? 'first' : 'other');
      numSpan.textContent = t.idx;

      var info = document.createElement('div');
      info.className = 'q-info';

      var title = document.createElement('div');
      title.className = 'q-title ' + (t.idx === 1 ? 'first' : 'other');
      title.textContent = t.title;

      var dur = document.createElement('div');
      dur.className = 'q-dur';
      dur.textContent = t.dur;

      info.appendChild(title);
      info.appendChild(dur);
      row.appendChild(numSpan);
      row.appendChild(info);

      if (IS_OWNER) {
        var del = document.createElement('button');
        del.className = 'q-del';
        del.title = 'Remove';
        del.innerHTML = '&#x2715;';
        (function(idx){ del.onclick = function(){ gwave.remove(idx); }; })(t.idx);
        row.appendChild(del);
      }

      list.appendChild(row);
    });
  },

  setNowPlaying: function(title, sub) {
    document.getElementById('np-title').textContent = title;
    document.getElementById('np-sub').textContent   = sub;
  },

  updateTime: function(formattedTime) {
    var el = document.getElementById('player-timer');
    if (el) el.textContent = formattedTime;
  },

  setState: function(state) {
    var icon = document.querySelector('#play-btn i');
    if (!icon) return;
    if (state === 'playing') {
      icon.classList.remove('icon-play');
      icon.classList.add('icon-pause');
    } else {
      icon.classList.remove('icon-pause');
      icon.classList.add('icon-play');
    }
  },

  setProgress: function(frac) {
    document.getElementById('progress-fill').style.width = (frac * 100) + '%';
  },

  setVolume: function(vol) {
    if (this.sliders && this.sliders.volume) {
        this.sliders.volume.setValue(vol);
    }
  },

  updateVolSliderBg: function(el) {
    // Legacy support, now handled by GWaveSlider
  },

  toggleMute: function() {
    if (!IS_OWNER || !window.gwave || !gwave.volume) return;
    var s = document.getElementById('vol-slider');
    var current = parseFloat(s.value);
    if (current > 0) {
      this._lastVol = current;
      gwave.volume(0);
      s.value = 0;
    } else {
      var restore = this._lastVol || 1;
      gwave.volume(restore);
      s.value = restore;
    }
    this.updateVolSliderBg(s);
  },

  showNotice: function(msg, type) {
    var el = document.getElementById('notice');
    el.textContent = msg;
    el.className = type || 'info';
    el.style.display = 'block';
    el.style.opacity = '1';
    clearTimeout(window._noticeTimer);
    window._noticeTimer = setTimeout(function(){
      el.style.opacity = '0';
      setTimeout(function(){ el.style.display='none'; el.style.opacity='1'; }, 300);
    }, 3000);
  },

  setLooping: function(isLooping) {
    var btn = document.getElementById('loop-btn');
    if (!btn) return;
    if (isLooping) {
      btn.style.color = 'var(--primary)';
    } else {
      btn.style.color = 'var(--foreground)';
    }
  },

  toggleSettings: function() {
    var main = document.getElementById('main-view');
    var settings = document.getElementById('settings-view');
    var btn = document.querySelector('#settings-btn i');

    if (settings.classList.contains('hidden')) {
        settings.classList.remove('hidden');
        main.classList.add('hidden');
        btn.classList.remove('icon-gear');
        btn.classList.add('icon-arrow-left');
    } else {
        settings.classList.add('hidden');
        main.classList.remove('hidden');
        btn.classList.remove('icon-arrow-left');
        btn.classList.add('icon-gear');
    }
  },

  setRadius: function(val) {
    if (this.sliders && this.sliders.radius) {
        this.sliders.radius.setValue(val);
    }
  },

  updateRadiusDisplay: function(val) {
    // Legacy support, now handled by GWaveSlider
  },

  _noop: function() {}
};

// ── Reusable Slider Class ──────────────────────────────────
class GWaveSlider {
    constructor(id, options = {}) {
        this.el = document.getElementById(id);
        if (!this.el) return;

        this.onUserChange = options.onUserChange || function(){};
        this.onUserInput  = options.onUserInput  || function(){};
        this.displayEl    = options.displayId ? document.getElementById(options.displayId) : null;
        this.unit         = options.unit || '';

        // Visual update on drag
        this.el.addEventListener('input', () => {
            this.updateBackground();
            if (this.displayEl) this.displayEl.textContent = this.el.value + this.unit;
            this.onUserInput(this.el.value);
        });

        // Networking update on release
        this.el.addEventListener('change', () => {
             if (IS_OWNER) this.onUserChange(this.el.value);
        });

        this.updateBackground();
    }

    updateBackground() {
        const min = parseFloat(this.el.min || 0);
        const max = parseFloat(this.el.max || 1);
        const val = ((parseFloat(this.el.value || 0) - min) / (max - min)) * 100;
        this.el.style.background = 'linear-gradient(to right, var(--primary) ' + val + '%, var(--muted) ' + val + '%)';
    }

    setValue(val) {
        if (document.activeElement === this.el) return;
        this.el.value = val;
        this.updateBackground();
        if (this.displayEl) this.displayEl.textContent = val + this.unit;
    }
}

// ── Bootstrap initial state ────────────────────────────────
window.gwaveUI.sliders = {
    volume: new GWaveSlider('vol-slider', {
        onUserChange: (v) => gwave.volume(v)
    }),
    radius: new GWaveSlider('radius-slider', {
        displayId: 'radius-val',
        onUserChange: (v) => gwave.setRadius(v)
    })
};

window.gwaveUI.updateQueue(]] .. initQueueJS .. [[);
window.gwaveUI.setState(']] .. initState .. [[');
window.gwaveUI.setLooping(]] .. initLooping .. [[);

window.gwaveUI.sliders.volume.setValue(]] .. initVolume .. [[);
window.gwaveUI.sliders.radius.setValue(]] .. ( radio:GetRadius() or 1500 ) .. [[);

if (!IS_OWNER) {
    document.getElementById('vol-slider').disabled = true;
    document.getElementById('radius-slider').disabled = true;
    document.getElementById('settings-btn').style.display = 'none';
}
</script>
</body>
</html>]] )

    -- Sync queue changes driven by gwave_syncqueue net message
    -- (the Think hook handles _queueChanged flag set by the net receiver)
end

net.Receive( "gwave_openmenu", function()
    local radio = net.ReadEntity()
    if not IsValid( radio ) then return end

    local count = net.ReadUInt( 16 )
    local queue = {}
    for i = 1, count do
        table.insert( queue, { url = net.ReadString(), duration = net.ReadFloat() } )
    end
    GWave.OpenRadioMenu( radio, queue )
end )

net.Receive( "gwave_syncqueue", function()
    local radio = net.ReadEntity()
    if not IsValid( radio ) then return end

    local count = net.ReadUInt( 16 )
    local queue = {}
    for i = 1, count do
        table.insert( queue, { url = net.ReadString(), duration = net.ReadFloat() } )
    end
    radio._queue = queue
    radio._queueChanged = true
end )
