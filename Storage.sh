#!/bin/bash
# Storage benchmark by James A. Chambers (https://jamesachambers.com/)
# Benchmarks your storage and anonymously submits result to jamesachambers.com
# Results and discussion available at https://jamesachambers.com/raspberry-pi-storage-benchmarks-2019-benchmarking-script/
#
# To run the benchmark use the following command:
# curl https://raw.githubusercontent.com/TheRemote/PiBenchmarks/master/Storage.sh | sudo bash

# Terminal colors
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
LIME_YELLOW=$(tput setaf 190)
POWDER_BLUE=$(tput setaf 153)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BRIGHT=$(tput bold)
NORMAL=$(tput sgr0)
BLINK=$(tput blink)
REVERSE=$(tput smso)
UNDERLINE=$(tput smul)

# Prints a line with color using terminal codes
Print_Style () {
    printf "%s\n" "${2}$1${NORMAL}"
}

# Get binary from string
Get_Binary () {
    local BinaryStr=$(printf "$1" | xxd -r -p | xxd -b | cut -d: -f 2 | sed 's/  .*//; s/ //g' | sed ':a;N;$!ba;s/\n//g')
    echo "$BinaryStr"
}

# Get specific bits from binary string
Get_Bits () {
    # $1 - Binary String
    # $2 - BitsStart
    # $3 - BitsCount
    # $4 - Structure size in bits
    local BitsStart=$(( $4 - $2 - $3 ))
    local BinaryStr=$(printf "$1")
    echo "${BinaryStr:BitsStart:$3}"
}

# Get decimal from binary
Get_Decimal () {
    echo "$((2#$1))"
}

# Get hex from binary
Get_Hex () {
    printf '%x\n' "$((2#$1))"
}

