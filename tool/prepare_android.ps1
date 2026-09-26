$ErrorActionPreference = 'Stop'

flutter create --platforms=android --org com.example --project-name circuit_solver .

$kotlinDirectory = 'android/app/src/main/kotlin/com/example/circuit_solver'
New-Item -ItemType Directory -Force -Path $kotlinDirectory | Out-Null
Copy-Item -Force 'tool/android/MainActivity.kt' "$kotlinDirectory/MainActivity.kt"
Copy-Item -Force 'tool/android/AndroidManifest.xml' 'android/app/src/main/AndroidManifest.xml'
$xmlDirectory = 'android/app/src/main/res/xml'
New-Item -ItemType Directory -Force -Path $xmlDirectory | Out-Null
Copy-Item -Force 'tool/android/file_paths.xml' "$xmlDirectory/file_paths.xml"

Write-Host 'Android platform files are ready.'
