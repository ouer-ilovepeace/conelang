module main

// ---------- 类型 / 名字辅助 ----------

fn typedef_base_masm(base string) string {
	if base == 'byte' {
		return 'byte'
	}
	if base == 'word' {
		return 'word'
	}
	if base == 'int' {
		return 'dword'
	}
	if base == 'long' {
		return 'qword'
	}
	if base == 'f32' {
		return 'real4'
	}
	if base == 'f64' {
		return 'real8'
	}
	return base
}

fn proto_param_type(st SymTab, name string) string {
	if name in st.typedefs {
		return name
	}
	return st.type_masm[name]
}

fn conv_str(c CallConv) string {
	if c == CallConv.cc_stdcall {
		return 'stdcall'
	}
	if c == CallConv.cc_c {
		return 'C'
	}
	return ''
}

// cone 0.9.2 coneABI：只要函数声明了结构体返回类型，就用「调用者结构体指针」
// 作第一个隐式参数返回（不分大小）；无中转缓冲、无调用后二次拷贝。
fn is_sret_fn(st SymTab, target string) bool {
	return st.func_ret_is_struct[target]
}

fn call_target(full string) string {
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
	if dot >= 0 {
		return full[dot + 1..]
	}
	return full
}

fn resolve_name(st SymTab, fname string, name string) string {
	// cone 0.6 fix1：不再做名称修饰 —— 局部变量 / 形参 / 全局符号一律用原名。
	// MASM32 的 PROC 局部名是函数作用域，与全局同名不冲突；寄存器也直接透传。
	if is_reg_name(name) {
		return name
	}
	key := name_key(fname, name)
	if key in st.name_maps {
		ni := st.name_maps[key]
		return ni.masm
	}
	return name
}

fn is_stack_name(st SymTab, fname string, name string) bool {
	if is_reg_name(name) {
		return false
	}
	key := name_key(fname, name)
	if key in st.name_maps {
		ni := st.name_maps[key]
		return ni.is_stack
	}
	return false
}

fn addr_target(prog Program, idx int) string {
	e := prog.exprs[idx]
	return prog.exprs[e.a].text
}

fn addr_is_stack(prog Program, st SymTab, fname string, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind != ExprKind.expr_addr {
		return false
	}
	inner := prog.exprs[e.a]
	if inner.kind != ExprKind.expr_ident {
		return false
	}
	return is_stack_name(st, fname, inner.text)
}

fn addr_is_global(prog Program, st SymTab, fname string, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind != ExprKind.expr_addr {
		return false
	}
	inner := prog.exprs[e.a]
	if inner.kind != ExprKind.expr_ident {
		return false
	}
	return !is_stack_name(st, fname, inner.text)
}

// hidden_name: 隐藏符号与用户全局符号冲突就反复加下划线。
// 注意：这里必须用 `for (n in globals)` 这种带括号的条件循环；
// 不加括号的 `for n in globals` 是 map 值迭代，会与外层 mut n 冲突（V 0.5.1 实机报错）。
fn hidden_name(base string, globals map[string]bool) string {
	mut n := base
	for (n in globals) {
		n = '_' + n
	}
	return n
}

// cone 0.84：把任意名字（尤其 seg 段名 ".fuckyou"）净化成合法 MASM 标号片段。
// MASM 标识符只允许 字母 / 数字 / _ ? @ $；其余字符一律换成 '_'。
// 之前 seg 裸代码把段名直接拼进 SEH 标号，得到 `__cone_seh_.fuckyou_1_dispatch`，
// 临时 option dotname 下 ml 报 A2008: syntax error : .fuckyou_1_dispatch。
fn label_safe(s string) string {
	mut r := ''
	mut i := 0
	for i < s.len {
		c := s[i]
		if (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 63 || c == 64 || c == 36 {
			r = r + s[i..i + 1]
		} else {
			r = r + '_'
		}
		i = i + 1
	}
	return r
}

// ---------- 尺寸辅助 ----------

fn reg_name(size int) string {
	if size == 1 {
		return 'al'
	}
	if size == 2 {
		return 'ax'
	}
	return 'eax'
}

fn size_ptr(size int) string {
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

fn sign_term(sign int, text string) string {
	if sign < 0 {
		return '-' + text
	}
	return '+' + text
}

fn strip_leading_plus(s string) string {
	if s.len > 0 && s[0] == 43 { // '+'
		return s[1..]
	}
	return s
}

// expr_has_call: 表达式（含 [] 地址表达式）里是否出现函数调用。
// 函数调用的结果在 eax，MASM invoke 的 addr 宏也是 lea eax，二者会互相覆盖，
// 因此它决定 invoke 里能否直接用 addr，以及二元表达式能否走两指令优化路径。
fn expr_has_call(prog Program, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_call {
		for a in e.args {
			if expr_has_call(prog, a) {
				return true
			}
		}
		return true
	}
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr || e.kind == ExprKind.expr_deref {
		return expr_has_call(prog, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		return expr_has_call(prog, e.a) || expr_has_call(prog, e.b)
	}
	return false
}

// ---------- 段布局 / 头部指令 ----------

struct AsmEntry {
	order   int
	section Section
	text    string
}

fn sorted_entries(src []AsmEntry) []AsmEntry {
	mut a := []AsmEntry{}
	for x in src {
		a << x
	}
	mut i := 1
	for i < a.len {
		mut j := i
		for j > 0 && a[j].order < a[j - 1].order {
			tmp := a[j]
			a[j] = a[j - 1]
			a[j - 1] = tmp
			j = j - 1
		}
		i = i + 1
	}
	return a
}

struct HeaderLine {
	order int
	text  string
}

fn sorted_headers(src []HeaderLine) []HeaderLine {
	mut a := []HeaderLine{}
	for x in src {
		a << x
	}
	mut i := 1
	for i < a.len {
		mut j := i
		for j > 0 && a[j].order < a[j - 1].order {
			tmp := a[j]
			a[j] = a[j - 1]
			a[j - 1] = tmp
			j = j - 1
		}
		i = i + 1
	}
	return a
}

// ---------- cone 0.4：MASM STRUCT / ENDS ----------
// 嵌套结构体必须先定义被引用者，按依赖做一次稳定的拓扑排序。
fn ordered_structs(prog Program, st SymTab) []StructDef {
	mut out := []StructDef{}
	mut done := map[string]bool{}
	mut guard := 0
	for guard < 64 {
		mut changed := false
		for sd in prog.structs {
			if sd.name in done {
				continue
			}
			mut ready := true
			for m in sd.members {
				b := resolve_base_type(st, m.typ_name)
				if b in st.struct_size && b != sd.name && !(b in done) {
					ready = false
				}
			}
			if ready {
				out << sd
				done[sd.name] = true
				changed = true
			}
		}
		if !changed {
			break
		}
		guard = guard + 1
	}
	for sd in prog.structs {
		if !(sd.name in done) {
			out << sd
		}
	}
	return out
}

fn render_struct_defs(prog Program, st SymTab) []string {
	mut lines := []string{}
	for sd in ordered_structs(prog, st) {
		lines << '${sd.name} struct'
		// cone 0.9prelease：align 结构体在成员之前 / 尾部显式插 _padding_N BYTE n dup(?)
		pads := st.struct_pads[sd.name]
		mut pad_no := 0
		mut mi := 0
		for mi < sd.members.len {
			m := sd.members[mi]
			for pd in pads {
				if !pd.is_tail && pd.mi == mi {
					lines << '    _padding_${pad_no} BYTE ${pd.nb} dup(?)'
					pad_no = pad_no + 1
				}
			}
			b := resolve_base_type(st, m.typ_name)
			mut dir := 'DWORD'
			mut is_struct_field := false
			if b in st.struct_size {
				dir = b
				is_struct_field = true
			} else if b in st.struct_extern {
				dir = st.type_masm[b]
				is_struct_field = true
			} else if b in st.type_masm {
				dir = st.type_masm[b]
			}
			if m.array_len.len > 0 && is_struct_field {
				// STRUCT 类型的数组成员：MASM32 要 dup(<>)，不能用 dup(?)
				lines << '    ${m.name} ${dir} ${m.array_len} dup(<>)'
			} else if m.array_len.len > 0 {
				lines << '    ${m.name} ${dir} ${m.array_len} dup(?)'
			} else if is_struct_field {
				// 嵌套 STRUCT / 外部 win.STRUCT 成员需要 <> 初值，不能用 ?
				lines << '    ${m.name} ${dir} <>'
			} else {
				lines << '    ${m.name} ${dir} ?'
			}
			mi = mi + 1
		}
		for pd in pads {
			if pd.is_tail {
				lines << '    _padding_${pad_no} BYTE ${pd.nb} dup(?)'
				pad_no = pad_no + 1
			}
		}
		lines << '${sd.name} ends'
		lines << ''
	}
	return lines
}

fn section_of(v VarDef) Section {
	if v.is_const {
		return Section.sec_const
	}
	if v.has_init_list {
		return Section.sec_data
	}
	if v.array_len.len > 0 {
		return Section.sec_data_uninit
	}
	if v.init_idx >= 0 {
		return Section.sec_data
	}
	return Section.sec_data_uninit
}

fn section_name(s Section) string {
	if s == Section.sec_const {
		return '.const'
	}
	if s == Section.sec_data {
		return '.data'
	}
	return '.data?'
}

fn render_data_def(prog Program, d DataDef) string {
	mut parts := []string{}
	for idx in d.items {
		parts << render_raw(prog, idx)
	}
	return '${d.name} db ' + parts.join(',')
}

// cone 0.9.2：align 结构体在 MASM 侧被插入了 _padding_N 字段，
// 初始化 <...> 必须按 MASM 字段顺序一一对应：cone 成员前的 padding 用 <> 占位
// （取该字段定义时的默认值），否则初值会错位到 padding 字段上。
// 尾部 padding 不需占位（MASM 允许列表短于字段数，剩余用默认值）。
fn mi_has_pad(pads []PadInfo, mi int) bool {
	for pd in pads {
		if !pd.is_tail && pd.mi == mi {
			return true
		}
	}
	return false
}

fn struct_init_parts(prog Program, st SymTab, type_name string, items []int) []string {
	b := resolve_base_type(st, type_name)
	pads := st.struct_pads[b]
	mut parts := []string{}
	for i, it in items {
		if mi_has_pad(pads, i) {
			parts << '<>'
		}
		if it < 0 {
			parts << '?'
		} else {
			parts << render_raw(prog, it)
		}
	}
	return parts
}

fn render_var(prog Program, st SymTab, v VarDef) string {
	b := resolve_base_type(st, v.typ_name)
	if b in st.struct_size || b in st.struct_extern {
		mut parts := []string{}
		if v.has_init_list {
			parts = struct_init_parts(prog, st, v.typ_name, v.init_items)
		}
		return '${v.name} ${st.type_masm[b]} <${parts.join(',')}>'
	}
	dir := st.type_dir[v.typ_name]
	if v.array_len.len > 0 {
		return '${v.name} ${dir} ${v.array_len} dup(?)'
	}
	if v.init_idx >= 0 {
		return '${v.name} ${dir} ${render_init(prog, v.init_idx)}'
	}
	return '${v.name} ${dir} ?'
}

// ---------- 浮点常量池 ----------

struct FloatCollector {
	prog  Program
	st    SymTab
	fname string
mut:
	texts []string
}

fn (mut c FloatCollector) add(text string) {
	for t in c.texts {
		if t == text {
			return
		}
	}
	c.texts << text
}

fn (mut c FloatCollector) walk(idx int, in_float bool) {
	if idx < 0 || idx >= c.prog.exprs.len {
		return
	}
	e := c.prog.exprs[idx]
	// cone 0.6：float(N) 里的整数字面量也要造一个 REAL4 <N> 常量（fld 只能读内存）
	if e.is_float_hint && e.kind == ExprKind.expr_num {
		c.add(e.text)
		return
	}
	if e.kind == ExprKind.expr_num {
		if in_float && is_float_lit(e.text) {
			c.add(e.text)
		}
		return
	}
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr {
		mut f := false
		if in_float {
			f = true
		}
		if expr_is_float(c.prog, c.st, c.fname, idx) {
			f = true
		}
		c.walk(e.a, f)
		return
	}
	if e.kind == ExprKind.expr_deref {
		// 地址表达式里不会有浮点字面量（语义层已禁止），解引用结果按原始 dword 位处理
		c.walk(e.a, false)
		return
	}
	if e.kind == ExprKind.expr_bin {
		mut f := false
		if in_float {
			f = true
		}
		if expr_is_float(c.prog, c.st, c.fname, idx) {
			f = true
		}
		c.walk(e.a, f)
		c.walk(e.b, f)
		return
	}
	if e.kind == ExprKind.expr_call {
		for a in e.args {
			mut f := false
			if expr_is_float(c.prog, c.st, c.fname, a) {
				f = true
			}
			c.walk(a, f)
		}
		return
	}
}

fn collect_float_literals(prog Program, st SymTab) []string {
	mut result := []string{}
	for f in prog.funcs {
		mut c := FloatCollector{
			prog:  prog
			st:    st
			fname: f.name
			texts: []string{}
		}
		for s in f.body {
			if s.kind == StmtKind.st_return {
				c.walk(s.ret_idx, false)
			}
			if s.kind == StmtKind.st_assign {
				// cone 0.4 fix：[] / 结构体成员也能作浮点左值，右值里的浮点字面量
				// 必须进 .const 池（否则 fld __cone_flt_N 引用不存在的标签）。
				c.walk(s.rhs_idx, expr_has_float_lit(prog, s.rhs_idx))
			}
			if s.kind == StmtKind.st_call {
				c.walk(s.call_idx, false)
			}
			if s.kind == StmtKind.st_if || s.kind == StmtKind.st_elseif {
				c.walk(s.cond_idx, false)
			}
			// cone 0.6 fix1：match 判别值 / case 值 / for 条件 / ++-- 目标里的
			// 浮点字面量同样要进 REAL4 常量池，否则会引用不存在的 __cone_flt_N。
			if s.kind == StmtKind.st_match {
				c.walk(s.cond_idx, expr_has_float_lit(prog, s.cond_idx))
			}
			if s.kind == StmtKind.st_case {
				c.walk(s.case_idx, expr_has_float_lit(prog, s.case_idx))
			}
			if s.kind == StmtKind.st_for && !s.is_forever {
				c.walk(s.cond_idx, expr_has_float_lit(prog, s.cond_idx))
			}
			if s.kind == StmtKind.st_inc || s.kind == StmtKind.st_dec {
				c.walk(s.target_idx, false)
			}
		}
		for t in c.texts {
			mut dup := false
			for r in result {
				if r == t {
					dup = true
				}
			}
			if !dup {
				result << t
			}
		}
	}
	return result
}

fn make_float_labels(texts []string, globals map[string]bool) map[string]string {
	mut m := map[string]string{}
	mut i := 0
	for t in texts {
		mut name := '__cone_flt_${i}'
		// 同样必须用带括号的条件循环
		for (name in globals) {
			name = '_' + name
		}
		m[t] = name
		i = i + 1
	}
	return m
}

// ---------- cone 0.3：字符常量池 ----------
//
// 表达式位置的字符串字面量（expr_str.is_char_const）展开成 MASM 字节序列，
// 按【展开后的文本】去重，标签 __cone_str_N 与用户全局符号冲突就反复加下划线。
// 调用时传的是常量地址（offset label），所以 `win.crt_printf("Hello\r\n")`
// 与 `hello:"Hello",0dh,0ah,0` + `win.crt_printf(addr hello)` 等价。

fn collect_char_consts(prog Program) []string {
	mut result := []string{}
	for e in prog.exprs {
		if e.kind != ExprKind.expr_str || !e.is_char_const {
			continue
		}
		text := char_const_text(e.text)
		mut dup := false
		for t in result {
			if t == text {
				dup = true
			}
		}
		if !dup {
			result << text
		}
	}
	return result
}

fn make_char_labels(texts []string, globals map[string]bool) map[string]string {
	mut m := map[string]string{}
	mut i := 0
	for t in texts {
		mut name := '__cone_str_${i}'
		for (name in globals) {
			name = '_' + name
		}
		m[t] = name
		i = i + 1
	}
	return m
}

fn char_label_of(lit string, labels map[string]string) string {
	text := char_const_text(lit)
	if text in labels {
		return labels[text]
	}
	return '__cone_str_missing'
}

// ---------- cone 0.6：结构体常量池 ----------
// 参考 __cone_str_N 的设计：按 (类型 + 初值文本) 去重，生成 __cone_stt_N 隐名标签，
// 与用户全局符号冲突就反复加下划线。默认作为 MASM32 侧的直接结构体（按值传参），
// 写 addr Type{...} 则取这个隐名标签的地址。
struct StructConst {
	key       string
	type_name string
	items     []int
}

fn collect_struct_consts(prog Program) []StructConst {
	mut result := []StructConst{}
	for e in prog.exprs {
		if !e.is_struct_lit {
			continue
		}
		mut dup := false
		for r in result {
			if r.key == e.text {
				dup = true
			}
		}
		if !dup {
			mut items := []int{}
			for it in e.lit_items {
				items << it
			}
			result << StructConst{
				key:       e.text
				type_name: e.lit_type
				items:     items
			}
		}
	}
	return result
}

fn make_struct_labels(consts []StructConst, globals map[string]bool) map[string]string {
	mut m := map[string]string{}
	mut i := 0
	for c in consts {
		mut name := '__cone_stt_${i}'
		for (name in globals) {
			name = '_' + name
		}
		m[c.key] = name
		i = i + 1
	}
	return m
}

fn struct_label_of(key string, labels map[string]string) string {
	if key in labels {
		return labels[key]
	}
	return '__cone_stt_missing'
}

fn float_label_of(text string, labels map[string]string) string {
	if text in labels {
		return labels[text]
	}
	return '__cone_flt_missing'
}

fn render_struct_const(prog Program, c StructConst, st SymTab, labels map[string]string) string {
	parts := struct_init_parts(prog, st, c.type_name, c.items)
	return '${struct_label_of(c.key, labels)} ${win_masm_name(c.type_name)} <${parts.join(',')}>'
}

// ---------- 生成上下文 ----------

// IfFrame: 降级 if 链的标签状态。MASM `.if` 路径只用 degraded=false。
// tag 里带函数名：每个函数的 if_id 都从 0 开始，不加函数名会让两个函数
// 都生成 __cone_if_0_end，MASM 侧标签重复定义。
struct IfFrame {
	id       int
	tag      string // 标签前缀 = __cone_if_<函数名>_<id>
	end      string
	pending  string // 下一个"条件为假"要落到的标签
	clause   int
	degraded bool
mut:
	plans    []CondPlan // .if 链各分支的 mem-mem 中转计划（仅非降级路径）
	plan_idx int        // 下一个 st_elseif 该用 plans[plan_idx]
}

// LoopFrame: for 循环的标签栈。
//   degraded=false -> MASM `.while` / `.endw`，break/continue 直接出 `.break` / `.continue`
//   degraded=true  -> cone 自己算条件 + 显式标签，break/continue 出 jmp
struct LoopFrame {
	id       int
	tag      string
	cond_lbl string
	body_lbl string
	end_lbl  string
	degraded bool
	forever  bool
}

// MatchFrame: cone 0.5 match 链的标签栈。
// 跳转表在 st_match 一次性发出（前瞻收集全部 case 值），各分支体由标记流驱动。
struct MatchFrame {
mut:
	tag     string
	end     string
	def     string
	cases   []string
	cur     int
	started bool
}

// cone 0.7：try/except 的 SEH 帧。每个 try 在栈上装一个扩展的
// EXCEPTION_REGISTRATION = [prev:dd][handler:dd][code:dd]（第 3 项存异常码，
// 每帧独立，嵌套 / 递归不共享状态）。
struct TryFrame {
mut:
	tag        string
	codes      []string // 各 except 的 ErrorType 渲染文本；通配分支为空串占位
	has_any    bool     // 是否存在不带 ErrorType 的 except（匹配所有）
	cur        int      // 当前正在发射第几个 except
	dispatch   bool     // 跳转表 / jmp normal 是否已发射
	needs_ret  bool     // try/except 体内出现过 return，需要帧卸载后的统一 ret 汇合点
}

struct GenCtx {
	prog         Program
	st           SymTab
	fname        string
	float_labels map[string]string
	char_labels  map[string]string
	stt_labels   map[string]string // cone 0.6：结构体常量键 -> __cone_stt_N
	itmp         string
mut:
	lines      []string
	if_stack   []IfFrame
	if_id      int
	loop_stack []LoopFrame
	loop_id    int
	body        []Stmt // 当前函数的摊平语句流（条件链前瞻 / 寄存器占用扫描）
	body_pos    int    // 当前语句在 body 中的下标
	match_id    int
	match_stack []MatchFrame
	try_stack   []TryFrame // cone 0.7：SEH 帧栈
	o1          bool      // cone 0.9.4：实验性 -O1，注入 asm/asm64 不透明哨兵
}

fn (mut ctx GenCtx) emit(line string) {
	ctx.lines << line
}

// addr_walk: 把 [] 内部地址表达式渲染成 MASM 寻址文本（标识符走名称修饰）。
//   * 数值 / 标识符 -> +imm / +name
//   * 函数调用       -> 先 emit 一次调用（结果在 eax），渲染成 +eax（或 +eax*scale）
//   * base*scale     -> +eax*4 / +name*4
// 对应 MASM32 的 [mem] / [mem+imm] / [mem+reg] / [mem+reg*scale+imm]。
fn (mut ctx GenCtx) addr_walk(idx int, sign int) string {
	if idx < 0 || idx >= ctx.prog.exprs.len {
		return sign_term(sign, '?')
	}
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		return sign_term(sign, e.text)
	}
	if e.kind == ExprKind.expr_ident {
		return sign_term(sign, resolve_name(ctx.st, ctx.fname, e.text))
	}
	if e.kind == ExprKind.expr_member {
		return sign_term(sign, ctx.member_text(idx))
	}
	if e.kind == ExprKind.expr_neg {
		return ctx.addr_walk(e.a, -sign)
	}
	if e.kind == ExprKind.expr_addr {
		return ctx.addr_walk(e.a, sign)
	}
	if e.kind == ExprKind.expr_call {
		ctx.call(idx)
		return sign_term(sign, 'eax')
	}
	if e.kind == ExprKind.expr_bin {
		if e.text == '*' {
			mut scale := ''
			mut base_idx := -1
			if ctx.prog.exprs[e.a].kind == ExprKind.expr_num {
				scale = ctx.prog.exprs[e.a].text
				base_idx = e.b
			} else {
				scale = ctx.prog.exprs[e.b].text
				base_idx = e.a
			}
			base := strip_leading_plus(ctx.addr_walk(base_idx, 1))
			return sign_term(sign, base + '*' + scale)
		}
		if e.text == '+' {
			return ctx.addr_walk(e.a, sign) + ctx.addr_walk(e.b, sign)
		}
		if e.text == '-' {
			return ctx.addr_walk(e.a, sign) + ctx.addr_walk(e.b, -sign)
		}
	}
	return sign_term(sign, '?')
}

fn (mut ctx GenCtx) addr_text(idx int) string {
	return strip_leading_plus(ctx.addr_walk(idx, 1))
}

// is_simple_arg: 能直接写进 invoke 参数列表的表达式形态。
// ---------- cone 0.6 fix1：MASM 汇编期常量表达式 ----------
// expr_has_bitop: 表达式树里是否含位运算节点（决定要不要走汇编期常量求值）。
fn expr_has_bitop(prog Program, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len { return false }
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_neg && e.text == '~' { return true }
	if e.kind == ExprKind.expr_bin && is_bitop(e.text) { return true }
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr || e.kind == ExprKind.expr_deref {
		return expr_has_bitop(prog, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		return expr_has_bitop(prog, e.a) || expr_has_bitop(prog, e.b)
	}
	if e.kind == ExprKind.expr_call {
		for a in e.args {
			if expr_has_bitop(prog, a) { return true }
		}
	}
	return false
}

// masm_const: 只由「数值 / equ 常量 / win.宏 / 函数标签」组成的表达式，
// 可以直接写成 MASM32 的汇编期常量表达式（or/and/xor/shl/shr/not 交给 ml 折叠）。
// 局部变量 / 寄存器 / data / var 内存标签 / 解引用 / 调用 / 浮点一律返回空串。
fn masm_const(prog Program, st SymTab, fname string, idx int) string {
	if idx < 0 || idx >= prog.exprs.len { return '' }
	e := prog.exprs[idx]
	if e.is_float_hint || e.is_struct_lit { return '' }
	if e.kind == ExprKind.expr_num {
		if is_float_lit(e.text) { return '' }
		return e.text
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg { return '' }
		if e.is_win_sym { return e.text }
		if name_key(fname, e.text) in st.name_maps { return '' }
		if e.text in st.globals {
			kk := st.global_kind[e.text]
			if kk == 'data' || kk == 'var' { return '' }
			return resolve_name(st, fname, e.text)
		}
		return ''
	}
	if e.kind == ExprKind.expr_neg {
		a := masm_const(prog, st, fname, e.a)
		if a.len == 0 { return '' }
		if e.text == '~' { return 'not (' + a + ')' }
		return '-(' + a + ')'
	}
	if e.kind == ExprKind.expr_bin {
		if is_cond_op(e.text) { return '' }
		a := masm_const(prog, st, fname, e.a)
		b := masm_const(prog, st, fname, e.b)
		if a.len == 0 || b.len == 0 { return '' }
		op := masm_bin_op(e.text)
		if is_masm_word_op(op) { return '(' + a + ' ' + op + ' ' + b + ')' }
		return '(' + a + op + b + ')'
	}
	if e.kind == ExprKind.expr_addr {
		inner := prog.exprs[e.a]
		if inner.kind == ExprKind.expr_ident && !inner.is_reg && !inner.is_win_sym {
			return 'offset ' + resolve_name(st, fname, inner.text)
		}
		return ''
	}
	return ''
}

// cone 0.3：[] 是直接内存访问（type ptr [addr]），但地址表达式里可能含函数调用，
// 因此统一预计算到池寄存器；addr 也由 call() 单独处理。二者都不是"可直接写进列表"的简单参数。
fn is_simple_arg(prog Program, st SymTab, fname string, idx int) bool {
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_num || e.kind == ExprKind.expr_ident || e.kind == ExprKind.expr_str {
		return true
	}
	if e.kind == ExprKind.expr_member {
		return true
	}
	if e.kind == ExprKind.expr_neg && prog.exprs[e.a].kind == ExprKind.expr_num {
		return true
	}
	// cone 0.6 fix1：整体是 MASM 汇编期常量表达式时可直接写进 invoke / push
	if e.kind == ExprKind.expr_bin || e.kind == ExprKind.expr_neg {
		if masm_const(prog, st, fname, idx).len > 0 { return true }
	}
	return false
}

// expr_uses_reg: 表达式里是否用到某个寄存器族（按 32 位族名比较）。
// 用于给 [] 左值的 mem->mem 中转、以及二元求值的 scratch 选择避开冲突寄存器。
fn expr_uses_reg(prog Program, idx int, family string) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_ident && e.is_reg {
		return eq_ci(reg_family(e.text), family)
	}
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr || e.kind == ExprKind.expr_deref {
		return expr_uses_reg(prog, e.a, family)
	}
	if e.kind == ExprKind.expr_bin {
		return expr_uses_reg(prog, e.a, family) || expr_uses_reg(prog, e.b, family)
	}
	if e.kind == ExprKind.expr_call {
		for a in e.args {
			if expr_uses_reg(prog, a, family) {
				return true
			}
		}
		return eq_ci(family, 'eax')
	}
	return false
}

// pick_store_reg: [] 左值遇到 mem->mem（x86 不允许两内存操作数）时的中转寄存器。
// 必须选有 8/16 位低位名的族（ebx/bl/bx、ecx/cl/cx、edx/dl/dx），
// 因为 [] 可以指定 byte/word 尺寸；同时避开地址表达式与右值里已用到的族。
fn pick_store_reg(prog Program, addr_idx int, rhs_idx int) string {
	mut cands := []string{}
	cands << 'ebx'
	cands << 'ecx'
	cands << 'edx'
	for c in cands {
		fam := reg_family(c)
		if expr_uses_reg(prog, addr_idx, fam) {
			continue
		}
		if expr_uses_reg(prog, rhs_idx, fam) {
			continue
		}
		return c
	}
	return 'ebx'
}

fn store_low_reg(reg string, nb int) string {
	if nb == 1 {
		return reg_low_for(reg, 1)
	}
	if nb == 2 {
		return reg_low_for(reg, 2)
	}
	return reg
}

// is_inline_bin_right: 二元表达式的【右操作数】能否在左值已装进目标寄存器之后
// 安全地内联成一个 MASM 操作数（必要指令只写进 scratch，绝不碰目标寄存器 / eax）。
//
// 允许：立即数、标识符/寄存器、负立即数、addr 取地址、[] 直接内存访问（地址不含 call）。
// 不允许：复合表达式、函数调用、以及地址里含 call 的 []（它们求值会占用 eax）。
// 这样 `addr hello+11` 就走 `mov eax,offset hello / add eax,11`，
// 不再退化成 push/pop 保护的五条指令。
fn is_inline_bin_right(prog Program, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_num || e.kind == ExprKind.expr_ident {
		return true
	}
	if e.kind == ExprKind.expr_str {
		return e.is_char_const
	}
	if e.kind == ExprKind.expr_neg {
		if e.a >= 0 && e.a < prog.exprs.len {
			return prog.exprs[e.a].kind == ExprKind.expr_num
		}
		return false
	}
	if e.kind == ExprKind.expr_addr {
		return true
	}
	if e.kind == ExprKind.expr_deref {
		return !expr_has_call(prog, e.a)
	}
	return false
}

// is_simple_load: 可以按目标尺寸直接 mov al/ax 加载的简单值
fn is_simple_load(prog Program, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_num || e.kind == ExprKind.expr_ident || e.kind == ExprKind.expr_deref {
		return true
	}
	if e.kind == ExprKind.expr_neg {
		return is_simple_load(prog, e.a)
	}
	return false
}

fn arg_is_small_ident(prog Program, st SymTab, fname string, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind != ExprKind.expr_ident {
		return false
	}
	if is_data_label(st, e.text) || is_equ(st, e.text) {
		return false
	}
	sz := symbol_size(st, fname, e.text)
	return sz == 1 || sz == 2
}

// ret_is_direct: 入口 return 能否直接写成 invoke ExitProcess, <操作数>
fn ret_is_direct(prog Program, st SymTab, fname string, idx int) bool {
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		return !is_float_lit(e.text)
	}
	if e.kind == ExprKind.expr_ident {
		if is_data_label(st, e.text) {
			return false
		}
		if is_equ(st, e.text) {
			return true
		}
		return symbol_size(st, fname, e.text) == 4
	}
	return false
}

// render_arg: invoke 参数列表里的一项
// member_text: 把结构体成员访问渲染成 MASM 操作数。
//   base 是结构体类型名 -> 原样输出 `ttt.x`（MASM 字段偏移常量，只用于 [] 寻址）
//   base 是变量 / 形参   -> 名称修饰后的 base + '.' + 成员链（如 `arg1.y` / `@st.x`）
fn (mut ctx GenCtx) member_text(idx int) string {
	e := ctx.prog.exprs[idx]
	if e.member_base in ctx.st.struct_size {
		// cone 0.9prelease：structtype.member 视为 cone 计算的立即数偏移
		key := e.member_base + '.' + e.member_path
		if key in ctx.st.struct_offsets {
			return '${ctx.st.struct_offsets[key]}'
		}
		return e.text
	}
	if e.member_base in ctx.st.struct_extern {
		// win.RECT.left -> RECT.left（MASM32 的字段偏移常量）
		return win_masm_name(e.member_base) + '.' + e.member_path
	}
	return resolve_name(ctx.st, ctx.fname, e.member_base) + '.' + e.member_path
}

fn (mut ctx GenCtx) member_bytes(idx int) int {
	return member_size_bytes(ctx.st, ctx.fname, ctx.prog.exprs[idx])
}

// struct_label_or_name: 结构体常量的 text 是去重键而不是 MASM 符号，
// 取地址 / 取偏移时先换成隐名标签；普通标识符仍走 cone 名称修饰。
fn (mut ctx GenCtx) struct_label_or_name(name string) string {
	if name in ctx.stt_labels {
		return ctx.stt_labels[name]
	}
	return resolve_name(ctx.st, ctx.fname, name)
}

// struct_const_bytes: cone 结构体按 st.struct_size；win 外部结构体 cone
// 不掌握字段布局，按 dword（与 win.XXX 类型登记时的占位一致）。
fn (mut ctx GenCtx) struct_const_bytes(idx int) int {
	e := ctx.prog.exprs[idx]
	b := resolve_base_type(ctx.st, e.lit_type)
	if b in ctx.st.struct_size {
		n := ctx.st.struct_size[b]
		if n > 0 {
			return n
		}
	}
	return 4
}

// push_struct_const: 手工压栈路径下把结构体常量按值压栈（高 dword 先推）。
fn (mut ctx GenCtx) push_struct_const(idx int) {
	e := ctx.prog.exprs[idx]
	label := struct_label_of(e.text, ctx.stt_labels)
	n := ctx.struct_const_bytes(idx)
	mut nd := n / 4
	if n % 4 != 0 {
		nd = nd + 1
	}
	mut k := nd - 1
	for k >= 0 {
		if k == 0 {
			ctx.emit('    push dword ptr [${label}]    ; 结构体常量按值压栈（低 dword）')
		} else {
			ctx.emit('    push dword ptr [${label}+${k * 4}]    ; 结构体常量按值压栈')
		}
		k = k - 1
	}
}

fn (mut ctx GenCtx) render_arg(idx int) string {
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		// cone 0.6：float(N) 把整数字面量也当 REAL4 常量传（位模式由 .const 池给出）
		if e.is_float_hint || is_float_lit(e.text) {
			return float_label_of(e.text, ctx.float_labels)
		}
		return e.text
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_struct_lit {
			return struct_label_of(e.text, ctx.stt_labels)
		}
		return resolve_name(ctx.st, ctx.fname, e.text)
	}
	if e.kind == ExprKind.expr_member {
		return ctx.member_text(idx)
	}
	if e.kind == ExprKind.expr_str {
		if e.is_char_const {
			return 'offset ' + char_label_of(e.text, ctx.char_labels)
		}
		return e.text
	}
	if e.kind == ExprKind.expr_neg {
		c := masm_const(ctx.prog, ctx.st, ctx.fname, idx)
		if c.len > 0 { return c }
		if e.text == '~' { return '?' }
		return '-' + ctx.render_arg(e.a)
	}
	if e.kind == ExprKind.expr_bin {
		c := masm_const(ctx.prog, ctx.st, ctx.fname, idx)
		if c.len > 0 { return c }
		return '?'
	}
	if e.kind == ExprKind.expr_addr {
		name := addr_target(ctx.prog, idx)
		if is_stack_name(ctx.st, ctx.fname, name) {
			return 'addr ' + ctx.struct_label_or_name(name)
		}
		return 'offset ' + ctx.struct_label_or_name(name)
	}
	// cone 0.3：[] 解引用必须先装入寄存器，不能内联成直接内存操作数，
	// 所以这里不再渲染 expr_deref；call() 会把它预处理到池寄存器里。
	return '?'
}

