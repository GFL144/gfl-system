# ========================= GFL-All-In-One.ps1 =========================
[CmdletBinding()]
param(
  [string]$Root = 'C:\GFL-System',
  [switch]$SkipDockerInstall,
  [switch]$SkipFFmpegInstall,
  [switch]$NoAutoStartDocker
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Note ($m){ Write-Host $m -ForegroundColor Cyan }
function Good ($m){ Write-Host $m -ForegroundColor Green }
function Warn ($m){ Write-Host $m -ForegroundColor Yellow }
function MkDir($p){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Ascii($path, $content){ $content | Set-Content -Path $path -Encoding ascii } # avoid BOM

# --- 0) Folders
MkDir $Root
MkDir "$Root\Scripts"
MkDir "$Root\Dashboards\Bully-3D"
MkDir "$Root\StageMatrix\controller"
MkDir "$Root\StageMatrix\ui\static"
MkDir "$Root\GFL-OneClick-Auth\public"

# --- 1) Pre-req installs (Docker, FFmpeg) ---
if (-not $SkipDockerInstall) {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Note "Installing Docker Desktop (winget)?"
    winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements
  } else { Note "Docker already present." }
  if (-not $NoAutoStartDocker) {
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue | Out-Null
    Warn "If first run, finish Docker Desktop setup from the tray."
  }
} else { Warn "Skipping Docker install (--SkipDockerInstall)." }

if (-not $SkipFFmpegInstall) {
  if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Note "Installing FFmpeg (winget)?"
    winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements
  } else { Note "FFmpeg already present." }
} else { Warn "Skipping FFmpeg install (--SkipFFmpegInstall)." }