# Get string of text from binary
Get_Text() {
  for a in $1; do printf "%x\n" $((2#$a)); done | xxd -r -p
}

# Check if script is running as root first
if [[ "$(whoami)" != "root" ]]; then
  Print_Style "Benchmarks must be ran as root!  Example: sudo ./Storage.sh" $RED
  exit 1
fi

# Trim drives for more accurate benchmarking
sudo fstrim -av

# Initialize variables
Score=0
DDWriteResult=0
fio4kRandReadIOPS=0
fio4kRandWriteIOPS=0
IO4kRead=0
IO4kWrite=0
IO4kRandRead=0
IO4kRandWrite=0

# Change directory to rootfs
cd /

# Get host board information
HostArchitecture=$(uname -m)
HostOSInfo=$(cat /etc/os-release | sed 's/;/!/g')
HostOS=$(echo "$HostOSInfo" | grep "PRETTY_NAME" | cut -d= -f2 | xargs)

if [[ "$HostArchitecture" == *"x86"* || "$HostArchitecture" == *"amd64"* ]]; then
  # X86 or X86_64 system -- use dmidecode
  HostModel=$(dmidecode -t1 | grep 'Product Name' -m 1 | cut -d: -f2 | xargs)
  HostManufacturer=$(dmidecode -t1 | grep 'Manufacturer' -m 1 | cut -d: -f2 | xargs)
else
  # ARM system
  HostModel=$(tr -d '\0' </proc/device-tree/model)
  if [[ "$HostModel" == *"Raspberry Pi"* ]]; then
    HostManufacturer="Raspberry Pi Foundation"
  elif [[ "$HostModel" == *"Tinker Board"* ]]; then
    HostManufacturer="ASUSTeK"
  else
    HostManufacturer="N/A"
  fi
fi
Print_Style "Board information: Manufacturer: $HostManufacturer - Model: $HostModel - Architecture: $HostArchitecture - OS: $HostOS" $YELLOW

# Install required components
Print_Style "Fetching required components ..." $YELLOW

# Test for apt first (all Debian based distros)
if [[ -n "`which apt`" ]]; then
  # Check if we are on a Raspberry Pi
  if [[ $HostModel == *"Raspberry Pi"* ]]; then
    # Check if we are running Ubuntu
    if [[ $HostOS == *"Ubuntu"* ]]; then
      if [ ! -n "`which vcgencmd`" ]; then
        # Add Raspberry Pi repository to Ubuntu sources
        add-apt-repository ppa:ubuntu-raspi2/ppa -y
      fi
    fi
    apt-get update
    # Check for vcgencmd (measures clock speeds)
    if [ ! -n "`which vcgencmd`" ]; then
      apt-get install libraspberrypi-bin -y
    fi
  else
    apt-get update
  fi

  apt-get install hdparm -y
  apt-get install lshw -y
  apt-get install bc -y
  apt-get install fio -y
  apt-get install curl -y
  apt-get install iozone3 -y
  apt-get install libcurl4 -y

  DpkgArch=$(dpkg --print-architecture)
  if [ ! -n "`which iozone`" ]; then
    # Attempt to install iozone from package
    if [[ "$HostArchitecture" == *"armv7"* || "$HostArchitecture" == *"armhf"* ]]; then
      curl -o iozone3.deb http://ftp.us.debian.org/debian/pool/non-free/i/iozone3/iozone3_429-3+b1_armhf.deb
      dpkg --install iozone3.deb
      rm iozone3.deb
    elif [[ "$DpkgArch" == *"arm64"* || "$HostArchitecture" == *"aarch64"* || "$HostArchitecture" == *"arm64"* ]]; then
      curl -o iozone3.deb http://ftp.us.debian.org/debian/pool/non-free/i/iozone3/iozone3_429-3+b1_arm64.deb
      dpkg --install iozone3.deb
      rm iozone3.deb
    elif [[ "$DpkgArch" == *"armel"* ]]; then
      curl -o iozone3.deb http://ftp.us.debian.org/debian/pool/non-free/i/iozone3/iozone3_429-3+b1_armel.deb
      dpkg --install iozone3.deb
      rm iozone3.deb
    elif [[ "$HostArchitecture" == *"x86_64"* || "$HostArchitecture" == *"amd64"* ]]; then
      curl -o iozone3.deb http://ftp.us.debian.org/debian/pool/non-free/i/iozone3/iozone3_429-3+b1_amd64.deb
      dpkg --install iozone3.deb
      rm iozone3.deb
    elif [[ "$HostArchitecture" == *"i386"* ]]; then
      curl -o iozone3.deb http://ftp.us.debian.org/debian/pool/non-free/i/iozone3/iozone3_429-3+b1_i386.deb
      dpkg --install iozone3.deb
      rm iozone3.deb
    fi
  fi

  # Test if we were able to install iozone3 from a package and don't install build-essential if we were
  if [ ! -n "`which iozone`" ]; then
    apt-get install build-essential
  fi
# Next test for Pac-Man (Arch Linux)
elif [ -n "`which pacman`" ]; then
  pacman -Syy
  pacman --needed --noconfirm -S vim
  pacman --needed --noconfirm -S hdparm
  pacman --needed --noconfirm -S base-devel
  pacman --needed --noconfirm -S fio
  pacman --needed --noconfirm -S bc
  pacman --needed --noconfirm -S lshw
  pacman --needed --noconfirm -S iozone3

  # Check if running on a Raspberry Pi
  if [[ $HostModel == *"Raspberry Pi"* ]]; then
    if [ ! -n "`which vcgencmd`" ]; then
      # Create soft link for vcgencmd
      ln -s /opt/vc/bin/vcgencmd /usr/local/bin
    fi
  fi
else
  Print_Style "No package manager found!" $RED
fi

# Get clock speeds
if [[ "$HostArchitecture" == *"x86"* || "$HostArchitecture" == *"amd64"* ]]; then
  # X86 or X86_64 system -- use dmidecode
  HostConfig=$(dmidecode)
  HostCPUClock=$(dmidecode -t4 | grep -m 1 'Max Speed' | cut -d: -f2 | cut -d' ' -f2 | xargs)
  HostCoreClock="N/A"
  HostRAMClock=$(dmidecode -t17 | grep -m 1 "Speed: " | cut -d' ' -f2 | xargs)
  HostConfig+=$(echo "/n")
  HostConfig+=$(lshw)
else
  # Check for vcgencmd
  if [ -n "`which vcgencmd`" ]; then
    HostConfig=$(vcgencmd get_config int)
    HostCPUClock=$(echo "$HostConfig" | grep -m 1 arm_freq= | cut -d= -f2 | xargs)
    if [ ! -n "$HostCPUClock" ]; then
      HostCPUClock=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq | xargs)
      HostCPUClock=$(echo "scale=0; $HostCPUClock / 1000" | bc)
    fi
    HostCoreClock=$(echo "$HostConfig" | grep -m 1 core_freq= | cut -d= -f2 | xargs)
    if [ ! -n "$HostCoreClock" ]; then
      HostCoreClock=$(echo "$HostConfig" | grep -m 1 gpu_freq= | cut -d= -f2 | xargs)
    fi
    if [ ! -n "$HostCoreClock" ]; then
      HostCoreClock=$(vcgencmd measure_clock core | cut -d= -f2 | xargs)
      HostCoreClock=$(echo "scale=0; $HostCoreClock / 1000000" | bc)
    fi
    HostRAMClock=$(echo "$HostConfig" | grep -m 1 sdram_freq= | cut -d= -f2 | xargs)
    if [ ! -n "$HostRAMClock" ]; then
      HostRAMClock="N/A"
    fi
    HostConfig+=$(echo "/n")
    HostConfig+=$(lshw)
  else
    HostConfig+=$(echo "/n")
    HostConfig+=$(lshw)
    HostCPUClock=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)
    HostCPUClock=$(echo "scale=0; $HostCPUClock / 1000" | bc)
    HostCoreClock="N/A"
    HostRAMClock="N/A"
  fi
fi
Print_Style "Clock speeds: CPU: $HostCPUClock - Core: $HostCoreClock - RAM: $HostRAMClock" $YELLOW

