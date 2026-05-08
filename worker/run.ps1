# ==============================================================================
# Cat-Nap — Worker Launcher (PowerShell / Windows native)
#
# Usage:
#   .\worker\run.ps1
#   .\worker\run.ps1 --api-url https://cat-nap.replit.app
#
# Optional env vars (set before running, or edit defaults below):
#   $env:CATNAP_API_URL       API URL  (default: https://cat-nap.replit.app)
#   $env:CATNAP_WORKER_NAME   Worker display name
#   $env:CATNAP_GPU_MODEL     GPU label
#   $env:CATNAP_BLENDER_PATH  Full path to blender.exe  (auto-detected if not set)
#   $env:CATNAP_FFMPEG_PATH   Full path to ffmpeg.exe   (auto-detected if not set)
#   $env:CATNAP_HUNYUAN_DIR   Path to Hunyuan3D-2.1 clone (default: ..\Hunyuan3D-2.1)
# ==============================================================================

param(
    [string]$ApiUrl      = "",
    [string]$WorkerName  = "",
    [string]$GpuModel    = "",
    [string]$BlenderPath = "",
    [string]$FfmpegPath  = "",
    [string]$HunyuanDir  = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$VenvDir     = Join-Path $ScriptDir ".venv"
$VenvPy      = Join-Path $VenvDir "Scripts\python.exe"
$VenvPip     = Join-Path $VenvDir "Scripts\pip.exe"

# ── Virtual environment ───────────────────────────────────────────────────────
if (-not (Test-Path $VenvPy)) {
    Write-Host ""
    Write-Host "[run] Creating virtual environment at $VenvDir ..."
    python -m venv $VenvDir
    if (-not (Test-Path $VenvPy)) {
        Write-Error "ERROR: Failed to create venv. Is Python 3.10+ installed and on PATH?"
        exit 1
    }
}

# Activate venv for this process
$activate = Join-Path $VenvDir "Scripts\Activate.ps1"
if (Test-Path $activate) {
    . $activate
}

# ── Auto-install missing dependencies ────────────────────────────────────────
Write-Host "[run] Checking Python dependencies ..."
$missingMods = & $VenvPy -c @"
mods = [
    'requests', 'PIL', 'rembg', 'onnxruntime', 'torch', 'torchvision',
    'diffusers', 'transformers', 'accelerate', 'huggingface_hub',
    'einops', 'scipy', 'trimesh', 'omegaconf', 'timm', 'torchdiffeq',
]
missing = []
for m in mods:
    try:
        __import__(m)
    except Exception:
        missing.append(m)
print(','.join(missing))
"@

if ($missingMods -ne "") {
    Write-Host "[run] Missing: $missingMods"
    Write-Host "[run] Installing from requirements.txt ..."
    & $VenvPip install -r (Join-Path $ScriptDir "requirements.txt")
}

# ── Hunyuan3D-2.1 ─────────────────────────────────────────────────────────────
$hunyuanDir = if ($HunyuanDir -ne "") { $HunyuanDir } `
              elseif ($env:CATNAP_HUNYUAN_DIR) { $env:CATNAP_HUNYUAN_DIR } `
              else { Join-Path $ProjectRoot "Hunyuan3D-2.1" }

if (-not (Test-Path (Join-Path $hunyuanDir "hy3dshape"))) {
    Write-Error @"
ERROR: Hunyuan3D-2.1 not found at: $hunyuanDir
Clone it with:
  git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git "$hunyuanDir"
"@
    exit 1
}

# ── Blender auto-detection ────────────────────────────────────────────────────
function Find-Blender {
    # Explicit arg or env var wins
    if ($BlenderPath -ne "") { return $BlenderPath }
    if ($env:CATNAP_BLENDER_PATH) { return $env:CATNAP_BLENDER_PATH }

    # Scan common Windows install locations
    $drive = Split-Path -Qualifier $ProjectRoot   # e.g. "D:"
    $candidates = @(
        "$drive\blender-5.1.1\blender-5.1.1-windows-x64\blender.exe",
        "$drive\blender-5.1.0\blender-5.1.0-windows-x64\blender.exe",
        "$drive\blender-4.3.2\blender-4.3.2-windows-x64\blender.exe",
        "$drive\blender-4.3.1\blender-4.3.1-windows-x64\blender.exe",
        "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
        "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return ""  # worker.py will search PATH
}

function Find-Ffmpeg {
    if ($FfmpegPath -ne "") { return $FfmpegPath }
    if ($env:CATNAP_FFMPEG_PATH) { return $env:CATNAP_FFMPEG_PATH }

    $drive = Split-Path -Qualifier $ProjectRoot
    $candidates = @(
        "$drive\ffmpeg\bin\ffmpeg.exe",
        "C:\ffmpeg\bin\ffmpeg.exe",
        "C:\ProgramData\chocolatey\bin\ffmpeg.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return ""
}

$resolvedBlender = Find-Blender
$resolvedFfmpeg  = Find-Ffmpeg

# ── Build argument list ───────────────────────────────────────────────────────
$apiUrl     = if ($ApiUrl     -ne "") { $ApiUrl }     elseif ($env:CATNAP_API_URL)     { $env:CATNAP_API_URL }     else { "https://cat-nap.replit.app" }
$workerName = if ($WorkerName -ne "") { $WorkerName } elseif ($env:CATNAP_WORKER_NAME) { $env:CATNAP_WORKER_NAME } else { "Windows-RTX4080S" }
$gpuModel   = if ($GpuModel   -ne "") { $GpuModel }   elseif ($env:CATNAP_GPU_MODEL)   { $env:CATNAP_GPU_MODEL }   else { "NVIDIA RTX 4080 Super" }

$workerArgs = @(
    (Join-Path $ScriptDir "worker.py"),
    "--api-url",     $apiUrl,
    "--worker-name", $workerName,
    "--gpu-model",   $gpuModel,
    "--hunyuan-dir", $hunyuanDir
)
if ($resolvedBlender -ne "") { $workerArgs += "--blender-path", $resolvedBlender }
if ($resolvedFfmpeg  -ne "") { $workerArgs += "--ffmpeg-path",  $resolvedFfmpeg  }

Write-Host ""
Write-Host "Launching worker with:"
Write-Host "  venv:        $VenvDir"
Write-Host "  python:      $VenvPy"
Write-Host "  hunyuan-dir: $hunyuanDir"
Write-Host "  blender:     $(if ($resolvedBlender) { $resolvedBlender } else { '(system PATH)' })"
Write-Host "  ffmpeg:      $(if ($resolvedFfmpeg)  { $resolvedFfmpeg  } else { '(system PATH)' })"
Write-Host "  api-url:     $apiUrl"
Write-Host ""

& $VenvPy @workerArgs
