module main

// 当前语法（EBNF，cone 0.3 · 本轮大更新）:
//
//   program     := decl* entry_decl eof
//   decl        := import_decl | include_decl | equ_def | typedef_decl | proto_decl
//                | str_def | var_def | array_def | func_def
//   import_decl := "import" IDENT "." "dll"
//   include_decl:= "include" IDENT
//   equ_def     := IDENT "equ" ( "<" RAW ">" | expr ("," expr)* )
//   typedef_decl:= "typedef" IDENT type_name
//   proto_decl  := "func" IDENT "(" decl_params? ")" call_conv?
//   str_def     := IDENT ":" str_item ("," str_item)*
//   var_def     := ["const"] type_name IDENT ["=" expr]
//   array_def   := IDENT type_name "[" NUMBER "]"
//   func_def    := "def" IDENT "(" def_params? ")" call_conv? "{" stmt* "}"
//   stmt        := "return" expr | local_decl | local_array | str_def | assign_stmt
//                | deref_assign | call_expr | if_chain
//   if_chain    := "if" expr "{" stmt* "}" ("elseif" expr "{" stmt* "}")* ("else" "{" stmt* "}")?
//   assign_stmt := (IDENT | REG) "=" expr           // REG 也是合法左值
//   deref_assign:= deref "=" expr                   // [] 直接内存写，与 MASM32 一致
//   local_array := IDENT type_name "[" NUMBER "]"
//   entry_decl  := "end" IDENT
//
//   expr        := or_expr
//   or_expr     := and_expr ("||" and_expr)*
//   and_expr    := cmp_expr ("&&" cmp_expr)*
//   cmp_expr    := add_expr (cmpop add_expr)*        // == != > < >= <=
//   add_expr    := term (("+"|"-") term)*
//   term        := unary (("*"|"/") unary)*
//   unary       := ("-"|"+"|"!"|"addr") unary | primary
//   primary     := NUMBER | STRING | IDENT | REG | win_sym | call_expr | deref | "(" expr ")"
//   win_sym     := "win" "." IDENT                  // MASM 侧已定义的宏常量 / 变量
//   STRING      := 表达式位置 = 字符常量（转义 / 补 0 / .const / 取地址）
//   deref       := "[" size_word? addr_expr "]"      // type ptr [addr]，一步访问
//   addr_expr   := addr_term (("+"|"-") addr_term)*   // 至少含一个标识符/寄存器/函数调用
//   addr_term   := (IDENT | REG | call_expr | "addr" IDENT) ["*" NUMBER] | NUMBER
//                  // 对应 MASM 的 [mem] / [mem+imm] / [mem+reg] / [mem+reg*scale+imm]
//   size_word   := cone 类型关键字 | MASM 尺寸词（byte/word/dword/qword/real4/...）
//   call_expr   := ("win" | IDENT) ["." IDENT] "(" args? ")"
//   args        := expr ("," expr)*
//
// 换行【不是】语句终止符。return 必须带表达式。
// REG = 32/16/8 位通用寄存器 + 段寄存器，与 MASM32 同名，是保留特殊标识符，
// 可以出现在表达式、左值、参数、[] 地址里。
// [] 与 MASM32 语义完全一致：[type addr] 就是 type ptr [addr]，一步访问。
// [type mem]=yyy 生成 mov type ptr [mem],yyy；type 与 mem 尺寸一致时等价于 mem=yyy，
// 但 cone 还能自定义尺寸（byte/word/...）与偏移（+4 / +reg*scale）。
// 想解引用请显式写 `regname=var` 再 `[type regname]=yyy`，编译器不猜测间接层数。
// 函数体内的 str_def 提升到全局 .data；local_array 生成 MASM 的 local 数组。

struct Parser {
	toks []Token
mut:
	pos           int
	exprs         []Expr
	data          []DataDef
	order         int
	loop_depth    int // break / continue 的词法嵌套校验
	struct_names  []string // cone 0.6：已声明的 cone 结构体名，用于辨识 Type{...}
	win_names     []string // cone 0.6 fix2：win{...} 批量登记的 MASM 侧符号（已去重）
	typedef_names []string // cone 0.6 fix3：已声明的 typedef 名（类型位置上 cone 名字优先）
	equ_values    map[string]string // cone 0.7：cone 侧已求值的数值 equ（名字 -> 立即数文本）
	try_id        int               // cone 0.7：函数内 try 编号，生成唯一 SEH 标签
	no_struct_lit bool              // cone 0.7：解析 except ErrorType 时禁用 Type{...} 消费 {
}

// cone 0.7：equ 预扫描用的临时结果。parse_equ_def 失败时 ok=false，
// 这样 prescan_folded_equs 里不需要在 or 块写 continue（保持保守写法）。
struct EquScan {
	name      string
	items     []int
	exprs     []Expr
	end_pos   int
	line      int
	is_raw    bool
	ok        bool
	has_str   bool
}

// fold_e: 只用节点池求值的编译期整数常量表达式（parser 阶段没有完整 Program）。
// expr_ident 查 values（已求出的数值 equ）；win. / 寄存器 / 局部变量一律视为不可求值。
fn fold_e(exprs []Expr, idx int, values map[string]string) !i64 {
	if idx < 0 || idx >= exprs.len {
		return error('表达式索引越界')
	}
	e := exprs[idx]
	if e.is_float_hint || e.is_struct_lit {
		return error('float(...) / 结构体常量不是编译期整数常量')
	}
	if e.kind == ExprKind.expr_num {
		return parse_int_lit(e.text)
	}
	if e.kind == ExprKind.expr_ident {
		if e.is_reg || e.is_win_sym {
			return error('寄存器 / MASM 外部符号不是 cone 侧立即数')
		}
		if e.text in values {
			return parse_int_lit(values[e.text])
		}
		return error('标识符 ${e.text} 不是已求值的数值 equ')
	}
	if e.kind == ExprKind.expr_neg {
		v := fold_e(exprs, e.a, values) or { return error(err.msg()) }
		if e.text == '~' {
			return -v - 1
		}
		return -v
	}
	if e.kind == ExprKind.expr_bin {
		l := fold_e(exprs, e.a, values) or { return error(err.msg()) }
		r := fold_e(exprs, e.b, values) or { return error(err.msg()) }
		if e.text == '+' { return l + r }
		if e.text == '-' { return l - r }
		if e.text == '*' { return l * r }
		if e.text == '/' {
			if r == 0 { return error('编译期计算出现除零') }
			return l / r
		}
		if e.text == '|' { return l | r }
		if e.text == '&' { return l & r }
		if e.text == '^' { return l ^ r }
		if e.text == '<<' { return bit_shl(l, r) }
		if e.text == '>>' { return bit_shr(l, r) }
		return error('未知运算符 ${e.text}')
	}
	return error('不是编译期整数常量表达式')
}

struct EquFoldRes {
	ok    bool
	value i64
}

fn try_fold_e(exprs []Expr, idx int, values map[string]string) EquFoldRes {
	v := fold_e(exprs, idx, values) or { return EquFoldRes{ok: false, value: 0} }
	return EquFoldRes{ok: true, value: v}
}

// folded_text_of: 单个数值 token 保留源码原文（0C0000005h / 0dh / -11），
// 复合表达式输出求值结果的十进制文本。这样 hex 错误码在 .asm 里仍可读。
fn folded_text_of(exprs []Expr, idx int, v i64) string {
	e := exprs[idx]
	if e.kind == ExprKind.expr_num {
		return e.text
	}
	if e.kind == ExprKind.expr_neg && e.text == '-' && e.a >= 0 && e.a < exprs.len {
		if exprs[e.a].kind == ExprKind.expr_num {
			return '-' + exprs[e.a].text
		}
	}
	return '${v}'
}

// scan_equ_at: 在指定位置试解析一条 equ（用一次性 Parser，不污染主解析流）。
fn scan_equ_at(toks []Token, start int) EquScan {
	mut tp := Parser{
		toks:          toks
		pos:           start
		exprs:         []Expr{}
		data:          []DataDef{}
		order:         0
		loop_depth:    0
		struct_names:  []string{}
		win_names:     []string{}
		typedef_names: []string{}
		equ_values:    map[string]string{}
		try_id:        0
		no_struct_lit: false
	}
	eq := tp.parse_equ_def() or {
		return EquScan{name: '', items: []int{}, exprs: []Expr{}, end_pos: start + 1, line: 0, is_raw: false, ok: false, has_str: false}
	}
	mut has_str := false
	for it in eq.items {
		if it >= 0 && it < tp.exprs.len && tp.exprs[it].kind == ExprKind.expr_str {
			has_str = true
		}
	}
	return EquScan{
		name:    eq.name
		items:   eq.items.clone()
		exprs:   tp.exprs.clone()
		end_pos: tp.pos
		line:    eq.line
		is_raw:  eq.is_raw
		ok:      true
		has_str: has_str
	}
}

// prescan_folded_equs: 正式解析前扫一遍最终展开后的 token 流，把「单个可求值的
// 常量表达式」equ 在 cone 侧算成立即数。多轮迭代支持链式 / 前向引用（B equ A+2）。
// 保留 MASM equ 伪指令的形态：尖括号原文、逗号列表、字符串、win. 外部符号、
// 不可求值表达式 —— 这些 cone 侧没有数值，无法展开成立即数。
fn prescan_folded_equs(toks []Token) map[string]string {
	mut scans := []EquScan{}
	mut i := 0
	for i + 1 < toks.len {
		if toks[i].kind == TokenKind.ident && toks[i + 1].kind == TokenKind.kw_equ {
			// 尖括号原文形式不做折叠
			if i + 2 < toks.len && toks[i + 2].kind == TokenKind.equ_text {
				i = i + 1
				continue
			}
			sc := scan_equ_at(toks, i)
			if sc.ok {
				if !sc.is_raw && sc.items.len == 1 && !sc.has_str {
					scans << sc
				}
				i = sc.end_pos
				continue
			}
		}
		i = i + 1
	}
	mut values := map[string]string{}
	mut round := 0
	for round <= scans.len {
		mut added := 0
		for sc in scans {
			if sc.name in values {
				continue
			}
			idx := sc.items[0]
			fr := try_fold_e(sc.exprs, idx, values)
			if !fr.ok {
				continue
			}
			values[sc.name] = folded_text_of(sc.exprs, idx, fr.value)
			added = added + 1
		}
		if added == 0 {
			break
		}
		round = round + 1
	}
	return values
}

// cone 0.6 fix3：正式解析前先扫一遍 token 流，把全部 win{...} 块里的名字提前登记。
// win{...} 允许写在文件末尾（全文件生效），而「类型位置」「结构体常量」「字段偏移」
// 这三种用法在【解析时】就要决定节点形态，不能等解析完再回填，所以必须预扫描。
// 块本身的合法性仍由 parse_win_block 逐 token 校验，这里只做名字收集（容错）。
fn prescan_win_names(toks []Token) []string {
	mut names := []string{}
	mut i := 0
	for i + 1 < toks.len {
		if toks[i].kind == TokenKind.kw_win && toks[i + 1].kind == TokenKind.lbrace {
			mut j := i + 2
			for j < toks.len && toks[j].kind != TokenKind.rbrace && toks[j].kind != TokenKind.eof {
				if toks[j].kind == TokenKind.ident && !(toks[j].lit in names) {
					names << toks[j].lit
				}
				j = j + 1
			}
			i = j + 1
			continue
		}
		i = i + 1
	}
	return names
}

fn (mut p Parser) cur() Token {
	return p.toks[p.pos]
}

fn (mut p Parser) peek(off int) Token {
	idx := p.pos + off
	if idx >= p.toks.len {
		return p.toks[p.toks.len - 1]
	}
	return p.toks[idx]
}

fn (mut p Parser) advance() Token {
	t := p.cur()
	if p.pos < p.toks.len - 1 {
		p.pos = p.pos + 1
	}
	return t
}

fn (mut p Parser) expect(kind TokenKind, what string) !Token {
	t := p.cur()
	if t.kind != kind {
		return error('期望 ${what}，实际得到 ${t.desc()}')
	}
	return p.advance()
}

fn (mut p Parser) expect_ident(what string) !string {
	t := p.cur()
	if t.kind == TokenKind.reg {
		return error('第 ${t.line} 行: `${t.lit}` 是 cone 0.3 的寄存器（保留特殊标识符），不能用作 cone 的 ${what}；寄存器可以直接写 `reg=...` / 用在表达式与参数里')
	}
	if t.kind == TokenKind.reserved {
		return error('第 ${t.line} 行: `${t.lit}` 是 MASM32 保留标识符（指令 / 伪指令 / 属性 / 运算符），不能用作 cone 的 ${what}')
	}
	if t.kind != TokenKind.ident {
		return error('期望 ${what}，实际得到 ${t.desc()}')
	}
	p.advance()
	return t.lit
}

// cone 0.7：需要 NUMBER 的地方（数组长度等）也接受 cone 侧已求值的数值 equ，
// 直接返回展开后的立即数文本，不再把它当标识符。
fn (mut p Parser) expect_const_number(what string) !string {
	// cone 0.9prelease：数组维度 / 编译期常量接受完整 cone 立即数表达式文本。
	// 数值、equ 数值宏、sizeof(...)、结构体类型名.成员偏移、$、四则 / 位运算 / 括号
	// 都可出现；扫到数组右括号或语句边界为止，由 analyzer 的 fold_int_text 求值。
	mut parts := []string{}
	mut depth := 0
	mut started := false
	for {
		t := p.cur()
		k := t.kind
		if k == TokenKind.eof {
			break
		}
		if depth == 0 && (k == TokenKind.rbracket || k == TokenKind.comma || k == TokenKind.rbrace || k == TokenKind.assign || k == TokenKind.lbrace) {
			break
		}
		allowed := match k {
			.number, .dollar, .ident, .kw_sizeof, .kw_win, .dot, .lparen, .rparen,
			.plus, .minus, .star, .slash, .amp, .pipe, .caret, .shl, .shr, .tilde,
			.reg, .string_lit { true }
			else { false }
		}
		if !allowed {
			break
		}
		if k == TokenKind.rparen {
			if depth == 0 {
				break
			}
			depth = depth - 1
		} else if k == TokenKind.lparen {
			depth = depth + 1
		}
		parts << t.lit
		p.advance()
		started = true
	}
	if !started {
		r := p.expect(TokenKind.number, '${what}（可直接写数值，或写 cone 侧数值 equ 名）') or {
			return error(err.msg())
		}
		return r.lit
	}
	return parts.join('')
}

