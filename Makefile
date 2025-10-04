include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI app: Speedtest (server selection)
LUCI_DESCRIPTION:=LuCI interface for internet speed tests with server selection (Ookla/LibreSpeed/speedtestcpp)
LUCI_DEPENDS:=+luci-base +luci-compat +libuci-lua +luci-lib-jsonc +librespeed-cli-bin
LUCI_PKGARCH:=all
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Andrzej <andrzej@example.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
