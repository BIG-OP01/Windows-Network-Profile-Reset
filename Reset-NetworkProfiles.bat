@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM 指定UTF-8編碼顯示中文 
chcp 65001 >nul

echo ==================================================
echo  網路重置工具 (詳細模式) 
echo ==================================================
echo.

REM ==================================================
REM 0) 確保以系統管理員身分執行
REM ==================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo [INFO] 權限不足，嘗試以系統管理員身分重新啟動...
  powershell -NoProfile -Command ^
    "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo [成功] 已取得系統管理員權限。
echo.

REM ==================================================
REM 1) 取得桌面路徑
REM ==================================================
echo 1.取得桌面路徑... 
for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"') do set "DESKTOP=%%D"
if "%DESKTOP%"=="" (
  echo [失敗] 無法取得桌面路徑
  pause
  exit /b 1
)
echo [成功] %DESKTOP%
echo.

set "MARKER=%DESKTOP%\自動啟用網卡指令執行.txt"
set "CMD_FILE=%DESKTOP%\Enable-Network.cmd"

set "TMP_LIST=%TEMP%\targets_%RANDOM%.txt"
set "TMP_ENC=%TEMP%\enc_%RANDOM%.txt"

REM ==================================================
REM 2) 取得啟用中的實體網路介面卡清單
REM ==================================================
echo 2.取得啟用中的實體網路介面卡清單... 
powershell -NoProfile -Command ^
 "Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true } | Select-Object -ExpandProperty Name" ^
 > "%TMP_LIST%" 2>nul

if not exist "%TMP_LIST%" (
  echo [失敗] 無法取得網路介面卡清單 
  pause
  exit /b 1
)

REM 檢查是否空檔
for %%A in ("%TMP_LIST%") do if %%~zA==0 (
  echo [失敗] 找不到任何啟用中的實體網路介面卡
  del /f /q "%TMP_LIST%" >nul 2>&1
  pause
  exit /b 1
)

echo [成功] 
echo ----- 網卡清單 ----- 
type "%TMP_LIST%"
echo ---------------- 
echo.

choice /c YN /n /m "是否繼續下一步?[Y/N] "
if errorlevel 2 (
  echo 已停止程式。 
  del /f /q "%TMP_LIST%" >nul 2>&1
  del /f /q "%TMP_ENC%"  >nul 2>&1
  REM 等待 1 秒後關閉
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^^
    "Start-Sleep -Seconds 1"
  exit /b 0
)
echo.

REM ==================================================
REM 3) 建立狀態標記檔 ( marker 檔含時間戳 + 清單）
REM ==================================================
echo 3.建立狀態標記檔... 
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH:mm:ss"') do set "TS=%%T"

(
  echo 【注意】 
  echo 自動啟用網卡指令執行中 
  echo.
  echo 建立時間：%TS%
  echo.
  echo 以下為此次將被重新啟用的網卡清單：
  for /f "delims=" %%N in ('type "%TMP_LIST%"') do echo  - %%N
  echo.
  echo 判定方式（嚴格但符合實際 / 選項A）：
  echo → 名單中每張網卡必須「不是 Disabled 且不是 Not Present」（允許 Disconnected）
  echo.
  echo 若重開後此檔仍存在，表示尚未完全恢復，請手動確認：
  echo Get-NetAdapter ^| ft Name,Status,HardwareInterface -Auto
) > "%MARKER%"

if not exist "%MARKER%" (
  echo [失敗] 狀態標記檔建立失敗
  del /f /q "%TMP_LIST%" >nul 2>&1
  pause
  exit /b 1
)
echo [成功] %MARKER%
echo.

REM ==================================================
REM 4) 建立 Enable-Network.cmd ( batch 直接產生，用於啟動被停用的網路介面卡)  
REM   依賴變數：TMP_LIST, MARKER, CMD_FILE 
REM ==================================================
echo 4.建立 Enable-Network.cmd... 

