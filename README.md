plic
====

Use plic to send a one-time secret message.

Get started
-----------

    shards install
    crystal run src/plic.cr

Open [localhost:8080](http://localhost:8080).

Security
--------

### Client

WebCrypto is used for all cryptographic operations in the browser. Messages are
encrypted using AES-128-GCM and the authentication tag is used as a unique ID.
When using a password, the secret key is derived using PBKDF2-HMAC-SHA256 with
100000 iterations. No external resources (such as scripts, styles and links)
are used. The webpage is loaded in a single request and is less than 250 lines
long which can be easily reviewed.

### Server

Strict security headers (including CSP and HSTS) are set on all requests. No
data is stored other than the encrypted blob and the ID (which is extracted
from the blob). No logs are kept on the server.
