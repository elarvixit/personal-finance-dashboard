# Minimal static file server for the Ledgerline dashboard.
# Usage: powershell -ExecutionPolicy Bypass -File serve.ps1 [-Port 8080]
param([int]$Port = 8080)

$root = $PSScriptRoot
$types = @{
  '.html'='text/html; charset=utf-8'; '.css'='text/css; charset=utf-8'; '.js'='text/javascript; charset=utf-8'
  '.json'='application/json'; '.csv'='text/csv'; '.svg'='image/svg+xml'; '.png'='image/png'; '.ico'='image/x-icon'
}

# Mirrors the Vercel /api/config function: Supabase settings come from environment
# variables, or from .env.local next to this script (re-read on every request).
function Get-SupabaseConfig {
  $vals = @{}
  $envFile = Join-Path $root '.env.local'
  if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
      if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$' -and -not $line.TrimStart().StartsWith('#')) {
        $vals[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
      }
    }
  }
  $pick = { param($names) foreach ($n in $names) {
      $v = [Environment]::GetEnvironmentVariable($n); if ($v) { return $v }
      if ($vals[$n]) { return $vals[$n] } }; return $null }
  $url = & $pick @('SUPABASE_URL','NEXT_PUBLIC_SUPABASE_URL')
  $key = & $pick @('SUPABASE_ANON_KEY','SUPABASE_PUBLISHABLE_KEY','NEXT_PUBLIC_SUPABASE_ANON_KEY','NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY')
  if ($key -and $key.StartsWith('sb_secret_')) { $key = $null; Write-Host 'Ignoring SUPABASE_ANON_KEY: it is a secret key, use the anon/publishable key.' }
  return (@{ supabaseUrl = $url; supabaseAnonKey = $key } | ConvertTo-Json -Compress)
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "Ledgerline running at http://localhost:$Port/  (Ctrl+C to stop)"

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    # Each request is handled on its own so one failure never stops the server.
    try {
      $req = $ctx.Request
      $res = $ctx.Response
      $path = [Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
      if ([string]::IsNullOrEmpty($path)) { $path = 'index.html' }
      $file = [IO.Path]::GetFullPath((Join-Path $root $path))

      if ($path -eq 'api/config') {
        $res.ContentType = 'application/json; charset=utf-8'
        $res.Headers['Cache-Control'] = 'no-store'
        $bytes = [Text.Encoding]::UTF8.GetBytes((Get-SupabaseConfig))
      } elseif ($file.StartsWith($root) -and (Test-Path $file -PathType Leaf) -and -not ($path -split '[\\/]' | Where-Object { $_.StartsWith('.') })) {
        $bytes = [IO.File]::ReadAllBytes($file)
        $ext = [IO.Path]::GetExtension($file).ToLower()
        $res.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
        $res.Headers['Cache-Control'] = 'no-cache'
      } else {
        $res.StatusCode = 404
        $res.ContentType = 'text/plain; charset=utf-8'
        $bytes = [Text.Encoding]::UTF8.GetBytes('Not found')
      }

      if ($req.HttpMethod -ne 'HEAD') { $res.OutputStream.Write($bytes, 0, $bytes.Length) }
      Write-Host "$($req.HttpMethod) /$path -> $($res.StatusCode)"
    } catch {
      Write-Host "Request error: $($_.Exception.Message)"
    } finally {
      try { $ctx.Response.Close() } catch {}
    }
  }
} finally {
  $listener.Stop()
}
