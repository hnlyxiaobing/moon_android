# W8 CLI 退出码矩阵本地实跑（T-W8-1…T-W8-6 证据采集）。
Set-Location $PSScriptRoot\..
$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "PASS $name" } else { Write-Output "FAIL $name"; $script:fail = 1 }
}

$g = moon run cmd/main -- gates 2>$null
Check "T-W8-1 gates exit0+7lines" (($LASTEXITCODE -eq 0) -and ($g.Count -eq 7))

$r = moon run cmd/main -- render 2>$null
Check "T-W8-2 render exit0+shebang" (($LASTEXITCODE -eq 0) -and ($r[0] -eq "#!/bin/sh"))
Check "T-W8-2 render DO-NOT-EXECUTE" (($r -join "`n").Contains("DO NOT EXECUTE"))

$bad = moon run cmd/main -- render --package bad 2>&1 | Out-String
Check "T-W8-3 badpkg exit1" ($LASTEXITCODE -eq 1)
Check "T-W8-3 stderr InvalidPackage" ($bad.Contains("InvalidPackage"))

moon run cmd/main -- nonsense 2>$null | Out-Null
Check "T-W8-4 usage exit2" ($LASTEXITCODE -eq 2)

$secret = "password" + "=abc"
$k = moon run cmd/main -- render --keystore-ref $secret 2>&1 | Out-String
Check "T-W8-5 key exit1" ($LASTEXITCODE -eq 1)
Check "T-W8-5 stderr KeyMaterialEmbedded" ($k.Contains("KeyMaterialEmbedded"))
$kout = moon run cmd/main -- render --keystore-ref $secret 2>$null
Check "T-W8-5 stdout no secret" (-not (($kout -join "`n").Contains($secret)))

$t = moon run cmd/main -- template 2>$null
Check "template exit0+shebang" (($LASTEXITCODE -eq 0) -and ($t[0] -eq "#!/bin/sh"))

$p = moon run cmd/main -- probe-jdk --java-home C:\Java\jdk-17 --java-version 17.0.9 --existing C:/Java/jdk-17 2>$null
Check "probe-jdk found exit0" (($LASTEXITCODE -eq 0) -and ($p[0] -eq "status: JdkFound"))

$s = moon run cmd/main -- probe-jdk --strict --java-home C:\Java\jdk-17 --existing C:/Java/jdk-17 2>$null
Check "probe-jdk strict exit1" (($LASTEXITCODE -eq 1) -and ($s[0] -eq "status: JdkVersionUnmatched"))

moon run cmd/main -- render --min-sdk abc 2>$null | Out-Null
Check "bad sdk value exit2" ($LASTEXITCODE -eq 2)

Write-Output "cli-smoke fail=$fail"
exit $fail