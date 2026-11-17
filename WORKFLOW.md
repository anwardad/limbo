# Limbo GPU Acceleration Development Workflow

This workflow is for the Limbo fork based on the supplied `limbo-master` source snapshot.
It separates the existing Limbo baseline, the Android host renderer, the XP guest graphics
transport/driver, and the independent Linux VirGL workstream.

> Scope warning: the included GitHub Actions pipeline builds the **unmodified Limbo native
> baseline** for an ARM64 Android host with the x86_64 QEMU system target, then packages the
> x86 Android application. It does not add VirGL, a Windows XP graphics driver, or 3D support.

## 0. Establish a safe fork workflow

1. Keep the fork's default branch as a clean mirror of upstream history.
2. Create a working branch named `work/gpu-baseline`.
3. Add this workflow package at the repository root, preserving the `.github/` and `scripts/`
   directory structure.
4. Commit and push the branch, then open a draft pull request against your fork's default branch.
   The `pull_request` trigger runs the baseline CI. After the workflow is merged into the default
   branch, you can also start it manually from **Actions → Limbo ARM64 baseline build → Run workflow**.
5. Do not begin graphics changes until this baseline build succeeds or its failures have been
   recorded and understood.

Suggested branch names for later work:

- `feature/android-egl-renderer`
- `feature/qemu-gpu-pci-device`
- `feature/xp-xpdm-driver`
- `feature/xp-2d-acceleration`
- `feature/xp-direct3d-translation`
- `feature/xp-opengl-icd`
- `feature/xp-glide-translation`
- `feature/linux-virgl`

Use one focused pull request per layer. Keep the standard VGA/VNC/SDL paths working throughout.

## 1. Baseline build (first gate)

The source's `README.developers` documents these pinned inputs:

| Component | Baseline version |
|---|---:|
| QEMU | 5.1.0 |
| GLib | 2.56.1 |
| libffi | 3.3 |
| Pixman | 0.40.0 |
| SDL2 | 2.0.8 |
| Android NDK | r23b / `23.1.7779620` |
| Android API | 21 |
| Android compile SDK | 29 |
| Android build tools | 29.0.3 |
| Android Gradle Plugin | 4.1.1 |
| Gradle | 7.0.2 |
| Java | 11 |
| Android host ABI | `arm64-v8a` |
| QEMU system target | `x86_64-softmmu` |

The repository does not contain the Gradle wrapper launchers (`gradlew` / `gradlew.bat`).
The CI workflow uses Gradle 7.0.2 directly with the repository's existing wrapper properties.

The pipeline downloads the five external source trees, applies the QEMU 5.1.0, GLib 2.56.1,
and SDL2 2.0.8 patches already stored in `limbo-android-lib/src/main/jni/patches/`, builds
with the repository's `make limbo` target, then runs `:limbo-android-x86:assembleDebug`.

### Baseline success criteria

- The native `make limbo` command exits successfully.
- The build produces `libqemu-system-x86_64.so` for `arm64-v8a`.
- The `limbo-android-x86` debug APK is produced and archived by CI.
- A real ARM64 Android device can install the APK and boot an x86 Windows XP installation
  using the existing non-accelerated display path.
- Save the CI run URL, APK, QEMU version, and `adb logcat` output with the baseline record.

A successful CI build proves compilation and packaging, not runtime correctness. The device
boot test is a separate manual gate.

## 2. Architecture decisions before coding

Create an architecture decision record (ADR) before implementing the protocol. Decide and
write down:

1. Whether the XP guest device is a new custom PCI device or an extension of an existing QEMU
   device. Do not assume the Linux virtio-gpu guest driver can serve Windows XP.
2. The command transport: shared-memory command ring, guest/host ownership rules, queue sizes,
   resource handles, fences, error handling, and reset semantics.
3. Guest-visible device IDs, PCI BAR layout, interrupt model, and version negotiation.
4. Renderer ownership: EGL context thread, surface attach/detach, resource lifetime, and recovery
   after Android activity pause/resume or surface recreation.
5. The protocol's security boundary: validate guest-controlled offsets, sizes, handles, and
   command payloads before use.
6. The licensing and code-reuse status of any XP driver/reference project before copying code.

Keep the Windows XP protocol independent from VirGL. They may share host-side EGL/GLES resource
helpers, but should not share guest command protocols unless a compatibility layer explicitly
proves that is safe.

## 3. Implementation sequence and pull-request gates

### PR 1 — Android EGL/GLES renderer (no QEMU or XP changes)

- Add a native renderer module that can create an EGL display, GLES 3 context, and pbuffer or
  Android-window surface.
- Integrate surface creation, resize, pause, resume, destruction, and recreation with Limbo's
  existing SDL/Activity lifecycle.
- Ensure EGL context ownership is confined to one rendering thread.
- Add a diagnostic screen or test mode that clears the screen and draws a textured triangle.

**Gate:** repeatedly rotate, background, resume, and recreate the surface without EGL errors,
black screens, leaks, or crashes. Existing software/VNC rendering remains available.

### PR 2 — QEMU host-side graphics device and protocol tests