# Retrieve and build iozone
if [ ! -n "`which iozone`" ]; then
  if [ ! -f iozone/src/current/iozone ]; then
    Print_Style "Building iozone ..." $YELLOW
    DownloadURL=$(curl -N iozone.org | grep -m 1 -o 'src/current/iozone3_[^"]*')
    curl -o iozone.tar "http://www.iozone.org/$DownloadURL"
    tar -xf iozone.tar
    rm iozone.tar
    mv iozone3_* iozone
    cd iozone/src/current
    make --quiet linux-arm
    cd ../../..
  fi
fi

# Run sync to make sure all changes have been written to disk
sync

# --Get system boot drive information--
# Find from mountpoint first
BootDrive=$(findmnt -n -o SOURCE /)
if [ ! -n "$BootDrive" ]; then
  RDEV=$(mountpoint -d /)

  for file in /dev/* ; do
    CURRENT_DEVICE=$(printf "%d:%d" $(stat --printf="0x%t 0x%T" "$file"))
    if [ $CURRENT_DEVICE = $RDEV ]; then
      BootDrive=$file
      break
    fi
  done
fi
# Fall back to finding from lsblk
if [ ! -n "$BootDrive" ]; then
  BootDrive=$(lsblk -l | grep -v "0 part /boot" | grep -m 1 "0 part /" | awk 'NR==1{ print $1 }')
  if [ -n "$BootDrive" ]; then
    BootDrive="/dev/"$BootDrive
  fi
fi
# Fall back to finding from df
if [ ! -n "$BootDrive" ]; then
  BootDrive=$(df -H | grep -m 1 boot | awk 'NR==1{ print $1 }')
fi

# Detect BootDrive suffix
BootDriveSuffix=$(echo "$BootDrive" | cut -d"/" -f3)
if [ ! -n "$BootDriveSuffix" ]; then
  BootDriveSuffix=$(echo "$BootDrive" | cut -d"/" -f2)
fi
if [ ! -n "$BootDriveSuffix" ]; then
  BootDriveSuffix=$(echo "$BootDrive" | cut -d"/" -f1)
fi
if [ ! -n "$BootDriveSuffix" ]; then
  BootDriveSuffix="$BootDrive"
fi

Print_Style "System rootfs drive (/) has been detected as $BootDrive ($BootDriveSuffix)" $YELLOW

Test_udevadm=$(udevadm info -a -n $BootDrive | sed 's/;/!/g' | sed '/^[[:space:]]*$/d')
Test_lsblk=$(lsblk -l -o NAME,FSTYPE,LABEL,MOUNTPOINT,SIZE,MODEL)
Test_lshw=$(lshw -class disk -class storage)
Test_findmnt=$(findmnt -n)
Test_diskbyid=$(ls /dev/disk/by-id)
Test_lsusb=$(lsusb 2>&1)
Test_lspci=$(lspci 2>&1)
Test_df=$(df -h 2>&1)
Test_cpuinfo=$(cat /proc/cpuinfo 2>&1)
Capacity=$(lsblk -l | grep $BootDriveSuffix -m 1 | awk 'NR==1{ print $4 }' | sed 's/,/./g')

# Check for Micro SD / MMC card
if [[ "$BootDrive" == *"mmcblk"* ]]; then

  # Determine if MMC or Micro SD
  RootDrive=$(echo "$BootDrive" | cut -dp -f1 | cut -d/ -f3)
  MMCType=$(cat /sys/block/$RootDrive/device/type)

  # Get card information
  Manufacturer=$(echo "$Test_udevadm" | grep -m 1 "manfid" | cut -d= -f3 | cut -d\" -f2 | xargs)
  if [ ! -n "$Manufacturer" ]; then
    Manufacturer=$(cat /sys/block/$RootDrive/device/manfid)
    Product=$(cat /sys/block/$RootDrive/device/type)
    Firmware=$(cat /sys/block/$RootDrive/device/fwrev)
    DateManufactured=$(cat /sys/block/$RootDrive/device/date)
    Model=$(cat /sys/block/$RootDrive/device/name)
    Version=$(cat /sys/block/$RootDrive/device/hwrev)
    Vendor=$(cat /sys/block/$RootDrive/device/oemid)
    SSR=$(cat /sys/block/$RootDrive/device/ssr)
    SCR=$(cat /sys/block/$RootDrive/device/scr)
    CID=$(cat /sys/block/$RootDrive/device/cid)
    CSD=$(cat /sys/block/$RootDrive/device/csd)
    OCR=$(cat /sys/block/$RootDrive/device/ocr)
  else
    Product=$(echo "$Test_udevadm" | grep -m 1 "{type}" | cut -d= -f3 | cut -d\" -f2 | xargs)
    Firmware=$(echo "$Test_udevadm" | grep -m 1 "{fwrev}" | cut -d= -f3 | cut -d\" -f2 | xargs)
    DateManufactured=$(echo "$Test_udevadm" | grep -m 1 "date" | cut -d= -f3 | cut -d\" -f2 | xargs)
    Model=$(echo "$Test_udevadm" | grep -m 1 "{name}" | cut -d= -f3 | cut -d\" -f2 | xargs)
    Version=$(echo "$Test_udevadm" | grep -m 1 "{hwrev}" | cut -d= -f3 | cut -d\" -f2 | xargs)
    Vendor=$(echo "$Test_udevadm" | grep -m 1 "oemid" | cut -d= -f3 | cut -d\" -f2 | xargs | xxd -r)
    SSR=$(echo "$Test_udevadm" | grep -m 1 "{ssr}" | cut -d= -f3 | cut -d\" -f2 | xargs)
    SCR=$(echo "$Test_udevadm" | grep -m 1 "{scr}" | cut -d= -f3 | cut -d\" -f2 | xargs)
    CID=$(echo "$Test_udevadm" | grep -m 1 "{cid}" | cut -d= -f3 | cut -d\" -f2 | xargs)
    CSD=$(echo "$Test_udevadm" | grep -m 1 "{csd}" | cut -d= -f3 | cut -d\" -f2 | xargs)
    OCR=$(echo "$Test_udevadm" | grep -m 1 "{ocr}" | cut -d= -f3 | cut -d\" -f2 | xargs)
  fi

  if [[ "$MMCType" == *"SD"* ]]; then
    # MicroSD hardware identification
    HostSDClock=$(grep "actual clock" /sys/kernel/debug/mmc0/ios 2>/dev/null | awk '{printf("%0.1f", $3/1000000)}')

    # Parse SSR status register
    SSRBinary=$(Get_Binary $SSR)
    SSRAppClass=$(Get_Decimal $(Get_Bits $SSRBinary 336 4 512))
    SSRVideoClass=$(Get_Decimal $(Get_Bits $SSRBinary 384 8 512))
    SSRUHSClass=$(Get_Decimal $(Get_Bits $SSRBinary 396 4 512))
    SSRSpeedClass=$(Get_Decimal $(Get_Bits $SSRBinary 440 8 512))

    # Parse CID status register
    CIDBinary=$(Get_Binary $CID)
    CIDMID=$(Get_Hex $(Get_Bits $CIDBinary 120 8 128))
    CIDMDateM=$(Get_Decimal $(Get_Bits $CIDBinary 8 4 128))
    CIDMDateY=$(Get_Decimal $(Get_Bits $CIDBinary 12 8 128))
    CIDMDate="$CIDMDateM/20$CIDMDateY"
    CIDOID=$(Get_Text $(Get_Bits $CIDBinary 104 16 128))
    CIDPNM=$(Get_Text $(Get_Bits $CIDBinary 64 40 128))
    CIDPRVHW=$(Get_Hex $(Get_Bits $CIDBinary 60 4 128))
    CIDPRVFW=$(Get_Hex $(Get_Bits $CIDBinary 56 4 128))
    CIDPRV="$CIDPRVHW.$CIDPRVFW"

    # Parse CSD status register
    CSDBinary=$(Get_Binary $CSD)
    CSDMID=$(Get_Hex $(Get_Bits $CSDBinary 120 8 128))
    Print_Style "Card CSD status register: MID: $CIDMID OID: $CIDOID PNM: $CIDPNM PRV: $CIDPRV MDATE: $CIDMDate" $YELLOW

    # Parse SCR status register
    SCRBinary=$(Get_Binary $SCR)
    SCRSDSpec=$(Get_Decimal $(Get_Bits $SCRBinary 56 4 64))
    SCRSDSpec3=$(Get_Decimal $(Get_Bits $SCRBinary 47 1 64))
    SCRSDSpec4=$(Get_Decimal $(Get_Bits $SCRBinary 42 1 64))
    SCRSDSpecX=$(Get_Decimal $(Get_Bits $SCRBinary 38 4 64))

    # Get SD physical layer specification version
    if [ "$SCRSDSpecX" == "2" ]; then # 6.XX
      SCRSDSpecVer="6"
    elif [ "$SCRSDSpecX" == "1" ]; then # 5.XX
      SCRSDSpecVer="5"
    elif [ "$SCRSDSpec4" == "1" ]; then # 4.XX
      SCRSDSpecVer="4"
    elif [ "$SCRSDSpec3" == "1" ]; then # 3.XX
      SCRSDSpecVer="3"
    elif [ "$SCRSDSpec" == "2" ]; then # 2.00
      SCRSDSpecVer="2"
    elif [ "$SCRSDSpec" == "1" ]; then # 1.10
      SCRSDSpecVer="1.1"
    elif [ "$SCRSDSpec" == "0" ]; then # 1.0
      SCRSDSpecVer="1"
    fi
    Print_Style "Card SCR status register: SD Physical Version Specification: $SCRSDSpecVer" $YELLOW

    # Check for known manufacturers
    case "$Manufacturer" in
      0x000001)
        Manufacturer="Panasonic"
        ;;
      0x000002)
        Manufacturer="Toshiba"
        ;;
      0x000003)
        Manufacturer="SanDisk"
        ;;
      0x000008)
        Manufacturer="Silicon Power"
        ;;
      0x000018)
        Manufacturer="Infineon"
        ;;
      0x00001b)
        Manufacturer="Samsung"
        ;;
      0x00001d)
        Manufacturer="Corsair/AData"
        ;;
      0x000027)
        Manufacturer="Phison"
        ;;
      0x000028)
        Manufacturer="Lexar"
        ;;
      0x000030)
        Manufacturer="SanDisk"
        ;;
      0x000031)
        Manufacturer="Silicon Power"
        ;;
      0x000033)
        Manufacturer="STMicroelectronics"
        ;;
      0x000041)
        Manufacturer="Kingston"
        ;;
      0x000045)
        Manufacturer="Team Group"
        ;;
      0x00006f)
        Manufacturer="STMicroelectronics"
        ;;
      0x000073)
        Manufacturer="Hama"
        ;;
      0x000074)
        Manufacturer="Transcend"
        ;;
      0x000076)
        Manufacturer="Patriot"
        ;;
      0x000082)
        Manufacturer="Sony"
        ;;
      0x000092)
        Manufacturer="Sony"
        ;;
      0x00009c)
        Manufacturer="Sony"
        ;;
      0x00009e)
        Manufacturer="Lexar"
        ;;
      0x00009f)
        Manufacturer="Texas Instruments"
        ;;
      *)
        ;;
    esac

    # Identify card classifications
    Class=""
    if [[ $SSRAppClass > 0 ]]; then
      Class="A$SSRAppClass"
    fi
    case "$SSRSpeedClass" in
      0)
        Class="$Class Class 0"
        ;;
      1)
        Class="$Class Class 2"
        ;;
      2)
        Class="$Class Class 4"
        ;;
      3)
        Class="$Class Class 6"
        ;;
      4)
        Class="$Class Class 10"
        ;;
      *)
        Class="$Class ?"
        ;;
    esac
    if [[ $SSRVideoClass > 0 ]]; then
      Class="$Class V$SSRVideoClass"
    fi
    if [[ $SSRUHSClass > 0 ]]; then
      Class="$Class U$SSRUHSClass"
    fi
    Class=$(echo "$Class" | xargs)
    Print_Style "MicroSD information: Clock Speed: $HostSDClock - Manufacturer: $Manufacturer - Model: $Model - Vendor: $Vendor - Product: $Product - HW Version: $Version - FW Version: $Firmware - Date Manufactured: $DateManufactured" $YELLOW
    Print_Style "Class: $Class" $YELLOW
  elif [[ "$MMCType" == *"MMC"* ]]; then
    # Attempt to identify MMC device

    HostSDClock="N/A"

    case "$Manufacturer" in
      0x000000)
        Manufacturer="SanDisk"
        ;;
      0x000002)
        Manufacturer="Kingston/SanDisk"
        ;;
      0x000003)
        Manufacturer="Toshiba"
        ;;
      0x000011)
        Manufacturer="Toshiba"
        ;;
      0x000015)
        Manufacturer="Samsung/SanDisk/LG"
        ;;
      0x000037)
        Manufacturer="KingMax"
        ;;
      0x000044)
        Manufacturer="SanDisk"
        ;;
      0x000090)
        Manufacturer="SK Hynix"
        ;;
      0x00002c)
        Manufacturer="Kingston"
        ;;
      0x000070)
        Manufacturer="Kingston"
        ;;
      *)
        ;;
    esac

    # Get capacity
    DriveCapacity=$(cat /sys/block/$RootDrive/device/emmc_total_size)
    if [ -n "$DriveCapacity" ]; then
      if [ "$DriveCapacity" -eq "$DriveCapacity" ] 2>/dev/null
      then
          Capacity=$DriveCapacity"G"
      fi
    fi

    # Parse CSD register
    CSDBinary=$(Get_Binary $CSD)
    CSDSpecVersion=$(Get_Decimal $(Get_Bits $CSDBinary 122 4 128))

    # Parse CID register
    CIDBinary=$(Get_Binary $CID)
    CIDCBX=$(Get_Decimal $(Get_Bits $CIDBinary 112 1 128))

    # Check CBX value to see if MMC is embedded or removable
    case "$CIDCBX" in
      0)
        Product="MMC"
        Class="MMC v$CSDSpecVersion (Card)"
        ;;
      1)
        Product="eMMC"
        Class="eMMC v$CSDSpecVersion (Embedded)"
        ;;
      10)
        Product="MMC"
        Class="MMC v$CSDSpecVersion (POP)"
        ;;
      *)
        ;;
    esac

  Print_Style "MMC Type: $Class - Manufacturer: $Manufacturer - Model: $Model - Size: $Capacity" $YELLOW

  fi
else
  # Not a MicroSD card
  HDParmInfo=$(hdparm -Ii "$BootDrive" 2>/dev/null | sed '/^[[:space:]]*$/d')
  if [ ! -n "$HDParmInfo" ]; then
    HDParmInfo=$(hdparm -I "$BootDrive" 2>/dev/null | sed '/^[[:space:]]*$/d')
  fi
  Test_hdparm=$(echo "$HDParmInfo")

  HostSDClock="N/A"
  DateManufactured="N/A"

  # Attempt to identify drive model
  Model=$(echo "$Test_udevadm" | grep -m 1 "{model}" | cut -d= -f3 | cut -d\" -f2 | xargs)
  Vendor=$(echo "$Test_udevadm" | grep -m 1 "{vendor}" | cut -d= -f3 | cut -d\" -f2 | xargs)
  Manufacturer=$(echo "$Test_udevadm" | grep -m 1 "{manufacturer}" | cut -d= -f3 | cut -d\" -f2 | xargs)

  case "$Model" in
    "ASM105x")
      # This is the ASMedia USB TO 2.5" SATA adapter chipset
      Product="SSD"
      FormFactor="2.5"
      Class="SSD (2.5\" SATA)"
      Adapter="ASMedia ASM105x"
      Model=
      Manufacturer=
      ;;
    "SABRENT")
      # This is the Sabrent USB TO 2.5" SATA adapter chipset
      Product="SSD"
      FormFactor="2.5"
      Class="SSD (2.5\" SATA)"
      Adapter="Sabrent"
      Model=
      Manufacturer=
      ;;
    "2105")
      # ASMedia adapter 2105
      Product="SSD"
      FormFactor="2.5"
      Class="SSD (2.5\" SATA)"
      Adapter="ASMedia 2105"
      Model=
      Manufacturer=
      ;;
    "2115")
      # ASMedia adapter 2115
      Product="SSD"
      FormFactor="2.5"
      Class="SSD (2.5\" SATA)"
      Adapter="ASMedia 2115"
      Model=
      Manufacturer=
      ;;
    "USB 3.0 Device")
      # ASMedia USB to SATA adapter (generic)
      Product="SSD"
      FormFactor="2.5"
      Class="SSD (2.5\" SATA)"
      Adapter="ASMedia 3.0 Generic"
      Model=
      Manufacturer=
      ;;
    "AQ3120")
      # Geekworm x855
      Product="SSD"
      FormFactor="2.5"
      Class="SSD (mSATA)"
      Adapter="Geekworm x855"
      Model=
      Manufacturer=
      ;;
    *)
      ;;
  esac
  if [ ! -n "$Model" ]; then
    Model=$(echo "$Test_hdparm" | grep -m 1 "Model Number:" | awk 'NR==1{ print $3 }' | grep "_" | cut -d_ -f2 | xargs)
  fi
  if [ ! -n "$Model" ]; then
    Model=$(echo "$Test_hdparm" | grep -m 1 "Model Number:" | awk 'NR==1{ print $3 }' | grep " " | cut -d" " -f2 | xargs)
  fi
  if [ ! -n "$Model" ]; then
    Model=$(echo "$Test_hdparm" | grep -m 1 "Model Number:" | awk 'NR==1{ print $3$4$5$6$7$8$9 }' | xargs)
  fi
  if [ ! -n "$Model" ]; then
    Model=$(echo "$Test_hdparm" | grep -m 1 "Model Number:" | awk 'NR==1{ print $3$4$5$6$7$8$9 }' | xargs)
  fi

  # Attempt to identify drive manufacturer
  if [ ! -n "$Manufacturer" ]; then
    Manufacturer=$(echo "$Test_hdparm" | grep -m 1 "Model Number:" | grep "_" | awk 'NR==1{ print $3 }' | cut -d_ -f1 | xargs)
  fi
  if [ ! -n "$Manufacturer" ]; then
    Manufacturer=$(echo "$Test_hdparm" | grep -m 1 "Model Number:" | grep " " | awk 'NR==1{ print $3 }' | cut -d" " -f1 | xargs)
  fi
  if [ ! -n "$Manufacturer" ]; then
    Manufacturer=$(echo "$Test_hdparm" | grep -m 1 "Model Number:" | awk 'NR==1{ print $3 }' | xargs)
  fi

  # Identify drive type, form factor
  if [ ! -n "$FormFactor" ]; then
    FormFactor=$(echo "$Test_hdparm" | grep -m 1 "Form Factor:" | cut -d: -f2 | cut -d' ' -f1 | xargs)
    if [ ! -n "$FormFactor" ]; then
      FormFactor="2.5"
    fi
  fi

  # Attempt to get drive capacity
  DriveCapacity=$(echo "$Test_hdparm" | grep -m 1 "device size with M = 1000*" | cut -d\( -f2 | cut -d' ' -f1 | xargs)
  if [ -n "$DriveCapacity" ]; then
    if [ "$DriveCapacity" -eq "$DriveCapacity" ] 2>/dev/null
    then
        Capacity=$DriveCapacity"G"
    fi
  fi

  # Attempt to identify drive type
  DriveType=$(echo "$Test_hdparm" | grep -m 1 "Nominal Media Rotation Rate:" | cut -d: -f2 | xargs)
  case "$DriveType" in
    5400 | 7200 | 10000)
      Product="HDD"
      Class="HDD ($FormFactor\" SATA)"
      ;;
    "Solid State Device")
      Product="SSD"
      Class="SSD ($FormFactor\" SATA)"
      ;;
    *)
      Product="USB Flash"
      Class="USB Flash Drive"
      ;;
  esac

  # Identify hardware and firmware versions of drive
  Version=$(echo "$Test_udevadm" | grep -m 1 "{version}" | cut -d= -f3 | cut -d\" -f2 | xargs)
  Firmware=$(echo "$Test_hdparm" | grep -m 1 "Firmware Revision:" | awk 'NR==1{ print $3$4$5$6 }')
  if [ -n "$Firmware" ]; then
    Firmware=$(echo "$Test_hdparm" | grep -m 1 "Firmware Revision:" | awk 'NR==1{ print $3$4$5$6 }')
  fi


  Print_Style "Drive information: Manufacturer: $Manufacturer - Model: $Model - Product: $Product" $YELLOW
fi

# Run HDParm tests
Print_Style "Running HDParm tests ..." $YELLOW
HDParm=$(hdparm -Tt --direct $BootDrive 2>/dev/null | sed '/^[[:space:]]*$/d')
if [ ! -n "$HDParm" ]; then
  HDParm=$(hdparm -Tt $BootDrive 2>/dev/null | sed '/^[[:space:]]*$/d')
fi
if [ ! -n "$HDParm" ]; then
  HDParm=$(hdparm -T --direct $BootDrive 2>/dev/null | sed '/^[[:space:]]*$/d')
fi
if [ ! -n "$HDParm" ]; then
  HDParm=$(hdparm -T $BootDrive 2>/dev/null | sed '/^[[:space:]]*$/d')
fi
if [ ! -n "$HDParm" ]; then
  HDParm=$(hdparm -t --direct $BootDrive 2>/dev/null | sed '/^[[:space:]]*$/d')
fi
if [ ! -n "$HDParm" ]; then
  HDParm=$(hdparm -t $BootDrive 2>/dev/null | sed '/^[[:space:]]*$/d')
fi
Print_Style "$HDParm" $NORMAL
HDParmDisk=$(echo "$HDParm" | grep "disk reads:" | awk 'NR==1{ print $11 }')
HDParmCached=$(echo "$HDParm" | grep "cached reads:" | awk 'NR==1{ print $11 }')
Print_Style "HDParm: $HDParmDisk MB/s - HDParmCached: $HDParmCached MB/s" $YELLOW

# Run DD tests
Print_Style "Running dd tests ..." $YELLOW
DDWrite=$(dd if=/dev/zero of=test bs=4k count=80k conv=fsync 2>&1 | sed '/^[[:space:]]*$/d')
DDWriteResult=$(echo "$DDWrite" | tail -n 1 | awk 'NR==1{ print $(NF-1) }' | sed 's/,/./g')

echo "$DDWrite"
Print_Style "DD Write Speed: $DDWriteResult MB/s" $YELLOW
rm -f test

# Run fio tests
Print_Style "Running fio write test ..." $YELLOW
fio4kRandWrite=$(fio --minimal --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=100M --readwrite=randwrite | sed 's/;/!/g')
fio4kRandWriteIOPS=$(echo "$fio4kRandWrite" | awk -F '!' '{print $49}')
fio4kRandWriteSpeed=$(echo "$fio4kRandWrite" | awk -F '!' '{print $48}')
rm -f test
Print_Style "Running fio read test ..." $YELLOW
fio4kRandRead=$(fio --minimal --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=200M --readwrite=randread | sed 's/;/!/g')
fio4kRandReadIOPS=$(echo "$fio4kRandRead" | awk -F '!' '{print $8}')
fio4kRandReadSpeed=$(echo "$fio4kRandRead" | awk -F '!' '{print $7}')
Print_Style "FIO results - 4k RandWrite: $fio4kRandWriteIOPS IOPS ($fio4kRandWriteSpeed KB/s) - 4k RandRead: $fio4kRandReadIOPS IOPS ($fio4kRandReadSpeed KB/s)" $YELLOW
rm -f test

# Run iozone tests
Print_Style "Running iozone test ..." $YELLOW
if [ ! -n "`which iozone`" ]; then
  IOZone=$(iozone/src/current/./iozone -a -e -I -i 0 -i 1 -i 2 -s 80M -r 4k)
else
  IOZone=$(iozone -a -e -I -i 0 -i 1 -i 2 -s 80M -r 4k)
fi
IO4kRandRead=$(echo "$IOZone" | tail -n 3 | awk 'NR==1{ print $7 }')
IO4kRandWrite=$(echo "$IOZone" | tail -n 3 | awk 'NR==1{ print $8 }')
IO4kRead=$(echo "$IOZone" | tail -n 3 | awk 'NR==1{ print $5 }')
IO4kWrite=$(echo "$IOZone" | tail -n 3 | awk 'NR==1{ print $3 }')
echo "$IOZone"
IOZone=$(echo "$IOZone" | sed '/^[[:space:]]*$/d')
Print_Style "RandRead: $IO4kRandRead - RandWrite: $IO4kRandWrite - Read: $IO4kRead - Write: $IO4kWrite" $YELLOW

# Get brand information
Print_Style "Enter a description of your storage (SSD vs SD card, made by SanDisk, anything relevant:"
read -p 'Description: ' Brand < /dev/tty
Print_Style "(Optional) Enter alias to use on benchmark results.  Leave blank for completely anonymous:"
read -p 'Alias (leave blank for Anonymous): ' UserAlias < /dev/tty
if [[ ! "$UserAlias" ]]; then UserAlias="Anonymous"; fi

# Submit results
curl --form "form_tools_form_id=1" --form "DDTest=$DDWrite" --form "DDWriteSpeed=$DDWriteResult" --form "HDParmDisk=$HDParmDisk" --form "HDParmCached=$HDParmCached" --form "HDParm=$HDParm" --form "fio4kRandRead=$fio4kRandRead" --form "fio4kRandWrite=$fio4kRandWrite" --form "fio4kRandWriteIOPS=$fio4kRandWriteIOPS" --form "fio4kRandReadIOPS=$fio4kRandReadIOPS" --form "fio4kRandWriteSpeed=$fio4kRandWriteSpeed" --form "fio4kRandReadSpeed=$fio4kRandReadSpeed" --form "IOZone=$IOZone" --form "IO4kRandRead=$IO4kRandRead" --form "IO4kRandWrite=$IO4kRandWrite" --form "IO4kRead=$IO4kRead" --form "IO4kWrite=$IO4kWrite" --form "Drive=$BootDrive" --form "Test_hdparm=$Test_hdparm" --form "Test_lsblk=$Test_lsblk" --form "Test_findmnt=$Test_findmnt" --form "Test_lsusb=$Test_lsusb" --form "Test_lshw=$Test_lshw" --form "Test_lspci=$Test_lspci" --form "Test_diskbyid=$Test_diskbyid" --form "Test_df=$Test_df" --form "Test_cpuinfo=$Test_cpuinfo" --form "Test_udevadm=$Test_udevadm" --form "Model=$Model" --form "Vendor=$Vendor" --form "Capacity=$Capacity" --form "Manufacturer=$Manufacturer" --form "Product=$Product" --form "DateManufactured=$DateManufactured" --form "Note=$Brand" --form "Class=$Class" --form "OCR=$OCR" --form "SSR=$SSR" --form "SCR=$SCR" --form "CID=$CID" --form "CSD=$CSD" --form "UserAlias=$UserAlias" --form "HostModel=$HostModel" --form "HostSDClock=$HostSDClock" --form "HostConfig=$HostConfig" --form "HostCPUClock=$HostCPUClock" --form "HostCoreClock=$HostCoreClock" --form "HostRAMClock=$HostRAMClock" --form "HostArchitecture=$HostArchitecture" --form "HostOS=$HostOS" --form "HostOSInfo=$HostOSInfo" --form "HostManufacturer=$HostManufacturer" --form "Adapter=$Adapter" https://jamesachambers.com/formtools/process.php

# Calculate score
Score=$(echo "scale=2; $DDWriteResult * 1024" | bc)
ScratchPad=$(echo "scale=2; $fio4kRandReadIOPS * 4" | bc)
Score=$(echo "scale=2; $Score + $ScratchPad" | bc)
ScratchPad=$(echo "scale=2; $fio4kRandWriteIOPS * 10" | bc)
Score=$(echo "scale=2; $Score + $ScratchPad" | bc)
Score=$(echo "scale=2; $Score + $IO4kRead" | bc)
Score=$(echo "scale=2; $Score + $IO4kWrite" | bc)
ScratchPad=$(echo "scale=2; $IO4kRandRead * 4" | bc)
Score=$(echo "scale=2; $Score + $ScratchPad" | bc)
ScratchPad=$(echo "scale=2; $IO4kRandWrite * 10" | bc)
Score=$(echo "scale=2; $Score + $ScratchPad" | bc)
Score=$(echo "scale=0; $Score / 100" | bc )

# Display results
printf "\n$BRIGHT$UNDERLINE%-25s %-25s %-25s\n" "     Category" "     Test" "     Result     "$NORMAL$CYAN
printf "%-25s %-25s %-25s\n" "HDParm" "Disk Read" "$HDParmDisk MB/s"
printf "%-25s %-25s %-25s\n" "HDParm" "Cached Disk Read" "$HDParmCached MB/s"
printf "%-25s %-25s %-25s\n" "DD" "Disk Write" "$DDWriteResult MB/s"
printf "%-25s %-25s %-25s\n" "FIO" "4k random read" "$fio4kRandReadIOPS IOPS ($fio4kRandReadSpeed KB/s)"
printf "%-25s %-25s %-25s\n" "FIO" "4k random write" "$fio4kRandWriteIOPS IOPS ($fio4kRandWriteSpeed KB/s)"
printf "%-25s %-25s %-25s\n" "IOZone" "4k read" "$IO4kRead KB/s"
printf "%-25s %-25s %-25s\n" "IOZone" "4k write" "$IO4kWrite KB/s"
printf "%-25s %-25s %-25s\n" "IOZone" "4k random read" "$IO4kRandRead KB/s"
printf "%-25s %-25s %-25s\n" "IOZone" "4k random write" "$IO4kRandWrite KB/s"
printf "\n$BRIGHT$MAGENTA$UNDERLINE%-25s %-25s %-25s\n" " " "Score: $Score" " "
echo ""
echo "Compare with previous benchmark results at:"
echo "https://www.jamesachambers.com/raspberry-pi-storage-benchmarks/ $NORMAL"

# Return to home directory
cd ~