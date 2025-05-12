import {
	// extended,
	formatting,
	javascript,
	json,
	markdown,
	toml,
	typescript,
	yaml,
} from "./index.js"

/** @type { FlatConfig[] } */
export default [
	...javascript,
	...typescript,
	...json,
	...markdown,
	...toml,
	...yaml,
	// ...extended,
	...formatting,
	{
		// Note: there should be no other properties in this object
		ignores: [
			"eslint.config.cjs",
			"plugins/*.js", // or even
			"**/eslint/plugins/**/*.js",
		],
	},
]
