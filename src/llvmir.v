module main

// cone 0.9.f —— LLVM IR 后端（V 实现）
//
// x64 后端。规范见 conex64.txt（简明语法，不含版本沿革）；版本沿革见 README / SYNTAX_x86.txt。
// 本版要点：_fltused 自动定义；try/except 走 Windows x64 SEH（catchswitch/catchpad）；
// 结构体按 Windows x64 ABI 传参 / 隐藏 sret 返回；诊断统一为「问题 + 原因 + 做法」。

import math

const llvm_triple_x64 = 'x86_64-pc-windows-msvc'
const llvm_dl_x64 = 'e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128'
const llvm_hexdigits = '0123456789ABCDEF'
// cone 0.9.f：Windows x64 SEH 辅助符号
const llvm_seh_personality = '__C_specific_handler'
const llvm_seh_enter = '__cone_seh_enter'
const llvm_seh_leave = '__cone_seh_leave'
const llvm_seh_marker = '__cone_seh_marker'
const llvm_fltused = '_fltused'

fn llvm_triple_v(arch string) string {
	return llvm_triple_x64
}

fn llvm_dl_v(arch string) string {
	return llvm_dl_x64
}

fn llvm_itype_v(t string) string {
	if t == 'byte' { return 'i8' }
	if t == 'word' { return 'i16' }
	if t == 'long' { return 'i64' }
	if t == 'f32' { return 'float' }
	if t == 'f64' { return 'double' }
	return 'i32'
}

fn llvm_is_float_ty_v(t string) bool { return t == 'float' || t == 'double' }

fn llvm_digits_v(t string) bool {
	if t.len == 0 { return false }
	for c in t {
		if c < `0` || c > `9` { return false }
	}
	return true
}

fn llvm_is_float_text_v(text string) bool {
	mut t := text.trim_space()
	if t.len > 0 && (t[0] == `+` || t[0] == `-`) { t = t[1..] }
	if t.count('.') != 1 { return false }
	parts := t.split('.')
	if parts.len != 2 { return false }
	return llvm_digits_v(parts[0]) && llvm_digits_v(parts[1])
}

fn llvm_zero_of_v(ty string) string {
	if llvm_is_float_ty_v(ty) { return '0.0' }
	if ty.starts_with('[') { return 'zeroinitializer' }
	return '0'
}

fn llvm_float_const_v(text string, ty string) string {
	mut t := text.trim_space()
	if t.len == 0 { t = '0' }
	if !t.contains('.') && !t.contains('e') && !t.contains('E') { t += '.0' }
	if t.contains('e') || t.contains('E') {
		mut parts := t.split('e')
		if parts.len == 2 {
			if !parts[0].contains('.') { mut head := parts[0] + '.0'
				parts[0] = head }
			t = parts[0] + 'e' + parts[1]
		}
	}
	return t
}

// 结构体初值列表里浮点成员 -> IEEE 位模式字节（小端）
fn llvm_float_bytes_v(text string, ty string) []u8 {
	mut out := []u8{}
	t := text.trim_space()
	if ty == 'float' {
		bits := math.f32_bits(t.f32())
		for b := 0; b < 4; b++ { out << u8((bits >> u32(8 * b)) & 255) }
	} else {
		bits := math.f64_bits(t.f64())
		for b := 0; b < 8; b++ { out << u8((bits >> u32(8 * b)) & 255) }
	}
	return out
}

fn llvm_fbinop_v(op string) string {
	if op == '+' { return 'fadd' }
	if op == '-' { return 'fsub' }
	if op == '*' { return 'fmul' }
	if op == '/' { return 'fdiv' }
	return ''
}

fn llvm_fcmp_v(op string) string {
	if op == '==' { return 'oeq' }
	if op == '!=' { return 'one' }
	if op == '<' { return 'olt' }
	if op == '<=' { return 'ole' }
	if op == '>' { return 'ogt' }
	if op == '>=' { return 'oge' }
	return ''
}

fn llvm_ptr_size_ty_v(w string) string {
	if w == 'byte' { return 'i8' }
	if w == 'word' { return 'i16' }
	if w == 'long' || w == 'qword' { return 'i64' }
	return 'i32'
}

fn llvm_type_rank_v(t string) int {
	if t == 'i8' { return 1 }
	if t == 'i16' { return 2 }
	if t == 'i32' { return 4 }
	if t == 'i64' { return 8 }
	return 0
}

fn llvm_hex2(b u8) string {
	hi := int(b) >> 4
	lo := int(b) & 15
	return llvm_hexdigits[hi..hi + 1] + llvm_hexdigits[lo..lo + 1]
}

// 0.9.7 修复版：字节一律写成 LLVM c"..." 的 \XX 转义。
fn llvm_byte_esc(b u8) string {
	return '\\' + llvm_hex2(b)
}

fn llvm_hex_bytes_v(data []u8) string {
	mut esc := ''
	for b in data { esc += llvm_byte_esc(b) }
	return esc
}

// cone 字符串原文（带引号）-> (LLVM c"..." 内容, 字节数含结尾 \00)
// ---- cone 0.9.f：w"..." 宽字符串（UTF-16LE）----
fn is_wide_lit_v(raw string) bool {
	return raw.len >= 3 && (raw[0] == 119 || raw[0] == 87) && (raw[1] == 34 || raw[1] == 39)
}

fn strip_lit_v(raw string) (string, bool) {
	wide := is_wide_lit_v(raw)
	mut s2 := raw
	// w"..." 里 w 是 [0]、开引号是 [1]：只跳 w，引号交给下面统一剥离。
	if wide { s2 = raw[1..] }
	if s2.len >= 2 && (s2[0] == 34 || s2[0] == 39) && s2[s2.len - 1] == s2[0] {
		s2 = s2[1..s2.len - 1]
	}
	return s2, wide
}

// UTF-8 字节序列 -> Unicode 码点（最多 4 字节），返回 (码点, 消费字节数)。
fn llvm_utf8_cp_v(s string, i int) (u32, int) {
	b0 := u32(s[i])
	if b0 < 0x80 { return b0, 1 }
	if b0 >= 0xC2 && b0 <= 0xDF && i + 1 < s.len {
		return ((b0 & 0x1F) << 6) | (u32(s[i + 1]) & 0x3F), 2
	}
	if b0 >= 0xE0 && b0 <= 0xEF && i + 2 < s.len {
		return ((b0 & 0x0F) << 12) | ((u32(s[i + 1]) & 0x3F) << 6) | (u32(s[i + 2]) & 0x3F), 3
	}
	if b0 >= 0xF0 && b0 <= 0xF4 && i + 3 < s.len {
		return ((b0 & 0x07) << 18) | ((u32(s[i + 1]) & 0x3F) << 12) |
			((u32(s[i + 2]) & 0x3F) << 6) | (u32(s[i + 3]) & 0x3F), 4
	}
	return b0, 1
}

fn llvm_push_u16_v(mut data []u8, v u32) {
	data << u8(v & 255)
	data << u8((v >> 8) & 255)
}

fn llvm_push_cp_v(mut data []u8, cp u32) {
	if cp <= 0xFFFF {
		llvm_push_u16_v(mut data, cp)
	} else {
		v := cp - 0x10000
		llvm_push_u16_v(mut data, 0xD800 + (v >> 10))
		llvm_push_u16_v(mut data, 0xDC00 + (v & 0x3FF))
	}
}

fn lit_bytes_v(s string, wide bool) []u8 {
	mut data := []u8{}
	mut i := 0
	for i < s.len {
		c := s[i]
		if c == 92 && i + 1 < s.len {
			n := s[i + 1]
			mut v := int(n)
			if n == 110 { v = 10 } else if n == 114 { v = 13 }
			else if n == 116 { v = 9 } else if n == 48 { v = 0 }
			else if n == 92 { v = 92 } else if n == 34 { v = 34 }
			else if n == 39 { v = 39 } else if n == 97 { v = 7 }
			else if n == 98 { v = 8 } else if n == 102 { v = 12 }
			else if n == 118 { v = 11 }
			if wide { llvm_push_u16_v(mut data, u32(v & 255)) } else { data << u8(v & 255) }
			i += 2
			continue
		}
		if wide {
			cp, nn := llvm_utf8_cp_v(s, i)
			i += nn
			llvm_push_cp_v(mut data, cp)
		} else {
			data << c
			i++
		}
	}
	return data
}

fn masm_hex_byte_v(bb u8) string {
	hi := int(bb >> 4)
	lo := int(bb & 15)
	h := llvm_hexdigits[hi..hi + 1] + llvm_hexdigits[lo..lo + 1]
	if hi >= 10 { return '0' + h + 'h' }
	return h + 'h'
}

// x86 后端：w"..." -> MASM db 的十六进制字节项（自带 2 字节 NUL）。
fn wide_lit_masm_v(lit string) string {
	s2, wide := strip_lit_v(lit)
	if !wide { return lit }
	mut data := lit_bytes_v(s2, true)
	data << u8(0)
	data << u8(0)
	mut parts := []string{}
	for b2 in data { parts << masm_hex_byte_v(b2) }
	return parts.join(',')
}

fn llvm_str_bytes_v(raw string) (string, int) {
	s2, wide := strip_lit_v(raw)
	mut data := lit_bytes_v(s2, wide)
	if wide { data << u8(0); data << u8(0) } else { data << u8(0) }
	return llvm_hex_bytes_v(data), data.len
}


fn (mut g LGen) data_item_bytes_v(idx int) []u8 {
	mut data := []u8{}
	if idx < 0 || idx >= g.prog.exprs.len { return data }
	e := g.prog.exprs[idx]
	if e.kind == ExprKind.expr_str {
		s2, wide := strip_lit_v(e.text)
		mut out := lit_bytes_v(s2, wide)
		// 数据定义里的 w"..." 自带 2 字节 UTF-16 终止符，不要再加 ,0。
		if wide { out << u8(0); out << u8(0) }
		return out
	}
	if e.kind == ExprKind.expr_num {
		data << u8(llvm_int_v(e.text).int() & 255)
		return data
	}
	if e.kind == ExprKind.expr_neg {
		data << u8((-llvm_int_v(g.prog.exprs[e.a].text).int()) & 255)
		return data
	}
	g.err = 'x64: 不支持数据段里的非常量项'
	return data
}

fn llvm_int_v(text string) string {
	mut s := text.trim_space()
	if s.len == 0 { return '0' }
	if s.len >= 3 && s[0] == 39 && s[s.len - 1] == 39 {
		return int(s[1]).str()
	}
	mut base := 10
	mut body := s
	mut neg := false
	if s.starts_with('-') { neg = true; body = s[1..] }
	if body.starts_with('0x') || body.starts_with('0X') {
		base = 16
		body = body[2..]
	} else if body.ends_with('h') || body.ends_with('H') {
		base = 16
		body = body[..body.len - 1]
	}
	mut v := 0
	for i := 0; i < body.len; i++ {
		c := body[i]
		mut d := 0
		if c >= 48 && c <= 57 { d = int(c) - 48 }
		else if c >= 65 && c <= 70 { d = int(c) - 55 }
		else if c >= 97 && c <= 102 { d = int(c) - 87 }
		else { continue }
		v = v * base + d
	}
	if neg { v = -v }
	return v.str()
}

