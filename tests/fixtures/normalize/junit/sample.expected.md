junit: 14 tests, 3 failures, 1 error, 1 skipped in 2 suites

| severity | file | line | code | detail |
| --- | --- | --- | --- | --- |
| error | src/lib/parse.test.js | - | error | throws on a circular reference (TypeError) |
| error | src/lib/parse.test.js | - | failure | keeps "quoted" keys intact (AssertionError) |
| error | src/lib/parse.test.js | - | failure | rejects a token it cannot read (AssertionError) |
| error | src/ui/table.test.js | - | failure | sorts by the column the header names (AssertionError) |

showing 4 of 4 items
source: tests/fixtures/normalize/junit/sample.xml sha256:4d8831637686d008ba226691d0696926cf848032d58a689c0a3742b6728f75e7
