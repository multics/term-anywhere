# Third-party code

| Component | Pinned version | Use |
| --- | --- | --- |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.20.0; `5d14406844143538cd8f8851d2d8a67c1fe443e5` | Terminal rendering and input |
| [libssh2](https://github.com/libssh2/libssh2) | `bb8e0957b8091e5b6668b2ffe647721f5cc2fb7d` | SSH transport and key authentication |
| [OpenSSL framework package](https://github.com/krzyzanowskim/OpenSSL) | 3.6.3000; `4b1188ba947ddc23d03b13096b9e44b804e146c9` | libssh2 cryptography |

License texts are included in `App/ThirdPartyNotices.txt` and in the app bundle. The libssh2 public header in `Sources/CSSH/include/libssh2.h` is an upstream copy with its license notice. OpenSSL is an embedded dynamic framework.

The [AWS Session Manager plugin](https://github.com/aws/session-manager-plugin) was used as a protocol reference for the narrow SSM implementation. The app does not bundle or run that desktop plugin.
