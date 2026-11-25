%{
/* ------------------------------------------------------------------
 * lexer.l  -  Lexical analyzer (Flex)
 * Prints one TOKEN|line|kind|lexeme record per token on stdout, and
 * LEX_ERROR|line|message|lexeme records on stderr.
 * ------------------------------------------------------------------ */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.tab.h"

/* keep the line number of every token for the parser (@n.first_line) */
#define YY_USER_ACTION yylloc.first_line = yylloc.last_line = yylineno;

static int lexErrorCount = 0;
static int lastLexErrorLine = 0;

static void report_lex_error(const char *msg, const char *lexeme) {
    lexErrorCount++;
    lastLexErrorLine = yylineno;
    fprintf(stderr, "LEX_ERROR|%d|%s|%s\n", yylineno, msg, lexeme);
}

int getLexErrorCount(void) { return lexErrorCount; }
int getLastLexErrorLine(void) { return lastLexErrorLine; }

/* print the token, then hand it to the parser */
#define TOK(kind, code) do { \
    printf("TOKEN|%d|%s|%s\n", yylineno, kind, yytext); return code; } while (0)
%}

%option noyywrap yylineno nounput

digit       [0-9]
letter      [a-zA-Z_]
id          {letter}({letter}|{digit})*
intlit      {digit}+
floatlit    {digit}+\.{digit}+

%%

"int"       { TOK("KEYWORD", KW_INT); }
"float"     { TOK("KEYWORD", KW_FLOAT); }
"bool"      { TOK("KEYWORD", KW_BOOL); }
"if"        { TOK("KEYWORD", KW_IF); }
"else"      { TOK("KEYWORD", KW_ELSE); }
"while"     { TOK("KEYWORD", KW_WHILE); }
"print"     { TOK("KEYWORD", KW_PRINT); }
"true"      { TOK("BOOL_LITERAL", KW_TRUE); }
"false"     { TOK("BOOL_LITERAL", KW_FALSE); }

{floatlit}  { yylval.fval = (float)atof(yytext); TOK("FLOAT_LITERAL", FLOAT_LIT); }
{intlit}    { yylval.ival = atoi(yytext);        TOK("INT_LITERAL", INT_LIT); }

{digit}+{letter}({letter}|{digit})* {
    report_lex_error("Invalid identifier (starts with a digit)", yytext);
}

{id}        { yylval.sval = strdup(yytext); TOK("IDENTIFIER", IDENTIFIER); }

"=="        { TOK("OPERATOR", OP_EQ); }
"!="        { TOK("OPERATOR", OP_NE); }
"<="        { TOK("OPERATOR", OP_LE); }
">="        { TOK("OPERATOR", OP_GE); }
"&&"        { TOK("OPERATOR", OP_AND); }
"||"        { TOK("OPERATOR", OP_OR); }
"<"         { TOK("OPERATOR", OP_LT); }
">"         { TOK("OPERATOR", OP_GT); }
"+"         { TOK("OPERATOR", OP_PLUS); }
"-"         { TOK("OPERATOR", OP_MINUS); }
"*"         { TOK("OPERATOR", OP_MUL); }
"/"         { TOK("OPERATOR", OP_DIV); }
"%"         { TOK("OPERATOR", OP_MOD); }
"!"         { TOK("OPERATOR", OP_NOT); }
"="         { TOK("OPERATOR", OP_ASSIGN); }

";"         { TOK("DELIMITER", DELIM_SEMI); }
"("         { TOK("DELIMITER", DELIM_LPAREN); }
")"         { TOK("DELIMITER", DELIM_RPAREN); }
"{"         { TOK("DELIMITER", DELIM_LBRACE); }
"}"         { TOK("DELIMITER", DELIM_RBRACE); }

"//"[^\n]*                      { /* single-line comment: discarded */ }
"/*"([^*]|\*+[^*/])*\*+"/"      { /* block comment: discarded */ }
"/*"        {
    /* a block comment that never closes: report it and skip to EOF */
    int c;
    report_lex_error("Unterminated block comment", "/*");
    while ((c = input()) > 0) { }
}

[ \t\r\n]+  { /* whitespace: discarded (yylineno counts the newlines) */ }

.           { report_lex_error("Invalid character", yytext); }

%%
