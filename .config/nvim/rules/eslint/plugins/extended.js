/** @type { FlatConfig[] } */
import importPlugin from "eslint-plugin-import"
// import { languageOptions } from "eslint-plugin-import/config/flat/react"
import unicornPlugin from "eslint-plugin-unicorn"
import globals from "globals"

const unicornRules = {
	"unicorn/better-regex": "warn",
	"unicorn/catch-error-name": ["warn", { name: "e" }],
	"unicorn/consistent-destructuring": "warn",
	"unicorn/custom-error-definition": "warn",
	"unicorn/empty-brace-spaces": "warn",
	"unicorn/escape-case": "warn",
	"unicorn/explicit-length-check": "off",
	"unicorn/filename-case": [
		"error",
		{
			cases: { camelCase: true, pascalCase: true },
		},
	],
	"unicorn/new-for-builtins": "warn",
	"unicorn/no-array-for-each": "warn",
	"unicorn/no-array-method-this-argument": "warn",
	"unicorn/no-array-push-push": "warn",
	"unicorn/no-array-reduce": "off",
	"unicorn/no-await-expression-member": "off",
	"unicorn/no-console-spaces": "warn",
	"unicorn/no-for-loop": "warn",
	"unicorn/no-hex-escape": "warn",
	"unicorn/no-instanceof-array": "warn",
	"unicorn/no-lonely-if": "warn",
	"unicorn/no-negated-condition": "warn",
	"unicorn/no-nested-ternary": "warn",
	"unicorn/no-new-array": "warn",
	"unicorn/no-new-buffer": "warn",
	"unicorn/no-null": "off",
	"unicorn/no-static-only-class": "warn",
	"unicorn/no-typeof-undefined": ["warn", { checkGlobalVariables: true }],
	"unicorn/no-unnecessary-await": "warn",
	"unicorn/no-unreadable-array-destructuring": "warn",
	"unicorn/no-useless-fallback-in-spread": "warn",
	"unicorn/no-useless-length-check": "warn",
	"unicorn/no-useless-promise-resolve-reject": "warn",
	"unicorn/no-useless-spread": "warn",
	"unicorn/no-useless-undefined": ["warn", { checkArguments: false }],
	"unicorn/no-zero-fractions": "warn",
	"unicorn/number-literal-case": "warn",
	"unicorn/numeric-separators-style": "warn",
	"unicorn/prefer-add-event-listener": "warn",
	"unicorn/prefer-array-find": ["warn", { checkFromLast: true }],
	"unicorn/prefer-array-flat": "warn",
	"unicorn/prefer-array-flat-map": "warn",
	"unicorn/prefer-array-index-of": "warn",
	"unicorn/prefer-array-some": "warn",
	"unicorn/prefer-at": "warn",
	"unicorn/prefer-date-now": "warn",
	"unicorn/prefer-default-parameters": "warn",
	"unicorn/prefer-dom-node-append": "warn",
	"unicorn/prefer-dom-node-dataset": "warn",
	"unicorn/prefer-dom-node-remove": "warn",
	"unicorn/prefer-export-from": ["warn", { ignoreUsedVariables: true }],
	"unicorn/prefer-includes": "warn",
	"unicorn/prefer-json-parse-buffer": "warn",
	"unicorn/prefer-keyboard-event-key": "warn",
	"unicorn/prefer-math-trunc": "warn",
	"unicorn/prefer-modern-dom-apis": "warn",
	"unicorn/prefer-modern-math-apis": "warn",
	"unicorn/prefer-module": "warn",
	"unicorn/prefer-native-coercion-functions": "warn",
	"unicorn/prefer-negative-index": "warn",
	"unicorn/prefer-node-protocol": "warn",
	"unicorn/prefer-number-properties": "off",
	"unicorn/prefer-object-from-entries": "warn",
	"unicorn/prefer-optional-catch-binding": "warn",
	"unicorn/prefer-prototype-methods": "warn",
	"unicorn/prefer-query-selector": "warn",
	"unicorn/prefer-reflect-apply": "warn",
	"unicorn/prefer-regexp-test": "warn",
	"unicorn/prefer-set-has": "warn",
	"unicorn/prefer-set-size": "warn",
	"unicorn/prefer-spread": "warn",
	"unicorn/prefer-string-replace-all": "warn",
	"unicorn/prefer-string-slice": "warn",
	"unicorn/prefer-string-starts-ends-with": "warn",
	"unicorn/prefer-string-trim-start-end": "warn",
	"unicorn/prefer-switch": ["warn", { emptyDefaultCase: "no-default-case" }],
	"unicorn/prefer-ternary": "warn",
	"unicorn/prefer-top-level-await": "off",
	"unicorn/prefer-type-error": "warn",
	"unicorn/prevent-abbreviations": "off",
	"unicorn/relative-url-style": "warn",
	"unicorn/require-array-join-separator": "warn",
	"unicorn/require-number-to-fixed-digits-argument": "warn",
	"unicorn/string-content": "warn",
	"unicorn/switch-case-braces": ["warn", "avoid"],
	"unicorn/template-indent": "warn",
	"unicorn/text-encoding-identifier-case": "warn",
	"unicorn/throw-new-error": "warn",
}

