$ErrorActionPreference = "Stop"

$VERSION = if ($env:VERSION) { $env:VERSION } else { "0.0.0" }
$ARCH = "x64"

function Reset-Dir($p) {
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    New-Item -ItemType Directory $p | Out-Null
}

function Download-Once($url, $out) {
    if (!(Test-Path $out)) {
        Invoke-WebRequest $url -OutFile $out
    }
}

python .\build.py --portable --flutter --skip-portable-pack

if (!(Test-Path ".\flutter\build\windows\x64\runner\Release")) {
    exit 1
}

Reset-Dir .\rustdesk
Copy-Item .\flutter\build\windows\x64\runner\Release\* .\rustdesk -Recurse -Force

Download-Once `
  https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip `
  usbmmidd_v2.zip

Reset-Dir .\usbmmidd_v2_tmp
Expand-Archive usbmmidd_v2.zip -DestinationPath .\usbmmidd_v2_tmp -Force

Remove-Item -Recurse -Force .\usbmmidd_v2_tmp\Win32 -ErrorAction SilentlyContinue
Remove-Item .\usbmmidd_v2_tmp\deviceinstaller64.exe,
             .\usbmmidd_v2_tmp\deviceinstaller.exe,
             .\usbmmidd_v2_tmp\usbmmidd.bat -ErrorAction SilentlyContinue

Copy-Item .\usbmmidd_v2_tmp .\rustdesk\usbmmidd_v2 -Recurse -Force

try {
    Download-Once https://github.com/rustdesk/hbb_common/releases/download/driver/rustdesk_printer_driver_v4-1.4.zip rustdesk_printer_driver_v4-1.4.zip
    Download-Once https://github.com/rustdesk/hbb_common/releases/download/driver/printer_driver_adapter.zip printer_driver_adapter.zip
    Download-Once https://github.com/rustdesk/hbb_common/releases/download/driver/sha256sums sha256sums

    $driverSum = (Select-String sha256sums "rustdesk_printer_driver_v4-1.4.zip").Line.Split(" ")[0]
    $driverHash = (Get-FileHash rustdesk_printer_driver_v4-1.4.zip -Algorithm SHA256).Hash
    $adapterSum = (Select-String sha256sums "printer_driver_adapter.zip").Line.Split(" ")[0]
    $adapterHash = (Get-FileHash printer_driver_adapter.zip -Algorithm SHA256).Hash

    if ($driverSum -eq $driverHash -and $adapterSum -eq $adapterHash) {
        Reset-Dir .\rustdesk\drivers\RustDeskPrinterDriver
        Expand-Archive rustdesk_printer_driver_v4-1.4.zip -DestinationPath .\tmp_driver -Force
        Copy-Item .\tmp_driver\* .\rustdesk\drivers\RustDeskPrinterDriver -Recurse -Force
        Remove-Item .\tmp_driver -Recurse -Force

        Expand-Archive printer_driver_adapter.zip -DestinationPath .\tmp_adapter -Force
        Copy-Item .\tmp_adapter\printer_driver_adapter.dll .\rustdesk -Force
        Remove-Item .\tmp_adapter -Recurse -Force
    }
} catch {}

$runnerRes = Get-ChildItem -Recurse -Filter Runner.res | Select-Object -First 1
if ($runnerRes) {
    Copy-Item $runnerRes.FullName .\libs\portable\Runner.res -Force
}

(Get-Content res\manifest.xml) | Where-Object { $_ -notmatch "dpiAware" } | Set-Content res\manifest.xml

Push-Location .\libs\portable
python -m pip install -r requirements.txt
python .\generate.py -f ..\..\rustdesk\ -o . -e ..\..\rustdesk\rustdesk.exe
Pop-Location

New-Item -ItemType Directory .\SignOutput -ErrorAction SilentlyContinue | Out-Null
Remove-Item .\SignOutput\* -Force -ErrorAction SilentlyContinue
Move-Item .\target\release\rustdesk-portable-packer.exe .\SignOutput\rustdesk-$VERSION-$ARCH.exe -Force

# Push-Location .\res\msi
# python preprocess.py --arp -d ..\..\rustdesk
# msbuild msi.sln -t:Restore
# msbuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
# Move-Item .\Package\bin\x64\Release\en-us\Package.msi ..\..\SignOutput\rustdesk-$VERSION-$ARCH.msi -Force
# Pop-Location