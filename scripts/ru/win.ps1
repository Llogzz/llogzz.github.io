$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$NC = "`e[0m"

$STORAGE_FILE = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\Cursor\User\globalStorage\backups"

function Generate-RandomString {
    param([int]$Length)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $result = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $result += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $result
}

function Modify-CursorJSFiles {
    Write-Host ""
    Write-Host "$BLUE[Модификация ядра]$NC Начинаю модификацию JS-файлов ядра Cursor для обхода идентификации устройства..."
    Write-Host "$BLUE[План]$NC Использую улучшенную схему перехвата: глубокий перехват модулей + замена someValue"
    Write-Host ""

    $cursorAppPath = "${env:LOCALAPPDATA}\Programs\Cursor"
    if (-not (Test-Path $cursorAppPath)) {
        $alternatePaths = @(
            "${env:ProgramFiles}\Cursor",
            "${env:ProgramFiles(x86)}\Cursor",
            "${env:USERPROFILE}\AppData\Local\Programs\Cursor"
        )

        foreach ($path in $alternatePaths) {
            if (Test-Path $path) {
                $cursorAppPath = $path
                break
            }
        }

        if (-not (Test-Path $cursorAppPath)) {
            Write-Host "$RED[Ошибка]$NC Не найден путь установки приложения Cursor"
            Write-Host "$YELLOW[Подсказка]$NC Убедитесь, что Cursor установлен правильно"
            return $false
        }
    }

    Write-Host "$GREEN[Найдено]$NC Путь установки Cursor: $cursorAppPath"

    $newUuid = [System.Guid]::NewGuid().ToString().ToLower()
    $randomBytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng.GetBytes($randomBytes)
    $machineId = [System.BitConverter]::ToString($randomBytes) -replace '-',''
    $rng.Dispose()
    $deviceId = [System.Guid]::NewGuid().ToString().ToLower()
    $randomBytes2 = New-Object byte[] 32
    $rng2 = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng2.GetBytes($randomBytes2)
    $macMachineId = [System.BitConverter]::ToString($randomBytes2) -replace '-',''
    $rng2.Dispose()
    $sqmId = "{" + [System.Guid]::NewGuid().ToString().ToUpper() + "}"
    $sessionId = [System.Guid]::NewGuid().ToString().ToLower()
    $macAddress = "00:11:22:33:44:55"

    Write-Host "$GREEN[Сгенерировано]$NC Новые идентификаторы устройств созданы"
    Write-Host "   machineId: $($machineId.Substring(0,16))..."
    Write-Host "   deviceId: $($deviceId.Substring(0,16))..."
    Write-Host "   macMachineId: $($macMachineId.Substring(0,16))..."
    Write-Host "   sqmId: $sqmId"

    $idsConfigPath = "$env:USERPROFILE\.cursor_ids.json"
    if (Test-Path $idsConfigPath) {
        Remove-Item -Path $idsConfigPath -Force
        Write-Host "$YELLOW[Очистка]$NC Удален старый файл конфигурации ID"
    }
    $idsConfig = @{
        machineId = $machineId
        macMachineId = $macMachineId
        devDeviceId = $deviceId
        sqmId = $sqmId
        macAddress = $macAddress
        createdAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    $idsConfig | ConvertTo-Json | Set-Content -Path $idsConfigPath -Encoding UTF8
    Write-Host "$GREEN[Сохранено]$NC Новая конфигурация ID сохранена в: $idsConfigPath"

    $jsFiles = @(
        "$cursorAppPath\resources\app\out\main.js"
    )

    $modifiedCount = 0

    Write-Host "$BLUE[Закрытие]$NC Закрываю процессы Cursor для модификации файлов..."
    Stop-AllCursorProcesses -MaxRetries 3 -WaitSeconds 3 | Out-Null

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$cursorAppPath\resources\app\out\backups"

    Write-Host "$BLUE[Резервное копирование]$NC Создаю резервные копии JS-файлов Cursor..."
    try {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

        $originalBackup = "$backupPath\main.js.original"

        foreach ($file in $jsFiles) {
            if (-not (Test-Path $file)) {
                Write-Host "$YELLOW[Предупреждение]$NC Файл не существует: $(Split-Path $file -Leaf)"
                continue
            }

            $fileName = Split-Path $file -Leaf
            $fileOriginalBackup = "$backupPath\$fileName.original"

            if (-not (Test-Path $fileOriginalBackup)) {
                $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
                if ($content -and $content -match "__cursor_patched__") {
                    Write-Host "$YELLOW[Предупреждение]$NC Файл уже изменен, но исходной резервной копии нет, будет использована текущая версия"
                }
                Copy-Item $file $fileOriginalBackup -Force
                Write-Host "$GREEN[Резервное копирование]$NC Исходная резервная копия создана: $fileName"
            } else {
                Write-Host "$BLUE[Восстановление]$NC Восстанавливаю из исходной резервной копии: $fileName"
                Copy-Item $fileOriginalBackup $file -Force
            }
        }

        foreach ($file in $jsFiles) {
            if (Test-Path $file) {
                $fileName = Split-Path $file -Leaf
                Copy-Item $file "$backupPath\$fileName.backup_$timestamp" -Force
            }
        }
        Write-Host "$GREEN[Резервное копирование]$NC Резервная копия с меткой времени создана: $backupPath"
    } catch {
        Write-Host "$RED[Ошибка]$NC Не удалось создать резервную копию: $($_.Exception.Message)"
        return $false
    }

    Write-Host "$BLUE[Модификация]$NC Начинаю модификацию JS-файлов (использую новые идентификаторы устройств)..."

    foreach ($file in $jsFiles) {
        if (-not (Test-Path $file)) {
            Write-Host "$YELLOW[Пропуск]$NC Файл не существует: $(Split-Path $file -Leaf)"
            continue
        }

        Write-Host "$BLUE[Обработка]$NC Обрабатываю: $(Split-Path $file -Leaf)"

        try {
            $content = Get-Content $file -Raw -Encoding UTF8
            $replaced = $false

            $firstSessionDateValue = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

            $placeholders = @(
                @{ Name = 'someValue.machineId';         Value = [string]$machineId },
                @{ Name = 'someValue.macMachineId';      Value = [string]$macMachineId },
                @{ Name = 'someValue.devDeviceId';       Value = [string]$deviceId },
                @{ Name = 'someValue.sqmId';             Value = [string]$sqmId },
                @{ Name = 'someValue.sessionId';         Value = [string]$sessionId },
                @{ Name = 'someValue.firstSessionDate';  Value = [string]$firstSessionDateValue }
            )

            foreach ($ph in $placeholders) {
                $name = $ph.Name
                $jsonValue = ($ph.Value | ConvertTo-Json -Compress)

                $changed = $false

                $doubleLiteral = '"' + $name + '"'
                if ($content.Contains($doubleLiteral)) {
                    $content = $content.Replace($doubleLiteral, $jsonValue)
                    $changed = $true
                }
                $singleLiteral = "'" + $name + "'"
                if ($content.Contains($singleLiteral)) {
                    $content = $content.Replace($singleLiteral, $jsonValue)
                    $changed = $true
                }

                if (-not $changed -and $content.Contains($name)) {
                    $content = $content.Replace($name, $jsonValue)
                    $changed = $true
                }

                if ($changed) {
                    Write-Host "   $GREEN✓$NC [Схема A] Замена $name"
                    $replaced = $true
                }
            }

            $injectCode = @"
;(async function(){/*__cursor_patched__*/
'use strict';
if(globalThis.__cursor_patched__)return;

var __require__=typeof require==='function'?require:null;
if(!__require__){
    try{
        var __m__=await import('module');
        __require__=__m__.createRequire(import.meta.url);
    }catch(e){
        return;
    }
}

globalThis.__cursor_patched__=true;

var __ids__={
    machineId:'$machineId',
    macMachineId:'$macMachineId',
    devDeviceId:'$deviceId',
    sqmId:'$sqmId',
    macAddress:'$macAddress'
};

globalThis.__cursor_ids__=__ids__;

var Module=__require__('module');
var _origReq=Module.prototype.require;
var _hooked=new Map();

Module.prototype.require=function(id){
    var result=_origReq.apply(this,arguments);
    if(_hooked.has(id))return _hooked.get(id);
    var hooked=result;

    if(id==='child_process'){
        var _origExecSync=result.execSync;
        result.execSync=function(cmd,opts){
            var cmdStr=String(cmd).toLowerCase();
            if(cmdStr.includes('reg')&&cmdStr.includes('machineguid')){
                return Buffer.from('\r\n    MachineGuid    REG_SZ    '+__ids__.machineId.substring(0,36)+'\r\n');
            }
            if(cmdStr.includes('ioreg')&&cmdStr.includes('ioplatformexpertdevice')){
                return Buffer.from('"IOPlatformUUID" = "'+__ids__.machineId.substring(0,36).toUpperCase()+'"');
            }
            return _origExecSync.apply(this,arguments);
        };
        hooked=result;
    }
    else if(id==='os'){
        var _origNI=result.networkInterfaces;
        result.networkInterfaces=function(){
            return{'Ethernet':[{address:'192.168.1.100',netmask:'255.255.255.0',family:'IPv4',mac:__ids__.macAddress,internal:false}]};
        };
        hooked=result;
    }
    else if(id==='crypto'){
        var _origCreateHash=result.createHash;
        var _origRandomUUID=result.randomUUID;
        result.createHash=function(algo){
            var hash=_origCreateHash.apply(this,arguments);
            if(algo.toLowerCase()==='sha256'){
                var _origDigest=hash.digest.bind(hash);
                var _origUpdate=hash.update.bind(hash);
                var inputData='';
                hash.update=function(data,enc){inputData+=String(data);return _origUpdate(data,enc);};
                hash.digest=function(enc){
                    if(inputData.includes('MachineGuid')||inputData.includes('IOPlatformUUID')||(inputData.length>=32&&inputData.length<=40)){
                        return enc==='hex'?__ids__.machineId:Buffer.from(__ids__.machineId,'hex');
                    }
                    return _origDigest(enc);
                };
            }
            return hash;
        };
        if(_origRandomUUID){
            var uuidCount=0;
            result.randomUUID=function(){
                uuidCount++;
                if(uuidCount<=2)return __ids__.devDeviceId;
                return _origRandomUUID.apply(this,arguments);
            };
        }
        hooked=result;
    }
    else if(id==='@vscode/deviceid'){
        hooked={...result,getDeviceId:async function(){return __ids__.devDeviceId;}};
    }
    else if(id==='@vscode/windows-registry'){
        var _origGetReg=result.GetStringRegKey;
        hooked={...result,GetStringRegKey:function(hive,path,name){
            if(name==='MachineId'||path.includes('SQMClient'))return __ids__.sqmId;
            if(name==='MachineGuid'||path.includes('Cryptography'))return __ids__.machineId.substring(0,36);
            return _origGetReg?_origGetReg.apply(this,arguments):'';
        }};
    }

    if(hooked!==result)_hooked.set(id,hooked);
    return hooked;
};

console.log('[Cursor ID Modifier] Улучшенный перехват активирован');
})();

"@

            if ($content -match '(\*/\s*\n)') {
                $content = $content -replace '(\*/\s*\n)', "`$1$injectCode"
                Write-Host "   $GREEN✓$NC [Схема B] Код улучшенного перехвата внедрен (после уведомления об авторских правах)"
            } else {
                $content = $injectCode + $content
                Write-Host "   $GREEN✓$NC [Схема B] Код улучшенного перехвата внедрен (в начало файла)"
            }

            Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline

            if ($replaced) {
                Write-Host "$GREEN[Успех]$NC Улучшенная комбинированная схема применена успешно (замена someValue + глубокий перехват)"
            } else {
                Write-Host "$GREEN[Успех]$NC Улучшенный перехват применен успешно"
            }
            $modifiedCount++

        } catch {
            Write-Host "$RED[Ошибка]$NC Не удалось изменить файл: $($_.Exception.Message)"
            $fileName = Split-Path $file -Leaf
            $backupFile = "$backupPath\$fileName.original"
            if (Test-Path $backupFile) {
                Copy-Item $backupFile $file -Force
                Write-Host "$YELLOW[Восстановление]$NC Файл восстановлен из резервной копии"
            }
        }
    }

    if ($modifiedCount -gt 0) {
        Write-Host ""
        Write-Host "$GREEN[Готово]$NC Успешно изменено $modifiedCount JS-файлов"
        Write-Host "$BLUE[Резервное копирование]$NC Исходные файлы сохранены в: $backupPath"
        Write-Host "$BLUE[Объяснение]$NC Использована улучшенная схема перехвата:"
        Write-Host "   • Схема A: Замена заполнителей someValue (стабильные точки привязки, совместимость между версиями)"
        Write-Host "   • Схема B: Глубокий перехват модулей (child_process, crypto, os, @vscode/*)"
        Write-Host "$BLUE[Конфигурация]$NC Файл конфигурации ID: $idsConfigPath"
        return $true
    } else {
        Write-Host "$RED[Неудача]$NC Не удалось изменить ни одного файла"
        return $false
    }
}

function Remove-CursorTrialFolders {
    Write-Host ""
    Write-Host "$GREEN[Основная функция]$NC Выполняю удаление папок для сброса пробного периода Cursor..."
    Write-Host "$BLUE[Объяснение]$NC Эта функция удалит указанные папки Cursor для сброса статуса пробного периода"
    Write-Host ""

    $foldersToDelete = @()

    $adminPaths = @(
        "C:\Users\Administrator\.cursor",
        "C:\Users\Administrator\AppData\Roaming\Cursor"
    )

    $currentUserPaths = @(
        "$env:USERPROFILE\.cursor",
        "$env:APPDATA\Cursor"
    )

    $foldersToDelete += $adminPaths
    $foldersToDelete += $currentUserPaths

    Write-Host "$BLUE[Проверка]$NC Будут проверены следующие папки:"
    foreach ($folder in $foldersToDelete) {
        Write-Host "   📁 $folder"
    }
    Write-Host ""

    $deletedCount = 0
    $skippedCount = 0
    $errorCount = 0

    foreach ($folder in $foldersToDelete) {
        Write-Host "$BLUE[Проверка]$NC Проверяю папку: $folder"

        if (Test-Path $folder) {
            try {
                Write-Host "$YELLOW[Предупреждение]$NC Папка найдена, удаляю..."
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-Host "$GREEN[Успех]$NC Папка удалена: $folder"
                $deletedCount++
            }
            catch {
                Write-Host "$RED[Ошибка]$NC Не удалось удалить папку: $folder"
                Write-Host "$RED[Детали]$NC Сообщение об ошибке: $($_.Exception.Message)"
                $errorCount++
            }
        } else {
            Write-Host "$YELLOW[Пропуск]$NC Папка не существует: $folder"
            $skippedCount++
        }
        Write-Host ""
    }

    Write-Host "$GREEN[Статистика]$NC Статистика завершения операций:"
    Write-Host "   ✅ Успешно удалено: $deletedCount папок"
    Write-Host "   ⏭️  Пропущено: $skippedCount папок"
    Write-Host "   ❌ Ошибок удаления: $errorCount папок"
    Write-Host ""

    if ($deletedCount -gt 0) {
        Write-Host "$GREEN[Готово]$NC Удаление папок завершено!"

        Write-Host "$BLUE[Исправление]$NC Предварительно создаю необходимую структуру каталогов во избежание проблем с правами..."

        $cursorAppData = "$env:APPDATA\Cursor"
        $cursorLocalAppData = "$env:LOCALAPPDATA\cursor"
        $cursorUserProfile = "$env:USERPROFILE\.cursor"

        try {
            if (-not (Test-Path $cursorAppData)) {
                New-Item -ItemType Directory -Path $cursorAppData -Force | Out-Null
            }
            if (-not (Test-Path $cursorUserProfile)) {
                New-Item -ItemType Directory -Path $cursorUserProfile -Force | Out-Null
            }
            Write-Host "$GREEN[Готово]$NC Структура каталогов предварительно создана"
        } catch {
            Write-Host "$YELLOW[Предупреждение]$NC Проблема при предварительном создании каталогов: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW[Подсказка]$NC Не найдены папки для удаления, возможно, уже очищено"
    }
    Write-Host ""
}

function Restart-CursorAndWait {
    Write-Host ""
    Write-Host "$GREEN[Перезапуск]$NC Перезапускаю Cursor для повторного создания файлов конфигурации..."

    if (-not $global:CursorProcessInfo) {
        Write-Host "$RED[Ошибка]$NC Информация о процессе Cursor не найдена, перезапуск невозможен"
        return $false
    }

    $cursorPath = $global:CursorProcessInfo.Path

    if ($cursorPath -is [array]) {
        $cursorPath = $cursorPath[0]
    }

    if ([string]::IsNullOrEmpty($cursorPath)) {
        Write-Host "$RED[Ошибка]$NC Путь Cursor пуст"
        return $false
    }

    Write-Host "$BLUE[Путь]$NC Использую путь: $cursorPath"

    if (-not (Test-Path $cursorPath)) {
        Write-Host "$RED[Ошибка]$NC Исполняемый файл Cursor не существует: $cursorPath"

        $backupPaths = @(
            "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
            "$env:PROGRAMFILES\Cursor\Cursor.exe",
            "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
        )

        $foundPath = $null
        foreach ($backupPath in $backupPaths) {
            if (Test-Path $backupPath) {
                $foundPath = $backupPath
                Write-Host "$GREEN[Найдено]$NC Использую альтернативный путь: $foundPath"
                break
            }
        }

        if (-not $foundPath) {
            Write-Host "$RED[Ошибка]$NC Не удалось найти действительный исполняемый файл Cursor"
            return $false
        }

        $cursorPath = $foundPath
    }

    try {
        Write-Host "$GREEN[Запуск]$NC Запускаю Cursor..."
        $process = Start-Process -FilePath $cursorPath -PassThru -WindowStyle Hidden

        Write-Host "$YELLOW[Ожидание]$NC Ожидаю 20 секунд для полного запуска Cursor и создания файлов конфигурации..."
        Start-Sleep -Seconds 20

        $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
        $maxWait = 45
        $waited = 0

        while (-not (Test-Path $configPath) -and $waited -lt $maxWait) {
            Write-Host "$YELLOW[Ожидание]$NC Ожидаю создания файла конфигурации... ($waited/$maxWait секунд)"
            Start-Sleep -Seconds 1
            $waited++
        }

        if (Test-Path $configPath) {
            Write-Host "$GREEN[Успех]$NC Файл конфигурации создан: $configPath"

            Write-Host "$YELLOW[Ожидание]$NC Ожидаю 5 секунд для полной записи файла конфигурации..."
            Start-Sleep -Seconds 5
        } else {
            Write-Host "$YELLOW[Предупреждение]$NC Файл конфигурации не создан за ожидаемое время"
            Write-Host "$BLUE[Подсказка]$NC Возможно, потребуется вручную запустить Cursor один раз для создания файла конфигурации"
        }

        Write-Host "$YELLOW[Закрытие]$NC Закрываю Cursor для изменения конфигурации..."
        if ($process -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000)
        }

        Get-Process -Name "Cursor" -ErrorAction SilentlyContinue | Stop-Process -Force
        Get-Process -Name "cursor" -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-Host "$GREEN[Готово]$NC Процедура перезапуска Cursor завершена"
        return $true

    } catch {
        Write-Host "$RED[Ошибка]$NC Не удалось перезапустить Cursor: $($_.Exception.Message)"
        Write-Host "$BLUE[Отладка]$NC Детали ошибки: $($_.Exception.GetType().FullName)"
        return $false
    }
}

function Stop-AllCursorProcesses {
    param(
        [int]$MaxRetries = 3,
        [int]$WaitSeconds = 5
    )

    Write-Host "$BLUE[Проверка процессов]$NC Проверяю и закрываю все связанные с Cursor процессы..."

    $cursorProcessNames = @(
        "Cursor",
        "cursor",
        "Cursor Helper",
        "Cursor Helper (GPU)",
        "Cursor Helper (Plugin)",
        "Cursor Helper (Renderer)",
        "CursorUpdater"
    )

    for ($retry = 1; $retry -le $MaxRetries; $retry++) {
        Write-Host "$BLUE[Проверка]$NC Попытка $retry/$MaxRetries проверки процессов..."

        $foundProcesses = @()
        foreach ($processName in $cursorProcessNames) {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                $foundProcesses += $processes
                Write-Host "$YELLOW[Обнаружено]$NC Процесс: $processName (PID: $($processes.Id -join ', '))"
            }
        }

        if ($foundProcesses.Count -eq 0) {
            Write-Host "$GREEN[Успех]$NC Все процессы Cursor закрыты"
            return $true
        }

        Write-Host "$YELLOW[Закрытие]$NC Закрываю $($foundProcesses.Count) процессов Cursor..."

        foreach ($process in $foundProcesses) {
            try {
                $process.CloseMainWindow() | Out-Null
                Write-Host "$BLUE  • Graceful shutdown: $($process.ProcessName) (PID: $($process.Id))$NC"
            } catch {
                Write-Host "$YELLOW  • Graceful shutdown failed: $($process.ProcessName)$NC"
            }
        }

        Start-Sleep -Seconds 3

        foreach ($processName in $cursorProcessNames) {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                foreach ($process in $processes) {
                    try {
                        Stop-Process -Id $process.Id -Force
                        Write-Host "$RED  • Force termination: $($process.ProcessName) (PID: $($process.Id))$NC"
                    } catch {
                        Write-Host "$RED  • Force termination failed: $($process.ProcessName)$NC"
                    }
                }
            }
        }

        if ($retry -lt $MaxRetries) {
            Write-Host "$YELLOW[Ожидание]$NC Ожидаю $WaitSeconds секунд перед повторной проверкой..."
            Start-Sleep -Seconds $WaitSeconds
        }
    }

    Write-Host "$RED[Неудача]$NC После $MaxRetries попыток процессы Cursor все еще запущены"
    return $false
}

