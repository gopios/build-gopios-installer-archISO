#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="gopios"
iso_label="GOPI_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="GopiOS <https://siliconpin.com/gopios>"
iso_application="GopiOS Live/Rescue"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d.%H%M)"
install_dir="gopios"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '-1')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.gnupg"]="0:0:700"
  ["/root/install.sh"]="0:0:755"
  # ["/usr/local/bin/choose-mirror"]="0:0:755"
  # ["/usr/local/bin/Installation_guide"]="0:0:755"
  # ["/usr/local/bin/livecd-sound"]="0:0:755"
)