// ---------- 整型量载入（cone 0.3 寄存器感知 / [] 直接内存访问） ----------

// deref_load_reg: cone 0.3 完善版的 [] 直接内存访问。
// [] 与 MASM32 语义完全一致 —— [type addr] 就是 type ptr [addr]，
// 即"该地址处的值"，一步访问，不再自动做两次间接（那是 cone 0.3 初版多此一举的语义）。
//
//   [dword mem]        ->  mov reg, dword ptr [mem]
//   [byte mem+4]       ->  movzx reg, byte ptr [mem+4]
//   [word eax+ecx*4+8] ->  movzx reg, word ptr [eax+ecx*4+8]
//
// 想要"解引用"（把某处保存的 4 字节当指针）由 cone 代码显式写：
//   regname = var        ; mov regname, var   —— 取出指针值
//   [type regname] = yyy ; mov type ptr [regname], yyy
// 这样语法统一、语义与 MASM32 一致，编译器不再替程序员猜测间接层数。
fn (mut ctx GenCtx) deref_load_reg(idx int, reg string) {
	e := ctx.prog.exprs[idx]
	a := ctx.addr_text(e.a)
	ptr := deref_ptr_text(e.ptr_size)
	n := deref_size_bytes(e.ptr_size)
	if n == 1 || n == 2 {
		ctx.emit('    movzx ${reg}, ${ptr} [${a}]')
		return
	}
	if n >= 6 {
		ctx.emit('    mov ${reg}, dword ptr [${a}]    ; [] 指定 ${ptr}，32 位寄存器只取低 dword')
		return
	}
	ctx.emit('    mov ${reg}, ${ptr} [${a}]')
}

// emit_load_reg_to_reg: reg -> reg，带尺寸换算，绝不发无意义 mov reg,reg。
fn (mut ctx GenCtx) emit_load_reg_to_reg(src string, dst string) {
	if eq_ci(src, dst) {
		return
	}
	ss := reg_size(src)
	ds := reg_size(dst)
	if ss == ds {
		ctx.emit('    mov ${dst}, ${src}')
		return
	}
	if ss < ds {
		ctx.emit('    movzx ${dst}, ${src}')
		return
	}
	low := reg_low_for(src, ds)
	if low.len > 0 {
		if eq_ci(low, dst) {
			return
		}
		ctx.emit('    mov ${dst}, ${low}')
		return
	}
	ctx.emit('    movzx eax, ${src}')
	ctx.emit('    mov ${dst}, ${reg_low_of_eax(ds)}')
}

fn (mut ctx GenCtx) emit_ident_to_reg(name string, reg string) {
	if is_reg_name(name) {
		ctx.emit_load_reg_to_reg(name, reg)
		return
	}
	nm := resolve_name(ctx.st, ctx.fname, name)
	if is_data_label(ctx.st, name) {
		ctx.emit('    mov ${reg}, dword ptr [${nm}]')
		return
	}
	if is_equ(ctx.st, name) {
		ctx.emit('    mov ${reg}, ${nm}')
		return
	}
	sz := symbol_size(ctx.st, ctx.fname, name)
	if sz == 1 || sz == 2 {
		ctx.emit('    movzx ${reg}, ${nm}')
		return
	}
	if sz == 8 {
		ctx.emit('    mov ${reg}, dword ptr ${nm}')
		return
	}
	ctx.emit('    mov ${reg}, ${nm}')
}

// emit_load: 把任意整型表达式的值装进 32 位寄存器 dst（可指定，避免多余搬运）。
fn (mut ctx GenCtx) emit_load(idx int, dst string) {
	if idx < 0 || idx >= ctx.prog.exprs.len {
		return
	}
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_bin || e.kind == ExprKind.expr_neg {
		if expr_has_bitop(ctx.prog, idx) {
			c := masm_const(ctx.prog, ctx.st, ctx.fname, idx)
			if c.len > 0 {
				ctx.emit('    mov ${dst}, ${c}')
				return
			}
		}
	}
	if e.kind == ExprKind.expr_num {
		if is_float_lit(e.text) {
			mut label := '__cone_flt_missing'
			if e.text in ctx.float_labels {
				label = ctx.float_labels[e.text]
			}
			ctx.emit('    mov ${dst}, dword ptr [${label}]    ; 浮点字面量按原始 4 字节位装入')
		} else {
			ctx.emit('    mov ${dst}, ${e.text}')
		}
		return
	}
	if e.kind == ExprKind.expr_ident {
		ctx.emit_ident_to_reg(e.text, dst)
		return
	}
	if e.kind == ExprKind.expr_member {
		t := ctx.member_text(idx)
		sz := ctx.member_bytes(idx)
		if sz == 1 || sz == 2 {
			ctx.emit('    movzx ${dst}, ${t}')
		} else {
			ctx.emit('    mov ${dst}, ${t}')
		}
		return
	}
	if e.kind == ExprKind.expr_str {
		if e.is_char_const {
			ctx.emit('    mov ${dst}, offset ${char_label_of(e.text, ctx.char_labels)}')
			return
		}
		ctx.emit('    ; TODO 裸字符串字面量不能求值到 ${dst}')
		return
	}
	if e.kind == ExprKind.expr_neg {
		ctx.emit_load(e.a, dst)
		if e.text == '~' {
			ctx.emit('    not ${dst}')
		} else {
			ctx.emit('    neg ${dst}')
		}
		return
	}
	if e.kind == ExprKind.expr_addr {
		inner := ctx.prog.exprs[e.a]
		if inner.kind == ExprKind.expr_ident {
			nm := ctx.struct_label_or_name(inner.text)
			if is_stack_name(ctx.st, ctx.fname, inner.text) {
				ctx.emit('    lea ${dst}, ${nm}')
			} else {
				ctx.emit('    mov ${dst}, offset ${nm}')
			}
			return
		}
		ctx.emit('    ; TODO addr 后面必须是标识符')
		return
	}
	if e.kind == ExprKind.expr_deref {
		ctx.deref_load_reg(idx, dst)
		return
	}
	if e.kind == ExprKind.expr_call {
		ctx.call(idx)
		if !eq_ci(dst, 'eax') {
			ctx.emit('    mov ${dst}, eax')
		}
		return
	}
	if e.kind == ExprKind.expr_bin {
		// 目标寄存器导向：能直接在 dst 上做二元运算就不经 eax 中转。
		ctx.emit_bin_to(idx, dst)
		return
	}
	ctx.emit('    ; TODO 无法求值到 ${dst} 的表达式')
}

fn (mut ctx GenCtx) expr_eax(idx int) {
	ctx.emit_load(idx, 'eax')
}

fn (mut ctx GenCtx) emit_load_eax(idx int) {
	ctx.emit_load(idx, 'eax')
}

fn (mut ctx GenCtx) emit_load_ebx(idx int) {
	ctx.emit_load(idx, 'ebx')
}

// bin_operand: 把右操作数渲染成一个 MASM 操作数字符串。
// 需要发射指令时一律写进 scratch（由调用方保证 scratch 不等于目标寄存器），
// 这样左值留在目标寄存器里不会被覆盖。
fn (mut ctx GenCtx) bin_operand(idx int, scratch string) string {
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		return e.text
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg {
			if reg_size(e.text) == 4 {
				return e.text
			}
			ctx.emit('    movzx ${scratch}, ${e.text}')
			return scratch
		}
		// 注意：这里的 movzx 是 32 位算术表达式内部需要的尺寸统一，
		// 不是给 invoke 参数做 dword 化。
		if arg_is_small_ident(ctx.prog, ctx.st, ctx.fname, idx) {
			ctx.emit('    movzx ${scratch}, ${resolve_name(ctx.st, ctx.fname, e.text)}')
			return scratch
		}
		if is_data_label(ctx.st, e.text) {
			return 'dword ptr [${resolve_name(ctx.st, ctx.fname, e.text)}]'
		}
		return resolve_name(ctx.st, ctx.fname, e.text)
	}
	if e.kind == ExprKind.expr_neg {
		inner := ctx.prog.exprs[e.a]
		if inner.kind == ExprKind.expr_num {
			return '-' + inner.text
		}
	}
	if e.kind == ExprKind.expr_deref {
		ctx.deref_load_reg(idx, scratch)
		return scratch
	}
	ctx.emit_load(idx, scratch)
	return scratch
}

