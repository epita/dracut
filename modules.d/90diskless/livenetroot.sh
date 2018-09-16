#!/bin/sh
# livenetroot - fetch a live image from the network and run it

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

. /lib/url-lib.sh

PATH=/usr/sbin:/usr/bin:/sbin:/bin

[ -e /tmp/livenet.downloaded ] && exit 0

# args get passed from 40network/netroot
netroot="$2"
liveurl="${netroot#livenet:}"
info "fetching $liveurl"
imgfile=$(fetch_url "$liveurl")

if [ $? != 0 ]; then
	warn "failed to download live image: error $?"
	exit 1
fi

> /tmp/livenet.downloaded

mkdir -p /run/upper
mkdir -p /run/work

mkdir -p /run/sysroot
mount -n -t squashfs -o ro,loop $imgfile /run/sysroot
ln -s /run/sysroot /dev/root