REM 4-1) 從 TMP_LIST 組成 NAMES（用 ;; 分隔）
set "NAMES="
for /f "usebackq delims=" %%N in ("%TMP_LIST%") do (
  if defined NAMES (
    set "NAMES=!NAMES!;;%%N"
  ) else (
    set "NAMES=%%N"
  )
)

REM 4-2) 產生 Enable-Network.cmd 到 %CMD_FILE%
(
  echo @echo off
  echo setlocal EnableExtensions
  echo.
  echo REM 指定UTF-8編碼顯示中文 
  echo chcp 65001 ^>nul
  echo.
  echo REM ==================================================
  echo REM ====== 0^) 被停用的網路介面卡清單（用;;分隔）======
  echo REM ==================================================
  echo set "NAMES=%NAMES%"
  echo set "MARKER=%MARKER%"
  echo.
  echo echo [0] 被停用的網路介面卡清單 = %%NAMES%%
  echo echo.
  echo REM ==================================================
  echo REM ====== 1^) 檢查所有的網路介面卡狀態 ======
  echo REM ==================================================
  echo echo [1] 檢查所有的網路卡狀態...
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^^
  echo   "Get-NetAdapter | ft Name,Status,HardwareInterface -Auto"
  echo echo.
  echo REM ==================================================
  echo REM ====== 2^) 驗證清單中的網路介面卡是否存在 ======
  echo REM ==================================================
  echo echo [2] 驗證清單中的網路介面卡是否存在...
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^^
  echo   "$names=$env:NAMES -split ';;'; $missing=0; foreach($n in $names){ Write-Host ('== ' + $n + ' =='); $a=Get-NetAdapter -Name $n -ErrorAction SilentlyContinue; if($a){ $a | Format-List Name,Status,HardwareInterface,ifIndex } else { Write-Host '  [不存在]'; $missing=1 } }; if($missing){ exit 1 } else { exit 0 }"
  echo set "RC=%%errorlevel%%"
  echo REM echo [2] ExitCode=%%RC%%
  echo echo.
  echo REM ==================================================
  echo REM ====== 3^) 逐張啟用（顯示成功/失敗原因）======
  echo REM ==================================================
  echo echo [3] 啟用網路介面卡...
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^^
  echo   "$names=$env:NAMES -split ';;'; $fail=0; foreach($n in $names){ Write-Host ('[Enable] '+$n); try{ Enable-NetAdapter -Name $n -Confirm:$false -ErrorAction Stop | Out-Null; Write-Host '  OK' } catch { Write-Host ('  FAIL: '+$_.Exception.Message); $fail=1 } }; if($fail){ exit 1 } else { exit 0 }"
  echo set "RC=%%errorlevel%%"
  echo REM echo [3] ExitCode=%%RC%%
  echo echo.
  echo REM ==================================================
  echo REM ====== 4^) 檢查狀態 ======
  echo REM ==================================================
  echo REM 等待 2 秒後檢查，避免系統反應不及...
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^^
  echo   "Start-Sleep -Seconds 2"
  echo echo.
  echo echo [4] 檢查啟用的網路介面卡狀態...
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^^
  echo   "$names=$env:NAMES -split ';;'; foreach($n in $names){ $a=Get-NetAdapter -Name $n -ErrorAction SilentlyContinue; if($a){ Write-Host ('[狀態] '+$n+' => '+$a.Status) } else { Write-Host ('[狀態] '+$n+' => Not found') } }"
  echo echo.
  echo REM ==================================================
  echo REM ====== 5^) 嚴格判定：不是 Disabled 且不是 Not Present ======
  echo REM ==================================================
  echo echo [5] 執行嚴格判定...
  echo powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^^
  echo   "$names=$env:NAMES -split ';;'; $ok=0; foreach($n in $names){ $a=Get-NetAdapter -Name $n -ErrorAction SilentlyContinue; if($a -and $a.Status -ne 'Disabled' -and $a.Status -ne 'Not Present'){ $ok++ } }; Write-Host ('ok='+$ok+'/'+$names.Count); if($names.Count -gt 0 -and $ok -eq $names.Count){ exit 0 } else { exit 1 }"
  echo set "RC=%%errorlevel%%"
  echo REM echo [5] ExitCode=%%RC%%
  echo echo.
  echo REM ==================================================
  echo REM ====== 6^) 依結果決定：成功則刪除狀態標記檔 + 自刪 ======
  echo REM ==================================================
  echo if not "%%RC%%"=="0" ^(
  echo   echo [結果] 失敗 - 部分網路介面卡未通過驗證，請確認 自動啟用網卡指令執行.txt 內的網路介面卡清單。 
  echo   echo.
  echo   pause
  echo ^) else ^(
  echo   echo [結果] 成功
  echo   echo.
  echo   REM 刪除狀態標記檔 
  echo   if defined MARKER ^(
  echo     if exist "%%MARKER%%" ^(
  echo       echo 刪除標記檔：%%MARKER%%
  echo       del "%%MARKER%%" /f /q ^>nul 2^>^&1
  echo     ^)
  echo   ^)
  echo   REM 延遲刪除自己 
  echo   echo 即將刪除本檔案...
  echo   start "" cmd /c "timeout /t 2 >nul & del "%%~f0""
  echo ^)
  echo.
  echo endlocal
  echo exit /b %%RC%%
) > "%CMD_FILE%"