# --- 2) Bully 3D Desktop (single HTML) ---
$BullyHtml = @'
<!doctype html><html><head><meta charset="utf-8"/><title>Bully 3D Desktop</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 html,body{margin:0;height:100%;overflow:hidden;background:#0a0a0f;font-family:system-ui,Segoe UI,Roboto,Arial}
 #overlay{position:fixed;top:20px;left:20px;color:#e8e8f0;z-index:10;backdrop-filter:blur(6px);padding:12px 16px;border-radius:14px;box-shadow:0 10px 30px rgba(0,0,0,.35);opacity:.95}
 #overlay h1{margin:0 0 6px;font-size:20px;letter-spacing:.5px}
 #overlay .row{display:flex;gap:14px;font-size:13px;opacity:.9}
 #overlay .chip{padding:6px 10px;border-radius:999px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.08)}
 #hint{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);color:#9aa3b2;font-size:12px;letter-spacing:.3px;opacity:.75}
 canvas{display:block}
</style></head><body>
<div id="overlay"><h1>?? Bully Interactive ? 3D Desktop</h1>
  <div class="row"><div class="chip" id="clock">--:--:--</div><div class="chip">Mode: LIVE</div><div class="chip">FPS: <span id="fps">--</span></div></div>
</div><div id="hint">Drag to orbit ? Scroll to zoom ? Move mouse for parallax ?</div>
<script src="https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/three@0.160.0/examples/js/controls/OrbitControls.js"></script>
<script>(function(){
 const scene=new THREE.Scene();
 const renderer=new THREE.WebGLRenderer({antialias:true,powerPreference:'high-performance'});
 renderer.setPixelRatio(Math.min(devicePixelRatio,1.75)); renderer.setSize(innerWidth,innerHeight); renderer.setClearColor(0x0a0a0f,1); document.body.appendChild(renderer.domElement);
 const camera=new THREE.PerspectiveCamera(55,innerWidth/innerHeight,0.1,2000); camera.position.set(0,1.2,5);
 const controls=new THREE.OrbitControls(camera,renderer.domElement); controls.enableDamping=true; controls.dampingFactor=.06; controls.rotateSpeed=.5; controls.minDistance=2; controls.maxDistance=12;
 scene.add(new THREE.HemisphereLight(0x7aa0ff,0x111133,.9)); const dir=new THREE.DirectionalLight(0xffffff,1); dir.position.set(5,6,3); scene.add(dir);
 const sky=new THREE.Mesh(new THREE.SphereGeometry(1000,64,64), new THREE.ShaderMaterial({side:THREE.BackSide,
   uniforms:{top:{value:new THREE.Color(0x0e1530)},bottom:{value:new THREE.Color(0x06070d)}},
   vertexShader:"varying vec3 vPos; void main(){ vPos=position; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }",
   fragmentShader:"varying vec3 vPos; uniform vec3 top; uniform vec3 bottom; void main(){ float h=normalize(vPos).y*.5+.5; gl_FragColor=vec4(mix(bottom,top,smoothstep(0.,1.,h)),1.); }"})); scene.add(sky);
 const pCount=1500, pGeo=new THREE.BufferGeometry(), pos=new Float32Array(pCount*3);
 for(let i=0;i<pCount;i++){const r=40*Math.random()+10,t=Math.random()*Math.PI*2,u=Math.random()*Math.PI*2; pos[i*3]=Math.cos(t)*Math.sin(u)*r; pos[i*3+1]=Math.cos(u)*r*.25; pos[i*3+2]=Math.sin(t)*Math.sin(u)*r;}
 pGeo.setAttribute('position', new THREE.BufferAttribute(pos,3)); scene.add(new THREE.Points(pGeo,new THREE.PointsMaterial({size:.05,transparent:true,opacity:.75})));
 const group=new THREE.Group(); scene.add(group);
 const torus=new THREE.Mesh(new THREE.TorusKnotGeometry(1.1,.32,180,32), new THREE.MeshStandardMaterial({metalness:.4,roughness:.25,color:0x6ea8ff,envMapIntensity:1.2})); torus.rotation.x=Math.PI*.2; group.add(torus);
 const makeText=(t)=>{const c=document.createElement('canvas'),s=512; c.width=c.height=s; const x=c.getContext('2d'); x.font='bold 120px Segoe UI, Arial'; x.textAlign='center'; x.textBaseline='middle';
   const g=x.createLinearGradient(0,0,s,0); g.addColorStop(0,'#a9d0ff'); g.addColorStop(1,'#7aa0ff'); x.fillStyle=g; x.shadowColor='#113'; x.shadowBlur=24; x.fillText(t,s/2,s/2);
   const tex=new THREE.CanvasTexture(c); tex.anisotropy=8; return new THREE.Mesh(new THREE.PlaneGeometry(2.4,2.4), new THREE.MeshBasicMaterial({map:tex,transparent:true})); };
 const t1=makeText('Bully'); const t2=makeText('Interactive'); t1.position.y=.65; t2.position.y=-.55; t2.scale.set(.8,.8,.8); t2.position.z=.01; group.add(t1,t2);
 const mouse={x:0,y:0}; addEventListener('mousemove',e=>{mouse.x=e.clientX/innerWidth-.5; mouse.y=e.clientY/innerHeight-.5;});
 addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth,innerHeight)});
 const clockEl=document.getElementById('clock'), fpsEl=document.getElementById('fps'); let last=performance.now(), frames=0, acc=0;
 (function tick(t){ requestAnimationFrame(tick); const dt=(t-last)/1000; last=t; frames++; acc+=dt; if(acc>=1){ fpsEl.textContent=frames; frames=0; acc=0; }
  clockEl.textContent=(new Date()).toLocaleTimeString(); scene.children[1].rotation.y+=.002; group.rotation.y+=.35*dt; group.position.x=mouse.x*.6; group.position.y=-mouse.y*.3;
  controls.update(); renderer.render(scene,camera); })(performance.now());
})();</script></body></html>
'@
Write-Ascii "$Root\Dashboards\Bully-3D\index.html" $BullyHtml
Good "Bully 3D: $Root\Dashboards\Bully-3D\index.html"

# --- 3) StageMatrix (LiveKit + Controller + UI + RTMP) ---
$Compose = @'
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
    ports:
      - "1935:1935"
      - "8081:80"
'@
Write-Ascii "$Root\StageMatrix\docker-compose.yml" $Compose

$CtlDocker = @'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
EXPOSE 8787
CMD ["node","server.js"]
'@
Write-Ascii "$Root\StageMatrix\controller\Dockerfile" $CtlDocker

