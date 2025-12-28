module pratt;

import std::io, std::collections::list;
import c3::lexer;

fn void print_repl() @inline
{
	io::print("pratt> ");
}

fn void main() => @pool()
{
	io::printfn("Pratt REPL -- print 'q' to quit.");
	print_repl();
	while (try s = io::treadline(io::stdin()))
	{
		if (s == "q") break;
		PrattParser p;
		p.init(s);
		if (try e = p.parse())
		{
			io::printfn("eval: %s", e);
			if (!p.lexer.at_end())
			{
				io::print("remaining tokens:");
				while (!p.lexer.at_end())
				{
					io::printf(" %s", p.lexer.next() ?? (Token){});
				}
			}
		}
		else
		{
			io::printfn(" -- Parse() failed");
		}
		print_repl();
	}
}

struct TestCase
{
	String input;
	String want;
}

fn void test_pratt_parser() @test
{
	TestCase[] test = {
		{ "a!", "<IDENT> a <BANG> !" },
	};
	foreach (tc: test)
	{
		PrattParser p;
		p.init(tc.input);
		String expr = string::tformat("%s", p.parse()!!);
		assert(expr == tc.want, "Pratt Parser Test failed: got=%s, want=%s", expr, tc.want);
	}
}

struct PrattParser
{
	Lexer lexer;
	Token tok;
}

fn void PrattParser.init(&self, String s)
{
	self.lexer.init(s);
	self.tok = self.lexer.next() ?? {};
}

fn Token PrattParser.peek(&self) => self.tok;
fn Token PrattParser.consume(&self)
{
	Token tok = self.tok;
	self.tok = self.lexer.next() ?? {};
	return tok;
}

fn bool PrattParser.match(&self, TokenType expect)
{
	if (self.peek().type != expect) return false;
	(void)self.consume();
	return true;
}

fn Expr*? PrattParser.parse(&self) => parse_expr(self, 0)!;

fn Expr*? parse_expr(PrattParser *p, int min_bp)
{
	Token tok = p.consume();

	Parselet parselet = pratt_table[tok.type];
	assert(parselet.prefix, "Pratt: No prefix parselet for Token %s", tok);

	Expr *left = parselet.prefix(p, tok)!;

	while (true)
	{
		parselet = pratt_table[p.peek().type];
		if (parselet.infix == null || min_bp >= parselet.binding_power) break;

		tok = p.consume();
		left = parselet.infix(p, left, tok)!;
	}

	return left;
}

/*
 Parslets
*/

alias PrefixParselet = fn Expr*? (PrattParser *p, Token tok);
alias InfixParselet  = fn Expr*? (PrattParser *p, Expr *left, Token tok);

enum Assoc : const inline char
{
	NONE  = 0,
	RIGHT = 0,
	LEFT  = 1,
}

enum Precedence : inline char
{
	NONE,
	ASSIGNMENT,     // = "= /= %= += etc.
	TERNARY,        // ?: ? ??
	OR,             // || |||
	AND,            // && &&&
	RELATIONAL,     // < > <= >= == !=
	ADDITIVE,       // + - +++
	BIT,            // ~ | &
	SHIFT,          // << >>
	MULTIPLICATIVE, // * / %
	UNARY,          // ! - + ~ * & prefix ++/-- (type)
	CALL,           // . () [] postfix ++ -- !! !
	PRIMARY,
}

struct Parselet
{
	PrefixParselet prefix;
	InfixParselet  infix;
	int            binding_power;
	Assoc          assoc;
}