if not exist "%CMD_FILE%" (
  echo [失敗] Enable-Network.cmd 未生成：%CMD_FILE%
  pause
  exit /b 1
)

echo [成功] %CMD_FILE%
echo.

REM ==================================================
REM 5) 註冊 RunOnce (開機後執行 Enable-Network.cmd ) 
REM ==================================================
echo 5.註冊 RunOnce... 
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce" ^
 /v ReEnableNetwork ^
 /t REG_SZ ^
 /d "cmd /c \"%CMD_FILE%\"" /f >nul 2>&1

if not %errorlevel%==0 (
  echo [失敗] RunOnce 寫入失敗
  del /f /q "%TMP_LIST%" >nul 2>&1
  del /f /q "%TMP_ENC%"  >nul 2>&1
  pause
  exit /b 1
)

echo [成功]
echo.

REM ==================================================
REM 6) 停用網路介面卡（只停用名單中的） 
REM ==================================================
echo 6.停用網路介面卡... 
set "DIS_FAIL=0"
for /f "delims=" %%N in ('type "%TMP_LIST%"') do (
  echo - 停用：%%N
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Disable-NetAdapter -Name \"%%N\" -Confirm:$false -ErrorAction Stop | Out-Null"
  if not !errorlevel!==0 (
    echo   ^> [失敗] 停用 %%N 失敗
    set "DIS_FAIL=1"
  ) else (
    echo   ^> [成功]
  )
)

if "%DIS_FAIL%"=="1" (
  echo [注意] 部分網路介面卡停用失敗，建議先確認狀態再繼續。
  echo.
) else (
  echo [成功]
  echo.
)

REM ==================================================
REM 7) 清除 NetworkList (Profiles + Signatures) 
REM ==================================================
echo 7.清除 NetworkList 登錄檔(Profiles + Signatures) ... 
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles" /f >nul 2>&1
set "E1=%errorlevel%"
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\Unmanaged" /f >nul 2>&1
set "E2=%errorlevel%"

REM 若 key 不存在，reg delete 也會回非0；這裡視為「已清乾淨」(存在才刪、沒有也算成功)
echo [成功]
echo.

REM 清除暫存
del /f /q "%TMP_LIST%" >nul 2>&1
del /f /q "%TMP_ENC%"  >nul 2>&1

REM ==================================================
REM 8) 重新啟動（問答）
REM ==================================================
choice /c YN /n /m "已完成設定，是否立即重新啟動系統?[Y/N] "
if errorlevel 2 (
  echo.
  echo 目前網卡已被停用，需等待系統重新啟動。 
  echo （重開後登入會自動執行 RunOnce -> Enable-Network.cmd）
  echo.
  pause
  exit /b 0
)

echo.
echo 系統即將重新啟動...
shutdown /r /t 5
exit /b 0
