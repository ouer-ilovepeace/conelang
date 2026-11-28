module main

// ---------- 枚举 ----------

enum ImportKind {
	ik_cone // import os      -> 源码级展开 os.cone
	ik_dll  // import os.dll  -> includelib os.lib
}

enum CallConv {
	cc_default // 未写调用约定，沿用 .model flat, stdcall
	cc_stdcall
	cc_c
}

enum Section {
	sec_const
	sec_data
	sec_data_uninit
}

enum ExprKind {
	expr_num
	expr_str
	expr_ident
	expr_neg
	expr_bin
	expr_call
	expr_addr
	expr_deref // [expr] 解引用；a 指向"地址表达式"节点
	expr_member // cone 0.4：结构体成员访问 a.b.c / 结构体类型名.成员（字段偏移）
	expr_sizeof // cone 0.9prelease：sizeof(xxx) 编译期立即数（text = 名字/点链）
}

enum StmtKind {
	st_return
	st_local
	st_assign
	st_call
	st_if      // if 条件；flat 标记流，与 st_elseif / st_else / st_endif 配对
	st_elseif
	st_else
	st_endif
	st_for     // for 循环：flat 标记流，与 st_endfor 配对
	st_endfor
	st_break
	st_continue
	st_asm      // cone 0.4 fix2：asm{...} 内嵌汇编
	st_asm64    // cone 0.9preview：asm64{...} 内嵌 x64 指令（编码成 db 机器码）
	st_match    // cone 0.5：match 开始（cond_idx = 判别表达式）
	st_case     // cone 0.5：case 分支（case_idx = 分支值表达式）
	st_default  // cone 0.5：default 分支
	st_endmatch // cone 0.5：match 结束
	st_inc      // cone 0.6 fix1：++ 语句
	st_dec      // cone 0.6 fix1：-- 语句
	st_try      // cone 0.7：SEH 保护块开始（flat 标记流，与 st_except / st_endtry 配对）
	st_except   // cone 0.7：异常处理分支（except_idx = 错误码表达式，-1 = 通配）
	st_endtry   // cone 0.7：try 链结束
}

// ---------- 顶层声明 ----------

struct ImportDecl {
	module_name string
	kind        ImportKind
	lib_name    string // os.dll -> os.lib
	line        int
	order       int
}

// IncludeDecl: cone 0.8prelease 的 include 三种形态。
//   include xxx       -> inc_file='xxx.inc', lib_file='xxx.lib'
//   include xxx.yyy   -> inc_file='xxx.yyy', lib_file=''
//   include xxx.lib   -> inc_file='',        lib_file='xxx.lib'
// name 是源码里写出的完整名字（无后缀时就是 xxx），用于去重 / 保留字校验 / 模块前缀。
struct IncludeDecl {
	name     string
	inc_file string // 空串 = 不生成 include 行
	lib_file string // 空串 = 不生成 includelib 行
	line     int
	order    int
}

// EquDecl: 两种形态都直接对应 MASM32 的 equ
//   NAME equ xxx        -> items 解析成表达式，原样拼接输出（不加括号）
//   NAME equ <xxx>      -> is_raw=true，raw_text 为尖括号内部原文，整段透传
struct EquDecl {
mut:
	name         string
	items        []int
	is_raw       bool
	raw_text     string
	line         int
	pos          int    // cone 0.6 fix2：声明起始 token 在最终展开流中的位置（顺序检查用）
	order        int
	is_folded    bool   // cone 0.7：cone 侧求值成单个立即数，不再输出 MASM equ 行
	folded_text  string // cone 0.7：展开后的立即数文本（如 '0C0000005h' / '7'）
}

// WinBlockDecl: cone 0.6 fix2 —— win{ 标识符... } 批量声明。
// 块内每个名字等价于写了一次 win.名字：cone 侧不查符号表，生成时原样输出。
// 这是纯声明块，不生成任何 MASM 代码；名字全文件生效（不看行号）。
struct WinBlockDecl {
	names []string
	line  int
	order int
}

