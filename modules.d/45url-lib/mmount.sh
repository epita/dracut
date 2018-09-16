#!/bin/sh

mkdir -p /sysroot/srv/torrent
mount -o bind,ro /srv/torrent /sysroot/srv/torrent
