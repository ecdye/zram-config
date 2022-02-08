CC = gcc
CFLAGS = -Wall -std=c99
LDFLAGS = -lm
ifeq (,$(wildcard /etc/alpine-release))
  LDFLAGS += -lfts
endif

all: overlay

overlay: main.o logic.o sh.o
	$(CC) main.o logic.o sh.o -o overlay $(LDFLAGS)

main.o: main.c logic.h
	$(CC) $(CFLAGS) -c main.c

logic.o: logic.c logic.h sh.h
	$(CC) $(CFLAGS) -c logic.c

sh.o: sh.c sh.h
	$(CC) $(CFLAGS) -c sh.c

clean:
	$(RM) main.o logic.o sh.o overlay
