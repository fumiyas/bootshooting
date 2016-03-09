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
  /bin/sync
  /bin/ps
  /bin/dd
  /bin/sleep
  /sbin/poweroff
)

bin_optionals=(
  "$busybox_path"
  /usr/bin/shred
  /sbin/fsfreeze
)
bin_optionals_found=()

lib_requires=(
  /lib*/ld-*.so.*
)

## ======================================================================

bootshoot_dir="/tmp/${0##*/}.$$.tmp"

echo "Creating BootShooting directory $bootshoot_dir ..."

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

## Dummy file for poweroff(8) and reboot(8)
: >"$bootshoot_dir/proc/cmdline"

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

BOOTSHOOT_HOSTNAME=$(uname -n |sed 's/\..*//')
BOOTSHOOT_TTY=$(tty |sed 's#^/dev/##')
export BOOTSHOOT_HOSTNAME BOOTSHOOT_TTY

echo "Entering BootBhooting directory $bootshoot_dir ..."
cat <<'EOT' >"$bootshoot_dir/bin/bootshoot"
#!/bin/sh

set -u
export PATH=/bin

trap '' INT TERM
trap 'umount /proc' EXIT

pids() {
  ps -ef \
  |(
    read x
    while read x pid ppid x x tty x cmd; do
      ## Login user's processes
      [ x"$tty" = x"$BOOTSHOOT_TTY" ] && continue
      ## Remote user's sshd process
      cmd="$cmd "
      [ -z "${cmd%%*@$BOOTSHOOT_TTY *}" ] && continue
      ## BootShooting and child processes
      [ x"$ppid" = x"$$" ] && continue
      [ x"$pid" = x"$$" ] && continue
      ## Other processes
      echo $pid
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

echo 'Mounting /proc ...'
mount -t proc proc /proc

while :; do
  echo
  echo 'BootShooting Menu:'
  echo
  echo '  1 : Suspend all processes except BootShooting processes'
  echo '  2 : Start /bin/sh in BootShooting environment'
  echo '  3 : Force to poweroff'
  echo '  4 : Force to reboot'
  echo '  5 : Resume all suspended processes'
  echo '  6 : Exit from BootShooting environment'
  echo
  echo -n 'Enter a number to do: '

  read answer
  echo

  case $answer in
  1)
    echo 'Sending SIGSTOP to all processes except BootShooting ...'
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
      ## Prevent kernel panic on flushing after BootShooting
      echo 'Flushing cached writes to filesystem in storge ...'
      sync
    fi
    ;;
  2)
    PS1='BootShooting@$BOOTSHOOT_HOSTNAME # ' /bin/sh
    ;;
  3)
    umount /proc
    poweroff -f
    ;;
  4)
    umount /proc
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
EOT
chmod +x "$bootshoot_dir/bin/bootshoot"

exec chroot "$bootshoot_dir" /bin/bootshoot

