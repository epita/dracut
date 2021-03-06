#!/bin/sh
# url-lib.sh - functions for handling URLs (file fetching etc.)
#
# Authors:
#   Will Woods <wwoods@redhat.com>

type mkuniqdir >/dev/null 2>&1 || . /lib/dracut-lib.sh

# fetch_url URL [OUTFILE]
#   fetch the given URL to a locally-visible location.
#   if OUTFILE is given, the URL will be fetched to that filename,
#   overwriting it if present.
#   If the URL is something mountable (e.g. nfs://) and no OUTFILE is given,
#   the server will be left mounted until pre-pivot.
#   the return values are as follows:
#   0: success
#   253: unknown error (file missing)
#   254: unhandled URL scheme / protocol
#   255: bad arguments / unparseable URLs
#   other: fetch command failure (whatever curl/mount/etc return)
fetch_url() {
    local url="$1" outloc="$2"
    local handler="$(get_url_handler $url)"
    [ -n "$handler" ] || return 254
    [ -n "$url" ] || return 255
    "$handler" "$url" "$outloc"
}

# get_url_handler URL
#   returns the first HANDLERNAME corresponding to the URL's scheme
get_url_handler() {
    local scheme="${1%%:*}" item=""
    for item in $url_handler_map; do
        [ "$scheme" = "${item%%:*}" ] && echo "${item#*:}" && return 0
    done
    return 1
}

# add_url_handler HANDLERNAME SCHEME [SCHEME...]
#   associate the named handler with the named scheme(s).
add_url_handler() {
    local handler="$1"; shift
    local schemes="$@" scheme=""
    set --
    for scheme in $schemes; do
        [ "$(get_url_handler $scheme)" = "$handler" ] && continue
        set -- "$@" "$scheme:$handler"
    done
    set -- $@ $url_handler_map # add new items to *front* of list
    url_handler_map="$@"
}

### HTTP, HTTPS, FTP #################################################

export CURL_HOME="/run/initramfs/url-lib"
mkdir -p $CURL_HOME
curl_args="--globoff --location --retry 3 --fail --show-error"
getargbool 0 rd.noverifyssl && curl_args="$curl_args --insecure"

proxy=$(getarg proxy=)
[ -n "$proxy" ] && curl_args="$curl_args --proxy $proxy"

curl_fetch_url() {
    local url="$1" outloc="$2"
    echo "$url" > /proc/self/fd/0
    if [ -n "$outloc" ]; then
        curl $curl_args --output - -- "$url" > "$outloc" || return $?
    else
        local outdir="$(mkuniqdir /tmp curl_fetch_url)"
        ( cd "$outdir"; curl $curl_args --remote-name "$url" || return $? )
        outloc="$outdir/$(ls -A $outdir)"
    fi
    if ! [ -f "$outloc" ]; then
	    warn "Downloading '$url' failed!"
	    return 253
    fi
    if [ -z "$2" ]; then echo "$outloc" ; fi
}
add_url_handler curl_fetch_url http https ftp tftp

set_http_header() {
    echo "header = \"$1: $2\"" >> $CURL_HOME/.curlrc
}

### TORRENT ##########################################################

ctorrent_args="-E 0 -e 0"