// emit_bin_to: 把二元算术表达式直接求进【目标寄存器 dst】（cone 0.3 完善版优化）。
//
// 旧实现要求左右都是"简单操作数"才走两指令路径，于是 `eax=addr hello+11`
// 因为左操作数是 addr 表达式被判为复合，退化成 push/pop 五条指令。
// 现在改为：左操作数任意（emit_load 求到 target），只要右操作数能安全内联
// （立即数 / 标识符 / 寄存器 / 负立即数 / addr / 不含 call 的 []），
// 就直接在 target 上 add/sub/imul，一条都不多。
//
// div 隐式使用 eax:edx，因此 '/' 强制在 eax 上做；其余 + - * 可以任意 32 位目标寄存器。
// 右操作数需要发射指令时写进 scratch（避开 target），不会覆盖左值。
// 右操作数本身是复合表达式 / 含函数调用时，才回退到 push/pop 通用路径。
fn (mut ctx GenCtx) emit_bin_to(idx int, dst string) {
	e := ctx.prog.exprs[idx]
	op := e.text
	mut target := dst
	if op == '/' || op == '%' {
		target = 'eax'
	}

	// cone 0.6 fix1：运行期位运算 -> or / and / xor（内存形式，绝不误用 fi* 系列）
	if op == '|' || op == '&' || op == '^' {
		ins := masm_bit_insn(op)
		if is_inline_bin_right(ctx.prog, e.b) && !expr_has_call(ctx.prog, e.b) {
			ctx.emit_load(e.a, target)
			mut scratch := 'ebx'
			if eq_ci(target, 'ebx') { scratch = 'esi' }
			rb := ctx.bin_operand(e.b, scratch)
			ctx.emit('    ${ins} ${target}, ${rb}')
		} else {
			ctx.emit_load(e.a, 'eax')
			ctx.emit('    push eax')
			ctx.emit_load(e.b, 'eax')
			ctx.emit('    mov ebx, eax')
			ctx.emit('    pop eax')
			ctx.emit('    ${ins} eax, ebx')
			target = 'eax'
		}
		if !eq_ci(target, dst) { ctx.emit('    mov ${dst}, ${target}') }
		return
	}
	// cone 0.6 fix1：运行期移位 -> shl / shr；非常量计数用 cl，push/pop ecx 保护用户寄存器
	if op == '<<' || op == '>>' {
		ins := masm_bit_insn(op)
		rb := ctx.prog.exprs[e.b]
		if rb.kind == ExprKind.expr_num && !is_float_lit(rb.text) {
			ctx.emit_load(e.a, target)
			ctx.emit('    ${ins} ${target}, ${rb.text}')
		} else {
			ctx.emit('    push ecx')
			ctx.emit_load(e.a, 'eax')
			ctx.emit('    push eax')
			ctx.emit_load(e.b, 'ecx')
			ctx.emit('    pop eax')
			ctx.emit('    ${ins} eax, cl')
			ctx.emit('    pop ecx')
			target = 'eax'
		}
		if !eq_ci(target, dst) { ctx.emit('    mov ${dst}, ${target}') }
		return
	}

	if is_inline_bin_right(ctx.prog, e.b) && !expr_has_call(ctx.prog, e.b) {
		ctx.emit_load(e.a, target)
		if op == '/' || op == '%' {
			ctx.emit_load(e.b, 'ebx')
			ctx.emit('    xor edx, edx')
			ctx.emit('    div ebx')
			if op == '%' {
				ctx.emit('    mov eax, edx    ; % 取模：余数在 edx')
			}
		} else {
			mut scratch := 'ebx'
			if eq_ci(target, 'ebx') {
				scratch = 'esi'
			}
			rb := ctx.bin_operand(e.b, scratch)
			if op == '+' {
				ctx.emit('    add ${target}, ${rb}')
			} else if op == '-' {
				ctx.emit('    sub ${target}, ${rb}')
			} else if op == '*' {
				ctx.emit('    imul ${target}, ${rb}')
			}
		}
	} else {
		// 右操作数无法内联：push 保存左值，求右值到 ebx，再合并。
		ctx.emit_load(e.a, 'eax')
		ctx.emit('    push eax')
		ctx.emit_load(e.b, 'eax')
		ctx.emit('    mov ebx, eax')
		ctx.emit('    pop eax')
		if op == '+' {
			ctx.emit('    add eax, ebx')
		} else if op == '-' {
			ctx.emit('    sub eax, ebx')
		} else if op == '*' {
			ctx.emit('    mul ebx')
		} else if op == '/' || op == '%' {
			ctx.emit('    xor edx, edx')
			ctx.emit('    div ebx')
			if op == '%' {
				ctx.emit('    mov eax, edx    ; % 取模：余数在 edx')
			}
		}
		target = 'eax'
	}
	if !eq_ci(target, dst) {
		ctx.emit('    mov ${dst}, ${target}')
	}
}

// emit_small_load: 把简单值按目标尺寸装入 al / ax（支持寄存器源，避免 mov al,al）
fn (mut ctx GenCtx) emit_small_load(idx int, reg string, size int) {
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_member {
		ctx.emit('    mov ${reg}, ${ctx.member_text(idx)}')
		return
	}
	if e.kind == ExprKind.expr_num {
		ctx.emit('    mov ${reg}, ${e.text}')
		return
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg {
			low := reg_low_for(e.text, size)
			if low.len > 0 {
				if !eq_ci(low, reg) {
					ctx.emit('    mov ${reg}, ${low}')
				}
				return
			}
			ctx.emit_load(idx, 'eax')
			return
		}
		nm := resolve_name(ctx.st, ctx.fname, e.text)
		if is_data_label(ctx.st, e.text) {
			ctx.emit('    mov ${reg}, ${size_ptr(size)} [${nm}]')
			return
		}
		if is_equ(ctx.st, e.text) {
			ctx.emit('    mov ${reg}, ${nm}')
			return
		}
		src := symbol_size(ctx.st, ctx.fname, e.text)
		if src == size {
			ctx.emit('    mov ${reg}, ${nm}')
		} else if src > size {
			ctx.emit('    mov ${reg}, ${size_ptr(size)} ${nm}')
		} else {
			ctx.emit('    movzx eax, ${nm}')
		}
		return
	}
	if e.kind == ExprKind.expr_deref {
		ctx.deref_load_reg(idx, 'eax')
		return
	}
	if e.kind == ExprKind.expr_neg {
		ctx.emit_small_load(e.a, reg, size)
		ctx.emit('    neg ${reg}')
		return
	}
	ctx.emit_load(idx, 'eax')
}

// ---------- 浮点求值（x87） ----------

// ---------- cone 0.6：float(...) ----------
// 核心原则：右值出现 float 关键字或浮点字面量就走 x87；被 float() 括起的内容
// 需要载入时一律 fld（浮点载入），未经 float() 的整数内容默认 fild（整数载入）。
// 当 float() 括住的是简单内存操作数时，进一步用 x87 的内存形式算术指令
// （fadd/fsub/fmul/fdiv 与反向 fsubr/fdivr，绝不误用 fiadd/fidiv 系列），
// 这样 `WindowX/float(MousePosition.x)` 生成 `fild WindowX` + `fdiv dword ptr MousePosition.x`。

fn float_load_ptr(n int) string {
	if n == 8 {
		return 'qword ptr'
	}
	return 'dword ptr'
}

fn float_mem_op(op string) string {
	if op == '+' {
		return 'fadd'
	}
	if op == '-' {
		return 'fsub'
	}
	if op == '*' {
		return 'fmul'
	}
	return 'fdiv'
}

fn float_mem_op_r(op string) string {
	if op == '+' {
		return 'fadd'
	}
	if op == '*' {
		return 'fmul'
	}
	if op == '-' {
		return 'fsubr'
	}
	return 'fdivr'
}

// float_mem_text: 被 float() 标记且可作为 x87 内存操作数时返回带尺寸词的文本；
// 复合表达式返回空串（改走「整数求值 -> 按位 fld」路径）。
fn (mut ctx GenCtx) float_mem_text(idx int) string {
	e := ctx.prog.exprs[idx]
	if !e.is_float_hint {
		return ''
	}
	if e.kind == ExprKind.expr_num {
		return float_label_of(e.text, ctx.float_labels)
	}
	if e.kind == ExprKind.expr_ident {
		nb := symbol_size(ctx.st, ctx.fname, e.text)
		return float_load_ptr(nb) + ' ' + resolve_name(ctx.st, ctx.fname, e.text)
	}
	if e.kind == ExprKind.expr_member {
		nb := member_size_bytes(ctx.st, ctx.fname, e)
		return float_load_ptr(nb) + ' ' + ctx.member_text(idx)
	}
	if e.kind == ExprKind.expr_deref {
		a := ctx.addr_text(e.a)
		return deref_ptr_text(e.ptr_size) + ' [' + a + ']'
	}
	return ''
}

// float_load_hinted: 把 float(...) 的内容按浮点位载入 st(0)。
fn (mut ctx GenCtx) float_load_hinted(idx int) {
	m := ctx.float_mem_text(idx)
	if m.len > 0 {
		ctx.emit('    fld ${m}')
		return
	}
	// 复合内容：cone 不区分类型，先按整数求值，再把 4 字节原位当成 REAL4 载入
	ctx.expr_eax(idx)
	ctx.emit('    mov ${ctx.itmp}, eax')
	ctx.emit('    fld dword ptr ${ctx.itmp}')
}

fn (mut ctx GenCtx) float_operand(idx int) {
	if expr_is_float(ctx.prog, ctx.st, ctx.fname, idx) {
		ctx.float_eax(idx)
		return
	}
	ctx.expr_eax(idx)
	ctx.emit('    mov ${ctx.itmp}, eax')
	ctx.emit('    fild ${ctx.itmp}')
}

fn (mut ctx GenCtx) float_eax(idx int) {
	e := ctx.prog.exprs[idx]

	// cone 0.6：float(...) 括起的内容一律用 fld，绝不 fild
	if e.is_float_hint {
		ctx.float_load_hinted(idx)
		return
	}
	if e.kind == ExprKind.expr_num {
		if is_float_lit(e.text) {
			mut label := '__cone_flt_missing'
			if e.text in ctx.float_labels {
				label = ctx.float_labels[e.text]
			}
			ctx.emit('    fld ${label}')
		} else {
			ctx.emit('    mov eax, ${e.text}')
			ctx.emit('    mov ${ctx.itmp}, eax')
			ctx.emit('    fild ${ctx.itmp}')
		}
		return
	}
	if e.kind == ExprKind.expr_ident {
		if is_float_base(symbol_base_type(ctx.st, ctx.fname, e.text)) {
			ctx.emit('    fld ${resolve_name(ctx.st, ctx.fname, e.text)}')
		} else {
			ctx.expr_eax(idx)
			ctx.emit('    mov ${ctx.itmp}, eax')
			ctx.emit('    fild ${ctx.itmp}')
		}
		return
	}
	if e.kind == ExprKind.expr_member {
		t := ctx.member_text(idx)
		if member_is_float(ctx.st, ctx.fname, e) {
			ctx.emit('    fld ${t}')
		} else {
			ctx.emit('    mov eax, ${t}')
			ctx.emit('    mov ${ctx.itmp}, eax')
			ctx.emit('    fild ${ctx.itmp}')
		}
		return
	}
	if e.kind == ExprKind.expr_neg {
		ctx.float_operand(e.a)
		ctx.emit('    fchs')
		return
	}
	if e.kind == ExprKind.expr_bin {
		if e.text == '+' || e.text == '-' || e.text == '*' || e.text == '/' {
			bm := ctx.float_mem_text(e.b)
			if bm.len > 0 {
				ctx.float_operand(e.a)
				ctx.emit('    ${float_mem_op(e.text)} ${bm}')
				return
			}
			am := ctx.float_mem_text(e.a)
			if am.len > 0 {
				ctx.float_operand(e.b)
				ctx.emit('    ${float_mem_op_r(e.text)} ${am}')
				return
			}
		}
		ctx.float_operand(e.a)
		ctx.float_operand(e.b)
		if e.text == '+' {
			ctx.emit('    faddp st(1), st(0)')
		} else if e.text == '-' {
			ctx.emit('    fsubp st(1), st(0)')
		} else if e.text == '*' {
			ctx.emit('    fmulp st(1), st(0)')
		} else if e.text == '/' {
			ctx.emit('    fdivp st(1), st(0)')
		}
		return
	}
	if e.kind == ExprKind.expr_call {
		ctx.call(idx)
		ctx.emit('    mov ${ctx.itmp}, eax')
		ctx.emit('    fild ${ctx.itmp}')
		return
	}
	if e.kind == ExprKind.expr_deref || e.kind == ExprKind.expr_addr {
		ctx.expr_eax(idx)
		ctx.emit('    mov ${ctx.itmp}, eax')
		ctx.emit('    fild ${ctx.itmp}')
		return
	}
	ctx.emit('    ; TODO 浮点求值：未知表达式节点')
}

// expr_eax / emit_bin_to / emit_load 已在上方"整型量载入"区统一实现，
// 这里不再重复定义。

// ---------- 调用 ----------

// declared_param_types: 从 func 声明 / def 定义里取形参类型序列（cone 类型名）。
// win.* / equ 别名没有形参表，返回空，由实参尺寸兜底。
fn declared_param_types(prog Program, target string) []string {
	mut out := []string{}
	for pr in prog.protos {
		if pr.name == target {
			for pm in pr.params {
				out << pm.typ_name
			}
		}
	}
	if out.len == 0 {
		for f in prog.funcs {
			if f.name == target {
				for pm in f.params {
					out << pm.typ_name
				}
			}
		}
	}
	return out
}

// arg_is_64_expr: 实参本身是不是 8 字节值（long/f64 变量、8 字节成员、qword []）。
// cone 只论字节大小，不看符号；数值字面量 / 寄存器 / 地址一律按 4 字节。
fn arg_is_64_expr(prog Program, st SymTab, fname string, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_ident && !e.is_reg {
		// 结构体变量按值传参由 MASM32 的 invoke / PROTO 自己处理，不拆 qword
		b := symbol_base_type(st, fname, e.text)
		if b in st.struct_size || b in st.struct_extern {
			return false
		}
		return expr_size(prog, st, fname, idx) == 8
	}
	if e.kind == ExprKind.expr_member {
		return member_size_bytes(st, fname, e) == 8
	}
	if e.kind == ExprKind.expr_deref {
		return deref_size_bytes(e.ptr_size) == 8
	}
	if e.kind == ExprKind.expr_neg {
		return arg_is_64_expr(prog, st, fname, e.a)
	}
	return false
}

// param_push_sizes: 每个参数实际压栈的字节数（4 或 8）。
// 优先按 func/def 的形参声明（typedef 会展开），再用实参尺寸兜底；
// 可变参数 / win.* 没有形参表时完全按实参推断。
fn (mut ctx GenCtx) param_push_sizes(e Expr) []int {
	target := call_target(e.text)
	decl := declared_param_types(ctx.prog, target)
	mut sizes := []int{}
	mut i := 0
	for i < e.args.len {
		mut sz := 4
		if i < decl.len {
			// 有形参声明时【以形参为准】：:DWORD 形参只压 4 字节（8 字节实参取低 dword），
			// :QWORD / :long / :f64 才压 8 字节。结构体形参交给 MASM invoke。
			b := resolve_base_type(ctx.st, decl[i])
			if !(b in ctx.st.struct_size) && !(b in ctx.st.struct_extern) {
				if b in ctx.st.type_bytes {
					if ctx.st.type_bytes[b] == 8 {
						sz = 8
					}
				}
			}
		} else if arg_is_64_expr(ctx.prog, ctx.st, ctx.fname, e.args[i]) {
			// 没有形参表（win.* / equ 别名 / 可变参数多出的实参）：按实参尺寸推断
			sz = 8
		}
		sizes << sz
		i = i + 1
	}
	return sizes
}

// push_qword_arg: 把一个 64 位值拆成两个 DWORD 压栈。
// 逆序压栈时先 push 高 32 位、再 push 低 32 位，被调函数看到
// [ebp+8]=低 dword、[ebp+12]=高 dword，与 MASM32 按值传 QWORD 一致。
fn (mut ctx GenCtx) push_qword_arg(idx int) {
	e := ctx.prog.exprs[idx]
	if expr_is_float(ctx.prog, ctx.st, ctx.fname, idx) {
		ctx.float_eax(idx)
		ctx.emit('    sub esp, 8')
		ctx.emit('    fstp qword ptr [esp]    ; 64 位浮点参数直接压栈（低 dword 在低地址）')
		return
	}
	fr := try_fold(ctx.prog, idx)
	if fr.ok {
		ctx.emit('    mov eax, ${fr.value}')
		ctx.emit('    xor edx, edx    ; QWORD 立即数高 32 位为零')
	} else if e.kind == ExprKind.expr_ident && !e.is_reg {
		nm := resolve_name(ctx.st, ctx.fname, e.text)
		ctx.emit('    mov eax, dword ptr [${nm}]')
		ctx.emit('    mov edx, dword ptr [${nm}+4]')
	} else if e.kind == ExprKind.expr_member {
		t := ctx.member_text(idx)
		ctx.emit('    mov eax, dword ptr [${t}]')
		ctx.emit('    mov edx, dword ptr [${t}+4]')
	} else if e.kind == ExprKind.expr_deref {
		a := ctx.addr_text(e.a)
		ctx.emit('    mov eax, dword ptr [${a}]')
		ctx.emit('    mov edx, dword ptr [${a}+4]')
	} else {
		ctx.emit_load(idx, 'eax')
		ctx.emit('    xor edx, edx    ; 32 位结果按 QWORD 传参，高 32 位为零')
	}
	ctx.emit('    push edx    ; QWORD 高 32 位（先入栈）')
	ctx.emit('    push eax    ; QWORD 低 32 位（后入栈）')
}

// call_manual: 手工逆序 push + call。没有 MASM invoke 宏帮忙，
// cone 自己 lea ebx + push ebx（等价于 addr），小尺寸零扩展到 32 位；
// 8 字节参数由 push_qword_arg 拆成两个 dword。C 约定由调用者清栈，
// total 按【实际压栈字节数】累计（含 8 字节参数），不是 args.len*4。
// cone 0.9.2：按编译期 size 展开 dword/word/byte 最优拷贝
fn (mut ctx GenCtx) sret_copy_words(src string, dst string, size int) {
	// cone 0.9.2：按编译期已知的 size 展开最优拷贝（dword -> word -> byte），
	// 恰好拷贝 size 字节，不多不少；align 结构体的 size 含 padding。
	mut off := 0
	for off + 4 <= size {
		mut so := '[${src}+${off}]'
		mut do := '[${dst}+${off}]'
		if off == 0 {
			so = '[${src}]'
			do = '[${dst}]'
		}
		ctx.emit('    mov eax, dword ptr ${so}')
		ctx.emit('    mov dword ptr ${do}, eax')
		off = off + 4
	}
	if size - off >= 2 {
		mut so := '[${src}+${off}]'
		mut do := '[${dst}+${off}]'
		if off == 0 {
			so = '[${src}]'
			do = '[${dst}]'
		}
		ctx.emit('    mov ax, word ptr ${so}')
		ctx.emit('    mov word ptr ${do}, ax')
		off = off + 2
	}
	if off < size {
		ctx.emit('    mov al, byte ptr [${src}+${off}]')
		ctx.emit('    mov byte ptr [${dst}+${off}], al')
	}
}
fn (mut ctx GenCtx) sret_copy_from(idx int, size int, ptr string) {
	// 被调方：把要返回的结构体【完整】拷贝到隐式指针指向的调用者内存
	e := ctx.prog.exprs[idx]
	mut src := ''
	if e.kind == ExprKind.expr_member {
		ctx.emit('    lea esi, ${ctx.member_text(idx)}')
		src = 'esi'
	} else {
		src = resolve_name(ctx.st, ctx.fname, e.text)
	}
	ctx.emit('    mov edi, ${ptr}')
	// cone 0.9.3：多字节拷贝改用串指令 cld + rep movsd（尾部 movsw / movsb）
	if size >= 8 {
		ctx.emit('    cld')
		if src != 'esi' {
			if is_stack_name(ctx.st, ctx.fname, e.text) {
				ctx.emit('    lea esi, ${src}')
			} else {
				ctx.emit('    mov esi, offset ${src}')
			}
		}
		ctx.emit('    mov ecx, ${size / 4}')
		ctx.emit('    rep movsd')
		rem := size % 4
		if rem >= 2 {
			ctx.emit('    movsw')
		}
		if rem == 1 {
			ctx.emit('    movsb')
		}
		return
	}
	ctx.sret_copy_words(src, 'edi', size)
}

fn (mut ctx GenCtx) call_manual(idx int, sizes []int, sret_ptr string, discard int) {
	// sret_ptr：cone 0.9.2 接收路径，调用者结构体地址文本（'addr X' / 'offset X'）
	// discard>0：裸调用，栈上开 discard 字节临时接收区并传其地址，调用后回收
	e := ctx.prog.exprs[idx]
	target := call_target(e.text)
	mut total := 0
	if discard > 0 {
		ctx.emit('    sub esp, ${discard}    ; cone 0.9.2 裸调用：栈上临时接收区（丢弃返回值）')
	}
	mut i := e.args.len - 1
	for i >= 0 {
		a := e.args[i]
		mut sz := 4
		if i < sizes.len {
			sz = sizes[i]
		}
		if ctx.prog.exprs[a].is_struct_lit {
			total = total + ctx.struct_const_bytes(a)
		} else {
			total = total + sz
		}
		if ctx.prog.exprs[a].is_struct_lit {
			ctx.push_struct_const(a)
		} else if sz == 8 {
			ctx.push_qword_arg(a)
		} else if addr_is_stack(ctx.prog, ctx.st, ctx.fname, a) {
			nm := ctx.struct_label_or_name(addr_target(ctx.prog, a))
			ctx.emit('    lea ebx, ${nm}')
			ctx.emit('    push ebx')
		} else if addr_is_global(ctx.prog, ctx.st, ctx.fname, a) {
			ctx.emit('    push offset ${ctx.struct_label_or_name(addr_target(ctx.prog, a))}')
		} else if is_small_reg_arg(ctx.prog, a) {
			ctx.emit('    movzx eax, ${ctx.prog.exprs[a].text}')
			ctx.emit('    push eax')
		} else if arg_is_small_ident(ctx.prog, ctx.st, ctx.fname, a) {
			ctx.emit('    movzx eax, ${resolve_name(ctx.st, ctx.fname, ctx.prog.exprs[a].text)}')
			ctx.emit('    push eax')
		} else if ctx.prog.exprs[a].kind == ExprKind.expr_deref {
			ctx.deref_load_reg(a, 'ebx')
			ctx.emit('    push ebx')
		} else if expr_is_float(ctx.prog, ctx.st, ctx.fname, a) {
			ctx.float_eax(a)
			ctx.emit('    sub esp, 4')
			ctx.emit('    fstp dword ptr [esp]')
		} else if is_simple_arg(ctx.prog, ctx.st, ctx.fname, a) {
			if arg_is_64_expr(ctx.prog, ctx.st, ctx.fname, a) && ctx.prog.exprs[a].kind == ExprKind.expr_ident {
				nm := resolve_name(ctx.st, ctx.fname, ctx.prog.exprs[a].text)
				ctx.emit('    push dword ptr [${nm}]    ; 8 字节变量传给 32 位形参，只压低 dword')
			} else {
				ctx.emit('    push ${ctx.render_arg(a)}')
			}
		} else {
			ctx.emit_load(a, 'eax')
			ctx.emit('    push eax')
		}
		i = i - 1
	}
	if discard > 0 {
		if total == 0 {
			ctx.emit('    mov ebx, esp    ; cone 0.9.2 临时接收区地址')
		} else {
			ctx.emit('    lea ebx, [esp+${total}]    ; cone 0.9.2 临时接收区地址')
		}
		ctx.emit('    push ebx    ; 第一个隐式参数：接收指针')
		total = total + 4
	} else if sret_ptr.len > 0 {
		if sret_ptr.starts_with('addr ') {
			ctx.emit('    lea ebx, ${sret_ptr[5..]}')
			ctx.emit('    push ebx')
		} else {
			ctx.emit('    push ${sret_ptr}    ; cone 0.9.2 第一个隐式参数：调用者接收指针')
		}
		total = total + 4
	}
	ctx.emit('    call ${target}')
	mut conv := CallConv.cc_default
	if target in ctx.st.func_convs {
		conv = ctx.st.func_convs[target]
	}
	if conv == CallConv.cc_c {
		ctx.emit('    add esp, ${total}    ; C 调用约定：调用者清栈（按实际压栈字节数）')
	}
	if discard > 0 {
		ctx.emit('    add esp, ${discard}    ; cone 0.9.2 回收临时接收区')
	}
}