struct TypedefDecl {
	name           string // 新类型名，如 void
	base_type_name string // 底层类型名，如 int
	line           int
	order          int // cone 0.6：顶层源码顺序（asm 原位插入用）
}

// ---------- cone 0.4：结构体 ----------
// struct name{ memberName type / memberName type[count] ... }
// 成员类型可以是内置类型、typedef 别名，或另一个结构体（嵌套）。
struct StructMember {
mut:
	name      string
	typ_name  string
	array_len string // 非空 -> name type count dup(?)
	line      int
}

struct StructDef {
mut:
	name    string
	members []StructMember
	aligned bool // cone 0.9prelease：struct NAME align{...}，按 Windows ABI 对齐
	line    int
	order   int // cone 0.6：顶层源码顺序
}

// Param: name 可为空（func print(:void) 形参名省略，同 MASM PROTO）
struct Param {
	name     string
	typ_name string // cone 里写的类型名：内置关键字或 typedef 别名
	line     int
}

struct ProtoDecl {
	name      string
	params    []Param
	conv      CallConv
	line      int
	pos       int // cone 0.6 fix2：声明起始 token 位置（顺序检查用）
	is_export bool // cone 0.5：MASM32 EXPORT 属性
	order     int  // cone 0.6：顶层源码顺序
	ret_type  string // cone 0.9.1：可选返回类型
	file      string // cone 0.9.3：来源文件（诊断定位）
	is_external bool // cone 0.9.3：efunc 只在 cone 侧登记，不生成 MASM PROTO
}

// DataDef: hello:"hello world!",0,0,-11,0dh,0ah
struct DataDef {
	name     string
	items    []int
	line     int
	order    int
	is_const bool // cone 0.5：const fmt:"..." -> .const 段
}

struct VarDef {
mut:
	name          string
	typ_name      string
	init_idx      int  // -1 表示无初值；标量初值
	has_init_list bool // cone 0.4：结构体变量写了 ={...}
	init_items    []int // 结构体初始化项；-1 表示该位置是 ?
	is_const      bool
	array_len     string // 非空表示数组，原样写进 dup(?) 前
	line          int
	order         int
	in_seg        string // cone 0.83：非空 = 属于该特殊段，不进常规 .data/.data?/.const 段
}

// ---------- 函数与语句 ----------

// 注意：Stmt / Expr 的字段会被 parser 就地改写，整块字段必须放在 mut: 域里
// （V 0.5.1 实机编译验证过的写法）。
struct Stmt {
mut:
	kind            StmtKind
	line            int
	ret_idx         int    // st_return 的表达式索引；cone 0.2 完善版起必定 >= 0
	lhs             string // st_assign 左值（标识符）
	lhs_idx         int    // st_assign 左值是 [] 解引用时指向 expr_deref 节点，-1 = 用 lhs 字符串
	rhs_idx         int    // st_assign 右值
	call_idx        int    // st_call
	cond_idx        int    // st_if / st_elseif / st_for 的条件表达式索引
	cond_unsigned   bool   // condition 前有 unsigned：无符号（默认即无符号，显式写等价）
	cond_signed     bool   // condition 前有 signed：该条件的比较按有符号生成
	is_forever      bool   // st_for：for{} 无条件循环
	degraded        bool   // 条件链 / 循环是否含 MASM .if / .while 无法表达的成分
	local_names     []string
	local_type      string
	local_array_len string // 非空 -> 局部数组，生成 local name[N]:TYPE
	local_inits     []int  // cone 0.7：与 local_names 并行的初值表达式索引，-1 = 无初值（数组恒为 -1）
	asm_text        string // st_asm 的正文原文（%标识符 在 codegen 里替换成修饰后的 MASM 名）
	asm64_lines     []string // cone 0.9preview：st_asm64 预编译出的 MASM db 行
	case_idx        int    // st_case 的分支值表达式索引
	target_idx      int    // cone 0.6 fix1：st_inc / st_dec 的目标左值表达式索引
	except_idx      int    // cone 0.7：st_except 的 ErrorType 表达式索引，-1 = 匹配所有错误码
	try_id          int    // cone 0.7：st_try 的函数内编号（生成唯一 SEH 标签）
}

