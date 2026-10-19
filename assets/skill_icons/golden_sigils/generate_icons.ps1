$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'icons'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$classes = @(
  @{id='berserker'; hue='#ff334b'; pale='#ff9a7d'; bg1='#4b0714'; bg2='#19030b'; bg3='#080108'; metal='#da6861'; names=@('Rupture','Bloodstorm','Crimson Charge','Beast Awakening'); shapes=@('blade','cyclone','charge','beast')},
  @{id='heavy_knight'; hue='#ff682a'; pale='#ffd166'; bg1='#57200b'; bg2='#241005'; bg3='#0d0502'; metal='#e1a04a'; names=@('Fire Tornado','Phoenix Slam','Infernal Earthshaker','Heart of the Inferno'); shapes=@('flame','phoenix','quake','sun')},
  @{id='martial_artist'; hue='#fa3156'; pale='#41e9e5'; bg1='#102b49'; bg2='#081528'; bg3='#030915'; metal='#79bfc8'; names=@('Focus Strike','Electric Uppercut','Ground Slam','Crimson Hadouken'); shapes=@('fist','bolt','impact','orb')},
  @{id='mage'; hue='#c05cff'; pale='#70d9ff'; bg1='#30105a'; bg2='#120d36'; bg3='#060b1b'; metal='#938bdf'; names=@('Arcane Burst','Astral Prison','Arcane Shift','Apocalypse'); shapes=@('void','chains','portal','rain')},
  @{id='rogue'; hue='#b3a2ff'; pale='#d8d4ee'; bg1='#251638'; bg2='#100b20'; bg3='#050711'; metal='#999bb8'; names=@('Shadow Dagger','Dash','Invisibility','Shadow Execution'); shapes=@('dagger','slash','shadow','execution')},
  @{id='cleric'; hue='#7dffbb'; pale='#fff0a4'; bg1='#155642'; bg2='#082c2c'; bg3='#031617'; metal='#79d5ba'; names=@('Heal','Divine Beam','Radiant Ground','Divine Ascent'); shapes=@('leaf','beam','halo','sun')},
  @{id='ranger'; hue='#77e66d'; pale='#d9f28b'; bg1='#24572b'; bg2='#0d3326'; bg3='#041b18'; metal='#92d379'; names=@('Verdant Slash','Entangling Arrow','Seeker Barrage','Rain of Arrows'); shapes=@('leafslash','roots','arrow','arrows')},
  @{id='gunslinger'; hue='#ffbd57'; pale='#e9efff'; bg1='#493014'; bg2='#211828'; bg3='#0c1020'; metal='#d8bb82'; names=@('Fan the Hammer','Gunslinger Roll','Deadeye Ricochet','High Noon'); shapes=@('revolver','roll','coin','crosshair')},
  @{id='swordsman'; hue='#c7d8ff'; pale='#ffffff'; bg1='#253859'; bg2='#101d38'; bg3='#070c1a'; metal='#a8c1ed'; names=@('Sword Rush','Parry','Phantom Thrust','Blade Storm'); shapes=@('rapier','parry','thrust','xslash')},
  @{id='ice_mage'; hue='#79efff'; pale='#ffffff'; bg1='#15577d'; bg2='#092d55'; bg3='#041529'; metal='#91d8ff'; names=@('Ice Spikes','Ice Beam','Ice Clone','Blizzard'); shapes=@('spikes','beam','crystal','blizzard')}
)

