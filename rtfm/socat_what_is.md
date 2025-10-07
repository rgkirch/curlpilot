https://copyconstruct.medium.com/socat-29453e9fc8a6

## What is socat?

socat stands for SOcket CAT. It is a utility for data transfer between two addresses.

What makes socat so versatile is the fact that an address can represent a network socket, any file descriptor, a Unix domain datagram or stream socket, TCP and UDP (over both IPv4 and IPv6), SOCKS 4/4a over IPv4/IPv6, SCTP, PTY, datagram and stream sockets, named and unnamed pipes, raw IP sockets, OpenSSL, or on Linux even any arbitrary network device.

---

## Usage

The way I learn CLI tools is by first learning the usage of the tool, followed by committing a few simple commands to muscle memory. Usually, I can get by with those just all right. If I need to do something a little more involved, I can look at the man page, or failing that, I can Google it.

The most “basic” socat invocation would:

```
socat [options] <address> <address>
```

A more concrete example would be:

```
socat -d -d - TCP4:www.example.com:80
```

where `-d -d` would be the options, `-` would be the first address and `TCP4:www.example.com:80` would be the second address.

---

## A typical socat invocation

At first glance, this might seem like a lot to take in (and the examples in the man page are, if anything, even more inscrutable), so let’s break each component down a bit more.

Let’s first start with the address, since the address is the cornerstone aspect of socat.

---

## Addresses

In order to understand socat it’s important to understand what addresses are and how they work.

The address is something that the user provides via the command line. Invoking socat without any addresses results in:

```
~: socat2018/09/22 19:12:30 socat[15505] E exactly 2 addresses required (there are 0); use option "-h" for help
```

An address comprises of three components:

1. the address type, followed by a `:`
2. zero or more required address parameters separated by `:`
3. zero or more address options separated by `,`

---

### The anatomy of an address

#### Type

The type is used to specify the kind of address we need. Popular options are TCP4, CREATE, EXEC, GOPEN, STDIN, STDOUT, PIPE, PTY, UDP4 etc, where the names are pretty self-explanatory.

However, in the example we saw in the previous section, a socat command was represented as

```
socat -d -d - TCP4:www.example.com:80
```

where `-` was said to be one of the two addresses. This doesn’t look like a fully formed address that adheres to the aforementioned convention.

This is because certain address types have aliases. `-` is one such alias used to represend STDIO. Another alias is `TCP` which stands for TCPv4. The manpage of socat lists all other aliases.

---

#### Parameters

Immediately after the type comes zero or more required address parameters separated by `:`.

The number of address parameters depends on the address type.

The address type TCP4 requires a server specification and a port specification (number or service name). A valid address of type TCP4 established with port 80 of host www.example.com would be `TCP:www.example.com:80` .

Another example of an address would be `UDP_RECVFROM:9125` which creates a UDP socket on port 9125, receives one packet from an unspecified peer and may send one or more answer packets to that peer.

The type (like TCP or UDP_RECVFROM) is sometimes optional. Address specifications starting with a number are assumed to be of type FD(raw file descriptor) addresses. Similarly, if a `/` is found before the first `:` or `,`, then the address type is assumed to be GOPEN (generic file open).

---

#### Address Options

Address parameters can be further enhanced with options, which govern how the opening of the address is done or what the properties of the resulting bytestreams will be.

Options are specified after address parameters and they are separated from the last address parameter by a `,` (the `,` indicates when the address parameters end and when the options begin). Options can be specified either directly or with an `option_name=value` pair.

Extending the previous example, we can specify the option `retry=5` on the address to specify the number of times the connection to www.example.com needs to be retried.

```
TCP:www.example.com:80,retry=5
```

Similarly, the following address allows one to set up a TCP listening socket and fork a child process to handle all incoming client connections.

```
TCP4-LISTEN:www.example.com:80,fork

