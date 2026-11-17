#include <sandbox.h>
#include "OfflineSandbox.h"

// Native window tracking needs broad local access, so use a network-only profile rather than App Sandbox.
// Keep the deprecated Seatbelt entry point in this wrapper; startup fails closed if macOS rejects it.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
int AltTabEnableOfflineSandbox(char **error) {
    return sandbox_init(kSBXProfileNoNetwork, SANDBOX_NAMED, error);
}
void AltTabFreeSandboxError(char *error) {
    sandbox_free_error(error);
}
#pragma clang diagnostic pop
