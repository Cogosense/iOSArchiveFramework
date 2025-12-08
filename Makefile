#
# supports architectures arm64, x86_64 and bitcode
#
# make - build a fat archive framework using $ARCHS, if $ARCHS is empty all architectures are built (device and simulator)
#                   \
# make ARCHS=x86_64  |
#                     > build a thin archive framework with named architecture
#                    |
# make ARCHS=arm64  /
# make ARCHS='x86_64' - bulid a fat archive framework with only the named architectures
#
# From xcode build script:
# make ARCHS=${ARCHS} - build all active architectures
#
# Xcode bitcode support:
# make ARCHS="arm64" ENABLE_BITCODE=YES BITCODE_GENERATION_MODE=bitcode - create bitcode
# make ARCHS="arm64" ENABLE_BITCODE=YES BITCODE_GENERATION_MODE=marker - add bitcode marker (but no real bitcode)
#
# The ENABLE_BITCODE and BITCODE_GENERATION_MODE flags are set in the Xcode project settings
#

SHELL = /bin/bash

V ?= 0
at = @
ifeq ($(V),1)
	at =
endif

MACOS_MIN_VERSION = 10.13
IOS_MIN_VERSION = 11.0

#
# Repository info
#
GITBRANCH ?= $(shell which git > /dev/null && git rev-parse --abbrev-ref --verify -q HEAD || echo "unknown")
GITCOMMIT ?= $(shell which git > /dev/null && git rev-parse --verify -q HEAD || echo "unknown")

#
# library distribution to be built
DIST_NAME = libarchive
DIST_VERSION = 3.8.0

#
# Release version on GitHub - bump last digit to make new
# GitHub release with same distribution version.
NAME = archive
VERSION =  3.8.0

#
# Download location URL
#
TARBALL = $(DIST_NAME)-$(DIST_VERSION).tar.gz
DOWNLOAD_URL = http://www.libarchive.org/downloads/$(TARBALL)

#
# Files used to trigger builds for each architecture
# TARGET_BUILD_LIB file under install prefix that can be built directly
# TARGET_NOBUILD_ARTIFACT file under install prefix that is built indirectly
#
INSTALLED_LIB = /lib/libarchive.a
INSTALLED_HEADER_DIR = /include

#
# Output framework name
#
FRAMEWORK_NAME = $(NAME)

#
# The supported Xcode SDKs
#
MACOSX_SDK = macosx
IPHONEOS_SDK = iphoneos
IPHONESIMULATOR_SDK = iphonesimulator

#
# The supported build target os
#
MACOSX_TARGET = apple-darwin
IPHONEOS_TARGET = apple-ios
IPHONESIMULATOR_TARGET = apple-iossim

#
# The supported build target architecture
#
ARM64_TARGET = aarch64
X86_64_TARGET = x86_64

#
# The supported Xcode build architectures
#
ARM_64_ARCH = arm64
X86_64_ARCH = x86_64

#
# SDK platform version
#
IPHONESIMULATOR_SDK_PLATFORM_VERSION = $(shell xcrun --sdk $(IPHONESIMULATOR_SDK) --show-sdk-platform-version)

#
# set or unset warning flags
#
WFLAGS = -Wno-tautological-pointer-compare -Wno-deprecated-declarations
EXTRA_CFLAGS =
EXTRA_CXXFLAGS = -stdlib=libc++ -std=c++17
EXTRA_CPPFLAGS =
EXTRA_LDFLAGS = -Z -L/usr/lib
EXTRA_CONFIGURE_ARGS =

#
# enable bitcode support
#
ifeq "$(ENABLE_BITCODE)" "YES"
    ifeq "$(BITCODE_GENERATION_MODE)" "marker"
	XCODE_BITCODE_FLAG = -fembed-bitcode-marker
    endif
    ifeq "$(BITCODE_GENERATION_MODE)" "bitcode"
	XCODE_BITCODE_FLAG = -fembed-bitcode
    endif
endif

#
# SDK_NAME, ARCHS and BUILT_PRODUCTS_DIR are set by xcode
# only set them if make is invoked directly
#
# build for device or simulator
ifneq ($(findstring $(IPHONEOS_SDK), $(SDK_NAME)),)
	SDK = $(IPHONEOS_SDK)
