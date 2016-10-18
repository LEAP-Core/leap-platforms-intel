include ../../base/sw/base_include.mk

all: test_random

test_random: test_random.o $(BASE_FILE_OBJ)
	$(CXX) $(CFLAGS) -o $@ $^ $(LDFLAGS)

.cpp.o: cci_test.h $(BASE_FILE_INC)
	$(CXX) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

clean:
	$(RM) test_random $(BASE_FILE_OBJ) *.o

.PHONY:all clean
