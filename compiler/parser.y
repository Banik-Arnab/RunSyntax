%{
/* ------------------------------------------------------------------
 * parser.y  -  Syntax analyzer (Bison) + AST + symbol table +
 *              semantic analyzer + Three Address Code generator
 * ------------------------------------------------------------------ */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

extern int yylex(void);
extern int yylineno;
extern int getLexErrorCount(void);
extern int getLastLexErrorLine(void);
void yyerror(const char *msg);
static const char *opStr(int op);

/* ================= TYPES + AST ================= */
typedef enum { T_INT, T_FLOAT, T_BOOL, T_ERROR, T_VOID } DataType;

static const char *typeName(DataType t) {
    switch (t) {
        case T_INT:   return "int";
        case T_FLOAT: return "float";
        case T_BOOL:  return "bool";
        case T_VOID:  return "void";
        default:      return "error";
    }
}

typedef enum {
    N_PROGRAM, N_BLOCK, N_DECL, N_ASSIGN, N_PRINT,
    N_IF, N_WHILE, N_BINOP, N_UNOP, N_IDENT, N_INT, N_FLOAT, N_BOOL
} NodeKind;

typedef struct ASTNode {
    NodeKind kind;
    int line;
    DataType dtype;             /* declared type / expression type        */
    char *name;                 /* identifier name                        */
    int ival; float fval; int bval;
    int op;                     /* token code of the operator             */
    struct ASTNode *left, *right;
    struct ASTNode *body;       /* block statements / if-then / loop body */
    struct ASTNode *elseBody;   /* else part                              */
    struct ASTNode *next;       /* next statement in the same list        */
} ASTNode;

static ASTNode *newNode(NodeKind k, int line) {
    ASTNode *n = calloc(1, sizeof(ASTNode));
    n->kind = k; n->line = line; n->dtype = T_VOID;
    return n;
}

static int syntaxErrorCount = 0;

/* ================= SYMBOL TABLE =================
 * Symbols are kept forever in 'allSymbols' (so the whole table can be
 * printed at the end). A stack of per-scope lists is used for lookup:
 * leaving a block pops its list, which hides its variables.          */
typedef struct Symbol {
    char *name;
    DataType type;
    int scopeId;                /* 0 = global, 1,2,3... = nested blocks   */
    int depth;                  /* nesting depth (0 = global)             */
    int declLine;
    struct Symbol *next;        /* next in the same scope list            */
    struct Symbol *allNext;     /* next in the global declaration list    */
} Symbol;

#define MAX_SCOPES 64
static Symbol *scopeStack[MAX_SCOPES];
static int scopeIds[MAX_SCOPES];
static int scopeDepth = 0, scopeCounter = 0;
static Symbol *allHead = NULL, *allTail = NULL;

static void enterScope(void) {
    if (scopeDepth < MAX_SCOPES - 1) scopeDepth++;
    scopeStack[scopeDepth] = NULL;
    scopeIds[scopeDepth] = ++scopeCounter;
}
static void exitScope(void) {
    scopeStack[scopeDepth] = NULL;      /* hide, but keep in allSymbols */
    if (scopeDepth > 0) scopeDepth--;
}
static Symbol *lookupCurrent(const char *n) {
    for (Symbol *s = scopeStack[scopeDepth]; s; s = s->next)
        if (!strcmp(s->name, n)) return s;
    return NULL;
}
static Symbol *lookupAll(const char *n) {
    for (int i = scopeDepth; i >= 0; i--)
        for (Symbol *s = scopeStack[i]; s; s = s->next)
            if (!strcmp(s->name, n)) return s;
    return NULL;
}
/* declared somewhere, but in a block we have already left? */
static Symbol *lookupHidden(const char *n) {
    for (Symbol *s = allHead; s; s = s->allNext)
        if (!strcmp(s->name, n)) return s;
    return NULL;
}
static int insertSymbol(const char *n, DataType t, int line) {
    if (lookupCurrent(n)) return 0;
    Symbol *s = calloc(1, sizeof(Symbol));
    s->name = strdup(n); s->type = t; s->declLine = line;
    s->scopeId = scopeIds[scopeDepth]; s->depth = scopeDepth;
    s->next = scopeStack[scopeDepth]; scopeStack[scopeDepth] = s;
    if (allTail) allTail->allNext = s; else allHead = s;
    allTail = s;
    return 1;
}

/* ================= ERROR REPORTING ================= */
static int semErrorCount = 0;
static void semError(int line, const char *msg, const char *detail) {
    semErrorCount++;
    fprintf(stderr, "SEM_ERROR|%d|%s|%s\n", line, msg, detail ? detail : "");
}

/* ================= AST PRINT ================= */
static void indent(int n) { for (int i = 0; i < n; i++) printf("  "); }

static const char *kindName(NodeKind k) {
    switch (k) {
        case N_PROGRAM: return "Program";   case N_BLOCK: return "Block";
        case N_DECL:    return "Declaration"; case N_ASSIGN: return "Assignment";
        case N_PRINT:   return "Print";     case N_IF: return "If";
        case N_WHILE:   return "While";     case N_BINOP: return "BinaryOp";
        case N_UNOP:    return "UnaryOp";   case N_IDENT: return "Identifier";
        case N_INT:     return "Int";       case N_FLOAT: return "Float";
        case N_BOOL:    return "Bool";      default: return "?";
    }
}

static void printNode(ASTNode *n, int d);
static void printList(ASTNode *n, int d) {
    for (; n; n = n->next) printNode(n, d);
}
static void printLabeled(const char *label, ASTNode *c, int d) {
    if (!c) return;
    indent(d); printf("%s:\n", label);
    if (c->kind == N_BLOCK) printNode(c, d + 1);
    else                    printNode(c, d + 1);
}

static void printNode(ASTNode *n, int d) {
    if (!n) return;
    indent(d);
    printf("%s", kindName(n->kind));
    switch (n->kind) {
        case N_DECL:   printf(" [%s %s]", typeName(n->dtype), n->name); break;
        case N_ASSIGN: printf(" [%s]", n->name); break;
        case N_IDENT:  printf(" [%s]", n->name); break;
        case N_INT:    printf(" [%d]", n->ival); break;
        case N_FLOAT:  printf(" [%g]", n->fval); break;
        case N_BOOL:   printf(" [%s]", n->bval ? "true" : "false"); break;
        case N_BINOP:
        case N_UNOP:   printf(" [%s]", opStr(n->op)); break;
        default: break;
    }
    printf("\n");
    switch (n->kind) {
        case N_PROGRAM:
        case N_BLOCK:  printList(n->body, d + 1); break;
        case N_IF:
            printLabeled("condition", n->left, d + 1);
            printLabeled("then", n->body, d + 1);
            printLabeled("else", n->elseBody, d + 1);
            break;
        case N_WHILE:
            printLabeled("condition", n->left, d + 1);
            printLabeled("body", n->body, d + 1);
            break;
        default:
            if (n->left)  printNode(n->left, d + 1);
            if (n->right) printNode(n->right, d + 1);
            break;
    }
}

/* ================= SYMBOL TABLE PRINT ================= */
static void printSymbols(void) {
    for (Symbol *s = allHead; s; s = s->allNext)
        printf("SYMBOL|%s|%s|%d|%d\n", s->name, typeName(s->type), s->scopeId, s->declLine);
}
%}

