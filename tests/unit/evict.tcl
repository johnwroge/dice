# Comprehensive unit tests for the EVICT command

start_server {tags {"evict"}} {
    test "EVICT: Basic eviction of specific keys" {
        r flushall
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
    
    test "EVICT: Non-existent keys return empty" {
        r flushall
        set result [r evict nonexistent1 nonexistent2 nonexistent3]
        assert_equal $result {}
    }
    
    test "EVICT: Mixed existing and non-existing keys" {
        r flushall
        r mset key1 val1 key2 val2 key3 val3
        
        # Mix of existing and non-existing keys
        set result [r evict key1 missing1 key3 missing2]
        assert_equal [lsort $result] [lsort {key1 key3}]
        
        # Verify only existing keys were evicted
        assert_equal [r exists key1] 0
        assert_equal [r exists key2] 1
        assert_equal [r exists key3] 0
    }
    
    test "EVICT: No arguments evicts one random key" {
        r flushall
        
        # Empty database returns empty
        set result [r evict]
        assert_equal $result {}
        
        # With keys in database
        r mset a 1 b 2 c 3 d 4 e 5
        set initial_count [r dbsize]
        
        set result [r evict]
        assert_equal [llength $result] 1
        
        # Verify one key was removed
        assert_equal [r dbsize] [expr {$initial_count - 1}]
        
        # The evicted key should not exist
        assert_equal [r exists [lindex $result 0]] 0
        
        # The evicted key should have been one of our keys
        assert {[lsearch -exact {a b c d e} [lindex $result 0]] >= 0}
    }
    
    test "EVICT: Multiple random evictions" {
        r flushall
        r mset k1 v1 k2 v2 k3 v3 k4 v4 k5 v5
        
        set evicted_keys {}
        
        # Evict 3 random keys one by one
        for {set i 0} {$i < 3} {incr i} {
            set result [r evict]
            assert_equal [llength $result] 1
            lappend evicted_keys [lindex $result 0]
        }
        
        # Should have 2 keys left
        assert_equal [r dbsize] 2
        
        # All evicted keys should be unique
        assert_equal [llength $evicted_keys] [llength [lsort -unique $evicted_keys]]
        
        # All evicted keys should no longer exist
        foreach key $evicted_keys {
            assert_equal [r exists $key] 0
        }
    }
    
    test "EVICT: Statistics tracking" {
        r flushall
        set initial_evicted [status_evicted_keys r]
        
        r mset k1 v1 k2 v2 k3 v3 k4 v4 k5 v5
        
        # Evict specific keys
        r evict k1 k2 k3
        
        # Evict a random key
        r evict
        
        set final_evicted [status_evicted_keys r]
        assert_equal [expr {$final_evicted - $initial_evicted}] 4
    }
    
    test "EVICT: All data types" {
        r flushall
        
        # Create different data types
        r set string_key "string_value"
        r lpush list_key item1 item2 item3
        r hset hash_key field1 val1 field2 val2
        r sadd set_key member1 member2 member3
        r zadd zset_key 1 member1 2 member2 3 member3
        r xadd stream_key * field value
        
        set result [r evict string_key list_key hash_key set_key zset_key stream_key]
        assert_equal [llength $result] 6
        
        # All keys should be gone
        assert_equal [r exists string_key list_key hash_key set_key zset_key stream_key] 0
    }
    
    test "EVICT: Large values eviction" {
        r flushall
        
        # Create keys with large values
        set large_value [string repeat "x" 1000000]  ;# 1MB
        r set large1 $large_value
        r set large2 $large_value
        r set small "tiny"
        
        set result [r evict large1 large2]
        assert_equal [lsort $result] [lsort {large1 large2}]
        
        # Large keys should be gone, small should remain
        assert_equal [r exists large1] 0
        assert_equal [r exists large2] 0
        assert_equal [r exists small] 1
    }
    
    test "EVICT: Keys with special characters" {
        r flushall
        
        # Keys with special characters
        r set "key:with:colons" value1
        r set "key-with-dashes" value2
        r set "key.with.dots" value3
        r set "key_with_underscores" value4
        r set "key with spaces" value5
        
        set result [r evict "key:with:colons" "key.with.dots" "key with spaces"]
        assert_equal [llength $result] 3
        
        # Verify evicted keys don't exist
        assert_equal [r exists "key:with:colons"] 0
        assert_equal [r exists "key.with.dots"] 0
        assert_equal [r exists "key with spaces"] 0
        
        # Others should still exist
        assert_equal [r exists "key-with-dashes"] 1
        assert_equal [r exists "key_with_underscores"] 1
    }
    
    test "EVICT: Expired keys handling" {
        r flushall
        
        r set key_expire value ex 1
        r set key_normal value
        
        after 1100  ;# Wait for expiration
        
        # Expired key should not be returned in eviction list
        set result [r evict key_expire key_normal]
        assert_equal $result {key_normal}
        
        # Both should be gone now
        assert_equal [r exists key_expire key_normal] 0
    }
    
    test "EVICT: Database selection" {
        r flushall
        r select 0
        r mset k1 v1 k2 v2 k3 v3
        
        r select 1
        r mset k1 v1 k2 v2
        
        # Evict from DB 1
        set result [r evict k1]
        assert_equal $result {k1}
        
        # Check DB 1
        assert_equal [r exists k1] 0
        assert_equal [r exists k2] 1
        
        # Check DB 0 - should be unchanged
        r select 0
        assert_equal [r exists k1] 1
        assert_equal [r exists k2] 1
        assert_equal [r exists k3] 1
    }
    
    test "EVICT: Empty database edge case" {
        r flushall
        
        # Multiple attempts on empty DB
        for {set i 0} {$i < 5} {incr i} {
            set result [r evict]
            assert_equal $result {}
        }
        
        # Evict with non-existent keys on empty DB
        set result [r evict key1 key2 key3]
        assert_equal $result {}
    }
    
    test "EVICT: Single key database" {
        r flushall
        r set only_key only_value
        
        set result [r evict]
        assert_equal $result {only_key}
        assert_equal [r dbsize] 0
        
        # Try again on now-empty DB
        set result [r evict]
        assert_equal $result {}
    }
    
    test "EVICT: Concurrent evictions" {
        r flushall
        r mset k1 v1 k2 v2 k3 v3 k4 v4 k5 v5 k6 v6 k7 v7 k8 v8
        
        # Evict multiple sets of keys
        set result1 [r evict k1 k2]
        set result2 [r evict k3 k4]
        set result3 [r evict k5 k6]
        
        assert_equal [lsort $result1] [lsort {k1 k2}]
        assert_equal [lsort $result2] [lsort {k3 k4}]
        assert_equal [lsort $result3] [lsort {k5 k6}]
        
        # Only k7 and k8 should remain
        assert_equal [r dbsize] 2
        assert_equal [r exists k7] 1
        assert_equal [r exists k8] 1
    }
}

# Keyspace notification tests
start_server {tags {"evict" "pubsub"}} {
    test "EVICT: Keyspace notifications" {
        r flushall
        r config set notify-keyspace-events Ke

        # Subscribe to keyspace notifications
        set rd1 [valkey_deferring_client]
        $rd1 psubscribe "__keyspace@*__:*"
        $rd1 read  ;# Read subscription confirmation

        # Create and evict a key
        r set test_key test_value
        r evict test_key

        # Check for evicted notification
        set msg [$rd1 read]
        assert_equal [lindex $msg 0] "pmessage"
        assert_match "*evicted*" [lindex $msg 3]

        $rd1 close
    }
    
    test "EVICT: Multiple keyspace notifications" {
        r flushall
        r config set notify-keyspace-events Ke

        # Create multiple keys BEFORE subscribing to avoid SET notifications
        r set k1 v1
        r set k2 v2
        r set k3 v3

        # Now subscribe to keyspace notifications
        set rd1 [valkey_deferring_client]
        $rd1 psubscribe "__keyspace@*__:*"
        $rd1 read  ;# Read subscription confirmation

        # Evict them
        r evict k1 k2 k3

        # Should receive 3 evicted notifications (one per key)
        set msg1 [$rd1 read]
        set msg2 [$rd1 read]
        set msg3 [$rd1 read]

        assert_equal [lindex $msg1 0] "pmessage"
        assert_match "*evicted*" [lindex $msg1 3]

        assert_equal [lindex $msg2 0] "pmessage"
        assert_match "*evicted*" [lindex $msg2 3]

        assert_equal [lindex $msg3 0] "pmessage"
        assert_match "*evicted*" [lindex $msg3 3]

        $rd1 close
    }
}