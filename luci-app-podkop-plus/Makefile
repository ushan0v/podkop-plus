include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-podkop-plus

PODKOP_RELEASE_VERSION:=$(or $(PODKOP_PACKAGE_VERSION),$(PODKOP_VERSION),0.7.17-4)
PODKOP_BASE_VERSION:=$(or $(PODKOP_BASE_VERSION),$(word 1,$(subst -, ,$(PODKOP_RELEASE_VERSION))))
PODKOP_FORK_RELEASE:=$(or $(PODKOP_FORK_RELEASE),$(word 2,$(subst -, ,$(PODKOP_RELEASE_VERSION))),4)
PODKOP_COMPILED_VERSION:=$(PODKOP_BASE_VERSION)-$(PODKOP_FORK_RELEASE)
PODKOP_APK_VERSION:=$(PODKOP_BASE_VERSION)-r$(PODKOP_FORK_RELEASE)
PODKOP_PO_VERSION:=$(if $(filter apk,$(PODKOP_PACKAGE_FORMAT)),$(PODKOP_APK_VERSION),$(PODKOP_COMPILED_VERSION))
PODKOP_SDK_VERSION:=$(if $(filter apk,$(PODKOP_PACKAGE_FORMAT)),$(PODKOP_BASE_VERSION),$(PODKOP_COMPILED_VERSION))
PODKOP_SDK_RELEASE:=$(if $(filter apk,$(PODKOP_PACKAGE_FORMAT)),$(PODKOP_FORK_RELEASE),)

PKG_VERSION:=$(PODKOP_SDK_VERSION)
PKG_RELEASE:=$(PODKOP_SDK_RELEASE)
PKG_PO_VERSION:=$(PODKOP_PO_VERSION)

LUCI_TITLE:=LuCI Podkop Plus app
LUCI_DEPENDS:=+luci-base +podkop-plus
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

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)$(HTDOCS)/luci-static/resources/view/podkop_plus
	$(CP) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/podkop/* $(1)$(HTDOCS)/luci-static/resources/view/podkop_plus/
	$(INSTALL_DIR) $(1)/
	$(CP) $(PKG_BUILD_DIR)/root/* $(1)/
	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(PODKOP_COMPILED_VERSION)/g' $(1)$(HTDOCS)/luci-static/resources/view/podkop_plus/main.js || true
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