%code requires {
    #include <stdarg.h>
    typedef struct ASTNode ASTNode;
}

%union {
    int ival;
    float fval;
    char *sval;
    struct ASTNode *node;
    int dtype;
}

%define parse.error verbose
%locations

%token <ival> INT_LIT    "integer literal"
%token <fval> FLOAT_LIT  "float literal"
%token <sval> IDENTIFIER "identifier"
%token KW_INT "int" KW_FLOAT "float" KW_BOOL "bool" KW_IF "if" KW_ELSE "else"
%token KW_WHILE "while" KW_PRINT "print" KW_TRUE "true" KW_FALSE "false"
%token OP_EQ "==" OP_NE "!=" OP_LE "<=" OP_GE ">=" OP_AND "&&" OP_OR "||"
%token OP_LT "<" OP_GT ">" OP_PLUS "+" OP_MINUS "-" OP_MUL "*" OP_DIV "/"
%token OP_MOD "%" OP_NOT "!" OP_ASSIGN "="
%token DELIM_SEMI ";" DELIM_LPAREN "(" DELIM_RPAREN ")" DELIM_LBRACE "{" DELIM_RBRACE "}"

%type <node> program stmt_list stmt block decl assign print_stmt if_stmt while_stmt expr
%type <dtype> type

/* ---- precedence (lowest to highest) ---- */
%left OP_OR
%left OP_AND
%left OP_EQ OP_NE
%left OP_LT OP_GT OP_LE OP_GE
%left OP_PLUS OP_MINUS
%left OP_MUL OP_DIV OP_MOD
%right OP_NOT