const imports = {
	...importPlugin.configs.recommended.rules,

	"import/no-empty-named-blocks": "warn",
	"import/no-import-module-exports": "warn",
	"import/no-absolute-path": "warn",
	"import/no-relative-packages": "warn",
	"import/no-useless-path-segments": [
		"warn",
		{ noUselessIndex: true, commonjs: true },
	],
	"import/consistent-type-specifier-style": "warn",
	"import/first": "warn",
	"import/newline-after-import": ["warn", { considerComments: true }],
	"import/order": [
		"warn",
		{
			"groups": [
				"builtin",
				"external",
				"internal",
				"parent",
				"sibling",
				"index",
				"object",
				"type",
			],
			"pathGroups": [{ pattern: "@/**", group: "internal" }],
			"newlines-between": "always",
			"alphabetize": {
				order: "asc",
				orderImportKind: "asc",
				caseInsensitive: true,
			},
			"warnOnUnassignedImports": true,
		},
	],
}

// /** @type { FlatConfig[] } */
export const extended = [
	// eslint-plugin-unicorn
	// console.log("unicornPlugin", unicornPlugin),
	{
		files: ["**/*.{ts,tsx,js,jsx,cjs,mjs,cts,mts}"],
		languageOptions: {
			globals: globals.builtin,
			parserOptions: { ecmaVersion: "latest", sourceType: "module" },
		},
		plugins: { unicorn: unicornPlugin },
		rules: {
			// ...unicornPlugin.configs.recommended.rules,
			...unicornRules,
			// "unicorn/custom-error-definition" : "warn",
		},
	},

	// eslint-plugin-import
	{
		files: ["**/*.{js,jsx,mjs}"],
		// A hack to make the `eslint-plugin-import` works with ESLint's flat-config.
		languageOptions: {
			parserOptions: { ecmaVersion: "latest", sourceType: "module" },
		},
		plugins: { import: importPlugin },
		settings: {
			"import/extensions": [".js", ".jsx", ".mjs"],
			"import/parsers": { espree: [".js", ".jsx", ".mjs"] },
			"import/resolver": { node: true },
		},
		rules: imports,
	},
	{
		files: ["**/*.{ts,tsx,mts}"],
		plugins: { import: importPlugin },
		settings: {
			"import/extensions": [
				".ts",
				".tsx",
				".d.ts",
				".js",
				".jsx",
				".mjs",
				".mts",
			],
			"import/parsers": {
				"espree": [".js", ".jsx", ".mjs"],
				"@typescript-eslint/parser": [".ts", ".tsx", ".d.ts", ".mts"],
			},
			"import/resolver": { typescript: true },
			"import/external-module-folders": ["node_modules", "node_modules/@types"],
		},
		rules: {
			// TypeScript compilation already ensures that named imports exist in the referenced module
			"import/named": "off",
		},
	},
	{
		files: ["eslint.config.js"],
		rules: {
			"import/no-useless-path-segments": ["warn", { noUselessIndex: false }],
		},
	},
]
