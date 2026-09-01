// Flat ESLint config on antfu's preset, with its stylistic defaults bent to
// the project's existing style (double quotes, semicolons, parenthesized
// arrow args, 1tbs braces — see AGENTS.md).
import antfu from "@antfu/eslint-config";

export default antfu({
  react: true,
  stylistic: {
    indent: 2,
    quotes: "double",
    semi: true,
  },
  rules: {
    "style/arrow-parens": ["error", "always"],
    "style/brace-style": ["error", "1tbs", { allowSingleLine: true }],
    // The renderer mirrors pushed main-process state into local UI state;
    // synchronous setState inside a push-driven effect is the design.
    "react/set-state-in-effect": "off",
  },
});
