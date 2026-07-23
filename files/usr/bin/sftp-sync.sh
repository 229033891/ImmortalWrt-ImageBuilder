#!/bin/sh
# FNNAS -> 本机 USB 同步骨架（对齐 ImmortalWrt-shlt）
# 凭证放在 USB 或 /etc，勿写入 Git 仓库：
#   推荐：/mnt/sda1/sync/rclone.conf
#   或：  /etc/rclone.conf
# 远程名请按你现网 rclone listremotes 调整（示例：fnnas-smb / fnnas-photos / fnnas-ftp）

set -e

SYNC_ROOT="/mnt/sda1/sync"
LOG="$SYNC_ROOT/sftp-sync.log"
RCLONE_CONF="$SYNC_ROOT/rclone.conf"
[ -f "$RCLONE_CONF" ] || RCLONE_CONF="/etc/rclone.conf"

mkdir -p "$SYNC_ROOT"
echo "===== $(date) start =====" >>"$LOG"

if ! command -v rclone >/dev/null 2>&1; then
	echo "rclone not installed" >>"$LOG"
	exit 1
fi

if [ ! -f "$RCLONE_CONF" ]; then
	echo "missing rclone config: $SYNC_ROOT/rclone.conf or /etc/rclone.conf" >>"$LOG"
	exit 1
fi

# 仅按体积判断，适合大目录夜间同步；需要更严校验可改掉 --size-only
RCLONE_OPTS="--config $RCLONE_CONF --size-only --transfers 4 --checkers 8 --log-file $LOG --log-level INFO"

# 示例远程：按刷后实际 remote 名称修改下面三行
# rclone sync "fnnas-smb:/vol1/1000/smb"     "$SYNC_ROOT/smb"     $RCLONE_OPTS
# rclone sync "fnnas-photos:/vol1/1000/Photos" "$SYNC_ROOT/Photos" $RCLONE_OPTS
# rclone sync "fnnas-ftp:/vol1/1000/ftp"     "$SYNC_ROOT/ftp"     $RCLONE_OPTS

if [ -x /mnt/sda1/sync/sftp-sync.local.sh ]; then
	# 优先执行 USB 上的本地覆盖脚本（可含真实 remote，且不进固件仓库）
	/mnt/sda1/sync/sftp-sync.local.sh >>"$LOG" 2>&1
else
	echo "no /mnt/sda1/sync/sftp-sync.local.sh ; edit this script or add local override" >>"$LOG"
fi

echo "===== $(date) end =====" >>"$LOG"
