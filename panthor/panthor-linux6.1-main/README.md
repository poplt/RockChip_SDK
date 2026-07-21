# Panthor
Panthor is for supporting newer Mali GPUs that implement Arm's v10 GPU architecture. This project ports Panthor to the RK3588 EVB platform based on the Rockchip Linux 6.1 kernel.

# NOTICE
Since Panthor is released based on the Linux kernel version 6.8, some adaptations to the drm driver are needed when porting it to Linux 6.1.

The Panthor code is obtained from the Linux repository, based on the following commit:
commit 36766cdebe92524009c8c8384e705f167e89c32c

Mali-G610 CSF firmware obtained from the following repository:  
https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git  

The Panfrost userspace driver's support for ARM Mali v10 GPU has been merged into the Mesa mainstream. Mali-G610 user driver is compiled and installed using the Mesa 24.1.0-devel (git-4586451b2d) mainstream version for testing.
