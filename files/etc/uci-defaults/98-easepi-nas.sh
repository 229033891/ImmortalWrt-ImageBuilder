#!/bin/sh
# EasePi R1 NAS 基线：USB 挂载、nas 用户、Samba 共享骨架、cron
# 不写入任何密码 / rclone 远程凭证；刷机后自行 smbpasswd / 恢复 rclone.conf

LOGFILE="/etc/config/uci-defaults-log.txt"
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "98-easepi-nas.sh board=$board_name at $(date)" >>"$LOGFILE"

case "$board_name" in
*easepi-r1*|*easepi_r1*) ;;
*)
	echo "skip 98-easepi-nas.sh (not EasePi R1)" >>"$LOGFILE"
	exit 0
	;;
esac

# USB 数据盘（现网 UUID）
USB_UUID="4e14454f-be3e-4048-8854-1bfc0cc820cf"
USB_TARGET="/mnt/sda1"

# 若尚未配置该 UUID 挂载则追加
already=$(uci show fstab 2>/dev/null | grep -F "$USB_UUID" || true)
if [ -z "$already" ]; then
	uci add fstab mount >/dev/null
	uci set fstab.@mount[-1].enabled='1'
	uci set fstab.@mount[-1].uuid="$USB_UUID"
	uci set fstab.@mount[-1].target="$USB_TARGET"
	uci set fstab.@mount[-1].fstype='ext4'
	uci set fstab.@mount[-1].options='rw,relatime'
	uci set fstab.@mount[-1].enabled_fsck='0'
	uci commit fstab
	echo "fstab: mount $USB_UUID -> $USB_TARGET" >>"$LOGFILE"
else
	echo "fstab: UUID already present" >>"$LOGFILE"
fi

mkdir -p "$USB_TARGET" /mnt/sda1/sync

# 系统用户 nas（home 指向 USB；密码请刷后: passwd nas && smbpasswd -a nas）
if ! id nas >/dev/null 2>&1; then
	if command -v useradd >/dev/null 2>&1; then
		useradd -M -d "$USB_TARGET" -s /bin/ash nas 2>/dev/null || true
		echo "created user nas" >>"$LOGFILE"
	else
		echo "useradd not found; create nas manually" >>"$LOGFILE"
	fi
fi

# Samba 共享 usbdata -> /mnt/sda1
if [ -f /etc/config/samba4 ] || command -v smbd >/dev/null 2>&1; then
	touch /etc/config/samba4
	if ! uci -q get samba4.@samba[0] >/dev/null; then
		uci add samba4 samba >/dev/null
	fi
	uci set samba4.@samba[0].interface='lan'
	uci set samba4.@samba[0].workgroup='WORKGROUP'
	uci set samba4.@samba[0].description='ImmortalWrt-shlt'
	uci set samba4.@samba[0].enable_extra_tuning='1'

	# 删除旧 usbdata 共享后重建，避免重复
	idx=0
	while uci -q get samba4.@sambashare[$idx] >/dev/null; do
		name=$(uci -q get samba4.@sambashare[$idx].name)
		if [ "$name" = "usbdata" ]; then
			uci delete samba4.@sambashare[$idx]
		else
			idx=$((idx + 1))
		fi
	done
	uci add samba4 sambashare >/dev/null
	uci set samba4.@sambashare[-1].name='usbdata'
	uci set samba4.@sambashare[-1].path="$USB_TARGET"
	uci set samba4.@sambashare[-1].read_only='no'
	uci set samba4.@sambashare[-1].guest_ok='no'
	uci set samba4.@sambashare[-1].dir_mask='0775'
	uci set samba4.@sambashare[-1].create_mask='0664'
	uci set samba4.@sambashare[-1].force_root='0'
	uci set samba4.@sambashare[-1].users='nas'
	uci commit samba4
	echo "samba4 share usbdata configured" >>"$LOGFILE"
fi

# 每日 01:00 同步（脚本在 files/usr/bin/sftp-sync.sh）
mkdir -p /etc/crontabs
if [ -f /etc/crontabs/root ]; then
	grep -q 'sftp-sync.sh' /etc/crontabs/root 2>/dev/null ||
		echo '0 1 * * * /usr/bin/sftp-sync.sh' >>/etc/crontabs/root
else
	echo '0 1 * * * /usr/bin/sftp-sync.sh' >/etc/crontabs/root
fi
/etc/init.d/cron enable 2>/dev/null || true
/etc/init.d/cron restart 2>/dev/null || true
echo "cron: 0 1 * * * /usr/bin/sftp-sync.sh" >>"$LOGFILE"

exit 0
