asdf set nodejs 24.11.1
yarn init -2
"nodeLinker: node-modules\n" | save --force .yarnrc.yml
yarn
yarn add -D typescript @tsconfig/node24 prettier @types/node@24
echo `{
  "semi": true,
  "trailingComma": "all",
  "singleQuote": true
}
` | save --force .prettierrc
echo `{
  "$schema": "https://www.schemastore.org/tsconfig",
  "extends": "@tsconfig/node24",
  "compilerOptions": {
    "noEmit": true,
    "rewriteRelativeImportExtensions": true,
    "erasableSyntaxOnly": true,
    "verbatimModuleSyntax": true
  }
}
` | save --force tsconfig.json