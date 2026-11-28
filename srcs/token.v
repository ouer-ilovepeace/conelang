module main

// TokenKind: cone 0.2 完善版的全部词素类别。
// 一律加前缀，避开 V 自身的 int/long/string 等类型名。
enum TokenKind {
	eof
	ident
	reg      // cone 0.3：通用寄存器 / 段寄存器，保留的特殊标识符
	number
	string_lit
	equ_text // equ 的 <...> 原文，含尖括号；lit 原样，text 为内部文本
	asm_body // cone 0.4 fix2：asm 块的正文原文（含换行，不做词法解析）
	kw_import
	kw_include
	kw_equ
	kw_enum    // cone 0.9.f：enum [名字]{ A, B=10, C }
	kw_ifdef   // cone 0.9.f：编译期条件编译
	kw_ifndef
	kw_elsedef
	kw_defsym  // cone 0.9.f：登记一个编译期符号
	kw_def
	kw_end
	kw_return
	kw_c
	kw_stdcall
	kw_byte
	kw_word
	kw_int
	kw_long
	kw_f32
	kw_f64
	kw_const
	kw_addr
	kw_win
	kw_typedef
	kw_func
	kw_efunc // cone 0.9.3：只在 cone 侧登记的外部函数声明
	kw_if
	kw_elseif
	kw_else
	kw_unsigned // condition 前缀：无符号比较（默认即无符号，显式写等价）
	kw_signed   // condition 前缀：该条件的比较按有符号生成
	kw_struct   // cone 0.4：结构体定义
	kw_asm      // cone 0.4 fix2：内嵌汇编 asm 块
	kw_match    // cone 0.5：match 分支
	kw_default  // cone 0.5：match 的 default 分支
	kw_export   // cone 0.5：MASM32 EXPORT 属性
	kw_float    // cone 0.6：float(...) 把内容按浮点载入/浮点运算处理
	kw_for
	kw_break
	kw_continue
	kw_try      // cone 0.7：SEH 保护块 try{...}
	kw_except   // cone 0.7：except [ErrorType]{...}，ErrorType 可选（= 通配）
	kw_compile_arg // cone 0.8prelease：__compile__ "附加编译参数"
	kw_link_arg    // cone 0.8prelease：__link__ "附加链接参数"
	kw_seg         // cone 0.83：seg "名字"{ ... } 特殊段
	kw_defined     // cone 0.83：defined 宏函数（无 exitm）
	kw_asm64       // cone 0.9preview：asm64{} 内嵌 x64 指令（编码成 db 机器码）
	kw_align       // cone 0.9prelease：struct NAME align{...} 的 Windows ABI 对齐修饰
	kw_sizeof      // cone 0.9prelease：sizeof(xxx) 编译期字节数（视为立即数）
	dollar         // cone 0.9preview：$ 特殊立即数（MASM32 当前地址）
	colon
	comma
	lparen
	rparen
	lbrace
	rbrace
	lbracket
	rbracket
	dot
	assign
	plus
	minus
	star
	slash
	percent // cone 0.9.1：取模运算符 %（整数，禁浮点）
	eq_eq
	not_eq
	gt
	lt
	ge
	le
	and_and
	or_or
	bang
	amp         // cone 0.6 fix1：按位与 &
	pipe        // cone 0.6 fix1：按位或 |
	caret       // cone 0.6 fix1：按位异或 ^
	tilde       // cone 0.6 fix1：按位非 ~
	shl         // cone 0.6 fix1：左移 <<
	shr         // cone 0.6 fix1：右移 >>
	plus_plus   // cone 0.6 fix1：++
	minus_minus // cone 0.6 fix1：--
	reserved // MASM32 保留字：指令 / 寄存器 / 伪指令 / 属性 / 运算符
}

struct Token {
	kind TokenKind
	lit  string // 源码原样切片：字符串【含首尾引号】，其余为原文
	text string // 仅 string_lit 有效：引号内部字节流（无转义）
	line int
	col  int
	file string
}

fn (t Token) desc() string {
	if t.file.len > 0 {
		return '${t.file}:${t.line}:${t.col} ${t.lit}'
	}
	return '${t.line}:${t.col} ${t.lit}'
}

