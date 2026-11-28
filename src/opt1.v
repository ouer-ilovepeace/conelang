module main

// cone 0.9.6 实验性 -O1 优化器（独立模块，与参考实现 _eq6.py 的 o1_optimize 逐函数对齐）
//
// 核心前提（不可协商）：O1 是 generate() 之后、仅 opts.o1 为真才调用的【独立文本级
// pass】；默认（无 -O1）根本不进入本模块，O0 的代码生成逐字节不受影响。
//
// 0.9.5 相对 0.9.4 的升级（RFC §3 / §4）：轻量 IR + 基本块 CFG + 位粒度 flags 数据流
// + 可收敛的多轮不动点。阶段：
//   P0 分区（FROZEN / OPAQUE / OPEN + 根集合 + MASM 高级伪指令块）
//   P1 基本块（连续 OPEN 段，标号/跳转/屏障断块，空行不打断）
//   P2 反向位粒度 FlagMask（ZF/CF/SF/OF/PF/AF）；call/invoke 为 FLAGS_KILL（A2）
//   P3 单指令变换（A7 恒等 / A8 窥孔 / A9 常量条件）
//   P4 块内跨行 DSE（A3）+ 可用表达式 CSE（A4）
//   P5 控制流（A5 不可达 / A6 跳转链 / A10 match 判别值链去重）
//   P6 不动点迭代（上限 8 轮，命中数非递增 + 文本收敛，超限回退）
//   P7 删哨兵 / 去尾部空行 / 报告 / 回退
//
// 冻结区（4.1~4.6 + 0.9.5 新增 7~10）：seg 段、asm/asm64 哨兵、含 SEH 的 proc、
// proc 之外、MASM 高级伪指令块、defined 宏正文、tab 缩进的不透明正文、常量池与默认 SEH 根标号。
// 可观测性：不删 call/invoke/int/db/rep*/fst*/含 [ 的 mov；不删用户标号（除 A5 证明不可达
// 且不在根集合）。显式寄存器保真：不做寄存器分配，只做同寄存器等价替换与被完全覆盖的冗余写入删除。

const o1_on = '__cone_o1_noopt_on__'
const o1_off = '__cone_o1_noopt_off__'
const o1_rounds_max = 8

// ---- 位粒度 FlagMask（RFC A1 / §7.2）----
const o1_f_zf = 1
const o1_f_cf = 2
const o1_f_sf = 4
const o1_f_of = 8
const o1_f_pf = 16
const o1_f_af = 32
const o1_f_all = 63

const o1_regs = ['eax', 'ebx', 'ecx', 'edx', 'esi', 'edi', 'ax', 'bx', 'cx', 'dx', 'si', 'di', 'al', 'bl', 'cl', 'dl', 'ah', 'bh', 'ch', 'dh']
const o1_opt = ['mov', 'xor', 'cmp', 'test', 'add', 'sub', 'inc', 'dec', 'imul', 'shl', 'shr', 'sar', 'and', 'or', 'not', 'neg', 'movzx', 'movsx', 'lea', 'xchg']
const o1_wrflags = ['cmp', 'test', 'add', 'sub', 'and', 'or', 'xor', 'inc', 'dec', 'neg', 'shl', 'shr', 'sar', 'imul', 'mul', 'div', 'idiv', 'adc', 'sbb']
const o1_jcc = ['ja', 'jae', 'jb', 'jbe', 'jc', 'je', 'jg', 'jge', 'jl', 'jle', 'jna', 'jnae', 'jnb', 'jnbe', 'jnc', 'jne', 'jng', 'jnge', 'jnl', 'jnle', 'jno', 'jnp', 'jns', 'jnz', 'jo', 'jp', 'jpe', 'jpo', 'js', 'jz', 'jcxz', 'jecxz', 'jrcxz', 'loop', 'loope', 'loopne', 'loopz', 'loopnz']
const o1_no_flags_read = ['ret', 'retn', 'retf', 'jmp', 'leave', 'end', 'nop', 'endp']
const o1_imm0 = ['0', '0h', '00h', '00000000h', '0x0', '0x00000000', '00000000h']
const o1_imm1 = ['1', '1h', '01h', '00000001h', '0x1', '0x00000001']
const o1_immm1 = ['-1', '0ffffffffh', '0ffffffff', '0xffffffff', '0ffffffffh', 'ffffffffh']
const o1_afread = ['daa', 'aaa', 'aas', 'aam', 'aad']
const o1_kill = ['call', 'invoke']
const o1_hard = ['int', 'db', 'dw', 'dd', 'dq', 'rep', 'repne', 'repe', 'movsw', 'movsb', 'cld', 'std', 'fst', 'fstp', 'fld', 'fild', 'fadd', 'fdivr', 'fsub', 'fmul', 'fdiv', 'in', 'out', 'hlt', 'iret', 'iretd', 'macro', 'endm']
const o1_nowrite = ['mov', 'lea', 'nop', 'push', 'pop', 'jmp', 'ret', 'retn', 'retf', 'end', 'endp', 'movzx', 'movsx', 'xchg', 'not', 'cld', 'std', 'int', 'db', 'dw', 'dd', 'dq', 'fst', 'fstp', 'fld', 'fild', 'fadd', 'fdivr', 'rep', 'movsw', 'movsb']
const o1_defop = ['mov', 'lea', 'add', 'sub', 'and', 'or', 'xor', 'inc', 'dec', 'neg', 'not', 'shl', 'shr', 'sar', 'imul', 'movzx', 'movsx', 'pop', 'xchg']
const o1_del_ok = ['mov', 'lea', 'add', 'sub', 'and', 'or', 'xor', 'inc', 'dec', 'shl', 'shr', 'sar', 'imul', 'cmp', 'test', 'nop']

// ---- 0.9.4 起保留的辅助函数（同名同义，双实现对齐）----
fn o1_in(arr []string, x string) bool {
	for v in arr {
		if v == x {
			return true
		}
	}
	return false
}

fn o1_lower(s string) string {
	mut b := []u8{}
	for i := 0; i < s.len; i++ {
		c := s[i]
		if c >= 65 && c <= 90 {
			b << c + 32
		} else {
			b << c
		}
	}
	return b.bytestr()
}

fn o1_op(s string) string {
	mut i := 0
	for i < s.len && s[i] != 32 && s[i] != 9 {
		i++
	}
	return o1_lower(s[..i])
}

fn o1_rest(s string) string {
	mut i := 0
	for i < s.len && s[i] != 32 && s[i] != 9 {
		i++
	}
	return s[i..].trim_space()
}

struct O1Args {
	a  string
	b  string
	ok bool
}

