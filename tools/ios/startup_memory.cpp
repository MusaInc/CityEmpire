// Appended to the Godot-generated iOS translation unit by TestFlight CI.
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <os/proc.h>
#include <sys/time.h>

#include <cstdio>
#include <cstdlib>
#include <string>

namespace {
struct StartupMemoryTrace {
	dispatch_source_t timer;
	FILE *file;
	int samples;
};

void sample_startup_memory(void *context) {
	auto *trace = static_cast<StartupMemoryTrace *>(context);
	task_vm_info_data_t info = {};
	mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
	const auto result = task_info(mach_task_self(), TASK_VM_INFO,
			reinterpret_cast<task_info_t>(&info), &count);
	timeval now = {};
	gettimeofday(&now, nullptr);
	std::fprintf(trace->file, "STARTUP_NATIVE wall=%lld.%03d sample=%d footprint_bytes=%llu available_bytes=%zu task_info=%d\n",
			static_cast<long long>(now.tv_sec), static_cast<int>(now.tv_usec / 1000), trace->samples++,
			static_cast<unsigned long long>(info.phys_footprint), os_proc_available_memory(), result);
	std::fflush(trace->file);
	if (trace->samples >= 90) {
		std::fclose(trace->file);
		dispatch_source_cancel(trace->timer);
	}
}

void free_startup_memory_trace(void *context) {
	auto *trace = static_cast<StartupMemoryTrace *>(context);
	dispatch_release(trace->timer);
	delete trace;
}

__attribute__((constructor)) void start_startup_memory_trace() {
	const char *home = std::getenv("HOME");
	if (!home || !*home) {
		return;
	}
	const auto path = std::string(home) + "/Documents/startup-memory.log";
	std::rename(path.c_str(), (path + ".previous").c_str());
	FILE *file = std::fopen(path.c_str(), "w");
	if (!file) {
		return;
	}
	auto timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
			dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
	if (!timer) {
		std::fclose(file);
		return;
	}
	auto *trace = new StartupMemoryTrace{timer, file, 0};
	dispatch_set_context(timer, trace);
	dispatch_source_set_event_handler_f(timer, sample_startup_memory);
	dispatch_source_set_cancel_handler_f(timer, free_startup_memory_trace);
	dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
	dispatch_resume(timer);
}
} // namespace