- Implement the host-side device in the QEMU source tree using the selected PCI transport.
- Initially accept only a minimal `GET_CAPS`, `CREATE_RESOURCE`, `CLEAR`, and `PRESENT` command
  set; reject unknown commands and invalid resource references.
- Add host-side unit tests for malformed descriptors, out-of-range offsets, invalid handles,
  queue wraparound, reset, and fence completion.
- Keep the renderer optional at configure time so non-GPU builds still work.

**Gate:** QEMU device tests pass without an Android surface and QEMU still builds with graphics
support disabled.

### PR 3 — Windows XP x86 test driver

- Build the initial guest test driver separately using a Windows XP-compatible WDK/toolchain.
- Start with device discovery, PCI BAR mapping, shared-memory mapping, version negotiation, and
  a single clear/present operation.
- Do not replace Windows system DLLs or claim DirectDraw/Direct3D support at this stage.

**Gate:** a test program in XP can submit a clear/present operation and the Android host displays
it. A failed device initialization must leave XP bootable with standard VGA.

### PR 4 — XP desktop / 2D acceleration

- Implement the XPDM miniport/display path and the documented subset of GDI/DDI operations.
- Begin with fill, copy, stretch, cursor, mode setting, and damage-region updates.
- Keep CPU fallback paths for unsupported raster operations.

**Gate:** desktop rendering, text, menus, window movement, resizing, and screen updates remain
correct. Compare screenshots against standard VGA output.

### PR 5 — DirectDraw and Direct3D 1–7

- Implement surface allocation, locking, flipping, blitting, palette, and synchronization.
- Add a legacy Direct3D translation layer only after the 2D surface model is stable.
- Validate API behavior with focused tests before testing games.

**Gate:** publish a compatibility list per API feature and per tested title; do not label the full
Direct3D 1–7 range supported after a single game succeeds.

### PR 6 — Direct3D 8 and 9

- Define a common internal command representation for shaders, vertex/index buffers, textures,
  render targets, depth/stencil, blend/raster state, queries, and fences.
- Implement D3D8 compatibility and D3D9 entry points separately, translating both into the common
  host command model where semantics match.
- Add capability negotiation and fallback for unsupported GLES features. If GLES 3.0 cannot
  implement a required feature, add an explicit optional Vulkan host backend rather than silently
  emulating unsupported behavior.

**Gate:** API conformance tests and a small set of representative games pass with screenshots,
logs, and measured frame times. Report unsupported features honestly.

### PR 7 — OpenGL ICD

- Implement the XP OpenGL Installable Client Driver (ICD) interface and advertise only extensions
  actually implemented by the host backend.
- Start with the OpenGL versions/features practical for the chosen host API; translate fixed
  function operations as needed.

**Gate:** XP identifies the ICD, OpenGL test applications render correctly, and unsupported
extensions are not advertised.

### PR 8 — Glide 2/3 translation

- Implement Glide entry points and translate them into the host renderer's resource/command model.
- Keep actual Voodoo hardware emulation as a separate compatibility fallback; it is not GPU
  acceleration.

**Gate:** test Glide 2 and Glide 3 titles independently and document per-title compatibility.

### Parallel track — Linux VirGL

VirGL is a separate Linux-guest workstream using the Linux virtio-gpu/Mesa stack. Do not use it as
an XP Direct3D driver. First prove EGL/GLES context creation, then evaluate the exact QEMU and
virglrenderer versions, Android build options, and whether the selected versions require GBM or
other desktop-only facilities. Avoid enabling QEMU's desktop OpenGL/GBM path blindly on Android.

## 4. Performance and correctness rules

- Prefer asynchronous command submission and batching; avoid per-draw synchronous guest/host
  round trips.
- Define explicit fences and bounded waits. Never busy-wait indefinitely on the UI thread.
- Validate every guest-controlled memory range and multiplication/addition for overflow.
- Bound allocations and provide resource eviction / teardown paths.
- Handle Android surface loss without destroying guest resources unnecessarily.
- Benchmark CPU translation overhead separately from GPU execution. The x86 guest CPU remains
  TCG-emulated on ARM64; GPU acceleration does not accelerate guest CPU instructions.
- Test with a 2D fallback and a clean disable switch for every experimental graphics backend.

## 5. Pull request template

Every graphics PR should contain:

- Scope and guest-visible behavior.
- Files changed and protocol/API additions.
- Build command and exact toolchain versions.
- Unit/integration tests and logs.
- Tested Android device/GPU/Android version where relevant.
- Tested Windows XP SP3 image/driver configuration where relevant.
- Screenshots or short captures for rendering changes.
- Performance numbers with resolution and guest workload.
- Known limitations and explicit fallback behavior.
- Confirmation that standard VGA/VNC/SDL paths still work.

## 6. First action

Add the `.github/workflows/limbo-arm64-baseline.yml` workflow and `scripts/ci/` helpers to the
fork, push branch `work/gpu-baseline`, and open a draft PR. Let the pull-request workflow run; after
the workflow is merged into the default branch, manual dispatch is available too. Fix the baseline
build first. Do not start PR 1 until the original project can be built reproducibly.
