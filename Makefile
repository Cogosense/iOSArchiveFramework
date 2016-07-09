SHELL = /bin/bash
NAME = libarchive
VERSION = 3.1.2
TARBALL = $(NAME)-$(VERSION).tar.gz
TOPDIR = $(CURDIR)
SRCDIR = $(NAME)-$(VERSION)
ARM_ARCH = arm-apple-darwin
X86_ARCH = i386-apple-darwin
FRAMEWORK_VERSION = A
FRAMEWORK_NAME = archive
FRAMEWORKDIR = $(FRAMEWORK_NAME).framework
DOWNLOAD_URL = http://www.libarchive.org/downloads/$(TARBALL)

define Info_plist
<?xml version="1.0" encoding="UTF-8"?>\n
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n
<plist version="1.0">\n
<dict>\n
\t<key>CFBundleDevelopmentRegion</key>\n
\t<string>English</string>\n
\t<key>CFBundleExecutable</key>\n
\t<string>$(FRAMEWORK_NAME)</string>\n
\t<key>CFBundleIdentifier</key>\n
\t<string>org.libarchive</string>\n
\t<key>CFBundleInfoDictionaryVersion</key>\n
\t<string>$(VERSION)</string>\n
\t<key>CFBundlePackageType</key>\n
\t<string>FMWK</string>\n
\t<key>CFBundleSignature</key>\n
\t<string>????</string>\n
\t<key>CFBundleVersion</key>\n
\t<string>$(VERSION)</string>\n
</dict>\n
</plist>\n
endef

all : env framework-build

distclean : clean
	$(RM) $(TARBALL)

clean : mostlyclean
	$(RM) -r $(FRAMEWORKDIR)

mostlyclean :
	$(RM) Info.plist
	$(RM) -r $(SRCDIR)

env:
	env

$(TARBALL) :
	curl --retry 10 -s -o $@ $(DOWNLOAD_URL) || $(RM) $@

$(SRCDIR)/configure : $(TARBALL)
	tar xf $(TARBALL)

$(SRCDIR)/$(ARM_ARCH)/Makefile : $(SRCDIR)/configure
	[ -d $(SRCDIR)/$(ARM_ARCH) ] || mkdir $(SRCDIR)/$(ARM_ARCH)
	cd $(SRCDIR)/$(ARM_ARCH) && \
	    ../configure \
		--prefix=/$(FRAMEWORKDIR) \
		--host=$(ARM_ARCH) \
		--disable-shared \
		-disable-bsdcpio \
		-disable-bsdtar \
		--without-bz2lib \
		--without-xml2 \
		--without-iconv \
		CC='xcrun --sdk iphoneos clang -fembed-bitcode -miphoneos-version-min=6.1 -arch armv7 -arch arm64' \
		CPP='xcrun --sdk iphoneos clang -arch arm -E' \
		AR='xcrun --sdk iphoneos ar' \
		LD='xcrun --sdk iphoneos ld' \
		LIPO='xcrun --sdk iphoneos lipo' \
		OTOOL='xcrun --sdk iphoneos otool' \
		STRIP='xcrun --sdk iphoneos strip' \
		NM='xcrun --sdk iphoneos nm' \
		LIBTOOL='xcrun --sdk iphoneos libtool'

$(SRCDIR)/$(X86_ARCH)/Makefile : $(SRCDIR)/configure
	[ -d $(SRCDIR)/$(X86_ARCH) ] || mkdir $(SRCDIR)/$(X86_ARCH)
	cd $(SRCDIR)/$(X86_ARCH) && \
	    ../configure \
		--prefix=/$(FRAMEWORKDIR) \
		--host=$(X86_ARCH) \
		--disable-shared \
		-disable-bsdcpio \
		-disable-bsdtar \
		--without-bz2lib \
		--without-xml2 \
		--without-iconv \
		CC='xcrun --sdk iphonesimulator clang -fembed-bitcode -miphoneos-version-min=6.1 -arch i386 -arch x86_64' \
		CPP='xcrun --sdk iphonesimulator clang -arch i386 -E' \
		AR='xcrun --sdk iphonesimulator ar' \
		LD='xcrun --sdk iphonesimulator ld' \
		LIPO='xcrun --sdk iphonesimulator lipo' \
		OTOOL='xcrun --sdk iphonesimulator otool' \
		STRIP='xcrun --sdk iphonesimulator strip' \
		NM='xcrun --sdk iphonesimulator nm' \
		LIBTOOL='xcrun --sdk iphonesimulator libtool'