Parselet[*] pratt_table = {
	[TokenType.INVALID]      = {},

	// Precedence.ASSIGNMENT
	[TokenType.CT_CONCAT_ASSIGN] = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.EQ]               = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.PLUS_ASSIGN]      = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.MINUS_ASSIGN]     = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.MULT_ASSIGN]      = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.MOD_ASSIGN]       = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.DIV_ASSIGN]       = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.BIT_XOR_ASSIGN]   = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.BIT_AND_ASSIGN]   = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.BIT_OR_ASSIGN]    = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.SHR_ASSIGN]       = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.SHL_ASSIGN]       = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },

	// Precedence.TERNARY
	[TokenType.QUESTION]         = { null,                    &parse_ternary,          Precedence.TERNARY,        Assoc.RIGHT },
	[TokenType.QUESTQUEST]       = { null,                    null /*TODO*/,           Precedence.TERNARY,        Assoc.RIGHT },
	[TokenType.ELVIS]            = { null,                    null /*TODO*/,           Precedence.TERNARY,        Assoc.RIGHT },
	[TokenType.CT_TERNARY]       = { null,                    &parse_ternary,          Precedence.TERNARY,        Assoc.RIGHT },

	// Precedence.OR
	[TokenType.OR]               = { null,                    &parse_binary,           Precedence.OR,             Assoc.LEFT  },
	[TokenType.CT_OR_OP]         = { null,                    &parse_binary,           Precedence.OR,             Assoc.LEFT  },

	// Precedence.AND
	[TokenType.AND]              = { &parse_unary,            &parse_binary,           Precedence.AND,            Assoc.LEFT  },
	[TokenType.CT_AND_OP]        = { &parse_unary,            &parse_binary,           Precedence.AND,            Assoc.LEFT  },

	// Precedence.RELATIONAL
	[TokenType.EQEQ]             = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.NOT_EQUAL]        = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.GREATER]          = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.GREATER_EQ]       = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.LESS]             = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.LESS_EQ]          = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },

	// Precedence.ADDITIVE
	[TokenType.PLUS]             = { &parse_unary,            &parse_binary,           Precedence.ADDITIVE,       Assoc.LEFT  },
	[TokenType.MINUS]            = { &parse_unary,            &parse_binary,           Precedence.ADDITIVE,       Assoc.LEFT  },
	[TokenType.CT_CONCAT_OP]     = { null,                    &parse_binary,           Precedence.ADDITIVE,       Assoc.LEFT  },

	// Precedence.BIT
	[TokenType.BIT_XOR]          = { null /*TODO*/,           &parse_binary,           Precedence.BIT,            Assoc.LEFT  },
	[TokenType.BIT_OR]           = { null,                    &parse_binary,           Precedence.BIT,            Assoc.LEFT  },
	[TokenType.AMP]              = { &parse_unary,            &parse_binary,           Precedence.BIT,            Assoc.LEFT  },

	// Precedence.SHIFT
	[TokenType.SHL_OP]           = { null,                    &parse_binary,           Precedence.SHIFT,          Assoc.LEFT  },
	[TokenType.SHR_OP]           = { null,                    &parse_binary,           Precedence.SHIFT,          Assoc.LEFT  },

	// Precedence.MULTIPLICAT    IVE
	[TokenType.DIV]              = { null,                    &parse_binary,           Precedence.MULTIPLICATIVE, Assoc.LEFT  },
	[TokenType.MOD]              = { null,                    &parse_binary,           Precedence.MULTIPLICATIVE, Assoc.LEFT  },
	[TokenType.STAR]             = { &parse_unary,            &parse_binary,           Precedence.MULTIPLICATIVE, Assoc.LEFT  },

	// Precedence.CALL
	[TokenType.PLUSPLUS]         = { &parse_unary,            &parse_postfix,          Precedence.CALL,           Assoc.LEFT  },
	[TokenType.MINUSMINUS]       = { &parse_unary,            &parse_postfix,          Precedence.CALL,           Assoc.LEFT  },
	[TokenType.LPAREN]           = { &parse_group,            &parse_call,             Precedence.CALL,           Assoc.LEFT  },
	[TokenType.BANGBANG]         = { &parse_unary,            null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.LBRACKET]         = { null,                    null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.LBRACE]           = { null /*TODO*/,           null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.DOT]              = { null,                    null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.BANG]             = { &parse_unary,            null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.BIT_NOT]          = { &parse_unary,            null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },

	// [TokenType.FIRST_KEYWORD..T  okenType.FIRST_NON_TYPE_KEYWORD]
	//                              = { &parse_type_ident,       null,                    NONE,           Assoc.NONE  },

	// [TokenType.BYTES]            = { &parse_bytes,            null,                    NONE,           Assoc.NONE  },
	[TokenType.TRUE]             = { &parse_bool,             null,                    Precedence.NONE,           Assoc.NONE  },
	[TokenType.FALSE]            = { &parse_bool,             null,                    Precedence.NONE,           Assoc.NONE  },
	[TokenType.NULL]              = { &parse_null,             null,                    Precedence.NONE,           Assoc.NONE  },
	// [TokenType.LENGTHOF]         = { &parse_lengthof,         null,                    NONE,           Assoc.NONE  },
	[TokenType.INTEGER]          = { &parse_integer,          null,                    Precedence.NONE,           Assoc.NONE  },
	[TokenType.REAL]             = { &parse_double,           null,                    Precedence.NONE,           Assoc.NONE  },
	// [TokenType.BUILTIN]          = { &parse_builtin,          null,                    NONE,           Assoc.NONE  },
	// [TokenType.CHAR_LITERAL]     = { &parse_char_lit,         null,                    NONE,           Assoc.NONE  },
	// [TokenType.STRING]           = { &parse_string,           null,                    NONE,           Assoc.NONE  },

	// [TokenType.IDENT]            = { &parse_ident_start_expr, null,                    NONE,           Assoc.NONE  },
	// [TokenType.TYPE_IDENT]       = { &parse_type_ident,       null,                    NONE,           Assoc.NONE  },
	// [TokenType.CT_IDENT]         = { &parse_ct_ident,         null,                    NONE,           Assoc.NONE  },
	// [TokenType.CONST_IDENT]      = { &parse_ident,            null,                    NONE,           Assoc.NONE  },
	// [TokenType.CT_CONST_IDENT]   = { &parse_ct_ident,         null,                    NONE,           Assoc.NONE  },
	// [TokenType.CT_TYPE_IDENT]    = { &parse_type_ident,       null,                    NONE,           Assoc.NONE  },
	// [TokenType.HASH_IDENT]       = { &parse_hash_ident,       null,                    NONE,           Assoc.NONE  },
	// [TokenType.AT_IDENT]         = { &parse_ident,            null,                    NONE,           Assoc.NONE  },
	// [TokenType.ELLIPSIS]         = { &parse_splat,            null,                    NONE,           Assoc.NONE  },
	// [TokenType.FN]               = { &parse_lambda,           null,                    NONE,           Assoc.NONE  },

	// TODO: CT_ALIGNOF .. CT_VATYPE

	[TokenType.EOF]          = {},
};