else ifneq ($(findstring $(IPHONESIMULATOR_SDK), $(SDK_NAME)),)
	SDK = $(IPHONESIMULATOR_SDK)
else ifneq ($(findstring $(MACOSX_SDK), $(SDK_NAME)),)
	SDK = $(MACOSX_SDK)
else ifneq ($(SDK_NAME),)
	SDK = $(SDK_NAME)
else
	SDK = $(IPHONEOS_SDK)
endif

# build for device or simulator
ifeq ($(SDK),$(IPHONEOS_SDK))
	ARCHS ?= $(ARM_64_ARCH)
	#
	# set minimum iOS version supported
	#
	ifneq "$(IPHONEOS_DEPLOYMENT_TARGET)" ""
    		MIN_OS_VER = $(IPHONEOS_DEPLOYMENT_TARGET)
	else
    		MIN_OS_VER = $(IOS_MIN_VERSION)
	endif
else ifeq ($(SDK),$(IPHONESIMULATOR_SDK))
	# MacOSX Tahoe removed support for all but one Intel Mac.
	# Tahoe shipped with SDK26.1, x86_64 simulator can still be built
	# but is no longer supported (discouraged) by Apple. Older SDK's
	# will still build it.
	ifeq ($(shell expr $(IPHONESIMULATOR_SDK_PLATFORM_VERSION) \>= 26),1)
		ARCHS ?= $(ARM_64_ARCH)
	else
		ARCHS ?= $(ARM_64_ARCH) $(X86_64_ARCH)
	endif
	#
	# set minimum iOS version supported
	#
	ifneq "$(IPHONEOS_DEPLOYMENT_TARGET)" ""
    		MIN_OS_VER = $(IPHONEOS_DEPLOYMENT_TARGET)
	else
    		MIN_OS_VER = $(IOS_MIN_VERSION)
	endif
else ifeq ($(SDK),$(MACOSX_SDK))
	#
	# set minimum MacOSX version supported
	#
	ifneq "$(MACOXS_DEPLOYMENT_TARGET)" ""
		MIN_OS_VER = $(MACOSX_DEPLOYMENT_TARGET)
	else
		MIN_OS_VER = $(MACOS_MIN_VERSION)
	endif
	ARCHS ?= $(ARM_64_ARCH) $(X86_64_ARCH)
else
	$(error unsupported sdk: $(SDK))
endif

BUILT_PRODUCTS_DIR ?= $(CURDIR)/build

MAKER_DIR = $(BUILT_PRODUCTS_DIR)/Maker
MAKER_ARCHIVES_DIR = $(MAKER_DIR)/Archives
MAKER_SOURCES_DIR = $(MAKER_DIR)/Sources
MAKER_BUILD_DIR = $(MAKER_DIR)/Build
MAKER_BUILDROOT_DIR = $(MAKER_DIR)/Buildroot
MAKER_INTERMEDIATE_DIR = $(MAKER_DIR)/Intermediate

PKGSRCDIR = $(MAKER_SOURCES_DIR)/$(DIST_NAME)-$(DIST_VERSION)

FRAMEWORKBUNDLE = $(FRAMEWORK_NAME).framework
XCFRAMEWORKBUNDLE = $(FRAMEWORK_NAME).xcframework

empty:=
space:= $(empty) $(empty)
comma:= ,

.PHONY : \
	all \
	build \
	install \
	carthage \
	clean \
	build-commence \
	build-complete \
	install-commence i\
	nstall-complete \
	dirs \
	tarball \
	configure \
	makefiles \
	$(addprefix Makefile_$(SDK)_, $(ARCHS)) \
	builds \
	$(addprefix Build_$(SDK)_, $(ARCHS))

all : build

build : build-commence dirs tarball configure makefiles builds bundle build-complete

install : install-commence dirs tarball configure makefiles builds bundle install-complete

carthage:
	carthage build --no-skip-current
	carthage archive

clean :
	$(RM) -r $(BUILT_PRODUCTS_DIR)
	$(RM) -r DerivedData
	$(RM) -r Carthage
	$(RM) *.xcframework.tar.gz
	$(RM) *.xcframework.tar.bz2
	$(RM) *.xcframework.tar.zip
	$(RM) Info.plist

build-commence :
	@echo "Commencing debug build for SDK:$(SDK) ARCHS:\"$(ARCHS)\" framework: $(FRAMEWORK_NAME)"

