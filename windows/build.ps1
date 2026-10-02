param(
    [switch]$Run
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$srcDir = Join-Path $scriptDir "src"
$distDir = Join-Path $scriptDir "dist"
$outExe = Join-Path $distDir "Tidebar.exe"
$icoPath = Join-Path $scriptDir "app.ico"

# 确保输出目录存在
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

# 若本地 app.ico 不存在，尝试从原始参考目录复制
if (-not (Test-Path $icoPath)) {
    $refIco = Join-Path $scriptDir "..\_原始参考\app.ico"
    if (Test-Path $refIco) {
        Copy-Item -Path $refIco -Destination $icoPath -Force -ErrorAction SilentlyContinue
    }
}

# 停止可能正在运行的 Tidebar 旧实例释放二进制文件锁（仅匹配 Tidebar 进程名）
Get-Process -Name "Tidebar" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$wpfDir = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF"

if (-not (Test-Path $csc)) {
    Write-Error "未找到内置 .NET 编译器: $csc"
    exit 1
}

Write-Host "正在使用 Windows 内置 C# 编译器构建 Tidebar..." -ForegroundColor Cyan

$refs = @(
    "mscorlib.dll",
    "System.dll",
    "System.Core.dll",
    "System.Drawing.dll",
    "System.Windows.Forms.dll",
    "PresentationFramework.dll",
    "PresentationCore.dll",
    "WindowsBase.dll",
    "System.Xaml.dll",
    "System.Web.Extensions.dll"
) -join ","

$cscParams = @(
    "/codepage:65001",
    "/debug:pdbonly",
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/platform:x64",
    "/lib:$wpfDir",
    "/r:$refs"
)

if (Test-Path $icoPath) {
    $cscParams += "/win32icon:$icoPath"
    Write-Host "✓ 挂载应用图标: $icoPath" -ForegroundColor Cyan
}

$csFiles = Get-ChildItem -Path $srcDir -Filter "*.cs" -Recurse | Select-Object -ExpandProperty FullName
$cscParams += "/out:$outExe"
$cscParams += $csFiles

& $csc $cscParams

if ($LASTEXITCODE -eq 0 -and (Test-Path $outExe)) {
    Write-Host "✓ 编译成功: $outExe" -ForegroundColor Green

    if ($Run) {
        Write-Host "启动 Tidebar..." -ForegroundColor Cyan
        Start-Process $outExe
    }
} else {
    Write-Error "编译失败，退出码: $LASTEXITCODE"
    exit $LASTEXITCODE
}
