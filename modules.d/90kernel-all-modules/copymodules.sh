#!/bin/sh

mkdir -p $NEWROOT/usr/lib/modules/
cp -r /usr/lib/modules/$(uname -r) $NEWROOT/usr/lib/modules/
