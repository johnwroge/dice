# Integration tests for EVICT command covering replication, persistence, and clustering scenarios

# Helper procedures
proc get_evicted_keys {client} {
    set info [$client info stats]
    if {[regexp {evicted_keys:(\d+)} $info -> evicted_keys]} {
        return $evicted_keys
    }
    return 0
}

proc get_used_memory {client} {
    set info [$client info memory]
    if {[regexp {used_memory:(\d+)} $info -> used_memory]} {
        return $used_memory
    }
    return 0
}

proc wait_replica_sync {master replica} {
    wait_for_ofs_sync $master $replica
}

# EVICT command replication tests
start_server {tags {"evict" "repl"}} {
    start_server {} {
        test "EVICT: Basic replication" {
            set master [srv -1 client]
            set replica [srv 0 client]
            
            $replica replicaof 127.0.0.1 [srv -1 port]
            wait_for_sync $replica
            
            # Set keys on master
            $master mset key1 val1 key2 val2 key3 val3
            wait_replica_sync $master $replica
            
            # Verify keys exist on both
            assert_equal [$master exists key1 key2 key3] 3
            assert_equal [$replica exists key1 key2 key3] 3
            
            # Evict keys on master
            set result [$master evict key1 key3]
            assert_equal [lsort $result] [lsort {key1 key3}]
            wait_replica_sync $master $replica
            
            # Verify eviction replicated
            assert_equal [$master exists key1] 0
            assert_equal [$master exists key2] 1
            assert_equal [$master exists key3] 0
            
            assert_equal [$replica exists key1] 0
            assert_equal [$replica exists key2] 1
            assert_equal [$replica exists key3] 0
        }
        
        test "EVICT: Random eviction replication" {
            set master [srv -1 client]
            set replica [srv 0 client]
            
            $master flushall
            wait_replica_sync $master $replica
            
            # Set keys on master
            $master mset a 1 b 2 c 3 d 4 e 5
            wait_replica_sync $master $replica
            
            # Random eviction on master
            set evicted [$master evict]
            assert_equal [llength $evicted] 1
            wait_replica_sync $master $replica
            
            # Verify random eviction replicated
            set evicted_key [lindex $evicted 0]
            assert_equal [$master exists $evicted_key] 0
            assert_equal [$replica exists $evicted_key] 0
            
            # Both should have same remaining keys
            assert_equal [$master dbsize] 4
            assert_equal [$replica dbsize] 4
        }
        
        test "EVICT: Eviction statistics replication" {
            set master [srv -1 client]
            set replica [srv 0 client]
            
            $master flushall
            wait_replica_sync $master $replica
            
            # Get initial stats
            set master_initial [get_evicted_keys $master]
            set replica_initial [get_evicted_keys $replica]
            
            # Evict keys on master
            $master mset k1 v1 k2 v2 k3 v3
            wait_replica_sync $master $replica
            $master evict k1 k2 k3
            wait_replica_sync $master $replica
            
            # Check statistics
            set master_final [get_evicted_keys $master]
            set replica_final [get_evicted_keys $replica]
            
            assert_equal [expr {$master_final - $master_initial}] 3
            assert_equal [expr {$replica_final - $replica_initial}] 3
        }
        
        test "EVICT: Read-only replica cannot evict" {
            set master [srv -1 client]
            set replica [srv 0 client]
            
            $master mset k1 v1 k2 v2
            wait_replica_sync $master $replica
            
            # Try to evict on replica - should fail
            catch {$replica evict k1} err
            assert_match "*READONLY*" $err
            
            # Keys should still exist
            assert_equal [$replica exists k1 k2] 2
        }
    }
}

# EVICT command persistence tests
start_server {tags {"evict" "persist"}} {
    test "EVICT: AOF persistence" {
        r flushall
        r config set appendonly yes
        r config set appendfsync always

        # Wait for AOF rewrite to complete
        waitForBgrewriteaof r

        # Create and evict keys
        r mset eapkey1 val1 eapkey2 val2 eapkey3 val3
        r evict eapkey1 eapkey3

        # Persist config and restart server
        r config rewrite
        restart_server 0 true false
        wait_done_loading r

        # Verify state after restart
        assert_equal [r exists eapkey1] 0
        assert_equal [r exists eapkey2] 1
        assert_equal [r exists eapkey3] 0

        # Clean up: disable AOF for next test
        r flushall
        r config set appendonly no
        r config rewrite
    }
    
    test "EVICT: AOF with random eviction" {
        r flushall
        r config set appendonly yes
        r config set appendfsync always

        # Wait for AOF rewrite to complete
        waitForBgrewriteaof r

        # Create keys and do random eviction
        r mset a 1 b 2 c 3 d 4 e 5
        set evicted [r evict]
        set evicted_key [lindex $evicted 0]

        # Persist config and restart server
        r config rewrite
        restart_server 0 true false
        wait_done_loading r

        # Verify evicted key is still gone
        assert_equal [r exists $evicted_key] 0
        assert_equal [r dbsize] 4

        # Clean up: disable AOF for next test
        r flushall
        r config set appendonly no
        r config rewrite
    }

    test "EVICT: RDB persistence" {
        r flushall
        # Ensure AOF is disabled
        r config set appendonly no
        r config set save "1 1"  ;# Save every second if at least 1 key changed

        # Create and evict keys
        r mset k1 v1 k2 v2 k3 v3 k4 v4
        r evict k1 k3

        # Force save and restart
        r bgsave
        waitForBgsave r
        restart_server 0 false true

        # Verify state after restart
        assert_equal [r exists k1 k3] 0
        assert_equal [r exists k2 k4] 2
    }
}

