module main

import os

// ---------- 数值字面量（沿用 cone 0.1 已实机验证的手写解析） ----------

fn parse_int_lit(text string) !i64 {
	mut s := text
	mut neg := false
	if s.len > 0 && (s[0] == 45 || s[0] == 43) { // - / +
		neg = s[0] == 45
		s = s[1..]
	}
	if s.len == 0 {
		return error('空数值')
	}
	mut base := 10
	mut digits := s
	if s[s.len - 1] == 104 || s[s.len - 1] == 72 { // h / H
		base = 16
		digits = s[..s.len - 1]
	}
	if digits.len == 0 {
		return error('数值缺少数字部分')
	}
	mut v := i64(0)
	guard := i64(1000000000000000000)
	mut i := 0
	for i < digits.len {
		c := digits[i]
		mut d := 0
		if c >= 48 && c <= 57 {
			d = int(c) - 48
		} else if c >= 97 && c <= 102 {
			if base != 16 {
				return error('十进制数值里出现字母 ${text}')
			}
			d = int(c) - 97 + 10
		} else if c >= 65 && c <= 70 {
			if base != 16 {
				return error('十进制数值里出现字母 ${text}')
			}
			d = int(c) - 65 + 10
		} else if c == 46 {
			return error('整数字面量里出现小数点：${text}')
		} else {
			return error('非法数值字面量 ${text}')
		}
		if d >= base {
			return error('数值 ${text} 含非法数字')
		}
		if v > (guard - i64(d)) / i64(base) {
			return error('数值 ${text} 超出 64 位可解析范围')
		}
		v = v * i64(base) + i64(d)
		i = i + 1
	}
	if neg {
		v = -v
	}
	return v
}

fn is_float_lit(text string) bool {
	mut s := text
	if s.len > 0 && (s[0] == 45 || s[0] == 43) {
		s = s[1..]
	}
	mut dot := -1
	mut i := 0
	for i < s.len {
		if s[i] == 46 {
			if dot >= 0 {
				return false
			}
			dot = i
		} else if !(s[i] >= 48 && s[i] <= 57) {
			return false
		}
		i = i + 1
	}
	return dot > 0 && dot < s.len - 1
}

// fits_i64: "不区分正负，只检查字节数" —— 正数按 2^(8N)-1，负数按 -2^(8N-1)。
fn fits_i64(v i64, nbytes int) bool {
	if nbytes >= 8 {
		return true
	}
	if v >= 0 {
		mut max := i64(1)
		mut k := 0
		for k < nbytes * 8 {
			max = max * 2
			k = k + 1
		}
		return v < max
	}
	mut min := i64(1)
	mut k := 0
	for k < nbytes * 8 - 1 {
		min = min * 2
		k = k + 1
	}
	return v >= -min
}

// ---------- 编译期常量折叠 ----------

// bit_shl / bit_shr: cone 0.6 fix1 的编译期移位。用循环实现，避免依赖 V 0.5.1
// 对 i64 移位运算符的具体类型要求；bit_shr 按算术右移（负数向下取整）实现。
fn bit_shl(v i64, n i64) i64 {
	mut r := v
	mut i := i64(0)
	for i < n && i < 64 {
		r = r * 2
		i = i + 1
	}
	return r
}

fn bit_shr(v i64, n i64) i64 {
	mut r := v
	mut i := i64(0)
	for i < n && i < 64 {
		if r < 0 {
			r = (r - 1) / 2
		} else {
			r = r / 2
		}
		i = i + 1
	}
	return r
}

fn fold_int(prog Program, idx int) !i64 {
	if idx < 0 || idx >= prog.exprs.len {
		return error('表达式索引越界')
	}
	e := prog.exprs[idx]
	if e.is_float_hint {
		return error('float(...) 不是编译期整数常量')
	}
	if e.kind == ExprKind.expr_num {
		return parse_int_lit(e.text)
	}
	if e.kind == ExprKind.expr_neg {
		v := fold_int(prog, e.a) or { return error(err.msg()) }
		if e.text == '~' {
			return -v - 1 // 二进制补码：~v == -v-1
		}
		return -v
	}
	if e.kind == ExprKind.expr_bin {
		l := fold_int(prog, e.a) or { return error(err.msg()) }
		r := fold_int(prog, e.b) or { return error(err.msg()) }
		if e.text == '+' {
			return l + r
		}
		if e.text == '-' {
			return l - r
		}
		if e.text == '*' {
			return l * r
		}
		if e.text == '/' {
			if r == 0 {
				return error('编译期计算出现除零')
			}
			return l / r
		}
		// cone 0.9.1：编译期取模，与截断除法一致：l - trunc(l/r)*r
		if e.text == '%' {
			if r == 0 {
				return error('编译期计算出现取模除零')
			}
			return l - (l / r) * r
		}
		// cone 0.6 fix1：编译期位运算
		if e.text == '|' { return l | r }
		if e.text == '&' { return l & r }
		if e.text == '^' { return l ^ r }
		if e.text == '<<' { return bit_shl(l, r) }
		if e.text == '>>' { return bit_shr(l, r) }
		return error('未知运算符 ${e.text}')
	}
	return error('不是编译期整数常量表达式')
}

struct FoldRes {
	ok    bool
	value i64
}

fn try_fold(prog Program, idx int) FoldRes {
	v := fold_int(prog, idx) or { return FoldRes{ok: false, value: 0} }
	return FoldRes{ok: true, value: v}
}