fn mk_token(k TokenKind, lit string, ln int, cl int, file string) Token {
	mut text := ''
	if k == TokenKind.string_lit && lit.len >= 2 {
		// cone 0.9.f：w"..." / W'...' 把前缀和引号一起剥掉
		if lit.len >= 3 && (lit[0] == 119 || lit[0] == 87) && (lit[1] == 34 || lit[1] == 39) {
			text = lit[2..lit.len - 1]
		} else {
			text = lit[1..lit.len - 1]
		}
	}
	if k == TokenKind.equ_text && lit.len >= 2 {
		text = lit[1..lit.len - 1]
	}
	return Token{
		kind: k
		lit:  lit
		text: text
		line: ln
		col:  cl
		file: file
	}
}

// eq_ci: 纯 ASCII 大小写不敏感比较（不依赖标准库方法）
fn eq_ci(s string, t string) bool {
	if s.len != t.len {
		return false
	}
	mut i := 0
	for i < s.len {
		mut a := int(s[i])
		mut b := int(t[i])
		if a >= 65 && a <= 90 {
			a = a + 32
		}
		if b >= 65 && b <= 90 {
			b = b + 32
		}
		if a != b {
			return false
		}
		i = i + 1
	}
	return true
}

fn keyword_of(lit string, x64_mode bool) TokenKind {
	if eq_ci(lit, 'import') {
		return TokenKind.kw_import
	}
	if eq_ci(lit, 'include') {
		return TokenKind.kw_include
	}
	if eq_ci(lit, 'equ') {
		return TokenKind.kw_equ
	}
	// cone 0.9.f：源码级预处理关键字
	if eq_ci(lit, 'enum') { return TokenKind.kw_enum }
	if eq_ci(lit, 'ifdef') { return TokenKind.kw_ifdef }
	if eq_ci(lit, 'ifndef') { return TokenKind.kw_ifndef }
	if eq_ci(lit, 'elsedef') { return TokenKind.kw_elsedef }
	if eq_ci(lit, 'defsym') { return TokenKind.kw_defsym }
	if eq_ci(lit, 'def') {
		return TokenKind.kw_def
	}
	if eq_ci(lit, 'end') {
		return TokenKind.kw_end
	}
	if eq_ci(lit, 'return') {
		return TokenKind.kw_return
	}
	if eq_ci(lit, 'c') {
		return TokenKind.kw_c
	}
	if eq_ci(lit, 'stdcall') {
		return TokenKind.kw_stdcall
	}
	if eq_ci(lit, 'byte') {
		return TokenKind.kw_byte
	}
	if eq_ci(lit, 'word') {
		return TokenKind.kw_word
	}
	if eq_ci(lit, 'int') {
		return TokenKind.kw_int
	}
	if eq_ci(lit, 'long') {
		return TokenKind.kw_long
	}
	if eq_ci(lit, 'f32') {
		return TokenKind.kw_f32
	}
	if eq_ci(lit, 'f64') {
		return TokenKind.kw_f64
	}
	if eq_ci(lit, 'const') {
		return TokenKind.kw_const
	}
	if eq_ci(lit, 'addr') {
		return TokenKind.kw_addr
	}
	if eq_ci(lit, 'win') {
		return TokenKind.kw_win
	}
	if eq_ci(lit, 'typedef') {
		return TokenKind.kw_typedef
	}
	if eq_ci(lit, 'func') {
		return TokenKind.kw_func
	}
	if eq_ci(lit, 'efunc') {
		return TokenKind.kw_efunc
	}
	if eq_ci(lit, 'if') {
		return TokenKind.kw_if
	}
	if eq_ci(lit, 'elseif') {
		return TokenKind.kw_elseif
	}
	if eq_ci(lit, 'else') {
		return TokenKind.kw_else
	}
	if eq_ci(lit, 'unsigned') {
		return TokenKind.kw_unsigned
	}
	if eq_ci(lit, 'signed') {
		return TokenKind.kw_signed
	}
	// cone 0.4：struct 是 MASM 保留字，但 cone 关键字优先于保留字判定
	if eq_ci(lit, 'struct') {
		return TokenKind.kw_struct
	}
	// cone 0.4 fix2：asm 关键字（MASM 保留字表里没有 asm，仍放在关键字段优先判定）
	if eq_ci(lit, 'asm') {
		return TokenKind.kw_asm
	}
	// cone 0.6：float 是 cone 关键字（MASM 保留字表里没有 float）
	if eq_ci(lit, 'float') {
		return TokenKind.kw_float
	}
	// cone 0.5：match / default / export（cone 关键字优先于 MASM 保留字判定）
	if eq_ci(lit, 'match') {
		return TokenKind.kw_match
	}
	if eq_ci(lit, 'default') {
		return TokenKind.kw_default
	}
	if eq_ci(lit, 'export') {
		return TokenKind.kw_export
	}
	if eq_ci(lit, 'for') {
		return TokenKind.kw_for
	}
	if eq_ci(lit, 'break') {
		return TokenKind.kw_break
	}
	if eq_ci(lit, 'continue') {
		return TokenKind.kw_continue
	}
	// cone 0.8prelease：源码内附加参数指令（必须优先于 ident 判定）
	if eq_ci(lit, '__compile__') {
		return TokenKind.kw_compile_arg
	}
	if eq_ci(lit, '__link__') {
		return TokenKind.kw_link_arg
	}
	// cone 0.83：seg / defined（cone 关键字优先于 MASM 保留字判定）
	if eq_ci(lit, 'asm64') {
		return TokenKind.kw_asm64
	}
	// cone 0.9prelease：align / sizeof 也在 MASM32 保留字表里，必须优先命中 cone 关键字
	if eq_ci(lit, 'align') {
		return TokenKind.kw_align
	}
	if eq_ci(lit, 'sizeof') {
		return TokenKind.kw_sizeof
	}
	if eq_ci(lit, 'seg') {
		return TokenKind.kw_seg
	}
	if eq_ci(lit, 'defined') {
		return TokenKind.kw_defined
	}
	// cone 0.7：try / except（MASM32 保留字表里没有这两个词，cone 关键字优先）
	if eq_ci(lit, 'try') {
		return TokenKind.kw_try
	}
	if eq_ci(lit, 'except') {
		return TokenKind.kw_except
	}
	// cone 0.3：寄存器是保留的特殊标识符，但可以作为表达式 / 左值 / 参数使用，
	// 因此单独成类，与"只能拦下、不能参与语法"的普通 MASM 保留字区分开。
	// cone 0.9.f：-llvm:x64 下 MASM32 寄存器 / 伪指令 / 汇编指令全部恢复为
	// 普通标识符；cone 关键字与 fuck 等 cone 特殊标识符仍受限。
	if x64_mode {
		return TokenKind.ident
	}
	if is_reg_name(lit) {
		return TokenKind.reg
	}
	// MASM32 其余保留字不能作为 cone 标识符（指令、伪指令、属性、运算符）
	if is_reserved_word(lit) {
		return TokenKind.reserved
	}
	return TokenKind.ident
}

