sarif: 1 error, 2 warnings, 1 note in 3 files

| severity | file | line | code | detail |
| --- | --- | --- | --- | --- |
| error | src/server/routes.js | 88 | javascript.express.security.audit.xss | Detected directly writing user input into the response. |
| warning | src/app.js | 3 | generic.secrets.hardcoded-token | Possible hardcoded token. |
| warning | src/app.js | 14 | javascript.lang.correctness.useless-eqeq | This comparison is always true. |
| note | - | - | config.missing-baseline | No baseline file was supplied, so every finding is reported as new. |

showing 4 of 4 items
result: sha256:7458b5552557d8c548d14f3706d1e1dafd4e1b9fb1082f3a67ee18241fbff9e6
source: tests/fixtures/normalize/sarif/sample.sarif sha256:dd9b9e844e9c7c5e0ceba9edfcda2c6ab8b021adb0adacd5809ad0b9a85be274
