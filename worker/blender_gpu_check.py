"""
Blender GPU diagnostic — run this BEFORE queueing jobs to confirm
Cycles can actually see your GPU.

Usage (on your local WSL machine):
    blender --background --python worker/blender_gpu_check.py
"""
import bpy

prefs = bpy.context.preferences.addons["cycles"].preferences

print()
print("=" * 50)
print("  Blender Cycles GPU Check")
print("=" * 50)

found_gpu = False
for backend in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
    try:
        prefs.compute_device_type = backend
    except TypeError:
        print(f"  {backend}: not compiled into this Blender build — skip")
        continue

    refresh = getattr(prefs, "refresh_devices", None) or getattr(prefs, "get_devices", None)
    if refresh:
        try:
            refresh()
        except Exception as e:
            print(f"  {backend}: refresh_devices() error — {e}")
            continue

    all_devs = list(prefs.devices)
    gpu_devs = [d for d in all_devs if d.type != "CPU"]

    print(f"  {backend}: {len(gpu_devs)} GPU / {len(all_devs)} total device(s)")
    for d in all_devs:
        marker = "GPU" if d.type != "CPU" else "cpu"
        print(f"    [{marker}] {d.name}  type={d.type}")

    if gpu_devs:
        print(f"  => Will use {backend} for rendering ✓")
        found_gpu = True
        break

if not found_gpu:
    print()
    print("  !! No GPU backend found — Blender will render on CPU")
    print("  Possible causes in WSL2:")
    print("    1. LD_LIBRARY_PATH missing /usr/lib/wsl/lib")
    print("    2. Blender CUDA kernels not compiled for your GPU arch")
    print("    3. OptiX driver not available in headless WSL2")
    print()
    print("  Try running with:")
    print("    LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH blender --background --python worker/blender_gpu_check.py")

print("=" * 50)
print()
