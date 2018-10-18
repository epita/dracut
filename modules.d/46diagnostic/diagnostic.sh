#!/bin/bash

echo "Launching diagnostic module..."

IDENTITY=`hostname -f`

MEMORY=$((`cat /proc/meminfo | grep MemTotal | sed 's/[^0-9]//g'` / 1000000))

KEYBOARD='false'
if [ `lsusb -v 2>/dev/null | egrep '(^Bus|Keyboard)' | grep -B1 Keyboard | wc -l` -ne 0 ]; then
        echo "USB Keyboard found."
        KEYBOARD='true'
fi

MOUSE='false'
if [ `lsusb -v 2>/dev/null | grep 'Mouse' | wc -l` -ne 0 ]; then
        echo "USB Mouse found."
        MOUSE='true'
fi

THUNDERBOLT='false'
THUNDERBOLT_SECURE='false'
echo "Activating thunderbolt hosts..."
modprobe thunderbolt
TBOUT="`find /sys/devices/platform | grep force_power`"
if [ $? -eq 0 ]; then
        echo "Thunderbolt host detected"
        THUNDERBOLT='true'
        echo 1 > "$TBOUT"
        echo "Thunderbolt hosts activated."
        THUNDERBOLT_DETAIL="`cat /sys/bus/thunderbolt/devices/domain0/security 2> /dev/null`"
        if [ "$THUNDERBOLT_DETAIL" = "secure" ]; then
                echo "Thunderbolt is in secure mode."
                THUNDERBOLT_SECURE='true'
        fi
fi

JSON=$(jq -n \
        --argjson usb_keyboard "$KEYBOARD" \
        --argjson usb_mouse "$MOUSE" \
        --argjson memory_size "$MEMORY" \
        --argjson thunderbolt "$THUNDERBOLT" \
        --argjson thunderbolt_secure "$THUNDERBOLT_SECURE" \
        --arg thunderbolt_detail "$THUNDERBOLT_DETAIL" \
        --arg identity "$IDENTITY" \
        '{
           usb_keyboard: $usb_keyboard,
           usb_mouse: $usb_mouse,
           memory_size: $memory_size
           thunderbolt: $thunderbolt,
           thunderbolt_secure: $thunderbolt_secure,
           thunderbolt_detail: $thunderbolt_detail,
           identity: $identity
        }')

echo $JSON

curl -X POST --header 'Content-Type: text/plain' -d "$JSON" \
'https://cri.epita.fr/api/diagnostics/report'

echo "Diagnostic done."
