#!/usr/bin/env bash
# set -x

# Copyright (C) 2014-2023 Uco Mesdag
# Usage:    kickstart-iso.sh [OPTIONS]
#   -i netinstall.iso               set the path of the ISO file.
#   -o custom.iso                   set the path of the ISO file or an output
#                                   directory to create the ISO file.
#   -k ks.cfg                       set the path of the kickstart configuration
#                                   file.
#   -p preseed.cfg                  set the path of the preseed configuration"
#                                   file."

# Instructions: Use this script to create a bootable ISO for Fedora, RHEL
#    CentOS, Almalinux, Rocky, or Debian installation, with a kickstarter or
#    preseed configuration file.

# Requirements: mkisofs (cdrtools), isomd5sum (only available on Linux),
#               syslinux (only available on Linux).

usage() {
  echo "Usage:    $(basename "$0") [OPTIONS]"
  echo "  -i netinstall.iso               set the path of the iso file."
  echo "  -o custom.iso                   set the path of the iso file or a output"
  echo "                                  directory to create the iso file."
  echo "  -k ks.cfg                       set the path of the kickstart configuration"
  echo "                                  file."
  echo "  -p preseed.cfg                  set the path of the preseed configuration"
  echo "                                  file."
}

if [ $# -ne 6 ]; then
  usage
  exit 1
fi

# Check if mkisofs is installed
if ! which mkisofs >/dev/null 2>&1; then
  echo "This script requires mkisofs to be installed."
  exit 1
fi

# On Linux Check if isomd5sum and syslinux are installed.
if [[ "$OSTYPE" != "darwin"* ]]; then
  if ! rpm -q --quiet isomd5sum; then
    echo "This script requires isomd5sum to be installed."
    exit 1
  fi
  # if ! rpm -q --quiet syslinux; then
  #   echo "This script requires syslinux to be installed."
  #   exit 1
  # fi
fi

echo "Your sudo password is required for mounting the ISO image."
sudo echo

OPTS="i:,o:,k:,p:"
while getopts $OPTS OPTIONS; do
   case $OPTIONS in
    i) ISO=$(readlink -f "$OPTARG") ;;
    o) IMG=$(touch "$OPTARG"; readlink -f "$OPTARG") ;;
    k) KS=$(readlink -f "$OPTARG") ;;
    p) PRESEED=$(readlink -f "$OPTARG") ;;
    ?) usage; exit 1;;
  esac
done

# Check options
if [ -z "$ISO" ]; then
  echo "ISO file not found."; exit 1
elif [ -z "$IMG" ]; then
  echo "Output file or directory not found."; exit 1
elif [ -z "$KS" ] && [ -z "$PRESEED" ]; then
  echo "Kickstart or preseed file not found."; exit 1
fi

echo "+--------------------------------------------------------+"
echo "|                  CUSTOM KICKSTART ISO                  | "
echo "+--------------------------------------------------------+"
echo

# make sure nothing was left over from a previous attempt
sudo umount /tmp/iso.* &>/dev/null
sudo rm -rf /tmp/iso.* &>/dev/null

WORKDIR=$(mktemp -d /tmp/iso.XXXXXX)
BUILD=$WORKDIR/build
MOUNT=$WORKDIR/mount

echo "> Copying files.."
mkdir -p "$BUILD" "$MOUNT"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  sudo mount -o ro,loop "$ISO" "$MOUNT"
  cp -aRT "$MOUNT" "$BUILD"
  sudo chown -R "$USER" "$BUILD"
  chmod -R +w "$BUILD"
  sudo umount "$ISO"
  rm -rf "$MOUNT"
else
  DISK=$(hdiutil attach -nobrowse -nomount "$ISO" \
    | grep -o "/dev/disk[0-9]\+" \
    | head -1)
  mount -t cd9660 "$DISK" "$MOUNT"
  sudo cp -R "$MOUNT/" "$BUILD" >/dev/null
  sudo chown -R "$USER" "$BUILD"
  chmod -R +w "$BUILD"
  umount "$DISK"
  rm -rf "$MOUNT"
fi

if [ -n "$KS" ]; then
  EFI_IMAGE="images/efiboot.img"

  echo "> Adding kickstart configuration.."
  cp "$KS" "$BUILD/ks.cfg"

  # Legacy boot
  if [ -f "$BUILD/isolinux/isolinux.cfg" ]; then
    LABEL=$(sed -n 's/menu label \^Install \(.*\)/\1/p' \
      "$BUILD/isolinux/isolinux.cfg" \
      | sed -e 's/^ *//' -e 's/ *$//')
    ID=$(grep hd:LABEL= "$BUILD/isolinux/isolinux.cfg" \
      | head -1 \
      | sed 's/.*=hd:LABEL=\(.*\)\s.*/\1/')
    sed -i '/menu default/d' "$BUILD/isolinux/isolinux.cfg"
    sed -i "/^label check$/{N; /^label check/ i \\