build-complete :
	@echo "Completed debug build for SDK:$(SDK) ARCHS:\"$(ARCHS)\" framework: $(FRAMEWORK_NAME)"

install-commence :
	@echo "Commencing release build for SDK:$(SDK) ARCHS:\"$(ARCHS)\" framework: $(FRAMEWORK_NAME)"

install-complete :
	@echo "Completed release build for SDK:$(SDK) ARCHS:\"$(ARCHS)\" framework: $(FRAMEWORK_NAME)"

dirs : $(MAKER_ARCHIVES_DIR) $(MAKER_SOURCES_DIR) $(MAKER_BUILD_DIR) $(MAKER_BUILDROOT_DIR) $(MAKER_INTERMEDIATE_DIR)

$(MAKER_ARCHIVES_DIR) $(MAKER_SOURCES_DIR) $(MAKER_BUILD_DIR) $(MAKER_BUILDROOT_DIR) $(MAKER_INTERMEDIATE_DIR) :
	@mkdir -p $@

tarball : dirs $(MAKER_ARCHIVES_DIR)/$(TARBALL)

$(MAKER_ARCHIVES_DIR)/$(TARBALL) :
	@echo "downloading $(DOWNLOAD_URL)"
	$(at)curl -L --retry 10 --retry-delay 12 -s -o $@ $(DOWNLOAD_URL) || { \
	    $(RM) $@ ; \
	    exit 1 ; \
	}

configure : dirs tarball $(PKGSRCDIR)/configure