fn (mut p Parser) add_expr(e Expr) int {
	p.exprs << e
	return p.exprs.len - 1
}

fn (mut p Parser) next_order() int {
	n := p.order
	p.order = p.order + 1
	return n
}

fn is_type_kw(k TokenKind) bool {
	if k == TokenKind.kw_byte || k == TokenKind.kw_word || k == TokenKind.kw_int {
		return true
	}
	if k == TokenKind.kw_long || k == TokenKind.kw_f32 || k == TokenKind.kw_f64 {
		return true
	}
	return false
}

// type_name: 内置类型关键字，或 typedef 别名（parser 不校验，交给语义分析）
fn (mut p Parser) parse_type_name() !string {
	t := p.cur()
	// cone 0.4 fix：win.XXX 表示 MASM32 / windows.inc 里已定义的结构体类型，
	// cone 侧不生成 STRUCT 定义、不校验成员名，输出时去掉 win. 前缀。
	if t.kind == TokenKind.kw_win {
		p.advance()
		p.expect(TokenKind.dot, '.') or { return error(err.msg()) }
		nm := p.expect_ident('win. 后的 MASM 结构体类型名') or { return error(err.msg()) }
		return 'win.' + nm
	}
	if t.kind == TokenKind.reserved {
		return error('第 ${t.line} 行: `${t.lit}` 是 MASM32 保留标识符，不能用作 cone 类型名；请换一个名字')
	}
	if is_type_kw(t.kind) || t.kind == TokenKind.ident {
		p.advance()
		// cone 0.6 fix3：win{...} 登记的裸名字用在类型位置，等价于写 win.NAME
		// （MASM32 侧已定义的外部结构体类型）。cone 自己的 struct / typedef 名优先，
		// 保持原有语义不被覆盖。
		if t.lit in p.win_names && !(t.lit in p.struct_names) && !(t.lit in p.typedef_names) {
			return 'win.' + t.lit
		}
		return t.lit
	}
	return error('期望类型名（byte/word/int/long/f32/f64 / 结构体 / win.MASM类型 / typedef 别名），实际得到 ${t.desc()}')
}

fn is_expr_start(k TokenKind) bool {
	if k == TokenKind.dollar {
		return true
	}
	if k == TokenKind.number || k == TokenKind.string_lit || k == TokenKind.ident {
		return true
	}
	if k == TokenKind.reg {
		return true
	}
	if k == TokenKind.kw_win || k == TokenKind.kw_addr || k == TokenKind.kw_float || k == TokenKind.kw_sizeof || k == TokenKind.lparen {
		return true
	}
	if k == TokenKind.lbracket {
		return true
	}
	if k == TokenKind.minus || k == TokenKind.plus {
		return true
	}
	if k == TokenKind.bang { // 逻辑非 !expr
		return true
	}
	if k == TokenKind.tilde { // cone 0.6 fix1：按位非 ~expr
		return true
	}
	return false
}

// describe_expr: 把"不是合法语句"的那个表达式说清楚，避免笼统报错。
fn describe_expr(exprs []Expr, idx int) string {
	if idx < 0 || idx >= exprs.len {
		return '表达式'
	}
	e := exprs[idx]
	if e.kind == ExprKind.expr_num {
		if is_float_lit(e.text) {
			return '浮点立即数 `${e.text}`'
		}
		return '立即数 `${e.text}`'
	}
	if e.kind == ExprKind.expr_str {
		return '字符串字面量 ${e.text}'
	}
	if e.kind == ExprKind.expr_ident {
		return '标识符 `${e.text}`（若想调用它，请写成 `${e.text}(...)`）'
	}
	if e.kind == ExprKind.expr_neg {
		return '负数表达式 `-${exprs[e.a].text}`'
	}
	if e.kind == ExprKind.expr_bin {
		return '算术表达式（运算符 `${e.text}`）'
	}
	if e.kind == ExprKind.expr_addr {
		return 'addr 取地址表达式'
	}
	if e.kind == ExprKind.expr_deref {
		return '[] 解引用表达式'
	}
	if e.kind == ExprKind.expr_member {
		return '结构体成员 / 字段偏移 `${e.text}`'
	}
	return '表达式'
}

// ---------- 顶层声明 ----------

// cone 0.8prelease：import 只支持 `import xxx`（在预处理阶段展开 xxx.cone）。
// `import xxx.dll` 已移除；链接 .lib 请写 `include xxx.lib`。
// 正常路径下所有 import 都已被 expand_imports 吃掉，这里只作为兜底报错。
fn (mut p Parser) parse_import() !ImportDecl {
	t := p.cur()
	return error('第 ${t.line} 行: import 现在只支持 `import 名字`（导入 std/名字.cone 或源码目录/名字.cone）；`import 名字.dll` 已移除，链接 .lib 请写 `include 名字.lib`')
}

// expect_include_suffix: include 名字.后缀 里的「后缀」是 MASM 文件名的一部分，
// 不是 cone 标识符 —— 因此连 `inc` 这种 MASM 保留字（指令）也要放行，
// 否则 `include windows.inc` 会被误判。只要求它是纯标识符字符序列。
fn (mut p Parser) expect_include_suffix(what string) !string {
	t := p.cur()
	if t.lit.len == 0 {
		return error('期望 ${what}，实际得到 ${t.desc()}')
	}
	mut i := 0
	for i < t.lit.len {
		if !is_ident_cont(t.lit[i]) {
			return error('期望 ${what}（纯标识符字符），实际得到 ${t.desc()}')
		}
		i = i + 1
	}
	p.advance()
	return t.lit
}

// parse_include: cone 0.8prelease 的三种形态
//   include xxx       -> include xxx.inc + includelib xxx.lib
//   include xxx.yyy   -> include xxx.yyy（后缀非 lib 时只生成 include）
//   include xxx.lib   -> includelib xxx.lib（后缀是 lib 时只生成 includelib）
fn (mut p Parser) parse_include() !IncludeDecl {
	ln := p.cur().line
	p.expect(TokenKind.kw_include, 'include') or { return error(err.msg()) }
	name := p.expect_ident('模块名') or { return error(err.msg()) }
	mut full := name
	mut inc_file := name + '.inc'
	mut lib_file := name + '.lib'
	if p.cur().kind == TokenKind.dot {
		p.advance()
		suf := p.expect_include_suffix('include 后缀') or { return error(err.msg()) }
		full = name + '.' + suf
		if p.cur().kind == TokenKind.dot {
			return error('第 ${ln} 行: include 只支持 `include 名字` 或 `include 名字.后缀` 两级，实际得到 ${full}.${p.peek(1).lit}')
		}
		if eq_ci(suf, 'lib') {
			inc_file = ''
			lib_file = full
		} else {
			inc_file = full
			lib_file = ''
		}
	}
	return IncludeDecl{
		name:     full
		inc_file: inc_file
		lib_file: lib_file
		line:     ln
		order:    p.next_order()
	}
}

// parse_equ_def: NAME equ <xxx>  或  NAME equ xxx(,xxx)*
// 两种形态都直接对应 MASM32：cone 写尖括号就输出尖括号，写裸文本就输出裸文本。
fn (mut p Parser) parse_equ_def() !EquDecl {
	ln := p.cur().line
	pos := p.pos // cone 0.6 fix2：声明起始 token 位置（顺序检查用）
	name := p.expect_ident('equ 常量名') or { return error(err.msg()) }
	p.expect(TokenKind.kw_equ, 'equ') or { return error(err.msg()) }

	// 尖括号形式：整段原文透传给 MASM（内部不做表达式解析）
	if p.cur().kind == TokenKind.equ_text {
		t := p.advance()
		return EquDecl{
			name:        name
			items:       []int{}
			is_raw:      true
			raw_text:    t.text
			line:        ln
			pos:         pos
			order:       p.next_order()
			is_folded:   false
			folded_text: ''
		}
	}

	mut items := []int{}
	for {
		// 裸形式里也允许别名写 win.xxx：cone 侧去掉 win. 前缀，MASM 侧输出 xxx。
		// 例如 `print equ win.crt_printf` -> `print equ crt_printf`，且 print 在 cone 侧可调用。
		if p.cur().kind == TokenKind.kw_win {
			wl := p.cur().line
			p.advance()
			p.expect(TokenKind.dot, '.') or { return error(err.msg()) }
			fname := p.expect_ident('win. 后的函数名') or { return error(err.msg()) }
			items << p.add_expr(new_expr(ExprKind.expr_ident, fname, wl))
		} else if p.cur().kind == TokenKind.string_lit {
			// equ 里的字符串保持"引号内即字节流、无转义"，不进字符常量池。
			st := p.advance()
			items << p.add_expr(new_expr(ExprKind.expr_str, st.lit, st.line))
		} else if is_expr_start(p.cur().kind) {
			idx := p.parse_expr() or { return error(err.msg()) }
			items << idx
		} else {
			return error('第 ${ln} 行: ${name} equ 后需要一个常量项（数值 / 字符串 / 标识符 / 常量表达式，或 <...> 原文 / win.xxx 别名），实际得到 ${p.cur().desc()}')
		}
		if p.cur().kind != TokenKind.comma {
			break
		}
		p.advance()
	}
	return EquDecl{
		name:        name
		items:       items
		is_raw:      false
		raw_text:    ''
		line:        ln
		pos:         pos
		order:       p.next_order()
		is_folded:   false
		folded_text: ''
	}
}

fn (mut p Parser) parse_typedef() !TypedefDecl {
	ln := p.cur().line
	p.expect(TokenKind.kw_typedef, 'typedef') or { return error(err.msg()) }
	name := p.expect_ident('新类型名') or { return error(err.msg()) }
	if !(name in p.typedef_names) {
		p.typedef_names << name
	}
	base := p.parse_type_name() or { return error(err.msg()) }
	return TypedefDecl{
		name:           name
		base_type_name: base
		line:           ln
		order:          p.next_order()
	}
}

// cone 0.5：函数修饰符 = 调用约定（c / stdcall，可选）+ export（可选），
// 二者顺序不限、各最多一次，与 MASM32 `PROC stdcall EXPORT` 的属性列表一致。
fn (mut p Parser) parse_modifiers() !FuncMods {
	mut mods := FuncMods{
		conv:      CallConv.cc_default
		is_export: false
	}
	mut got_conv := false
	for true {
		k := p.cur().kind
		if k == TokenKind.kw_c || k == TokenKind.kw_stdcall {
			if got_conv {
				return error('第 ${p.cur().line} 行: 调用约定重复（c / stdcall 只能写一个）')
			}
			got_conv = true
			if k == TokenKind.kw_c {
				mods.conv = CallConv.cc_c
			} else {
				mods.conv = CallConv.cc_stdcall
			}
			p.advance()
		} else if k == TokenKind.kw_export {
			if mods.is_export {
				return error('第 ${p.cur().line} 行: export 重复（只能写一次）')
			}
			mods.is_export = true
			p.advance()
		} else {
			break
		}
	}
	return mods
}

// cone 0.9.1：解析函数尾部可选返回类型。
// 只接受内置类型关键字或已登记的 cone 结构体/typedef 名，且必须与 func/def 同一行，
// 避免把下一行的顶层变量声明（如 `long g`）误当返回类型。
fn (mut p Parser) parse_ret_type(ln int) !string {
	t := p.cur()
	if t.line != ln { return '' }
	if is_type_kw(t.kind) {
		return p.parse_type_name() or { return error(err.msg()) }
	}
	if t.kind == TokenKind.ident && (t.lit in p.struct_names || t.lit in p.typedef_names) {
		return p.parse_type_name() or { return error(err.msg()) }
	}
	return ''
}

fn (mut p Parser) parse_decl_params() ![]Param {
	mut ps := []Param{}
	if p.cur().kind == TokenKind.rparen {
		return ps
	}
	for {
		ln := p.cur().line
		mut name := ''
		if p.cur().kind == TokenKind.ident {
			name = p.advance().lit
		}
		p.expect(TokenKind.colon, ':') or { return error(err.msg()) }
		// cone 0.9.p：x64 func 声明的 :vararg 标记（def 定义在 parse_def_params 里拒绝）
		if p.cur().kind == TokenKind.ident && eq_ci(p.cur().lit, 'vararg') {
			p.advance()
			ps << Param{name: name, typ_name: 'vararg', line: ln}
		} else {
			typ := p.parse_type_name() or { return error(err.msg()) }
			ps << Param{
				name:     name
				typ_name: typ
				line:     ln
			}
		}
		if p.cur().kind != TokenKind.comma {
			break
		}
		p.advance()
	}
	return ps
}

fn (mut p Parser) parse_proto(is_external bool) !ProtoDecl {
	ln := p.cur().line
	fl := p.cur().file // cone 0.9.3：来源文件
	pos := p.pos // cone 0.6 fix2：声明起始 token 位置（顺序检查用）
	kw := if is_external { TokenKind.kw_efunc } else { TokenKind.kw_func }
	kwn := if is_external { 'efunc' } else { 'func' }
	p.expect(kw, kwn) or { return error(err.msg()) }
	name := p.expect_ident('函数名') or { return error(err.msg()) }
	p.expect(TokenKind.lparen, '(') or { return error(err.msg()) }
	params := p.parse_decl_params() or { return error(err.msg()) }
	p.expect(TokenKind.rparen, ')') or { return error(err.msg()) }
	mods := p.parse_modifiers() or { return error(err.msg()) }
	rt := p.parse_ret_type(ln) or { return error(err.msg()) }
	return ProtoDecl{
		name:      name
		params:    params
		conv:      mods.conv
		line:      ln
		pos:       pos
		is_export: mods.is_export
		order:     p.next_order()
		ret_type:  rt
		file:      fl
		is_external: is_external
	}
}

