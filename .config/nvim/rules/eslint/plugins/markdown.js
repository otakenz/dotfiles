import tsPlugin from "@typescript-eslint/eslint-plugin"
import mdPlugin from "eslint-plugin-markdown"

/** @type { FlatConfig[] } */
export const markdown = [
	{
		files: ["**/*.md"], // override or enforce target
		...mdPlugin.configs.recommended,
	},
	{
		files          : ["**/*.md/*.{js,jsx}"],
		languageOptions: {
			parserOptions: {
				ecmaFeatures: { impliedStrict: true },
			},
		},
	},
	{
		files  : ["**/*.md/*.{ts,tsx}"],
		plugins: {
			"@typescript-eslint": tsPlugin,
		},
	},
]