fn o1_args(rest string) O1Args {
	mut cnt := 0
	mut pos := -1
	for i := 0; i < rest.len; i++ {
		if rest[i] == 44 {
			cnt++
			if cnt == 1 {
				pos = i
			}
		}
	}
	if cnt != 1 {
		return O1Args{ok: false}
	}
	return O1Args{a: rest[..pos].trim_space(), b: rest[pos + 1..].trim_space(), ok: true}
}

// 0.9.5：允许 0 或 1 个逗号（jmp / inc / ret 等单操作数 / 无操作数指令）
fn o1_args2(rest string) O1Args {
	mut cnt := 0
	mut pos := -1
	for i := 0; i < rest.len; i++ {
		if rest[i] == 44 {
			cnt++
			if cnt == 1 {
				pos = i
			}
		}
	}
	if cnt > 1 {
		return O1Args{a: '', b: '', ok: false}
	}
	if cnt == 1 {
		return O1Args{a: rest[..pos].trim_space(), b: rest[pos + 1..].trim_space(), ok: true}
	}
	return O1Args{a: rest.trim_space(), b: '', ok: true}
}

fn o1_is_reg(x string) bool {
	y := o1_lower(x)
	if y == 'esp' || y == 'ebp' || y == 'sp' || y == 'bp' {
		return false
	}
	return o1_in(o1_regs, y)
}

fn o1_is_label(s string) bool {
	if s.len < 2 || s[s.len - 1] != 58 {
		return false
	}
	for i := 0; i < s.len; i++ {
		c := s[i]
		if c == 32 || c == 9 || c == 44 || c == 91 {
			return false
		}
	}
	return true
}

fn o1_flags_read(op string) bool {
	if o1_in(o1_jcc, op) || op == 'adc' || op == 'sbb' {
		return true
	}
	return op.starts_with('set') || op.starts_with('cmov')
}

fn o1_barrier_live(s string) bool {
	t := s.trim_space()
	if t.len == 0 {
		return false
	}
	if o1_is_label(t) {
		return false
	}
	op := o1_op(t)
	if o1_in(o1_no_flags_read, op) {
		return false
	}
	return true
}

fn o1_indent(raw string) string {
	mut i := 0
	for i < raw.len && (raw[i] == 32 || raw[i] == 9) {
		i++
	}
	return raw[..i]
}