$(PKGSRCDIR)/configure :
	tar -C $(MAKER_SOURCES_DIR) -xf $(MAKER_ARCHIVES_DIR)/$(TARBALL)
	if [ -d patches/$(VERSION) ] ; then \
		for p in patches/$(VERSION)/*.patch ; do \
			if [ -f $$p ] ; then \
				patch -d $(PKGSRCDIR) -p1 < $$p ; \
			fi ; \
		done ; \
	fi

makefiles : dirs tarball configure $(addprefix Makefile_$(SDK)_, $(ARCHS))

builds : dirs tarball configure makefiles $(addprefix Build_$(SDK)_, $(ARCHS))

#
# $1 - sdk (iphoneos or iphonesimulator)
# $2 - xcode architecture (arm64, x86_64)
# $3 - target toolchain os name
# $4 - target toolchain architecture name
#
define configure_template

Makefile_$(1)_$(2) : $(MAKER_BUILD_DIR)/$(1)/$(2) $(MAKER_BUILD_DIR)/$(1)/$(2)/Makefile

$(MAKER_BUILD_DIR)/$(1)/$(2) :
	$(at)mkdir -p $$@

$(MAKER_BUILD_DIR)/$(1)/$2/Makefile :
	$(at)builddir="$(MAKER_BUILD_DIR)/$(1)/$(2)" ; \
	installdir="$(MAKER_BUILDROOT_DIR)/$(1)/$(2)/$(FRAMEWORKBUNDLE)" ; \
	cd $$$$builddir && \
	    $(PKGSRCDIR)/configure \
		--prefix=/$$(FRAMEWORKBUNDLE) \
		--host=$(4)-$(3) \
		--disable-shared \
		--disable-bsdcpio \
		--disable-bsdtar \
		--without-bz2lib \
		--without-xml2 \
		--without-iconv \
		$$(EXTRA_CONFIGURE_ARGS) \
		CC='xcrun --sdk $(1) clang -arch $(2)' \
		CFLAGS='$(EXTRA_CFLAGS) $(EXTRA_CPPFLAGS) -m$(1)-version-min=$$(MIN_OS_VER) $$(XCODE_BITCODE_FLAG) $$(WFLAGS)' \
		CXXFLAGS='$(EXTRA_CXXFLAGS) $(EXTRA_CPPFLAGS) -m$(1)-version-min=$$(MIN_OS_VER) $$(XCODE_BITCODE_FLAG) $$(WFLAGS)' \
		LDFLAGS='$(EXTRA_LDFLAGS)' \
		CPP='xcrun --sdk $(1) clang -arch $(2) -E' \
		AR='xcrun --sdk $(1) ar' \
		LD='xcrun --sdk $(1) ld' \
		LIPO='xcrun --sdk $(1) lipo' \
		OTOOL='xcrun --sdk $(1) otool' \
		STRIP='xcrun --sdk $(1) strip' \
		NM='xcrun --sdk $(1) nm' \
		LIBTOOL='xcrun --sdk $(1) libtool'

Build_$(1)_$(2) : $(MAKER_BUILDROOT_DIR)/$(1)/$(2)/$(FRAMEWORKBUNDLE)$(INSTALLED_LIB)

$(MAKER_BUILDROOT_DIR)/$(1)/$(2)/$(FRAMEWORKBUNDLE)$(INSTALLED_LIB) :
	$(at)$(MAKE) -C $(MAKER_BUILD_DIR)/$(1)/$(2) DESTDIR=$(MAKER_BUILDROOT_DIR)/$(1)/$(2) LIBTOOLFLAGS=--no-warn install

endef

$(eval $(call configure_template,$(MACOSX_SDK),$(ARM_64_ARCH),$(MACOSX_TARGET),$(ARM64_TARGET)))
$(eval $(call configure_template,$(MACOSX_SDK),$(X86_64_ARCH),$(MACOSX_TARGET),$(X86_64_TARGET)))
$(eval $(call configure_template,$(IPHONEOS_SDK),$(ARM_64_ARCH),$(IPHONEOS_TARGET),$(ARM64_TARGET)))
$(eval $(call configure_template,$(IPHONESIMULATOR_SDK),$(ARM_64_ARCH),$(IPHONESIMULATOR_TARGET),$(ARM64_TARGET)))
$(eval $(call configure_template,$(IPHONESIMULATOR_SDK),$(X86_64_ARCH),$(IPHONESIMULATOR_TARGET),$(X86_64_TARGET)))

FIRST_ARCH = $(firstword $(ARCHS))

.PHONY : bundle-dirs bundle-headers bundle-rm-fat-library bundle-info

SDK_DIR = $(MAKER_INTERMEDIATE_DIR)/$(SDK)
SDK_FRAMEWORK_DIR = $(SDK_DIR)/$(FRAMEWORKBUNDLE)

bundle : \
	bundle-dirs \
	bundle-headers \
	bundle-rm-fat-library \
	$(SDK_FRAMEWORK_DIR)/$(FRAMEWORK_NAME) \
	bundle-info \
	$(SDK_DIR)/$(FRAMEWORKBUNDLE).zip

FRAMEWORK_DIRS = \
	$(SDK_FRAMEWORK_DIR) \
	$(SDK_FRAMEWORK_DIR)/Resources \
	$(SDK_FRAMEWORK_DIR)/Headers \
	$(SDK_FRAMEWORK_DIR)/Documentation \
	$(SDK_FRAMEWORK_DIR)/Modules

bundle-dirs : $(FRAMEWORK_DIRS)

$(FRAMEWORK_DIRS) :
	@mkdir -p $@

bundle-headers : bundle-dirs
	$(at)rsync -r -u $(MAKER_BUILDROOT_DIR)/$(SDK)/$(FIRST_ARCH)/$(FRAMEWORKBUNDLE)$(INSTALLED_HEADER_DIR)/* $(SDK_FRAMEWORK_DIR)/Headers

$(SDK_FRAMEWORK_DIR)/Info.plist :
	$(at)cp $(FRAMEWORK_NAME)/Info.plist $@
	$(at)/usr/libexec/plistbuddy -c "Set:CFBundleDevelopmentRegion English" $@
	$(at)/usr/libexec/plistbuddy -c "Set:CFBundleExecutable $(NAME)" $@
	$(at)/usr/libexec/plistbuddy -c "Set:CFBundleName $(FRAMEWORK_NAME)" $@
	$(at)/usr/libexec/plistbuddy -c "Set:CFBundleIdentifier com.cogosense.$(NAME)" $@

bundle-info : $(SDK_FRAMEWORK_DIR)/Info.plist
	$(at)verCode=$$(git tag -l '[0-9]*\.[0-9]*\.[0-9]' | wc -l) ; \
	verStr=$$(git describe --match '[0-9]*\.[0-9]*\.[0-9]' --always) ; \
	/usr/libexec/plistbuddy -c "Set:CFBundleShortVersionString $${verStr}" $< ; \
	/usr/libexec/plistbuddy -c "Set:CFBundleVersion $${verCode}" $<
	$(at)plutil -convert binary1 $<

bundle-rm-fat-library :
	$(at)$(RM) $(SDK_FRAMEWORK_DIR)/$(FRAMEWORK_NAME)

$(SDK_FRAMEWORK_DIR)/$(FRAMEWORK_NAME) : $(addprefix $(MAKER_BUILDROOT_DIR)/$(SDK)/, $(addsuffix /$(FRAMEWORKBUNDLE)$(INSTALLED_LIB),$(ARCHS)))
	$(at)mkdir -p $(@D)
	$(at)xcrun -sdk $(SDK) lipo -create $^ -o $@

$(SDK_DIR)/$(FRAMEWORKBUNDLE).zip : $(SDK_DIR)/$(FRAMEWORKBUNDLE)
	@echo "creating $@"
	$(at)(cd $(SDK_DIR) && zip -qr $(FRAMEWORKBUNDLE).zip $(FRAMEWORKBUNDLE)) || exit $?
	@echo "$(FRAMEWORKBUNDLE) for $(SDK) saved to archive $@"

.PHONY : xcframework
xcframework : $(BUILT_PRODUCTS_DIR)/$(XCFRAMEWORKBUNDLE) $(XCFRAMEWORKBUNDLE).tar.gz  $(XCFRAMEWORKBUNDLE).tar.bz2 $(XCFRAMEWORKBUNDLE).zip

$(BUILT_PRODUCTS_DIR)/$(XCFRAMEWORKBUNDLE) : $(wildcard $(MAKER_INTERMEDIATE_DIR)/*/$(FRAMEWORKBUNDLE))
	$(at)$(RM) -r $@
	$(at)xcodebuild -create-xcframework -output $@ $(addprefix -framework , $^)

