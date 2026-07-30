include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI app for Harbor File
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-compat

PKG_NAME:=luci-app-harbor-file
PKG_VERSION:=1.0
PKG_RELEASE:=3

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