fn (mut p Parser) parse_str_def(is_const bool) !DataDef {
	ln := p.cur().line
	if is_const {
		p.expect(TokenKind.kw_const, 'const') or { return error(err.msg()) }
	}
	name := p.expect_ident('数据标签名') or { return error(err.msg()) }
	p.expect(TokenKind.colon, ':') or { return error(err.msg()) }
	mut items := []int{}
	for {
		t := p.cur()
		if t.kind == TokenKind.string_lit {
			p.advance()
			items << p.add_expr(new_expr(ExprKind.expr_str, t.lit, t.line))
		} else if t.kind == TokenKind.number || t.kind == TokenKind.minus || t.kind == TokenKind.plus {
			idx := p.parse_unary() or { return error(err.msg()) }
			items << idx
		} else {
			return error('第 ${ln} 行: ${name}: 后只允许字符串或数值，实际得到 ${t.desc()}')
		}
		if p.cur().kind != TokenKind.comma {
			break
		}
		p.advance()
	}
	return DataDef{
		name:     name
		items:    items
		line:     ln
		order:    p.next_order()
		is_const: is_const
	}
}

fn (mut p Parser) parse_var_def(is_const bool) !VarDef {
	ln := p.cur().line
	if is_const {
		p.expect(TokenKind.kw_const, 'const') or { return error(err.msg()) }
	}
	typ := p.parse_type_name() or { return error(err.msg()) }
	name := p.expect_ident('变量名') or { return error(err.msg()) }
	mut init_idx := -1
	mut has_init_list := false
	mut init_items := []int{}
	if p.cur().kind == TokenKind.assign {
		p.advance()
		if p.cur().kind == TokenKind.lbrace {
			has_init_list = true
			got := p.parse_struct_init_items() or { return error(err.msg()) }
			for gi in got {
				init_items << gi
			}
		} else {
			init_idx = p.parse_expr() or { return error(err.msg()) }
		}
	}
	return VarDef{
		name:          name
		typ_name:      typ
		init_idx:      init_idx
		has_init_list: has_init_list
		init_items:    init_items
		is_const:      is_const
		array_len:     ''
		line:          ln
		order:         p.next_order()
	}
}

// cone 0.4：struct name{ member type / member type[count] ... }
// 换行不是语句终止符，成员靠 "name type" / "name type[count]" 的 token 结构断句。
fn (mut p Parser) parse_struct() !StructDef {
	ln := p.cur().line
	p.expect(TokenKind.kw_struct, 'struct') or { return error(err.msg()) }
	name := p.expect_ident('结构体名') or { return error(err.msg()) }
	p.struct_names << name
	// cone 0.9prelease：struct NAME align{...} —— 按 Windows ABI 对齐并生成 _padding_ 字段
	mut aligned := false
	if p.cur().kind == TokenKind.kw_align {
		p.advance()
		aligned = true
	}
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	mut members := []StructMember{}
	for p.cur().kind != TokenKind.rbrace {
		if p.cur().kind == TokenKind.eof {
			return error('第 ${ln} 行: 结构体 ${name} 缺少右花括号 }')
		}
		mln := p.cur().line
		mname := p.expect_ident('结构体成员名') or { return error(err.msg()) }
		typ := p.parse_type_name() or { return error(err.msg()) }
		mut arr := ''
		if p.cur().kind == TokenKind.lbracket {
			p.advance()
			cnt := p.expect_const_number('结构体数组成员长度') or { return error(err.msg()) }
			p.expect(TokenKind.rbracket, ']') or { return error(err.msg()) }
			arr = cnt
		}
		members << StructMember{
			name:      mname
			typ_name:  typ
			array_len: arr
			line:      mln
		}
	}
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
	if members.len == 0 {
		return error('第 ${ln} 行: 结构体 ${name} 至少要有一个成员（MASM32 不接受空 STRUCT）')
	}
	return StructDef{
		name:    name
		members: members
		aligned: aligned
		line:    ln
		order:   p.next_order()
	}
}

// parse_struct_init_items: 解析 ={...} 里的项；? 记 -1，其余按表达式解析。
fn (mut p Parser) parse_struct_init_items() ![]int {
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	mut items := []int{}
	if p.cur().kind != TokenKind.rbrace {
		for {
			if p.cur().kind == TokenKind.ident && p.cur().lit == '?' {
				p.advance()
				items << -1
			} else if p.cur().kind == TokenKind.string_lit {
				// cone 0.6：初始化项里的字符串按字节流原文内联，不当作字符常量
				st := p.advance()
				items << p.add_expr(new_expr(ExprKind.expr_str, st.lit, st.line))
			} else {
				it := p.parse_expr() or { return error(err.msg()) }
				items << it
			}
			if p.cur().kind != TokenKind.comma {
				break
			}
			p.advance()
		}
	}
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
	return items
}

fn (mut p Parser) parse_array_def() !VarDef {
	ln := p.cur().line
	name := p.expect_ident('数组名') or { return error(err.msg()) }
	typ := p.parse_type_name() or { return error(err.msg()) }
	p.expect(TokenKind.lbracket, '[') or { return error(err.msg()) }
	cnt := p.expect_const_number('数组长度') or { return error(err.msg()) }
	p.expect(TokenKind.rbracket, ']') or { return error(err.msg()) }
	return VarDef{
		name:          name
		typ_name:      typ
		init_idx:      -1
		has_init_list: false
		init_items:    []int{}
		is_const:      false
		array_len:     cnt
		line:          ln
		order:         p.next_order()
	}
}

// ---------- 表达式（递归下降 + 节点池） ----------

// cone 0.6 fix1 优先级（低 -> 高）：
//   || < && < | < ^ < & < 比较 < << >> < + - < * / < 一元(- + addr ~ !)
// 位运算用 | & ^ << >> ~；&& / || 仍是逻辑运算，只服务于条件表达式。
fn (mut p Parser) parse_expr() !int {
	return p.parse_or() or { return error(err.msg()) }
}