# Memory management integration tests
start_server {tags {"evict" "memory"}} {
    test "EVICT: Memory usage after eviction" {
        r flushall
        
        # Get initial memory usage
        set initial_memory [get_used_memory r]
        
        # Create large keys
        set large_value [string repeat "x" 100000]
        r mset large1 $large_value large2 $large_value large3 $large_value
        
        set after_set_memory [get_used_memory r]
        assert {$after_set_memory > $initial_memory}
        
        # Evict large keys
        r evict large1 large2 large3
        
        set after_evict_memory [get_used_memory r]
        assert {$after_evict_memory < $after_set_memory}
    }
    
    test "EVICT: Manual vs automatic eviction behavior" {
        r flushall

        # Set memory limit low enough to trigger automatic eviction
        r config set maxmemory 1mb
        r config set maxmemory-policy allkeys-lru

        # Create keys that exceed memory limit
        set large_value [string repeat "x" 200000]
        for {set i 0} {$i < 10} {incr i} {
            catch {r set "auto_key$i" $large_value}
        }

        # Some keys should have been automatically evicted
        set auto_remaining [r dbsize]

        # Now test manual eviction
        r config set maxmemory 0  ;# Remove memory limit
        r flushall

        # Create same keys manually
        for {set i 0} {$i < 10} {incr i} {
            r set "manual_key$i" $large_value
        }

        # Manually evict specific keys
        r evict manual_key0 manual_key1 manual_key2 manual_key3 manual_key4
        set manual_remaining [r dbsize]

        assert_equal $manual_remaining 5

        # Reset maxmemory to 0 to avoid affecting subsequent tests
        r config set maxmemory 0
    }
}

# Performance and stress tests
start_server {tags {"evict" "stress"}} {
    test "EVICT: Large scale eviction" {
        r flushall
        
        # Create many keys
        set num_keys 10000
        for {set i 0} {$i < $num_keys} {incr i} {
            r set "key:$i" "value:$i"
        }
        assert_equal [r dbsize] $num_keys
        
        # Evict half of them in batches
        set to_evict {}
        for {set i 0} {$i < $num_keys} {incr i 2} {
            lappend to_evict "key:$i"
            if {[llength $to_evict] >= 100} {
                r evict {*}$to_evict
                set to_evict {}
            }
        }
        if {[llength $to_evict] > 0} {
            r evict {*}$to_evict
        }
        
        # Should have roughly half remaining
        set remaining [r dbsize]
        assert {$remaining >= 4900 && $remaining <= 5000}
    }
    
    test "EVICT: Random eviction patterns" {
        r flushall
        
        # Create initial set
        for {set i 0} {$i < 1000} {incr i} {
            r set "test:$i" "data:$i"
        }
        
        # Random eviction loop
        set evicted_total 0
        while {[r dbsize] > 100} {
            set result [r evict]
            if {[llength $result] == 1} {
                incr evicted_total
            }
        }
        
        # Should have evicted 900 keys
        assert_equal $evicted_total 900
        assert_equal [r dbsize] 100
    }
    
    test "EVICT: Performance comparison with DEL" {
        r flushall
        
        # Test DEL performance
        for {set i 0} {$i < 1000} {incr i} {
            r set "del:$i" "value:$i"
        }
        
        set start_time [clock milliseconds]
        for {set i 0} {$i < 1000} {incr i} {
            r del "del:$i"
        }
        set del_time [expr {[clock milliseconds] - $start_time}]
        
        # Test EVICT performance
        for {set i 0} {$i < 1000} {incr i} {
            r set "evict:$i" "value:$i"
        }
        
        set start_time [clock milliseconds]
        for {set i 0} {$i < 1000} {incr i} {
            r evict "evict:$i"
        }
        set evict_time [expr {[clock milliseconds] - $start_time}]
        
        # EVICT should be reasonably close to DEL performance
        # Allow EVICT to be up to 3x slower due to additional processing
        assert {$evict_time <= ($del_time * 3 + 100)}
    }
}

# Multi-database tests
start_server {tags {"evict" "multidb"}} {
    test "EVICT: Multiple database isolation" {
        # Clear all databases
        for {set db 0} {$db < 16} {incr db} {
            r select $db
            r flushdb
        }
        
        # Populate different databases
        for {set db 0} {$db < 4} {incr db} {
            r select $db
            for {set i 0} {$i < 10} {incr i} {
                r set "key:$db:$i" "value:$db:$i"
            }
        }
        
        # Evict from specific databases
        r select 0
        r evict key:0:1 key:0:3 key:0:5
        
        r select 2  
        r evict key:2:2 key:2:4 key:2:6
        
        # Verify isolation
        r select 0
        assert_equal [r exists key:0:1 key:0:3 key:0:5] 0
        assert_equal [r exists key:0:0 key:0:2 key:0:4] 3
        
        r select 1
        assert_equal [r dbsize] 10  ;# Untouched
        
        r select 2
        assert_equal [r exists key:2:2 key:2:4 key:2:6] 0
        assert_equal [r exists key:2:0 key:2:1 key:2:3] 3
        
        r select 3
        assert_equal [r dbsize] 10  ;# Untouched
    }
}