#!/bin/bash
##
## Unbootstrap: Shred files in a remote running OS (Shoot yourself in the foot)
## Copyright (c) 2016-2017 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU Genera Public Licsense version 3
##

set -u
set -e
set -o pipefail
umask 0022

export LC_ALL=C

## ======================================================================

busybox_path=""

bin_requires=(
  /bin/sh
  /bin/cat
  /bin/mount
  /bin/umount
  /bin/sync
  /bin/ps
  /bin/dd
  /bin/sleep
  /sbin/poweroff
)

bin_optionals=(
  /bin/busybox
  /sbin/busybox
  /bin/lsblk
  /usr/bin/shred
  /sbin/fsfreeze
)
bin_optionals_found=()

lib_requires=(
  /lib*/ld-*.so.*
)

## ======================================================================

unbootstrap_dir="/tmp/${0##*/}.$$.tmp"

echo "Creating Unbootstrap directory $unbootstrap_dir ..."

mkdir -m 0700 "$unbootstrap_dir"

mount -t tmpfs -o size=33554432,mode=0755 tmpfs "$unbootstrap_dir"

mkdir -m 0755 \
  "$unbootstrap_dir/dev" \
  "$unbootstrap_dir/proc" \
  "$unbootstrap_dir/sys" \
  "$unbootstrap_dir/tmp" \
  "$unbootstrap_dir/bin" \
  "$unbootstrap_dir/lib" \
;

ln -s lib "$unbootstrap_dir/lib64"

## Dummy file for poweroff(8) and reboot(8) in Linux
: >"$unbootstrap_dir/proc/cmdline"

## ----------------------------------------------------------------------

echo "Copying device files in /dev to $unbootstrap_dir/dev ..."

(
  cd / && find dev ! -type f -print \
  |cpio -o \
    2> >(sed '/^[0-9]\{1,\} blocks$/d' 1>&2) \
  ;
) \
|(
  cd "$unbootstrap_dir" && cpio -id \
    2> >(sed '/^[0-9]\{1,\} blocks$/d' 1>&2) \
  ;
)

## ----------------------------------------------------------------------

echo "Copying commands to $unbootstrap_dir/bin ..."

for bin in "${bin_requires[@]}"; do
  cp -pL "$bin" "$unbootstrap_dir/bin/"
done

for bin in "${bin_optionals[@]}"; do
  if [[ ${bin##*/} == "busybox" ]]; then
    [[ -n $busybox_path ]] && continue
    busybox_path="$bin"
  fi
  cp -pL "$bin" "$unbootstrap_dir/bin/" || continue
  bin_optionals_found+=("$bin")
done

## ----------------------------------------------------------------------

echo "Copying required libraries to $unbootstrap_dir/lib ..."

lib_requires+=($(
  { ldd "${bin_requires[@]}" "${bin_optionals_found[@]}" || :; } \
  |sed -n 's/ (.*//; s/.* => //p' \
  |sort -u \
  ;
))

for lib in "${lib_requires[@]}"; do
  cp -pL "$lib" "$unbootstrap_dir/lib/"
done

## ----------------------------------------------------------------------

if [[ -n $busybox_path ]]; then
  echo "Creating busybox commands in $unbootstrap_dir/bin ..."

  for bin in $("$busybox_path" |sed -n '1,/Currently defined functions/d; s/, */ /gp'); do
    [[ -e "$unbootstrap_dir/bin/$bin" ]] && continue
    ln -s busybox "$unbootstrap_dir/bin/$bin"
  done
fi

## ======================================================================

UNBOOTSTRAP_HOSTNAME=$(uname -n |sed 's/\..*//')
UNBOOTSTRAP_TTY=$(tty |sed 's#^/dev/##')
export UNBOOTSTRAP_HOSTNAME UNBOOTSTRAP_TTY

echo "Entering Unbootstrap directory $unbootstrap_dir ..."
sed '1,/^UNBOOTSTRAP_SHELL$/d' "$0" >"$unbootstrap_dir/bin/unbootstrap"
chmod +x "$unbootstrap_dir/bin/unbootstrap"

chroot "$unbootstrap_dir" /bin/unbootstrap
exit $?

## ======================================================================
UNBOOTSTRAP_SHELL
#!/bin/sh

set -u
export PATH=/bin

atexit() {
  umount /proc
  umount /sys
}

pids() {
  ps -ef \
  |(
    read x
    while read x pid ppid x x tty x cmd; do
      ## Login user's processes
      [ x"$tty" = x"$UNBOOTSTRAP_TTY" ] && continue
      ## Remote user's sshd process
      cmd="$cmd "
      [ -z "${cmd%%*@$UNBOOTSTRAP_TTY *}" ] && continue
      ## Unbootstrap and child processes
      [ x"$ppid" = x"$$" ] && continue
      [ x"$pid" = x"$$" ] && continue
      ## Other processes
      echo "$pid"
    done
  )
}

confirm() {
  local answer

  echo -n 'Are you sure? [y/N] '
  read answer

  if [ x"$answer" = x"y" ]; then
    return 0
  fi

  return 1
}

trap '' INT TERM
trap 'ret=$?; atexit; exit $?' EXIT

echo 'Mounting /proc ...'
mount -t proc proc /proc
echo 'Mounting /sys ...'
mount -t sysfs sysfs /sys

while :; do
  echo
  echo 'Unbootstrap Menu:'
  echo
  echo '  1 : Suspend all processes except Unbootstrap processes'
  echo '  2 : Start /bin/sh in Unbootstrap environment'
  echo '  3 : Force to poweroff'
  echo '  4 : Force to reboot'
  echo '  5 : Resume all suspended processes'
  echo '  6 : Exit from Unbootstrap environment'
  echo
  echo -n 'Enter a number to do: '

  read answer
  echo

  case $answer in
  1)
    echo 'Sending SIGSTOP to all processes except Unbootstrap ...'
    timedout=
    trap 'timedout=set' USR1
    pids=$(pids)
    kill -STOP $pids
    (
      sleep 10
      echo
      echo 'ERROR: Timed out'
      echo 'ERROR: Resuming all processes to recover ...'
      kill -CONT $pids
      kill -USR1 $$
      while :; do sleep 10; done
    ) &
    echo
    echo -n 'Press [Enter] key to continue ... '
    read x
    kill -9 $!
    trap - USR1
    if [ -z "$timedout" ]; then
      ## Prevent kernel panic or unexpected behavior on flushing after
      ## destroying filesystems in Unbootstrap environment
      echo 'Flushing cached writes to filesystem ...'
      sync
    fi
    ;;
  2)
    PS1='Unbootstrap@$UNBOOTSTRAP_HOSTNAME # ' /bin/sh
    ;;
  3)
    poweroff -f
    ;;
  4)
    reboot -f
    ;;
  5)
    if confirm; then
      pids=$(pids)
      kill -CONT $pids
    fi
    ;;
  6)
    if confirm; then
      exit 0
    fi
    ;;
  esac
done
