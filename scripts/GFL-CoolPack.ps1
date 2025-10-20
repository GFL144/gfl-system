# ===================== GFL-UltimatePack.ps1 =====================
[CmdletBinding()]
param(
  [string]$Root = 'C:\GFL-System',
  [string]$TaskName = 'GFL-StageMatrix-Autostart'
)

$ErrorActionPreference = 'Stop'
function Mk($p){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WAscii($path,$content){ $content | Set-Content -Path $path -Encoding ascii } # no BOM

# Paths
$Stage        = Join-Path $Root 'StageMatrix'
$Ctl          = Join-Path $Stage 'controller'
$Ui           = Join-Path $Stage 'ui\static'
$RtmpDir      = Join-Path $Stage 'rtmp'
$ComposeFile  = Join-Path $Stage 'docker-compose.yml'
$StartCmd     = Join-Path $Stage 'Start-Matrix.cmd'
$StopCmd      = Join-Path $Stage 'Stop-Matrix.cmd'
$Recordings   = Join-Path $Root  'Recordings'
$DashDir      = Join-Path $Root  'Dashboards\Bully-3D'
$Desktop      = [Environment]::GetFolderPath('Desktop')

Mk $Root; Mk $Stage; Mk $Ctl; Mk $Ui; Mk $RtmpDir; Mk $Recordings; Mk $DashDir

# ---------------- 1) 25-tile mosaic (5?5) ----------------
$Mosaic25 = @'
<!doctype html>
<html><head><meta charset="utf-8"><title>Subscriber x25</title>
<style>body{margin:0;font-family:system-ui}
.grid{display:grid;grid-template-columns:repeat(5,1fr);grid-auto-rows:minmax(18vh,1fr);gap:4px;background:#000;height:100vh}
video{width:100%;height:100%;object-fit:cover;background:#000}</style></head>
<body><div class="grid" id="grid"></div>
<script type="module">
const params=new URLSearchParams(location.search);
const stageId=params.get('stage');
const identity=params.get('id')||('out25_'+Math.random().toString(36).slice(2));
const grid=document.getElementById('grid'); for(let i=0;i<25;i++){ const v=document.createElement('video'); v.autoplay=true; v.playsInline=true; v.controls=false; v.id='v'+i; grid.appendChild(v); }
const { Room } = await import('https://cdn.jsdelivr.net/npm/livekit-client/dist/livekit-client.esm.js');
const outRes = await (await fetch('http://localhost:8787/api/outputs',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({label:identity,stageId})})).json();
const tok = await (await fetch('http://localhost:8787/api/token',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({stageId,identity,role:'subscriber'})})).json();
const room=new Room({adaptiveStream:true,dynacast:true}); await room.connect(tok.url,tok.token);
async function refresh(){ const st=await (await fetch('http://localhost:8787/api/state')).json(); const out=st.outputs[outRes.id]; if(!out) return;
  const routes=(out.routes||[]).slice(0,25);
  routes.forEach((rid,idx)=>{ const p=[...room.participants.values()].find(pp=>pp.identity===rid);
    if(p) p.tracks.forEach(async pub=>{ if(pub.kind==='video'){ await pub.setSubscribed(true); document.getElementById('v'+idx).srcObject=new MediaStream([pub.track.mediaStreamTrack]); }}); });
}
setInterval(refresh,2000); refresh();
</script></body></html>
'@
WAscii (Join-Path $Ui 'mosaic25.html') $Mosaic25

# ---------------- 2) Program Mixer (A/B bus with TAKE) ----------------
$Mixer = @'
<!doctype html>
<html><head><meta charset="utf-8"><title>Program Mixer</title>
<style>
  body{font-family:system-ui;margin:18px}
  .row{display:flex;gap:14px;align-items:center;margin-bottom:10px}
  .col{flex:1;border:1px solid #e5e7eb;border-radius:10px;padding:10px}
  video{width:100%;background:#000;border:1px solid #cbd5e1}
  button{padding:8px 14px;border-radius:8px;border:1px solid #cbd5e1;background:#111827;color:#fff}
  select,input{padding:6px 8px;border:1px solid #cbd5e1;border-radius:8px}
  .inputs{display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:8px;max-height:40vh;overflow:auto}
  .pill{padding:8px;border:1px solid #cbd5e1;border-radius:999px;background:#f8fafc;cursor:pointer}
</style></head>
<body>
<h1>Program Mixer (Preview / Program)</h1>
<div class="row">
  <label>Stage <input id="stage" placeholder="stage_xxx"></label>
  <label>Program Output <input id="outId" placeholder="out_xxx"></label>
  <button id="refresh">Load</button>
  <button id="take">TAKE</button>
</div>
<div class="row">
  <div class="col"><h3>Preview</h3><video id="prev" autoplay playsinline muted></video></div>
  <div class="col"><h3>Program</h3><video id="prog" autoplay playsinline muted></video></div>
</div>
<h3>Inputs</h3>
<div class="inputs" id="inputs"></div>

<script type="module">
const elPrev=document.getElementById('prev'), elProg=document.getElementById('prog'), grid=document.getElementById('inputs');
let selectedPreview=null, programInput=null, stageId=null, programOutId=null, room=null;

async function connectRoom(stage){
  if(room){ try{ await room.disconnect(); }catch{} room=null; }
  const { Room } = await import('https://cdn.jsdelivr.net/npm/livekit-client/dist/livekit-client.esm.js');
  const identity='mixer_'+Math.random().toString(36).slice(2);
  const tok=await (await fetch('http://localhost:8787/api/token',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({stageId:stage,identity,role:'subscriber'})})).json();
  room=new Room({adaptiveStream:true,dynacast:true}); await room.connect(tok.url,tok.token);
}

function setVideoFromParticipant(pid, videoEl){
  const p=[...room.participants.values()].find(pp=>pp.identity===pid);
  if(!p) return;
  p.tracks.forEach(async pub=>{ if(pub.kind==='video'){ await pub.setSubscribed(true); videoEl.srcObject=new MediaStream([pub.track.mediaStreamTrack]); }});
}

async function load(){
  stageId=document.getElementById('stage').value.trim();
  programOutId=document.getElementById('outId').value.trim();
  if(!stageId){ alert('Enter Stage'); return; }
  await connectRoom(stageId);
  const st=await (await fetch('http://localhost:8787/api/state')).json();
  const ins=Object.values(st.inputs).filter(i=>i.stageId===stageId);
  grid.innerHTML='';
  ins.forEach(i=>{
    const b=document.createElement('div');
    b.className='pill'; b.textContent=(i.label||i.id)+' ('+i.id+')';
    b.onclick=()=>{ selectedPreview=i.id; setVideoFromParticipant(i.id, elPrev); };
    grid.appendChild(b);
  });
  // show current program if output set
  if(programOutId){
    const out=st.outputs[programOutId]; if(out && out.routes && out.routes[0]){ programInput=out.routes[0]; setVideoFromParticipant(programInput, elProg); }
  }
}

document.getElementById('refresh').onclick=load;
document.getElementById('take').onclick=async ()=>{
  if(!selectedPreview || !programOutId){ alert('Pick a preview input and set Program Output'); return; }
  await fetch('http://localhost:8787/api/route',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({outputId:programOutId,inputs:[selectedPreview],mode:'single'})});
  programInput=selectedPreview; setVideoFromParticipant(programInput, elProg);
};

load();
</script>
</body></html>
'@
WAscii (Join-Path $Ui 'mixer.html') $Mixer

# ---------------- 3) RTMP recording (nginx.conf + compose patch) -------
$NginxConf = @"
worker_processes  auto;
events { worker_connections  1024; }
rtmp {
  server {
    listen 1935;
    chunk_size 4096;

    application live {
      live on;
      record all;
      record_unique on;
      record_path /recordings;
      # split files every 30 min
      record_max_size 2048M;
      record_interval 30m;
      # optional: hls off; (not using http hls here)
      allow publish all;
      allow play all;
    }
  }
}
http {
  server {
    listen 80;
    location / {
      return 200 'RTMP alive';
    }
  }
}
"@
WAscii (Join-Path $RtmpDir 'nginx.conf') $NginxConf

# Patch docker-compose to mount recordings + config (idempotent-ish)
if (Test-Path $ComposeFile) {
  $compose = Get-Content $ComposeFile -Raw
  if ($compose -notmatch 'rtmp:' -or $compose -notmatch '/recordings') {
    $compose = @"
version: "3.9"
services:
  livekit:
    image: livekit/livekit-server:v1.7
    command: >
      --dev
      --bind 0.0.0.0
      --node-ip livekit
      --rtc.use_external_ip=false
      --room-entry
    environment:
      LIVEKIT_KEYS: devkey:devsecret
    ports:
      - "7880:7880"
      - "5349:5349/udp"
      - "60000-60999:60000-60999/udp"
  redis:
    image: redis:7-alpine
  controller:
    build: ./controller
    environment:
      LIVEKIT_HOST: http://livekit:7880
      LIVEKIT_API_KEY: devkey
      LIVEKIT_API_SECRET: devsecret
      REDIS_URL: redis://redis:6379
    depends_on: [livekit, redis]
    ports:
      - "8787:8787"
  ui:
    build: ./ui
    ports:
      - "8080:80"
    depends_on: [controller]
  rtmp:
    image: alfg/nginx-rtmp
    volumes:
      - ./rtmp/nginx.conf:/etc/nginx/nginx.conf:ro
      - ${RECORDINGS:-/recordings_host}:/recordings
    environment:
      - RECORDINGS=$($Recordings -replace '\\','/')
    ports:
      - "1935:1935"
      - "8081:80"
"@
    WAscii $ComposeFile $compose
  }
} else {
  Write-Host "Compose file not found at $ComposeFile ? skipping patch." -ForegroundColor Yellow
}

# ---------------- 4) Health & Logs helper scripts ----------------------
$HealthCmd = @"
@echo off
echo ==== StageMatrix Health ====
docker ps
echo.
echo ---- Controller last 100 lines ----
docker compose -f ""$ComposeFile"" logs controller --tail=100
echo.
echo ---- LiveKit last 50 lines ----
docker compose -f ""$ComposeFile"" logs livekit --tail=50
echo.
echo Open UI: http://localhost:8080
echo API: http://localhost:8787/api/state
echo RTMP status: http://localhost:8081
pause
"@
WAscii (Join-Path $Stage 'Health-Check.cmd') $HealthCmd

$LogsCmd = @"
@echo off
docker compose -f ""$ComposeFile"" logs -f
"@
WAscii (Join-Path $Stage 'Follow-Logs.cmd') $LogsCmd

# ---------------- 5) Autostart on login (Scheduled Task) ---------------
# Create a small runner that waits for Docker to be ready then starts the stack
$Runner = @'
param([string]$Compose="C:\GFL-System\StageMatrix\docker-compose.yml",[int]$TimeoutSec=180)
$ErrorActionPreference='SilentlyContinue'
$start = Get-Date
Write-Host "GFL Runner: waiting for docker..." -ForegroundColor Cyan
while(-not (Get-Command docker -ErrorAction SilentlyContinue)){
  Start-Sleep -Seconds 2
  if((Get-Date)-$start -gt ([TimeSpan]::FromSeconds($TimeoutSec))){break}
}
# Give Docker Desktop extra time on cold boot
Start-Sleep -Seconds 15
cmd /c "docker compose -f `"$Compose`" up -d"
'@
$RunnerPath = Join-Path $Stage 'AutoStart-Runner.ps1'
WAscii $RunnerPath $Runner

# Register Scheduled Task
try {
  $Action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -WindowStyle Hidden -File `"$RunnerPath`""
  $Trigger = New-ScheduledTaskTrigger -AtLogOn
  $Principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType InteractiveToken -RunLevel Highest
  Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null
  Write-Host "Scheduled task '$TaskName' created (auto-start StageMatrix at logon)." -ForegroundColor Green
} catch {
  Write-Host "Could not create scheduled task (permissions?). You can create manually later." -ForegroundColor Yellow
}

# ---------------- 6) Firewall rules (idempotent) -----------------------
$ports = @(7880, 5349, 8080, 8787, 1935, 8081)
foreach($p in $ports){
  if(-not (Get-NetFirewallRule -DisplayName "GFL-$p" -ErrorAction SilentlyContinue)){
    New-NetFirewallRule -DisplayName "GFL-$p" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p | Out-Null
  }
}
# UDP for RTP range (LiveKit)
if(-not (Get-NetFirewallRule -DisplayName "GFL-RTP-60000-60999" -ErrorAction SilentlyContinue)){
  New-NetFirewallRule -DisplayName "GFL-RTP-60000-60999" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 60000-60999 | Out-Null
}

# ---------------- 7) Desktop Shortcuts -------------------------------
$Shell = New-Object -ComObject WScript.Shell
function Shortcut($name,$target){
  $sc = $Shell.CreateShortcut((Join-Path $Desktop $name))
  $sc.TargetPath = $target
  $sc.Save()
}
# Browser shortcuts to UI pages (uses default browser via URL file)
function UrlShortcut($name,$url){
  $p = Join-Path $Desktop $name
  "[InternetShortcut]`nURL=$url" | Set-Content -Path $p -Encoding ascii
}

UrlShortcut "GFL UI.url"            "http://localhost:8080"
UrlShortcut "GFL Matrix.url"        "http://localhost:8080/matrix.html"
UrlShortcut "GFL Mosaic x8.url"     "http://localhost:8080/mosaic8.html"
UrlShortcut "GFL Mosaic x16.url"    "http://localhost:8080/mosaic16.html"
UrlShortcut "GFL Mosaic x25.url"    "http://localhost:8080/mosaic25.html"
Shortcut    "GFL 3D Metrics.lnk"    (Join-Path $DashDir 'index-metrics.html')
Shortcut    "GFL Health Check.lnk"  (Join-Path $Stage 'Health-Check.cmd')
Shortcut    "GFL Follow Logs.lnk"   (Join-Path $Stage 'Follow-Logs.cmd')
Shortcut    "GFL Start Stack.lnk"   $StartCmd
Shortcut    "GFL Stop Stack.lnk"    $StopCmd

# ---------------- 8) Rebuild / Restart stack -------------------------
if (Get-Command docker -ErrorAction SilentlyContinue) {
  Push-Location $Stage
  Write-Host "Restarting containers to apply Ultimate Pack..." -ForegroundColor Cyan
  cmd /c "docker compose -f `"$ComposeFile`" down"
  cmd /c "docker compose -f `"$ComposeFile`" up -d --build"
  Pop-Location
} else {
  Write-Host "Docker not on PATH; stack will start at next login via Scheduled Task." -ForegroundColor Yellow
}

Write-Host "Ultimate Pack installed. New pages:" -ForegroundColor Green
Write-Host "  Mixer:      http://localhost:8080/mixer.html"
Write-Host "  Mosaic x25: http://localhost:8080/mosaic25.html?stage=<stage_id>"
Write-Host "Recordings:   $Recordings  (files appear after you push RTMP)" -ForegroundColor Cyan
Write-Host "RTMP Ingest:  rtmp://<host>:1935/live/<streamKey>" -ForegroundColor Cyan
# =================== END GFL-UltimatePack.ps1 ===================





















