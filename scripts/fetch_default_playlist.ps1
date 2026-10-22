# 从 archive.org 挑选可用的公版名曲 mp3 直链，写入 JSON 供 App 默认歌单使用。
$ErrorActionPreference = "Stop"
$out = "C:\Users\Administrator\Doubao\chats\2026-10-22\new-chat\LingYue\scripts\default_playlist.json"

$titles = @(
  "moonlight sonata", "fur elise", "canon in d", "ode to joy",
  "claire de lune debussy", "nocturne chopin", "gymnopedie",
  "air on the g string bach", "jesus joy of mans desiring", "the entertainer scott joplin",
  "morning mood grieg", "swan lake tchaikovsky", "trout quintet schubert", "four seasons spring vivaldi"
)

$results = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new()

function Test-Url([string]$url) {
  try {
    $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 15
    return ($r.StatusCode -eq 200)
  } catch { return $false }
}

foreach ($t in $titles) {
  if ($results.Count -ge 12) { break }
  $q = 'title:"' + $t + '" AND mediatype:audio AND format:mp3'
  $esc = [uri]::EscapeDataString($q)
  $url = "https://archive.org/advancedsearch.php?q=$esc&fl%5B%5D=identifier&rows=2&output=json"
  $docs = $null
  try { $docs = @((Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 20).response.docs) } catch { $docs = @() }
  foreach ($d in $docs) {
    if ($results.Count -ge 12) { break }
    $id = [string]$d.identifier
    if ($id.Length -lt 2 -or $seen.Contains($id)) { continue }
    $meta = $null
    try { $meta = Invoke-RestMethod -Uri ("https://archive.org/metadata/" + $id) -Method Get -TimeoutSec 20 } catch { continue }
    if ($null -eq $meta) { continue }
    $mp3s = @($meta.files | Where-Object { $_.format -match "MP3|VBR MP3" -or $_.name -match "\.mp3$" })
    if ($mp3s.Count -eq 0) { continue }
    $file = $mp3s | Select-Object -First 1
    $dl = "https://archive.org/download/$id/$($file.name)"
    if (-not (Test-Url $dl)) { continue }
    $seen.Add($id) | Out-Null
    $creator = [string]$meta.metadata.creator
    $title = [string]$meta.metadata.title
    if ([string]::IsNullOrWhiteSpace($title)) { $title = $file.name -replace '\.mp3$','' }
    $results.Add([pscustomobject]@{ title=$title; artist=$creator; url=$dl }) | Out-Null
  }
}

$results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $out -Encoding UTF8
"found=" + $results.Count
foreach ($r in $results) { " - " + $r.title + " | " + $r.artist + " | " + $r.url }