$CtlPkg = @'
{
  "name": "gfl-stage-controller",
  "version": "1.0.0",
  "type": "module",
  "main": "server.js",
  "dependencies": {
    "dotenv": "^16.4.0",
    "express": "^4.19.2",
    "ioredis": "^5.4.1",
    "livekit-server-sdk": "^1.4.0",
    "nanoid": "^5.0.7"
  }
}
'@
Write-Ascii "$Root\StageMatrix\controller\package.json" $CtlPkg

$CtlSrv = @'
import "dotenv/config";
import express from "express";
import Redis from "ioredis";
import { AccessToken } from "livekit-server-sdk";
import { nanoid } from "nanoid";

const app = express(); app.use(express.json());
const { LIVEKIT_HOST="http://localhost:7880", LIVEKIT_API_KEY="devkey", LIVEKIT_API_SECRET="devsecret", REDIS_URL="redis://127.0.0.1:6379" } = process.env;
const redis = new Redis(REDIS_URL);

// Create stage
app.post("/api/stages", async (req,res)=>{ const { label, room } = req.body || {};
  const id=`stage_${nanoid(6)}`; const s={id,label:label||id,room:room||id,inputs:[],outputs:[]};
  await redis.hset("stages", id, JSON.stringify(s)); res.json(s); });
// List stages
app.get("/api/stages", async (_req,res)=>{ const raw=await redis.hgetall("stages");
  res.json(Object.fromEntries(Object.entries(raw).map(([k,v])=>[k,JSON.parse(v)]))); });
// Register input
app.post("/api/inputs", async (req,res)=>{ const { label, stageId } = req.body || {};
  if(!stageId) return res.status(400).json({error:"stageId required"});
  const sRaw=await redis.hget("stages",stageId); if(!sRaw) return res.status(404).json({error:"stage not found"});
  const id=`in_${nanoid(6)}`; const input={id,label:label||id,stageId}; await redis.hset("inputs",id,JSON.stringify(input));
  const s=JSON.parse(sRaw); s.inputs.push(id); await redis.hset("stages",stageId,JSON.stringify(s)); res.json(input); });
// Register output
app.post("/api/outputs", async (req,res)=>{ const { label, stageId } = req.body || {};
  if(!stageId) return res.status(400).json({error:"stageId required"});
  const sRaw=await redis.hget("stages",stageId); if(!sRaw) return res.status(404).json({error:"stage not found"});
  const id=`out_${nanoid(6)}`; const output={id,label:label||id,stageId,routes:[],mode:"single"}; await redis.hset("outputs",id,JSON.stringify(output));
  const s=JSON.parse(sRaw); s.outputs.push(id); await redis.hset("stages",stageId,JSON.stringify(s)); res.json(output); });
// Route
app.post("/api/route", async (req,res)=>{ const { outputId, inputs, mode } = req.body || {};
  if(!outputId || !Array.isArray(inputs) || inputs.length===0) return res.status(400).json({error:"outputId and inputs[] required"});
  const oRaw=await redis.hget("outputs",outputId); if(!oRaw) return res.status(404).json({error:"output not found"});
  const out=JSON.parse(oRaw); out.routes=inputs.slice(0, mode==="quad"?4:1); out.mode=mode||"single";
  await redis.hset("outputs",outputId,JSON.stringify(out)); res.json({ok:true, output:out}); });
// Token
app.post("/api/token", async (req,res)=>{ const { stageId, identity, role="subscriber" } = req.body || {};
  const sRaw=await redis.hget("stages",stageId); if(!sRaw) return res.status(404).json({error:"stage not found"});
  const s=JSON.parse(sRaw); const at=new AccessToken(LIVEKIT_API_KEY,LIVEKIT_API_SECRET,{identity:identity||`${role}_${nanoid(6)}`,ttl:3600});
  at.addGrant({room:s.room, roomJoin:true, canPublish: role==="publisher", canSubscribe: true});
  res.json({ url: LIVEKIT_HOST, token: await at.toJwt(), room: s.room }); });
