#include "valkeymodule.h"
#include <stdio.h>
#include <string.h>

/* Global counter for pre-eviction notifications */
static long long preeviction_count = 0;
static long long eviction_count = 0;

/* Notification callback for pre-eviction events */
int PreEvictionCallback(ValkeyModuleCtx *ctx, int type, const char *event, ValkeyModuleString *key) {
    VALKEYMODULE_NOT_USED(ctx);
    VALKEYMODULE_NOT_USED(type);
    
    if (strcmp(event, "preeviction") == 0) {
        preeviction_count++;
        const char *keystr = ValkeyModule_StringPtrLen(key, NULL);
        ValkeyModule_Log(ctx, "notice", "Pre-eviction notification for key: %s", keystr);
    }
    return VALKEYMODULE_OK;
}

/* Notification callback for eviction events */
int EvictionCallback(ValkeyModuleCtx *ctx, int type, const char *event, ValkeyModuleString *key) {
    VALKEYMODULE_NOT_USED(ctx);
    VALKEYMODULE_NOT_USED(type);
    
    if (strcmp(event, "evicted") == 0) {
        eviction_count++;
        const char *keystr = ValkeyModule_StringPtrLen(key, NULL);
        ValkeyModule_Log(ctx, "notice", "Eviction notification for key: %s", keystr);
    }
    return VALKEYMODULE_OK;
}

/* Command to get the count of pre-eviction notifications */
int GetPreEvictionCount_ValkeyCommand(ValkeyModuleCtx *ctx, ValkeyModuleString **argv, int argc) {
    VALKEYMODULE_NOT_USED(argv);
    VALKEYMODULE_NOT_USED(argc);
    
    ValkeyModule_ReplyWithLongLong(ctx, preeviction_count);
    return VALKEYMODULE_OK;
}

/* Command to get the count of eviction notifications */
int GetEvictionCount_ValkeyCommand(ValkeyModuleCtx *ctx, ValkeyModuleString **argv, int argc) {
    VALKEYMODULE_NOT_USED(argv);
    VALKEYMODULE_NOT_USED(argc);
    
    ValkeyModule_ReplyWithLongLong(ctx, eviction_count);
    return VALKEYMODULE_OK;
}

/* Command to reset counters */
int ResetCounters_ValkeyCommand(ValkeyModuleCtx *ctx, ValkeyModuleString **argv, int argc) {
    VALKEYMODULE_NOT_USED(argv);
    VALKEYMODULE_NOT_USED(argc);
    
    preeviction_count = 0;
    eviction_count = 0;
    ValkeyModule_ReplyWithSimpleString(ctx, "OK");
    return VALKEYMODULE_OK;
}

/* Module initialization */
int ValkeyModule_OnLoad(ValkeyModuleCtx *ctx, ValkeyModuleString **argv, int argc) {
    VALKEYMODULE_NOT_USED(argv);
    VALKEYMODULE_NOT_USED(argc);

    if (ValkeyModule_Init(ctx, "test_preeviction", 1, VALKEYMODULE_APIVER_1) == VALKEYMODULE_ERR)
        return VALKEYMODULE_ERR;

    /* Subscribe to pre-eviction notifications */
    if (ValkeyModule_SubscribeToKeyspaceEvents(ctx, VALKEYMODULE_NOTIFY_PREEVICTION, PreEvictionCallback) != VALKEYMODULE_OK) {
        ValkeyModule_Log(ctx, "warning", "Failed to subscribe to pre-eviction notifications");
        return VALKEYMODULE_ERR;
    }

    /* Subscribe to eviction notifications */
    if (ValkeyModule_SubscribeToKeyspaceEvents(ctx, VALKEYMODULE_NOTIFY_EVICTED, EvictionCallback) != VALKEYMODULE_OK) {
        ValkeyModule_Log(ctx, "warning", "Failed to subscribe to eviction notifications");
        return VALKEYMODULE_ERR;
    }

    /* Register commands */
    if (ValkeyModule_CreateCommand(ctx, "test.preeviction_count", GetPreEvictionCount_ValkeyCommand, "readonly", 0, 0, 0) == VALKEYMODULE_ERR)
        return VALKEYMODULE_ERR;

    if (ValkeyModule_CreateCommand(ctx, "test.eviction_count", GetEvictionCount_ValkeyCommand, "readonly", 0, 0, 0) == VALKEYMODULE_ERR)
        return VALKEYMODULE_ERR;
        
    if (ValkeyModule_CreateCommand(ctx, "test.reset_counters", ResetCounters_ValkeyCommand, "readonly", 0, 0, 0) == VALKEYMODULE_ERR)
        return VALKEYMODULE_ERR;

    ValkeyModule_Log(ctx, "notice", "Pre-eviction test module loaded successfully");
    return VALKEYMODULE_OK;
}