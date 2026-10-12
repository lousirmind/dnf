#Requires -Version 5.1
<#
    DNF-单机版 — 单机服务端控制台

    [启动] Docker Desktop → 服务端容器 → 等双频道(11/52)就绪 → 等网关 /health → 打开登录器
    [停止] docker compose stop（只停容器，不删数据）
    每 8 秒自动刷新一次状态：容器 / 频道 / 网关 / 登录器 / 内存占用（对 compose 里的 mem_limit）。
    日志：本脚本同目录 DNF-单机版.log

    排错：
      服务端起不来          → 看窗口日志里 docker compose up -d 的输出
      频道一直不就绪        → docker logs docker-dnf-1-1
      登录器打不开/进不去   → E:\DNF1031客户端\ijl15.log
#>

$ErrorActionPreference = 'Stop'

# ==================== 依赖 ====================
# 必须在下面配色常量之前加载，否则 [System.Drawing.Color] 解析不了
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==================== 配置 ====================
$ComposeDir  = 'E:\DNF-Tai\客户端及docker'
$ClientDir   = 'E:\DNF1031客户端'
$LauncherExe = Join-Path $ClientDir 'dnf-launcher.exe'
$IconFile    = Join-Path $ClientDir 'DNF.ico'
$LogFile     = Join-Path $PSScriptRoot 'DNF-单机版.log'

$DockerDesktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
$DockerExe     = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'

$Container = 'docker-dnf-1-1'
$GateUrl   = 'http://127.0.0.1:5505/health'

# docker logs 里出现这两行 = 两个频道都起来了（注意：这两行走 stderr）
$ChannelMarkers = @(
    'game_siroco11 successfully started',
    'game_siroco52 successfully started'
)

# 超时（秒）
$TimeoutCompose  = 300   # 含 Docker Desktop 冷启动，别调太小
$TimeoutChannels = 300
$TimeoutGate     = 90
$RefreshMs       = 8000  # 空闲时状态自动刷新间隔

# 配色
$C_OK    = [System.Drawing.Color]::FromArgb(110, 220, 130)
$C_OFF   = [System.Drawing.Color]::FromArgb(138, 138, 146)
$C_WORK  = [System.Drawing.Color]::FromArgb(226, 192, 108)
$C_BAD   = [System.Drawing.Color]::FromArgb(240, 110, 110)

# ==================== 界面 ====================
$Form = New-Object System.Windows.Forms.Form
$Form.Text            = 'DNF-单机版'
$Form.ClientSize      = New-Object System.Drawing.Size(480, 382)
$Form.StartPosition   = 'CenterScreen'
$Form.FormBorderStyle = 'FixedDialog'
$Form.MaximizeBox     = $false
$Form.MinimizeBox     = $false
$Form.BackColor       = [System.Drawing.Color]::FromArgb(26, 26, 30)
try { $Form.Icon = New-Object System.Drawing.Icon($IconFile) } catch { }

$LblTitle = New-Object System.Windows.Forms.Label
$LblTitle.Text      = 'DNF-单机版'
$LblTitle.Font      = New-Object System.Drawing.Font('Microsoft YaHei UI', 17, [System.Drawing.FontStyle]::Bold)
$LblTitle.ForeColor = [System.Drawing.Color]::FromArgb(226, 192, 108)
$LblTitle.Location  = New-Object System.Drawing.Point(22, 12)
$LblTitle.AutoSize  = $true
$Form.Controls.Add($LblTitle)

$LblSub = New-Object System.Windows.Forms.Label
$LblSub.Text      = '单机服务端控制台'
$LblSub.Font      = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$LblSub.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 150)
$LblSub.Location  = New-Object System.Drawing.Point(176, 26)
$LblSub.AutoSize  = $true
$Form.Controls.Add($LblSub)

# ---- 状态行 ----
$script:Rows = @()
$rowDefs = @(
    @{ Name = '服务端容器'; Y = 56 },
    @{ Name = '游戏频道';   Y = 84 },
    @{ Name = '网关 5505';  Y = 112 },
    @{ Name = '登录器';     Y = 140 },
    @{ Name = '内存占用';   Y = 168 }
)
foreach ($d in $rowDefs) {
    $n = New-Object System.Windows.Forms.Label
    $n.Text      = $d.Name
    $n.Font      = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
    $n.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 170)
    $n.Location  = New-Object System.Drawing.Point(28, $d.Y)
    $n.Size      = New-Object System.Drawing.Size(110, 22)
    $Form.Controls.Add($n)

    $v = New-Object System.Windows.Forms.Label
    $v.Text      = '检测中…'
    $v.Font      = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
    $v.ForeColor = $C_OFF
    $v.Location  = New-Object System.Drawing.Point(146, $d.Y)
    $v.Size      = New-Object System.Drawing.Size(320, 22)
    $Form.Controls.Add($v)

    $script:Rows += $v
}

