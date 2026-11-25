# Formal Grammar (CFG) of the RunSyntax language

Terminals are in `monospace`; `ε` is the empty string.

```
program     → stmt_list
stmt_list   → stmt_list stmt  |  ε
stmt        → decl | assign | print_stmt | if_stmt | while_stmt | block
            | error ';'                         (error recovery)
block       → '{' stmt_list '}'
type        → 'int' | 'float' | 'bool'
decl        → type IDENTIFIER ';'
            | type IDENTIFIER '=' expr ';'
assign      → IDENTIFIER '=' expr ';'
print_stmt  → 'print' expr ';'
if_stmt     → 'if' '(' expr ')' block
            | 'if' '(' expr ')' block 'else' block
while_stmt  → 'while' '(' expr ')' block
expr        → expr '+' expr | expr '-' expr | expr '*' expr
            | expr '/' expr | expr '%' expr
            | expr '<' expr | expr '>' expr | expr '<=' expr | expr '>=' expr
            | expr '==' expr | expr '!=' expr
            | expr '&&' expr | expr '||' expr
            | '!' expr
            | '(' expr ')'
            | IDENTIFIER | INT_LIT | FLOAT_LIT | 'true' | 'false'
```

The ambiguity of `expr → expr op expr` is removed with Bison precedence
declarations (lowest to highest):

| Level | Operators            | Associativity |
|-------|----------------------|---------------|
| 1     | `\|\|`               | left          |
| 2     | `&&`                 | left          |
| 3     | `==` `!=`            | left          |
| 4     | `<` `>` `<=` `>=`    | left          |
| 5     | `+` `-`              | left          |
| 6     | `*` `/` `%`          | left          |
| 7     | `!`                  | right         |

`if` and `else` always take a `block`, so there is no dangling-else conflict.

## Semantic rules

* `int` may be assigned to a `float` variable (widening). All other
  assignments need identical types.
* `+ - * /` need numeric operands; `%` needs `int` operands.
* `< > <= >=` need numeric operands; `==` `!=` need two numeric or two bool operands.
* `&& || !` need `bool` operands. `if` / `while` conditions must be `bool`.
* A variable is visible from its declaration to the end of its block.