fn new_stmt(k StmtKind, line int) Stmt {
	return Stmt{
		kind:            k
		line:            line
		ret_idx:         -1
		lhs:             ''
		lhs_idx:         -1
		rhs_idx:         -1
		call_idx:        -1
		cond_idx:        -1
		cond_unsigned:   false
		cond_signed:     false
		is_forever:      false
		degraded:        false
		local_names:     []string{}
		local_type:      ''
		local_array_len: ''
		local_inits:     []int{}
		asm_text:        ''
		case_idx:        -1
		target_idx:      -1
		except_idx:      -1
		try_id:          0
	}
}

struct FuncDef {
mut:
	name      string
	params    []Param
	conv      CallConv
	body      []Stmt
	line      int
	pos       int // cone 0.6 fix2：def 起始 token 位置（顺序检查用）
	is_export bool // cone 0.5：MASM32 EXPORT 属性
	order     int  // cone 0.6：顶层源码顺序
	in_seg    string // cone 0.83：非空 = 属于该特殊段，不进常规 .code 段
	ret_type  string // cone 0.9.1：可选返回类型
	file      string // cone 0.9.3：来源文件（函数体内语句共用）
}

// ---------- 表达式（节点池，用索引互引） ----------

struct Expr {
mut:
	kind          ExprKind
	text          string // 字面量原文 / 标识符名 / 运算符 / 调用全名 / 寄存器名
	is_reg        bool   // cone 0.3：expr_ident 且 text 是寄存器名（保留特殊标识符）
	is_win_sym    bool   // cone 0.3：expr_ident 来自 win.XXX（MASM 侧已定义的常量/变量）
	is_char_const bool   // cone 0.3：expr_str 出现在表达式位置（字符常量，支持转义、进 .const）
	is_float_hint bool   // cone 0.6：节点被 float(...) 括起；需要浮点载入时用 fld 而非 fild
	is_struct_lit bool   // cone 0.6：节点是结构体常量 Type{...}（复用 expr_ident 形态，text=去重键）
	lit_type      string // cone 0.6：结构体常量的类型名（cone struct 名或 win.MASM 名）
	lit_items     []int  // cone 0.6：结构体常量初值项；-1 表示 ?
	ptr_size      string // 仅 expr_deref：[] 内指定的尺寸词（空 = 默认 dword）
	member_base   string // 仅 expr_member：点号左边第一段标识符（变量/形参/结构体类型名）
	member_path   string // 仅 expr_member：点号右边的成员链（如 y / inner.x）
	a             int // expr_neg / expr_addr / expr_deref 的子节点；expr_bin 的左子节点
	b             int // expr_bin 的右子节点
	args          []int // expr_call 的参数节点索引
	line          int
	pos           int // cone 0.6 fix2：expr_call 的调用名 token 位置（顺序检查用）
}

fn new_expr(k ExprKind, text string, line int) Expr {
	return Expr{
		kind:          k
		text:          text
		is_reg:        false
		is_win_sym:    false
		is_char_const: false
		is_float_hint: false
		is_struct_lit: false
		lit_type:      ''
		lit_items:     []int{}
		ptr_size:      ''
		member_base:   ''
		member_path:   ''
		a:             -1
		b:             -1
		args:          []int{}
		line:          line
		pos:           0
	}
}

// AsmBlock: cone 0.5 —— 顶层 asm{...} 原样透传块（按源码 order 在头部区输出）
struct AsmBlock {
mut:
	text  string
	line  int
	order int
}

// cone 0.9preview：顶层 asm64{} 块（函数体内用 st_asm64，复用 Stmt.asm_text）
struct Asm64Block {
mut:
	text  string
	line  int
	order int
	lines []string // cone 0.9preview：预编译出的 MASM db 行
}

