# This Makefile is meant to be used by people that do not usually work
# with Go source code. If you know what GOPATH is then you probably
# don't need to bother with make.

.PHONY: geth android ios geth-cross swarm evm all test clean
.PHONY: geth-linux geth-linux-386 geth-linux-amd64 geth-linux-mips64 geth-linux-mips64le
.PHONY: geth-linux-arm geth-linux-arm-5 geth-linux-arm-6 geth-linux-arm-7 geth-linux-arm64
.PHONY: geth-darwin geth-darwin-386 geth-darwin-amd64
.PHONY: geth-windows geth-windows-386 geth-windows-amd64

GOBIN = $(shell pwd)/build/bin
GO ?= latest

# USE_ROCKSDB
# - undefined | "NO": Do not use
# - "YES": build a static lib from vendor directory, and use that one
# - "EXISTING": use existing rocksdb shared lib.
ifndef USE_ROCKSDB
  ifeq ($(shell uname), Linux)
    USE_ROCKSDB = YES
  else
    USE_ROCKSDB = NO
  endif
endif
ifneq ($(shell uname), Linux)
  USE_ROCKSDB = NO
endif

USE_KVSSD = YES

ifneq ($(USE_KVSSD), NO)
KVSSD_DIR=$(shell pwd)/build/_workspace/src/github.com/ethereum/go-ethereum/vendor/github.com/OpenMPDK/KVSSD/PDK/core
CGO_CFLAGS  += -I$(KVSSD_DIR)/include
CGO_LDFLAGS += -L$(KVSSD_DIR)/build/deps -lkvapi_static -lkvkdd_static -lnuma -lrt
CGO_TAGS    += kvssd
CXXFLAGS     = -MMD -MP -Wall -DLINUX -D_FILE_OFFSET_BITS=64 -fPIC -march=native -O2 -g -std=c++11
LIBS        += $(KVSSD_DIR)/build/deps/libkvapi_static.a $(KVSSD_DIR)/build/deps/libkvkdd_static.a
endif

ifneq ($(USE_ROCKSDB), NO)
ROCKSDB_DIR = $(shell pwd)/build/_workspace/src/github.com/ethereum/go-ethereum/vendor/github.com/facebook/rocksdb
CGO_CFLAGS  += -I$(ROCKSDB_DIR)/include
CGO_LDFLAGS += -L$(ROCKSDB_DIR) -lrocksdb -lstdc++ -lm -lz -lzstd -lbz2 -llz4 -lsnappy -ljemalloc -pthread
CGO_TAGS    += rocksdb
LIBS        += $(ROCKSDB_DIR)/librocksdb.a
endif

ifneq ($(CGO_TAGS), "")
	CGO_TAGS := -tags "$(CGO_TAGS)"
endif

metadium: gmet logrot dbbench cdbbench
	@[ -d build/conf ] || mkdir -p build/conf
	@cp -p metadium/scripts/gmet.sh metadium/scripts/solc.sh build/bin/
	@cp -p metadium/scripts/config.json.example			  \
		metadium/scripts/genesis-template.json			  \
		metadium/contracts/MetadiumAdmin-template.sol build/conf/
	@(cd build; tar cfz metadium.tar.gz bin conf)
	@echo "Done building build/metadium.tar.gz"

gmet: rocksdb kvssd metadium/admin_abi.go
	CGO_CFLAGS="$(CGO_CFLAGS)" CGO_LDFLAGS="$(CGO_LDFLAGS)" build/env.sh go run build/ci.go install $(CGO_TAGS) ./cmd/gmet
	@echo "Done building."
	@echo "Run \"$(GOBIN)/gmet\" to launch gmet."

logrot:
	build/env.sh go run build/ci.go install ./cmd/logrot

geth:
	build/env.sh go run build/ci.go install ./cmd/geth
	@echo "Done building."
	@echo "Run \"$(GOBIN)/geth\" to launch geth."

dbbench: rocksdb kvssd
	CGO_CFLAGS="$(CGO_CFLAGS)" CGO_LDFLAGS="$(CGO_LDFLAGS)" build/env.sh go run build/ci.go install $(CGO_TAGS) ./cmd/dbbench

cdbbench: cmd/cdbbench/cdbbench.c rocksdb kvssd
	g++ $(CXXFLAGS) $(CGO_CFLAGS) $(CGO_LDFLAGS) -lcrypto -o build/bin/$@ cmd/cdbbench/cdbbench.c $(LIBS)

swarm:
	build/env.sh go run build/ci.go install ./cmd/swarm
	@echo "Done building."
	@echo "Run \"$(GOBIN)/swarm\" to launch swarm."

all:
	build/env.sh go run build/ci.go install

