const RedisProto = require('redis-proto');

var net = require('net');
var redis = require('redis');
var argv = require('minimist')(process.argv.slice(2));
var maxCacheSize = argv.maxsize || 500;
var maxCacheAge = argv.expiretime || 1000 * 60;
var redisServerAddr = argv.redis || '127.0.0.1:6379'
var redisHostAddress = redisServerAddr.split(":")[0];
var redisHostPort = parseInt(redisServerAddr.split(":")[1], 10);
var testMode = argv.test;
var redisClient = redis.createClient({host : redisHostAddress, port : redisHostPort});
var LRU = require('lru-cache');

var cacheOptions = {
	max: maxCacheSize,
	maxAge: maxCacheAge
};

var cache = LRU(cacheOptions);
var server = net.createServer();

server.on('connection', handleConnection);

server.listen(9000, function() {
  redisClient.on('ready',function() {
    console.log("Redis is ready");
  });

  redisClient.on('error',function() {
    console.log("Error in Redis: " + redisHostAddress + ":" + redisHostPort);
  });
  console.log('server listening to %j', server.address());
});

function handleGetFromCache(conn, key) {
  if (cache.has(key)) {
    writeResultToSocket(conn, cache.get(key), true);
  } else {
    redisClient.get(key, function(err, result) {
      if (err) conn.write('-error from redis server\r\n');
      else {
        cache.set(key, result);
        writeResultToSocket(conn, result, false);
      }
    });
  }
}

function writeResultToSocket(conn, result, isFromCache) {
  console.log(testMode);
  if (testMode) conn.write(RedisProto.encode([result, isFromCache]));
  else conn.write(RedisProto.encode(result));
}

function handleConnection(conn) {
  var remoteAddress = conn.remoteAddress + ':' + conn.remotePort;
  console.log('new client connection from %s', remoteAddress);

  conn.on('data', onConnData);
  conn.once('close', onConnClose);
  conn.on('error', onConnError);

  function onConnData(d) {
    var commandList = RedisProto.decode(d)[0];
    console.log(commandList);
    var command = commandList.length > 0 ? commandList[0] : 'UNKNOWN';
    if (command.toUpperCase() != 'GET') {
      conn.write('-Proxy only supports GET\r\n');
    } else if (commandList.length != 2) {
      conn.write('-Get command with wrong number of arguments.\r\n');
    } else {
      handleGetFromCache(conn, commandList[1]);
    }
  }

  function onConnClose() {
    console.log('connection from %s closed', remoteAddress);
  }

  function onConnError(err) {
    console.log('Connection %s error: %s', remoteAddress, err.message);
  }
}