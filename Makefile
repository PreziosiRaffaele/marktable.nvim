.PHONY: quality test check deps

MINI_NVIM := deps/mini.nvim
# Pin the test-only dependency so the suite is reproducible: a clean checkout
# always runs against this exact mini.nvim release, never a moving upstream tip.
MINI_NVIM_REF := v0.17.0

quality:
	luacheck lua/ plugin/
	stylua --check .
	lua-language-server --check lua/ --configpath $(CURDIR)/.luarc.json --checklevel=Error

# Clone the pinned mini.nvim revision on first run.
deps: $(MINI_NVIM)

$(MINI_NVIM):
	git clone --filter=blob:none --branch $(MINI_NVIM_REF) \
		https://github.com/echasnovski/mini.nvim $(MINI_NVIM)

test: deps
	NVIM_LOG_FILE=$(CURDIR)/deps/nvim.log nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run()"

check: quality test
