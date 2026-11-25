#include <stdio.h>
#include <stdlib.h>
#include "parser.tab.h"

extern FILE *yyin;
extern int yyparse(void);
extern ASTNode *getProgram(void);
extern void runCompiler(ASTNode *);
extern int getSyntaxErrorCount(void);
extern int getLexErrorCount(void);
extern int getSemanticErrorCount(void);

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "Usage: %s <source file>\n", argv[0]); return 1; }
    yyin = fopen(argv[1], "r");
    if (!yyin) { fprintf(stderr, "Cannot open %s\n", argv[1]); return 1; }

    /* Lexing and parsing run together: the parser pulls tokens from the
     * lexer, which prints a TOKEN| line for each one. */
    printf("===LEX===\n");
    int rc = yyparse();
    fclose(yyin);

    if (getSyntaxErrorCount() > 0 || rc != 0) {
        fprintf(stderr, "PIPELINE|aborted at syntax stage\n");
        return 2;
    }
    if (getLexErrorCount() > 0) {
        fprintf(stderr, "PIPELINE|aborted at lexical stage\n");
        return 2;
    }

    printf("===SYNTAX_OK===\n");
    runCompiler(getProgram());
    printf("===DONE===\n");

    return getSemanticErrorCount() > 0 ? 3 : 0;
}