// masm_reserved_words: 用空格分隔的一张表。全部小写，比较时 eq_ci 处理大小写。
// cone 自己的关键字优先在前段命中，表里出现同名项也不会造成误判。
const masm_reserved_words = 'eax ebx ecx edx esi edi ebp esp eip ax bx cx dx si di bp sp al ah bl bh cl ch dl dh cs ds es fs gs ss st mm0 mm1 mm2 mm3 mm4 mm5 mm6 mm7 xmm0 xmm1 xmm2 xmm3 xmm4 xmm5 xmm6 xmm7 cr0 cr2 cr3 cr4 dr0 dr1 dr2 dr3 dr6 dr7 tr3 tr4 tr5 tr6 tr7 eflags flags mov movsx movzx lea push pop pushad popad pushfd popfd pushf popf add adc sub sbb mul imul div idiv neg inc dec xor and or not test cmp shl shr sar sal rol ror rcl rcr shld shrd bswap xchg cmpxchg xadd call ret retn retf jmp je jne jz jnz ja jae jb jbe jg jge jl jle jc jnc jo jno js jns jp jnp jpe jpo jecxz jcxz loop loope loopne loopz loopnz nop leave enter clc stc cmc cld std cli sti cbw cwd cdq cwde int into iret iretd hlt wait fwait lock rep repe repne repz repnz movsb movsw movsd stosb stosw stosd lodsb lodsw lodsd cmpsb cmpsw cmpsd scasb scasw scasd insb insw insd outsb outsw outsd in out sete setne seta setae setb setbe setg setge setl setle setc setnc seto setno sets setns setp setnp cmove cmovne cmova cmovae cmovb cmovbe cmovg cmovge cmovl cmovle bt bts btr btc bsf bsr bound arpl lar lsl verr verw lgdt lidt lldt sgdt sidt sldt ltr str lmsw smsw clts invd wbinvd cpuid rdtsc rdmsr wrmsr ud2 pause emms movd movq fld fst fstp fild fist fistp fbld fbstp fadd faddp fsub fsubp fsubr fsubrp fmul fmulp fdiv fdivp fdivr fdivrp fchs fabs fsqrt fsin fcos fsincos fptan fpatan fprem fprem1 fscale frndint fxtract fcom fcomp fcompp fcomi fcomip fucom fucomp fucompp ftst fxam fldz fld1 fldpi fldl2e fldl2t fldlg2 fldln2 finit fninit fclex fnclex fnop fxch ffree fdecstp fincstp fstsw fnstsw fstcw fldcw fstenv fnstenv fldenv fsave fnsave frstor fxsave fxrstor proc endp proto typedef invoke include includelib macro endm exitm goto purge struct union ends record equ label org align even assume segment group public extern extrn comm dup offset ptr seg type length lengthof sizeof size low high lowword highword opattr short near far this mask width page title subtitle model option casemap uses stdcall syscall pascal fastcall vectorcall basic fortran flat db dw dd dq dt df byte word dword qword fword tbyte real4 real8 real10 sbyte sword sdword sqword local if ifdef ifndef ifb ifnb ifidn ifidni ifdif ifdifi else elseif endif while endw repeat until for endloop break continue echo err radix eq ne lt le gt ge mod c addr end'

