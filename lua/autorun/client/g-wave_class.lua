--- G-WAVE Handle class
GWave = GWave or {}

local function getUrlDuration( url, callback )
    sound.PlayURL( url, "noplay 3d noblock", function( obj, errorID, errorName )
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
local btnSnd
local errSnd
if IsValid( game.GetWorld() ) then
    btnSnd = CreateSound( game.GetWorld(), "buttons/lightswitch2.wav" )
    btnSnd:SetSoundLevel( 0 )

    errSnd = CreateSound( game.GetWorld(), "buttons/button10.wav" )
    errSnd:SetSoundLevel( 0 )
end

hook.Add( "InitPostEntity", "InitClient", function()
    btnSnd = CreateSound( game.GetWorld(), "buttons/lightswitch2.wav" )
    btnSnd:SetSoundLevel( 0 )
    
    errSnd = CreateSound( game.GetWorld(), "buttons/button10.wav" )
    errSnd:SetSoundLevel( 0 )
end )

local function playButtonSound()
    btnSnd:Stop()
    btnSnd:Play()
    btnSnd:ChangePitch( 200 )
end

local function playErrorSound()
    errSnd:Stop()
    errSnd:Play()
    errSnd:ChangePitch( 125 )
end

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
    local W = math.Clamp( scrW * 0.55, 580, 920 )
    local H = math.Clamp( scrH * 0.62, 480, 760 )

    local dframe = vgui.Create( "DFrame" )
    dframe:SetSize( W, H )
    dframe:Center()
    dframe:SetTitle( "" )
    dframe:MakePopup()
    dframe:ShowCloseButton( false )
    dframe:SetDraggable( true )
    dframe:InvalidateParent( true )
    radioMenu = dframe

    -- Transparent frame background — DHTML fills the whole area
    function dframe:Paint( w, h ) end

    -- ── DHTML panel (wiki.facepunch.com/gmod/DHTML) ─────────
    -- Docked FILL so it covers the entire DFrame client area.
    local dhtml = vgui.Create( "DHTML", dframe )
    dhtml:Dock( FILL )
    dhtml:SetScrollbars( false )   -- wiki.facepunch.com/gmod/DHTML:SetScrollbars

    -- ── Helper: escape a string for safe JS single-quote literal ──
    local function jsStr( s )
        s = tostring( s or "" )
        s = s:gsub( "\\", "\\\\" )
        s:gsub( "'",  "\\'" )
        s = s:gsub( "\n", "\\n" )
        s = s:gsub( "\r", "" )
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
        net.WriteFloat( radio._AudioChannel and radio._AudioChannel:GetTime() or 0 )
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

    -- Change Volume
    dhtml:AddFunction( "gwave", "volume", function( vol )
        if not isOwner then return end
        net.Start( "gwave_operation" )
        net.WriteUInt( GWAVE.OPCODES.VOLUME, GWAVE.OPCODECOUNT )
        net.WriteEntity( radio )
        net.WriteFloat( tonumber( vol ) or 1 )
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
    local initTitle    = ( initURL ~= "" ) and jsStr( getTitle( initURL ) ) or "Nothing playing"
    local initSubtitle = ( initURL ~= "" ) and "Now Streaming" or "Queue is empty"
    local initState    = jsStr( radio:GetState() or "stopped" )
    local initOwner    = jsStr( frameTitle )
    local initVolume   = radio:GetRadioVolume() or 1

    dhtml:SetHTML( [[<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>G-Wave Radio</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Inter:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0;}
:root{
  --background: #0e0e0e;
  --foreground: #ffffff;
  --card: #131313;
  --card-foreground: #ffffff;
  --primary: #9D50BB;
  --primary-foreground: #ffffff;
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
html,body{
  width:100%;height:100%;
  background:transparent;
  color:var(--foreground);
  font-family:'Inter',sans-serif;
  overflow:hidden;
  user-select:none;
}
#app{
  display:flex;
  flex-direction:column;
  height:100vh;
  background:var(--background);
  border:1px solid var(--border);
  border-radius:var(--radius);
  overflow:hidden;
  box-shadow:0 10px 15px -3px rgba(0,0,0,0.5),0 4px 6px -4px rgba(0,0,0,0.5);
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
}
#header-icon{
  display:flex;align-items:center;justify-content:center;
  width:24px;height:24px;
  border-radius:4px;
  background:var(--primary);
  color:var(--primary-foreground);
  font-size:12px;
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
#progress:hover{
  height:10px;
}
#progress-fill{
  position:relative;
  height:100%;
  width:0%;
  background:var(--primary);
  transition:width 0.2s linear;
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
  color:var(--muted-foreground);
  transition:color 0.2s;
  font-size:16px;
}
.t-btn:hover{color:var(--foreground);}
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
  <div id="header">
    <div id="header-icon"><i class="fa-solid fa-radio"></i></div>
    <div id="header-text">
      <span id="header-title">]] .. initOwner .. [[</span>
      <span id="header-super">Radio Station</span>
    </div>
    <button id="close-btn" onclick="gwave.close()" title="Close"><i class="fa-solid fa-xmark"></i></button>
  </div>

  <!-- URL row -->
  <div id="url-row">
    <input id="url-input" type="text" placeholder="Paste a stream URL..."
           onkeydown="if(event.key==='Enter'){gwave.add(this.value);this.value='';}">
    <button id="add-btn" onclick="gwave.add(document.getElementById('url-input').value);document.getElementById('url-input').value='';" title="Add to queue"><i class="fa-solid fa-plus"></i></button>
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

  <!-- Player bar -->
  <div id="player">
    <div id="progress" onclick="if(window.gwave && gwave.seek){ gwave.seek((event.clientX - this.getBoundingClientRect().left) / this.getBoundingClientRect().width); }"><div id="progress-fill"></div></div>
    <div id="player-inner">
      <div id="now-playing">
        <div id="np-sub">]] .. initSubtitle .. [[</div>
        <div id="np-title">]] .. initTitle .. [[</div>
      </div>
      <div id="transport">
        <button class="t-btn sm" onclick="gwave.rewind()" title="Rewind"><i class="fa-solid fa-backward-step"></i></button>
        <button id="play-btn" class="t-btn lg" onclick="gwave.playPause()" title="Play / Pause"><i class="fa-solid fa-play"></i></button>
        <button class="t-btn sm" onclick="gwave.skip()" title="Skip"><i class="fa-solid fa-forward-step"></i></button>
      </div>
      <div style="flex:0 0 36%; padding-right:16px;" id="vol-container">
        <i class="fa-solid fa-volume-high" style="color:var(--muted-foreground); font-size:12px;"></i>
        <input type="range" id="vol-slider" min="0" max="1" step="0.01" oninput="if(IS_OWNER && window.gwave && gwave.volume){gwave.volume(this.value);} window.gwaveUI.updateVolSliderBg(this);">
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

  setState: function(state) {
    var icon = document.querySelector('#play-btn i');
    if (!icon) return;
    if (state === 'playing') {
      icon.classList.remove('fa-play');
      icon.classList.add('fa-pause');
    } else {
      icon.classList.remove('fa-pause');
      icon.classList.add('fa-play');
    }
  },

  setProgress: function(frac) {
    document.getElementById('progress-fill').style.width = (frac * 100) + '%';
  },

  setVolume: function(vol) {
    var s = document.getElementById('vol-slider');
    if (document.activeElement !== s) {
      s.value = vol;
      this.updateVolSliderBg(s);
    }
  },

  updateVolSliderBg: function(el) {
    var val = parseFloat(el.value || 0) * 100;
    el.style.background = 'linear-gradient(to right, var(--primary) ' + val + '%, var(--muted) ' + val + '%)';
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

  _noop: function() {}
};

// ── Bootstrap initial state ────────────────────────────────
window.gwaveUI.updateQueue(]] .. initQueueJS .. [[);
window.gwaveUI.setState(']] .. initState .. [[');
document.getElementById('vol-slider').value = ]] .. initVolume .. [[;
window.gwaveUI.updateVolSliderBg(document.getElementById('vol-slider'));
if (!IS_OWNER) document.getElementById('vol-slider').disabled = true;
</script>
</body>
</html>]] )

    -- Sync queue changes driven by gwave_syncqueue net message
    -- (the Think hook handles _queueChanged flag set by the net receiver)
end

net.Receive( "gwave_openmenu", function()
    local radio = net.ReadEntity()
    if not IsValid( radio ) then return end

    local queue = net.ReadTable()
    GWave.OpenRadioMenu( radio, queue )
end )

net.Receive( "gwave_syncqueue", function()
    local radio = net.ReadEntity()
    if not IsValid( radio ) then return end

    local queue = net.ReadTable()
    radio._queue = queue
    radio._queueChanged = true
end )
