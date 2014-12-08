/*
 * jit_internal.h
 *
 *  Created on: 2014/12/08
 *      Author: masa
 */

#ifndef JIT_INTERNAL_H_
#define JIT_INTERNAL_H_

#define FMT(T) FMT_##T
#define FMT_int "%d"
#define FMT_long "%ld"
#define FMT_uint64_t "%04lld"
#define FMT_lir_t "%04ld"
#define FMT_LirPtr "%04ld"
#define FMT_ID "%04ld"
#define FMT_SPECIAL_VALUE "0x%lx"
#if DUMP_LIR_DUMP_VALUE_AS_STRING
#define FMT_VALUE "%s"
#else
#define FMT_VALUE "%lx"
#endif
#define FMT_VALUEPtr "%p"
#define FMT_voidPtr "%p"
#define FMT_GENTRY "%p"
#define FMT_CALL_INFO "%p"
#define FMT_IC "%p"
#define FMT_ISEQ "%p"
#define FMT_BasicBlockPtr "bb:%d"
#define FMT_rb_event_flag_t "%u"

#define DATA(T, V) DATA_##T(V)
#define DATA_int(V) (V)
#define DATA_uint64_t(V) (V)
#define DATA_long(V) (V)
#define DATA_lir_t(V) (lir_getid_null(V))
#define DATA_LirPtr(V) (lir_getid(*(V)))
#if DUMP_LIR_DUMP_VALUE_AS_STRING
#define DATA_VALUE(V) (RSTRING_PTR(rb_any_to_s(V)))
// #define DATA_VALUE(V) (RSTRING_PTR(rb_sprintf("<%" PRIsVALUE ">", V)))
#else
#define DATA_VALUE(V) (V)
#endif
#define DATA_VALUEPtr(V) (V)
#define DATA_SPECIAL_VALUE(V) (V)
#define DATA_GENTRY(V) (((struct rb_global_entry *)(V)))
#define DATA_voidPtr(V) (V)
#define DATA_CALL_INFO(V) (V)
#define DATA_IC(V) (V)
#define DATA_ISEQ(V) (V)
#define DATA_BasicBlockPtr(V) ((V)->base.id)
#define DATA_rb_event_flag_t(V) (V)

typedef struct lir_t *LirPtr;
typedef VALUE *VALUEPtr;
typedef VALUE SPECIAL_VALUE;
typedef void *voidPtr;
typedef struct basicblock_t *BasicBlockPtr;
typedef void *lir_folder_t;

#ifndef FALSE
#define FALSE 0
#endif

#ifndef TRUE
#define TRUE 1
#endif

#endif /* JIT_INTERNAL_H_ */
