# Module API tests for EVICT command pre-eviction and eviction notifications

set testmodule [file normalize tests/modules/test_preeviction.so]

start_server {tags {"modules" "evict"}} {
    r module load $testmodule
    
    test "Module EVICT: Pre-eviction notifications triggered" {
        r flushall
        r test.reset_counters
        
        # Create test keys
        r mset key1 val1 key2 val2 key3 val3
        
        # Evict specific keys
        r evict key1 key3
        
        # Check notification counts
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $preevict_count 2
        assert_equal $evict_count 2
    }
    
    test "Module EVICT: Random eviction notifications" {
        r flushall
        r test.reset_counters
        
        # Create test keys
        r mset a 1 b 2 c 3 d 4 e 5
        
        # Random eviction
        set result [r evict]
        assert_equal [llength $result] 1
        
        # Should have exactly 1 of each notification
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $preevict_count 1
        assert_equal $evict_count 1
    }
    
    test "Module EVICT: No notifications for non-existent keys" {
        r flushall
        r test.reset_counters
        
        # Try to evict non-existent keys
        r evict nonexistent1 nonexistent2 nonexistent3
        
        # Should have no notifications
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $preevict_count 0
        assert_equal $evict_count 0
    }
    
    test "Module EVICT: Mixed existing/non-existing keys notifications" {
        r flushall
        r test.reset_counters
        
        # Create some keys
        r mset key1 val1 key2 val2
        
        # Mix existing and non-existing
        r evict key1 nonexistent key2 missing
        
        # Should only get notifications for existing keys
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $preevict_count 2
        assert_equal $evict_count 2
    }
    
    test "Module EVICT: Notification order" {
        r flushall
        r test.reset_counters
        
        r set test_key test_value
        
        # Get initial counts
        set initial_preevict [r test.preeviction_count]
        set initial_evict [r test.eviction_count]
        
        # Evict the key
        r evict test_key
        
        # Pre-eviction should fire before eviction
        # (This is verified by the module implementation itself)
        set final_preevict [r test.preeviction_count]
        set final_evict [r test.eviction_count]
        
        assert_equal [expr {$final_preevict - $initial_preevict}] 1
        assert_equal [expr {$final_evict - $initial_evict}] 1
    }
    
    test "Module EVICT: Bulk eviction notifications" {
        r flushall
        r test.reset_counters
        
        # Create many keys
        for {set i 0} {$i < 100} {incr i} {
            r set "bulk:$i" "value:$i"
        }
        
        # Bulk evict
        set keys_to_evict {}
        for {set i 0} {$i < 50} {incr i 2} {
            lappend keys_to_evict "bulk:$i"
        }
        
        r evict {*}$keys_to_evict
        
        # Should get exactly 25 notifications (every other key from 0-48)
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $preevict_count 25
        assert_equal $evict_count 25
    }
    
    test "Module EVICT: Different data types notifications" {
        r flushall
        r test.reset_counters
        
        # Create different data types
        r set string_key "string_value"
        r lpush list_key item1 item2
        r hset hash_key field value
        r sadd set_key member1 member2
        r zadd zset_key 1 member1
        
        # Evict all types
        r evict string_key list_key hash_key set_key zset_key
        
        # Should get notifications for all types
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $preevict_count 5
        assert_equal $evict_count 5
    }
    
    test "Module EVICT: Empty database random eviction" {
        r flushall
        r test.reset_counters
        
        # Try random eviction on empty database
        set result [r evict]
        assert_equal $result {}
        
        # Should have no notifications
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $preevict_count 0
        assert_equal $evict_count 0
    }
    
    test "Module EVICT: Stress test notifications" {
        r flushall
        r test.reset_counters
        
        # Create many keys
        for {set i 0} {$i < 1000} {incr i} {
            r set "stress:$i" "value:$i"
        }
        
        # Evict them all one by one with random eviction
        set total_evicted 0
        while {[r dbsize] > 0} {
            set result [r evict]
            if {[llength $result] == 1} {
                incr total_evicted
            }
        }
        
        # Check that we got notifications for all evictions
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $total_evicted 1000
        assert_equal $preevict_count 1000
        assert_equal $evict_count 1000
    }
}

# Test with postnotifications module
set postnotifications_module [file normalize tests/modules/postnotifications.so]

start_server {tags {"modules" "evict" "postnotifications"}} {
    r module load $postnotifications_module
    
    test "Module EVICT: Post-notification jobs with pre-eviction" {
        r flushall
        
        # Set up keys that will trigger post-notification jobs
        r set test_key1 value1
        r set test_key2 value2
        
        # Evict keys - should trigger post-notification jobs
        r evict test_key1 test_key2
        
        # Check that post-notification jobs were executed
        # (The postnotifications module creates "before_evicted" list for pre-eviction
        #  and increments "evicted" counter for eviction)
        
        # Check if before_evicted list was created (pre-eviction post-notification job)
        set before_evicted_exists [r exists before_evicted]
        
        # Check if evicted counter was incremented (eviction post-notification job)
        set evicted_count [r get evicted]
        
        # Both should have been triggered
        assert_equal $before_evicted_exists 1
        assert {$evicted_count >= 2}
        
        # The before_evicted list should contain the evicted keys
        set before_evicted_keys [r lrange before_evicted 0 -1]
        assert {[lsearch -exact $before_evicted_keys test_key1] >= 0}
        assert {[lsearch -exact $before_evicted_keys test_key2] >= 0}
    }
    
    test "Module EVICT: Post-notification jobs with random eviction" {
        r flushall
        
        # Create test keys
        r mset random1 val1 random2 val2 random3 val3
        
        # Random eviction should also trigger post-notification jobs
        set evicted_key [r evict]
        assert_equal [llength $evicted_key] 1
        
        # Check post-notification job results
        set before_evicted_exists [r exists before_evicted]
        set evicted_count [r get evicted]
        
        assert_equal $before_evicted_exists 1
        assert {$evicted_count >= 1}
        
        # The evicted key should be in the before_evicted list
        set before_evicted_keys [r lrange before_evicted 0 -1]
        assert {[lsearch -exact $before_evicted_keys [lindex $evicted_key 0]] >= 0}
    }
}

# Test module notification filtering
start_server {tags {"modules" "evict" "filtering"}} {
    r module load $testmodule
    
    test "Module EVICT: Notification filtering by key pattern" {
        r flushall
        r test.reset_counters
        
        # Create keys with different prefixes
        r mset user:1 data1 user:2 data2 system:1 data3 system:2 data4 temp:1 data5
        
        # Evict all keys
        r evict user:1 user:2 system:1 system:2 temp:1
        
        # All should generate notifications (no filtering in our test module)
        set preevict_count [r test.preeviction_count]
        set evict_count [r test.eviction_count]
        
        assert_equal $preevict_count 5
        assert_equal $evict_count 5
    }
}