// State dump
app.get("/api/state", async (_req,res)=>{ const [A,B,C]=await Promise.all([redis.hgetall("stages"),redis.hgetall("inputs"),redis.hgetall("outputs")]);
  const conv=o=>Object.fromEntries(Object.entries(o).map(([k,v])=>[k,JSON.parse(v)])); res.json({stages:conv(A),inputs:conv(B),outputs:conv(C)}); });

app.listen(8787, ()=>console.log("Controller on :8787"));
'@
Write-Ascii "$Root\StageMatrix\controller\server.js" $CtlSrv

$UiDocker = @'
FROM nginx:alpine
COPY ./static /usr/share/nginx/html
'@
Write-Ascii "$Root\StageMatrix\ui\Dockerfile" $UiDocker

$UiIndex = @'
<!doctype html><html><head><meta charset="utf-8"><title>GFL Multi-Concert Matrix</title>
<style>body{font-family:system-ui;margin:24px}.grid{display:grid;grid-template-columns:repeat(3,minmax(260px,1fr));gap:16px}
pre{background:#f6f8fa;border:1px solid #e5e7eb;border-radius:8px;padding:12px;overflow:auto;max-height:420px}
a.btn{display:inline-block;background:#111827;color:#fff;padding:10px 14px;border-radius:8px;text-decoration:none;margin-right:10px}
label{display:block;margin:6px 0}input,select{padding:6px 8px;border:1px solid #cbd5e1;border-radius:6px}</style></head>
<body><h1>GFL Multi-Concert (100?100)</h1>
<p><a class="btn" href="publisher.html">Register & Publish Input</a> <a class="btn" href="subscriber.html">Register & View Output</a></p>
<div class="grid">
<div><h3>Create Stage</h3><label>Label <input id="stLabel" placeholder="Concert A"></label><button id="mkStage">Create</button><pre id="stages">Stages: (load?)</pre></div>
<div><h3>Route</h3><label>Output ID <input id="outId" placeholder="out_xxx"></label><label>Input IDs (comma) <input id="inIds" placeholder="in_a,in_b,in_c"></label>
<label>Mode <select id="mode"><option>single</option><option>quad</option></select></label><button id="doRoute">Apply Route</button><pre id="state">State: (load?)</pre></div>
<div><h3>Docs</h3><pre>1) Create a Stage. 2) Publisher: choose Stage & Start. 3) Subscriber: choose Stage & Start. 4) Route inputs?outputs.</pre></div></div>
<script>
async function load(){ const s=await (await fetch('http://localhost:8787/api/stages')).json(); stages.textContent=JSON.stringify(s,null,2);
const st=await (await fetch('http://localhost:8787/api/state')).json(); state.textContent=JSON.stringify(st,null,2); }
mkStage.onclick=async()=>{const label=document.getElementById('stLabel').value||'Stage';
await (await fetch('http://localhost:8787/api/stages',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({label})})).json(); load();};
doRoute.onclick=async()=>{const outputId=document.getElementById('outId').value.trim();
const inputs=document.getElementById('inIds').value.split(',').map(s=>s.trim()).filter(Boolean);
const mode=document.getElementById('mode').value; if(!outputId||inputs.length==0){alert('Need outputId & inputs'); return;}
await fetch('http://localhost:8787/api/route',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({outputId,inputs,mode})}); load();};
load(); setInterval(load,4000);
</script></body></html>
'@
Write-Ascii "$Root\StageMatrix\ui\static\index.html" $UiIndex