// arg_uses_eax: 该参数在 invoke 压栈时是否仍依赖 eax。
// cone 0.3 里复合表达式 / 调用 / [] 解引用都会被预计算进 ebx/esi/edi，
// 所以真正留在 eax 里的只剩"裸 eax 族寄存器"参数。
fn arg_uses_eax(prog Program, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_ident && e.is_reg {
		return is_eax_family(e.text)
	}
	return false
}

// is_small_reg_arg: 8/16 位寄存器参数（须 movzx 成 32 位才能进 invoke/push）。
fn is_small_reg_arg(prog Program, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	return e.kind == ExprKind.expr_ident && e.is_reg && reg_size(e.text) != 4
}

// arg_needs_float_eval: cone 0.6 —— 实参是不是「需要 x87 求值的浮点复合表达式」。
// 数值 / 变量 / 成员 / addr 这类简单操作数 MASM invoke 能直接写；但含浮点的
// expr_bin / expr_call 必须先求值到 st(0) 再压栈，invoke 参数表里塞不进 x87。
fn arg_needs_float_eval(prog Program, st SymTab, fname string, idx int) bool {
	if !expr_is_float(prog, st, fname, idx) {
		return false
	}
	e := prog.exprs[idx]
	// 逐行单行判断：V 0.5.1 不接受把 || 写在行首的跨行条件。
	if e.kind == ExprKind.expr_num || e.kind == ExprKind.expr_ident {
		return false
	}
	if e.kind == ExprKind.expr_member || e.kind == ExprKind.expr_str {
		return false
	}
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr {
		return arg_needs_float_eval(prog, st, fname, e.a)
	}
	return true
}

// arg_class: 参数在 invoke 生成中的分类。
//   addr   -> 直接用 MASM 的 addr 宏（栈上变量）
//   offset -> offset 全局
//   direct -> 直接写进 invoke 参数列表
//   pre    -> 先 emit 指令把值装进池寄存器，再把寄存器名写进列表
//   lea    -> 前面有 eax 依赖，addr 宏不安全，改成 lea 池寄存器
fn arg_class(prog Program, st SymTab, fname string, idx int, eax_before_addr bool) string {
	if addr_is_stack(prog, st, fname, idx) {
		if eax_before_addr {
			return 'lea'
		}
		return 'addr'
	}
	if addr_is_global(prog, st, fname, idx) {
		return 'offset'
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_deref {
		return 'pre'
	}
	if e.kind == ExprKind.expr_ident && e.is_reg {
		if is_small_reg_arg(prog, idx) {
			return 'pre'
		}
		if eax_before_addr && is_eax_family(e.text) {
			return 'pre'
		}
		return 'direct'
	}
	if is_simple_arg(prog, st, fname, idx) {
		return 'direct'
	}
	return 'pre'
}

// cone 0.83：无 exitm 宏调用。参数只做 cone 侧文本化（analyzer 已限制为简单操作数），
// MASM 宏引擎自己做参数替换，因此绝不生成 invoke / push / call。
fn (mut ctx GenCtx) macro_arg_text(idx int) string {
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_num || e.kind == ExprKind.expr_str {
		return e.text
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg || e.is_win_sym || e.is_struct_lit {
			return e.text
		}
		return resolve_name(ctx.st, ctx.fname, e.text)
	}
	if e.kind == ExprKind.expr_neg {
		return '-' + ctx.macro_arg_text(e.a)
	}
	if e.kind == ExprKind.expr_addr {
		return 'offset ' + ctx.macro_arg_text(e.a)
	}
	if e.kind == ExprKind.expr_member {
		return ctx.member_text(idx)
	}
	return ctx.render_arg(idx)
}

fn (mut ctx GenCtx) emit_macro_call(idx int, name string) {
	e := ctx.prog.exprs[idx]
	mut parts := []string{}
	for a in e.args {
		parts << ctx.macro_arg_text(a)
	}
	if parts.len > 0 {
		ctx.emit('    ${name} ' + parts.join(', '))
	} else {
		ctx.emit('    ${name}')
	}
}

fn (mut ctx GenCtx) call(idx int) {
	ctx.call_with_sret(idx, '')
}

fn (mut ctx GenCtx) call_with_sret(idx int, sret_ptr string) {
	e := ctx.prog.exprs[idx]
	target := call_target(e.text)
	sret := is_sret_fn(ctx.st, target)

	// cone 0.83：defined 宏（无 exitm）调用 -> `m a,b`（文本替换，不走 invoke）。
	if e.text in ctx.st.macros {
		ctx.emit_macro_call(idx, e.text)
		return
	}

	// cone 0.4 fix2：任一参数是 64 位就【不能】用 invoke —— MASM32 的
	// invoke 在 32 位模式下无法把 QWORD 压栈。改成手工逆序 push，
	// 把 QWORD 拆成两个 DWORD（先高后低）。
	sizes := ctx.param_push_sizes(e)
	// cone 0.9.2：裸调用（无接收目标）—— 栈上临时接收区，强制手工压栈路径
	if sret && sret_ptr.len == 0 {
		rsz := ctx.st.func_ret_size[target]
		nd := (rsz + 3) / 4 * 4
		ctx.call_manual(idx, sizes, '', nd)
		return
	}
	// cone 0.6：浮点复合表达式实参走手工逆序压栈（sub esp / fstp），
	// 不能用 invoke 的参数表（那里只能写 MASM 操作数，不能插入 x87 求值）。
	mut needs_fp := false
	for a in e.args {
		if arg_needs_float_eval(ctx.prog, ctx.st, ctx.fname, a) {
			needs_fp = true
		}
	}
	if needs_fp {
		ctx.emit('    ; ${target} 含浮点表达式参数：手工压栈走 x87 求值')
		ctx.call_manual(idx, sizes, sret_ptr, 0)
		return
	}
	mut has64 := false
	for sz in sizes {
		if sz == 8 {
			has64 = true
		}
	}
	if has64 {
		ctx.emit('    ; ${target} 含 64 位参数：MASM32 不支持 8 字节入栈，手工拆成两个 dword')
		ctx.call_manual(idx, sizes, sret_ptr, 0)
		return
	}
	// 实参本身是 8 字节内存、但形参是 32 位：invoke 里的 `push qwordvar`
	// 在 32 位模式下不合法，也要走手工路径只压低 dword。
	mut has64_expr := false
	for a in e.args {
		if arg_is_64_expr(ctx.prog, ctx.st, ctx.fname, a) {
			has64_expr = true
		}
	}
	if has64_expr {
		ctx.emit('    ; ${target} 有 8 字节实参但形参是 32 位：手工只压低 dword')
		ctx.call_manual(idx, sizes, sret_ptr, 0)
		return
	}

	// MASM32 的 addr 宏 = lea eax,xxx + push eax。只要局部变量 addr 之前
	// 没有"仍留在 eax 里的参数"（裸 eax/ax/al/ah），右到左压栈就安全；
	// 否则改用 lea 保护寄存器。
	mut eax_before_addr := false
	mut seen_eax := false
	for a in e.args {
		if addr_is_stack(ctx.prog, ctx.st, ctx.fname, a) && seen_eax {
			eax_before_addr = true
		}
		if arg_uses_eax(ctx.prog, a) {
			seen_eax = true
		}
	}

	// 统计需要池寄存器的参数个数；超过 3 个就退回手工逆序压栈。
	mut need_pool := 0
	for a in e.args {
		cl := arg_class(ctx.prog, ctx.st, ctx.fname, a, eax_before_addr)
		if cl == 'pre' || cl == 'lea' {
			need_pool = need_pool + 1
		}
	}

	if need_pool <= 3 {
		mut pool := []string{}
		pool << 'ebx'
		pool << 'esi'
		pool << 'edi'
		mut ri := 0
		mut reprs := []string{}
		for a in e.args {
			cl := arg_class(ctx.prog, ctx.st, ctx.fname, a, eax_before_addr)
			if cl == 'addr' {
				nm := ctx.struct_label_or_name(addr_target(ctx.prog, a))
				reprs << 'addr ${nm}'
			} else if cl == 'offset' {
				reprs << 'offset ' + ctx.struct_label_or_name(addr_target(ctx.prog, a))
			} else if cl == 'direct' {
				reprs << ctx.render_arg(a)
			} else {
				reg := pool[ri]
				ri = ri + 1
				if cl == 'lea' {
					nm := ctx.struct_label_or_name(addr_target(ctx.prog, a))
					ctx.emit('    lea ${reg}, ${nm}')
				} else if ctx.prog.exprs[a].kind == ExprKind.expr_deref {
					// [] 直接内存访问：把该地址处的值装进池寄存器
					ctx.deref_load_reg(a, reg)
				} else if is_small_reg_arg(ctx.prog, a) {
					ctx.emit('    movzx ${reg}, ${ctx.prog.exprs[a].text}')
				} else if ctx.prog.exprs[a].kind == ExprKind.expr_ident && ctx.prog.exprs[a].is_reg {
					ctx.emit('    mov ${reg}, ${ctx.prog.exprs[a].text}')
				} else {
					ctx.emit_load(a, reg)
				}
				reprs << reg
			}
		}
		mut allr := []string{}
		if sret_ptr.len > 0 {
			allr << sret_ptr
		}
		for r in reprs {
			allr << r
		}
		mut line := '    invoke ${target}'
		if allr.len > 0 {
			line = line + ', ' + allr.join(', ')
		}
		ctx.emit(line)
		return
	}

	// 参数过多：展开成 call + 逆序 push。
	ctx.emit('    ; invoke ${target} 的展开（池寄存器不足，手工逆序压栈）')
	ctx.call_manual(idx, sizes, sret_ptr, 0)
}

// ---------- 语句 ----------

// cone 0.4 fix2：asm{...} 内嵌汇编
// trim_asm_text: 只裁掉正文首尾的空白行，中间内容（含缩进、注释、空行）完全原样。
fn trim_asm_text(s string) string {
	mut a := 0
	mut b := s.len
	for a < b && (is_hspace(s[a]) || s[a] == 10) {
		a = a + 1
	}
	for b > a && (is_hspace(s[b - 1]) || s[b - 1] == 10) {
		b = b - 1
	}
	if a >= b {
		return ''
	}
	// 只裁掉首尾的空白【行】，保留正文每一行用户自己写的缩进。
	for a > 0 && s[a - 1] != 10 {
		a = a - 1
	}
	for b < s.len && s[b] != 10 {
		b = b + 1
	}
	return s[a..b]
}

// asm_resolve_text: %% -> 单个 %；%标识符 -> resolve_name() 得到的 MASM 名
// （cone 的名称修饰只在这里发生）；其余字符原样透传。
// asm 正文里 MASM 侧本来就存在的符号（MB_OK、crt_printf 等）直接写名字，不加 %。
fn asm_resolve_text(st SymTab, fname string, text0 string) string {
	// cone 0.9prelease：裸正文里的 sizeof(...) / cone struct Type.member 由 cone 算成立即数。
	// 折叠过的 equ 不替换裸文本（沿用 0.7 约定：必须用 %NAME，避免误伤普通 MASM 文本）。
	text := cone_subst_imm(st, text0, false)
	mut parts := []string{}
	mut i := 0
	for i < text.len {
		if text[i] == 37 { // %
			if i + 1 < text.len && text[i + 1] == 37 {
				parts << '%'
				i = i + 2
				continue
			}
			if i + 1 < text.len && is_ident_start(text[i + 1]) {
				mut j := i + 1
				for j < text.len && is_ident_cont(text[j]) {
					j = j + 1
				}
				// cone 0.9prelease：% 后允许点链（%Type.member）
				for j < text.len && text[j] == 46 && j + 1 < text.len && is_ident_start(text[j + 1]) {
					j = j + 1
					for j < text.len && is_ident_cont(text[j]) {
						j = j + 1
					}
				}
				nm := text[i + 1..j]
				// cone 0.9prelease：%sizeof(NAME)
				if nm.to_lower() == 'sizeof' && j < text.len && text[j] == 40 {
					mut k := j + 1
					for k < text.len && text[k] != 41 {
						k = k + 1
					}
					if k < text.len {
						arg := text[j + 1..k].trim_space()
						v := cone_sizeof_of(st, arg) or {
							parts << 'sizeof(${arg})'
							i = k + 1
							continue
						}
						parts << '${v}'
						i = k + 1
						continue
					}
				}
				// cone 0.9prelease：%Type.member -> cone 计算的字节偏移
				if nm.contains('.') {
					if nm in st.struct_offsets {
						parts << '${st.struct_offsets[nm]}'
						i = j
						continue
					}
					pcs := nm.split('.')
					mut done := false
					mut cut := pcs.len
					for cut > 0 {
						key2 := pcs[..cut].join('.')
						if key2 in st.struct_offsets {
							rest := pcs[cut..].join('.')
							mut r := '${st.struct_offsets[key2]}'
							if rest.len > 0 {
								r = r + '.' + rest
							}
							parts << r
							done = true
							break
						}
						cut = cut - 1
					}
					if done {
						i = j
						continue
					}
				}
				// cone 0.7：数值 equ 在 cone 侧已折叠，MASM 侧不再有该符号，
				// %NAME 必须替换成立即数文本，否则 .asm 会引用未定义符号。
				if nm in st.equ_values {
					parts << st.equ_values[nm]
				} else {
					parts << resolve_name(st, fname, nm)
				}
				i = j
				continue
			}
		}
		parts << text[i..i + 1]
		i = i + 1
	}
	return parts.join('')
}

// emit_asm: 整段正文（含换行）作为一次 emit 进入 .asm，generate 末尾按 \n join，
// 所以 asm 里的每一行都保持用户写的原样。
fn (mut ctx GenCtx) emit_asm(s Stmt) {
	ctx.emit(asm_resolve_text(ctx.st, ctx.fname, trim_asm_text(s.asm_text)))
}


// emit_mov_reg_reg: 寄存器值写入目标（寄存器或内存），按尺寸换算并避免 mov reg,reg。
fn (mut ctx GenCtx) emit_mov_reg_reg(dst string, dst_is_reg bool, dsize int, src string) {
	ssz := reg_size(src)
	if dst_is_reg {
		dsz := reg_size(dst)
		if eq_ci(src, dst) {
			return
		}
		if ssz == dsz {
			ctx.emit('    mov ${dst}, ${src}')
			return
		}
		if ssz < dsz {
			ctx.emit('    movzx ${dst}, ${src}')
			return
		}
		low := reg_low_for(src, dsz)
		if low.len > 0 {
			if eq_ci(low, dst) {
				return
			}
			ctx.emit('    mov ${dst}, ${low}')
			return
		}
		ctx.emit('    movzx eax, ${src}')
		ctx.emit('    mov ${dst}, ${reg_low_of_eax(dsz)}')
		return
	}
	if !eq_ci(reg_family(src), 'eax') && ssz < 4 {
		ctx.emit('    movzx eax, ${src}')
		ctx.emit_store_from_eax(dst, dsize)
		return
	}
	if ssz == dsize {
		ctx.emit('    mov ${dst}, ${src}')
		return
	}
	if ssz > dsize {
		low := reg_low_for(src, dsize)
		if low.len > 0 {
			ctx.emit('    mov ${dst}, ${low}')
			return
		}
	}
	ctx.emit_store_from_eax(dst, dsize)
}

// emit_store_from_eax: 值已在 eax，按目标尺寸写出（al/ax/eax 或 8 字节零扩展）。
fn (mut ctx GenCtx) emit_store_from_eax(dst string, dsize int) {
	if dsize == 8 {
		ctx.emit('    mov dword ptr ${dst}, eax')
		ctx.emit('    mov dword ptr ${dst}+4, 0    ; 零扩展')
		return
	}
	ctx.emit('    mov ${dst}, ${reg_low_of_eax(dsize)}')
}

// emit_assign: 统一的赋值发射器（cone 0.3）。
// 目标可以是全局变量 / 局部变量 / 形参 / 寄存器；右值可以是
// imm / reg / mem / [] 内存访问 / 复合表达式 / 调用。
// 优化点：能一条 mov 搞定就一条；结果已在目标寄存器时【不发】无意义 mov。
// ---------- cone 0.6 fix1：整数赋值优化 ----------
// a=a+2 -> add a,2；a=a|MASK -> or a,MASK；+1 / -1 直接用 inc / dec。
fn is_dec_digits(s string) bool {
	if s.len == 0 { return false }
	mut i := 0
	if s[0] == 45 { i = 1 }
	if i >= s.len { return false }
	for i < s.len {
		if s[i] < 48 || s[i] > 57 { return false }
		i = i + 1
	}
	return true
}

fn (mut ctx GenCtx) self_match(idx int, self_text string, lhs_idx int) bool {
	if idx < 0 { return false }
	if lhs_idx >= 0 && idx == lhs_idx { return true }
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_ident { return e.text == self_text }
	if e.kind == ExprKind.expr_member { return ctx.member_text(idx) == self_text }
	return false
}

fn (mut ctx GenCtx) simple_operand(idx int) string {
	if idx < 0 { return '' }
	fr := try_fold(ctx.prog, idx)
	if fr.ok { return '${fr.value}' }
	c := masm_const(ctx.prog, ctx.st, ctx.fname, idx)
	if c.len > 0 { return c }
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		if is_float_lit(e.text) { return '' }
		return e.text
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg {
			if reg_size(e.text) == 4 { return e.text }
			return ''
		}
		if is_data_label(ctx.st, e.text) {
			return 'dword ptr [' + resolve_name(ctx.st, ctx.fname, e.text) + ']'
		}
		return resolve_name(ctx.st, ctx.fname, e.text)
	}
	if e.kind == ExprKind.expr_member { return ctx.member_text(idx) }
	if e.kind == ExprKind.expr_deref {
		return deref_ptr_text(e.ptr_size) + ' [' + ctx.addr_text(e.a) + ']'
	}
	if e.kind == ExprKind.expr_str && e.is_char_const {
		return 'offset ' + char_label_of(e.text, ctx.char_labels)
	}
	if e.kind == ExprKind.expr_addr {
		nm := addr_target(ctx.prog, idx)
		if is_stack_name(ctx.st, ctx.fname, nm) { return 'addr ' + ctx.struct_label_or_name(nm) }
		return 'offset ' + ctx.struct_label_or_name(nm)
	}
	if e.kind == ExprKind.expr_neg && ctx.prog.exprs[e.a].kind == ExprKind.expr_num {
		return '-' + ctx.prog.exprs[e.a].text
	}
	return ''
}

fn (mut ctx GenCtx) peephole(dst string, dst_is_reg bool, rhs_idx int, lhs_idx int, self_text string) bool {
	if expr_is_float(ctx.prog, ctx.st, ctx.fname, rhs_idx) { return false }
	e := ctx.prog.exprs[rhs_idx]
	if e.kind != ExprKind.expr_bin { return false }
	op := e.text
	ins := peep_insn(op)
	if ins.len == 0 { return false }
	a := e.a
	b := e.b
	mut other := b
	if ctx.self_match(a, self_text, lhs_idx) {
		other = b
	} else if ctx.self_match(b, self_text, lhs_idx) {
		if op != '+' && op != '|' && op != '&' && op != '^' { return false }
		other = a
	} else {
		return false
	}
	if op == '-' || op == '<<' || op == '>>' {
		if !ctx.self_match(a, self_text, lhs_idx) { return false }
	}
	operand := ctx.simple_operand(other)
	if operand.len == 0 { return false }
	if op == '<<' || op == '>>' {
		if !is_dec_digits(operand) { return false }
	}
	if !dst_is_reg {
		// x86 不允许 mem-mem：目的为内存时另一个操作数只能是立即数 / 常量表达式
		oe := ctx.prog.exprs[other]
		mut ok := false
		if oe.kind == ExprKind.expr_num { ok = true }
		if oe.kind == ExprKind.expr_neg && ctx.prog.exprs[oe.a].kind == ExprKind.expr_num { ok = true }
		if oe.kind == ExprKind.expr_ident {
			if oe.is_reg || oe.is_win_sym || is_equ(ctx.st, oe.text) { ok = true }
		}
		if masm_const(ctx.prog, ctx.st, ctx.fname, other).len > 0 { ok = true }
		if !ok { return false }
	}
	if op == '+' && operand == '1' {
		ctx.emit('    inc ${dst}')
		return true
	}
	if op == '-' && operand == '1' {
		ctx.emit('    dec ${dst}')
		return true
	}
	ctx.emit('    ${ins} ${dst}, ${operand}')
	return true
}

