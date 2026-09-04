tsc: 4 errors, 1 warning in 3 files

| severity | file | line | code | detail |
| --- | --- | --- | --- | --- |
| error | - | - | TS5023 | Unknown compiler option 'strictNullCheck'. |
| error | src/app.ts | 12 | TS2322 | Type 'string' is not assignable to type 'number'. |
| error | src/app.ts | 48 | TS2551 | Property 'lenght' does not exist on type 'Row[]'. Did you mean 'length'? |
| error | src/ui/table.tsx | 7 | TS7006 | Parameter 'row' implicitly has an 'any' type. |
| warning | src/lib/parse.ts | 90 | TS6133 | 'walk' is declared but its value is never read. |

showing 5 of 5 items
result: sha256:78365dd543469d756fa531a3e27c9cad46735cdf576ba85d9ad80d436e92ac5f
source: tests/fixtures/normalize/tsc/sample.txt sha256:224470e56228eb5a9e1e7a365493095d0a1f3230e56607c4ea2fdf807d0ec08d