$UiPub = @'
<!doctype html><html><head><meta charset="utf-8"><title>Publisher</title></head><body>
<h2>Publisher ? Register Input & Publish</h2>
<label>Stage ID <input id="stage" placeholder="stage_xxx"></label>
<label>Label <input id="label" placeholder="Cam 01"></label>
<button id="go">Start</button>
<video id="v" autoplay playsinline muted style="width:560px;margin-top:10px;border:1px solid #ccc"></video>
<script type="module">
const go=document.getElementById('go'), v=document.getElementById('v');
go.onclick=async()=>{ const stageId=stage.value.trim(); const label=document.getElementById('label').value||'Input';
 const inRes=await (await fetch('http://localhost:8787/api/inputs',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({label,stageId})})).json();
 const identity=inRes.id; const tok=await (await fetch('http://localhost:8787/api/token',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({stageId,identity,role:"publisher"})})).json();
 const { Room, createLocalVideoTrack, VideoPresets } = await import('https://cdn.jsdelivr.net/npm/livekit-client/dist/livekit-client.esm.js');
 const room=new Room({adaptiveStream:true,dynacast:true}); await room.connect(tok.url,tok.token);
 const track = await createLocalVideoTrack({resolution: VideoPresets.h720.resolution}); await room.localParticipant.publishTrack(track); v.srcObject=await track.mediaStream; };
</script></body></html>
'@
Write-Ascii "$Root\StageMatrix\ui\static\publisher.html" $UiPub

$UiSub = @'
<!doctype html><html><head><meta charset="utf-8"><title>Subscriber</title>
<style>.quad{display:grid;grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;gap:6px} video{width:100%;border:1px solid #ccc}</style></head><body>
<h2>Subscriber ? Register Output & View Route</h2>
<label>Stage ID <input id="stage" placeholder="stage_xxx"></label>
<label>Label <input id="label" placeholder="Screen 01"></label>
<button id="go">Start</button>
<div id="wrap"><video id="v" autoplay playsinline controls></video></div>
<script type="module">
const wrap=document.getElementById('wrap'); let currentMode='single';
const ensureSingle=()=>{wrap.className=''; wrap.innerHTML='<video id="v" autoplay playsinline controls></video>'; return document.getElementById('v');}
const ensureQuad=()=>{wrap.className='quad'; wrap.innerHTML='<video id="v0" autoplay playsinline></video><video id="v1" autoplay playsinline></video><video id="v2" autoplay playsinline></video><video id="v3" autoplay playsinline></video>'; return [0,1,2,3].map(i=>document.getElementById('v'+i));}
go.onclick=async()=>{ const stageId=stage.value.trim(); const label=document.getElementById('label').value||'Output';
 const outRes=await (await fetch('http://localhost:8787/api/outputs',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({label,stageId})})).json();
 const identity=outRes.id; const tok=await (await fetch('http://localhost:8787/api/token',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({stageId,identity,role:"subscriber"})})).json();
 const { Room } = await import('https://cdn.jsdelivr.net/npm/livekit-client/dist/livekit-client.esm.js');
 const room=new Room({adaptiveStream:true,dynacast:true}); await room.connect(tok.url,tok.token);
 const refresh=async()=>{ const st=await (await fetch('http://localhost:8787/api/state')).json(); const out=st.outputs[identity]; if(!out) return;
  if(out.mode!==currentMode){ currentMode=out.mode; if(currentMode==='single') ensureSingle(); else ensureQuad(); }
  const ids=(out.routes||[]).slice(0,currentMode==='quad'?4:1);
  if(currentMode==='single'){ const vid=ensureSingle(); const p=[...room.participants.values()].find(pp=>pp.identity===ids[0]);
    if(p) p.tracks.forEach(async pub=>{ if(pub.kind==='video'){ await pub.setSubscribed(true); vid.srcObject=new MediaStream([pub.track.mediaStreamTrack]); }});
  } else { const vEls=ensureQuad(); ids.forEach((rid,idx)=>{ const p=[...room.participants.values()].find(pp=>pp.identity===rid);
    if(p) p.tracks.forEach(async pub=>{ if(pub.kind==='video'){ await pub.setSubscribed(true); vEls[idx].srcObject=new MediaStream([pub.track.mediaStreamTrack]); }}); }); } };
 setInterval(refresh,2000); refresh(); };
</script></body></html>
'@
Write-Ascii "$Root\StageMatrix\ui\static\subscriber.html" $UiSub

# Helper CMDs (ASCII -> no BOM)
Write-Ascii "$Root\StageMatrix\Start-Matrix.cmd" "docker compose -f `"$Root\StageMatrix\docker-compose.yml`" up -d --build"
Write-Ascii "$Root\StageMatrix\Stop-Matrix.cmd"  "docker compose -f `"$Root\StageMatrix\docker-compose.yml`" down"