fn (mut ctx GenCtx) emit_assign(dst string, dst_is_reg bool, dsize int, rhs_idx int, lhs_idx int, self_text string) {
	if ctx.peephole(dst, dst_is_reg, rhs_idx, lhs_idx, self_text) { return }
	e := ctx.prog.exprs[rhs_idx]
	fr := try_fold(ctx.prog, rhs_idx)
	if fr.ok {
		ctx.emit('    mov ${dst}, ${fr.value}')
		return
	}
	// cone 0.3 完善：目标是 32 位寄存器时，整个右值直接求进 dst。
	// emit_load 已能避免 mov reg,reg、尺寸换算、以及 bin 的 push/pop 退化，
	// 所以 `ebx=r+1` -> mov ebx,r / add ebx,1，`ecx=addr fmt-4` -> mov ecx,offset fmt / sub ecx,4。
	if dst_is_reg && dsize == 4 {
		ctx.emit_load(rhs_idx, dst)
		return
	}
	if e.kind == ExprKind.expr_ident && e.is_reg {
		ctx.emit_mov_reg_reg(dst, dst_is_reg, dsize, e.text)
		return
	}
	if e.kind == ExprKind.expr_ident && !e.is_reg {
		if dst_is_reg {
			ctx.emit_ident_to_reg(e.text, dst)
			return
		}
		// mem -> mem：x86 不支持，必须借 32 位寄存器中转（这一步不是无意义 mov）
		ctx.emit_ident_to_reg(e.text, 'eax')
		ctx.emit_store_from_eax(dst, dsize)
		return
	}
	if e.kind == ExprKind.expr_member {
		t := ctx.member_text(rhs_idx)
		if dst_is_reg && dsize == 4 {
			ctx.emit('    mov ${dst}, ${t}')
			return
		}
		ctx.emit('    mov eax, ${t}')
		ctx.emit_store_from_eax(dst, dsize)
		return
	}
	if e.kind == ExprKind.expr_deref {
		if dst_is_reg && dsize == 4 {
			// 直接把 [] 内存值装进目标寄存器，省一次搬运
			ctx.deref_load_reg(rhs_idx, dst)
			return
		}
		ctx.deref_load_reg(rhs_idx, 'eax')
		if dst_is_reg {
			ctx.emit_mov_reg_reg(dst, true, dsize, 'eax')
		} else {
			ctx.emit_store_from_eax(dst, dsize)
		}
		return
	}
	// 复合表达式 / 调用 / addr / 一元负号：求值到 eax
	ctx.emit_load(rhs_idx, 'eax')
	if dst_is_reg && dsize == 4 && eq_ci(dst, 'eax') {
		return
	}
	if dst_is_reg {
		ctx.emit_mov_reg_reg(dst, true, dsize, 'eax')
	} else {
		ctx.emit_store_from_eax(dst, dsize)
	}
}

// float_store_ptr: fstp 的目标尺寸前缀。cone 只论字节大小：4 字节 -> m32fp，
// 8 字节 -> m64fp；显式尺寸词只用于判定字节数，输出统一 dword/qword ptr。
fn float_store_ptr(n int) string {
	if n == 8 {
		return 'qword ptr'
	}
	return 'dword ptr'
}

// assign_float_lvalue: mem / 结构体成员 / [] 作左值且右值出现浮点时，
// 走 x87：fld ...（把浮点常量放进 .const 池）后 fstp 到目标，绝不生成
// `mov xxx, 1.0` 这种 MASM32 拒绝的 real 立即数指令。
fn (mut ctx GenCtx) assign_float_lvalue(rhs_idx int, dst string, nb int) {
	ctx.float_eax(rhs_idx)
	ctx.emit('    fstp ${float_store_ptr(nb)} ${dst}')
}

// assign_member: st.x = rhs / arg1.y = rhs，MASM 直接支持成员作 mov 目的操作数。
fn (mut ctx GenCtx) assign_member(s Stmt) {
	dst := ctx.member_text(s.lhs_idx)
	sz := ctx.member_bytes(s.lhs_idx)
	if expr_is_float(ctx.prog, ctx.st, ctx.fname, s.rhs_idx) {
		ctx.assign_float_lvalue(s.rhs_idx, dst, sz)
		return
	}
	ctx.emit_assign(dst, false, sz, s.rhs_idx, s.lhs_idx, dst)
}

// assign_int: 兼容旧调用点，转交 emit_assign。
fn (mut ctx GenCtx) assign_int(s Stmt) {
	dst_is_reg := is_reg_name(s.lhs)
	ctx.emit_assign(resolve_name(ctx.st, ctx.fname, s.lhs), dst_is_reg, symbol_size(ctx.st, ctx.fname, s.lhs), s.rhs_idx, -1, s.lhs)
}

// assign_deref: [type addr] = yyy，与 MASM32 一致 —— 直接
//   mov type ptr [addr], yyy
// cone 0.3 完善版撤销了初版的"两步间接"：MASM 里 mov [mem],x 与 mov mem,x 等效，
// [type mem]=yyy 在 type 与 mem 尺寸一致时就等价于 mem=yyy，但 cone 这里还能
// 自定义尺寸（byte/word/real4...）与偏移（+4 / +reg*scale），这才是它的价值。
// 真正的解引用由 cone 代码显式写 `regname=var` 再 `[type regname]=yyy`。
//
// 仅当左右都是内存操作数时（x86 不允许 mem,mem）才分配一个中转寄存器；
// 立即数与寄存器右值一律直写，不多发一条 mov。
fn (mut ctx GenCtx) assign_deref(s Stmt) {
	le := ctx.prog.exprs[s.lhs_idx]
	ptr := deref_ptr_text(le.ptr_size)
	nb := deref_size_bytes(le.ptr_size)
	addr_has_call := expr_has_call(ctx.prog, le.a)

	// cone 0.4 fix：[] 同样是合法浮点左值。先求浮点值进 st(0)，再渲染地址
	// （地址里若有函数调用会占 eax，但 x87 栈里的值不依赖 eax）。
	if expr_is_float(ctx.prog, ctx.st, ctx.fname, s.rhs_idx) {
		ctx.float_eax(s.rhs_idx)
		a := ctx.addr_text(le.a)
		ctx.emit('    fstp ${float_store_ptr(nb)} [${a}]')
		return
	}

	fr := try_fold(ctx.prog, s.rhs_idx)
	if fr.ok {
		a := ctx.addr_text(le.a)
		if nb >= 6 {
			ctx.emit('    mov dword ptr [${a}], ${fr.value}    ; [] 指定 ${ptr}，32 位立即数只写低 dword')
		} else {
			ctx.emit('    mov ${ptr} [${a}], ${fr.value}')
		}
		return
	}

	re := ctx.prog.exprs[s.rhs_idx]
	// 右值本来就是寄存器：按 [] 指定的尺寸取它的低位名直接写。
	// 地址表达式里含函数调用时结果占 eax，此时 eax 族右值要改走中转，避免被覆盖。
	if re.kind == ExprKind.expr_ident && re.is_reg {
		low := reg_low_for(re.text, nb)
		if low.len > 0 && !(addr_has_call && is_eax_family(re.text)) {
			a := ctx.addr_text(le.a)
			if nb >= 6 {
				ctx.emit('    mov dword ptr [${a}], ${re.text}    ; [] 指定 ${ptr}，32 位寄存器只写低 dword')
			} else {
				ctx.emit('    mov ${ptr} [${a}], ${low}')
			}
			return
		}
	}

	// 右值是内存 / 复合表达式 / 调用：必须用寄存器中转。
	// 先把右值求进中转寄存器，再渲染地址（地址里若有 call 会占 eax，不影响 val）。
	val := pick_store_reg(ctx.prog, le.a, s.rhs_idx)
	ctx.emit_load(s.rhs_idx, val)
	a := ctx.addr_text(le.a)
	if nb >= 6 {
		ctx.emit('    mov dword ptr [${a}], ${val}    ; [] 指定 ${ptr}，32 位寄存器只写低 dword')
	} else {
		ctx.emit('    mov ${ptr} [${a}], ${store_low_reg(val, nb)}')
	}
}

// render_cond: 把 cone 条件表达式渲染成 MASM `.if / .elseif` 的表达式文本。
// 调用方（parse_if_chain 的 degraded 判定）保证这里不含 expr_call / expr_addr /
// expr_str，所以 addr_text 不会在渲染时偷偷发射指令。
// ---------- cone 0.3：.if / .while 条件里的 mem-mem 比较中转 ----------
//
// MASM32 的 cmp 不接受 mem,mem，而 `.if ((x > y) || (x == y))` 展开后就是 `cmp x, y`。
// 简单条件仍优先保留 .if 系列伪指令：把比较的左操作数先搬进一个空闲寄存器，
// 再把该比较渲染成 `<reg> op <mem>`，MASM 就会生成合法的 cmp reg,mem。
// .while 的条件每轮都要重算，不能把 mov 提到循环外，所以循环里的 mem-mem 比较
// 一律降级成显式标签 + cmp + jcc（每轮重新求值），避免用到过期的值。

struct CondPlan {
mut:
	subs  map[string]string // 操作数文本 -> 中转寄存器
	moves []string          // 该条件求值前要发射的 mov / movzx
}

struct ChainPlan {
	plans []CondPlan
	ok    bool
}

fn is_mem_operand(prog Program, idx int) bool {
	if idx < 0 || idx >= prog.exprs.len {
		return false
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_ident && !e.is_reg && !e.is_win_sym {
		return true
	}
	if e.kind == ExprKind.expr_deref {
		return true
	}
	if e.kind == ExprKind.expr_member {
		return true
	}
	return false
}

fn collect_cmp_nodes(prog Program, idx int, out []int) []int {
	mut res := out.clone()
	if idx < 0 || idx >= prog.exprs.len {
		return res
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_bin && is_cmp_text(e.text) {
		if !(idx in res) {
			res << idx
		}
	}
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr || e.kind == ExprKind.expr_deref {
		res = collect_cmp_nodes(prog, e.a, res)
	}
	if e.kind == ExprKind.expr_bin {
		res = collect_cmp_nodes(prog, e.a, res)
		res = collect_cmp_nodes(prog, e.b, res)
	}
	if e.kind == ExprKind.expr_call {
		for a in e.args {
			res = collect_cmp_nodes(prog, a, res)
		}
	}
	return res
}

fn collect_registers(prog Program, idx int, out []string) []string {
	mut res := out.clone()
	if idx < 0 || idx >= prog.exprs.len {
		return res
	}
	e := prog.exprs[idx]
	if e.kind == ExprKind.expr_ident && e.is_reg {
		f := reg_family(e.text)
		mut seen := false
		for t in res {
			if eq_ci(t, f) {
				seen = true
			}
		}
		if !seen {
			res << f
		}
	}
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr || e.kind == ExprKind.expr_deref {
		res = collect_registers(prog, e.a, res)
	}
	if e.kind == ExprKind.expr_bin {
		res = collect_registers(prog, e.a, res)
		res = collect_registers(prog, e.b, res)
	}
	if e.kind == ExprKind.expr_call {
		for a in e.args {
			res = collect_registers(prog, a, res)
		}
	}
	return res
}

// free_scratch_pool: 本函数里用户没有显式碰过的 32 位寄存器，按 ebx/esi/edi/ecx/edx 顺序。
// ebx/esi/edi 由 `uses ebx esi edi` 保护；ecx/edx 在没有调用的 .if 路径里也安全。
fn (mut ctx GenCtx) free_scratch_pool() []string {
	mut touched := []string{}
	for s in ctx.body {
		if is_reg_name(s.lhs) {
			f := reg_family(s.lhs)
			mut seen := false
			for t in touched {
				if eq_ci(t, f) {
					seen = true
				}
			}
			if !seen {
				touched << f
			}
		}
		if s.ret_idx >= 0 {
			touched = collect_registers(ctx.prog, s.ret_idx, touched)
		}
		if s.rhs_idx >= 0 {
			touched = collect_registers(ctx.prog, s.rhs_idx, touched)
		}
		if s.call_idx >= 0 {
			touched = collect_registers(ctx.prog, s.call_idx, touched)
		}
		if s.cond_idx >= 0 {
			touched = collect_registers(ctx.prog, s.cond_idx, touched)
		}
		if s.lhs_idx >= 0 {
			touched = collect_registers(ctx.prog, s.lhs_idx, touched)
		}
		if s.target_idx >= 0 {
			touched = collect_registers(ctx.prog, s.target_idx, touched)
		}
		if s.case_idx >= 0 {
			touched = collect_registers(ctx.prog, s.case_idx, touched)
		}
	}
	mut pool := []string{}
	for r in ['ebx', 'esi', 'edi', 'ecx', 'edx'] {
		mut blocked := false
		for t in touched {
			if eq_ci(t, r) {
				blocked = true
			}
		}
		if !blocked {
			pool << r
		}
	}
	return pool
}

fn (mut ctx GenCtx) cond_operand_text(idx int) string {
	if idx < 0 || idx >= ctx.prog.exprs.len {
		return ''
	}
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_ident {
		nm := resolve_name(ctx.st, ctx.fname, e.text)
		// 数据标签是 db 字节流，MASM 不能把它当 32 位内存直接用，取低 dword。
		if is_data_label(ctx.st, e.text) {
			return 'dword ptr [${nm}]'
		}
		return nm
	}
	if e.kind == ExprKind.expr_deref {
		return '${deref_ptr_text(e.ptr_size)} [${ctx.addr_text(e.a)}]'
	}
	if e.kind == ExprKind.expr_member {
		return ctx.member_text(idx)
	}
	return ''
}

fn (mut ctx GenCtx) cond_operand_size(idx int) int {
	if idx < 0 || idx >= ctx.prog.exprs.len {
		return 4
	}
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_ident {
		return symbol_size(ctx.st, ctx.fname, e.text)
	}
	if e.kind == ExprKind.expr_deref {
		return deref_size_bytes(e.ptr_size)
	}
	if e.kind == ExprKind.expr_member {
		return ctx.member_bytes(idx)
	}
	return 4
}

// collect_chain_conds: 从当前 st_if 起收集同一条 if 链（深度 1）的全部条件，
// 让 stmt_if 一次性为整条链规划寄存器，避免走到中途才发现寄存器不够而推翻 .if。
fn (mut ctx GenCtx) collect_chain_conds() []int {
	mut conds := []int{}
	mut depth := 0
	mut j := ctx.body_pos
	for j < ctx.body.len {
		k := ctx.body[j].kind
		if k == StmtKind.st_if {
			depth = depth + 1
			if depth == 1 {
				conds << ctx.body[j].cond_idx
			}
		} else if k == StmtKind.st_elseif {
			if depth == 1 {
				conds << ctx.body[j].cond_idx
			}
		} else if k == StmtKind.st_endif {
			depth = depth - 1
			if depth == 0 {
				break
			}
		}
		j = j + 1
	}
	return conds
}

fn (mut ctx GenCtx) plan_conds(conds []int, allow_hoist bool) ChainPlan {
	mut plans := []CondPlan{}
	pool := ctx.free_scratch_pool()
	// 注意：寄存器分配必须【每条分支独立】。前一个分支的 body 可能改过变量，
	// 所以每条 condition 前都要重新发射一遍 mov，不能跨分支复用旧值。
	for ci in conds {
		mut plan := CondPlan{
			subs:  map[string]string{}
			moves: []string{}
		}
		mut used := []string{}
		mut text_to_reg := map[string]string{}
		mut nodes := []int{}
		nodes = collect_cmp_nodes(ctx.prog, ci, nodes)
		for ni in nodes {
			e := ctx.prog.exprs[ni]
			if !is_mem_operand(ctx.prog, e.a) || !is_mem_operand(ctx.prog, e.b) {
				continue
			}
			if !allow_hoist {
				return ChainPlan{plans: plans, ok: false}
			}
			// 两个操作数都搬进寄存器：MASM 展开出的一定是 cmp reg,reg，
			// 彻底避开 cmp mem,mem 以及 byte/word 与 32 位寄存器的尺寸不匹配。
			mut operands := []int{}
			operands << e.a
			operands << e.b
			for oi in operands {
				t := ctx.cond_operand_text(oi)
				sz := ctx.cond_operand_size(oi)
				if t.len == 0 || sz > 4 {
					return ChainPlan{plans: plans, ok: false}
				}
				mut reg := ''
				if t in text_to_reg {
					reg = text_to_reg[t]
				} else {
					if used.len >= pool.len {
						return ChainPlan{plans: plans, ok: false}
					}
					reg = pool[used.len]
					used << reg
					text_to_reg[t] = reg
					if sz == 1 || sz == 2 {
						plan.moves << '    movzx ${reg}, ${t}'
					} else {
						plan.moves << '    mov ${reg}, ${t}'
					}
				}
				plan.subs[t] = reg
			}
		}
		plans << plan
	}
	return ChainPlan{plans: plans, ok: true}
}

fn (mut ctx GenCtx) render_cond(idx int) string {
	empty := map[string]string{}
	return ctx.render_cond_ex(idx, empty)
}

// render_cond_ex: 把条件渲染成 MASM .if / .while 表达式；subs 把 mem 操作数换成
// 预先算好的中转寄存器，避免 MASM 展开出 cmp mem,mem。
fn (mut ctx GenCtx) render_cond_ex(idx int, subs map[string]string) string {
	if idx < 0 || idx >= ctx.prog.exprs.len {
		return '0'
	}
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		return e.text
	}
	if e.kind == ExprKind.expr_ident || e.kind == ExprKind.expr_deref || e.kind == ExprKind.expr_member {
		t := ctx.cond_operand_text(idx)
		if t.len == 0 {
			return '0'
		}
		if t in subs {
			return subs[t]
		}
		return t
	}
	if e.kind == ExprKind.expr_neg {
		inner := ctx.render_cond_ex(e.a, subs)
		if e.text == '!' { return '!(' + inner + ')' }
		if e.text == '~' { return 'not (' + inner + ')' }
		if e.a >= 0 && e.a < ctx.prog.exprs.len && ctx.prog.exprs[e.a].kind == ExprKind.expr_num {
			return '-' + inner // 负立即数直出，MASM .if 不接受 -(1)
		}
		return '-(' + inner + ')'
	}
	if e.kind == ExprKind.expr_bin {
		op := masm_bin_op(e.text)
		return '(' + ctx.render_cond_ex(e.a, subs) + ' ' + op + ' ' + ctx.render_cond_ex(e.b, subs) + ')'
	}
	return '0'
}

// cond_inline_operand: 右操作数能否直接写进 `cmp eax, <operand>`。
// 只放行 32 位宽的立即数 / 寄存器 / 变量 / win 符号 / equ 常量，避免
// `cmp eax, bytevar` 这种 MASM 会拒的尺寸不匹配；其余走 movzx/中转。
fn (mut ctx GenCtx) cond_inline_operand(idx int) string {
	if idx < 0 || idx >= ctx.prog.exprs.len {
		return ''
	}
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		if is_float_lit(e.text) {
			return ''
		}
		return e.text
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg {
			if reg_size(e.text) == 4 {
				return e.text
			}
			return ''
		}
		if e.is_win_sym {
			return e.text
		}
		if is_equ(ctx.st, e.text) {
			return resolve_name(ctx.st, ctx.fname, e.text)
		}
		if is_data_label(ctx.st, e.text) {
			return ''
		}
		if symbol_size(ctx.st, ctx.fname, e.text) == 4 {
			return resolve_name(ctx.st, ctx.fname, e.text)
		}
	}
	return ''
}

// emit_cmp: 把比较的左值求到 eax，右值尽量内联成 `cmp eax, imm/name`。
// 右值确实需要发射指令（调用 / 表达式 / 字符常量地址）时才 push 保护左值，
// 不再无脑 push eax + mov ebx,eax + pop eax 三条往返。
fn (mut ctx GenCtx) emit_cmp(idx int, signed bool) {
	e := ctx.prog.exprs[idx]
	ctx.emit_cond_eval_ex(e.a, signed)
	inline := ctx.cond_inline_operand(e.b)
	if inline.len > 0 {
		ctx.emit('    cmp eax, ${inline}')
		return
	}
	ctx.emit('    push eax')
	ctx.emit_load(e.b, 'ebx')
	ctx.emit('    pop eax')
	ctx.emit('    cmp eax, ebx')
}

// emit_cond_branch: 条件为假时跳到 false_lbl。
// 根节点是比较时直接 `cmp` + 反向 jcc，省掉 setcc / movzx / test / jz 四条；
// 默认与 MASM .if 一致按无符号（jbe / jae / jb / ja），signed 条件用有符号（jle / jge / jl / jg）。
fn (mut ctx GenCtx) emit_cond_branch(idx int, false_lbl string, signed bool) {
	if idx >= 0 && idx < ctx.prog.exprs.len {
		e := ctx.prog.exprs[idx]
		if e.kind == ExprKind.expr_bin && is_cmp_text(e.text) {
			ctx.emit_cmp(idx, signed)
			ctx.emit('    ${jcc_neg_of(e.text, signed)} ${false_lbl}')
			return
		}
	}
	ctx.emit_cond_eval_ex(idx, signed)
	ctx.emit('    test eax, eax')
	ctx.emit('    jz ${false_lbl}')
}

// emit_cond_eval_ex: 降级路径把条件求值成 eax（0 = 假，非 0 = 真）。
// 默认按无符号 setcc；condition 前写了 signed 才用有符号 setcc；&& / || 不短路，两侧都求值。
fn (mut ctx GenCtx) emit_cond_eval_ex(idx int, signed bool) {
	if idx < 0 || idx >= ctx.prog.exprs.len {
		return
	}
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_neg && e.text == '!' {
		ctx.emit_cond_eval_ex(e.a, signed)
		ctx.emit('    test eax, eax')
		ctx.emit('    sete al')
		ctx.emit('    movzx eax, al')
		return
	}
	if e.kind == ExprKind.expr_bin && is_cmp_text(e.text) {
		ctx.emit_cmp(idx, signed)
		ctx.emit('    ${setcc_of(e.text, signed)} al')
		ctx.emit('    movzx eax, al')
		return
	}
	if e.kind == ExprKind.expr_bin && (e.text == '&&' || e.text == '||') {
		ctx.emit_cond_eval_ex(e.a, signed)
		ctx.emit('    push eax')
		ctx.emit_cond_eval_ex(e.b, signed)
		ctx.emit('    mov ebx, eax')
		ctx.emit('    pop eax')
		ctx.emit('    test eax, eax')
		ctx.emit('    setne al')
		ctx.emit('    movzx eax, al')
		ctx.emit('    test ebx, ebx')
		ctx.emit('    setne bl')
		ctx.emit('    movzx ebx, bl')
		if e.text == '&&' {
			ctx.emit('    and eax, ebx')
		} else {
			ctx.emit('    or eax, ebx')
		}
		return
	}
	ctx.emit_load(idx, 'eax')
}

// ---------- if 链标签栈 ----------

fn (mut ctx GenCtx) if_push(fr IfFrame) {
	ctx.if_stack << fr
}

fn (mut ctx GenCtx) if_top() IfFrame {
	return ctx.if_stack[ctx.if_stack.len - 1]
}

fn (mut ctx GenCtx) if_set(fr IfFrame) {
	ctx.if_stack = ctx.if_stack[..ctx.if_stack.len - 1]
	ctx.if_stack << fr
}

fn (mut ctx GenCtx) if_pop() {
	ctx.if_stack = ctx.if_stack[..ctx.if_stack.len - 1]
}

