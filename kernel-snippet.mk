# Snippet for Linux kernel package building
# Copyright (C) 2020 Eugenio "g7" Paolantonio <me@medesimo.eu>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the <organization> nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


include $(CURDIR)/debian/kernel-info.mk

ifneq (,$(filter parallel=%,$(DEB_BUILD_OPTIONS)))
	NUMJOBS := $(patsubst parallel=%,%,$(filter parallel=%,$(DEB_BUILD_OPTIONS)))
else
	NUMJOBS := 1
endif

export DEB_HOST_MULTIARCH = $(shell dpkg-architecture -qDEB_HOST_MULTIARCH)

KERNEL_RELEASE = $(KERNEL_BASE_VERSION)-$(DEVICE_VENDOR)-$(DEVICE_MODEL)
BASEDIR = $(CURDIR)
OUT = $(CURDIR)/out
KERNEL_SOURCES ?= $(CURDIR)
KERNEL_OUT = $(OUT)/KERNEL_OBJ
ifeq ($(BUILD_CROSS), 1)
	CROSS_COMPILE = $(BUILD_TRIPLET)
endif
FULL_PATH = $(BUILD_PATH):$(CURDIR)/debian/path-override:${PATH}
BUILD_COMMAND = PATH=$(FULL_PATH) LDFLAGS="" CFLAGS="" $(MAKE) -C $(KERNEL_SOURCES) KERNELRELEASE=$(KERNEL_RELEASE) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(CROSS_COMPILE) CROSS_COMPILE_ARM32=$(CROSS_COMPILE) CLANG_TRIPLE=$(BUILD_CLANG_TRIPLET) -j$(NUMJOBS) O=$(KERNEL_OUT) CC=$(BUILD_CC)

KERNEL_BOOTIMAGE_VERSION ?= 0

ifndef KERNEL_CONFIG_COMMON_FRAGMENTS
KERNEL_CONFIG_COMMON_FRAGMENTS += $(KERNEL_SOURCES)/droidian/common_fragments/halium.config
KERNEL_CONFIG_COMMON_FRAGMENTS += $(KERNEL_SOURCES)/droidian/common_fragments/droidian.config
ifeq ($(KERNEL_CONFIG_DEBUG_FRAGMENT),1)
KERNEL_CONFIG_COMMON_FRAGMENTS += $(KERNEL_SOURCES)/droidian/common_fragments/debug.config
endif
endif

ifdef DEVICE_PLATFORM
KERNEL_CONFIG_DEVICE_FRAGMENTS += $(KERNEL_SOURCES)/droidian/$(DEVICE_PLATFORM).config
endif
KERNEL_CONFIG_DEVICE_FRAGMENTS += $(KERNEL_SOURCES)/droidian/$(DEVICE_MODEL).config

debian/control:
	sed -e "s|@KERNEL_BASE_VERSION@|$(KERNEL_BASE_VERSION)|g" \
		-e "s|@VARIANT@|$(VARIANT)|g" \
		-e "s|@DEVICE_VENDOR@|$(DEVICE_VENDOR)|g" \
		-e "s|@DEVICE_MODEL@|$(DEVICE_MODEL)|g" \
		-e "s|@DEVICE_FULL_NAME@|$(DEVICE_FULL_NAME)|g" \
		-e "s|@DEB_TOOLCHAIN@|$(DEB_TOOLCHAIN)|g" \
		-e "s|@DEB_BUILD_ON@|$(DEB_BUILD_ON)|g" \
		-e "s|@DEB_BUILD_FOR@|$(DEB_BUILD_FOR)|g" \
		/usr/share/linux-packaging-snippets/control.in > debian/control

path-override-prepare:
	mkdir -p debian/path-override
	ln -sf /opt/android/prebuilts/python/2.7.5/bin/python debian/path-override/python

ifeq ($(KERNEL_CONFIG_USE_FRAGMENTS),1)
out/KERNEL_OBJ/.config: path-override-prepare $(KERNEL_SOURCES)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG)
	mkdir -p $(KERNEL_OUT)
ifeq ($(KERNEL_CONFIG_USE_DIFFCONFIG),1)
	$(BUILD_COMMAND) ARCH=$(KERNEL_ARCH) O=$(KERNEL_OUT) KBUILD_DIFFCONFIG=$(KERNEL_PRODUCT_DIFFCONFIG) $(KERNEL_DEFCONFIG)
else
	$(BUILD_COMMAND) defconfig KBUILD_DEFCONFIG=$(KERNEL_DEFCONFIG)
