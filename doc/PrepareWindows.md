# Windows 单机部署指南

本指南面向**在 Windows 上跑单机版**的新手：服务端和客户端都在同一台电脑上，不需要公网 IP、不需要 Linux 服务器、不需要云主机。

跟着从头做一遍即可。全程只需要复制粘贴命令，遇到问题看[第八节 常见问题](#八常见问题)。

> 如果你要部署到 Linux 服务器供别人连接，请改看 [PrepareLinux.md](PrepareLinux.md) 和 [OtherDeploy.md](OtherDeploy.md)。

---

## 一、先确认电脑够不够用

| 项目 | 要求 | 说明 |
|---|---|---|
| 系统 | Windows 10 64 位（2004+）或 Windows 11 | Docker Desktop 需要 WSL 2 |
| 内存 | **建议 16GB，最低 8GB** | 服务端实测吃 **2.2GB**，再加 Docker Desktop 自身、客户端和浏览器，8GB 会很紧张 |
| 磁盘 | 预留 **15GB 以上** | 镜像约 0.9GB、数据库和数据目录会长到 1~2GB、客户端约 4GB |
| CPU | 支持硬件虚拟化 | 任务管理器 → 性能 → CPU，看「虚拟化：已启用」。显示「已禁用」要先进 BIOS 打开 |

**内存是这台机器上最容易出问题的地方**，别按文档里示例的 `1g` 去限制服务端（见[第四节](#四两个必须知道的坑)）。

---

## 二、安装 Docker Desktop

1. 到 [Docker 官网](https://www.docker.com/products/docker-desktop/) 下载 **Docker Desktop for Windows** 并安装。
2. 安装向导里勾选 **Use WSL 2 instead of Hyper-V**（推荐）。
3. 安装完重启电脑，启动 Docker Desktop，等左下角变成绿色的 **Engine running**。
4. 打开 PowerShell 验证：

   ```powershell
   docker version
   ```

   能看到 Client 和 Server 两段版本信息就算好了。

> **中国大陆用户**：如果拉取镜像很慢或超时，可以在 Docker Desktop 的 *Settings → Docker Engine* 里加国内镜像加速地址。海外用户不用管，直接走 Docker Hub 最快。

**版本注意**：如果你装的是 **Docker 29 或更高版本**，第四节的 seccomp 配置是**必须做**的，否则服务端起不来。

---

## 三、准备服务端目录

1. 在磁盘上新建一个专门的目录，比如 `E:\DNF-Tai\客户端及docker`（路径里**不要有空格和特殊符号**）。
2. 把这个仓库里 `客户端及docker/` 目录下的两个文件复制进去：

   | 文件 | 作用 |
   |---|---|
   | `docker-compose.yaml` | 服务端启动配置 |
   | `seccomp-profile-v0.2.1.json` | Docker 29+ 的 seccomp 兼容规则 |

   这两个文件**必须放在同一个目录里**，因为 compose 文件里是用相对路径引用 seccomp 文件的。

3. （可选）用记事本打开 `docker-compose.yaml`，确认这两项：

   ```yaml
   - PUBLIC_IP=127.0.0.1        # 单机版就填这个，别改成别的
   - GATE_AES_KEY=a1b2c3...     # 登录密钥，客户端要填一样的
   ```

   `PUBLIC_IP` 是**客户端用来连服务端的地址**。单机版填 `127.0.0.1` 即可 —— 客户端里的 `ijl15.dll` 会把服务端域名改写到这个 IP，所以**客户端不需要改 hosts**。

---

## 四、两个必须知道的坑

### 坑 1：Docker 29+ 不挂 seccomp profile，服务端起不来

**症状**：容器一直重启，日志里反复刷

```
Could not create a UDP socket : 38
```

**原因**：Docker 29 默认的 seccomp 策略收紧了，服务端创建 UDP socket 被拦。

**解决**：`docker-compose.yaml` 里加上这一段（本仓库的配置已经带好了）：

```yaml
    security_opt:
      - seccomp=./seccomp-profile-v0.2.1.json
```

注意这里是**相对路径**，所以执行 `docker compose` 命令时必须先 `cd` 进这个目录，否则会报找不到文件。

> 网上有让你写 `seccomp=unconfined` 的，那是直接关掉安全沙箱，**不建议**。

### 坑 2：内存限制别给 `1g`

**症状**：容器不报错，但频道一直起不来，`docker stats` 看到内存顶格在 1000MiB 左右不动。

**原因**：镜像默认的性能配置按容器内存额度来分配，给 1g 会把服务端掐死。实测服务端稳定运行要吃 **2.14GiB**。

**解决**：`mem_limit` 给 `4g`（本仓库的配置已经是 4g）：

```yaml
    mem_limit: 4g
```

---

## 五、启动服务端

在 PowerShell 里执行（**注意先 cd 到配置目录**）：

```powershell
cd E:\DNF-Tai\客户端及docker
docker compose up -d
```

第一次会自动下载镜像（约 0.9GB，压缩传输约 0.3GB），视网速要几分钟。

**启动需要约 1.5 分钟**（首次初始化或低配硬件更久）。看日志：

```powershell
docker logs -f docker-dnf-1-1
```

看到这两个频道的就绪日志就是成功了：

```
s6-rc: info: service game_siroco11 successfully started
s6-rc: info: service game_siroco52 successfully started
```

再验证一下网关（`curl` 在 PowerShell 里是 `Invoke-WebRequest` 的别名，参数不一样，所以要用 `curl.exe`）：

```powershell
curl.exe http://127.0.0.1:5505/health
```

返回 HTTP `200` 就通了。访问根路径 `http://127.0.0.1:5505/` 返回 404 是**正常的**，别当成故障。

**临时停止 / 再启动**：

```powershell
docker compose stop     # 停止，容器和数据都保留，下次启动快
docker compose up -d    # 再启动
```

---

## 六、下载并配置客户端

1. **下载客户端**：[百度网盘](https://pan.baidu.com/s/1AuDJ-VO4A9uToAsrg6ETGw?pwd=sora)，提取码 `sora`，下载后解压到一个固定目录，比如 `E:\DNF1031客户端`。
2. **配置登录器**：双击客户端目录里的 `dnf-launcher.exe`，点下方 ***设置***：
   - **服务器地址**：`http://127.0.0.1:5505`
   - **AES 密钥**：和 `docker-compose.yaml` 里 `GATE_AES_KEY` 的值**完全一致**
   - 滚到底部点保存

   > 也可以直接编辑客户端目录里的 `Config.toml`，效果一样：
   >
   > ```toml
   > server_url = "http://127.0.0.1:5505"
   > aes_key = "a1b2c3d4e5f6789012345678901234567890abcdef0123456789abcdef012345"
   > ```

3. **开始游戏**：回到登录器首页，先点「注册」创建账号，然后点「进入游戏」。

> **不需要改 hosts 文件**。客户端里的 `ijl15.dll` 会自动把服务端域名改写到 `PUBLIC_IP`。

---

## 七、一键启动器（可选，推荐）

仓库里带了一个 PowerShell 小工具 `tools/DNF-单机版.ps1`，把上面第五、六节的步骤合成一个窗口：自动拉起 Docker Desktop、启动容器、等到频道就绪、等到网关响应、再打开登录器。

**用法**：右键 → 使用 PowerShell 运行，或者双击桌面快捷方式（见下）。

窗口里有：

- **[启动]**：跑完整套流程，冷启动实测约 80 秒，已经在跑的话几秒就完
- **[停止]**：`docker compose stop`（会先弹确认框）。选的是 `stop` 不是 `down`，**数据不丢**，下次启动还在
- **状态行**：容器 / 频道 / 网关 / 登录器 / 内存占用，每 8 秒自动刷新
- **日志框**：带时间戳的运行记录，出错时看这里

**创建桌面快捷方式**（在 PowerShell 里跑一次）：

```powershell
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\DNF-单机版.lnk")
$sc.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$sc.Arguments        = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<仓库路径>\tools\DNF-单机版.ps1"'
$sc.IconLocation     = '<客户端路径>\DNF.ico,0'
$sc.Save()
```

把 `<仓库路径>` 和 `<客户端路径>` 换成你自己的实际路径。

> **脚本里的路径要改**：`DNF-单机版.ps1` 顶部有一段「配置」，`$ComposeDir` 和 `$ClientDir` 按你的实际路径填。

---

## 八、常见问题

**Q：日志刷 `Could not create a UDP socket : 38`，容器反复重启**
A：seccomp profile 没挂上。检查 `docker-compose.yaml` 里的 `security_opt` 段，并确认执行 `docker compose` 时人在配置目录里（相对路径才能解析）。

**Q：等了很久没出现 `successfully started`**
A：按顺序查：

```powershell
# 容器还在跑吗
docker ps -a --filter name=docker-dnf-1-1

# 看完整日志，找报错
docker logs docker-dnf-1-1

# 看 11 频道服务状态
docker exec docker-dnf-1-1 s6-svstat /run/service/game_siroco11
```

如果是内存顶格卡住，参考[坑 2](#坑-2内存限制别给-1g)。

**Q：`curl http://127.0.0.1:5505/health` 无响应**
A：容器没起来，或者 5505 端口被别的程序占了。查端口占用：

```powershell
netstat -ano | findstr :5505
```

**Q：登录器点「登录」没反应，或者进不去游戏**
A：按顺序看：

1. 客户端目录下的 **`ijl15.log`** —— 这是客户端加载器的日志，注入出问题第一时间看它
2. 登录器的服务器地址和 AES 密钥是否和服务端一致
3. `PUBLIC_IP` 是不是 `127.0.0.1`（单机版别填局域网 IP）

**Q：服务端到底吃了多少内存？**

```powershell
docker stats --no-stream docker-dnf-1-1
```

**Q：能不能用 WSL2 里的原生 Docker，不装 Docker Desktop？**
A：**不行。** WSL2 的 NAT 网络只转发 TCP 端口，而 DNF 需要一堆 **UDP** 端口（7001、7300、31011、31052、2311-2313）。必须用 Docker Desktop，它自带 TCP/UDP 双向端口转发。

**Q：装了 OpenVPN / TAP-Windows 之类的虚拟网卡后，WSL 没网了**
A：已知冲突。临时方案是把 `C:\Users\<用户名>\.wslconfig` 里的 `networkingMode=mirrored` 去掉（改回默认 NAT）。注意改完别再加回去，否则网络又会断。

**Q：怎么彻底删掉重来？**

```powershell
cd E:\DNF-Tai\客户端及docker
docker compose down          # 删除容器
Remove-Item .\mysql, .\data, .\log -Recurse -Force   # 删除数据（不可恢复！）
docker compose up -d
```

> 第二条命令会**永久删除所有账号和角色数据**，确认不需要了再执行。

---

## 附：目录结构参考

```
E:\DNF-Tai\客户端及docker\      # 服务端目录
├── docker-compose.yaml
├── seccomp-profile-v0.2.1.json
├── data\        # 服务端数据（自动生成，别手动改）
├── mysql\       # 数据库（自动生成，备份就备份这个目录）
└── log\         # 服务端日志

E:\DNF1031客户端\                # 客户端目录
├── dnf-launcher.exe            # 登录器
├── Config.toml                 # 登录器配置
├── ijl15.dll                   # 加载器（改写域名解析 + 注入插件）
├── ijl15.log                   # 加载器日志，排查客户端问题看这个
└── GameSettings.toml           # 内置插件设置（中文注释，热键 Alt+Insert）
```

**备份提醒**：账号和角色数据全在 `mysql\` 目录里，想备份就整个复制走，换机器时放回原位即可。
