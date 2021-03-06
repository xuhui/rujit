#!ruby

$indent_level = 0

class LValue
  attr_accessor :name, :type
  def initialize(name, type = nil)
    @name = name
    @type = type
  end

  def to_s
    @name
  end
end

class Yarv2Lir
  def self.match(op, &block)
    puts "#line #{eval "__LINE__", block.binding} \"#{eval "File.expand_path(__FILE__)", block.binding}\""
    puts "static void record_#{op}(lir_builder_t *builder, jit_event_t *e)"
    puts '{'
    $indent_level += 1
    yield
    $indent_level -= 1
    puts '}'
  end

  def self.indent
    '  ' * $indent_level
  end

  def self.emit(opname, *arg)
    if opname == :EnvLoad || opname == :EnvStore
      s = "emit_#{opname.to_s.downcase}(#{["builder", *arg].map(&:to_s).join(', ')})"
    else
      s = "EmitIR(#{[opname, *arg].map(&:to_s).join(', ')})"
    end
    if !opname.to_s.start_with?("Guard")
      s = s + ";"
    end
    s
  end

  def self.operand(type, idx)
    LValue.new("(#{type})GET_OPERAND(#{idx});", type)
  end

  def self.take_snapshot
    'take_snapshot(builder, e->pc);'
  end

  def self.pop
    '_POP();'
  end

  def self.topn(idx)
    "_TOPN(#{idx});"
  end

  def self.vtopn(idx)
    "TOPN(#{idx});"
  end

  def self.to_mid(sym)
    return 'idPLUS'      if sym == '+'
    return 'idMINUS'     if sym == '-'
    return 'idMULT'      if sym == '*'
    return 'idDIV'       if sym == '/'
    return 'idMOD'       if sym == '%'
    return 'idPow'       if sym == '**'
    return 'idLT'        if sym == '<'
    return 'idLTLT'      if sym == '<<'
    return 'idLE'        if sym == '<='
    return 'idGT'        if sym == '>'
    return 'idGE'        if sym == '>='
    return 'idEq'        if sym == '=='
    return 'idNeq'       if sym == '!='
    return 'idNot'       if sym == '!'
    return 'idNot'       if sym == 'not'
    return 'idAREF'      if sym == '[]'
    return 'idASET'      if sym == '[]='
    return 'idLength'    if sym == 'length'
    return 'idSize'      if sym == 'size'
    return 'idEmptyP'    if sym == 'empty?'
    return 'idSucc'      if sym == 'succ'
    return 'idEqTilde'   if sym == '=~'
    "rb_intern(\"#{sym}\")"
  end

  def self.stringify(sym)
    return 'JIT_BOP_PLUS'      if sym == '+'
    return 'JIT_BOP_MINUS'     if sym == '-'
    return 'JIT_BOP_MULT'      if sym == '*'
    return 'JIT_BOP_DIV'       if sym == '/'
    return 'JIT_BOP_MOD'       if sym == '%'
    return 'JIT_BOP_POW'       if sym == '**'
    return 'JIT_BOP_LT'        if sym == '<'
    return 'JIT_BOP_LTLT'      if sym == '<<'
    return 'JIT_BOP_LE'        if sym == '<='
    return 'JIT_BOP_GT'        if sym == '>'
    return 'JIT_BOP_GE'        if sym == '>='
    return 'JIT_BOP_EQ'        if sym == '=='
    return 'JIT_BOP_NEQ'       if sym == '!='
    return 'JIT_BOP_NOT'       if sym == '!'
    return 'JIT_BOP_NOT'       if sym == 'not'
    return 'JIT_BOP_AREF'      if sym == '[]'
    return 'JIT_BOP_ASET'      if sym == '[]='
    return 'JIT_BOP_LENGTH'    if sym == 'length'
    return 'JIT_BOP_SIZE'      if sym == 'size'
    return 'JIT_BOP_EMPTY_P'   if sym == 'empty?'
    return 'JIT_BOP_SUCC'      if sym == 'succ'
    return 'JIT_BOP_MATCH'     if sym == '=~'
    return 'JIT_BOP_FREEZE'    if sym == 'freeze'

    return 'JIT_BOP_NEG'       if sym == '-@'
    return 'JIT_BOP_AND'       if sym == '&'
    return 'JIT_BOP_OR'        if sym == '|'
    return 'JIT_BOP_XOR'       if sym == '^'
    return 'JIT_BOP_INV'       if sym == '~'
    return 'JIT_BOP_RSHIFT'    if sym == '>>'

    return 'JIT_BOP_TO_F'    if sym == 'to_f'
    return 'JIT_BOP_TO_I'    if sym == 'to_i'
    return 'JIT_BOP_TO_S'    if sym == 'to_s'
    # math
    return 'JIT_BOP_SIN'       if sym == 'sin'
    return 'JIT_BOP_COS'       if sym == 'cos'
    return 'JIT_BOP_TAN'       if sym == 'tan'
    return 'JIT_BOP_EXPR'      if sym == 'expr'
    return 'JIT_BOP_SQRT'      if sym == 'sqrt'
    return 'JIT_BOP_LOG2'      if sym == 'log2'
    return 'JIT_BOP_LOG10'     if sym == 'log10'
    'JIT_BOP_' + sym.upcase
  end

  def self.push(*arg)
    for val in arg
      print indent
      puts "_PUSH(#{val});"
    end
    print indent
    puts 'return;'
  end

  def self.guard(type, *arg, &block)
    puts "#line #{eval "__LINE__", block.binding} \"#{eval "File.expand_path(__FILE__)", block.binding}\""
    print indent
    $indent_level += 1
    if type.is_a? String
      type, mname = type.split('.')
      type = "#{type.upcase}_REDEFINED_OP_FLAG"
      mname = stringify(mname)
      print "if (JIT_OP_UNREDEFINED_P(#{mname}, #{type}) && ("
      print emit 'GuardMethodRedefine', 'CURRENT_PC', mname, type
      puts ") != NULL) {"
    else
      print "if (IS_#{type}(#{arg[1]}) && ("
      print emit "GuardType#{type}".to_sym, 'CURRENT_PC', arg[0]
      puts ") != NULL) {"
    end
    yield
    $indent_level -= 1
    print indent
    puts '}'
  end

  def self.if_(type, val, &block)
    puts "#line #{eval "__LINE__", block.binding} \"#{eval "File.expand_path(__FILE__)", block.binding}\""
    print indent
    if type == :argc
      puts "if (ci->#{type} == #{val}) {"
    elsif type == :mid
      puts "if (ci->mid == #{to_mid(val)}) {"
    elsif type == :method_type
      puts "if (ci->me && ci->me->def->type == VM_METHOD_TYPE_#{val.upcase}) {"
    else
      puts "if (#{type}) {"
    end
    $indent_level += 1
    yield
    $indent_level -= 1
    print indent
    puts '}'
  end

  def self.other(&block)
    puts "#line #{eval "__LINE__", block.binding} \"#{eval "File.expand_path(__FILE__)", block.binding}\""
    print indent
    puts '/*L_other:*/ {'
    $indent_level += 1
    yield
    $indent_level -= 1
    print indent
    puts '}'
  end

  def self.emit_get_prop(recv, snapshot)
    "emit_get_prop(builder, ci, #{recv}, #{snapshot});"
  end

  def self.emit_set_prop(recv, obj, snapshot)
    "emit_set_prop(builder, ci, #{recv}, #{obj}, #{snapshot});"
  end

  def self.emit_call_method(snapshot, *arg)
    argc = arg.length
    argv = ["builder", "ci", snapshot, arg].flatten.map(&:to_s).join(', ')
    "emit_call_method#{argc}(#{argv});"
  end

  def self.emit_load_const(obj)
    if obj.is_a? Fixnum
      obj = "LONG2FIX(#{obj})"
    end
    "emit_load_const(builder, #{obj});"
  end
  def self.emit_search_method(ci)
    print indent
    puts "vm_search_method(ci, ci->recv = TOPN(ci->orig_argc));"
  end

  class Local
    def pop(num = 1)
      num.times {|i|
        print '  ' * $indent_level
        puts "lir_t poped_#{i} = _POP();"
      }
    end
    def method_missing(name, *arg, &block)
      name = name.to_s
      if name.end_with?('=')
        name = name.gsub('=', '')
        print '  ' * $indent_level
        if name == 'snapshot'
          puts "jit_snapshot_t *#{name} = #{arg[0]}"
        elsif name == 'result'
          puts arg[0]
          print '  ' * $indent_level
          puts 'return;'
        elsif name.start_with?('v') && name.size > 1
          puts "VALUE #{name} = #{arg[0]}"
        elsif arg[0].is_a? LValue
          puts "#{arg[0].type} #{name} = #{arg[0]}"
        else
          puts "lir_t #{name} = #{arg[0]}"
        end
        LValue.new(name)
      else
        LValue.new(name)
      end
    end
  end

  local = Local.new

  match(:nop) {
  }

  match(:getlocal) {
    local.idx = operand :int, 1
    local.lev = operand :int, 2
    local.v = emit :EnvLoad, local.lev, local.idx
    push local.v
  }
  match(:setlocal) {
    local.idx = operand :int, 1
    local.lev = operand :int, 2
    local.v = pop
    local.result = emit :EnvStore, local.lev, local.idx, local.v
  }
  # match(:getspecial)
  # match(:setspecial)
  # match(:getinstancevariable)
  # match(:setinstancevariable)
  # match(:getclassvariable)
  # match(:setclassvariable)
  # match(:getconstant)
  # match(:setconstant)

  match(:getglobal) {
    local.entry = operand :GENTRY, 1
    local.v = emit :GetGlobal, local.entry
    push local.v
  }
  match(:setglobal) {
    local.entry = operand :GENTRY, 1
    local.v = pop
    local.result = emit :SetGlobal, local.entry, local.v
  }

  match(:putnil) {
    local.obj = emit_load_const('Qnil')
    push local.obj
  }

  match(:putself) {
    local.obj = emit :LoadSelf
    push local.obj
  }

  match(:putobject) {
    local.vobj = operand :VALUE, 1
    local.obj = emit_load_const(local.vobj)
    push local.obj
  }

  match(:putiseq) {
    local.vobj = operand :VALUE, 1
    local.obj = emit_load_const(local.vobj)
    push local.obj
  }
  match(:putstring) {
    local.vobj = operand :VALUE, 1
    local.obj = emit_load_const(local.vobj)
    push local.obj
  }
  match(:tostring) {
    local.recv = pop
    local.v = emit :ObjectToString, local.recv
    push local.v
  }
  # match(:toregexp)
  # match(:newarray)
  # match(:duparray)
  # match(:expandarray)
  # match(:concatarray)
  # match(:splatarray)
  # match(:newhash)
  # match(:newrange)
  match(:pop) {
    local.result = pop
  }
  match(:dup) {
    local.obj = pop
    push local.obj, local.obj
  }
  match(:swap) {
    local.obj1 = pop
    local.obj2 = pop
    push local.obj2, local.obj1

  }
  match(:reput) {
    local.obj = pop
    push local.obj
  }
  match(:trace) {
    local.flag = operand :rb_event_flag_t, 1
    local.result = emit :Trace, local.flag
  }

  match(:opt_str_freeze) {
    local.snapshot = take_snapshot
    local.recv = pop
    guard('String.freeze', local.snapshot) {
      push local.recv
    }
  }

  match(:opt_send_without_block) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    emit_search_method local.ci

    if_(:argc, 0) {
      local.recv = topn(0)
      local.vrecv = vtopn(0)
      if_(:method_type, :ivar) {
        guard(:Object, local.recv, local.vrecv, local.snapshot) {
          local.pop
          local.v = emit_get_prop local.recv, local.snapshot
          push local.v
        }
      }
      guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
        if_(:mid, '-@') {
          guard('Fixnum.-@', local.snapshot) {
            local.pop
            local.v = emit :FixnumNeg, local.recv
            push local.v
          }
        }
        if_(:mid, '~') {
          guard('Fixnum.~', local.snapshot) {
            local.pop
            local.v = emit :FixnumComplement, local.recv
            push local.v
          }
        }
        if_(:mid, 'to_f') {
          guard('Fixnum.to_f', local.snapshot) {
            local.pop
            local.v = emit :FixnumToFloat, local.recv
            push local.v
          }
        }
        if_(:mid, 'to_s') {
          guard('Fixnum.to_s', local.snapshot) {
            local.pop
            local.v = emit :FixnumToString, local.recv
            push local.v
          }
        }
        if_(:mid, 'to_i') {
          guard('Fixnum.to_i', local.snapshot) {
            local.pop
            push local.recv
          }
        }
      }
      guard(:Float, local.recv, local.vrecv, local.snapshot) {
        if_(:mid, '-@') {
          guard('Float.-@', local.snapshot) {
            local.pop
            local.v = emit :FloatNeg, local.recv
            push local.v
          }
        }
        if_(:mid, 'to_f') {
          guard('Float.to_f', local.snapshot) {
            local.pop
            push local.recv
          }
        }
        if_(:mid, 'to_s') {
          guard('Float.to_s', local.snapshot) {
            local.pop
            local.v = emit :FloatToString, local.recv
            push local.v
          }
        }
        if_(:mid, 'to_i') {
          guard('Float.to_i', local.snapshot) {
            local.pop
            local.v = emit :FloatToFixnum, local.recv
            push local.v
          }
        }
      }
      guard(:String, local.recv, local.vrecv, local.snapshot) {
        if_(:mid, 'to_f') {
          guard('String.to_f', local.snapshot) {
            local.pop
            local.v = emit :StringToFloat, local.recv
            push local.v
          }
        }
        if_(:mid, 'to_s') {
          guard('String.to_s', local.snapshot) {
            local.pop
            push local.recv
          }
        }
        if_(:mid, 'to_i') {
          guard('String.to_i', local.snapshot) {
            local.pop
            local.v = emit :StringToFixnum, local.recv
            push local.v
          }
        }
      }
      guard(:Array, local.recv, local.vrecv, local.snapshot) {
        if_(:mid, 'length') {
          guard('Array.length', local.snapshot) {
            local.pop
            local.v = emit :ArrayLength, local.recv
            push local.v
          }
        }
      }
      other {
        local.result = emit_call_method local.snapshot, local.recv
      }
    }
    if_(:argc, 1) {
      local.obj = topn(0)
      local.recv = topn(1)
      local.vobj = vtopn(0)
      local.vrecv = vtopn(1)
      guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
        #if_(:mid, '**') {
        #  guard('Fixnum.**', local.snapshot) {
        #    guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        #      local.v = emit :FixnumPowOverflow, local.recv, local.obj
        #      push local.v
        #    }
        #    # guard(:Float, local.obj, local.vobj, local.snapshot) {
        #    #   local.v = emit :FixnumPowOverflow, local.recv, local.obj
        #    #   push local.v
        #    # }
        #    # guard(:Bignum, local.obj, local.vobj, local.snapshot) {
        #    #   local.v = emit :FixnumPowOverflow, local.recv, local.obj
        #    #   push local.v
        #    # }
        #  }
        #}
        if_(:mid, '&') {
          guard('Fixnum.&', local.snapshot) {
            local.pop 2
            local.v = emit :FixnumAnd, local.recv, local.obj
            push local.v
          }
        }
        if_(:mid, '|') {
          guard('Fixnum.|', local.snapshot) {
            local.pop 2
            local.v = emit :FixnumOr, local.recv, local.obj
            push local.v
          }
        }
        if_(:mid, '^') {
          guard('Fixnum.^', local.snapshot) {
            local.pop 2
            local.v = emit :FixnumXor, local.recv, local.obj
            push local.v
          }
        }
        if_(:mid, '<<') {
          guard('Fixnum.<<', local.snapshot) {
            local.pop 2
            local.v = emit :FixnumLshift, local.recv, local.obj
            push local.v
          }
        }
        if_(:mid, '>>') {
          guard('Fixnum.>>', local.snapshot) {
            local.pop 2
            local.v = emit :FixnumRshift, local.recv, local.obj
            push local.v
          }
        }
      }
      guard(:Float, local.recv, local.vrecv, local.snapshot) {
        if_(:mid, '**') {
          guard('Float.**', local.snapshot) {
            local.pop 2
            local.v = emit :FloatPow, local.recv, local.obj
            push local.v
          }
        }
        if_(:mid, '**') {
          guard('Float.**', local.snapshot) {
            local.pop 2
            local.v = emit :FloatPow, local.recv, local.obj
            push local.v
          }
        }
      }
      guard(:Math, local.recv, local.vrecv, local.snapshot) {
        if_(:mid, 'sin') {
          guard('Math.sin', local.snapshot) {
            guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.t = emit :FixnumToFloat, local.obj
              local.v = emit :MathSin, local.recv, local.t
              push local.v
            }
            guard(:Float, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.v = emit :MathSin, local.recv, local.obj
              push local.v
            }
          }
        }
        if_(:mid, 'cos') {
          guard('Math.cos', local.snapshot) {
            guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.t = emit :FixnumToFloat, local.obj
              local.v = emit :MathCos, local.recv, local.t
              push local.v
            }
            guard(:Float, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.v = emit :MathCos, local.recv, local.obj
              push local.v
            }
          }
        }
        if_(:mid, 'tan') {
          guard('Math.tan', local.snapshot) {
            guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.t = emit :FixnumToFloat, local.obj
              local.v = emit :MathTan, local.recv, local.t
              push local.v
            }
            guard(:Float, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.v = emit :MathTan, local.recv, local.obj
              push local.v
            }
          }
        }
        if_(:mid, 'exp') {
          guard('Math.exp', local.snapshot) {
            guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.t = emit :FixnumToFloat, local.obj
              local.v = emit :MathExp, local.recv, local.t
              push local.v
            }
            guard(:Float, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.v = emit :MathExp, local.recv, local.obj
              push local.v
            }
          }
        }
        if_(:mid, 'sqrt') {
          guard('Math.sqrt', local.snapshot) {
            guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.t = emit :FixnumToFloat, local.obj
              local.v = emit :MathSqrt, local.recv, local.t
              push local.v
            }
            guard(:Float, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.v = emit :MathSqrt, local.recv, local.obj
              push local.v
            }
          }
        }
        if_(:mid, 'log10') {
          guard('Math.log10', local.snapshot) {
            guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.t = emit :FixnumToFloat, local.obj
              local.v = emit :MathLog10, local.recv, local.t
              push local.v
            }
            guard(:Float, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.v = emit :MathLog10, local.recv, local.obj
              push local.v
            }
          }
        }
        if_(:mid, 'log2') {
          guard('Math.log2', local.snapshot) {
            guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.t = emit :FixnumToFloat, local.obj
              local.v = emit :MathLog2, local.recv, local.t
              push local.v
            }
            guard(:Float, local.obj, local.vobj, local.snapshot) {
              local.pop 2
              local.v = emit :MathLog2, local.recv, local.obj
              push local.v
            }
          }
        }
      }
      guard(:Array, local.recv, local.vrecv, local.snapshot) {
        if_(:mid, '[]') {
          guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
            guard('Array.[]', local.snapshot) {
              local.pop 2
              local.v = emit :ArrayGet, local.recv, local.obj
              push local.v
            }
          }
        }
      }
      # TODO   ["ObjectToString", "tostring", "", [:String]],
      if_(:method_type, :attrset) {
        guard(:Object, local.recv, local.vrecv, local.snapshot) {
          local.pop 2
          local.result = emit_set_prop local.recv, local.obj, local.snapshot
        }
      }
      other {
        local.result = emit_call_method local.snapshot, local.recv, local.obj
      }
    }
    if_(:argc, 2) {
      local.obj = topn(0)
      local.idx = topn(1)
      local.recv = topn(2)
      # local.vobj = vtopn(0)
      local.vidx = vtopn(1)
      local.vrecv = vtopn(2)
      guard(:Array, local.recv, local.vrecv, local.snapshot) {
        if_(:mid, '[]=') {
          guard(:Fixnum, local.idx, local.vidx, local.snapshot) {
            guard('Array.[]=', local.snapshot) {
              local.pop 3
              local.v = emit :ArraySet, local.recv, local.idx, local.obj
              push local.v
            }
          }
        }
      }
      other {
        local.result = emit_call_method local.snapshot,
                                        local.recv, local.idx, local.obj
      }
    }
    other {
      local.result = emit_call_method local.snapshot
    }
  }

  match(:opt_plus) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.+', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumAddOverflow, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.+', local.snapshot) {
          local.pop 2
          local.v = emit :FloatAdd, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.+', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatAdd, local.recv, local.t
          push local.v
        }
      }
    }
    guard(:String, local.recv, local.vrecv, local.snapshot) {
      guard(:String, local.obj, local.vobj, local.snapshot) {
        guard('String.+', local.snapshot) {
          local.pop 2
          local.v = emit :StringAdd, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Array, local.recv, local.vrecv, local.snapshot) {
      guard(:Array, local.obj, local.vobj, local.snapshot) {
        guard('Array.+', local.snapshot) {
          local.pop 2
          local.v = emit :ArrayConcat, local.recv, local.obj
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }

  match(:opt_minus) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.-', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumSubOverflow, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.-', local.snapshot) {
          local.pop 2
          local.v = emit :FloatSub, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.-', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatSub, local.recv, local.t
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_mult) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.*', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumMulOverflow, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.*', local.snapshot) {
          local.pop 2
          local.v = emit :FloatMul, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.*', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatMul, local.recv, local.t
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }

  match(:opt_div) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum./', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumDivOverflow, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float./', local.snapshot) {
          local.pop 2
          local.v = emit :FloatDiv, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float./', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatDiv, local.recv, local.t
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }

  match(:opt_mod) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.%', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumModOverflow, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.%', local.snapshot) {
          local.pop 2
          local.v = emit :FloatMod, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.%', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatMod, local.recv, local.t
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_eq) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.==', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumEq, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.==', local.snapshot) {
          local.pop 2
          local.v = emit :FloatEq, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.==', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatEq, local.recv, local.t
          push local.v
        }
      }
    }
    # TODO   ["ObjectEq",  "opt_eq",  "==", [:_, :_]],
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_neq) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.!=', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumNe, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.!=', local.snapshot) {
          local.pop 2
          local.v = emit :FloatNe, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.!=', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatNe, local.recv, local.t
          push local.v
        }
      }
    }
    # TODO   ["ObjectNe",  "opt_neq", "!=", [:_, :_]],
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_gt) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.>', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumGt, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.>', local.snapshot) {
          local.pop 2
          local.v = emit :FloatGt, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.>', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatGt, local.recv, local.t
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_ge) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.>=', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumGe, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.>=', local.snapshot) {
          local.pop 2
          local.v = emit :FloatGe, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.>=', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatGe, local.recv, local.t
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_lt) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.<', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumLt, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.<', local.snapshot) {
          local.pop 2
          local.v = emit :FloatLt, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.<', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatLt, local.recv, local.t
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_le) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Fixnum.<=', local.snapshot) {
          local.pop 2
          local.v = emit :FixnumLe, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Float, local.recv, local.vrecv, local.snapshot) {
      guard(:Float, local.obj, local.vobj, local.snapshot) {
        guard('Float.<=', local.snapshot) {
          local.pop 2
          local.v = emit :FloatLe, local.recv, local.obj
          push local.v
        }
      }
      guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
        guard('Float.<=', local.snapshot) {
          local.pop 2
          local.t = emit :FixnumToFloat, local.obj
          local.v = emit :FloatLe, local.recv, local.t
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_ltlt) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:String, local.recv, local.vrecv, local.snapshot) {
      guard(:String, local.obj, local.vobj, local.snapshot) {
        guard('String.<<', local.snapshot) {
          local.pop 2
          local.v = emit :StringAdd, local.recv, local.obj
          push local.v
        }
      }
    }
    guard(:Array, local.recv, local.vrecv, local.snapshot) {
      guard('Array.<<', local.snapshot) {
        local.pop 2
        local.v = emit :ArrayAdd, local.recv, local.obj
        push local.v
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }

  match(:opt_aref) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.recv = topn(1)
    local.vobj  = vtopn(0)
    local.vrecv = vtopn(1)
    guard(:NonSpecialConst, local.recv, local.vrecv, local.snapshot) {
      guard(:Array, local.recv, local.vrecv, local.snapshot) {
        guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
          guard('Array.[]', local.snapshot) {
            local.pop 2
            local.v = emit :ArrayGet, local.recv, local.obj
            push local.v
          }
        }
      }
      guard(:Hash, local.recv, local.vrecv, local.snapshot) {
        guard('Hash.[]', local.snapshot) {
          local.pop 2
          local.v = emit :HashGet, local.recv, local.obj
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_aref_with) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.vobj  = operand :VALUE, 2
    local.vrecv = vtopn(0)
    local.recv = topn(0)
    local.obj  = emit_load_const(local.vobj)
    guard(:NonSpecialConst, local.recv, local.vrecv, local.snapshot) {
      guard(:Array, local.recv, local.vrecv, local.snapshot) {
        guard(:Fixnum, local.obj, local.vobj, local.snapshot) {
          guard('Array.[]', local.snapshot) {
            local.pop
            local.v = emit :ArrayGet, local.recv, local.obj
            push local.v
          }
        }
      }
      guard(:Hash, local.recv, local.vrecv, local.snapshot) {
        guard('Hash.[]', local.snapshot) {
          local.pop
          local.v = emit :HashGet, local.recv, local.obj
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }
  match(:opt_aset) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.obj  = topn(0)
    local.idx  = topn(1)
    local.recv = topn(2)
    # local.vobj  = vtopn(0)
    local.vidx  = vtopn(1)
    local.vrecv = vtopn(2)
    guard(:NonSpecialConst, local.recv, local.vrecv, local.snapshot) {
      guard(:Array, local.recv, local.vrecv, local.snapshot) {
        guard(:Fixnum, local.idx, local.vidx, local.snapshot) {
          guard('Array.[]=', local.snapshot) {
            local.pop 3
            local.v = emit :ArraySet, local.recv, local.idx, local.obj
            push local.v
          }
        }
      }
      guard(:Hash, local.recv, local.vrecv, local.snapshot) {
        guard('Hash.[]=', local.snapshot) {
          local.pop 3
          local.v = emit :HashSet, local.recv, local.idx, local.obj
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.idx, local.obj
    }
  }
  match(:opt_aset_with) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.vidx  = operand :VALUE, 2
    local.vrecv = vtopn(0)
    local.obj  = topn(0)
    local.recv = topn(1)
    local.idx  = emit_load_const(local.vidx)
    guard(:NonSpecialConst, local.recv, local.vrecv, local.snapshot) {
      guard(:Array, local.recv, local.vrecv, local.snapshot) {
        guard(:Fixnum, local.idx, local.vidx, local.snapshot) {
          guard('Array.[]=', local.snapshot) {
            local.pop 2
            local.v = emit :ArraySet, local.recv, local.idx, local.obj
            push local.v
          }
        }
      }
      guard(:Hash, local.recv, local.vrecv, local.snapshot) {
        guard('Hash.[]=', local.snapshot) {
          local.pop 2
          local.v = emit :HashSet, local.recv, local.idx, local.obj
          push local.v
        }
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.idx, local.obj
    }
  }
  match(:opt_length) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.recv = topn(0)
    local.vrecv = vtopn(0)
    guard(:String, local.recv, local.vrecv, local.snapshot) {
      guard('String.length', local.snapshot) {
        local.pop
        local.v = emit :StringLength, local.recv
        push local.v
      }
    }
    guard(:Array, local.recv, local.vrecv, local.snapshot) {
      guard('Array.length', local.snapshot) {
        local.pop
        local.v = emit :ArrayLength, local.recv
        push local.v
      }
    }
    guard(:Hash, local.recv, local.vrecv, local.snapshot) {
      guard('Hash.length', local.snapshot) {
        local.pop
        local.v = emit :HashLength, local.recv
        push local.v
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv
    }
  }
  match(:opt_size) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.recv = topn(0)
    local.vrecv = vtopn(0)
    guard(:String, local.recv, local.vrecv, local.snapshot) {
      guard('String.size', local.snapshot) {
        local.pop
        local.v = emit :StringLength, local.recv
        push local.v
      }
    }
    guard(:Array, local.recv, local.vrecv, local.snapshot) {
      guard('Array.size', local.snapshot) {
        local.pop
        local.v = emit :ArrayLength, local.recv
        push local.v
      }
    }
    guard(:Hash, local.recv, local.vrecv, local.snapshot) {
      guard('Hash.size', local.snapshot) {
        local.pop
        local.v = emit :HashLength, local.recv
        push local.v
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv
    }
  }
  match(:opt_empty_p) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.recv = topn(0)
    local.vrecv = vtopn(0)
    guard(:String, local.recv, local.vrecv, local.snapshot) {
      guard('String.empty?', local.snapshot) {
        local.pop
        local.v = emit :StringEmptyP, local.recv
        push local.v
      }
    }
    guard(:Array, local.recv, local.vrecv, local.snapshot) {
      guard('Array.empty?', local.snapshot) {
        local.pop
        local.v = emit :ArrayEmptyP, local.recv
        push local.v
      }
    }
    guard(:Hash, local.recv, local.vrecv, local.snapshot) {
      guard('Hash.empty?', local.snapshot) {
        local.pop
        local.v = emit :HashEmptyP, local.recv
        push local.v
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv
    }
  }

  match(:opt_succ) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.recv = topn(0)
    local.vrecv = vtopn(0)
    guard(:Fixnum, local.recv, local.vrecv, local.snapshot) {
      guard('Fixnum.succ', local.snapshot) {
        local.pop
        local.obj  = emit_load_const(1)
        local.v = emit :FixnumAddOverflow, local.recv, local.obj
        push local.v
      }
    }
    # TODO String.succ
    # guard(:String, local.recv, local.vrecv, local.snapshot) {
    #   guard('String.succ', local.snapshot) {
    #   }
    # }
    other {
      local.result = emit_call_method local.snapshot, local.recv
    }
  }

  # match(:opt_not)
  # TODO
  #    ["ObjectNot", "opt_not", "!",  [:_]],

  match(:opt_regexpmatch1) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.vobj = operand :VALUE, 1
    local.obj  = emit_load_const(local.vobj)
    local.recv = topn(0)
    guard('RegExp.=~', local.snapshot) {
      guard(:Regexp, local.obj, local.vobj, local.snapshot) {
        local.pop
        local.v = emit :RegExpMatch, local.recv, local.obj
        push local.v
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }

  match(:opt_regexpmatch2) {
    local.snapshot = take_snapshot
    local.ci = operand :CALL_INFO, 1
    local.recv = topn(0)
    local.obj  = topn(1)
    local.vobj = vtopn(1)
    guard('RegExp.=~', local.snapshot) {
      guard(:Regexp, local.obj, local.vobj, local.snapshot) {
        local.pop 2
        local.v = emit :RegExpMatch, local.recv, local.obj
        push local.v
      }
    }
    other {
      local.result = emit_call_method local.snapshot, local.recv, local.obj
    }
  }

  match(:getlocal_OP__WC__0) {
    local.idx = operand :int, 1
    local.v = emit :EnvLoad, 0, local.idx
    push local.v
  }
  match(:getlocal_OP__WC__1) {
    local.idx = operand :int, 1
    local.v = emit :EnvLoad, 1, local.idx
    push local.v
  }
  match(:setlocal_OP__WC__0) {
    local.idx = operand :int, 1
    local.v = pop
    local.result = emit :EnvStore, 0, local.idx, local.v
  }
  match(:setlocal_OP__WC__1) {
    local.idx = operand :int, 1
    local.v = pop
    local.result = emit :EnvStore, 1, local.idx, local.v
  }
  match(:putobject_OP_INT2FIX_O_0_C_) {
    local.obj = emit_load_const(0)
    push local.obj
  }
  match(:putobject_OP_INT2FIX_O_1_C_) {
    local.obj = emit_load_const(1)
    push local.obj
  }
end
