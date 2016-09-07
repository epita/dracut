#!/bin/bash

depends() {
	echo "kernel-modules"
	return 0
}

installkernel() {
	instmods =drivers =arch =crypto =fs =kernel =lib =misc =mm =net =security =sound =virt
}

install() {
	inst_hook pre-pivot 01 "$moddir/copymodules.sh"
}
