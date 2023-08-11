#!/bin/bash

###########################################################################################################
# This script is intended to be used on a spesific device only. (my laptop, Lenovo Legion Y530).          #
#                                                                                                         #
# It asummes many things. Such as:                                                                        #
# - You provide a file named 'packages' as a list of packages to install (including essential packages).  #
# - You use UEFI.                                                                                         #
# - You have an nvme drive named as 'nvme0n1'.                                                            #
# - You use GUID Partition Table (GPT).                                                                   #
# - You've partitioned the drive BEFORE running the script.                                               #
# - You created two partititons: nvme0n1p1 as ESP (at least 512MiB).                                      #
#                                nvme0n1p2 as the root partition (at least 20GiB).                        #
# - You have a seperate LUKS encrypted drive named as 'sda'                                               #
# - You have an Intel CPU.                                                                                #
# - You have an Nvidia card.                                                                              #
#                                                                                                         #
# Some things it does:                                                                                    #
# - Encrypts the root partition with LUKS.                                                                #
# - Sets up BTRFS (with a snapper friendly layout) for the root partition.                                #
# - Uses uinified kernel images with systemd-boot.                                                        #
# - Installs paru as AUR helper.                                                                          #
# - Sets up apparmor.                                                                                     #
# - Installs GNOME as the desktop environment.                                                            #
#                                                                                                         #
#                                                                                        Oğuzhan Yıldız   #
#                                                                                                         #
###########################################################################################################

# set variables
formatEsp="yes"
rootDev="nvme0n1"
espPart="nvme0n1p1"
rootPart="nvme0n1p2"
dataDrive="yes"
dataPart="sda1"
hostName="arch-y530"
defaultShell="bash"
userName="oguzhan"
realName="Oğuzhan Yıldız"
timeZone="Europe/Istanbul"
displayLang="en_US.UTF-8"
localeLang="tr_TR.UTF-8"
keyboardLayout="trq"
consoleFont="ter-120b"

read -p "WARNING! This script is ment to be for personal use only! It won't run as expected on other systems.
Please use it with caution. Read the code before using and change according to your needs.
Do you still want to continue? [Y/N]: " continue
if [[ "$continue" != [Yy]* ]]; then
	exit
fi

### MAKE FILE SYSTEMS

# change partition types in case user didn't
espPartNum=${espPart: -1}
# type: EFI System Partition
sfdisk /dev/$rootDev $espPartNum --part-type C12A7328-F81F-11D2-BA4B-00A0C93EC93B
rootPartNum=${rootPart: -1}
# type: Linux Filesystem
sfdisk /dev/$rootDev $rootPartNum --part-type 0FC63DAF-8483-4772-8E79-3D69D8477DE4

# ESP
if [[ "$formatEsp" == "yes" ]]; then
	mkfs.fat -F 32 -n "ESP" /dev/$espPart
fi

# ROOT
cryptsetup luksFormat /dev/$rootPart
cryptsetup open /dev/$rootPart luksArch
mkfs.btrfs -L "ARCH" /dev/mapper/luksArch
mount /dev/mapper/luksArch /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@root
btrfs su cr /mnt/@srv
btrfs su cr /mnt/@var_cache_pacman_pkg
btrfs su cr /mnt/@var_log
btrfs su cr /mnt/@.snapshots
umount /mnt

# store UUID of created partitions
luksArchUUID=$(lsblk /dev/$rootPart -rdno UUID)
if [[ "$dataDrive" == "yes" ]]; then
	luksDataUUID=$(lsblk /dev/$dataPart -rdno UUID)
fi

# mount partitions
mount -o noatime,compress=zstd,subvol=@ /dev/mapper/luksArch /mnt
mount --mkdir /dev/$espPart /mnt/efi
mount --mkdir -o noatime,compress=zstd,subvol=@home /dev/mapper/luksArch /mnt/home
mount --mkdir -o noatime,compress=zstd,subvol=@root /dev/mapper/luksArch /mnt/root
mount --mkdir -o noatime,compress=zstd,subvol=@srv /dev/mapper/luksArch /mnt/srv
mount --mkdir -o noatime,compress=zstd,subvol=@var_cache_pacman_pkg /dev/mapper/luksArch /mnt/var/cache/pacman/pkg
mount --mkdir -o noatime,compress=zstd,subvol=@var_log /dev/mapper/luksArch /mnt/var/log
mount --mkdir -o noatime,compress=zstd,subvol=@.snapshots /dev/mapper/luksArch /mnt/.snapshots
if [[ "$dataDrive" == "yes" ]]; then
	cryptsetup open /dev/$dataPart luksData
	mount --mkdir /dev/mapper/luksData /mnt/mnt/data
fi

# install packages
pacstrap -i /mnt - <packages

# generate fstab
genfstab -U /mnt >>/mnt/etc/fstab

# set hostname
printf "$hostName\n" >/mnt/etc/hostname

# set hosts
cat <<EOF >/mnt/etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $hostName.localdomain $hostName
EOF

# configure /etc/locale.gen
cat <<EOF >/mnt/etc/locale.gen
$displayLang UTF-8
$localeLang UTF-8
EOF

