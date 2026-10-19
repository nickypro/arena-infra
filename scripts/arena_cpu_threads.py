# Installed by arena-infra (docker_uv_setup.sh puts it + arena_cpu_threads.pth in arena-env's site-packages):
# cap OpenMP/BLAS threads to this container's CPU quota. Without it torch starts one thread per *host* core
# (e.g. 172 threads on a 5-CPU pod), and CPU-side ops like t.linalg.eigh slow down 10-100x. Explicitly set env vars win (setdefault).
import os


def _cpu_quota():
    try:
        quota, period = open("/sys/fs/cgroup/cpu.max").read().split()
        if quota != "max":
            return int(quota) / int(period)
    except Exception:
        pass
    try:
        quota = int(open("/sys/fs/cgroup/cpu/cpu.cfs_quota_us").read())
        period = int(open("/sys/fs/cgroup/cpu/cpu.cfs_period_us").read())
        if quota > 0:
            return quota / period
    except Exception:
        pass
    return None


_quota = _cpu_quota()
if _quota:
    for _var in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
        os.environ.setdefault(_var, str(max(1, int(_quota))))