fn (mut ctx GenCtx) stmt_if(s Stmt) {
	id := ctx.if_id
	ctx.if_id = ctx.if_id + 1
	tag := '__cone_if_${ctx.fname}_${id}'
	end := hidden_name('${tag}_end', ctx.st.globals)
	// 整条 if 链一次性规划 mem-mem 中转寄存器；寄存器不够就整链降级，
	// 避免走到某个 elseif 才发现要推翻已经发出的 .if。
	mut degraded := s.degraded
	mut plans := []CondPlan{}
	if !degraded {
		conds := ctx.collect_chain_conds()
		cp := ctx.plan_conds(conds, true)
		if !cp.ok {
			degraded = true
		} else {
			plans = cp.plans.clone()
		}
	}
	if degraded {
		lbl := hidden_name('${tag}_c0', ctx.st.globals)
		ctx.if_push(IfFrame{
			id:       id
			tag:      tag
			end:      end
			pending:  lbl
			clause:   0
			degraded: true
		})
		ctx.emit_cond_branch(s.cond_idx, lbl, s.cond_signed)
		return
	}
	ctx.if_push(IfFrame{
		id:       id
		tag:      tag
		end:      end
		pending:  ''
		clause:   0
		degraded: false
		plans:    plans
		plan_idx: 1
	})
	mut plan := CondPlan{
		subs:  map[string]string{}
		moves: []string{}
	}
	if plans.len > 0 {
		plan = plans[0]
	}
	for m in plan.moves {
		ctx.emit(m)
	}
	ctx.emit('    .if ${ctx.render_cond_ex(s.cond_idx, plan.subs)}')
}

fn (mut ctx GenCtx) stmt_elseif(s Stmt) {
	if ctx.if_stack.len > 0 {
		mut fr := ctx.if_top()
		if fr.degraded {
			ctx.emit('    jmp ${fr.end}')
			ctx.emit('${fr.pending}:')
			nc := fr.clause + 1
			lbl := hidden_name('${fr.tag}_c${nc}', ctx.st.globals)
			ctx.if_set(IfFrame{
				id:       fr.id
				tag:      fr.tag
				end:      fr.end
				pending:  lbl
				clause:   nc
				degraded: true
			})
			ctx.emit_cond_branch(s.cond_idx, lbl, s.cond_signed)
			return
		}
		if fr.plan_idx < fr.plans.len {
			plan := fr.plans[fr.plan_idx]
			fr.plan_idx = fr.plan_idx + 1
			ctx.if_set(fr)
			for m in plan.moves {
				ctx.emit(m)
			}
			ctx.emit('    .elseif ${ctx.render_cond_ex(s.cond_idx, plan.subs)}')
			return
		}
		fr.plan_idx = fr.plan_idx + 1
		ctx.if_set(fr)
	}
	ctx.emit('    .elseif ${ctx.render_cond(s.cond_idx)}')
}

fn (mut ctx GenCtx) stmt_else() {
	if ctx.if_stack.len > 0 {
		fr := ctx.if_top()
		if fr.degraded {
			ctx.emit('    jmp ${fr.end}')
			ctx.emit('${fr.pending}:')
			ctx.if_set(IfFrame{
				id:       fr.id
				tag:      fr.tag
				end:      fr.end
				pending:  ''
				clause:   fr.clause
				degraded: true
			})
			return
		}
	}
	ctx.emit('    .else')
}

fn (mut ctx GenCtx) stmt_endif() {
	if ctx.if_stack.len > 0 {
		fr := ctx.if_top()
		ctx.if_pop()
		if fr.degraded {
			// 真分支执行完会自然落到"条件为假"标签，再到 end；
			// 切换 elseif/else 时的 jmp end 已在 stmt_elseif / stmt_else 里发过，
			// 这里只补标签，不再多发一条紧邻 end 的无意义 jmp。
			if fr.pending.len > 0 {
				ctx.emit('${fr.pending}:')
			}
			ctx.emit('${fr.end}:')
			return
		}
		ctx.emit('    .endif')
	}
}

// ---------- for 循环标签栈 ----------

fn (mut ctx GenCtx) loop_push(fr LoopFrame) {
	ctx.loop_stack << fr
}

fn (mut ctx GenCtx) loop_top() LoopFrame {
	return ctx.loop_stack[ctx.loop_stack.len - 1]
}

fn (mut ctx GenCtx) loop_pop() {
	ctx.loop_stack = ctx.loop_stack[..ctx.loop_stack.len - 1]
}

fn (mut ctx GenCtx) stmt_for(s Stmt) {
	id := ctx.loop_id
	ctx.loop_id = ctx.loop_id + 1
	tag := '__cone_for_${ctx.fname}_${id}'
	end_lbl := hidden_name('${tag}_end', ctx.st.globals)
	// .while 的条件每轮重算，mem-mem 比较不能用"循环外提前 mov"中转（会读到过期值），
	// 所以循环里的 mem-mem 条件一律降级成显式标签，每轮重新求值。
	mut degraded := s.degraded
	if !degraded && !s.is_forever {
		mut conds := []int{}
		conds << s.cond_idx
		cp := ctx.plan_conds(conds, false)
		if !cp.ok {
			degraded = true
		}
	}
	if degraded {
		cond_lbl := hidden_name('${tag}_cond', ctx.st.globals)
		body_lbl := hidden_name('${tag}_body', ctx.st.globals)
		ctx.loop_push(LoopFrame{
			id:       id
			tag:      tag
			cond_lbl: cond_lbl
			body_lbl: body_lbl
			end_lbl:  end_lbl
			degraded: true
			forever:  s.is_forever
		})
		if s.is_forever {
			ctx.emit('${body_lbl}:')
		} else {
			ctx.emit('${cond_lbl}:')
			ctx.emit_cond_branch(s.cond_idx, end_lbl, s.cond_signed)
		}
		return
	}
	ctx.loop_push(LoopFrame{
		id:       id
		tag:      tag
		cond_lbl: ''
		body_lbl: ''
		end_lbl:  end_lbl
		degraded: false
		forever:  s.is_forever
	})
	if s.is_forever {
		ctx.emit('    .while 1')
	} else {
		ctx.emit('    .while ${ctx.render_cond(s.cond_idx)}')
	}
}

fn (mut ctx GenCtx) stmt_endfor() {
	if ctx.loop_stack.len == 0 {
		return
	}
	fr := ctx.loop_top()
	ctx.loop_pop()
	if fr.degraded {
		mut back := '    jmp ${fr.cond_lbl}'
		if fr.forever {
			back = '    jmp ${fr.body_lbl}'
		}
		// 循环体以 break / continue 收尾时，最后一条已经是 jmp，回边不可达，
		// 不再多发一条紧邻的重复 jmp。
		mut skip_back := false
		if ctx.lines.len > 0 {
			last := ctx.lines[ctx.lines.len - 1]
			if last == back {
				skip_back = true
			}
			if last == '    jmp ${fr.end_lbl}' {
				skip_back = true
			}
		}
		if !skip_back {
			ctx.emit(back)
		}
		ctx.emit('${fr.end_lbl}:')
		return
	}
	ctx.emit('    .endw')
}

fn (mut ctx GenCtx) stmt_break() {
	if ctx.loop_stack.len > 0 {
		fr := ctx.loop_top()
		if fr.degraded {
			ctx.emit('    jmp ${fr.end_lbl}')
			return
		}
	}
	ctx.emit('    .break')
}

fn (mut ctx GenCtx) stmt_continue() {
	if ctx.loop_stack.len > 0 {
		fr := ctx.loop_top()
		if fr.degraded {
			if fr.forever {
				ctx.emit('    jmp ${fr.body_lbl}')
			} else {
				ctx.emit('    jmp ${fr.cond_lbl}')
			}
			return
		}
	}
	ctx.emit('    .continue')
}

// ---------- cone 0.5：match / case / default ----------

// line_starts_with: 手写前缀判断，避免依赖 V 0.5.1 的字符串方法集。
fn line_starts_with(s string, prefix string) bool {
	if s.len < prefix.len {
		return false
	}
	mut i := 0
	for i < prefix.len {
		if s[i] != prefix[i] {
			return false
		}
		i = i + 1
	}
	return true
}

// cone 0.6 fix1：case 值可以是任意表达式。
// case_simple_text 返回能直接写进 `cmp reg, X` 的操作数（空串 = 需要先求值）；
// 小尺寸 byte/word 操作数不能和 32 位寄存器直接比较，改走求值路径做 movzx。
fn (mut ctx GenCtx) case_simple_text(idx int) string {
	fr := try_fold(ctx.prog, idx)
	if fr.ok { return '${fr.value}' }
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_num {
		if e.text in ctx.float_labels {
			return 'dword ptr [' + float_label_of(e.text, ctx.float_labels) + ']'
		}
		// cone 0.9preview：$ 等非浮点数值文本原样透传给 MASM（当前地址由汇编器替换）
		return e.text
	}
	if e.kind == ExprKind.expr_ident {
		if !e.is_reg && !e.is_win_sym && symbol_size(ctx.st, ctx.fname, e.text) < 4 { return '' }
		return resolve_name(ctx.st, ctx.fname, e.text)
	}
	if e.kind == ExprKind.expr_member {
		if ctx.member_bytes(idx) < 4 { return '' }
		return ctx.member_text(idx)
	}
	if e.kind == ExprKind.expr_deref {
		if deref_size_bytes(e.ptr_size) < 4 { return '' }
		return deref_ptr_text(e.ptr_size) + ' [' + ctx.addr_text(e.a) + ']'
	}
	if e.kind == ExprKind.expr_str && e.is_char_const {
		return 'offset ' + char_label_of(e.text, ctx.char_labels)
	}
	if e.kind == ExprKind.expr_addr {
		nm := addr_target(ctx.prog, idx)
		if is_stack_name(ctx.st, ctx.fname, nm) { return 'addr ' + ctx.struct_label_or_name(nm) }
		return 'offset ' + ctx.struct_label_or_name(nm)
	}
	c := masm_const(ctx.prog, ctx.st, ctx.fname, idx)
	if c.len > 0 { return c }
	return ''
}

fn (mut ctx GenCtx) case_is_simple(idx int) bool {
	return ctx.case_simple_text(idx).len > 0
}

fn (mut ctx GenCtx) emit_case_eval(idx int) {
	e := ctx.prog.exprs[idx]
	if e.kind == ExprKind.expr_bin {
		if is_cmp_text(e.text) || e.text == '&&' || e.text == '||' {
			ctx.emit_cond_eval_ex(idx, false)
			return
		}
	}
	ctx.emit_load(idx, 'eax')
}

// ---------- cone 0.7：Windows x86 栈式 SEH ----------
// 32 位 Windows 的异常处理是「栈基 / 帧式」：fs:[0] 指向 EXCEPTION_REGISTRATION 链。
// cone 为每个 try 在栈上装一个扩展帧 [prev][handler][code]：
//   - handler 由系统回调，[esp+4]=EXCEPTION_RECORD*，[esp+8]=pFrame，[esp+12]=CONTEXT*
//   - 命中 ErrorType（或不带 ErrorType 的通配分支）时，把 ExceptionCode 存进本帧
//     的 code 槽，改写 CONTEXT.Eip = dispatch 标签、CONTEXT.Esp = pFrame，
//     返回 ExceptionContinueExecution(0)；系统恢复 context 后 CPU 直接跳到
//     dispatch，dispatch 卸载 SEH 帧、按 code 分派到对应 except body。
//   - 未命中时返回 ExceptionContinueSearch(1)，系统继续沿 SEH 链找外层 handler。
// x86 CONTEXT 布局：Eip = 184 (0B8h)，Esp = 196 (0C4h)。
// handler 用 `jmp __cone_seh_ret_stub` 而不是 `ret`：MASM 的 `PROC USES ebx esi edi`
// 会重写 PROC 内所有 `ret` 为带 pop 的 epilogue，破坏 SEH 回调栈；统一 stub 在
// 所有 ENDP 之外，绕开 epilogue 重写。
fn (mut ctx GenCtx) try_top() TryFrame {
	return ctx.try_stack[ctx.try_stack.len - 1]
}

fn (mut ctx GenCtx) try_set(fr TryFrame) {
	ctx.try_stack = ctx.try_stack[..ctx.try_stack.len - 1]
	ctx.try_stack << fr
}

fn (mut ctx GenCtx) try_pop() {
	ctx.try_stack = ctx.try_stack[..ctx.try_stack.len - 1]
}

// except_code_text: ErrorType 渲染成 MASM 汇编期常量表达式（数值 / equ / win.宏 / 位运算）。
fn (mut ctx GenCtx) except_code_text(idx int) string {
	return masm_const(ctx.prog, ctx.st, ctx.fname, idx)
}

// stmt_try: 前瞻收集整条 try 链的所有 except 错误码，发射安装帧。
fn (mut ctx GenCtx) stmt_try(s Stmt) {
	mut codes := []string{}
	mut has_any := false
	mut depth := 0
	mut j := ctx.body_pos + 1
	for j < ctx.body.len {
		k := ctx.body[j].kind
		if k == StmtKind.st_try {
			depth = depth + 1
		} else if k == StmtKind.st_endtry {
			if depth == 0 {
				break
			}
			depth = depth - 1
		} else if depth == 0 && k == StmtKind.st_except {
			ci := ctx.body[j].except_idx
			if ci < 0 {
				has_any = true
				codes << ''
			} else {
				mut t := ctx.except_code_text(ci)
				if t.len == 0 {
					t = '0' // analyzer 已校验是编译期常量，兜底防止空操作数
				}
				codes << t
			}
		}
		j = j + 1
	}
	tag := hidden_name('__cone_seh_${label_safe(ctx.fname)}_${s.try_id}', ctx.st.globals)
	ctx.emit('    ; ---- cone 0.7 SEH try #${s.try_id}: install EXCEPTION_REGISTRATION ----')
	ctx.emit('    push 0                                  ; 本帧 code 槽（cone 扩展，存 ExceptionCode）')
	ctx.emit('    push offset ${tag}_handler')
	ctx.emit('    push fs:[0]                             ; prev')
	ctx.emit('    mov fs:[0], esp                         ; pFrame = esp')
	ctx.try_stack << TryFrame{
		tag:       tag
		codes:     codes.clone()
		has_any:   has_any
		cur:       0
		dispatch:  false
		needs_ret: false
	}
}

// emit_seh_unwind: 正常路径卸载当前 SEH 帧。esp 仍指向帧首 [prev][handler][code]
// （cone 生成的语句栈平衡；asm{} 里手写 push 必须自行配平），用 push/pop edx
// 保护 edx，避免污染后续表达式求值；不再强制 mov esp, ...，以免破坏 MASM 的
// local 栈帧。
fn (mut ctx GenCtx) emit_seh_unwind() {
	ctx.emit('    push edx')
	ctx.emit('    mov edx, [esp+4]                   ; prev = [pFrame]')
	ctx.emit('    mov fs:[0], edx                    ; 卸载当前 SEH 帧')
	ctx.emit('    pop edx')
	ctx.emit('    add esp, 12                        ; 弹出 [prev][handler][code]')
}

// emit_ret: cone 0.7 —— 在 try/except 体内时，return 不能直接 ret（会带着 SEH
// 帧返回，造成 fs:[0] 悬空）。改成跳到帧卸载之后的统一汇合点再 ret。
// eax / ax / al 里的返回值在 _normal / _dispatch 路径均保持不变。
fn (mut ctx GenCtx) emit_ret(suffix string) {
	if ctx.try_stack.len == 0 {
		ctx.emit('    ret' + suffix)
		return
	}
	mut fr := ctx.try_top()
	fr.needs_ret = true
	ctx.try_set(fr)
	ctx.emit('    jmp ${fr.tag}_ret               ; return 汇合点：先卸载 SEH 帧再返回')
}

// stmt_except: 第一个 except 发射「jmp normal + dispatch 跳转表」，之后每个 except
// 发射自己的标签；上一个 body 用 emit_match_close 补 jmp end（ret/jmp 收尾则省掉）。
fn (mut ctx GenCtx) stmt_except(s Stmt) {
	if ctx.try_stack.len == 0 {
		return
	}
	mut fr := ctx.try_top()
	if !fr.dispatch {
		fr.dispatch = true
		// try body 以 return / jmp / ExitProcess 收尾时这条 jmp 不可达，省掉。
		mut need_jmp_normal := true
		if ctx.lines.len > 0 {
			last := ctx.lines[ctx.lines.len - 1]
			if line_starts_with(last, '    jmp ') {
				need_jmp_normal = false
			}
			if line_starts_with(last, '    ret') {
				need_jmp_normal = false
			}
			if line_starts_with(last, '    invoke ExitProcess') {
				need_jmp_normal = false
			}
			if line_starts_with(last, '    call ExitProcess') {
				need_jmp_normal = false
			}
		}
		if need_jmp_normal {
			ctx.emit('    jmp ${fr.tag}_normal                ; 正常路径：跳过异常处理区')
		}
		ctx.emit('${fr.tag}_dispatch:                       ; 由 handler 改 CONTEXT.Eip 跳入，esp = pFrame')
		ctx.emit('    mov eax, [esp+8]                   ; 取出本帧存的 ExceptionCode（卸载前读）')
		ctx.emit('    mov fuck, eax                      ; cone 0.7：捕获异常时把错误码写入保留变量 fuck')
		ctx.emit_seh_unwind()
		mut i := 0
		for i < fr.codes.len {
			if fr.codes[i].len > 0 {
				ctx.emit('    cmp eax, ${fr.codes[i]}')
				ctx.emit('    je ${fr.tag}_e${i}')
			}
			i = i + 1
		}
		if fr.has_any {
			ai := fr.codes.len - 1
			ctx.emit('    jmp ${fr.tag}_e${ai}              ; 通配 except{}（必须在最后）')
		} else {
			ctx.emit('    jmp ${fr.tag}_end                ; handler 已保证命中，兜底')
		}
	}
	if fr.cur > 0 {
		ctx.emit_match_close(fr.tag + '_end')
	}
	ctx.emit('${fr.tag}_e${fr.cur}:')
	fr.cur = fr.cur + 1
	ctx.try_set(fr)
}

// stmt_endtry: 发射私有 handler、正常卸载路径与汇合标签。
fn (mut ctx GenCtx) stmt_endtry(s Stmt) {
	if ctx.try_stack.len == 0 {
		return
	}
	fr := ctx.try_top()
	if fr.cur > 0 {
		ctx.emit_match_close(fr.tag + '_end')
	}
	ctx.emit('${fr.tag}_handler:                         ; Windows x86 SEH 回调（cdecl，系统在栈上放 4 个参数）')
	ctx.emit('    mov eax, [esp+4]                   ; EXCEPTION_RECORD*')
	ctx.emit('    mov ecx, [eax]                     ; EXCEPTION_RECORD.ExceptionCode')
	mut i := 0
	for i < fr.codes.len {
		if fr.codes[i].len > 0 {
			ctx.emit('    cmp ecx, ${fr.codes[i]}')
			ctx.emit('    je ${fr.tag}_match')
		}
		i = i + 1
	}
	if fr.has_any {
		ctx.emit('    jmp ${fr.tag}_match                ; 不带 ErrorType：匹配所有错误码')
	} else {
		ctx.emit('    mov eax, 1                         ; ExceptionContinueSearch = 1（交给外层 / 系统）')
		ctx.emit('    jmp __cone_seh_ret_stub')
	}
	ctx.emit('${fr.tag}_match:')
	ctx.emit('    mov edx, [esp+8]                   ; pFrame')
	ctx.emit('    mov [edx+8], ecx                   ; 把 ExceptionCode 存进本帧 code 槽')
	ctx.emit('    mov eax, [esp+12]                  ; CONTEXT*')
	ctx.emit('    mov dword ptr [eax+184], offset ${fr.tag}_dispatch   ; CONTEXT.Eip = 0B8h')
	ctx.emit('    mov dword ptr [eax+196], edx       ; CONTEXT.Esp = 0C4h = pFrame（unwind）')
	ctx.emit('    xor eax, eax                       ; ExceptionContinueExecution = 0')
	ctx.emit('    jmp __cone_seh_ret_stub')
	ctx.emit('${fr.tag}_normal:                         ; try body 正常结束')
	ctx.emit_seh_unwind()
	ctx.emit('    jmp ${fr.tag}_end')
	if fr.needs_ret {
		ctx.emit('${fr.tag}_ret:                            ; try/except 体内 return 的汇合点')
		ctx.emit_seh_unwind()
		ctx.emit('    ret')
	}
	ctx.emit('${fr.tag}_end:')
	ctx.try_pop()
}

fn (mut ctx GenCtx) match_push(fr MatchFrame) {
	ctx.match_stack << fr
}

fn (mut ctx GenCtx) match_top() MatchFrame {
	return ctx.match_stack[ctx.match_stack.len - 1]
}

fn (mut ctx GenCtx) match_set(fr MatchFrame) {
	ctx.match_stack = ctx.match_stack[..ctx.match_stack.len - 1]
	ctx.match_stack << fr
}

fn (mut ctx GenCtx) match_pop() {
	ctx.match_stack = ctx.match_stack[..ctx.match_stack.len - 1]
}

// emit_match_close: 关闭上一个分支，补一条 jmp end（V match 无 fallthrough）。
// 分支已经以 ret / jmp / ExitProcess 收尾时这条 jmp 不可达，直接省掉。
fn (mut ctx GenCtx) emit_match_close(end string) {
	if ctx.lines.len > 0 {
		last := ctx.lines[ctx.lines.len - 1]
		mut unreachable := line_starts_with(last, '    ret') || line_starts_with(last, '    jmp ')
		if line_starts_with(last, '    invoke ExitProcess') || line_starts_with(last, '    call ExitProcess') {
			unreachable = true
		}
		if unreachable {
			return
		}
	}
	ctx.emit('    jmp ${end}')
}