$(XCFRAMEWORKBUNDLE).tar.gz : $(BUILT_PRODUCTS_DIR)/$(XCFRAMEWORKBUNDLE)
	@echo "creating $@"
	$(at)tar -C $(BUILT_PRODUCTS_DIR) -czf $(XCFRAMEWORKBUNDLE).tar.gz $(XCFRAMEWORKBUNDLE)
	@echo "$(XCFRAMEWORKBUNDLE) saved to archive $@"

$(XCFRAMEWORKBUNDLE).tar.bz2 : $(BUILT_PRODUCTS_DIR)/$(XCFRAMEWORKBUNDLE)
	@echo "creating $@"
	$(at)tar -C $(BUILT_PRODUCTS_DIR) -cjf $(XCFRAMEWORKBUNDLE).tar.bz2 $(XCFRAMEWORKBUNDLE)
	@echo "$(XCFRAMEWORKBUNDLE) saved to archive $@"

$(XCFRAMEWORKBUNDLE).zip : $(BUILT_PRODUCTS_DIR)/$(XCFRAMEWORKBUNDLE)
	@echo "creating $@"
	$(at)(cd $(BUILT_PRODUCTS_DIR) && zip -qr ../$(XCFRAMEWORKBUNDLE).zip $(XCFRAMEWORKBUNDLE)) || exit $?
	@echo "$(XCFRAMEWORKBUNDLE) saved to archive $@"

.PHONY : release

version :
	@echo $(VERSION)

release : notes/RELNOTES-$(VERSION) $(XCFRAMEWORKBUNDLE).tar.gz $(XCFRAMEWORKBUNDLE).tar.bz2 $(XCFRAMEWORKBUNDLE).zip
	$(at)if [ $(GITBRANCH) == 'master' ] ; then \
		if ! gh release view $(VERSION)  > /dev/null 2>&1 ; then \
			echo "creating release $(VERSION)" ; \
			git tag -am "Release $(NAME) for iOS/MacOS $(VERSION)" $(VERSION) ; \
			git push origin HEAD:master --follow-tags ; \
			gh release create "$(VERSION)" \
				--verify-tag \
				--generate-notes \
				-F notes/RELNOTES-$(VERSION) \
				$(XCFRAMEWORKBUNDLE).tar.gz $(XCFRAMEWORKBUNDLE).tar.bz2 $(XCFRAMEWORKBUNDLE).zip \
				$(MAKER_INTERMEDIATE_DIR)/$(IPHONEOS_SDK)/$(FRAMEWORKBUNDLE).zip ; \
		else \
			echo "warning: $(NAME) $(VERSION) has already been created: skipping release" ; \
		fi ; \
	fi