# ---- 忙碌进度条 ----
$Bar = New-Object System.Windows.Forms.ProgressBar
$Bar.Location = New-Object System.Drawing.Point(24, 194)
$Bar.Size     = New-Object System.Drawing.Size(432, 6)
$Bar.Style    = 'Marquee'
$Bar.MarqueeAnimationSpeed = 30
$Bar.Visible  = $false
$Form.Controls.Add($Bar)

# ---- 日志框 ----
$TxtLog = New-Object System.Windows.Forms.TextBox
$TxtLog.Location   = New-Object System.Drawing.Point(24, 208)
$TxtLog.Size       = New-Object System.Drawing.Size(432, 104)
$TxtLog.Multiline  = $true
$TxtLog.ReadOnly   = $true
$TxtLog.WordWrap   = $true
$TxtLog.ScrollBars = 'Vertical'
$TxtLog.BackColor  = [System.Drawing.Color]::FromArgb(18, 18, 22)
$TxtLog.ForeColor  = [System.Drawing.Color]::FromArgb(170, 175, 185)
$TxtLog.BorderStyle = 'FixedSingle'
$TxtLog.Font       = New-Object System.Drawing.Font('Consolas', 8.25)
$Form.Controls.Add($TxtLog)

# ---- 按钮 ----
function New-Btn {
    param([string]$Text, [int]$X, [System.Drawing.Color]$Back, [System.Drawing.Color]$Fore)
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Text
    $b.Location  = New-Object System.Drawing.Point($X, 324)
    $b.Size      = New-Object System.Drawing.Size(148, 38)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Back
    $b.ForeColor = $Fore
    $b.Font      = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
    $b.UseVisualStyleBackColor = $false
    return $b
}

$BtnStart = New-Btn '启 动' 24  ([System.Drawing.Color]::FromArgb(46, 106, 60))  ([System.Drawing.Color]::FromArgb(215, 245, 220))
$BtnStop  = New-Btn '停 止' 308 ([System.Drawing.Color]::FromArgb(112, 48, 48))  ([System.Drawing.Color]::FromArgb(248, 220, 220))
$Form.Controls.Add($BtnStart)
$Form.Controls.Add($BtnStop)

# ==================== 状态与日志 ====================
$script:Busy = $false

function Pump { [System.Windows.Forms.Application]::DoEvents() }

function Add-UiLog {
    param([string]$Text)
    try {
        $TxtLog.AppendText(('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $Text) + "`r`n")
        if ($TxtLog.TextLength -gt 60000) {
            $keep = $TxtLog.Lines | Select-Object -Last 200
            $TxtLog.Lines = $keep
        }
        $TxtLog.SelectionStart = $TxtLog.TextLength
        $TxtLog.ScrollToCaret()
    } catch { }
}

function Write-Log {
    param([string]$Message)
    try {
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 1MB)) {
            Remove-Item $LogFile -Force
        }
        Add-Content -Path $LogFile -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    } catch { }
    Add-UiLog $Message
}

function Set-Row {
    param([int]$Index, [string]$Text, [System.Drawing.Color]$Color)
    $script:Rows[$Index].Text      = $Text
    $script:Rows[$Index].ForeColor = $Color
    Pump
}

function Set-Busy {
    param([bool]$On, [string]$Hint = '')
    $script:Busy = $On
    $BtnStart.Enabled = -not $On
    $BtnStop.Enabled  = -not $On
    $Bar.Visible      = $On
    if ($Hint) { Set-Row 0 $Hint $C_WORK }
    Pump
}

