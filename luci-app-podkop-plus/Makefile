include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-podkop-plus

PODKOP_BASE_VERSION:=$(or $(PODKOP_BASE_VERSION),$(PODKOP_VERSION),0.7.14)
PODKOP_FORK_RELEASE:=$(or $(PODKOP_FORK_RELEASE),1)
PODKOP_PACKAGE_VERSION:=$(PODKOP_BASE_VERSION)-$(PODKOP_FORK_RELEASE)

PKG_VERSION:=$(PODKOP_PACKAGE_VERSION)
PKG_RELEASE:=
PKG_PO_VERSION:=$(PODKOP_PACKAGE_VERSION)

LUCI_TITLE:=LuCI Podkop Plus app
LUCI_DEPENDS:=+luci-base +sing-box +curl +jq +kmod-nft-tproxy +coreutils-base64 +bind-dig +nftables +kmod-nft-nat +kmod-nft-offload +kmod-nft-queue +libnetfilter-queue +libmnl +libcap +zlib +gzip +coreutils +coreutils-sort +coreutils-sleep
LUCI_PKGARCH:=all
LUCI_LANG.ru:=Русский (Russian)
LUCI_LANG.en:=English
LUCI_MAINTAINER:=ushan0v <ushan0v@users.noreply.github.com>

PKG_LICENSE:=GPL-2.0-or-later
LUCI_LANGUAGES:=en ru

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/description
	Rule-based Podkop Plus LuCI app with hybrid sing-box + zapret orchestration
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh

grep -q "105 podkopplus" /etc/iproute2/rt_tables && sed -i "/105 podkopplus/d" /etc/iproute2/rt_tables

/etc/init.d/podkop-plus stop >/dev/null 2>&1 || true

exit 0
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/podkop_plus
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)$(HTDOCS)/luci-static/resources/view/podkop_plus
	$(CP) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/podkop/* $(1)$(HTDOCS)/luci-static/resources/view/podkop_plus/
	$(INSTALL_DIR) $(1)/
	$(CP) $(PKG_BUILD_DIR)/root/* $(1)/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ../podkop/files/etc/init.d/podkop $(1)/etc/init.d/podkop-plus
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ../podkop/files/etc/config/podkop $(1)/etc/config/podkop_plus
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ../podkop/files/usr/bin/podkop $(1)/usr/bin/podkop-plus
	$(INSTALL_DIR) $(1)/usr/lib/podkop-plus
	$(CP) ../podkop/files/usr/lib/* $(1)/usr/lib/podkop-plus/
	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(PODKOP_PACKAGE_VERSION)/g' $(1)$(HTDOCS)/luci-static/resources/view/podkop_plus/main.js || true
	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(PODKOP_PACKAGE_VERSION)/g' $(1)/usr/lib/podkop-plus/constants.sh || true
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