// FuncMods: cone 0.5 —— 函数声明/定义的调用约定 + export 属性
struct FuncMods {
mut:
	conv      CallConv
	is_export bool
	ret_type  string // cone 0.9.1：可选返回类型（写在调用约定/export 之后）
}

struct Program {
mut:
	imports    []ImportDecl
	structs    []StructDef // cone 0.4
	includes   []IncludeDecl
	equs       []EquDecl
	typedefs   []TypedefDecl
	protos     []ProtoDecl
	data       []DataDef
	vars       []VarDef
	funcs      []FuncDef
	entry      string
	has_entry  bool
	exprs      []Expr
	asms       []AsmBlock // cone 0.5：顶层 asm{...}
	win_blocks []WinBlockDecl // cone 0.6 fix2：win{...} 批量声明块（纯声明，不生成代码）
	win_names  []string       // cone 0.6 fix2：所有块里登记的名字（已去重）
	folded_equs map[string]string // cone 0.7：cone 侧求值成立的数值 equ（名字 -> 立即数文本）
	compile_args []string     // cone 0.8prelease：源码里 __compile__ "..." 收集的附加编译参数
	link_args    []string     // cone 0.8prelease：源码里 __link__ "..." 收集的附加链接参数
	segs         []SegDef     // cone 0.83：特殊段（段内单元保持源码顺序）
	macros       []MacroDef   // cone 0.83：defined 宏函数（对应 MASM macro/endm）
	asm64s       []Asm64Block // cone 0.9preview：顶层 asm64{} 块
}

// ---------- cone 0.83：特殊段 seg "名字"{ ... } ----------
// 段内单元严格按源码顺序排列，不允许编译器按 section 聚合重排。
// 单元分三类：段内全局数据定义、段内裸代码语句、段内函数定义。
enum SegItemKind {
	si_var  // 段内全局数据（VarDef，视为全局变量，可跨段访问）
	si_stmt // 段内裸代码（连续若干条函数体语句，直接生成指令）
	si_func // 段内函数（FuncDef，与顶层函数生成逻辑完全一致，可跨段调用）
}

struct SegItem {
mut:
	kind     SegItemKind
	var_def  VarDef   // si_var 有效
	func_def FuncDef  // si_func 有效
	stmts    []Stmt   // si_stmt 有效
}

struct SegDef {
mut:
	name  string // 段名原文（不含引号），如 '.fuck' / 'fuck'
	items []SegItem
	line  int
	order int
}

// ---------- cone 0.83：defined 宏函数（无 exitm） ----------
// defined m(p1:req,p2:vararg){ 原样汇编正文 }
//   -> m macro p1:req,p2:vararg / 正文 / m endm
// 宏调用 m(a,b) -> m a,b（cone 侧括号，MASM 侧空格分隔）
struct MacroParam {
	name      string
	restraint string // '' / 'req' / 'vararg'
}

struct MacroDef {
mut:
	name   string
	params []MacroParam
	body   string // 宏体原样文本（类似 asm{}，不做词法解析）
	line   int
	order  int
}

// GenOpts: cone 0.8preview —— 由命令行传给 codegen 的全局生成选项。
// cone_dir 是 cone.exe 所在目录（发行根目录），short_include 对应 -s。
struct GenOpts {
	cone_dir      string
	short_include bool
	no_default_seh bool  // cone 0.84：-noseh 不挂默认全局 try-except
	o1            bool  // cone 0.9.4：实验性 -O1 优化（默认关闭）
	o1_opts      string // cone 0.9.5：-O1:子开关（默认空 = A 组）
	src_path      string // cone 0.9.5：仅 -O1 回退 warning 定位用
}

// 扩充点:
//   * 局部初值 / 结构体成员默认值 / 常量段 -> 并列新节点
//   * 比较 / 逻辑运算与短路求值 -> ExprKind 增加节点，求值器按同一节点池扩展
