#include <CoreFoundation/CoreFoundation.h>
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include "OfflineSandbox.h"

static int expect_denied(int type) {
    int fd = socket(AF_INET, type, 0);
    if (fd < 0) {
        return errno == EPERM || errno == EACCES ? 0 : 1;
    }
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(9);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    int result = type == SOCK_STREAM
        ? connect(fd, (struct sockaddr *)&address, sizeof(address))
        : (int)sendto(fd, "x", 1, 0, (struct sockaddr *)&address, sizeof(address));
    int error = errno;
    close(fd);
    if (result == -1 && (error == EPERM || error == EACCES)) {
        return 0;
    }
    fprintf(stderr, "Socket operation escaped offline policy: result=%d errno=%d\n", result, error);
    return 1;
}

static CFDataRef reply(CFMessagePortRef port, SInt32 message, CFDataRef data, void *context) {
    (void)port; (void)message; (void)data; (void)context;
    return NULL;
}

int main(void) {
    char *error = NULL;
    if (AltTabEnableOfflineSandbox(&error) != 0) {
        fprintf(stderr, "Offline sandbox failed: %s\n", error ? error : "unknown");
        if (error) AltTabFreeSandboxError(error);
        return 1;
    }
    if (expect_denied(SOCK_STREAM) || expect_denied(SOCK_DGRAM)) return 1;
    CFStringRef name = CFStringCreateWithFormat(NULL, NULL, CFSTR("com.houskii.alttab.offline-probe.%d"), getpid());
    CFMessagePortRef port = CFMessagePortCreateLocal(NULL, name, reply, NULL, NULL);
    CFRelease(name);
    if (!port) {
        fprintf(stderr, "Offline policy blocked local command IPC\n");
        return 1;
    }
    CFMessagePortInvalidate(port);
    CFRelease(port);
    puts("PASS: TCP and UDP blocked by macOS; local Mach IPC remains available");
    return 0;
}
