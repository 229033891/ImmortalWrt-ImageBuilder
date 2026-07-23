#!/bin/sh
# 首启：Tailscale 守护进程开机自启 + 防火墙区域（对齐 luci-app-tailscale-community）
# 登录 tailnet 仍需在 LuCI 或 tailscale up 完成；子网路由需在控制台批准
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "98-tailscale.sh at $(date)" >>"$LOGFILE"

[ -x /etc/init.d/tailscale ] || {
	echo "skip 98-tailscale.sh: tailscale not installed" >>"$LOGFILE"
	exit 0
}

# ---------- 网络接口 ----------
if ! uci -q get network.tailscale >/dev/null 2>&1; then
	uci set network.tailscale=interface
	uci set network.tailscale.proto='none'
	uci set network.tailscale.device='tailscale0'
	echo "network.tailscale created" >>"$LOGFILE"
else
	cur_dev=$(uci -q get network.tailscale.device)
	if [ "$cur_dev" != "tailscale0" ]; then
		uci set network.tailscale.device='tailscale0'
		echo "network.tailscale device -> tailscale0" >>"$LOGFILE"
	fi
fi

# ---------- 防火墙区域与转发（lan<->tailscale，tailscale->wan 供出口节点）----------
ts_zone=""
for z in $(uci show firewall 2>/dev/null | awk -F'[.=]' '/=zone$/ {print $2}'); do
	zname=$(uci -q get "firewall.$z.name")
	if [ "$zname" = "tailscale" ]; then
		ts_zone="$z"
		break
	fi
done

if [ -z "$ts_zone" ]; then
	ts_zone=$(uci add firewall zone)
	uci set "firewall.$ts_zone.name"='tailscale'
	uci set "firewall.$ts_zone.input"='ACCEPT'
	uci set "firewall.$ts_zone.output"='ACCEPT'
	uci set "firewall.$ts_zone.forward"='ACCEPT'
	uci set "firewall.$ts_zone.masq"='1'
	uci set "firewall.$ts_zone.mtu_fix"='1'
	uci set "firewall.$ts_zone.network"='tailscale'
	echo "firewall zone tailscale created" >>"$LOGFILE"
else
	has_ts_net=0
	for net in $(uci -q get "firewall.$ts_zone.network" 2>/dev/null); do
		[ "$net" = "tailscale" ] && has_ts_net=1
	done
	if [ "$has_ts_net" -eq 0 ]; then
		uci add_list "firewall.$ts_zone.network"='tailscale'
		echo "firewall zone tailscale: added network tailscale" >>"$LOGFILE"
	fi
fi

fwd_exists() {
	src="$1"
	dest="$2"
	for f in $(uci show firewall 2>/dev/null | awk -F'[.=]' '/=forwarding$/ {print $2}'); do
		[ "$(uci -q get "firewall.$f.src")" = "$src" ] \
			&& [ "$(uci -q get "firewall.$f.dest")" = "$dest" ] \
			&& return 0
	done
	return 1
}

add_forwarding() {
	src="$1"
	dest="$2"
	if fwd_exists "$src" "$dest"; then
		return 0
	fi
	f=$(uci add firewall forwarding)
	uci set "firewall.$f.src"="$src"
	uci set "firewall.$f.dest"="$dest"
	echo "firewall forwarding $src -> $dest added" >>"$LOGFILE"
}

add_forwarding lan tailscale
add_forwarding tailscale lan
add_forwarding tailscale wan

uci commit network
uci commit firewall

# ---------- 服务与 LuCI 参数（网络/防火墙 UCI 已写好后再启动）----------
if ! uci -q get tailscale.settings >/dev/null 2>&1; then
	uci set tailscale.settings=settings
fi
uci -q set tailscale.settings.service_enabled='1'
uci -q set tailscale.settings.fw_mode='nftables'
uci -q set tailscale.settings.log_stdout='1'
uci -q set tailscale.settings.log_stderr='1'
uci commit tailscale

/etc/init.d/tailscale enable
/etc/init.d/tailscale start

if [ -x /etc/init.d/tailscale-settings ]; then
	/etc/init.d/tailscale-settings enable
fi

echo "tailscale firewall + enable+start done (login still required)" >>"$LOGFILE"

exit 0
