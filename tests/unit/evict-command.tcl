# Test the EVICT command

start_server {tags {"evict"}} {
    test "EVICT basic functionality" {
        r set key1 value1
        r set key2 value2
        r set key3 value3
        
        # Evict specific keys
        set result [r evict key1 key3]
        assert_equal [lsort $result] [lsort {key1 key3}]
        
        # Verify keys are gone
        assert_equal [r exists key1] 0
        assert_equal [r exists key2] 1
        assert_equal [r exists key3] 0
    }
    
    test "EVICT non-existent keys" {
        # Try to evict keys that don't exist
        set result [r evict nonexistent1 nonexistent2]
        assert_equal $result {}
    }
    
    test "EVICT mixed existing and non-existing keys" {
        r set existing_key value
        set result [r evict existing_key missing_key]
        assert_equal $result {existing_key}
        
        # Verify existing key was evicted
        assert_equal [r exists existing_key] 0
    }
    
    test "EVICT with no arguments evicts random key" {
        # Empty database, EVICT with no args should return empty array
        r flushall
        set result [r evict]
        assert_equal $result {}
        
        # With keys in database, should evict one random key
        r mset key1 val1 key2 val2 key3 val3
        set result [r evict]
        assert_equal [llength $result] 1
        
        # The evicted key should be one of the three
        assert {[lsearch -exact {key1 key2 key3} [lindex $result 0]] >= 0}
        
        # Only 2 keys should remain
        assert_equal [r dbsize] 2
        
        # The evicted key should not exist
        assert_equal [r exists [lindex $result 0]] 0
    }
    
    test "EVICT increments evicted_keys stat" {
        r flushall
        set initial_evicted [status_evicted_keys r]
        
        r mset key1 val1 key2 val2 key3 val3
        r evict key1 key2
        
        set final_evicted [status_evicted_keys r]
        assert_equal [expr {$final_evicted - $initial_evicted}] 2
    }
    
    test "EVICT triggers keyspace notifications" {
        r flushall
        r config set notify-keyspace-events KEe

        # Subscribe to keyspace notifications
        set rd1 [valkey_deferring_client]
        $rd1 psubscribe "__key*__:*"
        $rd1 read  ;# Read subscription confirmation

        # Create and evict a key
        r set notify_key notify_value
        r evict notify_key

        # Check for evicted notification
        set msg [$rd1 read]
        assert_equal [lindex $msg 0] "pmessage"
        assert_match "*evicted*" [lindex $msg 3]

        $rd1 close
    }
    
    test "EVICT works with different data types" {
        r flushall
        
        # String
        r set str_key str_value
        # List  
        r lpush list_key item1 item2
        # Hash
        r hset hash_key field value
        # Set
        r sadd set_key member1 member2
        # Sorted set
        r zadd zset_key 1 member1 2 member2
        
        set result [r evict str_key list_key hash_key set_key zset_key]
        assert_equal [llength $result] 5
        
        # All keys should be gone
        assert_equal [r exists str_key list_key hash_key set_key zset_key] 0
    }
    
    test "EVICT respects TTL and expires keys first" {
        r flushall
        
        r set key_with_ttl value ex 1
        r set normal_key value
        
        after 1100  ;# Wait for key to expire
        
        # Try to evict both - expired key should not be counted
        set result [r evict key_with_ttl normal_key]
        assert_equal $result {normal_key}
        
        # Both keys should be gone (one evicted, one expired)
        assert_equal [r exists key_with_ttl normal_key] 0
    }
}