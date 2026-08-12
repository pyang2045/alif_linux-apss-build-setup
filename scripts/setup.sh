#!/bin/bash

export -n BBPATH
if [ -n "$BASH_SOURCE" ]; then
   THIS_SCRIPT=$BASH_SOURCE
elif [ -n "$ZSH_NAME" ]; then
   THIS_SCRIPT=$0
else
   THIS_SCRIPT="$(pwd)/setup.sh"
fi
if [ -z "$ZSH_NAME" ] && [ "$0" = "$THIS_SCRIPT" ]; then
   EXIT="exit"
else
   EXIT="return"
fi
export PATH=$PATH
THIS_SCRIPT=$(readlink -f $THIS_SCRIPT)
TOPDIR=$(dirname $THIS_SCRIPT)/../

if [ -e ~/.windows_docker -a "x$1" = "x" ] ; then
   BUILD_DIR=~/build
   echo "$BUILD_DIR used as project." 2>&1
   echo "To change run source ${THIS_SCRIPT} <builddir>" 2>&1
elif [ -e ~/.windows_docker -a "x$1" != "x" ] ; then
   BUILD_DIR=~/$(basename $1)
   echo "$BUILD_DIR used as project." 2>&1
   echo "To change run source ${THIS_SCRIPT} <builddir>" 2>&1
elif [ "x$1" = "x" ] ; then
   BUILD_DIR=$TOPDIR/build
   echo "$BUILD_DIR used as project." 2>&1
   echo "To change run source ${THIS_SCRIPT} <builddir>" 2>&1
else
   BUILD_DIR=$(readlink -f $1)
fi


BITBAKE="$TOPDIR/tools/bitbake"

if [ ! -d "$BITBAKE" ] ; then
   echo "Unable to find $BITBAKE directory"
   $EXIT 1
fi

export BITBAKEDIR=$TOPDIR/tools/bitbake

# Add base OE-core layer
source ${TOPDIR}/layers/openembedded-core/oe-init-build-env ${BUILD_DIR}

# Use custom local.conf from meta-alif
LOCALCONF="$(readlink -f conf/local.conf)"
OELOCALSAMPLE="${TOPDIR}/layers/openembedded-core/meta/conf/local.conf.sample"
ALIFLOCALSAMPLE="${TOPDIR}/layers/meta-alif-ensemble/conf/local.conf.sample"
if diff -q $LOCALCONF $OELOCALSAMPLE ; then
   cp -f $ALIFLOCALSAMPLE $LOCALCONF
fi
unset LOCALCONF OELOCALSAMPLE ALIFLOCALSAMPLE

# Add dependent layers
LAYERS="meta-alif  \
meta-alif-ensemble \
meta-openembedded/meta-oe \
meta-openembedded/meta-filesystems \
meta-openembedded/meta-python \
meta-yocto/meta-poky \
meta-alif-iot"

