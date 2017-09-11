#!/bin/sh
echo_error_message()
{
	error_time=$1
	if [ ${error_time} != 0 ]; then
		echo 'FAIL'
	else
		echo 'PASS'
	fi
}

# Start redis server
(redis-server &) >/dev/null 2>&1

# start proxy. Set cache timeout to 2 seconds.
(node proxy.js --maxsize=5 --expiretime=2000 --redis=localhost:6379 --test &) >/dev/null 2>&1

# Wait for 1 second so that we have everything running in background.
sleep 1

# Populate test data into redis
for i in `seq 1 10`;
do
	echo SET ${i} data_${i} | redis-cli >/dev/null 2>&1
done

error_time=0

# Test sending single request and check whether the data is correct.
echo 'Validating data correctness...'
error_time_in_current_phase=0
for i in `seq 1 10`;
do 
	(echo get ${i} | redis-cli -h 127.0.0.1 -p 9000 | grep data_${i}) >/dev/null 2>&1
	if [ $? != 0 ]; then
		echo "key $i mismatched with data in redis."
		let "error_time++"
		let "error_time_in_current_phase++"
	fi
done
echo_error_message ${error_time_in_current_phase}

# Test whether the cache expiration works.
echo 'Validating cache expiration works as expected. This may take a few seconds.'
error_time_in_current_phase=0
sleep 2.1
for i in `seq 1 10`;
do 
	(echo get ${i} | redis-cli -h 127.0.0.1 -p 9000 | grep 'false') >/dev/null 2>&1
	if [ $? != 0 ]; then
		echo "key $i does not expire in local cache as expected."
		let "error_time++"
		let "error_time_in_current_phase++"
	fi
	(echo get ${i} | redis-cli -h 127.0.0.1 -p 9000 | grep 'true') >/dev/null 2>&1
	if [ $? != 0 ]; then
		echo "key $i expires unexpectedly in local cache."
		let "error_time++"
		let "error_time_in_current_phase++"
	fi 
done
echo_error_message ${error_time_in_current_phase}

# Test whether the cache capacity works.
echo 'Validating cache capactiy setting works as expected...'
error_time_in_current_phase=0
sleep 1
for i in `seq 1 5`;
do
	(echo get ${i} | redis-cli -h 127.0.0.1 -p 9000) >/dev/null 2>&1
done
(echo get 6 | redis-cli -h 127.0.0.1 -p 9000 | grep 'false') >/dev/null 2>&1
if [ $? != 0 ]; then
	echo "key 6 should not be in local cache."
	let "error_time++"
	let "error_time_in_current_phase++"
fi
(echo get 1 | redis-cli -h 127.0.0.1 -p 9000 | grep 'false') >/dev/null 2>&1
if [ $? != 0 ]; then
	echo "key 1 should not be kicked out from local cache."
	let "error_time++"
	let "error_time_in_current_phase++"
fi
echo_error_message ${error_time_in_current_phase}

# Test concurrency.
echo 'Validating concurrency with multiple clients...'
error_time_in_current_phase=0
sleep 2.1
for i in `seq 1 5`;
do 
	(echo get $i | redis-cli -h 127.0.0.1 -p 9000 | grep -E "data_${i}|false" | wc -l > ./redis_proxy_test_$i &)
done
sleep .2
for i in `seq 1 5`;
do
	# grep should fine both data_$i and false since data is not from cache.
	# Thus expected value for wc -l should be 2.
	(cat ./redis_proxy_test_$i | grep 2) >/dev/null 2>&1
	if [ $? != 0 ]; then
		echo "Result from concurrent requests with key $i are not correct without data in local cache."
		let "error_time++"
		let "error_time_in_current_phase++"
	fi
done

# Validate cache is still valid under concurrency.
for i in `seq 1 5`;
do 
	(echo get $i | redis-cli -h 127.0.0.1 -p 9000 | grep -E "data_${i}|true" | wc -l > ./redis_proxy_test_$i &)
done
sleep .2
for i in `seq 1 5`;
do
	(cat ./redis_proxy_test_$i | grep 2) >/dev/null 2>&1
	if [ $? != 0 ]; then
		echo "Result from concurrent requests with key $i are not correct with data in local cache."
		let "error_time++"
		let "error_time_in_current_phase++"
	fi
done
echo_error_message ${error_time_in_current_phase}

echo "total error: ${error_time}"


# Kill background processes. Bye.
kill $(ps aux | grep redis-server | awk '{print $2}') >/dev/null 2>/dev/null
kill $(ps aux | grep proxy.js | awk '{print $2}') >/dev/null 2>/dev/null

# Delete temporary files created during test.
rm redis_proxy_test_*

sleep 1

if [ ${error_time} != 0 ]; then
	exit 1
fi
echo 'All tests pass!'
exit 0