fn llvm_binop_v(op string) string {
	if op == '+' { return 'add' }
	if op == '-' { return 'sub' }
	if op == '*' { return 'mul' }
	if op == '/' { return 'sdiv' }
	if op == '%' { return 'srem' }
	if op == '&' { return 'and' }
	if op == '|' { return 'or' }
	if op == '^' { return 'xor' }
	if op == '<<' { return 'shl' }
	if op == '>>' { return 'lshr' }
	return ''
}

fn llvm_cmp_v(op string) string {
	if op == '==' { return 'eq' }
	if op == '!=' { return 'ne' }
	if op == '<' { return 'ult' }
	if op == '<=' { return 'ule' }
	if op == '>' { return 'ugt' }
	if op == '>=' { return 'uge' }
	return ''
}

// ---------- cone 0.9.a：声明 / 调用约定 / 符号修饰 ----------
fn llvm_struct_size_v(st SymTab, t string) int {
	if t in st.struct_size { return st.struct_size[t] }
	return 0
}

fn llvm_is_struct_v(st SymTab, t string) bool {
	return llvm_struct_size_v(st, t) > 0
}

// Windows x64 ABI：1/2/4/8 字节结构体按值走整数寄存器，其余按指针（调用方拷贝）。
fn llvm_param_ir_ty_v(st SymTab, t string) (string, string) {
	if llvm_is_struct_v(st, t) {
		size := llvm_struct_size_v(st, t)
		if size == 1 || size == 2 || size == 4 || size == 8 {
			return 'i' + (size * 8).str(), 'value'
		}
		return 'ptr', 'ref'
	}
	return llvm_ret_type_v(t), 'value'
}

fn llvm_struct_agg_ty_v(size int) string {
	return '[' + size.str() + ' x i8]'
}

// x64：include xxx -> xxx.lib；include xxx.yyy -> xxx.yyy（原样）。
// import 是源码级导入，不产生链接项。
fn llvm_int_width_v(ty string) int {
	if ty == 'i1' { return 1 }
	if ty == 'i8' { return 8 }
	if ty == 'i16' { return 16 }
	if ty == 'i32' { return 32 }
	if ty == 'i64' { return 64 }
	return 0
}

// 把 ret 的返回值转成 ExitProcess 的实参类型，必要时追加转换指令。
fn (mut g LGen) cast_exit_v(v string, from_ty string) string {
	to_ty := g.exit_arg
	if from_ty == to_ty { return v }
	fw := llvm_int_width_v(from_ty)
	tw := llvm_int_width_v(to_ty)
	if fw > 0 && tw > 0 {
		if fw == tw { return v }
		mut op := 'sext'
		if fw > tw { op = 'trunc' } else if from_ty == 'i1' { op = 'zext' }
		t := g.nt()
		g.lines << '  ' + t + ' = ' + op + ' ' + from_ty + ' ' + v + ' to ' + to_ty
		return t
	}
	if (from_ty == 'float' || from_ty == 'double') && tw > 0 {
		t := g.nt()
		g.lines << '  ' + t + ' = fptosi ' + from_ty + ' ' + v + ' to ' + to_ty
		return t
	}
	if fw > 0 && (to_ty == 'float' || to_ty == 'double') {
		t := g.nt()
		g.lines << '  ' + t + ' = sitofp ' + from_ty + ' ' + v + ' to ' + to_ty
		return t
	}
	return llvm_zero_of_v(to_ty)
}

// 准备 ExitProcess 的 declare：优先复用用户声明的签名，否则用真实 Windows
// 签名 void @ExitProcess(i32)。
fn (mut g LGen) setup_exitprocess_v() {
	g.exit_ret = 'void'
	g.exit_arg = 'i32'
	for p2 in g.protos {
		if p2.cone_name == 'ExitProcess' {
			g.exit_ret = p2.ret
			if p2.ptypes.len > 0 { g.exit_arg = p2.ptypes[0] }
			break
		}
	}
	mut has := false
	for d in g.decls { if d.name == 'ExitProcess' { has = true; break } }
	if !has {
		g.decls << LDecl{
			name:  'ExitProcess'
			sig:   'declare ' + g.exit_ret + ' @ExitProcess(' + g.exit_arg + ')'
			types: g.exit_arg
			va:    false
		}
	}
}

// 把入口函数体内所有 ret 换成 call ExitProcess + unreachable。
fn (mut g LGen) rewrite_entry_v(lo int) {
	mut rest := []string{}
	for i in lo .. g.lines.len { rest << g.lines[i] }
	g.lines = g.lines[..lo]
	for ln in rest {
		st := ln.trim_space()
		if st == 'ret void' || st.starts_with('ret ') {
			mut ps := []string{}
			for q in st.split(' ') { if q.len > 0 { ps << q } }
			mut val := '0'
			if ps.len >= 3 { val = g.cast_exit_v(ps[2], ps[1]) }
			g.lines << '  call ' + g.exit_ret + ' @ExitProcess(' + g.exit_arg + ' ' + val + ')'
			g.lines << '  unreachable'
		} else {
			g.lines << ln
		}
	}
}

fn x64_auto_exit_needed_v(prog Program) bool {
	// cone 0.9.f：入口存在且函数体内没有显式 ExitProcess 调用时，编译器
	// 自动以 ExitProcess 结束入口；链接命令因此需要 kernel32.lib。
	for f in prog.funcs {
		if f.name != prog.entry { continue }
		mut stack := []int{}
		mut seen := []int{}
		for s2 in f.body {
			for idx in [s2.ret_idx, s2.rhs_idx, s2.cond_idx, s2.call_idx,
						s2.target_idx, s2.case_idx, s2.lhs_idx] {
				if idx >= 0 { stack << idx }
			}
			for idx in s2.local_inits { if idx >= 0 { stack << idx } }
		}
		for stack.len > 0 {
			i := stack.pop()
			if i in seen || i >= prog.exprs.len { continue }
			seen << i
			e := prog.exprs[i]
			if e.kind == ExprKind.expr_call && e.text == 'ExitProcess' { return false }
			if e.a >= 0 { stack << e.a }
			if e.b >= 0 { stack << e.b }
			for ai in e.args { stack << ai }
		}
		return true
	}
	return false
}

fn x64_include_libs_v(prog Program) []string {
	mut out := []string{}
	for inc in prog.includes {
		nm := inc.name.trim_space()
		if nm.len == 0 { continue }
		mut lib := nm
		if !nm.contains('.') { lib = nm + '.lib' }
		if !(lib in out) { out << lib }
	}
	// cone 0.9.f：入口自动 ExitProcess 需要 kernel32.lib（main.v 去重）。
	if x64_auto_exit_needed_v(prog) && !('kernel32.lib' in out) {
		out << 'kernel32.lib'
	}
	return out
}

fn llvm_ret_type_v(t string) string {
	if t == 'int' { return 'i32' }
	if t == 'byte' { return 'i8' }
	if t == 'word' { return 'i16' }
	if t == 'long' { return 'i64' }
	if t == 'f32' { return 'float' }
	if t == 'f64' { return 'double' }
	return 'i32'
}

// cone 0.9.f：x64 下 c 与 stdcall 都**不产生符号修饰**，链接符号一律原名。
// 依据：dumpbin /exports kernel32.lib 导出全是裸名；统一 Windows x64 ABI 后
// 调用约定与符号修饰都不再由这两个后缀决定。
fn llvm_decorate_v(name string, conv string, nfixed int) (string, bool) {
	return name, false
}

fn llvm_is_crt_alias_v(base string) bool {
	return base == 'printf' || base == 'crt_printf' || base == 'puts' || base == 'crt_puts' ||
		base == 'sprintf' || base == 'crt_sprintf' || base == 'strlen' || base == 'crt_strlen' ||
		base == 'malloc' || base == 'crt_malloc' || base == 'free' || base == 'crt_free' ||
		base == 'exit' || base == 'crt_exit' || base == 'wsprintf' || base == 'crt_wsprintf'
}

fn llvm_has_proto_v(ps []LProto, name string) bool {
	for p in ps { if p.cone_name == name { return true } }
	return false
}

// 收集 func 声明 / def 定义 / win.crt_* 内建兼容别名

fn (mut g LGen) init_protos_v() {
	mut defined := []string{}
	for f in g.prog.funcs {
		defined << f.name
		if f.is_export { g.exports << f.name }
		mut rt := f.ret_type
		if rt.len == 0 && f.name in g.st.func_ret_type { rt = g.st.func_ret_type[f.name] }
		mut ps := []string{}
		mut pc := []string{}
		for q in f.params {
			if q.typ_name == 'vararg' { continue }
			ity, _ := llvm_param_ir_ty_v(g.st, q.typ_name)
			ps << ity
			pc << q.typ_name
		}
		mut sret := false
		mut rsz := 0
		if llvm_is_struct_v(g.st, rt) || (f.name in g.st.func_ret_is_struct && g.st.func_ret_is_struct[f.name]) {
			sret = true
			rsz = llvm_struct_size_v(g.st, rt)
		}
		mut rty := 'void'
		if !sret { rty = llvm_ret_type_v(rt) }
		g.protos << LProto{cone_name: f.name, ret: rty, sret: sret, sret_size: rsz,
			conv: 'cc_c', nfixed: ps.len, ptypes: ps, pcone: pc,
			sym: f.name, quoted: false, va: false, legacy: false}
	}
	for pd in g.prog.protos {
		if pd.name in defined {
			for q2 in pd.params {
				if q2.typ_name == 'vararg' {
					for i := 0; i < g.protos.len; i++ {
						if g.protos[i].cone_name == pd.name { g.protos[i].va = true }
					}
					break
				}
			}
			if pd.ret_type.len > 0 {
				for i := 0; i < g.protos.len; i++ {
					if g.protos[i].cone_name == pd.name {
						if llvm_is_struct_v(g.st, pd.ret_type) ||
							(pd.name in g.st.func_ret_is_struct && g.st.func_ret_is_struct[pd.name]) {
							g.protos[i].sret = true
							g.protos[i].sret_size = llvm_struct_size_v(g.st, pd.ret_type)
							g.protos[i].ret = 'void'
						} else {
							g.protos[i].ret = llvm_ret_type_v(pd.ret_type)
						}
						break
					}
				}
			}
			continue
		}
		mut conv := 'cc_default'
		if pd.conv == CallConv.cc_c { conv = 'cc_c' }
		else if pd.conv == CallConv.cc_stdcall { conv = 'cc_stdcall' }
		mut ps := []string{}
		mut pc := []string{}
		mut va := false
		for q in pd.params {
			if q.typ_name == 'vararg' {
				va = true
				continue
			}
			ity, _ := llvm_param_ir_ty_v(g.st, q.typ_name)
			ps << ity
			pc << q.typ_name
		}
		sym, quoted := llvm_decorate_v(pd.name, conv, ps.len)
		mut sret := false
		mut rsz := 0
		if llvm_is_struct_v(g.st, pd.ret_type) ||
			(pd.name in g.st.func_ret_is_struct && g.st.func_ret_is_struct[pd.name]) {
			sret = true
			rsz = llvm_struct_size_v(g.st, pd.ret_type)
		}
		mut rty := 'void'
		if !sret { rty = llvm_ret_type_v(pd.ret_type) }
		g.protos << LProto{cone_name: pd.name, ret: rty, sret: sret, sret_size: rsz,
			conv: conv, nfixed: ps.len, ptypes: ps, pcone: pc,
			sym: sym, quoted: quoted, va: va, legacy: false}
	}
}

