#!/bin/sh

mkdir -p /sysroot/srv/torrent
mount -o bind,ro /torrent /sysroot/srv/torrent
