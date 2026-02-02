# REFERENCES: WebSocket Protocol Standards

## Core Protocol Specifications

### RFC 6455 - The WebSocket Protocol
**Primary WebSocket Specification**
- URL: https://tools.ietf.org/html/rfc6455
- Defines the WebSocket protocol
- Covers handshake, frame format, opcode definitions
- Specifies connection lifecycle and error handling
- Defines close codes and reasons

## Extensions & Related Protocols

### RFC 7692 - Compression Extensions for WebSocket
**Permessage-deflate Compression**
- URL: https://tools.ietf.org/html/rfc7692
- Defines compression extension for WebSocket
- Specifies permessage-deflate algorithm
- Covers negotiation and parameter handling

### RFC 6455 Related Documents

#### WebSocket API (W3C)
**JavaScript API for WebSocket**
- URL: https://websockets.spec.whatwg.org/
- Defines the WebSocket interface for browsers
- Specifies event handling and API methods

#### RFC 8441 - Bootstrapping WebSockets with HTTP/2
**HTTP/2 WebSocket Support**
- URL: https://tools.ietf.org/html/rfc8441
- Defines WebSocket over HTTP/2
- Covers CONNECT method usage
- Specifies HTTP/2 stream handling

## Related HTTP Specifications

### RFC 7230 - HTTP/1.1 Message Syntax and Routing
**HTTP Message Format**
- URL: https://tools.ietf.org/html/rfc7230
- HTTP request/response format
- Header handling
- Connection management
- (Obsoletes RFC 2616)

### RFC 7231 - HTTP/1.1 Semantics and Content
**HTTP Methods and Status Codes**
- URL: https://tools.ietf.org/html/rfc7231
- HTTP methods (GET, POST, etc.)
- Status codes
- Content negotiation
- (Obsoletes RFC 2616)

### RFC 7234 - HTTP Caching
**HTTP Caching**
- URL: https://tools.ietf.org/html/rfc7234
- Cache headers and behavior
- Relevant for handshake caching

### RFC 7235 - HTTP/1.1 Authentication
**HTTP Authentication**
- URL: https://tools.ietf.org/html/rfc7235
- WWW-Authenticate and Authorization headers
- Relevant for WebSocket authentication

## Security Specifications

### RFC 6265 - HTTP State Management Mechanism
**Cookies**
- URL: https://tools.ietf.org/html/rfc6265
- Cookie handling in HTTP
- Relevant for session management in WebSocket handshake

### RFC 6797 - HTTP Strict Transport Security (HSTS)
**HTTPS Enforcement**
- URL: https://tools.ietf.org/html/rfc6797
- HSTS header and behavior
- Relevant for secure WebSocket (wss://) connections

### RFC 7469 - Public Key Pinning Extension for HTTP
**HPKP**
- URL: https://tools.ietf.org/html/rfc7469
- Certificate pinning
- Relevant for secure WebSocket connections

## Transport & Security

### RFC 5246 - The Transport Layer Security (TLS) Protocol Version 1.2
**TLS 1.2**
- URL: https://tools.ietf.org/html/rfc5246
- TLS handshake and record layer
- Relevant for wss:// (WebSocket Secure)

### RFC 8446 - The Transport Layer Security (TLS) Protocol Version 1.3
**TLS 1.3**
- URL: https://tools.ietf.org/html/rfc8446
- Modern TLS protocol
- Performance improvements
- Security enhancements

## Encoding & Compression

### RFC 1951 - DEFLATE Compressed Data Format Specification
**DEFLATE Algorithm**
- URL: https://tools.ietf.org/html/rfc1951
- Base compression algorithm
- Used by permessage-deflate extension

### RFC 1952 - GZIP File Format Specification
**GZIP Format**
- URL: https://tools.ietf.org/html/rfc1952
- GZIP compression format
- Related to compression extensions

### RFC 3629 - UTF-8, a transformation format of ISO 10646
**UTF-8 Encoding**
- URL: https://tools.ietf.org/html/rfc3629
- Text encoding for WebSocket text frames
- Character encoding specification

## Test Suites & Compliance

### Autobahn Test Suite
**WebSocket Conformance Testing**
- URL: https://github.com/crossbario/autobahn-testsuite
- Comprehensive WebSocket protocol tests
- Fuzzing and conformance testing
- Industry standard for WebSocket validation

## IANA Registries

### WebSocket Subprotocol Name Registry
**Registered Subprotocols**
- URL: https://www.iana.org/assignments/websocket/websocket.xhtml#subprotocol-name
- List of registered WebSocket subprotocols

### WebSocket Extension Name Registry
**Registered Extensions**
- URL: https://www.iana.org/assignments/websocket/websocket.xhtml#extension-name
- List of registered WebSocket extensions

### WebSocket Close Code Number Registry
**Close Codes**
- URL: https://www.iana.org/assignments/websocket/websocket.xhtml#close-code-number
- Registered close codes and meanings

### WebSocket Opcode Registry
**Frame Opcodes**
- URL: https://www.iana.org/assignments/websocket/websocket.xhtml#opcode
- Opcode assignments for different frame types

## Additional Resources

### MDN Web Docs - WebSocket API
**Developer Documentation**
- URL: https://developer.mozilla.org/en-US/docs/Web/API/WebSocket
- Browser WebSocket API reference
- Usage examples and best practices

### WHATWG WebSocket Protocol Living Standard
**Living Specification**
- URL: https://websockets.spec.whatwg.org/
- Current WebSocket protocol specification
- Maintained by WHATWG

### Ecosystem Libraries (For Reference)
- **Cowboy**: https://github.com/ninenines/cowboy (Erlang/Elixir WebSocket)
- **WebSockex**: https://github.com/Azolo/websockex (Elixir WebSocket client)
- **Websocket-client**: https://github.com/jeremyevans/websocket-client (Ruby)
- **ws**: https://github.com/websockets/ws (Node.js)