fn llvm_crt_name_v(base string) string {
	if base == 'crt_printf' { return 'printf' }
	if base == 'crt_puts' { return 'puts' }
	if base == 'crt_sprintf' { return 'sprintf' }
	if base == 'crt_strlen' { return 'strlen' }
	if base == 'crt_malloc' { return 'malloc' }
	if base == 'crt_free' { return 'free' }
	if base == 'crt_exit' { return 'exit' }
	if base == 'wsprintf' || base == 'crt_wsprintf' { return 'wsprintfA' }
	return base
}

fn llvm_is_va_v(n string) bool {
	return n == 'printf' || n == 'sprintf' || n == 'wsprintfA'
}

// ---- 生成器状态 ----
// 槽位 kind：scalar / array / struct / data
struct LVar {
mut:
	name    string
	ptr     string
	ty      string
	kind    string
	elem_ty string
	n       int
	sname   string
}

struct LStr {
	esc  string
	name string
	n    int
}

// ---- cone 0.9.f：LLVM IR 名字转义 ----
// LLVM 裸标识符只允许 [-a-zA-Z$._0-9]；cone x64 标识符允许 @ 和 ?，
// 这类名字在 IR 里必须写成 @"..." / %"..."（$ 本身是合法裸字符，不转义）。
// 生成完整 IR 后做一遍文本级后处理：只改引号外、注释外的 @/% 名字。
fn llvm_name_char_v(c u8) bool {
	return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57)
		|| c == 45 || c == 46 || c == 95 || c == 36 || c == 64 || c == 63
}

fn llvm_quote_names_in_code_v(code string) string {
	// 注释从第一个 ; 开始（IR 字符串里 ; 一律写成 \3B）
	mut ci := 0
	for ci < code.len && code[ci] != 59 {
		ci++
	}
	head := code[..ci]
	tail := code[ci..]
	mut out := ''
	mut i := 0
	for i < head.len {
		c := head[i]
		if (c == 64 || c == 37) && i + 1 < head.len && head[i + 1] != 34 {
			mut j := i + 1
			mut special := false
			for j < head.len && llvm_name_char_v(head[j]) {
				if head[j] == 64 || head[j] == 63 { special = true }
				j++
			}
			name := head[i + 1..j]
			if name.len > 0 && special {
				out += head[i..i + 1] + '"' + name + '"'
			} else {
				out += head[i..j]
			}
			i = j
		} else {
			out += head[i..i + 1]
			i++
		}
	}
	return out + tail
}

fn llvm_quote_special_names_v(ir string) string {
	mut out := ''
	for line in ir.split('\n') {
		mut segs := line.split('"')
		mut k := 0
		for k < segs.len {
			if k % 2 == 0 {
				segs[k] = llvm_quote_names_in_code_v(segs[k])
			}
			k++
		}
		out += segs.join('"') + '\n'
	}
	if out.len > 0 && out[out.len - 1] == 10 {
		out = out[..out.len - 1]
	}
	return out
}

struct LDecl {
	name  string
	sig   string
	types string
	va    bool
}

// cone 0.9.f：x64 外部/内部函数声明表（func 声明驱动 declare / call）
struct LProto {
mut:
	cone_name string
	ret       string // LLVM 返回类型
	conv      string // 'cc_c' / 'cc_stdcall' / 'cc_default'：仅影响符号修饰
	nfixed    int    // 固定形参数
	ptypes    []string
	sym       string // COFF 链接符号（可能带 stdcall 修饰）
	quoted    bool   // IR 里是否要写成 @"..."
	va        bool
	legacy    bool   // 0.9.9 win.crt_* 兼容路径
	// cone 0.9.f：结构体返回 / 形参
	sret      bool
	sret_size int
	pcone     []string // cone 层形参类型名（用于结构体实参转换）
}

struct LIfFrame {
mut:
	end         string
	pending     string
	has_pending bool
}

struct LForFrame {
mut:
	cond  string
	after string
}

struct LMatchFrame {
mut:
	disc     string
	end      string
	next     string
	has_next bool
}

struct LSehHandler {
	except_idx int
	lbl        string
}

struct LSehFrame {
mut:
	try_id        int
	seq           int
	cs            string
	cp            string
	filt          string
	flag_g        string
	retval_g      string
	cont          string
	disp          string
	hand          string
	ret_lbl       string
	normal        string
	default_lbl   string
	handlers      []LSehHandler
	cur_handler   int
	body_done     bool
	except_open   bool
	parent        string // catchswitch within 的父 funclet（none 或外层 %cp）
	saved_funclet string
	saved_cont    string
	saved_flag    string
	saved_retval  string
	loop_after    string
	loop_cond     string
	line          int
}

struct LGen {
mut:
	prog       Program
	st         SymTab
	arch       string
	opt        string // cone 0.9.f：llc 优化级别 '0'..'z'
	lines      []string
	tmp        int
	blk        int
	cur        string
	term       bool
	gvars      []LVar
	vars       []LVar
	decls      []LDecl
	strs       []LStr
	func_names []string
	ifs        []LIfFrame
	fors       []LForFrame
	matches    []LMatchFrame
	err        string
	// cone 0.9.f
	protos     []LProto
	notices    []string
	ret_ty     string
	exports    []string
	hint_skip  int
	// cone 0.9.f：SEH / 结构体返回 / funclet / 诊断
	cur_func       string
	funclet        string
	funclet_cont   string
	funclet_flag   string
	funclet_retval string
	sehs           []LSehFrame
	seh_seq        int
	seh_used       bool
	filters        []string
	seh_globals    []string
	sret_ptr       string
	sret_size      int
	sret_target    string
	err_line       int
	cur_line       int
	asm64_seq      int // cone 0.9.p：asm64{} 块序号（标号前缀唯一化）
	// cone 0.9.f：入口函数自动 ExitProcess（不能用 ret 退出进程）
	entry_name     string
	auto_exit      bool
	exit_ret       string
	exit_arg       string
}

fn (mut g LGen) out(s string) { g.lines << s }

// funclet 内的 call/invoke 必须带 bundle。
fn (mut g LGen) fbundle_v() string {
	if g.funclet.len > 0 { return ' [ "funclet"(token ' + g.funclet + ') ]' }
	return ''
}

fn (mut g LGen) set_err_v(msg string, line int) {
	if g.err.len == 0 {
		g.err = msg
		g.err_line = line
	}
}

fn (mut g LGen) nt() string {
	g.tmp++
	return '%t' + g.tmp.str()
}

fn (mut g LGen) nb(tag string) string {
	g.blk++
	return 'B' + g.blk.str() + '_' + tag
}

fn (mut g LGen) setblk(name string) {
	if !g.term && g.cur.len > 0 { g.out('  br label %' + name) }
	g.out(name + ':')
	g.cur = name
	g.term = false
}

fn (mut g LGen) jump(t string) {
	g.out('  br label %' + t)
	g.term = true
}

fn (mut g LGen) br(c string, t string, f string) {
	g.out('  br i1 ' + c + ', label %' + t + ', label %' + f)
	g.term = true
}


fn (mut g LGen) as_i1(v string, ty string) string {
	if ty == 'i1' { return v }
	if ty == 'ptr' {
		g.err = 'x64: 不支持把指针当条件'
		return '0'
	}
	if llvm_is_float_ty_v(ty) {
		r := g.nt()
		g.out('  ' + r + ' = fcmp one ' + ty + ' ' + v + ', 0.0')
		return r
	}
	r := g.nt()
	g.out('  ' + r + ' = icmp ne ' + ty + ' ' + v + ', 0')
	return r
}


fn (mut g LGen) as_i32(v string, ty string) string {
	if ty == 'ptr' {
		g.err = 'x64: 不支持把指针转成 32 位整数（x64 地址是 64 位；请用数组/结构体成员语法）'
		return '0'
	}
	return g.as_type_v(v, ty, 'i32')
}


fn (mut g LGen) as_type_v(v string, ty string, want string) string {
	if ty == want { return v }
	if ty == 'ptr' || want == 'ptr' {
		g.err = 'x64: 不支持指针与数值互转'
		return '0'
	}
	mut vv := v
	mut tt := ty
	if tt == 'i1' {
		r := g.nt()
		g.out('  ' + r + ' = zext i1 ' + vv + ' to i32')
		vv = r
		tt = 'i32'
	}
	if tt == want { return vv }
	rank_t := llvm_type_rank_v(tt)
	rank_w := llvm_type_rank_v(want)
	if rank_t > 0 && rank_w > 0 {
		r := g.nt()
		if rank_w < rank_t {
			g.out('  ' + r + ' = trunc ' + tt + ' ' + vv + ' to ' + want)
		} else {
			g.out('  ' + r + ' = sext ' + tt + ' ' + vv + ' to ' + want)
		}
		return r
	}
	if rank_t > 0 && llvm_is_float_ty_v(want) {
		r := g.nt()
		g.out('  ' + r + ' = sitofp ' + tt + ' ' + vv + ' to ' + want)
		return r
	}
	if llvm_is_float_ty_v(tt) && rank_w > 0 {
		r := g.nt()
		g.out('  ' + r + ' = fptosi ' + tt + ' ' + vv + ' to ' + want)
		return r
	}
	if llvm_is_float_ty_v(tt) && llvm_is_float_ty_v(want) {
		r := g.nt()
		if tt == 'float' {
			g.out('  ' + r + ' = fpext float ' + vv + ' to double')
		} else {
			g.out('  ' + r + ' = fptrunc double ' + vv + ' to float')
		}
		return r
	}
	return '0'
}

fn (mut g LGen) find_var(name string) LVar {
	for v in g.vars { if v.name == name { return v } }
	for v in g.gvars { if v.name == name { return v } }
	return LVar{}
}

fn (mut g LGen) slot_ptr0_v(v LVar) string {
	if v.kind == 'scalar' || v.kind == 'structref' { return v.ptr }
	r := g.nt()
	g.out('  ' + r + ' = getelementptr inbounds ' + v.ty + ', ptr ' + v.ptr + ', i32 0, i32 0')
	return r
}

fn (mut g LGen) load_ptr_v(ptr string, ty string) string {
	r := g.nt()
	g.out('  ' + r + ' = load ' + ty + ', ptr ' + ptr)
	return r
}

fn (mut g LGen) gep_bytes_v(ptr string, off string) string {
	r := g.nt()
	g.out('  ' + r + ' = getelementptr inbounds i8, ptr ' + ptr + ', i32 ' + off)
	return r
}