// stmt_match: 判别值求进 eax，一次性发出 cmp/je 跳转表 + 兜底跳转。
// case 值通过前瞻 body 收集（深度计数跳过嵌套 match），这样每个 case
// 标签在进入分支体之前就已确定。
fn (mut ctx GenCtx) stmt_match(s Stmt) {
	mut vals := []int{}
	mut has_default := false
	mut depth := 0
	mut j := ctx.body_pos + 1
	for j < ctx.body.len {
		k := ctx.body[j].kind
		if k == StmtKind.st_match {
			depth = depth + 1
		} else if k == StmtKind.st_endmatch {
			if depth == 0 {
				break
			}
			depth = depth - 1
		} else if depth == 0 && k == StmtKind.st_case {
			vals << ctx.body[j].case_idx
		} else if depth == 0 && k == StmtKind.st_default {
			has_default = true
		}
		j = j + 1
	}
	id := ctx.match_id
	ctx.match_id = ctx.match_id + 1
	mut tag := '__cone_match_${ctx.fname}_${id}'
	tag = hidden_name(tag, ctx.st.globals)
	end := tag + '_end'
	def := tag + '_default'
	mut cases := []string{}
	ctx.expr_eax(s.cond_idx)
	mut need_eval := false
	for v in vals {
		if !ctx.case_is_simple(v) { need_eval = true }
	}
	if !need_eval {
		// 全部 case 都是直接操作数：保持 0.6 的最小指令形态，零中转
		mut i := 0
		for i < vals.len {
			lbl := tag + '_c${i}'
			cases << lbl
			ctx.emit('    cmp eax, ${ctx.case_simple_text(vals[i])}')
			ctx.emit('    je ${lbl}')
			i = i + 1
		}
	} else {
		// 含需要求值的 case：从空闲池挑 S 保存判别值，求值前后 push/pop S；
		// 池空则退化为栈中转（push eax / cmp [esp],eax / pop eax），不覆盖任何寄存器。
		pool := ctx.free_scratch_pool()
		mut sr := ''
		for r in ['edi', 'esi', 'ebx', 'ecx', 'edx'] {
			if sr.len == 0 {
				for q in pool {
					if eq_ci(q, r) { sr = r }
				}
			}
		}
		if sr.len > 0 { ctx.emit('    mov ${sr}, eax') }
		mut i := 0
		for i < vals.len {
			lbl := tag + '_c${i}'
			cases << lbl
			if ctx.case_is_simple(vals[i]) {
				mut cr := 'eax'
				if sr.len > 0 { cr = sr }
				ctx.emit('    cmp ${cr}, ${ctx.case_simple_text(vals[i])}')
				ctx.emit('    je ${lbl}')
			} else {
				if sr.len > 0 {
					ctx.emit('    push ${sr}')
					ctx.emit_case_eval(vals[i])
					ctx.emit('    pop ${sr}')
					ctx.emit('    cmp ${sr}, eax')
				} else {
					ctx.emit('    push eax')
					ctx.emit_case_eval(vals[i])
					ctx.emit('    cmp dword ptr [esp], eax')
					ctx.emit('    pop eax')
				}
				ctx.emit('    je ${lbl}')
			}
			i = i + 1
		}
	}
	if has_default {
		ctx.emit('    jmp ${def}')
	} else {
		ctx.emit('    jmp ${end}')
	}
	ctx.match_push(MatchFrame{
		tag:     tag
		end:     end
		def:     def
		cases:   cases
		cur:     0
		started: false
	})
}

fn (mut ctx GenCtx) stmt_case(s Stmt) {
	if ctx.match_stack.len == 0 {
		return
	}
	mut fr := ctx.match_top()
	if fr.started {
		ctx.emit_match_close(fr.end)
	}
	if fr.cur < fr.cases.len {
		ctx.emit('${fr.cases[fr.cur]}:')
		fr.cur = fr.cur + 1
	}
	fr.started = true
	ctx.match_set(fr)
}

fn (mut ctx GenCtx) stmt_default(s Stmt) {
	if ctx.match_stack.len == 0 {
		return
	}
	mut fr := ctx.match_top()
	if fr.started {
		ctx.emit_match_close(fr.end)
	}
	ctx.emit('${fr.def}:')
	fr.started = true
	ctx.match_set(fr)
}

fn (mut ctx GenCtx) stmt_endmatch(s Stmt) {
	if ctx.match_stack.len == 0 {
		return
	}
	fr := ctx.match_top()
	if fr.started {
		ctx.emit_match_close(fr.end)
		// 最后一个分支的 jmp end 紧跟 end: 是冗余，删掉它让输出更干净。
		if ctx.lines.len > 0 && ctx.lines[ctx.lines.len - 1] == '    jmp ${fr.end}' {
			ctx.lines = ctx.lines[..ctx.lines.len - 1]
		}
	}
	ctx.emit('${fr.end}:')
	ctx.match_pop()
}

// stmt_incdec: cone 0.6 fix1 的 ++ / -- 直接生成 inc / dec（支持 reg / 变量 / 成员 / []）。
fn (mut ctx GenCtx) stmt_incdec(s Stmt, inc bool) {
	idx := s.target_idx
	e := ctx.prog.exprs[idx]
	mut text := ''
	if e.kind == ExprKind.expr_ident {
		if e.is_reg {
			text = e.text
		} else {
			nm := resolve_name(ctx.st, ctx.fname, e.text)
			sz := symbol_size(ctx.st, ctx.fname, e.text)
			if sz == 1 || sz == 2 {
				text = size_ptr(sz) + ' ' + nm
			} else {
				text = nm
			}
		}
	} else if e.kind == ExprKind.expr_member {
		t := ctx.member_text(idx)
		sz := ctx.member_bytes(idx)
		if sz == 1 || sz == 2 {
			text = size_ptr(sz) + ' ' + t
		} else {
			text = t
		}
	} else {
		text = deref_ptr_text(e.ptr_size) + ' [' + ctx.addr_text(e.a) + ']'
	}
	if inc {
		ctx.emit('    inc ${text}')
	} else {
		ctx.emit('    dec ${text}')
	}
}

fn (mut ctx GenCtx) stmt(s Stmt, is_entry bool) {
	if s.kind == StmtKind.st_local {
		// cone 0.7：局部变量声明带初值时，在声明所在位置发射赋值（数组恒无初值）。
		mut li := 0
		for li < s.local_names.len {
			mut ii := -1
			if li < s.local_inits.len {
				ii = s.local_inits[li]
			}
			if ii >= 0 {
				nm := resolve_name(ctx.st, ctx.fname, s.local_names[li])
				mut sz := symbol_size(ctx.st, ctx.fname, s.local_names[li])
				if sz == 0 {
					sz = 4
				}
				ie := ctx.prog.exprs[ii]
				mut tg2 := ''
				if ie.kind == ExprKind.expr_call {
					tg2 = call_target(ie.text)
				}
				if tg2.len > 0 && is_sret_fn(ctx.st, tg2) {
					mut pref2 := 'offset '
					if is_stack_name(ctx.st, ctx.fname, s.local_names[li]) {
						pref2 = 'addr '
					}
					ptr2 := pref2 + ctx.struct_label_or_name(s.local_names[li])
					ctx.call_with_sret(ii, ptr2)   // cone 0.9.2：直接传目标地址，无二次拷贝
				} else if tg2.len > 0 && ctx.st.func_ret_size[tg2] == 8 {
					ctx.call(ii)
					ctx.emit('    mov dword ptr ${nm}, eax')
					ctx.emit('    mov dword ptr ${nm}+4, edx    ; cone 0.9.2 coneABI：edx:eax 接收 8 字节标量返回值')
				} else {
					ctx.emit_assign(nm, false, sz, ii, -1, s.local_names[li])
				}
			}
			li = li + 1
		}
		return
	}
	if s.kind == StmtKind.st_inc || s.kind == StmtKind.st_dec {
		ctx.stmt_incdec(s, s.kind == StmtKind.st_inc)
		return
	}
	if s.kind == StmtKind.st_asm {
		if ctx.o1 {
			ctx.emit(o1_on)
		}
		ctx.emit_asm(s)
		if ctx.o1 {
			ctx.emit(o1_off)
		}
		return
	}
	if s.kind == StmtKind.st_asm64 {
		key := 'f${ctx.fname}:${ctx.body_pos}'
		if ctx.o1 {
			ctx.emit(o1_on)
		}
		if key in ctx.st.asm64_cache {
			for l in ctx.st.asm64_cache[key] {
				ctx.emit(l)
			}
		}
		if ctx.o1 {
			ctx.emit(o1_off)
		}
		return
	}
	// cone 0.7：Windows x86 栈式 SEH
	if s.kind == StmtKind.st_try {
		ctx.stmt_try(s)
		return
	}
	if s.kind == StmtKind.st_except {
		ctx.stmt_except(s)
		return
	}
	if s.kind == StmtKind.st_endtry {
		ctx.stmt_endtry(s)
		return
	}
	if s.kind == StmtKind.st_match {
		ctx.stmt_match(s)
		return
	}
	if s.kind == StmtKind.st_case {
		ctx.stmt_case(s)
		return
	}
	if s.kind == StmtKind.st_default {
		ctx.stmt_default(s)
		return
	}
	if s.kind == StmtKind.st_endmatch {
		ctx.stmt_endmatch(s)
		return
	}
	if s.kind == StmtKind.st_if {
		ctx.stmt_if(s)
		return
	}
	if s.kind == StmtKind.st_elseif {
		ctx.stmt_elseif(s)
		return
	}
	if s.kind == StmtKind.st_else {
		ctx.stmt_else()
		return
	}
	if s.kind == StmtKind.st_endif {
		ctx.stmt_endif()
		return
	}
	if s.kind == StmtKind.st_for {
		ctx.stmt_for(s)
		return
	}
	if s.kind == StmtKind.st_endfor {
		ctx.stmt_endfor()
		return
	}
	if s.kind == StmtKind.st_break {
		ctx.stmt_break()
		return
	}
	if s.kind == StmtKind.st_continue {
		ctx.stmt_continue()
		return
	}
	if s.kind == StmtKind.st_return {
		rhs_float := expr_is_float(ctx.prog, ctx.st, ctx.fname, s.ret_idx)
		if is_entry {
			if rhs_float {
				ctx.float_eax(s.ret_idx)
				ctx.emit('    sub esp, 4')
				ctx.emit('    fistp dword ptr [esp]')
				ctx.emit('    call ExitProcess    ; 浮点退出码转整数；ExitProcess 按 stdcall 清栈且不返回')
			} else if ret_is_direct(ctx.prog, ctx.st, ctx.fname, s.ret_idx) {
				ctx.emit('    invoke ExitProcess, ${ctx.render_arg(s.ret_idx)}')
			} else {
				ctx.expr_eax(s.ret_idx)
				ctx.emit('    invoke ExitProcess, eax')
			}
			return
		}
		// cone 0.9.2：return float(xxx) —— st(0) 返回 + 同步到 eax / edx:eax
		if rhs_float {
			ctx.float_eax(s.ret_idx)
			qword := expr_size(ctx.prog, ctx.st, ctx.fname, s.ret_idx) == 8
			if qword {
				ctx.emit('    sub esp, 8')
				ctx.emit('    fst qword ptr [esp]')
				ctx.emit('    pop eax')
				ctx.emit('    pop edx')
			} else {
				ctx.emit('    sub esp, 4')
				ctx.emit('    fst dword ptr [esp]')
				ctx.emit('    pop eax')
			}
			ctx.emit_ret('    ; cone 0.9.2 浮点返回：st(0) 同时同步到 eax / edx:eax（fst 不弹栈）')
			return
		}
		rt := ctx.st.func_ret_type[ctx.fname]
		ris := ctx.st.func_ret_is_struct[ctx.fname]
		rsz := ctx.st.func_ret_size[ctx.fname]
		re := ctx.prog.exprs[s.ret_idx]
		mut is_struct_inst := false
		if re.kind == ExprKind.expr_ident && !re.is_reg {
			sb := symbol_base_type(ctx.st, ctx.fname, re.text)
			is_struct_inst = sb in ctx.st.struct_size
		}
		// cone 0.9.2 coneABI：返回类型是结构体 -> 完整拷贝到第一个隐式参数
		// （调用者提供的接收指针）。rsz 是正确的结构体大小（align 含 padding）。
		if rt.len > 0 && ris {
			ctx.sret_copy_from(s.ret_idx, rsz, '__cone_sret_ptr')
			ctx.emit('    mov eax, __cone_sret_ptr    ; coneABI：同时把接收指针留在 eax')
			ctx.emit_ret('')
			return
		}
		// cone 0.9.2：返回类型是标量 —— 尺寸<rsz 警告并零扩展；匹配时完整返回 edx:eax
		if rt.len > 0 && !ris {
			mut sz0 := expr_size(ctx.prog, ctx.st, ctx.fname, s.ret_idx)
			if sz0 == 0 { sz0 = 4 }
			if rsz == 8 && sz0 >= 8 && re.kind == ExprKind.expr_ident && !re.is_reg {
				nm := resolve_name(ctx.st, ctx.fname, re.text)
				ctx.emit('    mov eax, dword ptr [${nm}]')
				ctx.emit('    mov edx, dword ptr [${nm}+4]    ; cone 0.9.2：8 字节值类型匹配，edx:eax 完整返回')
			} else {
				ctx.expr_eax(s.ret_idx)
				if rsz == 8 && sz0 < 8 {
					ctx.emit('    xor edx, edx    ; coneABI：零扩展到 edx:eax')
				}
			}
			ctx.emit_ret('')
			return
		}
		// 未声明返回类型、return 整个结构体实例：Windows x86 ABI
		if is_struct_inst {
			sb := symbol_base_type(ctx.st, ctx.fname, re.text)
			ssz := ctx.st.struct_size[sb]
			nm := resolve_name(ctx.st, ctx.fname, re.text)
			if ssz == 1 {
				ctx.emit('    movzx eax, byte ptr [${nm}]    ; ${sb} 1 字节：eax 返回')
			} else if ssz == 2 {
				ctx.emit('    movzx eax, word ptr [${nm}]    ; ${sb} 2 字节：eax 返回')
			} else if ssz == 3 {
				ctx.emit('    movzx eax, word ptr [${nm}]    ; ${sb} 3 字节：精确读，不多不少')
				ctx.emit('    movzx ecx, byte ptr [${nm}+2]')
				ctx.emit('    shl ecx, 16')
				ctx.emit('    or eax, ecx')
			} else if ssz == 4 {
				ctx.emit('    mov eax, dword ptr [${nm}]    ; ${sb} 4 字节：eax 返回')
			} else if ssz <= 8 {
				ctx.emit('    mov eax, dword ptr [${nm}]    ; ${sb} ${ssz} 字节：edx:eax 返回')
				hi := ssz - 4
				if hi == 1 {
					ctx.emit('    movzx edx, byte ptr [${nm}+4]')
				} else if hi == 2 {
					ctx.emit('    movzx edx, word ptr [${nm}+4]')
				} else if hi == 3 {
					ctx.emit('    movzx edx, word ptr [${nm}+4]')
					ctx.emit('    movzx ecx, byte ptr [${nm}+6]')
					ctx.emit('    shl ecx, 16')
					ctx.emit('    or edx, ecx')
				} else {
					ctx.emit('    mov edx, dword ptr [${nm}+4]')
				}
			} else {
				ctx.emit('    ; cone 0.9.2：${sb} ${ssz} 字节 >8，未声明返回类型：按 Windows x86 ABI 返回结构体指针（调用侧接收交给编程者）')
				ctx.emit('    lea eax, [${nm}]    ; 返回结构体指针')
			}
			ctx.emit_ret('')
			return
		}
		mut sz := expr_size(ctx.prog, ctx.st, ctx.fname, s.ret_idx)
		if sz == 0 {
			sz = 4
		}
		if sz == 1 || sz == 2 {
			reg := reg_name(sz)
			if is_simple_load(ctx.prog, s.ret_idx) {
				ctx.emit_small_load(s.ret_idx, reg, sz)
			} else {
				ctx.expr_eax(s.ret_idx) // al/ax 即 eax 的低位
			}
			ctx.emit_ret('    ; 返回值在 ${reg}')
		} else {
			ctx.expr_eax(s.ret_idx)
			ctx.emit_ret('')
		}
		return
	}
	if s.kind == StmtKind.st_assign {
		if s.lhs_idx >= 0 {
			if ctx.prog.exprs[s.lhs_idx].kind == ExprKind.expr_member {
				ctx.assign_member(s)
			} else {
				ctx.assign_deref(s)
			}
			return
		}
		// cone 0.3：寄存器左值没有 cone 类型，直接走统一 mov 发射器
		if is_reg_name(s.lhs) {
			ctx.emit_assign(s.lhs, true, reg_size(s.lhs), s.rhs_idx, -1, s.lhs)
			return
		}
		dst := resolve_name(ctx.st, ctx.fname, s.lhs)
		// cone 0.9.2：stname=funcname() —— 只传入 stname 的指针作隐式首参，
		// 被调方把要返回的结构体完整拷贝到该指针指向的调用者内存，无中转缓冲。
		re := ctx.prog.exprs[s.rhs_idx]
		mut tg := ''
		if re.kind == ExprKind.expr_call {
			tg = call_target(re.text)
		}
		if tg.len > 0 && is_sret_fn(ctx.st, tg) {
			mut pref := 'offset '
			if is_stack_name(ctx.st, ctx.fname, s.lhs) {
				pref = 'addr '
			}
			ptr := pref + ctx.struct_label_or_name(s.lhs)
			ctx.call_with_sret(s.rhs_idx, ptr)
			return
		}
		if tg.len > 0 && ctx.st.func_ret_size[tg] == 8 {
			ctx.call(s.rhs_idx)
			ctx.emit('    mov dword ptr ${dst}, eax')
			ctx.emit('    mov dword ptr ${dst}+4, edx    ; cone 0.9.2 coneABI：edx:eax 接收 8 字节标量返回值')
			return
		}
		dst_base := symbol_base_type(ctx.st, ctx.fname, s.lhs)
		dst_float := is_float_base(dst_base)
		rhs_float := expr_is_float(ctx.prog, ctx.st, ctx.fname, s.rhs_idx)
		if dst_float {
			// 目标 f32/f64：右值有浮点 -> x87；右值无浮点 -> 走整数/原始位路径（不自动转换）
			if rhs_float {
				ctx.float_eax(s.rhs_idx)
				ctx.emit('    fstp ${dst}')
				return
			}
			ctx.assign_int(s)
			return
		}
		if rhs_float {
			ctx.float_eax(s.rhs_idx)
			if dst_base == 'long' {
				ctx.emit('    fistp qword ptr ${dst}')
			} else {
				ctx.emit('    fistp dword ptr ${dst}')
			}
			return
		}
		ctx.assign_int(s)
		return
	}
	if s.kind == StmtKind.st_call {
		ctx.call(s.call_idx)
	}
}

// ---------- 主生成 ----------

// ---------- cone 0.6：按源码位置发射顶层声明 ----------
// 把 import/include / STRUCT / typedef / equ / PROTO / 数据 / 代码 / 顶层 asm
// 统一收进带 (phase, order) 的发射单元：phase 保留 cone 既有的分组约束
// （STRUCT 必须先于 PROTO、段按 .const/.data/.data?/.code 聚合），order 是
// 顶层声明的真实源码顺序。顶层 asm 按自己 order 插进前一声明所在的 phase，
// 因此不再一律置顶到 include 之后。
struct EmitUnit {
	phase    int
	order    int
	section  int // -1 头部（无段伪指令）；0=.const 1=.data 2=.data? 3=.code
	lines    []string
	text     string // asm 正文（含换行，整段作为一行进 out）
	is_asm   bool
	switches bool // asm 正文里是否写了段切换（决定后续是否重新声明段）
}

struct OrderPhase {
	order int
	phase int
}

fn sort_units(src []EmitUnit) []EmitUnit {
	mut a := []EmitUnit{}
	for x in src {
		a << x
	}
	mut i := 1
	for i < a.len {
		mut j := i
		for j > 0 {
			prev := a[j - 1]
			cur := a[j]
			mut do_swap := cur.phase < prev.phase
			if cur.phase == prev.phase && cur.order < prev.order {
				do_swap = true
			}
			if !do_swap {
				break
			}
			tmp := a[j]
			a[j] = a[j - 1]
			a[j - 1] = tmp
			j = j - 1
		}
		i = i + 1
	}
	return a
}

fn emit_section_name(sec int) string {
	if sec == 0 {
		return '.const'
	}
	if sec == 1 {
		return '.data'
	}
	if sec == 2 {
		return '.data?'
	}
	return '.code'
}