fn Expr*? parse_integer(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_INTEGER, .ixx = tok };
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

fn Expr*? parse_double(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_FLOAT, .fxx = tok };
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

fn Expr*? parse_bool(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_BOOL, .b = (tok.type == TRUE) ? true : false};
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

fn Expr*? parse_null(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_POINTER, .ptr = 0 };
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}


fn Expr*? parse_ident(PrattParser *p, Token tok)
{
	Expr *e = mem::tnew(Expr);
	*e = { .kind = IDENT_EXPR, .as.i.ident = tok };
	return e;
}

fn Expr*? parse_group(PrattParser *p, Token tok)
{
	Expr *e = parse_expr(p, 0)!;
	if (!p.match(TokenType.RPAREN))
	{
		// TODO: Better throw error than abort
		abort("Unclosed parenthesis");
	}
	return e;
}

fn Expr*? parse_unary(PrattParser *p, Token tok)
{
	Parselet parselet = pratt_table[tok.type];
	int next_bp = Precedence.UNARY;

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = UNARY_EXPR, .as.u = { tok, right} };

	return e;
}

fn Expr*? parse_assign(PrattParser *p, Expr *left, Token tok)
{
	assert(left.kind == IDENT_EXPR,
		"Left-hand side of assignment needs to be a name");

	Parselet parselet = pratt_table[tok.type];

	// If operator is right-associated, decrease binding power by one.
	int next_bp = parselet.binding_power - (parselet.assoc == Assoc.RIGHT ? 1 : 0);

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = ASSIGN_EXPR, .as.a = { left.as.i.ident, right} };

	return e;
}

fn Expr*? parse_postfix(PrattParser *p, Expr *left, Token tok)
{
	Expr *e = mem::tnew(Expr);
	*e = { .kind = POSTFIX_EXPR, .as.p = { left, tok } };
	return e;
}

fn Expr*? parse_ternary(PrattParser *p, Expr *left, Token tok)
{
	Parselet parselet = pratt_table[tok.type];

	// If operator is right-associated, decrease binding power by one.
	int next_bp = parselet.binding_power - (parselet.assoc == Assoc.RIGHT ? 1 : 0);

	Expr* then_arm = parse_expr(p, 0)!;

	if (!p.match(TokenType.COLON))
	{
		abort("Expected ':'");
	}

	Expr* else_arm = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_TERNARY, .as.ternary_expr = { left, then_arm, else_arm } };

	return e;
}

