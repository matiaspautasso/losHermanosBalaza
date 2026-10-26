# bal.ps1 — helper de pruebas para hablar con la balanza Systel Cuora por el puerto serie.
# NO es el driver de produccion: es codigo de referencia usado en la sesion del 2026-10-26.
# Uso:   . .\kit\herramientas\bal.ps1     (dot-source) y luego, por ejemplo:
#        F62 '8000'                       # leer la ficha completa de un PLU
#        F31                              # lista de PLU con su letra de gestion (hashtable)
#        F33 '8000' '1' '020000' '015000' # cambiar precios (pesos enteros, version '1')
#        F4  '8000' '1' ($enc.GetBytes('PRUEBA KG')) -tipo P   # alta/modif. (precio 000000)
#        F5  '8000'                       # borrar un PLU (irreversible)
# Requisitos: puente frenado (comparten el COM), puerto COM3 (cambiar en Send si es otro).
# Escribir SOLO sobre el PLU de prueba 8000. Ver CLAUDE.md y descubrimientos/.
# Notas: nombres en Latin-1; F72 pesa ~7 KB (si se lee, usar ReadBufferSize grande).
$ErrorActionPreference = 'Stop'
$enc = [Text.Encoding]::GetEncoding(28591)   # latin1: 1 byte = 1 char, sin pérdida

function Xor([byte[]]$b) { $x = 0; foreach ($v in $b) { $x = $x -bxor $v }; [byte]$x }

function Frame([byte]$fn, [byte[]]$data) {
  $body = [byte[]](0x14, $fn) + $data
  $body + (Xor $body)
}

function Send([byte[]]$req, [int]$wait = 1500, [int]$tries = 6) {
  for ($i = 1; $i -le $tries; $i++) {
    $p = New-Object System.IO.Ports.SerialPort 'COM3', 115200, 'None', 8, 'One'
    try {
      $p.Open(); $p.DiscardInBuffer(); $p.Write($req, 0, $req.Length)
      Start-Sleep -Milliseconds $wait
      $n = $p.BytesToRead; $b = New-Object byte[] $n
      if ($n) { [void]$p.Read($b, 0, $n) }
    } finally { if ($p.IsOpen) { $p.Close() } }
    $busy = ($b.Length -eq 5 -and $b[2] -eq 0x45 -and $b[3] -eq 0x33)   # 'E3'
    if (-not $busy) { return , $b }
    Start-Sleep -Seconds 3
  }
  return , $b
}

function Txt([byte[]]$b) { $enc.GetString($b) }
function Hex([byte[]]$b) { ($b | ForEach-Object { $_.ToString('x2') }) -join ' ' }
function Ok([byte[]]$b) { $b.Length -ge 6 -and (Xor $b[0..($b.Length - 2)]) -eq $b[$b.Length - 1] }

function Resp([byte[]]$b) {
  if ($b.Length -eq 5 -and $b[2] -eq 0x45) { return "ERROR " + (Txt $b[2..3]) }
  if ($b.Length -eq 6 -and (Txt $b[2..4]) -eq 'ACK') { return 'ACK' }
  return "RAW " + (Hex $b)
}

function Pad([string]$s, [int]$n) { $s.PadRight($n).Substring(0, $n) }

function F62([string]$plu) {
  $r = Send (Frame 62 ($enc.GetBytes($plu)))
  if ($r.Length -lt 60) { return [pscustomobject]@{ plu = $plu; error = (Resp $r) } }
  $d = $r[2..($r.Length - 2)]          # datos (sin 14 3E ni XOR)
  [pscustomobject]@{
    plu = Txt $d[0..3]; gestion = Txt $d[4..4]; nombre = Txt $d[5..22]
    nombreHex = Hex $d[5..22]; p1 = Txt $d[23..28]; p2 = Txt $d[29..34]
    codigo = Txt $d[35..39]; sector = Txt $d[40..41]; dias = Txt $d[42..45]
    tipo = Txt $d[46..46]; tara = Txt $d[47..50]; agua = Txt $d[51..54]
    xorOk = (Ok $r); bytes = $r.Length; raw = $r
  }
}

function F31() {
  $r = Send ([byte[]](0x14, 0x1F, 0x0B)) 2500
  if ($r.Length -lt 20) { return @{ error = (Resp $r) } }
  $s = Txt $r
  $m = [regex]::Matches($s, 'N(\d{4})V(.)')
  $h = @{}; foreach ($x in $m) { $h[$x.Groups[1].Value] = $x.Groups[2].Value }
  $h
}

function F33([string]$plu, [string]$ver, [string]$p1, [string]$p2) {
  Resp (Send (Frame 33 ($enc.GetBytes($plu + $ver + $p1 + $p2))))
}

function F5([string]$plu) { Resp (Send (Frame 5 ($enc.GetBytes($plu)))) }

# Registro F4 (55 chars de datos); $nombre se pasa como bytes latin1 para probar la Ñ
function F4([string]$plu, [string]$ver, [byte[]]$nombre, [string]$p1 = '000000', [string]$p2 = '000000',
            [string]$codigo = '00000', [string]$sector = '01', [string]$dias = '0000',
            [string]$tipo = 'P', [string]$tara = '000000', [string]$mant = 'N') {
  $nm = New-Object byte[] 18; for ($i = 0; $i -lt 18; $i++) { $nm[$i] = 0x20 }
  [Array]::Copy($nombre, $nm, [Math]::Min(18, $nombre.Length))
  $head = $enc.GetBytes($plu + $ver)
  $tail = $enc.GetBytes($p1 + $p2 + $codigo + $sector + $dias + $tipo + $tara + $mant + 'N')
  Resp (Send (Frame 4 ($head + $nm + $tail)))
}

