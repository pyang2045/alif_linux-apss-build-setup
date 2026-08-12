# SMP support for the E7 DevKit.
#
# TF-A never initializes CNTVOFF on the Hyp non-secure entry path, so the two
# A32 cores disagree about virtual time by an implementation-defined amount.
# With SMP enabled that makes tick_do_update_jiffies64() compute an enormous
# delta, so do_timer(++ticks) credits thousands of jiffies per tick and
# userspace is never scheduled -- the kernel brings both cores up, prints
# "Run /sbin/init as init process", and stops there.
#
# See files/0001-aarch32-zero-cntvoff-for-hyp-nonsecure-entry.patch.

FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += "file://0001-aarch32-zero-cntvoff-for-hyp-nonsecure-entry.patch"

# Pin TF-A. The recipe otherwise uses ${AUTOREV}, which tracks the branch tip
# and makes bl32.bin non-reproducible between builds.
# Confirmed at runtime: this hash appears in the SP_MIN boot banner.
SRCREV = "e18dde23eeb7fadec350340e8ca9ee52a8479136"