fn (mut g LGen) store_int_v(ptr string, ty string, v string, src_ty string) {
	x := g.as_type_v(v, src_ty, ty)
	g.out('  store ' + ty + ' ' + x + ', ptr ' + ptr)
}

fn (mut g LGen) string_v(raw string) (string, string) {
	esc, n := llvm_str_bytes_v(raw)
	mut nm := ''
	for s in g.strs {
		if s.esc == esc { nm = s.name; break }
	}
	if nm.len == 0 {
		nm = '.str.' + g.strs.len.str()
		g.strs << LStr{esc: esc, name: nm, n: n}
	}
	p := g.nt()
	g.out('  ' + p + ' = getelementptr inbounds [' + n.str() + ' x i8], ptr @' + nm + ', i32 0, i32 0')
	return p, 'ptr'
}

fn (mut g LGen) const_expr(idx int) string {
	if idx < 0 || idx >= g.prog.exprs.len { return '0' }
	e := g.prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		if llvm_is_float_text_v(e.text) { return e.text }
		return llvm_int_v(e.text)
	}
	if e.kind == ExprKind.expr_neg {
		a := g.const_expr(e.a)
		return '-' + a
	}
	if e.kind == ExprKind.expr_ident {
		if e.text in g.st.equ_values { return llvm_int_v(g.st.equ_values[e.text]) }
		if e.text in g.prog.folded_equs { return llvm_int_v(g.prog.folded_equs[e.text]) }
	}
	if e.kind == ExprKind.expr_bin {
		a := g.const_expr(e.a).int()
		b := g.const_expr(e.b).int()
		op := e.text
		mut v := 0
		if op == '+' { v = a + b }
		else if op == '-' { v = a - b }
		else if op == '*' { v = a * b }
		else if op == '/' && b != 0 { v = a / b }
		else if op == '%' && b != 0 { v = a % b }
		else if op == '&' { v = a & b }
		else if op == '|' { v = a | b }
		else if op == '^' { v = a ^ b }
		// 0.9.8：先转 u32 再移位，避免 V 的「signed 移位可能改符号」notice
		else if op == '<<' { v = int(u32(a) << u32(b)) }
		else if op == '>>' { v = int(u32(a) >> u32(b)) }
		return v.str()
	}
	g.err = 'x64: 不支持非常量全局初值'
	return '0'
}

fn (mut g LGen) logic_v(op string, ai int, bi int) (string, string) {
	a0, t0 := g.expr_v(ai)
	a := g.as_i1(a0, t0)
	rhs := g.nb('lrhs')
	sc := g.nb('lshort')
	join := g.nb('ljoin')
	if op == '&&' { g.br(a, rhs, sc) } else { g.br(a, sc, rhs) }
	g.setblk(rhs)
	b0, t1 := g.expr_v(bi)
	b := g.as_i1(b0, t1)
	g.jump(join)
	g.setblk(sc)
	g.jump(join)
	g.setblk(join)
	r := g.nt()
	if op == '&&' {
		g.out('  ' + r + ' = phi i1 [ false, %' + sc + ' ], [ ' + b + ', %' + rhs + ' ]')
	} else {
		g.out('  ' + r + ' = phi i1 [ true, %' + sc + ' ], [ ' + b + ', %' + rhs + ' ]')
	}
	return r, 'i1'
}

fn llvm_has_decl_v(ds []LDecl, name string) bool {
	for d in ds { if d.name == name { return true } }
	return false
}


fn (mut g LGen) call_v(e Expr) (string, string) {
	// conex64 实参尺寸三分支（代码生成口径，不随诊断文案变化）：
	//   等于声明尺寸：ty == want，as_type 原样返回，不发射转换指令；
	//   小于声明尺寸：按声明类型发射 as_type —— iN -> iM 用 sext、i1 -> i32
	//       用 zext、iN -> f32/f64 用 sitofp、浮点之间用 fptrunc/fpext，
	//       结果类型为声明类型；
	//   大于声明尺寸：as_type 会走 trunc（诊断层在 x64 下拦截）。
	// 诊断见 analyzer.v 的 x64_check_calls_v()，只在 -llvm:x64 生效。
	raw := e.text
	mut vals := []string{}
	mut types := []string{}
	for ai in e.args {
		v0, t0 := g.expr_v(ai)
		mut v := v0
		mut t := t0
		if t == 'i1' { v = g.as_i32(v, t); t = 'i32' }
		vals << v
		types << t
	}
	irname := raw
	mut pi := LProto{}
	mut found := false
	for p in g.protos {
		if p.cone_name == irname { pi = p; found = true; break }
	}
	if !found {
		mut ps := []string{}
		mut pc := []string{}
		for t in types { ps << t; pc << 'int' }
		pi = LProto{cone_name: irname, ret: 'i32', conv: 'cc_c', nfixed: types.len,
			ptypes: ps, pcone: pc, sym: irname, quoted: false, va: false, legacy: false,
			sret: false, sret_size: 0}
		g.protos << pi
	}
	mut ref := '@' + pi.sym
	if pi.quoted { ref = '@"' + pi.sym + '"' }
	mut ptypes := []string{}
	for t in pi.ptypes { ptypes << t }
	mut pcone := []string{}
	for t in pi.pcone { pcone << t }
	for k := 0; k < ptypes.len && k < types.len; k++ {
		if types[k] == 'ptr' && !(k < pcone.len && llvm_is_struct_v(g.st, pcone[k])) {
			ptypes[k] = 'ptr'
		}
	}
	sret := pi.sret
	is_va := pi.va || vals.len > pi.nfixed
	mut sig_fixed := []string{}
	if sret { sig_fixed << 'ptr' }
	for k := 0; k < pi.nfixed && k < ptypes.len; k++ { sig_fixed << ptypes[k] }
	mut decl_sig := sig_fixed.join(', ')
	if is_va {
		if decl_sig.len > 0 { decl_sig += ', ...' } else { decl_sig = '...' }
	}
	mut is_internal := false
	for fname in g.func_names { if fname == irname { is_internal = true; break } }
	if !llvm_has_decl_v(g.decls, irname) && !is_internal {
		g.decls << LDecl{name: irname, sig: 'declare ' + pi.ret + ' ' + ref + '(' + decl_sig + ')',
			types: decl_sig, va: is_va}
	}
	mut actual := []string{}
	if sret {
		mut sp := g.sret_target
		if sp.len == 0 {
			sp = g.nt()
			g.out('  ' + sp + ' = alloca ' + llvm_struct_agg_ty_v(pi.sret_size))
		}
		actual << 'ptr ' + sp
	}
	for k := 0; k < vals.len; k++ {
		mut want := 'i32'
		if k < pi.nfixed {
			want = ptypes[k]
		} else {
			want = types[k]
			if types[k] == 'i1' || types[k] == 'i8' || types[k] == 'i16' { want = 'i32' }
			else if types[k] == 'float' { want = 'double' }
		}
		mut vv := vals[k]
		mut tt := types[k]
		// cone 0.9.f：结构体形参按 Windows x64 ABI 转换
		if k < pi.nfixed && k < pcone.len && llvm_is_struct_v(g.st, pcone[k]) && tt == 'ptr' {
			size := llvm_struct_size_v(g.st, pcone[k])
			agg := llvm_struct_agg_ty_v(size)
			if want != 'ptr' {
				nv := g.nt()
				g.out('  ' + nv + ' = load ' + want + ', ptr ' + vv)
				vv = nv
				tt = want
			} else {
				tmp := g.nt()
				g.out('  ' + tmp + ' = alloca ' + agg)
				av := g.nt()
				g.out('  ' + av + ' = load ' + agg + ', ptr ' + vv)
				g.out('  store ' + agg + ' ' + av + ', ptr ' + tmp)
				vv = tmp
				tt = 'ptr'
			}
		}
		if want == 'ptr' && tt != 'ptr' {
			g.err = 'x64: 对 @' + irname + ' 传 ' + tt + ' 给 ptr 形参；请用字符串字面量或 addr 标签'
			g.err_line = g.cur_line
			return '0', 'i32'
		}
		if llvm_is_num_ty_v(want) && tt == 'ptr' {
			g.err = 'x64: 把指针传给 @' + irname + ' 的 ' + want + ' 形参；x64 地址是 64 位'
			g.err_line = g.cur_line
			return '0', 'i32'
		}
		if want != tt && want != 'ptr' { vv = g.as_type_v(vv, tt, want) }
		actual << want + ' ' + vv
	}
	r := g.nt()
	mut call_line := 'call ' + pi.ret
	if is_va { call_line += ' (' + decl_sig + ')' }
	call_line += ' ' + ref + '(' + actual.join(', ') + ')' + g.fbundle_v()
	if pi.ret == 'void' {
		g.out('  ' + call_line)
		return '0', 'void'
	}
	g.out('  ' + r + ' = ' + call_line)
	return r, pi.ret
}

fn llvm_is_num_ty_v(t string) bool {
	return t == 'i1' || t == 'i8' || t == 'i16' || t == 'i32' || t == 'i64' ||
		t == 'float' || t == 'double'
}

fn (mut g LGen) expr_ident_v(e Expr) (string, string) {
	nm := e.text
	if nm in g.st.equ_values { return llvm_int_v(g.st.equ_values[nm]), 'i32' }
	if nm in g.prog.folded_equs { return llvm_int_v(g.prog.folded_equs[nm]), 'i32' }
	v := g.find_var(nm)
	if v.name.len == 0 {
		g.err = 'x64: 不支持标识符 ' + nm + '（未声明符号；x86 请走默认后端）'
		return '0', 'i32'
	}
	if v.kind != 'scalar' {
		return g.slot_ptr0_v(v), 'ptr'
	}
	val := g.load_ptr_v(v.ptr, v.ty)
	return val, v.ty
}

fn (mut g LGen) member_addr_v(e Expr) (string, string) {
	base := e.member_base
	path := e.member_path
	// 类型名.member：偏移立即数（analyzer 通常已折叠；这里兜底）
	if base in g.st.struct_size {
		key := base + '.' + path
		if !(key in g.st.struct_offsets) {
			g.err = 'x64: 不支持结构体偏移 ' + key
			return '0', 'imm'
		}
		return g.st.struct_offsets[key].str(), 'imm'
	}
	v := g.find_var(base)
	if v.name.len == 0 {
		g.err = 'x64: 不支持标识符 ' + base + '（未声明符号）'
		return '0', 'i32'
	}
	if v.kind != 'struct' && v.kind != 'structref' {
		g.err = 'x64: ' + base + '.' + path + ' 不是 cone 结构体变量'
		return '0', 'i32'
	}
	key2 := v.sname + '.' + path
	if !(key2 in g.st.struct_offsets) {
		g.err = 'x64: 不支持结构体成员 ' + key2
		return '0', 'i32'
	}
	off := g.st.struct_offsets[key2]
	p0 := g.slot_ptr0_v(v)
	p := g.gep_bytes_v(p0, off.str())
	mut mt := 'int'
	if key2 in g.st.struct_mtype { mt = g.st.struct_mtype[key2] }
	mut marr := ''
	if key2 in g.st.struct_marray { marr = g.st.struct_marray[key2] }
	if marr.len > 0 || mt in g.st.struct_size {
		return p, 'ptr'
	}
	mty := llvm_itype_v(mt)
	return p, mty
}

