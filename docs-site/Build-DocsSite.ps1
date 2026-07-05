# docs-site/Build-DocsSite.ps1 — Baut die statische OUPilot-Doku-Site aus den
# Repo-Markdown-Dateien nach docs-site\site\ (self-contained, No-CDN, Light/Dark).
# Aufruf i. d. R. ueber ..\run-docs.ps1.
param(
    [string]$OutDir
)
$ErrorActionPreference = 'Stop'

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo    = Split-Path -Parent $here
if (-not $OutDir) { $OutDir = Join-Path $here 'site' }

Import-Module (Join-Path $here 'Convert-Markdown.psm1') -Force -DisableNameChecking

# Seiten-Manifest: Quelle -> Zieldatei + Navigationstitel.
$pages = @(
    [ordered]@{ Src = 'README.md';                     Out = 'index.html';      Nav = 'Überblick' }
    [ordered]@{ Src = 'docs/Testclient-Checkliste.md'; Out = 'testclient.html'; Nav = 'Testclient-Checkliste' }
    [ordered]@{ Src = 'CHANGELOG.md';                   Out = 'changelog.html';  Nav = 'Changelog' }
)

# Interne Markdown-Links auf die generierten Seiten umbiegen.
$linkMap = @{
    'README.md'                     = 'index.html'
    'CHANGELOG.md'                  = 'changelog.html'
    'docs/Testclient-Checkliste.md' = 'testclient.html'
}

# Version aus dem CHANGELOG ziehen (erster "## X.Y.Z"-Eintrag).
$version = '1.4.0'
$clPath  = Join-Path $repo 'CHANGELOG.md'
if (Test-Path $clPath) {
    $vm = Select-String -Path $clPath -Pattern '^\#\#\s+(\d+\.\d+\.\d+)' | Select-Object -First 1
    if ($vm) { $version = $vm.Matches[0].Groups[1].Value }
}
$stamp = (Get-Date -Format 'yyyy-MM-dd HH:mm')

function Read-Utf8 { param([string]$Path)
    $t = [System.IO.File]::ReadAllText($Path)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }  # BOM strip
    return $t
}