// 手写按空格切词，不依赖任何标准库方法（避免 V 版本差异）
fn is_reserved_word(lit string) bool {
	mut start := 0
	mut i := 0
	for i < masm_reserved_words.len {
		if masm_reserved_words[i] == 32 {
			if i > start {
				w := masm_reserved_words[start..i]
				if eq_ci(lit, w) {
					return true
				}
			}
			start = i + 1
		}
		i = i + 1
	}
	if start < masm_reserved_words.len {
		w := masm_reserved_words[start..]
		if eq_ci(lit, w) {
			return true
		}
	}
	return false
}

// ---------- [] 解引用的尺寸词 ----------
//
//   [fmt]          -> dword ptr [fmt]        （默认）
//   [byte fmt]     -> byte ptr [fmt]
//   [word fmt]     -> word ptr [fmt]
//   [real4 fmt]    -> real4 ptr [fmt]
//   [int fmt]      -> dword ptr [fmt]       （cone 类型关键字映射到 MASM 尺寸名）
//   [long fmt]     -> qword ptr [fmt]
//   [f32 fmt]      -> real4 ptr [fmt]
//   [f64 fmt]      -> real8 ptr [fmt]
//
// cone 内置类型关键字与 MASM 原生尺寸词都能用；按字面生成 xxx ptr，不做隐式转换。
// 这些 MASM 尺寸词本身在保留字表里（不能作 cone 标识符），但出现在 [] 开头时
// parser 会特判为尺寸词。

const masm_size_words = 'byte sbyte word sword dword sdword qword sqword fword tbyte real4 real8 real10'

fn is_masm_size_word(lit string) bool {
	mut start := 0
	mut i := 0
	for i < masm_size_words.len {
		if masm_size_words[i] == 32 {
			if i > start {
				w := masm_size_words[start..i]
				if eq_ci(lit, w) {
					return true
				}
			}
			start = i + 1
		}
		i = i + 1
	}
	if start < masm_size_words.len {
		w := masm_size_words[start..]
		if eq_ci(lit, w) {
			return true
		}
	}
	return false
}

// deref_ptr_word: 把 cone 侧写的尺寸词规范化成 MASM 尺寸名（不带 ptr）。
// 空串 = 默认 dword。MASM 原生尺寸词原样保留，cone 类型关键字做映射。
fn deref_ptr_word(size_word string) string {
	if size_word.len == 0 {
		return 'dword'
	}
	if eq_ci(size_word, 'byte') {
		return 'byte'
	}
	if eq_ci(size_word, 'word') {
		return 'word'
	}
	if eq_ci(size_word, 'int') {
		return 'dword'
	}
	if eq_ci(size_word, 'long') {
		return 'qword'
	}
	if eq_ci(size_word, 'f32') {
		return 'real4'
	}
	if eq_ci(size_word, 'f64') {
		return 'real8'
	}
	return size_word
}

