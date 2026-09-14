#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")



# =========================================================
# 写入开机初始化脚本 (三频独立命名 + IPv6中继模式)
# =========================================================
mkdir -p ./package/base-files/files/etc/uci-defaults/

cat <<EOF > ./package/base-files/files/etc/uci-defaults/99-custom-setup
#!/bin/sh

# 等待系统默认的 Wi-Fi 配置文件生成完毕
sleep 3

# ==================== 三频独立命名配置 ====================
uci -q batch <<-UciEoF
	# === 2.4GHz 配置 ===
	set wireless.radio1.channel="1"
	set wireless.radio1.htmode="HE20"
	set wireless.radio1.disabled="0"
	set wireless.default_radio1.ssid="${WRT_SSID}"
	set wireless.default_radio1.encryption="psk2+ccmp"
	set wireless.default_radio1.key="${WRT_WORD}"

	# === 5GHz-1 配置 ===
	set wireless.radio0.channel="149"
	set wireless.radio0.htmode="HE80"
	set wireless.radio0.disabled="0"
	set wireless.default_radio0.ssid="${WRT_SSID}_5G1"
	set wireless.default_radio0.encryption="psk2+ccmp"
	set wireless.default_radio0.key="${WRT_WORD}"

	# === 5GHz-2 配置 ===
	set wireless.radio2.channel="44"
	set wireless.radio2.htmode="HE160"
	set wireless.radio2.disabled="0"
	set wireless.default_radio2.ssid="${WRT_SSID}_5G2"
	set wireless.default_radio2.encryption="psk2+ccmp"
	set wireless.default_radio2.key="${WRT_WORD}"
UciEoF

uci commit wireless

# ==================== IPv6 中继模式配置 ====================
# 修改 LAN 口 IPv6 模式为中继 (Relay)
uci set dhcp.lan.dhcpv6='relay'
uci set dhcp.lan.ra='relay'
uci set dhcp.lan.ndp='relay'

# 设置 WAN6 口 DHCP/RA/NDP 为中继并设为主接口 (Master)
uci set dhcp.wan6=dhcp
uci set dhcp.wan6.interface='wan6'
uci set dhcp.wan6.dhcpv6='relay'
uci set dhcp.wan6.ra='relay'
uci set dhcp.wan6.ndp='relay'
uci set dhcp.wan6.master='1'

# 清空 ULA 前缀（禁用内网私有 IPv6 地址，避免影响主网公网 IPv6 分配）
uci set network.globals.ula_prefix=''

uci commit dhcp
uci commit network

exit 0
EOF

chmod +x ./package/base-files/files/etc/uci-defaults/99-custom-setup




CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi
