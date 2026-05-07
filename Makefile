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
		stage_dir="$(TOOLCHAIN_DIR)/.toolchain-staging.$$$$"; \
		download_ok=0; \
		attempted_urls=""; \
		for url in $(TOOLCHAIN_URLS); do \
			if [ -z "$$attempted_urls" ]; then \
				attempted_urls="$$url"; \
			else \
				attempted_urls="$$attempted_urls, $$url"; \
			fi; \
			echo "Trying $$url"; \
			if curl -fL --retry 3 --retry-delay 2 -o "$$tmp_dir/toolchain.tar.xz" "$$url"; then \
				rm -rf "$$tmp_dir/extract"; \
				mkdir -p "$$tmp_dir/extract"; \
				if tar Jxf "$$tmp_dir/toolchain.tar.xz" -C "$$tmp_dir/extract"; then \
					toolchain_src="$$tmp_dir/extract"; \
					if [ ! -x "$$toolchain_src/bin/mipsel-linux-uclibc-gcc" ]; then \
						candidate_gccs="$$(find "$$tmp_dir/extract" -type f -path '*/bin/mipsel-linux-uclibc-gcc')"; \
						candidate_count="$$(printf '%s\n' "$$candidate_gccs" | sed '/^$$/d' | wc -l)"; \
						candidate_gcc="$$(printf '%s\n' "$$candidate_gccs" | head -n 1)"; \
						if [ "$$candidate_count" -eq 1 ] && [ -n "$$candidate_gcc" ]; then \
							toolchain_src="$$(dirname "$$(dirname "$$candidate_gcc")")"; \
						elif [ "$$candidate_count" -gt 1 ]; then \
							echo "Skip $$url: multiple toolchain roots found in archive, trying next URL."; \
							continue; \
						else \
							echo "Skip $$url: toolchain compiler not found in archive, trying next URL."; \
							continue; \
						fi; \
					fi; \
					rm -rf "$$stage_dir"; \
					mkdir -p "$$stage_dir"; \
					cp -a "$$toolchain_src"/. "$$stage_dir"/; \
					if [ -x "$$stage_dir/bin/mipsel-linux-uclibc-gcc" ]; then \
						rm -rf $(TOOLCHAIN_ROOT); \
						mv "$$stage_dir" $(TOOLCHAIN_ROOT); \
						if [ -x $(TOOLCHAIN_GCC) ]; then \
							download_ok=1; \
							break; \
						fi; \
					fi; \
				fi; \
			fi; \
			rm -rf "$$tmp_dir/extract" "$$tmp_dir/toolchain.tar.xz"; \
		done; \
		rm -rf "$$tmp_dir" "$$stage_dir"; \
		if [ $$download_ok -ne 1 ]; then \
			echo "Failed to download a valid toolchain from all configured URLs. Tried: $$attempted_urls"; \
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