$css = @'
:root{
  --bg:#f6f8fb; --surface:#ffffff; --side:#eef2f7; --side-line:#dbe2ea;
  --text:#1b2430; --muted:#586573; --border:#d7dee7; --code-bg:#eef1f5;
  --accent:#215d99; --accent-soft:#d6e6f5; --accent-ink:#0e4373;
  --ok:#177245; --warn:#a8620f; --shadow:0 1px 2px rgba(20,35,55,.06),0 4px 16px rgba(20,35,55,.06);
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#0e1218; --surface:#151b23; --side:#0b0f15; --side-line:#232c37;
    --text:#e6edf5; --muted:#93a1b1; --border:#28323e; --code-bg:#1a212b;
    --accent:#5aa2ea; --accent-soft:#17304a; --accent-ink:#a9cdf3;
    --ok:#4cc38a; --warn:#e0a458; --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 28px rgba(0,0,0,.35);
  }
}
:root[data-theme="light"]{
  --bg:#f6f8fb; --surface:#ffffff; --side:#eef2f7; --side-line:#dbe2ea;
  --text:#1b2430; --muted:#586573; --border:#d7dee7; --code-bg:#eef1f5;
  --accent:#215d99; --accent-soft:#d6e6f5; --accent-ink:#0e4373;
  --ok:#177245; --warn:#a8620f; --shadow:0 1px 2px rgba(20,35,55,.06),0 4px 16px rgba(20,35,55,.06);
}
:root[data-theme="dark"]{
  --bg:#0e1218; --surface:#151b23; --side:#0b0f15; --side-line:#232c37;
  --text:#e6edf5; --muted:#93a1b1; --border:#28323e; --code-bg:#1a212b;
  --accent:#5aa2ea; --accent-soft:#17304a; --accent-ink:#a9cdf3;
  --ok:#4cc38a; --warn:#e0a458; --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 28px rgba(0,0,0,.35);
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{
  margin:0; background:var(--bg); color:var(--text);
  font-family:"Segoe UI",-apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif;
  font-size:16px; line-height:1.62; -webkit-font-smoothing:antialiased;
}
code,pre,.mono{font-family:"Cascadia Code","Consolas","SFMono-Regular",Menlo,monospace}
a{color:var(--accent); text-decoration:none}
a:hover{text-decoration:underline}
.layout{display:grid; grid-template-columns:290px minmax(0,1fr); min-height:100vh}
/* Sidebar */
.sidebar{
  background:var(--side); border-right:1px solid var(--side-line);
  padding:22px 18px; position:sticky; top:0; align-self:start; height:100vh; overflow-y:auto;
}
.brand{display:flex; align-items:baseline; gap:10px; font-weight:700; font-size:19px; letter-spacing:.2px}
.brand .glyph{font-size:22px}
.brand small{display:block; font-weight:500; font-size:12px; color:var(--muted); letter-spacing:.14em; text-transform:uppercase; margin-top:2px}
.nav{margin-top:26px; display:flex; flex-direction:column; gap:2px}
.nav a.top{
  display:block; padding:7px 11px; border-radius:7px; color:var(--text);
  font-weight:600; font-size:14.5px;
}
.nav a.top:hover{background:var(--surface); text-decoration:none}
.nav a.top.active{background:var(--accent); color:#fff}
.subnav{margin:2px 0 8px 6px; padding-left:10px; border-left:2px solid var(--side-line);
  display:flex; flex-direction:column; gap:1px}
.subnav a{display:block; padding:4px 9px; border-radius:6px; color:var(--muted); font-size:13px}
.subnav a:hover{background:var(--surface); color:var(--text); text-decoration:none}
.side-foot{margin-top:26px; padding-top:16px; border-top:1px solid var(--side-line);
  color:var(--muted); font-size:12.5px; line-height:1.8}
.side-foot .badge{display:inline-block; background:var(--accent-soft); color:var(--accent-ink);
  padding:1px 8px; border-radius:20px; font-weight:600; font-size:12px}
/* Content */
.content{padding:46px 8vw 96px; min-width:0}
.article{max-width:820px; margin:0 auto}
.article h1{font-size:2.05rem; line-height:1.15; margin:.2em 0 .5em; text-wrap:balance; letter-spacing:-.01em}
.article h2{font-size:1.4rem; margin:2.1em 0 .5em; padding-top:.5em; border-top:1px solid var(--border); text-wrap:balance}
.article h3{font-size:1.13rem; margin:1.6em 0 .4em}
.article h4{font-size:1rem; margin:1.3em 0 .3em; color:var(--muted); text-transform:uppercase; letter-spacing:.06em}
.article p{margin:.7em 0}
.article ul,.article ol{margin:.6em 0; padding-left:1.4em}
.article li{margin:.28em 0}
.article li>ul,.article li>ol{margin:.2em 0}
.article a{overflow-wrap:anywhere}
.article strong{font-weight:700}
.article code{background:var(--code-bg); padding:.12em .4em; border-radius:5px; font-size:.9em; border:1px solid var(--border)}
.article pre{background:var(--code-bg); border:1px solid var(--border); border-radius:10px;
  padding:14px 16px; overflow-x:auto; box-shadow:var(--shadow)}
.article pre code{background:none; border:none; padding:0; font-size:.86em; line-height:1.55}
.article blockquote{margin:1em 0; padding:.5em 1em; border-left:4px solid var(--warn);
  background:var(--code-bg); border-radius:0 8px 8px 0; color:var(--text)}
.article blockquote p{margin:.2em 0}
.article hr{border:none; border-top:1px solid var(--border); margin:2.2em 0}
.table-wrap{overflow-x:auto; margin:1.1em 0; border:1px solid var(--border); border-radius:10px; box-shadow:var(--shadow)}
.article table{border-collapse:collapse; width:100%; font-size:.94em; background:var(--surface)}
.article th,.article td{padding:8px 13px; text-align:left; border-bottom:1px solid var(--border); vertical-align:top}
.article thead th{background:var(--code-bg); font-weight:700; border-bottom:2px solid var(--border)}
.article tbody tr:last-child td{border-bottom:none}
/* Task-Listen */
.article ul li.task{list-style:none; margin-left:-1.2em; padding-left:1.9em; position:relative}
.article li.task .chk{position:absolute; left:0; top:.28em; width:15px; height:15px; border-radius:4px;
  border:1.5px solid var(--border); background:var(--surface)}
.article li.task .chk.on{background:var(--accent); border-color:var(--accent)}
.article li.task .chk.on::after{content:"✓"; color:#fff; font-size:11px; position:absolute; left:2px; top:-3px}
/* Theme-Toggle */
.theme-toggle{position:fixed; top:16px; right:18px; z-index:10; width:38px; height:38px; border-radius:9px;
  border:1px solid var(--border); background:var(--surface); color:var(--text); cursor:pointer;
  font-size:16px; box-shadow:var(--shadow)}
.theme-toggle:hover{border-color:var(--accent)}
@media (max-width:860px){
  .layout{grid-template-columns:1fr}
  .sidebar{position:static; height:auto; border-right:none; border-bottom:1px solid var(--side-line)}
  .content{padding:32px 6vw 72px}
}
@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
'@

function Build-Nav { param($Active, $Headings)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<nav class="nav">')
    foreach ($p in $pages) {
        $isActive = ($p.Out -eq $Active)
        $cls = if ($isActive) { 'top active' } else { 'top' }
        [void]$sb.Append("<a class=""$cls"" href=""$($p.Out)"">$($p.Nav)</a>")
        if ($isActive -and $Headings) {
            $subs = @($Headings | Where-Object { $_.Level -eq 2 })
            if ($subs.Count -gt 0) {
                [void]$sb.Append('<div class="subnav">')
                foreach ($h in $subs) { [void]$sb.Append("<a href=""#$($h.Id)"">$($h.Text)</a>") }
                [void]$sb.Append('</div>')
            }
        }
    }
    [void]$sb.Append('</nav>')
    return $sb.ToString()
}

function New-Page { param([string]$Title, [string]$Body, [string]$Nav)
    $head = @"
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$Title — OUPilot Doku</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<button class="theme-toggle" id="themeToggle" title="Hell/Dunkel umschalten" aria-label="Theme umschalten">◐</button>
<div class="layout">
<aside class="sidebar">
  <div class="brand"><span class="glyph">🧭</span><span>OUPilot<small>Dokumentation</small></span></div>
  $Nav
  <div class="side-foot">
    <span class="badge">v$version</span><br>
    <a href="https://github.com/monoeagle/lucent-job-OUPilot" target="_blank" rel="noopener">GitHub-Repo</a><br>
    Generiert: $stamp
  </div>
</aside>
<main class="content"><article class="article">
$Body
</article></main>
</div>
<script>
(function(){
  var root=document.documentElement, KEY="oup-doc-theme";
  var saved=localStorage.getItem(KEY);
  if(saved){root.setAttribute("data-theme",saved);}
  document.getElementById("themeToggle").addEventListener("click",function(){
    var cur=root.getAttribute("data-theme");
    if(!cur){cur=window.matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light";}
    var next=cur==="dark"?"light":"dark";
    root.setAttribute("data-theme",next);
    localStorage.setItem(KEY,next);
  });
})();
</script>
</body>
</html>
"@
    return $head
}

# ── Build ────────────────────────────────────────────────────────────────────
if (Test-Path $OutDir) { Get-ChildItem $OutDir -File -ErrorAction SilentlyContinue | Remove-Item -Force }
[void](New-Item -ItemType Directory -Path $OutDir -Force)
[System.IO.File]::WriteAllText((Join-Path $OutDir 'style.css'), $css, (New-Object System.Text.UTF8Encoding($false)))

$built = 0
foreach ($p in $pages) {
    $srcPath = Join-Path $repo $p.Src
    if (-not (Test-Path $srcPath)) { Write-Warning "Quelle fehlt: $($p.Src)"; continue }
    $md = Read-Utf8 $srcPath
    $res = ConvertFrom-OupMarkdown -Markdown $md
    $body = $res.Html

    # Interne Links umbiegen (href="...md" -> generierte Seite).
    foreach ($k in $linkMap.Keys) {
        $body = $body.Replace("href=""$k""", "href=""$($linkMap[$k])""")
    }

    $nav  = Build-Nav -Active $p.Out -Headings $res.Headings
    $html = New-Page -Title $p.Nav -Body $body -Nav $nav
    [System.IO.File]::WriteAllText((Join-Path $OutDir $p.Out), $html, (New-Object System.Text.UTF8Encoding($false)))
    $built++
}

Write-Host ("Doku-Site gebaut: {0} Seite(n) + style.css -> {1}" -f $built, $OutDir)
return (Join-Path $OutDir 'index.html')
