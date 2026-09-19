import js from "@eslint/js";
import html from "eslint-plugin-html";
import globals from "globals";

export default [
  {
    // The project-init templates scaffold generated projects. They import
    // packages this repository never installs and ship their own
    // eslint.config.js, so linting them here reports missing modules rather
    // than real defects.
    ignores: ["claude-skills/skills/project-init/templates/**"],
  },
  js.configs.recommended,
  {
    // eslint-plugin-html extracts each <script> body and hands it to the rules
    // below, so a template that inlines its own JavaScript gets the same checks
    // as a standalone .js file.
    files: ["**/*.html"],
    plugins: { html },
    languageOptions: {
      sourceType: "script",
      globals: globals.browser,
    },
  },
  {
    rules: {
      "no-var": "error",
      "prefer-const": "error",
    },
  },
];
