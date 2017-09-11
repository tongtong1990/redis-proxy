# Redis Proxy

This is a simple node redis proxy implementation with a LRU local cache. It only supports GET operation while the SET directly goes to backend redis server. Proxy is running on 9000 port.

## Assumptions on Functionality

- Only supports GET command -- which means list, hash and object will not be supported.
- No SET/any other write command through proxy.

## High Level View

Basicaly the proxy is built on a node.js TCP server with different modules/libraries:

- Redis module to connect to redis server.
- LRU-cache moduel which is an implementation of LRU cache that supports setting capacity and expiration.
- Redis-proto module to help to encode/decode redis protocol (error encoding is implemented separately).

For each message received on socket, we will parse the command and check the local cache. If local cache does not have the key, we will get data from redis-server **asynchronously** and update the local cache. The async model makes sure that we could handle more concurrent clients.

Along with proxy.js we also have an end to end test written in shell.

## How to run proxy

node proxy.js --maxsize=5 --expiretime=20000 --redis=localhost:6379

Or run with test mode:

node proxy.js --maxsize=5 --expiretime=20000 --redis=localhost:6379 --test

proxy.js takes a few arguments from commandline:

- redis: the address and port number for the backend redis server. Default value is 127.0.0.1:6379
- maxsize: the capacity of local cache. Default value is 500.
- expiretime: the global expiration time for each element in local cache in milliseconds. Default value is 60 seconds.
- test: boolean flag to determine whether or not running proxy in a test mode. When running in test mode, additional information will be returned to specify whether or not the result comes from local cache.

After running proxy you could use any client following redis protocol to send message to proxy, e.g. redis-cli:

redis-cli -h 127.0.0.1 -p 9000

127.0.0.1:9000>ping
(error) Proxy only supports GET
127.0.0.1:9000> get 1
"data_1"

If proxy is running under test mode, the output will be:

127.0.0.1:9000> get 1
1) "data_1"
2) "false"

## How to test

We have a e2e test shell script along with the project. To run the tests:

npm test

It contains multiple end to end test cases to verify correctness of the data/capacity of cache/expiration as well as functionality under concurrency.

## Time spent on project

- Choosing npm modules: 10min
- Warm up wirh Redis Protocol: 10min
- Implementing proxy.js and debugging: 25min
- Implementing e2e test: 30min
- Documentation: 15min