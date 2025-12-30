@echo off
setlocal EnableExtensions

REM 指定UTF-8編碼顯示中文 
chcp 65001 >nul

REM ==================================================
REM ====== 0) 被停用的網路介面卡清單（用;;分隔）======
REM ==================================================
set "NAMES=乙太網路"
set "MARKER=C:\Users\USER\Desktop\自動啟用網卡指令執行.txt"

echo [0] 被停用的網路介面卡清單 = %NAMES%
echo.
REM ==================================================
REM ====== 1) 檢查所有的網路介面卡狀態 ======
REM ==================================================
echo [1] 檢查所有的網路卡狀態...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-NetAdapter | ft Name,Status,HardwareInterface -Auto"
echo.
REM ==================================================
REM ====== 2) 驗證清單中的網路介面卡是否存在 ======
REM ==================================================
echo [2] 驗證清單中的網路介面卡是否存在...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$names=$env:NAMES -split ';;'; $missing=0; foreach($n in $names){ Write-Host ('== ' + $n + ' =='); $a=Get-NetAdapter -Name $n -ErrorAction SilentlyContinue; if($a){ $a | Format-List Name,Status,HardwareInterface,ifIndex } else { Write-Host '  [不存在]'; $missing=1 } }; if($missing){ exit 1 } else { exit 0 }"
set "RC=%errorlevel%"
REM echo [2] ExitCode=%RC%
echo.
REM ==================================================
REM ====== 3) 逐張啟用（顯示成功/失敗原因）======
REM ==================================================
echo [3] 啟用網路介面卡...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$names=$env:NAMES -split ';;'; $fail=0; foreach($n in $names){ Write-Host ('[Enable] '+$n); try{ Enable-NetAdapter -Name $n -Confirm:$false -ErrorAction Stop | Out-Null; Write-Host '  OK' } catch { Write-Host ('  FAIL: '+$_.Exception.Message); $fail=1 } }; if($fail){ exit 1 } else { exit 0 }"
set "RC=%errorlevel%"
REM echo [3] ExitCode=%RC%
echo.
REM ==================================================
REM ====== 4) 檢查狀態 ======
REM ==================================================
REM 等待 2 秒後檢查，避免系統反應不及...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Sleep -Seconds 2"
echo.
echo [4] 檢查啟用的網路介面卡狀態...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$names=$env:NAMES -split ';;'; foreach($n in $names){ $a=Get-NetAdapter -Name $n -ErrorAction SilentlyContinue; if($a){ Write-Host ('[狀態] '+$n+' => '+$a.Status) } else { Write-Host ('[狀態] '+$n+' => Not found') } }"
echo.
REM ==================================================
REM ====== 5) 嚴格判定：不是 Disabled 且不是 Not Present ======
REM ==================================================
echo [5] 執行嚴格判定...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$names=$env:NAMES -split ';;'; $ok=0; foreach($n in $names){ $a=Get-NetAdapter -Name $n -ErrorAction SilentlyContinue; if($a -and $a.Status -ne 'Disabled' -and $a.Status -ne 'Not Present'){ $ok++ } }; Write-Host ('ok='+$ok+'/'+$names.Count); if($names.Count -gt 0 -and $ok -eq $names.Count){ exit 0 } else { exit 1 }"
set "RC=%errorlevel%"
REM echo [5] ExitCode=%RC%
echo.
REM ==================================================
REM ====== 6) 依結果決定：成功則刪除狀態標記檔 + 自刪 ======
REM ==================================================
if not "%RC%"=="0" (
  echo [結果] 失敗 - 部分網路介面卡未通過驗證，請確認 自動啟用網卡指令執行.txt 內的網路介面卡清單。 
  echo.
  pause
) else (
  echo [結果] 成功
  echo.
  REM 刪除狀態標記檔 
  if defined MARKER (
    if exist "%MARKER%" (
      echo 刪除標記檔：%MARKER%
      del "%MARKER%" /f /q >nul 2>&1
    )
  )
  REM 延遲刪除自己 
  echo 即將刪除本檔案...
  start "" cmd /c "timeout /t 2 >nul & del "%~f0""
)

endlocal
exit /b %RC%