fn ci_starts_with(s string, p string) bool {
	if s.len < p.len {
		return false
	}
	mut i := 0
	for i < p.len {
		mut a := int(s[i])
		mut b := int(p[i])
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

// asm_switches_segment: 顶层 asm 正文里出现 .code/.data/.const/.model/segment
// 这类段伪指令时，后面的 cone 声明必须重新写一次段伪指令。
fn asm_switches_segment(text string) bool {
	mut i := 0
	for i < text.len {
		mut j := i
		for j < text.len && text[j] != 10 {
			j = j + 1
		}
		mut k := i
		for k < j && (text[k] == 32 || text[k] == 9) {
			k = k + 1
		}
		line := text[k..j]
		mut sw := ci_starts_with(line, '.code') || ci_starts_with(line, '.data')
		if ci_starts_with(line, '.const') || ci_starts_with(line, '.model') {
			sw = true
		}
		if ci_starts_with(line, '.fardata') || ci_starts_with(line, 'segment') {
			sw = true
		}
		if sw {
			return true
		}
		i = j + 1
	}
	return false
}

fn section_index(sec Section) int {
	if sec == Section.sec_const {
		return 0
	}
	if sec == Section.sec_data_uninit {
		return 2
	}
	return 1
}

// cone 0.8preview：include / includelib 的路径策略。
//   默认（无 -s）：全部指向 cone.exe 所在目录的 masm32\include / masm32\lib，
//                  这样不带 /I 的默认 ml.exe / link.exe 也能找到 SDK 文件；
//                  0.8preview2：路径不加引号 —— MASM32 的 include / includelib
//                  指令不接受引号包裹的文件名，加了 ml 会直接报错；
//   -s：           全部用短名（xxx.inc / xxx.lib），交给 MASM 的 /I 或当前目录解析。
// 固定头与源码里的 `include xxx` / `import xxx.dll` 都走这两个函数，口径一致。
fn include_line(opts GenOpts, file string) string {
	if opts.short_include {
		return 'include ${file}'
	}
	return 'include ${opts.cone_dir}\\masm32\\include\\${file}'
}

fn lib_line(opts GenOpts, file string) string {
	if opts.short_include {
		return 'includelib ${file}'
	}
	return 'includelib ${opts.cone_dir}\\masm32\\lib\\${file}'
}

// cone 0.9.3：去掉生成的 .asm 里所有不必要的注释，只保留头部版本信息注释。
// 字符串字面量里的分号不当注释，避免破坏 db 'a;b',0 这类数据行。
fn strip_asm_comments(asm_text string) string {
	mut out := []string{}
	for line in asm_text.split('\n') {
		if line.contains('generated MASM32 assembly') {
			out << line
			continue
		}
		mut q := u8(0)
		mut cut := -1
		for i := 0; i < line.len; i++ {
			c := line[i]
			if q != 0 {
				if c == q {
					q = 0
				}
				continue
			}
			if c == 39 || c == 34 {
				q = c
				continue
			}
			if c == 59 {
				cut = i
				break
			}
		}
		mut l := line
		if cut >= 0 {
			l = line[..cut]
			for l.len > 0 && (l[l.len - 1] == 32 || l[l.len - 1] == 9) {
				l = l[..l.len - 1]
			}
			if l.trim_space().len == 0 {
				continue
			}
		}
		out << l
	}
	mut res := []string{}
	mut blank := false
	for l in out {
		if l.trim_space().len == 0 {
			if blank {
				continue
			}
			blank = true
		} else {
			blank = false
		}
		res << l
	}
	for res.len > 0 && res.last().trim_space().len == 0 {
		res.pop()
	}
	return res.join('\n') + '\n'
}

fn generate(prog Program, st SymTab, opts GenOpts) string {
	mut out := []string{}

	float_texts := collect_float_literals(prog, st)
	float_labels := make_float_labels(float_texts, st.globals)
	char_texts := collect_char_consts(prog)
	char_labels := make_char_labels(char_texts, st.globals)
	struct_consts := collect_struct_consts(prog)
	stt_labels := make_struct_labels(struct_consts, st.globals)
	itmp := hidden_name('__cone_itmp', st.globals)

	out << '; ============================================================'
	out << '; cone 0.9.p - generated MASM32 assembly'
	out << '; SEH try/except (stack-based, fs:[0]) / cone-side equ immediate folding'
	out << '; pipeline: lexer -> imports -> parser -> analyzer -> codegen -> cli'
	out << '; ============================================================'
	out << '.586'
	out << '.model flat, stdcall'
	out << 'option casemap :none'
	out << 'option scoped    ; cone 0.83：proc 内单冒号标号为局部，全局标号用双冒号'
	out << 'assume fs:nothing    ; cone 0.7：SEH 帧链 fs:[0] 需要 fs 段可寻址'
	out << ''
	out << include_line(opts, 'windows.inc')
	out << include_line(opts, 'kernel32.inc')
	out << lib_line(opts, 'kernel32.lib')
	out << include_line(opts, 'user32.inc')
	out << lib_line(opts, 'user32.lib')

	mut units := []EmitUnit{}
	mut seen_lines := map[string]bool{}
	// cone 0.83：in_seg 函数的完整生成行暂存，供 seg 段按源码顺序取用。
	mut func_lines := map[string][]string{}
	// cone 0.8prelease：固定头已经在 out 里，登记进去重集合。
	// 这样源码写 `include windows.inc` / `include kernel32.lib` 时不会重复生成一行。
	seen_lines[include_line(opts, 'windows.inc')] = true
	seen_lines[include_line(opts, 'kernel32.inc')] = true
	seen_lines[lib_line(opts, 'kernel32.lib')] = true
	seen_lines[include_line(opts, 'user32.inc')] = true
	seen_lines[lib_line(opts, 'user32.lib')] = true

	// phase 0：include X（按源码 order，与旧版一致的去重）。
	// cone 0.8prelease：import xxx.dll 已移除，prog.imports 恒为空；下面这段保留兜底。
	for imp in prog.imports {
		if imp.kind != ImportKind.ik_dll {
			continue
		}
		line := lib_line(opts, imp.lib_name)
		mut dup := false
		if line in seen_lines {
			dup = true
		}
		if !dup {
			seen_lines[line] = true
			mut ls := []string{}
			ls << line
			units << EmitUnit{phase: 0, order: imp.order, section: -1, lines: ls, text: '', is_asm: false, switches: false}
		}
	}
	for inc in prog.includes {
		mut ls := []string{}
		// cone 0.8prelease：inc_file / lib_file 可为空（include xxx.lib / include xxx.inc）。
		if inc.inc_file.len > 0 {
			l1 := include_line(opts, inc.inc_file)
			mut d1 := false
			if l1 in seen_lines {
				d1 = true
			}
			if !d1 {
				seen_lines[l1] = true
				ls << l1
			}
		}
		if inc.lib_file.len > 0 {
			l2 := lib_line(opts, inc.lib_file)
			mut d2 := false
			if l2 in seen_lines {
				d2 = true
			}
			if !d2 {
				seen_lines[l2] = true
				ls << l2
			}
		}
		if ls.len > 0 {
			units << EmitUnit{phase: 0, order: inc.order, section: -1, lines: ls, text: '', is_asm: false, switches: false}
		}
	}

	// phase 1：STRUCT / ENDS（拓扑序，整体锚在第一个 struct 的 order 上）
	slines := render_struct_defs(prog, st)
	if slines.len > 0 {
		mut so := 2147483647
		for sd in prog.structs {
			if sd.order < so {
				so = sd.order
			}
		}
		mut ls := []string{}
		for sl in slines {
			ls << sl
		}
		units << EmitUnit{phase: 1, order: so, section: -1, lines: ls, text: '', is_asm: false, switches: false}
	}

	// cone 0.83：defined 宏函数（无 exitm）。用 is_asm 单元整段插入头部区，
	// phase 1 保证它在所有 PROC / 调用之前；asm_resolve_text 处理 %名字。
	for m in prog.macros {
		mut hd := m.name + ' macro'
		if m.params.len > 0 {
			mut ps := []string{}
			for pm in m.params {
				if pm.restraint.len > 0 {
					ps << pm.name + ':' + pm.restraint
				} else {
					ps << pm.name
				}
			}
			hd = hd + ' ' + ps.join(', ')
		}
		body := asm_resolve_text(st, '', trim_asm_text(m.body))
		mut ind := []string{}
		mut bs := 0
		mut bi := 0
		for bi < body.len {
			if body[bi] == 10 {
				ind << '    ' + trim_ws(body[bs..bi])
				bs = bi + 1
			}
			bi = bi + 1
		}
		if bs < body.len {
			ind << '    ' + trim_ws(body[bs..])
		}
		mut txt := hd + '\n'
		for l in ind {
			txt = txt + l + '\n'
		}
		txt = txt + m.name + ' endm\n'
		units << EmitUnit{phase: 1, order: m.order, section: -1, lines: []string{}, text: txt, is_asm: true, switches: false}
	}

	// phase 2：typedef
	for td in prog.typedefs {
		base := st.typedef_base[td.name]
		mut ls := []string{}
		ls << '${td.name} typedef ${typedef_base_masm(base)}'
		units << EmitUnit{phase: 2, order: td.order, section: -1, lines: ls, text: '', is_asm: false, switches: false}
	}

	// phase 3：equ（cone 0.7：已在 cone 侧展开成立即数的数值 equ 不再输出 equ 行）
	for eq in prog.equs {
		if eq.is_folded {
			continue
		}
		rhs := equ_masm_text(prog, eq)
		mut ls := []string{}
		if eq.is_raw {
			ls << '${eq.name} equ <${rhs}>'
		} else {
			ls << '${eq.name} equ ${rhs}'
		}
		units << EmitUnit{phase: 3, order: eq.order, section: -1, lines: ls, text: '', is_asm: false, switches: false}
	}

	// phase 4：PROTO
	for pr in prog.protos {
		if pr.is_external {
			continue // cone 0.9.3：efunc 不生成 MASM PROTO（由 .inc 提供）
		}
		mut head := []string{}
		head << pr.name
		head << 'proto'
		cs := conv_str(pr.conv)
		if cs.len > 0 {
			head << cs
		}
		if pr.is_export {
			head << 'export'
		}
		mut ps := []string{}
		if is_sret_fn(st, pr.name) {
			ps << '__cone_sret_ptr:DWORD'
		}
		for pm in pr.params {
			if pm.typ_name == 'vararg' { continue } // cone 0.9.p：x86 PROTO 不发射该标记
			pt := proto_param_type(st, pm.typ_name)
			if pm.name.len > 0 {
				ps << '${pm.name}:${pt}'
			} else {
				ps << ':${pt}'
			}
		}
		if ps.len > 0 {
			head << ps.join(', ')
		}
		mut ls := []string{}
		ls << head.join(' ')
		units << EmitUnit{phase: 4, order: pr.order, section: -1, lines: ls, text: '', is_asm: false, switches: false}
	}

	// phase 5/6/7：数据段条目（按 section 聚合，段内按 order）
	for d in prog.data {
		mut sec := 1
		if d.is_const {
			sec = 0
		}
		mut ls := []string{}
		ls << render_data_def(prog, d)
		units << EmitUnit{phase: 5 + sec, order: d.order, section: sec, lines: ls, text: '', is_asm: false, switches: false}
	}
	for v in prog.vars {
		// cone 0.83：seg 段内数据由 seg 单元按源码顺序生成，不进常规段。
		if v.in_seg.len > 0 {
			continue
		}
		sec := section_index(section_of(v))
		mut ls := []string{}
		ls << render_var(prog, st, v)
		units << EmitUnit{phase: 5 + sec, order: v.order, section: sec, lines: ls, text: '', is_asm: false, switches: false}
	}

	// 自动生成池条目：排在各自段的末尾
	mut oi := 1000000
	for t in char_texts {
		mut label := '__cone_str_missing'
		if t in char_labels {
			label = char_labels[t]
		}
		mut ls := []string{}
		ls << '${label} db ${t}    ; cone 字符常量（默认补 0，按内容去重）'
		units << EmitUnit{phase: 5, order: oi, section: 0, lines: ls, text: '', is_asm: false, switches: false}
		oi = oi + 1
	}
	for t in float_texts {
		mut label := '__cone_flt_missing'
		if t in float_labels {
			label = float_labels[t]
		}
		mut ls := []string{}
		ls << '${label} REAL4 ${t}'
		units << EmitUnit{phase: 5, order: oi, section: 0, lines: ls, text: '', is_asm: false, switches: false}
		oi = oi + 1
	}
	for c in struct_consts {
		mut ls := []string{}
		ls << render_struct_const(prog, c, st, stt_labels)
		units << EmitUnit{phase: 5, order: oi, section: 0, lines: ls, text: '', is_asm: false, switches: false}
		oi = oi + 1
	}
	// cone 0.7：fuck 是 .data? 段的第一个变量（order = -1 保证排在最前）。
	mut ls_fuck := []string{}
	ls_fuck << 'fuck dd ?    ; cone 0.7 保留变量：try/except 捕获异常时写入 ExceptionCode'
	units << EmitUnit{phase: 7, order: -1, section: 2, lines: ls_fuck, text: '', is_asm: false, switches: false}
	mut ls_itmp := []string{}
	ls_itmp << '${itmp} dd ?    ; cone 隐藏临时：整数<->浮点转换中转'
	units << EmitUnit{phase: 7, order: oi, section: 2, lines: ls_itmp, text: '', is_asm: false, switches: false}
	// cone 0.9.2：不再生成静态中转缓冲；接收内存由调用者提供。

	// phase 8：代码段（每个函数一个单元，末尾保留空行）
	for f in prog.funcs {
		mut ctx := GenCtx{
			prog:         prog
			st:           st
			fname:        f.name
			float_labels: float_labels
			char_labels:  char_labels
			stt_labels:   stt_labels
			itmp:         itmp
			o1:           opts.o1
			lines:        []string{}
			if_stack:     []IfFrame{}
			if_id:        0
			loop_stack:   []LoopFrame{}
			loop_id:      0
			body:         []Stmt{}
			body_pos:     0
			match_id:     0
			match_stack:  []MatchFrame{}
			try_stack:    []TryFrame{}
		}
		mut head := f.name + ' proc'
		cs := conv_str(f.conv)
		if cs.len > 0 {
			head = head + ' ' + cs
		}
		if f.is_export {
			head = head + ' export'
		}
		head = head + ' uses ebx esi edi'
		mut ps := []string{}
		if is_sret_fn(st, f.name) {
			ps << '__cone_sret_ptr:DWORD'
		}
		for pm in f.params {
			ps << '${resolve_name(st, f.name, pm.name)}:${st.type_masm[pm.typ_name]}'
		}
		if ps.len > 0 {
			head = head + ', ' + ps.join(', ')
		}
		mut ls := []string{}
		ls << head
		for stmtx in f.body {
			if stmtx.kind != StmtKind.st_local {
				continue
			}
			mut parts := []string{}
			for n in stmtx.local_names {
				nm := resolve_name(st, f.name, n)
				t := st.type_masm[stmtx.local_type]
				if stmtx.local_array_len.len > 0 {
					parts << '${nm}[${stmtx.local_array_len}]:${t}'
				} else {
					parts << '${nm}:${t}'
				}
			}
			ls << '    local ' + parts.join(', ')
		}
		is_entry := f.name == prog.entry
		ctx.body = f.body
		mut bi := 0
		for bi < f.body.len {
			ctx.body_pos = bi
			ctx.stmt(f.body[bi], is_entry)
			bi = bi + 1
		}
		for l in ctx.lines {
			ls << l
		}
		ls << '${f.name} endp'
		ls << ''
		// cone 0.83：seg 段内函数不单独出单元，整段行存起来由 seg 取用。
		if f.in_seg.len > 0 {
			func_lines[f.name] = ls
		} else {
			units << EmitUnit{phase: 8, order: f.order, section: 3, lines: ls, text: '', is_asm: false, switches: false}
		}
	}

	// cone 0.83：特殊段。option dotname 临时开启（即使段名无 . 也开），
	// class 与段名同名；段内 items 严格按源码顺序输出，不参与常规 phase 聚合。
	for sg in prog.segs {
		mut ls := []string{}
		ls << 'option dotname    ; cone 0.83：临时开启，段结束立刻 option nodotname'
		ls << '${sg.name} segment para \'${sg.name}\''
		for it in sg.items {
			if it.kind == SegItemKind.si_var {
				ls << '    ' + render_var(prog, st, it.var_def)
			} else if it.kind == SegItemKind.si_func {
				if it.func_def.name in func_lines {
					for l in func_lines[it.func_def.name] {
						if l.len == 0 {
							continue
						}
						ls << l
					}
				}
			} else if it.kind == SegItemKind.si_stmt {
				// 段内裸代码：复用函数体语句发射器，但不套 proc / endp、不生成 ret。
				mut sctx := GenCtx{
					prog:         prog
					st:           st
					fname:        sg.name
					float_labels: float_labels
					char_labels:  char_labels
					stt_labels:   stt_labels
					itmp:         itmp
					o1:           opts.o1
					lines:        []string{}
					if_stack:     []IfFrame{}
					if_id:        0
					loop_stack:   []LoopFrame{}
					loop_id:      0
					body:         it.stmts
					body_pos:     0
					match_id:     0
					match_stack:  []MatchFrame{}
					try_stack:    []TryFrame{}
				}
				mut si := 0
				for si < it.stmts.len {
					sctx.body_pos = si
					sctx.stmt(it.stmts[si], false)
					si = si + 1
				}
				for l in sctx.lines {
					ls << l
				}
			}
		}
		ls << '${sg.name} ends'
		ls << 'option nodotname'
		ls << ''
		units << EmitUnit{phase: 8, order: sg.order, section: -1, lines: ls, text: '', is_asm: false, switches: false}
	}

	// cone 0.7：SEH handler 统一返回 stub。必须放在所有 ENDP 之外，否则 MASM 的
	// `PROC USES ebx esi edi` 会把这里的 ret 重写成带 pop 的 epilogue，破坏回调栈。
	// 只在源码里出现过 try 时生成，老示例的 .asm 不多一行。
	// cone 0.84：stub 的触发条件扩展到 seg 段内 try（段内裸代码 / 段内函数），
	// 以及「挂了默认全局 SEH」——默认 handler 也 jmp 到这个 stub。
	mut has_seh := !opts.no_default_seh
	for f in prog.funcs {
		for s in f.body {
			if s.kind == StmtKind.st_try {
				has_seh = true
			}
		}
	}
	for sg in prog.segs {
		for it in sg.items {
			if it.kind == SegItemKind.si_stmt {
				for s in it.stmts {
					if s.kind == StmtKind.st_try {
						has_seh = true
					}
				}
			}
		}
	}
	if has_seh {
		mut ls_stub := []string{}
		ls_stub << '__cone_seh_ret_stub:                     ; cone 0.7：SEH handler 统一返回（ENDP 之外）'
		ls_stub << '    ret'
		ls_stub << ''
		units << EmitUnit{phase: 8, order: 2147483645, section: 3, lines: ls_stub, text: '', is_asm: false, switches: false}
	}

	// cone 0.84：默认全局 try-except（链式最外层）。
	// 用户 try 帧注册在它之后（prev 指向它）；用户分支都不匹配 -> ContinueSearch
	// 冒泡到这个帧 -> 无条件接管：有 `def cone()`（无参）就 call cone，
	// 否则直接 ExitProcess(fuck)。两者最后都以 fuck（异常码）退出进程。
	// 全部是 proc 外的 .code 裸标号，避开 PROC USES 的 epilogue 重写。
	if !opts.no_default_seh {
		mut has_cone := false
		for f in prog.funcs {
			if f.name == 'cone' && f.params.len == 0 {
				has_cone = true
			}
		}
		mut ds := []string{}
		ds << '__cone_default_seh_handler:                     ; cone 0.84：默认全局 SEH（用户未捕获时接管）'
		ds << '    mov eax, [esp+4]                   ; EXCEPTION_RECORD*'
		ds << '    mov ecx, [eax]                     ; ExceptionCode'
		ds << '    mov edx, [esp+8]                   ; pFrame'
		ds << '    mov [edx+8], ecx                   ; 存进本帧 code 槽'
		ds << '    mov eax, [esp+12]                  ; CONTEXT*'
		ds << '    mov dword ptr [eax+184], offset __cone_default_seh_dispatch   ; CONTEXT.Eip = 0B8h'
		ds << '    mov dword ptr [eax+196], edx       ; CONTEXT.Esp = 0C4h = pFrame（unwind）'
		ds << '    xor eax, eax                       ; ExceptionContinueExecution = 0'
		ds << '    jmp __cone_seh_ret_stub'
		ds << '__cone_default_seh_dispatch:                     ; 由 handler 改 CONTEXT.Eip 跳入，esp = pFrame'
		ds << '    mov eax, [esp+8]                   ; 取出本帧存的 ExceptionCode'
		ds << '    mov fuck, eax                      ; 写入保留变量 fuck（错误码）'
		ds << '    push edx'
		ds << '    mov edx, [esp+4]                   ; prev = [pFrame]'
		ds << '    mov fs:[0], edx                    ; 卸载默认 SEH 帧'
		ds << '    pop edx'
		ds << '    add esp, 12                        ; 弹出 [prev][handler][code]'
		if has_cone {
			ds << '    call cone                          ; 定义了无参 def cone()：交给用户处理'
		} else {
			ds << '    ; 未定义无参 def cone()：直接以错误码退出'
		}
		ds << '    invoke ExitProcess, fuck'
		ds << ''
		ds << '__cone_default_entry:                            ; cone 0.84：全局入口（end 指向这里）'
		ds << '    push 0                                  ; 本帧 code 槽'
		ds << '    push offset __cone_default_seh_handler'
		ds << '    push fs:[0]                             ; prev'
		ds << '    mov fs:[0], esp                         ; 安装默认帧（链式最外层）'
		ds << '    call ${prog.entry}'
		ds << '    ; 入口正常返回（未 ExitProcess）时卸载默认帧'
		ds << '    push edx'
		ds << '    mov edx, [esp+4]                   ; prev'
		ds << '    mov fs:[0], edx'
		ds << '    pop edx'
		ds << '    add esp, 12'
		ds << '    ret'
		ds << ''
		units << EmitUnit{phase: 8, order: 2147483640, section: 3, lines: ds, text: '', is_asm: false, switches: false}
	}

	// phase 9：end 入口。挂了默认 SEH 时改指向 wrapper，否则保持原入口。
	mut ls_end := []string{}
	if opts.no_default_seh {
		ls_end << 'end ${prog.entry}'
	} else {
		ls_end << 'end __cone_default_entry'
	}
	units << EmitUnit{phase: 9, order: 2147483646, section: -1, lines: ls_end, text: '', is_asm: false, switches: false}

	// 顶层 asm：按自身 order 落进「前一个源码声明」所在的 phase
	mut anchors := []OrderPhase{}
	for u in units {
		anchors << OrderPhase{order: u.order, phase: u.phase}
	}
	// cone 0.9preview：顶层 asm64{} —— 预编译的 db 机器码行，按源码 order 落进 .code。
	for ab in prog.asm64s {
		mut ls := []string{}
		key := 't${ab.order}'
		if key in st.asm64_cache {
			for l in st.asm64_cache[key] {
				ls << l
			}
		}
		mut ols := []string{}
		if opts.o1 {
			ols << o1_on
		}
		for l in ls {
			ols << l
		}
		if opts.o1 {
			ols << o1_off
		}
		units << EmitUnit{phase: 8, order: ab.order, section: 3, lines: ols, text: '', is_asm: false, switches: false}
	}
	for ab in prog.asms {
		mut ph := 0
		mut best := -1
		mut bestorder := -1
		for a in anchors {
			if a.order < ab.order && a.order > bestorder {
				bestorder = a.order
				best = a.phase
			}
		}
		if best >= 0 {
			ph = best
		}
		txt := asm_resolve_text(st, '', trim_asm_text(ab.text))
		units << EmitUnit{
			phase:    ph
			order:    ab.order
			section:  -1
			lines:    []string{}
			text:     txt
			is_asm:   true
			switches: asm_switches_segment(txt)
		}
	}

	units = sort_units(units)

	mut cur_sec := -1
	for u in units {
		if u.is_asm {
			if opts.o1 {
				out << o1_on
			}
			if u.text.len > 0 {
				out << u.text
			}
			if opts.o1 {
				out << o1_off
			}
			if u.switches {
				cur_sec = -2
			}
			continue
		}
		if u.section >= 0 && u.section != cur_sec {
			out << ''
			out << emit_section_name(u.section)
			cur_sec = u.section
		} else if u.section < 0 {
			cur_sec = -1
		}
		for l in u.lines {
			out << l
		}
	}
	asm_text := strip_asm_comments(out.join('\n') + '\n')
	if opts.o1 {
		return o1_optimize(asm_text, O1Config{
			opts:      opts.o1_opts
			src_path:  opts.src_path
		})
	}
	return asm_text
}
