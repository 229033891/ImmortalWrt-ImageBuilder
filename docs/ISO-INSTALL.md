# x86-64 ISO 安装说明

本仓库工作流 **Build 25.12.x ISO x86-64** 会生成安装盘：

- Release 标签：`Custom-Installer-x86_64-ISO`
- 文件名：`custom-installer-x86_64.iso`

ISO 内嵌的 ImmortalWrt 与普通 **x86-64 img** 同源（同一套 `files/` 定制）。差别主要在部署方式：ISO 可写入更大虚拟盘/物理盘，安装后便于利用剩余空间。

默认登录（以当前定制为准，可按构建参数调整）：

| 项 | 默认值 |
|----|--------|
| 后台地址 | `http://192.168.100.1`（构建时可改） |
| 用户名 | `root` |
| 密码 | `password` |
| AdGuard | `http://<后台IP>:3000` → `admin` / `admin` |
| 固件类型 | EFI（`squashfs-combined-efi`） |

---

## 一、ESXi / 虚拟机（推荐）

### 1. 新建虚拟机

1. 客户机类型：其他 Linux 64 位 / Debian 均可  
2. 固件：**EFI**  
3. 网卡：至少 1 块（需要路由功能时建议多网口）  
4. 硬盘：新建**空磁盘**，建议 **8GB 及以上**  
5. 光驱：挂载 `custom-installer-x86_64.iso`，并从光驱启动  

### 2. 安装 ImmortalWrt

1. 开机进入 Debian Live（较快）  
2. 在命令行输入：

```bash
ddd
```

3. 按菜单选择要写入的**目标硬盘**（虚拟机空盘，如 `/dev/sda`）  
4. 确认后等待写入完成（会覆盖该盘数据）  

### 3. 收尾并首次开机

1. **关机**  
2. 编辑虚拟机：**卸下 / 取消连接 ISO**，避免再次进入安装盘  
3. 确认从**硬盘**启动后开机  
4. 等待约 1–2 分钟（首启 `uci-defaults` 脚本执行）  
5. 浏览器访问后台，使用上表账号登录  

### 4. 网络提示

- 虚拟机网卡需与可管理的网段连通（或临时将电脑改为 `192.168.100.0/24`）  
- 单网口设备：脚本可能按 DHCP 客户端处理 LAN，后台 IP 以上级路由分配为准  
- 多网口：一般 WAN 为 DHCP，LAN 为静态管理地址 + DHCP 服务器  

---

## 二、物理机（U 盘）

### Windows

1. 建议用 [Ventoy](https://www.ventoy.net/cn/index.html) 制作启动 U 盘  
2. 将 ISO 拷贝到 Ventoy U 盘  
3. 软路由从 U 盘启动后，命令行输入 `ddd`，按提示写入内置硬盘  

### macOS

1. 使用 [balenaEtcher](https://etcher.balena.io/) 将 ISO 写入 U 盘  
2. 软路由从 U 盘启动（Del / F12 / F11 / F7 等进启动菜单）  
3. 命令行输入 `ddd`，按提示写入目标硬盘  

安装完成后拔掉 U 盘，从硬盘启动即可。

---

## 三、ISO 与 img 对比

| | ISO 安装器 | img（如转 VMDK） |
|--|--|--|
| 系统内容 | 相同定制固件 | 相同定制固件 |
| 部署 | Live + `ddd` 写入磁盘 | 整盘镜像直接挂载/转换 |
| 磁盘大小 | 可先建大盘，安装后常有剩余空间 | 解压后约等于 rootfs 设定大小 |
| 虚拟机 | 一般更省事 | 需注意 VMDK 格式兼容 |

---

## 四、相关链接

- 安装器原理：[wukongdaily/img-installer](https://github.com/wukongdaily/img-installer)  
- 视频参考（上游）：[Bilibili](https://www.bilibili.com/video/BV1enxMzwEUe/) / [YouTube](https://www.youtube.com/watch?v=ftSE3wSJi64)  

刷机或安装完成后，请尽快修改 `root` 与 AdGuard 默认密码；调试结束后建议将 WAN 入站改回拒绝。
