import { fileURLToPath } from 'node:url';
import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import sql from 'eslint-plugin-sql';
import sqlTemplate from 'eslint-plugin-sql-template';

export default tseslint.config(
  { ignores: ['dist', 'coverage', 'src/generated/**', 'prisma/**'] },
  {
    files: ['**/*.ts'],
    extends: [
      js.configs.recommended,
      ...tseslint.configs.recommendedTypeChecked,
    ],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.node,
      parserOptions: {
        project: './tsconfig.json',
        tsconfigRootDir: fileURLToPath(new URL('.', import.meta.url)),
      },
    },
    plugins: {
      sql,
      'sql-template': sqlTemplate,
    },
    settings: {
      sql: {
        placeholderRule: '\\$[0-9]+',
      },
    },
    rules: {
      'sql/no-unsafe-query': ['error', { allowLiteral: false }],
      'sql/format': 'off',
      'sql-template/no-unsafe-query': 'error',
    },
  }
);