fn (mut g LGen) member_v(e Expr, want_addr bool) (string, string) {
	p, mty := g.member_addr_v(e)
	if mty == 'imm' { return p, 'i32' }
	if want_addr || mty == 'ptr' { return p, 'ptr' }
	val := g.load_ptr_v(p, mty)
	return val, mty
}

fn (mut g LGen) addr_of_v(idx int) string {
	if idx < 0 || idx >= g.prog.exprs.len {
		g.err = 'x64: 不支持空 addr'
		return '0'
	}
	e := g.prog.exprs[idx]
	if e.kind == ExprKind.expr_ident {
		v := g.find_var(e.text)
		if v.name.len == 0 {
			g.err = 'x64: 不支持 addr ' + e.text + '（未声明符号）'
			return '0'
		}
		return g.slot_ptr0_v(v)
	}
	if e.kind == ExprKind.expr_member {
		p, mty := g.member_addr_v(e)
		if mty == 'imm' || mty == 'ptr' {
			g.err = 'x64: 不支持 addr ' + e.text + '（成员偏移/数组成员）'
			return '0'
		}
		return p
	}
	if e.kind == ExprKind.expr_deref {
		a, ta := g.expr_v(e.a)
		if ta != 'ptr' {
			g.err = 'x64: 不支持 32 位整数地址解引用（x86 地址语义；请用数组/结构体成员语法）'
			return '0'
		}
		return a
	}
	if e.kind == ExprKind.expr_bin {
		a0, t0 := g.expr_v(e.a)
		b0, t1 := g.expr_v(e.b)
		if t0 == 'ptr' && t1 != 'ptr' { return g.gep_bytes_v(a0, g.as_i32(b0, t1)) }
		if t1 == 'ptr' && t0 != 'ptr' { return g.gep_bytes_v(b0, g.as_i32(a0, t0)) }
	}
	g.err = 'x64: 不支持 addr 的目标表达式'
	return '0'
}

fn (mut g LGen) deref_v(e Expr) (string, string) {
	a, ta := g.expr_v(e.a)
	if ta != 'ptr' {
		g.err = 'x64: 不支持 32 位整数地址解引用（x86 地址语义；请用 [int 数组名 + 下标*元素宽度] 或结构体成员语法）'
		return '0', 'i32'
	}
	lty := llvm_ptr_size_ty_v(e.ptr_size)
	val := g.load_ptr_v(a, lty)
	return val, lty
}

fn (mut g LGen) lvalue_of_v(idx int) (string, string) {
	if idx < 0 || idx >= g.prog.exprs.len {
		g.err = 'x64: 不支持空左值'
		return '0', 'i32'
	}
	e := g.prog.exprs[idx]
	if e.kind == ExprKind.expr_deref {
		p := g.addr_of_v(e.a)
		return p, llvm_ptr_size_ty_v(e.ptr_size)
	}
	if e.kind == ExprKind.expr_member {
		p, mty := g.member_addr_v(e)
		if mty == 'imm' || mty == 'ptr' {
			g.err = 'x64: 不支持对 ' + e.text + ' 赋值（成员偏移/数组成员）'
			return '0', 'i32'
		}
		return p, mty
	}
	if e.kind == ExprKind.expr_ident {
		v := g.find_var(e.text)
		if v.name.len == 0 {
			g.err = 'x64: 不支持标识符 ' + e.text
			return '0', 'i32'
		}
		if v.kind != 'scalar' { return g.slot_ptr0_v(v), v.ty }
		return v.ptr, v.ty
	}
	g.err = 'x64: 不支持该赋值左值'
	return '0', 'i32'
}


fn (mut g LGen) expr_v(idx int) (string, string) {
	if idx < 0 || idx >= g.prog.exprs.len { return '0', 'i32' }
	e := g.prog.exprs[idx]
	// cone 0.9.f：float(...) 包裹非字面量时先按原语义求值再 sitofp 到 double
	if e.is_float_hint && e.kind != ExprKind.expr_num && idx != g.hint_skip {
		g.hint_skip = idx
		v0, t0 := g.expr_v(idx)
		g.hint_skip = -1
		return g.as_type_v(v0, t0, 'double'), 'double'
	}
	if e.kind == ExprKind.expr_num {
		if (e.is_float_hint && idx != g.hint_skip) || llvm_is_float_text_v(e.text) {
			return llvm_float_const_v(e.text, 'double'), 'double'
		}
		return llvm_int_v(e.text), 'i32'
	}
	if e.kind == ExprKind.expr_str { return g.string_v(e.text) }
	if e.kind == ExprKind.expr_ident { return g.expr_ident_v(e) }
	if e.kind == ExprKind.expr_addr { return g.addr_of_v(e.a), 'ptr' }
	if e.kind == ExprKind.expr_deref { return g.deref_v(e) }
	if e.kind == ExprKind.expr_member { return g.member_v(e, false) }
	if e.kind == ExprKind.expr_neg {
		v0, t := g.expr_v(e.a)
		if llvm_is_float_ty_v(t) {
			r := g.nt()
			g.out('  ' + r + ' = fsub ' + t + ' 0.0, ' + v0)
			return r, t
		}
		v := g.as_i32(v0, t)
		r := g.nt()
		g.out('  ' + r + ' = sub i32 0, ' + v)
		return r, 'i32'
	}
	if e.kind == ExprKind.expr_bin {
		op := e.text
		if op == '&&' || op == '||' { return g.logic_v(op, e.a, e.b) }
		a0, t0 := g.expr_v(e.a)
		b0, t1 := g.expr_v(e.b)
		if t0 == 'ptr' && t1 != 'ptr' { return g.gep_bytes_v(a0, g.as_i32(b0, t1)), 'ptr' }
		if t1 == 'ptr' && t0 != 'ptr' { return g.gep_bytes_v(b0, g.as_i32(a0, t0)), 'ptr' }
		// cone 0.9.f：任一操作数是浮点 -> 统一到较宽浮点类型
		if llvm_is_float_ty_v(t0) || llvm_is_float_ty_v(t1) {
			mut want := 'float'
			if t0 == 'double' || t1 == 'double' { want = 'double' }
			a := g.as_type_v(a0, t0, want)
			b := g.as_type_v(b0, t1, want)
			r := g.nt()
			cc := llvm_fcmp_v(op)
			if cc.len > 0 {
				g.out('  ' + r + ' = fcmp ' + cc + ' ' + want + ' ' + a + ', ' + b)
				return r, 'i1'
			}
			bo := llvm_fbinop_v(op)
			if bo.len > 0 {
				g.out('  ' + r + ' = ' + bo + ' ' + want + ' ' + a + ', ' + b)
				return r, want
			}
			if op == '%' {
				g.err = 'x64: 浮点不支持 % 取模'
			} else {
				g.err = 'x64: 浮点不支持位运算符 ' + op + ''
			}
			return '0', 'i32'
		}
		a := g.as_i32(a0, t0)
		b := g.as_i32(b0, t1)
		r := g.nt()
		cc := llvm_cmp_v(op)
		if cc.len > 0 {
			g.out('  ' + r + ' = icmp ' + cc + ' i32 ' + a + ', ' + b)
			return r, 'i1'
		}
		bo := llvm_binop_v(op)
		if bo.len > 0 {
			g.out('  ' + r + ' = ' + bo + ' i32 ' + a + ', ' + b)
			return r, 'i32'
		}
		g.err = 'x64: 不支持二元运算符 ' + op + ''
		return '0', 'i32'
	}
	if e.kind == ExprKind.expr_call { return g.call_v(e) }
	g.err = 'x64: 不支持该表达式'
	return '0', 'i32'
}

// ---- cone 0.9.f：Windows x64 SEH（栈式 flat 标记流） ----
fn (mut g LGen) emit_filter_v(name string, hs []LSehHandler) {
	mut codes := []string{}
	mut has_any := false
	for h in hs {
		if h.except_idx >= 0 { codes << g.const_expr(h.except_idx) }
		else { has_any = true }
	}
	g.filters << 'define internal i32 @' + name + '(ptr %ep, ptr %fp) {'
	g.filters << 'entry:'
	g.filters << '  %er = load ptr, ptr %ep'
	g.filters << '  %code = load i32, ptr %er'
	g.filters << '  store i32 %code, ptr @fuck'
	if has_any || codes.len == 0 {
		g.filters << '  ret i32 1'
	} else {
		mut prev := ''
		for i := 0; i < codes.len; i++ {
			g.filters << '  %m' + i.str() + ' = icmp eq i32 %code, ' + codes[i]
			if i == 0 {
				prev = '%m0'
			} else {
				g.filters << '  %o' + i.str() + ' = or i1 ' + prev + ', %m' + i.str()
				prev = '%o' + i.str()
			}
		}
		g.filters << '  %r = zext i1 ' + prev + ' to i32'
		g.filters << '  ret i32 %r'
	}
	g.filters << '}'
	g.filters << ''
}

fn (mut g LGen) sret_call_v(rhs int) bool {
	if rhs < 0 || rhs >= g.prog.exprs.len { return false }
	e := g.prog.exprs[rhs]
	if e.kind != ExprKind.expr_call { return false }
	for p in g.protos {
		if p.cone_name == e.text { return p.sret }
	}
	return false
}