android:
	build/env.sh go run build/ci.go aar --local
	@echo "Done building."
	@echo "Import \"$(GOBIN)/geth.aar\" to use the library."

ios:
	build/env.sh go run build/ci.go xcode --local
	@echo "Done building."
	@echo "Import \"$(GOBIN)/Geth.framework\" to use the library."

test: all
	build/env.sh go run build/ci.go test

lint: ## Run linters.
	build/env.sh go run build/ci.go lint

clean:
	./build/clean_go_build_cache.sh
	rm -fr build/_workspace/pkg/ $(GOBIN)/* build/conf metadium/admin_abi.go
	@ROCKSDB_DIR=$(shell pwd)/build/_workspace/src/github.com/ethereum/go-ethereum/vendor/github.com/facebook/rocksdb;		\
	if [ -d $${ROCKSDB_DIR} ]; then			\
		cd $${ROCKSDB_DIR};		  	\
		make clean;				\
	fi
	@KVSSD_DIR=$(shell pwd)/vendor/github.com/OpenMPDK/KVSSD/PDK/core/build;	\
	if [ -d $${KVSSD_DIR} ]; then			\
		cd $${KVSSD_DIR};		  	\
		make clean;				\
	fi

# The devtools target installs tools required for 'go generate'.
# You need to put $GOBIN (or $GOPATH/bin) in your PATH to use 'go generate'.

devtools:
	env GOBIN= go get -u golang.org/x/tools/cmd/stringer
	env GOBIN= go get -u github.com/kevinburke/go-bindata/go-bindata
	env GOBIN= go get -u github.com/fjl/gencodec
	env GOBIN= go get -u github.com/golang/protobuf/protoc-gen-go
	env GOBIN= go install ./cmd/abigen
	@type "npm" 2> /dev/null || echo 'Please install node.js and npm'
	@type "solc" 2> /dev/null || echo 'Please install solc'
	@type "protoc" 2> /dev/null || echo 'Please install protoc'

# Cross Compilation Targets (xgo)

geth-cross: geth-linux geth-darwin geth-windows geth-android geth-ios
	@echo "Full cross compilation done:"
	@ls -ld $(GOBIN)/geth-*

geth-linux: geth-linux-386 geth-linux-amd64 geth-linux-arm geth-linux-mips64 geth-linux-mips64le
	@echo "Linux cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-*

geth-linux-386:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/386 -v ./cmd/geth
	@echo "Linux 386 cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep 386

geth-linux-amd64:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/amd64 -v ./cmd/geth
	@echo "Linux amd64 cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep amd64

geth-linux-arm: geth-linux-arm-5 geth-linux-arm-6 geth-linux-arm-7 geth-linux-arm64
	@echo "Linux ARM cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep arm

geth-linux-arm-5:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/arm-5 -v ./cmd/geth
	@echo "Linux ARMv5 cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep arm-5

geth-linux-arm-6:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/arm-6 -v ./cmd/geth
	@echo "Linux ARMv6 cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep arm-6

geth-linux-arm-7:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/arm-7 -v ./cmd/geth
	@echo "Linux ARMv7 cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep arm-7

geth-linux-arm64:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/arm64 -v ./cmd/geth
	@echo "Linux ARM64 cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep arm64

geth-linux-mips:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/mips --ldflags '-extldflags "-static"' -v ./cmd/geth
	@echo "Linux MIPS cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep mips

geth-linux-mipsle:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/mipsle --ldflags '-extldflags "-static"' -v ./cmd/geth
	@echo "Linux MIPSle cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep mipsle

geth-linux-mips64:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/mips64 --ldflags '-extldflags "-static"' -v ./cmd/geth
	@echo "Linux MIPS64 cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep mips64

geth-linux-mips64le:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=linux/mips64le --ldflags '-extldflags "-static"' -v ./cmd/geth
	@echo "Linux MIPS64le cross compilation done:"
	@ls -ld $(GOBIN)/geth-linux-* | grep mips64le

geth-darwin: geth-darwin-386 geth-darwin-amd64
	@echo "Darwin cross compilation done:"
	@ls -ld $(GOBIN)/geth-darwin-*

geth-darwin-386:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=darwin/386 -v ./cmd/geth
	@echo "Darwin 386 cross compilation done:"
	@ls -ld $(GOBIN)/geth-darwin-* | grep 386

geth-darwin-amd64:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=darwin/amd64 -v ./cmd/geth
	@echo "Darwin amd64 cross compilation done:"
	@ls -ld $(GOBIN)/geth-darwin-* | grep amd64

geth-windows: geth-windows-386 geth-windows-amd64
	@echo "Windows cross compilation done:"
	@ls -ld $(GOBIN)/geth-windows-*

geth-windows-386:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=windows/386 -v ./cmd/geth
	@echo "Windows 386 cross compilation done:"
	@ls -ld $(GOBIN)/geth-windows-* | grep 386

geth-windows-amd64:
	build/env.sh go run build/ci.go xgo -- --go=$(GO) --targets=windows/amd64 -v ./cmd/geth
	@echo "Windows amd64 cross compilation done:"
	@ls -ld $(GOBIN)/geth-windows-* | grep amd64

ifneq ($(USE_ROCKSDB), YES)
rocksdb:
else
rocksdb:
	@build/env.sh test 1;
	@export GOPATH=$(shell pwd)/build/_workspace;			\
	[ -d build/_workspace/bin ] || mkdir -p build/_workspace/bin;	\
	if [ ! -x build/_workspace/bin/govendor ]; then			\
		echo "Installing govendor...";				\
		go get -v -u github.com/kardianos/govendor;		\
	fi;								\
	if [ ! -f vendor/github.com/facebook/rocksdb/README.md ]; then	\
		echo "Syncing rocksdb...";				\
		cd $${GOPATH}/src/github.com/ethereum/go-ethereum/vendor; \
		$${GOPATH}/bin/govendor sync -v;			\
	fi
	@cd $(shell pwd)/build/_workspace/src/github.com/ethereum/go-ethereum/vendor/github.com/facebook/rocksdb; \
		make -j24 static_lib;
endif

ifneq ($(USE_KVSSD), YES)
kvssd:
else
kvssd:
	@build/env.sh test 1;
	@export GOPATH=$(shell pwd)/build/_workspace;			\
	[ -d build/_workspace/bin ] || mkdir -p build/_workspace/bin;	\
	if [ ! -x build/_workspace/bin/govendor ]; then			\
		echo "Installing govendor...";				\
		go get -v -u github.com/kardianos/govendor;		\
	fi;								\
	if [ ! -f vendor/github.com/OpenMPDK/KVSSD/README.md ]; then	\
		echo "Syncing KVSSD PDK...";				\
		cd $${GOPATH}/src/github.com/ethereum/go-ethereum/vendor; \
		$${GOPATH}/bin/govendor sync -v;			\
	fi
	@THE_FILE=$${GOPATH}/src/github.com/ethereum/go-ethereum/vendor/github.com/OpenMPDK/KVSSD/PDK/core/CMakeLists.txt;				\
		 grep -q kvapi_static $${THE_FILE} 2> /dev/null || 	\
		 sed -i '/add_library(kvapi SHARED/aadd_library(kvapi_static STATIC $${SOURCES_API} $${HEADERS_API})' $${THE_FILE};
	@cd $(shell pwd)/build/_workspace/src/github.com/ethereum/go-ethereum/vendor/github.com/OpenMPDK/KVSSD/PDK/core;				\
		mkdir -p build;						\
		cd build;						\
		cmake -DWITH_KDD=ON ../;				\
		make -j24 kvkdd_static kvapi_static;
endif

AWK_CODE='								\
BEGIN { print "package metadium"; bin = 0; name = ""; abi = ""; }	\
/^{/ { bin = 1; abi = ""; name = ""; }					\
/^}/ { bin = 0; abi = abi "}"; print "var " name "Abi = `" abi "`"; }	\
{									\
  if (bin == 1) {							\
    abi = abi $$0;							\
    if ($$1 == "\"contractName\":") {					\
      name = $$2;							\
      gsub(",|\"", "", name);						\
    }									\
  }									\
}'

metadium/admin_abi.go: metadium/contracts/MetadiumAdmin-template.sol build/bin/solc
	@PATH=${PATH}:build/bin metadium/scripts/solc.sh -f abi $< /tmp/junk.$$$$; \
	cat /tmp/junk.$$$$ | awk $(AWK_CODE) > $@;	\
	rm -f /tmp/junk.$$$$;

ifneq ($(shell uname), Linux)

build/bin/solc:
	@test 1

else

SOLC_URL=https://github.com/ethereum/solidity/releases/download/v0.4.24/solc-static-linux
build/bin/solc:
	@[ -d build/bin ] || mkdir -p build/bin;		\
	if [ ! -x build/bin/solc ]; then			\
		if which curl > /dev/null 2>&1; then		\
			curl -Ls -o build/bin/solc $(SOLC_URL);	\
			chmod +x build/bin/solc;		\
		elif which wget > /dev/null 2>&1; then		\
			wget -nv -o build/bin/solc $(SOLC_URL);	\
			chmod +x build/bin/solc;		\
		fi						\
	fi

endif