%code {
/* ================= SEMANTIC ANALYZER =================
 * Lives here (after the token definitions) because it uses OP_* codes. */

static int isNumeric(DataType t) { return t == T_INT || t == T_FLOAT; }

/* int may be widened to float; everything else must match exactly */
static int assignable(DataType dst, DataType src) {
    return dst == src || (dst == T_FLOAT && src == T_INT);
}

static DataType checkExpr(ASTNode *n) {
    char buf[160];
    if (!n) return T_ERROR;
    switch (n->kind) {
        case N_INT:   n->dtype = T_INT;   return T_INT;
        case N_FLOAT: n->dtype = T_FLOAT; return T_FLOAT;
        case N_BOOL:  n->dtype = T_BOOL;  return T_BOOL;
        case N_IDENT: {
            Symbol *s = lookupAll(n->name);
            if (!s) {
                if (lookupHidden(n->name))
                    semError(n->line, "Scope violation: variable used outside its block", n->name);
                else
                    semError(n->line, "Undeclared variable", n->name);
                return T_ERROR;
            }
            n->dtype = s->type;
            return s->type;
        }
        case N_UNOP: {
            DataType T = checkExpr(n->left);
            if (T == T_ERROR) return T_ERROR;
            if (T != T_BOOL) {
                snprintf(buf, sizeof buf, "operand has type %s", typeName(T));
                semError(n->line, "Invalid expression: '!' needs a bool operand", buf);
                return T_ERROR;
            }
            n->dtype = T_BOOL; return T_BOOL;
        }
        case N_BINOP: {
            DataType L = checkExpr(n->left), R = checkExpr(n->right);
            int op = n->op;
            if (L == T_ERROR || R == T_ERROR) return T_ERROR;
            snprintf(buf, sizeof buf, "operands are %s and %s", typeName(L), typeName(R));

            if (op == OP_PLUS || op == OP_MINUS || op == OP_MUL || op == OP_DIV || op == OP_MOD) {
                if (!isNumeric(L) || !isNumeric(R)) {
                    semError(n->line, "Invalid expression: arithmetic needs numeric operands", buf);
                    return T_ERROR;
                }
                if (op == OP_MOD && (L == T_FLOAT || R == T_FLOAT)) {
                    semError(n->line, "Invalid expression: '%' needs int operands", buf);
                    return T_ERROR;
                }
                n->dtype = (L == T_FLOAT || R == T_FLOAT) ? T_FLOAT : T_INT;
                return n->dtype;
            }
            if (op == OP_LT || op == OP_GT || op == OP_LE || op == OP_GE) {
                if (!isNumeric(L) || !isNumeric(R)) {
                    semError(n->line, "Invalid expression: relational operator needs numeric operands", buf);
                    return T_ERROR;
                }
                n->dtype = T_BOOL; return T_BOOL;
            }
            if (op == OP_EQ || op == OP_NE) {
                if (!((isNumeric(L) && isNumeric(R)) || (L == T_BOOL && R == T_BOOL))) {
                    semError(n->line, "Invalid expression: cannot compare these types", buf);
                    return T_ERROR;
                }
                n->dtype = T_BOOL; return T_BOOL;
            }
            if (op == OP_AND || op == OP_OR) {
                if (L != T_BOOL || R != T_BOOL) {
                    semError(n->line, "Invalid expression: logical operator needs bool operands", buf);
                    return T_ERROR;
                }
                n->dtype = T_BOOL; return T_BOOL;
            }
            return T_ERROR;
        }
        default: return T_ERROR;
    }
}

static void checkStmt(ASTNode *n);

static void checkBlock(ASTNode *b) {
    enterScope();
    for (ASTNode *s = b ? b->body : NULL; s; s = s->next) checkStmt(s);
    exitScope();
}

static void checkCondition(ASTNode *cond, int line, const char *what) {
    DataType c = checkExpr(cond);
    if (c != T_ERROR && c != T_BOOL) {
        char buf[80];
        snprintf(buf, sizeof buf, "condition has type %s", typeName(c));
        semError(line, what, buf);
    }
}

static void checkStmt(ASTNode *n) {
    char buf[160];
    if (!n) return;
    switch (n->kind) {
        case N_DECL: {
            DataType R = n->right ? checkExpr(n->right) : T_VOID;   /* int x = expr; */
            if (!insertSymbol(n->name, n->dtype, n->line))
                semError(n->line, "Redeclaration in the same scope", n->name);
            else if (n->right && R != T_ERROR && !assignable(n->dtype, R)) {
                snprintf(buf, sizeof buf, "cannot initialise %s '%s' with %s",
                         typeName(n->dtype), n->name, typeName(R));
                semError(n->line, "Type mismatch in declaration", buf);
            }
            break;
        }
        case N_ASSIGN: {
            Symbol *s = lookupAll(n->name);
            DataType R = checkExpr(n->right);
            if (!s) {
                if (lookupHidden(n->name))
                    semError(n->line, "Scope violation: variable assigned outside its block", n->name);
                else
                    semError(n->line, "Assignment to undeclared variable", n->name);
                break;
            }
            if (R == T_ERROR) break;
            if (!assignable(s->type, R)) {
                snprintf(buf, sizeof buf, "cannot assign %s to %s variable '%s'",
                         typeName(R), typeName(s->type), n->name);
                semError(n->line, "Invalid assignment (type mismatch)", buf);
            }
            break;
        }
        case N_PRINT:
            checkExpr(n->left);
            break;
        case N_IF:
            checkCondition(n->left, n->line, "If condition must be bool");
            checkBlock(n->body);
            if (n->elseBody) checkBlock(n->elseBody);
            break;
        case N_WHILE:
            checkCondition(n->left, n->line, "While condition must be bool");
            checkBlock(n->body);
            break;
        case N_BLOCK: checkBlock(n); break;
        default: break;
    }
}

/* ================= TAC GENERATOR ================= */
static int tempCount = 0, labelCount = 0;

static void emit(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    printf("TAC|"); vprintf(fmt, ap); printf("\n");
    va_end(ap);
}
static char *newTemp(void)  { char *b = malloc(16); sprintf(b, "t%d", ++tempCount); return b; }
static char *newLabel(void) { char *b = malloc(16); sprintf(b, "L%d", ++labelCount); return b; }

static const char *opStrImpl(int op) {
    switch (op) {
        case OP_PLUS: return "+";  case OP_MINUS: return "-"; case OP_MUL: return "*";
        case OP_DIV:  return "/";  case OP_MOD: return "%";   case OP_LT: return "<";
        case OP_GT:   return ">";  case OP_LE: return "<=";   case OP_GE: return ">=";
        case OP_EQ:   return "=="; case OP_NE: return "!=";   case OP_AND: return "&&";
        case OP_OR:   return "||"; case OP_NOT: return "!";
        default: return "?";
    }
}
static const char *opStr(int op) { return opStrImpl(op); }

static char *genExpr(ASTNode *n) {
    if (!n) return strdup("0");
    switch (n->kind) {
        case N_INT:   { char *b = malloc(24); sprintf(b, "%d", n->ival); return b; }
        case N_FLOAT: {
            char *b = malloc(40); sprintf(b, "%g", n->fval);
            if (!strpbrk(b, ".eE")) strcat(b, ".0");
            return b;
        }
        case N_BOOL:  return strdup(n->bval ? "true" : "false");
        case N_IDENT: return strdup(n->name);
        case N_UNOP: {
            char *a = genExpr(n->left), *t = newTemp();
            emit("%s = %s%s", t, opStr(n->op), a);
            free(a); return t;
        }
        case N_BINOP: {
            char *a = genExpr(n->left), *b = genExpr(n->right), *t = newTemp();
            emit("%s = %s %s %s", t, a, opStr(n->op), b);
            free(a); free(b); return t;
        }
        default: return strdup("0");
    }
}

static void genStmt(ASTNode *n);

static void genBlock(ASTNode *b) {
    for (ASTNode *s = b ? b->body : NULL; s; s = s->next) genStmt(s);
}

static void genStmt(ASTNode *n) {
    if (!n) return;
    switch (n->kind) {
        case N_DECL:
            if (n->right) {                      /* int x = expr; */
                char *r = genExpr(n->right);
                emit("%s = %s", n->name, r);
                free(r);
            }
            break;
        case N_ASSIGN: {
            char *r = genExpr(n->right);
            emit("%s = %s", n->name, r);
            free(r); break;
        }
        case N_PRINT: {
            char *r = genExpr(n->left);
            emit("print %s", r);
            free(r); break;
        }
        case N_IF: {
            char *c = genExpr(n->left), *l1 = newLabel();
            emit("ifFalse %s goto %s", c, l1);
            genBlock(n->body);
            if (n->elseBody) {
                char *l2 = newLabel();
                emit("goto %s", l2);
                emit("%s:", l1);
                genBlock(n->elseBody);
                emit("%s:", l2);
                free(l2);
            } else {
                emit("%s:", l1);
            }
            free(c); free(l1); break;
        }
        case N_WHILE: {
            char *l1 = newLabel(), *l2 = newLabel();
            emit("%s:", l1);
            char *c = genExpr(n->left);
            emit("ifFalse %s goto %s", c, l2);
            genBlock(n->body);
            emit("goto %s", l1);
            emit("%s:", l2);
            free(c); free(l1); free(l2); break;
        }
        case N_BLOCK: genBlock(n); break;
        default: break;
    }
}

/* ================= DRIVER ENTRY (called from main) ================= */
static ASTNode *g_program = NULL;

ASTNode *getProgram(void) { return g_program; }
int getSemanticErrorCount(void) { return semErrorCount; }

void runCompiler(ASTNode *program) {
    printf("===AST===\n");
    printNode(program, 0);

    /* global scope = scope 0 (already the base of the stack) */
    scopeDepth = 0; scopeIds[0] = 0; scopeStack[0] = NULL;
    for (ASTNode *s = program ? program->body : NULL; s; s = s->next) checkStmt(s);

    printf("===SYMBOLS===\n");
    printSymbols();

    printf("===TAC===\n");
    if (semErrorCount == 0)
        for (ASTNode *s = program ? program->body : NULL; s; s = s->next) genStmt(s);
}
}

