import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['lib/**', 'node_modules/**', 'coverage/**'] },
  js.configs.recommended,
  ...tseslint.configs.strict,
  {
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      // tsconfig enables `noUncheckedIndexedAccess`, so every array/record
      // index is `T | undefined`; `!` after an already-checked lookup is the
      // idiomatic narrowing. Unchecked access is still caught by the compiler.
      '@typescript-eslint/no-non-null-assertion': 'off',
      'no-console': ['error', { allow: ['warn', 'error'] }],
    },
  },
);
