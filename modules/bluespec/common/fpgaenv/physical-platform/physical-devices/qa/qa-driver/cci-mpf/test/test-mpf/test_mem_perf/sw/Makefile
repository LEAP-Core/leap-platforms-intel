include ../../base/sw/base_include.mk

CFLAGS += -DVCMAP_ENABLE_DEFAULT=false

all: test_mem_perf test_mem_latency

test_mem_perf: test_mem_perf.o test_mem_perf_common.o $(BASE_FILE_OBJ)
	$(CXX) $(CFLAGS) -o $@ $^ $(LDFLAGS)

test_mem_latency: test_mem_latency.o test_mem_perf_common.o $(BASE_FILE_OBJ)
	$(CXX) $(CFLAGS) -o $@ $^ $(LDFLAGS)

.cpp.o: cci_test.h $(BASE_FILE_INC)
	$(CXX) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

clean:
	$(RM) test_mem_perf test_mem_latency $(BASE_FILE_OBJ) *.o

.PHONY:all clean