endif
	cd $(KERNEL_SOURCES) ; PATH=$(FULL_PATH) ARCH=$(KERNEL_ARCH) $(KERNEL_SOURCES)/scripts/kconfig/merge_config.sh -O $(KERNEL_OUT) \
		$(KERNEL_OUT)/.config \
		$(KERNEL_CONFIG_COMMON_FRAGMENTS) \
		$(KERNEL_CONFIG_DEVICE_FRAGMENTS) \
		;
else
out/KERNEL_OBJ/.config: $(KERNEL_SOURCES)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG)
	$(BUILD_COMMAND) defconfig KBUILD_DEFCONFIG=$(KERNEL_DEFCONFIG)
endif

out/kernel-stamp: out/KERNEL_OBJ/.config
	$(BUILD_COMMAND) $(KERNEL_BUILD_TARGET)
	touch $(OUT)/kernel-stamp

out/modules-stamp: out/kernel-stamp out/dtb-stamp
	$(BUILD_COMMAND) modules
	touch $(OUT)/modules-stamp

out/dtb-stamp: out/kernel-stamp
	$(BUILD_COMMAND) dtbs
	touch $(OUT)/dtb-stamp

out/KERNEL_OBJ/dtb-merged: out/dtb-stamp
ifeq ($(KERNEL_IMAGE_WITH_DTB),1)
	rm -f $(KERNEL_OUT)/dtb
	rm -f $(KERNEL_OUT)/dtb-merged
ifeq ($(KERNEL_IMAGE_WITH_DTB_OVERLAY_IN_KERNEL),1)
	if [ -n "$(KERNEL_IMAGE_DTB)" ]; then \
		for dtb in $(KERNEL_IMAGE_DTB); do \
			cat $(KERNEL_OUT)/$${dtb} >> $(KERNEL_OUT)/dtb; \
		done; \
		KERNEL_IMAGE_DTB=$(KERNEL_OUT)/dtb; \
	else \
		KERNEL_IMAGE_DTB=$$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot -type f -iname \*.dtb | head -n 1); \
	fi; \
	if [ -n "$(KERNEL_IMAGE_DTB_OVERLAY)" ]; then \
		KERNEL_IMAGE_DTB_OVERLAY=$(KERNEL_OUT)/$(KERNEL_IMAGE_DTB_OVERLAY); \
	else \
		KERNEL_IMAGE_DTB_OVERLAY=$$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot -type f -iname \*.dtbo | head -n 1); \
	fi; \
	[ -n "$${KERNEL_IMAGE_DTB}" ] && [ -n "$${KERNEL_IMAGE_DTB_OVERLAY}" ] && \
		ufdt_apply_overlay $${KERNEL_IMAGE_DTB} $${KERNEL_IMAGE_DTB_OVERLAY} $(KERNEL_OUT)/dtb-merged
else
	if [ -n "$(KERNEL_IMAGE_DTB)" ]; then \
		for dtb in $(KERNEL_IMAGE_DTB); do \
			cat $(KERNEL_OUT)/$${dtb} >> $(KERNEL_OUT)/dtb; \
		done; \
		KERNEL_IMAGE_DTB=$(KERNEL_OUT)/dtb; \
	else \
		KERNEL_IMAGE_DTB=$$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot -type f -iname \*.dtb | head -n 1); \
	fi; \
	[ -n "$${KERNEL_IMAGE_DTB}" ] && \
		cp $${KERNEL_IMAGE_DTB} $(KERNEL_OUT)/dtb-merged
endif
else
	touch $@
endif

out/KERNEL_OBJ/target-dtb: out/kernel-stamp out/KERNEL_OBJ/dtb-merged
ifeq ($(KERNEL_IMAGE_WITH_DTB),1)
	cat $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) \
		$(KERNEL_OUT)/dtb-merged \
		> $@
else
	cp $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) $@
endif

out/KERNEL_OBJ/dtbo.img: out/dtb-stamp
ifeq ($(KERNEL_IMAGE_WITH_DTB_OVERLAY),1)
ifdef KERNEL_IMAGE_DTB_OVERLAY_CONFIGURATION
	mkdtboimg cfg_create $@ $(KERNEL_IMAGE_DTB_OVERLAY_CONFIGURATION) --dtb-dir $(KERNEL_OUT)/$(KERNEL_IMAGE_DTB_OVERLAY_DTB_DIRECTORY)