fn deref_ptr_text(size_word string) string {
	return deref_ptr_word(size_word) + ' ptr'
}

// deref_size_bytes: 尺寸词对应的字节数，供 return 的寄存器选择与载入方式判断。
// 未知尺寸按 4 字节处理。
fn deref_size_bytes(size_word string) int {
	w := deref_ptr_word(size_word)
	if eq_ci(w, 'byte') || eq_ci(w, 'sbyte') {
		return 1
	}
	if eq_ci(w, 'word') || eq_ci(w, 'sword') {
		return 2
	}
	if eq_ci(w, 'fword') {
		return 6
	}
	if eq_ci(w, 'qword') || eq_ci(w, 'sqword') || eq_ci(w, 'real8') {
		return 8
	}
	if eq_ci(w, 'tbyte') || eq_ci(w, 'real10') {
		return 10
	}
	return 4
}

fn is_ptr_size_kw(k TokenKind) bool {
	if k == TokenKind.kw_byte || k == TokenKind.kw_word || k == TokenKind.kw_int {
		return true
	}
	if k == TokenKind.kw_long || k == TokenKind.kw_f32 || k == TokenKind.kw_f64 {
		return true
	}
	return false
}

// ---------- cone 0.3 寄存器表 ----------
//
// 所有通用寄存器（32/16/8 位）与段寄存器都是 cone 的保留特殊标识符，
// cone 侧名字与 MASM32 侧一一对应，可直接出现在：
//   赋值左值 / 表达式 / 调用参数 / [] 内存寻址
// 例如 eax=5 -> mov eax,5；ax=bx -> mov ax,bx；al=[byte mem]；[dword mem+eax*4+8]=r。
//
// 段寄存器按 16 位处理（mov 到/从段寄存器由 MASM32 裁决，cone 只做名称透传）。

const reg_words_32 = 'eax ebx ecx edx esi edi ebp esp'
const reg_words_16 = 'ax bx cx dx si di bp sp'
const reg_words_8  = 'al ah bl bh cl ch dl dh'
const reg_words_seg = 'cs ds es fs gs ss'

// 族表：每行 "32位名 16位名 8位低位名"，用 | 分行。'-' 表示没有 8 位低位寄存器。
const reg_family_table = 'eax ax al|ebx bx bl|ecx cx cl|edx dx dl|esi si -|edi di -|ebp bp -|esp sp -'

fn word_in_const_list(list string, lit string) bool {
	mut start := 0
	mut i := 0
	for i < list.len {
		if list[i] == 32 {
			if i > start {
				if eq_ci(lit, list[start..i]) {
					return true
				}
			}
			start = i + 1
		}
		i = i + 1
	}
	if start < list.len {
		if eq_ci(lit, list[start..]) {
			return true
		}
	}
	return false
}

fn is_reg_name(lit string) bool {
	if word_in_const_list(reg_words_32, lit) {
		return true
	}
	if word_in_const_list(reg_words_16, lit) {
		return true
	}
	if word_in_const_list(reg_words_8, lit) {
		return true
	}
	if word_in_const_list(reg_words_seg, lit) {
		return true
	}
	return false
}

// reg_size: 寄存器字节数（段寄存器按 2 字节）。非寄存器返回 0。
fn reg_size(lit string) int {
	if word_in_const_list(reg_words_32, lit) {
		return 4
	}
	if word_in_const_list(reg_words_16, lit) {
		return 2
	}
	if word_in_const_list(reg_words_8, lit) {
		return 1
	}
	if word_in_const_list(reg_words_seg, lit) {
		return 2
	}
	return 0
}

