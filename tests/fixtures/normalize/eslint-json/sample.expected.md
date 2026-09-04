eslint: 4 errors, 2 warnings in 3 files

| severity | file | line | code | detail |
| --- | --- | --- | --- | --- |
| error | src/app.js | 12 | no-unused-vars | 'config' is assigned a value but never used. |
| error | src/app.js | 48 | eqeqeq | Expected '===' and instead saw '=='. |
| error | src/lib/parse.js | 1 | - | Parsing error: Unexpected token } |
| error | src/ui/table.js | 7 | no-mixed-operators | Unexpected mix of '\|\|' and '&&'. |
| warning | src/app.js | 3 | no-console | Unexpected console statement. |
| warning | src/lib/parse.js | 90 | complexity | Function 'walk' has a complexity of 24. Maximum allowed is 10, and this message is deliberately l... |

showing 6 of 6 items
source: tests/fixtures/normalize/eslint-json/sample.json sha256:df83753470845c781d3125a998f442cb2ded0fd878f5b87d287f8f73f4d17d76