export Info_plist

Info.plist : Makefile
	echo -e $$Info_plist > $@

arm : $(SRCDIR)/$(ARM_ARCH)/$(FRAMEWORKDIR)
x86 : $(SRCDIR)/$(X86_ARCH)/$(FRAMEWORKDIR)

framework-build: arm x86 $(FRAMEWORKDIR).tar.bz2

#
# The framework-no-build target is used by Jenkins to assemble
# the results of the individual architectures built in parallel.
#
# The pipeline stash/unstash feature is used to assemble the build
# results from each parallel phase.
#
# This target depends on a built file in each framework bundle,
# if it is missing then the build fails as the master has no
# rules to build it.
#
framework-no-build: \
	$(SRCDIR)/$(ARM_ARCH)/$(FRAMEWORKDIR)/lib/lib$(FRAMEWORK_NAME).a \
	$(SRCDIR)/$(X86_ARCH)/$(FRAMEWORKDIR)/lib/lib$(FRAMEWORK_NAME).a \
	$(FRAMEWORKDIR).tar.bz2

$(SRCDIR)/$(ARM_ARCH)/$(FRAMEWORKDIR) : $(SRCDIR)/$(ARM_ARCH)/Makefile
	make -C $(SRCDIR)/$(ARM_ARCH) DESTDIR=$(TOPDIR)/$(SRCDIR)/$(ARM_ARCH) install

$(SRCDIR)/$(X86_ARCH)/$(FRAMEWORKDIR) : $(SRCDIR)/$(X86_ARCH)/Makefile
	make -C $(SRCDIR)/$(X86_ARCH) DESTDIR=$(TOPDIR)/$(SRCDIR)/$(X86_ARCH) install

$(FRAMEWORKDIR) : Info.plist
	$(RM) -r $(FRAMEWORKDIR)
	mkdir $(FRAMEWORKDIR)
	cd $(FRAMEWORKDIR) && set -e ; \
	mkdir Versions ; \
	mkdir Versions/$(FRAMEWORK_VERSION) ; \
	mkdir Versions/$(FRAMEWORK_VERSION)/Resources ; \
	cp $(TOPDIR)/Info.plist Versions/$(FRAMEWORK_VERSION)/Resources/ ; \
	cp -R $(TOPDIR)/$(SRCDIR)/$(ARM_ARCH)/$(FRAMEWORKDIR)/include Versions/$(FRAMEWORK_VERSION)/Headers ; \
	cp -R $(TOPDIR)/$(SRCDIR)/$(ARM_ARCH)/$(FRAMEWORKDIR)/share Versions/$(FRAMEWORK_VERSION)/Documentation ; \
	xcrun -sdk iphoneos lipo -create \
	    $(TOPDIR)/$(SRCDIR)/$(ARM_ARCH)/$(FRAMEWORKDIR)/lib/libarchive.a \
	    $(TOPDIR)/$(SRCDIR)/$(X86_ARCH)/$(FRAMEWORKDIR)/lib/libarchive.a \
	    -o Versions/$(FRAMEWORK_VERSION)/$(FRAMEWORK_NAME) ; \
	ln -s $(FRAMEWORK_VERSION) Versions/Current ; \
	ln -s Versions/Current/Headers Headers ; \
	ln -s Versions/Current/Resources Resources ; \
	ln -s Versions/Current/Documentation Documentation ; \
	ln -s Versions/Current/$(FRAMEWORK_NAME) $(FRAMEWORK_NAME)

$(FRAMEWORKDIR).tar.bz2 : $(FRAMEWORKDIR)
	$(RM) -f $(FRAMEWORKDIR).tar.bz2
	tar -cjf $(FRAMEWORKDIR).tar.bz2 $(FRAMEWORKDIR)