# --- 4) OAuth (Google + GitHub) scaffold (Node/Express) ---
$AuthPkg = @'
{
  "name": "gfl-oneclick-auth",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "cookie-session": "^2.0.0",
    "dotenv": "^16.4.0",
    "express": "^4.18.0",
    "node-fetch": "^2.6.7",
    "qs": "^6.11.0"
  }
}
'@
Write-Ascii "$Root\GFL-OneClick-Auth\package.json" $AuthPkg

$AuthEnv = @'
PORT=3000
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-google-client-secret
GITHUB_CLIENT_ID=your-github-client-id
GITHUB_CLIENT_SECRET=your-github-client-secret
SESSION_SECRET=change-to-a-very-long-random-string
'@
Write-Ascii "$Root\GFL-OneClick-Auth\.env.example" $AuthEnv

$AuthSrv = @'
require("dotenv").config();
const express=require("express"); const fetch=require("node-fetch"); const qs=require("qs"); const session=require("cookie-session"); const path=require("path");
const app=express(); const PORT=process.env.PORT||3000;
app.use(express.static(path.join(__dirname,"public"))); app.use(express.urlencoded({extended:true})); app.use(express.json());
app.use(session({name:"gfl-session",keys:[process.env.SESSION_SECRET||"dev-secret"],maxAge:24*60*60*1000}));
function buildUrl(base,params={}){const s=qs.stringify(params); return base+(s?`?${s}`:"");} function urlBase(req){const proto=req.headers["x-forwarded-proto"]||req.protocol; return `${proto}://${req.get("host")}`;}
app.get("/auth/google",(req,res)=>{ const state=Math.random().toString(36).slice(2); req.session.oauth_state=state; const redirect_uri=urlBase(req)+"/auth/google/callback";
  const url=buildUrl("https://accounts.google.com/o/oauth2/v2/auth",{client_id:process.env.GOOGLE_CLIENT_ID,redirect_uri,response_type:"code",scope:"openid email profile",access_type:"offline",prompt:"select_account",state}); res.redirect(url); });
app.get("/auth/google/callback", async (req,res)=>{ const {code,state}=req.query; if(!code||state!==req.session.oauth_state) return res.status(400).send(`<script>window.opener.postMessage({error:'invalid_state_or_code'},'*');window.close()</script>`);
  const redirect_uri=urlBase(req)+"/auth/google/callback";
  const tr=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:qs.stringify({code,client_id:process.env.GOOGLE_CLIENT_ID,client_secret:process.env.GOOGLE_CLIENT_SECRET,redirect_uri,grant_type:"authorization_code"})});
  const tj=await tr.json(); if(tj.error) return res.status(400).send(`<script>window.opener.postMessage({error:${JSON.stringify(tj)}},'*');window.close()</script>`);
  const pr=await fetch("https://www.googleapis.com/oauth2/v2/userinfo",{headers:{Authorization:`Bearer ${tj.access_token}`}}); const profile=await pr.json();
  const out={provider:"google",tokens:tj,profile}; res.send(`<script>window.opener.postMessage(${JSON.stringify(out)},'*');window.close()</script>`); });
app.get("/auth/github",(req,res)=>{ const state=Math.random().toString(36).slice(2); req.session.oauth_state=state; const redirect_uri=urlBase(req)+"/auth/github/callback";
  const url=buildUrl("https://github.com/login/oauth/authorize",{client_id:process.env.GITHUB_CLIENT_ID,redirect_uri,scope:"read:user user:email",state}); res.redirect(url); });
