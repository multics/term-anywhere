#include "CSSH.h"
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
static pthread_once_t init_once = PTHREAD_ONCE_INIT;
static void initialize(void) { libssh2_init(0); }
LIBSSH2_SESSION *ta_session(void) {
    pthread_once(&init_once, initialize);
    return libssh2_session_init();
}
LIBSSH2_CHANNEL *ta_channel(LIBSSH2_SESSION *s) { return libssh2_channel_open_session(s); }
int ta_exec(LIBSSH2_CHANNEL *c, const char *s) { return libssh2_channel_exec(c, s); }
int ta_shell(LIBSSH2_CHANNEL *c) { return libssh2_channel_shell(c); }
int ta_connect(const char *host, int port) {
    struct addrinfo hints = {0}, *addresses = NULL;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    char service[8]; snprintf(service, sizeof(service), "%d", port);
    if (getaddrinfo(host, service, &hints, &addresses) != 0) return -1;
    int result = -1;
    for (struct addrinfo *a = addresses; a; a = a->ai_next) {
        int fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0) continue;
        int yes = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
        fcntl(fd, F_SETFL, O_NONBLOCK);
        int status = connect(fd, a->ai_addr, a->ai_addrlen);
        if (status != 0) {
            struct pollfd p = {fd, POLLOUT, 0};
            int error = 0; socklen_t length = sizeof(error);
            status = poll(&p, 1, 10000) > 0 && getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0 ? 0 : -1;
        }
        if (status == 0) { fcntl(fd, F_SETFL, 0); result = fd; break; }
        close(fd);
    }
    freeaddrinfo(addresses);
    return result;
}
