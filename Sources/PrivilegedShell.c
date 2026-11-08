#include <Security/Authorization.h>
#include <stdio.h>

int BIOpenPrivilegedShell(AuthorizationRef authorization, FILE **pipe) {
    char *args[] = {"-s", NULL};
    return (int)AuthorizationExecuteWithPrivileges(
        authorization,
        "/bin/sh",
        kAuthorizationFlagDefaults,
        args,
        pipe
    );
}
