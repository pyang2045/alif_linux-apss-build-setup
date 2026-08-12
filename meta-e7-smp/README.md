# meta-e7-smp

Makes the Alif Ensemble E7 DevKit boot Linux on **both** Cortex-A32 cores.

Added to `bblayers.conf` automatically by `scripts/setup.sh`. Nothing to install.

For the MRAM-saving layout that pairs with this (root filesystem on SD, 2,505,888 B freed
for M55 firmware), see [`docs/config-b2-sd-root.md`](../docs/config-b2-sd-root.md).

## The bug this fixes

With `SMP = "1"`, the stock BSP brings both cores up and then dies before userspace:

```
smp: Brought up 1 node, 2 CPUs
SMP: Total of 2 processors activated (400.00 BogoMIPS).
VFS: Mounted root (cramfs filesystem) readonly on device 31:0.
Run /sbin/init as init process
                                    <- nothing, forever
```

**Cause: TF-A never initializes `CNTVOFF`.**

1. Cortex-A32 reports `ID_PFR1.VIRTEXT`, so TF-A enters Linux in **Hyp** mode — the kernel
   runs its hyp stub and drops to SVC itself.
2. That sets `SCR.HCE` in the saved non-secure context (`SIF|HCE|NS = 0x301`).
3. `cm_prepare_el3_exit()` therefore takes the **HCE branch**, which writes `HSCTLR` but
   **not** `CNTVOFF`.
4. The only `write64_cntvoff(0)` in TF-A sits in the **EL2-unused** branch — skipped
   precisely when `SCR.HCE` is set.
5. `CNTVOFF` resets to an IMPLEMENTATION DEFINED value. CPU0 survives on a power-on zero;
   CPU1, released later by `PSCI_CPU_ON`, does not.
6. `CNTVCT = CNTPCT - CNTVOFF`, so the cores read different virtual time. In
   `tick_do_update_jiffies64()` the delta comes out enormous, and `do_timer(++ticks)`
   credits thousands of jiffies per tick instead of one. Userspace never gets scheduled.

Measured before and after, on hardware:

| | Broken | Fixed |
|---|---|---|
| `jiffies_64` | 788,356/s — 7,884x too fast | **101.5/s** (HZ=100) |
| userspace | stuck after `Run /sbin/init` | **`devkit-e7 login:`** |
| `nproc` | — | **2** |
| `arch_timer` IRQs | — | CPU0 12865 / CPU1 12865 |

Diagnosis notes: the tick fires correctly the whole time — `tk_core.seq` advances at exactly
101/s and `cycle_interval` is a sane 1,000,000 cycles. Only the *count* passed to `do_timer()`
is wrong, which is why the clocksource looks healthy while jiffies races. `maxcpus=1` boots
fine with the same kernel binary, which isolates it to CPU1 participating.

## Contents

| File | Purpose |
|---|---|
| `recipes-bsp/trusted-firmware-a/files/0001-aarch32-zero-cntvoff-*.patch` | the fix — adds `write64_cntvoff(0)` to the HCE path |
| `recipes-bsp/trusted-firmware-a/trusted-firmware-a.bbappend` | applies the patch; pins TF-A to `e18dde23` |
| `recipes-kernel/linux/linux-alif_%.bbappend` | pins the kernel to `73d1a0df` |

## Why the pins

Both stock recipes float: TF-A uses `${AUTOREV}` and `linux-alif_5.4.bb` sets `SRCREV` to a
branch *name*. Either can change under you between builds. The TF-A pin is confirmed at
runtime — `e18dde23` appears in the `SP_MIN` boot banner.

## Upstream

The patched file (`lib/el3_runtime/aarch32/context_mgmt.c`) is **generic TF-A**, not Alif code,
and current upstream master still has the same gap. The assumption there — that a hypervisor
at EL2 will own `CNTVOFF` — does not hold for `ARM_LINUX_KERNEL_AS_BL33`, where Linux enters
Hyp only to install a stub and immediately drops to SVC. Any AArch32 platform combining
`RESET_TO_SP_MIN` + `ARM_LINUX_KERNEL_AS_BL33` + SMP should hit this.

The patch is marked `Upstream-Status: Pending`. It is validated on the E7 DevKit only and
would need broader testing before submission to the TF-A list.

## Building on macOS

The macOS host filesystem is case-insensitive, which Yocto cannot use for its build
directory. Keep the checkout bind-mounted at `/src` but place the build directory inside the
container's own case-sensitive overlay (e.g. `/build`) rather than under the mount. This is
an environment constraint, not a source change — nothing in this layer depends on it.

## Verified from a clean clone

`git clone -b smp-support`, `fetch-layers.sh`, `setup.sh`, `bitbake alif-tiny-image`, then
provisioning MRAM from the resulting artifacts:

| Check | Result |
|---|---|
| Layer wired in | `bblayers.conf` has `/src/meta-e7-smp`; `auto.conf` has `SMP="1"` |
| Patch applied | `do_patch` log confirms; `write64_cntvoff(0)` present in the HCE branch |
| `bl32.bin` reproducible | 30,136 B; **only 3 differing byte ranges vs the reference, all inside the build-timestamp string** |
| Kernel config | `CONFIG_SMP=y`, `CONFIG_NR_CPUS=2` |
| Boot | `SMP: Total of 2 processors activated`, reaches `devkit-e7 login:` |
| Runtime | `nproc` = 2; `arch_timer` 10643 on CPU0 **and** 10643 on CPU1 |