fn Expr*? parse_binary(PrattParser *p, Expr *left, Token tok)
{
	Parselet parselet = pratt_table[tok.type];

	// If operator is right-associated, decrease binding power by one.
	int next_bp = parselet.binding_power - (parselet.assoc == Assoc.RIGHT ? 1 : 0);

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_BINARY, .as.binary_expr = { left, tok, right} };

	return e;
}

fn Expr*? parse_call(PrattParser *p, Expr *left, Token tok)
{
	// `args` will be the comma-separated arguments
	List{Expr*} args;
	args.tinit(); // TODO: Allocator?

	// There might be no arguments
	if (!p.match(TokenType.RPAREN))
	{
		do {
			if (try arg = parse_expr(p, 0))
			{
				args.push(arg);
			}
			else
			{
				break;
			}
		} while (p.match(TokenType.COMMA));
	}

	if (!p.match(TokenType.RPAREN))
	{
		// TODO: Better throw error than abort
		abort("Unclosed parenthesis");
	}

	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CALL, .as.call_expr = { left, args} };

	return e;
}


/*
 Expressions
*/

struct IdentExpression
{
	Token ident;
}

struct UnaryExpression
{
	Token op;
	Expr *right;
}

struct AssignExpression
{
	Token op;
	Expr *right;
}

struct ExprTernary
{
	Expr *condition;
	Expr *then_arm;
	Expr *else_arm;
}

struct ExprBinary
{
	Expr *left;
	Token op;
	Expr *right;
}

struct PostfixExpression
{
	Expr *left;
	Token op;
}

struct ExprCall
{
	Expr*       func;
	List{Expr*} args;
}

enum ConstKind
{
	CONST_FLOAT,
	CONST_INTEGER,
	CONST_BOOL,
	CONST_POINTER,
}

struct ExprConst (Printable)
{
	ConstKind const_kind;
	union
	{
		Token fxx;
		Token ixx;
		bool  b;
		uptr  ptr;
	}
}

fn usz? ExprConst.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	switch (self.const_kind)
	{
		case CONST_FLOAT:   n += f.printf("%s", self.fxx)!;
		case CONST_INTEGER: n += f.printf("%s", self.ixx)!;
		case CONST_BOOL   : n += f.printf("<%s>", self.b)!;
		case CONST_POINTER: n += f.printf("%s", self.ptr == 0 ? null : (void*)self.ptr)!;
	}
	return n;
}

enum ExprKind
{
	// Prefix Parselets
	EXPR_CONST,
	IDENT_EXPR,
	UNARY_EXPR,

	// Infix Parselets
	ASSIGN_EXPR,
	EXPR_TERNARY,
	EXPR_BINARY,
	POSTFIX_EXPR,
	EXPR_CALL,
}

struct Expr (Printable)
{
	ExprKind kind;
	union as {
		ExprConst   const_expr;
		ExprTernary ternary_expr;
		ExprBinary  binary_expr;
		ExprCall    call_expr;

		IdentExpression   i;
		UnaryExpression   u;
		AssignExpression  a;


		PostfixExpression p;
	}
}

fn usz? Expr.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	switch (self.kind)
	{
		case EXPR_CONST:   n += f.printf("%s", self.as.const_expr)!;
		case EXPR_TERNARY: n += f.printf("( %s ? %s : %s )", self.as.ternary_expr.condition, self.as.ternary_expr.then_arm, self.as.ternary_expr.else_arm)!;
		case EXPR_BINARY:  n += f.printf("( %s %s %s )", self.as.binary_expr.left, self.as.binary_expr.op, self.as.binary_expr.right)!;
		case EXPR_CALL:    n += f.printf("%s( %s )", self.as.call_expr.func, self.as.call_expr.args)!;

		case IDENT_EXPR:   n += f.printf("%s", self.as.i.ident)!;
		case UNARY_EXPR:   n += f.printf("( %s %s )", self.as.u.op, self.as.u.right)!;
		case ASSIGN_EXPR:  n += f.printf("( %s = %s )", self.as.a.op, self.as.a.right)!;
		case POSTFIX_EXPR: n += f.printf("( %s %s )", self.as.p.left, self.as.p.op)!;
	}
	return n;
}

