#pragma once
#include "libssh2.h"
int ta_connect(const char *host, int port);
LIBSSH2_SESSION *ta_session(void);
LIBSSH2_CHANNEL *ta_channel(LIBSSH2_SESSION *session);
int ta_exec(LIBSSH2_CHANNEL *channel, const char *command);
int ta_shell(LIBSSH2_CHANNEL *channel);