// reg_family: 把任意通用寄存器名归到它的 32 位族名；段寄存器返回自身。
fn reg_family(lit string) string {
	if word_in_const_list(reg_words_seg, lit) {
		return lit
	}
	if word_in_const_list(reg_words_32, lit) {
		return lit
	}
	// 高 8 位寄存器 ah/bh/ch/dh 不在族表的三列里，显式归族
	if eq_ci(lit, 'ah') || eq_ci(lit, 'al') || eq_ci(lit, 'ax') {
		return 'eax'
	}
	if eq_ci(lit, 'bh') || eq_ci(lit, 'bl') || eq_ci(lit, 'bx') {
		return 'ebx'
	}
	if eq_ci(lit, 'ch') || eq_ci(lit, 'cl') || eq_ci(lit, 'cx') {
		return 'ecx'
	}
	if eq_ci(lit, 'dh') || eq_ci(lit, 'dl') || eq_ci(lit, 'dx') {
		return 'edx'
	}
	mut start := 0
	mut i := 0
	for i < reg_family_table.len {
		if reg_family_table[i] == 124 { // |
			fields := reg_family_table[start..i]
			if family_field_match(fields, lit) {
				return family_field_first(fields)
			}
			start = i + 1
		}
		i = i + 1
	}
	fields := reg_family_table[start..]
	if family_field_match(fields, lit) {
		return family_field_first(fields)
	}
	return lit
}

fn family_field_first(fields string) string {
	mut i := 0
	for i < fields.len {
		if fields[i] == 32 {
			return fields[..i]
		}
		i = i + 1
	}
	return fields
}

fn family_field_match(fields string, lit string) bool {
	mut start := 0
	mut i := 0
	for i < fields.len {
		if fields[i] == 32 {
			if eq_ci(lit, fields[start..i]) {
				return true
			}
			start = i + 1
		}
		i = i + 1
	}
	return eq_ci(lit, fields[start..])
}

// reg_low_for: 给定族里某个寄存器，按目标字节数返回同族的寄存器名。
// size=4 -> 32 位名；size=2 -> 16 位名；size=1 -> 8 位低位名（没有则返回空串）。
fn reg_low_for(lit string, size int) string {
	if is_seg_reg(lit) {
		if size == 2 {
			return lit
		}
		return ''
	}
	// 高 8 位 ah/bh/ch/dh 本身就是 8 位值，按原样返回（不能映射到 al/bl/cl/dl）
	if eq_ci(lit, 'ah') || eq_ci(lit, 'bh') || eq_ci(lit, 'ch') || eq_ci(lit, 'dh') {
		if size == 1 {
			return lit
		}
	}
	// 其余先归一到同族低 8 位名，再查族表
	mut n := lit
	if eq_ci(n, 'ah') {
		n = 'al'
	}
	if eq_ci(n, 'bh') {
		n = 'bl'
	}
	if eq_ci(n, 'ch') {
		n = 'cl'
	}
	if eq_ci(n, 'dh') {
		n = 'dl'
	}
	mut start := 0
	mut i := 0
	for i < reg_family_table.len {
		if reg_family_table[i] == 124 { // |
			fields := reg_family_table[start..i]
			if family_field_match(fields, n) {
				return family_field_at(fields, size)
			}
			start = i + 1
		}
		i = i + 1
	}
	fields := reg_family_table[start..]
	if family_field_match(fields, n) {
		return family_field_at(fields, size)
	}
	return ''
}

fn family_field_at(fields string, size int) string {
	mut idx := 0
	if size == 2 {
		idx = 1
	}
	if size == 1 {
		idx = 2
	}
	mut start := 0
	mut i := 0
	mut n := 0
	for i < fields.len {
		if fields[i] == 32 {
			if n == idx {
				part := fields[start..i]
				if part == '-' {
					return ''
				}
				return part
			}
			n = n + 1
			start = i + 1
		}
		i = i + 1
	}
	if n == idx {
		last := fields[start..]
		if last == '-' {
			return ''
		}
		return last
	}
	return ''
}

fn is_seg_reg(lit string) bool {
	return word_in_const_list(reg_words_seg, lit)
}

fn is_eax_family(lit string) bool {
	return eq_ci(reg_family(lit), 'eax')
}

// reg_low_of_eax: 按目标字节数返回 eax 族里对应的寄存器名（al/ax/eax）。
fn reg_low_of_eax(size int) string {
	if size == 1 {
		return 'al'
	}
	if size == 2 {
		return 'ax'
	}
	return 'eax'
}

// reg_size_ptr: 按字节数给出 MASM 尺寸前缀（不含变量标签）。
fn reg_size_ptr(size int) string {
	if size == 1 {
		return 'byte ptr'
	}
	if size == 2 {
		return 'word ptr'
	}
	if size == 8 {
		return 'qword ptr'
	}
	return 'dword ptr'
}

