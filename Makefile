# Argus Master Makefile
# Build native C11 FFI library, run Prolog/Python test suites, and execute benchmarks.

CC ?= clang
SWIPL ?= swipl
PYTHON ?= python3

CFLAGS ?= -std=c11 -O3 -Wall -Wextra -Wpedantic -fPIC -Iinclude
PLBASE ?= $(shell $(SWIPL) --dump-runtime-variables | grep PLBASE | cut -d'"' -f2)
PLLIBDIR ?= $(shell $(SWIPL) --dump-runtime-variables | grep PLLIBDIR | cut -d'"' -f2)
PLINCDIR ?= $(PLBASE)/include

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	SO_EXT := dylib
	LDFLAGS_SHARED := -dynamiclib -undefined dynamic_lookup
else
	SO_EXT := so
	LDFLAGS_SHARED := -shared
endif

LIB_DIR := lib
BUILD_DIR := build
SRC_DIR := src/ffi
FFI_LIB := $(LIB_DIR)/libargus_ffi.$(SO_EXT)

.PHONY: all clean test test-unit test-integration test-style test-python bench help

all: $(FFI_LIB)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(LIB_DIR):
	mkdir -p $(LIB_DIR)

$(BUILD_DIR)/argus_ffi.o: $(SRC_DIR)/argus_ffi.c include/argus/argus_ffi.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(PLINCDIR) -c $< -o $@

$(FFI_LIB): $(BUILD_DIR)/argus_ffi.o | $(LIB_DIR)
	$(CC) $(LDFLAGS_SHARED) $< -o $@

test: test-style test-unit test-integration test-regression test-python

test-style:
	$(PYTHON) scripts/check_no_em_dash.py
	$(SWIPL) -g "consult('tests/structural/test_code_style.pl'), run_style_tests, halt." -t "halt(1)"

test-unit: all
	$(SWIPL) -g "consult('tests/unit/run_unit_tests.pl'), run_all_unit_tests, halt." -t "halt(1)"

test-integration: all
	$(SWIPL) -g "consult('tests/integration/run_integration_tests.pl'), run_all_integration_tests, halt." -t "halt(1)"

test-regression: all
	$(SWIPL) -g "consult('tests/regression/test_regression_ledger.pl'), run_regression_tests, halt." -t "halt(1)"

test-python:
	PYTHONPATH=python $(PYTHON) -m unittest discover -s tests/integration -p "*test*.py"

bench: all
	$(SWIPL) -g "consult('prolog/bench/runner.pl'), run_benchmarks, halt." -t "halt(1)"

clean:
	rm -rf $(BUILD_DIR) $(LIB_DIR)
	find . -type f -name "*.qlf" -delete
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete

help:
	@echo "Argus Build and Test Targets:"
	@echo "  all              Build native C11 FFI acceleration library"
	@echo "  test             Run full test suite (style, unit, integration, regression, python)"
	@echo "  test-style       Run em dash and code style invariant checks"
	@echo "  test-unit        Run Prolog plunit unit test suite"
	@echo "  test-integration Run end-to-end Incident Zoo diagnosis tests"
	@echo "  test-regression  Run regression ledger tests"
	@echo "  test-python      Run Python integration and CLI tests"
	@echo "  bench            Run synthetic benchmark suite"
	@echo "  clean            Remove build and cache artifacts"