$symbols = @{}
$symbols.blade = '<path d="M50 12 57 43 52 67 50 78 48 67 43 43Z"/><path d="M39 42l11 6 11-6M50 47v26" fill="none" stroke="#fff5c7" stroke-width="2.5"/><path d="m50 78-7 10 7-3 7 3Z"/>'
$symbols.fist = '<path d="M31 61 27 48q-1-7 5-7 4 0 5 6V33q0-7 6-7 6 0 6 7V28q1-7 7-6 5 1 5 7v7q2-7 7-4 4 2 3 8l-2 22q-2 17-18 18l-12-1q-9-2-11-18Z"/><path d="M35 47h28M43 27v12m10-15v14m10 0v8" fill="none" stroke="#fff5c7" stroke-width="2.5"/>'
$symbols.flame = '<path d="M51 13q4 19-9 25 2-10-4-15Q35 39 27 49 14 69 35 82q14 9 29-1 18-12 4-33-1 13-10 16 2-19-7-31Z"/><path d="M50 55q10 12 0 22-11-8 0-22Z" fill="#fff5c7"/>'
$symbols.beast = '<path d="M27 39 22 19l17 12 11-8 11 8 17-12-5 24 4 20-15 16H37L22 63Z"/><path d="m36 49 9 4-9 5m28-9-9 4 9 5M42 69l8 5 8-5" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.charge = '<path d="m18 58 20-27 1 16 26-14-14 25 10 1-27 17 2-16Z"/><path d="M18 82h54" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.cyclone = '<path d="M22 35q11-20 38-12 19 6 10 18-8 8-28 3-15-3-12 5 4 7 22 4 20-4 22 8 2 17-24 18-23 1-35-9" fill="none" stroke="#fff5c7" stroke-width="5" stroke-linecap="round"/>'
$symbols.phoenix = '<path d="M50 82Q23 70 24 48q10 10 18 10Q27 41 35 23q8 15 15 18 8-3 15-18 8 18-7 35 9 1 18-10 0 23-26 34Z"/><path d="M50 83V40m0 26-13-9m13 9 13-9" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.quake = '<path d="M50 15 61 39 51 35 57 53 49 49 45 72 38 58 30 69 32 50 22 54 35 37 32 27 43 32Z"/><path d="m15 77 20-5 15 7 15-7 20 5M22 85h56" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.bolt = '<path d="m55 15-26 39h17l-4 30 29-44H53Z"/><path d="m25 33-8 7 8 7m50-14 8 7-8 7" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.impact = '<path d="m50 15 7 24 22-12-12 22 22 7-24 7 12 22-22-12-5 24-7-24-22 12 12-22-24-7 24-7-12-22 22 12Z"/><circle cx="50" cy="56" r="9" fill="#fff5c7"/>'
$symbols.orb = '<circle cx="50" cy="50" r="20"/><ellipse cx="50" cy="50" rx="35" ry="12" fill="none" stroke="#fff5c7" stroke-width="3" transform="rotate(-25 50 50)"/><circle cx="50" cy="50" r="7" fill="#fff5c7"/>'
$symbols.void = '<circle cx="50" cy="50" r="20"/><ellipse cx="50" cy="50" rx="37" ry="12" fill="none" stroke="#fff5c7" stroke-width="3" transform="rotate(-25 50 50)"/><circle cx="50" cy="50" r="6" fill="#01170d"/>'
$symbols.chains = '<path d="M24 38a12 12 0 0 1 17-17l10 10-8 8-10-10a3 3 0 0 0-4 4l10 10-8 8Zm52 24a12 12 0 0 1-17 17L49 69l8-8 10 10a3 3 0 0 0 4-4L61 57l8-8Z"/><path d="m40 61 22-22m-27 4 24 24" stroke="#fff5c7" stroke-width="3"/>'
$symbols.portal = '<ellipse cx="50" cy="50" rx="22" ry="34" fill="none" stroke="#fff5c7" stroke-width="4"/><ellipse cx="50" cy="50" rx="11" ry="24" fill="none" stroke="#ffe58a" stroke-width="3"/><path d="M18 76q32 19 64 0" fill="none" stroke="#ffe58a" stroke-width="3"/>'
$symbols.rain = '<path d="M50 18 55 32 70 26 63 41 79 45 64 53 72 68 55 64 50 81 44 64 28 69 36 53 21 45 37 41 30 26 45 32Z"/><path d="M23 80 17 88m23-8-5 8m25-8-2 8m22-8-7 8" stroke="#fff5c7" stroke-width="3" stroke-linecap="round"/>'
$symbols.dagger = '<path d="M68 17 55 58 48 72 42 60 54 49Z"/><path d="m42 60-12 8 12 4 6 10 6-10 12-8-11 1Z"/><path d="M65 21 51 53" stroke="#fff5c7" stroke-width="2.5"/>'
$symbols.slash = '<path d="M19 68Q44 29 80 26 62 43 35 77l-16 5Z"/><path d="M20 84Q46 67 70 38" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.shadow = '<path d="M50 17q-25 16-22 40 2 17 22 27 20-10 22-27 3-24-22-40Z"/><path d="M38 52h7m10 0h7m-22 9q10 12 20 0" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.execution = '<path d="M50 16 57 39 81 29 68 50 84 67 59 63 50 86 42 63 17 67 33 50 20 29 44 39Z"/><path d="M31 31 69 69M69 31 31 69" stroke="#fff5c7" stroke-width="2"/>'
$symbols.sun = '<circle cx="50" cy="50" r="16"/><path d="M50 12v14m0 48v14M12 50h14m48 0h14M23 23l10 10m34 34 10 10m0-54L67 33M33 67 23 77" stroke="#fff5c7" stroke-width="4" stroke-linecap="round"/>'
$symbols.leaf = '<path d="M77 22Q34 20 25 47q-8 24 20 29 27 4 32-54Z"/><path d="M27 74Q47 51 68 34M43 57l-2-14m15 2 12 1" fill="none" stroke="#fff5c7" stroke-width="3" stroke-linecap="round"/>'
$symbols.beam = '<path d="M13 44h50l24 6-24 6H13Z"/><circle cx="31" cy="50" r="7" fill="#fff5c7"/><path d="M56 37v26" stroke="#ffe58a" stroke-width="3"/>'
$symbols.halo = '<circle cx="50" cy="53" r="20" fill="none" stroke="#fff5c7" stroke-width="5"/><path d="M25 29q25-21 50 0M50 10v10m-33 7-7-8m73 8 7-8M50 36v34m-13-17h26" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.arrow = '<path d="M18 75 70 23l9-3-3 10-52 52Z"/><path d="m60 33 13 13m-43 16L18 49l-5 23 23-5Z" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.leafslash = '<path d="M17 71Q46 57 78 25M27 75Q50 64 73 34" fill="none" stroke="#ffe58a" stroke-width="6"/><path d="M34 62Q28 39 47 34q-1 15-13 28m16-12q2-21 25-25-6 18-25 25Z"/>'
$symbols.roots = '<path d="M50 18v28m0-12L31 27m19 7 19-11M50 45l-21 9-7 24m28-33 21 10 7 24M50 47v36M29 54l-9-10m9 10-12 4m54-4 9-10m-9 10 12 4m-34 13-12 9m12-9 13 9" fill="none" stroke="#fff5c7" stroke-width="4" stroke-linecap="round"/>'
$symbols.arrows = '<path d="m27 70 4-38 9 8 9-20 9 20 9-8 4 38-22 15Z"/><path d="M50 19v60M30 39l20 18 20-18" fill="none" stroke="#fff5c7" stroke-width="2.5"/>'
$symbols.revolver = '<path d="M23 34h44q9 0 9 9v8H57l-6 8H37l-4-8H23Z"/><path d="M39 59h16l-4 20H39l-5-18m30-28v-7m8 9 6-5"/><circle cx="39" cy="42" r="8" fill="none" stroke="#fff5c7" stroke-width="3"/><circle cx="39" cy="42" r="2" fill="#fff5c7"/>'
$symbols.roll = '<path d="M25 61q2-25 27-28 21-2 27 15 4 12-8 22H38Z"/><circle cx="50" cy="28" r="10"/><path d="m27 66-10 10m56-1 10 6M39 54l12 11 16-13" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.coin = '<circle cx="49" cy="49" r="18"/><circle cx="49" cy="49" r="12" fill="none" stroke="#fff5c7" stroke-width="2"/><path d="M28 72Q48 80 71 72M32 27l-9-8m48 8 9-8M24 53l-10 2m72-2 10 2" fill="none" stroke="#ffe58a" stroke-width="3"/>'
$symbols.crosshair = '<circle cx="50" cy="50" r="23" fill="none" stroke="#ffe58a" stroke-width="4"/><circle cx="50" cy="50" r="8" fill="none" stroke="#fff5c7" stroke-width="3"/><path d="M50 12v20m0 36v20M12 50h20m36 0h20" stroke="#fff5c7" stroke-width="3"/>'
$symbols.rapier = '<path d="M73 17 53 61l-5 10-4-13 20-43Z"/><path d="m44 58-13 7 13 4 5 10 5-10 12-7-12 1Z"/><path d="m67 23-17 39" stroke="#fff5c7" stroke-width="2.5"/>'
$symbols.parry = '<path d="M29 22 48 56 43 68 35 59 20 31Zm42 0L52 56l5 12 8-9 15-28Z"/><path d="M50 42v35m-9-26 9 8 9-8" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.thrust = '<path d="M50 12 58 49 50 86 42 49Z"/><path d="M34 37 50 47l16-10M50 49l-29-7m29 7 29-7" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.xslash = '<path d="M21 28 30 19 79 70 70 79Zm49-9 9 9-49 51-9-9Z"/><path d="m27 33 40 41m0-41L27 74" stroke="#fff5c7" stroke-width="2"/>'
$symbols.crystal = '<path d="m50 15 22 22-6 34-16 14-16-14-6-34Z"/><path d="m50 15-1 34 23-12M49 49 34 71l16 14m-1-36 18 22" fill="none" stroke="#fff5c7" stroke-width="3"/>'
$symbols.spikes = '<path d="m16 70 13-40 12 40 10-54 12 54 10-35 11 35Z"/><path d="M17 78h66" stroke="#fff5c7" stroke-width="3"/>'
$symbols.blizzard = '<path d="M50 17v66M21 33l58 34M21 67l58-34" stroke="#fff5c7" stroke-width="4" stroke-linecap="round"/><circle cx="50" cy="50" r="8"/>'