fn o1_is_plain_name(s string) bool {
	if s.len == 0 {
		return false
	}
	for i := 0; i < s.len; i++ {
		c := s[i]
		ok := (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 63 || c == 64 || c == 36
		if !ok {
			return false
		}
	}
	return true
}

// 判断 src（如 'eax' / '5' / 'eax + 1'）是否读取了目标名 dst
fn o1_src_reads(src string, dst string) bool {
	mut tok := ''
	mut i := 0
	for i <= src.len {
		mut c := u8(0)
		if i < src.len {
			c = src[i]
		}
		if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 63 || c == 64 || c == 36 {
			tok += src[i..i + 1]
		} else {
			if tok.len > 0 && o1_reg_alias(tok) == o1_reg_alias(dst) {
				return true
			}
			tok = ''
		}
		i++
	}
	return false
}

// ---- 0.9.5 新增：位粒度 FlagMask gen/kill ----
fn o1_cc_mask(cc string) int {
	if cc == 'e' || cc == 'z' || cc == 'ne' || cc == 'nz' { return o1_f_zf }
	if cc == 'b' || cc == 'c' || cc == 'nae' || cc == 'ae' || cc == 'nb' || cc == 'nc' { return o1_f_cf }
	if cc == 'a' || cc == 'nbe' || cc == 'be' || cc == 'na' { return o1_f_cf | o1_f_zf }
	if cc == 'g' || cc == 'nle' || cc == 'le' || cc == 'ng' { return o1_f_zf | o1_f_sf | o1_f_of }
	if cc == 'ge' || cc == 'nl' || cc == 'l' || cc == 'nge' { return o1_f_sf | o1_f_of }
	if cc == 's' || cc == 'ns' { return o1_f_sf }
	if cc == 'o' || cc == 'no' { return o1_f_of }
	if cc == 'p' || cc == 'pe' || cc == 'np' || cc == 'po' { return o1_f_pf }
	return o1_f_all
}

fn o1_f_use(op string) int {
	if op == 'adc' || op == 'sbb' { return o1_f_cf }
	if o1_in(o1_afread, op) { return o1_f_af }
	if op.starts_with('set') { return o1_cc_mask(op[3..]) }
	if op.starts_with('cmov') { return o1_cc_mask(op[4..]) }
	if op.starts_with('j') && op.len > 1 {
		if op.starts_with('loop') || op == 'jcxz' || op == 'jecxz' || op == 'jrcxz' { return 0 }
		return o1_cc_mask(op[1..])
	}
	return 0
}

fn o1_f_def(op string) int {
	if o1_in(o1_nowrite, op) { return 0 }
	// 0.9.6：jcc / setcc / cmovcc 只读 flags、不写任何 EFLAGS 位。
	// 0.9.5 默认分支把它们当成「flags 全覆盖写」，会让 I1 的 interval fuse 永远为空。
	if o1_in(o1_jcc, op) || op.starts_with('set') || op.starts_with('cmov') || op.starts_with('loop') || op == 'jcxz' || op == 'jecxz' || op == 'jrcxz' { return 0 }
	if op == 'inc' || op == 'dec' { return o1_f_all ^ o1_f_cf } // inc/dec 不写 CF
	if o1_in(o1_wrflags, op) { return o1_f_all }
	return o1_f_all
}

// ---- cone 0.9.6 R1：x86 子寄存器别名表（O1-BUG-001 主修复）----
// EAX/AX/AH/AL 是同一物理寄存器的不同视图；写 16/8 位子寄存器只合并低位、
// 不清高位，读子寄存器就是读父寄存器的一部分。0.9.5 把寄存器名当扁平字符串，
// `mov tmp.x, ax` 没登记成 use(eax)，导致 movzx/add 被跨行 DSE 误删。
const o1_parent32 = ['eax', 'ebx', 'ecx', 'edx', 'esi', 'edi', 'ebp', 'esp']
const o1_child_parent = ['ax|eax', 'al|eax', 'ah|eax', 'bx|ebx', 'bl|ebx', 'bh|ebx',
	'cx|ecx', 'cl|ecx', 'ch|ecx', 'dx|edx', 'dl|edx', 'dh|edx',
	'si|esi', 'di|edi', 'bp|ebp', 'sp|esp']

fn o1_reg_alias(name string) string {
	n := o1_lower(name)
	for e in o1_child_parent {
		parts := e.split('|')
		if parts[0] == n { return parts[1] }
	}
	return n
}

fn o1_is_subreg(name string) bool { return o1_reg_alias(name) != o1_lower(name) }

fn o1_is_parent32(name string) bool { return o1_in(o1_parent32, o1_lower(name)) }

fn o1_is_stackreg(name string) bool {
	a := o1_reg_alias(name)
	return a == 'esp' || a == 'ebp'
}

// R3：目标是内存位置的写一律不参与 A3/A4 删除与 CSE
fn o1_is_mem_target(x string) bool {
	if x.len == 0 { return true }
	xl := o1_lower(x)
	if x.contains('[') || x.contains('.') { return true }
	if xl.starts_with('__cone_') { return true }
	if o1_is_plain_name(x) && !o1_is_reg(xl) { return true }
	return false
}

// 规则 1：部分读 -> 同时登记父寄存器读
fn o1_expand(ts []string) []string {
	mut out := []string{}
	for t in ts {
		out << t
		pa := o1_reg_alias(t)
		if pa != t && !(pa in out) { out << pa }
	}
	return out
}

fn o1_toks(x string) []string {
	mut out := []string{}
	if x.len == 0 { return out }
	mut cur := ''
	for i := 0; i <= x.len; i++ {
		mut c := u8(0)
		if i < x.len { c = x[i] }
		// 0.9.6：把 [ ] 也当分隔符，[eax+1] / [esp+4] 的隐式读不能整个丢掉
		sep := c == 43 || c == 42 || c == 45 || c == 32 || c == 9 || c == 91 || c == 93
		if !sep && i < x.len {
			cur += x[i..i + 1]
		} else {
			if cur.len > 0 {
				tl := o1_lower(cur)
				if !(tl == 'offset' || tl == 'addr' || tl == 'dword' || tl == 'word' || tl == 'byte' || tl == 'qword' || tl == 'ptr' || tl == 'short' || tl == 'near' || tl == 'far' || tl == 'st' || tl == 'st(0)') {
					mut dig := true
					for k := 0; k < cur.len; k++ {
						if cur[k] < 48 || cur[k] > 57 { dig = false }
					}
					if !dig && o1_is_plain_name(cur) { out << tl }
				}
			}
			cur = ''
		}
	}
	return out
}

// R1：读集合展开子寄存器别名（ax -> {ax, eax}），I3：push/pop 登记隐式 esp
fn o1_reads(op string, a string, b string) []string {
	mut out := []string{}
	if op == 'jmp' || op == 'ret' || op == 'retn' || op == 'retf' || op == 'nop' || op == 'end' || op == 'endp' { return out }
	if o1_in(o1_jcc, op) || op.starts_with('set') || op.starts_with('cmov') { return out }
	if op == 'mov' || op == 'lea' || op == 'movzx' || op == 'movsx' { return o1_expand(o1_toks(b)) }
	if op == 'push' || op == 'pop' {
		mut r := o1_expand(o1_toks(b))
		if b.len == 0 { r = o1_expand(o1_toks(a)) }
		r << 'esp'
		return r
	}
	for t in o1_expand(o1_toks(a)) { out << t }
	for t in o1_expand(o1_toks(b)) { out << t }
	return out
}

fn o1_def_target(op string, a string, _ string) string {
	if !o1_in(o1_defop, op) || a.len == 0 { return '' }
	if a.contains('[') || a.contains(':') || !o1_is_plain_name(a) { return '' }
	la := o1_lower(a)
	if la == 'offset' || la == 'addr' || la == 'dword' || la == 'word' || la == 'byte' || la == 'qword' || la == 'ptr' { return '' }
	if o1_is_subreg(la) { return '@partial:' + o1_reg_alias(la) }    // 规则 2：部分写只记 partial_def
	if o1_is_stackreg(la) { return '@stack:' + o1_reg_alias(la) }      // stack_related 不参与 A3/A4
	if !o1_is_parent32(la) { return '@mem:' + a }                       // R3：目标是内存位置
	return a
}

fn o1_is_hard(op string, st string) bool {
	if o1_in(o1_hard, op) || op.starts_with('rep') { return true }
	return st.contains('fs:[') || st.contains('gs:[')
}

// ---- 0.9.5 IR / 配置 / 结果结构 ----
struct O1Config {
	opts     string // -O1:子开关（逗号分隔，默认空 = A 组）
	src_path string // 仅回退 warning 定位用
}

struct O1IR {
	n           int
	region      []int    // 0 FROZEN / 1 OPAQUE / 2 OPEN
	barrier     []int    // 1 HARD / 2 FLAGS_KILL / 4 MEM_CLOBBER
	sentinel    []bool
	blank       []bool
	op          []string
	a           []string
	b           []string
	label       []string
	roots       map[string]bool
	first_after map[string]string
	skips       map[string]int // I2：跳过原因分类（P0 按行统计）
}

struct O1Flags {
mut:
	seh_thin       bool
	licm           bool
	memcse         bool
	peephole_aggr  bool
	report         bool
}

struct O1Tx {
	lines   []string
	deleted []bool
	hits    int
	counts  map[string]int
}

struct O1Full {
	text        string
	err         string
	counts      map[string]int
	rounds      int
	report_text string
	fallback    string
}

// ---- 0.9.6 R2 / I1 块级辅助（依赖 O1IR，故放在结构定义之后）----
fn o1_skip_block(ir O1IR, blk []int) bool {
	// R2 安全网：块内任一操作数是 8/16 位子寄存器 -> 该块禁用跨行 DSE/CSE
	for i in blk {
		for t in o1_toks(ir.a[i]) { if o1_is_subreg(t) { return true } }
		for t in o1_toks(ir.b[i]) { if o1_is_subreg(t) { return true } }
	}
	return false
}

fn o1_interval_fuse(ir O1IR, lines []string, i int) int {
	// I1：add r,1 之后、到下一次 flags 全覆盖写 / HARD / ret / 标号之前，
	// 所有 f_use 位的并集。HARD 是【边界】而非「抬活」。
	mut fuse := 0
	for j := i + 1; j < ir.n; j++ {
		st := lines[j].trim_space()
		if st.len == 0 { continue }
		if ir.sentinel[j] || ir.region[j] == 1 || (ir.barrier[j] & 1) != 0 || (ir.barrier[j] & 2) != 0 { break }
		if o1_is_label(st) { break }
		o := ir.op[j]
		if o == 'ret' || o == 'retn' || o == 'retf' || o == 'leave' || o == 'end' || o == 'endp' || o == 'exit' || o == 'jmp' { break }
		fuse = fuse | o1_f_use(o)        // adc/sbb 先读 CF，再写全覆盖 flags
		if o1_f_def(o) == o1_f_all { break }
		if o1_flags_read(o) { break }
	}
	return fuse
}

fn o1_result_read_after(ir O1IR, i int, end int) bool {
	// I1 白名单：r 的结果在变换后仍被后续读（含子寄存器别名读）
	parent := o1_reg_alias(ir.a[i])
	for j := i + 1; j < end && j < ir.n; j++ {
		for t in o1_reads(ir.op[j], ir.a[j], ir.b[j]) {
			if t == parent { return true }
		}
	}
	return false
}

fn o1_strip_sentinels(asm_text string) string {
	mut out := []string{}
	for l in asm_text.split('\n') {
		if l.trim_space() != o1_on && l.trim_space() != o1_off {
			out << l
		}
	}
	for out.len > 0 && out.last().trim_space().len == 0 {
		out.pop()
	}
	return out.join('\n') + '\n'
}

// ---- P0：分区 + IR 解析 + 根集合 ----
fn o1_partition(lines []string, seh_thin bool) O1IR {
	n := lines.len
	mut region := []int{len: n, init: 0}
	mut barrier := []int{len: n, init: 0}
	mut sentinel := []bool{len: n, init: false}
	mut blank := []bool{len: n, init: false}
	mut in_seg := false
	mut noopt := false
	mut pstart := -1
	mut pseh := false
	mut opaque := 0
	// I2：跳过原因分类（P0 按行统计；块级统计在 o1_transform 里累加）
	mut skips := map[string]int{}
	for k in ['frozen_proc', 'frozen_seg', 'opaque_masm', 'hard_invoke', 'hard_rep_x87',
		'subreg_guard', 'memwrite_guard', 'alias_guard', 'root_label', 'stack_guard', 'rep_guard'] {
		skips[k] = 0
	}
	for i := 0; i < n; i++ {
		raw := lines[i]
		st := raw.trim_space()
		if st == o1_on {
			noopt = true
			region[i] = 0
			sentinel[i] = true
			barrier[i] = 1
			continue
		}
		if st == o1_off {
			noopt = false
			region[i] = 0
			sentinel[i] = true
			barrier[i] = 1
			continue
		}
		if noopt {
			region[i] = 0
			barrier[i] = 1
			skips['frozen_proc']++
			continue
		}
		// §7.1 第 9 条：asm{} / defined 宏正文常以 tab 缩进；cone 自身生成用 4 空格。
		// 二次 O1（输入已无哨兵）也把 tab 行视为不透明，保证冻结区与幂等。
		if raw.len > 0 && raw[0] == 9 {
			region[i] = 0
			barrier[i] = 1
			continue
		}
		if st.contains(' segment ') || st.ends_with(' segment') { in_seg = true }
		if in_seg {
			region[i] = 0
			barrier[i] = 1
			skips['frozen_seg']++
			if st.ends_with(' ends') { in_seg = false }
			continue
		}
		if st.ends_with(' proc') || st.contains(' proc ') || st.starts_with('proc ') {
			pstart = i
			pseh = false
			region[i] = 0
			continue
		}
		if st.ends_with(' endp') || st.contains(' endp ') {
			if pseh && !seh_thin && pstart >= 0 {
				skips['frozen_proc'] += i - pstart + 1
				for j := pstart; j <= i; j++ { region[j] = 0 }
			}
			pstart = -1
			region[i] = 0
			continue
		}
		if pstart < 0 {
			region[i] = 0
			if st.len > 0 { skips['frozen_proc']++ }
			continue
		}
		// MASM 高级伪指令块 -> OPAQUE（RFC §3.2 第 5 条 / §7.1 第 8 条）
		if st.starts_with('.if') || st.starts_with('.while') || st.starts_with('.repeat') { opaque++ }
		if st.starts_with('.endif') || st.starts_with('.endw') || st.starts_with('.until') {
			if opaque > 0 { opaque-- }
		}
		if st.contains('__cone_seh_') || st.contains('fs:[0]') || st.contains('__cone_default') || st.contains('CONTEXT') || st.contains('ExceptionContinue') || st.contains('assume fs') {
			pseh = true
		}
		op := o1_op(st)
		if o1_in(o1_kill, op) { skips['hard_invoke']++ }
		if o1_is_hard(op, st) || op.starts_with('rep') || op.starts_with('fst') || op.starts_with('fld') {
			skips['hard_rep_x87']++
		}
		if op == 'push' || op == 'pop' { skips['stack_guard']++ }
		// I3：push/pop 是 stack_related，隐式读/写 esp -> HARD 屏障，禁止 A3 跨越
		if o1_is_hard(op, st) || opaque > 0 || op == 'push' || op == 'pop' {
			barrier[i] = 1
		} else if o1_in(o1_kill, op) {
			barrier[i] = 2 | 4
		} else if st.contains('[') {
			barrier[i] = 4
		}
		if st.len == 0 {
			blank[i] = true
			region[i] = 0
		} else if o1_is_label(st) {
			region[i] = 0
		} else if opaque > 0 {
			region[i] = 1
		} else if o1_in(o1_opt, op) || o1_flags_read(op) || op == 'jmp' || op == 'ret' || op == 'retn' || op == 'retf' || op == 'nop' {
			region[i] = 2
		} else {
			region[i] = 0
		}
		if opaque > 0 { skips['opaque_masm']++ }
		if region[i] == 0 && !sentinel[i] && !o1_in(o1_kill, op) { skips['frozen_proc']++ }
		// seh=thin：帧链相关行逐字冻结，其余 OPEN（默认关闭）
		if pseh && seh_thin {
			if st.contains('fs:[0]') || st.contains('CONTEXT') || st.contains('ExceptionContinue') || st.contains('__cone_seh_') || st.contains('__cone_default') || st.contains('__cone_sret') {
				region[i] = 0
				barrier[i] = 1
			}
		}
	}
	mut opa := []string{}
	mut aa := []string{}
	mut bb := []string{}
	mut lab := []string{}
	for i := 0; i < n; i++ {
		st := lines[i].trim_space()
		ag := o1_args2(o1_rest(st))
		opa << o1_op(st)
		aa << ag.a
		bb << ag.b
		if o1_is_label(st) { lab << st[..st.len - 1] } else { lab << '' }
	}
	// 根集合：end 目标 / SEH 与默认帧 / __cone_sret/stt/str/itmp（外部可达根）
	mut roots := map[string]bool{}
	for i := 0; i < n; i++ {
		st := lines[i].trim_space()
		if o1_is_label(st) {
			nm := st[..st.len - 1]
			if nm.contains('__cone_seh_') || nm.contains('__cone_default') || nm.contains('__cone_sret') || nm.contains('__cone_stt') || nm.contains('__cone_str') || nm.contains('__cone_itmp') {
				roots[nm] = true
			}
		}
		if opa[i] == 'end' && aa[i].len > 0 { roots[aa[i]] = true }
	}
	// I3：默认全局帧四个标号显式列入根集合（CONTEXT.Eip 改写跳入，外部可达）
	for r in ['__cone_default_seh_handler', '__cone_default_seh_dispatch',
		'__cone_default_entry', '__cone_seh_ret_stub'] {
		roots[r] = true
	}
	skips['root_label'] = roots.len
	// 标号 -> 之后第一条可执行指令的 op（跳转链 / CFG 感知 jmp 用）
	mut first_after := map[string]string{}
	for i := 0; i < n; i++ {
		if !o1_is_label(lines[i].trim_space()) { continue }
		mut nm := lines[i].trim_space()
		nm = nm[..nm.len - 1]
		mut j := i + 1
		for j < n && (lines[j].trim_space().len == 0 || o1_is_label(lines[j].trim_space())) { j++ }
		if j < n { first_after[nm] = o1_op(lines[j].trim_space()) } else { first_after[nm] = '' }
	}
	return O1IR{n: n, region: region, barrier: barrier, sentinel: sentinel, blank: blank,
		op: opa, a: aa, b: bb, label: lab, roots: roots, first_after: first_after, skips: skips}
}

// ---- P1：基本块（连续 OPEN 段；标号/跳转/屏障断块；空行不打断）----
fn o1_blocks(ir O1IR) [][]int {
	mut blocks := [][]int{}
	mut cur := []int{}
	for i := 0; i < ir.n; i++ {
		if ir.blank[i] { continue }
		if ir.sentinel[i] || ir.region[i] != 2 || ir.label[i].len > 0 {
			if cur.len > 0 { blocks << cur; cur = []int{} }
			continue
		}
		cur << i
		if ir.op[i] == 'jmp' || ir.op[i] == 'ret' || ir.op[i] == 'retn' || ir.op[i] == 'retf' || o1_in(o1_jcc, ir.op[i]) {
			blocks << cur
			cur = []int{}
		}
	}
	if cur.len > 0 { blocks << cur }
	return blocks
}

// ---- P2：反向位粒度 flags 活性 ----
fn o1_flags_liveness(ir O1IR, lines []string) []int {
	mut live := 0 // 文件 / 函数末尾之后无 flags 读
	mut live_after := []int{len: ir.n, init: 0}
	for i := ir.n - 1; i >= 0; i-- {
		live_after[i] = live
		st := lines[i].trim_space()
		op := ir.op[i]
		// 控制流终止（无论 OPEN / FROZEN）：函数边界隔离，之后无人读本函数 flags
		if op == 'ret' || op == 'retn' || op == 'retf' || op == 'leave' || op == 'end' || op == 'endp' || op == 'exit' {
			live = 0
			continue
		}
		if ir.sentinel[i] || ir.region[i] == 1 || (ir.barrier[i] & 1) != 0 {
			live = o1_f_all
			continue
		}
		if (ir.barrier[i] & 2) != 0 {
			live = 0 // call/invoke：FLAGS_KILL（A2，不是永久屏障）
			continue
		}
		if ir.region[i] == 0 {
			if st.len == 0 || o1_is_label(st) { continue }
			if op == 'nop' { live = 0; continue }
			if op == 'jmp' {
				tgt := ir.a[i]
				mut t := ''
				if tgt in ir.first_after { t = ir.first_after[tgt] }
				if o1_in(o1_jcc, t) || t.starts_with('set') { live = o1_f_use(t) }
				else if o1_in(o1_wrflags, t) || t == 'call' || t == 'invoke' || t == 'ret' || t == 'retn' || t == 'xor' { live = 0 }
				else if o1_barrier_live(st) { live = o1_f_all }
				else { live = 0 }
				continue
			}
			if op == 'call' || op == 'invoke' { live = 0; continue }
			if o1_in(o1_wrflags, op) { live = 0; continue }
			if o1_flags_read(op) { live = live | o1_f_use(op); continue }
			continue
		}
		// OPEN 行：gen/kill 按位推进
		live = live | o1_f_use(op)
		fd := o1_f_def(op)
		if fd == o1_f_all { live = 0 }
		else if fd > 0 { live = live & (o1_f_all ^ fd) }
	}
	return live_after
}

// ---- P3~P5：单轮变换 ----
fn o1_transform(lines []string, ir O1IR, live_after []int, fl O1Flags) O1Tx {
	n := ir.n
	mut out_lines := lines.clone()
	mut deleted := []bool{len: n, init: false}
	mut hits := 0
	mut cnt := map[string]int{}
	mut skips := map[string]int{}
	for sk in ir.skips.keys() { skips[sk] = ir.skips[sk] }
	mut i1_pos := map[int]bool{}   // I1 改写过的位置，A8 lea 折叠须互斥
	// ---- P3 单指令变换 ----
	for i := 0; i < n; i++ {
		if ir.region[i] != 2 || deleted[i] { continue }
		op := ir.op[i]
		mut x := ir.a[i]
		mut y := ir.b[i]
		// 0.9.4 辅助函数沿用：单指令变换只接受严格双操作数（cone 生成至多一个逗号）
		ag := o1_args(o1_rest(lines[i].trim_space()))
		if ag.ok {
			x = ag.a
			y = ag.b
		} else {
			continue
		}
		raw := lines[i]
		ind := o1_indent(raw)
		// A8: cmp reg,0 -> test reg,reg（AF 例外；test 使 AF 未定义）
		if op == 'cmp' && o1_is_reg(x) && o1_in(o1_imm0, o1_lower(y)) && (live_after[i] & o1_f_af) == 0 {
			out_lines[i] = ind + 'test ${x}, ${x}'
			cnt['cmp0->test'] = cnt['cmp0->test'] + 1
			hits++
			continue
		}
		// A8: mov reg,0 -> xor reg,reg（位粒度：xor 写 ALL flags，要求之后无读）
		if op == 'mov' && o1_is_reg(x) && o1_in(o1_imm0, o1_lower(y)) && live_after[i] == 0 {
			out_lines[i] = ind + 'xor ${x}, ${x}'
			cnt['mov0->xor'] = cnt['mov0->xor'] + 1
			hits++
			continue
		}
		// A7: mov r,r / lea r,[r] 删除（不写 flags）
		if op == 'mov' && x.len > 0 && y.len > 0 && o1_lower(x) == o1_lower(y) && o1_is_reg(x) {
			deleted[i] = true
			cnt['mov r,r'] = cnt['mov r,r'] + 1
			hits++
			continue
		}
		if op == 'lea' && x.len > 0 && y.len > 0 && o1_lower(y) == '[' + o1_lower(x) + ']' {
			deleted[i] = true
			cnt['lea r,[r]'] = cnt['lea r,[r]'] + 1
			hits++
			continue
		}
		// A7: 恒等代数化简（f_def=ALL，要求位粒度无读）
		if live_after[i] == 0 && o1_is_reg(x) {
			if (op == 'add' || op == 'sub' || op == 'or' || op == 'xor') && o1_in(o1_imm0, o1_lower(y)) {
				deleted[i] = true
				cnt['identity'] = cnt['identity'] + 1
				hits++
				continue
			}
			if op == 'and' && o1_in(o1_immm1, o1_lower(y)) {
				deleted[i] = true
				cnt['identity'] = cnt['identity'] + 1
				hits++
				continue
			}
			if op == 'imul' && o1_in(o1_imm1, o1_lower(y)) {
				deleted[i] = true
				cnt['identity'] = cnt['identity'] + 1
				hits++
				continue
			}
			if (op == 'shl' || op == 'shr' || op == 'sar') && o1_in(o1_imm0, o1_lower(y)) {
				deleted[i] = true
				cnt['identity'] = cnt['identity'] + 1
				hits++
				continue
			}
		}
		// ---- I1（0.9.6）：条件化 add r,1 指令选择 ----
		// f_use 含 CF -> 保留 add；不含 CF 非空 -> inc；空集 -> lea r,[r+1]。
		// 乘常数->shift 仍永久禁止；不做无条件 add->inc。
		if op == 'add' && o1_is_reg(x) && o1_in(o1_imm1, o1_lower(y)) && o1_is_parent32(x) && !o1_is_stackreg(x) && !o1_is_subreg(x) && !o1_is_mem_target(x) {
			mut repseg := false
			for k := 0; k < n; k++ {
				if k < i - 6 || k > i + 6 { continue }
				ok := ir.op[k]
				if ok.starts_with('rep') || ok == 'cld' || ok == 'std' || ok == 'movsd' || ok == 'movsw' || ok == 'movsb' { repseg = true }
			}
			if repseg && (o1_lower(x) == 'esi' || o1_lower(x) == 'edi' || o1_lower(x) == 'ecx') {
				skips['rep_guard']++
			} else {
				fuse := o1_interval_fuse(ir, lines, i)
				if (fuse & o1_f_cf) == 0 && o1_result_read_after(ir, i, i + 12) {
					if fuse == 0 {
						out_lines[i] = ind + 'lea ${x}, [${x}+1]'
						i1_pos[i] = true
						cnt['arith-lea'] = cnt['arith-lea'] + 1
						hits++
					} else {
						out_lines[i] = ind + 'inc ${x}'
						i1_pos[i] = true
						cnt['arith-inc'] = cnt['arith-inc'] + 1
						hits++
					}
				}
			}
		}
	}
	// ---- A9：cmp r,r 常量条件折叠（ZF=1 CF=0 OF=0 SF=0 PF=1）----
	for i := 0; i + 1 < n; i++ {
		if ir.region[i] != 2 || deleted[i] || ir.op[i] != 'cmp' || !o1_is_reg(ir.a[i]) { continue }
		if o1_lower(ir.a[i]) != o1_lower(ir.b[i]) { continue }
		mut j := i + 1
		for j < n && (lines[j].trim_space().len == 0 || o1_is_label(lines[j].trim_space())) { j++ }
		if j >= n || ir.region[j] != 2 || deleted[j] || !o1_flags_read(ir.op[j]) { continue }
		mut cc := ''
		if ir.op[j].starts_with('j') { cc = ir.op[j][1..] }
		always := cc == 'e' || cc == 'z' || cc == 'ae' || cc == 'nb' || cc == 'nc' || cc == 'be' || cc == 'na' || cc == 'ge' || cc == 'nl' || cc == 'le' || cc == 'ng' || cc == 'ns' || cc == 'no' || cc == 'p' || cc == 'pe'
		never := cc == 'ne' || cc == 'nz' || cc == 'b' || cc == 'c' || cc == 'nae' || cc == 'a' || cc == 'nbe' || cc == 'g' || cc == 'nle' || cc == 'l' || cc == 'nge' || cc == 's' || cc == 'o' || cc == 'np' || cc == 'po'
		if always {
			out_lines[j] = o1_indent(lines[j]) + 'jmp ' + ir.a[j]
			cnt['cc->jmp'] = cnt['cc->jmp'] + 1
			hits++
		} else if never {
			deleted[j] = true
			cnt['cc->del'] = cnt['cc->del'] + 1
			hits++
		}
	}
	// ---- P4（0.9.6 R1/R2/R3/R4）：块内跨行 DSE + 可用表达式 CSE ----
	// R2：块内出现任一 8/16 位子寄存器 -> 禁用跨行 DSE/CSE，退回 0.9.4 相邻两行窗口；
	// R3：仅「目标是 32 位通用寄存器」才允许删除，内存位置写一律不参与；
	// R4：别名不确定的块只局部跳过并计数，不整文件回退。
	blocks := o1_blocks(ir)
	for blk in blocks {
		if o1_skip_block(ir, blk) {
			skips['subreg_guard']++
			// 0.9.4 相邻窗口（严格复刻）：仅两条相邻 mov、目标为 32 位通用寄存器
			for q := 0; q + 1 < blk.len; q++ {
				i := blk[q]
				j := blk[q + 1]
				if deleted[i] || deleted[j] { continue }
				if ir.op[i] != 'mov' || ir.op[j] != 'mov' { continue }
				if !o1_is_parent32(ir.a[i]) || o1_is_stackreg(ir.a[i]) { continue }
				if o1_lower(ir.a[i]) != o1_lower(ir.a[j]) { continue }
				if (ir.barrier[i] & 1) != 0 || (ir.barrier[j] & 1) != 0 || (ir.barrier[i] & 2) != 0 || (ir.barrier[j] & 2) != 0 { continue }
				if ir.a[i].contains('[') || ir.a[j].contains('[') || ir.b[i].contains('[') || ir.b[j].contains('[') { continue }
				mut has_sub := false
				for t in o1_toks(ir.b[i]) { if o1_is_subreg(t) { has_sub = true } }
				for t in o1_toks(ir.b[j]) { if o1_is_subreg(t) { has_sub = true } }
				if has_sub { continue }
				if ir.b[i] == ir.b[j] || !o1_src_reads(ir.b[j], ir.a[i]) {
					deleted[i] = true
					cnt['DSE'] = cnt['DSE'] + 1
					hits++
				}
			}
			continue
		}
		mut last := map[string]int{}
		mut avail := map[string]int{}
		mut alias_parents := map[string]bool{}
		for i in blk {
			if deleted[i] { continue }
			op := ir.op[i]
			x := ir.a[i]
			y := ir.b[i]
			if (ir.barrier[i] & 1) != 0 || (ir.barrier[i] & 2) != 0 || o1_in(o1_kill, op) || op == 'push' || op == 'pop' || x.contains('[') || y.contains('[') {
				last = map[string]int{}
				avail = map[string]int{}
				continue
			}
			rd := o1_reads(op, x, y)
			for u in rd {
				if u in last { last[u] = -1 }   // R1：ax -> {ax, eax}，阻止前驱全写被判死
			}
			mut key := ''
			mut safe_target := o1_is_parent32(x) && !o1_is_stackreg(x) && !o1_is_mem_target(x) && x.len > 0 && y.len > 0
			if safe_target {
				for t in o1_toks(x) { if o1_is_subreg(t) { safe_target = false } }
				for t in o1_toks(y) { if o1_is_subreg(t) { safe_target = false } }
			}
			if op == 'mov' && safe_target {
				key = op + '|' + o1_lower(x) + '|' + o1_lower(y)
			}
			if key.len > 0 && key in avail && avail[key] >= 0 {
				deleted[i] = true
				cnt['CSE'] = cnt['CSE'] + 1
				hits++
				continue
			}
			d := o1_def_target(op, x, y)
			if d.starts_with('@partial:') {
				skips['alias_guard']++
				parts := d.split(':')
				if parts.len > 1 { alias_parents[parts[1]] = true }
				continue
			}
			if d.starts_with('@stack:') {
				skips['stack_guard']++
				last = map[string]int{}
				avail = map[string]int{}
				continue
			}
			if d.starts_with('@mem:') {
				skips['memwrite_guard']++       // 可观测内存写：自身不删，且截断传播
				last = map[string]int{}
				avail = map[string]int{}
				continue
			}
			if d.len > 0 {
				dl := o1_lower(d)
				if dl in alias_parents {
					skips['alias_guard']++
					continue
				}
				if dl in last && last[dl] >= 0 && !o1_src_reads(y, d) {
					deleted[last[dl]] = true
					cnt['DSE'] = cnt['DSE'] + 1
					hits++
				}
				last[dl] = i
				mut killed := []string{}
				for ak in avail.keys() {
					parts := ak.split('|')
					if parts.len >= 3 && (parts[1] == dl || parts[2] == dl) { killed << ak }
				}
				for ak in killed { avail[ak] = -1 }
			}
			if key.len > 0 { avail[key] = i }
		}
	}
	// ---- A10：match 判别值链直接 case 去重（独立扫描，跨 je 断块）----
	// je 会把 CFG 切成不同基本块，但判别链是「无标号 / 无写 S / 无调用 / 无屏障」
	// 的连续裸指令流；文本相同的直接 case，后一对恒不跳 -> 删。
	mut ai := 0
	for ai < n {
		if ir.region[ai] != 2 || deleted[ai] || ir.op[ai] != 'cmp' || ir.a[ai].len == 0 || ir.b[ai].len == 0 {
			ai++
			continue
		}
		if !o1_is_plain_name(ir.b[ai]) || o1_lower(ir.b[ai]).starts_with('0x') || ir.b[ai].contains('(') {
			ai++
			continue
		}
		mut seen := map[string]bool{}
		mut aj := ai
		mut chained := false
		for aj + 1 < n {
			if deleted[aj] || deleted[aj + 1] || ir.region[aj] != 2 || ir.region[aj + 1] != 2 { break }
			if ir.op[aj] != 'cmp' || ir.op[aj + 1] != 'je' { break }
			if ir.a[aj] != ir.a[ai] || !o1_is_plain_name(ir.b[aj]) || ir.b[aj].contains('(') { break }
			if (ir.barrier[aj] & 1) != 0 || (ir.barrier[aj + 1] & 1) != 0 || (ir.barrier[aj] & 2) != 0 || (ir.barrier[aj + 1] & 2) != 0 { break }
			ck := o1_lower(ir.a[aj]) + '|' + o1_lower(ir.b[aj])
			if ck in seen {
				deleted[aj] = true
				deleted[aj + 1] = true
				cnt['match-dedup'] = cnt['match-dedup'] + 1
				hits++
			} else {
				seen[ck] = true
			}
			chained = true
			aj += 2
		}
		if chained { ai = aj } else { ai++ }
	}
	// ---- A5：jmp 之后、下一个标号之前的直落死代码（白名单严格，段内无标号）----
	for i := 0; i + 1 < n; i++ {
		if deleted[i] || ir.region[i] != 2 || ir.op[i] != 'jmp' { continue }
		mut j := i + 1
		for j < n && lines[j].trim_space().len == 0 { j++ }
		if j >= n || o1_is_label(lines[j].trim_space()) { continue }
		mut k := j
		mut dead := []int{}
		for k < n && lines[k].trim_space().len > 0 && !o1_is_label(lines[k].trim_space()) {
			st := lines[k].trim_space()
			o2 := o1_op(st)
			if o1_in(o1_del_ok, o2) && !st.contains('[') && ir.region[k] == 2 && !deleted[k] {
				dead << k
			} else {
				dead = []int{}
				break
			}
			k++
		}
		if dead.len > 0 && k < n && o1_is_label(lines[k].trim_space()) {
			for q in dead {
				deleted[q] = true
				cnt['dead-code'] = cnt['dead-code'] + 1
				hits++
			}
		}
	}
	// ---- P5 / A6：jmp-to-next 泛化（允许夹空行 / 连续标号）----
	for i := 0; i + 1 < n; i++ {
		if deleted[i] || ir.region[i] != 2 || ir.sentinel[i] || ir.op[i] != 'jmp' { continue }
		tgt := ir.a[i]
		if tgt.len == 0 || tgt in ir.roots || tgt.contains('__cone_seh_') || tgt.contains('__cone_default') { continue }
		mut j := i + 1
		mut seen := false
		for j < n && (lines[j].trim_space().len == 0 || (o1_is_label(lines[j].trim_space()) && !deleted[j])) {
			if o1_is_label(lines[j].trim_space()) && lines[j].trim_space()[..lines[j].trim_space().len - 1] == tgt {
				seen = true
				break
			}
			j++
		}
		if seen {
			deleted[i] = true
			cnt['jmp->next'] = cnt['jmp->next'] + 1
			hits++
			continue
		}
		// A6 跳转链：L 标号后第一条可执行是 jmp L2 -> 重定向
		mut fa := ''
		if tgt in ir.first_after { fa = ir.first_after[tgt] }
		if fa == 'jmp' {
			mut t := -1
			for q := 0; q < n; q++ {
				if o1_is_label(lines[q].trim_space()) && lines[q].trim_space()[..lines[q].trim_space().len - 1] == tgt {
					t = q
					break
				}
			}
			if t >= 0 {
				mut m := t + 1
				for m < n && (lines[m].trim_space().len == 0 || o1_is_label(lines[m].trim_space())) { m++ }
				if m < n && ir.op[m] == 'jmp' && ir.b[m].len == 0 && ir.a[m].len > 0 && ir.a[m] != tgt && !(ir.a[m] in ir.roots) {
					out_lines[i] = o1_indent(lines[i]) + 'jmp ' + ir.a[m]
					cnt['jump-thread'] = cnt['jump-thread'] + 1
					hits++
				}
			}
		}
	}
	// ---- A8 lea 折叠（仅 :peephole=aggr）----
	if fl.peephole_aggr {
		for i := 0; i + 1 < n; i++ {
			if deleted[i] || deleted[i + 1] || ir.region[i] != 2 || ir.region[i + 1] != 2 { continue }
			if i + 1 in i1_pos { continue }        // I1 与 A8 lea 折叠互斥
			if ir.op[i] == 'mov' && ir.op[i + 1] == 'add' && ir.a[i].len > 0 && o1_lower(ir.a[i]) == o1_lower(ir.a[i + 1]) && o1_is_reg(ir.a[i]) && o1_is_reg(ir.b[i]) && ir.b[i + 1].len > 0 && live_after[i + 1] == 0 && o1_lower(ir.a[i]) != o1_lower(ir.b[i]) {
				out_lines[i] = o1_indent(lines[i]) + 'lea ${ir.a[i]}, [${ir.b[i]}+${ir.b[i + 1]}]'
				deleted[i + 1] = true
				cnt['lea-fold'] = cnt['lea-fold'] + 1
				hits++
			}
		}
	}
	for sk in skips.keys() { cnt['skip:' + sk] = skips[sk] }
	return O1Tx{lines: out_lines, deleted: deleted, hits: hits, counts: cnt}
}

// ---- 单轮：解析 -> 活性 -> 变换 -> 拼回（哨兵保留到 P7）----
fn o1_one_round(asm_text string, fl O1Flags) (string, int, map[string]int) {
	lines := asm_text.split('\n')
	ir := o1_partition(lines, fl.seh_thin)
	live_after := o1_flags_liveness(ir, lines)
	tx := o1_transform(lines, ir, live_after, fl)
	mut out := []string{}
	for i := 0; i < lines.len; i++ {
		if !tx.deleted[i] { out << tx.lines[i] }
	}
	return out.join('\n'), tx.hits, tx.counts
}

// ---- 全量：不动点 + P7 + 报告 ----
fn o1_optimize_full(asm_text string, o1_opts string) O1Full {
	mut fl := O1Flags{}
	for sub in o1_opts.split(',') {
		t := sub.trim_space()
		if t == 'seh=thin' { fl.seh_thin = true }
		if t == 'licm=on' { fl.licm = true }
		if t == 'memcse=on' { fl.memcse = true }
		if t == 'peephole=aggr' { fl.peephole_aggr = true }
		if t == 'report' { fl.report = true }
	}
	mut cur := asm_text
	mut counts := map[string]int{}
	mut prev_hits := -1
	mut rounds := 0
	mut converged := false
	mut err := ''
	mut outs := []string{}          // I4：周期振荡检测（add <-> lea 来回改写）
	for rnd := 0; rnd < o1_rounds_max; rnd++ {
		rounds = rnd + 1
		nxt, hits, cnt := o1_one_round(cur, fl)
		for k in cnt.keys() {
			if k.starts_with('skip:') {
				if counts[k] < cnt[k] { counts[k] = cnt[k] }   // 跳过统计按单轮最大，不累加
			} else {
				counts[k] = counts[k] + cnt[k]
			}
		}
		// I4：同一位置不得在相邻两轮被不同规则反复改写（防 add <-> lea 振荡）
		if outs.len >= 2 && nxt == outs[outs.len - 2] && nxt != outs[outs.len - 1] {
			err = '不动点出现周期振荡（同位置反复改写），已回退'
			break
		}
		outs << nxt
		// 命中数【非递增】（防振荡）+ 轮数上限 + 文本收敛；cone 的 jmp 连锁删除会稳定 1,1,1,0
		if prev_hits >= 0 && hits > prev_hits {
			err = '不动点命中数反弹（第 ${rounds} 轮 ${hits} > 上轮 ${prev_hits}）'
			break
		}
		prev_hits = hits
		if nxt == cur || hits == 0 {
			converged = true
			cur = nxt
			break
		}
		cur = nxt
	}
	if !converged {
		if err.len == 0 { err = '不动点超过 ${o1_rounds_max} 轮未收敛' }
		return O1Full{err: err, counts: counts, rounds: rounds}
	}
	cur = o1_strip_sentinels(cur)
	if cur.contains(o1_on) || cur.contains(o1_off) {
		return O1Full{err: 'O1 哨兵残留（pass 内部不一致）', counts: counts, rounds: rounds}
	}
	mut total := 0
	for k in counts.keys() { if !k.starts_with('skip:') { total += counts[k] } }
	mut report_text := ''
	if fl.report {
		report_text = '[cone -O1:report] 轮数=${rounds} 命中=${total}\n'
		mut body := ''
		for k in counts.keys() {
			if !k.starts_with('skip:') && counts[k] > 0 { body += '${k}=${counts[k]} ' }
		}
		if body.len == 0 { report_text += '  （无变换命中）\n' } else { report_text += '  ' + body.trim_space() + '\n' }
		mut l1 := '  skip: '
		for k in ['frozen_proc', 'frozen_seg', 'opaque_masm', 'hard_invoke', 'hard_rep_x87'] {
			l1 += '${k}=${counts['skip:' + k]} '
		}
		mut l2 := '        '
		for k in ['subreg_guard', 'memwrite_guard', 'alias_guard', 'root_label', 'stack_guard', 'rep_guard'] {
			l2 += '${k}=${counts['skip:' + k]} '
		}
		report_text += l1.trim_space() + '\n' + l2.trim_space() + '\n'
		report_text += '  子开关: seh=' + (if fl.seh_thin { 'on' } else { 'off' }) +
			' licm=' + (if fl.licm { 'on' } else { 'off' }) +
			' memcse=' + (if fl.memcse { 'on' } else { 'off' }) +
			' peephole=' + (if fl.peephole_aggr { 'on' } else { 'off' }) + ' report=on\n'
	}
	return O1Full{text: cur, counts: counts, rounds: rounds, report_text: report_text}
}

// ---- 薄包装：仅 -O1 调用；异常 / 显式失败 -> 回退未优化 asm + warning ----
fn o1_optimize(asm_text string, cfg O1Config) string {
	r := o1_optimize_full(asm_text, cfg.opts)
	if r.err.len > 0 {
		eprintln('${cfg.src_path}:0: warning: -O1 pass 已回退到未优化 .asm：${r.err}')
		return o1_strip_sentinels(asm_text)
	}
	if r.report_text.len > 0 {
		print(r.report_text)
	}
	return r.text
}