ctorrent_fetch_url() {
    local url="$1" outloc="$2"
    url=${url#*//}
    torrent_outloc="$outloc.torrent"
    echo "$url" > /proc/self/fd/0
    if [ -n "$outloc" ]; then
        curl $curl_args --output - -- "$url" > "$torrent_outloc" || return $?
    else
        local outdir="$(mkuniqdir /tmp torrent_fetch_url)"
        ( cd "$outdir"; curl $curl_args --remote-name "$url" || return $? )
        torrent_outloc="$outdir/$(ls -A $outdir)"
        outloc=${torrent_outloc%.*}
    fi
    if ! [ -f "$torrent_outloc" ]; then
        warn "Downloading '$url' failed!"
        return 253
    fi
    ctorrent $ctorrent_args -s $outloc $torrent_outloc >&2
    if ! [ -f "$outloc" ]; then
        warn "Torrent download of '$url' failed!"
        return 253
    fi
    if [ -z "$2" ]; then echo "$outloc" ; fi
}

command -v ctorrent >/dev/null \
    && add_url_handler ctorrent_fetch_url torrent

### NFS ##############################################################

[ -e /lib/nfs-lib.sh ] && . /lib/nfs-lib.sh

nfs_already_mounted() {
    local server="$1" path="$2" localdir="" s="" p=""
    cat /proc/mounts | while read src mnt rest || [ -n "$src" ]; do
        splitsep ":" "$src" s p
        if [ "$server" = "$s" ]; then
            if [ "$path" = "$p" ]; then
                echo $mnt
            elif str_starts "$path" "$p"; then
                echo $mnt/${path#$p/}
            fi
        fi
    done
}

nfs_fetch_url() {
    local url="$1" outloc="$2" nfs="" server="" path="" options=""
    nfs_to_var "$url" || return 255
    local filepath="${path%/*}" filename="${path##*/}" mntdir=""

    # skip mount if server:/filepath is already mounted
    mntdir=$(nfs_already_mounted "$server" "$path")
    if [ -z "$mntdir" ]; then
        local mntdir="$(mkuniqdir /run nfs_mnt)"
        mount_nfs "$nfs:$server:$filepath${options:+:$options}" "$mntdir"
        # lazy unmount during pre-pivot hook
        inst_hook --hook pre-pivot --name 99url-lib-umount-nfs umount -l -- "$mntdir"
    fi

    if [ -z "$outloc" ]; then
        outloc="$mntdir/$filename"
    else
        cp -f -- "$mntdir/$filename" "$outloc" || return $?
    fi
    [ -f "$outloc" ] || return 253
    if [ -z "$2" ]; then echo "$outloc" ; fi
}
command -v nfs_to_var >/dev/null && add_url_handler nfs_fetch_url nfs nfs4

aria2_base=" -V --file-allocation=prealloc --enable-mmap=true --seed-ratio=0 --summary-interval=60"
aria2_nodht="--enable-dht=false --enable-dht6=false"
aria2_noseed="--seed-time=0"
aria2_opts="$aria2_base $aria2_nodht $aria2_noseed"

aria_fetch_url() {
    local url="$1" outloc="$2"
    url=${url#*//}
    torrentname=${url##*/}
    filename=${torrentname%.torrent}.squashfs
    torrentfile="https://$url"

    if [ -z "$outloc" ]; then
        outloc="/srv/torrent"
    fi

    # Launch rngd to fill entropy pools for aria2c
    rngd >&2

    mkdir -p "$outloc"

    if getargbool 0 nobootcache; then
        warn "bootcache disabled"
        mount -t tmpfs none "$outloc"
    else
        if [[ -e /dev/disk/by-partlabel/bootcache ]]; then
            if mount -t ext4 /dev/disk/by-partlabel/bootcache "$outloc"; then
                if ! getargbool 0 skipdownload; then
                    rm -f "$outloc/$torrentname"
                fi
            else
                warn "Failed to mount bootcache, falling back to tmpfs"
                mount -t tmpfs none "$outloc"
            fi
        else
            warn "No bootcache partition found"
            mount -t tmpfs none "$outloc"
        fi
    fi

    if getargbool 0 skipdownload && [ -r "$outloc/$torrentname" ]; then
        torrentfile="$outloc/$torrentname"
    fi

    aria2c $aria2_opts -d $outloc -O 1=$filename "$torrentfile" > /dev/console

    if ! [ -f "$outloc/$filename" ]; then
        warn "Torrent download of '$url' failed!"
        return 253
    fi

    kill -9 $(pidof rngd)

    for torrent in $(ls $outloc/*.torrent); do
	torrentname=${torrent##*/}
	echo $torrent
	echo " index-out=1=${torrentname%.torrent}.squashfs"
	echo " dir=$outloc"
	echo " check-integrity=true"
    done > "$outloc/aria2_seedlist.txt"

    if [ -z "$2" ]; then echo "$outloc/$filename" ; fi
}

command -v aria2c >/dev/null && add_url_handler aria_fetch_url torrent