// ---------- cone 0.3：条件运算符 ----------

fn is_cond_op(text string) bool {
	if text == '==' || text == '!=' {
		return true
	}
	if text == '>' || text == '<' || text == '>=' || text == '<=' {
		return true
	}
	if text == '&&' || text == '||' {
		return true
	}
	return false
}

fn is_cmp_kind(k TokenKind) bool {
	if k == TokenKind.eq_eq || k == TokenKind.not_eq {
		return true
	}
	if k == TokenKind.gt || k == TokenKind.lt {
		return true
	}
	if k == TokenKind.ge || k == TokenKind.le {
		return true
	}
	return false
}
// ---------- cone 0.6 fix1：位运算符 ----------
// MASM32 的汇编期表达式用 or/and/xor/shl/shr/not；cone 源码用 | & ^ << >> ~。
fn is_bitop(text string) bool {
	if text == '|' || text == '&' || text == '^' {
		return true
	}
	if text == '<<' || text == '>>' || text == '~' {
		return true
	}
	return false
}

fn masm_bin_op(text string) string {
	if text == '%' {
		return 'mod'
	}
	if text == '|' {
		return 'or'
	}
	if text == '&' {
		return 'and'
	}
	if text == '^' {
		return 'xor'
	}
	if text == '<<' {
		return 'shl'
	}
	if text == '>>' {
		return 'shr'
	}
	if text == '~' {
		return 'not'
	}
	return text
}

fn is_masm_word_op(text string) bool {
	if text == 'mod' {
		return true
	}
	if text == 'or' || text == 'and' || text == 'xor' {
		return true
	}
	if text == 'shl' || text == 'shr' || text == 'not' {
		return true
	}
	return false
}

fn masm_bit_insn(op string) string {
	if op == '|' {
		return 'or'
	}
	if op == '&' {
		return 'and'
	}
	if op == '^' {
		return 'xor'
	}
	if op == '<<' {
		return 'shl'
	}
	if op == '>>' {
		return 'shr'
	}
	return ''
}

fn peep_insn(op string) string {
	if op == '+' {
		return 'add'
	}
	if op == '-' {
		return 'sub'
	}
	if op == '|' {
		return 'or'
	}
	if op == '&' {
		return 'and'
	}
	if op == '^' {
		return 'xor'
	}
	if op == '<<' {
		return 'shl'
	}
	if op == '>>' {
		return 'shr'
	}
	return ''
}

// is_cmp_text: 只判断六个比较运算符（排除 && / ||），降级路径据此直接发 cmp+jcc。
fn is_cmp_text(text string) bool {
	if text == '==' || text == '!=' {
		return true
	}
	if text == '>' || text == '<' || text == '>=' || text == '<=' {
		return true
	}
	return false
}

// setcc_of: 降级路径把比较结果写进 al 时用的 setcc。
// 默认有符号（setg/setge/setl/setle），unsigned 条件改用无符号（seta/setae/setb/setbe）。
// setcc_of: 降级路径把比较结果写进 al 时用的 setcc。
// cone 0.3 口径：默认与 MASM .if / .while 一致，按【无符号】比较（seta/setae/setb/setbe）；
// 只有 condition 前写了 signed 才用有符号（setg/setge/setl/setle）。
fn setcc_of(op string, signed bool) string {
	if op == '==' {
		return 'sete'
	}
	if op == '!=' {
		return 'setne'
	}
	if signed {
		if op == '>' {
			return 'setg'
		}
		if op == '<' {
			return 'setl'
		}
		if op == '>=' {
			return 'setge'
		}
		if op == '<=' {
			return 'setle'
		}
	}
	if op == '>' {
		return 'seta'
	}
	if op == '<' {
		return 'setb'
	}
	if op == '>=' {
		return 'setae'
	}
	if op == '<=' {
		return 'setbe'
	}
	return 'sete'
}

// jcc_neg_of: 条件为【假】时跳走的指令（emit_cond_branch 用）。
// 省略 setcc+movzx+test+jz 四条冗余，直接一条 cmp + jcc。
// 默认无符号（jbe/jae/jb/ja），signed 时有符号（jle/jge/jl/jg）。
fn jcc_neg_of(op string, signed bool) string {
	if op == '==' {
		return 'jne'
	}
	if op == '!=' {
		return 'je'
	}
	if signed {
		if op == '>' {
			return 'jle'
		}
		if op == '<' {
			return 'jge'
		}
		if op == '>=' {
			return 'jl'
		}
		if op == '<=' {
			return 'jg'
		}
	}
	if op == '>' {
		return 'jbe'
	}
	if op == '<' {
		return 'jae'
	}
	if op == '>=' {
		return 'jb'
	}
	if op == '<=' {
		return 'ja'
	}
	return 'jne'
}

