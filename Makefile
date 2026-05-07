TOPDIR:=${CURDIR}
SOURCE_DIR:=$(TOPDIR)/trunk
TOOLCHAIN_DIR:=$(TOPDIR)/toolchain-mipsel
TOOLCHAIN_ROOT:=$(TOOLCHAIN_DIR)/toolchain-4.4.x
TOOLCHAIN_URL_PRIMARY:=https://github.com/HiGarfield/padavan-4.4/releases/download/toolchain/mipsel-linux-uclibc-gcc10.tar.xz
TOOLCHAIN_URL_FALLBACK_1:=https://github.com/tsl0922/padavan/releases/download/toolchain/mipsel-linux-uclibc.tar.xz
TOOLCHAIN_URL_FALLBACK_2:=https://github.com/tsl0922/padavan/releases/download/toolchain/mipsel-linux-uclibc-gcc-12.3.0.tar.xz
TOOLCHAIN_URLS:=$(TOOLCHAIN_URL_PRIMARY) $(TOOLCHAIN_URL_FALLBACK_1) $(TOOLCHAIN_URL_FALLBACK_2)
TOOLCHAIN_GCC:=$(TOOLCHAIN_ROOT)/bin/mipsel-linux-uclibc-gcc
TEMPLATE_DIR:=$(SOURCE_DIR)/configs/templates
PRODUCTS:=$(shell ls $(TEMPLATE_DIR) | sed 's/.config//g')
CONFIG:=$(SOURCE_DIR)/.config

all: build

toolchain/build:
	@echo "Building toolchain..."
	@(cd $(TOOLCHAIN_DIR); \
		./bootstrap && \
		./configure --enable-local && \
		make && \
		./ct-ng mipsel-linux-uclibc && \
		./ct-ng build \
	)

toolchain/clean:
	@(cd $(TOOLCHAIN_DIR); \
		if [ -f ct-ng ]; then ./ct-ng distclean; fi; \
		if [ -f Makefile ]; then make distclean; fi; \
		if [ -d $(TOOLCHAIN_ROOT) ]; then rm -rf $(TOOLCHAIN_ROOT); fi \
	)

toolchain/download:
	@if [ ! -x $(TOOLCHAIN_GCC) ]; then \
		echo "Downloading toolchain..."; \
		tmp_dir="$$(mktemp -d)"; \
		download_ok=0; \
		for url in $(TOOLCHAIN_URLS); do \
			echo "Trying $$url"; \
			if curl -fL --retry 3 --retry-delay 2 -o "$$tmp_dir/toolchain.tar.xz" "$$url"; then \
				mkdir -p "$$tmp_dir/extract"; \
				if tar Jxf "$$tmp_dir/toolchain.tar.xz" -C "$$tmp_dir/extract"; then \
					rm -rf $(TOOLCHAIN_ROOT); \
					mkdir -p $(TOOLCHAIN_ROOT); \
					cp -a "$$tmp_dir/extract"/. $(TOOLCHAIN_ROOT)/; \
					if [ -x $(TOOLCHAIN_GCC) ]; then \
						download_ok=1; \
						break; \
					fi; \
				fi; \
			fi; \
			rm -rf "$$tmp_dir/extract" "$$tmp_dir/toolchain.tar.xz"; \
		done; \
		rm -rf "$$tmp_dir"; \
		if [ $$download_ok -ne 1 ]; then \
			echo "Failed to download a valid toolchain from all configured URLs."; \
			exit 1; \
		fi; \
	fi

build: toolchain/download
	@if [ ! -f $(CONFIG) ]; then \
		echo "Please run 'make PRODUCT_NAME' to start build!"; \
		echo "Supported products: $(PRODUCTS)"; \
		exit 1; \
	fi
	$(MAKE) -C $(SOURCE_DIR)

clean:
	@if [ ! -f $(CONFIG) ]; then \
		echo "Project config file .config not found! Terminate."; \
		exit 1; \
	fi
	$(MAKE) -C $(SOURCE_DIR) clean
	@rm -f $(CONFIG)

.PHONY: $(PRODUCTS)
$(PRODUCTS):
	cp -f $(TEMPLATE_DIR)/$(@).config $(CONFIG)
	@echo "CONFIG_CROSS_COMPILER_ROOT=$(TOOLCHAIN_ROOT)" >> $(CONFIG)
	@echo "CONFIG_CCACHE=y" >> $(CONFIG)
	@make build
