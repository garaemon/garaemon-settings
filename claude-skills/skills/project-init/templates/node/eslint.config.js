// @ts-check
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['dist/', 'node_modules/'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      // Require braces on every control statement. Prettier does not add
      // braces, so this is what turns `if (x) foo();` into a braced block;
      // Prettier then puts the body on its own line. Auto-fixable.
      curly: ['error', 'all'],
    },
  },
);