app.get("/auth/github/callback", async (req,res)=>{ const {code,state}=req.query; if(!code||state!==req.session.oauth_state) return res.status(400).send(`<script>window.opener.postMessage({error:'invalid_state_or_code'},'*');window.close()</script>`);
  const tr=await fetch("https://github.com/login/oauth/access_token",{method:"POST",headers:{accept:"application/json","content-type":"application/json"},body:JSON.stringify({client_id:process.env.GITHUB_CLIENT_ID,client_secret:process.env.GITHUB_CLIENT_SECRET,code,redirect_uri:urlBase(req)+"/auth/github/callback"})});
  const tj=await tr.json(); if(tj.error) return res.status(400).send(`<script>window.opener.postMessage({error:${JSON.stringify(tj)}},'*');window.close()</script>`);
  const pr=await fetch("https://api.github.com/user",{headers:{Authorization:`token ${tj.access_token}`,"user-agent":"GFL-OneClick"}}); const profile=await pr.json();
  const out={provider:"github",tokens:tj,profile}; res.send(`<script>window.opener.postMessage(${JSON.stringify(out)},'*');window.close()</script>`); });
app.get("/me",(req,res)=>res.json({ok:true,session:!!req.session}));
app.listen(PORT,()=>console.log("One-click auth server http://localhost:"+PORT));
'@
Write-Ascii "$Root\GFL-OneClick-Auth\server.js" $AuthSrv

$AuthHtml = @'
<!doctype html><html><head><meta charset="utf-8"/><title>GFL One-Click Sign-In</title>
<style>body{font-family:system-ui;padding:40px}.btn{display:inline-block;padding:12px 18px;margin:8px;border-radius:6px;text-decoration:none;color:#fff}
.google{background:#DB4437}.github{background:#24292e}pre{background:#f4f4f4;padding:12px;border-radius:6px}</style></head>
<body><h1>GFL One-Click Sign-In</h1><p>A popup will open for Google/GitHub sign-in and return here.</p>
<a href="#" id="googleBtn" class="btn google">Sign in with Google</a>
<a href="#" id="githubBtn" class="btn github">Sign in with GitHub</a>
<h3>Result</h3><pre id="result">Not signed in</pre>
<script>
const popup="width=600,height=700,toolbar=no,menubar=no,location=no,resizable=yes,scrollbars=yes,status=no";
function openPopup(url){const w=window.open(url,'oauthPopup',popup); if(!w){alert('Popup blocked.'); return;} w.focus();}
document.getElementById('googleBtn').onclick=(e)=>{e.preventDefault(); openPopup('/auth/google');};
document.getElementById('githubBtn').onclick=(e)=>{e.preventDefault(); openPopup('/auth/github');};
window.addEventListener('message',(ev)=>{ const out=document.getElementById('result'); out.textContent=JSON.stringify(ev.data,null,2); },false);
</script></body></html>
'@
Write-Ascii "$Root\GFL-OneClick-Auth\public\index.html" $AuthHtml

# --- 5) Quick launchers for you ---
Write-Ascii "$Root\Start-StageMatrix.cmd" "docker compose -f `"$Root\StageMatrix\docker-compose.yml`" up -d --build"
Write-Ascii "$Root\Stop-StageMatrix.cmd"  "docker compose -f `"$Root\StageMatrix\docker-compose.yml`" down"

# Done
Good "All components written under $Root"
Warn  "Next:"
Write-Host "1) Start the video stack:" -ForegroundColor Cyan
Write-Host "   cd `"$Root\StageMatrix`""; Write-Host "   .\Start-Matrix.cmd"
Write-Host "   UI:   http://localhost:8080" -ForegroundColor Yellow
Write-Host "   API:  http://localhost:8787/api/state" -ForegroundColor Yellow
Write-Host "   RTMP: http://localhost:8081" -ForegroundColor Yellow
Write-Host "2) Test FFmpeg push (PowerShell syntax):" -ForegroundColor Cyan
Write-Host '   ffmpeg -rtsp_transport tcp -i "rtsp://<camera-ip>/stream" `'
Write-Host '     -c:v libx264 -preset veryfast -tune zerolatency -f flv `'
Write-Host '     rtmp://localhost:1935/live/stageA_cam07'
Write-Host "3) Bully 3D: open `"$Root\Dashboards\Bully-3D\index.html`"" -ForegroundColor Cyan
Write-Host "4) OAuth app: cd `"$Root\GFL-OneClick-Auth`"; copy .env.example to .env (fill IDs); npm install; npm start" -ForegroundColor Cyan
# ======================= END GFL-All-In-One.ps1 =======================































