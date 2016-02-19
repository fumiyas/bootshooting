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

echo "Creating bootshooting directory $bootshoot_dir ..."

mkdir -m 0700 "$bootshoot_dir"

mount -t tmpfs -o size=33554432,mode=0755 tmpfs "$bootshoot_dir"

mkdir -m 0755 \
  "$bootshoot_dir/dev" \
  "$bootshoot_dir/proc" \
  "$bootshoot_dir/tmp" \
  "$bootshoot_dir/bin" \
  "$bootshoot_dir/lib" \
;
ln -s lib "$bootshoot_dir/lib64"

## ----------------------------------------------------------------------

echo "Copying device files in /dev to $bootshoot_dir/dev ..."

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

echo "Copying commands to $bootshoot_dir/bin ..."

for bin in "${bin_requires[@]}"; do
  cp -pL "$bin" "$bootshoot_dir/bin/"
done

for bin in "${bin_optionals[@]}"; do
  cp -pL "$bin" "$bootshoot_dir/bin/" || continue
  bin_optionals_found+=("$bin")
done

## ----------------------------------------------------------------------

echo "Copying required libraries to $bootshoot_dir/lib ..."

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
  echo "Creating busybox commands in $bootshoot_dir/bin ..."

  for bin in $("$busybox_path" |sed -n '1,/Currently defined functions/d; s/, */ /gp'); do
    [[ -e "$bootshoot_dir/bin/$bin" ]] && continue
    ln -s busybox "$bootshoot_dir/bin/$bin"
  done
fi

## ======================================================================

tty=$(tty |sed 's#^/dev/##')
export tty

echo "Entering bootshooting directory $bootshoot_dir ..."
cat <<'EOT' >"$bootshoot_dir/bin/bootshoot"
#!/bin/sh

export PATH=/bin
trap '' INT TERM

confirm() {
  echo -n 'Are you sure? [y/N] '

  read answer

  if [ x"$answer" = "y" ]; then
    return 0
  fi

  return 1
}

echo 'Mounting /proc ...'
mount -t proc proc /proc

echo 'Suspending all processes except bootshooting processes ...'
pids=$(
  ps -ef \
  |tail -n +2 \
  |egrep -v "[ @]$tty( |$)" \
  |awk '{print $2}' \
  ;
)
kill -STOP $pids

echo 'Starting /bin/sh ...'
/bin/sh

## Dummy file for poweroff(8) and reboot(8)
: /proc/cmdline

echo 'Unmounting /proc ...'
umount /proc

while :; do
  echo
  echo 'Menu:'
  echo
  echo '  1 Force to poweroff'
  echo '  2 Force to reboot'
  echo '  3 Resume all suspended processes'
  echo '  4 Exit from bootshooting directory'
  echo '  5 Start /bin/sh again'
  echo
  echo -n 'Enter a number to do: '

  read answer

  case $answer in
  1)
    poweroff -f
    ;;
  2)
    reboot -f
    ;;
  3)
    if confirm; then
      kill -CONT $pids
    fi
    ;;
  4)
    if confirm; then
      exit 0
    fi
    ;;
  5)
    /bin/sh
    ;;
  esac
done
EOT
chmod +x "$bootshoot_dir/bin/bootshoot"

exec chroot "$bootshoot_dir" /bin/bootshoot

