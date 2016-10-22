include ../../base/sw/base_include.mk

CFLAGS += -DVCMAP_ENABLE_DEFAULT=false

all: test_mem_perf

test_mem_perf: test_mem_perf.o $(BASE_FILE_OBJ)
	$(CXX) $(CFLAGS) -o $@ $^ $(LDFLAGS)

.cpp.o: cci_test.h $(BASE_FILE_INC)
	$(CXX) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

clean:
	$(RM) test_mem_perf $(BASE_FILE_OBJ) *.o

.PHONY:all clean