function Test-FileAccessibility {
    param(
        [string]$FilePath
    )

    Write-Host "$BLUE[Проверка прав]$NC Проверяю доступ к файлу: $(Split-Path $FilePath -Leaf)"

    if (-not (Test-Path $FilePath)) {
        Write-Host "$RED[Ошибка]$NC Файл не существует"
        return $false
    }

    try {
        $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
        $fileStream.Close()
        Write-Host "$GREEN[Права]$NC Файл доступен для чтения и записи, не заблокирован"
        return $true
    } catch [System.IO.IOException] {
        Write-Host "$RED[Блокировка]$NC Файл заблокирован другим процессом: $($_.Exception.Message)"
        return $false
    } catch [System.UnauthorizedAccessException] {
        Write-Host "$YELLOW[Права]$NC Права доступа к файлу ограничены, пытаюсь изменить права..."

        try {
            $file = Get-Item $FilePath
            if ($file.IsReadOnly) {
                $file.IsReadOnly = $false
                Write-Host "$GREEN[Исправлено]$NC Атрибут 'только для чтения' снят"
            }

            $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
            $fileStream.Close()
            Write-Host "$GREEN[Права]$NC Права доступа успешно исправлены"
            return $true
        } catch {
            Write-Host "$RED[Права]$NC Не удалось исправить права доступа: $($_.Exception.Message)"
            return $false
        }
    } catch {
        Write-Host "$RED[Ошибка]$NC Неизвестная ошибка: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-CursorInitialization {
    Write-Host ""
    Write-Host "$GREEN[Инициализация]$NC Выполняю очистку инициализации Cursor..."
    $BASE_PATH = "$env:APPDATA\Cursor\User"

    $filesToDelete = @(
        (Join-Path -Path $BASE_PATH -ChildPath "globalStorage\state.vscdb"),
        (Join-Path -Path $BASE_PATH -ChildPath "globalStorage\state.vscdb.backup")
    )

    $folderToCleanContents = Join-Path -Path $BASE_PATH -ChildPath "History"
    $folderToDeleteCompletely = Join-Path -Path $BASE_PATH -ChildPath "workspaceStorage"

    Write-Host "$BLUE[Отладка]$NC Базовый путь: $BASE_PATH"

    foreach ($file in $filesToDelete) {
        Write-Host "$BLUE[Проверка]$NC Проверяю файл: $file"
        if (Test-Path $file) {
            try {
                Remove-Item -Path $file -Force -ErrorAction Stop
                Write-Host "$GREEN[Успех]$NC Файл удален: $file"
            }
            catch {
                Write-Host "$RED[Ошибка]$NC Не удалось удалить файл $file: $($_.Exception.Message)"
            }
        } else {
            Write-Host "$YELLOW[Пропуск]$NC Файл не существует, пропускаю удаление: $file"
        }
    }

    Write-Host "$BLUE[Проверка]$NC Проверяю папку для очистки содержимого: $folderToCleanContents"
    if (Test-Path $folderToCleanContents) {
        try {
            Get-ChildItem -Path $folderToCleanContents -Recurse | Remove-Item -Force -Recurse -ErrorAction Stop
            Write-Host "$GREEN[Успех]$NC Содержимое папки очищено: $folderToCleanContents"
        }
        catch {
            Write-Host "$RED[Ошибка]$NC Не удалось очистить папку $folderToCleanContents: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW[Пропуск]$NC Папка не существует, пропускаю очистку: $folderToCleanContents"
    }

    Write-Host "$BLUE[Проверка]$NC Проверяю папку для полного удаления: $folderToDeleteCompletely"
    if (Test-Path $folderToDeleteCompletely) {
        try {
            Remove-Item -Path $folderToDeleteCompletely -Recurse -Force -ErrorAction Stop
            Write-Host "$GREEN[Успех]$NC Папка удалена: $folderToDeleteCompletely"
        }
        catch {
            Write-Host "$RED[Ошибка]$NC Не удалось удалить папку $folderToDeleteCompletely: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW[Пропуск]$NC Папка не существует, пропускаю удаление: $folderToDeleteCompletely"
    }

    Write-Host "$GREEN[Готово]$NC Очистка инициализации Cursor завершена"
    Write-Host ""
}

function Update-MachineGuid {
    try {
        Write-Host "$BLUE[Реестр]$NC Изменяю MachineGuid в системном реестре..."

        $registryPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        if (-not (Test-Path $registryPath)) {
            Write-Host "$YELLOW[Предупреждение]$NC Путь в реестре не существует: $registryPath, создаю..."
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "$GREEN[Информация]$NC Путь в реестре создан"
        }

        $originalGuid = ""
        try {
            $currentGuid = Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction SilentlyContinue
            if ($currentGuid) {
                $originalGuid = $currentGuid.MachineGuid
                Write-Host "$GREEN[Информация]$NC Текущее значение в реестре:"
                Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
                Write-Host "    MachineGuid    REG_SZ    $originalGuid"
            } else {
                Write-Host "$YELLOW[Предупреждение]$NC Значение MachineGuid не существует, будет создано новое"
            }
        } catch {
            Write-Host "$YELLOW[Предупреждение]$NC Не удалось прочитать реестр: $($_.Exception.Message)"
            Write-Host "$YELLOW[Предупреждение]$NC Будет создано новое значение MachineGuid"
        }

        $backupFile = $null
        if ($originalGuid) {
            $backupFile = "$BACKUP_DIR\MachineGuid_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
            Write-Host "$BLUE[Резервное копирование]$NC Создаю резервную копию реестра..."
            $backupResult = Start-Process "reg.exe" -ArgumentList "export", "`"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography`"", "`"$backupFile`"" -NoNewWindow -Wait -PassThru

            if ($backupResult.ExitCode -eq 0) {
                Write-Host "$GREEN[Резервное копирование]$NC Раздел реестра скопирован в: $backupFile"
            } else {
                Write-Host "$YELLOW[Предупреждение]$NC Не удалось создать резервную копию, продолжаю..."
                $backupFile = $null
            }
        }

        $newGuid = [System.Guid]::NewGuid().ToString()
        Write-Host "$BLUE[Генерация]$NC Новый MachineGuid: $newGuid"

        Set-ItemProperty -Path $registryPath -Name MachineGuid -Value $newGuid -Force -ErrorAction Stop

        $verifyGuid = (Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction Stop).MachineGuid
        if ($verifyGuid -ne $newGuid) {
            throw "Проверка реестра не удалась: обновленное значение ($verifyGuid) не соответствует ожидаемому ($newGuid)"
        }

        Write-Host "$GREEN[Успех]$NC Реестр успешно обновлен:"
        Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
        Write-Host "    MachineGuid    REG_SZ    $newGuid"
        return $true
    }
    catch {
        Write-Host "$RED[Ошибка]$NC Операция с реестром не удалась: $($_.Exception.Message)"

        if ($backupFile -and (Test-Path $backupFile)) {
            Write-Host "$YELLOW[Восстановление]$NC Восстанавливаю из резервной копии..."
            $restoreResult = Start-Process "reg.exe" -ArgumentList "import", "`"$backupFile`"" -NoNewWindow -Wait -PassThru

            if ($restoreResult.ExitCode -eq 0) {
                Write-Host "$GREEN[Восстановление успешно]$NC Исходное значение реестра восстановлено"
            } else {
                Write-Host "$RED[Ошибка]$NC Восстановление не удалось, вручную импортируйте файл: $backupFile"
            }
        } else {
            Write-Host "$YELLOW[Предупреждение]$NC Файл резервной копии не найден или его создание не удалось, автоматическое восстановление невозможно"
        }

        return $false
    }
}

function Test-CursorEnvironment {
    param(
        [string]$Mode = "FULL"
    )

    Write-Host ""
    Write-Host "$BLUE[Проверка окружения]$NC Проверяю окружение Cursor..."

    $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
    $cursorAppData = "$env:APPDATA\Cursor"
    $issues = @()

    if (-not (Test-Path $configPath)) {
        $issues += "Файл конфигурации не существует: $configPath"
    } else {
        try {
            $content = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $config = $content | ConvertFrom-Json -ErrorAction Stop
            Write-Host "$GREEN[Проверка]$NC Формат файла конфигурации корректен"
        } catch {
            $issues += "Ошибка формата файла конфигурации: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path $cursorAppData)) {
        $issues += "Каталог данных приложения Cursor не существует: $cursorAppData"
    }

    $cursorPaths = @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:PROGRAMFILES\Cursor\Cursor.exe",
        "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
    )

    $cursorFound = $false
    foreach ($path in $cursorPaths) {
        if (Test-Path $path) {
            Write-Host "$GREEN[Проверка]$NC Установка Cursor найдена: $path"
            $cursorFound = $true
            break
        }
    }

    if (-not $cursorFound) {
        $issues += "Установка Cursor не найдена, убедитесь, что Cursor установлен правильно"
    }

    if ($issues.Count -eq 0) {
        Write-Host "$GREEN[Проверка окружения]$NC Все проверки пройдены"
        return @{ Success = $true; Issues = @() }
    } else {
        Write-Host "$RED[Проверка окружения]$NC Найдено $($issues.Count) проблем:"
        foreach ($issue in $issues) {
            Write-Host "$RED  • ${issue}$NC"
        }
        return @{ Success = $false; Issues = $issues }
    }
}

function Modify-MachineCodeConfig {
    param(
        [string]$Mode = "FULL"
    )

    Write-Host ""
    Write-Host "$GREEN[Конфигурация]$NC Изменяю конфигурацию машинного кода..."

    $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"

    if (-not (Test-Path $configPath)) {
        Write-Host "$RED[Ошибка]$NC Файл конфигурации не существует: $configPath"
        Write-Host ""
        Write-Host "$YELLOW[Решение]$NC Попробуйте следующие шаги:"
        Write-Host "$BLUE  1️⃣  Вручную запустите приложение Cursor$NC"
        Write-Host "$BLUE  2️⃣  Дождитесь полной загрузки Cursor (около 30 секунд)$NC"
        Write-Host "$BLUE  3️⃣  Закройте приложение Cursor$NC"
        Write-Host "$BLUE  4️⃣  Запустите этот скрипт заново$NC"
        Write-Host ""
        Write-Host "$YELLOW[Альтернатива]$NC Если проблема сохраняется:"
        Write-Host "$BLUE  • Выберите опцию 'Сброс окружения + изменение машинного кода'$NC"
        Write-Host "$BLUE  • Эта опция автоматически создаст файл конфигурации$NC"
        Write-Host ""

        $userChoice = Read-Host "Попробовать запустить Cursor для создания файла конфигурации сейчас? (y/n)"
        if ($userChoice -match "^(y|yes)$") {
            Write-Host "$BLUE[Попытка]$NC Пытаюсь запустить Cursor..."
            return Start-CursorToGenerateConfig
        }

        return $false
    }

    if ($Mode -eq "MODIFY_ONLY") {
        Write-Host "$BLUE[Безопасность]$NC Даже в режиме только изменения необходимо убедиться, что процессы Cursor полностью закрыты"
        if (-not (Stop-AllCursorProcesses -MaxRetries 3 -WaitSeconds 3)) {
            Write-Host "$RED[Ошибка]$NC Не удалось закрыть все процессы Cursor, изменение может не удаться"
            $userChoice = Read-Host "Продолжить принудительно? (y/n)"
            if ($userChoice -notmatch "^(y|yes)$") {
                return $false
            }
        }
    }

    if (-not (Test-FileAccessibility -FilePath $configPath)) {
        Write-Host "$RED[Ошибка]$NC Нет доступа к файлу конфигурации, возможно, он заблокирован или недостаточно прав"
        return $false
    }

    try {
        Write-Host "$BLUE[Проверка]$NC Проверяю формат файла конфигурации..."
        $originalContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $originalContent | ConvertFrom-Json -ErrorAction Stop
        Write-Host "$GREEN[Проверка]$NC Формат файла конфигурации корректен"

        Write-Host "$BLUE[Текущая конфигурация]$NC Проверяю существующие свойства телеметрии:"
        $telemetryProperties = @('telemetry.machineId', 'telemetry.macMachineId', 'telemetry.devDeviceId', 'telemetry.sqmId')
        foreach ($prop in $telemetryProperties) {
            if ($config.PSObject.Properties[$prop]) {
                $value = $config.$prop
                $displayValue = if ($value.Length -gt 20) { "$($value.Substring(0,20))..." } else { $value }
                Write-Host "$GREEN  ✓ ${prop}$NC = $displayValue"
            } else {
                Write-Host "$YELLOW  - ${prop}$NC (не существует, будет создано)"
            }
        }
        Write-Host ""
    } catch {
        Write-Host "$RED[Ошибка]$NC Ошибка формата файла конфигурации: $($_.Exception.Message)"
        Write-Host "$YELLOW[Рекомендация]$NC Файл конфигурации может быть поврежден, рекомендуется выбрать опцию 'Сброс окружения + изменение машинного кода'"
        return $false
    }

    $maxRetries = 3
    $retryCount = 0

    while ($retryCount -lt $maxRetries) {
        $retryCount++
        Write-Host ""
        Write-Host "$BLUE[Попытка]$NC Попытка изменения $retryCount/$maxRetries..."

        try {
            Write-Host "$BLUE[Прогресс]$NC 1/6 - Генерирую новые идентификаторы устройств..."

            $MAC_MACHINE_ID = [System.Guid]::NewGuid().ToString()
            $UUID = [System.Guid]::NewGuid().ToString()
            $prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
            $prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
            $randomBytes = New-Object byte[] 32
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($randomBytes)
            $randomPart = [System.BitConverter]::ToString($randomBytes) -replace '-',''
            $rng.Dispose()
            $MACHINE_ID = "${prefixHex}${randomPart}"
            $SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"
            $SERVICE_MACHINE_ID = [System.Guid]::NewGuid().ToString()
            $FIRST_SESSION_DATE = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

            Write-Host "$GREEN[Прогресс]$NC 1/7 - Идентификаторы устройств сгенерированы"

            Write-Host "$BLUE[Прогресс]$NC 2/7 - Создаю каталог для резервных копий..."

            $backupDir = "$env:APPDATA\Cursor\User\globalStorage\backups"
            if (-not (Test-Path $backupDir)) {
                New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
            }

            $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')_retry$retryCount"
            $backupPath = "$backupDir\$backupName"

            Write-Host "$BLUE[Прогресс]$NC 3/7 - Создаю резервную копию исходной конфигурации..."
            Copy-Item $configPath $backupPath -ErrorAction Stop

            if (Test-Path $backupPath) {
                $backupSize = (Get-Item $backupPath).Length
                $originalSize = (Get-Item $configPath).Length
                if ($backupSize -eq $originalSize) {
                    Write-Host "$GREEN[Прогресс]$NC 3/7 - Резервная копия конфигурации создана: $backupName"
                } else {
                    Write-Host "$YELLOW[Предупреждение]$NC Размер резервного файла не совпадает, но продолжаю"
                }
            } else {
                throw "Не удалось создать файл резервной копии"
            }

            Write-Host "$BLUE[Прогресс]$NC 4/7 - Читаю исходную конфигурацию в память..."

            $originalContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $config = $originalContent | ConvertFrom-Json -ErrorAction Stop

            Write-Host "$BLUE[Прогресс]$NC 5/7 - Обновляю конфигурацию в памяти..."

            $propertiesToUpdate = @{
                'telemetry.machineId' = $MACHINE_ID
                'telemetry.macMachineId' = $MAC_MACHINE_ID
                'telemetry.devDeviceId' = $UUID
                'telemetry.sqmId' = $SQM_ID
                'storage.serviceMachineId' = $SERVICE_MACHINE_ID
                'telemetry.firstSessionDate' = $FIRST_SESSION_DATE
            }

            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $value = $property.Value

                if ($config.PSObject.Properties[$key]) {
                    $config.$key = $value
                    Write-Host "$BLUE  ✓ Обновлено свойство: ${key}$NC"
                } else {
                    $config | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
                    Write-Host "$BLUE  + Добавлено свойство: ${key}$NC"
                }
            }

            Write-Host "$BLUE[Прогресс]$NC 6/7 - Атомарно записываю новый файл конфигурации..."

            $tempPath = "$configPath.tmp"
            $updatedJson = $config | ConvertTo-Json -Depth 10

            [System.IO.File]::WriteAllText($tempPath, $updatedJson, [System.Text.Encoding]::UTF8)

            $tempContent = Get-Content $tempPath -Raw -Encoding UTF8
            $tempConfig = $tempContent | ConvertFrom-Json

            $tempVerificationPassed = $true
            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $expectedValue = $property.Value
                $actualValue = $tempConfig.$key

                if ($actualValue -ne $expectedValue) {
                    $tempVerificationPassed = $false
                    Write-Host "$RED  ✗ Проверка временного файла не удалась: ${key}$NC"
                    break
                }
            }

            if (-not $tempVerificationPassed) {
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                throw "Проверка временного файла не удалась"
            }

            Remove-Item $configPath -Force
            Move-Item $tempPath $configPath

            $file = Get-Item $configPath
            $file.IsReadOnly = $false

            Write-Host "$BLUE[Прогресс]$NC 7/7 - Проверяю новый файл конфигурации..."

            $verifyContent = Get-Content $configPath -Raw -Encoding UTF8
            $verifyConfig = $verifyContent | ConvertFrom-Json

            $verificationPassed = $true
            $verificationResults = @()

            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $expectedValue = $property.Value
                $actualValue = $verifyConfig.$key

                if ($actualValue -eq $expectedValue) {
                    $verificationResults += "✓ ${key}: проверка пройдена"
                } else {
                    $verificationResults += "✗ ${key}: проверка не пройдена (ожидалось: ${expectedValue}, фактически: ${actualValue})"
                    $verificationPassed = $false
                }
            }

            Write-Host "$BLUE[Детали проверки]$NC"
            foreach ($result in $verificationResults) {
                Write-Host "   $result"
            }

            if ($verificationPassed) {
                Write-Host "$GREEN[Успех]$NC Попытка $retryCount изменений успешна!"
                Write-Host ""
                Write-Host "$GREEN[Готово]$NC Изменение конфигурации машинного кода завершено!"
                Write-Host "$BLUE[Детали]$NC Обновлены следующие идентификаторы:"
                Write-Host "   🔹 machineId: $MACHINE_ID"
                Write-Host "   🔹 macMachineId: $MAC_MACHINE_ID"
                Write-Host "   🔹 devDeviceId: $UUID"
                Write-Host "   🔹 sqmId: $SQM_ID"
                Write-Host "   🔹 serviceMachineId: $SERVICE_MACHINE_ID"
                Write-Host "   🔹 firstSessionDate: $FIRST_SESSION_DATE"
                Write-Host ""
                Write-Host "$GREEN[Резервное копирование]$NC Исходная конфигурация сохранена в: $backupName"

                Write-Host "$BLUE[machineid]$NC Изменяю файл machineid..."
                $machineIdFilePath = "$env:APPDATA\Cursor\machineid"
                try {
                    if (Test-Path $machineIdFilePath) {
                        $machineIdBackup = "$backupDir\machineid.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                        Copy-Item $machineIdFilePath $machineIdBackup -Force
                        Write-Host "$GREEN[Резервное копирование]$NC Файл machineid скопирован: $machineIdBackup"
                    }
                    [System.IO.File]::WriteAllText($machineIdFilePath, $SERVICE_MACHINE_ID, [System.Text.Encoding]::UTF8)
                    Write-Host "$GREEN[machineid]$NC Файл machineid изменен успешно: $SERVICE_MACHINE_ID"

                    $machineIdFile = Get-Item $machineIdFilePath
                    $machineIdFile.IsReadOnly = $true
                    Write-Host "$GREEN[Защита]$NC Файл machineid установлен в режим 'только для чтения'"
                } catch {
                    Write-Host "$YELLOW[machineid]$NC Не удалось изменить файл machineid: $($_.Exception.Message)"
                    Write-Host "$BLUE[Подсказка]$NC Измените файл вручную: $machineIdFilePath"
                }

                Write-Host "$BLUE[updaterId]$NC Изменяю файл .updaterId..."
                $updaterIdFilePath = "$env:APPDATA\Cursor\.updaterId"
                try {
                    if (Test-Path $updaterIdFilePath) {
                        $updaterIdBackup = "$backupDir\.updaterId.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                        Copy-Item $updaterIdFilePath $updaterIdBackup -Force
                        Write-Host "$GREEN[Резервное копирование]$NC Файл .updaterId скопирован: $updaterIdBackup"
                    }
                    $newUpdaterId = [System.Guid]::NewGuid().ToString()
                    [System.IO.File]::WriteAllText($updaterIdFilePath, $newUpdaterId, [System.Text.Encoding]::UTF8)
                    Write-Host "$GREEN[updaterId]$NC Файл .updaterId изменен успешно: $newUpdaterId"

                    $updaterIdFile = Get-Item $updaterIdFilePath
                    $updaterIdFile.IsReadOnly = $true
                    Write-Host "$GREEN[Защита]$NC Файл .updaterId установлен в режим 'только для чтения'"
                } catch {
                    Write-Host "$YELLOW[updaterId]$NC Не удалось изменить файл .updaterId: $($_.Exception.Message)"
                    Write-Host "$BLUE[Подсказка]$NC Измените файл вручную: $updaterIdFilePath"
                }

                Write-Host "$BLUE[Защита]$NC Устанавливаю защиту файла конфигурации..."
                try {
                    $configFile = Get-Item $configPath
                    $configFile.IsReadOnly = $true
                    Write-Host "$GREEN[Защита]$NC Файл конфигурации установлен в режим 'только для чтения', чтобы предотвратить перезапись Cursor"
                    Write-Host "$BLUE[Подсказка]$NC Путь к файлу: $configPath"
                } catch {
                    Write-Host "$YELLOW[Защита]$NC Не удалось установить атрибут 'только для чтения': $($_.Exception.Message)"
                    Write-Host "$BLUE[Рекомендация]$NC Можно вручную щелкнуть правой кнопкой мыши файл → Свойства → Установить флажок 'Только для чтения'"
                }
                Write-Host "$BLUE [Безопасность]$NC Рекомендуется перезапустить Cursor для вступления изменений в силу"
                return $true
            } else {
                Write-Host "$RED[Неудача]$NC Попытка $retryCount проверки не удалась"
                if ($retryCount -lt $maxRetries) {
                    Write-Host "$BLUE[Восстановление]$NC Восстанавливаю из резервной копии, готовлюсь к повторной попытке..."
                    Copy-Item $backupPath $configPath -Force
                    Start-Sleep -Seconds 2
                    continue
                } else {
                    Write-Host "$RED[Конечная неудача]$NC Все попытки не удались, восстанавливаю исходную конфигурацию"
                    Copy-Item $backupPath $configPath -Force
                    return $false
                }
            }

        } catch {
            Write-Host "$RED[Исключение]$NC Попытка $retryCount вызвала исключение: $($_.Exception.Message)"
            Write-Host "$BLUE[Отладочная информация]$NC Тип ошибки: $($_.Exception.GetType().FullName)"

            if (Test-Path "$configPath.tmp") {
                Remove-Item "$configPath.tmp" -Force -ErrorAction SilentlyContinue
            }

            if ($retryCount -lt $maxRetries) {
                Write-Host "$BLUE[Восстановление]$NC Восстанавливаю из резервной копии, готовлюсь к повторной попытке..."
                if (Test-Path $backupPath) {
                    Copy-Item $backupPath $configPath -Force
                }
                Start-Sleep -Seconds 3
                continue
            } else {
                Write-Host "$RED[Конечная неудача]$NC Все попытки не удались"
                if (Test-Path $backupPath) {
                    Write-Host "$BLUE[Восстановление]$NC Восстанавливаю резервную копию конфигурации..."
                    try {
                        Copy-Item $backupPath $configPath -Force
                        Write-Host "$GREEN[Восстановление]$NC Исходная конфигурация восстановлена"
                    } catch {
                        Write-Host "$RED[Ошибка]$NC Не удалось восстановить резервную копию: $($_.Exception.Message)"
                    }
                }
                return $false
            }
        }
    }

    Write-Host "$RED[Конечная неудача]$NC После $maxRetries попыток изменение не может быть завершено"
    return $false

}

function Start-CursorToGenerateConfig {
    Write-Host "$BLUE[Запуск]$NC Пытаюсь запустить Cursor для создания файла конфигурации..."

    $cursorPaths = @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:PROGRAMFILES\Cursor\Cursor.exe",
        "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
    )

    $cursorPath = $null
    foreach ($path in $cursorPaths) {
        if (Test-Path $path) {
            $cursorPath = $path
            break
        }
    }

    if (-not $cursorPath) {
        Write-Host "$RED[Ошибка]$NC Установка Cursor не найдена, убедитесь, что Cursor установлен правильно"
        return $false
    }

    try {
        Write-Host "$BLUE[Путь]$NC Путь Cursor: $cursorPath"

        $process = Start-Process -FilePath $cursorPath -PassThru -WindowStyle Normal
        Write-Host "$GREEN[Запуск]$NC Cursor запущен, PID: $($process.Id)"

        Write-Host "$YELLOW[Ожидание]$NC Дождитесь полной загрузки Cursor (около 30 секунд)..."
        Write-Host "$BLUE[Подсказка]$NC Вы можете закрыть Cursor вручную после полной загрузки"

        $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
        $maxWait = 60
        $waited = 0

        while (-not (Test-Path $configPath) -and $waited -lt $maxWait) {
            Start-Sleep -Seconds 2
            $waited += 2
            if ($waited % 10 -eq 0) {
                Write-Host "$YELLOW[Ожидание]$NC Ожидаю создания файла конфигурации... ($waited/$maxWait секунд)"
            }
        }

        if (Test-Path $configPath) {
            Write-Host "$GREEN[Успех]$NC Файл конфигурации создан!"
            Write-Host "$BLUE[Подсказка]$NC Теперь можно закрыть Cursor и снова запустить скрипт"
            return $true
        } else {
            Write-Host "$YELLOW[Тайм-аут]$NC Файл конфигурации не создан за ожидаемое время"
            Write-Host "$BLUE[Рекомендация]$NC Вручную выполните в Cursor действие (например, создание нового файла), чтобы вызвать создание конфигурации"
            return $false
        }

    } catch {
        Write-Host "$RED[Ошибка]$NC Не удалось запустить Cursor: $($_.Exception.Message)"
        return $false
    }
}

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[Ошибка]$NC Запустите этот скрипт от имени администратора"
    Write-Host "Щелкните правой кнопкой мыши скрипт и выберите 'Запуск от имени администратора'"
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

Clear-Host
Write-Host @"

    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝

"@
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN🚀   Инструмент сброса пробного периода Cursor          $NC"
Write-Host "$YELLOW📱  Скрипт для сброса идентификаторов устройства Cursor $NC"
Write-Host "$YELLOW🤝  Для обмена знаниями и опытом  $NC"
Write-Host ""
Write-Host "$YELLOW⚡  [Информация] Инструмент предназначен для сброса пробного периода Cursor $NC"
Write-Host "$BLUE================================$NC"

Write-Host ""
Write-Host "$GREEN[Выбор режима]$NC Выберите действие для выполнения:"
Write-Host ""
Write-Host "$BLUE  1️⃣  Только изменить машинный код$NC"
Write-Host "$YELLOW      • Выполнить изменение машинного кода$NC"
Write-Host "$YELLOW      • Внедрить код обхода в основные файлы$NC"
Write-Host "$YELLOW      • Пропустить удаление папок/сброс окружения$NC"
Write-Host "$YELLOW      • Сохранить существующие настройки и данные Cursor$NC"
Write-Host ""
Write-Host "$BLUE  2️⃣  Сбросить окружение + изменить машинный код$NC"
Write-Host "$RED      • Выполнить полный сброс окружения (удаление папок Cursor)$NC"
Write-Host "$RED      • ⚠️  Настройки будут потеряны, сделайте резервную копию$NC"
Write-Host "$YELLOW      • Изменить машинный код$NC"
Write-Host "$YELLOW      • Внедрить код обхода в основные файлы$NC"
Write-Host "$YELLOW      • Это соответствует полному поведению текущего скрипта$NC"
Write-Host ""

do {
    $userChoice = Read-Host "Введите выбор (1 или 2)"
    if ($userChoice -eq "1") {
        Write-Host "$GREEN[Выбор]$NC Вы выбрали: Только изменить машинный код"
        $executeMode = "MODIFY_ONLY"
        break
    } elseif ($userChoice -eq "2") {
        Write-Host "$GREEN[Выбор]$NC Вы выбрали: Сбросить окружение + изменить машинный код"
        Write-Host "$RED[Важное предупреждение]$NC Это действие удалит все файлы конфигурации Cursor!"
        $confirmReset = Read-Host "Подтвердите полный сброс? (введите yes для подтверждения, любую другую клавишу для отмены)"
        if ($confirmReset -eq "yes") {
            $executeMode = "RESET_AND_MODIFY"
            break
        } else {
            Write-Host "$YELLOW[Отмена]$NC Пользователь отменил операцию сброса"
            continue
        }
    } else {
        Write-Host "$RED[Ошибка]$NC Неверный выбор, введите 1 или 2"
    }
} while ($true)

Write-Host ""

if ($executeMode -eq "MODIFY_ONLY") {
    Write-Host "$GREEN[Процесс выполнения]$NC Режим 'Только изменить машинный код' выполнит следующие шаги:"
    Write-Host "$BLUE  1️⃣  Обнаружение файла конфигурации Cursor$NC"
    Write-Host "$BLUE  2️⃣  Резервное копирование существующего файла конфигурации$NC"
    Write-Host "$BLUE  3️⃣  Изменение конфигурации машинного кода$NC"
    Write-Host "$BLUE  4️⃣  Показать информацию о завершении операции$NC"
    Write-Host ""
    Write-Host "$YELLOW[Примечания]$NC"
    Write-Host "$YELLOW  • Не будет удалена ни одна папка или сброшено окружение$NC"
    Write-Host "$YELLOW  • Сохраняются все существующие настройки и данные$NC"
    Write-Host "$YELLOW  • Исходный файл конфигурации автоматически резервируется$NC"
} else {
    Write-Host "$GREEN[Процесс выполнения]$NC Режим 'Сбросить окружение + изменить машинный код' выполнит следующие шаги:"
    Write-Host "$BLUE  1️⃣  Обнаружение и закрытие процессов Cursor$NC"
    Write-Host "$BLUE  2️⃣  Сохранение информации о пути программы Cursor$NC"
    Write-Host "$BLUE  3️⃣  Удаление указанных папок, связанных с пробным периодом Cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\Administrator\.cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\Administrator\AppData\Roaming\Cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\%USERNAME%\.cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\%USERNAME%\AppData\Roaming\Cursor$NC"
    Write-Host "$BLUE  3.5️⃣ Предварительное создание необходимой структуры каталогов во избежание проблем с правами$NC"
    Write-Host "$BLUE  4️⃣  Перезапуск Cursor для создания новых файлов конфигурации$NC"
    Write-Host "$BLUE  5️⃣  Ожидание создания файла конфигурации (максимум 45 секунд)$NC"
    Write-Host "$BLUE  6️⃣  Закрытие процессов Cursor$NC"
    Write-Host "$BLUE  7️⃣  Изменение нового сгенерированного файла конфигурации машинного кода$NC"
    Write-Host "$BLUE  8️⃣  Показать статистику завершения операций$NC"
    Write-Host ""
    Write-Host "$YELLOW[Примечания]$NC"
    Write-Host "$YELLOW  • Не выполняйте вручную операции с Cursor во время работы скрипта$NC"
    Write-Host "$YELLOW  • Рекомендуется закрыть все окна Cursor перед выполнением$NC"
    Write-Host "$YELLOW  • После завершения необходимо перезапустить Cursor$NC"
    Write-Host "$YELLOW  • Исходный файл конфигурации автоматически резервируется в папке backups$NC"
}
Write-Host ""

Write-Host "$GREEN[Подтверждение]$NC Подтвердите, что вы ознакомились с вышеуказанным процессом выполнения"
$confirmation = Read-Host "Продолжить выполнение? (введите y или yes для продолжения, любую другую клавишу для выхода)"
if ($confirmation -notmatch "^(y|yes)$") {
    Write-Host "$YELLOW[Выход]$NC Пользователь отменил выполнение, скрипт завершает работу"
    Read-Host "Нажмите Enter для выхода"
    exit 0
}
Write-Host "$GREEN[Подтверждение]$NC Пользователь подтвердил продолжение выполнения"
Write-Host ""

function Get-CursorVersion {
    try {
        $packagePath = "$env:LOCALAPPDATA\\Programs\\cursor\\resources\\app\\package.json"
        
        if (Test-Path $packagePath) {
            $packageJson = Get-Content $packagePath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Информация]$NC Текущая установленная версия Cursor: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        $altPath = "$env:LOCALAPPDATA\\cursor\\resources\\app\\package.json"
        if (Test-Path $altPath) {
            $packageJson = Get-Content $altPath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Информация]$NC Текущая установленная версия Cursor: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        Write-Host "$YELLOW[Предупреждение]$NC Не удалось определить версию Cursor"
        Write-Host "$YELLOW[Подсказка]$NC Убедитесь, что Cursor установлен правильно"
        return $null
    }
    catch {
        Write-Host "$RED[Ошибка]$NC Не удалось получить версию Cursor: $_"
        return $null
    }
}

$cursorVersion = Get-CursorVersion
Write-Host ""

Write-Host "$YELLOW[Важная подсказка]$NC Последняя версия 1.0.x поддерживается"

Write-Host ""

Write-Host "$GREEN[Проверка]$NC Проверяю процессы Cursor..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE[Отладка]$NC Получаю подробную информацию о процессе $processName:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" |
        Select-Object ProcessId, ExecutablePath, CommandLine |
        Format-List
}

$MAX_RETRIES = 5
$WAIT_TIME = 1

function Close-CursorProcessAndSaveInfo {
    param($processName)

    $global:CursorProcessInfo = $null

    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "$YELLOW[Предупреждение]$NC Обнаружен запущенный $processName"

        $firstProcess = if ($processes -is [array]) { $processes[0] } else { $processes }
        $processPath = $firstProcess.Path

        if ($processPath -is [array]) {
            $processPath = $processPath[0]
        }

        $global:CursorProcessInfo = @{
            ProcessName = $firstProcess.ProcessName
            Path = $processPath
            StartTime = $firstProcess.StartTime
        }
        Write-Host "$GREEN[Сохранение]$NC Информация о процессе сохранена: $($global:CursorProcessInfo.Path)"

        Get-ProcessDetails $processName

        Write-Host "$YELLOW[Операция]$NC Пытаюсь закрыть $processName..."
        Stop-Process -Name $processName -Force

        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }

            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write-Host "$RED[Ошибка]$NC Не удалось закрыть $processName после $MAX_RETRIES попыток"
                Get-ProcessDetails $processName
                Write-Host "$RED[Ошибка]$NC Закройте процесс вручную и повторите попытку"
                Read-Host "Нажмите Enter для выхода"
                exit 1
            }
            Write-Host "$YELLOW[Ожидание]$NC Ожидаю закрытия процесса, попытка $retryCount/$MAX_RETRIES..."
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write-Host "$GREEN[Успех]$NC $processName успешно закрыт"
    } else {
        Write-Host "$BLUE[Подсказка]$NC Процесс $processName не запущен"
        $cursorPaths = @(
            "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
            "$env:PROGRAMFILES\Cursor\Cursor.exe",
            "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
        )

        foreach ($path in $cursorPaths) {
            if (Test-Path $path) {
                $global:CursorProcessInfo = @{
                    ProcessName = "Cursor"
                    Path = $path
                    StartTime = $null
                }
                Write-Host "$GREEN[Обнаружение]$NC Найден путь установки Cursor: $path"
                break
            }
        }

        if (-not $global:CursorProcessInfo) {
            Write-Host "$YELLOW[Предупреждение]$NC Путь установки Cursor не найден, будет использован путь по умолчанию"
            $global:CursorProcessInfo = @{
                ProcessName = "Cursor"
                Path = "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe"
                StartTime = $null
            }
        }
    }
}

if (-not (Test-Path $BACKUP_DIR)) {
    try {
        New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        Write-Host "$GREEN[Каталог резервных копий]$NC Каталог резервных копий создан: $BACKUP_DIR"
    } catch {
        Write-Host "$YELLOW[Предупреждение]$NC Не удалось создать каталог резервных копий: $($_.Exception.Message)"
    }
}

if ($executeMode -eq "MODIFY_ONLY") {
    Write-Host "$GREEN[Начало]$NC Начинаю выполнение функции только изменения машинного кода..."

    $envCheck = Test-CursorEnvironment -Mode "MODIFY_ONLY"
    if (-not $envCheck.Success) {
        Write-Host ""
        Write-Host "$RED[Проверка окружения не удалась]$NC Невозможно продолжить выполнение, обнаружены следующие проблемы:"
        foreach ($issue in $envCheck.Issues) {
            Write-Host "$RED  • ${issue}$NC"
        }
        Write-Host ""
        Write-Host "$YELLOW[Рекомендация]$NC Выберите одно из следующих действий:"
        Write-Host "$BLUE  1️⃣  Выбрать опцию 'Сброс окружения + изменение машинного кода' (рекомендуется)$NC"
        Write-Host "$BLUE  2️⃣  Вручную запустить Cursor один раз, затем снова запустить скрипт$NC"
        Write-Host "$BLUE  3️⃣  Проверить, правильно ли установлен Cursor$NC"
        Write-Host ""
        Read-Host "Нажмите Enter для выхода"
        exit 1
    }

    $configSuccess = Modify-MachineCodeConfig -Mode "MODIFY_ONLY"

    if ($configSuccess) {
        Write-Host ""
        Write-Host "$GREEN[Файл конфигурации]$NC Изменение файла конфигурации машинного кода завершено!"

        Write-Host "$BLUE[Реестр]$NC Изменяю системный реестр..."
        $registrySuccess = Update-MachineGuid

        Write-Host ""
        Write-Host "$BLUE[Обход идентификации устройства]$NC Выполняю функцию внедрения JavaScript..."
        Write-Host "$BLUE[Объяснение]$NC Эта функция напрямую изменяет JS-файлы ядра Cursor для реализации более глубокого обхода идентификации устройства"
        $jsSuccess = Modify-CursorJSFiles

        if ($registrySuccess) {
            Write-Host "$GREEN[Реестр]$NC Системный реестр успешно изменен"

            if ($jsSuccess) {
                Write-Host "$GREEN[JavaScript внедрение]$NC Функция внедрения JavaScript выполнена успешно"
                Write-Host ""
                Write-Host "$GREEN[Готово]$NC Все изменения машинного кода завершены (улучшенная версия)!"
                Write-Host "$BLUE[Детали]$NC Выполнены следующие изменения:"
                Write-Host "$GREEN  ✓ Файл конфигурации Cursor (storage.json)$NC"
                Write-Host "$GREEN  ✓ Системный реестр (MachineGuid)$NC"
                Write-Host "$GREEN  ✓ Внедрение в ядро JavaScript (обход идентификации устройства)$NC"
            } else {
                Write-Host "$YELLOW[JavaScript внедрение]$NC Функция внедрения JavaScript не удалась, но другие функции успешны"
                Write-Host ""
                Write-Host "$GREEN[Готово]$NC Все изменения машинного кода завершены!"
                Write-Host "$BLUE[Детали]$NC Выполнены следующие изменения:"
                Write-Host "$GREEN  ✓ Файл конфигурации Cursor (storage.json)$NC"
                Write-Host "$GREEN  ✓ Системный реестр (MachineGuid)$NC"
                Write-Host "$YELLOW  ⚠ Внедрение в ядро JavaScript (частично неудачно)$NC"
            }

            Write-Host "$BLUE[Защита]$NC Устанавливаю защиту файла конфигурации..."
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN[Защита]$NC Файл конфигурации установлен в режим 'только для чтения', чтобы предотвратить перезапись Cursor"
                Write-Host "$BLUE[Подсказка]$NC Путь к файлу: $configPath"
            } catch {
                Write-Host "$YELLOW[Защита]$NC Не удалось установить атрибут 'только для чтения': $($_.Exception.Message)"
                Write-Host "$BLUE[Рекомендация]$NC Можно вручную щелкнуть правой кнопкой мыши файл → Свойства → Установить флажок 'Только для чтения'"
            }
        } else {
            Write-Host "$YELLOW[Реестр]$NC Изменение реестра не удалось, но изменение файла конфигурации успешно"

            if ($jsSuccess) {
                Write-Host "$GREEN[JavaScript внедрение]$NC Функция внедрения JavaScript выполнена успешно"
                Write-Host ""
                Write-Host "$YELLOW[Частично завершено]$NC Файл конфигурации и внедрение JavaScript завершены, изменение реестра не удалось"
                Write-Host "$BLUE[Рекомендация]$NC Могут потребоваться права администратора для изменения реестра"
                Write-Host "$BLUE[Детали]$NC Выполнены следующие изменения:"
                Write-Host "$GREEN  ✓ Файл конфигурации Cursor (storage.json)$NC"
                Write-Host "$YELLOW  ⚠ Системный реестр (MachineGuid) - неудачно$NC"
                Write-Host "$GREEN  ✓ Внедрение в ядро JavaScript (обход идентификации устройства)$NC"
            } else {
                Write-Host "$YELLOW[JavaScript внедрение]$NC Функция внедрения JavaScript не удалась"
                Write-Host ""
                Write-Host "$YELLOW[Частично завершено]$NC Изменение файла конфигурации завершено, изменение реестра и внедрение JavaScript не удались"
                Write-Host "$BLUE[Рекомендация]$NC Могут потребоваться права администратора для изменения реестра"
            }

            Write-Host "$BLUE[Защита]$NC Устанавливаю защиту файла конфигурации..."
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN[Защита]$NC Файл конфигурации установлен в режим 'только для чтения', чтобы предотвратить перезапись Cursor"
                Write-Host "$BLUE[Подсказка]$NC Путь к файлу: $configPath"
            } catch {
                Write-Host "$YELLOW[Защита]$NC Не удалось установить атрибут 'только для чтения': $($_.Exception.Message)"
                Write-Host "$BLUE[Рекомендация]$NC Можно вручную щелкнуть правой кнопкой мыши файл → Свойства → Установить флажок 'Только для чтения'"
            }
        }

        Write-Host "$BLUE[Подсказка]$NC Теперь можно запустить Cursor с новой конфигурацией машинного кода"
    } else {
        Write-Host ""
        Write-Host "$RED[Неудача]$NC Изменение машинного кода не удалось!"
        Write-Host "$YELLOW[Рекомендация]$NC Попробуйте опцию 'Сброс окружения + изменение машинного кода'"
    }
} else {
    Write-Host "$GREEN[Начало]$NC Начинаю выполнение функции сброса окружения и изменения машинного кода..."

    Close-CursorProcessAndSaveInfo "Cursor"
    if (-not $global:CursorProcessInfo) {
        Close-CursorProcessAndSaveInfo "cursor"
    }

    Write-Host ""
    Write-Host "$RED[Важное предупреждение]$NC ============================================"
    Write-Host "$YELLOW[Напоминание о контроле рисков]$NC Механизм контроля рисков Cursor очень строгий!"
    Write-Host "$YELLOW[Необходимо удалить]$NC Необходимо полностью удалить указанные папки, не должно остаться никаких следов настроек"
    Write-Host "$YELLOW[Предотвращение потери пробной версии Pro]$NC Только тщательная очистка может эффективно предотвратить потерю статуса пробной версии Pro"
    Write-Host "$RED[Важное предупреждение]$NC ============================================"
    Write-Host ""

    Write-Host "$GREEN[Начало]$NC Начинаю выполнение основной функции..."
    Remove-CursorTrialFolders

    Restart-CursorAndWait

    $configSuccess = Modify-MachineCodeConfig
    
    Invoke-CursorInitialization

    if ($configSuccess) {
        Write-Host ""
        Write-Host "$GREEN[Файл конфигурации]$NC Изменение файла конфигурации машинного кода завершено!"

        Write-Host "$BLUE[Реестр]$NC Изменяю системный реестр..."
        $registrySuccess = Update-MachineGuid

        Write-Host ""
        Write-Host "$BLUE[Обход идентификации устройства]$NC Выполняю функцию внедрения JavaScript..."
        Write-Host "$BLUE[Объяснение]$NC Эта функция напрямую изменяет JS-файлы ядра Cursor для реализации более глубокого обхода идентификации устройства"
        $jsSuccess = Modify-CursorJSFiles

        if ($registrySuccess) {
            Write-Host "$GREEN[Реестр]$NC Системный реестр успешно изменен"

            if ($jsSuccess) {
                Write-Host "$GREEN[JavaScript внедрение]$NC Функция внедрения JavaScript выполнена успешно"
                Write-Host ""
                Write-Host "$GREEN[Готово]$NC Все операции завершены (улучшенная версия)!"
                Write-Host "$BLUE[Детали]$NC Выполнены следующие операции:"
                Write-Host "$GREEN  ✓ Удалены папки, связанные с пробной версией Cursor$NC"
                Write-Host "$GREEN  ✓ Очистка инициализации Cursor$NC"
                Write-Host "$GREEN  ✓ Повторное создание файлов конфигурации$NC"
                Write-Host "$GREEN  ✓ Изменение конфигурации машинного кода$NC"
                Write-Host "$GREEN  ✓ Изменение системного реестра$NC"
                Write-Host "$GREEN  ✓ Внедрение в ядро JavaScript (обход идентификации устройства)$NC"
            } else {
                Write-Host "$YELLOW[JavaScript внедрение]$NC Функция внедрения JavaScript не удалась, но другие функции успешны"
                Write-Host ""
                Write-Host "$GREEN[Готово]$NC Все операции завершены!"
                Write-Host "$BLUE[Детали]$NC Выполнены следующие операции:"
                Write-Host "$GREEN  ✓ Удалены папки, связанные с пробной версией Cursor$NC"
                Write-Host "$GREEN  ✓ Очистка инициализации Cursor$NC"
                Write-Host "$GREEN  ✓ Повторное создание файлов конфигурации$NC"
                Write-Host "$GREEN  ✓ Изменение конфигурации машинного кода$NC"
                Write-Host "$GREEN  ✓ Изменение системного реестра$NC"
                Write-Host "$YELLOW  ⚠ Внедрение в ядро JavaScript (частично неудачно)$NC"
            }

            Write-Host "$BLUE[Защита]$NC Устанавливаю защиту файла конфигурации..."
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN[Защита]$NC Файл конфигурации установлен в режим 'только для чтения', чтобы предотвратить перезапись Cursor"
                Write-Host "$BLUE[Подсказка]$NC Путь к файлу: $configPath"
            } catch {
                Write-Host "$YELLOW[Защита]$NC Не удалось установить атрибут 'только для чтения': $($_.Exception.Message)"
                Write-Host "$BLUE[Рекомендация]$NC Можно вручную щелкнуть правой кнопкой мыши файл → Свойства → Установить флажок 'Только для чтения'"
            }
        } else {
            Write-Host "$YELLOW[Реестр]$NC Изменение реестра не удалось, но другие операции успешны"

            if ($jsSuccess) {
                Write-Host "$GREEN[JavaScript внедрение]$NC Функция внедрения JavaScript выполнена успешно"
                Write-Host ""
                Write-Host "$YELLOW[Частично завершено]$NC Большинство операций завершено, изменение реестра не удалось"
                Write-Host "$BLUE[Рекомендация]$NC Могут потребоваться права администратора для изменения реестра"
                Write-Host "$BLUE[Детали]$NC Выполнены следующие операции:"
                Write-Host "$GREEN  ✓ Удалены папки, связанные с пробной версией Cursor$NC"
                Write-Host "$GREEN  ✓ Очистка инициализации Cursor$NC"
                Write-Host "$GREEN  ✓ Повторное создание файлов конфигурации$NC"
                Write-Host "$GREEN  ✓ Изменение конфигурации машинного кода$NC"
                Write-Host "$YELLOW  ⚠ Изменение системного реестра - неудачно$NC"
                Write-Host "$GREEN  ✓ Внедрение в ядро JavaScript (обход идентификации устройства)$NC"
            } else {
                Write-Host "$YELLOW[JavaScript внедрение]$NC Функция внедрения JavaScript не удалась"
                Write-Host ""
                Write-Host "$YELLOW[Частично завершено]$NC Большинство операций завершено, изменение реестра и внедрение JavaScript не удались"
                Write-Host "$BLUE[Рекомендация]$NC Могут потребоваться права администратора для изменения реестра"
            }

            Write-Host "$BLUE[Защита]$NC Устанавливаю защиту файла конфигурации..."
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN[Защита]$NC Файл конфигурации установлен в режим 'только для чтения', чтобы предотвратить перезапись Cursor"
                Write-Host "$BLUE[Подсказка]$NC Путь к файлу: $configPath"
            } catch {
                Write-Host "$YELLOW[Защита]$NC Не удалось установить атрибут 'только для чтения': $($_.Exception.Message)"
                Write-Host "$BLUE[Рекомендация]$NC Можно вручную щелкнуть правой кнопкой мыши файл → Свойства → Установить флажок 'Только для чтения'"
            }
        }
    } else {
        Write-Host ""
        Write-Host "$RED[Неудача]$NC Изменение конфигурации машинного кода не удалось!"
        Write-Host "$YELLOW[Рекомендация]$NC Проверьте сообщение об ошибке и повторите попытку"
    }
}

Write-Host ""
Write-Host "$GREEN================================$NC"
Write-Host "$YELLOW📱  Инструмент для сброса пробного периода Cursor $NC"
Write-Host "$YELLOW⚡   Скрипт для сброса идентификаторов устройства Cursor $NC"
Write-Host "$GREEN================================$NC"
Write-Host ""

Write-Host "$GREEN[Скрипт завершен]$NC Спасибо за использование инструмента изменения машинного кода Cursor!"
Write-Host "$BLUE[Подсказка]$NC При возникновении проблем ознакомьтесь с инструкцией или снова запустите скрипт"
Write-Host ""
Read-Host "Нажмите Enter для выхода"
exit 0
