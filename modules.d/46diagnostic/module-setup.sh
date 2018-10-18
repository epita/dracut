#!/bin/bash
# module setup for CRI's diagnostic module
check() {
        require_binaries curl || return 1
        return 0
}

depends() {
        echo network
        return 0
}

install() {
        inst_multiple jq
        inst_hook pre-pivot 46 "$moddir/diagnostic.sh"
}
