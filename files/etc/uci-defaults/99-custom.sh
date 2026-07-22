#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 设置默认防火墙规则，方便单网口虚拟机首次访问 WebUI 
# 因为本项目中 单网口模式是dhcp模式 直接就能上网并且访问web界面 避免新手每次都要修改/etc/config/network中的静态ip
# 当你刷机运行后 都调整好了 你完全可以在web页面自行关闭 wan口防火墙的入站数据
# 具体操作方法：网络——防火墙 在wan的入站数据 下拉选项里选择 拒绝 保存并应用即可。
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
    . "$SETTINGS_FILE"
fi

# 1. 先获取所有物理接口列表
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 2. 根据板子型号映射WAN和LAN接口
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

wan_ifname=""
lan_ifnames=""
wan2_ifname=""
easepi_r1=0
# 此处特殊处理个别开发板网口顺序问题
case "$board_name" in
    "radxa,e20c"|"friendlyarm,nanopi-r5c")
        wan_ifname="eth1"
        lan_ifnames="eth0"
        echo "Using $board_name mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
    *easepi-r1*|*easepi_r1*)
        # 对齐现网 ImmortalWrt-shlt：LAN=eth1+eth2，主 WAN=eth5，副 WAN=eth0
        easepi_r1=1
        wan_ifname="eth5"
        wan2_ifname="eth0"
        lan_ifnames="eth1 eth2"
        echo "Using EasePi R1 mapping: WAN1=$wan_ifname WAN2=$wan2_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
    *)
        # 默认第一个接口为WAN，其余为LAN
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
        echo "Using default mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
esac

# 3. 配置网络
if [ "$count" -eq 1 ]; then
    # 单网口设备，DHCP模式
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network
elif [ "$easepi_r1" -eq 1 ]; then
    # EasePi R1：尽量接近现网（双 WAN + 指定 LAN）
    # 清理可能存在的默认 wan/wan6，改用 wan1/wan2 命名
    uci -q delete network.wan
    uci -q delete network.wan6

    # br-lan = eth1 eth2
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        uci -q delete "network.$section.ports"
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
    fi

    # LAN 172.20.0.1/24（Actions custom_router_ip 可覆盖）
    IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_VALUE_FILE" ]; then
        CUSTOM_IP=$(cat "$IP_VALUE_FILE" | tr -d ' \r\n')
    else
        CUSTOM_IP="172.20.0.1"
    fi
    # 去掉可能已带的 /24
    CUSTOM_IP=$(echo "$CUSTOM_IP" | cut -d/ -f1)
    uci set network.lan.proto='static'
    uci -q delete network.lan.ipaddr
    uci -q delete network.lan.netmask
    uci add_list network.lan.ipaddr="${CUSTOM_IP}/24"
    uci set network.lan.ip6assign='60'
    echo "EasePi R1 LAN ip is ${CUSTOM_IP}/24" >>$LOGFILE

    # wan1 = eth5（主上行，metric 10）
    uci set network.wan1=interface
    uci set network.wan1.device="$wan_ifname"
    uci set network.wan1.metric='10'
    uci set network.wan1.multipath='off'
    uci set network.wan1.norelease='1'
    echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        uci set network.wan1.proto='pppoe'
        uci set network.wan1.username="$pppoe_account"
        uci set network.wan1.password="$pppoe_password"
        uci set network.wan1.ipv6='auto'
        uci set network.wan1.peerdns='1'
        uci set network.wan1.auto='1'
        echo "EasePi R1 wan1 PPPoE configured (credentials from Actions)." >>$LOGFILE
    else
        # 未在 Actions 勾选 PPPoE：先 DHCP，刷后可在 LuCI 改回 PPPoE
        uci set network.wan1.proto='dhcp'
        uci set network.wan1.ipv6='auto'
        echo "EasePi R1 wan1 DHCP placeholder; set PPPoE after flash if needed." >>$LOGFILE
    fi

    # wan2 = eth0（副上行 DHCP，metric 20）
    uci set network.wan2=interface
    uci set network.wan2.device="$wan2_ifname"
    uci set network.wan2.proto='dhcp'
    uci set network.wan2.ipv6='auto'
    uci set network.wan2.metric='20'
    uci set network.wan2.norelease='1'
    uci set network.wan2.multipath='off'

    uci set network.wan2_v6=interface
    uci set network.wan2_v6.device="$wan2_ifname"
    uci set network.wan2_v6.proto='dhcpv6'

    # Tailscale 占位接口（安装插件后由服务接管）
    uci set network.tailscale=interface
    uci set network.tailscale.proto='none'
    uci set network.tailscale.device='tailscale0'

    # 防火墙 wan 区挂上 wan1/wan2
    for z in $(uci show firewall | awk -F'[.=]' '/=zone$/ {print $2}'); do
        zname=$(uci -q get "firewall.$z.name")
        if [ "$zname" = "wan" ]; then
            uci -q delete "firewall.$z.network"
            uci add_list "firewall.$z.network"='wan1'
            uci add_list "firewall.$z.network"='wan2'
            uci add_list "firewall.$z.network"='wan2_v6'
            echo "firewall wan zone -> wan1/wan2" >>$LOGFILE
            break
        fi
    done

    uci set system.@system[0].hostname='ImmortalWrt-shlt'
    uci commit system
    uci commit network
    uci commit firewall
elif [ "$count" -gt 1 ]; then
    # 多网口设备配置
    # 配置WAN
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # 配置WAN6
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    # 查找 br-lan 设备 section
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        # 删除原有ports
        uci -q delete "network.$section.ports"
        # 添加LAN接口端口
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
    fi

    # LAN口设置静态IP
    uci set network.lan.proto='static'
    # 多网口设备 支持修改为别的管理后台地址 在Github Action 的UI上自行输入即可 
    uci set network.lan.netmask='255.255.255.0'
    # 设置路由器管理后台地址
    IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_VALUE_FILE" ]; then
        CUSTOM_IP=$(cat "$IP_VALUE_FILE")
        # 用户在UI上设置的路由器后台管理地址
        uci set network.lan.ipaddr=$CUSTOM_IP
        echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
    else
        uci set network.lan.ipaddr='192.168.100.1'
        echo "default router ip is 192.168.100.1" >> $LOGFILE
    fi

    # PPPoE设置
    echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE enabled, configuring..." >>$LOGFILE
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        uci set network.wan6.proto='none'
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    uci commit network
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 若luci-app-advancedplus (进阶设置)已安装 则去除zsh的调用 防止命令行报 /usb/bin/zsh: not found的提示
if [ -f /usr/lib/lua/luci/controller/advancedplus.lua ]; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
    echo "fix ttyd show msg: /usb/bin/zsh: not found" >>$LOGFILE
fi

# 只有安装了 luci-app-quickfile 才执行
if [ -f /usr/bin/quickfile ]; then
    uci set nginx.global.uci_enable='true'
    uci del nginx._lan 2>/dev/null
    uci del nginx._redirect2ssl 2>/dev/null

    uci add nginx server
    uci rename nginx.@server[-1]='_lan'

    uci set nginx._lan.server_name='_lan'
    uci add_list nginx._lan.listen='80 default_server'
    uci add_list nginx._lan.listen='[::]:80 default_server'
    uci add_list nginx._lan.include='conf.d/*.locations'
    uci set nginx._lan.access_log='off; # logd openwrt'

    uci commit nginx
    echo "fix quickfile nginx config" >>$LOGFILE
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall

# 追加新的 zone + forwarding 配置
cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

exit 0
