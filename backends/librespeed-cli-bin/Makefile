include $(TOPDIR)/rules.mk

PKG_NAME:=librespeed-cli-bin
PKG_VERSION:=1.0.12
PKG_RELEASE:=1

PKG_LICENSE:=LGPL-3.0-or-later
PKG_MAINTAINER:=Andrzej Jablonski

# mapowanie architektury upstream → OpenWrt target (tu: aarch64 Filogic)
ifeq ($(ARCH_PACKAGES),aarch64_cortex-a53)
  UPSTREAM_ARCH:=linux_arm64
  PKG_HASH:=e8d6fb054aee8bbfcad8c9f70fc89e983800f64221cfbb9b62ba1842bfcad6d4
else
  $(error No upstream binary mapping for $(ARCH_PACKAGES))
endif

PKG_SOURCE:=librespeed-cli_$(PKG_VERSION)_$(UPSTREAM_ARCH).tar.gz
PKG_SOURCE_URL:=https://github.com/librespeed/speedtest-cli/releases/download/v$(PKG_VERSION)
PKG_BUILD_DIR:=$(BUILD_DIR)/librespeed-cli-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/librespeed-cli-bin
  SECTION:=net
  CATEGORY:=Network
  TITLE:=LibreSpeed CLI (prebuilt binary)
  URL:=https://github.com/librespeed/speedtest-cli
endef

define Build/Compile
  # nothing to compile
endef

define Package/librespeed-cli-bin/install
	$(INSTALL_DIR) $(1)/usr/local/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/librespeed-cli $(1)/usr/local/bin/librespeed-cli
endef

$(eval $(call BuildPackage,librespeed-cli-bin))