for iter in ${LAYERS} ; do
   if [ ! -f "${BUILD_DIR}/.${iter///}" ] ; then
      bitbake-layers add-layer ${TOPDIR}/layers/$iter
      if [ $? -eq 0 ] ; then touch ${BUILD_DIR}/.${iter///} ; fi
   fi
done

# meta-e7-smp ships in this repository rather than being fetched into layers/,
# so it is added separately. It carries the TF-A CNTVOFF fix that SMP needs,
# plus SRCREV pins for TF-A and the kernel.
if [ ! -f "${BUILD_DIR}/.meta-e7-smp" ] ; then
   bitbake-layers add-layer ${TOPDIR}/meta-e7-smp
   if [ $? -eq 0 ] ; then touch ${BUILD_DIR}/.meta-e7-smp ; fi
fi

if [ ! -f "conf/auto.conf" ] ; then
   echo "MACHINE=\"devkit-e7\"" > conf/auto.conf
   echo "DISTRO=\"apss-tiny\""  >> conf/auto.conf
   # Build both A32 cores by default. devkit-e7.conf defaults SMP to "0",
   # which selects devkit_e7_unicore_defconfig. Set SMP=0 here for unicore.
   echo "SMP=\"${SMP:-1}\"" >> conf/auto.conf
   # Root filesystem on SD by default. MRAM then holds only TF-A, the DTB and the
   # XIP kernel, freeing 2,505,888 B for M55 firmware instead of the ~561 KB left
   # by the cramfs-in-MRAM layout.
   #
   # apss-sd-boot is a stock BSP feature (linux-alif.inc) that pulls in sd_boot.cfg:
   # the SDHCI/MMC drivers plus CONFIG_CMDLINE_FORCE=y with
   #   root=/dev/mmcblk0p1 rootfstype=ext4 rootwait rw
   # CONFIG_CMDLINE_FORCE means the kernel IGNORES the device tree bootargs, so the
   # stock DTB needs no patching -- but it also means this kernel REQUIRES an SD
   # card holding an ext4 root on the first partition. It will not fall back to a
   # cramfs in MRAM even if one is present.
   #
   # Set ROOTFS_ON_SD=0 for the stock cramfs-in-MRAM layout with no SD card.
   # See docs/config-b2-sd-root.md.
   if [ "${ROOTFS_ON_SD:-1}" = "1" ] ; then
      echo "DISTRO_FEATURES_append = \" apss-sd-boot\"" >> conf/auto.conf
   fi
   if [ "x$SOURCE_MIRROR_URL" = "x" ] ; then
      echo "SOURCE_MIRROR_URL=\"https://downloads.yoctoproject.org/mirror/sources/\"" >> conf/auto.conf
   fi
   echo "TFA_BRANCH=\"devkit-ex-b0\"" >> conf/auto.conf
   echo "ALIF_KERNEL_BRANCH=\"devkit-b0-5.4.y\"" >> conf/auto.conf
   echo "LINUX_DD_TC_BRANCH=\"devkit-ex-b0\"" >> conf/auto.conf
   if [ "x$HTTPS_USER" != "x" -a "x$HTTPS_PASSWD" != "x" ] ; then
       echo "TFA_TREE=\"git://github.com/alifsemi/alif_arm-tf;user=$HTTPS_USER:$HTTPS_PASSWD;protocol=https\"" >> conf/auto.conf
       echo "ALIF_KERNEL_TREE=\"git://github.com/alifsemi/alif_linux;user=$HTTPS_USER:$HTTPS_PASSWD;protocol=https\"" >> conf/auto.conf
       echo "LINUX_DD_TC_TREE=\"git://github.com/alifsemi/alif_a32_linux_DD_testcases;user=$HTTPS_USER:$HTTPS_PASSWD;protocol=https\"" >> conf/auto.conf
   else
       echo "TFA_TREE=\"git://github.com/alifsemi/alif_arm-tf;protocol=https\"" >> conf/auto.conf
       echo "ALIF_KERNEL_TREE=\"git://github.com/alifsemi/alif_linux;protocol=https\"" >> conf/auto.conf
       echo "LINUX_DD_TC_TREE=\"git://github.com/alifsemi/alif_a32_linux_DD_testcases;protocol=https\"" >> conf/auto.conf
   fi
   if [ "x$REL_TAG" != "x" ] ; then
       echo "SRCREV_pn-linux-alif=\"$REL_TAG\"" >> conf/auto.conf
       echo "SRCREV_pn-trusted-firmware-a=\"$REL_TAG\"" >> conf/auto.conf
   fi
fi

# Temporary waiting for proper bitbake integration: https://patchwork.openembedded.org/patch/144806/
RELPATH=$(python -c "from os.path import relpath; print (relpath(\"$TOPDIR/layers\",\"$(pwd)\"))")
#sed -i conf/bblayers.conf -e "s,$TOPDIR/layers/,\${TOPDIR}/$RELPATH/,"

if [ "$(readlink -f setup.sh)" = "$(readlink -f $TOPDIR/setup.sh)" ] ; then
   echo "Something went wrong. Exiting to prevent overwritting setup.sh"
   $EXIT 1
fi
SCRIPT_RELPATH=$(python -c "from os.path import relpath; print (relpath(\"$TOPDIR\",\"`pwd`\"))")
cat > setup.sh << EOF
#!/bin/bash
if [ -n "\$BASH_SOURCE" ]; then
   THIS_SCRIPT=\$BASH_SOURCE
elif [ -n "\$ZSH_NAME" ]; then
   THIS_SCRIPT=\$0
else
   THIS_SCRIPT="\$(pwd)/setup.sh"
fi
PROJECT_DIR=\$(dirname \$(readlink -f \$THIS_SCRIPT))
cd \$PROJECT_DIR
export BITBAKEDIR=$SCRIPT_RELPATH/tools/bitbake
source $SCRIPT_RELPATH/layers/openembedded-core/oe-init-build-env \$PROJECT_DIR
EOF


if [ "$EXIT" = "exit" ] ; then
   echo
   echo "=Setup Complete="
   echo
   echo "* Run the following to start building with your project:"
   echo "source $BUILD_DIR/setup.sh"
   echo "bitbake alif-helloworld-image"
   echo "bitbake alif-tiny-image"
   echo
else
   echo
   echo "=Setup Complete="
   echo
   echo "* Run the following to start building with your project:"
   echo "bitbake alif-helloworld-image"
   echo "bitbake alif-tiny-image"
   echo
fi