fn (mut g LGen) gen_seh_try(s Stmt, body []Stmt, si int) {
	g.seh_seq = g.seh_seq + 1
	seq := g.seh_seq
	tid := s.try_id
	fnm := g.cur_func
	cs := '%cs' + seq.str()
	cp := '%cp' + seq.str()
	filt := '__cone_seh_filter_' + fnm + '_' + seq.str()
	flag_g := '__cone_seh_flag_' + fnm + '_' + seq.str()
	retval_g := '__cone_seh_ret_' + fnm + '_' + seq.str()
	g.seh_globals << '@' + flag_g + ' = internal global i32 0'
	mut retv := ''
	if g.ret_ty != 'void' {
		g.seh_globals << '@' + retval_g + ' = internal global ' + g.ret_ty + ' ' + llvm_zero_of_v(g.ret_ty)
		retv = retval_g
	}
	// 预扫描本 try 的所有 except 分支（按 try_id / 嵌套深度配对）
	mut hs := []LSehHandler{}
	mut depth := 0
	for j := si + 1; j < body.len; j++ {
		t := body[j]
		if t.kind == StmtKind.st_try && t.try_id != tid {
			depth = depth + 1
		} else if t.kind == StmtKind.st_endtry {
			if depth > 0 { depth = depth - 1 } else { break }
		} else if t.kind == StmtKind.st_except && depth == 0 && t.try_id == tid {
			hs << LSehHandler{except_idx: t.except_idx, lbl: g.nb('except')}
		}
	}
	g.emit_filter_v(filt, hs)
	body_lbl := g.nb('trybody')
	cont := g.nb('trycont')
	disp := g.nb('sehdispatch')
	hand := g.nb('sehhandler')
	ret_lbl := g.nb('sehret')
	normal := g.nb('trynormal')
	mut any_lbl := ''
	for h in hs {
		if h.except_idx < 0 { any_lbl = h.lbl; break }
	}
	mut default_lbl := ''
	if any_lbl.len > 0 {
		default_lbl = any_lbl
	} else {
		default_lbl = g.nb('sehdefault')
	}
	mut loop_after := ''
	mut loop_cond := ''
	if g.fors.len > 0 {
		loop_after = g.fors.last().after
		loop_cond = g.fors.last().cond
	}
	mut parent := 'none'
	if g.funclet.len > 0 { parent = g.funclet }
	fr := LSehFrame{
		try_id: tid, seq: seq, cs: cs, cp: cp, filt: filt,
		flag_g: flag_g, retval_g: retv, cont: cont, disp: disp, hand: hand,
		ret_lbl: ret_lbl, normal: normal, default_lbl: default_lbl,
		handlers: hs, cur_handler: -1, body_done: false, except_open: false,
		parent: parent,
		saved_funclet: g.funclet, saved_cont: g.funclet_cont,
		saved_flag: g.funclet_flag, saved_retval: g.funclet_retval,
		loop_after: loop_after, loop_cond: loop_cond, line: s.line}
	// 进入 try 区域：invoke 给 WinEHPrepare 提供第一条 unwind 边
	g.out('  invoke void @' + llvm_seh_enter + '() to label %' + body_lbl +
		' unwind label %' + disp + g.fbundle_v())
	g.term = true
	g.setblk(body_lbl)
	g.sehs << fr
}

fn (mut g LGen) gen_seh_except(s Stmt) {
	if g.sehs.len == 0 { return }
	mut fr := g.sehs.last()
	if !fr.body_done {
		if !g.term {
			g.out('  invoke void @' + llvm_seh_leave + '() to label %' + fr.cont +
				' unwind label %' + fr.disp + g.fbundle_v())
			g.term = true
		}
		g.setblk(fr.disp)
		g.out('  ' + fr.cs + ' = catchswitch within ' + fr.parent +
			' [label %' + fr.hand + '] unwind to caller')
		g.term = true
		g.setblk(fr.hand)
		g.out('  ' + fr.cp + ' = catchpad within ' + fr.cs + ' [ptr @' + fr.filt + ']')
		code := g.nt()
		g.out('  ' + code + ' = load i32, ptr @fuck')
		mut parts := []string{}
		for h in fr.handlers {
			if h.except_idx >= 0 {
				parts << 'i32 ' + g.const_expr(h.except_idx) + ', label %' + h.lbl
			}
		}
		if parts.len > 0 {
			g.out('  switch i32 ' + code + ', label %' + fr.default_lbl +
				' [ ' + parts.join(' ') + ' ]')
		} else {
			mut dest := fr.cont
			if fr.handlers.len > 0 { dest = fr.handlers[0].lbl }
			g.out('  br label %' + dest)
		}
		g.term = true
		fr.body_done = true
	} else {
		if !g.term {
			g.out('  catchret from ' + fr.cp + ' to label %' + fr.cont)
			g.term = true
		}
	}
	fr.cur_handler = fr.cur_handler + 1
	if fr.cur_handler < fr.handlers.len {
		g.setblk(fr.handlers[fr.cur_handler].lbl)
		g.funclet = fr.cp
		g.funclet_cont = fr.cont
		g.funclet_flag = fr.flag_g
		g.funclet_retval = fr.retval_g
	}
	g.sehs[g.sehs.len - 1] = fr
}

fn (mut g LGen) gen_seh_endtry(s Stmt) {
	if g.sehs.len == 0 { return }
	fr := g.sehs.last()
	if !g.term {
		g.out('  catchret from ' + fr.cp + ' to label %' + fr.cont)
		g.term = true
	}
	mut has_any := false
	for h in fr.handlers {
		if h.except_idx < 0 { has_any = true; break }
	}
	if !has_any && fr.handlers.len > 0 {
		g.setblk(fr.default_lbl)
		g.out('  catchret from ' + fr.cp + ' to label %' + fr.cont)
		g.term = true
	}
	g.funclet = fr.saved_funclet
	g.funclet_cont = fr.saved_cont
	g.funclet_flag = fr.saved_flag
	g.funclet_retval = fr.saved_retval
	g.setblk(fr.cont)
	fv := g.nt()
	g.out('  ' + fv + ' = load i32, ptr @' + fr.flag_g)
	g.out('  store i32 0, ptr @' + fr.flag_g)
	mut cases := []string{}
	cases << 'i32 1, label %' + fr.ret_lbl
	if fr.loop_after.len > 0 {
		cases << 'i32 2, label %' + fr.loop_after
		cases << 'i32 3, label %' + fr.loop_cond
	}
	g.out('  switch i32 ' + fv + ', label %' + fr.normal +
		' [ ' + cases.join(' ') + ' ]')
	g.term = true
	g.setblk(fr.ret_lbl)
	if g.ret_ty == 'void' {
		g.out('  ret void')
	} else {
		rv := g.nt()
		g.out('  ' + rv + ' = load ' + g.ret_ty + ', ptr @' + fr.retval_g)
		g.out('  ret ' + g.ret_ty + ' ' + rv)
	}
	g.term = true
	g.setblk(fr.normal)
	g.term = false
	g.sehs.pop()
}

// ---- cone 0.9.p：asm64{} -> LLVM inline asm / module asm ----
fn (mut g LGen) gen_asm64_v(s Stmt) {
	g.asm64_seq++
	uid := 'f${g.asm64_seq}'
	mut vars := map[string]string{}
	for v in g.vars {
		if v.name.len > 0 { vars[v.name] = v.ptr }
	}
	for v in g.gvars {
		if v.name.len > 0 && !(v.name in vars) { vars[v.name] = v.ptr }
	}
	lines, ops := a64x_template_v(s.asm_text, vars, uid, false, s.line) or {
		g.err = err.msg()
		g.err_line = s.line
		return
	}
	mut cons := []string{}
	for _ in ops { cons << 'r' }
	cons << a64x_clobbers
	mut args := []string{}
	for op in ops { args << 'ptr ' + op }
	g.out('  call void asm sideeffect "' + a64x_asm_string_v(lines) + '", "' +
		cons.join(',') + '"(' + args.join(', ') + ')' + g.fbundle_v())
}

fn (mut g LGen) gen_top_asm64_v() []string {
	mut out := []string{}
	for ab in g.prog.asm64s {
		uid := 't${ab.order}'
		mut vars := map[string]string{}
		for v in g.gvars {
			if v.name.len > 0 { vars[v.name] = v.name }
		}
		lines, _ := a64x_template_v(ab.text, vars, uid, true, ab.line) or {
			g.err = err.msg()
			g.err_line = ab.line
			return out
		}
		mut pref := ['.text', '.globl __cone_a64_top_' + uid,
			'__cone_a64_top_' + uid + ':']
		pref << lines
		out << 'module asm "' + a64x_asm_string_v(pref) + '"'
	}
	return out
}