// render_raw_e: cone 0.6 —— 只用节点池（parser 阶段还没有完整 Program）。
// render_raw / struct_lit_key 共用它，保证源码还原口径一致。
fn render_raw_e(exprs []Expr, idx int) string {
	if idx < 0 || idx >= exprs.len {
		return ''
	}
	e := exprs[idx]
	if e.kind == ExprKind.expr_member {
		return e.text
	}
	if e.kind == ExprKind.expr_num {
		return e.text
	}
	if e.kind == ExprKind.expr_str {
		if is_wide_lit_v(e.text) { return wide_lit_masm_v(e.text) }
		return e.text
	}
	if e.kind == ExprKind.expr_ident {
		return e.text
	}
	if e.kind == ExprKind.expr_neg {
		if e.text == '~' { return 'not (' + render_raw_e(exprs, e.a) + ')' }
		return '-' + render_raw_e(exprs, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		a := render_raw_e(exprs, e.a)
		b := render_raw_e(exprs, e.b)
		op := masm_bin_op(e.text)
		if is_masm_word_op(op) { return '(' + a + ' ' + op + ' ' + b + ')' }
		return a + op + b
	}
	if e.kind == ExprKind.expr_addr {
		return 'offset ' + render_raw_e(exprs, e.a)
	}
	if e.kind == ExprKind.expr_deref {
		mut s := '['
		if e.ptr_size.len > 0 {
			s = s + e.ptr_size + ' '
		}
		return s + render_raw_e(exprs, e.a) + ']'
	}
	return ''
}

fn render_raw(prog Program, idx int) string {
	return render_raw_e(prog.exprs, idx)
}

// struct_lit_key: cone 0.6 结构体常量的去重键（参考 __cone_str_N 的设计）。
// 键 = 类型名 + '<' + 逐项源码还原文本 + '>'；相同类型与相同初值共用一个隐名标签。
fn struct_lit_key(type_name string, items []int, exprs []Expr) string {
	mut parts := []string{}
	for it in items {
		if it < 0 {
			parts << '?'
		} else {
			parts << render_raw_e(exprs, it)
		}
	}
	return type_name + '<' + parts.join(',') + '>'
}

fn render_init(prog Program, idx int) string {
	if idx >= 0 && idx < prog.exprs.len {
		e := prog.exprs[idx]
		if e.kind == ExprKind.expr_num {
			return e.text
		}
		if e.kind == ExprKind.expr_str {
			return e.text
		}
	}
	v := fold_int(prog, idx) or { return render_raw(prog, idx) }
	return '${v}'
}

// ---------- equ 与 cone 侧别名 ----------

// render_equ_expr: equ 裸表达式项按源码原样拼接交给 MASM32（不加括号、不套尖括号）。
fn render_equ_expr(prog Program, idx int) string {
	if idx < 0 || idx >= prog.exprs.len {
		return ''
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_num || e.kind == ExprKind.expr_str || e.kind == ExprKind.expr_ident {
		return e.text
	}
	if e.kind == ExprKind.expr_neg {
		if e.text == '~' { return 'not (' + render_equ_expr(prog, e.a) + ')' }
		return '-' + render_equ_expr(prog, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		a := render_equ_expr(prog, e.a)
		b := render_equ_expr(prog, e.b)
		op := masm_bin_op(e.text)
		if is_masm_word_op(op) { return '(' + a + ' ' + op + ' ' + b + ')' }
		return a + op + b
	}
	return render_raw(prog, idx)
}

// strip_win_tokens: 去掉 equ 文本里所有 win.xxx 的 `win.` 前缀。
// 在 <> 内只有 win.xxx 特殊：cone 侧写 print equ <win.crt_printf>，
// MASM 侧就得到 print equ <crt_printf>；其余字符（逗号/引号/四则/空格）原样保留。
fn strip_win_tokens(text string) string {
	mut out := ''
	mut i := 0
	for i < text.len {
		if i + 4 <= text.len && eq_ci(text[i..i + 4], 'win.') {
			prev_ok := i == 0 || !is_ident_cont(text[i - 1])
			next_ok := i + 4 < text.len && is_ident_start(text[i + 4])
			if prev_ok && next_ok {
				i = i + 4
				continue
			}
		}
		out = out + text[i..i + 1]
		i = i + 1
	}
	return out
}

// equ_masm_text: 生成 `NAME equ <RHS>` 里的 RHS（不含尖括号，尖括号由 codegen 决定）。
fn equ_masm_text(prog Program, eq EquDecl) string {
	if eq.is_raw {
		return strip_win_tokens(eq.raw_text)
	}
	mut parts := []string{}
	for item_idx in eq.items {
		parts << render_equ_expr(prog, item_idx)
	}
	return parts.join(',')
}

fn is_plain_ident_text(s string) bool {
	if s.len == 0 {
		return false
	}
	if !is_ident_start(s[0]) {
		return false
	}
	mut i := 1
	for i < s.len {
		if !is_ident_cont(s[i]) {
			return false
		}
		i = i + 1
	}
	return true
}

// equ_alias_target: equ 的 RHS 是单个标识符时，认为它是 cone 侧的符号别名。
// 返回目标名（已去掉 win. 前缀）；不是别名则返回空串。
fn equ_alias_target(prog Program, eq EquDecl) string {
	t := equ_masm_text(prog, eq)
	if is_plain_ident_text(t) {
		return t
	}
	return ''
}

// expr_has_float_lit: 表达式里是否出现浮点字面量（MASM 指令立即数不允许 REAL）。
fn expr_has_float_lit(prog Program, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		return is_float_lit(e.text)
	}
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr || e.kind == ExprKind.expr_deref {
		return expr_has_float_lit(prog, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		return expr_has_float_lit(prog, e.a) || expr_has_float_lit(prog, e.b)
	}
	if e.kind == ExprKind.expr_call {
		for a in e.args {
			if expr_has_float_lit(prog, a) {
				return true
			}
		}
	}
	return false
}

// ---------- 符号表与名称修饰 ----------

struct NameInfo {
	masm     string // 写进 MASM 的名字
	is_stack bool   // 局部变量 / 形参（栈上变量），决定 addr 用 lea 还是 offset
}

struct SymTab {
mut:
	globals      map[string]bool
	global_kind  map[string]string // data / var / const / func / proto / typedef / equ
	global_type  map[string]string // 变量 -> cone 类型名（已解 typedef）
	local_type   map[string]string // key = 函数名::cone名
	declared     map[string]bool
	defined      map[string]bool
	imports      map[string]bool
	typedefs     map[string]bool
	typedef_base map[string]string
	type_masm    map[string]string
	type_dir     map[string]string
	type_bytes   map[string]int
	name_maps    map[string]NameInfo
	func_convs   map[string]CallConv
	equ_aliases  map[string]string // equ 别名名 -> 去掉 win. 后的目标符号名
	equ_values   map[string]string // cone 0.7：数值 equ 的立即数文本（asm %NAME 展开用）
	decl_line    map[string]int    // 名字首次变得可调用（PROTO / def / equ 别名）的源码行（仅用于报错展示）
	decl_pos     map[string]int    // cone 0.6 fix2：声明起始 token 在最终展开流里的位置（顺序检查用）
	win_bare     map[string]bool   // cone 0.6 fix2：win{...} 批量登记的裸 MASM 侧符号
	macros       map[string]bool   // cone 0.83：defined 宏函数名（无 exitm）
	asm64_cache  map[string][]string // cone 0.9preview：asm64{} 预编译出的 MASM db 行（key -> lines）
	proto_sig    map[string]string // func 声明的形参类型序列（解 typedef 后）
	def_sig      map[string]string // def 定义的形参类型序列
	proto_conv   map[string]CallConv
	// cone 0.4：结构体类型表
	struct_names   map[string]bool
	struct_members map[string][]string // 结构体名 -> 成员名顺序
	struct_mtype   map[string]string  // "结构体.成员" -> cone 类型名
	struct_marray  map[string]string  // "结构体.成员" -> 数组长度（空 = 标量）
	struct_size    map[string]int     // 结构体名 -> 总字节数
	struct_extern  map[string]bool    // cone 0.4 fix：win.XXX 外部 MASM 结构体类型
	// cone 0.9prelease：结构体对齐 / 成员偏移 / padding / 数据字节数
	struct_align     map[string]bool
	struct_align_max map[string]int
	struct_offsets   map[string]int   // "Type.member[.sub]" -> 字节偏移
	struct_pads      map[string][]PadInfo
	data_bytes       map[string]int   // 数据定义（db 字节数组）-> 总字节数
	// cone 0.9.1：函数返回类型表（可选，指示调用/返回值接收的汇编行为）
	func_ret_type      map[string]string
	func_ret_size      map[string]int
	func_ret_is_struct map[string]bool
	x64_mode bool // cone 0.9.p：collect_diagnostics 里是否做 x64 调用检查
}

// cone 0.3：func 声明 + def 定义可以成对出现（对应 MASM32 的 PROTO + proc）。
// 只要形参类型序列与调用约定一致就不是重定义；cc_default 与 cc_stdcall 视为兼容
// （PROTO 不写调用约定时沿用 .model flat, stdcall）。
// cone 0.9.1：返回类型 -> (字节数, 是否 cone 结构体)。空/未知 -> (0, false) 不校验。
fn ret_size_of(st SymTab, rt string) (int, bool) {
	if rt.len == 0 { return 0, false }
	b := resolve_base_type(st, rt)
	if b in st.struct_size && st.struct_size[b] > 0 {
		return st.struct_size[b], true
	}
	n := st.type_bytes[b]
	return n, false
}

fn reg_ret(mut st SymTab, n string, rt string, ln int) ! {
	if rt.len == 0 { return }
	if n in st.func_ret_type && st.func_ret_type[n] != rt {
		return error('第 ${ln} 行: 函数 ${n} 的返回类型 ${rt} 与之前的声明 ${st.func_ret_type[n]} 不一致')
	}
	st.func_ret_type[n] = rt
	nsz, nis := ret_size_of(st, rt)
	st.func_ret_size[n] = nsz
	st.func_ret_is_struct[n] = nis
}

fn conv_compatible(a CallConv, b CallConv) bool {
	if a == b {
		return true
	}
	if a == CallConv.cc_default && b == CallConv.cc_stdcall {
		return true
	}
	if a == CallConv.cc_stdcall && b == CallConv.cc_default {
		return true
	}
	return false
}

fn sig_of(st SymTab, params []Param) string {
	mut parts := []string{}
	for pm in params {
		if pm.typ_name == 'vararg' { continue }
		parts << resolve_base_type(st, pm.typ_name)
	}
	return parts.join(',')
}

// ---------- cone 0.4 fix2：asm{...} 的 %标识符 ----------
// asm_percent_names: 收集正文里所有 %标识符；%% 是转义的普通百分号，不算引用。
// codegen 与 analyzer 共用同一套切分规则，保证校验与替换一致。
fn asm_percent_names(text string) []string {
	mut out := []string{}
	mut i := 0
	for i < text.len {
		if text[i] != 37 { // %
			i = i + 1
			continue
		}
		if i + 1 < text.len && text[i + 1] == 37 {
			i = i + 2
			continue
		}
		if i + 1 < text.len && is_ident_start(text[i + 1]) {
			mut j := i + 1
			for j < text.len && is_ident_cont(text[j]) {
				j = j + 1
			}
			out << text[i + 1..j]
			i = j
			continue
		}
		i = i + 1
	}
	return out
}

// check_asm_text: % 后面必须是 cone 已定义的标识符（或寄存器）。
// MASM 侧本来就存在的符号（win.MB_OK 之类）直接写名字即可，不需要 %。
fn check_asm_text(st SymTab, fname string, text string, line int) ! {
	for nm in asm_percent_names(text) {
		if is_reg_name(nm) {
			continue
		}
		mut ok := false
		if nm in st.globals {
			ok = true
		}
		if name_key(fname, nm) in st.name_maps {
			ok = true
		}
		if nm in st.declared {
			ok = true
		}
		if nm in st.equ_aliases {
			ok = true
		}
		// cone 0.9prelease：%sizeof(...) / %Type.member（cone struct 偏移立即数）
		if nm == 'sizeof' || (nm in st.struct_size) || (nm in st.equ_values) {
			ok = true
		}
		if !ok {
			return error('第 ${line} 行: asm 正文里的 %${nm} 不是 cone 已定义的标识符（也不是寄存器）；% 只用于引用 cone 符号以套用名称修饰，MASM32 侧已存在的符号请直接写名字、不要加 %')
		}
	}
}

// ---------- cone 0.5：match 链校验 ----------
// check_case_value: case 值必须是编译期整数常量，或 cone 已定义的符号
// （equ 常量 / win.宏 / 数据标签；MASM 的 cmp eax,NAME 对它们是合法的右操作数）。
// cone 0.6 fix1：case 值不再限定为「编译期常量或裸标识符」，任意表达式都可以。
// 比较 / 逻辑表达式也按条件表达式校验（它们求值为 0/1 后再和判别值比较）。
fn check_case_value(prog Program, st SymTab, fname string, idx int, line int) ! {
	check_expr_cond(prog, st, idx, fname) or { return error(err.msg()) }
	e := prog.exprs[idx]
	if e.is_struct_lit {
		return error('第 ${line} 行: match 的 case 值不能是结构体常量 ${e.lit_type}{...}')
	}
	return
}

// check_match_flow: 摊平后的标记流复核（parser 已保证基本形状，这里防止手写 AST 绕过）。
fn check_match_flow(prog Program, st SymTab, f FuncDef) ! {
	mut md_default := []bool{}
	mut md_branch := []int{}
	for s in f.body {
		k := s.kind
		if k == StmtKind.st_match {
			check_expr(prog, st, s.cond_idx, f.name) or { return error(err.msg()) }
			md_default << false
			md_branch << 0
			continue
		}
		if k == StmtKind.st_endmatch {
			if md_default.len == 0 {
				return error('第 ${s.line} 行: 多余的 endmatch（没有对应的 match）')
			}
			li := md_branch.len - 1
			if md_branch[li] == 0 {
				return error('第 ${s.line} 行: match 至少要有一个 case 或 default 分支')
			}
			_ = md_default.pop()
			_ = md_branch.pop()
			continue
		}
		if k == StmtKind.st_case || k == StmtKind.st_default {
			if md_default.len == 0 {
				return error('第 ${s.line} 行: case / default 只能出现在 match 内部')
			}
			li := md_default.len - 1
			if k == StmtKind.st_case {
				if md_default[li] {
					return error('第 ${s.line} 行: default 必须是 match 的最后一个分支，后面不能再写 case')
				}
				check_case_value(prog, st, f.name, s.case_idx, s.line) or { return error(err.msg()) }
			} else {
				if md_default[li] {
					return error('第 ${s.line} 行: match 里只能有一个 default 分支')
				}
				md_default[li] = true
			}
			md_branch[li] = md_branch[li] + 1
		}
	}
	if md_default.len > 0 {
		return error('第 ${f.line} 行: 函数 ${f.name} 里有未闭合的 match（缺少右花括号 }）')
	}
}

// ---------- cone 0.4 fix：win.XXX 外部 MASM 结构体类型 ----------
// cone 侧不定义 STRUCT、不校验成员名，输出时去掉 win. 前缀（win.RECT -> RECT）。
fn is_win_type(t string) bool {
	return t.len >= 4 && t[0..4] == 'win.'
}

fn win_masm_name(t string) string {
	if is_win_type(t) {
		return t[4..t.len]
	}
	return t
}

// ---------- cone 0.4：结构体类型辅助 ----------

// struct_member_type: 沿 "a.b.c" 成员链逐级查表，返回最后一级成员的 cone 类型名。
// 手写按 '.' 切分，不用 split()，保持与 V 0.5.1 实机验证过的写法一致。
fn struct_member_type(st SymTab, sname string, path string) !string {
	mut parts := []string{}
	mut start := 0
	mut i := 0
	for i < path.len {
		if path[i] == 46 {
			parts << path[start..i]
			start = i + 1
		}
		i = i + 1
	}
	parts << path[start..]
	mut cur := sname
	mut pi := 0
	for pi < parts.len {
		part := parts[pi]
		if part.len == 0 {
			return error('结构体成员链 ${path} 里有空的成员名')
		}
		if !(cur in st.struct_size) {
			if cur in st.struct_extern {
				if pi < parts.len - 1 {
					return error('外部 MASM 结构体 ${win_masm_name(cur)} 的字段 .${part} 后不能继续用 . 访问（成员链 ${path}；cone 侧不掌握 windows.inc 的字段类型）')
				}
				// 外部结构体：末级成员名交给 MASM32 校验，cone 按 4 字节处理
				return 'int'
			}
			return error('${cur} 不是结构体类型，无法继续访问成员 .${part}（成员链 ${path}）')
		}
		key := cur + '.' + part
		if !(key in st.struct_mtype) {
			return error('结构体 ${cur} 没有成员 ${part}（成员链 ${path}）')
		}
		if st.struct_marray[key].len > 0 && pi < parts.len - 1 {
			return error('成员 ${cur}.${part} 是数组，cone 0.4 暂不支持在数组成员后继续用 . 访问')
		}
		cur = resolve_base_type(st, st.struct_mtype[key])
		pi = pi + 1
	}
	return cur
}

// struct_type_of_symbol: 变量 / 形参的 cone 类型若是结构体，返回结构体名，否则 ''。
fn struct_type_of_symbol(st SymTab, fname string, name string) string {
	mut t := ''
	key := name_key(fname, name)
	if key in st.local_type {
		t = st.local_type[key]
	} else if name in st.global_type {
		t = st.global_type[name]
	}
	if t.len == 0 {
		return ''
	}
	b := resolve_base_type(st, t)
	if b in st.struct_size || b in st.struct_extern {
		return b
	}
	return ''
}

// member_size_bytes: 结构体成员访问的字节数，供 expr_size / return 寄存器选择。
fn member_size_bytes(st SymTab, fname string, e Expr) int {
	sname := struct_type_of_symbol(st, fname, e.member_base)
	if sname.len == 0 {
		return 4
	}
	t := struct_member_type(st, sname, e.member_path) or { return 4 }
	if t in st.type_bytes {
		sz := st.type_bytes[t]
		if sz > 0 && sz <= 8 {
			return sz
		}
	}
	return 4
}

// member_is_float: 结构体成员声明是否为 f32/f64（决定它进 x87 时是 fld 还是整数转 fild）。
// 外部 win.STRUCT 的字段 cone 不掌握类型，一律按整数处理。
fn member_is_float(st SymTab, fname string, e Expr) bool {
	sname := struct_type_of_symbol(st, fname, e.member_base)
	if sname.len == 0 {
		return false
	}
	t := struct_member_type(st, sname, e.member_path) or { return false }
	return is_float_base(resolve_base_type(st, t))
}

// check_member_expr: 校验 a.b.c。
//   base 是结构体类型名 -> MASM 字段偏移常量，只允许出现在 [] 地址表达式里；
//   base 是结构体变量/形参 -> 成员内存引用（读写都支持）。
fn check_member_expr(prog Program, st SymTab, fname string, idx int, in_addr bool) !string {
	e := prog.exprs[idx]
	loc := '第 ${e.line} 行'
	base := e.member_base
	if base in st.struct_size || base in st.struct_extern {
		struct_member_type(st, base, e.member_path) or { return error('${loc}: ${err.msg()}') }
		if !in_addr {
			disp := win_masm_name(base)
			return error('${loc}: ${e.text} 是结构体字段偏移常量（MASM32 的 ${disp}.成员），只能写在 [] 地址表达式里（如 [int lpst+${disp}.成员]）；不能单独作值或赋值目标')
		}
		return ''
	}
	mut known := false
	if name_key(fname, base) in st.name_maps {
		known = true
	}
	if base in st.globals {
		known = true
	}
	if !known {
		return error('${loc}: 标识符 ${base} 未定义（既不是全局符号，也不是本函数局部变量/形参）')
	}
	sname := struct_type_of_symbol(st, fname, base)
	if sname.len == 0 {
		return error('${loc}: ${base} 不是结构体变量，不能用 . 访问成员 ${e.member_path}；只有结构体类型的变量 / 形参才支持成员访问')
	}
	struct_member_type(st, sname, e.member_path) or { return error('${loc}: ${err.msg()}') }
	return ''
}

fn name_key(fname string, cone_name string) string {
	return fname + '::' + cone_name
}

fn resolve_base_type(st SymTab, name string) string {
	mut n := name
	mut guard := 0
	for guard < 32 {
		mut changed := false
		if n in st.typedef_base {
			n = st.typedef_base[n]
			changed = true
		}
		if !changed {
			break
		}
		guard = guard + 1
	}
	return n
}

fn symbol_base_type(st SymTab, fname string, name string) string {
	key := name_key(fname, name)
	mut t := ''
	if key in st.local_type {
		t = st.local_type[key]
	} else if name in st.global_type {
		t = st.global_type[name]
	}
	if t.len == 0 {
		return ''
	}
	return resolve_base_type(st, t)
}

fn is_float_base(base string) bool {
	return base == 'f32' || base == 'f64'
}

fn is_data_label(st SymTab, name string) bool {
	mut ok := false
	if name in st.global_kind {
		if st.global_kind[name] == 'data' {
			ok = true
		}
	}
	return ok
}

fn is_equ(st SymTab, name string) bool {
	mut ok := false
	if name in st.global_kind {
		if st.global_kind[name] == 'equ' {
			ok = true
		}
	}
	return ok
}

// symbol_size: cone 标识符的字节数。字符串数据标签 / equ / 函数名按 4 字节（dword）计，
// 因为 MASM 里把它们当 32 位量使用（数据标签取值时显式 dword ptr）。
fn symbol_size(st SymTab, fname string, name string) int {
	if is_reg_name(name) {
		return reg_size(name)
	}
	key := name_key(fname, name)
	if key in st.local_type {
		t := st.local_type[key]
		if t in st.type_bytes {
			return st.type_bytes[t]
		}
		return 4
	}
	if name in st.global_kind {
		k := st.global_kind[name]
		if k == 'data' || k == 'equ' || k == 'func' || k == 'proto' || k == 'typedef' {
			return 4
		}
		if name in st.global_type {
			t := st.global_type[name]
			if t in st.type_bytes {
				return st.type_bytes[t]
			}
		}
	}
	return 4
}

// expr_size: 表达式结果的字节数；数值返回 0（中性），由调用方把 0 当 4。
// 复合表达式取两侧较大者（所以 `return x-10` 里 x 是 word 就按 2 字节返回）。
fn expr_size(prog Program, st SymTab, fname string, idx int) int {
	if idx < 0 || idx >= prog.exprs.len {
		return 4
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_member {
		return member_size_bytes(st, fname, e)
	}
	if e.kind == ExprKind.expr_num {
		return 0
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg {
			return reg_size(e.text)
		}
		return symbol_size(st, fname, e.text)
	}
	if e.kind == ExprKind.expr_neg {
		return expr_size(prog, st, fname, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		l := expr_size(prog, st, fname, e.a)
		r := expr_size(prog, st, fname, e.b)
		if l > r {
			return l
		}
		return r
	}
	if e.kind == ExprKind.expr_deref {
		return deref_size_bytes(e.ptr_size)
	}
	return 4
}

// expr_is_float: 【本轮确认的口径】必须表达式里出现浮点字面量或 f32/f64 变量才走 x87。
// 其余一律按整数/原始位处理（后续再按目的地尺寸做零扩展或截断）。
// cone 0.9.2：表达式结果的 cone 类型名（用于 return 值 / 返回类型一致性校验）。
fn expr_type_of(prog Program, st SymTab, fname string, idx int) string {
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_ident && !e.is_reg && !e.is_win_sym && !e.is_struct_lit {
		return symbol_base_type(st, fname, e.text)
	}
	if e.kind == ExprKind.expr_member {
		sn := struct_type_of_symbol(st, fname, e.member_base)
		if sn.len == 0 {
			return ''
		}
		t := struct_member_type(st, sn, e.member_path) or { return '' }
		return resolve_base_type(st, t)
	}
	return ''
}

fn expr_is_float(prog Program, st SymTab, fname string, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	// cone 0.6：float(...) 括起的内容一律按浮点处理（表达式因此走 x87）。
	if e.is_float_hint {
		return true
	}
	if e.kind == ExprKind.expr_member {
		return member_is_float(st, fname, e)
	}
	if e.kind == ExprKind.expr_num {
		return is_float_lit(e.text)
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg {
			return false
		}
		return is_float_base(symbol_base_type(st, fname, e.text))
	}
	if e.kind == ExprKind.expr_neg {
		return expr_is_float(prog, st, fname, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		l := expr_is_float(prog, st, fname, e.a)
		r := expr_is_float(prog, st, fname, e.b)
		return l || r
	}
	// expr_call / expr_addr / expr_deref / expr_str 都不携带浮点类型信息
	return false
}

// mangle_name: cone 0.6 fix1 取消名称修饰。MASM32 的 PROC 局部变量 / 形参是
// 函数作用域，与全局符号同名不冲突，不同函数间的同名局部 / 形参也不冲突。
fn mangle_name(name string, prefix string, globals map[string]bool, used map[string]bool) string {
	return name
}

// cone 0.6 fix2：pos 是调用名 token 在【最终展开后的 token 流】里的绝对位置。
// 之前用源码行号比较：cone 库 import 展开后仍带着库内行号（例如 os.cone 的 31 行），
// 跟主文件调用点（例如 24 行）比较毫无意义，于是明明在 import 之后调用也被误判为
// 「调用在声明之前」。改用绝对位置后，库里的 def 天然排在 import 点之后的主文件代码之前。
// line / decl_line 只保留给报错文本，展示真实源码行。
fn check_call(st SymTab, full string, pos int, line int) !string {
	if full.len > 4 && full[..4] == 'win.' {
		return full[4..]
	}
	mut dot := -1
	mut i := 0
	for i < full.len {
		if full[i] == 46 {
			dot = i
		}
		i = i + 1
	}
	mut fnname := full
	if dot >= 0 {
		prefix := full[..dot]
		fnname = full[dot + 1..]
		mut mod_ok := false
		if prefix in st.imports {
			mod_ok = true
		}
		if !mod_ok {
			return error('第 ${line} 行: 模块 ${prefix} 未导入（调用 ${full} 需要 `include ${prefix}.lib` 或 `include ${prefix}`；若是 .inc 里的函数，请用 win.${fnname} 调用）')
		}
	}
	// cone 0.6 fix2：win{...} 批量登记的名字与 win.* 同等待遇，免声明 / 免顺序检查。
	if fnname in st.win_bare {
		return fnname
	}
	// cone 0.83：defined 宏（无 exitm）免「函数声明/定义」与调用顺序检查。
	if fnname in st.macros {
		return fnname
	}
	mut known := false
	if fnname in st.declared {
		known = true
	}
	if fnname in st.defined {
		known = true
	}
	if !known {
		return error('第 ${line} 行: 函数 ${fnname} 既未声明(func)也未定义(def)，也不是 win.* 默认 include 函数')
	}
	// cone 0.3：与 MASM32 一致——invoke 之前必须先有 PROTO 声明或 proc 定义。
	// 调用点之前既没有 def 也没有 func 声明就报错（即使函数在文件后面定义了也不行）。
	if fnname in st.decl_pos {
		if st.decl_pos[fnname] >= pos {
			return error('第 ${line} 行: 函数 ${fnname} 在本次调用之前既未定义也未声明（cone 0.3 与 MASM32 一致：invoke 之前必须有 PROTO 或 proc 定义；cone 库经 import 展开后按展开位置判断）。请在调用点之前加 `func ${fnname}(...)` 声明，或把 `def ${fnname}` 移到调用点之前；该名字首次出现在第 ${st.decl_line[fnname]} 行')
		}
	}
	return fnname
}

// ---------- [] 地址表达式校验 ----------
//
// 支持的形态（对应 MASM32 的 [mem] / [mem+imm] / [mem+reg] / [mem+reg*scale+imm]）：
//   [type xxx]
//   [type xxx+imm]
//   [type xxx+xxx*imm+imm]
// 其中 xxx = 标识符（数据标签/变量/形参）或函数调用（结果在 eax，即 [eax+imm]）。
// 纯立即数 [type imm] 被拒绝（MASM32 不允许），因为必须有至少一个基址项。
// 比例因子只允许 1/2/4/8（x86 SIB）。

struct AddrInfo {
	has_base    bool
	calls       int
	plain_bases int
	scaled      int
}

fn addr_info_merge(a AddrInfo, b AddrInfo) AddrInfo {
	return AddrInfo{
		has_base:    a.has_base || b.has_base
		calls:       a.calls + b.calls
		plain_bases: a.plain_bases + b.plain_bases
		scaled:      a.scaled + b.scaled
	}
}

fn check_addr_expr(prog Program, st SymTab, fname string, idx int) !AddrInfo {
	if idx < 0 || idx >= prog.exprs.len {
		return error('内部错误: 地址表达式索引越界')
	}
	e := prog.exprs[idx]
	loc := '第 ${e.line} 行'

	if e.kind == ExprKind.expr_str {
		return error('${loc}: [] 内的地址表达式不能含字符常量（字符串字面量）；地址只能由标识符 / 寄存器 / 数值 / 调用组成')
	}
	if e.kind == ExprKind.expr_bin && is_cond_op(e.text) {
		return error('${loc}: [] 内的地址表达式不允许比较 / 逻辑运算符 ${e.text}')
	}
	if e.kind == ExprKind.expr_neg && e.text == '!' {
		return error('${loc}: [] 内的地址表达式不允许逻辑非 !')
	}
	if e.kind == ExprKind.expr_num {
		if is_float_lit(e.text) {
			return error('${loc}: [] 内的地址表达式不能含浮点字面量 ${e.text}')
		}
		return AddrInfo{}
	}
	if e.kind == ExprKind.expr_ident {
		check_expr(prog, st, idx, fname) or { return error(err.msg()) }
		return AddrInfo{
			has_base:    true
			plain_bases: 1
		}
	}
	if e.kind == ExprKind.expr_member {
		check_member_expr(prog, st, fname, idx, true) or { return error(err.msg()) }
		if !(e.member_base in st.struct_size) && !(e.member_base in st.struct_extern) {
			return error('${loc}: [] 内只接受 `结构体类型名.成员` 或 `win.外部类型.成员` 形式的字段偏移（如 [int lpst+ttt.x] / [int lpst+win.RECT.left]）；${e.text} 是结构体变量的成员（内存值），不能当地址项')
		}
		return AddrInfo{}
	}
	if e.kind == ExprKind.expr_neg {
		if prog.exprs[e.a].kind != ExprKind.expr_num {
			return error('${loc}: [] 内的一元负号只用于数值位移（如 [byte fmt+4] 的形式）')
		}
		r := check_addr_expr(prog, st, fname, e.a) or { return error(err.msg()) }
		return r
	}
	if e.kind == ExprKind.expr_addr {
		inner := prog.exprs[e.a]
		if inner.kind != ExprKind.expr_ident {
			return error('${loc}: [] 内的 addr 后面必须是标识符')
		}
		if inner.is_reg {
			return error('${loc}: [] 内的 addr 后面必须是变量标识符，不能是寄存器 ${inner.text}；请直接写 [type ${inner.text}+imm]')
		}
		check_expr(prog, st, e.a, fname) or { return error(err.msg()) }
		return AddrInfo{
			has_base:    true
			plain_bases: 1
		}
	}
	if e.kind == ExprKind.expr_call {
		check_expr(prog, st, idx, fname) or { return error(err.msg()) }
		return AddrInfo{
			has_base:    true
			calls:       1
			plain_bases: 1
		}
	}
	if e.kind == ExprKind.expr_bin {
		if e.text == '/' {
			return error('${loc}: [] 内的地址表达式不允许 / （只支持 + - 与 * 比例因子）')
		}
		if e.text == '*' {
			mut num_idx := -1
			mut base_idx := -1
			if prog.exprs[e.a].kind == ExprKind.expr_num {
				num_idx = e.a
				base_idx = e.b
			} else if prog.exprs[e.b].kind == ExprKind.expr_num {
				num_idx = e.b
				base_idx = e.a
			} else {
				return error('${loc}: [] 内的 * 只允许 `标识符或函数调用 * 立即数` 作比例项（如 [byte fmt+idx*4+8]），不允许两项都不是立即数')
			}
			scale_tok := prog.exprs[num_idx]
			if is_float_lit(scale_tok.text) {
				return error('${loc}: [] 内的比例因子不能是浮点字面量 ${scale_tok.text}')
			}
			scale := parse_int_lit(scale_tok.text) or {
				return error('${loc}: [] 内的比例因子 ${scale_tok.text} 不是合法整数')
			}
			if scale != 1 && scale != 2 && scale != 4 && scale != 8 {
				return error('${loc}: [] 内的比例因子只允许 1/2/4/8（x86 SIB 比例），得到 ${scale}')
			}
			bk := prog.exprs[base_idx].kind
			if bk != ExprKind.expr_ident && bk != ExprKind.expr_call {
				return error('${loc}: [] 内的 * 比例项里被乘的一方必须是标识符或函数调用，得到 ${describe_expr(prog.exprs, base_idx)}')
			}
			bi := check_addr_expr(prog, st, fname, base_idx) or { return error(err.msg()) }
			return AddrInfo{
				has_base:    true
				calls:       bi.calls
				plain_bases: 0
				scaled:      1
			}
		}
		la := check_addr_expr(prog, st, fname, e.a) or { return error(err.msg()) }
		rb := check_addr_expr(prog, st, fname, e.b) or { return error(err.msg()) }
		return addr_info_merge(la, rb)
	}
	return error('${loc}: [] 内只允许 标识符 / 函数调用 / 数值 / + - / *比例因子 / addr 标识符 组成的地址表达式，实际是 ${describe_expr(prog.exprs, idx)}')
}

fn check_deref(prog Program, st SymTab, fname string, idx int) !string {
	info := check_addr_expr(prog, st, fname, prog.exprs[idx].a) or { return error(err.msg()) }
	loc := '第 ${prog.exprs[idx].line} 行'
	if !info.has_base {
		return error('${loc}: [] 内的地址表达式必须包含至少一个标识符或函数调用（MASM32 不允许 type ptr [imm] 这种纯立即数寻址）')
	}
	if info.calls > 1 {
		return error('${loc}: [] 内的地址表达式最多支持一个函数调用（其结果按 eax 参与寻址）')
	}
	// cone 0.3：寄存器可进入寻址，x86 形如 [disp32+base+index*scale+imm]，
	// 因此允许至多两个基址项（一个数据标签/变量 + 一个寄存器）+ 一个比例项。
	if info.plain_bases > 2 || info.scaled > 1 {
		return error('${loc}: [] 的地址表达式只支持 [type xxx+imm] / [type xxx+reg+imm] / [type xxx+xxx*imm+imm] 形式（至多两个基址项 + 一个比例项）')
	}
	return ''
}

// check_expr_ex: 表达式校验。allow_cond=true 时允许比较 / 逻辑运算符（仅 if 条件）。
// cone 0.3：比较与逻辑运算目前只为 if 链服务，赋给变量 / 作 return / 作调用参数时
// 给出明确报错，而不是静默生成空代码。
fn check_expr_ex(prog Program, st SymTab, idx int, fname string, allow_cond bool, allow_struct bool) !string {
	if idx < 0 || idx >= prog.exprs.len {
		return error('内部错误: 表达式索引越界')
	}
	e := prog.exprs[idx]
	loc := '第 ${e.line} 行'

	if e.kind == ExprKind.expr_num {
		return ''
	}
	// cone 0.9prelease：sizeof(xxx) 是编译期立即数，最终由 cone_fold_immediates(strict) 折叠
	if e.kind == ExprKind.expr_sizeof {
		return ''
	}
	if e.kind == ExprKind.expr_str {
		if e.is_char_const {
			expand_char_const(e.text) or {
				return error('${loc}: 字符常量 ${e.text} 的转义序列非法：${err.msg()}')
			}
		}
		return ''
	}
	if e.kind == ExprKind.expr_ident {
		// cone 0.3：寄存器 / win.XXX 都是天然已知符号，不查 cone 符号表。
		if e.is_reg || e.is_win_sym {
			// cone 0.6：结构体常量只在「直接作函数调用参数」或「addr 取地址」时有意义，
			// 参与算术 / 比较 / 赋值 / return / 条件会生成非法 MASM 操作数。
			if e.is_struct_lit && !allow_struct {
				return error('${loc}: 结构体常量 ${e.lit_type}{...} 只能直接作为函数调用参数，或用 addr 取其地址；不能参与算术 / 比较 / 赋值 / return / 条件表达式')
			}
			return ''
		}
		mut known := false
		if e.text in st.globals {
			known = true
		}
		if name_key(fname, e.text) in st.name_maps {
			known = true
		}
		// cone 0.6 fix2：win{...} 登记的名字等价于 win.名字，不查 cone 符号表。
		if e.text in st.win_bare {
			known = true
		}
		if !known {
			return error('${loc}: 标识符 ${e.text} 未定义（既不是全局符号，也不是本函数局部变量/形参）；若想调用函数请写成 ${e.text}(...)')
		}
		return ''
	}
	if e.kind == ExprKind.expr_member {
		check_member_expr(prog, st, fname, idx, false) or { return error(err.msg()) }
		return ''
	}
	if e.kind == ExprKind.expr_neg {
		if e.text == '!' && !allow_cond {
			return error('${loc}: 逻辑非 ! 目前只能在 if / elseif 条件里使用（cone 0.3 不生成布尔值表达式）')
		}
		check_expr_ex(prog, st, e.a, fname, allow_cond, false) or { return error(err.msg()) }
		return ''
	}
	if e.kind == ExprKind.expr_bin {
		if is_cond_op(e.text) && !allow_cond {
			return error('${loc}: 比较 / 逻辑运算符 `${e.text}` 目前只能在 if / elseif 条件里使用；cone 0.3 暂不支持把比较结果赋给变量或传给函数')
		}
		// cone 0.9.1：% 取模不允许浮点操作数；只检查 % 的直接左右子树，
		// 这样 float(a % b)（% 两侧是整数）仍合法，结果再由 float() 送 st(0)。
		if e.text == '%' {
			if expr_is_float(prog, st, fname, e.a) || expr_is_float(prog, st, fname, e.b) {
				return error('${loc}: % 取模运算不支持浮点操作数（float(...) / 浮点字面量 / f32,f64 变量）；请只对整数表达式取模，需要浮点结果请写 float(整数取模表达式)')
			}
		}
		check_expr_ex(prog, st, e.a, fname, allow_cond, false) or { return error(err.msg()) }
		check_expr_ex(prog, st, e.b, fname, allow_cond, false) or { return error(err.msg()) }
		return ''
	}
	if e.kind == ExprKind.expr_addr {
		inner := prog.exprs[e.a]
		if inner.kind != ExprKind.expr_ident {
			return error('${loc}: addr 后面必须是标识符（取地址），不能是 ${describe_expr(prog.exprs, e.a)}')
		}
		if inner.is_reg {
			return error('${loc}: addr 后面必须是变量标识符，不能是寄存器 ${inner.text}（寄存器本身没有 cone 层地址；要取寄存器参与寻址，请直接把寄存器写进 [] 地址表达式）')
		}
		check_expr_ex(prog, st, e.a, fname, false, true) or { return error(err.msg()) }
		return ''
	}
	if e.kind == ExprKind.expr_deref {
		check_deref(prog, st, fname, idx) or { return error(err.msg()) }
		return ''
	}
	if e.kind == ExprKind.expr_call {
		check_call(st, e.text, e.pos, e.line) or { return error(err.msg()) }
		mut i := 0
		for i < e.args.len {
			arg := prog.exprs[e.args[i]]
			if arg.kind == ExprKind.expr_str && !arg.is_char_const {
				return error('第 ${arg.line} 行: 字符串字面量不能直接作调用参数（请定义数据标签再用 addr）')
			}
			// 调用参数里永远不允许比较 / 逻辑运算符（它们不是值表达式）；
			// 但 cone 0.6 允许把结构体常量直接写在参数位置。
			check_expr_ex(prog, st, e.args[i], fname, false, true) or { return error(err.msg()) }
			i = i + 1
		}
		return ''
	}
	return error('${loc}: 未知表达式节点')
}

fn check_expr(prog Program, st SymTab, idx int, fname string) !string {
	return check_expr_ex(prog, st, idx, fname, false, false) or { return error(err.msg()) }
}

fn check_expr_cond(prog Program, st SymTab, idx int, fname string) !string {
	return check_expr_ex(prog, st, idx, fname, true, false) or { return error(err.msg()) }
}

// validate_equ_expr: equ 项只允许常量表达式，不允许函数调用 / 解引用 / addr。
fn validate_equ_expr(prog Program, st SymTab, idx int, owner string, line int) !string {
	if idx < 0 || idx >= prog.exprs.len {
		return error('内部错误: equ 表达式索引越界')
	}
	e := prog.exprs[idx]
	if e.is_float_hint {
		return error('第 ${line} 行: ${owner} 里不允许 float(...)（它是运行时浮点求值，不是编译期常量）')
	}
	if e.is_struct_lit {
		return error('第 ${line} 行: ${owner} 里不允许结构体常量')
	}
	if e.kind == ExprKind.expr_num || e.kind == ExprKind.expr_str {
		return ''
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg || e.is_win_sym || e.text in st.win_bare {
			return ''
		}
		if !(e.text in st.globals) {
			return error('第 ${line} 行: ${owner} equ 引用了未定义的标识符 ${e.text}')
		}
		return ''
	}
	if e.kind == ExprKind.expr_neg {
		validate_equ_expr(prog, st, e.a, owner, line) or { return error(err.msg()) }
		return ''
	}
	if e.kind == ExprKind.expr_bin {
		if is_cond_op(e.text) {
			return error('第 ${line} 行: ${owner} equ 里不允许比较 / 逻辑运算符 ${e.text}（equ 只接受常量四则表达式）')
		}
		validate_equ_expr(prog, st, e.a, owner, line) or { return error(err.msg()) }
		validate_equ_expr(prog, st, e.b, owner, line) or { return error(err.msg()) }
		return ''
	}
	return error('第 ${line} 行: ${owner} equ 里不允许 ${describe_expr(prog.exprs, idx)}（只接受数值 / 字符串 / 已定义标识符 / 常量四则表达式）')
}

// cone 0.7：except 的 ErrorType 必须是编译期错误码常量（数值 / 数值 equ /
// win.MASM 常量 / 未折叠的 equ 常量名 / 常量四则与位运算）。
fn validate_except_code(prog Program, st SymTab, idx int, line int) !string {
	if idx < 0 || idx >= prog.exprs.len {
		return error('内部错误: except ErrorType 表达式索引越界')
	}
	e := prog.exprs[idx]
	if e.is_float_hint || e.is_struct_lit || e.is_char_const {
		return error('第 ${line} 行: except 的 ErrorType 必须是编译期错误码常量，不能是 float(...) / 结构体常量 / 字符常量')
	}
	if e.kind == ExprKind.expr_num {
		return ''
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg {
			return error('第 ${line} 行: except 的 ErrorType 不能是寄存器 ${e.text}（必须是编译期错误码常量）')
		}
		if e.is_win_sym || (e.text in st.win_bare) {
			return ''
		}
		if e.text in st.globals {
			k := st.global_kind[e.text]
			if k == 'equ' {
				return '' // 未折叠的 equ 常量名，交给 MASM32 的文本替换
			}
			return error('第 ${line} 行: except 的 ErrorType 引用了 ${e.text}，它是 ${k} 而不是编译期常量')
		}
		return error('第 ${line} 行: except 的 ErrorType 引用了未定义标识符 ${e.text}')
	}
	if e.kind == ExprKind.expr_neg {
		validate_except_code(prog, st, e.a, line) or { return error(err.msg()) }
		return ''
	}
	if e.kind == ExprKind.expr_bin {
		if is_cond_op(e.text) {
			return error('第 ${line} 行: except 的 ErrorType 里不允许比较 / 逻辑运算符 ${e.text}')
		}
		validate_except_code(prog, st, e.a, line) or { return error(err.msg()) }
		validate_except_code(prog, st, e.b, line) or { return error(err.msg()) }
		return ''
	}
	return error('第 ${line} 行: except 的 ErrorType 必须是编译期错误码常量表达式（数值 / equ / win.MASM 常量 / 位运算），实际得到 ${describe_expr(prog.exprs, idx)}；不能是字符串 / 函数调用 / addr / [] / 结构体成员')
}

// cone 0.7：按摊平标记流复核 try/except 配对（parser 已做结构校验，这里兜底）。
fn validate_try_chain(prog Program, st SymTab, f FuncDef) !string {
	mut depth := 0
	for s in f.body {
		if s.kind == StmtKind.st_try {
			depth = depth + 1
		} else if s.kind == StmtKind.st_endtry {
			depth = depth - 1
			if depth < 0 {
				return error('第 ${s.line} 行: 函数 ${f.name} 的 try/except 标记流不配对（多余的结束标记）')
			}
		} else if s.kind == StmtKind.st_except {
			if depth == 0 {
				return error('第 ${s.line} 行: 函数 ${f.name} 里 except 没有对应的 try')
			}
			if s.except_idx >= 0 {
				validate_except_code(prog, st, s.except_idx, s.line) or { return error(err.msg()) }
			}
		}
	}
	if depth != 0 {
		return error('第 ${f.line} 行: 函数 ${f.name} 的 try 缺少结束标记')
	}
	return ''
}


// =====================================================================
// cone 0.9prelease：编译期立即数统一层
//   * cone struct 的 Type.member 由 cone 计算成字节偏移（win 外部结构体透传 MASM）
//   * struct NAME align{...} 按 Windows ABI 对齐，生成 _padding_ 字段
//   * sizeof(xxx) 编译期求值（类型 / 数组 / 结构体 / 数据字节数组）
//   * addr / $ / equ 数值宏 / sizeof / Type.member 统一视为立即数
// =====================================================================

// cone 0.9.3：统一诊断收集器。error / warning 都带「文件:行号」，一次编译
// 收集全部诊断，最后统一输出；有 error 则不生成 .asm，warning 不中断编译。
struct Diagnostic {
	severity string
	file     string
	line     int
	msg      string
}
struct Diagnostics {
mut:
	items []Diagnostic
}
fn (mut d Diagnostics) add(severity string, file string, line int, raw string) {
	msg := strip_cn_line_prefix(raw)
	mut f := file
	if f.len == 0 {
		f = '<unknown>'
	}
	for it in d.items {
		if it.severity == severity && it.file == f && it.line == line && it.msg == msg {
			return
		}
	}
	d.items << Diagnostic{severity: severity, file: f, line: line, msg: msg}
}
fn (mut d Diagnostics) add_error(file string, line int, msg string) {
	d.add('error', file, line, msg)
}
fn (mut d Diagnostics) add_warning(file string, line int, msg string) {
	d.add('warning', file, line, msg)
}
fn (d Diagnostics) has_errors() bool {
	for it in d.items {
		if it.severity == 'error' {
			return true
		}
	}
	return false
}
fn (d Diagnostics) render() string {
	// cone 0.9.p：header 独占一行，正文可多行；tty 下 error 红 / warning 黄，
	// 重定向或 CONE_NO_COLOR=1 时输出纯文本。
	color := os.is_atty(2) != 0 && os.getenv('CONE_NO_COLOR').len == 0
	mut ls := []string{}
	for it in d.items {
		tag := if it.severity == 'error' { 'ERROR' } else { 'WARNING' }
		mut blk := '${it.file}:line ${it.line} (${tag}):\n${it.msg}'
		if color {
			c := if it.severity == 'error' { '\x1b[31m' } else { '\x1b[33m' }
			blk = c + blk + '\x1b[0m'
		}
		ls << blk
	}
	return ls.join('\n')
}

// cone 0.9.3：全量诊断扫描。逐条收集、不中断，一次编译爆出所有 error/warning。
// 返回类型优先从 prog 的 func/efunc 声明读（不依赖 analyze 是否跑完），尺寸用
// 符号表 + 内置类型表兜底，因此即使 analyze 在第一处抛错仍能列出其余问题。
fn ret_bytes_fallback(rt string) int {
	return match rt {
		'byte' { 1 }
		'word' { 2 }
		'int', 'f32' { 4 }
		'long', 'f64' { 8 }
		else { 0 }
	}
}
fn collect_diagnostics(prog Program, st SymTab, mut diags Diagnostics, main_file string) {
	// 1) % 取模的浮点操作数
	for e in prog.exprs {
		if e.kind == ExprKind.expr_bin && e.text == '%' {
			if expr_is_float(prog, st, '', e.a) || expr_is_float(prog, st, '', e.b) {
				diags.add_error(main_file, e.line, '% 取模运算不支持浮点操作数（float(...) / 浮点字面量 / f32,f64 变量）；请只对整数表达式取模，需要浮点结果请写 float(整数取模表达式)')
			}
		}
	}
	// 2) 函数声明的返回类型（prog 级，efunc 同样登记）
	mut rty := map[string]string{}
	for pr in prog.protos {
		if pr.ret_type.len > 0 {
			rty[pr.name] = pr.ret_type
		}
	}
	for f in prog.funcs {
		if f.ret_type.len > 0 {
			rty[f.name] = f.ret_type
		}
	}
	for f in prog.funcs {
		mut ff := main_file
		if f.file.len > 0 {
			ff = f.file
		}
		rt := rty[f.name]
		if rt.len == 0 {
			continue
		}
		ris := st.func_ret_is_struct[f.name]
		mut rsz := st.func_ret_size[f.name]
		if rsz == 0 {
			rsz = ret_bytes_fallback(resolve_base_type(st, rt))
		}
		rb := resolve_base_type(st, rt)
		mut has_ret := false
		for s in f.body {
			if s.kind == StmtKind.st_return {
				has_ret = true
				if s.ret_idx < 0 {
					diags.add_error(ff, s.line, '空 return；cone 0.2 完善版要求 return <表达式>')
					continue
				}
				et := expr_type_of(prog, st, f.name, s.ret_idx)
				if ris {
					if et != rb {
						diags.add_error(ff, s.line, '函数 ${f.name} 声明返回结构体 ${rt}，return 值必须是 ${rt} 类型的结构体实例，实际得到 ${describe_expr(prog.exprs, s.ret_idx)}')
					}
					continue
				}
				if et in st.struct_size || et in st.struct_extern {
					diags.add_error(ff, s.line, '函数 ${f.name} 声明返回标量 ${rt}，不能 return 结构体实例（${describe_expr(prog.exprs, s.ret_idx)}）')
					continue
				}
				if expr_is_float(prog, st, f.name, s.ret_idx) {
					continue
				}
				mut esz := expr_size(prog, st, f.name, s.ret_idx)
				if esz == 0 {
					esz = 4
				}
				if esz > rsz {
					diags.add_error(ff, s.line, '函数 ${f.name} 声明返回 ${rt}（${rsz} 字节），return 值 ${esz} 字节大于返回类型声明尺寸')
				} else if esz < rsz {
					// cone 0.9.3：不再是 .asm 注释，而是编译器 warning（带 文件:行号）
					diags.add_warning(ff, s.line, '函数 ${f.name} 声明返回 ${rt}（${rsz} 字节），return 值 ${esz} 字节小于 ${rsz}，已按 coneABI 零扩展到 edx:eax')
				}
			} else if s.kind == StmtKind.st_assign && s.lhs_idx < 0 && !is_reg_name(s.lhs) {
				// 3) 结构体 / 标量函数返回值的接收约束
				re := prog.exprs[s.rhs_idx]
				if re.kind == ExprKind.expr_call {
					tg := call_target(re.text)
					trt := rty[tg]
					if trt.len > 0 {
						tris := st.func_ret_is_struct[tg]
						mut trsz := st.func_ret_size[tg]
						if trsz == 0 {
							trsz = ret_bytes_fallback(resolve_base_type(st, trt))
						}
						db := resolve_base_type(st, symbol_base_type(st, f.name, s.lhs))
						if tris {
							if db != resolve_base_type(st, trt) {
								diags.add_error(ff, s.line, '用结构体接收函数 ${tg} 的返回值时，类型必须是 ${trt}，实际是 ${db}')
							}
						} else {
							mut dsz := st.type_bytes[db]
							if dsz == 0 {
								dsz = ret_bytes_fallback(db)
							}
							if dsz == 0 {
								dsz = 4
							}
							if dsz != trsz {
								diags.add_error(ff, s.line, '函数 ${tg} 返回 ${trt}（${trsz} 字节），接收变量 ${s.lhs} 是 ${dsz} 字节，尺寸不足或过大')
							}
						}
					}
				}
			} else if s.kind == StmtKind.st_local && s.local_array_len.contains('$') {
				diags.add_error(ff, s.line, '数组长度 / 编译期常量 $ 不是合法 cone 立即数表达式（展开为 ${s.local_array_len}）')
			}
		}
		if !has_ret {
			diags.add_error(ff, f.line, '函数 ${f.name} 没有 return')
		}
	}
	// cone 0.9.p：x64 调用参数个数 / 尺寸检查（x86 不进入）
	x64_check_calls_v(prog, st, mut diags, main_file)
}

// =====================================================================
// cone 0.9.p : x64 调用检查（参数个数 / 参数尺寸）—— 与 Python 参考实现同名同义
// =====================================================================
struct X64Proto {
mut:
	types []string
	va    bool
	line  int
	file  string
	src   string
}

fn x64_call_target_v(full string) string {
	if full.len > 4 && full[..4] == 'win.' { return full[4..] }
	mut dot := -1
	for i := 0; i < full.len; i++ {
		if full[i] == 46 { dot = i }
	}
	if dot >= 0 { return full[dot + 1..] }
	return full
}

fn x64_proto_map_v(prog Program) map[string]X64Proto {
	mut out := map[string]X64Proto{}
	for f in prog.funcs {
		mut ts := []string{}
		for q in f.params {
			if q.typ_name != 'vararg' { ts << q.typ_name }
		}
		out[f.name] = X64Proto{types: ts, va: false, line: f.line, file: f.file, src: 'def'}
	}
	for pr in prog.protos {
		mut va := false
		mut ts := []string{}
		for q in pr.params {
			if q.typ_name == 'vararg' {
				va = true
			} else {
				ts << q.typ_name
			}
		}
		if pr.name in out {
			mut p2 := out[pr.name]
			p2.va = p2.va || va
			if p2.types.len == 0 { p2.types = ts }
			out[pr.name] = p2
		} else {
			out[pr.name] = X64Proto{types: ts, va: va, line: pr.line, file: pr.file, src: 'func'}
		}
	}
	// cone 0.9.p：内置 CRT 变参函数（与 llvmir.py LLVM_VARARGS 同源）
	for nm in ['printf', 'sprintf', 'wsprintfA', 'puts', 'strlen', 'wprintf'] {
		if nm in out {
			mut p3 := out[nm]
			p3.va = true
			out[nm] = p3
		}
	}
	return out
}

fn x64_type_bytes_v(st SymTab, name string) int {
	b := resolve_base_type(st, name)
	if b in st.struct_size {
		n := st.struct_size[b]
		if n > 8 { return 8 }
		return n
	}
	return st.type_bytes[b]
}

fn x64_ptr_arg_v(prog Program, st SymTab, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len { return false }
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_str || e.kind == ExprKind.expr_addr
		|| e.kind == ExprKind.expr_member { return true }
	if e.kind != ExprKind.expr_ident { return false }
	for d in prog.data {
		if d.name == e.text { return true }
	}
	for v in prog.vars {
		if v.name == e.text && v.array_len.len > 0 { return true }
	}
	for f in prog.funcs {
		for st2 in f.body {
			if st2.kind == StmtKind.st_local && st2.local_array_len.len > 0 {
				for nm in st2.local_names {
					if nm == e.text { return true }
				}
			}
		}
	}
	for f3 in prog.funcs {
		t := symbol_base_type(st, f3.name, e.text)
		if t.len > 0 && resolve_base_type(st, t) in st.struct_size { return true }
	}
	t2 := symbol_base_type(st, '', e.text)
	return t2.len > 0 && resolve_base_type(st, t2) in st.struct_size
}

fn x64_decl_label_v(st SymTab, name string) string {
	return resolve_base_type(st, name)
}

fn x64_size_label_v(n int) string {
	if n == 1 { return 'byte' }
	if n == 2 { return 'word' }
	if n == 8 { return 'long' }
	return 'int'
}

fn x64_arg_size_v(prog Program, st SymTab, fname string, idx int) (int, string) {
	if idx < 0 || idx >= prog.exprs.len { return 0, '' }
	e := prog.exprs[idx]
	if e.is_float_hint { return 8, 'f64' }
	if e.kind == ExprKind.expr_num {
		if is_float_lit(e.text) { return 8, 'f64' }
		return 4, 'int'
	}
	if e.kind == ExprKind.expr_str || e.kind == ExprKind.expr_addr { return 8, 'ptr' }
	if e.kind == ExprKind.expr_sizeof { return 4, 'int' }
	if e.kind == ExprKind.expr_deref {
		n := deref_size_bytes(e.ptr_size)
		return n, x64_size_label_v(n)
	}
	if e.kind == ExprKind.expr_bin || e.kind == ExprKind.expr_neg {
		if expr_is_float(prog, st, fname, idx) { return 8, 'f64' }
		return 4, 'int'
	}
	if e.kind == ExprKind.expr_call {
		nm := x64_call_target_v(e.text)
		rt := st.func_ret_type[nm]
		if rt.len == 0 { return 4, 'int' }
		return x64_type_bytes_v(st, rt), x64_decl_label_v(st, rt)
	}
	if e.kind == ExprKind.expr_member {
		n := member_size_bytes(st, fname, e)
		return n, x64_size_label_v(n)
	}
	if e.kind == ExprKind.expr_ident {
		nm2 := e.text
		if e.is_reg || e.is_win_sym { return 4, 'int' }
		if nm2 in st.equ_values || nm2 in prog.folded_equs { return 4, 'int' }
		mut ty := symbol_base_type(st, fname, nm2)
		if ty.len == 0 {
			for f4 in prog.funcs {
				ty = symbol_base_type(st, f4.name, nm2)
				if ty.len > 0 { break }
			}
		}
		if ty.len == 0 { return 0, '' }
		if x64_ptr_arg_v(prog, st, idx) { return 8, 'ptr' }
		return x64_type_bytes_v(st, ty), x64_decl_label_v(st, ty)
	}
	return 0, ''
}

fn x64_imm_value_v(prog Program, st SymTab, idx int) (bool, i64) {
	// 实参是否是编译期整数立即数（字面量 / 常量表达式 / 数值 equ）。
	if idx < 0 || idx >= prog.exprs.len { return false, 0 }
	e := prog.exprs[idx]
	if e.is_float_hint { return false, 0 }
	if e.kind == ExprKind.expr_num && is_float_lit(e.text) { return false, 0 }
	fr := try_fold(prog, idx)
	if fr.ok { return true, fr.value }
	if e.kind == ExprKind.expr_ident && !e.is_reg && !e.is_win_sym {
		nm := e.text
		mut eq := ''
		if nm in st.equ_values {
			eq = st.equ_values[nm]
		} else if nm in prog.folded_equs {
			eq = prog.folded_equs[nm]
		}
		if eq.len > 0 {
			v := cone_fold_int_text(st, eq) or { return false, 0 }
			return true, v
		}
	}
	return false, 0
}

fn x64_conv_short_v(st SymTab, asz int, dst string, dsz int) string {
	b := resolve_base_type(st, dst)
	src := 'i${asz * 8}'
	if b == 'f32' || b == 'f64' {
		dstl := if b == 'f32' { 'float' } else { 'double' }
		return 'cone会转换${src}->${dstl}'
	}
	if b == 'byte' || b == 'word' || b == 'int' || b == 'long' {
		return 'cone会符号扩展${src}->i${dsz * 8}'
	}
	return 'cone会按声明转换'
}

fn x64_check_calls_v(prog Program, st SymTab, mut diags Diagnostics, main_file string) {
	// x64 调用检查。诊断只给结论 + 必要建议；立即数按值判定，不按字面宽度。
	// 代码生成逻辑（call_v / as_type_v）完全不变。
	if !st.x64_mode { return }
	pmap := x64_proto_map_v(prog)
	for e in prog.exprs {
		if e.kind != ExprKind.expr_call { continue }
		nm := x64_call_target_v(e.text)
		if !(nm in pmap) { continue }
		p := pmap[nm]
		n := e.args.len
		nf := p.types.len
		ff := main_file
		ln := e.line
		mut df := base_name(p.file)
		if df.len == 0 { df = base_name(main_file) }
		if !p.va && n != nf {
			diags.add_error(ff, ln, 'x64--调用${nm}的参数与声明不匹配，声明${nf}个(${df}第${p.line}行声明)，调用了${n}个.\nattention:win关键字被禁用，声明必须与调用匹配，或声明为可变参数 `func ${nm}(... , :vararg)`')
			continue
		}
		for k := 0; k < n && k < nf; k++ {
			ai := e.args[k]
			if x64_ptr_arg_v(prog, st, ai) { continue }
			asz, alab := x64_arg_size_v(prog, st, '', ai)
			dsz := x64_type_bytes_v(st, p.types[k])
			dlab := x64_decl_label_v(st, p.types[k])
			if asz <= 0 || dsz <= 0 { continue }
			// 立即数：值落在声明尺寸可表示范围内 -> 不诊断；超出 -> 报错。
			iok, ival := x64_imm_value_v(prog, st, ai)
			if iok {
				if !fits_i64(ival, dsz) {
					diags.add_error(ff, ln, 'x64--${nm}第 ${k + 1} 个参数立即数 ${ival} 超出声明 ${dlab} 的范围(${dsz}bytes).\nattention:请减小立即数，或把声明改成更宽的类型(long)')
				}
				continue
			}
			if asz > dsz {
				diags.add_error(ff, ln, 'x64--${nm}第 ${k + 1} 个参数尺寸大于声明(${alab}:${asz}bytes>${dlab}:${dsz}bytes).\nattention:请改用不超过声明尺寸的实参，或把声明改成更宽的类型(long/f64)')
			} else if asz < dsz {
				diags.add_warning(ff, ln, 'x64--${nm}第 ${k + 1} 个参数尺寸小于声明(${alab}:${asz}bytes<${dlab}:${dsz}bytes). ${x64_conv_short_v(st, asz, p.types[k], dsz)}')
			}
		}
	}
}

struct PadInfo {
mut:
	mi      int
	nb      int
	is_tail bool
}

struct CurInfo {
mut:
	name  string
	off   int
	base  string
	unit  int
	isarr bool
}

struct IntEval {
mut:
	s   string
	pos int
}

fn cone_type_bytes(base string) int {
	if base == 'byte' || base == 'sbyte' {
		return 1
	}
	if base == 'word' || base == 'sword' {
		return 2
	}
	if base == 'int' || base == 'f32' || base == 'dword' || base == 'sdword' {
		return 4
	}
	if base == 'long' || base == 'f64' || base == 'qword' || base == 'sqword' {
		return 8
	}
	return 0
}

fn cone_first_dot(s string) int {
	mut i := 0
	for i < s.len {
		if s[i] == 46 {
			return i
		}
		i = i + 1
	}
	return -1
}

fn cone_align_unit(st SymTab, typ string, arr string) (int, int) {
	b := resolve_base_type(st, typ)
	mut a := 0
	mut unit := 0
	if b in st.struct_size {
		a = st.struct_align_max[b]
		unit = st.struct_size[b]
	} else if b in st.struct_extern {
		a = 4
		unit = 4
	} else {
		unit = st.type_bytes[b]
		if unit == 0 {
			unit = cone_type_bytes(b)
		}
		if unit == 1 {
			a = 1
		} else if unit == 2 {
			a = 2
		} else if unit == 4 {
			a = 4
		} else if unit == 8 {
			a = 8
		} else {
			a = 1
		}
	}
	if arr.len > 0 {
		n := parse_int_lit(arr) or { 0 }
		if n > 0 {
			unit = unit * int(n)
		}
	}
	if a <= 0 {
		a = 1
	}
	return a, unit
}

fn cone_compute_layout(mut prog Program, mut st SymTab) ! {
	for sd in prog.structs {
		st.struct_align[sd.name] = sd.aligned
	}
	// 成员数组长度里的 cone 立即数尽量先求值（依赖未算出布局的留文本给后续轮次）
	mut si0 := 0
	for si0 < prog.structs.len {
		mut mi0 := 0
		for mi0 < prog.structs[si0].members.len {
			al := prog.structs[si0].members[mi0].array_len
			if al.len > 0 {
				v := cone_fold_int_text(st, al) or {
					mi0 = mi0 + 1
					continue
				}
				prog.structs[si0].members[mi0].array_len = '${v}'
			}
			mi0 = mi0 + 1
		}
		si0 = si0 + 1
	}
	// 迭代算各结构体的最大对齐值（嵌套结构体互相依赖）
	mut pass := 0
	for pass < 64 {
		for sd in prog.structs {
			mut mx := 1
			for m in sd.members {
				a, _ := cone_align_unit(st, m.typ_name, m.array_len)
				if a > mx {
					mx = a
				}
			}
			st.struct_align_max[sd.name] = mx
		}
		pass = pass + 1
	}
	// 迭代算 size / 成员偏移 / padding
	pass = 0
	for pass < 64 {
		mut all_ready := true
		for sd0 in prog.structs {
			n := sd0.name
			if st.struct_size[n] > 0 {
				continue
			}
			mut off := 0
			mut ready := true
			mut pads := []PadInfo{}
			mut cur := []CurInfo{}
			mut mi := 0
			for mi < sd0.members.len {
				m := sd0.members[mi]
				a, unit := cone_align_unit(st, m.typ_name, m.array_len)
				b := resolve_base_type(st, m.typ_name)
				if (b in st.struct_size) && st.struct_size[b] == 0 {
					ready = false
				}
				if sd0.aligned && a > 1 && off % a != 0 {
					pad := a - (off % a)
					pads << PadInfo{mi: mi, nb: pad, is_tail: false}
					off = off + pad
				}
				cur << CurInfo{name: m.name, off: off, base: b, unit: unit, isarr: m.array_len.len > 0}
				off = off + unit
				mi = mi + 1
			}
			if !ready || off == 0 {
				all_ready = false
				continue
			}
			mut mx := st.struct_align_max[n]
			if mx <= 0 {
				mx = 1
			}
			if sd0.aligned && mx > 1 && off % mx != 0 {
				pad := mx - (off % mx)
				pads << PadInfo{mi: -1, nb: pad, is_tail: true}
				off = off + pad
			}
			st.struct_size[n] = off
			st.type_bytes[n] = off
			st.struct_pads[n] = pads
			for ci in cur {
				st.struct_offsets[n + '.' + ci.name] = ci.off
			}
			for ci in cur {
				if ci.isarr || !(ci.base in st.struct_size) {
					continue
				}
				pre := ci.base + '.'
				mut keys := []string{}
				for k in st.struct_offsets.keys() {
					keys << k
				}
				for k in keys {
					if k.starts_with(pre) && !(k[pre.len..].contains('.')) {
						st.struct_offsets[n + '.' + ci.name + '.' + k[pre.len..]] = ci.off + st.struct_offsets[k]
					}
				}
			}
		}
		if all_ready {
			break
		}
		pass = pass + 1
	}
	for sd in prog.structs {
		if st.struct_size[sd.name] == 0 {
			return error('第 ${sd.line} 行: 结构体 ${sd.name} 存在自引用 / 循环嵌套，无法计算大小（MASM32 不接受）；请把递归字段改成 int 指针')
		}
	}
	// 多级嵌套成员链展开
	mut p2 := 0
	for p2 < 8 {
		mut changed := false
		for sd in prog.structs {
			n := sd.name
			for m in sd.members {
				ofs := st.struct_offsets[n + '.' + m.name]
				b := resolve_base_type(st, m.typ_name)
				if !(b in st.struct_size) || m.array_len.len > 0 {
					continue
				}
				pre := b + '.'
				mut keys := []string{}
				for k in st.struct_offsets.keys() {
					keys << k
				}
				for k in keys {
					if k.starts_with(pre) && k[pre.len..].contains('.') {
						newk := n + '.' + m.name + '.' + k[pre.len..]
						if !(newk in st.struct_offsets) {
							st.struct_offsets[newk] = ofs + st.struct_offsets[k]
							changed = true
						}
					}
				}
			}
		}
		if !changed {
			break
		}
		p2 = p2 + 1
	}
}

fn cone_sizeof_of(st SymTab, name string) !i64 {
	if name.starts_with('win.') {
		return error('sizeof(${name}) 无法计算：cone 不掌握 win. 外部 MASM 结构体的字段布局')
	}
	tb := cone_type_bytes(name)
	if tb > 0 {
		return i64(tb)
	}
	b := resolve_base_type(st, name)
	tb2 := cone_type_bytes(b)
	if tb2 > 0 {
		return i64(tb2)
	}
	if (b in st.struct_size) && st.struct_size[b] > 0 {
		return i64(st.struct_size[b])
	}
	if b in st.struct_size {
		return error('sizeof(${name}) 依赖尚未计算的结构体布局')
	}
	if b in st.struct_extern {
		return error('sizeof(${name}) 无法计算：cone 不掌握 win. 外部 MASM 结构体的字段布局')
	}
	if name in st.data_bytes {
		return i64(st.data_bytes[name])
	}
	di := cone_first_dot(name)
	if di > 0 {
		base := name[..di]
		rest := name[di + 1..]
		di2 := cone_first_dot(rest)
		mut first := rest
		if di2 > 0 {
			first = rest[..di2]
		}
		if base in st.struct_size {
			key := base + '.' + first
			if key in st.struct_mtype {
				typ := st.struct_mtype[key]
				arr := st.struct_marray[key]
				_, unit := cone_align_unit(st, typ, arr)
				return i64(unit)
			}
		}
		mut vt := st.global_type[base]
		for k, v in st.local_type {
			if k.ends_with('::' + base) {
				vt = v
				break
			}
		}
		mut vb := ''
		if vt.len > 0 {
			vb = resolve_base_type(st, vt)
		}
		if vb.len > 0 && (vb in st.struct_size) {
			key := vb + '.' + first
			if key in st.struct_mtype {
				typ := st.struct_mtype[key]
				arr := st.struct_marray[key]
				_, unit := cone_align_unit(st, typ, arr)
				return i64(unit)
			}
		}
		return error('sizeof(${name}) 无法计算：${base} 不是 cone 结构体类型 / 结构体变量')
	}
	if name in st.globals {
		typ := st.global_type[name]
		bb := resolve_base_type(st, typ)
		if bb in st.struct_size {
			return i64(st.struct_size[bb])
		}
		if bb in st.struct_extern {
			return i64(4)
		}
		if st.global_kind[name] == 'data' {
			return i64(st.data_bytes[name])
		}
		mut t := st.type_bytes[bb]
		if t == 0 {
			t = cone_type_bytes(bb)
		}
		if t == 0 {
			t = 4
		}
		return i64(t)
	}
	for k, v in st.local_type {
		if k.ends_with('::' + name) {
			bb := resolve_base_type(st, v)
			if bb in st.struct_size {
				return i64(st.struct_size[bb])
			}
			mut t := st.type_bytes[bb]
			if t == 0 {
				t = cone_type_bytes(bb)
			}
			if t == 0 {
				t = 4
			}
			return i64(t)
		}
	}
	if name in st.equ_values {
		return parse_int_lit(st.equ_values[name]) or { i64(0) }
	}
	return error('sizeof(${name}) 无法计算：${name} 不是已知类型 / 变量 / 数据定义 / 结构体')
}

fn cone_is_start(c u8) bool {
	return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 63 || c == 64
}

fn cone_is_cont(c u8) bool {
	return cone_is_start(c) || (c >= 48 && c <= 57)
}

fn cone_is_bound(c u8) bool {
	return cone_is_cont(c) || c == 36 || c == 37
}

fn cone_hex(c u8) bool {
	return (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
}

fn parse_hex(s string) !i64 {
	mut v := i64(0)
	mut i := 0
	for i < s.len {
		c := s[i]
		mut d := 0
		if c >= 48 && c <= 57 {
			d = int(c) - 48
		} else if c >= 97 && c <= 102 {
			d = int(c) - 97 + 10
		} else if c >= 65 && c <= 70 {
			d = int(c) - 65 + 10
		} else {
			return error('非法十六进制 ${s}')
		}
		v = v * 16 + i64(d)
		i = i + 1
	}
	return v
}

fn cone_skip_ws(s string, i0 int) int {
	mut i := i0
	for i < s.len {
		c := s[i]
		if c == 32 || c == 9 || c == 10 || c == 13 {
			i = i + 1
		} else {
			break
		}
	}
	return i
}

// cone_subst_sizeof：把文本里的 sizeof(NAME) 换成 cone 算出的字节数。
fn cone_subst_sizeof(st SymTab, text string) string {
	mut out := []string{}
	mut i := 0
	for i < text.len {
		if i + 6 <= text.len && text[i..i + 6].to_lower() == 'sizeof' && (i == 0 || !cone_is_bound(text[i - 1])) {
			mut j := cone_skip_ws(text, i + 6)
			if j < text.len && text[j] == 40 {
				j = cone_skip_ws(text, j + 1)
				ns := j
				for j < text.len && (cone_is_cont(text[j]) || text[j] == 46) {
					j = j + 1
				}
				nm := text[ns..j]
				j = cone_skip_ws(text, j)
				if j < text.len && text[j] == 41 && nm.len > 0 {
					v := cone_sizeof_of(st, nm) or {
						out << text[i..j + 1]
						i = j + 1
						continue
					}
					out << '${v}'
					i = j + 1
					continue
				}
			}
		}
		out << text[i..i + 1]
		i = i + 1
	}
	return out.join('')
}

// cone_subst_imm：把文本里的 sizeof(...) / cone struct `Type.member` / 折叠 equ
// 替换成立即数文本；win. 外部结构体成员不替换（透传给 MASM32）。
fn cone_subst_imm(st SymTab, text string, allow_equ bool) string {
	s := cone_subst_sizeof(st, text)
	mut out := []string{}
	mut i := 0
	for i < s.len {
		if !cone_is_start(s[i]) || (i > 0 && cone_is_bound(s[i - 1])) {
			out << s[i..i + 1]
			i = i + 1
			continue
		}
		mut j := i
		for j < s.len && cone_is_cont(s[j]) {
			j = j + 1
		}
		for j < s.len && s[j] == 46 && j + 1 < s.len && cone_is_start(s[j + 1]) {
			j = j + 1
			for j < s.len && cone_is_cont(s[j]) {
				j = j + 1
			}
		}
		if j < s.len && (cone_is_cont(s[j]) || s[j] == 36) {
			out << s[i..i + 1]
			i = i + 1
			continue
		}
		w := s[i..j]
		if w.starts_with('win.') {
			out << w
		} else if allow_equ && !(w.contains('.')) && (w in st.equ_values) {
			out << st.equ_values[w]
		} else if w.contains('.') {
			parts := w.split('.')
			mut done := false
			mut cut := parts.len
			for cut > 0 {
				key := parts[..cut].join('.')
				if key in st.struct_offsets {
					rest := parts[cut..].join('.')
					mut r := '${st.struct_offsets[key]}'
					if rest.len > 0 {
						r = r + '.' + rest
					}
					out << r
					done = true
					break
				}
				cut = cut - 1
			}
			if !done {
				out << w
			}
		} else {
			out << w
		}
		i = j
	}
	return out.join('')
}

fn (mut e IntEval) skip() {
	for e.pos < e.s.len {
		c := e.s[e.pos]
		if c == 32 || c == 9 || c == 10 || c == 13 {
			e.pos = e.pos + 1
		} else {
			break
		}
	}
}

fn (mut e IntEval) peek2(a u8, b u8) bool {
	return e.pos + 1 < e.s.len && e.s[e.pos] == a && e.s[e.pos + 1] == b
}

fn (mut e IntEval) parse_primary() !i64 {
	e.skip()
	if e.pos >= e.s.len {
		return error('编译期常量表达式缺少操作数')
	}
	if e.s[e.pos] == 40 {
		e.pos = e.pos + 1
		v := e.parse_or() or { return error(err.msg()) }
		e.skip()
		if e.pos >= e.s.len || e.s[e.pos] != 41 {
			return error('编译期常量表达式缺少 )')
		}
		e.pos = e.pos + 1
		return v
	}
	st := e.pos
	if e.s[e.pos] == 48 && e.pos + 1 < e.s.len && (e.s[e.pos + 1] == 120 || e.s[e.pos + 1] == 88) {
		e.pos = e.pos + 2
		ds := e.pos
		for e.pos < e.s.len && cone_hex(e.s[e.pos]) {
			e.pos = e.pos + 1
		}
		if e.pos == ds {
			return error('0x 缺少十六进制数字')
		}
		return parse_hex(e.s[ds..e.pos]) or { return error(err.msg()) }
	}
	for e.pos < e.s.len && (cone_is_cont(e.s[e.pos]) || e.s[e.pos] == 46) {
		e.pos = e.pos + 1
	}
	tok := e.s[st..e.pos]
	if tok.len == 0 {
		return error('编译期常量表达式非法字符')
	}
	return parse_int_lit(tok) or { return error('编译期常量 ${tok} 不是合法整数') }
}

fn (mut e IntEval) parse_unary() !i64 {
	e.skip()
	if e.pos < e.s.len {
		c := e.s[e.pos]
		if c == 45 {
			e.pos = e.pos + 1
			v := e.parse_unary() or { return error(err.msg()) }
			return -v
		}
		if c == 43 {
			e.pos = e.pos + 1
			return e.parse_unary() or { return error(err.msg()) }
		}
		if c == 126 {
			e.pos = e.pos + 1
			v := e.parse_unary() or { return error(err.msg()) }
			return -v - 1
		}
	}
	return e.parse_primary() or { return error(err.msg()) }
}

fn (mut e IntEval) parse_mul() !i64 {
	mut v := e.parse_unary() or { return error(err.msg()) }
	for {
		e.skip()
		if e.pos >= e.s.len {
			break
		}
		c := e.s[e.pos]
		if c != 42 && c != 47 && c != 37 {
			break
		}
		e.pos = e.pos + 1
		r := e.parse_unary() or { return error(err.msg()) }
		if c == 42 {
			v = v * r
		} else if c == 47 {
			if r == 0 {
				return error('编译期常量表达式除零')
			}
			if v % r != 0 {
				return error('编译期常量表达式的除法结果不是整数')
			}
			v = v / r
		} else {
			// cone 0.9.1：编译期文本求值器支持 %（截断除法一致）
			if r == 0 {
				return error('编译期常量表达式取模除零')
			}
			v = v - (v / r) * r
		}
	}
	return v
}

fn (mut e IntEval) parse_add() !i64 {
	mut v := e.parse_mul() or { return error(err.msg()) }
	for {
		e.skip()
		if e.pos >= e.s.len {
			break
		}
		c := e.s[e.pos]
		if c != 43 && c != 45 {
			break
		}
		e.pos = e.pos + 1
		r := e.parse_mul() or { return error(err.msg()) }
		if c == 43 {
			v = v + r
		} else {
			v = v - r
		}
	}
	return v
}

fn (mut e IntEval) parse_shift() !i64 {
	mut v := e.parse_add() or { return error(err.msg()) }
	for {
		e.skip()
		if e.pos >= e.s.len {
			break
		}
		if e.peek2(60, 60) {
			e.pos = e.pos + 2
			r := e.parse_add() or { return error(err.msg()) }
			v = bit_shl(v, r)
		} else if e.peek2(62, 62) {
			e.pos = e.pos + 2
			r := e.parse_add() or { return error(err.msg()) }
			v = bit_shr(v, r)
		} else {
			break
		}
	}
	return v
}

fn (mut e IntEval) parse_and() !i64 {
	mut v := e.parse_shift() or { return error(err.msg()) }
	for {
		e.skip()
		if e.pos >= e.s.len || e.s[e.pos] != 38 {
			break
		}
		if e.peek2(38, 38) {
			break
		}
		e.pos = e.pos + 1
		r := e.parse_shift() or { return error(err.msg()) }
		v = v & r
	}
	return v
}

fn (mut e IntEval) parse_xor() !i64 {
	mut v := e.parse_and() or { return error(err.msg()) }
	for {
		e.skip()
		if e.pos >= e.s.len || e.s[e.pos] != 94 {
			break
		}
		e.pos = e.pos + 1
		r := e.parse_and() or { return error(err.msg()) }
		v = v ^ r
	}
	return v
}

fn (mut e IntEval) parse_or() !i64 {
	mut v := e.parse_xor() or { return error(err.msg()) }
	for {
		e.skip()
		if e.pos >= e.s.len || e.s[e.pos] != 124 {
			break
		}
		if e.peek2(124, 124) {
			break
		}
		e.pos = e.pos + 1
		r := e.parse_xor() or { return error(err.msg()) }
		v = v | r
	}
	return v
}

fn cone_eval_int(text string) !i64 {
	mut e := IntEval{s: text, pos: 0}
	v := e.parse_or() or { return error(err.msg()) }
	e.skip()
	if e.pos != e.s.len {
		return error('编译期常量表达式尾部有多余内容：${text}')
	}
	return v
}

fn cone_fold_int_text(st SymTab, text string) !i64 {
	t := cone_subst_imm(st, text, true)
	mut k := 0
	for k < t.len {
		c := t[k]
		ok := (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102) ||
			c == 120 || c == 88 || c == 104 || c == 72 ||
			c == 43 || c == 45 || c == 42 || c == 47 || c == 40 || c == 41 ||
			c == 124 || c == 38 || c == 94 || c == 60 || c == 62 ||
			c == 32 || c == 9 || c == 10 || c == 13 || c == 126 || c == 37 // % cone 0.9.1
		if !ok {
			return error('数组长度 / 编译期常量 ${text} 不是合法 cone 立即数表达式（展开为 ${t}）')
		}
		k = k + 1
	}
	return cone_eval_int(t) or {
		return error('数组长度 / 编译期常量 ${text} 求值失败（MASM 侧地址立即数不能用于 cone 编译期计算）')
	}
}

fn cone_data_str_len(t string) int {
	if is_wide_lit_v(t) { return wide_lit_masm_v(t).split(',').len }
	if t.len >= 2 && (t[0] == 34 || t[0] == 39) && t[t.len - 1] == t[0] {
		return t.len - 2
	}
	return t.len
}

fn cone_fold_immediates(mut prog Program, mut st SymTab, strict bool) ! {
	mut round := 0
	for round < 64 {
		mut changed := false
		mut ei := 0
		for ei < prog.exprs.len {
			k := prog.exprs[ei].kind
			if k == ExprKind.expr_sizeof {
				v := cone_sizeof_of(st, prog.exprs[ei].text) or {
					ei = ei + 1
					continue
				}
				prog.exprs[ei].kind = ExprKind.expr_num
				prog.exprs[ei].text = '${v}'
				changed = true
			} else if k == ExprKind.expr_member && (prog.exprs[ei].member_base in st.struct_size) {
				key := prog.exprs[ei].member_base + '.' + prog.exprs[ei].member_path
				if key in st.struct_offsets {
					prog.exprs[ei].kind = ExprKind.expr_num
					prog.exprs[ei].text = '${st.struct_offsets[key]}'
					changed = true
				}
			} else if k == ExprKind.expr_ident && !prog.exprs[ei].is_reg && !prog.exprs[ei].is_win_sym && !prog.exprs[ei].is_struct_lit {
				if prog.exprs[ei].text in st.equ_values {
					prog.exprs[ei].kind = ExprKind.expr_num
					prog.exprs[ei].text = st.equ_values[prog.exprs[ei].text]
					changed = true
				}
			}
			ei = ei + 1
		}
		// equ 二次折叠：parser 阶段没折叠的（依赖结构体布局的）现在可求值
		mut qi := 0
		for qi < prog.equs.len {
			if !prog.equs[qi].is_folded && !prog.equs[qi].is_raw && prog.equs[qi].items.len == 1 {
				it := prog.equs[qi].items[0]
				mut has_str := false
				if it >= 0 && it < prog.exprs.len && prog.exprs[it].kind == ExprKind.expr_str {
					has_str = true
				}
				if !has_str && it >= 0 && it < prog.exprs.len {
					fr := try_fold_e(prog.exprs, it, st.equ_values)
					if fr.ok {
						ft := folded_text_of(prog.exprs, it, fr.value)
						prog.equs[qi].is_folded = true
						prog.equs[qi].folded_text = ft
						st.equ_values[prog.equs[qi].name] = ft
						prog.folded_equs[prog.equs[qi].name] = ft
						changed = true
					}
				}
			}
			qi = qi + 1
		}
		// 数组维度文本求值成整数
		mut si := 0
		for si < prog.structs.len {
			mut mi := 0
			for mi < prog.structs[si].members.len {
				al := prog.structs[si].members[mi].array_len
				if al.len > 0 {
					v := cone_fold_int_text(st, al) or {
						mi = mi + 1
						continue
					}
					if al != '${v}' {
						prog.structs[si].members[mi].array_len = '${v}'
						changed = true
					}
				}
				mi = mi + 1
			}
			si = si + 1
		}
		mut vi := 0
		for vi < prog.vars.len {
			al := prog.vars[vi].array_len
			if al.len > 0 {
				v := cone_fold_int_text(st, al) or {
					vi = vi + 1
					continue
				}
				if al != '${v}' {
					prog.vars[vi].array_len = '${v}'
					changed = true
				}
			}
			vi = vi + 1
		}
		mut fi := 0
		for fi < prog.funcs.len {
			mut bi := 0
			for bi < prog.funcs[fi].body.len {
				al := prog.funcs[fi].body[bi].local_array_len
				if al.len > 0 {
					v := cone_fold_int_text(st, al) or {
						bi = bi + 1
						continue
					}
					if al != '${v}' {
						prog.funcs[fi].body[bi].local_array_len = '${v}'
						changed = true
					}
				}
				bi = bi + 1
			}
			fi = fi + 1
		}
		if !changed {
			break
		}
		round = round + 1
	}
	// cone 0.9.1：加强编译期计算 —— 纯 cone 立即数构成的算术/位运算子树
	// 直接折叠成数字；含 win 块符号 / $ / addr / 变量 / 调用 / 浮点的表达式
	// try_fold 求值失败，自动保留给 MASM32 侧（不参与 cone 编译期计算）。
	mut cpass := 0
	for cpass < 64 {
		mut cch := false
		mut cei := 0
		for cei < prog.exprs.len {
			ck := prog.exprs[cei].kind
			mut ctry := false
			if ck == ExprKind.expr_bin && !is_cond_op(prog.exprs[cei].text) {
				ctry = true
			}
			if ck == ExprKind.expr_neg && (prog.exprs[cei].text == '-' || prog.exprs[cei].text == '~') {
				ctry = true
			}
			if ctry {
				cfr := try_fold(prog, cei)
				if cfr.ok {
					prog.exprs[cei].kind = ExprKind.expr_num
					prog.exprs[cei].text = '${cfr.value}'
					prog.exprs[cei].is_float_hint = false
					cch = true
				}
			}
			cei = cei + 1
		}
		if !cch {
			break
		}
		cpass = cpass + 1
	}
	if strict {
		mut ei := 0
		for ei < prog.exprs.len {
			if prog.exprs[ei].kind == ExprKind.expr_sizeof {
				return error('sizeof(${prog.exprs[ei].text}) 无法计算：${prog.exprs[ei].text} 不是已知类型 / 变量 / 数据定义 / 结构体')
			}
			ei = ei + 1
		}
	}
}

fn analyze(prog0 Program, src_path string, x64_mode bool) !SymTab {
	// cone 0.9prelease：局部 mut 副本；slice / map 底层共享，折叠改写对 main 的 prog 可见。
	mut prog := prog0
	mut st := SymTab{
		globals:      map[string]bool{}
		global_kind:  map[string]string{}
		global_type:  map[string]string{}
		local_type:   map[string]string{}
		declared:     map[string]bool{}
		defined:      map[string]bool{}
		imports:      map[string]bool{}
		typedefs:     map[string]bool{}
		typedef_base: map[string]string{}
		type_masm:    map[string]string{}
		type_dir:     map[string]string{}
		type_bytes:   map[string]int{}
		name_maps:    map[string]NameInfo{}
		func_convs:   map[string]CallConv{}
		equ_aliases:  map[string]string{}
		equ_values:   map[string]string{}
		decl_line:    map[string]int{}
		decl_pos:     map[string]int{}
		win_bare:     map[string]bool{}
		macros:       map[string]bool{}
		asm64_cache:  map[string][]string{}
		x64_mode:     x64_mode
		proto_sig:    map[string]string{}
		def_sig:      map[string]string{}
		proto_conv:   map[string]CallConv{}
		struct_names:   map[string]bool{}
		struct_members: map[string][]string{}
		struct_mtype:   map[string]string{}
		struct_marray:  map[string]string{}
		struct_size:    map[string]int{}
		struct_extern:  map[string]bool{}
		struct_align:     map[string]bool{}
		struct_align_max: map[string]int{}
		struct_offsets:   map[string]int{}
		struct_pads:      map[string][]PadInfo{}
		data_bytes:       map[string]int{}
	}

	// cone 0.83：seg 段名唯一；defined 宏名登记为可调用目标（定义总在头部，免顺序检查）。
	mut seg_names := map[string]bool{}
	for sg in prog.segs {
		if sg.name in seg_names {
			return error('第 ${sg.line} 行: seg 段名 "${sg.name}" 重复（cone 0.83 约定 seg 不能重名）')
		}
		seg_names[sg.name] = true
	}
	for m in prog.macros {
		if m.name in st.macros {
			return error('第 ${m.line} 行: 宏 ${m.name} 重复定义（defined 宏名必须唯一）')
		}
		st.macros[m.name] = true
		st.declared[m.name] = true
	}

	// cone 0.6 fix2：win{...} 批量登记的 MASM 侧符号，全文件生效。
	for wn in prog.win_names {
		st.win_bare[wn] = true
	}
	// cone 0.7：数值 equ 已在 parser 侧展开成立即数；这里存一份给 asm %NAME 用。
	for ek, ev in prog.folded_equs {
		st.equ_values[ek] = ev
	}
	// cone 0.7：SEH 异常码传递变量。编译器把它定义在 .data? 段第一个位置，
	// 视为特殊已定义标识符（4 字节）；用户重复声明会被下面的「重复定义」检查拦下。
	st.globals['fuck'] = true
	st.global_kind['fuck'] = 'var'
	st.global_type['fuck'] = 'int'
	st.declared['fuck'] = true

	// 1) 内置类型表
	st.type_masm['byte'] = 'BYTE'
	st.type_masm['word'] = 'WORD'
	st.type_masm['int'] = 'DWORD'
	st.type_masm['long'] = 'QWORD'
	st.type_masm['f32'] = 'REAL4'
	st.type_masm['f64'] = 'REAL8'
	st.type_dir['byte'] = 'db'
	st.type_dir['word'] = 'dw'
	st.type_dir['int'] = 'dd'
	st.type_dir['long'] = 'dq'
	st.type_dir['f32'] = 'REAL4'
	st.type_dir['f64'] = 'REAL8'
	st.type_bytes['byte'] = 1
	st.type_bytes['word'] = 2
	st.type_bytes['int'] = 4
	st.type_bytes['long'] = 8
	st.type_bytes['f32'] = 4
	st.type_bytes['f64'] = 8

	// 2) typedef
	for td in prog.typedefs {
		if td.name in st.type_masm {
			return error('第 ${td.line} 行: 类型 ${td.name} 与内置类型或已有 typedef 冲突')
		}
		if !(td.base_type_name in st.type_masm) {
			return error('第 ${td.line} 行: typedef ${td.name} 的底层类型 ${td.base_type_name} 未知')
		}
		st.typedefs[td.name] = true
		st.typedef_base[td.name] = td.base_type_name
		st.type_masm[td.name] = td.name
		st.type_dir[td.name] = st.type_dir[td.base_type_name]
		st.type_bytes[td.name] = st.type_bytes[td.base_type_name]
	}

	// 2.4) cone 0.4 fix：登记 win.XXX 外部结构体类型（MASM 侧已定义，cone 不生成 STRUCT）
	mut win_types := []string{}
	for sd in prog.structs {
		for m in sd.members {
			if is_win_type(m.typ_name) {
				win_types << m.typ_name
			}
		}
	}
	for v in prog.vars {
		if is_win_type(v.typ_name) {
			win_types << v.typ_name
		}
	}
	for pr in prog.protos {
		for pm in pr.params {
			if is_win_type(pm.typ_name) {
				win_types << pm.typ_name
			}
		}
	}
	for f in prog.funcs {
		for pm in f.params {
			if is_win_type(pm.typ_name) {
				win_types << pm.typ_name
			}
		}
		for stx in f.body {
			if stx.kind == StmtKind.st_local && is_win_type(stx.local_type) {
				win_types << stx.local_type
			}
		}
	}
	// cone 0.6：结构体常量 win.Type{...} 可能只在实参里出现，也要登记成外部结构体类型
	for e in prog.exprs {
		if e.is_struct_lit && is_win_type(e.lit_type) {
			win_types << e.lit_type
		}
		// cone 0.6 fix3：RECT.left / win.RECT.left 字段偏移常量，即使没有任何
		// 类型位置用到该外部结构体，也要登记成 struct_extern 才能校验放行。
		if e.kind == ExprKind.expr_member && is_win_type(e.member_base) {
			win_types << e.member_base
		}
	}
	for w in win_types {
		if !(w in st.type_masm) {
			st.type_masm[w] = win_masm_name(w)
			st.type_dir[w] = win_masm_name(w)
			st.type_bytes[w] = 4
			st.struct_extern[w] = true
		}
	}

	// 2.5) cone 0.4：结构体定义登记为类型（MASM STRUCT / ENDS）
	for sd in prog.structs {
		if sd.name in st.type_masm {
			return error('第 ${sd.line} 行: 结构体 ${sd.name} 与内置类型或 typedef 别名冲突')
		}
		if sd.name in st.globals {
			return error('第 ${sd.line} 行: 全局符号 ${sd.name} 重复定义')
		}
		if !x64_mode && is_reserved_word(sd.name) {
			return error('第 ${sd.line} 行: `${sd.name}` 是 MASM32 保留标识符，不能作为 cone 结构体名')
		}
		st.globals[sd.name] = true
		st.global_kind[sd.name] = 'struct'
		st.struct_names[sd.name] = true
		st.struct_size[sd.name] = 0
		st.type_masm[sd.name] = sd.name
		st.type_dir[sd.name] = sd.name
		st.type_bytes[sd.name] = 0
		mut mnames := []string{}
		for m in sd.members {
			if m.name in mnames {
				return error('第 ${m.line} 行: 结构体 ${sd.name} 的成员 ${m.name} 重复')
			}
			if !x64_mode && is_reserved_word(m.name) {
				return error('第 ${m.line} 行: `${m.name}` 是 MASM32 保留标识符，不能作为结构体成员名')
			}
			mnames << m.name
			k := sd.name + '.' + m.name
			st.struct_mtype[k] = m.typ_name
			st.struct_marray[k] = m.array_len
			if m.array_len.len > 0 {
				cone_fold_int_text(st, m.array_len) or {
					return error('第 ${m.line} 行: 结构体 ${sd.name} 成员 ${m.name} 的数组长度 ${m.array_len} 不是合法 cone 立即数表达式')
				}
			}
		}
		st.struct_members[sd.name] = mnames.clone()
	}
	// 成员类型校验（结构体可前向引用后面定义的结构体）
	for sd in prog.structs {
		for m in sd.members {
			b := resolve_base_type(st, m.typ_name)
			if !(b in st.type_masm) {
				return error('第 ${m.line} 行: 结构体 ${sd.name} 成员 ${m.name} 的类型 ${m.typ_name} 未知（可用内置类型 / typedef / 其他结构体）')
			}
		}
	}
	// cone 0.9prelease：Windows ABI 对齐布局 + 编译期立即数统一折叠
	cone_compute_layout(mut prog, mut st) or { return error(err.msg()) }
	cone_fold_immediates(mut prog, mut st, false) or { return error(err.msg()) }

	// 3) 全局符号收集
	for d in prog.data {
		if d.name in st.globals {
			return error('第 ${d.line} 行: 全局符号 ${d.name} 重复定义')
		}
		if !x64_mode && is_reserved_word(d.name) {
			return error('第 ${d.line} 行: `${d.name}` 是 MASM32 保留标识符，不能作为 cone 标识符')
		}
		st.globals[d.name] = true
		st.global_kind[d.name] = 'data'
		st.global_type[d.name] = 'byte'
	}
	// cone 0.9prelease：数据字节数组的 sizeof（字符串按原文长度，数值项按 1 字节）
	for d in prog.data {
		mut nb := 0
		for it in d.items {
			if it >= 0 && it < prog.exprs.len && prog.exprs[it].kind == ExprKind.expr_str {
				nb = nb + cone_data_str_len(prog.exprs[it].text)
			} else {
				nb = nb + 1
			}
		}
		st.data_bytes[d.name] = nb
	}
	for v in prog.vars {
		if v.name in st.globals {
			return error('第 ${v.line} 行: 全局符号 ${v.name} 重复定义')
		}
		if !x64_mode && is_reserved_word(v.name) {
			return error('第 ${v.line} 行: `${v.name}` 是 MASM32 保留标识符，不能作为 cone 标识符')
		}
		if !(resolve_base_type(st, v.typ_name) in st.type_masm) {
			return error('第 ${v.line} 行: 变量 ${v.name} 的类型 ${v.typ_name} 未知（可用内置类型 / typedef / 结构体）')
		}
		if v.has_init_list {
			b := resolve_base_type(st, v.typ_name)
			is_cone_struct := b in st.struct_size
			is_win_struct := b in st.struct_extern
			if !is_cone_struct && !is_win_struct {
				return error('第 ${v.line} 行: 只有结构体类型变量能写 ={...} 初始化列表；${v.name} 的类型 ${v.typ_name} 不是结构体')
			}
			if v.array_len.len > 0 {
				return error('第 ${v.line} 行: cone 暂不支持结构体数组变量的初始化列表（${v.name} ${v.typ_name}[${v.array_len}]）')
			}
			// cone 0.6：win.XXX 的字段布局由 MASM32 侧掌握，cone 不校验项数；
			// 只保证每一项是编译期常量 / ?，成员个数与类型交给 ml 裁决。
			if is_cone_struct {
				mnames := st.struct_members[b]
				if v.init_items.len > mnames.len {
					return error('第 ${v.line} 行: 结构体 ${b} 只有 ${mnames.len} 个成员，但 ${v.name} 的初始化列表有 ${v.init_items.len} 项')
				}
			}
			mut ki := 0
			for ki < v.init_items.len {
				if v.init_items[ki] >= 0 {
					validate_equ_expr(prog, st, v.init_items[ki], '${v.name} (${v.typ_name})', v.line) or { return error(err.msg()) }
				}
				ki = ki + 1
			}
		}
		st.globals[v.name] = true
		if v.is_const {
			st.global_kind[v.name] = 'const'
		} else {
			st.global_kind[v.name] = 'var'
		}
		st.global_type[v.name] = resolve_base_type(st, v.typ_name)
	}
	for eq in prog.equs {
		if eq.name in st.globals {
			return error('第 ${eq.line} 行: 全局符号 ${eq.name} 重复定义')
		}
		if !x64_mode && is_reserved_word(eq.name) {
			return error('第 ${eq.line} 行: `${eq.name}` 是 MASM32 保留标识符，不能作为 cone 标识符')
		}
		st.globals[eq.name] = true
		st.global_kind[eq.name] = 'equ'
		st.global_type[eq.name] = 'int'
	}
	for td in prog.typedefs {
		if td.name in st.globals {
			return error('第 ${td.line} 行: 全局符号 ${td.name} 重复定义')
		}
		st.globals[td.name] = true
		st.global_kind[td.name] = 'typedef'
	}
	for pr in prog.protos {
		sig := sig_of(st, pr.params)
		if pr.name in st.global_kind {
			k := st.global_kind[pr.name]
			if k == 'proto' {
				if st.proto_sig[pr.name] != sig {
					return error('第 ${pr.line} 行: func ${pr.name} 重复声明的形参与第 ${st.decl_line[pr.name]} 行的声明不一致')
				}
				if !conv_compatible(st.proto_conv[pr.name], pr.conv) {
					return error('第 ${pr.line} 行: func ${pr.name} 重复声明的调用约定与之前的声明不一致')
				}
			} else if k == 'func' {
				if st.def_sig[pr.name] != sig {
					return error('第 ${pr.line} 行: func ${pr.name} 声明的形参类型与实际 def 定义不一致')
				}
				if !conv_compatible(st.func_convs[pr.name], pr.conv) {
					return error('第 ${pr.line} 行: func ${pr.name} 声明的调用约定与实际 def 定义不一致')
				}
			} else {
				return error('第 ${pr.line} 行: 全局符号 ${pr.name} 已被数据 / 变量占用，不能再声明函数')
			}
		} else {
			st.globals[pr.name] = true
			st.global_kind[pr.name] = 'proto'
			st.proto_sig[pr.name] = sig
			st.proto_conv[pr.name] = pr.conv
			if !(pr.name in st.func_convs) {
				st.func_convs[pr.name] = pr.conv
			}
		}
		reg_ret(mut st, pr.name, pr.ret_type, pr.line) or { return error(err.msg()) }
		st.declared[pr.name] = true
		if !(pr.name in st.decl_line) || pr.line < st.decl_line[pr.name] {
			st.decl_line[pr.name] = pr.line
		}
		if !(pr.name in st.decl_pos) || pr.pos < st.decl_pos[pr.name] {
			st.decl_pos[pr.name] = pr.pos
		}
	}
	for f in prog.funcs {
		sig := sig_of(st, f.params)
		if f.name in st.global_kind {
			k := st.global_kind[f.name]
			if k == 'func' {
				return error('第 ${f.line} 行: 函数 ${f.name} 重复定义')
			}
			if k == 'proto' {
				if st.proto_sig[f.name] != sig {
					return error('第 ${f.line} 行: def ${f.name} 的形参与第 ${st.decl_line[f.name]} 行 func 声明不一致')
				}
				if !conv_compatible(st.func_convs[f.name], f.conv) {
					return error('第 ${f.line} 行: def ${f.name} 的调用约定与第 ${st.decl_line[f.name]} 行 func 声明不一致')
				}
			} else {
				return error('第 ${f.line} 行: 全局符号 ${f.name} 已被数据 / 变量占用，不能再定义函数')
			}
		} else {
			st.globals[f.name] = true
		}
		st.global_kind[f.name] = 'func'
		reg_ret(mut st, f.name, f.ret_type, f.line) or { return error(err.msg()) }
		st.def_sig[f.name] = sig
		st.defined[f.name] = true
		st.func_convs[f.name] = f.conv
		if !(f.name in st.decl_line) || f.line < st.decl_line[f.name] {
			st.decl_line[f.name] = f.line
		}
		if !(f.name in st.decl_pos) || f.pos < st.decl_pos[f.name] {
			st.decl_pos[f.name] = f.pos
		}
	}
	for imp in prog.imports {
		if imp.kind == ImportKind.ik_dll {
			st.imports[imp.module_name] = true
		}
	}

	// 3.5) equ 别名在 cone 侧生效
	// print equ <win.crt_printf> 里 RHS 是单个标识符（去掉 win. 后为 crt_printf），
	// 把 print 登记为已知调用目标，这样 print(...) 不会报"函数未声明"，
	// 同时 x=print 之类的标识符引用也不会报"符号未定义"。
	// MASM 侧由 `print equ <crt_printf>` 完成文本替换，cone 生成的代码仍写 invoke print。
	for eq in prog.equs {
		target := equ_alias_target(prog, eq)
		if target.len == 0 {
			continue
		}
		st.equ_aliases[eq.name] = target
		// cone 0.9.3：efunc 的 cone 侧别名同样继承返回类型，接收端也能约束
		if target in st.func_ret_type {
			st.func_ret_type[eq.name] = st.func_ret_type[target]
			st.func_ret_size[eq.name] = st.func_ret_size[target]
			st.func_ret_is_struct[eq.name] = st.func_ret_is_struct[target]
		}
		st.declared[eq.name] = true
		st.func_convs[eq.name] = CallConv.cc_default
		if !(eq.name in st.decl_line) || eq.line < st.decl_line[eq.name] {
			st.decl_line[eq.name] = eq.line
		}
		if !(eq.name in st.decl_pos) || eq.pos < st.decl_pos[eq.name] {
			st.decl_pos[eq.name] = eq.pos
		}
		// 若目标是 cone 里已声明/定义的函数，沿用它的调用约定
		if target in st.func_convs {
			st.func_convs[eq.name] = st.func_convs[target]
		}
	}

	// 4) cone 0.8prelease：include 名字校验 + 把 .lib 的库名登记成可调用模块前缀。
	//    `include os.lib` / `include os` 都会链接 os.lib，因此允许写 `os.print(...)`。
	//    `include xxx.inc` 只带 .inc 不登记前缀（其函数请用 win.xxx）。
	for inc in prog.includes {
		if !x64_mode && is_reserved_word(inc.name) {
			return error('第 ${inc.line} 行: `${inc.name}` 是 MASM32 保留标识符，不能用作 include 名字')
		}
		if inc.lib_file.len > 0 {
			mut prefix := inc.name
			mut pi := 0
			for pi < prefix.len {
				if prefix[pi] == 46 {
					prefix = prefix[..pi]
					break
				}
				pi = pi + 1
			}
			st.imports[prefix] = true
		}
	}

	// 5) 类型合法性 + 数据初值 + equ 项检查
	for pr in prog.protos {
		mut va_pos := -1
		for qi := 0; qi < pr.params.len; qi++ {
			if pr.params[qi].typ_name == 'vararg' { va_pos = qi }
		}
		if va_pos >= 0 && va_pos != pr.params.len - 1 {
			return error('第 ${pr.line} 行: func ${pr.name} 的 :vararg 必须是最后一项')
		}
		for pm in pr.params {
			if pm.typ_name == 'vararg' { continue }
			if !(pm.typ_name in st.type_masm) {
				return error('第 ${pm.line} 行: func ${pr.name} 的参数类型 ${pm.typ_name} 未知')
			}
		}
	}
	for f in prog.funcs {
		for pm in f.params {
			if pm.typ_name == 'vararg' {
				return error('第 ${pm.line} 行: def ${f.name} 不支持 :vararg；只有 func 声明可写，且必须是最后一项')
			}
		}
	}
	for eq in prog.equs {
		// <...> 是 MASM 的文本 equate，内部按原文透传，cone 不做表达式校验
		if eq.is_raw {
			continue
		}
		// 单标识符别名（含 win.xxx）指向的外部符号 cone 侧本来就不认识，
		// 交给 MASM 的 equ 文本替换处理，不做"标识符必须已定义"校验。
		if equ_alias_target(prog, eq).len > 0 {
			continue
		}
		if eq.items.len == 0 {
			return error('第 ${eq.line} 行: ${eq.name} equ 后没有任何常量项')
		}
		for item_idx in eq.items {
			validate_equ_expr(prog, st, item_idx, eq.name, eq.line) or { return error(err.msg()) }
		}
	}
	for d in prog.data {
		if d.items.len == 0 {
			return error('第 ${d.line} 行: ${d.name}: 后没有任何初值')
		}
		for idx in d.items {
			e := prog.exprs[idx]
			if e.kind == ExprKind.expr_str {
				continue
			}
			if e.kind == ExprKind.expr_num || e.kind == ExprKind.expr_neg {
				fr := try_fold(prog, idx)
				if !fr.ok {
					return error('第 ${e.line} 行: ${d.name} 的初值不是编译期整数常量')
				}
				if !fits_i64(fr.value, 1) {
					return error('第 ${e.line} 行: ${fr.value} 装不进 db 的 1 字节（cone 只检查字节数）')
				}
				continue
			}
			return error('第 ${e.line} 行: ${d.name}: 后只允许字符串或数值字面量')
		}
	}
	for v in prog.vars {
		if !(v.typ_name in st.type_masm) {
			return error('第 ${v.line} 行: 变量 ${v.name} 的类型 ${v.typ_name} 未知')
		}
		// cone 0.6：const 结构体变量用 ={...} 初始化时 init_idx 仍是 -1，但已算初始化
		if v.is_const && v.init_idx < 0 && !v.has_init_list {
			return error('第 ${v.line} 行: const ${v.name} 必须初始化')
		}
		if v.array_len.len > 0 {
			n := cone_fold_int_text(st, v.array_len) or {
				return error('第 ${v.line} 行: 数组 ${v.name} 的长度 ${v.array_len} 非法')
			}
			if n <= 0 {
				return error('第 ${v.line} 行: 数组 ${v.name} 的长度必须为正')
			}
		}
		if v.init_idx >= 0 {
			fr := try_fold(prog, v.init_idx)
			nb := st.type_bytes[v.typ_name]
			if fr.ok {
				if !fits_i64(fr.value, nb) {
					return error('第 ${v.line} 行: ${fr.value} 装不进 ${nb} 字节的 ${v.typ_name}')
				}
			} else {
				raw := render_raw(prog, v.init_idx)
				mut is_quoted := false
				if raw.len > 0 && (raw[0] == 34 || raw[0] == 39) {
					is_quoted = true
				}
				if !is_float_lit(raw) && !is_quoted {
					return error('第 ${v.line} 行: ${v.name} 的初值必须是编译期常量表达式（或浮点/字符串字面量）')
				}
			}
		}
	}

	// 5.8) cone 0.6：结构体常量 Type{...} / win.Type{...}
	for e in prog.exprs {
		if !e.is_struct_lit {
			continue
		}
		b := resolve_base_type(st, e.lit_type)
		if !(b in st.struct_size) && !(b in st.struct_extern) {
			return error('第 ${e.line} 行: 结构体常量 ${e.lit_type}{...} 需要结构体类型（cone struct 或 win.MASM 结构体），实际得到 ${e.lit_type}')
		}
		if b in st.struct_size {
			mnames := st.struct_members[b]
			if e.lit_items.len > mnames.len {
				return error('第 ${e.line} 行: 结构体 ${b} 只有 ${mnames.len} 个成员，但结构体常量 ${e.lit_type}{...} 有 ${e.lit_items.len} 项')
			}
		}
		for it in e.lit_items {
			if it < 0 {
				continue
			}
			validate_equ_expr(prog, st, it, '结构体常量 ${e.lit_type}', e.line) or { return error(err.msg()) }
		}
	}

	// 6) 入口（cone 0.9.f：x64 多文件联合链接时库单元可没有 end）
	if !x64_mode {
		if !prog.has_entry {
			return error('缺少顶层 `end 函数名` 入口声明（{} 只表示 proc/endp）')
		}
		mut entry_ok := false
		if prog.entry in st.defined {
			entry_ok = true
		}
		if !entry_ok {
			return error('end ${prog.entry} 指定的入口必须是 def 定义的函数名')
		}
	}

	// 6.5) cone 0.5：顶层 asm{...} 的 %标识符 校验（无函数作用域，fname 传空串）
	for ab in prog.asms {
		check_asm_text(st, '', ab.text, ab.line) or { return error(err.msg()) }
	}

	// 7) 每个函数必须至少有一条 return；名称修饰 + 语句检查
	for f in prog.funcs {
		// cone 0.7：try/except 标记流配对 + ErrorType 编译期常量校验
		validate_try_chain(prog, st, f) or { return error(err.msg()) }
		mut has_ret := false
		for s in f.body {
			if s.kind == StmtKind.st_return {
				has_ret = true
			}
		}
		if !has_ret {
			return error('第 ${f.line} 行: 函数 ${f.name} 没有任何 return 语句（cone 0.2 完善版起 return 必须带表达式）')
		}

		mut used := map[string]bool{}
		mut scope := map[string]bool{}

		for pm in f.params {
			if pm.typ_name == 'vararg' { continue }
			if pm.name in scope {
				return error('第 ${pm.line} 行: 函数 ${f.name} 的形参 ${pm.name} 重复')
			}
			scope[pm.name] = true
			if !(pm.typ_name in st.type_masm) {
				return error('第 ${pm.line} 行: 形参 ${pm.name} 的类型 ${pm.typ_name} 未知')
			}
			m := mangle_name(pm.name, '_', st.globals, used)
			used[m] = true
			st.name_maps[name_key(f.name, pm.name)] = NameInfo{
				masm:     m
				is_stack: true
			}
			st.local_type[name_key(f.name, pm.name)] = resolve_base_type(st, pm.typ_name)
		}
		for s in f.body {
			if s.kind != StmtKind.st_local {
				continue
			}
			if !(s.local_type in st.type_masm) {
				return error('第 ${s.line} 行: 局部变量类型 ${s.local_type} 未知')
			}
			if s.local_array_len.len > 0 {
				n := cone_fold_int_text(st, s.local_array_len) or {
					return error('第 ${s.line} 行: 局部数组长度 ${s.local_array_len} 非法')
				}
				if n <= 0 {
					return error('第 ${s.line} 行: 局部数组长度必须为正')
				}
			}
			for n in s.local_names {
				if n in scope {
					return error('第 ${s.line} 行: 函数 ${f.name} 里 ${n} 重复声明（cone 层局部变量/形参不可重名）')
				}
				scope[n] = true
				m := mangle_name(n, '@', st.globals, used)
				used[m] = true
				st.name_maps[name_key(f.name, n)] = NameInfo{
					masm:     m
					is_stack: true
				}
				st.local_type[name_key(f.name, n)] = resolve_base_type(st, s.local_type)
			}
			// cone 0.7：局部变量初值表达式校验（名字已登记，可引用此前声明的局部变量）。
			for ii in s.local_inits {
				if ii >= 0 {
					check_expr(prog, st, ii, f.name) or { return error(err.msg()) }
					// cone 0.9.1：声明时初始化 `T v = func()` 也按返回类型校验
					ie := prog.exprs[ii]
					if ie.kind == ExprKind.expr_call {
						tg := call_target(ie.text)
						if tg in st.func_ret_type {
							rt := st.func_ret_type[tg]
							rsz := st.func_ret_size[tg]
							ris := st.func_ret_is_struct[tg]
							db := resolve_base_type(st, s.local_type)
							if ris {
								rb := resolve_base_type(st, rt)
								if db != rb {
									return error('第 ${s.line} 行: 用结构体接收函数 ${tg} 的返回值时，类型必须是 ${rt}，实际是 ${db}')
								}
							} else {
								mut dsz := st.type_bytes[db]
								if dsz == 0 { dsz = 4 }
								if dsz != rsz {
									return error('第 ${s.line} 行: 函数 ${tg} 返回 ${rt}（${rsz} 字节），接收变量是 ${dsz} 字节，尺寸不足或过大')
								}
							}
						}
					}
				}
			}
		}

		// cone 0.5：match 标记流结构 / case 值校验
		check_match_flow(prog, st, f) or { return error(err.msg()) }

		// break / continue 只能出现在 for 循环体内（parser 已按词法 loop_depth 拦过一次，
		// 这里按摊平后的 st_for / st_endfor 标记流再复核一遍，防止手写 AST 绕过）。
		mut loop_depth := 0
		for s in f.body {
			if s.kind == StmtKind.st_for {
				loop_depth = loop_depth + 1
			}
			if s.kind == StmtKind.st_endfor {
				loop_depth = loop_depth - 1
			}
			if s.kind == StmtKind.st_break || s.kind == StmtKind.st_continue {
				if loop_depth == 0 {
					mut kw := 'break'
					if s.kind == StmtKind.st_continue {
						kw = 'continue'
					}
					return error('第 ${s.line} 行: ${kw} 只能出现在 for 循环体内（cone 0.3）')
				}
			}
		}

		for s in f.body {
			if s.kind == StmtKind.st_asm64 {
				continue
			}
			if s.kind == StmtKind.st_asm {
				check_asm_text(st, f.name, s.asm_text, s.line) or { return error(err.msg()) }
				continue
			}
			// cone 0.5：match 的四个标记由 check_match_flow 统一校验，这里跳过
			if s.kind == StmtKind.st_match || s.kind == StmtKind.st_case || s.kind == StmtKind.st_default || s.kind == StmtKind.st_endmatch {
				continue
			}
			if s.kind == StmtKind.st_return {
				if s.ret_idx < 0 {
					return error('第 ${s.line} 行: 函数 ${f.name} 出现空 return；cone 0.2 完善版要求 return <表达式>')
				}
				check_expr(prog, st, s.ret_idx, f.name) or { return error(err.msg()) }
				// cone 0.9.2：函数声明了返回类型时校验 return 值
				rt := st.func_ret_type[f.name]
				if rt.len > 0 {
					ris := st.func_ret_is_struct[f.name]
					rsz := st.func_ret_size[f.name]
					rb := resolve_base_type(st, rt)
					et := expr_type_of(prog, st, f.name, s.ret_idx)
					if ris {
						// 问题 1：return 值必须是声明的结构体类型本身
						if et != rb {
							return error('第 ${s.line} 行: 函数 ${f.name} 声明返回结构体 ${rt}，return 值必须是 ${rt} 类型的结构体实例，实际得到 ${describe_expr(prog.exprs, s.ret_idx)}')
						}
					} else {
						// 问题 3：标量返回类型 —— 不能 return 结构体；return 尺寸 > 声明尺寸报错
						if et in st.struct_size || et in st.struct_extern {
							return error('第 ${s.line} 行: 函数 ${f.name} 声明返回标量 ${rt}，不能 return 结构体实例（${describe_expr(prog.exprs, s.ret_idx)}）')
						}
						if !expr_is_float(prog, st, f.name, s.ret_idx) {
							mut esz := expr_size(prog, st, f.name, s.ret_idx)
							if esz == 0 { esz = 4 }
							if esz > rsz {
								return error('第 ${s.line} 行: 函数 ${f.name} 声明返回 ${rt}（${rsz} 字节），return 值 ${esz} 字节大于返回类型声明尺寸')
							}
						}
					}
				}
			} else if s.kind == StmtKind.st_assign {
				// [] 解引用作左值：cone 支持内存写，生成 mov xxx ptr [addr], reg/imm
				if s.lhs_idx >= 0 {
					le := prog.exprs[s.lhs_idx]
					if le.kind != ExprKind.expr_deref && le.kind != ExprKind.expr_member {
						return error('第 ${s.line} 行: 内部错误，赋值左值不是 [] 解引用或结构体成员节点')
					}
					if le.kind == ExprKind.expr_member {
						check_member_expr(prog, st, f.name, s.lhs_idx, false) or { return error(err.msg()) }
					} else {
						check_deref(prog, st, f.name, s.lhs_idx) or { return error(err.msg()) }
					}
					check_expr(prog, st, s.rhs_idx, f.name) or { return error(err.msg()) }
					if prog.exprs[s.rhs_idx].kind == ExprKind.expr_str && !prog.exprs[s.rhs_idx].is_char_const {
						return error('第 ${s.line} 行: 字符串字面量不能直接写入内存（请定义数据标签后写入其数值）')
					}
					// cone 0.4 fix：[] / 结构体成员同样是合法左值。右值出现浮点时
					// 走 x87（fld / fstp），而不是把 real 立即数塞进 mov。
					if expr_has_float_lit(prog, s.rhs_idx) || expr_is_float(prog, st, f.name, s.rhs_idx) {
						if le.kind == ExprKind.expr_deref {
							nb := deref_size_bytes(le.ptr_size)
							if nb != 4 && nb != 8 {
								return error('第 ${s.line} 行: 浮点写入 [] 需要 4 或 8 字节目标（默认 dword / 显式 qword、real8、f64、long），当前 ${le.ptr_size} 是 ${nb} 字节；MASM32 的 fstp 只支持 m32fp / m64fp / m80fp，byte / word 尺寸请先改成 4 字节目标')
							}
						}
					}
					continue
				}
				// cone 0.3：寄存器是合法左值（reg=imm/reg/mem -> mov reg,imm/reg/mem）
				if is_reg_name(s.lhs) {
					check_expr(prog, st, s.rhs_idx, f.name) or { return error(err.msg()) }
					if expr_is_float(prog, st, f.name, s.rhs_idx) {
						return error('第 ${s.line} 行: 浮点表达式不能写进通用寄存器 ${s.lhs}（x87 结果请用 f32/f64 变量承接）')
					}
					continue
				}
				mut lhs_ok := false
				if s.lhs in st.globals {
					k := st.global_kind[s.lhs]
					if k == 'const' {
						return error('第 ${s.line} 行: 不能给 const 常量 ${s.lhs} 赋值（常量只读）')
					}
					if k == 'func' || k == 'proto' {
						return error('第 ${s.line} 行: 不能给函数名 ${s.lhs} 赋值；赋值目标必须是变量（全局变量/局部变量/形参）')
					}
					if k == 'typedef' {
						return error('第 ${s.line} 行: 不能给类型名 ${s.lhs} 赋值；赋值目标必须是变量')
					}
					if k == 'equ' {
						return error('第 ${s.line} 行: 不能给 equ 常量 ${s.lhs} 赋值（equ 是汇编期符号，运行时只读）')
					}
					lhs_ok = true
				}
				if s.lhs in scope {
					lhs_ok = true
				}
				// cone 0.6 fix2：win{...} 登记的 MASM 侧变量也能作左值。
				if s.lhs in st.win_bare {
					lhs_ok = true
				}
				if !lhs_ok {
					return error('第 ${s.line} 行: 赋值目标 ${s.lhs} 未定义（只能是全局变量、局部变量或形参）；若想调用函数请写成 ${s.lhs}(...)')
				}
				check_expr(prog, st, s.rhs_idx, f.name) or { return error(err.msg()) }
				// cone 0.9.1：函数声明了返回类型时，接收变量必须匹配尺寸/结构体类型
				re := prog.exprs[s.rhs_idx]
				if re.kind == ExprKind.expr_call {
					tg := call_target(re.text)
					if tg in st.func_ret_type {
						rt := st.func_ret_type[tg]
						rsz := st.func_ret_size[tg]
						ris := st.func_ret_is_struct[tg]
						db := resolve_base_type(st, symbol_base_type(st, f.name, s.lhs))
						if ris {
							rb := resolve_base_type(st, rt)
							if db != rb {
								return error('第 ${s.line} 行: 用结构体接收函数 ${tg} 的返回值时，类型必须是 ${rt}，实际是 ${db}')
							}
						} else {
							mut dsz := st.type_bytes[db]
							if dsz == 0 { dsz = 4 }
							if dsz != rsz {
								return error('第 ${s.line} 行: 函数 ${tg} 返回 ${rt}（${rsz} 字节），接收变量 ${s.lhs} 是 ${dsz} 字节，尺寸不足或过大')
							}
						}
					}
				}
				if expr_is_float(prog, st, f.name, s.rhs_idx) {
					base := symbol_base_type(st, f.name, s.lhs)
					if base == 'byte' || base == 'word' {
						return error('第 ${s.line} 行: 浮点表达式不能隐式赋给 ${base} 变量 ${s.lhs}（x87 FISTP 最小只支持 16 位整数内存）；请改用 int/long 变量')
					}
				}
			} else if s.kind == StmtKind.st_inc || s.kind == StmtKind.st_dec {
				ti := s.target_idx
				if ti < 0 {
					return error('第 ${s.line} 行: ++/-- 缺少目标')
				}
				le := prog.exprs[ti]
				if le.kind != ExprKind.expr_ident && le.kind != ExprKind.expr_member && le.kind != ExprKind.expr_deref {
					return error('第 ${s.line} 行: ++/-- 目标必须是寄存器 / 变量 / 结构体成员 / [] 内存')
				}
				check_expr(prog, st, ti, f.name) or { return error(err.msg()) }
				if le.kind == ExprKind.expr_member {
					check_member_expr(prog, st, f.name, ti, false) or { return error(err.msg()) }
				}
				if le.kind == ExprKind.expr_deref {
					check_deref(prog, st, f.name, ti) or { return error(err.msg()) }
				}
				if expr_is_float(prog, st, f.name, ti) {
					return error('第 ${s.line} 行: ++/-- 不支持浮点目标（inc/dec 只作用于整数 reg/mem）')
				}
				if le.kind == ExprKind.expr_ident && !le.is_reg && !le.is_win_sym {
					k := st.global_kind[le.text]
					if k == 'equ' || k == 'const' || k == 'func' || k == 'proto' || k == 'typedef' {
						return error('第 ${s.line} 行: ++/-- 不能作用于常量 / 函数名 ${le.text}')
					}
				}
			} else if s.kind == StmtKind.st_call {
				check_expr(prog, st, s.call_idx, f.name) or { return error(err.msg()) }
			} else if s.kind == StmtKind.st_if || s.kind == StmtKind.st_elseif {
				if s.cond_idx < 0 {
					return error('第 ${s.line} 行: 内部错误，if / elseif 缺少条件表达式')
				}
				check_expr_cond(prog, st, s.cond_idx, f.name) or { return error(err.msg()) }
			} else if s.kind == StmtKind.st_for {
				if !s.is_forever {
					if s.cond_idx < 0 {
						return error('第 ${s.line} 行: 内部错误，for 缺少条件表达式')
					}
					check_expr_cond(prog, st, s.cond_idx, f.name) or { return error(err.msg()) }
				}
			} else if s.kind == StmtKind.st_else || s.kind == StmtKind.st_endif || s.kind == StmtKind.st_endfor || s.kind == StmtKind.st_break || s.kind == StmtKind.st_continue {
				// 摊平标记语句 / 循环控制语句：无需表达式校验
			}
		}
	}

	// cone 0.83：seg 裸语句 / 宏调用位置的语义检查。
	// 只允许宏作为独立调用语句（st_call）；作为右值 / 参数 / 条件 / return 一律报错，
	// 因为无 exitm 宏不产生值。段内裸代码不允许 return / 局部变量声明。
	mut allowed := map[int]bool{}
	for f in prog.funcs {
		for s in f.body {
			if s.kind == StmtKind.st_call {
				allowed[s.call_idx] = true
			}
		}
	}
	for sg in prog.segs {
		for it in sg.items {
			if it.kind != SegItemKind.si_stmt {
				continue
			}
			for s in it.stmts {
				if s.kind == StmtKind.st_call {
					allowed[s.call_idx] = true
				}
				if s.kind == StmtKind.st_return {
					return error('第 ${s.line} 行: seg 段内裸代码不能用 return（return 只能写在段内 def 函数里）')
				}
				if s.kind == StmtKind.st_local {
					return error('第 ${s.line} 行: seg 段内裸代码不能声明局部变量；段内数据请写 `类型 名字=初值`')
				}
			}
		}
	}
	mut mi := 0
	for mi < prog.exprs.len {
		e := prog.exprs[mi]
		if e.kind == ExprKind.expr_call && e.text in st.macros {
			if !(mi in allowed) {
				return error('第 ${e.line} 行: 宏 ${e.text} 是无 exitm 宏，不能作为右值 / 参数 / 条件 / return；只能写成独立调用语句 `${e.text}(...)`')
			}
			for ai in e.args {
				ae := prog.exprs[ai]
				if ae.kind == ExprKind.expr_bin || ae.kind == ExprKind.expr_call {
					return error('第 ${ae.line} 行: 宏参数目前只支持简单操作数（立即数 / 标识符 / 寄存器 / addr / 成员 / 解引用），不支持表达式或函数调用')
				}
			}
		}
		mi = mi + 1
	}

	// cone 0.9prelease：布局算完后统一折叠 cone 立即数（sizeof / Type.member / equ）
	cone_fold_immediates(mut prog, mut st, true) or { return error(err.msg()) }
	// cone 0.9preview：asm64{} 统一在 analyzer 阶段预编译（错误带精确行号）。
	// prefix 用全局递增序号，V 侧与参考实现遍历顺序完全一致（顶层按列表、函数按列表+body 顺序）。
	// cone 0.9.p：x64 下 asm64{} 正文原样交给 LLVM 汇编器（inline asm / module asm），
	// 不走 x86 的 cone 侧 x64 指令编码器（它不认 %变量引用与 masm64 数据形态）。
	// 默认 x86 后端的 db 机器码路径一字不改。
	mut a64seq := 0
	if !x64_mode {
		for ab in prog.asm64s {
			pfx := '__cone_a64_${a64seq}'
			a64seq = a64seq + 1
			key := 't${ab.order}'
			st.asm64_cache[key] = compile_asm64(cone_subst_imm(st, ab.text, true), pfx) or { return error('第 ${ab.line} 行: ${err.msg()}') }
		}
		for f in prog.funcs {
			mut bi := 0
			for bi < f.body.len {
				ss := f.body[bi]
				if ss.kind == StmtKind.st_asm64 {
					pfx := '__cone_a64_${a64seq}'
					a64seq = a64seq + 1
					key := 'f${f.name}:${bi}'
					st.asm64_cache[key] = compile_asm64(cone_subst_imm(st, ss.asm_text, true), pfx) or { return error('第 ${ss.line} 行: ${err.msg()}') }
				}
				bi = bi + 1
			}
		}
	}
	for sg in prog.segs {
		for it in sg.items {
			if it.kind == SegItemKind.si_stmt {
				for ss in it.stmts {
					if ss.kind == StmtKind.st_asm64 {
						return error('第 ${ss.line} 行: seg 段内裸代码暂不支持 asm64{}（请放进段内 def 函数，或放到 seg 外）')
					}
				}
			}
		}
	}

	return st
}
