#include <pcap/pcap.h>
#include <sys/ioctl.h>
#include <net/bpf.h>

// Swift가 직접 가져오지 못하는 ioctl 매크로를 상수로 노출한다.
static const unsigned long DJLINK_BIOCIMMEDIATE = BIOCIMMEDIATE;