else
	if [ -n "$(KERNEL_IMAGE_DTB_OVERLAY)" ]; then \
		KERNEL_IMAGE_DTB_OVERLAY=$(KERNEL_OUT)/$(KERNEL_IMAGE_DTB_OVERLAY); \
	else \
		KERNEL_IMAGE_DTB_OVERLAY=$$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot -type f -iname \*.dtbo | head -n 1); \
	fi; \
	[ -n "$${KERNEL_IMAGE_DTB_OVERLAY}" ] && \
		mkdtboimg create $@ $${KERNEL_IMAGE_DTB_OVERLAY}
endif
else
	touch $@
endif

out/KERNEL_OBJ/vbmeta.img:
ifeq ($(DEVICE_VBMETA_REQUIRED),1)
ifeq ($(DEVICE_VBMETA_IS_SAMSUNG),0)
	avbtool make_vbmeta_image --flags 2 --padding_size 4096 --set_hashtree_disabled_flag --output $@
else
	avbtool make_vbmeta_image --flags 0 --padding_size 4096 --set_hashtree_disabled_flag --output $@
endif
else
	touch $@
endif

out/KERNEL_OBJ/initramfs.gz:
	OVERLAY_DIR="$(CURDIR)/debian/initramfs-overlay"; \
	if [ -e "$${OVERLAY_DIR}" ]; then \
		tmpdir=$$(mktemp -d); \
		cd $${tmpdir}; \
		gunzip -c /usr/lib/$(DEB_HOST_MULTIARCH)/halium-generic-initramfs/initrd.img-halium-generic | cpio -i; \
		cp -Rv $${OVERLAY_DIR}/* .; \
		find . | cpio -o -R 0:0 -H newc | gzip > $(BASEDIR)/$@; \
	else \
		cp /usr/lib/$(DEB_HOST_MULTIARCH)/halium-generic-initramfs/initrd.img-halium-generic $@; \
	fi

out/KERNEL_OBJ/recovery-initramfs.gz:
	OVERLAY_DIR="$(CURDIR)/debian/initramfs-overlay"; \
	RECOVERY_OVERLAY_DIR="$(CURDIR)/debian/recovery-initramfs-overlay"; \
	if [ -e "$${OVERLAY_DIR}" ] || [ -e "$${RECOVERY_OVERLAY_DIR}" ]; then \
		tmpdir=$$(mktemp -d); \
		cd $${tmpdir}; \
		gunzip -c /usr/lib/$(DEB_HOST_MULTIARCH)/halium-generic-initramfs/recovery-initramfs.img-halium-generic | cpio -i;\
		[ -e "$${OVERLAY_DIR}" ] && cp -Rv $${OVERLAY_DIR}/* .; \
		[ -e "$${RECOVERY_OVERLAY_DIR}" ] && cp -Rv $${RECOVERY_OVERLAY_DIR}/* .; \
		find . | cpio -o -R 0:0 -H newc | gzip > $(BASEDIR)/$@; \
	else \
		cp /usr/lib/$(DEB_HOST_MULTIARCH)/halium-generic-initramfs/recovery-initramfs.img-halium-generic $@; \
	fi

out/KERNEL_OBJ/boot.img: out/KERNEL_OBJ/initramfs.gz out/KERNEL_OBJ/target-dtb
	if [ "$(KERNEL_BOOTIMAGE_VERSION)" -eq "2" ]; then \
		MKBOOTIMG_KERNEL_ARGS="--kernel $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) --dtb $(KERNEL_OUT)/dtb-merged --dtb_offset $(KERNEL_BOOTIMAGE_DTB_OFFSET) --header_version $(KERNEL_BOOTIMAGE_VERSION)"; \
	elif [ -f "$(KERNEL_PREBUILT_DT)" ]; then \
		MKBOOTIMG_KERNEL_ARGS="--kernel $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) --dt $(KERNEL_PREBUILT_DT)"; \
	else \
		MKBOOTIMG_KERNEL_ARGS="--kernel $(KERNEL_OUT)/target-dtb --header_version $(KERNEL_BOOTIMAGE_VERSION)"; \
	fi; \
	if [ -n "$(KERNEL_BOOTIMAGE_PATCH_LEVEL)" ]; then \
			MKBOOTIMG_SPL_ARGS="--os_patch_level $(KERNEL_BOOTIMAGE_PATCH_LEVEL)"; \
	else \
			MKBOOTIMG_SPL_ARGS=""; \
	fi; \
	eval mkbootimg \
		$${MKBOOTIMG_KERNEL_ARGS} \
		--ramdisk out/KERNEL_OBJ/initramfs.gz \
		--base $(KERNEL_BOOTIMAGE_BASE_OFFSET) \
		--kernel_offset $(KERNEL_BOOTIMAGE_KERNEL_OFFSET) \
		--ramdisk_offset $(KERNEL_BOOTIMAGE_INITRAMFS_OFFSET) \
		--second_offset $(KERNEL_BOOTIMAGE_SECONDIMAGE_OFFSET) \
		--tags_offset $(KERNEL_BOOTIMAGE_TAGS_OFFSET) \
		--pagesize $(KERNEL_BOOTIMAGE_PAGE_SIZE) \
		--cmdline "\"$(KERNEL_BOOTIMAGE_CMDLINE)\"" \
		$${MKBOOTIMG_SPL_ARGS} \
		-o $@

out/KERNEL_OBJ/recovery.img: out/KERNEL_OBJ/recovery-initramfs.gz out/KERNEL_OBJ/target-dtb
	if [ "$(KERNEL_BOOTIMAGE_VERSION)" -eq "2" ]; then \
		MKBOOTIMG_KERNEL_ARGS="--kernel $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) --dtb $(KERNEL_OUT)/dtb-merged --dtb_offset $(KERNEL_BOOTIMAGE_DTB_OFFSET) --header_version $(KERNEL_BOOTIMAGE_VERSION)"; \
	elif [ -n "$(KERNEL_PREBUILT_DT)" ]; then \
		MKBOOTIMG_KERNEL_ARGS="--kernel $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) --dt $(KERNEL_PREBUILT_DT)"; \
	else \
		MKBOOTIMG_KERNEL_ARGS="--kernel $(KERNEL_OUT)/target-dtb --header_version $(KERNEL_BOOTIMAGE_VERSION)"; \
	fi; \
	if [ -n "$(KERNEL_BOOTIMAGE_PATCH_LEVEL)" ]; then \
			MKBOOTIMG_SPL_ARGS="--os_patch_level $(KERNEL_BOOTIMAGE_PATCH_LEVEL)"; \
	else \
			MKBOOTIMG_SPL_ARGS=""; \
	fi; \
	eval mkbootimg \
		$${MKBOOTIMG_KERNEL_ARGS} \
		--ramdisk out/KERNEL_OBJ/recovery-initramfs.gz \
		--base $(KERNEL_BOOTIMAGE_BASE_OFFSET) \
		--kernel_offset $(KERNEL_BOOTIMAGE_KERNEL_OFFSET) \
		--ramdisk_offset $(KERNEL_BOOTIMAGE_INITRAMFS_OFFSET) \
		--second_offset $(KERNEL_BOOTIMAGE_SECONDIMAGE_OFFSET) \
		--tags_offset $(KERNEL_BOOTIMAGE_TAGS_OFFSET) \
		--pagesize $(KERNEL_BOOTIMAGE_PAGE_SIZE) \
		--cmdline "\"$(KERNEL_BOOTIMAGE_CMDLINE) halium.recovery\"" \
		$${MKBOOTIMG_SPL_ARGS} \
		-o $@

override_dh_auto_configure: debian/control out/KERNEL_OBJ/.config path-override-prepare

override_dh_auto_build: out/KERNEL_OBJ/target-dtb out/KERNEL_OBJ/boot.img out/KERNEL_OBJ/recovery.img out/KERNEL_OBJ/dtbo.img out/KERNEL_OBJ/vbmeta.img out/modules-stamp out/dtb-stamp

kernel_snippet_install:
	mkdir -p $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot
	$(BUILD_COMMAND) modules_install INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=$(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)
	cp -v $(KERNEL_OUT)/System.map $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot/System.map-$(KERNEL_RELEASE)
ifeq ($(KERNEL_BOOTIMAGE_VERSION),2)
	cp -v $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(KERNEL_BUILD_TARGET) $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot/$(KERNEL_BUILD_TARGET)-$(KERNEL_RELEASE)
	cp -v $(KERNEL_OUT)/dtb-merged $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot/dtb-$(KERNEL_RELEASE)
else
	cp -v $(KERNEL_OUT)/target-dtb $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot/$(KERNEL_BUILD_TARGET)-$(KERNEL_RELEASE)
endif
	cp -v $(KERNEL_OUT)/.config $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/boot/config-$(KERNEL_RELEASE)
	rm -f $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/lib/modules/$(KERNEL_RELEASE)/build
	rm -f $(CURDIR)/debian/linux-image-$(KERNEL_RELEASE)/lib/modules/$(KERNEL_RELEASE)/source

	mkdir -p $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot
	cp -v $(KERNEL_OUT)/boot.img $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot/boot.img-$(KERNEL_RELEASE)
	cp -v $(KERNEL_OUT)/recovery.img $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot/recovery.img-$(KERNEL_RELEASE)
ifeq ($(KERNEL_IMAGE_WITH_DTB_OVERLAY),1)
	cp -v $(KERNEL_OUT)/dtbo.img $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot/dtbo.img-$(KERNEL_RELEASE)
endif

ifeq ($(DEVICE_VBMETA_REQUIRED),1)
	cp -v $(KERNEL_OUT)/vbmeta.img $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/boot/vbmeta.img-$(KERNEL_RELEASE)
endif

	# Generate flash-bootimage settings
	mkdir -p $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage
ifeq ($(FLASH_ENABLED), 1)

	# Install postinst (perhaps this isn't the best place)
	sed -e "s|@KERNEL_RELEASE@|$(KERNEL_RELEASE)|g" \
		/usr/share/linux-packaging-snippets/linux-bootimage.postinst.in \
			> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE).postinst
	chmod +x $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE).postinst

	sed -e "s|@KERNEL_BASE_VERSION@|$(KERNEL_BASE_VERSION)|g" \
		-e "s|@VARIANT@|$(VARIANT)|g" \
		-e "s|@FLASH_INFO_MANUFACTURER@|$(FLASH_INFO_MANUFACTURER)|g" \
		-e "s|@FLASH_INFO_MODEL@|$(FLASH_INFO_MODEL)|g" \
		-e "s|@FLASH_INFO_CPU@|$(FLASH_INFO_CPU)|g" \
		-e "s|@FLASH_INFO_DEVICE_IDS@|$(FLASH_INFO_DEVICE_IDS)|g" \
		/usr/share/linux-packaging-snippets/flash-bootimage-template.in \
			> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
else
	echo "FLASH_ENABLED=no" \
		> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
endif

	# Handle legacy devices
ifeq ($(FLASH_IS_LEGACY_DEVICE), 1)
	# Handle devices with capitalized partition names
ifeq ($(FLASH_IS_EXYNOS), 1)
	cat /usr/share/linux-packaging-snippets/flash-bootimage-template-legacy-exynos-extend.in \
		>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
else
	cat /usr/share/linux-packaging-snippets/flash-bootimage-template-legacy-extend.in \
		>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
endif
endif

	# Handle aonly devices
ifeq ($(FLASH_IS_AONLY), 1)
	# Handle devices with capitalized partition names
ifeq ($(FLASH_IS_EXYNOS), 1)
	cat /usr/share/linux-packaging-snippets/flash-bootimage-template-aonly-exynos-extend.in \
		>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
else
	cat /usr/share/linux-packaging-snippets/flash-bootimage-template-aonly-extend.in \
		>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf
endif
endif

	# Disable DTB Overlay flashing if this kernel doesn't support it
	# Use shell features to check
	if [ "$(KERNEL_IMAGE_WITH_DTB_OVERLAY)" != "1" ] || [ "$(KERNEL_IMAGE_WITH_DTB_OVERLAY_IN_KERNEL)" = "1" ]; then \
		cat /usr/share/linux-packaging-snippets/flash-bootimage-template-no-dtbo-extend.in \
			>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf; \
	fi

	# Disable VBMETA flashing if we don't supply any
	# Use shell features to check
	if [ "$(DEVICE_VBMETA_REQUIRED)" != "1" ]; then \
		cat /usr/share/linux-packaging-snippets/flash-bootimage-template-no-vbmeta.in \
			>> $(CURDIR)/debian/linux-bootimage-$(KERNEL_RELEASE)/lib/flash-bootimage/$(KERNEL_RELEASE).conf; \
	fi

	mkdir -p $(CURDIR)/debian/linux-headers-$(KERNEL_RELEASE)/lib/modules/$(KERNEL_RELEASE)
	/usr/share/linux-packaging-snippets/extract_headers.sh $(KERNEL_RELEASE) $(KERNEL_SOURCES) $(KERNEL_OUT) $(CURDIR)/debian/linux-headers-$(KERNEL_RELEASE) $(KERNEL_ARCH)

override_dh_auto_install: kernel_snippet_install

override_dh_auto_clean:
	rm -rf $(OUT)
	rm -rf debian/path-override
	rm -rf include/config/
	rm -f debian/linux-*.postinst
	dh_clean

override_dh_strip:

override_dh_auto_test:

.PHONY: path-override-prepare kernel_snippet_install
