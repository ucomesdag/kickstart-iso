# kickstart-iso

This repository contains `kickstart-iso.sh` , a script that enables the creation of a custom bootable ISO image for automated installation using a kickstart or preseed configuration file. The script supports all EL (Enterprise Linux) distributions: Fedora, RHEL, CentOS, AlmaLinux, Rocky and Debian installations and is compatible with Linux and macOS systems.

*Note: "Due to the unavailability of isomd5sum, a tool to update the md5 checksum on the ISO image, testing the media is not possible when using an EL ISO image created on MacOS."*

## Requirements
+ mkisofs (cdrtools)
+ isomd5sum (not available for MacOS)

## Usage
1. Clone this repository on your local machine.

2. Next download an EL (Enterprise Linux) ISO image and customize the `kickstart.cfg` or `pressed.cfg` file.

3. Run the following command to create the customized ISO image:
```
# With a kickstart file:
./kickstart-iso.sh -i netinstall.iso -o custom.iso -k kickstart.cfg

# With a preseed file:
./kickstart-iso.sh -i netinstall.iso -o custom.iso -p preseed.cfg
```

```
% ./kickstart-iso.sh
Usage:    kickstart-iso.sh [OPTIONS]
  -i netinstall.iso               set the path of the ISO file.
  -o custom.img                   set the path of the ISO file or an output
                                  directory to create the ISO file.
  -k ks.cfg                       set the path of the kickstart configuration
                                  file.
  -p preseed.cfg                  set the path of the preseed configuration"
                                  file."
```