%start program

%%

program:
      stmt_list { $$ = newNode(N_PROGRAM, 1); $$->body = $1; g_program = $$; }
    ;

stmt_list:
      /* empty */      { $$ = NULL; }
    | stmt_list stmt   {
          if (!$2)      $$ = $1;                 /* statement was a recovered error */
          else if (!$1) $$ = $2;
          else { ASTNode *t = $1; while (t->next) t = t->next; t->next = $2; $$ = $1; }
      }
    ;

stmt:
      decl        { $$ = $1; }
    | assign      { $$ = $1; }
    | print_stmt  { $$ = $1; }
    | if_stmt     { $$ = $1; }
    | while_stmt  { $$ = $1; }
    | block       { $$ = $1; }
    /* ---- error recovery: skip to the next ';' and keep parsing ---- */
    | error DELIM_SEMI   { yyerrok; $$ = NULL; }
    ;

block:
      DELIM_LBRACE stmt_list DELIM_RBRACE {
          $$ = newNode(N_BLOCK, @1.first_line); $$->body = $2; }
    ;

type:
      KW_INT   { $$ = T_INT; }
    | KW_FLOAT { $$ = T_FLOAT; }
    | KW_BOOL  { $$ = T_BOOL; }
    ;

decl:
      type IDENTIFIER DELIM_SEMI {
          $$ = newNode(N_DECL, @2.first_line); $$->dtype = $1; $$->name = $2; }
    | type IDENTIFIER OP_ASSIGN expr DELIM_SEMI {
          $$ = newNode(N_DECL, @2.first_line); $$->dtype = $1; $$->name = $2; $$->right = $4; }
    ;