// ---------- cone 0.3：字符常量（表达式位置的字符串字面量） ----------
//
// cone 侧 `win.crt_printf("Hello World\r\n")` 与
// `hello:"Hello World",0dh,0ah,0` + `win.crt_printf(addr hello)` 等价：
// 字符常量被展开成 MASM 的字节序列、默认补结束字节 0、统一放 .const 段，
// 调用时传的是这个常量的【地址】（offset label）。
// 与 cone 的 `label:"...",...` 数据定义不同：后者仍是"引号内即字节流、无转义"。

fn hex_val(c u8) int {
	if c >= 48 && c <= 57 {
		return int(c) - 48
	}
	if c >= 65 && c <= 70 {
		return int(c) - 55
	}
	if c >= 97 && c <= 102 {
		return int(c) - 87
	}
	return -1
}

// expand_char_const: 把带引号的字符常量展开成 MASM db 的数据项文本。
//   "Hello World\r\n"  ->  "Hello World",0dh,0ah,0
//   "say \"hi\"\t!"     ->  "say ",22h,"hi",22h,09h,"!",0
fn expand_char_const(lit string) !string {
	if lit.len < 2 {
		return error('字符常量缺少引号')
	}
	// cone 0.9.f：w"..." 宽字符串直接展开成 UTF-16LE 的 MASM 字节项
	if is_wide_lit_v(lit) {
		return wide_lit_masm_v(lit)
	}
	inner := lit[1..lit.len - 1]
	mut parts := []string{}
	mut buf := ''
	mut i := 0
	for i < inner.len {
		c := inner[i]
		if c == 92 { // 反斜杠：转义序列
			if buf.len > 0 {
				parts << '"' + buf + '"'
				buf = ''
			}
			i = i + 1
			if i >= inner.len {
				return error('字符常量末尾有孤立的反斜杠')
			}
			e := inner[i]
			if e == 114 {
				parts << '0dh' // \r
			} else if e == 110 {
				parts << '0ah' // \n
			} else if e == 116 {
				parts << '09h' // \t
			} else if e == 48 {
				parts << '00h' // \0
			} else if e == 98 {
				parts << '08h' // \b
			} else if e == 102 {
				parts << '0ch' // \f
			} else if e == 118 {
				parts << '0bh' // \v
			} else if e == 97 {
				parts << '07h' // \a
			} else if e == 92 {
				parts << '5ch' // 反斜杠本身
			} else if e == 34 {
				parts << '22h' // 双引号
			} else if e == 39 {
				parts << '27h' // 单引号
			} else if e == 120 { // \xHH
				if i + 2 >= inner.len {
					return error('字符常量的 \\x 后需要两个十六进制数字')
				}
				h1 := hex_val(inner[i + 1])
				h2 := hex_val(inner[i + 2])
				if h1 < 0 || h2 < 0 {
					return error('字符常量的 \\x 后不是合法十六进制数字')
				}
				parts << '0' + inner[i + 1..i + 2] + inner[i + 2..i + 3] + 'h'
				i = i + 2
			} else {
				return error('字符常量里有不支持的转义序列（只支持 r n t 0 b f v a 反斜杠 引号 xHH）')
			}
			i = i + 1
			continue
		}
		if c == 34 { // 裸双引号：转成 22h 项，避免破坏 MASM 字符串段
			if buf.len > 0 {
				parts << '"' + buf + '"'
				buf = ''
			}
			parts << '22h'
			i = i + 1
			continue
		}
		buf = buf + inner[i..i + 1]
		i = i + 1
	}
	if buf.len > 0 {
		parts << '"' + buf + '"'
	}
	parts << '0' // 默认补结束字节
	return parts.join(',')
}

// char_const_text: codegen 用的不抛错版本（转义合法性已在语义层校验过）。
fn char_const_text(lit string) string {
	t := expand_char_const(lit) or { return '0' }
	return t
}
