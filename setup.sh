#!/bin/bash

#
# Copyright (c) 2016, Manuel Streuhofer <manuel@streuhofer.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

IF_LOCAL="lo"
IF_EXTERNAL="eth0"
IF_INTERNAL="wznat"

if [[ "$OSTYPE" == "darwin"* ]]; then
	PATH="$PATH:/usr/local/bin"

	[ -z "$(command -v VBoxManage)" ] && exit 0

	IF_LOCAL="lo0"
	IF_EXTERNAL="en0"
	IF_INTERNAL="vboxnet"
	VBOX_USER=""

	MODE="start"
	IFACE="vboxnet0"
	IF_ADDRESS="172.16.0.1"
	IF_NETMASK="255.255.0.0"
fi

LOCAL_CONFIG="/etc/wznat/setup.conf"
[ -f "$LOCAL_CONFIG" ] && source "$LOCAL_CONFIG"

CONFIGD="/etc/wznat/config.d"
[ ! -d "$CONFIGD" ] && exit 1

function setup_configd {
	CONFIGD_HOSTS="$CONFIGD/dnsmasq.hosts"
	CONFIGD_IFACE_LOCAL="$CONFIGD/dnsmasq.$IF_LOCAL.iface"
	CONFIGD_IFACE="$CONFIGD/dnsmasq.$IFACE.iface"
	CONFIGD_PF="$CONFIGD/pf.rules"
}

function cleanup_configd {
	setup_configd

	echo "interface=$IF_LOCAL" > "$CONFIGD_IFACE_LOCAL"
	echo "no-dhcp-interface=$IF_LOCAL" >> "$CONFIGD_IFACE_LOCAL"

	[ -f "$CONFIGD_IFACE" ] && rm "$CONFIGD_IFACE"
	[ -f "$CONFIGD_PF" ] && rm "$CONFIGD_PF"

	for CLEANUP_IFACE_FILE in $(find "$CONFIGD" -type f -name 'dnsmasq.*.iface'); do
		CLEANUP_IFACE_NAME="$(basename "$CLEANUP_IFACE_FILE" | cut -d'.' -f2)"
		ifconfig "$CLEANUP_IFACE_NAME" >/dev/null 2>&1 && continue
		rm "$CLEANUP_IFACE_FILE"
	done

	touch "$CONFIGD_HOSTS"

	[[ "$IFACE" != "$IF_INTERNAL"* ]] && return
	[ -z "$IF_ADDRESS" ] && return

	if [[ "$OSTYPE" == "darwin"* ]]; then
		sed -i '' "/^$IF_ADDRESS/d" "$CONFIGD_HOSTS"
		sed -i '' "/-$IFACE-gw$/d" "$CONFIGD_HOSTS"
	else
		sed -i "/^$IF_ADDRESS/d" "$CONFIGD_HOSTS"
		sed -i "/-$IFACE-gw$/d" "$CONFIGD_HOSTS"
	fi
}

function generate_configd {
	setup_configd

	if [[ "$IFACE" != "$IF_INTERNAL"* ]]; then
		echo "Ignoring interface \`$IFACE': does not match \`$IF_INTERNAL'." | logger -t "$0"
		return
	fi

	if [ "$(echo "$IF_NETMASK" | cut -d. -f3,4)" != "0.0" ]; then
		echo "Ignoring interface \`$IFACE': unsupported netmask \`$IF_NETMASK'." | logger -t "$0"
		return
	fi

	IF_NETWORK="$(echo "$IF_ADDRESS" | cut -d. -f1,2)"

	echo "$IF_ADDRESS  $(hostname -s)-$IFACE-gw" >> "$CONFIGD_HOSTS"

	echo "interface=$IFACE" > "$CONFIGD_IFACE"
	echo "dhcp-range=$IF_ADDRESS,static,$IF_NETMASK" >> "$CONFIGD_IFACE"
	echo "dhcp-range=$IF_NETWORK.128.1,$IF_NETWORK.255.254,1h" >> "$CONFIGD_IFACE"

	if [[ "$OSTYPE" == "darwin"* ]]; then
		echo "nat on $IF_EXTERNAL inet from ($IFACE:network) to any -> ($IF_EXTERNAL)" >> "$CONFIGD_PF"
	fi
}

