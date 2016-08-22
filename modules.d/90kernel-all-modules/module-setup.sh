#!/bin/bash

depends() {
	echo "kernel-modules"
	return 0
}

installkernel() {
	instmods =drivers =arch =crypto =fs =kernel =lib =misc =mm =net =security =sound =virt
}

install() {
	:
}
