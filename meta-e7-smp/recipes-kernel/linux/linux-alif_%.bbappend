# Pin the kernel. linux-alif_5.4.bb sets SRCREV to the branch NAME, which
# floats with upstream and makes xipImage non-reproducible.
#
# The %-wildcard filename keeps this applying if the recipe version is bumped,
# rather than silently detaching.

SRCREV = "73d1a0df1f2bf43d7373b57ce9092f0d098e8a8e"
