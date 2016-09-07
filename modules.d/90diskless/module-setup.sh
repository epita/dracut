#!/bin/bash
# module-setup.sh for livenet

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    echo network url-lib
    return 0
}

# called by dracut
install() {
    inst_hook cmdline 29 "$moddir/parse-livenet.sh"
    inst_script "$moddir/livenetroot.sh" "/sbin/livenetroot"
    if dracut_module_included "systemd-initrd"; then
        inst_script "$moddir/livenet-generator.sh" $systemdutildir/system-generators/dracut-livenet-generator
    fi
    dracut_need_initqueue
}