fn (mut g LGen) gen_body_flat(body []Stmt) {
	for si := 0; si < body.len; si++ {
		s := body[si]
		k := s.kind
		g.cur_line = s.line
		if k == StmtKind.st_asm64 {
			g.gen_asm64_v(s)
		} else if k == StmtKind.st_local {
			for q := 0; q < s.local_names.len; q++ {
				nm := s.local_names[q]
				v := g.find_var(nm)
				has_init := q < s.local_inits.len && s.local_inits[q] >= 0
				if has_init && g.sret_call_v(s.local_inits[q]) {
					g.sret_target = g.slot_ptr0_v(v)
					x, t := g.expr_v(s.local_inits[q])
					g.sret_target = ''
					if t != 'void' { g.store_int_v(v.ptr, v.ty, x, t) }
					continue
				}
				if v.kind == 'scalar' {
					if has_init {
						x, t := g.expr_v(s.local_inits[q])
						g.store_int_v(v.ptr, v.ty, x, t)
					} else {
						g.out('  store ' + v.ty + ' ' + llvm_zero_of_v(v.ty) + ', ptr ' + v.ptr)
					}
				} else {
					g.out('  store ' + v.ty + ' zeroinitializer, ptr ' + v.ptr)
				}
			}
		} else if k == StmtKind.st_assign {
			mut lp := ''
			mut lty := 'i32'
			rhs_sret := g.sret_call_v(s.rhs_idx)
			if s.lhs_idx >= 0 {
				lp, lty = g.lvalue_of_v(s.lhs_idx)
			} else {
				v := g.find_var(s.lhs)
				if v.name.len == 0 {
					g.set_err_v('x64: 标识符 ' + s.lhs + ' 未声明', s.line)
					return
				}
				if v.kind != 'scalar' && !rhs_sret {
					g.set_err_v('x64: 不能对数组 / 结构体变量整体赋值；请用成员或 [] 元素赋值', s.line)
					return
				}
				if rhs_sret { lp = g.slot_ptr0_v(v) } else { lp = v.ptr }
				lty = v.ty
			}
			if rhs_sret { g.sret_target = lp }
			x, t := g.expr_v(s.rhs_idx)
			if rhs_sret { g.sret_target = '' }
			if t != 'void' { g.store_int_v(lp, lty, x, t) }
		} else if k == StmtKind.st_call {
			g.expr_v(s.call_idx)
		} else if k == StmtKind.st_inc || k == StmtKind.st_dec {
			if s.target_idx >= 0 && s.target_idx < g.prog.exprs.len {
				nm := g.prog.exprs[s.target_idx].text
				v := g.find_var(nm)
				if v.name.len == 0 || v.kind != 'scalar' {
					g.set_err_v('x64: ++/-- 的目标 ' + nm + ' 必须是标量', s.line)
					return
				}
				cur0 := g.load_ptr_v(v.ptr, v.ty)
				cur := g.as_i32(cur0, v.ty)
				r := g.nt()
				mut op := 'add'
				if k == StmtKind.st_dec { op = 'sub' }
				g.out('  ' + r + ' = ' + op + ' i32 ' + cur + ', 1')
				g.store_int_v(v.ptr, v.ty, r, 'i32')
			}
		} else if k == StmtKind.st_return {
			if g.funclet.len > 0 {
				// except 处理器是 funclet：不能直接 ret，写标记后 catchret 汇合
				if s.ret_idx >= 0 && g.funclet_retval.len > 0 {
					x0, t := g.expr_v(s.ret_idx)
					if t != 'void' && t != 'ptr' {
						x := g.as_type_v(x0, t, g.ret_ty)
						g.out('  store ' + g.ret_ty + ' ' + x + ', ptr @' + g.funclet_retval)
					}
				}
				g.out('  store i32 1, ptr @' + g.funclet_flag)
				g.out('  catchret from ' + g.funclet + ' to label %' + g.funclet_cont)
				g.term = true
				g.setblk(g.nb('afterret'))
			} else if g.ret_ty == 'void' {
				// 结构体返回：把 return 的结构体内容整块拷进隐藏 sret 指针
				if s.ret_idx >= 0 {
					x0, t := g.expr_v(s.ret_idx)
					if t == 'ptr' && g.sret_ptr.len > 0 {
						agg := llvm_struct_agg_ty_v(g.sret_size)
						tmp := g.nt()
						g.out('  ' + tmp + ' = load ' + agg + ', ptr ' + x0)
						g.out('  store ' + agg + ' ' + tmp + ', ptr ' + g.sret_ptr)
					}
				}
				g.out('  ret void')
				g.term = true
				g.setblk(g.nb('afterret'))
			} else {
				if s.ret_idx >= 0 {
					x0, t := g.expr_v(s.ret_idx)
					x := g.as_type_v(x0, t, g.ret_ty)
					g.out('  ret ' + g.ret_ty + ' ' + x)
				} else {
					g.out('  ret ' + g.ret_ty + ' ' + llvm_zero_of_v(g.ret_ty))
				}
				g.term = true
				g.setblk(g.nb('afterret'))
			}
		} else if k == StmtKind.st_if {
			x0, t := g.expr_v(s.cond_idx)
			x := g.as_i1(x0, t)
			then := g.nb('ifthen')
			nxt := g.nb('ifnext')
			end := g.nb('ifend')
			g.br(x, then, nxt)
			g.setblk(then)
			g.ifs << LIfFrame{end: end, pending: nxt, has_pending: true}
		} else if k == StmtKind.st_elseif {
			if g.ifs.len == 0 { continue }
			end := g.ifs.last().end
			if !g.term { g.jump(end) }
			g.setblk(g.ifs.last().pending)
			x0, t := g.expr_v(s.cond_idx)
			x := g.as_i1(x0, t)
			then := g.nb('ifthen')
			nxt := g.nb('ifnext')
			g.br(x, then, nxt)
			g.setblk(then)
			g.ifs[g.ifs.len - 1].pending = nxt
			g.ifs[g.ifs.len - 1].has_pending = true
		} else if k == StmtKind.st_else {
			if g.ifs.len == 0 { continue }
			end := g.ifs.last().end
			if !g.term { g.jump(end) }
			g.setblk(g.ifs.last().pending)
			g.ifs[g.ifs.len - 1].pending = ''
			g.ifs[g.ifs.len - 1].has_pending = false
		} else if k == StmtKind.st_endif {
			if g.ifs.len == 0 { continue }
			fr := g.ifs.last()
			if !g.term { g.jump(fr.end) }
			if fr.has_pending && fr.pending.len > 0 {
				g.setblk(fr.pending)
				g.jump(fr.end)
			}
			g.setblk(fr.end)
			g.ifs.pop()
		} else if k == StmtKind.st_for {
			cond := g.nb('forcond')
			body2 := g.nb('forbody')
			after := g.nb('forend')
			if !g.term { g.jump(cond) }
			g.setblk(cond)
			if s.is_forever {
				g.jump(body2)
			} else {
				x0, t := g.expr_v(s.cond_idx)
				x := g.as_i1(x0, t)
				g.br(x, body2, after)
			}
			g.setblk(body2)
			g.fors << LForFrame{cond: cond, after: after}
		} else if k == StmtKind.st_endfor {
			if g.fors.len == 0 { continue }
			fr := g.fors.last()
			if !g.term { g.jump(fr.cond) }
			g.setblk(fr.after)
			g.fors.pop()
		} else if k == StmtKind.st_break {
			if g.funclet.len > 0 {
				g.out('  store i32 2, ptr @' + g.funclet_flag)
				g.out('  catchret from ' + g.funclet + ' to label %' + g.funclet_cont)
				g.term = true
				g.setblk(g.nb('afterbrk'))
			} else if g.fors.len > 0 {
				g.jump(g.fors.last().after)
				g.setblk(g.nb('afterbrk'))
			}
		} else if k == StmtKind.st_continue {
			if g.funclet.len > 0 {
				g.out('  store i32 3, ptr @' + g.funclet_flag)
				g.out('  catchret from ' + g.funclet + ' to label %' + g.funclet_cont)
				g.term = true
				g.setblk(g.nb('aftercont'))
			} else if g.fors.len > 0 {
				g.jump(g.fors.last().cond)
				g.setblk(g.nb('aftercont'))
			}
		} else if k == StmtKind.st_match {
			x0, t := g.expr_v(s.cond_idx)
			x := g.as_i32(x0, t)
			g.matches << LMatchFrame{disc: x, end: g.nb('matchend'), next: '', has_next: false}
		} else if k == StmtKind.st_case {
			if g.matches.len == 0 { continue }
			fr := g.matches.last()
			if fr.has_next {
				if !g.term { g.jump(fr.end) }
				g.setblk(fr.next)
			}
			cv0, ct := g.expr_v(s.case_idx)
			cv := g.as_i32(cv0, ct)
			cmpv := g.nt()
			g.out('  ' + cmpv + ' = icmp eq i32 ' + fr.disc + ', ' + cv)
			tb := g.nb('case')
			nb2 := g.nb('casenext')
			g.br(cmpv, tb, nb2)
			g.setblk(tb)
			g.matches[g.matches.len - 1].next = nb2
			g.matches[g.matches.len - 1].has_next = true
		} else if k == StmtKind.st_default {
			if g.matches.len == 0 { continue }
			fr := g.matches.last()
			if !g.term { g.jump(fr.end) }
			if fr.has_next { g.setblk(fr.next) }
			g.matches[g.matches.len - 1].has_next = false
			g.matches[g.matches.len - 1].next = ''
		} else if k == StmtKind.st_endmatch {
			if g.matches.len == 0 { continue }
			fr := g.matches.last()
			if !g.term { g.jump(fr.end) }
			if fr.has_next && fr.next.len > 0 {
				g.setblk(fr.next)
				g.jump(fr.end)
			}
			g.setblk(fr.end)
			g.matches.pop()
		} else if k == StmtKind.st_try {
			g.gen_seh_try(s, body, si)
		} else if k == StmtKind.st_except {
			g.gen_seh_except(s)
		} else if k == StmtKind.st_endtry {
			g.gen_seh_endtry(s)
		}
	}
}


fn (mut g LGen) local_slot_v(s Stmt) LVar {
	t := s.local_type
	arr := s.local_array_len
	ity := llvm_itype_v(t)
	if arr.len > 0 {
		mut n := llvm_int_v(arr).int()
		if n <= 0 { n = 1 }
		return LVar{ty: '[' + n.str() + ' x ' + ity + ']', kind: 'array', elem_ty: ity, n: n}
	}
	if t in g.st.struct_size {
		size := g.st.struct_size[t]
		return LVar{ty: '[' + size.str() + ' x i8]', kind: 'struct', sname: t, n: size}
	}
	return LVar{ty: ity, kind: 'scalar'}
}


fn (mut g LGen) gen_func_v(f FuncDef) {
	lo := g.lines.len
	g.vars = []LVar{}
	g.cur = ''
	g.term = true
	g.ifs = []LIfFrame{}
	g.fors = []LForFrame{}
	g.matches = []LMatchFrame{}
	g.sehs = []LSehFrame{}
	g.funclet = ''
	g.funclet_cont = ''
	g.funclet_flag = ''
	g.funclet_retval = ''
	g.cur_func = f.name
	mut pi := LProto{}
	for p in g.protos {
		if p.cone_name == f.name { pi = p; break }
	}
	sret := pi.sret
	g.sret_size = pi.sret_size
	g.sret_ptr = ''
	g.ret_ty = pi.ret
	mut has_seh := false
	for s in f.body {
		if s.kind == StmtKind.st_try { has_seh = true; break }
	}
	mut dllexp := ''
	if f.name in g.exports { dllexp = 'dllexport ' }
	mut pdecl := []string{}
	if sret { pdecl << 'ptr %__cone_sret' }
	for p in f.params {
		ity, _ := llvm_param_ir_ty_v(g.st, p.typ_name)
		pdecl << ity + ' %' + p.name
	}
	mut pers := ''
	if has_seh { pers = ' personality ptr @' + llvm_seh_personality }
	g.out('define ' + dllexp + g.ret_ty + ' @' + f.name + '(' + pdecl.join(', ') + ')' + pers + ' {')
	g.setblk('entry')
	mut seen := []string{}
	for s in f.body {
		if s.kind != StmtKind.st_local { continue }
		sl := g.local_slot_v(s)
		for nm in s.local_names {
			if !(nm in seen) {
				ptr := '%p.' + nm
				g.out('  ' + ptr + ' = alloca ' + sl.ty)
				g.vars << LVar{name: nm, ptr: ptr, ty: sl.ty, kind: sl.kind,
					elem_ty: sl.elem_ty, n: sl.n, sname: sl.sname}
				seen << nm
			}
		}
	}
	if sret { g.sret_ptr = '%__cone_sret' }
	for p in f.params {
		ct := p.typ_name
		ity, mode := llvm_param_ir_ty_v(g.st, ct)
		ptr := '%p.' + p.name
		if llvm_is_struct_v(g.st, ct) {
			size := llvm_struct_size_v(g.st, ct)
			agg := llvm_struct_agg_ty_v(size)
			if mode == 'value' {
				g.out('  ' + ptr + ' = alloca ' + agg)
				g.out('  store ' + ity + ' %' + p.name + ', ptr ' + ptr)
				g.vars << LVar{name: p.name, ptr: ptr, ty: agg, kind: 'struct',
					sname: ct, n: size}
			} else {
				g.vars << LVar{name: p.name, ptr: '%' + p.name, ty: agg,
					kind: 'structref', sname: ct, n: size}
			}
		} else {
			g.out('  ' + ptr + ' = alloca ' + ity)
			g.out('  store ' + ity + ' %' + p.name + ', ptr ' + ptr)
			g.vars << LVar{name: p.name, ptr: ptr, ty: ity, kind: 'scalar'}
		}
	}
	g.gen_body_flat(f.body)
	if !g.term {
		if g.ret_ty == 'void' {
			g.out('  ret void')
		} else {
			g.out('  ret ' + g.ret_ty + ' ' + llvm_zero_of_v(g.ret_ty))
		}
	}
	if g.auto_exit && f.name == g.entry_name { g.rewrite_entry_v(lo) }
	g.out('}')
	g.out('')
}

