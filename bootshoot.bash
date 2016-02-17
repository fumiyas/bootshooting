#!/bin/bash
##
## BootShooting: Shoot itself in the boots
## Copyright (c) 2016 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU Genera Public Licsense version 3
##

set -u
set -e
set -o pipefail
shopt -s lastpipe
umask 0022

export LC_ALL=C

## ======================================================================

busybox_path="/bin/busybox"

bin_requires=(
  /bin/sh
  /bin/cat
  /bin/mount
  /bin/umount
  /bin/ps
  /bin/dd
  /sbin/poweroff
)

bin_optionals=(
  "$busybox_path"
  /usr/bin/shred
  /usr/sbin/sshd
)
bin_optionals_found=()

lib_requires=(
  /lib*/ld-*.so.*
)

## ======================================================================

bootshoot_dir="/tmp/${0##*/}.$$.tmp"

mkdir -m 0700 "$bootshoot_dir"
mkdir -m 0755 \
  "$bootshoot_dir/dev" \
  "$bootshoot_dir/proc" \
  "$bootshoot_dir/tmp" \
  "$bootshoot_dir/bin" \
  "$bootshoot_dir/lib" \
;
ln -s lib "$bootshoot_dir/lib64"

## ----------------------------------------------------------------------

(
  cd / && find dev ! -type f -print \
  |cpio -o \
    2> >(sed '/^[0-9]\{1,\} blocks$/d' 1>&2) \
  ;
) \
|(
  cd "$bootshoot_dir" && cpio -id \
    2> >(sed '/^[0-9]\{1,\} blocks$/d' 1>&2) \
  ;
)

## ----------------------------------------------------------------------

for bin in "${bin_requires[@]}"; do
  cp -pL "$bin" "$bootshoot_dir/bin/"
done

for bin in "${bin_optionals[@]}"; do
  cp -pL "$bin" "$bootshoot_dir/bin/" || continue
  bin_optionals_found+=("$bin")
done

lib_requires+=($(
  ldd "${bin_requires[@]}" "${bin_optionals_found[@]}" \
  |sed -n 's/ (.*//; s/.* => //p' \
  |sort -u \
  ;
))

for lib in "${lib_requires[@]}"; do
  cp -pL "$lib" "$bootshoot_dir/lib/"
done

## ----------------------------------------------------------------------

if [[ -x $busybox_path ]]; then
  for bin in $("$busybox_path" |sed -n '1,/Currently defined functions/d; s/, */ /gp'); do
    [[ -e "$bootshoot_dir/bin/$bin" ]] && continue
    ln -s busybox "$bootshoot_dir/bin/$bin"
  done
fi

