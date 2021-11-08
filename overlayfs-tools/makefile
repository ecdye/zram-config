CFLAGS = -Wall -std=c99
LFLAGS = -lm
CC = gcc

all: overlay

overlay: main.o logic.o sh.o
	$(CC) $(LFLAGS) main.o logic.o sh.o -o overlay

main.o: main.c logic.h
	$(CC) $(CFLAGS) -c main.c

logic.o: logic.c logic.h sh.h
	$(CC) $(CFLAGS) -c logic.c

sh.o: sh.c sh.h
	$(CC) $(CFLAGS) -c sh.c

clean:
	rm -f main.o logic.o sh.o overlay
