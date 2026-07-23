#!/bin/sh
# 首启：dnsmasq 仅 DHCP，DNS 由 AdGuard Home(:53) 接管
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "97-adguardhome.sh at $(date)" >>"$LOGFILE"

[ -f /etc/adguardhome/adguardhome.yaml ] || {
	echo "skip 97-adguardhome.sh: no adguardhome.yaml" >>"$LOGFILE"
	exit 0
}

# 关闭 dnsmasq 的 DNS 服务，避免与 AGH 抢 53 端口
uci -q set dhcp.@dnsmasq[0].port='0'

# 写入 UCI 路径（官方 init 不读取 enabled 选项，仅作 LuCI 展示）
if [ -f /etc/config/adguardhome ]; then
	uci -q set adguardhome.config.config_file='/etc/adguardhome/adguardhome.yaml'
	uci -q set adguardhome.config.work_dir='/var/lib/adguardhome'
	uci commit adguardhome
fi

uci commit dhcp

# 先释放 53 端口，再注册开机自启（实际启动放到 99-custom，等 LAN/DHCP 配完）
/etc/init.d/dnsmasq reload 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null

if [ -x /etc/init.d/adguardhome ]; then
	/etc/init.d/adguardhome enable
	echo "adguardhome enable done (start deferred to 99-custom)" >>"$LOGFILE"
fi

echo "dnsmasq DNS disabled (port=0); adguardhome boot enabled" >>"$LOGFILE"

exit 0
