CC      = gcc
CFLAGS  = -Wall -O2 -std=gnu11
FLEX    = flex
BISON   = bison

OBJS = lex.yy.o parser.tab.o main.o

all: runsyntax

runsyntax: $(OBJS)
	$(CC) $(CFLAGS) -o runsyntax $(OBJS)

lex.yy.c: lexer.l parser.tab.h
	$(FLEX) -o lex.yy.c lexer.l

parser.tab.c parser.tab.h: parser.y
	$(BISON) -d -o parser.tab.c parser.y

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

test: runsyntax
	sh ../tests/run_tests.sh

clean:
	rm -f *.o lex.yy.c parser.tab.c parser.tab.h runsyntax runsyntax.exe
