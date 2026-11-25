# RunSyntax — Mini Compiler Front-End (Flex + Bison)

Compiler front-end for a small C-like language: lexical analysis, parsing,
AST, symbol table with nested scopes, semantic analysis and Three Address
Code (TAC) generation. The engine is C / Flex / Bison.
The `backend/` + `frontend/` web dashboard is an **optional bonus (GUI)**;
the compiler itself runs fine from the command line.

Pipeline: `Source → Lexer → Parser → AST → Symbol Table + Semantic → TAC`

## Language
Types `int float bool` · statements: declaration (`int x;` or `int x = 5;`),
assignment, `print`, `if`, `if-else`, `while`, nested blocks ·
operators `+ - * / %`, `< > <= >= == !=`, `&& || !` · comments `//` and `/* */`.
Formal grammar: [docs/grammar.md](docs/grammar.md).

## Build (MSYS2 UCRT64 shell, or Linux)
```
pacman -S --needed make mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-flex mingw-w64-ucrt-x86_64-bison
cd compiler
make
```
On Ubuntu/Debian: `sudo apt install flex bison gcc make`.

## Run (command line)
```
cd compiler
./runsyntax ../examples/sample1.rs
```
Output sections: `TOKEN|…` lines (lexer), `===AST===`, `===SYMBOLS===`
(`name|type|scope|line`, scope 0 = global), `===TAC===`.
Errors go to stderr as `LEX_ERROR|line|…`, `SYNTAX_ERROR|line|…`, `SEM_ERROR|line|…`.

## Tests
```
cd compiler
make test            # or: sh ../tests/run_tests.sh
sh ../tests/run_tests.sh --update   # regenerate .expected files after a change
```
`tests/` has `valid/`, `lexical_errors/`, `syntax_errors/`,
`semantic_errors/` (undeclared, redeclaration, scope violation, type mismatch,
invalid assignment, invalid expressions), each with an `.expected` output.

## Optional web dashboard
```
cd backend
npm install
node server.js
```
Open <http://localhost:3000> (do not open `index.html` directly).

## Project structure
```
compiler/   lexer.l  parser.y  main.c  makefile
backend/    package.json  server.js        (optional GUI)
frontend/   index.html                     (optional GUI)
tests/      valid/ lexical_errors/ syntax_errors/ semantic_errors/ run_tests.sh
examples/   sample1.rs  sample2.rs
docs/       grammar.md
```

## Team
_Add team member names and IDs here._

## Troubleshooting
| Problem | Fix |
|---|---|
| `make: command not found` | `pacman -S make` in the MSYS2 UCRT64 shell |
| `flex`/`bison: command not found` | install them with pacman (see Build) |
| `Compiler spawn failed` | build the compiler first (`cd compiler && make`) |
| `Unexpected end of JSON input` | open http://localhost:3000, not the HTML file; make sure `node server.js` is running |
| Port 3000 busy | change `PORT` in `backend/server.js` |