fn (mut p Parser) parse_or() !int {
	left := p.parse_land() or { return error(err.msg()) }
	mut a := left
	for p.cur().kind == TokenKind.or_or {
		p.advance()
		b := p.parse_land() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, '||', p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

fn (mut p Parser) parse_land() !int {
	left := p.parse_bor() or { return error(err.msg()) }
	mut a := left
	for p.cur().kind == TokenKind.and_and {
		p.advance()
		b := p.parse_bor() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, '&&', p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

fn (mut p Parser) parse_bor() !int {
	left := p.parse_bxor() or { return error(err.msg()) }
	mut a := left
	for p.cur().kind == TokenKind.pipe {
		p.advance()
		b := p.parse_bxor() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, '|', p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

fn (mut p Parser) parse_bxor() !int {
	left := p.parse_band() or { return error(err.msg()) }
	mut a := left
	for p.cur().kind == TokenKind.caret {
		p.advance()
		b := p.parse_band() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, '^', p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

fn (mut p Parser) parse_band() !int {
	left := p.parse_not() or { return error(err.msg()) }
	mut a := left
	for p.cur().kind == TokenKind.amp {
		p.advance()
		b := p.parse_not() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, '&', p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

// parse_not: 逻辑非独立成层；!a==b 解析成 !(a==b)，与 MASM `.if !(a==b)` 一致。
fn (mut p Parser) parse_not() !int {
	if p.cur().kind == TokenKind.bang {
		ln := p.cur().line
		p.advance()
		inner := p.parse_not() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_neg, '!', ln)
		e.a = inner
		return p.add_expr(e)
	}
	return p.parse_cmp() or { return error(err.msg()) }
}

fn (mut p Parser) parse_cmp() !int {
	left := p.parse_shift() or { return error(err.msg()) }
	mut a := left
	for is_cmp_kind(p.cur().kind) {
		op := p.advance().lit
		b := p.parse_shift() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, op, p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

fn (mut p Parser) parse_shift() !int {
	left := p.parse_add() or { return error(err.msg()) }
	mut a := left
	for p.cur().kind == TokenKind.shl || p.cur().kind == TokenKind.shr {
		op := p.advance().lit
		b := p.parse_add() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, op, p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

fn (mut p Parser) parse_add() !int {
	left := p.parse_term() or { return error(err.msg()) }
	mut a := left
	for p.cur().kind == TokenKind.plus || p.cur().kind == TokenKind.minus {
		op := p.advance().lit
		b := p.parse_term() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, op, p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

fn (mut p Parser) parse_term() !int {
	left := p.parse_unary() or { return error(err.msg()) }
	mut a := left
	for p.cur().kind == TokenKind.star || p.cur().kind == TokenKind.slash || p.cur().kind == TokenKind.percent {
		op := p.advance().lit
		b := p.parse_unary() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_bin, op, p.cur().line)
		e.a = a
		e.b = b
		a = p.add_expr(e)
	}
	return a
}

fn (mut p Parser) parse_unary() !int {
	ln := p.cur().line
	if p.cur().kind == TokenKind.minus {
		p.advance()
		inner := p.parse_unary() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_neg, '-', ln)
		e.a = inner
		return p.add_expr(e)
	}
	if p.cur().kind == TokenKind.plus {
		p.advance()
		r := p.parse_unary() or { return error(err.msg()) }
		return r
	}
	if p.cur().kind == TokenKind.kw_addr {
		p.advance()
		inner := p.parse_unary() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_addr, 'addr', ln)
		e.a = inner
		return p.add_expr(e)
	}
	if p.cur().kind == TokenKind.tilde {
		p.advance()
		inner := p.parse_unary() or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_neg, '~', ln)
		e.a = inner
		return p.add_expr(e)
	}
	r := p.parse_primary() or { return error(err.msg()) }
	return r
}

// parse_incdec: cone 0.6 fix1 的 ++ / -- 语句。
// 只接受寄存器 / 变量 / 结构体成员 / [] 内存作左值，直接生成 inc / dec。
fn (mut p Parser) parse_incdec(idx int, ln int) !Stmt {
	k := p.cur().kind
	p.advance()
	ek := p.exprs[idx].kind
	if ek != ExprKind.expr_ident && ek != ExprKind.expr_member && ek != ExprKind.expr_deref {
		return error('第 ${ln} 行: ++/-- 只能作用于寄存器 / 变量 / 结构体成员 / [] 内存，不能作用于 ${describe_expr(p.exprs, idx)}')
	}
	mut s := new_stmt(StmtKind.st_inc, ln)
	if k == TokenKind.minus_minus {
		s = new_stmt(StmtKind.st_dec, ln)
	}
	s.target_idx = idx
	return s
}

// cone 0.6 fix2：pos 是调用名 token 在最终展开流里的绝对位置。
// 「调用必须在声明之后」改用位置比较，不再用源码行号（import 展开后库内行号没有可比性）。
fn (mut p Parser) parse_call_tail(full string, ln int, pos int) !int {
	p.expect(TokenKind.lparen, '(') or { return error(err.msg()) }
	mut args := []int{}
	if p.cur().kind != TokenKind.rparen {
		for {
			a := p.parse_expr() or { return error(err.msg()) }
			args << a
			if p.cur().kind != TokenKind.comma {
				break
			}
			p.advance()
		}
	}
	p.expect(TokenKind.rparen, ')') or { return error(err.msg()) }
	mut e := new_expr(ExprKind.expr_call, full, ln)
	e.pos = pos
	e.args = args
	return p.add_expr(e)
}

// cone 0.6：尝试把 `Type{...}` 解析成结构体常量。
// 成功返回节点索引；失败（例如其实是 if/match 的 `{` 块起始）回滚 pos 返回 -1，
// 让调用方按普通标识符继续解析。结构体常量复用 expr_ident 形态：text 是去重键，
// lit_type / lit_items 保存类型与初值，codegen 据键生成 __cone_stt_N 隐名标签。
fn (mut p Parser) try_struct_lit(type_name string, ln int) int {
	save := p.pos
	items := p.parse_struct_init_items() or {
		p.pos = save
		return -1
	}
	mut lit := []int{}
	for it in items {
		lit << it
	}
	key := struct_lit_key(type_name, lit, p.exprs)
	mut e := new_expr(ExprKind.expr_ident, key, ln)
	e.is_win_sym = true // 隐名标签不在 cone 符号表里，跳过符号定义检查
	e.is_struct_lit = true
	e.lit_type = type_name
	e.lit_items = lit
	return p.add_expr(e)
}

fn (mut p Parser) parse_primary() !int {
	t := p.cur()
	ln := t.line
	start_pos := p.pos // cone 0.6 fix2：调用名 token 的绝对位置（顺序检查用）

	if t.kind == TokenKind.kw_unsigned || t.kind == TokenKind.kw_signed {
		return error('第 ${ln} 行: unsigned / signed 只能写在 condition 前面（if / elseif / for 的条件前，例如 `if signed x>9{`），不能出现在表达式内部')
	}
	// cone 0.9prelease：sizeof(xxx) 编译期字节数，视为立即数（analyzer 折叠成 expr_num）。
	if t.kind == TokenKind.kw_sizeof {
		p.advance()
		p.expect(TokenKind.lparen, '(') or { return error(err.msg()) }
		mut nm := ''
		if p.cur().kind == TokenKind.kw_win {
			p.advance()
			p.expect(TokenKind.dot, '.') or { return error(err.msg()) }
			nm = 'win.' + p.cur().lit
			p.advance()
		} else {
			nm = p.cur().lit
			p.advance()
		}
		for p.cur().kind == TokenKind.dot {
			p.advance()
			nm = nm + '.' + p.cur().lit
			p.advance()
		}
		p.expect(TokenKind.rparen, ')') or { return error(err.msg()) }
		return p.add_expr(new_expr(ExprKind.expr_sizeof, nm, ln))
	}
	if t.kind == TokenKind.kw_align {
		return error('第 ${ln} 行: align 只能写在 struct 定义的结构体名之后（struct NAME align{ ... }）')
	}
	// cone 0.6：float(expr) —— 不新增节点种类，复制内部节点并打 is_float_hint 标记。
	// 这样所有既有 ExprKind 分派逻辑天然兼容，只有浮点求值器与参数渲染需要识别它。
	if t.kind == TokenKind.kw_float {
		p.advance()
		p.expect(TokenKind.lparen, '(') or { return error(err.msg()) }
		inner := p.parse_expr() or { return error(err.msg()) }
		p.expect(TokenKind.rparen, ')') or { return error(err.msg()) }
		mut fe := p.exprs[inner]
		fe.is_float_hint = true
		return p.add_expr(fe)
	}
	if t.kind == TokenKind.number {
		p.advance()
		return p.add_expr(new_expr(ExprKind.expr_num, t.lit, ln))
	}
	if t.kind == TokenKind.dollar {
		p.advance()
		return p.add_expr(new_expr(ExprKind.expr_num, '$', ln))
	}
	if t.kind == TokenKind.string_lit {
		p.advance()
		// 表达式位置的字符串 = 字符常量：支持转义、默认补 0、进 .const、值为地址。
		// 数据定义 label:"..." 走 parse_str_def，不设这个标记，仍是"字节流无转义"。
		mut e := new_expr(ExprKind.expr_str, t.lit, ln)
		e.is_char_const = true
		return p.add_expr(e)
	}
	// cone 0.3：寄存器是保留特殊标识符，作为 expr_ident(is_reg=true) 进入表达式。
	// 它可出现在赋值右值、调用参数、[] 地址表达式与算术表达式里。
	if t.kind == TokenKind.reg {
		name := p.advance().lit
		mut e := new_expr(ExprKind.expr_ident, name, ln)
		e.is_reg = true
		return p.add_expr(e)
	}
	// [] 内存访问：cone 0.3 完善版与 MASM32 一致，生成 type ptr [addr]。
	// 开头可带尺寸词，按字面生成 xxx ptr；不写尺寸词就是 dword ptr。
	if t.kind == TokenKind.lbracket {
		p.advance()
		mut size_word := ''
		st := p.cur()
		if is_ptr_size_kw(st.kind) {
			size_word = p.advance().lit
		} else if st.kind == TokenKind.reserved && is_masm_size_word(st.lit) {
			size_word = p.advance().lit
		}
		inner := p.parse_expr() or { return error(err.msg()) }
		p.expect(TokenKind.rbracket, ']') or { return error(err.msg()) }
		mut e := new_expr(ExprKind.expr_deref, '[]', ln)
		e.a = inner
		e.ptr_size = size_word
		return p.add_expr(e)
	}
	if t.kind == TokenKind.lparen {
		p.advance()
		e := p.parse_expr() or { return error(err.msg()) }
		p.expect(TokenKind.rparen, ')') or { return error(err.msg()) }
		return e
	}
	if t.kind == TokenKind.kw_win {
		p.advance()
		p.expect(TokenKind.dot, '.') or { return error(err.msg()) }
		fname := p.expect_ident('win. 后的符号名') or { return error(err.msg()) }
		// cone 0.4 fix：win.RECT.left 这类多级点链是"外部结构体字段偏移"，
		// 生成时去掉 win. 前缀输出 RECT.left；成员名交给 MASM32 校验。
		mut rest := ''
		mut wdots := 0
		for p.cur().kind == TokenKind.dot {
			p.advance()
			part := p.expect_ident('外部结构体成员名') or { return error(err.msg()) }
			if wdots > 0 {
				rest = rest + '.'
			}
			rest = rest + part
			wdots = wdots + 1
		}
		if p.cur().kind == TokenKind.lparen {
			if wdots != 0 {
				return error('第 ${ln} 行: win. 调用只支持 `win.函数(...)` 一级点号；win.${fname}.${rest}(...) 不是合法调用')
			}
			return p.parse_call_tail('win.' + fname, ln, start_pos)
		}
		// cone 0.6：win.Type{...} = MASM32 侧外部结构体的结构体常量
		if p.cur().kind == TokenKind.lbrace && wdots == 0 && !p.no_struct_lit {
			si := p.try_struct_lit('win.' + fname, ln)
			if si >= 0 {
				return si
			}
		}
		if wdots > 0 {
			mut e := new_expr(ExprKind.expr_member, 'win.' + fname + '.' + rest, ln)
			e.member_base = 'win.' + fname
			e.member_path = rest
			e.is_win_sym = true
			return p.add_expr(e)
		}
		// cone 0.3：win.XXX 不跟 ( 就是 MASM 侧已定义的宏常量 / 变量引用。
		mut e := new_expr(ExprKind.expr_ident, fname, ln)
		e.is_win_sym = true
		return p.add_expr(e)
	}
	if t.kind == TokenKind.ident {
		name := p.advance().lit
		// cone 0.6：Type{...} 结构体常量（仅对已声明的 cone 结构体名成立，
		// 避免与 if x{ / match x{ / for x{ 的块起始花括号冲突；解析失败会回滚）
		if name in p.struct_names && p.cur().kind == TokenKind.lbrace && !p.no_struct_lit {
			si := p.try_struct_lit(name, ln)
			if si >= 0 {
				return si
			}
		}
		// cone 0.6 fix3：win{...} 登记的名字也能写结构体常量 NAME{...}，
		// 与 win.NAME{...} 完全等价（同一个去重键 / 同一份外部结构体类型）。
		// cone struct 同名时上面已优先；解析失败同样回滚，不吃掉块的 {。
		if name in p.win_names && !(name in p.struct_names) && p.cur().kind == TokenKind.lbrace && !p.no_struct_lit {
			si := p.try_struct_lit('win.' + name, ln)
			if si >= 0 {
				return si
			}
		}
		mut path := ''
		mut dots := 0
		for p.cur().kind == TokenKind.dot {
			p.advance()
			part := p.expect_ident('成员名 / 函数名') or { return error(err.msg()) }
			if dots > 0 {
				path = path + '.'
			}
			path = path + part
			dots = dots + 1
		}
		if p.cur().kind == TokenKind.lparen {
			// dots=0 -> 自定义函数调用 f(...)；dots=1 -> 模块调用 mod.f(...)
			if dots > 1 {
				return error('第 ${ln} 行: 函数调用最多支持一级点号（模块.函数）；${name}.${path}(...) 不是合法调用')
			}
			if dots == 1 {
				return p.parse_call_tail(name + '.' + path, ln, start_pos)
			}
			return p.parse_call_tail(name, ln, start_pos)
		}
		if dots > 0 {
			// cone 0.4：a.b / a.b.c = 结构体成员访问；若 a 是结构体类型名，
			// 则整体是 MASM 的字段偏移常量（只用在 [] 地址表达式里）。
			// cone 0.6 fix3：win{...} 登记的名字等价于 win.NAME.field，
			// 用同一套节点形态，输出时去掉 win. 前缀。
			if name in p.win_names && !(name in p.struct_names) {
				mut e := new_expr(ExprKind.expr_member, 'win.' + name + '.' + path, ln)
				e.member_base = 'win.' + name
				e.member_path = path
				e.is_win_sym = true
				return p.add_expr(e)
			}
			mut e := new_expr(ExprKind.expr_member, name + '.' + path, ln)
			e.member_base = name
			e.member_path = path
			return p.add_expr(e)
		}
		return p.add_expr(new_expr(ExprKind.expr_ident, name, ln))
	}
	if t.kind == TokenKind.reserved {
		return error('第 ${ln} 行: `${t.lit}` 是 MASM32 保留标识符（指令 / 伪指令 / 属性 / 运算符），不能作为 cone 表达式里的标识符')
	}
	return error('第 ${ln} 行: 表达式中出现非法 token ${t.desc()}')
}

// cone 0.6 fix2：win{ 标识符1 标识符2 ... } —— 批量登记 MASM 侧已定义符号。
// 块内只接受裸标识符（可用逗号或换行分隔），等价于给每个名字写了一次 win.名字。
// 纯声明块，不生成任何 MASM 代码；名字全文件生效，不参与「先声明后调用」顺序检查。
fn (mut p Parser) parse_win_block() !WinBlockDecl {
	ln := p.cur().line
	p.expect(TokenKind.kw_win, 'win') or { return error(err.msg()) }
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	mut names := []string{}
	mut seen := map[string]bool{}
	for p.cur().kind != TokenKind.rbrace {
		if p.cur().kind == TokenKind.eof {
			return error('第 ${ln} 行: win{...} 缺少右花括号 }（块内只能写标识符，逗号 / 换行分隔）')
		}
		if p.cur().kind == TokenKind.comma {
			p.advance()
			continue
		}
		t := p.cur()
		if t.kind == TokenKind.reg || t.kind == TokenKind.reserved {
			return error('第 ${t.line} 行: win{...} 里的 `${t.lit}` 是寄存器 / MASM32 保留标识符，不能登记为 win 符号')
		}
		if t.kind != TokenKind.ident {
			return error('第 ${t.line} 行: win{...} 里只能写标识符，实际得到 ${t.desc()}；单条形式仍写 win.名字')
		}
		p.advance()
		if t.lit in seen {
			return error('第 ${t.line} 行: win{...} 块里标识符 ${t.lit} 重复登记')
		}
		seen[t.lit] = true
		names << t.lit
		if !(t.lit in p.win_names) {
			p.win_names << t.lit
		}
	}
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
	return WinBlockDecl{
		names: names
		line:  ln
		order: p.next_order()
	}
}

// ---------- 函数体 ----------

fn (mut p Parser) parse_def_params() ![]Param {
	mut ps := []Param{}
	if p.cur().kind == TokenKind.rparen {
		return ps
	}
	for {
		ln := p.cur().line
		if p.cur().kind == TokenKind.colon && p.pos + 1 < p.toks.len
			&& p.toks[p.pos + 1].kind == TokenKind.ident
			&& eq_ci(p.toks[p.pos + 1].lit, 'vararg') {
			return error('第 ${ln} 行: def 不支持 :vararg；只有 func 声明可写，且必须是最后一项')
		}
		name := p.expect_ident('形参名') or { return error(err.msg()) }
		p.expect(TokenKind.colon, ':') or { return error(err.msg()) }
		if p.cur().kind == TokenKind.ident && eq_ci(p.cur().lit, 'vararg') {
			return error('第 ${ln} 行: def 不支持 :vararg；只有 func 声明可写，且必须是最后一项')
		}
		typ := p.parse_type_name() or { return error(err.msg()) }
		ps << Param{
			name:     name
			typ_name: typ
			line:     ln
		}
		if p.cur().kind != TokenKind.comma {
			break
		}
		p.advance()
	}
	return ps
}

fn (mut p Parser) parse_return() !Stmt {
	r := p.expect(TokenKind.kw_return, 'return') or { return error(err.msg()) }
	if !is_expr_start(p.cur().kind) {
		return error('第 ${r.line} 行: return 必须带一个表达式（cone 0.2 完善版起不支持空 return，以避免与后续语句的解析歧义）；例如 `return 0`。当前后面是 ${p.cur().desc()}')
	}
	idx := p.parse_expr() or { return error(err.msg()) }
	mut s := new_stmt(StmtKind.st_return, r.line)
	s.ret_idx = idx
	return s
}

// cone 0.7：局部变量声明支持初值（多字节数组除外）。
//   int a=1, b=2, c        -> 并行数组 local_inits = [idx1, idx2, -1]
// 初值表达式沿用完整的 parse_expr，声明所在位置发射赋值（执行到此处才初始化）。
fn (mut p Parser) parse_local() !Stmt {
	ln := p.cur().line
	typ := p.parse_type_name() or { return error(err.msg()) }
	mut names := []string{}
	mut inits := []int{}
	for {
		names << p.expect_ident('局部变量名') or { return error(err.msg()) }
		mut init := -1
		if p.cur().kind == TokenKind.assign {
			p.advance()
			if !is_expr_start(p.cur().kind) {
				return error('第 ${ln} 行: 局部变量初值需要一个表达式，实际得到 ${p.cur().desc()}')
			}
			init = p.parse_expr() or { return error(err.msg()) }
		}
		inits << init
		if p.cur().kind != TokenKind.comma {
			break
		}
		p.advance()
	}
	mut s := new_stmt(StmtKind.st_local, ln)
	s.local_names = names
	s.local_type = typ
	s.local_inits = inits
	return s
}

fn (mut p Parser) parse_local_array() !Stmt {
	ln := p.cur().line
	name := p.expect_ident('局部数组名') or { return error(err.msg()) }
	typ := p.parse_type_name() or { return error(err.msg()) }
	p.expect(TokenKind.lbracket, '[') or { return error(err.msg()) }
	cnt := p.expect_const_number('局部数组长度') or { return error(err.msg()) }
	p.expect(TokenKind.rbracket, ']') or { return error(err.msg()) }
	// cone 0.7：局部数组不支持初值（局部变量初值只支持标量）。
	if p.cur().kind == TokenKind.assign {
		return error('第 ${ln} 行: 局部数组不支持初始化；cone 0.7 起局部变量初值只支持标量，请先声明数组再逐项赋值')
	}
	mut s := new_stmt(StmtKind.st_local, ln)
	mut names := []string{}
	names << name
	s.local_names = names
	s.local_type = typ
	s.local_array_len = cnt
	mut no_init := []int{}
	no_init << -1
	s.local_inits = no_init
	return s
}

fn (mut p Parser) parse_assign() !Stmt {
	ln := p.cur().line
	mut lhs := ''
	if p.cur().kind == TokenKind.reg {
		// cone 0.3：reg=imm/reg/mem -> mov reg,imm/reg/mem
		lhs = p.advance().lit
	} else {
		lhs = p.expect_ident('赋值目标') or { return error(err.msg()) }
	}
	p.expect(TokenKind.assign, '=') or { return error(err.msg()) }
	rhs := p.parse_expr() or { return error(err.msg()) }
	mut s := new_stmt(StmtKind.st_assign, ln)
	s.lhs = lhs
	s.rhs_idx = rhs
	return s
}

// exprs_has_call_node: 表达式节点池里是否含函数调用节点（parser 阶段用，不依赖完整 Program）。
fn exprs_has_call_node(exprs []Expr, idx int) bool {
	if idx < 0 || idx >= exprs.len {
		return false
	}
	e := exprs[idx]
	if e.kind == ExprKind.expr_call {
		return true
	}
	if e.kind == ExprKind.expr_neg || e.kind == ExprKind.expr_addr || e.kind == ExprKind.expr_deref {
		return exprs_has_call_node(exprs, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		return exprs_has_call_node(exprs, e.a) || exprs_has_call_node(exprs, e.b)
	}
	return false
}

// cond_need_degrade: 条件里是否含 MASM `.if` 表达式无法直接写出的成分。
// 函数调用 / addr / 字符常量，以及 [] 地址里含调用（渲染时会偷偷发 invoke），
// 都会让整条 if 链降级成 cone 自己算 eax + 显式标签跳转，保证 elseif 也正确。
//
// cone 0.7：比较 / 逻辑之外的运算（+ - * / 与位运算）MASM `.if / .while` 只会在
// 汇编期对【常量】求值；遇到运行时变量 `i*i` / `i/n` 会生成 `.if (i*i)<123`
// 这种非法展开。因此凡含算术 / 位运算的条件一律降级，由 cone 自己发 imul /
// idiv 等计算指令 + 显式 cmp + jcc；只有简单条件才保留几乎原样的 MASM 伪指令。
fn cond_need_degrade(exprs []Expr, idx int) bool {
	if idx < 0 || idx >= exprs.len {
		return false
	}
	e := exprs[idx]
	if e.kind == ExprKind.expr_call || e.kind == ExprKind.expr_addr || e.kind == ExprKind.expr_str {
		return true
	}
	if e.kind == ExprKind.expr_deref {
		return exprs_has_call_node(exprs, e.a)
	}
	if e.kind == ExprKind.expr_neg {
		// 一元 ! 是 MASM 逻辑非，放行；- / ~ 作用在变量上要 cone 自己发 neg/not。
		if e.text == '-' || e.text == '~' {
			if e.a < 0 || e.a >= exprs.len || exprs[e.a].kind != ExprKind.expr_num {
				return true
			}
		}
		return cond_need_degrade(exprs, e.a)
	}
	if e.kind == ExprKind.expr_bin {
		// 只有比较 / 逻辑能直接交给 MASM .if；其余运算一律降级。
		if !is_cond_op(e.text) {
			return true
		}
		return cond_need_degrade(exprs, e.a) || cond_need_degrade(exprs, e.b)
	}
	return false
}

// IfBranch: 解析 if 链时的临时分支（cond = -1 表示 else）。
// 放在 parser 内部而不是 Stmt 里，避免 Stmt 与自身递归嵌套。
struct IfBranch {
	cond int
	sign int // 0=默认无符号 1=unsigned 2=signed
	body []Stmt
}

// parse_cond_prefix: condition 前可选的无符号 / 有符号前缀。
// 返回 0=默认（无符号）、1=unsigned（与默认等价）、2=signed（有符号）。
// MASM .if / .while 的比较默认就是无符号，所以只有 signed 需要 cone 自己显式发 jcc。
fn (mut p Parser) parse_cond_prefix() !int {
	if p.cur().kind == TokenKind.kw_unsigned {
		p.advance()
		return 1
	}
	if p.cur().kind == TokenKind.kw_signed {
		p.advance()
		return 2
	}
	return 0
}

// parse_for_chain: for [unsigned] condition{ body } 或 for{ body }（无条件循环）。
// 摊平成 st_for, <body...>, st_endfor；break / continue 由 parse_stmt_list 用
// loop_depth 校验只能出现在循环体内，codegen 再用循环标签栈生成跳转。
fn (mut p Parser) parse_for_chain() ![]Stmt {
	ln := p.cur().line
	p.expect(TokenKind.kw_for, 'for') or { return error(err.msg()) }
	sign := p.parse_cond_prefix() or { return error(err.msg()) }
	mut cond := -1
	mut forever := false
	if p.cur().kind == TokenKind.lbrace {
		if sign != 0 {
			return error('第 ${ln} 行: unsigned / signed 必须修饰一个条件表达式；无条件循环写 `for{ ... }`，不能写 `for unsigned{` / `for signed{`')
		}
		forever = true
	} else {
		if !is_expr_start(p.cur().kind) {
			return error('第 ${ln} 行: for 后面必须是条件表达式或直接 {（无条件循环），实际得到 ${p.cur().desc()}')
		}
		cond = p.parse_expr() or { return error(err.msg()) }
	}
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	p.loop_depth = p.loop_depth + 1
	body := p.parse_stmt_list(false) or { return error(err.msg()) }
	p.loop_depth = p.loop_depth - 1
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
	mut degraded := false
	if sign == 2 {
		degraded = true // MASM .while 做不到有符号比较
	}
	if cond >= 0 && cond_need_degrade(p.exprs, cond) {
		degraded = true
	}
	mut out := []Stmt{}
	mut first := new_stmt(StmtKind.st_for, ln)
	first.cond_idx = cond
	first.cond_unsigned = sign == 1
	first.cond_signed = sign == 2
	first.is_forever = forever
	first.degraded = degraded
	out << first
	for st in body {
		out << st
	}
	out << new_stmt(StmtKind.st_endfor, ln)
	return out
}

// parse_if_chain: 把 if / elseif / else 展开成一条【扁平的标记语句流】：
//   st_if, <then body...>, st_elseif, <body...>, st_else, <body...>, st_endif
// 嵌套 if 也自然摊平在同一列表里，codegen 用一个标签栈就能处理，不需要递归结构。
fn (mut p Parser) parse_if_chain() ![]Stmt {
	ln := p.cur().line
	p.expect(TokenKind.kw_if, 'if') or { return error(err.msg()) }
	sg0 := p.parse_cond_prefix() or { return error(err.msg()) }
	if !is_expr_start(p.cur().kind) {
		return error('第 ${ln} 行: if 后面必须有一个条件表达式（例如 `if x==5{` / `if signed x>9{`），实际得到 ${p.cur().desc()}')
	}
	c0 := p.parse_expr() or { return error(err.msg()) }
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	b0 := p.parse_stmt_list(false) or { return error(err.msg()) }
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
	mut branches := []IfBranch{}
	branches << IfBranch{cond: c0, sign: sg0, body: b0}

	for p.cur().kind == TokenKind.kw_elseif {
		eln := p.cur().line
		p.advance()
		esg := p.parse_cond_prefix() or { return error(err.msg()) }
		if !is_expr_start(p.cur().kind) {
			return error('第 ${eln} 行: elseif 后面必须有一个条件表达式，实际得到 ${p.cur().desc()}')
		}
		c := p.parse_expr() or { return error(err.msg()) }
		p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
		b := p.parse_stmt_list(false) or { return error(err.msg()) }
		p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
		branches << IfBranch{cond: c, sign: esg, body: b}
	}
	if p.cur().kind == TokenKind.kw_else {
		p.advance()
		p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
		b := p.parse_stmt_list(false) or { return error(err.msg()) }
		p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
		branches << IfBranch{cond: -1, sign: 0, body: b}
	}

	mut degraded := false
	for br in branches {
		if br.cond >= 0 && br.sign == 2 {
			degraded = true // MASM .if 做不到有符号比较，整条链走显式 cmp+jcc
		}
		if br.cond >= 0 && cond_need_degrade(p.exprs, br.cond) {
			degraded = true
		}
	}

	mut out := []Stmt{}
	mut first := new_stmt(StmtKind.st_if, ln)
	first.cond_idx = branches[0].cond
	first.cond_unsigned = branches[0].sign == 1
	first.cond_signed = branches[0].sign == 2
	first.degraded = degraded
	out << first
	for st in branches[0].body {
		out << st
	}
	mut bi := 1
	for bi < branches.len {
		br := branches[bi]
		if br.cond < 0 {
			out << new_stmt(StmtKind.st_else, ln)
		} else {
			mut es := new_stmt(StmtKind.st_elseif, ln)
			es.cond_idx = br.cond
			es.cond_unsigned = br.sign == 1
			es.cond_signed = br.sign == 2
			es.degraded = degraded
			out << es
		}
		for st in br.body {
			out << st
		}
		bi = bi + 1
	}
	out << new_stmt(StmtKind.st_endif, ln)
	return out
}

// parse_stmt_list: 解析到 } 为止（不消费 }）。函数体与 if 分支体共用。
// cone 0.83：判断当前 token 是否是 seg 段内的「段级声明」形态
// （数据定义 / 函数定义）。不是声明就按段内裸代码语句解析。
fn (mut p Parser) seg_is_decl() bool {
	t := p.cur()
	if t.kind == TokenKind.kw_def || t.kind == TokenKind.kw_const {
		return true
	}
	if t.kind == TokenKind.kw_win && p.peek(1).kind == TokenKind.dot {
		return true
	}
	if is_type_kw(t.kind) {
		return true
	}
	if t.kind == TokenKind.ident {
		nk := p.peek(1).kind
		if nk == TokenKind.colon {
			return true // fmt:"..." 字符串数据定义
		}
		if is_type_kw(nk) || nk == TokenKind.ident || nk == TokenKind.reserved {
			return true // 结构体类型 / 内置类型开头的变量定义或数组定义
		}
	}
	return false
}

fn (mut p Parser) parse_seg_stmt_list() ![]Stmt {
	mut body := []Stmt{}
	for p.cur().kind != TokenKind.rbrace {
		if p.cur().kind == TokenKind.eof {
			return error('第 ${p.cur().line} 行: 缺少右花括号 }（seg 段未闭合）')
		}
		// cone 0.83：遇到段级声明（数据定义 / def）就结束这一段裸代码，
		// 交回 parse_seg 处理，保证段内单元严格保持源码顺序。
		if p.seg_is_decl() {
			break
		}
		// cone 0.6 fix1：reg++ / reg-- / ident++ / ident--
		if p.cur().kind == TokenKind.reg || p.cur().kind == TokenKind.ident {
			inc_nk := p.peek(1).kind
			if inc_nk == TokenKind.plus_plus || inc_nk == TokenKind.minus_minus {
				inc_ln := p.cur().line
				inc_tok := p.cur()
				p.advance()
				mut inc_expr := new_expr(ExprKind.expr_ident, inc_tok.lit, inc_ln)
				if inc_tok.kind == TokenKind.reg {
					inc_expr.is_reg = true
				}
				inc_idx := p.add_expr(inc_expr)
				inc_st := p.parse_incdec(inc_idx, inc_ln) or { return error(err.msg()) }
				body << inc_st
				continue
			}
		}
		if p.cur().kind == TokenKind.kw_end {
			return error('第 ${p.cur().line} 行: end 是顶层入口声明，不能写在函数体内')
		}
		if p.cur().kind == TokenKind.kw_include {
			return error('第 ${p.cur().line} 行: include 只能在顶层声明（它生成 masm32 的 include/includelib）')
		}
		if p.cur().kind == TokenKind.kw_import {
			return error('第 ${p.cur().line} 行: import 只能在顶层声明')
		}
		if p.cur().kind == TokenKind.kw_elseif {
			return error('第 ${p.cur().line} 行: elseif 必须紧跟在 if 或另一个 elseif 的 } 之后，不能单独出现')
		}
		if p.cur().kind == TokenKind.kw_else {
			return error('第 ${p.cur().line} 行: else 必须紧跟在 if / elseif 的 } 之后，不能单独出现')
		}
		if p.cur().kind == TokenKind.kw_unsigned || p.cur().kind == TokenKind.kw_signed {
			return error('第 ${p.cur().line} 行: unsigned / signed 只能写在 condition 前面（if / elseif / for 的条件前，例如 `if signed x>9{`），不能作为语句')
		}
		if p.cur().kind == TokenKind.kw_if {
			chunk := p.parse_if_chain() or { return error(err.msg()) }
			for st in chunk {
				body << st
			}
			continue
		}
		// cone 0.7：try{...} except[...]{...}（Windows x86 栈式 SEH）
		if p.cur().kind == TokenKind.kw_try {
			chunk := p.parse_try_chain() or { return error(err.msg()) }
			for st in chunk {
				body << st
			}
			continue
		}
		if p.cur().kind == TokenKind.kw_except {
			return error('第 ${p.cur().line} 行: except 必须紧跟在 try 或另一个 except 的 } 之后，不能单独出现；cone 0.7 的 try/except 采用 Windows x86 栈式 SEH')
		}
		if p.cur().kind == TokenKind.kw_match {
			chunk := p.parse_match_chain() or { return error(err.msg()) }
			for st in chunk {
				body << st
			}
			continue
		}
		if p.cur().kind == TokenKind.kw_default {
			return error('第 ${p.cur().line} 行: default 只能写在 match 的分支位置（match xxx{ ... default{} }）')
		}
		if p.cur().kind == TokenKind.kw_for {
			chunk := p.parse_for_chain() or { return error(err.msg()) }
			for st in chunk {
				body << st
			}
			continue
		}
		if p.cur().kind == TokenKind.kw_break {
			ln := p.cur().line
			if p.loop_depth == 0 {
				return error('第 ${ln} 行: break 只能出现在 for 循环体内（当前不在任何循环中）')
			}
			p.advance()
			body << new_stmt(StmtKind.st_break, ln)
			continue
		}
		if p.cur().kind == TokenKind.kw_continue {
			ln := p.cur().line
			if p.loop_depth == 0 {
				return error('第 ${ln} 行: continue 只能出现在 for 循环体内（当前不在任何循环中）')
			}
			p.advance()
			body << new_stmt(StmtKind.st_continue, ln)
			continue
		}
		if p.cur().kind == TokenKind.kw_return {
			r := p.parse_return() or { return error(err.msg()) }
			body << r
			continue
		}
		// cone 0.9preview：asm64{...} 内嵌 x64 指令（analyzer 预编译成 db 行）。
		if p.cur().kind == TokenKind.kw_asm64 {
			ln := p.cur().line
			p.advance()
			bt := p.expect(TokenKind.asm_body, 'asm64{...} 的正文') or { return error(err.msg()) }
			mut a := new_stmt(StmtKind.st_asm64, ln)
			a.asm_text = bt.lit
			body << a
			continue
		}
		// cone 0.4 fix2：asm{...} 内嵌汇编。lexer 已把 {...} 正文收成单个
		// asm_body token，这里只取原文，语义层校验 %标识符，codegen 原样输出。
		if p.cur().kind == TokenKind.kw_asm {
			ln := p.cur().line
			p.advance()
			bt := p.expect(TokenKind.asm_body, 'asm{...} 的汇编正文（asm 后面必须跟 `{`）') or { return error(err.msg()) }
			mut a := new_stmt(StmtKind.st_asm, ln)
			a.asm_text = bt.lit
			body << a
			continue
		}
		// cone 0.6 fix2：函数体内也能写 win{...}（登记为全局 win 符号，不生成代码）
		if p.cur().kind == TokenKind.kw_win && p.peek(1).kind == TokenKind.lbrace {
			p.parse_win_block() or { return error(err.msg()) }
			continue
		}
		// cone 0.4 fix：win.XXX 作类型的局部结构体变量声明（win.RECT r）
		if p.cur().kind == TokenKind.kw_win && p.peek(1).kind == TokenKind.dot && p.peek(2).kind == TokenKind.ident && p.peek(3).kind == TokenKind.ident {
			l := p.parse_local() or { return error(err.msg()) }
			body << l
			continue
		}
		if p.cur().kind == TokenKind.kw_const {
			return error('第 ${p.cur().line} 行: 函数体内暂不支持 const 局部声明')
		}
		if is_type_kw(p.cur().kind) {
			l := p.parse_local() or { return error(err.msg()) }
			body << l
			continue
		}
		// cone 0.3：寄存器作左值 reg = expr
		if p.cur().kind == TokenKind.reg && p.peek(1).kind == TokenKind.assign {
			a := p.parse_assign() or { return error(err.msg()) }
			body << a
			continue
		}
		// [] 解引用作左值：[type xxx+imm] = expr / [type xxx+xxx*imm+imm] = expr
		if p.cur().kind == TokenKind.lbracket {
			lline := p.cur().line
			lidx := p.parse_primary() or { return error(err.msg()) }
			if p.exprs[lidx].kind != ExprKind.expr_deref {
				return error('第 ${lline} 行: 内部错误，[ 开头没有解析成解引用节点')
			}
			if p.cur().kind == TokenKind.plus_plus || p.cur().kind == TokenKind.minus_minus {
				st := p.parse_incdec(lidx, lline) or { return error(err.msg()) }
				body << st
				continue
			}
			p.expect(TokenKind.assign, '=') or {
				return error('第 ${lline} 行: [] 解引用作左值后面必须跟 =（形如 `[byte fmt]=1`）；单独的 [] 解引用不能作语句，也不能参与更复杂的左值表达式')
			}
			rhs := p.parse_expr() or { return error(err.msg()) }
			mut s := new_stmt(StmtKind.st_assign, lline)
			s.lhs_idx = lidx
			s.rhs_idx = rhs
			body << s
			continue
		}
		if p.cur().kind == TokenKind.ident {
			nk := p.peek(1).kind
			if nk == TokenKind.dot {
				// cone 0.4：arg1.y=5 是结构体成员左值；os.print(...) 仍是调用语句。
				lline := p.cur().line
				lidx := p.parse_primary() or { return error(err.msg()) }
				lk := p.exprs[lidx].kind
				if lk == ExprKind.expr_call {
					mut cs := new_stmt(StmtKind.st_call, lline)
					cs.call_idx = lidx
					body << cs
					continue
				}
				if lk != ExprKind.expr_member {
					return error('第 ${lline} 行: 带点号的语句只能是结构体成员赋值（如 `st.x=5`）或模块函数调用')
				}
				if p.cur().kind == TokenKind.plus_plus || p.cur().kind == TokenKind.minus_minus {
					st := p.parse_incdec(lidx, lline) or { return error(err.msg()) }
					body << st
					continue
				}
				p.expect(TokenKind.assign, '=') or {
					return error('第 ${lline} 行: 结构体成员 ${p.exprs[lidx].text} 作左值后面必须跟 =（形如 `st.x=5`）；单独的成员访问不是合法语句')
				}
				rhs := p.parse_expr() or { return error(err.msg()) }
				mut s := new_stmt(StmtKind.st_assign, lline)
				s.lhs_idx = lidx
				s.rhs_idx = rhs
				body << s
				continue
			}
			if nk == TokenKind.kw_equ {
				return error('第 ${p.cur().line} 行: equ 常量只能在顶层定义（MASM 的 equ 是汇编期全局符号）')
			}
			if nk == TokenKind.colon {
				d := p.parse_str_def(false) or { return error(err.msg()) }
				p.data << d
				continue
			}
			if nk == TokenKind.assign {
				a := p.parse_assign() or { return error(err.msg()) }
				body << a
				continue
			}
			k2 := p.peek(2).kind
			if k2 == TokenKind.lbracket {
				la := p.parse_local_array() or { return error(err.msg()) }
				body << la
				continue
			}
			// cone 0.4：局部结构体变量 `ttt x`（结构体名也是合法类型名）
			if nk == TokenKind.ident {
				l := p.parse_local() or { return error(err.msg()) }
				body << l
				continue
			}
		}
		start_tok := p.cur()
		idx := p.parse_expr() or { return error(err.msg()) }
		if p.exprs[idx].kind != ExprKind.expr_call {
			if p.cur().kind == TokenKind.assign {
				return error('第 ${start_tok.line} 行: 赋值目标必须是标识符（全局变量 / 局部变量 / 形参），实际是 ${describe_expr(p.exprs, idx)}；cone 不允许立即数、字面量或表达式做目的操作数（如 `2=z`）。请检查是否写反了左右两边')
			}
			return error('第 ${start_tok.line} 行: 单独的 ${describe_expr(p.exprs, idx)} 不是合法语句；函数体内只支持 `return <表达式>` / 局部声明 / 局部数组 / 字符串定义 / 赋值 / 调用语句 / if 链（表达式语句必须是函数调用）')
		}
		mut s := new_stmt(StmtKind.st_call, p.exprs[idx].line)
		s.call_idx = idx
		body << s
	}
	return body
}

// cone 0.5：顶层 asm{...} —— 正文原样透传，按源码 order 在头部区输出。
fn (mut p Parser) parse_stmt_list(stop_at_except bool) ![]Stmt {
	mut body := []Stmt{}
	for p.cur().kind != TokenKind.rbrace {
		if p.cur().kind == TokenKind.eof {
			return error('第 ${p.cur().line} 行: 缺少右花括号 }（函数体或 if 分支未闭合）')
		}
		// cone 0.84：解析 try} 与 except 之间的间隔语句时，遇到 except 立即收尾，
		// 不把它当「孤立 except」报错。函数体 / 分支体传 false，行为不变。
		if stop_at_except && p.cur().kind == TokenKind.kw_except {
			break
		}
		// cone 0.6 fix1：reg++ / reg-- / ident++ / ident--
		if p.cur().kind == TokenKind.reg || p.cur().kind == TokenKind.ident {
			inc_nk := p.peek(1).kind
			if inc_nk == TokenKind.plus_plus || inc_nk == TokenKind.minus_minus {
				inc_ln := p.cur().line
				inc_tok := p.cur()
				p.advance()
				mut inc_expr := new_expr(ExprKind.expr_ident, inc_tok.lit, inc_ln)
				if inc_tok.kind == TokenKind.reg {
					inc_expr.is_reg = true
				}
				inc_idx := p.add_expr(inc_expr)
				inc_st := p.parse_incdec(inc_idx, inc_ln) or { return error(err.msg()) }
				body << inc_st
				continue
			}
		}
		if p.cur().kind == TokenKind.kw_end {
			return error('第 ${p.cur().line} 行: end 是顶层入口声明，不能写在函数体内')
		}
		if p.cur().kind == TokenKind.kw_include {
			return error('第 ${p.cur().line} 行: include 只能在顶层声明（它生成 masm32 的 include/includelib）')
		}
		if p.cur().kind == TokenKind.kw_import {
			return error('第 ${p.cur().line} 行: import 只能在顶层声明')
		}
		if p.cur().kind == TokenKind.kw_elseif {
			return error('第 ${p.cur().line} 行: elseif 必须紧跟在 if 或另一个 elseif 的 } 之后，不能单独出现')
		}
		if p.cur().kind == TokenKind.kw_else {
			return error('第 ${p.cur().line} 行: else 必须紧跟在 if / elseif 的 } 之后，不能单独出现')
		}
		if p.cur().kind == TokenKind.kw_unsigned || p.cur().kind == TokenKind.kw_signed {
			return error('第 ${p.cur().line} 行: unsigned / signed 只能写在 condition 前面（if / elseif / for 的条件前，例如 `if signed x>9{`），不能作为语句')
		}
		if p.cur().kind == TokenKind.kw_if {
			chunk := p.parse_if_chain() or { return error(err.msg()) }
			for st in chunk {
				body << st
			}
			continue
		}
		// cone 0.7：try{...} except[...]{...}（Windows x86 栈式 SEH）
		if p.cur().kind == TokenKind.kw_try {
			chunk := p.parse_try_chain() or { return error(err.msg()) }
			for st in chunk {
				body << st
			}
			continue
		}
		if p.cur().kind == TokenKind.kw_except {
			return error('第 ${p.cur().line} 行: except 必须紧跟在 try 或另一个 except 的 } 之后，不能单独出现；cone 0.7 的 try/except 采用 Windows x86 栈式 SEH')
		}
		if p.cur().kind == TokenKind.kw_match {
			chunk := p.parse_match_chain() or { return error(err.msg()) }
			for st in chunk {
				body << st
			}
			continue
		}
		if p.cur().kind == TokenKind.kw_default {
			return error('第 ${p.cur().line} 行: default 只能写在 match 的分支位置（match xxx{ ... default{} }）')
		}
		if p.cur().kind == TokenKind.kw_for {
			chunk := p.parse_for_chain() or { return error(err.msg()) }
			for st in chunk {
				body << st
			}
			continue
		}
		if p.cur().kind == TokenKind.kw_break {
			ln := p.cur().line
			if p.loop_depth == 0 {
				return error('第 ${ln} 行: break 只能出现在 for 循环体内（当前不在任何循环中）')
			}
			p.advance()
			body << new_stmt(StmtKind.st_break, ln)
			continue
		}
		if p.cur().kind == TokenKind.kw_continue {
			ln := p.cur().line
			if p.loop_depth == 0 {
				return error('第 ${ln} 行: continue 只能出现在 for 循环体内（当前不在任何循环中）')
			}
			p.advance()
			body << new_stmt(StmtKind.st_continue, ln)
			continue
		}
		if p.cur().kind == TokenKind.kw_return {
			r := p.parse_return() or { return error(err.msg()) }
			body << r
			continue
		}
		// cone 0.9preview：asm64{...} 内嵌 x64 指令（analyzer 预编译成 db 行）。
		if p.cur().kind == TokenKind.kw_asm64 {
			ln := p.cur().line
			p.advance()
			bt := p.expect(TokenKind.asm_body, 'asm64{...} 的正文') or { return error(err.msg()) }
			mut a := new_stmt(StmtKind.st_asm64, ln)
			a.asm_text = bt.lit
			body << a
			continue
		}
		// cone 0.4 fix2：asm{...} 内嵌汇编。lexer 已把 {...} 正文收成单个
		// asm_body token，这里只取原文，语义层校验 %标识符，codegen 原样输出。
		if p.cur().kind == TokenKind.kw_asm {
			ln := p.cur().line
			p.advance()
			bt := p.expect(TokenKind.asm_body, 'asm{...} 的汇编正文（asm 后面必须跟 `{`）') or { return error(err.msg()) }
			mut a := new_stmt(StmtKind.st_asm, ln)
			a.asm_text = bt.lit
			body << a
			continue
		}
		// cone 0.6 fix2：函数体内也能写 win{...}（登记为全局 win 符号，不生成代码）
		if p.cur().kind == TokenKind.kw_win && p.peek(1).kind == TokenKind.lbrace {
			p.parse_win_block() or { return error(err.msg()) }
			continue
		}
		// cone 0.4 fix：win.XXX 作类型的局部结构体变量声明（win.RECT r）
		if p.cur().kind == TokenKind.kw_win && p.peek(1).kind == TokenKind.dot && p.peek(2).kind == TokenKind.ident && p.peek(3).kind == TokenKind.ident {
			l := p.parse_local() or { return error(err.msg()) }
			body << l
			continue
		}
		if p.cur().kind == TokenKind.kw_const {
			return error('第 ${p.cur().line} 行: 函数体内暂不支持 const 局部声明')
		}
		if is_type_kw(p.cur().kind) {
			l := p.parse_local() or { return error(err.msg()) }
			body << l
			continue
		}
		// cone 0.3：寄存器作左值 reg = expr
		if p.cur().kind == TokenKind.reg && p.peek(1).kind == TokenKind.assign {
			a := p.parse_assign() or { return error(err.msg()) }
			body << a
			continue
		}
		// [] 解引用作左值：[type xxx+imm] = expr / [type xxx+xxx*imm+imm] = expr
		if p.cur().kind == TokenKind.lbracket {
			lline := p.cur().line
			lidx := p.parse_primary() or { return error(err.msg()) }
			if p.exprs[lidx].kind != ExprKind.expr_deref {
				return error('第 ${lline} 行: 内部错误，[ 开头没有解析成解引用节点')
			}
			if p.cur().kind == TokenKind.plus_plus || p.cur().kind == TokenKind.minus_minus {
				st := p.parse_incdec(lidx, lline) or { return error(err.msg()) }
				body << st
				continue
			}
			p.expect(TokenKind.assign, '=') or {
				return error('第 ${lline} 行: [] 解引用作左值后面必须跟 =（形如 `[byte fmt]=1`）；单独的 [] 解引用不能作语句，也不能参与更复杂的左值表达式')
			}
			rhs := p.parse_expr() or { return error(err.msg()) }
			mut s := new_stmt(StmtKind.st_assign, lline)
			s.lhs_idx = lidx
			s.rhs_idx = rhs
			body << s
			continue
		}
		if p.cur().kind == TokenKind.ident {
			nk := p.peek(1).kind
			if nk == TokenKind.dot {
				// cone 0.4：arg1.y=5 是结构体成员左值；os.print(...) 仍是调用语句。
				lline := p.cur().line
				lidx := p.parse_primary() or { return error(err.msg()) }
				lk := p.exprs[lidx].kind
				if lk == ExprKind.expr_call {
					mut cs := new_stmt(StmtKind.st_call, lline)
					cs.call_idx = lidx
					body << cs
					continue
				}
				if lk != ExprKind.expr_member {
					return error('第 ${lline} 行: 带点号的语句只能是结构体成员赋值（如 `st.x=5`）或模块函数调用')
				}
				if p.cur().kind == TokenKind.plus_plus || p.cur().kind == TokenKind.minus_minus {
					st := p.parse_incdec(lidx, lline) or { return error(err.msg()) }
					body << st
					continue
				}
				p.expect(TokenKind.assign, '=') or {
					return error('第 ${lline} 行: 结构体成员 ${p.exprs[lidx].text} 作左值后面必须跟 =（形如 `st.x=5`）；单独的成员访问不是合法语句')
				}
				rhs := p.parse_expr() or { return error(err.msg()) }
				mut s := new_stmt(StmtKind.st_assign, lline)
				s.lhs_idx = lidx
				s.rhs_idx = rhs
				body << s
				continue
			}
			if nk == TokenKind.kw_equ {
				return error('第 ${p.cur().line} 行: equ 常量只能在顶层定义（MASM 的 equ 是汇编期全局符号）')
			}
			if nk == TokenKind.colon {
				d := p.parse_str_def(false) or { return error(err.msg()) }
				p.data << d
				continue
			}
			if nk == TokenKind.assign {
				a := p.parse_assign() or { return error(err.msg()) }
				body << a
				continue
			}
			k2 := p.peek(2).kind
			if k2 == TokenKind.lbracket {
				la := p.parse_local_array() or { return error(err.msg()) }
				body << la
				continue
			}
			// cone 0.4：局部结构体变量 `ttt x`（结构体名也是合法类型名）
			if nk == TokenKind.ident {
				l := p.parse_local() or { return error(err.msg()) }
				body << l
				continue
			}
		}
		start_tok := p.cur()
		idx := p.parse_expr() or { return error(err.msg()) }
		if p.exprs[idx].kind != ExprKind.expr_call {
			if p.cur().kind == TokenKind.assign {
				return error('第 ${start_tok.line} 行: 赋值目标必须是标识符（全局变量 / 局部变量 / 形参），实际是 ${describe_expr(p.exprs, idx)}；cone 不允许立即数、字面量或表达式做目的操作数（如 `2=z`）。请检查是否写反了左右两边')
			}
			return error('第 ${start_tok.line} 行: 单独的 ${describe_expr(p.exprs, idx)} 不是合法语句；函数体内只支持 `return <表达式>` / 局部声明 / 局部数组 / 字符串定义 / 赋值 / 调用语句 / if 链（表达式语句必须是函数调用）')
		}
		mut s := new_stmt(StmtKind.st_call, p.exprs[idx].line)
		s.call_idx = idx
		body << s
	}
	return body
}

// cone 0.5：顶层 asm{...} —— 正文原样透传，按源码 order 在头部区输出。
fn (mut p Parser) parse_top_asm() !AsmBlock {
	ln := p.cur().line
	p.expect(TokenKind.kw_asm, 'asm') or { return error(err.msg()) }
	bt := p.expect(TokenKind.asm_body, 'asm{...} 的汇编正文（asm 后面必须跟 `{`）') or { return error(err.msg()) }
	return AsmBlock{
		text:  bt.lit
		line:  ln
		order: p.next_order()
	}
}

// cone 0.9preview：顶层 asm64{...} —— x64 指令编码成 db 机器码，按源码 order 输出。
fn (mut p Parser) parse_top_asm64() !Asm64Block {
	ln := p.cur().line
	p.expect(TokenKind.kw_asm64, 'asm64') or { return error(err.msg()) }
	bt := p.expect(TokenKind.asm_body, 'asm64{...} 的正文') or { return error(err.msg()) }
	return Asm64Block{
		text:  bt.lit
		line:  ln
		order: p.next_order()
		lines: []string{}
	}
}

// cone 0.5：match 链摊平成标记流（与 if 链同一套风格）
// cone 0.7：try / except [ErrorType] —— Windows x86 栈式 SEH（fs:[0] 链）。
//   try { body } except [ErrorType] { body } ...
//   -> st_try / [try body...] / st_except(except_idx) / [body...] / ... / st_endtry
// except_idx = -1 表示不带 ErrorType，匹配所有错误码，且必须是最后一个分支。
// ErrorType 是错误码常量表达式（数值 / 数值 equ / win.MASM 常量 / 位运算）。
fn (mut p Parser) parse_try_chain() ![]Stmt {
	mut out := []Stmt{}
	ln := p.cur().line
	p.expect(TokenKind.kw_try, 'try') or { return error(err.msg()) }
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	mut ts := new_stmt(StmtKind.st_try, ln)
	tid := p.try_id
	p.try_id = p.try_id + 1
	ts.try_id = tid
	out << ts
	bdy := p.parse_stmt_list(false) or { return error(err.msg()) }
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
	for b in bdy {
		out << b
	}
	// cone 0.84：try} 与 except 之间允许夹普通语句（不能跨函数 / 跨段）。
	// 这些语句摊平进 st_try 与 st_except 之间，仍在 SEH 帧保护下、正常路径执行，
	// 异常时随 try 体一起被跳过。遇到 `}`（函数/段结束）或 eof 时下面的检查会报错。
	gap := p.parse_stmt_list(true) or { return error(err.msg()) }
	for b in gap {
		out << b
	}
	if p.cur().kind != TokenKind.kw_except {
		return error('第 ${p.cur().line} 行: try{...} 之后没有找到 except 分支（try 与 except 之间可以夹普通语句，但不能跨函数 / 跨段；cone 0.7 采用 Windows x86 栈式 SEH，不提供 finally）')
	}
	mut seen_catchall := false
	for p.cur().kind == TokenKind.kw_except {
		eln := p.cur().line
		if seen_catchall {
			return error('第 ${eln} 行: 不带 ErrorType 的 except{}（匹配所有错误码）必须是 try 链的最后一个分支，后面不能再写 except')
		}
		p.advance()
		mut es := new_stmt(StmtKind.st_except, eln)
		es.try_id = tid
		if p.cur().kind == TokenKind.lbrace {
			es.except_idx = -1
			seen_catchall = true
		} else {
			if !is_expr_start(p.cur().kind) {
				return error('第 ${eln} 行: except 后面要么直接跟 `{`（匹配所有错误码），要么写一个 ErrorType 错误码常量表达式，实际得到 ${p.cur().desc()}')
			}
			// ErrorType 后面紧跟语句块的 {，不能被误当成 Type{...} 结构体常量。
			p.no_struct_lit = true
			ci := p.parse_expr() or {
				p.no_struct_lit = false
				return error(err.msg())
			}
			p.no_struct_lit = false
			es.except_idx = ci
		}
		p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
		eb := p.parse_stmt_list(false) or { return error(err.msg()) }
		p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
		out << es
		for b in eb {
			out << b
		}
	}
	out << new_stmt(StmtKind.st_endtry, ln)
	return out
}

//   match expr { value1 { ... } value2 { ... } default { ... } }
//   -> st_match / [st_case, body..., st_case, body...] / [st_default, body...] / st_endmatch
fn (mut p Parser) parse_match_chain() ![]Stmt {
	mut out := []Stmt{}
	ln := p.cur().line
	p.expect(TokenKind.kw_match, 'match') or { return error(err.msg()) }
	if !is_expr_start(p.cur().kind) {
		return error('第 ${ln} 行: match 后面必须跟一个判别表达式，实际得到 ${p.cur().desc()}')
	}
	cond := p.parse_expr() or { return error(err.msg()) }
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	mut ms := new_stmt(StmtKind.st_match, ln)
	ms.cond_idx = cond
	out << ms
	mut branches := 0
	mut seen_default := false
	for p.cur().kind != TokenKind.rbrace {
		if p.cur().kind == TokenKind.eof {
			return error('第 ${ln} 行: match 缺少右花括号 }')
		}
		if seen_default {
			if p.cur().kind == TokenKind.kw_default {
				return error('第 ${p.cur().line} 行: match 里只能有一个 default 分支')
			}
			return error('第 ${p.cur().line} 行: default 必须是 match 的最后一个分支，后面不能再写 case')
		}
		bln := p.cur().line
		if p.cur().kind == TokenKind.kw_default {
			p.advance()
			mut ds := new_stmt(StmtKind.st_default, bln)
			seen_default = true
			p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
			bdy := p.parse_stmt_list(false) or { return error(err.msg()) }
			p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
			out << ds
			for b in bdy {
				out << b
			}
			branches = branches + 1
			continue
		}
		if !is_expr_start(p.cur().kind) {
			return error('第 ${bln} 行: match 分支需要 `值{}` 或 `default{}`，实际得到 ${p.cur().desc()}')
		}
		val := p.parse_expr() or { return error(err.msg()) }
		mut cs := new_stmt(StmtKind.st_case, bln)
		cs.case_idx = val
		p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
		bdy := p.parse_stmt_list(false) or { return error(err.msg()) }
		p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
		out << cs
		for b in bdy {
			out << b
		}
		branches = branches + 1
	}
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
	if branches == 0 {
		return error('第 ${ln} 行: match 至少要有一个 case 或 default 分支')
	}
	out << new_stmt(StmtKind.st_endmatch, ln)
	return out
}

// cone 0.83：seg "名字"{ ... } 特殊段。
// 段内单元严格按源码顺序收进 items：数据定义（si_var）、裸代码语句（si_stmt）、
// 函数定义（si_func）。段内数据/函数同时由 program() 追加到全局 vars/funcs
// （打上 in_seg 标记），以便 analyzer 照常登记符号、但 codegen 不重复生成。
fn (mut p Parser) parse_seg() !SegDef {
	ln := p.cur().line
	p.expect(TokenKind.kw_seg, 'seg') or { return error(err.msg()) }
	nt := p.expect(TokenKind.string_lit, '段名字符串（例如 seg ".fuck"{...}）') or { return error(err.msg()) }
	name := nt.text
	if name.len == 0 {
		return error('第 ${ln} 行: seg 的段名不能为空')
	}
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	mut items := []SegItem{}
	for p.cur().kind != TokenKind.rbrace {
		if p.cur().kind == TokenKind.eof {
			return error('第 ${ln} 行: seg "${name}" 缺少右花括号 }')
		}
		t := p.cur()
		if t.kind == TokenKind.kw_def {
			f := p.parse_func() or { return error(err.msg()) }
			items << SegItem{kind: SegItemKind.si_func, func_def: f}
			continue
		}
		// 段内数据定义：VarDef 形态（标量 / 数组 / const 修饰的字符串除外）。
		if t.kind == TokenKind.kw_const {
			if p.peek(1).kind == TokenKind.ident && p.peek(2).kind == TokenKind.colon {
				return error('第 ${t.line} 行: seg 段内暂不支持 `名字:"..."` 字符串数据定义；请写成 `byte 名字[N]` 或放到 seg 外作全局字符串')
			}
			v := p.parse_var_def(true) or { return error(err.msg()) }
			items << SegItem{kind: SegItemKind.si_var, var_def: v}
			continue
		}
		if is_type_kw(t.kind) || (t.kind == TokenKind.kw_win && p.peek(1).kind == TokenKind.dot) {
			v := p.parse_var_def(false) or { return error(err.msg()) }
			items << SegItem{kind: SegItemKind.si_var, var_def: v}
			continue
		}
		if t.kind == TokenKind.ident {
			nk := p.peek(1).kind
			if nk == TokenKind.colon {
				return error('第 ${t.line} 行: seg 段内暂不支持 `名字:"..."` 字符串数据定义；请写成 `byte 名字[N]` 或放到 seg 外作全局字符串')
			}
			if is_type_kw(nk) || nk == TokenKind.ident || nk == TokenKind.reserved {
				if p.peek(2).kind == TokenKind.lbracket {
					v := p.parse_array_def() or { return error(err.msg()) }
					items << SegItem{kind: SegItemKind.si_var, var_def: v}
				} else {
					v := p.parse_var_def(false) or { return error(err.msg()) }
					items << SegItem{kind: SegItemKind.si_var, var_def: v}
				}
				continue
			}
		}
		// 其余按段内裸代码语句解析，直到遇到下一个段级声明或 }
		chunk := p.parse_seg_stmt_list() or { return error(err.msg()) }
		if chunk.len > 0 {
			items << SegItem{kind: SegItemKind.si_stmt, stmts: chunk}
		}
	}
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }
	return SegDef{
		name:  name
		items: items
		line:  ln
		order: p.next_order()
	}
}

// cone 0.83：defined 宏函数（无 exitm）。
// defined m(p1:req,p2:vararg){ 原样汇编正文 } -> m macro ... / 正文 / m endm
fn (mut p Parser) parse_macro_def() !MacroDef {
	ln := p.cur().line
	p.expect(TokenKind.kw_defined, 'defined') or { return error(err.msg()) }
	name := p.expect_ident('宏名') or { return error(err.msg()) }
	p.expect(TokenKind.lparen, '(') or { return error(err.msg()) }
	mut params := []MacroParam{}
	if p.cur().kind != TokenKind.rparen {
		for p.cur().kind != TokenKind.rparen {
			if p.cur().kind == TokenKind.eof {
				return error('第 ${ln} 行: 宏 ${name} 的形参列表缺少右括号 )')
			}
			pn := p.expect_ident('宏形参名') or { return error(err.msg()) }
			mut rest := ''
			if p.cur().kind == TokenKind.colon {
				p.advance()
				rt := p.expect_ident('宏形参修饰符（只允许 :req / :vararg）') or { return error(err.msg()) }
				if !eq_ci(rt, 'req') && !eq_ci(rt, 'vararg') {
					return error('第 ${ln} 行: 宏 ${name} 的形参 ${pn} 修饰符只能是 :req 或 :vararg，实际得到 :${rt}')
				}
				rest = rt
			}
			params << MacroParam{name: pn, restraint: rest}
			if p.cur().kind == TokenKind.comma {
				p.advance()
				continue
			}
			break
		}
	}
	p.expect(TokenKind.rparen, ')') or { return error(err.msg()) }
	bt := p.expect(TokenKind.asm_body, '宏体 {...}（defined 后必须跟 { 正文 }）') or { return error(err.msg()) }
	return MacroDef{
		name:   name
		params: params
		body:   bt.lit
		line:   ln
		order:  p.next_order()
	}
}

fn (mut p Parser) parse_func() !FuncDef {
	ln := p.cur().line
	fl := p.cur().file // cone 0.9.3：来源文件
	pos := p.pos // cone 0.6 fix2：def 起始 token 位置（顺序检查用）
	p.expect(TokenKind.kw_def, 'def') or { return error(err.msg()) }
	name := p.expect_ident('函数名') or { return error(err.msg()) }
	p.expect(TokenKind.lparen, '(') or { return error(err.msg()) }
	params := p.parse_def_params() or { return error(err.msg()) }
	p.expect(TokenKind.rparen, ')') or { return error(err.msg()) }
	mods := p.parse_modifiers() or { return error(err.msg()) }
	rt := p.parse_ret_type(ln) or { return error(err.msg()) }
	p.expect(TokenKind.lbrace, '{') or { return error(err.msg()) }
	body := p.parse_stmt_list(false) or { return error(err.msg()) }
	p.expect(TokenKind.rbrace, '}') or { return error(err.msg()) }

	return FuncDef{
		name:      name
		params:    params
		conv:      mods.conv
		body:      body
		line:      ln
		pos:       pos
		is_export: mods.is_export
		order:     p.next_order()
		ret_type:  rt
		file:      fl
	}
}

// parse: 阶段 3 —— 语法分析
fn parse(toks []Token) !Program {
	mut p := Parser{
		toks:          toks
		pos:           0
		exprs:         []Expr{}
		data:          []DataDef{}
		order:         0
		loop_depth:    0
		struct_names:  []string{}
		win_names:     prescan_win_names(toks)
		typedef_names: []string{}
		equ_values:    prescan_folded_equs(toks)
		try_id:        0
		no_struct_lit: false
	}
	mut imports := []ImportDecl{}
	mut includes := []IncludeDecl{}
	mut equs := []EquDecl{}
	mut typedefs := []TypedefDecl{}
	mut protos := []ProtoDecl{}
	mut structs := []StructDef{}
	mut vars := []VarDef{}
	mut funcs := []FuncDef{}
	mut asms := []AsmBlock{}
	mut win_blocks := []WinBlockDecl{}
	mut compile_args := []string{}
	mut link_args := []string{}
	mut segs := []SegDef{}
	mut macros := []MacroDef{}
	mut asm64s := []Asm64Block{}
	mut entry := ''
	mut has_entry := false

	for p.cur().kind != TokenKind.eof {
		t := p.cur()
		if t.kind == TokenKind.kw_import {
			imp := p.parse_import() or { return error(err.msg()) }
			imports << imp
		} else if t.kind == TokenKind.kw_include {
			inc := p.parse_include() or { return error(err.msg()) }
			includes << inc
		} else if t.kind == TokenKind.kw_typedef {
			td := p.parse_typedef() or { return error(err.msg()) }
			typedefs << td
		} else if t.kind == TokenKind.kw_struct {
			sd := p.parse_struct() or { return error(err.msg()) }
			structs << sd
		} else if t.kind == TokenKind.kw_func {
			pr := p.parse_proto(false) or { return error(err.msg()) }
			protos << pr
		} else if t.kind == TokenKind.kw_efunc {
			pr := p.parse_proto(true) or { return error(err.msg()) }
			protos << pr
		} else if t.kind == TokenKind.kw_def {
			f := p.parse_func() or { return error(err.msg()) }
			funcs << f
		} else if t.kind == TokenKind.kw_asm {
			ab := p.parse_top_asm() or { return error(err.msg()) }
			asms << ab
		} else if t.kind == TokenKind.kw_asm64 {
			ab := p.parse_top_asm64() or { return error(err.msg()) }
			asm64s << ab
		} else if t.kind == TokenKind.kw_seg {
			sg := p.parse_seg() or { return error(err.msg()) }
			for it in sg.items {
				if it.kind == SegItemKind.si_var {
					mut v := it.var_def
					v.in_seg = sg.name
					vars << v
				} else if it.kind == SegItemKind.si_func {
					mut f := it.func_def
					f.in_seg = sg.name
					funcs << f
				}
			}
			segs << sg
		} else if t.kind == TokenKind.kw_defined {
			m := p.parse_macro_def() or { return error(err.msg()) }
			macros << m
		} else if t.kind == TokenKind.kw_compile_arg || t.kind == TokenKind.kw_link_arg {
			// cone 0.8prelease：__compile__ "..." / __link__ "..." 只收集参数文本，
			// 引号由 lexer 去掉（Token.text），不生成任何 MASM 输出。
			p.advance()
			argtok := p.expect(TokenKind.string_lit, '附加参数字符串（例如 __compile__ "/Zi /Fl"）') or { return error(err.msg()) }
			if t.kind == TokenKind.kw_compile_arg {
				compile_args << argtok.text
			} else {
				link_args << argtok.text
			}
		} else if t.kind == TokenKind.kw_float {
			return error('第 ${t.line} 行: float(...) 是表达式运算符，只能写在函数体内（右值 / 参数 / return / 条件），不能作为顶层声明')
		} else if t.kind == TokenKind.kw_align || t.kind == TokenKind.kw_sizeof {
			return error('第 ${t.line} 行: ${t.lit} 不是顶层声明（align 只能写在 struct 定义里，sizeof(...) 是表达式立即数')
		} else if t.kind == TokenKind.kw_match || t.kind == TokenKind.kw_default || t.kind == TokenKind.kw_export {
			return error('第 ${t.line} 行: ${t.lit} 只能写在函数体内 / 函数声明的定义修饰符位置，不能作为顶层声明')
		} else if t.kind == TokenKind.kw_if || t.kind == TokenKind.kw_elseif || t.kind == TokenKind.kw_else {
			return error('第 ${t.line} 行: ${t.lit} 只能写在函数体内（cone 的 if / elseif / else 是语句，不是顶层声明）')
		} else if t.kind == TokenKind.kw_for || t.kind == TokenKind.kw_break || t.kind == TokenKind.kw_continue || t.kind == TokenKind.kw_unsigned || t.kind == TokenKind.kw_signed {
			return error('第 ${t.line} 行: ${t.lit} 只能写在函数体内（for / break / continue 是循环语句，unsigned / signed 只能修饰 condition）')
		} else if t.kind == TokenKind.kw_try || t.kind == TokenKind.kw_except {
			return error('第 ${t.line} 行: ${t.lit} 只能写在函数体内（cone 0.7 的 try/except 是 SEH 语句，不是顶层声明）')
		} else if t.kind == TokenKind.kw_end {
			p.advance()
			name := p.expect_ident('入口函数名') or { return error(err.msg()) }
			if has_entry {
				return error('第 ${t.line} 行: end 入口声明重复（已有 end ${entry}）')
			}
			entry = name
			has_entry = true
		} else if t.kind == TokenKind.kw_win && p.peek(1).kind == TokenKind.lbrace {
			// cone 0.6 fix2：win{ 标识符... } 批量声明（纯声明，不生成代码）
			wb := p.parse_win_block() or { return error(err.msg()) }
			win_blocks << wb
		} else if t.kind == TokenKind.kw_win && p.peek(1).kind == TokenKind.dot {
			v := p.parse_var_def(false) or { return error(err.msg()) }
			vars << v
		} else if t.kind == TokenKind.kw_const {
			// cone 0.5：const 修饰的字符串数据定义 `const fmt:"...",0dh,0ah,0` -> .const 段
			if p.peek(1).kind == TokenKind.ident && p.peek(2).kind == TokenKind.colon {
				d := p.parse_str_def(true) or { return error(err.msg()) }
				p.data << d
			} else {
				v := p.parse_var_def(true) or { return error(err.msg()) }
				vars << v
			}
		} else if is_type_kw(t.kind) {
			v := p.parse_var_def(false) or { return error(err.msg()) }
			vars << v
		} else if t.kind == TokenKind.reserved {
			return error('顶层不允许出现 MASM32 保留标识符 ${t.desc()}（指令 / 寄存器 / 伪指令名不能作为 cone 标识符）')
		} else if t.kind == TokenKind.ident {
			nk := p.peek(1).kind
			if nk == TokenKind.colon {
				d := p.parse_str_def(false) or { return error(err.msg()) }
				p.data << d
			} else if nk == TokenKind.kw_equ {
				eq := p.parse_equ_def() or { return error(err.msg()) }
				equs << eq
			} else if nk == TokenKind.assign {
				return error('第 ${t.line} 行: 顶层不允许赋值语句（赋值只能写在函数体内）；实际得到 ${t.lit}=...')
			} else if is_type_kw(nk) || nk == TokenKind.ident || nk == TokenKind.reserved {
				if p.peek(2).kind == TokenKind.lbracket {
					v := p.parse_array_def() or { return error(err.msg()) }
					vars << v
				} else {
					v := p.parse_var_def(false) or { return error(err.msg()) }
					vars << v
				}
			} else {
				return error('顶层不允许出现 ${t.desc()} 后跟该 token（只接受 import / include / equ / typedef / struct / func / 数据定义 / 数组定义 / def / end）')
			}
		} else {
			return error('顶层不允许出现 ${t.desc()}（只接受 import / include / equ / typedef / struct / func / 数据定义 / 数组定义 / def / end）')
		}
	}

	// cone 0.7：数值 equ 在 cone 侧展开成立即数（不再输出 MASM equ 伪指令）。
	// 放在全部解析完成后统一做：此时能拿到完整的局部 / 形参名，若某函数里声明了
	// 与 equ 同名的局部变量，保守跳过该名字（MASM PROC 内局部名优先，cone 侧也
	// 保持「局部遮蔽全局」），避免把变量误替换成数字。
	if p.equ_values.len > 0 {
		mut protected := map[string]bool{}
		for f in funcs {
			for pm in f.params {
				if pm.name.len > 0 {
					protected[pm.name] = true
				}
			}
			for s in f.body {
				if s.kind == StmtKind.st_local {
					for n in s.local_names {
						protected[n] = true
					}
				}
			}
		}
		mut ei := 0
		for ei < p.exprs.len {
			mut ex := p.exprs[ei]
			if ex.kind == ExprKind.expr_ident && !ex.is_reg && !ex.is_win_sym && !ex.is_struct_lit {
				nm := ex.text
				if (nm in p.equ_values) && !(nm in protected) {
					ex.kind = ExprKind.expr_num
					ex.text = p.equ_values[nm]
					p.exprs[ei] = ex
				}
			}
			ei = ei + 1
		}
		mut qi := 0
		for qi < equs.len {
			if equs[qi].name in p.equ_values {
				equs[qi].is_folded = true
				equs[qi].folded_text = p.equ_values[equs[qi].name]
			}
			qi = qi + 1
		}
	}

	// cone 0.6 fix2：win{...} 里登记的裸名字，在表达式里等价于 win.名字。
	// 放在全部解析完成后回填，这样「块写在文件后面」也能生效；cone 自己定义的
	// 全局 / 局部 / 形参名优先，保持原有行为不变（不会被误当成 MASM 侧符号）。
	if p.win_names.len > 0 {
		mut cone_names := map[string]bool{}
		// cone 0.7：fuck 是编译器预定义的异常码变量，不能被 win{} 回填标成 win 符号。
		cone_names['fuck'] = true
		for d in p.data {
			cone_names[d.name] = true
		}
		for v in vars {
			cone_names[v.name] = true
		}
		for eq in equs {
			cone_names[eq.name] = true
		}
		for td in typedefs {
			cone_names[td.name] = true
		}
		for pr in protos {
			cone_names[pr.name] = true
		}
		for sd in structs {
			cone_names[sd.name] = true
		}
		for f in funcs {
			cone_names[f.name] = true
			for pm in f.params {
				if pm.name.len > 0 {
					cone_names[pm.name] = true
				}
			}
			for stx in f.body {
				if stx.kind == StmtKind.st_local {
					for n in stx.local_names {
						cone_names[n] = true
					}
				}
			}
		}
		mut ei := 0
		for ei < p.exprs.len {
			mut ex := p.exprs[ei]
			if ex.kind == ExprKind.expr_ident && !ex.is_reg && !ex.is_win_sym && !ex.is_struct_lit {
				if ex.text in p.win_names && !(ex.text in cone_names) {
					ex.is_win_sym = true
					p.exprs[ei] = ex
				}
			}
			ei = ei + 1
		}
	}

	mut folded := map[string]string{}
	for ek, ev in p.equ_values {
		folded[ek] = ev
	}

	return Program{
		imports:    imports
		includes:   includes
		equs:       equs
		typedefs:   typedefs
		structs:    structs
		protos:     protos
		data:       p.data
		vars:       vars
		funcs:      funcs
		entry:      entry
		has_entry:  has_entry
		exprs:      p.exprs
		asms:       asms
		win_blocks:  win_blocks
		win_names:   p.win_names.clone()
		folded_equs: folded
		compile_args: compile_args
		link_args:    link_args
		segs:         segs
		macros:       macros
		asm64s:       asm64s
	}
}