label linux_ks \\
  menu default \\
  menu label Install $LABEL with ^Kickstart \\
  kernel vmlinuz \\
  append initrd=initrd.img inst.stage2=hd:LABEL=$ID inst.ks=hd:LABEL=$ID:/ks.cfg inst.sshd quiet \\

}" "$BUILD/isolinux/isolinux.cfg"
  fi

  # UEFI boot
  if [ -f "$BUILD/EFI/BOOT/grub.cfg" ]; then
    LABEL=$(sed -n 's/^menuentry \x27Install \(.*\)\x27.*/\1/p' \
      "$BUILD/EFI/BOOT/grub.cfg")
    ID=$(grep hd:LABEL= "$BUILD/EFI/BOOT/grub.cfg" \
      | head -1 \
      | sed 's/.*=hd:LABEL=\(.*\)\s.*/\1/')
    # sed -i 's/^set default="1"/set default="2"/' "$BUILD/EFI/BOOT/grub.cfg"
    sed -i "/^menuentry \x27Test/{N; /^menuentry \x27Test/ i \\
menuentry 'Install $LABEL with Kickstart' --class fedora --class gnu-linux --class gnu --class os { \\
        linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$ID inst.ks=hd:LABEL=$ID:/ks.cfg inst.sshd quiet \\
        initrdefi /images/pxeboot/initrd.img \\
}

}" "$BUILD/EFI/BOOT/grub.cfg"
    [ -f "$BUILD/EFI/BOOT/BOOT.conf" ] && \
      cp "$BUILD/EFI/BOOT/grub.cfg" "$BUILD/EFI/BOOT/BOOT.conf"
  fi

fi

if [ -n "$PRESEED" ]; then
  EFI_IMAGE="boot/grub/efi.img"
  ID="$(isoinfo -d -i "$ISO" | grep Volume\ id: | sed -e 's/Volume id:\(.*\)/\1/' | xargs)"

  echo "> Adding preseed configuration.."
  cp "$PRESEED" "$BUILD/preseed.cfg"

  # Legacy boot
  if [ -f "$BUILD/isolinux/isolinux.cfg" ]; then
    # add preseed.cfg to all auto install options
    for file in $(grep -Rl auto=true  "$BUILD/isolinux"); do
      sed -i 's/auto=true priority=critical/file=\/cdrom\/preseed.cfg auto=true priority=critical locale=en_US/' "$file"
    done
    # remove default
    sed -i -e 's/^default/# default/' -e 's/menu default/# menu default/' "$BUILD/isolinux/gtk.cfg"
    # remove autoboot for speech-enabled install
    sed -i -e 's/^timeout/# timeout/' \
      -e 's/^ontimeout/# ontimeout/' \
      -e 's/^menu autoboot/# menu autoboot/' \
      "$BUILD/isolinux/spkgtk.cfg"
    # add new entry to default menu
    cat >> "$BUILD/isolinux/txt.cfg" <<EOF
default auto
label auto
	menu label ^Automated install
  menu default
	kernel /install.amd/vmlinuz
	append file=/cdrom/preseed.cfg auto=true priority=critical locale=en_US vga=788 initrd=/install.amd/initrd.gz --- quiet
# timeout to automated install install
timeout 300
ontimeout /install.amd/vmlinuz file=/cdrom/preseed.cfg auto=true priority=critical locale=en_US vga=788 initrd=/install.amd/initrd.gz --- quiet
menu autoboot Press a key, otherwise Automated install will be started in # second{,s}...
EOF
  fi

  # UEFI boot
  if [ -f "$BUILD/boot/grub/grub.cfg" ]; then
    sed -i 's/auto=true priority=critical/file=\/cdrom\/preseed.cfg auto=true priority=critical locale=en_US/g' "$BUILD/boot/grub/grub.cfg"
    echo -e "set default=2\nset timeout=30\n$(cat "$BUILD/boot/grub/grub.cfg")" > "$BUILD/boot/grub/grub.cfg"
    sed -i "/^submenu --hotkey=a 'Advanced options ...'/ i \\
menuentry --hotkey=a 'Automated install' { \\
    set background_color=black \\
    linux    /install.amd/vmlinuz file=/cdrom/preseed.cfg auto=true priority=critical locale=en_US vga=788 --- quiet \\
    initrd   /install.amd/initrd.gz \\
}
" "$BUILD/boot/grub/grub.cfg"
  fi

cd "$BUILD" || exit

# Update md5sum
md5sum "$(find -L . -type f ! -name md5sum.txt ! -name boot.cat ! -name isolinux.bin)" > md5sum.txt

fi

echo "> Creating image file.."
cd "$BUILD" || exit
mkisofs -quiet -untranslated-filenames -V "$ID" \
  -J -joliet-long -rational-rock -translation-table -input-charset utf-8 \
  -x ./lost+found -b isolinux/isolinux.bin -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot \
  -b "$EFI_IMAGE" -no-emul-boot \
  -o "$IMG" \
  -T "$BUILD" &>/dev/null

if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "> Update md5sum.."
  implantisomd5 "$IMG" &>/dev/null
fi

echo "> Making image bootable from USB.."
if [[ "$OSTYPE" == "darwin"* ]]; then
  if [ ! -f "$WORKDIR/isohybrid.pl" ]; then
    curl -s https://gist.githubusercontent.com/AkdM/2cd3766236582ed0263920d42c359e0f/raw/6eabb3905d614d0999266ff6623bce70771c4b20/isohybrid.pl -o "$WORKDIR/isohybrid.pl"
  fi
  perl "$WORKDIR/isohybrid.pl" "$IMG" &>/dev/null
else
  isohybrid "$IMG" &>/dev/null
fi

# Cleanup tmp directory
sudo rm -rf "$WORKDIR"

sleep 5; echo "Done!"; exit 0