function osx_vbox_hostonlyif {
	if [ -z "$VBOX_USER" ]; then
		echo "VirtualBox configuration not possible. VBOX_USER not defined. Setup \`$LOCAL_CONFIG'." | logger -t "$0"
		exit 1
	fi

	VBOX_KEXT_LOADED="no"

	for i in {60..1}; do
		if kextstat -lb org.virtualbox.kext.VBoxNetAdp 2>&1 | grep -q org.virtualbox.kext.VBoxNetAdp; then
			VBOX_KEXT_LOADED="yes"
			break
		fi

		sleep 1
	done

	if [ "$VBOX_KEXT_LOADED"  != "yes" ]; then
		echo "VirtualBox kernel extension not loaded. Giving up." | logger -t "$0"
		exit 1
	fi

	VBOX_IFLIST="$(sudo -Hnu "$VBOX_USER" VBoxManage list hostonlyifs)"
	VBOX_INITIAL_SETUP="no"

	if [ -z "$VBOX_IFLIST" ]; then
		sudo -Hnu "$VBOX_USER" VBoxManage hostonlyif create 2>&1 | logger -t "$0"
		VBOX_IFLIST="$(sudo -Hnu "$VBOX_USER" VBoxManage list hostonlyifs)"
		VBOX_INITIAL_SETUP="yes"
	fi

	if [ -z "$VBOX_IFLIST" ]; then
		echo "Error creating host-only network. Giving up." | logger -t "$0"
		exit 1
	fi

	if [ "$VBOX_INITIAL_SETUP" == "yes" ]; then
		IFACE="$(echo "$VBOX_IFLIST" | egrep '^Name:' | head -1 | awk '{ print $2 }')"

		sudo -Hnu "$VBOX_USER" VBoxManage hostonlyif ipconfig "$IFACE" \
			--ip "$IF_ADDRESS" --netmask "$IF_NETMASK" 2>&1 | logger -t "$0"

		VBOX_IFLIST="$(sudo -Hnu "$VBOX_USER" VBoxManage list hostonlyifs)"
	fi

	IFACE=""
	IF_ADDRESS=""
	IF_NETMASK=""

	for LINE in $(echo "$VBOX_IFLIST" | sed 's/ //g'); do
		KEY="$(echo "$LINE" | cut -d: -f1)"
		VALUE="$(echo "$LINE" | cut -d: -f2)"

		case "$KEY" in
			Name) IFACE="$VALUE" ;;
			IPAddress) IF_ADDRESS="$VALUE" ;;
			NetworkMask) IF_NETMASK="$VALUE" ;;

			Status)
				if [[ "$IFACE" == "$IF_INTERNAL"* ]]; then
					sudo -Hnu "$VBOX_USER" VBoxManage hostonlyif ipconfig "$IFACE" \
						--ip "$IF_ADDRESS" --netmask "$IF_NETMASK" 2>&1 | logger -t "$0"

					sudo -Hnu "$VBOX_USER" VBoxManage dhcpserver modify \
						--ifname "$IFACE" --disable 2>&1 | logger -t "$0"

					generate_configd
				fi

				IFACE=""
				IF_ADDRESS=""
				IF_NETMASK=""
				;;
		esac
	done
}

cleanup_configd

if [[ "$OSTYPE" == "darwin"* ]]; then
	osx_vbox_hostonlyif

	pfctl -f /etc/wznat/pf.conf -e 2>&1 | logger -t "$0"
	launchctl unload /etc/wznat/dnsmasq.plist 2>&1 | logger -t "$0"
	launchctl load /etc/wznat/dnsmasq.plist 2>&1 | logger -t "$0"
	sysctl -w net.inet.ip.forwarding=1 2>&1 | logger -t "$0"
else
	[[ "$IFACE" != "$IF_INTERNAL"* ]] && exit 0

	iptables -t nat -D POSTROUTING -s $IF_ADDRESS/$IF_NETMASK -o $IF_EXTERNAL -j MASQUERADE >/dev/null 2>&1
	iptables -t mangle -D POSTROUTING -p udp --dport bootpc -o $IFACE -j CHECKSUM --checksum-fill >/dev/null 2>&1
	service dnsmasq status >/dev/null 2>&1 && service dnsmasq restart

	[ "$MODE" != "start" ] && exit 0

	generate_configd

	iptables -t nat -I POSTROUTING -s $IF_ADDRESS/$IF_NETMASK -o $IF_EXTERNAL -j MASQUERADE
	iptables -t mangle -I POSTROUTING -p udp --dport bootpc -o $IFACE -j CHECKSUM --checksum-fill
	service dnsmasq status >/dev/null 2>&1 && service dnsmasq restart

	sysctl -qw net.ipv4.ip_forward=1
fi
