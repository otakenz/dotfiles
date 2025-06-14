return {
	-- ISSUE: https://github.com/Saghen/blink.cmp/issues/1727#issuecomment-2867452782
	-- Remember to manually build rust implementation of blink.cmp when needed.
	-- rust@nightly required to build
	-- cargo build --release (at ~/.local/share/nvim/lazy/blink.cmp)
	{
		"saghen/blink.cmp",
		opts = {
			fuzzy = { implementation = "lua" },
		},
	},
}