# configure /etc/locale.conf
cat <<EOF >/mnt/etc/locale.conf
LANG=$displayLang
LC_CTYPE=$localeLang
LC_NUMERIC=$localeLang
LC_TIME=$localeLang
LC_COLLATE=$localeLang
LC_MONETARY=$localeLang
LC_MESSAGES=$displayLang
LC_PAPER=$localeLang
LC_NAME=$localeLang
LC_ADDRESS=$localeLang
LC_TELEPHONE=$localeLang
LC_MEASUREMENT=$localeLang
LC_IDENTIFICATION=$localeLang
EOF

# change default keyboard layout and default font for the linux console
cat <<EOF >/mnt/etc/vconsole.conf
KEYMAP=$keyboardLayout
FONT=$consoleFont
EOF

# add wheel group to suders
cat <<EOF >/mnt/etc/sudoers.d/01_wheel
%wheel ALL=(ALL:ALL) ALL
EOF

# configure /etc/pacman.conf
cat <<EOF >/mnt/etc/pacman.conf
[options]
HoldPkg     = pacman glibc
Architecture = auto
NoExtract  = usr/share/fonts/noto/* !*NotoMono-* !*NotoSansDisplay-* !*NotoSansLinearB-* !*NotoSansMono-* !*NotoSansSymbols* !*NotoSerif-* !*NotoSerifDisplay-*
Color
ILoveCandy
CheckSpace
VerbosePkgLists
ParallelDownloads = 5
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

# pacman hooks
mkdir -p /mnt/etc/pacman.d/hooks

# nvidia
cat <<EOF >/mnt/etc/pacman.d/hooks/nvidia.hook
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia
Target=linux

[Action]
Description=Update NVIDIA module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case $trg in linux) exit 0; esac; done; /usr/bin/mkinitcpio -P'
EOF

# pacman cache cleanup
cat <<EOF >/mnt/etc/pacman.d/hooks/pacman-cache-cleanup.hook
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Cleaning up pacman cache...
When = PostTransaction
Exec = /bin/sh -c "/usr/bin/paccache -rk2; /usr/bin/paccache -ruk1"
EOF

# add kernel paramters
cat <<EOF >/mnt/etc/kernel/cmdline
quiet loglevel=3 systemd.show_status=auto rd.udev.loglevel=3 splash vt.global_cursor_default=0
nvidia_drm_modeset=1
lsm=landlock,lockdown,yama,integrity,apparmor,bpf
ro root=/dev/mapper/luksArch rootflags=subvol=@
rd.luks.options=timeout=180s,tries=3,discard
rd.luks.name=$luksArchUUID=luksArch
EOF
if [[ "$dataDrive" == "yes" ]]; then
	cat <<EOF >>/mnt/etc/kernel/cmdline
rd.luks.name=$luksDataUUID=luksData
EOF
fi

# configure mkinitcpio.conf
cat <<EOF >/mnt/etc/mkinitcpio.conf
MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)
BINARIES=(/usr/bin/btrfs)
FILES=()
HOOKS=(base systemd plymouth autodetect modconf kms keyboard keymap sd-vconsole block sd-encrypt filesystems)
EOF

#  configure linux.preset
cat <<EOF >/mnt/etc/mkinitcpio.d/linux.preset
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_microcode="/boot/intel-ucode.img"

PRESETS=('default' 'fallback')

default_uki="/efi/EFI/Linux/archlinux-linux.efi"

fallback_uki="/efi/EFI/Linux/archlinux-linux-fallback.efi"
fallback_options="-S autodetect"
EOF

#create another script to configure installed system
cat <<EOF >/mnt/setup.sh
#!/bin/bash

# change root passsword
echo "Set root password:"
passwd

# add user
useradd -mg wheel -s /bin/$defaultShell -c "$realName" $userName
echo "Set password for $realName:"
passwd $userName

# set timezone
ln -sf /usr/share/zoneinfo/$timeZone /etc/localtime
hwclock --systohc

# generate locales
locale-gen

# regenerate initrd to create UKIs
mkdir -p /efi/EFI/Linux
mkinitcpio -P

# delete unused kernel images
rm /boot/initramfs*

# install systemd-boot
bootctl install

# enable services
systemctl enable apparmor avahi-daemon bluetooth cronie cups fstrim.timer gdm NetworkManager sshd systemd-timesyncd ufw

# disable GDM's forcing X11 becaouse of nvidia
ln -s /dev/null /etc/udev/rules.d/61-gdm.rules

# install an AUR helper (paru)
sudo -u $userName git clone https://aur.archlinux.org/paru-bin.git /home/$userName/paru-bin
(cd /home/$userName/paru-bin && sudo -u $userName makepkg -si)
rm -rf /home/$userName/paru-bin

# restore dotfiles
sudo -u $userName git clone https://github.com/oguzhanygi/dotfiles.git /home/$userName/.dotfiles
(cd /home/$userName && ls -A | grep -xv ".dotfiles" | xargs rm -rf)
sudo -u $userName mkdir -p /home/$userName/{.config,.local/share}
(cd /home/$userName/.dotfiles && sudo -u $userName stow .)

# remove created script
rm /setup.sh

exit
EOF

chmod +x /mnt/setup.sh
arch-chroot /mnt /setup.sh