foreach ($class in $classes) {
  for ($i = 0; $i -lt 4; $i++) {
    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 100 100">
<defs><radialGradient id="bg"><stop stop-color="$($class.bg1)"/><stop offset=".76" stop-color="$($class.bg2)"/><stop offset="1" stop-color="$($class.bg3)"/></radialGradient><linearGradient id="metal" x2="0" y2="1"><stop stop-color="$($class.pale)"/><stop offset=".42" stop-color="$($class.hue)"/><stop offset=".76" stop-color="$($class.metal)"/><stop offset="1" stop-color="$($class.pale)"/></linearGradient><filter id="glow" x="-70%" y="-70%" width="240%" height="240%"><feGaussianBlur stdDeviation="1.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
<rect width="100" height="100" fill="url(#bg)"/>
<ellipse cx="50" cy="84" rx="29" ry="3.5" fill="none" stroke="url(#metal)" stroke-width="1.7"/>
<ellipse cx="50" cy="84" rx="22" ry="2" fill="none" stroke="$($class.hue)" stroke-width="1.5" opacity=".9"/>
<circle cx="50" cy="49" r="30" fill="none" stroke="$($class.hue)" stroke-width="8" opacity=".25" filter="url(#glow)"/>
<circle cx="50" cy="49" r="27" fill="none" stroke="url(#metal)" stroke-width="1.7"/>
<circle cx="50" cy="49" r="22" fill="none" stroke="$($class.pale)" stroke-width=".8" stroke-dasharray="2 3" opacity=".95"/>
<path d="M50 15V8m0 84v-7M16 49H9m82 0h-7M26 25l-5-5m58 58-5-5m0-48 5-5m-58 58 5-5" stroke="url(#metal)" stroke-width="2.4" stroke-linecap="round"/>
<g fill="url(#metal)" stroke="url(#metal)" filter="url(#glow)">$($symbols[$class.shapes[$i]])</g>
<path d="M18 42q-4 7 0 14m64-14q4 7 0 14" fill="none" stroke="$($class.hue)" stroke-width="1.5"/>
<path d="m18 82 2 5 5 1-5 2-2 5-2-5-5-2 5-1Zm64 0 2 5 5 1-5 2-2 5-2-5-5-2 5-1Z" fill="$($class.pale)" filter="url(#glow)"/>
</svg>
"@
    $path = Join-Path $out "$($class.id)_$($i+1).svg"
    Set-Content -Path $path -Value $svg -Encoding utf8
    Write-Output "$($class.id)_$($i+1) - $($class.names[$i])"
  }
}


