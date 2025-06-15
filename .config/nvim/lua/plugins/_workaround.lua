return {
	-- ISSUE: https://github.com/Saghen/blink.cmp/pull/1908
	-- PR is merged in the main branch of blink.cmp, but not yet in tagged release.
	{
		"Saghen/blink.cmp",
		branch = "main",
		version = false,
		-- rust@nightly required to build the library as no pre-built binaries are available.
		build = "cargo build --release",
	},
}