function Invoke-Docker {
    param([string[]]$Arguments)
    # 关键：docker logs 里 s6-rc 的 "successfully started" 走的是 stderr，
    # 而 PS 5.1 的 `2>&1` 会把原生命令 stderr 包成 NativeCommandError。
    # 所以用 Start-Process 分流到两个临时文件，再合并读回来。
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $DockerExe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $stdout = Get-Content -Raw -Path $outFile -Encoding UTF8 -ErrorAction SilentlyContinue
        $stderr = Get-Content -Raw -Path $errFile -Encoding UTF8 -ErrorAction SilentlyContinue
        $merged = (@($stdout, $stderr) | Where-Object { $_ }) -join "`n"
        [pscustomobject]@{
            Code = $proc.ExitCode
            Out  = $merged.Trim()
        }
    } finally {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-Gate {
    try {
        $r = Invoke-WebRequest -Uri $GateUrl -UseBasicParsing -TimeoutSec 3
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Test-Launcher {
    return [bool](Get-Process -Name 'dnf-launcher' -ErrorAction SilentlyContinue)
}

function Get-MemInfo {
    # 容器是 cgroup v2，直接读文件：~130ms。
    # 不用 `docker stats --no-stream`，那个要采样，单次要 1.1 秒，会把 UI 线程卡住。
    $usageRaw = (Invoke-Docker @('exec', $Container, 'cat', '/sys/fs/cgroup/memory.current')).Out.Trim()
    $usage = 0.0
    if (-not [double]::TryParse($usageRaw, [ref]$usage)) { return $null }

    # mem_limit 落在 HostConfig.Memory 上，跟 compose 里的 `mem_limit: 4g` 同步
    $limitRaw = (Invoke-Docker @('inspect', '-f', '{{.HostConfig.Memory}}', $Container)).Out.Trim()
    $limit = 0.0
    [void][double]::TryParse($limitRaw, [ref]$limit)

    [pscustomobject]@{ Usage = $usage; Limit = $limit }
}

# ---- 状态探测（只读，不做动作）----
function Update-State {
    if ($script:Busy) { return }

    $r = Invoke-Docker @('inspect', '-f', '{{.State.Running}}', $Container)
    $running = ($r.Out -eq 'true')

    if ($running) {
        Set-Row 0 '● 运行中' $C_OK
        # 空闲刷新只看进程和网关，不重扫日志 —— 所以频道一栏只能以网关连通为准，
        # 别写成"已就绪"假装验证过（启动流程里那两行才是真的逐频道校验过的）
        if (Test-Gate) {
            Set-Row 1 '● 11 / 52 在线' $C_OK
            Set-Row 2 '● 正常 (HTTP 200)' $C_OK
        } else {
            Set-Row 1 '● 频道状态未知' $C_OFF
            Set-Row 2 '● 无响应' $C_BAD
        }

        $mem = Get-MemInfo
        if ($mem) {
            $text = '{0:N2} GiB' -f ($mem.Usage / 1GB)
            $pct  = 0.0
            if ($mem.Limit -gt 0) {
                $pct  = 100.0 * $mem.Usage / $mem.Limit
                $text = '{0} / {1:N2} GiB   ({2:N0}%)' -f $text, ($mem.Limit / 1GB), $pct
            }
            if     ($pct -ge 90) { Set-Row 4 "● $text" $C_BAD }
            elseif ($pct -ge 70) { Set-Row 4 "● $text" $C_WORK }
            else                 { Set-Row 4 "● $text" $C_OK }
        } else {
            Set-Row 4 '— 读取失败' $C_OFF
        }
    } else {
        Set-Row 0 '○ 已停止' $C_OFF
        Set-Row 1 '— 未运行' $C_OFF
        Set-Row 2 '— 未运行' $C_OFF
        Set-Row 4 '— 未运行' $C_OFF
    }

    if (Test-Launcher) { Set-Row 3 '● 已打开' $C_OK } else { Set-Row 3 '○ 未打开' $C_OFF }
}

# ==================== 启动 ====================
function Start-Server {
    $script:Busy = $true
    $BtnStart.Enabled = $false
    $BtnStop.Enabled  = $false
    $Bar.Visible      = $true
    Pump

    Write-Log '========== 开始启动 =========='
    try {
        # ---- 1. Docker Desktop ----
        Set-Row 4 '● 启动中…' $C_WORK
        if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
            Set-Row 0 '● 正在启动 Docker Desktop…' $C_WORK
            Write-Log 'Docker Desktop 未运行，正在拉起（冷启动约 30~90 秒）'
            Start-Process -FilePath $DockerDesktop
        } else {
            Set-Row 0 '● 正在启动服务端容器…' $C_WORK
        }

        # ---- 2. 起服务端容器（失败就重试，直到引擎就绪）----
        $deadline = (Get-Date).AddSeconds($TimeoutCompose)
        $attempt  = 0
        while ($true) {
            $attempt++
            Set-Row 0 "● 启动中…（第 $attempt 次尝试）" $C_WORK
            Write-Log "docker compose up -d（第 $attempt 次）"

            Push-Location $ComposeDir
            $res = Invoke-Docker @('compose', 'up', '-d')
            Pop-Location

            if ($res.Code -eq 0) { break }

            $tail = ($res.Out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' / '
            Write-Log "  ↑ 失败 (exit $($res.Code)): $tail"

            if ((Get-Date) -gt $deadline) {
                throw "docker compose up -d 未能在 $TimeoutCompose 秒内成功。最后输出：$tail"
            }
            if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
                Start-Process -FilePath $DockerDesktop -ErrorAction SilentlyContinue
            }
            for ($i = 0; $i -lt 50; $i++) { Pump; Start-Sleep -Milliseconds 100 }
        }
        Write-Log '容器已创建/启动，等待频道就绪…'

        # ---- 3. 等双频道 ----
        # 用容器本次的 StartedAt 做 --since，避免读到上一次运行的旧日志造成假成功
        $startedAtRaw = (Invoke-Docker @('inspect', '-f', '{{.State.StartedAt}}', $Container)).Out
        if (-not $startedAtRaw) { throw "找不到容器 $Container（compose 起来了但容器名对不上？）" }
        $since = $startedAtRaw.Substring(0, 19) + 'Z'

        $deadline = (Get-Date).AddSeconds($TimeoutChannels)
        while ($true) {
            Pump
            $running = (Invoke-Docker @('inspect', '-f', '{{.State.Running}}', $Container)).Out
            if ($running -ne 'true') { throw "容器 $Container 已退出，去看日志：docker logs $Container" }

            $logs = (Invoke-Docker @('logs', '--since', $since, $Container)).Out
            $pending = @($ChannelMarkers | Where-Object { $logs -notmatch [regex]::Escape($_) }).Count

            if ($pending -eq 0) { break }

            Set-Row 1 "● 等待中…还差 $pending 个频道" $C_WORK
            if ((Get-Date) -gt $deadline) {
                throw "频道未能在 $TimeoutChannels 秒内全部就绪（还差 $pending 个）。看 docker logs $Container"
            }
            for ($i = 0; $i -lt 50; $i++) { Pump; Start-Sleep -Milliseconds 100 }
        }
        Set-Row 1 '● 11 / 52 就绪' $C_OK
        Write-Log '两个频道都已就绪'

        # ---- 4. 等网关 ----
        Set-Row 2 '● 等待网关响应…' $C_WORK
        $deadline = (Get-Date).AddSeconds($TimeoutGate)
        while (-not (Test-Gate)) {
            Pump
            if ((Get-Date) -gt $deadline) { throw "网关 $GateUrl 未在 $TimeoutGate 秒内返回 200。" }
            for ($i = 0; $i -lt 20; $i++) { Pump; Start-Sleep -Milliseconds 100 }
        }
        Set-Row 2 '● 正常 (HTTP 200)' $C_OK
        Write-Log '网关正常'

        # ---- 5. 开登录器 ----
        if (Test-Launcher) {
            Write-Log '登录器已在运行，跳过'
        } else {
            Start-Process -FilePath $LauncherExe -WorkingDirectory $ClientDir
            Write-Log "已启动 $LauncherExe"
        }
        Set-Row 3 '● 已打开' $C_OK

        Write-Log '========== 启动成功 =========='
    } catch {
        Write-Log "启动失败: $($_.Exception.Message)"
        Write-Log '========== 启动失败 =========='
        Set-Row 0 '● 启动失败（详见下方日志）' $C_BAD
    } finally {
        $script:Busy = $false
        $BtnStart.Enabled = $true
        $BtnStop.Enabled  = $true
        $Bar.Visible      = $false
        Pump
        Update-State
    }
}

# ==================== 停止 ====================
function Stop-Server {
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "确定要停止服务端吗？`r`n`r`n如果正在游戏里，角色会立刻掉线。`r`n数据库和角色数据不会丢，下次启动还在。",
        'DNF-单机版', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    $script:Busy = $true
    $BtnStart.Enabled = $false
    $BtnStop.Enabled  = $false
    $Bar.Visible      = $true
    Set-Row 0 '● 正在停止…' $C_WORK
    Set-Row 4 '● 停止中…' $C_WORK
    Write-Log '========== 开始停止 =========='
    try {
        Push-Location $ComposeDir
        $res = Invoke-Docker @('compose', 'stop')
        Pop-Location

        if ($res.Code -ne 0) {
            $tail = ($res.Out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' / '
            throw "docker compose stop 失败 (exit $($res.Code)): $tail"
        }
        Write-Log '服务端已停止'
        Write-Log '========== 停止完成 =========='
        Set-Row 0 '○ 已停止' $C_OFF
        Set-Row 1 '— 未运行' $C_OFF
        Set-Row 2 '— 未运行' $C_OFF
    } catch {
        Write-Log "停止失败: $($_.Exception.Message)"
        Set-Row 0 '● 停止失败（详见下方日志）' $C_BAD
    } finally {
        $script:Busy = $false
        $BtnStart.Enabled = $true
        $BtnStop.Enabled  = $true
        $Bar.Visible      = $false
        Pump
        Update-State
    }
}

$BtnStart.Add_Click({ if (-not $script:Busy) { Start-Server } })
$BtnStop.Add_Click({ if (-not $script:Busy) { Stop-Server } })

# ---- 定时刷新 ----
$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = $RefreshMs
$Timer.Add_Tick({ Update-State })
$Timer.Start()

$Form.Add_Shown({
    Write-Log "控制台已打开（容器 $Container / 网关 $GateUrl）"
    Update-State
})

[void]$Form.ShowDialog()
$Timer.Stop()