assign:
      IDENTIFIER OP_ASSIGN expr DELIM_SEMI {
          $$ = newNode(N_ASSIGN, @1.first_line); $$->name = $1; $$->right = $3; }
    ;

print_stmt:
      KW_PRINT expr DELIM_SEMI {
          $$ = newNode(N_PRINT, @1.first_line); $$->left = $2; }
    ;

if_stmt:
      KW_IF DELIM_LPAREN expr DELIM_RPAREN block {
          $$ = newNode(N_IF, @1.first_line); $$->left = $3; $$->body = $5; }
    | KW_IF DELIM_LPAREN expr DELIM_RPAREN block KW_ELSE block {
          $$ = newNode(N_IF, @1.first_line); $$->left = $3; $$->body = $5; $$->elseBody = $7; }
    ;

while_stmt:
      KW_WHILE DELIM_LPAREN expr DELIM_RPAREN block {
          $$ = newNode(N_WHILE, @1.first_line); $$->left = $3; $$->body = $5; }
    ;

expr:
      expr OP_PLUS  expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_PLUS;  $$->left = $1; $$->right = $3; }
    | expr OP_MINUS expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_MINUS; $$->left = $1; $$->right = $3; }
    | expr OP_MUL   expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_MUL;   $$->left = $1; $$->right = $3; }
    | expr OP_DIV   expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_DIV;   $$->left = $1; $$->right = $3; }
    | expr OP_MOD   expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_MOD;   $$->left = $1; $$->right = $3; }
    | expr OP_LT    expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_LT;    $$->left = $1; $$->right = $3; }
    | expr OP_GT    expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_GT;    $$->left = $1; $$->right = $3; }
    | expr OP_LE    expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_LE;    $$->left = $1; $$->right = $3; }
    | expr OP_GE    expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_GE;    $$->left = $1; $$->right = $3; }
    | expr OP_EQ    expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_EQ;    $$->left = $1; $$->right = $3; }
    | expr OP_NE    expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_NE;    $$->left = $1; $$->right = $3; }
    | expr OP_AND   expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_AND;   $$->left = $1; $$->right = $3; }
    | expr OP_OR    expr { $$ = newNode(N_BINOP, @2.first_line); $$->op = OP_OR;    $$->left = $1; $$->right = $3; }
    | OP_NOT expr        { $$ = newNode(N_UNOP,  @1.first_line); $$->op = OP_NOT; $$->left = $2; }
    | DELIM_LPAREN expr DELIM_RPAREN { $$ = $2; }
    | IDENTIFIER { $$ = newNode(N_IDENT, @1.first_line); $$->name = $1; }
    | INT_LIT    { $$ = newNode(N_INT,   @1.first_line); $$->ival = $1; }
    | FLOAT_LIT  { $$ = newNode(N_FLOAT, @1.first_line); $$->fval = $1; }
    | KW_TRUE    { $$ = newNode(N_BOOL,  @1.first_line); $$->bval = 1; }
    | KW_FALSE   { $$ = newNode(N_BOOL,  @1.first_line); $$->bval = 0; }
    ;

%%

void yyerror(const char *msg) {
    /* a bad character already reported on this line makes the parser fail
       too; that follow-up error is noise, so do not report it again */
    if (getLexErrorCount() > 0 && yylineno == getLastLexErrorLine()) return;
    syntaxErrorCount++;
    fprintf(stderr, "SYNTAX_ERROR|%d|%s\n", yylineno, msg);
}

int getSyntaxErrorCount(void) { return syntaxErrorCount; }
