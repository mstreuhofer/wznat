# wznat

`wznat`, pronounced *whiz-nat*. NAT auto-configuration. Local DNS and DHCP
service provided by `dnsmasq`. Works on Linux and OS X.

Configure all locally running LXC container, VirtualBox machines and possibly
LXC container within VirtualBox machines with ease by using DHCP, yet have all
these machines refer to each other by name and have access to the outside world
thru the physical host machine's external network interface. No more thinking
about which IP address to give to which machine, editing any `/etc/hosts` file
or other shenanigans.

`dnsmasq` will provide DNS for the domain `.wznat` on `IF_LOCAL` and all
`IF_INTERNAL` interfaces as well as DHCP on all `IF_INTERNAL` interfaces. NAT
between `IF_INTERNAL` and `IF_EXTERNAL` will be handled by `iptables` on Linux
and `pf` on OS X.

The first half of the /16 subnet (`x.x.0.1 - x.x.127.255`) as configured on
`IF_INTERNAL` ist setup as static DHCP range while the second half
(`x.x.128.1 - x.x.255.254`) is setup as dynamic DHCP range.

Hardcoded defaults:

|              | Linux | OS X    |
| :---         | :---  | :---    |
| IF\_LOCAL    | lo    | lo0     |
| IF\_EXTERNAL | eth0  | en0     |
| IF\_INTERNAL | wznat | vboxnet |
| VBOX\_USER   | -     | -       |

Local defaults can be specified in `/etc/wznat/setup.conf`.

## OS X

Install necessary software (you will need [Homebrew] (http://brew.sh) for
this): `brew install dnsmasq`.

Symlink like you never symlinked before:

```
/etc/wznat -> $repo-checkout
/etc/resolver/wznat -> /etc/wznat/resolver.conf
/Library/LaunchDaemons/wznat.plist -> /etc/wznat/setup.plist
```

All `*.plist` files within the directory `/etc/wznat` have to be owned by
`root`. Make sure to set the proper ownership.

There is no such thing as LXC on OS X. It is all about VirtualBox. The script
`setup.sh` will use `VBoxManage` to find out about your VirtualBox
configuration. It will create a host-only network if there is none. It will
deactivate the associated VirtualBox DHCP server. Finally it will activate the
necessary network interfaces.

Setup is done on boot as system user `root`. It uses `sudo` to configure
VirtualBox for your user. This is the reason why you have to **specify your
username** in the variable `VBOX_USER` within `/etc/wznat/setup.conf`.

Configure your VirtualBox machine to have it's Network Adapter 1 attached to
Host-only Adapter `vboxnet0`. Set Promiscuous Mode under Advanced to *Allow
All*.

## Linux

Install necessary software `iptables` and `dnsmasq`.

Symlink like you never symlinked before:

```
/etc/wznat -> $repo-checkout
/etc/network/if-up.d/wznat -> /etc/wznat/setup.sh
/etc/network/if-down.d/wznat -> /etc/wznat/setup.sh
/etc/dnsmasq.d/wznat -> /etc/wznat/dnsmasq.conf
```

Configure your VirtualBox machine to have it's Network Adapter 1 attached to
Bridged Adapter `wznat0`. Set Promiscuous Mode under Advanced to *Allow All*.

### /etc/network/interfaces

```
auto wznat0
iface wznat0 inet static
  bridge_ports none
  bridge_fd 0
  bridge_maxwait 0
  bridge_stp off
  address 172.16.0.1/16

auto wznat1
iface wznat0 inet static
  bridge_ports none
  bridge_fd 0
  bridge_maxwait 0
  bridge_stp off
  address 172.17.0.1/16
```

### /etc/lxc/default.conf

```
lxc.network.type = veth
lxc.network.link = wznat1
lxc.network.flags = up
```

### /etc/dhcp/dhclient.conf

```
prepend domain-name-servers 127.0.0.1;
prepend domain-search "wznat";
```

# LICENSE

Copyright (c) 2016, Manuel Streuhofer <manuel@streuhofer.net>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