fn (mut g LGen) global_def_v(v VarDef) (string, LVar) {
	t := v.typ_name
	arr := v.array_len
	ity := llvm_itype_v(t)
	mut sl := LVar{name: v.name, ptr: '@' + v.name}
	if arr.len > 0 {
		mut n := llvm_int_v(arr).int()
		if n <= 0 { n = 1 }
		ty := '[' + n.str() + ' x ' + ity + ']'
		sl.ty = ty
		sl.kind = 'array'
		sl.elem_ty = ity
		sl.n = n
		return '@' + v.name + ' = global ' + ty + ' zeroinitializer', sl
	}
	if t in g.st.struct_size {
		size := g.st.struct_size[t]
		ty := '[' + size.str() + ' x i8]'
		sl.ty = ty
		sl.kind = 'struct'
		sl.sname = t
		sl.n = size
		mut init := 'zeroinitializer'
		if v.has_init_list {
			mut data := []u8{}
			for z := 0; z < size; z++ { data << u8(0) }
			mut members := []string{}
			if t in g.st.struct_members { members = g.st.struct_members[t] }
			for q := 0; q < members.len && q < v.init_items.len; q++ {
				ii := v.init_items[q]
				if ii < 0 { continue }
				key := t + '.' + members[q]
				if !(key in g.st.struct_offsets) { continue }
				off := g.st.struct_offsets[key]
				mut mt := 'int'
				if key in g.st.struct_mtype { mt = g.st.struct_mtype[key] }
				mty := llvm_itype_v(mt)
				if llvm_is_float_ty_v(mty) {
					fb := llvm_float_bytes_v(g.const_expr(ii), mty)
					for b := 0; b < fb.len; b++ {
						if off + b < size { data[off + b] = fb[b] }
					}
					continue
				}
				mut w := 4
				if mty == 'i8' { w = 1 } else if mty == 'i16' { w = 2 } else if mty == 'i64' { w = 8 }
				val := u32(g.const_expr(ii).int())
				for b := 0; b < w; b++ {
					if off + b < size {
						data[off + b] = u8(int(val >> u32(8 * b)) & 255)
					}
				}
			}
			init = 'c"' + llvm_hex_bytes_v(data) + '"'
		}
		return '@' + v.name + ' = global ' + ty + ' ' + init, sl
	}
	mut init := llvm_zero_of_v(ity)
	if v.init_idx >= 0 {
		raw := g.const_expr(v.init_idx)
		if llvm_is_float_ty_v(ity) { init = llvm_float_const_v(raw, ity) } else { init = raw }
	}
	sl.ty = ity
	sl.kind = 'scalar'
	return '@' + v.name + ' = global ' + ity + ' ' + init, sl
}

fn (mut g LGen) data_def_v(d DataDef) (string, LVar) {
	mut data := []u8{}
	for ii in d.items {
		chunk := g.data_item_bytes_v(ii)
		for b in chunk { data << b }
	}
	if data.len == 0 { data << u8(0) }
	n := data.len
	sl := LVar{name: d.name, ptr: '@' + d.name, ty: '[' + n.str() + ' x i8]', kind: 'data', n: n}
	return '@' + d.name + ' = private unnamed_addr constant [' + n.str() + ' x i8] c"' + llvm_hex_bytes_v(data) + '"', sl
}

// ---- x64 约束检查 ----

// x64 约束：诊断只写「问题 + 原因 + 做法」，不带版本 / 手册章节 / 历史口径。
fn llvm_check_v(prog Program, st SymTab) (string, int) {
	win_ban := 'x64: 已禁用 win 关键字（win.* / win{}）：编译器无法推断外部标识符；请写 func 声明或 import x64crt'
	mut defined := []string{}
	for f in prog.funcs { defined << f.name }
	// --- 顶层结构 ---
	if prog.win_blocks.len > 0 {
		return 'x64: 已禁用 win{} 块：' + win_ban, prog.win_blocks[0].line
	}
	if prog.segs.len > 0 {
		return 'x64: 不支持 seg 自定义段：段语法只在默认 x86 后端有效', prog.segs[0].line
	}
	if prog.macros.len > 0 {
		return 'x64: 不支持 defined 宏：宏语法只在默认 x86 后端有效', prog.macros[0].line
	}
	if prog.asms.len > 0 {
		return 'x64: 不支持 asm{}（32 位汇编块）：请用 asm64{} 或走默认 x86 后端', prog.asms[0].line
	}
	for im in prog.imports {
		if im.kind == ImportKind.ik_dll {
			return 'x64: 不支持 import ' + im.module_name + '.dll：请写 include ' + im.module_name + '.lib 或 func 声明', im.line
		}
	}
	for v in prog.vars {
		if v.typ_name.starts_with('win.') {
			return 'x64: 已禁用 win 外部结构体变量 ' + v.name + '：请自己用 struct 定义布局', v.line
		}
	}
	for sd in prog.structs {
		for m in sd.members {
			if m.typ_name.starts_with('win.') {
				return 'x64: 已禁用 win 外部结构体类型 ' + m.typ_name + '：请自己用 struct 定义布局', sd.line
			}
		}
	}
	// --- 函数声明 / 定义 ---
	for pd in prog.protos {
		if pd.is_external {
			return 'x64: 不支持 efunc：请改用 func 声明', pd.line
		}
		if pd.is_export && !(pd.name in defined) {
			return 'export 只能写在 def 定义上：func 声明 ' + pd.name + ' 没有对应的 def', pd.line
		}
		if !(pd.name in defined) && pd.ret_type.len == 0 {
			return '外部函数 func ' + pd.name + ' 未写返回类型：请在声明行末补 int / long / f64 等', pd.line
		}
	}
	for f in prog.funcs {
		if f.in_seg.len > 0 {
			return 'x64: 不支持 seg 段内函数', f.line
		}
		for s2 in f.body {
			if s2.kind == StmtKind.st_asm {
				return 'x64: 不支持 asm{}（32 位汇编块）：请用 asm64{} 或走默认 x86 后端', s2.line
			}
		}
	}
	// --- 表达式 ---
	for e in prog.exprs {
		if e.text.starts_with('win.') {
			return e.text + ' —— ' + win_ban, e.line
		}
		if e.is_reg {
			return 'x64 不支持显式寄存器 ' + e.text + '：32 位寄存器只在默认 x86 后端有效', e.line
		}
		if e.is_struct_lit {
			return 'x64 不支持结构体常量 ' + e.lit_type + '{...}：请用结构体变量初值列表', e.line
		}
		if e.kind == ExprKind.expr_sizeof {
			return 'x64 不支持未折叠的 sizeof：请用 sizeof(类型名/变量名)', e.line
		}
		if e.kind == ExprKind.expr_call && e.text.starts_with('os.') {
			return 'x64: 不支持 os.* 外部调用：os.lib 是 32 位库；请用 func 声明或 import x64crt', e.line
		}
	}
	return '', 0
}


fn gen_llvm_v(prog Program, st SymTab, arch string, opt string) (string, string, string, int) {
	chk, cline := llvm_check_v(prog, st)
	if chk.len > 0 { return '', chk, '', cline }
	mut g := LGen{prog: prog, st: st, arch: 'x64', opt: opt, term: true, ret_ty: 'i32', hint_skip: -1}
	for f in prog.funcs { g.func_names << f.name }
	for f in prog.funcs {
		for s2 in f.body {
			if s2.kind == StmtKind.st_try { g.seh_used = true; break }
		}
	}
	g.init_protos_v()
	// cone 0.9.f：入口函数自动以 ExitProcess 结束（除非用户已显式调用）
	g.entry_name = prog.entry
	g.auto_exit = x64_auto_exit_needed_v(prog)
	if g.auto_exit { g.setup_exitprocess_v() }
	mut body := []string{}
	if g.seh_used {
		g.gvars << LVar{name: 'fuck', ptr: '@fuck', ty: 'i32', kind: 'scalar'}
	}
	for v in prog.vars {
		line, sl := g.global_def_v(v)
		g.gvars << sl
		body << line
	}
	if g.err.len > 0 { return '', g.err, '', g.err_line }
	for d in prog.data {
		line, sl := g.data_def_v(d)
		g.gvars << sl
		body << line
	}
	if g.err.len > 0 { return '', g.err, '', g.err_line }
	for f in prog.funcs { g.gen_func_v(f) }
	if g.err.len > 0 { return '', g.err, '', g.err_line }

	// cone 0.9.f：Windows x64 SEH 需要的模块级符号
	if g.seh_used {
		body << '@fuck = linkonce_odr global i32 0'
		body << '@' + llvm_seh_marker + ' = internal global i32 0'
		body << 'declare i32 @' + llvm_seh_personality + '(...)'
		for ln in g.seh_globals { body << ln }
	}
	// LLVM X86 COFF 后端遇到浮点会发射未定义 _fltused；本模块定义它，
	// 链接不再依赖 libcmt / ucrt 提供该标记。
	mut uses_float := false
	mut all_lines := []string{}
	for ln in body { all_lines << ln }
	for ln in g.lines { all_lines << ln }
	for ln in g.filters { all_lines << ln }
	for d in g.decls { all_lines << d.sig }
	fp_keys := ['float ', 'double ', 'fadd ', 'fsub ', 'fmul ', 'fdiv ', 'fcmp ',
		'fpext ', 'fptrunc ', 'sitofp ', 'fptosi ', 'fneg ']
	for ln in all_lines {
		for kw in fp_keys {
			if ln.contains(kw) { uses_float = true; break }
		}
		if uses_float { break }
	}
	if uses_float { body << '@' + llvm_fltused + ' = linkonce_odr global i32 0' }

	mut head := []string{}
	head << '; cone 0.9.p - generated LLVM IR (-llvm:x64)'
	head << '; target: ' + llvm_triple_v(arch) + ' / COFF -> lld-link -> .exe'
	mut seen_notices := []string{}
	for nt in g.notices {
		if !(nt in seen_notices) {
			head << '; notice: ' + nt
			seen_notices << nt
		}
	}
	head << 'target triple = "' + llvm_triple_v(arch) + '"'
	head << 'target datalayout = "' + llvm_dl_v(arch) + '"'
	head << ''
	// cone 0.9.p：顶层 asm64{} 用 module asm 原样透传（不在函数指令流里）
	top_asm := g.gen_top_asm64_v()
	if g.err.len > 0 { return '', g.err, '', g.err_line }
	if top_asm.len > 0 {
		for ln2 in top_asm { head << ln2 }
		head << ''
	}
	if body.len > 0 {
		for ln in body { head << ln }
		head << ''
	}
	for st2 in g.strs {
		head << '@' + st2.name + ' = private unnamed_addr constant [' + st2.n.str() + ' x i8] c"' + st2.esc + '"'
	}
	if g.strs.len > 0 { head << '' }
	for d in g.decls { head << d.sig }
	if g.decls.len > 0 { head << '' }
	for ln in g.lines { head << ln }

	mut extra := []string{}
	if g.seh_used {
		extra << 'define internal void @' + llvm_seh_enter + '() noinline {'
		extra << 'entry:'
		extra << '  store volatile i32 1, ptr @' + llvm_seh_marker
		extra << '  ret void'
		extra << '}'
		extra << ''
		extra << 'define internal void @' + llvm_seh_leave + '() noinline {'
		extra << 'entry:'
		extra << '  store volatile i32 2, ptr @' + llvm_seh_marker
		extra << '  ret void'
		extra << '}'
		extra << ''
	}
	for ln in g.filters { extra << ln }
	for ln in extra { head << ln }
	return llvm_quote_special_names_v(head.join('
') + '
'), '', '', 0
}
